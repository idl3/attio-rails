class AttioSyncJob < ApplicationJob
  queue_as :low
  
  retry_on Attio::RateLimitError, wait: 1.minute, attempts: 3
  retry_on Attio::ServerError, wait: :exponentially_longer, attempts: 5
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
    raise # Re-raise to trigger job failure notifications
  rescue Attio::ValidationError => e
    Attio::Rails.logger.error "Attio validation error for #{model_name}##{model_id}: #{e.message}"
    # Don't retry validation errors
  rescue StandardError => e
    Attio::Rails.logger.error "Attio sync failed for #{model_name}##{model_id}: #{e.message}"
    Attio::Rails.logger.error e.backtrace.join("\n") if Rails.env.development?
    raise e
  end

  private

  def sync_record(model_class, model_id)
    model = model_class.find_by(id: model_id)
    return unless model
    
    # Check if model should still be synced
    return unless model.should_sync_to_attio?
    
    model.sync_to_attio_now
  end

  def delete_record(model_class, model_id, attio_record_id)
    return unless attio_record_id.present?

    # Model might already be deleted, so we work with the class
    object_type = model_class.attio_object_type
    return unless object_type.present?

    client = Attio::Rails.client
    client.records.delete(
      object: object_type,
      id: attio_record_id
    )
    
    Attio::Rails.logger.info "Deleted Attio record #{attio_record_id} for #{model_class.name}##{model_id}"
  rescue Attio::NotFoundError
    # Record already deleted in Attio, nothing to do
    Attio::Rails.logger.info "Attio record #{attio_record_id} already deleted"
  end
end