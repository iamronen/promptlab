# frozen_string_literal: true

class MadeBoardsController < ApplicationController
  include ProjectNested

  before_action :set_project

  def show
    @made_timeline = MadeTimeline.new(@project)
    render layout: false
  end
end
