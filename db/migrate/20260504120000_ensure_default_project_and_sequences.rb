class EnsureDefaultProjectAndSequences < ActiveRecord::Migration[8.1]
  class MigrationProject < ApplicationRecord
    self.table_name = "projects"
  end

  class MigrationSequence < ApplicationRecord
    self.table_name = "sequences"
  end

  def up
    default = MigrationProject.find_or_create_by!(name: "Default Project")

    valid_project_ids = MigrationProject.pluck(:id)
    return if valid_project_ids.empty?

    orphans = MigrationSequence.where.not(project_id: valid_project_ids)
    orphans.update_all(project_id: default.id) if orphans.exists?
  end

  def down
    # no-op
  end
end
