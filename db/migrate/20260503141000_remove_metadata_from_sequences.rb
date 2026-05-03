class RemoveMetadataFromSequences < ActiveRecord::Migration[8.1]
  def change
    return unless column_exists?(:sequences, :metadata)

    remove_column :sequences, :metadata, :jsonb, default: [], null: false
  end
end
