# frozen_string_literal: true

# Set up a simple in-memory database for testing
ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

ActiveRecord::Schema.define do
  create_table :test_models, force: true do |t|
    t.string :name
    t.string :email
    t.string :attio_record_id
    t.boolean :active, default: true
    t.timestamps
  end

  create_table :companies, force: true do |t|
    t.string :name
    t.string :attio_record_id
    t.timestamps
  end
end

class TestModel < ActiveRecord::Base
  include Attio::Rails::Concerns::Syncable

  def prepare_for_sync
    # Called before sync
  end

  def handle_sync_result(result)
    # Called after sync with result
  end

  def handle_attio_error(error)
    # Called when sync fails
  end

  def transform_for_attio(attrs = nil)
    (attrs || attributes).merge(custom_field: "transformed")
  end
end

class Company < ActiveRecord::Base
  include Attio::Rails::Concerns::Syncable
end

class Opportunity < TestModel
  include Attio::Rails::Concerns::Dealable

  attr_accessor :attio_deal_id, :value, :stage_id, :status, :closed_date, :lost_reason, :current_stage_id,
                :company_attio_id, :owner_attio_id, :expected_close_date

  def initialize(attrs = {})
    super(attrs.except(:value, :stage_id, :attio_deal_id, :status, :closed_date, :lost_reason, :current_stage_id,
                       :company_attio_id, :owner_attio_id, :expected_close_date))
    @value = attrs[:value]
    @stage_id = attrs[:stage_id]
    @attio_deal_id = attrs[:attio_deal_id]
    @status = attrs[:status]
    @closed_date = attrs[:closed_date]
    @lost_reason = attrs[:lost_reason]
    @current_stage_id = attrs[:current_stage_id]
    @company_attio_id = attrs[:company_attio_id]
    @owner_attio_id = attrs[:owner_attio_id]
    @expected_close_date = attrs[:expected_close_date]
  end

  def id
    @id ||= rand(1000)
  end

  def update_column(column, value)
    send("#{column}=", value)
  end
end
