# Set up a simple in-memory database for testing
ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: ':memory:'
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
end

class Company < ActiveRecord::Base
  include Attio::Rails::Concerns::Syncable
end