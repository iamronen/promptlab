# frozen_string_literal: true

class AddThreadSharingData < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    change_table :sequences, bulk: true do |t|
      t.string :share_state, null: false, default: "none"
      t.string :share_public_name
    end

    add_index :sequences, :share_state,
              where: "share_state = 'enabled'",
              name: "index_sequences_on_share_state_enabled",
              algorithm: :concurrently

    change_table :projects, bulk: true do |t|
      t.boolean :sharing_allowed, null: false, default: true
    end

    create_table :sequence_share_inclusions do |t|
      t.references :root_sequence, null: false, foreign_key: { to_table: :sequences, on_delete: :cascade }
      t.references :included_sequence, null: false, foreign_key: { to_table: :sequences, on_delete: :cascade }
      t.timestamps
    end

    add_index :sequence_share_inclusions,
              %i[root_sequence_id included_sequence_id],
              unique: true,
              name: "index_sequence_share_inclusions_on_root_and_included"
  end
end
