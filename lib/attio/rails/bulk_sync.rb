# frozen_string_literal: true

module Attio
  module Rails
    class BulkSync
      attr_reader :records, :object_type, :options, :results

      def initialize(records, object_type:, **options)
        @records = records
        @object_type = object_type
        @options = options
        @results = { successful: [], failed: [], partial: [] }
        @logger = Attio::Rails.logger
        @client = Attio::Rails.client
      end

      def perform
        return @results if records.empty?

        batch_size = options[:batch_size] || Attio::Rails.configuration.bulk_batch_size || 100
        operation = options[:operation] || :create

        if records.respond_to?(:find_in_batches)
          # ActiveRecord relation
          total_batches = (records.count.to_f / batch_size).ceil
          current_batch = 0

          records.find_in_batches(batch_size: batch_size) do |batch|
            current_batch += 1
            @logger.info("Processing batch #{current_batch}/#{total_batches} for #{object_type}")

            process_batch(batch, operation)

            options[:progress_callback]&.call(current_batch, total_batches, @results)
          end
        else
          # Array or other enumerable
          records_array = records.to_a
          total_batches = (records_array.size.to_f / batch_size).ceil
          current_batch = 0

          records_array.each_slice(batch_size) do |batch|
            current_batch += 1
            @logger.info("Processing batch #{current_batch}/#{total_batches} for #{object_type}")

            process_batch(batch, operation)

            options[:progress_callback]&.call(current_batch, total_batches, @results)
          end
        end

        handle_results
        @results
      end

      def self.perform(records, **options)
        new(records, **options).perform
      end

      private def process_batch(batch, operation)
        case operation
        when :create
          create_batch(batch)
        when :update
          update_batch(batch)
        when :upsert
          upsert_batch(batch)
        when :delete
          delete_batch(batch)
        else
          raise ArgumentError, "Unknown operation: #{operation}"
        end
      rescue Attio::RateLimitError => e
        handle_rate_limit_error(e, batch, operation)
      rescue StandardError => e
        # Don't catch ArgumentError - let it propagate
        raise if e.is_a?(ArgumentError)
        handle_batch_error(e, batch)
      end

      private def create_batch(batch)
        records_data = batch.map { |record| transform_record(record) }

        response = if @client.respond_to?(:bulk)
                     @client.bulk.create_records(
                       object: object_type,
                       records: records_data,
                       options: { partial_success: options[:partial_success] != false }
                     )
                   else
                     legacy_bulk_create(records_data, batch)
                   end

        process_response(response, batch)
      end

      private def update_batch(batch)
        updates = batch.map do |record|
          {
            id: record.respond_to?(:attio_id) ? record.attio_id : record.attio_record_id,
            data: transform_record(record),
          }
        end

        response = if @client.respond_to?(:bulk)
                     @client.bulk.update_records(
                       object: object_type,
                       updates: updates,
                       options: { partial_success: options[:partial_success] != false }
                     )
                   else
                     legacy_bulk_update(updates, batch)
                   end

        process_response(response, batch)
      end

      private def upsert_batch(batch)
        match_attribute = options[:match_attribute] ||
                          Attio::Rails.configuration.upsert_match_attribute ||
                          :email

        records_data = batch.map { |record| transform_record(record) }

        response = if @client.respond_to?(:bulk)
                     @client.bulk.upsert_records(
                       object: object_type,
                       records: records_data,
                       match_attribute: match_attribute,
                       options: { partial_success: options[:partial_success] != false }
                     )
                   else
                     legacy_bulk_upsert(records_data, match_attribute, batch)
                   end

        process_response(response, batch)
      end

      private def delete_batch(batch)
        ids = batch.map { |r| r.respond_to?(:attio_id) ? r.attio_id : r.attio_record_id }.compact
        return if ids.empty?

        response = if @client.respond_to?(:bulk)
                     @client.bulk.delete_records(
                       object: object_type,
                       ids: ids
                     )
                   else
                     legacy_bulk_delete(ids, batch)
                   end

        process_response(response, batch)
      end

      private def transform_record(record)
        if options[:transform]
          if options[:transform].is_a?(Proc)
            options[:transform].call(record)
          else
            record.send(options[:transform])
          end
        elsif record.respond_to?(:to_attio)
          record.to_attio
        else
          record.attributes
        end
      end

      private def process_response(response, batch)
        if response[:success]
          @results[:successful].concat(batch)
        elsif response[:partial_success]
          successful_ids = response[:successful_ids] || []
          failed_ids = response[:failed_ids] || []

          batch.each do |record|
            if successful_ids.include?(record.id)
              @results[:successful] << record
            elsif failed_ids.include?(record.id)
              @results[:failed] << { record: record, error: response[:errors]&.dig(record.id) }
            else
              @results[:partial] << record
            end
          end
        else
          batch.each do |record|
            @results[:failed] << { record: record, error: response[:error] }
          end
        end
      end

      private def handle_batch_error(error, batch)
        @logger.error("Batch sync error: #{error.message}")

        options[:on_error]&.call(error, batch)

        batch.each do |record|
          @results[:failed] << { record: record, error: error.message }
        end
      end

      private def handle_rate_limit_error(error, batch, operation)
        retry_after = error.retry_after || 60
        @logger.warn("Rate limit hit during bulk sync. Retrying after #{retry_after} seconds")

        if options[:async] && defined?(AttioSyncJob)
          batch.each do |record|
            AttioSyncJob.set(wait: retry_after.seconds).perform_later(
              model_name: record.class.name,
              model_id: record.id,
              action: "batch_#{operation}",
              object_type: object_type,
              options: options
            )
          end
          @results[:partial].concat(batch)
        else
          sleep(retry_after)
          process_batch(batch, operation)
        end
      end

      private def handle_results
        total_count = @results[:successful].count + @results[:failed].count + @results[:partial].count

        @logger.info("Bulk sync completed: #{@results[:successful].count}/#{total_count} successful")

        if @results[:failed].any?
          @logger.error("Failed records: #{@results[:failed].count}")
          if options[:raise_on_failure] && @results[:successful].empty?
            raise BulkSyncError, "All records failed to sync"
          end
        end

        return unless options[:on_complete]

        options[:on_complete].call(@results)
      end

      private def legacy_bulk_create(records_data, batch)
        successful = []
        failed = []

        records_data.each_with_index do |data, index|
          @client.records.create(object: object_type, data: data)
          successful << batch[index].id
        rescue StandardError => e
          failed << { id: batch[index].id, error: e.message }
        end

        {
          success: failed.empty?,
          partial_success: successful.any? && failed.any?,
          successful_ids: successful,
          failed_ids: failed.map { |f| f[:id] },
          errors: failed.each_with_object({}) { |f, h| h[f[:id]] = f[:error] },
        }
      end

      private def legacy_bulk_update(updates, batch)
        successful = []
        failed = []

        updates.each_with_index do |update, index|
          @client.records.update(
            object: object_type,
            id: update[:id],
            data: update[:data]
          )
          successful << batch[index].id
        rescue StandardError => e
          failed << { id: batch[index].id, error: e.message }
        end

        {
          success: failed.empty?,
          partial_success: successful.any? && failed.any?,
          successful_ids: successful,
          failed_ids: failed.map { |f| f[:id] },
          errors: failed.each_with_object({}) { |f, h| h[f[:id]] = f[:error] },
        }
      end

      private def legacy_bulk_upsert(records_data, match_attribute, batch)
        successful = []
        failed = []

        records_data.each_with_index do |data, index|
          # Try to find existing record
          existing = @client.records.list(
            object: object_type,
            filter: { match_attribute => data[match_attribute] }
          ).first

          if existing
            @client.records.update(object: object_type, id: existing[:id], data: data)
          else
            @client.records.create(object: object_type, data: data)
          end
          successful << batch[index].id
        rescue StandardError => e
          failed << { id: batch[index].id, error: e.message }
        end

        {
          success: failed.empty?,
          partial_success: successful.any? && failed.any?,
          successful_ids: successful,
          failed_ids: failed.map { |f| f[:id] },
          errors: failed.each_with_object({}) { |f, h| h[f[:id]] = f[:error] },
        }
      end

      private def legacy_bulk_delete(_ids, batch)
        successful = []
        failed = []
        skipped = []

        batch.each do |record|
          attio_id = record.respond_to?(:attio_id) ? record.attio_id : record.attio_record_id
          unless attio_id
            skipped << record.id
            next
          end

          @client.records.delete(object: object_type, id: attio_id)
          successful << record.id
        rescue StandardError => e
          failed << { id: record.id, error: e.message }
        end

        # If we have skipped records, it's a partial success
        has_skipped = skipped.any?
        has_failed = failed.any?
        has_successful = successful.any?
        
        {
          success: !has_failed && !has_skipped && has_successful,
          partial_success: (has_successful && (has_failed || has_skipped)) || (!has_successful && has_skipped),
          successful_ids: successful,
          failed_ids: failed.map { |f| f[:id] },
          errors: failed.each_with_object({}) { |f, h| h[f[:id]] = f[:error] },
        }
      end
    end

    class BulkSyncError < StandardError; end
  end
end
