class ProjectsController < ApplicationController
  before_action :set_project, only: %i[update open settings destroy export_pdf]

  def index
    @projects = current_user.projects.order(:created_at).includes(:sequences)
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
    @project = current_user.projects.build(project_params)
    seq = nil
    ActiveRecord::Base.transaction do
      @project.save!
      seq = @project.bootstrap_initial_sequence_on_genesis!
    end
    genesis = @project.genesis_thread
    redirect_to edit_project_sequence_path(
      @project,
      seq,
      weave_thread: genesis.public_id,
      focus_transformation_id: seq.public_id
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
      if request.format.json?
        render json: {
          default_process_taxonomy_id: @project.default_process_taxonomy_id,
          sharing_allowed: @project.sharing_allowed
        }
      else
        redirect_to project_update_redirect_path, notice: "Project saved."
      end
    elsif request.format.json?
      render json: { errors: @project.errors.full_messages }, status: :unprocessable_entity
    elsif project_settings_modal_frame_request?
      render partial: "projects/project_settings_modal", layout: false, status: :unprocessable_entity
    else
      redirect_to project_update_redirect_path,
                  alert: @project.errors.full_messages.to_sentence.presence || "Could not rename project.",
                  status: :see_other
    end
  end

  def export_pdf
    pdf = ProjectPdfGenerator.render(@project)
    filename = "#{@project.name.parameterize.presence || 'project'}-threads.pdf"
    send_data pdf,
              filename: filename,
              type: "application/pdf",
              disposition: "attachment"
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
    redirect_to edit_project_sequence_path(
      @project,
      seq,
      weave_thread: @project.genesis_thread.public_id
    )
  end

  private

  def project_settings_modal_frame_request?
    request.headers["Turbo-Frame"].to_s == "project_settings_modal"
  end

  def project_create_modal_frame_request?
    request.headers["Turbo-Frame"].to_s == "project_create_modal"
  end

  def set_project
    @project = current_user.projects.find_by!(public_id: params[:id].to_s.strip)
  end

  def project_params
    params.require(:project).permit(:name, :default_process_taxonomy_id, :sharing_allowed)
  end

  def project_update_redirect_path
    return_to = params[:return_to].to_s
    return return_to if safe_project_return_to?(return_to)

    projects_path
  end

  def safe_project_return_to?(path)
    s = path.to_s
    return false if s.blank? || !s.start_with?("/") || s.include?("..")
    return false unless @project

    s.match?(%r{\A/projects/#{Regexp.escape(@project.public_id)}(?:/|\z)})
  end
end
