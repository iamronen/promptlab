# frozen_string_literal: true

require "test_helper"

class TaxonomyAssignmentHistoryTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy =
      @project.taxonomies.create!(
        name: "Status",
        cardinality: :one,
        process_tracking: true,
        position: 1
      )
    @term = @taxonomy.taxonomy_terms.create!(label: "Open", position: 1)
    @sequence =
      @project.sequences.create!(
        kind: :sequence,
        title: "S",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
  end

  test "valid history record" do
    history =
      TaxonomyAssignmentHistory.new(
        project_id: @project.id,
        sequence_id: @sequence.id,
        taxonomy_id: @taxonomy.id,
        taxonomy_term_id: @term.id,
        label_snapshot: @term.label,
        assigned_at: 2.hours.ago,
        ended_at: 1.hour.ago
      )

    assert history.valid?
    assert history.save
  end

  test "rejects ended_at before assigned_at" do
    history =
      TaxonomyAssignmentHistory.new(
        project_id: @project.id,
        sequence_id: @sequence.id,
        taxonomy_id: @taxonomy.id,
        taxonomy_term_id: @term.id,
        label_snapshot: @term.label,
        assigned_at: 1.hour.ago,
        ended_at: 2.hours.ago
      )

    refute history.valid?
    assert_includes history.errors[:ended_at], "must be on or after assigned_at"
  end

  test "rejects bundle sequence" do
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "B",
        intent: "i",
        position: 2,
        steps_data: [],
        is_term: false
      )

    history =
      TaxonomyAssignmentHistory.new(
        project_id: @project.id,
        sequence_id: bundle.id,
        taxonomy_id: @taxonomy.id,
        taxonomy_term_id: @term.id,
        label_snapshot: @term.label,
        assigned_at: 2.hours.ago,
        ended_at: 1.hour.ago
      )

    refute history.valid?
    assert_includes history.errors[:sequence_id], "must be a generative sequence"
  end
end
