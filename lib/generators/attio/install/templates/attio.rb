Attio::Rails.configure do |config|
  # Set your Attio API key
  config.api_key = ENV['ATTIO_API_KEY']
  
  # Optional: Set a default workspace ID
  # config.default_workspace_id = 'your-workspace-id'
end