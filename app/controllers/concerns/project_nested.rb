# frozen_string_literal: true

module ProjectNested
  extend ActiveSupport::Concern

  private

  def set_project
    @project = current_user.projects.find(params[:project_id])
  end
end
