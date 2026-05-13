# frozen_string_literal: true

class AddThreadsThreadNodesAndBackfill < ActiveRecord::Migration[8.1]
  def up
    add_column :sequences, :is_genesis, :boolean, default: false, null: false

    create_table :thread_nodes do |t|
      t.bigint :parent_thread_id, null: false
      t.bigint :parent_transformation_id, null: false
      t.bigint :child_thread_id, null: false
      t.integer :child_order, null: false
      t.timestamps
    end

    add_foreign_key :thread_nodes, :sequences, column: :parent_thread_id
    add_foreign_key :thread_nodes, :sequences, column: :parent_transformation_id
    add_foreign_key :thread_nodes, :sequences, column: :child_thread_id
    add_index :thread_nodes, :child_thread_id, unique: true,
                                                name: "index_thread_nodes_on_child_thread_id_unique"
    add_index :thread_nodes, [:parent_thread_id, :parent_transformation_id, :child_order],
              unique: true, name: "index_thread_nodes_on_parent_fork_and_child_order"

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequences_unique_genesis_thread_per_project
      ON sequences (project_id)
      WHERE kind = 'thread' AND is_genesis IS TRUE;
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_step_position
      ON sequence_dependencies (parent_id, position)
      WHERE kind = 'thread_step';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_step_child
      ON sequence_dependencies (child_id)
      WHERE kind = 'thread_step';
    SQL

    say_with_time "Backfill genesis thread per project" do
      backfill_genesis_threads
    end
  end

  def down
    say_with_time "Remove thread weave data" do
      execute "DELETE FROM thread_nodes;"
      execute <<~SQL.squish
        DELETE FROM sequence_dependencies WHERE kind = 'thread_step';
      SQL
      execute <<~SQL.squish
        DELETE FROM sequences WHERE kind = 'thread';
      SQL
    end

    execute "DROP INDEX IF EXISTS index_sequence_dependencies_unique_thread_step_child;"
    execute "DROP INDEX IF EXISTS index_sequence_dependencies_unique_thread_step_position;"
    execute "DROP INDEX IF EXISTS index_sequences_unique_genesis_thread_per_project;"

    drop_table :thread_nodes
    remove_column :sequences, :is_genesis
  end

  private

  def backfill_genesis_threads
    Sequence.reset_column_information

    Project.find_each do |project|
      next if Sequence.where(project_id: project.id, kind: "thread", is_genesis: true).exists?

      thread_position = Sequence.where(project_id: project.id, kind: "thread").maximum(:position).to_i + 1

      genesis = Sequence.create!(
        project_id: project.id,
        kind: :thread,
        title: Sequence::THREAD_DEFAULT_TITLE,
        intent: Sequence::THREAD_DEFAULT_INTENT,
        position: thread_position,
        steps_data: [],
        is_term: false,
        is_genesis: true
      )

      ids = Sequence.where(project_id: project.id, kind: "transformation").order(:position).pluck(:id)
      genesis.update!(
        steps_data: ids.map { |tid| { "transformation_id" => tid } }
      )
    end
  end
end
