# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Dealable Win/Loss Status Coverage" do
  let(:deal_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "test_models"
      include Attio::Rails::Concerns::Dealable
      
      # Add status and related attributes
      attr_accessor :status, :closed_date, :lost_reason, :stage_id, :current_stage_id, :attio_deal_id
      
      def deal_name
        "Test Deal"
      end
      
      def deal_value
        1000
      end
    end.tap do |klass|
      klass.attio_pipeline_id = "test_pipeline"
    end
  end

  let(:deal) { deal_class.new }
  let(:client) { instance_double(Attio::Client) }
  let(:deals_resource) { instance_double(Attio::Resources::Deals) }
  let(:logger) { instance_double(Logger) }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(logger)
    allow(client).to receive(:respond_to?).with(:deals).and_return(true)
    allow(client).to receive(:deals).and_return(deals_resource)
  end

  describe "#sync_deal_to_attio_now - status == 'won' branch" do
    before do
      # Set up the deal as existing (has attio_deal_id)
      deal.attio_deal_id = "existing_deal_123"
      
      # Set status to "won"
      deal.status = "won"
      deal.closed_date = Date.today
    end

    context "when deal status is 'won'" do
      it "updates deal as won in Attio successfully (line 76-78)" do
        # Stage hasn't changed, but status is "won"
        deal.current_stage_id = "same_stage"
        deal.stage_id = "same_stage"
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_123",
          data: { status: "won", closed_date: Date.today }
        ).and_return({ "data" => { "id" => "existing_deal_123", "status" => "won" } })
        
        # This should take the elsif branch at line 76
        deal.sync_deal_to_attio_now
      end

      it "logs error and re-raises when marking as won fails (lines 79-81)" do
        # Set up for won status branch
        deal.current_stage_id = "same_stage"
        deal.stage_id = "same_stage"
        
        error = StandardError.new("API error on win")
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_123",
          data: { status: "won", closed_date: Date.today }
        ).and_raise(error)
        
        expect(logger).to receive(:error).with("Failed to mark deal as won: API error on win")
        
        expect {
          deal.sync_deal_to_attio_now
        }.to raise_error(StandardError, "API error on win")
      end
    end
  end

  describe "#sync_deal_to_attio_now - status == 'lost' branch" do
    before do
      # Set up the deal as existing
      deal.attio_deal_id = "existing_deal_456"
      
      # Set status to "lost"
      deal.status = "lost"
      deal.lost_reason = "No budget"
    end

    context "when deal status is 'lost'" do
      it "updates deal as lost in Attio successfully (line 83-85)" do
        # Stage hasn't changed, status isn't "won", but is "lost"
        deal.current_stage_id = "same_stage"
        deal.stage_id = "same_stage"
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_456",
          data: { status: "lost", lost_reason: "No budget" }
        ).and_return({ "data" => { "id" => "existing_deal_456", "status" => "lost" } })
        
        # This should take the elsif branch at line 83
        deal.sync_deal_to_attio_now
      end

      it "logs error and re-raises when marking as lost fails (lines 86-88)" do
        # Set up for lost status branch
        deal.current_stage_id = "same_stage"
        deal.stage_id = "same_stage"
        
        error = StandardError.new("API error on loss")
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_456",
          data: { status: "lost", lost_reason: "No budget" }
        ).and_raise(error)
        
        expect(logger).to receive(:error).with("Failed to mark deal as lost: API error on loss")
        
        expect {
          deal.sync_deal_to_attio_now
        }.to raise_error(StandardError, "API error on loss")
      end
    end
  end

  describe "#sync_deal_to_attio_now - else branch (regular update)" do
    before do
      deal.attio_deal_id = "existing_deal_789"
    end

    context "when no special conditions apply" do
      it "performs regular deal update (line 91)" do
        # No stage change, not won, not lost - just a regular update
        deal.current_stage_id = "same_stage"
        deal.stage_id = "same_stage"
        deal.status = "in_progress" # Not won or lost
        
        deal_data = deal.to_attio_deal
        
        expect(deals_resource).to receive(:update).with(
          id: "existing_deal_789",
          data: deal_data
        ).and_return({ "data" => { "id" => "existing_deal_789" } })
        
        # This should take the else branch at line 90-91
        deal.sync_deal_to_attio_now
      end
    end
  end

  describe "Integration test for all branches" do
    it "correctly routes through all conditional branches based on deal state" do
      # Test 1: Stage changed branch
      deal.attio_deal_id = "deal_001"
      deal.current_stage_id = "old_stage"
      deal.stage_id = "new_stage"
      
      expect(deals_resource).to receive(:update).with(
        id: "deal_001",
        data: { stage_id: "new_stage" }
      ).and_return({ "data" => { "id" => "deal_001" } })
      
      deal.sync_deal_to_attio_now
      
      # Test 2: Status = won branch
      deal.attio_deal_id = "deal_002"
      deal.current_stage_id = "stage"
      deal.stage_id = "stage" # Same stage
      deal.status = "won"
      deal.closed_date = Date.today
      
      expect(deals_resource).to receive(:update).with(
        id: "deal_002",
        data: { status: "won", closed_date: Date.today }
      ).and_return({ "data" => { "id" => "deal_002" } })
      
      deal.sync_deal_to_attio_now
      
      # Test 3: Status = lost branch
      deal.attio_deal_id = "deal_003"
      deal.status = "lost"
      deal.lost_reason = "Competition"
      
      expect(deals_resource).to receive(:update).with(
        id: "deal_003",
        data: { status: "lost", lost_reason: "Competition" }
      ).and_return({ "data" => { "id" => "deal_003" } })
      
      deal.sync_deal_to_attio_now
      
      # Test 4: Regular update branch
      deal.attio_deal_id = "deal_004"
      deal.status = "active"
      
      expect(deals_resource).to receive(:update).with(
        id: "deal_004",
        data: deal.to_attio_deal
      ).and_return({ "data" => { "id" => "deal_004" } })
      
      deal.sync_deal_to_attio_now
    end
  end

  describe "Edge cases for status conditions" do
    before do
      deal.attio_deal_id = "edge_case_deal"
    end

    it "handles when respond_to?(:status) is false" do
      # Remove status method
      if deal.respond_to?(:status)
        deal.instance_eval { undef :status }
      end
      
      deal.current_stage_id = "stage"
      deal.stage_id = "stage"
      
      # Should go to the else branch (regular update)
      expect(deals_resource).to receive(:update).with(
        id: "edge_case_deal",
        data: deal.to_attio_deal
      )
      
      deal.sync_deal_to_attio_now
    end

    it "handles when status exists but is nil" do
      deal.status = nil
      deal.current_stage_id = "stage"
      deal.stage_id = "stage"
      
      # Should go to the else branch (regular update)
      expect(deals_resource).to receive(:update).with(
        id: "edge_case_deal",
        data: deal.to_attio_deal
      )
      
      deal.sync_deal_to_attio_now
    end

    it "handles when status is 'won' but closed_date is nil" do
      deal.status = "won"
      deal.closed_date = nil
      deal.current_stage_id = "stage"
      deal.stage_id = "stage"
      
      expect(deals_resource).to receive(:update).with(
        id: "edge_case_deal",
        data: { status: "won", closed_date: nil }
      )
      
      deal.sync_deal_to_attio_now
    end

    it "handles when status is 'lost' but lost_reason is nil" do
      deal.status = "lost"
      deal.lost_reason = nil
      deal.current_stage_id = "stage"
      deal.stage_id = "stage"
      
      expect(deals_resource).to receive(:update).with(
        id: "edge_case_deal",
        data: { status: "lost", lost_reason: nil }
      )
      
      deal.sync_deal_to_attio_now
    end
  end
end