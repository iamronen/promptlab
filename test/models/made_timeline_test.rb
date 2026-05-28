# frozen_string_literal: true

require "test_helper"

class MadeTimelineTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Made timeline", user: users(:alice))
    @taxonomy =
      @project.taxonomies.create!(
        name: "Stage",
        cardinality: :one,
        process_tracking: true,
        single_select_ui: "dropdown",
        applies_to_bundles: true,
        position: 1
      )
    @project.reload
    @doing = @taxonomy.taxonomy_terms.create!(label: "Doing", position: 1)
    @done = @taxonomy.taxonomy_terms.create!(label: "Done", position: 2, process_end_state: true)
    @seq_a =
      @project.sequences.create!(
        kind: :sequence,
        title: "Alpha",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "x" }],
        is_term: false
      )
    @seq_b =
      @project.sequences.create!(
        kind: :sequence,
        title: "Beta",
        intent: "i",
        position: 2,
        steps_data: [{ "content" => "y" }],
        is_term: false
      )
    @timeline = MadeTimeline.new(@project)
  end

  test "ready when default process taxonomy exists" do
    assert @timeline.ready?
  end

  test "entries empty when no end-state assignments" do
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq_a,
      taxonomy: @taxonomy,
      taxonomy_term: @doing,
      label_snapshot: @doing.label,
      assigned_at: Time.current
    )

    assert_empty @timeline.entries
  end

  test "entries include only end-state assignments sorted oldest first" do
    older = Time.zone.parse("2026-01-01 10:00")
    newer = Time.zone.parse("2026-02-01 12:00")

    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq_b,
      taxonomy: @taxonomy,
      taxonomy_term: @done,
      label_snapshot: @done.label,
      assigned_at: newer
    )
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq_a,
      taxonomy: @taxonomy,
      taxonomy_term: @done,
      label_snapshot: @done.label,
      assigned_at: older
    )

    entries = @timeline.entries
    assert_equal 2, entries.size
    assert_equal [@seq_a.id, @seq_b.id], entries.map { |e| e.sequence.id }
    assert_equal [@done.id, @done.id], entries.map { |e| e.term.id }
    assert_equal [older, newer], entries.map(&:assigned_at)
  end

  test "date_groups merge same-day assignments under one date" do
    morning = Time.zone.parse("2026-03-10 09:00")
    evening = Time.zone.parse("2026-03-10 18:30")
    other_day = Time.zone.parse("2026-03-12 11:00")
    seq_c =
      @project.sequences.create!(
        kind: :sequence,
        title: "Gamma",
        intent: "i",
        position: 3,
        steps_data: [{ "content" => "z" }],
        is_term: false
      )

    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq_a,
      taxonomy: @taxonomy,
      taxonomy_term: @done,
      label_snapshot: @done.label,
      assigned_at: morning
    )
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq_b,
      taxonomy: @taxonomy,
      taxonomy_term: @done,
      label_snapshot: @done.label,
      assigned_at: evening
    )
    TaxonomyAssignment.create!(
      project: @project,
      sequence: seq_c,
      taxonomy: @taxonomy,
      taxonomy_term: @done,
      label_snapshot: @done.label,
      assigned_at: other_day
    )

    groups = MadeTimeline.new(@project).date_groups
    assert_equal 2, groups.size
    assert_equal Date.new(2026, 3, 10), groups[0].date
    assert_equal [@seq_a.id, @seq_b.id], groups[0].entries.map { |e| e.sequence.id }
    assert_equal Date.new(2026, 3, 12), groups[1].date
    assert_equal [seq_c.id], groups[1].entries.map { |e| e.sequence.id }
  end

  test "show_end_state_labels when more than one end-state term" do
    assert_not @timeline.show_end_state_labels?

    @taxonomy.taxonomy_terms.create!(label: "Shipped", position: 3, process_end_state: true)
    @project.reload

    assert MadeTimeline.new(@project).show_end_state_labels?
  end

  test "end_state_terms_configured reflects taxonomy terms" do
    assert @timeline.end_state_terms_configured?

    @done.update!(process_end_state: false)
    @project.reload
    assert_not MadeTimeline.new(@project).end_state_terms_configured?
  end

  test "excludes sequences with exclusion rule triggers" do
    perspective = @project.taxonomies.create!(name: "Perspective", cardinality: :one, position: 2)
    vision = perspective.taxonomy_terms.create!(label: "Vision", position: 1)

    Taxonomies::SyncExclusionRules.call(
      taxonomy: @taxonomy,
      rules: [{ excluding_taxonomy_id: perspective.id, excluding_term_ids: [vision.id] }]
    )

    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq_a,
      taxonomy: perspective,
      taxonomy_term: vision,
      label_snapshot: vision.label,
      assigned_at: Time.current
    )
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq_a,
      taxonomy: @taxonomy,
      taxonomy_term: @done,
      label_snapshot: @done.label,
      assigned_at: Time.current
    )

    assert_empty MadeTimeline.new(@project).entries
  end
end
