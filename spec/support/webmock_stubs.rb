RSpec.configure do |config|
  config.before(:each) do
    # Stub all Attio API calls by default
    stub_request(:post, /api\.attio\.com\/v2\/objects\/\w+\/records/)
      .to_return(status: 200, body: { data: { id: 'attio123' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    
    stub_request(:patch, /api\.attio\.com\/v2\/objects\/\w+\/records\/\w+/)
      .to_return(status: 200, body: { data: { id: 'attio123' } }.to_json, headers: { 'Content-Type' => 'application/json' })
    
    stub_request(:delete, /api\.attio\.com\/v2\/objects\/\w+\/records\/\w+/)
      .to_return(status: 200, body: { data: { deleted: true } }.to_json, headers: { 'Content-Type' => 'application/json' })
  end
end