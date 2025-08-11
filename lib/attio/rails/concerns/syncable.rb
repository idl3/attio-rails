module Attio
  module Rails
    module Concerns
      module Syncable
        extend ActiveSupport::Concern

        included do
          after_commit :sync_to_attio, on: [:create, :update], if: :should_sync_to_attio?
          after_commit :remove_from_attio, on: :destroy, if: :should_remove_from_attio?

          class_attribute :attio_object_type
          class_attribute :attio_attribute_mapping
          class_attribute :attio_sync_conditions
          class_attribute :attio_identifier_attribute
        end

        class_methods do
          def syncs_with_attio(object_type, mapping = {}, options = {})
            self.attio_object_type = object_type
            self.attio_attribute_mapping = mapping
            self.attio_sync_conditions = options[:if] || -> { true }
            self.attio_identifier_attribute = options[:identifier] || :id
          end

          def skip_attio_sync
            skip_callback :commit, :after, :sync_to_attio
            skip_callback :commit, :after, :remove_from_attio
          end
        end

        def sync_to_attio
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
          Attio::Rails.logger.error "Failed to sync to Attio: #{e.message}"
          raise if ::Rails.env.development?
        end

        def sync_to_attio_now
          client = Attio::Rails.client
          attributes = attio_attributes
          
          if attio_record_id.present?
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
            update_column(:attio_record_id, response['data']['id']) if respond_to?(:attio_record_id=)
          end
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
            value = case local_key
                    when Proc
                      local_key.call(self)
                    when Symbol, String
                      send(local_key)
                    else
                      local_key
                    end
            hash[attio_key] = value unless value.nil?
          end
        end

        def should_sync_to_attio?
          return false unless Attio::Rails.sync_enabled?
          return false unless attio_object_type.present? && attio_attribute_mapping.present?
          
          condition = attio_sync_conditions
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
      end
    end
  end
end