# frozen_string_literal: true

module Attio
  module Rails
    module RSpec
      # RSpec helper methods for testing Attio Rails integration
      #
      # @example Including in your specs
      #   RSpec.configure do |config|
      #     config.include Attio::Rails::RSpec::Helpers
      #   end
      #
      # @example Basic usage
      #   it 'syncs to Attio' do
      #     stub_attio_client
      #
      #     user = User.create!(email: 'test@example.com')
      #     expect(user.attio_record_id).to eq('attio-test-id')
      #   end
      #
      # @example Testing with expectations
      #   it 'sends correct attributes' do
      #     expect_attio_sync(
      #       object: 'people',
      #       attributes: { email: 'test@example.com' }
      #     ) do
      #       User.create!(email: 'test@example.com')
      #     end
      #   end
      module Helpers
        # Stub the Attio client and records API
        #
        # @return [Hash{Symbol => RSpec::Mocks::Double}] Hash with :client and :records doubles
        #
        # @example
        #   stubs = stub_attio_client
        #   allow(stubs[:records]).to receive(:create).and_return(response)
        def stub_attio_client
          client = instance_double(Attio::Client)
          records = instance_double(Attio::Resources::Records)

          allow(Attio::Rails).to receive(:client).and_return(client)
          allow(client).to receive(:records).and_return(records)

          { client: client, records: records }
        end

        # Stub Attio create operations
        #
        # @param response [Hash] Custom response to return (default: { "data" => { "id" => "attio-test-id" } })
        # @return [Hash{Symbol => RSpec::Mocks::Double}] Hash with :client and :records doubles
        #
        # @example
        #   stub_attio_create
        #   User.create!(email: 'test@example.com')
        #
        # @example With custom response
        #   stub_attio_create('data' => { 'id' => 'custom-id' })
        def stub_attio_create(response = { "data" => { "id" => "attio-test-id" } })
          stubs = stub_attio_client
          allow(stubs[:records]).to receive(:create).and_return(response)
          stubs
        end

        # Stub Attio update operations
        #
        # @param response [Hash] Custom response to return
        # @return [Hash{Symbol => RSpec::Mocks::Double}] Hash with :client and :records doubles
        #
        # @example
        #   stub_attio_update
        #   user.update!(name: 'New Name')
        def stub_attio_update(response = { "data" => { "id" => "attio-test-id" } })
          stubs = stub_attio_client
          allow(stubs[:records]).to receive(:update).and_return(response)
          stubs
        end

        # Stub Attio delete operations
        #
        # @param response [Hash] Custom response to return
        # @return [Hash{Symbol => RSpec::Mocks::Double}] Hash with :client and :records doubles
        #
        # @example
        #   stub_attio_delete
        #   user.destroy!
        def stub_attio_delete(response = { "data" => { "deleted" => true } })
          stubs = stub_attio_client
          allow(stubs[:records]).to receive(:delete).and_return(response)
          stubs
        end

        # Expect a sync to Attio with specific parameters
        #
        # @param object [String] Expected Attio object type
        # @param attributes [Hash, nil] Expected attributes (nil to match any)
        # @yield Block to execute that should trigger the sync
        # @return [Hash{Symbol => RSpec::Mocks::Double}] Hash with :client and :records doubles
        #
        # @example
        #   expect_attio_sync(object: 'people', attributes: { email: 'test@example.com' }) do
        #     User.create!(email: 'test@example.com')
        #   end
        def expect_attio_sync(object:, attributes: nil)
          stubs = stub_attio_client

          if attributes
            expect(stubs[:records]).to receive(:create).with(
              object: object,
              data: { values: attributes }
            ).and_return({ "data" => { "id" => "attio-test-id" } })
          else
            expect(stubs[:records]).to receive(:create).with(
              hash_including(object: object)
            ).and_return({ "data" => { "id" => "attio-test-id" } })
          end

          yield if block_given?

          stubs
        end

        # Expect no sync to Attio
        #
        # @yield Block to execute that should not trigger any sync
        # @return [Hash{Symbol => RSpec::Mocks::Double}] Hash with :client and :records doubles
        #
        # @example
        #   expect_no_attio_sync do
        #     with_attio_sync_disabled do
        #       User.create!(email: 'test@example.com')
        #     end
        #   end
        def expect_no_attio_sync
          stubs = stub_attio_client

          expect(stubs[:records]).not_to receive(:create)
          expect(stubs[:records]).not_to receive(:update)

          yield if block_given?

          stubs
        end

        # Temporarily disable Attio syncing
        #
        # @yield Block to execute with syncing disabled
        #
        # @example
        #   with_attio_sync_disabled do
        #     User.create!(email: 'test@example.com') # Won't sync
        #   end
        def with_attio_sync_disabled
          original_value = Attio::Rails.configuration.sync_enabled
          Attio::Rails.configure { |c| c.sync_enabled = false }

          yield
        ensure
          Attio::Rails.configure { |c| c.sync_enabled = original_value }
        end

        # Temporarily enable background sync
        #
        # @yield Block to execute with background sync enabled
        #
        # @example
        #   with_attio_background_sync do
        #     User.create!(email: 'test@example.com') # Will sync in background
        #   end
        #   expect(attio_sync_jobs.size).to eq(1)
        def with_attio_background_sync
          original_value = Attio::Rails.configuration.background_sync
          Attio::Rails.configure { |c| c.background_sync = true }

          yield
        ensure
          Attio::Rails.configure { |c| c.background_sync = original_value }
        end

        # Get all enqueued AttioSyncJob jobs
        #
        # @return [Array<Hash>] Array of enqueued job hashes
        #
        # @example
        #   User.create!(email: 'test@example.com')
        #   expect(attio_sync_jobs.size).to eq(1)
        #   expect(attio_sync_jobs.first[:args]).to include('model_name' => 'User')
        def attio_sync_jobs
          ActiveJob::Base.queue_adapter.enqueued_jobs.select do |job|
            job[:job] == AttioSyncJob
          end
        end

        # Clear all enqueued AttioSyncJob jobs
        #
        # @return [Array<Hash>] The deleted jobs
        #
        # @example
        #   clear_attio_sync_jobs
        #   expect(attio_sync_jobs).to be_empty
        def clear_attio_sync_jobs
          ActiveJob::Base.queue_adapter.enqueued_jobs.delete_if do |job|
            [AttioSyncJob, Attio::Rails::Jobs::AttioSyncJob].include?(job[:job])
          end
        end
      end
    end
  end
end
