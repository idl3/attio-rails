# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::WorkspaceManager Batch Operations" do
  let(:client) { double("Attio::Client") }
  let(:manager) { Attio::Rails::WorkspaceManager.new(client) }
  let(:members_resource) { double("Attio::Resources::WorkspaceMembers") }
  
  before do
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
    allow(client).to receive(:workspace_members).and_return(members_resource)
  end
  
  describe "HIGH PRIORITY: Batch member addition with failures" do
    it "handles mixed success and failure in batch operations" do
      users = [
        { email: "success1@example.com", role: "member" },
        { email: "fail1@example.com", role: "member" },
        { email: "success2@example.com", role: "admin" },
        { email: "fail2@example.com", role: "member" },
        { email: "success3@example.com", role: "member" }
      ]
      
      # Configure responses for each user
      allow(members_resource).to receive(:invite).with(email: "success1@example.com", role: "member")
        .and_return({ "id" => "member_1", "email" => "success1@example.com" })
      
      allow(members_resource).to receive(:invite).with(email: "fail1@example.com", role: "member")
        .and_raise(Attio::Error, "Invalid email format")
      
      allow(members_resource).to receive(:invite).with(email: "success2@example.com", role: "admin")
        .and_return({ "id" => "member_2", "email" => "success2@example.com" })
      
      allow(members_resource).to receive(:invite).with(email: "fail2@example.com", role: "member")
        .and_raise(Attio::Error, "User already exists")
      
      allow(members_resource).to receive(:invite).with(email: "success3@example.com", role: "member")
        .and_return({ "id" => "member_3", "email" => "success3@example.com" })
      
      results = manager.add_members(users)
      
      # Verify correct categorization
      expect(results[:successful].size).to eq(3)
      expect(results[:failed].size).to eq(2)
      
      # Verify successful results have correct data
      expect(results[:successful].map { |r| r[:data]["email"] }).to contain_exactly(
        "success1@example.com", "success2@example.com", "success3@example.com"
      )
      
      # Verify failed results have error details
      failed_emails = results[:failed].map { |f| f[:user][:email] }
      expect(failed_emails).to contain_exactly("fail1@example.com", "fail2@example.com")
      
      expect(results[:failed].find { |f| f[:user][:email] == "fail1@example.com" }[:error])
        .to eq("Invalid email format")
      expect(results[:failed].find { |f| f[:user][:email] == "fail2@example.com" }[:error])
        .to eq("User already exists")
    end
    
    it "handles complete failure of all batch operations" do
      users = [
        { email: "fail1@example.com", role: "member" },
        { email: "fail2@example.com", role: "admin" }
      ]
      
      allow(members_resource).to receive(:invite).and_raise(Attio::Error, "API is down")
      
      results = manager.add_members(users)
      
      expect(results[:successful]).to be_empty
      expect(results[:failed].size).to eq(2)
      results[:failed].each do |failure|
        expect(failure[:error]).to eq("API is down")
      end
    end
    
    it "handles network errors differently from validation errors" do
      users = [
        { email: "network_error@example.com", role: "member" },
        { email: "validation_error@example.com", role: "invalid_role" }
      ]
      
      allow(members_resource).to receive(:invite).with(email: "network_error@example.com", role: "member")
        .and_raise(Attio::NetworkError, "Connection timeout")
      
      allow(members_resource).to receive(:invite).with(email: "validation_error@example.com", role: "invalid_role")
        .and_raise(Attio::ValidationError, "Invalid role specified")
      
      results = manager.add_members(users)
      
      expect(results[:successful]).to be_empty
      expect(results[:failed].size).to eq(2)
      
      network_failure = results[:failed].find { |f| f[:user][:email] == "network_error@example.com" }
      validation_failure = results[:failed].find { |f| f[:user][:email] == "validation_error@example.com" }
      
      expect(network_failure[:error]).to eq("Connection timeout")
      expect(validation_failure[:error]).to eq("Invalid role specified")
    end
  end
  
  describe "HIGH PRIORITY: Member update error handling" do
    it "returns error details when update fails" do
      member_id = "member_123"
      new_role = "admin"
      
      allow(members_resource).to receive(:update)
        .with(member_id, role: new_role)
        .and_raise(Attio::Error, "Insufficient permissions")
      
      expect(Attio::Rails.logger).to receive(:error).with(/Failed to update member role/)
      
      result = manager.update_member_role(member_id, new_role)
      
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Insufficient permissions")
      expect(result[:member_id]).to eq(member_id)
    end
    
    it "handles rate limits during member updates" do
      member_id = "member_456"
      new_role = "member"
      
      rate_limit_error = Attio::RateLimitError.new("Rate limit exceeded")
      allow(rate_limit_error).to receive(:retry_after).and_return(60)
      
      allow(members_resource).to receive(:update)
        .with(member_id, role: new_role)
        .and_raise(rate_limit_error)
      
      result = manager.update_member_role(member_id, new_role)
      
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Rate limit exceeded")
    end
  end
  
  describe "HIGH PRIORITY: Member removal error handling" do
    it "handles errors when removing members" do
      member_id = "member_789"
      
      allow(members_resource).to receive(:remove)
        .with(member_id)
        .and_raise(Attio::Error, "Member not found")
      
      expect(Attio::Rails.logger).to receive(:error).with(/Failed to remove member/)
      
      result = manager.remove_member(member_id)
      
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Member not found")
    end
    
    it "handles authorization errors differently" do
      member_id = "owner_001"
      
      allow(members_resource).to receive(:remove)
        .with(member_id)
        .and_raise(Attio::AuthorizationError, "Cannot remove workspace owner")
      
      result = manager.remove_member(member_id)
      
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Cannot remove workspace owner")
    end
  end
  
  describe "HIGH PRIORITY: Workspace switching errors" do
    it "handles invalid workspace ID" do
      invalid_workspace = "non_existent_workspace"
      
      allow(client).to receive(:workspace_id=)
        .with(invalid_workspace)
        .and_raise(Attio::Error, "Workspace not found")
      
      expect(Attio::Rails.logger).to receive(:error).with(/Failed to switch workspace/)
      
      result = manager.switch_workspace(invalid_workspace)
      
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Workspace not found")
      expect(result[:workspace_id]).to eq(invalid_workspace)
    end
    
    it "handles permission errors when switching workspace" do
      restricted_workspace = "restricted_workspace_id"
      
      allow(client).to receive(:workspace_id=)
        .with(restricted_workspace)
        .and_raise(Attio::AuthorizationError, "No access to workspace")
      
      result = manager.switch_workspace(restricted_workspace)
      
      expect(result[:success]).to be false
      expect(result[:error]).to eq("No access to workspace")
    end
  end
  
  describe "Sync with user record failures" do
    it "continues operation even if sync with user fails" do
      email = "test@example.com"
      user = double("User")
      
      # API call succeeds
      allow(members_resource).to receive(:invite)
        .with(email: email, role: "member")
        .and_return({ "id" => "member_new", "email" => email })
      
      # But sync with user record fails
      allow(user).to receive(:update_column)
        .with(:attio_member_id, "member_new")
        .and_raise(ActiveRecord::RecordNotFound, "User record deleted")
      
      expect(Attio::Rails.logger).to receive(:error).with(/Failed to sync member with user record/)
      
      result = manager.invite_member(email: email, sync_with_user: user)
      
      # API operation should still be considered successful
      expect(result[:success]).to be true
      expect(result[:member_id]).to eq("member_new")
      expect(result[:data]["email"]).to eq(email)
    end
  end
end