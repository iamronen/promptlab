# frozen_string_literal: true

require "test_helper"

class TaxonomyBundleSettingsTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy = @project.taxonomies.create!(name: "Status", cardinality: :one, position: 1)
  end

  test "defaults apply to sequences only" do
    assert @taxonomy.applies_to_sequences?
    assert_not @taxonomy.applies_to_bundles?
    assert_not @taxonomy.applies_to_bundle_pipeline_sequences?
  end

  test "bundle pipeline sequences cleared when applies to bundles is false" do
    @taxonomy.applies_to_bundles = false
    @taxonomy.applies_to_bundle_pipeline_sequences = true
    @taxonomy.valid?

    assert_not @taxonomy.applies_to_bundle_pipeline_sequences?
  end

  test "process tracking clears bundle pipeline sequences" do
    @taxonomy.update!(applies_to_bundles: true, applies_to_bundle_pipeline_sequences: true)
    @taxonomy.update!(process_tracking: true)

    assert_not @taxonomy.applies_to_bundle_pipeline_sequences?
  end

  test "applicable_to_sequence for standalone sequence" do
    seq = @project.sequences.create!(
      kind: :sequence,
      title: "S",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )

    assert @taxonomy.applicable_to_sequence?(seq)

    @taxonomy.update!(applies_to_sequences: false)
    assert_not @taxonomy.applicable_to_sequence?(seq)
  end

  test "applicable_to_sequence excludes pipeline child when bundles enabled without pipeline flag" do
    gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )
    bundle = @project.sequences.create!(
      kind: :bundle,
      title: "B",
      intent: "bi",
      position: 1,
      steps_data: [{ "sequence_id" => gen.id }],
      is_term: false
    )
    bundle # touch
    gen.reload

    @taxonomy.update!(applies_to_bundles: true, applies_to_bundle_pipeline_sequences: false)

    assert gen.in_bundle_pipeline?
    assert_not @taxonomy.applicable_to_sequence?(gen)

    @taxonomy.update!(applies_to_bundle_pipeline_sequences: true)
    assert @taxonomy.applicable_to_sequence?(gen)
  end
end
