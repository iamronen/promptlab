# frozen_string_literal: true

class AddPublicIdToProjects < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  class MigrationProject < ApplicationRecord
    self.table_name = "projects"
  end

  def up
    add_column :projects, :public_id, :string, limit: 24

    say_with_time "Backfill public_id for existing projects" do
      MigrationProject.find_each do |project|
        project.update_column(:public_id, generate_unique_public_id)
      end
    end

    change_column_null :projects, :public_id, false
    add_index :projects, :public_id, unique: true, algorithm: :concurrently
  end

  def down
    remove_index :projects, :public_id
    remove_column :projects, :public_id
  end

  private

  def generate_unique_public_id
    loop do
      candidate = SecureRandom.urlsafe_base64(16)
      break candidate unless MigrationProject.exists?(public_id: candidate)
    end
  end
end
