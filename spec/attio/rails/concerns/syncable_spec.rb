# frozen_string_literal: true

RSpec.describe Attio::Rails::Concerns::Syncable do
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
        full_name: ->(m) { "#{m.name} (Test)" },
      })
    end
  end

  let(:model) { model_class.create!(name: "John Doe", email: "john@example.com") }

  describe ".syncs_with_attio" do
    it "sets the attio_object_type" do
      expect(model_class.attio_object_type).to eq("contacts")
    end

    it "sets the attio_attribute_mapping" do
      mapping = model_class.attio_attribute_mapping
      expect(mapping[:email]).to eq(:email)
      expect(mapping[:name]).to eq(:name)
      expect(mapping[:full_name]).to be_a(Proc)
    end

    context "with options" do
      before do
        model_class.syncs_with_attio("users", { name: :name }, {
          if: :active?,
          identifier: :email,
        })
      end

      it "sets sync conditions" do
        expect(model_class.attio_sync_conditions).to eq(:active?)
      end

      it "sets identifier attribute" do
        expect(model_class.attio_identifier_attribute).to eq(:email)
      end
    end
  end

  describe ".skip_attio_sync" do
    it "skips callbacks" do
      expect(model_class).to receive(:skip_callback).with(:commit, :after, :sync_to_attio)
      expect(model_class).to receive(:skip_callback).with(:commit, :after, :remove_from_attio)
      model_class.skip_attio_sync
    end
  end

  describe "#sync_to_attio" do
    context "with background sync enabled" do
      before { Attio::Rails.configure { |c| c.background_sync = true } }

      it "enqueues a sync job on create" do
        expect do
          model_class.create!(name: "Jane", email: "jane@example.com")
        end.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(1)

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(job[:job]).to eq(AttioSyncJob)

        # ActiveJob serializes arguments, so we need to check the serialized format
        args = job[:args].first
        expect(args["model_name"]).to eq("TestModel")
        expect(args["action"]["value"]).to eq("sync")
      end

      it "enqueues a sync job on update" do
        model # create first
        ActiveJob::Base.queue_adapter.enqueued_jobs.clear

        expect do
          model.update!(name: "John Updated")
        end.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(1)

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(job[:job]).to eq(AttioSyncJob)
        args = job[:args].first
        expect(args["model_name"]).to eq("TestModel")
        expect(args["action"]["value"]).to eq("sync")
      end
    end

    context "with background sync disabled" do
      let(:client) { instance_double(Attio::Client) }
      let(:records) { instance_double(Attio::Resources::Records) }

      before do
        Attio::Rails.configure { |c| c.background_sync = false }
        allow(Attio::Rails).to receive(:client).and_return(client)
        allow(client).to receive(:records).and_return(records)
      end

      it "syncs immediately on create" do
        expect(records).to receive(:create).with(
          object: "contacts",
          data: { values: {
            email: "new@example.com",
            name: "New User",
            full_name: "New User (Test)",
          } }
        ).and_return({ "data" => { "id" => "attio123" } })

        model_class.create!(name: "New User", email: "new@example.com")
      end

      it "updates existing record when attio_record_id is present" do
        # Allow initial creation
        allow(records).to receive(:create).and_return({ "data" => { "id" => "new123" } })

        # Create model and set attio_record_id
        test_model = model_class.create!(name: "John Doe", email: "john@example.com")
        test_model.update_column(:attio_record_id, "existing123")

        # Expect update call
        expect(records).to receive(:update).with(
          object: "contacts",
          id: "existing123",
          data: { values: {
            email: "john@example.com",
            name: "Updated Name",
            full_name: "Updated Name (Test)",
          } }
        ).and_return({ "data" => { "id" => "existing123" } })

        test_model.update!(name: "Updated Name")
      end
    end
  end

  describe "#remove_from_attio" do
    before { model.update_column(:attio_record_id, "attio123") }

    context "with error handling" do
      let(:client) { instance_double(Attio::Client) }
      let(:records) { instance_double(Attio::Resources::Records) }
      let(:logger) { instance_double(Logger) }

      before do
        Attio::Rails.configure { |c| c.background_sync = false }
        allow(Attio::Rails).to receive(:client).and_return(client)
        allow(Attio::Rails).to receive(:logger).and_return(logger)
        allow(client).to receive(:records).and_return(records)
        allow(logger).to receive(:error)
      end

      it "logs errors and re-raises in development when removing" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        allow(records).to receive(:delete).and_raise(StandardError, "Delete Error")

        expect(logger).to receive(:error).with(/Failed to remove from Attio/)
        expect { model.destroy! }.to raise_error(StandardError)
      end

      it "logs errors but doesn't raise in production when removing" do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        allow(records).to receive(:delete).and_raise(StandardError, "Delete Error")

        expect(logger).to receive(:error).with(/Failed to remove from Attio/)
        expect { model.destroy! }.not_to raise_error
      end
    end

    context "with background sync enabled" do
      it "enqueues a delete job on destroy" do
        expect do
          model.destroy!
        end.to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size).by(1)

        job = ActiveJob::Base.queue_adapter.enqueued_jobs.last
        expect(job[:job]).to eq(AttioSyncJob)
        args = job[:args].first
        expect(args["model_name"]).to eq("TestModel")
        expect(args["action"]["value"]).to eq("delete")
        expect(args["attio_record_id"]).to eq("attio123")
      end
    end

    context "with background sync disabled" do
      let(:client) { instance_double(Attio::Client) }
      let(:records) { instance_double(Attio::Resources::Records) }

      before do
        Attio::Rails.configure { |c| c.background_sync = false }
        allow(Attio::Rails).to receive(:client).and_return(client)
        allow(client).to receive(:records).and_return(records)
      end

      it "deletes immediately on destroy" do
        expect(records).to receive(:delete).with(
          object: "contacts",
          id: "attio123"
        ).and_return({ "data" => { "deleted" => true } })

        model.destroy!
      end
    end

    it "does not enqueue job if attio_record_id is blank" do
      model.update_column(:attio_record_id, nil)

      expect do
        model.destroy!
      end.not_to change(ActiveJob::Base.queue_adapter.enqueued_jobs, :size)
    end
  end

  describe "#attio_attributes" do
    it "returns mapped attributes" do
      expect(model.attio_attributes).to eq({
        email: "john@example.com",
        name: "John Doe",
        full_name: "John Doe (Test)",
      })
    end

    it "handles nil values by excluding them" do
      model.update_column(:email, nil)
      expect(model.attio_attributes).to eq({
        name: "John Doe",
        full_name: "John Doe (Test)",
      })
    end

    it "handles static values" do
      model_class.syncs_with_attio("contacts", {
        email: :email,
        source: "web",
      })

      expect(model.attio_attributes).to include(source: "web")
    end

    it "handles methods as string" do
      model_class.syncs_with_attio("contacts", {
        email: "email",
        name: "name",
      })

      expect(model.attio_attributes).to eq({
        email: "john@example.com",
        name: "John Doe",
      })
    end

    it "handles non-callable values" do
      model_class.syncs_with_attio("contacts", {
        type: "customer",
        status: true,
        priority: 5,
      })

      attributes = model.attio_attributes
      expect(attributes[:type]).to eq("customer")
      expect(attributes[:status]).to eq(true)
      expect(attributes[:priority]).to eq(5)
    end
  end

  describe "#should_sync_to_attio?" do
    it "returns true when sync is enabled and configured" do
      expect(model.should_sync_to_attio?).to be true
    end

    it "returns true when sync condition is true value" do
      model_class.syncs_with_attio("contacts", { email: :email }, if: true)
      expect(model.should_sync_to_attio?).to be true
    end

    it "returns false when sync is disabled globally" do
      Attio::Rails.configure { |c| c.sync_enabled = false }
      expect(model.should_sync_to_attio?).to be false
    end

    it "returns false when object type is not set" do
      model_class.attio_object_type = nil
      expect(model.should_sync_to_attio?).to be false
    end

    it "returns false when attribute mapping is not set" do
      model_class.attio_attribute_mapping = nil
      expect(model.should_sync_to_attio?).to be false
    end

    context "with sync conditions" do
      before do
        model_class.syncs_with_attio("contacts", { email: :email }, if: :active?)
      end

      it "returns true when condition is met" do
        model.update_column(:active, true)
        expect(model.should_sync_to_attio?).to be true
      end

      it "returns true when proc condition is met" do
        model_class.syncs_with_attio("contacts", { email: :email }, if: -> { active? })
        model.update_column(:active, true)
        expect(model.should_sync_to_attio?).to be true
      end

      it "returns false when condition is not met" do
        model.update_column(:active, false)
        expect(model.should_sync_to_attio?).to be false
      end
    end
  end

  describe "#should_remove_from_attio?" do
    it "returns true when attio_record_id is present and sync is enabled" do
      model.update_column(:attio_record_id, "attio123")
      expect(model.should_remove_from_attio?).to be true
    end

    it "returns false when attio_record_id is blank" do
      model.update_column(:attio_record_id, nil)
      expect(model.should_remove_from_attio?).to be false
    end

    it "returns false when sync is disabled" do
      model.update_column(:attio_record_id, "attio123")
      Attio::Rails.configure { |c| c.sync_enabled = false }
      expect(model.should_remove_from_attio?).to be false
    end
  end

  describe "#attio_identifier" do
    it "returns the id by default" do
      expect(model.attio_identifier).to eq(model.id)
    end

    it "returns the configured identifier attribute" do
      model_class.syncs_with_attio("contacts", { email: :email }, identifier: :email)
      expect(model.attio_identifier).to eq("john@example.com")
    end
  end

  describe "error handling" do
    let(:client) { instance_double(Attio::Client) }
    let(:records) { instance_double(Attio::Resources::Records) }
    let(:logger) { instance_double(Logger) }

    before do
      Attio::Rails.configure { |c| c.background_sync = false }
      allow(Attio::Rails).to receive(:client).and_return(client)
      allow(Attio::Rails).to receive(:logger).and_return(logger)
      allow(client).to receive(:records).and_return(records)
      allow(logger).to receive(:error)
    end

    it "logs errors and re-raises in development" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      allow(records).to receive(:create).and_raise(StandardError, "API Error")

      expect(logger).to receive(:error).with(/Failed to sync to Attio/)
      expect { model_class.create!(name: "Test", email: "test@example.com") }.to raise_error(StandardError)
    end

    it "logs errors but doesn't raise in production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      allow(records).to receive(:create).and_raise(StandardError, "API Error")

      expect(logger).to receive(:error).with(/Failed to sync to Attio/)
      expect { model_class.create!(name: "Test", email: "test@example.com") }.not_to raise_error
    end
  end
end
