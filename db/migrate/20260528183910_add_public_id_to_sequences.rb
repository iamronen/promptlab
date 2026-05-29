# frozen_string_literal: true

class AddPublicIdToSequences < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationSequence < ApplicationRecord
    self.table_name = "sequences"
  end

  def up
    add_column :sequences, :public_id, :string, limit: 24

    say_with_time "Backfill public_id for existing sequences" do
      MigrationSequence.find_each do |sequence|
        sequence.update_column(:public_id, generate_unique_public_id)
      end
    end

    change_column_null :sequences, :public_id, false
    add_index :sequences, :public_id, unique: true, algorithm: :concurrently
  end

  def down
    remove_index :sequences, :public_id
    remove_column :sequences, :public_id
  end

  private

  def generate_unique_public_id
    loop do
      candidate = SecureRandom.urlsafe_base64(16)
      break candidate unless MigrationSequence.exists?(public_id: candidate)
    end
  end
end
