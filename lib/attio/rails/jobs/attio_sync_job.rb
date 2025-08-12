# frozen_string_literal: true

module Attio
  module Rails
    module Jobs
      class AttioSyncJob < ActiveJob::Base
        queue_as { Attio::Rails.configuration.queue || :default }

        # Use retry_after from server when available
        retry_on Attio::RateLimitError, wait: :polynomially_longer, attempts: 3 do |job, error|
          retry_after = error.retry_after || 60
          job.class.set(wait: retry_after.seconds).perform_later(*job.arguments)
        end

        retry_on Attio::ServerError, wait: :polynomially_longer, attempts: 5
        discard_on ActiveJob::DeserializationError

        def perform(model_name:, model_id:, action:, **options)
          return unless Attio::Rails.sync_enabled?

          model_class = model_name.constantize

          case action.to_sym
          when :sync
            sync_record(model_class, model_id, options)
          when :delete
            delete_record(model_class, model_id, options[:attio_record_id])
          when :sync_deal
            sync_deal(model_class, model_id, options)
          when :delete_deal
            delete_deal(model_class, model_id, options[:attio_deal_id])
          when :batch_create, :batch_update, :batch_upsert, :batch_delete
            batch_operation(model_class, model_id, action, options)
          else
            Attio::Rails.logger.error "Unknown Attio sync action: #{action}"
          end
        rescue Attio::AuthenticationError => e
          handle_authentication_error(e, model_name, model_id)
        rescue Attio::ValidationError => e
          handle_validation_error(e, model_name, model_id)
        rescue StandardError => e
          handle_general_error(e, model_name, model_id)
        end

        private def sync_record(model_class, model_id, _options)
          model = find_model(model_class, model_id)
          return unless model&.should_sync_to_attio?

          model.sync_to_attio_now
        end

        private def delete_record(model_class, model_id, attio_record_id)
          return unless attio_record_id.present?

          object_type = model_class.attio_object_type
          return unless object_type.present?

          client = Attio::Rails.client
          client.records.delete(object: object_type, id: attio_record_id)

          log_deletion(model_class, model_id, attio_record_id)
        rescue Attio::NotFoundError
          Attio::Rails.logger.info "Attio record #{attio_record_id} already deleted"
        end

        private def sync_deal(model_class, model_id, _options)
          model = find_model(model_class, model_id)
          return unless model.respond_to?(:sync_deal_to_attio_now)

          model.sync_deal_to_attio_now
        end

        private def delete_deal(model_class, model_id, attio_deal_id)
          return unless attio_deal_id.present?

          client = Attio::Rails.client
          return unless client.respond_to?(:deals)

          client.deals.delete(id: attio_deal_id)

          log_deletion(model_class, model_id, attio_deal_id, "deal")
        rescue Attio::NotFoundError
          Attio::Rails.logger.info "Attio deal #{attio_deal_id} already deleted"
        end

        private def batch_operation(model_class, model_id, action, options)
          model = find_model(model_class, model_id)
          return unless model

          operation = action.to_s.sub("batch_", "").to_sym
          object_type = options[:object_type] || model_class.attio_object_type

          BulkSync.perform(
            [model],
            object_type: object_type,
            operation: operation,
            **options.except(:object_type)
          )
        end

        private def find_model(model_class, model_id)
          if Attio::Rails.configuration.raise_on_missing_record
            model_class.find(model_id)
          else
            model_class.find_by(id: model_id)
          end
        end

        private def handle_authentication_error(error, model_name, model_id)
          Attio::Rails.logger.error "Attio authentication failed: #{error.message}"
          notify_error(error, model_name, model_id)
          raise # Re-raise to trigger job failure notifications
        end

        private def handle_validation_error(error, model_name, model_id)
          Attio::Rails.logger.error "Attio validation error for #{model_name}##{model_id}: #{error.message}"
          notify_error(error, model_name, model_id)
          # Don't retry validation errors
        end

        private def handle_general_error(error, model_name, model_id)
          Attio::Rails.logger.error "Attio sync failed for #{model_name}##{model_id}: #{error.message}"
          Attio::Rails.logger.error error.backtrace.join("\n") if ::Rails.env.development?
          notify_error(error, model_name, model_id)
          raise error
        end

        private def log_deletion(model_class, model_id, attio_id, type = "record")
          Attio::Rails.logger.info(
            "Deleted Attio #{type} #{attio_id} for #{model_class.name}##{model_id}"
          )
        end

        private def notify_error(error, model_name, model_id)
          return unless defined?(::Rails.error) && ::Rails.error.respond_to?(:report)

          ::Rails.error.report(
            error,
            context: {
              model_name: model_name,
              model_id: model_id,
              job: self.class.name,
            }
          )
        end
      end
    end
  end
end
