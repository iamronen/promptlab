# frozen_string_literal: true

# Member actions on `Sequence` when kind is `thread`: reorder strand steps, insert bundle/sequence, fork child strand.
module ThreadStrandMutations
  extend ActiveSupport::Concern

  def thread_update_steps
    pairs = parse_strand_step_pairs_param
    current = @sequence.strand_step_pairs

    unless reorder_pairs_valid?(current, pairs)
      if workspace_autosave_request?
        head :unprocessable_entity
      else
        redirect_to thread_redirect_url, alert: "Invalid strand order."
      end
      return
    end

    @sequence.steps_data = pairs.map do |kind, sid|
      kind == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid }
    end
    if @sequence.save
      if workspace_autosave_request?
        head :no_content
      else
        redirect_to thread_redirect_url, notice: "Strand order updated."
      end
    elsif workspace_autosave_request?
      render json: { errors: @sequence.errors.full_messages }, status: :unprocessable_entity
    else
      redirect_to thread_redirect_url, alert: @sequence.errors.full_messages.to_sentence.presence || "Could not update order."
    end
  end

  def thread_insert_bundle
    insert = params[:insert].to_s
    anchor_id = params[:relative_to_bundle_id].to_i
    new_bundle = nil

    ActiveRecord::Base.transaction do
      position = @project.sequences.bundles.maximum(:position).to_i + 1
      new_bundle = @project.sequences.create!(
        kind: :bundle,
        title: Sequence::BUNDLE_DEFAULT_TITLE,
        intent: Sequence::BUNDLE_DEFAULT_INTENT,
        position: position,
        steps_data: [],
        is_term: false
      )

      pairs = @sequence.strand_step_pairs.dup

      case insert
      when "end"
        pairs << [:bundle, new_bundle.id]
      when "before"
        idx = pairs.index([:bundle, anchor_id])
        raise ActiveRecord::Rollback unless idx

        pairs.insert(idx, [:bundle, new_bundle.id])
      when "after"
        idx = pairs.index([:bundle, anchor_id])
        raise ActiveRecord::Rollback unless idx

        pairs.insert(idx + 1, [:bundle, new_bundle.id])
      else
        raise ActiveRecord::Rollback
      end

      @sequence.steps_data = pairs.map { |k, sid| k == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid } }
      raise ActiveRecord::Rollback unless @sequence.save
    end

    if new_bundle&.persisted?
      redirect_to thread_redirect_url(focus_bundle_id: new_bundle.id), notice: "Bundle added."
    else
      redirect_to thread_redirect_url,
                  alert: new_bundle&.errors&.full_messages&.to_sentence.presence || "Could not add bundle."
    end
  end

  def thread_insert_sequence
    insert = params[:insert].to_s
    new_seq = nil

    ActiveRecord::Base.transaction do
      scope = @project.sequences.generative_sequences
      position = scope.maximum(:position).to_i + 1
      new_seq = @project.sequences.create!(
        kind: :sequence,
        title: Sequence::DEFAULT_TITLE,
        intent: Sequence::DEFAULT_INTENT,
        position: position,
        steps_data: [{ "content" => "" }],
        is_term: false
      )

      pairs = @sequence.strand_step_pairs.dup

      case insert
      when "end"
        pairs << [:sequence, new_seq.id]
      when "before", "after"
        kind = params[:relative_kind].to_s == "bundle" ? :bundle : :sequence
        anchor_id = params[:relative_to_id].to_i
        token = [kind, anchor_id]
        idx = pairs.index(token)
        raise ActiveRecord::Rollback unless idx

        if insert == "before"
          pairs.insert(idx, [:sequence, new_seq.id])
        else
          pairs.insert(idx + 1, [:sequence, new_seq.id])
        end
      else
        raise ActiveRecord::Rollback
      end

      @sequence.steps_data = pairs.map { |k, sid| k == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid } }
      raise ActiveRecord::Rollback unless @sequence.save
    end

    if new_seq&.persisted?
      redirect_to thread_redirect_url(focus_transformation_id: new_seq.id), notice: "Sequence added."
    else
      redirect_to thread_redirect_url,
                  alert: new_seq&.errors&.full_messages&.to_sentence.presence || "Could not add sequence."
    end
  end

  def thread_duplicate_strand_child_sequence
    source_id = params[:source_sequence_id].to_i
    pairs = @sequence.strand_step_pairs
    idx = pairs.index([:sequence, source_id])
    unless idx
      redirect_to thread_redirect_url, alert: "Sequence is not on this strand."
      return
    end

    src = @project.sequences.generative_sequences.find_by(id: source_id)
    unless src
      redirect_to thread_redirect_url, alert: "Sequence not found."
      return
    end

    copy = nil
    ActiveRecord::Base.transaction do
      position = @project.sequences.generative_sequences.maximum(:position).to_i + 1
      copy = @project.sequences.create!(
        kind: :sequence,
        is_term: src.is_term,
        title: duplicate_sequence_title(src.title),
        intent: src.intent.to_s,
        position: position,
        steps_data: duplicate_steps_data(src.steps_data)
      )
      raise ActiveRecord::Rollback unless copy.persisted?

      new_pairs = pairs.dup
      new_pairs.insert(idx + 1, [:sequence, copy.id])
      @sequence.steps_data =
        new_pairs.map { |k, sid| k == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid } }
      raise ActiveRecord::Rollback unless @sequence.save
    end

    if copy&.persisted?
      redirect_to thread_redirect_url(focus_transformation_id: copy.id), notice: "Sequence duplicated."
    else
      redirect_to thread_redirect_url,
                  alert: copy&.errors&.full_messages&.to_sentence.presence || "Could not duplicate sequence."
    end
  end

  def thread_fork_strand
    anchor_seq_id = params[:parent_generative_sequence_id].to_i
    flat = @sequence.flattened_generative_sequence_ids_on_strand
    unless flat.include?(anchor_seq_id)
      redirect_to thread_redirect_url, alert: "Sequence is not on this strand."
      return
    end

    parent_bundle_id = @sequence.bundle_containing_generative_sequence(anchor_seq_id)

    child_thread = nil
    ActiveRecord::Base.transaction do
      threads_scope = @project.sequences.threads
      position = threads_scope.maximum(:position).to_i + 1
      child_thread = @project.sequences.create!(
        kind: :thread,
        title: Sequence::UNTITLED_THREAD_BRANCH_TITLE,
        intent: Sequence::THREAD_DEFAULT_INTENT,
        position: position,
        steps_data: [],
        is_genesis: false,
        is_orphans: false,
        is_term: false
      )

      sibling_max = ThreadNode.where(parent_thread_id: @sequence.id, parent_generative_sequence_id: anchor_seq_id)
        .maximum(:child_order).to_i

      ThreadNode.create!(
        parent_thread_id: @sequence.id,
        parent_bundle_id: parent_bundle_id,
        parent_generative_sequence_id: anchor_seq_id,
        child_thread_id: child_thread.id,
        child_order: sibling_max + 1
      )
    end

    if child_thread&.persisted?
      redirect_to thread_redirect_url(weave_thread: child_thread.id, thread_partner: @sequence.id),
                  notice: "New strand created."
    else
      redirect_to thread_redirect_url,
                  alert: child_thread&.errors&.full_messages&.to_sentence.presence || "Could not create strand."
    end
  end

  def thread_unbundle_pipeline_sequence
    bundle_id = params[:bundle_id].to_i
    sequence_id = params[:sequence_id].to_i
    if bundle_id <= 0 || sequence_id <= 0
      respond_unbundle_failure("Invalid request.")
      return
    end

    bundle = @project.sequences.bundles.find_by(id: bundle_id)
    gen = @project.sequences.generative_sequences.find_by(id: sequence_id)
    unless bundle && gen
      respond_unbundle_failure("Bundle or sequence not found.")
      return
    end

    thread = @sequence
    pairs = thread.strand_step_pairs
    b_idx = pairs.index([:bundle, bundle.id])
    unless b_idx
      respond_unbundle_failure("Bundle is not on this strand.")
      return
    end

    pipeline_ids = bundle.pipeline_generative_sequence_ids
    unless pipeline_ids.include?(gen.id)
      respond_unbundle_failure("Sequence is not in this bundle.")
      return
    end

    first_in_bundle = pipeline_ids.first == gen.id
    remaining_ids = pipeline_ids.reject { |sid| sid == gen.id }

    new_bundle_steps = Array.wrap(bundle.steps_data).reject do |raw|
      raw.is_a?(Hash) && raw.stringify_keys["sequence_id"].to_i == gen.id
    end

    pairs_work = pairs.dup
    if first_in_bundle
      pairs_work.insert(b_idx, [:sequence, gen.id])
    else
      pairs_work.insert(b_idx + 1, [:sequence, gen.id])
    end

    bundle_idx = pairs_work.index([:bundle, bundle.id])
    unless bundle_idx
      respond_unbundle_failure("Could not update strand.")
      return
    end

    if remaining_ids.empty?
      pairs_work.delete_at(bundle_idx)
    elsif remaining_ids.size == 1
      pairs_work[bundle_idx] = [:sequence, remaining_ids.first]
    end

    unless strand_pairs_referential_integrity?(pairs_work)
      respond_unbundle_failure("Would create a duplicate entry on the strand.")
      return
    end

    ok = false
    err_msg = nil
    ActiveRecord::Base.transaction do
      if remaining_ids.size >= 2
        bundle.steps_data = new_bundle_steps
        unless bundle.save
          err_msg = bundle.errors.full_messages.to_sentence.presence || "Could not update bundle."
          raise ActiveRecord::Rollback
        end
      end

      thread.steps_data =
        pairs_work.map { |k, sid| k == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid } }
      unless thread.save
        err_msg = thread.errors.full_messages.to_sentence.presence || "Could not update strand."
        raise ActiveRecord::Rollback
      end

      if remaining_ids.size < 2
        unless bundle.destroy
          err_msg = bundle.errors.full_messages.to_sentence.presence || "Could not remove bundle."
          raise ActiveRecord::Rollback
        end
      end

      ok = true
    end

    if ok
      extras = { focus_transformation_id: gen.id }
      extras[:focus_bundle_id] = bundle_id if remaining_ids.size >= 2
      if workspace_autosave_request?
        head :no_content
      else
        redirect_to thread_redirect_url(extras), notice: "Sequence removed from bundle."
      end
    else
      respond_unbundle_failure(err_msg || "Could not unbundle.")
    end
  end

  def thread_dissolve_strand_bundle
    bundle_id = params[:bundle_id].to_i
    if bundle_id <= 0
      respond_unbundle_failure("Invalid request.")
      return
    end

    bundle = @project.sequences.bundles.find_by(id: bundle_id)
    thread = @sequence
    pairs = thread.strand_step_pairs
    b_idx = pairs.index([:bundle, bundle_id])

    unless bundle && b_idx
      respond_unbundle_failure("Bundle is not on this strand.")
      return
    end

    pipeline_ids = bundle.pipeline_generative_sequence_ids
    replacement = pipeline_ids.map { |sid| [:sequence, sid] }
    new_pairs = pairs[0...b_idx] + replacement + (pairs[(b_idx + 1)..] || [])

    unless strand_pairs_referential_integrity?(new_pairs)
      respond_unbundle_failure("Would create a duplicate entry on the strand.")
      return
    end

    ok = false
    err_msg = nil
    ActiveRecord::Base.transaction do
      thread.steps_data =
        new_pairs.map { |k, sid| k == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid } }
      unless thread.save
        err_msg = thread.errors.full_messages.to_sentence.presence || "Could not update strand."
        raise ActiveRecord::Rollback
      end

      unless bundle.destroy
        err_msg = bundle.errors.full_messages.to_sentence.presence || "Could not remove bundle."
        raise ActiveRecord::Rollback
      end

      ok = true
    end

    if ok
      extras = {}
      extras[:focus_transformation_id] = pipeline_ids.first if pipeline_ids.any?
      if workspace_autosave_request?
        head :no_content
      else
        redirect_to thread_redirect_url(extras), notice: "Bundle unbundled onto strand."
      end
    else
      respond_unbundle_failure(err_msg || "Could not unbundle.")
    end
  end

  def thread_merge_adjacent_strand_steps
    token_pair = parse_strand_step_token_from_param
    unless token_pair
      respond_merge_failure("Invalid strand step.")
      return
    end

    direction = params[:merge_direction].to_s
    unless %w[previous next].include?(direction)
      respond_merge_failure("Invalid merge direction.")
      return
    end

    pairs = @sequence.strand_step_pairs
    if pairs.size < 2
      respond_merge_failure("Nothing to merge with.")
      return
    end

    focus_idx = pairs.index(token_pair)
    unless focus_idx
      respond_merge_failure("Step is not on this strand.")
      return
    end

    left_idx, left, right =
      if direction == "previous"
        if focus_idx.zero?
          respond_merge_failure("Nothing above to bundle with.")
          return
        end
        [focus_idx - 1, pairs[focus_idx - 1], pairs[focus_idx]]
      else
        if focus_idx >= pairs.size - 1
          respond_merge_failure("Nothing below to bundle with.")
          return
        end
        [focus_idx, pairs[focus_idx], pairs[focus_idx + 1]]
      end

    err_msg = nil
    surviving_bundle_id = nil
    ActiveRecord::Base.transaction do
      surviving_bundle_id, err_msg = apply_adjacent_strand_merge!(@project, @sequence, pairs, left_idx, left, right)
      raise ActiveRecord::Rollback if err_msg.present? || surviving_bundle_id.nil?
    end

    if surviving_bundle_id
      if workspace_autosave_request?
        head :no_content
      else
        redirect_to thread_redirect_url(focus_bundle_id: surviving_bundle_id), notice: "Bundled."
      end
    else
      respond_merge_failure(err_msg || "Could not bundle.")
    end
  end

  private

  def apply_adjacent_strand_merge!(project, thread, pairs, left_idx, left, right)
    suffix = pairs[(left_idx + 2)..] || []
    merged_tuple, absorbed_bundle_id =
      case [left[0], right[0]]
      when [:sequence, :sequence]
        bid = create_bundle_for_two_sequences!(project, left[1], right[1])
        return [nil, "Could not create bundle."] unless bid

        [[:bundle, bid], nil]
      when [:sequence, :bundle]
        ok, err = prepend_sequence_to_bundle_pipeline!(project, right[1], left[1])
        return [nil, err] unless ok

        [[:bundle, right[1]], nil]
      when [:bundle, :sequence]
        ok, err = append_sequence_to_bundle_pipeline!(project, left[1], right[1])
        return [nil, err] unless ok

        [[:bundle, left[1]], nil]
      when [:bundle, :bundle]
        ok, err = merge_two_bundles_on_strand!(project, left[1], right[1])
        return [nil, err] unless ok

        [[:bundle, left[1]], right[1]]
      else
        return [nil, "Unsupported merge."]
      end

    new_pairs = pairs[0...left_idx] + [merged_tuple] + suffix
    unless strand_pairs_referential_integrity?(new_pairs)
      return [nil, "Would create a duplicate entry on the strand."]
    end

    thread.steps_data =
      new_pairs.map { |k, sid| k == :bundle ? { "bundle_id" => sid } : { "sequence_id" => sid } }
    unless thread.save
      return [nil, thread.errors.full_messages.to_sentence.presence || "Could not update strand."]
    end

    if absorbed_bundle_id
      doomed = project.sequences.bundles.find_by(id: absorbed_bundle_id)
      if doomed && !doomed.destroy
        return [nil, doomed.errors.full_messages.to_sentence.presence || "Could not remove merged bundle."]
      end
    end

    [merged_tuple[1], nil]
  end

  def create_bundle_for_two_sequences!(project, seq_a_id, seq_b_id)
    gen_a = project.sequences.generative_sequences.find_by(id: seq_a_id)
    gen_b = project.sequences.generative_sequences.find_by(id: seq_b_id)
    return nil unless gen_a && gen_b

    position = project.sequences.bundles.maximum(:position).to_i + 1
    bundle = project.sequences.create!(
      kind: :bundle,
      title: Sequence::BUNDLE_DEFAULT_TITLE,
      intent: Sequence::BUNDLE_DEFAULT_INTENT,
      position: position,
      steps_data: [{ "sequence_id" => seq_a_id }, { "sequence_id" => seq_b_id }],
      is_term: false
    )
    bundle.id
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def prepend_sequence_to_bundle_pipeline!(project, bundle_id, sequence_id)
    bundle = project.sequences.bundles.find_by(id: bundle_id)
    gen = project.sequences.generative_sequences.find_by(id: sequence_id)
    return [false, "Bundle or sequence not found."] unless bundle && gen

    ids = bundle.pipeline_generative_sequence_ids
    return [false, "Sequence is already in this bundle."] if ids.include?(sequence_id)

    new_ids = [sequence_id] + ids
    bundle.steps_data = new_ids.map { |sid| { "sequence_id" => sid } }
    bundle.save ? [true, nil] : [false, bundle.errors.full_messages.to_sentence.presence || "Could not update bundle."]
  end

  def append_sequence_to_bundle_pipeline!(project, bundle_id, sequence_id)
    bundle = project.sequences.bundles.find_by(id: bundle_id)
    gen = project.sequences.generative_sequences.find_by(id: sequence_id)
    return [false, "Bundle or sequence not found."] unless bundle && gen

    ids = bundle.pipeline_generative_sequence_ids
    return [false, "Sequence is already in this bundle."] if ids.include?(sequence_id)

    new_ids = ids + [sequence_id]
    bundle.steps_data = new_ids.map { |sid| { "sequence_id" => sid } }
    bundle.save ? [true, nil] : [false, bundle.errors.full_messages.to_sentence.presence || "Could not update bundle."]
  end

  def merge_two_bundles_on_strand!(project, bundle_a_id, bundle_b_id)
    a = project.sequences.bundles.find_by(id: bundle_a_id)
    b = project.sequences.bundles.find_by(id: bundle_b_id)
    return [false, "Bundle not found."] unless a && b

    ThreadNode.where(parent_bundle_id: b.id).update_all(parent_bundle_id: a.id)

    merged_ids = a.pipeline_generative_sequence_ids + b.pipeline_generative_sequence_ids
    a.steps_data = merged_ids.map { |sid| { "sequence_id" => sid } }
    unless a.save
      return [false, a.errors.full_messages.to_sentence.presence || "Could not update bundle."]
    end

    prereqs = (a.prerequisite_bundle_ids + b.prerequisite_bundle_ids).uniq - [a.id, b.id]
    unless a.sync_prerequisite_dependencies!(prereqs)
      return [false, a.errors.full_messages.to_sentence.presence || "Could not merge prerequisites."]
    end

    [true, nil]
  end

  def parse_strand_step_token_from_param
    token = params[:strand_step_token].to_s
    m = token.match(/\A([bs]):(\d+)\z/)
    return nil unless m

    kind = m[1] == "s" ? :sequence : :bundle
    id = m[2].to_i
    return nil if id <= 0

    [kind, id]
  end

  def respond_merge_failure(message)
    if workspace_autosave_request?
      head :unprocessable_entity
    else
      redirect_to thread_redirect_url, alert: message
    end
  end

  def set_thread_sequence
    @sequence = @project.sequences.threads.find_by(id: params[:id])
    return if @sequence

    redirect_to open_project_path(@project, **workspace_shell_redirect_fragment), alert: "Thread not found."
    nil
  end

  # Accepts strand_step_tokens[] as "b:1" / "s:2", or strand_steps as JSON pairs, or legacy bundle_ids.
  def parse_strand_step_pairs_param
    raw = params[:strand_step_tokens]
    if raw.is_a?(Array) && raw.any?
      return raw.filter_map do |token|
        m = token.to_s.match(/\A([bs]):(\d+)\z/)
        next unless m

        kind = m[1] == "s" ? :sequence : :bundle
        id = m[2].to_i
        next if id <= 0

        [kind, id]
      end
    end

    raw = params[:strand_steps]
    if raw.is_a?(Array) && raw.any?
      return raw.filter_map do |row|
        next unless row.is_a?(Array) && row.size == 2

        kind = row[0].to_s == "sequence" ? :sequence : :bundle
        id = row[1].to_i
        next if id <= 0

        [kind, id]
      end
    end

    parse_legacy_bundle_ids_param
  end

  def parse_legacy_bundle_ids_param
    raw = params[:bundle_ids] || params[:transformation_ids]
    Array(raw).map(&:to_i).reject { |n| n <= 0 }.map { |id| [:bundle, id] }
  end

  def reorder_pairs_valid?(current, next_pairs)
    return false if current.length != next_pairs.length
    return false if next_pairs.length != next_pairs.uniq { |k, id| [k, id] }.length

    current.sort_by { |k, id| [k.to_s, id] } == next_pairs.sort_by { |k, id| [k.to_s, id] }
  end

  def thread_redirect_url(extra = {})
    merged = workspace_editor_redirect_options.merge(extra.compact)
    ref = params[:redirect_to].to_s
    if ref.start_with?("/") && !ref.include?("..")
      return merge_query_for_url("#{request.protocol}#{request.host_with_port}#{ref}", merged)
    end

    ref_url = request.headers["Referer"].presence
    if ref_url.present?
      begin
        uri = URI.parse(ref_url)
        if uri.host == request.host || uri.relative?
          return merge_query_for_url(ref_url, merged)
        end
      rescue URI::InvalidURIError
        nil
      end
    end

    merge_query_for_url(open_project_path(@project), merged)
  end

  def merge_query_for_url(url, extra)
    uri = URI.parse(url)
    q = Rack::Utils.parse_nested_query(uri.query.to_s)
    extra.each do |k, v|
      next if v.nil?

      q[k.to_s] = v.to_s
    end
    uri.query = q.to_query.presence
    uri.to_s
  end

  def respond_unbundle_failure(message)
    if workspace_autosave_request?
      head :unprocessable_entity
    else
      redirect_to thread_redirect_url, alert: message
    end
  end

  def strand_pairs_referential_integrity?(pairs)
    seq_ids = pairs.filter_map { |k, id| id if k == :sequence }
    return false if seq_ids.size != seq_ids.uniq.size

    bundle_ids = pairs.filter_map { |k, id| id if k == :bundle }
    bundle_ids.size == bundle_ids.uniq.size
  end
end
