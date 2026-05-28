module ApplicationHelper
  def render_application_shell?
    user_signed_in? && !@skip_application_shell
  end

  # Matches process-card / meta taxonomy JS toLocaleString (medium date, short time).
  def format_process_assigned_at(time)
    return "" if time.blank?

    I18n.l(time.in_time_zone, format: :process_assigned_at)
  rescue I18n::MissingTranslationData
    time.in_time_zone.strftime("%b %-d, %Y, %-l:%M %p")
  end

  def format_process_assigned_date(date)
    return "" if date.blank?

    I18n.l(date, format: :process_assigned_date)
  rescue I18n::MissingTranslationData
    date.strftime("%b %-d, %Y")
  end
end
