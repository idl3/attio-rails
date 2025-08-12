# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::BulkSync Integration", type: :integration do
  let(:client) { double("Attio::Client") }
  let(:bulk_resource) { double("Attio::Resources::Bulk") }
  let(:records_resource) { double("Attio::Resources::Records") }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
    allow(Attio::Rails.configuration).to receive(:bulk_batch_size).and_return(2) # Small batch for testing

    # Clear any existing records for proper test isolation
    TestModel.delete_all
    Company.delete_all if defined?(Company)
  end

  after do
    # Clean up after each test to prevent pollution
    TestModel.delete_all
    Company.delete_all if defined?(Company)
  end

  describe "BulkSync#perform with real ActiveRecord models" do
    context "with ActiveRecord relation" do
      before do
        # Create real ActiveRecord objects
        5.times do |i|
          TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com")
        end
      end

      it "processes records using find_in_batches" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people")
        results = bulk_sync.perform

        # This should execute the find_in_batches path
        expect(results[:successful]).not_to be_empty
      end

      it "handles progress callbacks" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        progress_calls = []
        progress_callback = ->(current, total, _results) { progress_calls << [current, total] }

        bulk_sync = Attio::Rails::BulkSync.new(
          TestModel.all,
          object_type: "people",
          progress_callback: progress_callback
        )

        bulk_sync.perform

        # With batch size 2 and 5 records, we should have 3 batches
        expect(progress_calls).to eq([[1, 3], [2, 3], [3, 3]])
      end

      it "processes different operations" do
        # Give records attio IDs for update/delete operations
        TestModel.all.each_with_index do |record, i|
          record.update_column(:attio_record_id, "attio-#{i}")
        end

        %i[update upsert delete].each do |operation|
          allow(client).to receive(:bulk).and_return(bulk_resource)
          allow(bulk_resource).to receive(:"#{operation}_records").and_return({ success: true })

          bulk_sync = Attio::Rails::BulkSync.new(
            TestModel.all,
            object_type: "people",
            operation: operation
          )

          results = bulk_sync.perform
          expect(results).to have_key(:successful)
        end
      end
    end

    context "with array of records" do
      let(:records) do
        TestModel.create!([
          { name: "Test 1", email: "test1@example.com" },
          { name: "Test 2", email: "test2@example.com" },
          { name: "Test 3", email: "test3@example.com" },
        ])
      end

      it "processes records using each_slice" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        # Use array instead of relation to trigger each_slice path
        bulk_sync = Attio::Rails::BulkSync.new(records.to_a, object_type: "people")
        results = bulk_sync.perform

        expect(results[:successful]).not_to be_empty
      end
    end

    context "error handling" do
      before do
        3.times do |i|
          TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com")
        end
      end

      it "handles API errors gracefully" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_raise(Attio::Error, "API Error")

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people")
        results = bulk_sync.perform

        expect(results[:failed]).not_to be_empty
      end

      it "handles partial success" do
        records = TestModel.all.to_a
        record_ids = records.map(&:id)

        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({
          success: false,
          partial_success: true,
          successful_ids: [],
          failed_ids: record_ids,
        })

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people")
        results = bulk_sync.perform

        expect(results[:failed]).not_to be_empty
        expect(results[:failed].size).to eq(records.size)
      end

      it "handles rate limit errors with retry" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        call_count = 0

        allow(bulk_resource).to receive(:create_records) do
          call_count += 1
          raise Attio::RateLimitError, "Rate limited" if call_count <= 2 # First two calls for two batches

          { success: true }
        end

        # Mock the retry_after method
        allow_any_instance_of(Attio::RateLimitError).to receive(:retry_after).and_return(0.01)
        allow_any_instance_of(Attio::Rails::BulkSync).to receive(:sleep) # Don't actually sleep in tests

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people")
        bulk_sync.perform

        # With 3 records and batch size of 2, we have 2 batches
        # Each batch retries once, so 2 initial + 2 retries = 4 calls
        expect(call_count).to eq(4)
      end
    end

    context "with transform option" do
      it "applies transform to records" do
        TestModel.create!(name: "Test", email: "test@example.com")

        allow(client).to receive(:bulk).and_return(bulk_resource)

        transform_proc = ->(record) { { custom_name: record.name.upcase } }

        expect(bulk_resource).to receive(:create_records).with(
          hash_including(records: [hash_including(custom_name: "TEST")])
        ).and_return({ success: true })

        bulk_sync = Attio::Rails::BulkSync.new(
          TestModel.all,
          object_type: "people",
          transform: transform_proc
        )

        bulk_sync.perform
      end

      it "handles transform method names" do
        TestModel.create!(name: "Test", email: "test@example.com")

        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        # TestModel has a transform_for_attio method
        bulk_sync = Attio::Rails::BulkSync.new(
          TestModel.all,
          object_type: "people",
          transform: :transform_for_attio
        )

        results = bulk_sync.perform
        expect(results[:successful]).not_to be_empty
      end
    end

    context "edge cases" do
      it "handles empty collection" do
        bulk_sync = Attio::Rails::BulkSync.new(TestModel.none, object_type: "people")
        results = bulk_sync.perform

        expect(results[:successful]).to be_empty
        expect(results[:failed]).to be_empty
      end

      it "handles nil values in records" do
        TestModel.create!(name: nil, email: "test@example.com")

        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people")
        results = bulk_sync.perform

        expect(results[:successful]).not_to be_empty
      end

      it "handles very large batch sizes" do
        10.times do |i|
          TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com")
        end

        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        bulk_sync = Attio::Rails::BulkSync.new(
          TestModel.all,
          object_type: "people",
          batch_size: 1000 # Larger than record count
        )

        results = bulk_sync.perform
        expect(results[:successful]).not_to be_empty
      end
    end
  end

  describe "BulkSync with records resource fallback" do
    context "when bulk API is not available" do
      before do
        allow(client).to receive(:respond_to?).with(:bulk).and_return(false)
        allow(client).to receive(:respond_to?).with(:records).and_return(true)
        allow(client).to receive(:records).and_return(records_resource)
      end

      it "falls back to individual record operations for create" do
        3.times { |i| TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com") }
        
        expect(records_resource).to receive(:create).exactly(3).times.and_return({ "data" => { "id" => "attio-1" } })

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people")
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(3)
      end

      it "handles partial failures in legacy create" do
        3.times { |i| TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com") }
        
        call_count = 0
        allow(records_resource).to receive(:create) do
          call_count += 1
          if call_count == 2
            raise StandardError, "API Error"
          else
            { "data" => { "id" => "attio-#{call_count}" } }
          end
        end

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people")
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(2)
        expect(results[:failed].size).to eq(1)
      end

      it "falls back for update operations" do
        3.times do |i|
          record = TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com")
          record.update_column(:attio_record_id, "attio-#{i}")
        end
        
        expect(records_resource).to receive(:update).exactly(3).times.and_return({ "data" => { "id" => "attio-updated" } })

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :update)
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(3)
      end

      it "handles failures in legacy update" do
        3.times do |i|
          record = TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com")
          record.update_column(:attio_record_id, "attio-#{i}")
        end
        
        call_count = 0
        allow(records_resource).to receive(:update) do
          call_count += 1
          if call_count == 1
            raise StandardError, "Update failed"
          else
            { "data" => { "id" => "attio-#{call_count}" } }
          end
        end

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :update)
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(2)
        expect(results[:failed].size).to eq(1)
      end

      it "falls back for upsert - creates new records" do
        3.times { |i| TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com") }
        
        allow(records_resource).to receive(:list).and_return([])
        expect(records_resource).to receive(:create).exactly(3).times.and_return({ "data" => { "id" => "attio-new" } })

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :upsert)
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(3)
      end

      it "falls back for upsert - updates existing records" do
        3.times { |i| TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com") }
        
        existing_record = { id: "attio-existing" }
        allow(records_resource).to receive(:list).and_return([existing_record])
        expect(records_resource).to receive(:update).exactly(3).times.and_return({ "data" => { "id" => "attio-updated" } })

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :upsert)
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(3)
      end

      it "handles failures in legacy upsert" do
        3.times { |i| TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com") }
        
        allow(records_resource).to receive(:list).and_raise(StandardError, "Search failed")

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :upsert)
        results = bulk_sync.perform

        expect(results[:failed].size).to eq(3)
      end

      it "falls back for delete operations" do
        3.times do |i|
          record = TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com")
          record.update_column(:attio_record_id, "attio-#{i}")
        end
        
        expect(records_resource).to receive(:delete).exactly(3).times

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :delete)
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(3)
      end

      it "skips records without attio_id in delete" do
        TestModel.create!(name: "Test 1", email: "test1@example.com", attio_record_id: "attio-1")
        TestModel.create!(name: "Test 2", email: "test2@example.com", attio_record_id: nil)
        TestModel.create!(name: "Test 3", email: "test3@example.com", attio_record_id: "attio-3")
        
        expect(records_resource).to receive(:delete).exactly(2).times

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :delete)
        results = bulk_sync.perform

        expect(results[:successful].size).to eq(2)
      end

      it "handles failures in legacy delete" do
        3.times do |i|
          record = TestModel.create!(name: "Test #{i}", email: "test#{i}@example.com")
          record.update_column(:attio_record_id, "attio-#{i}")
        end
        
        allow(records_resource).to receive(:delete).and_raise(StandardError, "Delete failed")

        bulk_sync = Attio::Rails::BulkSync.new(TestModel.all, object_type: "people", operation: :delete)
        results = bulk_sync.perform

        expect(results[:failed].size).to eq(3)
      end
    end
  end

end
