# frozen_string_literal: true

require "test_helper"

class SequenceTextFieldsTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @project = Project.create!(name: "Text fields project", user: @user)
  end

  teardown do
    Current.reset
  end

  test "save trims trailing whitespace from title and intent" do
    sequence = @project.sequences.create!(
      kind: :sequence,
      title: "My sequence   ",
      intent: "One clear intent.\n\n",
      position: 1,
      steps_data: [{ "content" => "" }],
      is_term: false
    )

    assert_equal "My sequence", sequence.title
    assert_equal "One clear intent.", sequence.intent
  end
end
