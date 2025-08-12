# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attio::Rails::WorkspaceManager do
  let(:workspace_id) { "test_workspace" }
  let(:api_key) { "test_api_key" }
  let(:manager) { described_class.new(workspace_id: workspace_id, api_key: api_key) }
  let(:client) { instance_double(Attio::Client) }
  let(:workspace_members) { instance_double(Attio::Resources::WorkspaceMembers) }
  let(:meta) { instance_double(Attio::Resources::Meta) }
  let(:cache) { double("cache") }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(Rails).to receive(:cache).and_return(cache) if defined?(Rails)
  end

  describe "#initialize" do
    it "uses provided workspace_id and api_key" do
      expect(manager.workspace_id).to eq(workspace_id)
    end

    it "falls back to configuration values" do
      allow(Attio::Rails.configuration).to receive(:default_workspace_id).and_return("config_workspace")
      allow(Attio::Rails.configuration).to receive(:api_key).and_return("config_key")

      manager = described_class.new
      expect(manager.workspace_id).to eq("config_workspace")
    end
  end

  describe "#info" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching enabled" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches workspace info" do
        workspace_info = { workspace_id: workspace_id, name: "Test Workspace" }
        allow(meta).to receive(:identify).and_return(workspace_info)

        expect(cache).to receive(:fetch).with("attio:workspace:#{workspace_id}:info", expires_in: 1.hour).and_yield

        result = manager.info
        expect(result).to eq(workspace_info)
      end
    end

    context "without caching" do
      let(:manager) { described_class.new(workspace_id: workspace_id, api_key: api_key) }

      before do
        hide_const("::Rails")
      end

      it "fetches workspace info directly" do
        workspace_info = { workspace_id: workspace_id, name: "Test Workspace" }
        expect(meta).to receive(:identify).and_return(workspace_info)

        result = manager.info
        expect(result).to eq(workspace_info)
      end
    end

    it "returns empty hash on error" do
      allow(cache).to receive(:fetch).and_raise(StandardError, "API Error")
      expect(manager.info).to eq({})
    end
  end

  describe "#members" do
    context "when workspace_members is available" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
        allow(client).to receive(:workspace_members).and_return(workspace_members)
      end

      it "returns list of members" do
        members_list = [
          { id: "member1", email: "user1@example.com", role: "admin" },
          { id: "member2", email: "user2@example.com", role: "member" },
        ]
        expect(workspace_members).to receive(:list).and_return(members_list)

        expect(manager.members).to eq(members_list)
      end
    end

    context "when workspace_members is not available" do
      before do
        allow(client).to receive(:respond_to?).with(:workspace_members).and_return(false)
      end

      it "returns nil" do
        expect(manager.members).to be_nil
      end
    end
  end

  describe "#member" do
    let(:member_id) { "member123" }

    before do
      allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
      allow(client).to receive(:workspace_members).and_return(workspace_members)
    end

    it "returns specific member details" do
      member_details = { id: member_id, email: "user@example.com", role: "admin" }
      expect(workspace_members).to receive(:get).with(member_id: member_id).and_return(member_details)

      expect(manager.member(member_id)).to eq(member_details)
    end
  end

  describe "#invite_member" do
    before do
      allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
      allow(client).to receive(:workspace_members).and_return(workspace_members)
    end

    it "invites a new member" do
      expect(workspace_members).to receive(:invite).with(email: "new@example.com", role: "member")
                                                   .and_return({ success: true, member_id: "new_member" })

      result = manager.invite_member(email: "new@example.com")
      expect(result[:success]).to be true
    end

    it "invites with custom role" do
      expect(workspace_members).to receive(:invite).with(email: "admin@example.com", role: "admin")
                                                   .and_return({ success: true, member_id: "admin_member" })

      result = manager.invite_member(email: "admin@example.com", role: "admin")
      expect(result[:success]).to be true
    end

    it "syncs with user model when provided" do
      user = double("User", attio_member_id: nil)
      allow(user).to receive(:respond_to?).with(:attio_member_id=).and_return(true)
      expect(user).to receive(:update).with(attio_member_id: "new_member")

      allow(workspace_members).to receive(:invite).and_return({ success: true, member_id: "new_member" })

      manager.invite_member(email: "user@example.com", sync_with_user: user)
    end

    it "handles errors gracefully" do
      allow(workspace_members).to receive(:invite).and_raise(StandardError, "Invite failed")

      result = manager.invite_member(email: "fail@example.com")
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Invite failed")
    end
  end

  describe "#update_member_role" do
    before do
      allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
      allow(client).to receive(:workspace_members).and_return(workspace_members)
    end

    it "updates member role" do
      expect(workspace_members).to receive(:update).with(member_id: "member123", data: { role: "admin" })
                                                   .and_return({ success: true })

      result = manager.update_member_role(member_id: "member123", role: "admin")
      expect(result[:success]).to be true
    end

    it "handles errors gracefully" do
      allow(workspace_members).to receive(:update).and_raise(StandardError, "Update failed")

      result = manager.update_member_role(member_id: "member123", role: "admin")
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Update failed")
    end
  end

  describe "#remove_member" do
    before do
      allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
      allow(client).to receive(:workspace_members).and_return(workspace_members)
    end

    it "removes a member" do
      expect(workspace_members).to receive(:remove).with(member_id: "member123")
                                                   .and_return({ success: true })

      result = manager.remove_member(member_id: "member123")
      expect(result[:success]).to be true
    end

    it "handles errors gracefully" do
      allow(workspace_members).to receive(:remove).and_raise(StandardError, "Remove failed")

      result = manager.remove_member(member_id: "member123")
      expect(result[:success]).to be false
      expect(result[:error]).to eq("Remove failed")
    end
  end

  describe "#sync_rails_users" do
    let(:users) { [] }
    let(:existing_members) do
      [
        { id: "member1", email: "existing@example.com", role: "member" },
        { id: "member2", email: "admin@example.com", role: "member" },
      ]
    end

    before do
      allow(client).to receive(:respond_to?).with(:workspace_members).and_return(true)
      allow(client).to receive(:workspace_members).and_return(workspace_members)
      allow(workspace_members).to receive(:list).and_return(existing_members)
    end

    context "with new users" do
      let(:new_user) { double("User", email: "new@example.com") }
      let(:users_collection) { double("collection") }

      before do
        allow(users_collection).to receive(:find_each).and_yield(new_user)
      end

      it "invites new users" do
        expect(workspace_members).to receive(:invite).with(email: "new@example.com", role: "member")
                                                     .and_return({ success: true, member_id: "new_member" })

        results = manager.sync_rails_users(users_collection)
        expect(results[:invited]).to include(new_user)
      end
    end

    context "with existing users needing role update" do
      let(:admin_user) { double("User", email: "admin@example.com", admin?: true) }
      let(:users_collection) { double("collection") }
      let(:role_mapping) { { admin?: "admin" } }

      before do
        allow(users_collection).to receive(:find_each).and_yield(admin_user)
      end

      it "updates roles for existing members" do
        expect(workspace_members).to receive(:update).with(member_id: "member2", data: { role: "admin" })
                                                     .and_return({ success: true })

        results = manager.sync_rails_users(users_collection, role_mapping: role_mapping)
        expect(results[:updated]).to include(admin_user)
      end
    end

    context "with role mapping" do
      let(:user) { double("User", email: "mapped@example.com", custom_role: "owner") }
      let(:users_collection) { double("collection") }
      let(:role_mapping) do
        {
          ->(u) { u.custom_role == "owner" } => "admin",
          :custom_role => "member",
        }
      end

      before do
        allow(users_collection).to receive(:find_each).and_yield(user)
      end

      it "applies proc-based role mapping" do
        expect(workspace_members).to receive(:invite).with(email: "mapped@example.com", role: "admin")
                                                     .and_return({ success: true, member_id: "mapped_member" })

        manager.sync_rails_users(users_collection, role_mapping: role_mapping)
      end
    end
  end

  describe "#usage_stats" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches usage statistics" do
        stats = { api_calls: 1000, storage: "100MB" }
        allow(meta).to receive(:usage_stats).and_return(stats)

        expect(cache).to receive(:fetch).with("attio:workspace:#{workspace_id}:usage", expires_in: 5.minutes).and_yield

        expect(manager.usage_stats).to eq(stats)
      end
    end

    it "returns empty hash on error" do
      allow(cache).to receive(:fetch).and_raise(StandardError, "Stats error")
      expect(manager.usage_stats).to eq({})
    end
  end

  describe "#rate_limits" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    it "returns rate limit information" do
      limits = { remaining: 900, limit: 1000 }
      expect(meta).to receive(:rate_limits).and_return(limits)

      expect(manager.rate_limits).to eq(limits)
    end

    it "returns empty hash on error" do
      allow(meta).to receive(:rate_limits).and_raise(StandardError)
      expect(manager.rate_limits).to eq({})
    end
  end

  describe "#health_check" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    it "returns true when API is operational" do
      allow(meta).to receive(:status).and_return({ status: "operational" })
      expect(manager.health_check).to be true
    end

    it "returns false when API is not operational" do
      allow(meta).to receive(:status).and_return({ status: "degraded" })
      expect(manager.health_check).to be false
    end

    it "returns false on error" do
      allow(meta).to receive(:status).and_raise(StandardError)
      expect(manager.health_check).to be false
    end
  end

  describe "#validate_api_key" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    it "returns true for valid API key" do
      allow(meta).to receive(:validate_key).and_return({ valid: true })
      expect(manager.validate_api_key).to be true
    end

    it "returns false for invalid API key" do
      allow(meta).to receive(:validate_key).and_return({ valid: false })
      expect(manager.validate_api_key).to be false
    end

    it "returns false on error" do
      allow(meta).to receive(:validate_key).and_raise(StandardError)
      expect(manager.validate_api_key).to be false
    end
  end

  describe "#feature_flags" do
    before do
      allow(client).to receive(:respond_to?).with(:meta).and_return(true)
      allow(client).to receive(:meta).and_return(meta)
    end

    context "with caching" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "caches feature flags" do
        features = { bulk_operations: true, advanced_search: false }
        allow(meta).to receive(:features).and_return(features)

        expect(cache).to receive(:fetch).with("attio:workspace:#{workspace_id}:features", expires_in: 1.hour).and_yield

        expect(manager.feature_flags).to eq(features)
      end
    end

    it "returns empty hash on error" do
      allow(cache).to receive(:fetch).and_raise(StandardError)
      expect(manager.feature_flags).to eq({})
    end
  end

  describe "#clear_cache" do
    context "with cache available" do
      before do
        stub_const("::Rails", double(cache: cache))
      end

      it "clears all workspace cache entries" do
        expect(cache).to receive(:delete_matched).with("attio:workspace:#{workspace_id}:*")
        manager.clear_cache
      end
    end

    context "without cache" do
      let(:manager) { described_class.new(workspace_id: workspace_id, api_key: api_key) }

      before do
        hide_const("::Rails")
      end

      it "does nothing" do
        expect { manager.clear_cache }.not_to raise_error
      end
    end
  end

  describe "error path coverage" do
    let(:client) { instance_double(Attio::Client) }
    let(:workspaces_resource) { instance_double(Attio::Resources::Workspaces) }
    let(:manager) { described_class.new }
    
    before do
      allow(Attio::Rails).to receive(:client).and_return(client)
    end
    
    context "validation errors" do
      it "handles validation failures in ensure_workspace!" do
        # Tests line 88
        allow(client).to receive(:workspaces).and_return(workspaces_resource)
        allow(workspaces_resource).to receive(:get).and_raise(Attio::Error, "Not found")
        
        expect { manager.ensure_workspace!("invalid_id") }.to raise_error(Attio::Rails::WorkspaceError)
      end
      
      it "handles validation failures in validate_member" do
        # Tests line 97
        allow(workspaces_resource).to receive(:get_member).and_raise(Attio::Error, "Member not found")
        
        expect { manager.validate_member("workspace_id", "member_id") }.to raise_error(Attio::Rails::WorkspaceError)
      end
      
      it "handles missing workspace in member validation" do
        # Tests line 115
        allow(workspaces_resource).to receive(:get_member).and_return(nil)
        
        expect(manager.validate_member("workspace_id", "member_id")).to be false
      end
    end
    
    context "access control errors" do
      it "handles permission check failures" do
        # Tests line 161
        allow(manager).to receive(:get_member).and_return(nil)
        
        expect(manager.can_access?("workspace_id", "member_id", :read)).to be false
      end
      
      it "handles errors in role determination" do
        # Tests lines 179-180
        member = { "access_level" => "unknown_level" }
        allow(manager).to receive(:get_member).and_return(member)
        
        expect(manager.send(:determine_role, member)).to eq(:viewer)
      end
      
      it "handles workspace switch errors" do
        # Tests line 200
        allow(manager).to receive(:validate_workspace).and_return(false)
        
        expect { manager.switch_to("invalid_workspace") }.to raise_error(Attio::Rails::WorkspaceError)
      end
    end
  end

  describe "additional sync_rails_users coverage" do
    let(:users_collection) { double("collection") }
    let(:user) { double("User", email: "test@example.com") }
    let(:existing_members) { { "test@example.com" => { id: "member-123", role: "member" } } }
    
    before do
      allow(users_collection).to receive(:find_each).and_yield(user)
      allow(manager).to receive(:members_by_email).and_return(existing_members)
    end
    
    it "updates existing member when role changes with custom role" do
      role_mapping = { admin?: "admin" }
      allow(user).to receive(:admin?).and_return(true)
      allow(workspace_members).to receive(:update).and_return({ success: true })
      
      results = manager.sync_rails_users(users_collection, role_mapping: role_mapping)
      
      expect(results[:updated]).to include(user)
    end
    
    it "handles update failure for existing member" do
      role_mapping = { admin?: "admin" }
      allow(user).to receive(:admin?).and_return(true)
      allow(workspace_members).to receive(:update).and_return({ success: false, error: "Update failed" })
      
      results = manager.sync_rails_users(users_collection, role_mapping: role_mapping)
      
      expect(results[:failed]).not_to be_empty
    end
  end
end