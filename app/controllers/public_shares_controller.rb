# frozen_string_literal: true

class PublicSharesController < ApplicationController
  include ApplicationShell
  include PublicShareReaderPayload

  skip_before_action :authenticate_user!
  before_action :skip_application_shell
  before_action :set_shared_thread
  before_action :set_initial_thread

  def show
    @reader_payload = reader_payload(@thread, initial_thread: @initial_thread)
  end

  private

  def set_shared_thread
    @thread = Sequence.threads.with_share_enabled.find_by!(public_id: params[:id].to_s.strip)
  end

  def set_initial_thread
    requested_id = params[:t].to_s.strip.presence
    @initial_thread = if requested_id.present?
                        candidate = @thread.project.sequences.threads.find_by(public_id: requested_id)
                        raise ActiveRecord::RecordNotFound unless candidate && @thread.share_reader_thread_readable?(candidate)

                        candidate
                      else
                        @thread
                      end
  end
end
