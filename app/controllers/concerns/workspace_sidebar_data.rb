# frozen_string_literal: true

# Shared workspace collections for sequence + bundle editors (weave + library).
module WorkspaceSidebarData
  extend ActiveSupport::Concern

  VALID_WORKSPACE_MODES = %w[sequencing browsing].freeze
  VALID_WORKSPACE_SHELLS = %w[v1 v2].freeze

  included do
    helper_method :workspace_editor_redirect_options, :workspace_modal_save_redirect_path,
                  :workspace_mode_param, :workspace_browsing?, :current_workspace_mode,
                  :workspace_shell_param, :workspace_shell_v2?, :workspace_thread_scope_params if respond_to?(:helper_method)
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
  end

  def workspace_mode_param
    m = params[:workspace_mode].to_s
    VALID_WORKSPACE_MODES.include?(m) ? m : nil
  end

  def workspace_browsing?
    workspace_mode_param == "browsing"
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

  # Path + query preserved after saving from modal (omit editor bootstrap param).
  def workspace_modal_save_redirect_path
    qs = Rack::Utils.parse_query(request.query_string.presence.to_s)
    qs.delete("editor_mode")
    qs.empty? ? request.path : "#{request.path}?#{Rack::Utils.build_query(qs)}"
  end

  def sidebar_redirect_options
    s = params[:sidebar].to_s
    s = "sequences" if s == "bundles" || s == "transformations"

    if workspace_mode_param == "browsing"
      return { sidebar: s } if %w[sequences terms].include?(s)

      return { sidebar: "sequences" }
    end

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

  # Params for forms/links so thread workspace split (?weave_thread=child&thread_partner=parent) persists.
  def workspace_thread_scope_params
    return {} unless @selected_weave_thread_id

    h = { weave_thread: @selected_weave_thread_id }
    h[:thread_partner] = @thread_panel_partner_thread.id if @thread_panel_partner_thread
    h
  end

  def resolve_thread_panel_partner_thread
    partner_id = params[:thread_partner].to_i
    child_id = @selected_weave_thread_id.to_i
    return nil unless partner_id.positive? && child_id.positive?
    return nil unless thread_partner_link_valid?(partner_id, child_id)

    @project.sequences.threads.find_by(id: partner_id)
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

  def workspace_shell_redirect_fragment
    ws = workspace_shell_param
    ws.present? ? { workspace_shell: ws } : {}
  end
end
