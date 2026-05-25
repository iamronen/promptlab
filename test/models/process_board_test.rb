# frozen_string_literal: true

require "test_helper"

class ProcessBoardTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Process board", user: users(:alice))
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
    @todo = @taxonomy.taxonomy_terms.create!(label: "Todo", position: 2)
    @doing = @taxonomy.taxonomy_terms.create!(label: "Doing", position: 1)
    @seq =
      @project.sequences.create!(
        kind: :sequence,
        title: "Alpha",
        intent: "i",
        position: 1,
        steps_data: [{ "content" => "x" }],
        is_term: false
      )
    @board = ProcessBoard.new(@project)
  end

  test "ready when default process taxonomy exists" do
    assert @board.ready?
    assert_equal "Stage", @board.taxonomy_name
  end

  test "not ready without default process taxonomy" do
    @taxonomy.update!(process_tracking: false)
    @project.reload

    assert_not ProcessBoard.new(@project).ready?
    assert_empty ProcessBoard.new(@project).columns
  end

  test "columns follow term position order then unassigned" do
    assert_equal ["Doing", "Todo", ProcessBoard::UNASSIGNED_LABEL], @board.columns.map(&:label)
  end

  test "places assigned sequence in term column" do
    TaxonomyAssignment.create!(
      project: @project,
      sequence: @seq,
      taxonomy: @taxonomy,
      taxonomy_term: @doing,
      label_snapshot: @doing.label,
      assigned_at: Time.current
    )

    doing_column = @board.columns.find { |c| c.label == "Doing" }
    assert_equal [@seq.id], doing_column.cards.map { |c| c.sequence.id }
  end

  test "places unassigned sequence in unassigned column" do
    unassigned = @board.columns.last
    assert_equal ProcessBoard::UNASSIGNED_LABEL, unassigned.label
    assert_equal [@seq.id], unassigned.cards.map { |c| c.sequence.id }
  end

  test "includes bundle when taxonomy applies to bundles" do
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "Pipeline",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )
    TaxonomyAssignment.create!(
      project: @project,
      sequence: bundle,
      taxonomy: @taxonomy,
      taxonomy_term: @todo,
      label_snapshot: @todo.label,
      assigned_at: Time.current
    )

    todo_column = @board.columns.find { |c| c.label == "Todo" }
    assert_includes todo_column.cards.map { |c| c.sequence.id }, bundle.id
  end

  test "excludes bundle when taxonomy does not apply to bundles" do
    @taxonomy.update!(applies_to_bundles: false)
    bundle =
      @project.sequences.create!(
        kind: :bundle,
        title: "Pipeline",
        intent: "i",
        position: 1,
        steps_data: [],
        is_term: false
      )

    all_ids = @board.columns.flat_map { |c| c.cards.map { |card| card.sequence.id } }
    assert_not_includes all_ids, bundle.id
  end

  test "excludes term sequences" do
    term =
      @project.sequences.create!(
        kind: :sequence,
        title: "Term",
        intent: "i",
        position: 2,
        steps_data: [{ "content" => "t" }],
        is_term: true
      )

    all_ids = @board.columns.flat_map { |c| c.cards.map { |card| card.sequence.id } }
    assert_not_includes all_ids, term.id
  end

  test "sorts cards by position then id within column" do
    beta =
      @project.sequences.create!(
        kind: :sequence,
        title: "Beta",
        intent: "i",
        position: 2,
        steps_data: [{ "content" => "y" }],
        is_term: false
      )
    [@seq, beta].each do |sequence|
      TaxonomyAssignment.create!(
        project: @project,
        sequence: sequence,
        taxonomy: @taxonomy,
        taxonomy_term: @doing,
        label_snapshot: @doing.label,
        assigned_at: Time.current
      )
    end

    doing_column = @board.columns.find { |c| c.label == "Doing" }
    assert_equal [@seq.id, beta.id], doing_column.cards.map { |c| c.sequence.id }
  end
end
