# frozen_string_literal: true

# Set up ActiveJob for testing
require "active_job"

ActiveJob::Base.queue_adapter = :test
ActiveJob::Base.logger = Logger.new(nil) # Silence logging in tests

class ApplicationJob < ActiveJob::Base
end

# Create the AttioSyncJob for testing
class AttioSyncJob < ApplicationJob
  queue_as :low

  retry_on Attio::RateLimitError, wait: 1.minute, attempts: 3
  retry_on Attio::ServerError, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(model_name:, model_id:, action:, attio_record_id: nil)
    return unless Attio::Rails.sync_enabled?

    model_class = model_name.constantize

    case action
    when :sync
      sync_record(model_class, model_id)
    when :delete
      delete_record(model_class, model_id, attio_record_id)
    else
      Attio::Rails.logger.error "Unknown Attio sync action: #{action}"
    end
  rescue Attio::AuthenticationError => e
    Attio::Rails.logger.error "Attio authentication failed: #{e.message}"
    raise
  rescue Attio::ValidationError => e
    Attio::Rails.logger.error "Attio validation error for #{model_name}##{model_id}: #{e.message}"
  rescue StandardError => e
    Attio::Rails.logger.error "Attio sync failed for #{model_name}##{model_id}: #{e.message}"
    raise e
  end

  private def sync_record(model_class, model_id)
    model = model_class.find_by(id: model_id)
    return unless model
    return unless model.should_sync_to_attio?

    model.sync_to_attio_now
  end

  private def delete_record(model_class, model_id, attio_record_id)
    return unless attio_record_id.present?

    object_type = model_class.attio_object_type
    return unless object_type.present?

    client = Attio::Rails.client
    client.records.delete(
      object: object_type,
      id: attio_record_id
    )

    Attio::Rails.logger.info "Deleted Attio record #{attio_record_id} for #{model_class.name}##{model_id}"
  rescue Attio::NotFoundError
    Attio::Rails.logger.info "Attio record #{attio_record_id} already deleted"
  end
end
