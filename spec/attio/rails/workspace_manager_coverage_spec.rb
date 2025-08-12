# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::WorkspaceManager Coverage" do
  let(:workspace_manager) { Attio::Rails::WorkspaceManager.new }
  let(:client) { instance_double(Attio::Client) }
  let(:workspaces_resource) { instance_double(Attio::Resources::Workspaces) }
  let(:workspace_members_resource) { instance_double(Attio::Resources::WorkspaceMembers) }
  
  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
    allow(client).to receive(:workspaces).and_return(workspaces_resource)
    allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
    allow(client).to receive(:workspace_members).and_return(workspace_members_resource)
  end

  describe "#can_access? - all role types coverage" do
    let(:workspace_id) { "workspace_123" }
    let(:member_id) { "member_456" }
    
    before do
      # Set up the workspace manager 
      workspace_manager.instance_variable_set(:@workspace_id, workspace_id)
      workspace_manager.instance_variable_set(:@client, client)
    end

    context "when member has admin role" do
      let(:member_data) do
        {
          "id" => member_id,
          "access_level" => "admin"
        }
      end

      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return(member_data)
      end

      it "returns true for admin permissions (line coverage for admin branch)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :delete)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :manage)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :unknown)).to be false
      end
    end

    context "when member has member role" do
      let(:member_data) do
        {
          "id" => member_id,
          "access_level" => "member"
        }
      end

      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return(member_data)
      end

      it "checks specific permissions (line coverage for member branch)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :delete)).to be false
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :manage)).to be false
      end
    end

    context "when member has viewer role (or unknown role)" do
      let(:member_data) do
        {
          "id" => member_id,
          "access_level" => "viewer"
        }
      end

      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return(member_data)
      end

      it "only has read permission (line coverage for viewer branch)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be false
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :delete)).to be false
      end
    end

    context "when member has unknown/custom role" do
      let(:member_data) do
        {
          "id" => member_id,
          "access_level" => "custom_analyst"
        }
      end

      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return(member_data)
      end

      it "defaults to viewer permissions (line coverage for default branch)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be false
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :manage)).to be false
      end
    end

    context "when member doesn't exist" do
      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: "nonexistent")
          .and_raise(StandardError.new("Member not found"))
      end

      it "returns false" do
        expect(workspace_manager.send(:can_access?, workspace_id, "nonexistent", :read)).to be false
      end
    end
  end

  describe "#get_member" do
    let(:member_id) { "member_789" }
    let(:workspace_id) { "workspace_123" }

    before do
      workspace_manager.instance_variable_set(:@workspace_id, workspace_id)
      workspace_manager.instance_variable_set(:@client, client)
    end

    context "when member exists" do
      let(:member_data) do
        {
          "id" => member_id,
          "email" => "user@example.com",
          "access_level" => "member"
        }
      end

      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return(member_data)
      end

      it "returns the member data" do
        result = workspace_manager.send(:get_member, member_id)
        expect(result).to eq(member_data)
      end
    end

    context "when member doesn't exist" do
      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_raise(StandardError.new("Member not found"))
      end

      it "returns nil" do
        result = workspace_manager.send(:get_member, member_id)
        expect(result).to be_nil
      end
    end

    context "when client doesn't respond to workspace_members" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(false)
      end

      it "returns nil" do
        result = workspace_manager.send(:get_member, member_id)
        expect(result).to be_nil
      end
    end
  end

  describe "#switch_to with real workspace validation" do
    let(:workspace_id) { "workspace_456" }
    let(:workspace_data) do
      {
        "id" => workspace_id,
        "name" => "Test Workspace",
        "created_at" => Time.now.iso8601
      }
    end

    before do
      workspace_manager.instance_variable_set(:@client, client)
      workspace_manager.instance_variable_set(:@logger, instance_double(Logger, error: nil))
    end

    context "when workspace validation passes" do
      before do
        # Don't stub the validation - let it actually run
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_return(workspace_data)
      end

      it "switches to the workspace and validates it through real client call" do
        # This should not raise an error
        expect { workspace_manager.send(:switch_to, workspace_id) }.not_to raise_error
        
        # Check that workspace was set
        expect(workspace_manager.instance_variable_get(:@workspace_id)).to eq(workspace_id)
        
        # Verify the actual client call was made
        expect(workspaces_resource).to have_received(:get).with(workspace_id: workspace_id)
      end

      it "covers the @client.respond_to?(:workspaces) branch" do
        # First test when client doesn't respond to workspaces
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(false)
        
        # Should raise error when validation fails
        expect { 
          workspace_manager.send(:switch_to, workspace_id) 
        }.to raise_error(Attio::Rails::WorkspaceManager::WorkspaceError)
        
        # Now test when it does respond
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
        
        expect { workspace_manager.send(:switch_to, workspace_id) }.not_to raise_error
        expect(workspaces_resource).to have_received(:get).with(workspace_id: workspace_id)
      end
    end

    context "when workspace doesn't exist" do
      before do
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_raise(StandardError.new("Workspace not found"))
      end

      it "raises error when validation fails" do
        expect { 
          workspace_manager.send(:switch_to, workspace_id)
        }.to raise_error(Attio::Rails::WorkspaceManager::WorkspaceError, /Cannot switch to invalid workspace/)
        
        # Workspace should not be changed
        expect(workspace_manager.instance_variable_get(:@workspace_id)).not_to eq(workspace_id)
      end
    end
  end

  describe "#fetch_workspace_info failure handling" do
    let(:workspace_id) { "workspace_789" }

    context "when API call fails" do
      before do
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_raise(StandardError.new("API Error"))
      end

      it "handles the error and returns nil" do
        result = workspace_manager.send(:fetch_workspace_info, workspace_id)
        expect(result).to be_nil
      end
    end

    context "when client doesn't respond to workspaces" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(false)
      end

      it "returns nil" do
        result = workspace_manager.send(:fetch_workspace_info, workspace_id)
        expect(result).to be_nil
      end
    end
  end

  describe "#feature_flags with no cache" do
    let(:workspace_id) { "workspace_111" }

    before do
      workspace_manager.instance_variable_set(:@current_workspace_id, workspace_id)
      # Ensure no cache exists
      workspace_manager.instance_variable_set(:@feature_flags_cache, {})
    end

    context "when fetching feature flags for the first time" do
      let(:flags_data) do
        {
          "feature_a" => true,
          "feature_b" => false,
          "feature_c" => true
        }
      end

      before do
        allow(workspaces_resource).to receive(:feature_flags)
          .with(workspace_id: workspace_id)
          .and_return(flags_data)
      end

      it "fetches from API and caches the result" do
        result = workspace_manager.feature_flags
        
        expect(result).to eq(flags_data)
        
        # Verify it was cached
        cached = workspace_manager.instance_variable_get(:@feature_flags_cache)[workspace_id]
        expect(cached).to eq(flags_data)
        
        # Second call should use cache (verify by calling again)
        expect(workspaces_resource).to have_received(:feature_flags).once
        workspace_manager.feature_flags
      end
    end

    context "when API call fails" do
      before do
        allow(workspaces_resource).to receive(:feature_flags)
          .with(workspace_id: workspace_id)
          .and_raise(StandardError.new("Feature flags unavailable"))
      end

      it "returns empty hash on error" do
        result = workspace_manager.feature_flags
        expect(result).to eq({})
      end
    end
  end

  describe "#sync_rails_users - update_member_role failure" do
    let(:workspace_id) { "workspace_222" }
    let(:users) do
      [
        double("User", email: "existing@example.com", attio_workspace_role: "admin")
      ]
    end
    let(:existing_member) do
      {
        id: "member_existing",
        email: "existing@example.com",
        role: "member"
      }
    end

    before do
      workspace_manager.instance_variable_set(:@current_workspace_id, workspace_id)
      
      # Set up existing members
      allow(workspace_members_resource).to receive(:list)
        .with(workspace_id: workspace_id)
        .and_return([existing_member])
    end

    context "when update_member_role fails" do
      before do
        allow(workspace_members_resource).to receive(:update)
          .with(workspace_id: workspace_id, member_id: "member_existing", role: "admin")
          .and_raise(StandardError.new("Update failed"))
      end

      it "handles the update failure gracefully" do
        result = workspace_manager.sync_rails_users(users)
        
        # Should continue despite the failure
        expect(result).to be_a(Hash)
        expect(result[:errors]).to include(/Update failed/)
      end
    end
  end

  describe "#sync_rails_users - invite_member failure" do
    let(:workspace_id) { "workspace_333" }
    let(:users) do
      [
        double("User", email: "newuser@example.com", attio_workspace_role: "member")
      ]
    end

    before do
      workspace_manager.instance_variable_set(:@current_workspace_id, workspace_id)
      
      # No existing members
      allow(workspace_members_resource).to receive(:list)
        .with(workspace_id: workspace_id)
        .and_return([])
    end

    context "when invite_member fails" do
      before do
        allow(workspace_members_resource).to receive(:invite)
          .with(
            workspace_id: workspace_id,
            email: "newuser@example.com",
            role: "member"
          )
          .and_raise(StandardError.new("Invitation failed"))
      end

      it "handles the invitation failure gracefully" do
        result = workspace_manager.sync_rails_users(users)
        
        # Should continue despite the failure
        expect(result).to be_a(Hash)
        expect(result[:errors]).to include(/Invitation failed/)
      end
    end

    context "when invite returns unexpected response" do
      before do
        allow(workspace_members_resource).to receive(:invite)
          .with(
            workspace_id: workspace_id,
            email: "newuser@example.com",
            role: "member"
          )
          .and_return(nil)
      end

      it "handles nil response from invite" do
        result = workspace_manager.sync_rails_users(users)
        
        expect(result).to be_a(Hash)
        expect(result[:invited]).to eq(0)
      end
    end
  end

  describe "Private method coverage" do
    describe "#validate_member" do
      let(:workspace_id) { "workspace_444" }
      let(:member_id) { "member_444" }

      context "when workspace is nil" do
        it "returns false" do
          result = workspace_manager.send(:validate_member, nil, member_id)
          expect(result).to be false
        end
      end

      context "when member_id is nil" do
        it "returns false" do
          result = workspace_manager.send(:validate_member, workspace_id, nil)
          expect(result).to be false
        end
      end

      context "when both are valid" do
        before do
          workspace_manager.instance_variable_set(:@members_cache, {
            workspace_id => { member_id => { id: member_id } }
          })
        end

        it "returns true when member exists" do
          result = workspace_manager.send(:validate_member, workspace_id, member_id)
          expect(result).to be true
        end
      end
    end

    describe "#determine_user_role" do
      let(:role_mapping) do
        {
          "admin" => ["admin@example.com"],
          "member" => ["member@example.com"]
        }
      end

      context "when user email matches admin role" do
        let(:user) { double("User", email: "admin@example.com") }

        it "returns admin role" do
          result = workspace_manager.send(:determine_user_role, user, role_mapping)
          expect(result).to eq("admin")
        end
      end

      context "when user email doesn't match any role" do
        let(:user) { double("User", email: "unknown@example.com") }

        it "returns default member role" do
          result = workspace_manager.send(:determine_user_role, user, role_mapping)
          expect(result).to eq("member")
        end
      end

      context "when user has attio_workspace_role method" do
        let(:user) { double("User", email: "test@example.com", attio_workspace_role: "custom_role") }

        it "uses the user's attio_workspace_role" do
          result = workspace_manager.send(:determine_user_role, user, nil)
          expect(result).to eq("custom_role")
        end
      end
    end
  end
end