# frozen_string_literal: true

module ProjectNested
  extend ActiveSupport::Concern

  private

  def set_project
    @project = current_user.projects.find_by!(public_id: params[:project_id].to_s.strip)
  end
end
