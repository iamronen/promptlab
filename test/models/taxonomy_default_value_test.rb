# frozen_string_literal: true

require "test_helper"

class TaxonomyDefaultValueTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
    @term = @taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
  end

  test "defaults default value settings to disabled" do
    assert_not @taxonomy.default_value_enabled?
    assert_nil @taxonomy.default_taxonomy_term_id
  end

  test "enabling default value with term persists selection" do
    @taxonomy.update!(default_value_enabled: true, default_taxonomy_term: @term)

    assert @taxonomy.default_value_enabled?
    assert_equal @term.id, @taxonomy.default_taxonomy_term_id
  end

  test "disabling default value clears selected term" do
    @taxonomy.update!(default_value_enabled: true, default_taxonomy_term: @term)
    @taxonomy.update!(default_value_enabled: false)

    assert_not @taxonomy.default_value_enabled?
    assert_nil @taxonomy.default_taxonomy_term_id
  end

  test "rejects default term from another taxonomy" do
    other = @project.taxonomies.create!(name: "Other", cardinality: :one, position: 2)
    foreign_term = other.taxonomy_terms.create!(label: "X", position: 1)

    @taxonomy.default_value_enabled = true
    @taxonomy.default_taxonomy_term = foreign_term

    assert_not @taxonomy.valid?
    assert_includes @taxonomy.errors[:default_taxonomy_term], "must be a value in this taxonomy"
  end

  test "deleting default term disables default value setting" do
    @taxonomy.update!(default_value_enabled: true, default_taxonomy_term: @term)
    @term.destroy!

    @taxonomy.reload
    assert_not @taxonomy.default_value_enabled?
    assert_nil @taxonomy.default_taxonomy_term_id
  end
end
