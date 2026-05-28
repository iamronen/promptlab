# frozen_string_literal: true

class TaxonomyEndStateTermsController < ApplicationController
  include TaxonomyJsonPayload
  include ProjectNested

  before_action :set_project
  before_action :set_taxonomy
  before_action :ensure_process_tracking!

  def update
    result = Taxonomies::SyncEndStateTerms.call(
      taxonomy: @taxonomy,
      term_ids: params.require(:end_state_term_ids)
    )

    case result.status
    when :ok
      render json: taxonomy_payload(result.taxonomy)
    when :invalid
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_taxonomy
    @taxonomy = @project.taxonomies.find(params[:id])
  end

  def ensure_process_tracking!
    return if @taxonomy.process_tracking?

    render json: { errors: ["End state values require process tracking"] }, status: :unprocessable_entity
  end
end
