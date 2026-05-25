module ApplicationHelper
  def render_application_shell?
    user_signed_in? && !@skip_application_shell
  end
end
