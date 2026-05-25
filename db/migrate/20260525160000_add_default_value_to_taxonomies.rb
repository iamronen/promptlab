# frozen_string_literal: true

class AddDefaultValueToTaxonomies < ActiveRecord::Migration[8.1]
  def change
    add_column :taxonomies, :default_value_enabled, :boolean, default: false, null: false
    add_reference :taxonomies, :default_taxonomy_term,
                  foreign_key: { to_table: :taxonomy_terms, on_delete: :nullify },
                  null: true
  end
end
