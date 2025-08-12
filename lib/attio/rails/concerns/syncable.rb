# frozen_string_literal: true

module Attio
  module Rails
    module Concerns
      module Syncable
        extend ActiveSupport::Concern

        included do
          after_commit :sync_to_attio, on: %i[create update], if: :should_sync_to_attio?
          after_commit :remove_from_attio, on: :destroy, if: :should_remove_from_attio?

          class_attribute :attio_object_type
          class_attribute :attio_attribute_mapping
          class_attribute :attio_sync_conditions
          class_attribute :attio_identifier_attribute
          class_attribute :attio_transform_method
          class_attribute :attio_error_handler
          class_attribute :attio_before_sync_callback
          class_attribute :attio_after_sync_callback
          class_attribute :attio_bulk_sync_options
        end

        class_methods do
          def syncs_with_attio(object_type, mapping = {}, options = {})
            self.attio_object_type = object_type
            self.attio_attribute_mapping = mapping
            self.attio_sync_conditions = options[:if]
            self.attio_identifier_attribute = options[:identifier] || :id
            self.attio_transform_method = options[:transform]
            self.attio_error_handler = options[:on_error]
            self.attio_before_sync_callback = options[:before_sync]
            self.attio_after_sync_callback = options[:after_sync]
            self.attio_bulk_sync_options = options[:bulk_sync] || {}
          end

          def before_attio_sync(method = nil, &block)
            self.attio_before_sync_callback = method || block
          end

          def after_attio_sync(method = nil, &block)
            self.attio_after_sync_callback = method || block
          end

          def skip_attio_sync
            skip_callback :commit, :after, :sync_to_attio
            skip_callback :commit, :after, :remove_from_attio
          end

          def bulk_sync_with_attio(options = {})
            self.attio_bulk_sync_options = options
          end

          def bulk_sync_to_attio(records = nil, **options)
            records ||= all
            merged_options = (attio_bulk_sync_options || {}).merge(options)

            BulkSync.perform(
              records,
              object_type: attio_object_type,
              **merged_options
            )
          end

          def bulk_upsert_to_attio(records = nil, **options)
            records ||= all
            merged_options = (attio_bulk_sync_options || {}).merge(options).merge(operation: :upsert)

            BulkSync.perform(
              records,
              object_type: attio_object_type,
              **merged_options
            )
          end
        end

        def sync_to_attio
          run_before_sync_callback

          if Attio::Rails.background_sync?
            AttioSyncJob.perform_later(
              model_name: self.class.name,
              model_id: id,
              action: :sync
            )
          else
            sync_to_attio_now
          end
        rescue StandardError => e
          handle_sync_error(e)
        end

        def sync_to_attio_now
          run_before_sync_callback

          client = Attio::Rails.client
          attributes = transformed_attio_attributes

          result = if attio_record_id.present?
                     client.records.update(
                       object: attio_object_type,
                       id: attio_record_id,
                       data: { values: attributes }
                     )
                   else
                     response = client.records.create(
                       object: attio_object_type,
                       data: { values: attributes }
                     )
                     update_column(:attio_record_id, response["data"]["id"]) if respond_to?(:attio_record_id=)
                     response
                   end

          run_after_sync_callback(result)
          result
        rescue StandardError => e
          handle_sync_error(e)
          raise unless self.class.attio_error_handler
        end

        def remove_from_attio
          if Attio::Rails.background_sync?
            AttioSyncJob.perform_later(
              model_name: self.class.name,
              model_id: id,
              action: :delete,
              attio_record_id: attio_record_id
            )
          else
            remove_from_attio_now
          end
        rescue StandardError => e
          Attio::Rails.logger.error "Failed to remove from Attio: #{e.message}"
          raise if ::Rails.env.development?
        end

        def remove_from_attio_now
          return unless attio_record_id.present?

          client = Attio::Rails.client
          client.records.delete(
            object: attio_object_type,
            id: attio_record_id
          )
        end

        def attio_attributes
          return {} unless attio_attribute_mapping

          attio_attribute_mapping.each_with_object({}) do |(attio_key, local_key), hash|
            value = attribute_value_for(local_key)
            hash[attio_key] = value unless value.nil?
          end
        end

        def transformed_attio_attributes
          attributes = attio_attributes

          case attio_transform_method
          when Proc
            attio_transform_method.call(attributes, self)
          when Symbol, String
            send(attio_transform_method, attributes)
          else
            attributes
          end
        end

        def to_attio
          transformed_attio_attributes
        end

        def should_sync_to_attio?
          return false unless Attio::Rails.sync_enabled?
          return false unless attio_object_type.present?
          return false unless attio_attribute_mapping.present?

          condition = attio_sync_conditions
          return true if condition.nil?

          case condition
          when Proc
            instance_exec(&condition)
          when Symbol, String
            send(condition)
          else
            true
          end
        end

        def should_remove_from_attio?
          attio_record_id.present? && Attio::Rails.sync_enabled?
        end

        def attio_identifier
          send(attio_identifier_attribute)
        end

        private def attribute_value_for(local_key)
          case local_key
          when Proc
            local_key.call(self)
          when Symbol
            send(local_key)
          when String
            respond_to?(local_key) ? send(local_key) : local_key
          else
            local_key
          end
        end

        private def run_before_sync_callback
          return unless self.class.attio_before_sync_callback

          case self.class.attio_before_sync_callback
          when Proc
            instance_exec(&self.class.attio_before_sync_callback)
          when Symbol, String
            send(self.class.attio_before_sync_callback)
          end
        end

        private def run_after_sync_callback(result)
          return unless self.class.attio_after_sync_callback

          case self.class.attio_after_sync_callback
          when Proc
            instance_exec(result, &self.class.attio_after_sync_callback)
          when Symbol, String
            send(self.class.attio_after_sync_callback, result)
          end
        end

        private def handle_sync_error(error)
          if self.class.attio_error_handler
            case self.class.attio_error_handler
            when Proc
              instance_exec(error, &self.class.attio_error_handler)
            when Symbol, String
              send(self.class.attio_error_handler, error)
            end
          else
            Attio::Rails.logger.error "Failed to sync to Attio: #{error.message}"
            raise if ::Rails.env.development?
          end
        end
      end
    end
  end
end
