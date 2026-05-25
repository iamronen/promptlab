# frozen_string_literal: true

class ProcessCardDetailsController < ApplicationController
  include ProjectNested
  include WorkspaceSidebarData

  before_action :set_project
  before_action :set_artifact

  helper_method :fabric_breadcrumb_thread_path, :fabric_open_artifact_path, :process_card_title

  def show
    @host_thread = @artifact.strand_host_thread
    @fabric_open_url = @host_thread ? fabric_open_artifact_path(@artifact, @host_thread) : nil

    if @artifact.bundle?
      @sequence = @artifact
      refresh_pipeline_children_lookup
    else
      @sequence = @artifact
      ensure_steps_placeholder
    end

    render layout: false
  end

  private

  def set_artifact
    record = @project.sequences.find(params[:id])
    raise ActiveRecord::RecordNotFound unless record.sequence? || record.bundle?

    @artifact = record
  end

  def process_card_title
    @artifact.title.presence ||
      (@artifact.bundle? ? Sequence::BUNDLE_DEFAULT_TITLE : Sequence::DEFAULT_TITLE)
  end

  def refresh_pipeline_children_lookup
    ids = @sequence.pipeline_generative_sequence_ids
    @pipeline_children_by_id =
      @project.sequences.generative_sequences.includes(:created_by).where(id: ids).index_by(&:id)
  end

  def ensure_steps_placeholder
    return if @sequence.steps_data.is_a?(Array) && @sequence.steps_data.any?

    @sequence.steps_data = [{ "content" => "" }]
  end

  def fabric_breadcrumb_thread_path(thread)
    base = { weave_thread: thread.id }
    if @artifact.bundle?
      edit_project_bundle_path(@project, @artifact, **base)
    else
      edit_project_sequence_path(@project, @artifact, **base)
    end
  end

  def fabric_open_artifact_path(artifact, host_thread)
    base = { weave_thread: host_thread.id }
    if artifact.bundle?
      edit_project_bundle_path(@project, artifact, **base, focus_bundle_id: artifact.id)
    else
      edit_project_sequence_path(@project, artifact, **base, focus_transformation_id: artifact.id)
    end
  end
end
