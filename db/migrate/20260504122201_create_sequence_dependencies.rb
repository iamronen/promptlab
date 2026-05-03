# frozen_string_literal: true

class CreateSequenceDependencies < ActiveRecord::Migration[8.1]
  def up
    create_table :sequence_dependencies do |t|
      t.bigint :parent_id, null: false
      t.bigint :child_id, null: false
      t.string :kind, null: false
      t.integer :position
      t.timestamps
    end

    add_foreign_key :sequence_dependencies, :sequences, column: :parent_id
    add_foreign_key :sequence_dependencies, :sequences, column: :child_id
    add_index :sequence_dependencies, :child_id
    add_index :sequence_dependencies, [:parent_id, :kind]

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_sequence_step_position
      ON sequence_dependencies (parent_id, position)
      WHERE kind = 'sequence_step';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_prerequisite_pair
      ON sequence_dependencies (parent_id, child_id)
      WHERE kind = 'transformation_prerequisite';
    SQL

    say_with_time "Clear legacy transformation steps_data (content-only blobs)" do
      Sequence.where(kind: "transformation").find_each do |seq|
        next unless seq.steps_data.is_a?(Array)

        if seq.steps_data.any? { |row| row.is_a?(Hash) && row.key?("content") && row["sequence_id"].blank? }
          seq.update_columns(steps_data: [])
        end
      end
    end
  end

  def down
    execute "DROP INDEX IF EXISTS index_sequence_dependencies_unique_sequence_step_position;"
    execute "DROP INDEX IF EXISTS index_sequence_dependencies_unique_prerequisite_pair;"
    drop_table :sequence_dependencies
  end
end
