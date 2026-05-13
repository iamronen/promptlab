class ProjectsController < ApplicationController
  before_action :enable_flowbite_app_shell, only: %i[index settings]
  before_action :set_project, only: %i[update open settings]

  def index
    @projects = Project.order(:created_at).includes(:sequences)
  end

  def settings
  end

  def update
    if @project.update(project_params)
      if params[:settings_form].present?
        redirect_to settings_project_path(@project), notice: "Project settings saved."
      else
        redirect_to projects_path, notice: "Project renamed."
      end
    elsif params[:settings_form].present?
      render :settings, status: :unprocessable_entity
    else
      redirect_to projects_path, alert: @project.errors.full_messages.to_sentence.presence || "Could not rename project."
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
    redirect_to edit_project_sequence_path(@project, seq, **workspace_shell_open_options)
  end

  private

  def enable_flowbite_app_shell
    @render_flowbite_app_shell = true
  end

  def workspace_shell_open_options
    s = params[:workspace_shell].to_s
    WorkspaceSidebarData::VALID_WORKSPACE_SHELLS.include?(s) ? { workspace_shell: s } : {}
  end

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description)
  end
end
