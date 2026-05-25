# frozen_string_literal: true

class AddBundleScopeToTaxonomies < ActiveRecord::Migration[8.0]
  def change
    change_table :taxonomies, bulk: true do |t|
      t.boolean :applies_to_sequences, null: false, default: true
      t.boolean :applies_to_bundles, null: false, default: false
      t.boolean :applies_to_bundle_pipeline_sequences, null: false, default: false
    end
  end
end
