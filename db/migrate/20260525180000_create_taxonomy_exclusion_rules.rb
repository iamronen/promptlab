# frozen_string_literal: true

class CreateTaxonomyExclusionRules < ActiveRecord::Migration[8.1]
  def change
    create_table :taxonomy_exclusion_rules do |t|
      t.references :taxonomy, null: false, foreign_key: { on_delete: :cascade }
      t.references :excluding_taxonomy, null: false, foreign_key: { to_table: :taxonomies, on_delete: :cascade }
      t.references :project, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :taxonomy_exclusion_rules,
              %i[taxonomy_id excluding_taxonomy_id],
              unique: true,
              name: "index_taxonomy_exclusion_rules_on_taxonomy_and_excluding"

    create_table :taxonomy_exclusion_rule_terms do |t|
      t.references :taxonomy_exclusion_rule, null: false, foreign_key: { on_delete: :cascade }
      t.references :taxonomy_term, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :taxonomy_exclusion_rule_terms,
              %i[taxonomy_exclusion_rule_id taxonomy_term_id],
              unique: true,
              name: "index_taxonomy_exclusion_rule_terms_on_rule_and_term"
  end
end
