# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::WorkspaceManager Complete Coverage" do
  let(:workspace_manager) { Attio::Rails::WorkspaceManager.new }
  let(:client) { instance_double(Attio::Client) }
  let(:workspaces_resource) { instance_double(Attio::Resources::Workspaces) }
  let(:workspace_members_resource) { instance_double(Attio::Resources::WorkspaceMembers) }
  let(:meta_resource) { instance_double(Attio::Resources::Meta) }
  let(:logger) { instance_double(Logger, error: nil, info: nil, debug: nil) }
  
  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    workspace_manager.instance_variable_set(:@client, client)
    workspace_manager.instance_variable_set(:@logger, logger)
    workspace_manager.instance_variable_set(:@workspace_id, "workspace_123")
  end

  describe "#validate_workspace" do
    let(:workspace_id) { "workspace_456" }

    context "when client responds to workspaces and workspace exists" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
        allow(client).to receive(:workspaces).and_return(workspaces_resource)
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_return({ "id" => workspace_id })
      end

      it "returns true and calls workspaces.get (covers line 214)" do
        result = workspace_manager.send(:validate_workspace, workspace_id)
        expect(result).to be true
        expect(workspaces_resource).to have_received(:get).with(workspace_id: workspace_id)
      end
    end

    context "when client doesn't respond to workspaces" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(false)
      end

      it "returns true without calling get (covers line 214 else branch)" do
        result = workspace_manager.send(:validate_workspace, workspace_id)
        expect(result).to be true
      end
    end

    context "when workspace_id is nil" do
      it "returns false (covers line 212)" do
        result = workspace_manager.send(:validate_workspace, nil)
        expect(result).to be false
      end
    end

    context "when get raises an error" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
        allow(client).to receive(:workspaces).and_return(workspaces_resource)
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_raise(StandardError.new("Not found"))
      end

      it "logs error and returns false (covers lines 217-218)" do
        result = workspace_manager.send(:validate_workspace, workspace_id)
        expect(result).to be false
        expect(logger).to have_received(:error).with(/Failed to validate workspace/)
      end
    end
  end

  describe "#validate_member" do
    let(:workspace_id) { "workspace_789" }
    let(:member_id) { "member_123" }

    context "when workspace_id is nil" do
      it "returns false (covers line 222)" do
        result = workspace_manager.send(:validate_member, nil, member_id)
        expect(result).to be false
      end
    end

    context "when member_id is nil" do
      it "returns false (covers line 222)" do
        result = workspace_manager.send(:validate_member, workspace_id, nil)
        expect(result).to be false
      end
    end

    context "when client responds to workspace_members and member exists" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
        allow(client).to receive(:workspace_members).and_return(workspace_members_resource)
        allow(workspace_members_resource).to receive(:get_member)
          .with(workspace_id: workspace_id, member_id: member_id)
          .and_return({ "id" => member_id })
      end

      it "returns true and calls get_member (covers lines 224-225)" do
        result = workspace_manager.send(:validate_member, workspace_id, member_id)
        expect(result).to be true
        expect(workspace_members_resource).to have_received(:get_member)
      end
    end

    context "when client doesn't respond to workspace_members" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(false)
      end

      it "returns true without calling get_member (covers line 224 else branch)" do
        result = workspace_manager.send(:validate_member, workspace_id, member_id)
        expect(result).to be true
      end
    end

    context "when get_member raises an error" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
        allow(client).to receive(:workspace_members).and_return(workspace_members_resource)
        allow(workspace_members_resource).to receive(:get_member)
          .with(workspace_id: workspace_id, member_id: member_id)
          .and_raise(StandardError.new("Member not found"))
      end

      it "logs error and raises WorkspaceError (covers lines 227-228)" do
        expect {
          workspace_manager.send(:validate_member, workspace_id, member_id)
        }.to raise_error(Attio::Rails::WorkspaceManager::WorkspaceError, /Member validation failed/)
        expect(logger).to have_received(:error).with(/Failed to validate member/)
      end
    end
  end

  describe "#can_access?" do
    let(:workspace_id) { "workspace_123" }
    let(:member_id) { "member_456" }

    before do
      allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
      allow(client).to receive(:workspace_members).and_return(workspace_members_resource)
    end

    context "when member doesn't exist (get_member returns nil)" do
      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_raise(StandardError.new("Not found"))
      end

      it "returns false (covers line 233)" do
        result = workspace_manager.send(:can_access?, workspace_id, member_id, :read)
        expect(result).to be false
      end
    end

    context "when member exists with admin access_level" do
      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return({ "access_level" => "admin" })
      end

      it "returns true for admin permissions (covers lines 235-236, 254-255, 265)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :delete)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :manage)).to be true
      end
    end

    context "when member exists with member access_level" do
      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return({ "access_level" => "member" })
      end

      it "returns true for member permissions (covers lines 256-257)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :delete)).to be false
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :manage)).to be false
      end
    end

    context "when member exists with unknown access_level" do
      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return({ "access_level" => "custom" })
      end

      it "defaults to viewer permissions (covers lines 258-259)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be false
      end
    end

    context "when member data is nil" do
      before do
        allow(workspace_members_resource).to receive(:get)
          .with(member_id: member_id)
          .and_return(nil)
      end

      it "defaults to viewer permissions (covers line 251)" do
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :read)).to be true
        expect(workspace_manager.send(:can_access?, workspace_id, member_id, :write)).to be false
      end
    end
  end

  describe "#get_member" do
    let(:member_id) { "member_789" }

    context "when client responds to workspace_members" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
        allow(client).to receive(:workspace_members).and_return(workspace_members_resource)
      end

      context "when member exists" do
        let(:member_data) { { "id" => member_id, "email" => "test@example.com" } }

        before do
          allow(workspace_members_resource).to receive(:get)
            .with(member_id: member_id)
            .and_return(member_data)
        end

        it "returns member data (covers line 240)" do
          result = workspace_manager.send(:get_member, member_id)
          expect(result).to eq(member_data)
        end
      end

      context "when get raises an error" do
        before do
          allow(workspace_members_resource).to receive(:get)
            .with(member_id: member_id)
            .and_raise(StandardError.new("Not found"))
        end

        it "returns nil (covers lines 241-242)" do
          result = workspace_manager.send(:get_member, member_id)
          expect(result).to be_nil
        end
      end
    end

    context "when client doesn't respond to workspace_members" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(false)
      end

      it "returns nil (covers line 240 else branch)" do
        result = workspace_manager.send(:get_member, member_id)
        expect(result).to be_nil
      end
    end
  end

  describe "#switch_to" do
    let(:workspace_id) { "workspace_999" }

    context "when validation passes" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
        allow(client).to receive(:workspaces).and_return(workspaces_resource)
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_return({ "id" => workspace_id })
      end

      it "sets workspace_id (covers lines 246-247)" do
        workspace_manager.send(:switch_to, workspace_id)
        expect(workspace_manager.instance_variable_get(:@workspace_id)).to eq(workspace_id)
      end
    end

    context "when validation fails" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
        allow(client).to receive(:workspaces).and_return(workspaces_resource)
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_raise(StandardError.new("Not found"))
      end

      it "raises WorkspaceError (covers line 246)" do
        expect {
          workspace_manager.send(:switch_to, workspace_id)
        }.to raise_error(Attio::Rails::WorkspaceManager::WorkspaceError, /Cannot switch to invalid workspace/)
      end
    end
  end

  describe "#has_permission?" do
    it "checks permissions for admin role (covers line 265)" do
      expect(workspace_manager.send(:has_permission?, :admin, :read)).to be true
      expect(workspace_manager.send(:has_permission?, :admin, :write)).to be true
      expect(workspace_manager.send(:has_permission?, :admin, :delete)).to be true
      expect(workspace_manager.send(:has_permission?, :admin, :manage)).to be true
      expect(workspace_manager.send(:has_permission?, :admin, :invalid)).to be false
    end

    it "checks permissions for member role" do
      expect(workspace_manager.send(:has_permission?, :member, :read)).to be true
      expect(workspace_manager.send(:has_permission?, :member, :write)).to be true
      expect(workspace_manager.send(:has_permission?, :member, :delete)).to be false
    end

    it "checks permissions for viewer role" do
      expect(workspace_manager.send(:has_permission?, :viewer, :read)).to be true
      expect(workspace_manager.send(:has_permission?, :viewer, :write)).to be false
    end

    it "returns false for unknown role (covers line 270)" do
      expect(workspace_manager.send(:has_permission?, :unknown, :read)).to be false
    end
  end

  describe "#feature_flags" do
    context "when cache is not set" do
      before do
        workspace_manager.instance_variable_set(:@cache, nil)
        allow(client).to receive(:respond_to?).with(:meta).and_return(true)
        allow(client).to receive(:meta).and_return(meta_resource)
      end

      it "fetches directly from meta.features (covers line 161)" do
        features = { "feature1" => true, "feature2" => false }
        allow(meta_resource).to receive(:features).and_return(features)

        result = workspace_manager.feature_flags
        expect(result).to eq(features)
        expect(meta_resource).to have_received(:features)
      end

      it "returns empty hash on error (covers lines 164-165)" do
        allow(meta_resource).to receive(:features).and_raise(StandardError.new("Error"))
        
        result = workspace_manager.feature_flags
        expect(result).to eq({})
        expect(logger).to have_received(:error).with(/Failed to fetch feature flags/)
      end
    end

    context "when client doesn't respond to meta" do
      before do
        allow(client).to receive(:respond_to?).with(:meta).and_return(false)
      end

      it "returns empty hash (covers line 152)" do
        result = workspace_manager.feature_flags
        expect(result).to eq({})
      end
    end
  end

  describe "#sync_rails_users" do
    let(:workspace_id) { "workspace_123" }
    let(:users) { [] }

    before do
      workspace_manager.instance_variable_set(:@workspace_id, workspace_id)
      allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
      allow(client).to receive(:workspace_members).and_return(workspace_members_resource)
    end

    context "when updating existing member role fails" do
      let(:existing_member) do
        { email: "existing@example.com", id: "member_existing", role: "member" }
      end
      let(:user) { double("User", email: "existing@example.com", attio_workspace_role: "admin") }
      let(:users) { [user] }

      before do
        allow(workspace_members_resource).to receive(:list)
          .with(workspace_id: workspace_id)
          .and_return([existing_member])
        
        allow(user).to receive(:respond_to?).with(:attio_workspace_role).and_return(true)
        
        allow(workspace_members_resource).to receive(:update)
          .with(
            workspace_id: workspace_id,
            member_id: "member_existing", 
            data: { role: "admin" }
          )
          .and_raise(StandardError.new("Update failed"))
      end

      it "handles update failure gracefully (covers error handling in sync_rails_users)" do
        result = workspace_manager.sync_rails_users(users)
        
        expect(result[:updated]).to eq(0)
        expect(result[:errors]).to include("existing@example.com")
        expect(logger).to have_received(:error).with(/Failed to update role/)
      end
    end

    context "when inviting new member fails" do
      let(:user) { double("User", email: "new@example.com", attio_workspace_role: "member") }
      let(:users) { [user] }

      before do
        allow(workspace_members_resource).to receive(:list)
          .with(workspace_id: workspace_id)
          .and_return([]) # No existing members
        
        allow(user).to receive(:respond_to?).with(:attio_workspace_role).and_return(true)
        
        allow(workspace_members_resource).to receive(:invite)
          .with(
            workspace_id: workspace_id,
            email: "new@example.com",
            role: "member"
          )
          .and_raise(StandardError.new("Invitation failed"))
      end

      it "handles invitation failure gracefully (covers error handling in sync_rails_users)" do
        result = workspace_manager.sync_rails_users(users)
        
        expect(result[:invited]).to eq(0)
        expect(result[:errors]).to include("new@example.com")
        expect(logger).to have_received(:error).with(/Failed to invite/)
      end
    end

    context "when user has no attio_workspace_role method" do
      let(:user) { double("User", email: "default@example.com") }
      let(:users) { [user] }

      before do
        allow(workspace_members_resource).to receive(:list)
          .with(workspace_id: workspace_id)
          .and_return([])
        
        allow(user).to receive(:respond_to?).with(:attio_workspace_role).and_return(false)
        
        allow(workspace_members_resource).to receive(:invite)
          .with(
            workspace_id: workspace_id,
            email: "default@example.com",
            role: "member"  # Should default to member
          )
          .and_return({ "id" => "new_member" })
      end

      it "uses default member role (covers line 200)" do
        result = workspace_manager.sync_rails_users(users)
        
        expect(result[:invited]).to eq(1)
        expect(workspace_members_resource).to have_received(:invite)
          .with(hash_including(role: "member"))
      end
    end
  end

  describe "#determine_user_role" do
    context "with Symbol condition that returns true" do
      let(:user) { double("User", is_admin: true) }
      let(:role_mapping) { { is_admin: "admin", is_member: "member" } }

      it "returns matching role (covers lines 195-196)" do
        result = workspace_manager.send(:determine_user_role, user, role_mapping)
        expect(result).to eq("admin")
      end
    end

    context "with Proc condition that returns true" do
      let(:user) { double("User", email: "admin@example.com") }
      let(:role_mapping) do
        {
          ->(u) { u.email.include?("admin") } => "admin",
          ->(u) { u.email.include?("member") } => "member"
        }
      end

      it "returns matching role (covers lines 197-198)" do
        result = workspace_manager.send(:determine_user_role, user, role_mapping)
        expect(result).to eq("admin")
      end
    end

    context "with String condition" do
      let(:user) { double("User", admin_flag: true) }
      let(:role_mapping) { { "admin_flag" => "admin" } }

      before do
        allow(user).to receive(:respond_to?).with("admin_flag").and_return(true)
      end

      it "returns matching role (covers lines 199-200)" do
        result = workspace_manager.send(:determine_user_role, user, role_mapping)
        expect(result).to eq("admin")
      end
    end

    context "when no conditions match" do
      let(:user) { double("User") }
      let(:role_mapping) { { is_admin: "admin" } }

      before do
        allow(user).to receive(:is_admin).and_return(false)
      end

      it "returns default member role (covers line 204)" do
        result = workspace_manager.send(:determine_user_role, user, role_mapping)
        expect(result).to eq("member")
      end
    end
  end

  describe "#ensure_workspace!" do
    let(:workspace_id) { "workspace_111" }

    context "when validation passes" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
        allow(client).to receive(:workspaces).and_return(workspaces_resource)
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_return({ "id" => workspace_id })
      end

      it "returns true (covers line 208 success path)" do
        result = workspace_manager.ensure_workspace!(workspace_id)
        expect(result).to be true
      end
    end

    context "when validation fails" do
      before do
        allow(client).to receive(:respond_to?).with(:workspaces).and_return(true)
        allow(client).to receive(:workspaces).and_return(workspaces_resource)
        allow(workspaces_resource).to receive(:get)
          .with(workspace_id: workspace_id)
          .and_raise(StandardError.new("Not found"))
      end

      it "raises WorkspaceError (covers line 208 error path)" do
        expect {
          workspace_manager.ensure_workspace!(workspace_id)
        }.to raise_error(Attio::Rails::WorkspaceManager::WorkspaceError, /Invalid workspace/)
      end
    end
  end
end