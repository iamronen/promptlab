class CreateSteps < ActiveRecord::Migration[8.1]
  def change
    create_table :steps do |t|
      t.references :sequence, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.text :content, null: false

      t.timestamps
    end

    add_index :steps, [:sequence_id, :position], unique: true
  end
end
