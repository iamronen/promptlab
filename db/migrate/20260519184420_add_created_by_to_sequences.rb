# frozen_string_literal: true

class AddCreatedByToSequences < ActiveRecord::Migration[8.1]
  def up
    add_reference :sequences, :created_by, foreign_key: { to_table: :users }, null: true

    say_with_time "Backfilling sequence creators from project owners" do
      execute <<~SQL.squish
        UPDATE sequences
        SET created_by_id = projects.user_id
        FROM projects
        WHERE sequences.project_id = projects.id
          AND sequences.created_by_id IS NULL
      SQL
    end

    change_column_null :sequences, :created_by_id, false
  end

  def down
    remove_reference :sequences, :created_by, foreign_key: { to_table: :users }
  end
end
