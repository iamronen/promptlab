# frozen_string_literal: true

class SequenceTaxonomyAssignmentsController < ApplicationController
  include TaxonomyJsonPayload
  include ProjectNested

  before_action :set_project
  before_action :set_sequence

  def show
    render json: assignments_payload(@sequence)
  end

  def update
    permitted = params.permit(assignments: [:taxonomy_id, { taxonomy_term_ids: [] }])
    list = permitted[:assignments]

    if list.nil?
      render json: { errors: ["assignments parameter is required"] }, status: :unprocessable_entity
      return
    end

    replacer = TaxonomyAssignments::Replace.new(sequence: @sequence, assignments: list)
    if replacer.call
      @sequence.taxonomy_assignments.reset
      render json: assignments_payload(@sequence.reload), status: :ok
    else
      render json: { errors: replacer.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_sequence
    @sequence = @project.sequences.where(kind: %i[sequence bundle]).find(params[:sequence_id])
  end
end
