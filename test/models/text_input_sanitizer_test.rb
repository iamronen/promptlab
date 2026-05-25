# frozen_string_literal: true

require "test_helper"

class TextInputSanitizerTest < ActiveSupport::TestCase
  test "trim_trailing removes trailing spaces and newlines" do
    assert_equal "hello", TextInputSanitizer.trim_trailing("hello   ")
    assert_equal "hello", TextInputSanitizer.trim_trailing("hello\n\n")
    assert_equal "  hello", TextInputSanitizer.trim_trailing("  hello  ")
  end

  test "trim_trailing preserves empty strings" do
    assert_equal "", TextInputSanitizer.trim_trailing("")
    assert_equal "", TextInputSanitizer.trim_trailing("   ")
  end
end
