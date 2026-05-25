# frozen_string_literal: true

class ProcessBoardsController < ApplicationController
  include ProjectNested

  before_action :set_project

  def show
    @process_board = ProcessBoard.new(@project)
    render layout: false
  end
end
