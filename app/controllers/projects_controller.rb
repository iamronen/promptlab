class ProjectsController < ApplicationController
  before_action :enable_flowbite_app_shell, only: %i[index]
  before_action :set_project, only: %i[update open settings destroy]

  def index
    @projects = Project.order(:created_at).includes(:sequences)
  end

  def new
    @project = Project.new
    if project_create_modal_frame_request?
      render partial: "projects/project_create_modal", layout: false
    else
      redirect_to projects_path
    end
  end

  def create
    @project = Project.new(project_params)
    seq = nil
    ActiveRecord::Base.transaction do
      @project.save!
      seq = @project.bootstrap_initial_sequence_on_genesis!
    end
    genesis = @project.genesis_thread
    redirect_to edit_project_sequence_path(
      @project,
      seq,
      weave_thread: genesis.id,
      focus_transformation_id: seq.id
    ),
      status: :see_other,
      notice: "Project created."
  rescue ActiveRecord::RecordInvalid
    if project_create_modal_frame_request?
      render partial: "projects/project_create_modal", layout: false, status: :unprocessable_entity
    else
      redirect_to projects_path,
                  alert: @project.errors.full_messages.to_sentence.presence || "Could not create project.",
                  status: :see_other
    end
  end

  def settings
    if project_settings_modal_frame_request?
      render partial: "projects/project_settings_modal", layout: false
    else
      redirect_to projects_path
    end
  end

  def update
    if @project.update(project_params)
      redirect_to projects_path, notice: "Project saved."
    elsif project_settings_modal_frame_request?
      render partial: "projects/project_settings_modal", layout: false, status: :unprocessable_entity
    else
      redirect_to projects_path,
                  alert: @project.errors.full_messages.to_sentence.presence || "Could not rename project."
    end
  end

  def destroy
    if @project.destroy
      redirect_to projects_path, notice: "Project deleted."
    else
      redirect_to projects_path,
                  alert: @project.errors.full_messages.to_sentence.presence || "Could not delete project."
    end
  end

  def open
    seq = @project.sequences.non_term_sequences.order(:position).first ||
      @project.sequences.terms.order(:position).first
    unless seq
      seq = @project.sequences.create!(
        kind: :sequence,
        title: Sequence::DEFAULT_TITLE,
        intent: Sequence::DEFAULT_INTENT,
        position: 1,
        steps_data: [{ "content" => "" }],
        is_term: false
      )
    end
    redirect_to edit_project_sequence_path(@project, seq)
  end

  private

  def enable_flowbite_app_shell
    @render_flowbite_app_shell = true
  end

  def project_settings_modal_frame_request?
    request.headers["Turbo-Frame"].to_s == "project_settings_modal"
  end

  def project_create_modal_frame_request?
    request.headers["Turbo-Frame"].to_s == "project_create_modal"
  end

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name)
  end
end
