# frozen_string_literal: true

require "test_helper"

class SequenceDependencyTest < ActiveSupport::TestCase
  setup do
    @project = Project.create!(name: "Proj")
    @gen = @project.sequences.create!(
      kind: :sequence,
      title: "Gen",
      intent: "g",
      position: 1,
      steps_data: [{ "content" => "a" }],
      is_term: false
    )
    @t1 = @project.sequences.create!(
      kind: :transformation,
      title: "T1",
      intent: "t1",
      position: 1,
      steps_data: [],
      is_term: false
    )
    @t2 = @project.sequences.create!(
      kind: :transformation,
      title: "T2",
      intent: "t2",
      position: 2,
      steps_data: [],
      is_term: false
    )
  end

  test "sequence_step requires transformation parent and generative child" do
    dep = SequenceDependency.new(parent: @gen, child: @gen, kind: :sequence_step, position: 1)
    assert_not dep.valid?

    dep = SequenceDependency.new(parent: @t1, child: @gen, kind: :sequence_step, position: 1)
    assert dep.valid?
  end

  test "transformation_prerequisite requires both transformations" do
    dep = SequenceDependency.new(parent: @t1, child: @gen, kind: :transformation_prerequisite)
    assert_not dep.valid?

    dep = SequenceDependency.new(parent: @t1, child: @t2, kind: :transformation_prerequisite)
    assert dep.valid?
  end

  test "transformation_prerequisite rejects cycle on create" do
    SequenceDependency.create!(parent: @t2, child: @t1, kind: :transformation_prerequisite)

    dep = SequenceDependency.new(parent: @t1, child: @t2, kind: :transformation_prerequisite)
    assert_not dep.valid?
    assert dep.errors[:base].any? { |m| m.include?("cycle") }
  end
end
