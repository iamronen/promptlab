class EmbedStepsInSequences < ActiveRecord::Migration[8.1]
  class MigrationSequence < ApplicationRecord
    self.table_name = "sequences"
  end

  class MigrationStep < ApplicationRecord
    self.table_name = "steps"
  end

  def up
    add_column :sequences, :steps_data, :jsonb, null: false, default: []

    MigrationSequence.reset_column_information
    MigrationSequence.find_each do |seq|
      rows = MigrationStep.where(sequence_id: seq.id).order(:position)
      payload = rows.map { |s| { "content" => s.content.to_s } }
      seq.update_columns(steps_data: payload)
    end

    drop_table :steps
  end

  def down
    create_table :steps do |t|
      t.references :sequence, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :content, null: false
      t.timestamps
    end
    add_index :steps, [:sequence_id, :position], unique: true

    MigrationSequence.reset_column_information
    MigrationSequence.find_each do |seq|
      list = seq.steps_data
      list = [] unless list.is_a?(Array)
      list.each_with_index do |h, i|
        content = h.is_a?(Hash) ? h.stringify_keys.fetch("content", "").to_s : ""
        MigrationStep.create!(
          sequence_id: seq.id,
          position: i + 1,
          content: content.presence || " "
        )
      end
    end

    remove_column :sequences, :steps_data
  end
end
