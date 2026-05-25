# frozen_string_literal: true

class AddDefaultProcessTaxonomyToProjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :projects,
                  :default_process_taxonomy,
                  foreign_key: { to_table: :taxonomies, on_delete: :nullify },
                  null: true
  end
end
