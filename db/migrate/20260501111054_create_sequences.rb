class CreateSequences < ActiveRecord::Migration[8.1]
  def change
    create_table :sequences do |t|
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.text :intent, null: false
      t.integer :position, null: false

      t.timestamps
    end

    add_index :sequences, [:project_id, :position], unique: true
  end
end
