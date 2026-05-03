class AddKindToSequences < ActiveRecord::Migration[8.1]
  def change
    add_column :sequences, :kind, :string, null: false, default: "sequence"
    remove_index :sequences, name: "index_sequences_on_project_id_and_position"
    add_index :sequences,
              %i[project_id kind position],
              unique: true,
              name: "index_sequences_on_project_id_kind_and_position"
  end
end
