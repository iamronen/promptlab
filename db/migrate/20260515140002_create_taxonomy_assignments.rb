# frozen_string_literal: true

class CreateTaxonomyAssignments < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_assignments do |t|
      t.references :project, null: false, foreign_key: true
      t.references :sequence, null: false, foreign_key: { to_table: :sequences }
      t.references :taxonomy, null: false, foreign_key: true
      t.references :taxonomy_term, null: false, foreign_key: { on_delete: :restrict }
      t.string :label_snapshot, null: false
      t.boolean :single_value_taxonomy_copy, null: false
      t.timestamps
    end

    add_index :taxonomy_assignments, [:taxonomy_id, :taxonomy_term_id]
    add_index :taxonomy_assignments, [:project_id, :taxonomy_id]
    add_index :taxonomy_assignments, [:sequence_id, :taxonomy_term_id], unique: true,
              name: "index_taxonomy_assignments_unique_sequence_term"

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          CREATE UNIQUE INDEX index_taxonomy_assignments_unique_single_taxonomy
          ON taxonomy_assignments (sequence_id, taxonomy_id)
          WHERE single_value_taxonomy_copy = TRUE;
        SQL
      end
      dir.down do
        execute <<~SQL.squish
          DROP INDEX IF EXISTS index_taxonomy_assignments_unique_single_taxonomy;
        SQL
      end
    end
  end
end
