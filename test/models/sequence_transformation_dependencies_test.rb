# frozen_string_literal: true

require "test_helper"

class SequenceTransformationDependenciesTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "P")
    @gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "i",
      position: 1,
      steps_data: [{ "content" => "x" }],
      is_term: false
    )
    @trans = @project.sequences.create!(
      kind: :transformation,
      title: "T",
      intent: "ti",
      position: 1,
      steps_data: [],
      is_term: false
    )
  end

  test "sync sequence_step rows after transformation steps_data update" do
    @trans.update!(steps_data: [{ "sequence_id" => @gen.id }])
    deps = SequenceDependency.where(parent_id: @trans.id, kind: :sequence_step)
    assert_equal 1, deps.count
    assert_equal @gen.id, deps.first.child_id
    assert_equal 1, deps.first.position
  end

  test "destroy generative sequence removes pipeline reference from transformation" do
    @trans.update!(steps_data: [{ "sequence_id" => @gen.id }])
    assert_equal 1, SequenceDependency.where(parent_id: @trans.id, kind: :sequence_step).count

    @gen.destroy!

    @trans.reload
    assert_equal [], @trans.steps_data
    assert_empty SequenceDependency.where(parent_id: @trans.id, kind: :sequence_step)
  end

  test "normalizes transformation steps_data dedupes sequence ids" do
    @trans.assign_attributes(
      steps_data: [
        { "sequence_id" => @gen.id },
        { "sequence_id" => @gen.id }
      ]
    )
    @trans.valid?
    assert_equal 1, @trans.steps_data.size
  end

  test "sync_prerequisite_dependencies replaces edges" do
    t2 = @project.sequences.create!(
      kind: :transformation,
      title: "T2",
      intent: "i2",
      position: 2,
      steps_data: [],
      is_term: false
    )
    assert @trans.sync_prerequisite_dependencies!([t2.id])
    assert_equal [t2.id], @trans.prerequisite_transformation_ids.sort
  end

  test "sync_prerequisite_dependencies rejects cycle" do
    t2 = @project.sequences.create!(
      kind: :transformation,
      title: "T2",
      intent: "i2",
      position: 2,
      steps_data: [],
      is_term: false
    )
    assert t2.sync_prerequisite_dependencies!([@trans.id])

    assert_not @trans.sync_prerequisite_dependencies!([t2.id])
    assert @trans.errors[:base].any? { |m| m.include?("cycle") }
  end
end
