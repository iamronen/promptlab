# frozen_string_literal: true

require "test_helper"

class TaxonomyExclusionRuleTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @process_taxonomy =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        position: 1
      )
    @perspective =
      @project.taxonomies.create!(
        name: "Perspective",
        cardinality: :one,
        position: 2
      )
    @vision = @perspective.taxonomy_terms.create!(label: "Vision", position: 1)
  end

  test "valid rule with excluding terms" do
    rule =
      @process_taxonomy.exclusion_rules.build(
        excluding_taxonomy: @perspective,
        project: @project
      )
    rule.taxonomy_exclusion_rule_terms.build(taxonomy_term: @vision)
    assert rule.valid?
    assert rule.save
  end

  test "rejects process taxonomy as excluding taxonomy" do
    rule =
      @process_taxonomy.exclusion_rules.build(
        excluding_taxonomy: @process_taxonomy,
        project: @project
      )
    rule.taxonomy_exclusion_rule_terms.build(taxonomy_term: @vision)

    assert_not rule.valid?
    assert_includes rule.errors[:excluding_taxonomy], "must differ from the process taxonomy"
  end

  test "rejects rule on non-process taxonomy" do
    standard = @project.taxonomies.create!(name: "Tags", cardinality: :many, position: 3)
    rule =
      standard.exclusion_rules.build(
        excluding_taxonomy: @perspective,
        project: @project
      )
    rule.taxonomy_exclusion_rule_terms.build(taxonomy_term: @vision)

    assert_not rule.valid?
    assert_includes rule.errors[:taxonomy], "must have process tracking enabled"
  end
end
