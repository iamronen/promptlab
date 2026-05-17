# frozen_string_literal: true

class CreateTaxonomiesAndTaxonomyTerms < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomies do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :cardinality, null: false
      t.string :single_select_ui
      t.integer :position, null: false, default: 0
      t.timestamps
    end

    add_index :taxonomies, "project_id, lower(name)", unique: true, name: "index_taxonomies_on_project_id_lower_name"

    create_table :taxonomy_terms do |t|
      t.references :taxonomy, null: false, foreign_key: true
      t.string :label, null: false
      t.integer :position, null: false
      t.timestamps
    end

    add_index :taxonomy_terms, [:taxonomy_id, :position], unique: true
  end
end
