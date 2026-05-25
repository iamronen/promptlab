# frozen_string_literal: true

class StepContent
  class << self
    def trim_trailing_whitespace(content)
      html = content.to_s.strip
      return "" if html.blank?

      fragment = Nokogiri::HTML.fragment(html)
      trim_trailing_whitespace_nodes!(fragment)
      result = fragment.to_html.strip
      result.blank? ? "" : result
    rescue StandardError
      html.strip
    end

    private

    def trim_trailing_whitespace_nodes!(parent)
      loop do
        last = parent.children.last
        break unless last

        if whitespace_only_node?(last)
          last.remove
        else
          trim_trailing_whitespace_nodes!(last) if last.element?
          trim_trailing_text!(last)
          break
        end
      end
    end

    def whitespace_only_node?(node)
      return node.text.gsub(/[\s\u00a0]/, "").empty? if node.text?

      return true if node.name == "br"
      return node.text.gsub(/[\s\u00a0]/, "").empty? if node.element?

      false
    end

    def trim_trailing_text!(node)
      return unless node.text?

      node.content = node.text.sub(/[\s\u00a0]+\z/, "")
    end
  end
end
