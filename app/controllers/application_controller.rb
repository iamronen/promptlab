class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for imported assets
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :set_current_attributes

  private

  def set_current_attributes
    Current.user = current_user
  end

  # Background save from thread workspace (no full-page redirect).
  def workspace_autosave_request?
    params[:autosave].present?
  end

  def turbo_frame_header
    (request.headers["Turbo-Frame"].presence ||
      request.get_header("HTTP_TURBO_FRAME").presence ||
      request.env["HTTP_TURBO_FRAME"].presence).to_s.strip
  end

  def safe_workspace_editor_redirect?(path)
    s = path.to_s
    return false if s.blank? || !s.start_with?("/") || s.include?("..")
    return false unless defined?(@project) && @project

    s.match?(%r{\A/projects/#{Regexp.escape(@project.id.to_s)}(?:/|\z)})
  end
end
