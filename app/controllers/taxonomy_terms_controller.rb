# frozen_string_literal: true

class TaxonomyTermsController < ApplicationController
  include TaxonomyJsonPayload

  before_action :set_project
  before_action :set_taxonomy
  before_action :set_term, only: %i[update destroy]

  def create
    term = @taxonomy.taxonomy_terms.build(term_params)
    if term.save
      render json: term_payload(term), status: :created
    else
      render json: { errors: term.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @term.update(term_params)
      render json: term_payload(@term.reload)
    else
      render json: { errors: @term.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    unless @term.destroy
      render json: { errors: @term.errors.full_messages }, status: :unprocessable_entity
      return
    end

    head :no_content
  end

  def reorder
    ids = params.require(:ordered_term_ids)
    ids = Array(ids).map(&:to_i).uniq

    if ids.blank?
      render json: { errors: ["ordered_term_ids cannot be empty"] }, status: :unprocessable_entity
      return
    end

    found_ids = @taxonomy.taxonomy_terms.where(id: ids).pluck(:id)
    if found_ids.size != ids.size
      render json: { errors: ["ordered_term_ids must reference terms for this taxonomy"] }, status: :unprocessable_entity
      return
    end

    TaxonomyTerm.transaction do
      ids.each_with_index do |id, idx|
        @taxonomy.taxonomy_terms.where(id: id).update_all(position: idx + 100_000)
      end
      ids.each_with_index do |id, idx|
        @taxonomy.taxonomy_terms.where(id: id).update_all(position: idx + 1)
      end
    end

    render json: taxonomy_payload(@taxonomy.reload)
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_taxonomy
    @taxonomy = @project.taxonomies.find(params[:taxonomy_id])
  end

  def set_term
    @term = @taxonomy.taxonomy_terms.find(params[:id])
  end

  def term_params
    params.require(:taxonomy_term).permit(:label, :position)
  end
end
