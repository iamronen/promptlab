class SequencesController < ApplicationController
  include SequenceEditing
  include WorkspaceSidebarData
  include ThreadStrandMutations
  include ProjectNested
  include SequencePublicIdLookup

  before_action :set_project
  before_action :set_sidebar_sequences, only: %i[edit update duplicate add_to_terms remove_from_terms]
  before_action :set_sequence, only: %i[edit update destroy duplicate add_to_terms remove_from_terms]
  before_action :set_thread_sequence,
                only: %i[
                  thread_update_steps
                  thread_insert_bundle
                  thread_insert_sequence
                  thread_fork_strand
                  thread_duplicate_strand_child_sequence
                  thread_unbundle_pipeline_sequence
                  thread_dissolve_strand_bundle
                  thread_merge_adjacent_strand_steps
                  thread_move_sequence_to_thread
                  thread_move_bundle_to_thread
                  thread_attach_branch_thread
                ]

  def edit
    if legacy_workspace_mode_redirect? && !sequence_modal_request?
      return redirect_to edit_project_sequence_path(@project, @sequence, **legacy_workspace_mode_redirect_options),
                        status: :see_other
    end

    ensure_steps_placeholder
    @strand_thread_chip_parent = ActiveModel::Type::Boolean.new.cast(params.fetch(:strand_thread_chip_parent, false))
    if sequence_modal_request?
      @sequence_modal_frame_id = modal_sequence_frame_id_from_request
      return render(:modal_body, layout: false)
    end
    if fabric_thread_panel_frame_request?
      return render partial: "sequences/fabric_thread_panel",
                    locals: fabric_thread_panel_locals,
                    layout: false
    end
  end

  def create
    wants_term = create_wants_term?
    scope = @project.sequences.generative_sequences
    position = scope.maximum(:position).to_i + 1
    sequence = @project.sequences.create!(
      kind: :sequence,
      title: Sequence::DEFAULT_TITLE,
      intent: Sequence::DEFAULT_INTENT,
      position: position,
      steps_data: [{ "content" => "" }],
      is_term: wants_term
    )

    opts = { sidebar: (wants_term ? "terms" : "sequences") }
    wt = parse_sequence_public_id(params[:weave_thread])
    opts[:weave_thread] = wt if wt.present? && thread_public_id_exists?(wt)
    ot = params[:open_threads].to_s.strip
    if ot.present?
      kept = resolve_thread_public_ids(ot)
      opts[:open_threads] = kept.join(",") if kept.any?
    end
    wm = workspace_mode_param
    opts[:workspace_mode] = wm if wm.present?

    redirect_to edit_project_sequence_path(@project, sequence, **opts),
                notice: wants_term ? "Term created." : "Sequence created."
  rescue ActiveRecord::RecordInvalid
    redirect_to open_project_path(@project),
                alert: wants_term ? "Could not create term." : "Could not create sequence."
  end

  def update
    assign_sequence_attributes

    if @sequence.save
      if workspace_autosave_request?
        render json: { sequence_id: @sequence.public_id, title: @sequence.title.to_s }, status: :ok
      elsif safe_workspace_editor_redirect?(params[:redirect_to])
        redirect_to params[:redirect_to].to_s, notice: "Sequence updated."
      else
        redirect_to edit_project_sequence_path(@project, @sequence, **workspace_editor_redirect_options),
                    notice: "Sequence updated."
      end
    elsif workspace_autosave_request?
      render json: { errors: @sequence.errors.full_messages }, status: :unprocessable_entity
    elsif sequence_modal_submission_via_redirect?
      @sequence_modal_frame_id = modal_sequence_frame_id_from_request
      @strand_thread_chip_parent = ActiveModel::Type::Boolean.new.cast(params.fetch(:strand_thread_chip_parent, false))
      render :modal_body, layout: false, status: :unprocessable_entity
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    deleted_sequence_id = @sequence.id
    deleted_sequence_public_id = @sequence.public_id
    was_thread = @sequence.thread?

    if @sequence.destroy
      if was_thread
        redirect_after_thread_workspace_thread_destroy(deleted_sequence_id, deleted_sequence_public_id)
      elsif safe_workspace_editor_redirect?(params[:redirect_to])
        redirect_to redirect_url_after_generative_sequence_destroy(deleted_sequence_public_id),
                    notice: "Sequence deleted."
      else
        redirect_after_generative_sequence_destroy(deleted_sequence_id)
      end
    else
      redirect_to edit_project_sequence_path(@project, @sequence, **workspace_editor_redirect_options),
                  alert:
                    @sequence.errors.full_messages.to_sentence.presence ||
                      "Could not delete sequence."
    end
  end

  def duplicate
    scope = @project.sequences.generative_sequences
    position = scope.maximum(:position).to_i + 1
    copy = @project.sequences.create!(
      kind: :sequence,
      is_term: @sequence.is_term,
      title: duplicate_sequence_title(@sequence.title),
      intent: @sequence.intent.to_s,
      position: position,
      steps_data: duplicate_steps_data(@sequence.steps_data)
    )
    redirect_to edit_project_sequence_path(@project, copy, **workspace_editor_redirect_options),
                notice: "Sequence duplicated."
  rescue ActiveRecord::RecordInvalid
    redirect_to edit_project_sequence_path(@project, @sequence, **workspace_editor_redirect_options),
                alert: "Could not duplicate sequence."
  end

  def add_to_terms
    if @sequence.update(is_term: true)
      redirect_to edit_project_sequence_path(@project, @sequence, **workspace_editor_redirect_options.merge(sidebar: "terms")),
                  notice: "Added to terms."
    else
      redirect_to edit_project_sequence_path(@project, @sequence, **workspace_editor_redirect_options),
                  alert: @sequence.errors.full_messages.to_sentence.presence || "Could not add to terms."
    end
  end

  def remove_from_terms
    if @sequence.update(is_term: false)
      redirect_to edit_project_sequence_path(@project, @sequence, **workspace_editor_redirect_options.merge(sidebar: "sequences")),
                  notice: "Removed from terms."
    else
      redirect_to edit_project_sequence_path(@project, @sequence, **workspace_editor_redirect_options),
                  alert: @sequence.errors.full_messages.to_sentence.presence || "Could not remove from terms."
    end
  end

  private

  def sequence_modal_request?
    turbo_frame_id = turbo_frame_header

    return true if turbo_frame_id.match?(/\Athread_editor_sequence_\d+\z/)

    return false unless ActiveModel::Type::Boolean.new.cast(params[:modal])

    # modal=1 is used when the Turbo-Frame header is missing (some environments strip it). Full
    # browser navigations (e.g. open in new tab) should still get the normal workspace page.
    dest = request.headers["Sec-Fetch-Dest"].to_s
    mode = request.headers["Sec-Fetch-Mode"].to_s
    !(dest == "document" && mode == "navigate")
  end

  def modal_sequence_frame_id_from_request
    id = turbo_frame_header
    return id if id.match?(/\Athread_editor_sequence_\d+\z/)

    "thread_editor_sequence_#{params[:id]}"
  end

  def sequence_modal_submission_via_redirect?
    safe_workspace_editor_redirect?(params[:redirect_to])
  end

  def set_sequence
    @sequence =
      if %w[edit update destroy].include?(action_name)
        record = find_project_sequence_by_public_id!(@project.sequences.includes(:created_by), params[:id])
        raise ActiveRecord::RecordNotFound unless record.sequence? || record.thread?

        record
      else
        find_project_sequence_by_public_id!(@project.sequences.generative_sequences.includes(:created_by), params[:id])
      end
  end

  def create_wants_term?
    ActiveModel::Type::Boolean.new.cast(params.dig(:sequence, :is_term))
  end

  def redirect_after_generative_sequence_destroy(deleted_sequence_id)
    redirect_to generative_sequence_destroy_fallback_url(deleted_sequence_id),
                notice: "Sequence deleted."
  end

  def redirect_url_after_generative_sequence_destroy(deleted_sequence_public_id)
    ref = params[:redirect_to].to_s
    base = "#{request.protocol}#{request.host_with_port}#{ref}"
    uri = URI.parse(base)

    if uri.path == edit_project_sequence_path(@project, deleted_sequence_public_id)
      return generative_sequence_destroy_fallback_url(deleted_sequence_public_id)
    end

    extras = {}
    q = Rack::Utils.parse_nested_query(uri.query.to_s)
    focus_id = parse_sequence_public_id(q["focus_transformation_id"])
    focus_id = parse_sequence_public_id(params[:focus_transformation_id]) if focus_id.blank?
    extras[:focus_transformation_id] = nil if focus_id == deleted_sequence_public_id

    merge_query_for_url(base, extras)
  end

  def generative_sequence_destroy_fallback_url(deleted_sequence_public_id)
    opts = workspace_editor_redirect_options
    if parse_sequence_public_id(opts[:focus_transformation_id]) == deleted_sequence_public_id
      opts = opts.except(:focus_transformation_id)
    end

    next_seq = @project.sequences.generative_sequences.order(:position).first
    if next_seq
      edit_project_sequence_path(@project, next_seq, **opts)
    else
      open_project_path(@project)
    end
  end

  def redirect_after_thread_workspace_thread_destroy(deleted_thread_id, deleted_thread_public_id = nil)
    base_url = thread_destroy_redirect_base_full_url
    extras = thread_destroy_redirect_query_overrides(deleted_thread_id, deleted_thread_public_id)
    redirect_to merge_query_for_url(base_url, extras), notice: "Thread deleted."
  end

  def thread_destroy_redirect_base_full_url
    rt = params[:redirect_to].to_s
    if rt.start_with?("/") && !rt.include?("..")
      return "#{request.protocol}#{request.host_with_port}#{rt}"
    end

    ref_url = request.headers["Referer"].presence
    if ref_url.present?
      begin
        uri = URI.parse(ref_url)
        if uri.scheme.blank? || (uri.scheme.in?(%w[http https]) && uri.host == request.host)
          return ref_url
        end
      rescue URI::InvalidURIError
        nil
      end
    end

    next_seq = @project.sequences.generative_sequences.order(:position).first
    path =
      if next_seq
        edit_project_sequence_path(@project, next_seq)
      else
        open_project_path(@project)
      end

    "#{request.protocol}#{request.host_with_port}#{path}"
  end

  # Matches client closePanel / visitFabricAfterClosingLastPanel wiring for the workspace strip.
  def thread_destroy_redirect_query_overrides(deleted_thread_id, deleted_thread_public_id = nil)
    deleted_public_id =
      parse_sequence_public_id(deleted_thread_public_id) ||
      thread_public_id_for_id(deleted_thread_id)
    otp = params[:open_threads].to_s.strip

    ordered_public_ids =
      if otp.present?
        otp.split(",").map(&:strip).filter_map { |pid| parse_sequence_public_id(pid) }
      else
        partner = find_project_thread_by_public_id(params[:thread_partner])
        weave = find_project_thread_by_public_id(params[:weave_thread])
        [partner&.public_id, weave&.public_id].compact.uniq
      end

    deleted_idx = ordered_public_ids.index(deleted_public_id)

    remaining =
      ordered_public_ids.reject { |pid| pid == deleted_public_id }.select do |pid|
        thread_public_id_exists?(pid)
      end

    if remaining.empty?
      return {
        open_threads: nil,
        weave_thread: nil,
        thread_partner: nil
      }
    end

    focus_was = parse_sequence_public_id(params[:weave_thread])

    next_focus =
      if deleted_idx && focus_was == deleted_public_id
        prev_pid = deleted_idx.positive? ? ordered_public_ids[deleted_idx - 1] : nil
        if prev_pid.present? && remaining.include?(prev_pid)
          prev_pid
        else
          remaining.first
        end
      elsif focus_was.present? && remaining.include?(focus_was)
        focus_was
      else
        remaining.first
      end

    partner_public_id = parse_sequence_public_id(params[:thread_partner])
    partner_out =
      if partner_public_id.present? && partner_public_id != deleted_public_id && thread_partner_link_valid?(partner_public_id, next_focus)
        partner_public_id
      else
        nil
      end

    {
      weave_thread: next_focus,
      open_threads: remaining.join(","),
      thread_partner: partner_out
    }
  end
end
