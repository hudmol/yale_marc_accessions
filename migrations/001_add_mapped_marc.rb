require 'db/migrations/utils'

Sequel.migration do

  up do
    create_table(:marc_accession_plugin_record) do
      primary_key :id
      String :uuid
      BlobField :json
      Date :create_time
    end
  end

  down do
  end

end
