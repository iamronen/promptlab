# frozen_string_literal: true

require "test_helper"

class Taxonomies::ApplyBundleSettingsTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy = @project.taxonomies.create!(
      name: "Lane",
      cardinality: :one,
      position: 1,
      applies_to_bundles: true,
      applies_to_bundle_pipeline_sequences: true
    )
    @term = @taxonomy.taxonomy_terms.create!(label: "Alpha", position: 1)
    @gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )
    @bundle = @project.sequences.create!(
      kind: :bundle,
      title: "Bundle",
      intent: "bi",
      position: 1,
      steps_data: [{ "sequence_id" => @gen.id }],
      is_term: false
    )
    @bundle.update!(steps_data: [{ "sequence_id" => @gen.id }])
    @gen.reload

    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @bundle.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @term.id,
      label_snapshot: @term.label,
      single_value_taxonomy_copy: true
    )
    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @gen.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @term.id,
      label_snapshot: @term.label,
      single_value_taxonomy_copy: true
    )
  end

  test "disabling bundles requires confirmation when bundle assignments exist" do
    result = Taxonomies::ApplyBundleSettings.call(
      taxonomy: @taxonomy,
      attrs: { applies_to_bundles: false }
    )

    assert_equal :confirmation_required, result.status
    assert_equal 1, result.confirmation.bundle_assignment_count
    assert @taxonomy.reload.applies_to_bundles?
    assert TaxonomyAssignment.exists?(sequence_id: @bundle.id, taxonomy_id: @taxonomy.id)
  end

  test "disabling bundles deletes bundle assignments when confirmed" do
    result = Taxonomies::ApplyBundleSettings.call(
      taxonomy: @taxonomy,
      attrs: { applies_to_bundles: false },
      confirm_deletions: true
    )

    assert_equal :ok, result.status
    assert_not @taxonomy.reload.applies_to_bundles?
    assert_not TaxonomyAssignment.exists?(sequence_id: @bundle.id, taxonomy_id: @taxonomy.id)
    assert TaxonomyAssignment.exists?(sequence_id: @gen.id, taxonomy_id: @taxonomy.id)
  end

  test "disabling pipeline sequences requires confirmation when pipeline assignments exist" do
    result = Taxonomies::ApplyBundleSettings.call(
      taxonomy: @taxonomy,
      attrs: { applies_to_bundle_pipeline_sequences: false }
    )

    assert_equal :confirmation_required, result.status
    assert_equal 1, result.confirmation.bundle_pipeline_sequence_assignment_count
    assert @taxonomy.reload.applies_to_bundle_pipeline_sequences?
  end

  test "disabling pipeline sequences deletes pipeline child assignments when confirmed" do
    result = Taxonomies::ApplyBundleSettings.call(
      taxonomy: @taxonomy,
      attrs: { applies_to_bundle_pipeline_sequences: false },
      confirm_deletions: true
    )

    assert_equal :ok, result.status
    assert_not @taxonomy.reload.applies_to_bundle_pipeline_sequences?
    assert_not TaxonomyAssignment.exists?(sequence_id: @gen.id, taxonomy_id: @taxonomy.id)
    assert TaxonomyAssignment.exists?(sequence_id: @bundle.id, taxonomy_id: @taxonomy.id)
  end

  test "disabling bundles deletes bundle assignments for process tracking taxonomy without archiving" do
    @taxonomy.update!(process_tracking: true)

    result = Taxonomies::ApplyBundleSettings.call(
      taxonomy: @taxonomy,
      attrs: { applies_to_bundles: false, applies_to_bundle_pipeline_sequences: false },
      confirm_deletions: true
    )

    assert_equal :ok, result.status
    assert_not @taxonomy.reload.applies_to_bundles?
    assert_not TaxonomyAssignment.exists?(sequence_id: @bundle.id, taxonomy_id: @taxonomy.id)
    assert_equal 0, TaxonomyAssignmentHistory.where(taxonomy_id: @taxonomy.id, sequence_id: @bundle.id).count
  end

  test "enabling bundles backfills from first pipeline sequence" do
    @taxonomy.update!(applies_to_bundles: false)
    TaxonomyAssignment.where(sequence_id: @bundle.id).delete_all

    result = Taxonomies::ApplyBundleSettings.call(
      taxonomy: @taxonomy,
      attrs: { applies_to_bundles: true }
    )

    assert_equal :ok, result.status
    assert TaxonomyAssignment.exists?(sequence_id: @bundle.id, taxonomy_id: @taxonomy.id)
  end
end
