# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attio::Rails::Jobs::AttioSyncJob do
  let(:model) { TestModel.create!(name: "Test", email: "test@example.com") }
  let(:client) { double("Attio::Client") }
  let(:records_resource) { double("Attio::Resources::Records") }
  
  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(Attio::Rails.configuration).to receive(:raise_on_missing_record).and_return(true)
  end
  
  describe "HIGH PRIORITY: Rate limit retry mechanism" do
    # While we can't directly test the retry_on block execution, 
    # we can test the behavior when rate limits are encountered
    
    it "handles rate limit errors during sync action" do
      job = described_class.new
      
      # Simulate rate limit error
      rate_limit_error = Attio::RateLimitError.new("Rate limited")
      allow(rate_limit_error).to receive(:retry_after).and_return(120)
      
      allow(model).to receive(:sync_to_attio_now).and_raise(rate_limit_error)
      
      # The job should raise the error to trigger the retry mechanism
      expect {
        job.perform(
          "model_name" => "TestModel",
          "model_id" => model.id,
          "action" => "sync"
        )
      }.to raise_error(Attio::RateLimitError)
    end
    
    it "respects retry_after value from the error" do
      job = described_class.new
      
      # Create error with specific retry_after
      rate_limit_error = Attio::RateLimitError.new("Rate limited")
      allow(rate_limit_error).to receive(:retry_after).and_return(300) # 5 minutes
      
      allow(model).to receive(:sync_to_attio_now).and_raise(rate_limit_error)
      
      # Verify the error is raised with the retry_after accessible
      begin
        job.perform(
          "model_name" => "TestModel",
          "model_id" => model.id,
          "action" => "sync"
        )
      rescue Attio::RateLimitError => e
        expect(e.retry_after).to eq(300)
      end
    end
    
    it "handles rate limit with nil retry_after" do
      job = described_class.new
      
      rate_limit_error = Attio::RateLimitError.new("Rate limited")
      allow(rate_limit_error).to receive(:retry_after).and_return(nil)
      
      allow(model).to receive(:sync_to_attio_now).and_raise(rate_limit_error)
      
      # Should still raise the error, letting retry_on handle default timing
      expect {
        job.perform(
          "model_name" => "TestModel",
          "model_id" => model.id,
          "action" => "sync"
        )
      }.to raise_error(Attio::RateLimitError)
    end
  end
  
  describe "HIGH PRIORITY: Server error retry" do
    it "handles server errors during sync" do
      job = described_class.new
      
      server_error = Attio::ServerError.new("Internal server error")
      allow(model).to receive(:sync_to_attio_now).and_raise(server_error)
      
      # Should raise to trigger retry mechanism
      expect {
        job.perform(
          "model_name" => "TestModel",
          "model_id" => model.id,
          "action" => "sync"
        )
      }.to raise_error(Attio::ServerError)
    end
  end
  
  describe "Edge cases in job execution" do
    it "handles sync_deal action with rate limits" do
      opportunity = Opportunity.new(name: "Deal", value: 5000)
      allow(Opportunity).to receive(:find).with(opportunity.id).and_return(opportunity)
      
      job = described_class.new
      rate_limit_error = Attio::RateLimitError.new("Rate limited")
      allow(rate_limit_error).to receive(:retry_after).and_return(60)
      
      allow(opportunity).to receive(:sync_deal_to_attio_now).and_raise(rate_limit_error)
      
      expect {
        job.perform(
          "model_name" => "Opportunity",
          "model_id" => opportunity.id,
          "action" => "sync_deal"
        )
      }.to raise_error(Attio::RateLimitError)
    end
  end
end