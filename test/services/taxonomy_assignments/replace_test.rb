# frozen_string_literal: true

require "test_helper"

class TaxonomyAssignmentsReplaceTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P", user: users(:alice))
    @taxonomy = @project.taxonomies.create!(name: "T", cardinality: :one, position: 1)
    @term = @taxonomy.taxonomy_terms.create!(label: "Only", position: 1)
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

  test "replace clears omitted taxonomies" do
    other = @project.taxonomies.create!(name: "Other", cardinality: :many, position: 2)
    other_term = other.taxonomy_terms.create!(label: "X", position: 1)

    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: other.id,
      taxonomy_term_id: other_term.id,
      label_snapshot: other_term.label,
      single_value_taxonomy_copy: false
    )

    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [{ "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] }]
      )

    assert replacer.call
    assert_predicate replacer.errors, :empty?
    assert_equal 1, TaxonomyAssignment.where(sequence_id: @sequence.id).count
    assert TaxonomyAssignment.exists?(taxonomy_id: @taxonomy.id, sequence_id: @sequence.id)
    refute TaxonomyAssignment.exists?(taxonomy_id: other.id, sequence_id: @sequence.id)
  end

  test "duplicate taxonomy payload is rejected" do
    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [
          { "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] },
          { "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] }
        ]
      )

    refute replacer.call
    assert_includes replacer.errors.join, "Duplicate taxonomy_id"
  end

  test "process taxonomy change archives prior assignment" do
    @taxonomy.update!(process_tracking: true)
    term_b = @taxonomy.taxonomy_terms.create!(label: "Next", position: 2)

    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [{ "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] }]
      )
    assert replacer.call

    first = TaxonomyAssignment.find_by!(sequence_id: @sequence.id, taxonomy_id: @taxonomy.id)
    first_assigned_at = first.assigned_at

    travel 1.hour do
      replacer =
        TaxonomyAssignments::Replace.new(
          sequence: @sequence,
          assignments: [{ "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [term_b.id] }]
        )
      assert replacer.call

      current = TaxonomyAssignment.find_by!(sequence_id: @sequence.id, taxonomy_id: @taxonomy.id)
      assert_equal term_b.id, current.taxonomy_term_id
      assert_equal 1, TaxonomyAssignmentHistory.where(sequence_id: @sequence.id, taxonomy_id: @taxonomy.id).count

      history = TaxonomyAssignmentHistory.find_by!(sequence_id: @sequence.id, taxonomy_id: @taxonomy.id)
      assert_equal @term.id, history.taxonomy_term_id
      assert_equal @term.label, history.label_snapshot
      assert_in_delta first_assigned_at.to_f, history.assigned_at.to_f, 1.0
      assert_in_delta Time.current.to_f, history.ended_at.to_f, 1.0
    end
  end

  test "process taxonomy same term is no-op without history row" do
    @taxonomy.update!(process_tracking: true)

    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @term.id,
      label_snapshot: @term.label,
      single_value_taxonomy_copy: true,
      assigned_at: 1.day.ago
    )

    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [{ "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [@term.id] }]
      )

    assert replacer.call
    assert_equal 0, TaxonomyAssignmentHistory.count
    assert_equal 1, TaxonomyAssignment.where(sequence_id: @sequence.id).count
  end

  test "process taxonomy clear archives and removes current assignment" do
    @taxonomy.update!(process_tracking: true)

    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @term.id,
      label_snapshot: @term.label,
      single_value_taxonomy_copy: true,
      assigned_at: 1.day.ago
    )

    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [{ "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [] }]
      )

    assert replacer.call
    refute TaxonomyAssignment.exists?(sequence_id: @sequence.id, taxonomy_id: @taxonomy.id)
    assert_equal 1, TaxonomyAssignmentHistory.where(sequence_id: @sequence.id, taxonomy_id: @taxonomy.id).count
  end

  test "non-process taxonomy still replaces rows without history" do
    term_b = @taxonomy.taxonomy_terms.create!(label: "Next", position: 2)

    TaxonomyAssignment.create!(
      project_id: @project.id,
      sequence_id: @sequence.id,
      taxonomy_id: @taxonomy.id,
      taxonomy_term_id: @term.id,
      label_snapshot: @term.label,
      single_value_taxonomy_copy: true,
      assigned_at: 1.day.ago
    )

    replacer =
      TaxonomyAssignments::Replace.new(
        sequence: @sequence,
        assignments: [{ "taxonomy_id" => @taxonomy.id, "taxonomy_term_ids" => [term_b.id] }]
      )

    assert replacer.call
    assert_equal 0, TaxonomyAssignmentHistory.count
    current = TaxonomyAssignment.find_by!(sequence_id: @sequence.id, taxonomy_id: @taxonomy.id)
    assert_equal term_b.id, current.taxonomy_term_id
  end
end
