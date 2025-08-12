# frozen_string_literal: true

require "spec_helper"

RSpec.describe Attio::Rails::BulkSync do
  let(:records) { create_list(:user, 5) }
  let(:object_type) { "people" }
  let(:bulk_sync) { described_class.new(records, object_type: object_type) }
  let(:client) { instance_double(Attio::Client) }
  let(:bulk_resource) { instance_double(Attio::Resources::Bulk) }
  let(:records_resource) { instance_double(Attio::Resources::Records) }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(Attio::Rails).to receive(:logger).and_return(Logger.new(nil))
  end

  def create_list(_model, count, with_attio_id: false)
    Array.new(count) do |i|
      id = i + 1
      attio_id = with_attio_id ? "attio-#{id}" : nil
      double("User", id: id, email: "user#{id}@example.com",
                     attributes: { email: "user#{id}@example.com" },
                     attio_id: attio_id)
    end
  end

  describe "#perform" do
    context "with empty records" do
      let(:records) { [] }

      it "returns early with empty results" do
        results = bulk_sync.perform
        expect(results[:successful]).to be_empty
        expect(results[:failed]).to be_empty
        expect(results[:partial]).to be_empty
      end
    end

    context "with create operation" do
      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
      end

      it "creates records in batches" do
        response = { success: true }
        expect(bulk_resource).to receive(:create_records).with(
          object: object_type,
          records: records.map(&:attributes),
          options: { partial_success: true }
        ).and_return(response)

        results = bulk_sync.perform
        expect(results[:successful]).to eq(records)
      end

      it "handles partial success" do
        response = {
          partial_success: true,
          successful_ids: [1, 2],
          failed_ids: [3, 4, 5],
          errors: { 3 => "Invalid email" },
        }
        allow(bulk_resource).to receive(:create_records).and_return(response)

        results = bulk_sync.perform
        expect(results[:successful].size).to eq(2)
        expect(results[:failed].size).to eq(3)
      end

      it "uses custom batch size" do
        bulk_sync = described_class.new(records, object_type: object_type, batch_size: 2)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        bulk_sync.perform
        # With 5 records and batch size 2, we expect 3 batches (2+2+1)
        expect(bulk_resource).to have_received(:create_records).exactly(3).times
      end

      it "calls progress callback" do
        progress_callback = double("callback")
        bulk_sync = described_class.new(records, object_type: object_type, progress_callback: progress_callback)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })

        expect(progress_callback).to receive(:call).with(1, 1, hash_including(:successful))
        bulk_sync.perform
      end
    end

    context "with update operation" do
      let(:records) { create_list(:user, 3, with_attio_id: true) }

      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
      end

      it "updates records with their attio_id" do
        updates = records.map { |r| { id: r.attio_id, data: r.attributes } }
        expect(bulk_resource).to receive(:update_records).with(
          object: object_type,
          updates: updates,
          options: { partial_success: true }
        ).and_return({ success: true })

        bulk_sync = described_class.new(records, object_type: object_type, operation: :update)
        results = bulk_sync.perform
        expect(results[:successful]).to eq(records)
      end
    end

    context "with upsert operation" do
      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
      end

      it "upserts records with match attribute" do
        expect(bulk_resource).to receive(:upsert_records).with(
          object: object_type,
          records: records.map(&:attributes),
          match_attribute: :email,
          options: { partial_success: true }
        ).and_return({ success: true })

        bulk_sync = described_class.new(records, object_type: object_type, operation: :upsert)
        results = bulk_sync.perform
        expect(results[:successful]).to eq(records)
      end

      it "uses custom match attribute" do
        expect(bulk_resource).to receive(:upsert_records).with(
          object: object_type,
          records: records.map(&:attributes),
          match_attribute: :external_id,
          options: { partial_success: true }
        ).and_return({ success: true })

        bulk_sync = described_class.new(records, object_type: object_type, operation: :upsert,
                                                 match_attribute: :external_id)
        bulk_sync.perform
      end
    end

    context "with delete operation" do
      let(:records) { create_list(:user, 3, with_attio_id: true) }

      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
      end

      it "deletes records by their attio_id" do
        ids = records.map(&:attio_id)
        expect(bulk_resource).to receive(:delete_records).with(
          object: object_type,
          ids: ids
        ).and_return({ success: true })

        bulk_sync = described_class.new(records, object_type: object_type, operation: :delete)
        results = bulk_sync.perform
        expect(results[:successful]).to eq(records)
      end

      it "skips records without attio_id" do
        allow(records.last).to receive(:attio_id).and_return(nil)
        ids = records[0..1].map(&:attio_id)

        expect(bulk_resource).to receive(:delete_records).with(
          object: object_type,
          ids: ids
        ).and_return({ success: true })

        bulk_sync = described_class.new(records, object_type: object_type, operation: :delete)
        bulk_sync.perform
      end
    end

    context "with transform option" do
      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
      end

      it "applies proc transform" do
        transform = ->(record) { { full_name: record.email.split("@").first } }
        transformed_data = records.map { |r| { full_name: r.email.split("@").first } }

        expect(bulk_resource).to receive(:create_records).with(
          object: object_type,
          records: transformed_data,
          options: { partial_success: true }
        ).and_return({ success: true })

        bulk_sync = described_class.new(records, object_type: object_type, transform: transform)
        bulk_sync.perform
      end

      it "calls transform method on record" do
        records.each do |record|
          allow(record).to receive(:to_attio).and_return({ custom: "data" })
        end

        expect(bulk_resource).to receive(:create_records).with(
          object: object_type,
          records: Array.new(5) { { custom: "data" } },
          options: { partial_success: true }
        ).and_return({ success: true })

        bulk_sync = described_class.new(records, object_type: object_type)
        bulk_sync.perform
      end
    end

    context "error handling" do
      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
      end

      it "handles rate limit errors" do
        error = Attio::RateLimitError.new("Rate limit exceeded")
        allow(error).to receive(:retry_after).and_return(60)

        call_count = 0
        allow(bulk_resource).to receive(:create_records) do
          call_count += 1
          raise error if call_count == 1

          { success: true }
        end

        bulk_sync = described_class.new(records, object_type: object_type, async: false)
        expect(bulk_sync).to receive(:sleep).with(60)

        bulk_sync.perform
      end

      it "handles general errors" do
        error = StandardError.new("API Error")
        allow(bulk_resource).to receive(:create_records).and_raise(error)

        results = bulk_sync.perform
        expect(results[:failed].size).to eq(5)
        results[:failed].each do |failure|
          expect(failure[:error]).to eq("API Error")
        end
      end

      it "calls error callback when provided" do
        error = StandardError.new("API Error")
        error_handler = double("error_handler")
        allow(bulk_resource).to receive(:create_records).and_raise(error)

        expect(error_handler).to receive(:call).with(error, records)

        bulk_sync = described_class.new(records, object_type: object_type, on_error: error_handler)
        bulk_sync.perform
      end
    end

    context "with legacy client (no bulk resource)" do
      before do
        allow(client).to receive(:bulk).and_return(nil)
        allow(client).to receive(:respond_to?).with(:bulk).and_return(false)
        allow(client).to receive(:records).and_return(records_resource)
      end

      it "falls back to individual create operations" do
        records.each do |record|
          expect(records_resource).to receive(:create).with(
            object: object_type,
            data: record.attributes
          )
        end

        results = bulk_sync.perform
        expect(results[:successful]).to eq(records)
      end

      it "handles mixed success/failure in legacy mode" do
        records.each_with_index do |record, index|
          if index < 3
            expect(records_resource).to receive(:create).with(
              object: object_type,
              data: record.attributes
            )
          else
            expect(records_resource).to receive(:create).with(
              object: object_type,
              data: record.attributes
            ).and_raise(StandardError, "Failed")
          end
        end

        results = bulk_sync.perform
        expect(results[:successful].size).to eq(3)
        expect(results[:failed].size).to eq(2)
      end
    end

    context "with on_complete callback" do
      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })
      end

      it "calls completion callback with results" do
        callback = double("callback")
        expect(callback).to receive(:call).with(hash_including(:successful, :failed, :partial))

        bulk_sync = described_class.new(records, object_type: object_type, on_complete: callback)
        bulk_sync.perform
      end
    end
  end

  describe ".perform" do
    it "creates instance and calls perform" do
      instance = instance_double(described_class)
      expect(described_class).to receive(:new).with(records, object_type: object_type).and_return(instance)
      expect(instance).to receive(:perform)

      described_class.perform(records, object_type: object_type)
    end
  end

  describe "legacy API fallback" do
    let(:records) { create_list(:user, 3) }
    
    before do
      allow(client).to receive(:respond_to?).with(:bulk).and_return(false)
      allow(client).to receive(:records).and_return(records_resource)
    end

    context "legacy_bulk_create" do
      it "creates records individually when bulk API is not available" do
        expect(records_resource).to receive(:create).exactly(3).times.and_return({ id: "attio-1" })
        
        bulk_sync = described_class.new(records, object_type: object_type)
        results = bulk_sync.perform
        
        expect(results[:successful]).to eq(records)
      end

      it "handles partial failures in legacy create" do
        call_count = 0
        allow(records_resource).to receive(:create) do
          call_count += 1
          if call_count == 2
            raise StandardError, "API Error"
          else
            { id: "attio-#{call_count}" }
          end
        end
        
        bulk_sync = described_class.new(records, object_type: object_type)
        results = bulk_sync.perform
        
        expect(results[:successful].size).to eq(2)
        expect(results[:failed].size).to eq(1)
      end
    end

    context "legacy_bulk_update" do
      let(:records) { create_list(:user, 3, with_attio_id: true) }
      
      it "updates records individually" do
        expect(records_resource).to receive(:update).exactly(3).times.and_return({ id: "attio-1" })
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :update)
        results = bulk_sync.perform
        
        expect(results[:successful]).to eq(records)
      end

      it "handles failures in legacy update" do
        call_count = 0
        allow(records_resource).to receive(:update) do
          call_count += 1
          if call_count == 1
            raise StandardError, "Update failed"
          else
            { id: "attio-#{call_count}" }
          end
        end
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :update)
        results = bulk_sync.perform
        
        expect(results[:successful].size).to eq(2)
        expect(results[:failed].size).to eq(1)
      end
    end

    context "legacy_bulk_upsert" do
      it "creates new records when not found" do
        allow(records_resource).to receive(:list).and_return([])
        expect(records_resource).to receive(:create).exactly(3).times.and_return({ id: "attio-new" })
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :upsert)
        results = bulk_sync.perform
        
        expect(results[:successful]).to eq(records)
      end

      it "updates existing records when found" do
        existing_record = { id: "attio-existing" }
        allow(records_resource).to receive(:list).and_return([existing_record])
        expect(records_resource).to receive(:update).exactly(3).times.and_return({ id: "attio-updated" })
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :upsert)
        results = bulk_sync.perform
        
        expect(results[:successful]).to eq(records)
      end

      it "handles failures in legacy upsert" do
        allow(records_resource).to receive(:list).and_raise(StandardError, "Search failed")
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :upsert)
        results = bulk_sync.perform
        
        expect(results[:failed].size).to eq(3)
      end
    end

    context "legacy_bulk_delete" do
      let(:records) { create_list(:user, 3, with_attio_id: true) }
      
      it "deletes records with attio_id" do
        expect(records_resource).to receive(:delete).exactly(3).times
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :delete)
        results = bulk_sync.perform
        
        expect(results[:successful]).to eq(records)
      end

      it "skips records without attio_id" do
        records[1] = double("User", id: 2, attio_id: nil)
        
        expect(records_resource).to receive(:delete).exactly(2).times
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :delete)
        results = bulk_sync.perform
        
        expect(results[:successful].size).to eq(2)
      end

      it "handles failures in legacy delete" do
        allow(records_resource).to receive(:delete).and_raise(StandardError, "Delete failed")
        
        bulk_sync = described_class.new(records, object_type: object_type, operation: :delete)
        results = bulk_sync.perform
        
        expect(results[:failed].size).to eq(3)
      end
    end
  end

  describe "edge cases and error handling" do
    context "with unknown operation" do
      it "raises ArgumentError" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        
        expect {
          described_class.new(records, object_type: object_type, operation: :invalid).perform
        }.to raise_error(ArgumentError, "Unknown operation: invalid")
      end
    end

    context "with async job scheduling" do
      let(:rate_limit_error) { Attio::RateLimitError.new("Rate limited") }
      
      before do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_raise(rate_limit_error)
        allow(rate_limit_error).to receive(:retry_after).and_return(60)
        stub_const("AttioSyncJob", Class.new)
        allow(AttioSyncJob).to receive(:set).and_return(AttioSyncJob)
        allow(AttioSyncJob).to receive(:perform_later)
      end

      it "schedules async jobs when rate limited with async option" do
        expect(AttioSyncJob).to receive(:set).with(wait: 60.seconds).and_return(AttioSyncJob)
        expect(AttioSyncJob).to receive(:perform_later).exactly(5).times
        
        bulk_sync = described_class.new(records, object_type: object_type, async: true)
        results = bulk_sync.perform
        
        expect(results[:partial]).to eq(records)
      end
    end

    context "with on_complete callback" do
      it "calls the callback with results" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })
        
        callback_results = nil
        on_complete = ->(results) { callback_results = results }
        
        bulk_sync = described_class.new(records, object_type: object_type, on_complete: on_complete)
        bulk_sync.perform
        
        expect(callback_results[:successful]).to eq(records)
      end
    end

    context "with raise_on_failure option" do
      it "raises error when all records fail" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ 
          success: false,
          error: "All failed"
        })
        
        bulk_sync = described_class.new(records, object_type: object_type, raise_on_failure: true)
        
        expect { bulk_sync.perform }.to raise_error(Attio::Rails::BulkSyncError, "All records failed to sync")
      end
    end

    context "with transform as method symbol" do
      it "calls the transform method on records" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })
        
        records.each do |record|
          expect(record).to receive(:custom_transform).and_return({ transformed: true })
        end
        
        bulk_sync = described_class.new(records, object_type: object_type, transform: :custom_transform)
        bulk_sync.perform
      end
    end

    context "with records responding to to_attio" do
      it "uses to_attio method" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_return({ success: true })
        
        records.each do |record|
          allow(record).to receive(:respond_to?).with(:to_attio).and_return(true)
          expect(record).to receive(:to_attio).and_return({ attio_format: true })
        end
        
        bulk_sync = described_class.new(records, object_type: object_type)
        bulk_sync.perform
      end
    end

    context "with on_error callback" do
      it "calls error callback on batch failure" do
        allow(client).to receive(:bulk).and_return(bulk_resource)
        allow(bulk_resource).to receive(:create_records).and_raise(StandardError, "Batch error")
        
        error_called = false
        on_error = ->(_error, _batch) { error_called = true }
        
        bulk_sync = described_class.new(records, object_type: object_type, on_error: on_error)
        bulk_sync.perform
        
        expect(error_called).to be true
      end
    end
  end
end
