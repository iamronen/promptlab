# frozen_string_literal: true

require "test_helper"

class StepContentTest < ActiveSupport::TestCase
  test "trim_trailing_whitespace removes trailing spaces in text" do
    assert_equal "<p>hello</p>", StepContent.trim_trailing_whitespace("<p>hello   </p>")
  end

  test "trim_trailing_whitespace removes trailing empty paragraphs and breaks" do
    assert_equal "<p>hello</p>", StepContent.trim_trailing_whitespace("<p>hello</p><p></p>")
    assert_equal "<p>hello</p>", StepContent.trim_trailing_whitespace("<p>hello<br></p>")
    assert_equal "<p>hello</p>", StepContent.trim_trailing_whitespace("<p>hello</p><br>")
  end

  test "trim_trailing_whitespace preserves meaningful content" do
    assert_equal "<p>hello</p><p>world</p>", StepContent.trim_trailing_whitespace("<p>hello</p><p>world</p>")
  end
end
