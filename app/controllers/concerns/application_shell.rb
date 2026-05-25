# frozen_string_literal: true

# Skip the unified application shell for specific actions (e.g. minimal auth pages).
module ApplicationShell
  extend ActiveSupport::Concern

  def skip_application_shell
    @skip_application_shell = true
  end
end
