class AddAttioRecordIdToTables < ActiveRecord::Migration<%= migration_version %>
  def change
    # Add attio_record_id to each table that needs to sync with Attio
    # Example:
    # add_column :users, :attio_record_id, :string
    # add_index :users, :attio_record_id
    #
    # add_column :companies, :attio_record_id, :string
    # add_index :companies, :attio_record_id
  end
end