# frozen_string_literal: true

class AddShareScopeAndTeaseToSequences < ActiveRecord::Migration[8.1]
  def up
    change_table :sequences, bulk: true do |t|
      t.string :share_scope, null: false, default: "everything"
      t.boolean :share_tease, null: false, default: false
    end

    execute <<~SQL.squish
      UPDATE sequences
      SET share_scope = 'selected'
      WHERE share_state IN ('enabled', 'disabled')
    SQL
  end

  def down
    change_table :sequences, bulk: true do |t|
      t.remove :share_scope
      t.remove :share_tease
    end
  end
end
