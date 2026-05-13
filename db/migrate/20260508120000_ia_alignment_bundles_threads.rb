# frozen_string_literal: true

class IaAlignmentBundlesThreads < ActiveRecord::Migration[8.1]
  def up
    add_column :sequences, :is_orphans, :boolean, default: false, null: false
    add_column :sequence_dependencies, :anchor_sequence_id, :bigint

    rename_column :thread_nodes, :parent_transformation_id, :parent_bundle_id
    add_column :thread_nodes, :parent_generative_sequence_id, :bigint
    change_column_null :thread_nodes, :parent_bundle_id, true

    add_foreign_key :sequence_dependencies, :sequences, column: :anchor_sequence_id, validate: false
    add_foreign_key :thread_nodes, :sequences, column: :parent_generative_sequence_id, validate: false

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequences_unique_orphans_thread_per_project
      ON sequences (project_id)
      WHERE kind = 'thread' AND is_orphans IS TRUE;
    SQL

    execute "DROP INDEX IF EXISTS index_sequence_dependencies_unique_prerequisite_pair;"
    execute "DROP INDEX IF EXISTS index_sequence_dependencies_unique_thread_step_child;"
    execute "DROP INDEX IF EXISTS index_sequence_dependencies_unique_thread_step_position;"
    execute "DROP INDEX IF EXISTS index_thread_nodes_on_parent_fork_and_child_order;"

    execute <<~SQL.squish
      UPDATE sequences SET kind = 'bundle' WHERE kind = 'transformation';
    SQL

    execute <<~SQL.squish
      UPDATE sequence_dependencies SET kind = 'bundle_prerequisite'
      WHERE kind = 'transformation_prerequisite';
    SQL

    execute <<~SQL.squish
      UPDATE sequence_dependencies SET kind = 'thread_step_bundle'
      WHERE kind = 'thread_step';
    SQL

    say_with_time "Migrate thread strand steps_data transformation_id to bundle_id" do
      migrate_thread_steps_data_keys
    end

    say_with_time "Backfill thread_nodes.parent_generative_sequence_id from fork bundle" do
      backfill_thread_node_anchors
    end

    say_with_time "Create thread_branch dependency rows" do
      backfill_thread_branch_dependencies
    end

    say_with_time "Backfill orphans root thread per project" do
      backfill_orphans_threads
    end

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_bundle_prerequisite_pair
      ON sequence_dependencies (parent_id, child_id)
      WHERE kind = 'bundle_prerequisite';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_step_bundle_child
      ON sequence_dependencies (child_id)
      WHERE kind = 'thread_step_bundle';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_step_bundle_position
      ON sequence_dependencies (parent_id, position)
      WHERE kind = 'thread_step_bundle';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_step_sequence_child
      ON sequence_dependencies (child_id)
      WHERE kind = 'thread_step_sequence';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_step_sequence_position
      ON sequence_dependencies (parent_id, position)
      WHERE kind = 'thread_step_sequence';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_branch_child
      ON sequence_dependencies (child_id)
      WHERE kind = 'thread_branch';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_sequence_dependencies_unique_thread_branch_position
      ON sequence_dependencies (parent_id, position)
      WHERE kind = 'thread_branch';
    SQL

    execute <<~SQL.squish
      CREATE UNIQUE INDEX index_thread_nodes_on_parent_anchor_child_order
      ON thread_nodes (parent_thread_id, parent_generative_sequence_id, child_order);
    SQL

    validate_foreign_key :sequence_dependencies, column: :anchor_sequence_id
    validate_foreign_key :thread_nodes, column: :parent_generative_sequence_id
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def migrate_thread_steps_data_keys
    Sequence.where(kind: "thread").find_each do |seq|
      data = seq.steps_data
      next unless data.is_a?(Array)

      new_data = data.map do |row|
        next row unless row.is_a?(Hash)

        h = row.stringify_keys
        if h["transformation_id"].present?
          { "bundle_id" => h["transformation_id"].to_i }
        else
          row
        end
      end
      seq.update_columns(steps_data: new_data)
    end
  end

  def backfill_thread_node_anchors
    connection.select_all(
      "SELECT id, parent_bundle_id FROM thread_nodes WHERE parent_bundle_id IS NOT NULL"
    ).each do |row|
      bundle = Sequence.find_by(id: row["parent_bundle_id"], kind: "bundle")
      next unless bundle

      sid = first_pipeline_sequence_id(bundle)
      next unless sid

      execute ApplicationRecord.sanitize_sql_array(["UPDATE thread_nodes SET parent_generative_sequence_id = ? WHERE id = ?", sid, row["id"]])
    end
  end

  def first_pipeline_sequence_id(bundle)
    Array.wrap(bundle.steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      raw.stringify_keys["sequence_id"].presence&.to_i
    end.reject { |n| n <= 0 }.first
  end

  def flattened_generative_ids_for_thread(thread)
    ids = []
    Array.wrap(thread.steps_data).each do |raw|
      next unless raw.is_a?(Hash)

      h = raw.stringify_keys
      if h["bundle_id"].present?
        b = Sequence.find_by(id: h["bundle_id"].to_i, kind: "bundle")
        ids.concat(pipeline_sequence_ids(b)) if b
      elsif h["sequence_id"].present?
        sid = h["sequence_id"].to_i
        ids << sid if sid.positive?
      end
    end
    ids
  end

  def pipeline_sequence_ids(bundle)
    return [] unless bundle

    Array.wrap(bundle.steps_data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      raw.stringify_keys["sequence_id"].presence&.to_i
    end.reject { |n| n <= 0 }
  end

  def backfill_thread_branch_dependencies
    execute "DELETE FROM sequence_dependencies WHERE kind = 'thread_branch'"

    rows = connection.select_all(<<~SQL.squish
      SELECT id, parent_thread_id, child_thread_id, parent_generative_sequence_id, child_order
      FROM thread_nodes
      WHERE parent_generative_sequence_id IS NOT NULL
    SQL
                                ).to_a

    by_parent = rows.group_by { |r| r["parent_thread_id"].to_i }
    now = Time.current

    by_parent.each_value do |list|
      thread = Sequence.find_by(id: list.first["parent_thread_id"].to_i, kind: "thread")
      next unless thread

      flat = flattened_generative_ids_for_thread(thread)
      ordered = list.sort_by do |n|
        idx = flat.index(n["parent_generative_sequence_id"].to_i)
        [idx || 1_000_000, n["child_order"].to_i, n["id"].to_i]
      end

      dep_rows = ordered.each_with_index.map do |n, i|
        {
          parent_id: n["parent_thread_id"].to_i,
          child_id: n["child_thread_id"].to_i,
          kind: "thread_branch",
          position: i + 1,
          anchor_sequence_id: n["parent_generative_sequence_id"].to_i,
          created_at: now,
          updated_at: now
        }
      end
      SequenceDependency.insert_all!(dep_rows) if dep_rows.any?
    end
  end

  def backfill_orphans_threads
    Sequence.reset_column_information
    Project.find_each do |project|
      next if Sequence.where(project_id: project.id, kind: "thread", is_orphans: true).exists?

      pos = Sequence.where(project_id: project.id, kind: "thread").maximum(:position).to_i + 1
      Sequence.create!(
        project_id: project.id,
        kind: :thread,
        title: Sequence::ORPHANS_THREAD_TITLE,
        intent: "Secondary thread for sequences without a clear place in the Genesis lineage.",
        position: pos,
        steps_data: [],
        is_genesis: false,
        is_orphans: true,
        is_term: false
      )
    end
  end
end
