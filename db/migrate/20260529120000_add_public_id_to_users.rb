# frozen_string_literal: true

class AddPublicIdToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    add_column :users, :public_id, :string, limit: 24

    say_with_time "Backfill public_id for existing users" do
      MigrationUser.find_each do |user|
        user.update_column(:public_id, generate_unique_public_id)
      end
    end

    change_column_null :users, :public_id, false
    add_index :users, :public_id, unique: true, algorithm: :concurrently
  end

  def down
    remove_index :users, :public_id
    remove_column :users, :public_id
  end

  private

  def generate_unique_public_id
    loop do
      candidate = SecureRandom.urlsafe_base64(16)
      break candidate unless MigrationUser.exists?(public_id: candidate)
    end
  end
end
