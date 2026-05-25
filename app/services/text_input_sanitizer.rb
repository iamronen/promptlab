# frozen_string_literal: true

class TextInputSanitizer
  TRAILING_WHITESPACE_PATTERN = /[\s\u00a0]+\z/

  class << self
    def trim_trailing(value)
      value.to_s.sub(TRAILING_WHITESPACE_PATTERN, "")
    end
  end
end
