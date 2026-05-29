# frozen_string_literal: true

# Shared workspace collections for sequence + bundle editors (weave + library).
module WorkspaceSidebarData
  extend ActiveSupport::Concern
  include SequencePublicIdLookup

  FABRIC_THREAD_PANEL_FRAME = "fabric_thread_panel"

  VALID_WORKSPACE_MODES = %w[fabric making made settings].freeze
  VALID_WORKSPACE_SHELLS = %w[v1 v2].freeze

  included do
    helper_method :workspace_editor_redirect_options,
                  :workspace_mode_param, :workspace_fabric?, :workspace_making?, :workspace_made?, :workspace_settings?,
                  :current_workspace_mode,
                  :workspace_shell_param, :workspace_shell_v2?,
                  :workspace_settings_return_path, :workspace_making_return_path, :workspace_made_return_path,
                  :workspace_board_refresh_path,
                  :workspace_thread_scope_params, :fabric_thread_path, :fabric_breadcrumb_thread_path,
                  :fabric_panel_thread, :fabric_selected_weave_thread_id,
                  :fabric_thread_panel_turbo_frame_data,
                  :thread_workspace_open_threads_param if respond_to?(:helper_method)
  end

  def fabric_thread_panel_turbo_frame_data
    { turbo_frame: FABRIC_THREAD_PANEL_FRAME }
  end

  def fabric_thread_panel_frame_request?
    request.headers["Turbo-Frame"] == FABRIC_THREAD_PANEL_FRAME
  end

  def fabric_thread_panel_locals
    q_keep = request.query_parameters.slice(
      "weave_thread", "thread_partner", "open_threads", "sidebar",
      "focus_bundle_id", "focus_transformation_id", "workspace_mode", "workspace_shell"
    ).symbolize_keys
    {
      panel_thread: fabric_panel_thread,
      embed_query: q_keep.except(:focus_bundle_id, :focus_transformation_id),
      editor_return_path: request.fullpath,
      selected_weave_thread_id: fabric_selected_weave_thread_id,
      workspace_thread_scope_hash: workspace_thread_scope_params
    }
  end

  def fabric_panel_thread
    return nil unless workspace_fabric?

    @selected_weave_thread_record
  end

  def fabric_selected_weave_thread_id
    return nil unless workspace_fabric?

    @selected_weave_thread_record&.public_id
  end

  def fabric_thread_path(thread)
    base =
      workspace_editor_redirect_options.except(:workspace_mode, :thread_partner, :open_threads).merge(weave_thread: thread.public_id)
    if @sequence.bundle?
      edit_project_bundle_path(@project, @sequence, **base)
    else
      edit_project_sequence_path(@project, @sequence, **base)
    end
  end

  alias_method :fabric_breadcrumb_thread_path, :fabric_thread_path

  def workspace_settings_return_path
    base = workspace_editor_redirect_options.except(:workspace_mode).merge(workspace_mode: :settings)
    if @sequence.bundle?
      edit_project_bundle_path(@project, @sequence, **base)
    else
      edit_project_sequence_path(@project, @sequence, **base)
    end
  end

  def workspace_making_return_path
    workspace_mode_return_path(:making)
  end

  def workspace_made_return_path
    workspace_mode_return_path(:made)
  end

  def workspace_board_refresh_path
    case workspace_mode_param
    when "made"
      project_made_board_path(@project)
    when "making"
      project_process_board_path(@project)
    else
      nil
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

    preload_workspace_public_ids!

    @selected_weave_thread_record = resolve_weave_thread_record_from_param
    @selected_weave_thread_id = resolve_selected_weave_thread_id
    @workspace_thread = workspace_thread_for_selected_id
    @thread_panel_partner_thread = resolve_thread_panel_partner_thread

    ids = resolve_thread_workspace_open_thread_ids
    @thread_workspace_open_thread_records =
      ids.filter_map { |public_id| find_project_thread_by_public_id(public_id) }

    @fabric_thread_tree_branches =
      if workspace_fabric?
        FabricThreadTree.root_branches(@project)
      end

    @process_board =
      if workspace_making?
        ProcessBoard.new(@project)
      end

    @made_timeline =
      if workspace_made?
        MadeTimeline.new(@project)
      end
  end

  def preload_workspace_public_ids!
    ids = []
    wt = parse_sequence_public_id(params[:weave_thread])
    ids << wt if wt.present?
    ids.concat(raw_open_thread_public_ids_from_param(params[:open_threads]))
    tp = parse_sequence_public_id(params[:thread_partner])
    ids << tp if tp.present?

    preload_thread_public_ids!(ids.compact.uniq)

    fb = parse_sequence_public_id(params[:focus_bundle_id])
    preload_sequence_public_ids!(@project.sequences.bundles, [fb]) if fb.present?
    ft = parse_sequence_public_id(params[:focus_transformation_id])
    preload_sequence_public_ids!(@project.sequences.generative_sequences, [ft]) if ft.present?
  end

  def resolve_weave_thread_record_from_param
    wt = parse_sequence_public_id(params[:weave_thread])
    return nil unless wt.present?

    find_project_thread_by_public_id(wt)
  end

  def workspace_thread_for_selected_id
    return nil unless @selected_weave_thread_id

    find_project_thread_by_public_id(@selected_weave_thread_id)
  end

  def raw_open_thread_public_ids_from_param(raw)
    raw.to_s.strip.split(",").filter_map { |pid| parse_sequence_public_id(pid) }
  end

  def workspace_mode_param
    m = params[:workspace_mode].to_s
    VALID_WORKSPACE_MODES.include?(m) ? m : nil
  end

  def workspace_fabric?
    workspace_mode_param.nil? || workspace_mode_param == "fabric"
  end

  def workspace_making?
    workspace_mode_param == "making"
  end

  def workspace_made?
    workspace_mode_param == "made"
  end

  def workspace_settings?
    workspace_mode_param == "settings"
  end

  def legacy_workspace_mode_redirect?
    params[:workspace_mode].to_s.in?(%w[browsing sequencing process])
  end

  def legacy_workspace_mode_redirect_options
    case params[:workspace_mode].to_s
    when "process"
      workspace_editor_redirect_options.merge(workspace_mode: :making)
    else
      workspace_editor_redirect_options.except(:workspace_mode)
    end
  end

  def workspace_mode_return_path(mode)
    base = workspace_editor_redirect_options.except(:workspace_mode).merge(workspace_mode: mode)
    if @sequence.bundle?
      edit_project_bundle_path(@project, @sequence, **base)
    else
      edit_project_sequence_path(@project, @sequence, **base)
    end
  end

  def current_workspace_mode
    workspace_mode_param || "fabric"
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

    wt = parse_sequence_public_id(params[:weave_thread])
    h[:weave_thread] = wt if wt.present? && thread_public_id_exists?(wt)
    open_list = parse_open_threads_param(params[:open_threads])
    h[:open_threads] = open_list.join(",") if open_list.any?
    tp = parse_sequence_public_id(params[:thread_partner])
    wt_selected = @selected_weave_thread_id || wt
    if tp.present? && wt_selected.present? && thread_partner_link_valid?(tp, wt_selected)
      h[:thread_partner] = tp
    end
    fb = parse_sequence_public_id(params[:focus_bundle_id])
    ft = parse_sequence_public_id(params[:focus_transformation_id])
    h[:focus_bundle_id] = fb if fb.present? && sequence_public_id_exists?(@project.sequences.bundles, fb)
    h[:focus_transformation_id] = ft if ft.present? && sequence_public_id_exists?(@project.sequences.generative_sequences, ft)
    h
  end

  def thread_workspace_open_threads_param
    @thread_workspace_open_thread_records&.map(&:public_id)&.join(",")
  end

  def sidebar_redirect_options
    s = params[:sidebar].to_s
    s = "sequences" if s == "bundles" || s == "transformations"

    return {} unless %w[sequences terms assistant].include?(s)

    { sidebar: s }
  end

  def resolve_selected_weave_thread_id
    if @selected_weave_thread_record
      @selected_weave_thread_record.public_id
    else
      @genesis_thread&.public_id
    end
  end

  # Params for forms/links — when open_threads is present, omit legacy thread_partner.
  def workspace_thread_scope_params
    return {} unless @selected_weave_thread_id

    h = { weave_thread: @selected_weave_thread_id }
    if params[:open_threads].blank?
      h[:thread_partner] = @thread_panel_partner_thread.public_id if @thread_panel_partner_thread
    elsif @thread_workspace_open_thread_records.present?
      h[:open_threads] = thread_workspace_open_threads_param
    end

    h
  end

  def resolve_thread_panel_partner_thread
    partner_public_id = parse_sequence_public_id(params[:thread_partner])
    child_public_id = @selected_weave_thread_id
    return nil unless partner_public_id.present? && child_public_id.present?
    return nil unless thread_partner_link_valid?(partner_public_id, child_public_id)

    find_project_thread_by_public_id(partner_public_id)
  end

  def resolve_thread_workspace_open_thread_ids
    otp = params[:open_threads].to_s.strip
    if otp.present?
      parse_open_threads_param(otp)
    elsif @thread_panel_partner_thread.present? && @selected_weave_thread_id.present?
      [@thread_panel_partner_thread.public_id, @selected_weave_thread_id]
    else
      [@selected_weave_thread_id].compact
    end
  end

  def parse_open_threads_param(raw)
    ids = raw_open_thread_public_ids_from_param(raw).uniq
    preload_thread_public_ids!(ids)
    ids.select { |pid| thread_public_id_exists?(pid) }
  end

  def thread_partner_link_valid?(parent_thread_public_id, child_thread_public_id)
    parent = find_project_thread_by_public_id(parent_thread_public_id)
    child = find_project_thread_by_public_id(child_thread_public_id)
    return false unless parent && child

    ThreadNode.exists?(parent_thread_id: parent.id, child_thread_id: child.id)
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
