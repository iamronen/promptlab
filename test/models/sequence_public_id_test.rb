# frozen_string_literal: true

require "test_helper"

class SequencePublicIdTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    Current.user = @user
    @project = Project.create!(name: "Public ID project", user: @user)
  end

  test "assigns public_id on create" do
    sequence = @project.sequences.create!(
      kind: :sequence,
      title: "Test",
      intent: "Intent",
      position: 1,
      steps_data: [{ "content" => "" }]
    )

    assert sequence.public_id.present?
    assert_match(/\A[A-Za-z0-9_-]+\z/, sequence.public_id)
    assert_operator sequence.public_id.length, :>=, 20
  end

  test "public_id is globally unique" do
    first = @project.sequences.create!(
      kind: :sequence,
      title: "One",
      intent: "Intent",
      position: 1,
      steps_data: [{ "content" => "" }]
    )
    other_project = Project.create!(name: "Other", user: @user)
    second = other_project.sequences.create!(
      kind: :sequence,
      title: "Two",
      intent: "Intent",
      position: 1,
      steps_data: [{ "content" => "" }]
    )

    assert_not_equal first.public_id, second.public_id
  end

  test "to_param returns public_id" do
    sequence = @project.sequences.create!(
      kind: :sequence,
      title: "Test",
      intent: "Intent",
      position: 1,
      steps_data: [{ "content" => "" }]
    )

    assert_equal sequence.public_id, sequence.to_param
  end

  test "find_by_public_id! locates sequence" do
    sequence = @project.sequences.create!(
      kind: :sequence,
      title: "Test",
      intent: "Intent",
      position: 1,
      steps_data: [{ "content" => "" }]
    )

    found = Sequence.find_by_public_id!(sequence.public_id)
    assert_equal sequence.id, found.id
  end

  test "thread step row exposes public strand token" do
    thread = @project.genesis_thread
    gen = @project.sequences.generative_sequences.create!(
      title: "Gen",
      intent: "Intent",
      position: 1,
      steps_data: [{ "content" => "x" }]
    )
    thread.update!(steps_data: [{ "sequence_id" => gen.id }])

    row = thread.ordered_steps.first
    assert_equal "s:#{gen.public_id}", row.step_key
  end
end
