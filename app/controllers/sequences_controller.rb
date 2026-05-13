class SequencesController < ApplicationController
  include SequenceEditing
  include WorkspaceSidebarData
  include ThreadStrandMutations

  prepend_before_action :prepend_workspace_shell_v2_views, only: %i[edit update], if: :workspace_shell_v2?

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
                ]

  def edit
    ensure_steps_placeholder
    if sequence_modal_request?
      @sequence_modal_frame_id = modal_sequence_frame_id_from_request
      return render(:modal_body, layout: false)
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

    opts = { editor_mode: "edit", sidebar: (wants_term ? "terms" : "sequences") }
    wt = params[:weave_thread].to_s
    opts[:weave_thread] = wt if wt.present? && wt.to_i.positive? && @project.sequences.threads.where(id: wt.to_i).exists?
    wm = workspace_mode_param
    opts[:workspace_mode] = wm if wm.present?
    ws = workspace_shell_param
    opts[:workspace_shell] = ws if ws.present?

    redirect_to edit_project_sequence_path(@project, sequence, **opts),
                notice: wants_term ? "Term created." : "Sequence created."
  rescue ActiveRecord::RecordInvalid
    redirect_to open_project_path(@project, **workspace_shell_redirect_fragment),
                alert: wants_term ? "Could not create term." : "Could not create sequence."
  end

  def update
    assign_sequence_attributes

    if @sequence.save
      if workspace_autosave_request?
        render json: { sequence_id: @sequence.id, title: @sequence.title.to_s }, status: :ok
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
      render :modal_body, layout: false, status: :unprocessable_entity
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @sequence.destroy
      if safe_workspace_editor_redirect?(params[:redirect_to])
        redirect_to params[:redirect_to].to_s, notice: "Sequence deleted."
      else
        redirect_after_generative_sequence_destroy
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

    return true if turbo_frame_id == "sequence_modal_frame"
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
    id.match?(/\Athread_editor_sequence_\d+\z/) ? id : "sequence_modal_frame"
  end

  def sequence_modal_submission_via_redirect?
    safe_workspace_editor_redirect?(params[:redirect_to])
  end

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_sequence
    @sequence =
      if %w[edit update].include?(action_name)
        record = @project.sequences.find(params[:id])
        raise ActiveRecord::RecordNotFound unless record.sequence? || record.thread?

        record
      else
        @project.sequences.generative_sequences.find(params[:id])
      end
  end

  def create_wants_term?
    ActiveModel::Type::Boolean.new.cast(params.dig(:sequence, :is_term))
  end

  def redirect_after_generative_sequence_destroy
    next_seq = @project.sequences.generative_sequences.order(:position).first
    if next_seq
      redirect_to edit_project_sequence_path(@project, next_seq, **workspace_editor_redirect_options),
                  notice: "Sequence deleted."
      return
    end

    redirect_to open_project_path(@project, **workspace_shell_redirect_fragment), notice: "Sequence deleted."
  end

  def prepend_workspace_shell_v2_views
    prepend_view_path Rails.root.join("app/views/workspace_shell_v2")
  end
end
