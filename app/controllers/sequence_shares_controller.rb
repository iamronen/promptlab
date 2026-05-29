# frozen_string_literal: true

class SequenceSharesController < ApplicationController
  include ProjectNested
  include SequencePublicIdLookup
  include ShareJsonPayload

  before_action :set_project
  before_action :set_thread
  before_action :ensure_share_defined!, only: %i[destroy]

  def show
    render json: { share: share_payload(@thread) }
  end

  def update
    operation = share_operation_param

    case operation
    when "save"
      apply_share_save!
    when "enable"
      ensure_sharing_allowed!
      @thread.update!(share_state: :enabled)
    when "disable"
      @thread.disable_share!
    else
      render json: { errors: ["Unknown share operation"] }, status: :unprocessable_entity
      return
    end

    respond_after_mutation
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy
    @thread.delete_share!
    respond_after_mutation
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  private

  def set_thread
    @thread = find_project_sequence_by_public_id!(@project.sequences.threads, params[:sequence_id])
  end

  def ensure_share_defined!
    return if @thread.share_defined?

    raise ActiveRecord::RecordNotFound
  end

  def ensure_sharing_allowed!
    return if @project.sharing_allowed?

    @thread.errors.add(:share_state, "cannot be enabled while project disallows sharing")
    raise ActiveRecord::RecordInvalid, @thread
  end

  def share_operation_param
    params.dig(:share, :operation).to_s.presence || "save"
  end

  def share_save_params
    params.fetch(:share, ActionController::Parameters.new).permit(
      :share_public_name,
      :share_scope,
      :share_tease,
      :share_enabled,
      included_thread_public_ids: []
    )
  end

  def resolve_included_threads(public_ids)
    Array(public_ids).filter_map { |pid| find_project_thread_by_public_id(pid) }.uniq
  end

  def share_scope_param(attrs)
    scope = attrs[:share_scope].to_s.presence
    if scope.blank?
      return @thread.share_scope if @thread.share_defined?

      return "everything"
    end

    %w[everything selected].include?(scope) ? scope : @thread.share_scope
  end

  def share_enabled_param(attrs)
    return @thread.share_state_enabled? if @thread.share_defined? && !attrs.key?(:share_enabled)

    ActiveModel::Type::Boolean.new.cast(attrs.fetch(:share_enabled, false))
  end

  def share_tease_param(attrs)
    return @thread.share_tease if @thread.share_defined? && !attrs.key?(:share_tease)

    ActiveModel::Type::Boolean.new.cast(attrs.fetch(:share_tease, false))
  end

  def apply_share_save!
    attrs = share_save_params
    name = attrs[:share_public_name].to_s.strip
    scope = share_scope_param(attrs)
    tease = share_tease_param(attrs)
    enabled = share_enabled_param(attrs)
    threads = resolve_included_threads(attrs[:included_thread_public_ids])

    if @thread.share_state_unset?
      @thread.define_share!(
        share_public_name: name,
        share_scope: scope,
        share_tease: tease,
        included_threads: threads,
        enabled: enabled
      )
    else
      @thread.update_share_config!(
        share_public_name: name,
        share_scope: scope,
        share_tease: tease,
        included_threads: threads,
        enabled: enabled
      )
    end
  end

  def respond_after_mutation
    @thread.reload

    respond_to do |format|
      format.json { render json: { share: share_payload(@thread) } }
      format.turbo_stream { render_share_list_turbo_stream }
    end
  end

  def render_share_list_turbo_stream
    render turbo_stream: turbo_stream.replace(
      "project_shares_list_content",
      partial: "projects/project_shares_list",
      locals: { project: @project }
    )
  end
end
