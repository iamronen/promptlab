# frozen_string_literal: true

class AddUserToProjects < ActiveRecord::Migration[8.1]
  LEGACY_OWNER_EMAIL = "legacy-owner@localhost"

  def up
    add_reference :projects, :user, foreign_key: true

    say_with_time "Backfilling project owners" do
      password = SecureRandom.hex(24)
      owner = User.find_or_initialize_by(email: LEGACY_OWNER_EMAIL)
      owner.password = password
      owner.password_confirmation = password
      owner.save!
      Project.where(user_id: nil).update_all(user_id: owner.id)
    end

    change_column_null :projects, :user_id, false
  end

  def down
    change_column_null :projects, :user_id, true
    remove_reference :projects, :user, foreign_key: true
    User.where(email: LEGACY_OWNER_EMAIL).delete_all
  end
end
