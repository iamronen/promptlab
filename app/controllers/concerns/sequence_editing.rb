module SequenceEditing
  extend ActiveSupport::Concern

  private

  def ensure_steps_placeholder
    return if @sequence.steps_data.is_a?(Array) && @sequence.steps_data.any?

    @sequence.steps_data = [{ "content" => "" }]
  end

  def assign_sequence_attributes
    attrs = sequence_params.to_h
    if @sequence.thread?
      @sequence.title = attrs["title"] if attrs.key?("title")
      @sequence.intent = attrs["intent"] if attrs.key?("intent")
      return
    end

    @sequence.title = attrs["title"] if attrs.key?("title")
    @sequence.intent = attrs["intent"] if attrs.key?("intent")
    return unless attrs["steps_attributes"].present?

    @sequence.steps_data = steps_payload_from_params(attrs)
  end

  # Builds generative sequence steps_data hashes from nested steps_attributes-style params.
  def build_generative_steps_data(steps_attributes_raw)
    steps_attrs =
      case steps_attributes_raw
      when ActionController::Parameters
        steps_attributes_raw.to_unsafe_h
      when Hash
        steps_attributes_raw
      else
        {}
      end
    rows = steps_attrs.values
    remaining = rows.reject do |s|
      h = step_attributes_row_hash(s)
      next true unless h

      dv = h["_destroy"] || h[:_destroy]
      ActiveModel::Type::Boolean.new.cast(dv)
    end
    sorted = remaining.sort_by do |s|
      h = step_attributes_row_hash(s)
      pos = h ? (h["position"] || h[:position]) : nil
      pos.to_i
    end
    sorted.map do |s|
      h = step_attributes_row_hash(s)
      content = h ? (h["content"] || h[:content]) : nil
      { "content" => StepContent.trim_trailing_whitespace(content.to_s) }
    end
  end

  # Permitted nested steps arrive as ActionController::Parameters, which is not a Hash in Rails 8+.
  def step_attributes_row_hash(raw)
    case raw
    when ActionController::Parameters
      raw.to_unsafe_h
    when Hash
      raw
    end
  end

  def steps_payload_from_params(attrs)
    raw = attrs["steps_attributes"] || attrs[:steps_attributes]
    build_generative_steps_data(raw)
  end

  def duplicate_steps_data(data)
    rows = Array.wrap(data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      { "content" => raw.stringify_keys.fetch("content", "").to_s }
    end
    rows.presence || [{ "content" => "" }]
  end

  def duplicate_sequence_title(title, default_title: Sequence::DEFAULT_TITLE)
    base = title.to_s.strip.presence || default_title
    "#{base} (copy)"
  end

  def sequence_params
    seq = params.require(:sequence)
    permitted = seq.permit(:title, :intent)
    nested = {}
    seq[:steps_attributes]&.each_pair do |key, attrs|
      next unless attrs.respond_to?(:permit)

      nested[key] = attrs.permit(:content, :position, :_destroy)
    end
    permitted[:steps_attributes] = nested unless nested.empty?

    permitted
  end
end
