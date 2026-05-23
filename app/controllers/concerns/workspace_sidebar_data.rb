# frozen_string_literal: true

# Shared workspace collections for sequence + bundle editors (weave + library).
module WorkspaceSidebarData
  extend ActiveSupport::Concern

  VALID_WORKSPACE_MODES = %w[sequencing fabric].freeze
  VALID_WORKSPACE_SHELLS = %w[v1 v2].freeze

  included do
    helper_method :workspace_editor_redirect_options,
                  :workspace_mode_param, :workspace_fabric?, :current_workspace_mode,
                  :workspace_shell_param, :workspace_shell_v2?,
                  :workspace_thread_scope_params, :fabric_thread_open_in_sequencing_path,
                  :thread_workspace_open_threads_param if respond_to?(:helper_method)
  end

  def fabric_thread_open_in_sequencing_path(thread)
    base =
      workspace_editor_redirect_options.except(:workspace_mode, :thread_partner, :open_threads).merge(weave_thread: thread.id)
    if @sequence.bundle?
      edit_project_bundle_path(@project, @sequence, **base)
    else
      edit_project_sequence_path(@project, @sequence, **base)
    end
  end

  private

  def set_sidebar_sequences
    @sequences = @project.sequences.generative_sequences.order(:position)
    @terms = @project.sequences.terms.order(:position)
    @bundles = @project.sequences.bundles.order(:position)
    @weave_threads = @project.sequences.threads.order(:position)
    @genesis_thread = @project.genesis_thread
    @orphans_thread = @project.orphans_thread
    @weave_children_index = build_weave_children_index
    @weave_thread_roots = build_weave_thread_roots
    @selected_weave_thread_id = resolve_selected_weave_thread_id
    @workspace_thread =
      if @selected_weave_thread_id
        @project.sequences.threads.find_by(id: @selected_weave_thread_id)
      end
    @thread_panel_partner_thread = resolve_thread_panel_partner_thread

    ids = resolve_thread_workspace_open_thread_ids
    @thread_workspace_open_thread_records =
      ids.filter_map do |tid|
        @project.sequences.threads.find_by(id: tid)
      end

    @fabric_thread_tree_branches =
      if workspace_fabric?
        FabricThreadTree.root_branches(@project)
      end
  end

  def workspace_mode_param
    m = params[:workspace_mode].to_s
    VALID_WORKSPACE_MODES.include?(m) ? m : nil
  end

  def workspace_fabric?
    workspace_mode_param == "fabric"
  end

  def current_workspace_mode
    workspace_mode_param || "sequencing"
  end

  def workspace_shell_param
    s = params[:workspace_shell].to_s
    VALID_WORKSPACE_SHELLS.include?(s) ? s : nil
  end

  def workspace_shell_v2?
    workspace_shell_param == "v2"
  end

  # Query params preserved when redirecting back to the workspace editor (library tab + weave selection).
  def workspace_editor_redirect_options
    h = sidebar_redirect_options.dup
    wm = workspace_mode_param
    h[:workspace_mode] = wm if wm.present?
    ws = workspace_shell_param
    h[:workspace_shell] = ws if ws.present?

    wt = params[:weave_thread].to_s
    if wt.present? && wt.to_i.positive? && @project.sequences.threads.where(id: wt.to_i).exists?
      h[:weave_thread] = wt
    end
    open_list = parse_open_threads_param(params[:open_threads])
    h[:open_threads] = open_list.join(",") if open_list.any?
    tp = params[:thread_partner].to_s
    wt_int = wt.present? ? wt.to_i : 0
    if tp.present? && tp.to_i.positive? && wt_int.positive? && thread_partner_link_valid?(tp.to_i, wt_int)
      h[:thread_partner] = tp
    end
    fb = params[:focus_bundle_id]
    ft = params[:focus_transformation_id]
    h[:focus_bundle_id] = fb if fb.to_s.match?(/\A\d+\z/)
    h[:focus_transformation_id] = ft if ft.to_s.match?(/\A\d+\z/)
    h
  end

  def thread_workspace_open_threads_param
    @thread_workspace_open_thread_records&.map(&:id)&.join(",")
  end

  def sidebar_redirect_options
    s = params[:sidebar].to_s
    s = "sequences" if s == "bundles" || s == "transformations"

    return {} unless %w[sequences terms assistant].include?(s)

    { sidebar: s }
  end

  def resolve_selected_weave_thread_id
    tid = params[:weave_thread].to_i
    if tid.positive? && @project.sequences.threads.where(id: tid).exists?
      tid
    else
      @genesis_thread&.id
    end
  end

  # Params for forms/links — when open_threads is present, omit legacy thread_partner.
  def workspace_thread_scope_params
    return {} unless @selected_weave_thread_id

    h = { weave_thread: @selected_weave_thread_id }
    if params[:open_threads].blank?
      h[:thread_partner] = @thread_panel_partner_thread.id if @thread_panel_partner_thread
    elsif @thread_workspace_open_thread_records.present?
      h[:open_threads] = thread_workspace_open_threads_param
    end

    h
  end

  def resolve_thread_panel_partner_thread
    partner_id = params[:thread_partner].to_i
    child_id = @selected_weave_thread_id.to_i
    return nil unless partner_id.positive? && child_id.positive?
    return nil unless thread_partner_link_valid?(partner_id, child_id)

    @project.sequences.threads.find_by(id: partner_id)
  end

  def resolve_thread_workspace_open_thread_ids
    otp = params[:open_threads].to_s.strip
    if otp.present?
      parse_open_threads_param(otp)
    elsif @thread_panel_partner_thread.present? && @selected_weave_thread_id.present?
      [@thread_panel_partner_thread.id, @selected_weave_thread_id]
    else
      [@selected_weave_thread_id].compact
    end
  end

  def parse_open_threads_param(raw)
    raw.to_s.strip
      .split(",")
      .map { |x| x.to_i }
      .select { |id| id.positive? && @project.sequences.threads.exists?(id) }
      .uniq
  end

  def thread_partner_link_valid?(parent_thread_id, child_thread_id)
    return false unless parent_thread_id.positive? && child_thread_id.positive?

    ThreadNode.exists?(parent_thread_id: parent_thread_id, child_thread_id: child_thread_id)
  end

  def build_weave_children_index
    thread_scope = @project.sequences.threads
    return {} unless thread_scope.exists?

    ThreadNode.where(parent_thread_id: thread_scope.select(:id))
      .includes(:child_thread)
      .order(:parent_thread_id, :child_order, :created_at)
      .group_by(&:parent_thread_id)
      .transform_values { |nodes| nodes.map(&:child_thread) }
  end

  def build_weave_thread_roots
    thread_scope = @project.sequences.threads
    return thread_scope.none unless thread_scope.exists?

    inbound = ThreadNode.where(child_thread_id: thread_scope.select(:id)).distinct.pluck(:child_thread_id)
    roots = thread_scope.where.not(id: inbound).order(:position)
    return roots if roots.exists?

    thread_scope.order(:position)
  end
end
