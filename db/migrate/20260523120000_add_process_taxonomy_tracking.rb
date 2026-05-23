# frozen_string_literal: true

class AddProcessTaxonomyTracking < ActiveRecord::Migration[8.1]
  def change
    add_column :taxonomies, :process_tracking, :boolean, null: false, default: false

    add_column :taxonomy_assignments, :assigned_at, :datetime

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE taxonomy_assignments SET assigned_at = created_at WHERE assigned_at IS NULL
        SQL
      end
    end

    change_column_null :taxonomy_assignments, :assigned_at, false

    create_table :taxonomy_assignment_histories do |t|
      t.references :project, null: false, foreign_key: true
      t.references :sequence, null: false, foreign_key: { to_table: :sequences }
      t.references :taxonomy, null: false, foreign_key: true
      t.references :taxonomy_term, null: true, foreign_key: { on_delete: :nullify }
      t.string :label_snapshot, null: false
      t.datetime :assigned_at, null: false
      t.datetime :ended_at, null: false
      t.timestamps
    end

    add_index :taxonomy_assignment_histories, [:sequence_id, :taxonomy_id, :assigned_at],
              name: "index_taxonomy_assignment_histories_on_seq_tax_assigned"
    add_index :taxonomy_assignment_histories, [:project_id, :taxonomy_id],
              name: "index_taxonomy_assignment_histories_on_project_taxonomy"
  end
end
