# frozen_string_literal: true

Attio::Rails.configure do |config|
  # Set your Attio API key
  config.api_key = ENV.fetch("ATTIO_API_KEY", nil)

  # Optional: Set a default workspace ID
  # config.default_workspace_id = 'your-workspace-id'
end
