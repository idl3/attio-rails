# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Attio::Rails::Concerns::Syncable enhanced features" do
  before do
    Attio::Rails.configuration = nil
    Attio::Rails.configure { |c| c.api_key = "test_key" }
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  let(:model_class) do
    TestModel.tap do |klass|
      klass.syncs_with_attio("contacts", {
        email: :email,
        name: :name,
      })
    end
  end

  let(:model) { model_class.create!(name: "John Doe", email: "john@example.com") }
  let(:client) { double("Attio::Client") }
  let(:records_resource) { double("Attio::Resources::Records") }

  before do
    allow(Attio::Rails).to receive(:client).and_return(client)
    allow(client).to receive(:records).and_return(records_resource)
  end

  describe "callbacks" do
    context "with before_sync callback" do
      it "runs proc callback before sync" do
        callback_run = false
        model_class.syncs_with_attio("contacts", { email: :email }, {
          before_sync: -> { callback_run = true },
        })

        allow(records_resource).to receive(:create).and_return({ "data" => { "id" => "attio_123" } })
        model.sync_to_attio_now

        expect(callback_run).to be true
      end

      it "runs method callback before sync" do
        model_class.syncs_with_attio("contacts", { email: :email }, {
          before_sync: :prepare_for_sync,
        })

        expect(model).to receive(:prepare_for_sync)
        allow(records_resource).to receive(:create).and_return({ "data" => { "id" => "attio_123" } })
        model.sync_to_attio_now
      end

      it "uses before_attio_sync class method" do
        callback_run = false
        model_class.before_attio_sync { callback_run = true }

        allow(records_resource).to receive(:create).and_return({ "data" => { "id" => "attio_123" } })
        model.sync_to_attio_now

        expect(callback_run).to be true
      end
    end

    context "with after_sync callback" do
      it "runs proc callback after sync with result" do
        callback_result = nil
        model_class.syncs_with_attio("contacts", { email: :email }, {
          after_sync: ->(result) { callback_result = result },
        })

        response = { "data" => { "id" => "attio_123" } }
        allow(records_resource).to receive(:create).and_return(response)
        model.sync_to_attio_now

        expect(callback_result).to eq(response)
      end

      it "runs method callback after sync" do
        model_class.syncs_with_attio("contacts", { email: :email }, {
          after_sync: :handle_sync_result,
        })

        response = { "data" => { "id" => "attio_123" } }
        allow(records_resource).to receive(:create).and_return(response)
        expect(model).to receive(:handle_sync_result).with(response)
        model.sync_to_attio_now
      end

      it "uses after_attio_sync class method" do
        callback_result = nil
        model_class.after_attio_sync { |result| callback_result = result }

        response = { "data" => { "id" => "attio_123" } }
        allow(records_resource).to receive(:create).and_return(response)
        model.sync_to_attio_now

        expect(callback_result).to eq(response)
      end
    end
  end

  describe "transforms" do
    it "applies proc transform to attributes" do
      model_class.syncs_with_attio("contacts", { email: :email }, {
        transform: ->(attrs, _model) { attrs.merge(custom: "value") },
      })

      expect(records_resource).to receive(:create).with(
        object: "contacts",
        data: { values: hash_including(email: "john@example.com", custom: "value") }
      ).and_return({ "data" => { "id" => "attio_123" } })

      model.sync_to_attio_now
    end

    it "calls transform method on model" do
      model_class.syncs_with_attio("contacts", { email: :email }, {
        transform: :transform_for_attio,
      })

      expect(model).to receive(:transform_for_attio).with(hash_including(email: "john@example.com")).and_return({ transformed: true })
      expect(records_resource).to receive(:create).with(
        object: "contacts",
        data: { values: { transformed: true } }
      ).and_return({ "data" => { "id" => "attio_123" } })

      model.sync_to_attio_now
    end
  end

  describe "error handling" do
    it "uses custom error handler" do
      error_handled = false
      error_received = nil
      model_class.syncs_with_attio("contacts", { email: :email }, {
        on_error: lambda { |e|
          error_handled = true
          error_received = e
        },
      })

      error = StandardError.new("API Error")
      allow(records_resource).to receive(:create).and_raise(error)

      model.sync_to_attio_now
      expect(error_handled).to be true
      expect(error_received).to eq(error)
    end

    it "calls error handler method" do
      model_class.syncs_with_attio("contacts", { email: :email }, {
        on_error: :handle_attio_error,
      })

      error = StandardError.new("API Error")
      allow(records_resource).to receive(:create).and_raise(error)
      expect(model).to receive(:handle_attio_error).with(error)

      model.sync_to_attio_now
    end
  end

  describe "bulk sync operations" do
    let(:models) { 3.times.map { |i| model_class.create!(name: "User #{i}", email: "user#{i}@example.com") } }

    describe ".bulk_sync_with_attio" do
      it "configures bulk sync options" do
        model_class.bulk_sync_with_attio(batch_size: 50, async: false)
        expect(model_class.attio_bulk_sync_options).to eq({ batch_size: 50, async: false })
      end
    end

    describe ".bulk_sync_to_attio" do
      it "performs bulk sync for all records" do
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          kind_of(ActiveRecord::Relation),
          object_type: "contacts",
          custom: "option"
        )

        model_class.bulk_sync_to_attio(custom: "option")
      end

      it "performs bulk sync for specific records" do
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          models,
          object_type: "contacts"
        )

        model_class.bulk_sync_to_attio(models)
      end

      it "merges class-level bulk sync options" do
        model_class.bulk_sync_with_attio(batch_size: 50)

        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          kind_of(ActiveRecord::Relation),
          object_type: "contacts",
          batch_size: 50,
          async: true
        )

        model_class.bulk_sync_to_attio(async: true)
      end
    end

    describe ".bulk_upsert_to_attio" do
      it "performs bulk upsert" do
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          kind_of(ActiveRecord::Relation),
          object_type: "contacts",
          operation: :upsert
        )

        model_class.bulk_upsert_to_attio
      end

      it "allows custom match attribute" do
        expect(Attio::Rails::BulkSync).to receive(:perform).with(
          models,
          object_type: "contacts",
          operation: :upsert,
          match_attribute: :external_id
        )

        model_class.bulk_upsert_to_attio(models, match_attribute: :external_id)
      end
    end
  end

  describe "#to_attio" do
    it "returns transformed attributes" do
      model_class.syncs_with_attio("contacts", { email: :email, name: :name })

      expect(model.to_attio).to eq({
        email: "john@example.com",
        name: "John Doe",
      })
    end

    it "applies transform when configured" do
      model_class.syncs_with_attio("contacts", { email: :email }, {
        transform: ->(attrs, _) { attrs.merge(source: "rails") },
      })

      expect(model.to_attio).to eq({
        email: "john@example.com",
        source: "rails",
      })
    end
  end

  describe "enhanced sync flow" do
    it "executes full sync flow with all features" do
      before_sync_run = false
      after_sync_result = nil
      transformed_attrs = nil

      model_class.syncs_with_attio("contacts", { email: :email }, {
        before_sync: -> { before_sync_run = true },
        after_sync: ->(result) { after_sync_result = result },
        transform: lambda { |attrs, _|
          transformed_attrs = attrs
          attrs.merge(synced_at: Time.current.iso8601)
        },
      })

      response = { "data" => { "id" => "full_flow_id" } }
      allow(records_resource).to receive(:create).and_return(response)

      model.sync_to_attio_now

      expect(before_sync_run).to be true
      expect(after_sync_result).to eq(response)
      expect(transformed_attrs).to include(email: "john@example.com")
    end

    it "handles errors in callback chain" do
      error_message = nil
      model_class.syncs_with_attio("contacts", { email: :email }, {
        before_sync: -> { raise "Before sync error" },
        on_error: ->(e) { error_message = e.message },
      })

      model.sync_to_attio

      expect(error_message).to eq("Before sync error")
    end
  end
end
