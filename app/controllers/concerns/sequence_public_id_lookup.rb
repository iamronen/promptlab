# frozen_string_literal: true

module SequencePublicIdLookup
  extend ActiveSupport::Concern

  STRAND_STEP_TOKEN_PATTERN = /\A([bs]):([A-Za-z0-9_-]+)\z/

  private

  def sequence_public_id_memo
    @_sequence_by_public_id ||= {}
  end

  def sequence_scope_cache_key(scope)
    scope.klass.name
  end

  def memo_sequence_key(scope, public_id)
    [sequence_scope_cache_key(scope), parse_sequence_public_id(public_id)]
  end

  def memoized_sequence(scope, public_id)
    pid = parse_sequence_public_id(public_id)
    return nil unless pid

    key = memo_sequence_key(scope, pid)
    if sequence_public_id_memo.key?(key)
      record = sequence_public_id_memo[key]
      return nil if record.nil? || record.destroyed?

      return record
    end

    record = scope.find_by(public_id: pid)
    sequence_public_id_memo[key] = record
    record
  end

  def find_project_sequence_by_public_id!(scope, public_id)
    record = find_project_sequence_by_public_id(scope, public_id)
    raise ActiveRecord::RecordNotFound unless record

    record
  end

  def parse_sequence_public_id(raw)
    raw.to_s.strip.presence
  end

  def preload_sequence_public_ids!(scope, ids)
    parsed = Array(ids).filter_map { |id| parse_sequence_public_id(id) }.uniq
    return if parsed.empty?

    missing = parsed.reject do |pid|
      sequence_public_id_memo.key?(memo_sequence_key(scope, pid))
    end
    return if missing.empty?

    scope.where(public_id: missing).find_each do |record|
      sequence_public_id_memo[memo_sequence_key(scope, record.public_id)] = record
    end

    missing.each do |pid|
      key = memo_sequence_key(scope, pid)
      sequence_public_id_memo[key] = nil unless sequence_public_id_memo.key?(key)
    end
  end

  def preload_thread_public_ids!(ids)
    preload_sequence_public_ids!(@project.sequences.threads, ids)
  end

  def filter_valid_thread_public_ids(ids)
    parsed = Array(ids).filter_map { |pid| parse_sequence_public_id(pid) }.uniq
    preload_thread_public_ids!(parsed)
    parsed.select { |pid| thread_public_id_exists?(pid) }
  end

  def resolve_thread_public_ids(raw_csv)
    filter_valid_thread_public_ids(
      raw_csv.to_s.split(",").filter_map { |pid| parse_sequence_public_id(pid) }
    )
  end

  def find_project_thread_by_public_id(public_id)
    find_project_sequence_by_public_id(@project.sequences.threads, public_id)
  end

  def find_project_sequence_by_public_id(scope, public_id)
    memoized_sequence(scope, public_id)
  end

  def thread_public_id_exists?(public_id)
    find_project_thread_by_public_id(public_id).present?
  end

  def sequence_public_id_exists?(scope, public_id)
    find_project_sequence_by_public_id(scope, public_id).present?
  end

  def resolve_generative_sequence_id_from_param(raw)
    find_project_sequence_by_public_id(@project.sequences.generative_sequences, raw)&.id
  end

  def resolve_bundle_id_from_param(raw)
    find_project_sequence_by_public_id(@project.sequences.bundles, raw)&.id
  end

  def resolve_thread_id_from_param(raw)
    find_project_thread_by_public_id(raw)&.id
  end

  def parse_strand_step_public_id_token(token)
    m = token.to_s.match(STRAND_STEP_TOKEN_PATTERN)
    return nil unless m

    kind = m[1] == "s" ? :sequence : :bundle
    public_id = m[2]
    return nil if public_id.blank?

    scope = kind == :sequence ? @project.sequences.generative_sequences : @project.sequences.bundles
    record = find_project_sequence_by_public_id(scope, public_id)
    return nil unless record

    [kind, record.id]
  end

  def parse_strand_step_token_from_public_id_param
    parse_strand_step_public_id_token(params[:strand_step_token])
  end

  def parse_strand_step_pairs_from_public_id_param
    raw = params[:strand_step_tokens]
    if raw.is_a?(Array) && raw.any?
      return raw.filter_map { |token| parse_strand_step_public_id_token(token) }
    end

    raw = params[:strand_steps]
    if raw.is_a?(Array) && raw.any?
      return raw.filter_map do |row|
        next unless row.is_a?(Array) && row.size == 2

        kind = row[0].to_s == "sequence" ? :sequence : :bundle
        public_id = parse_sequence_public_id(row[1])
        next unless public_id

        scope = kind == :sequence ? @project.sequences.generative_sequences : @project.sequences.bundles
        record = find_project_sequence_by_public_id(scope, public_id)
        next unless record

        [kind, record.id]
      end
    end

    parse_legacy_bundle_public_ids_param
  end

  def parse_legacy_bundle_public_ids_param
    raw = params[:bundle_ids] || params[:transformation_ids]
    Array(raw).filter_map do |value|
      bundle = find_project_sequence_by_public_id(@project.sequences.bundles, value)
      next unless bundle

      [:bundle, bundle.id]
    end
  end

  def thread_public_id_for(record)
    record&.public_id
  end

  def thread_public_id_for_id(thread_id)
    return nil unless thread_id.to_i.positive?

    @project.sequences.threads.find_by(id: thread_id)&.public_id
  end
end
