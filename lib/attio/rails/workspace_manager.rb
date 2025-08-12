# frozen_string_literal: true

module Attio
  module Rails
    class WorkspaceManager
      attr_reader :client, :workspace_id

      def initialize(workspace_id: nil, api_key: nil)
        @workspace_id = workspace_id || Attio::Rails.configuration.default_workspace_id
        @api_key = api_key || Attio::Rails.configuration.api_key
        @client = Attio::Rails.client
        @cache = ::Rails.cache if defined?(::Rails.cache)
        @logger = Attio::Rails.logger
      end

      def info
        cache_key = "attio:workspace:#{@workspace_id}:info"

        if @cache
          @cache.fetch(cache_key, expires_in: 1.hour) do
            fetch_workspace_info
          end
        else
          fetch_workspace_info
        end
      rescue StandardError => e
        @logger.error("Failed to fetch workspace info: #{e.message}")
        {}
      end

      def members
        @client.workspace_members.list if @client.respond_to?(:workspace_members)
      end

      def member(member_id)
        @client.workspace_members.get(member_id: member_id) if @client.respond_to?(:workspace_members)
      end

      def invite_member(email:, role: "member", sync_with_user: nil)
        return { success: false, error: "Client doesn't support workspace members" } unless @client.respond_to?(:workspace_members)

        api_result = @client.workspace_members.invite(email: email, role: role)
        result = { success: true, member_id: api_result["id"], data: api_result }

        if sync_with_user && result[:success] && sync_with_user.respond_to?(:attio_member_id=)
          sync_with_user.update(attio_member_id: result[:member_id])
        end

        result
      rescue StandardError => e
        @logger.error("Failed to invite member: #{e.message}")
        { success: false, error: e.message }
      end

      def update_member_role(member_id:, role:)
        return { success: false, error: "Client doesn't support workspace members" } unless @client.respond_to?(:workspace_members)

        result = @client.workspace_members.update(member_id: member_id, data: { role: role })
        { success: true, data: result }
      rescue StandardError => e
        @logger.error("Failed to update member role: #{e.message}")
        { success: false, error: e.message }
      end

      def remove_member(member_id:)
        return unless @client.respond_to?(:workspace_members)

        @client.workspace_members.remove(member_id: member_id)
      rescue StandardError => e
        @logger.error("Failed to remove member: #{e.message}")
        { success: false, error: e.message }
      end

      def sync_rails_users(users, role_mapping: {})
        results = { invited: [], updated: [], failed: [] }
        existing_members = members_by_email

        users.find_each do |user|
          email = user.email
          role = determine_user_role(user, role_mapping)

          if existing_members[email]
            # Update existing member if role changed
            existing_role = existing_members[email][:role]
            if existing_role != role
              result = update_member_role(member_id: existing_members[email][:id], role: role)
              if result[:success]
                results[:updated] << user
              else
                results[:failed] << { user: user, error: result[:error] }
              end
            end
          else
            # Invite new member
            result = invite_member(email: email, role: role, sync_with_user: user)
            if result[:success]
              results[:invited] << user
            else
              results[:failed] << { user: user, error: result[:error] }
            end
          end
        end

        results
      end

      def usage_stats
        return {} unless @client.respond_to?(:meta)

        cache_key = "attio:workspace:#{@workspace_id}:usage"

        if @cache
          @cache.fetch(cache_key, expires_in: 5.minutes) do
            @client.meta.usage_stats
          end
        else
          @client.meta.usage_stats
        end
      rescue StandardError => e
        @logger.error("Failed to fetch usage stats: #{e.message}")
        {}
      end

      def rate_limits
        return {} unless @client.respond_to?(:meta)

        @client.meta.rate_limits
      rescue StandardError => e
        @logger.error("Failed to fetch rate limits: #{e.message}")
        {}
      end

      def health_check
        return false unless @client.respond_to?(:meta)

        response = @client.meta.status
        response[:status] == "operational"
      rescue StandardError => e
        @logger.error("Health check failed: #{e.message}")
        false
      end

      def validate_api_key
        return false unless @client.respond_to?(:meta)

        response = @client.meta.validate_key
        response[:valid] == true
      rescue StandardError => e
        @logger.error("API key validation failed: #{e.message}")
        false
      end

      def feature_flags
        return {} unless @client.respond_to?(:meta)

        cache_key = "attio:workspace:#{@workspace_id}:features"

        if @cache
          @cache.fetch(cache_key, expires_in: 1.hour) do
            @client.meta.features
          end
        else
          @client.meta.features
        end
      rescue StandardError => e
        @logger.error("Failed to fetch feature flags: #{e.message}")
        {}
      end

      def clear_cache
        return unless @cache

        @cache.delete_matched("attio:workspace:#{@workspace_id}:*")
      end

      private def fetch_workspace_info
        return {} unless @client.respond_to?(:meta)

        @client.meta.identify
      rescue StandardError => e
        @logger.error("Failed to fetch workspace info: #{e.message}")
        {}
      end

      private def members_by_email
        return {} unless @client.respond_to?(:workspace_members)

        members_list = members || []
        members_list.each_with_object({}) do |member, hash|
          hash[member[:email]] = { id: member[:id], role: member[:role] }
        end
      end

      private def determine_user_role(user, role_mapping)
        role_mapping.each do |condition, role|
          case condition
          when Symbol
            return role if user.send(condition)
          when Proc
            return role if condition.call(user)
          when String
            return role if user.respond_to?(condition) && user.send(condition)
          end
        end

        "member" # default role
      end

      def ensure_workspace!(workspace_id)
        validate_workspace(workspace_id) || raise(WorkspaceError, "Invalid workspace: #{workspace_id}")
      end

      def validate_workspace(workspace_id)
        return false unless workspace_id
        
        @client.workspaces.get(workspace_id: workspace_id) if @client.respond_to?(:workspaces)
        true
      rescue StandardError => e
        @logger.error("Failed to validate workspace: #{e.message}")
        false
      end

      def validate_member(workspace_id, member_id)
        return false unless workspace_id && member_id
        
        @client.workspace_members.get_member(workspace_id: workspace_id, member_id: member_id) if @client.respond_to?(:workspace_members)
        true
      rescue StandardError => e
        @logger.error("Failed to validate member: #{e.message}")
        raise WorkspaceError, "Member validation failed: #{e.message}"
      end

      def can_access?(workspace_id, member_id, permission)
        member = get_member(member_id)
        return false unless member

        role = determine_role(member)
        has_permission?(role, permission)
      end

      def get_member(member_id)
        @client.workspace_members.get(member_id: member_id) if @client.respond_to?(:workspace_members)
      rescue StandardError
        nil
      end

      def switch_to(workspace_id)
        validate_workspace(workspace_id) || raise(WorkspaceError, "Cannot switch to invalid workspace")
        @workspace_id = workspace_id
      end

      private def determine_role(member)
        return :viewer unless member
        
        case member["access_level"]
        when "admin"
          :admin
        when "member"
          :member
        else
          :viewer
        end
      end

      private def has_permission?(role, permission)
        permissions = {
          admin: [:read, :write, :delete, :manage],
          member: [:read, :write],
          viewer: [:read]
        }
        
        permissions[role]&.include?(permission) || false
      end

    end

    class WorkspaceError < StandardError; end
  end
end
