# frozen_string_literal: true

class AddProcessEndStateToTaxonomyTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :taxonomy_terms, :process_end_state, :boolean, null: false, default: false
  end
end
