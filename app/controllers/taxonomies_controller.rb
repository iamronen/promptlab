# frozen_string_literal: true

class TaxonomiesController < ApplicationController
  include TaxonomyJsonPayload
  include ProjectNested

  before_action :set_project
  before_action :set_taxonomy, only: %i[update destroy]

  def index
    taxonomies = @project.taxonomies.includes(:taxonomy_terms).order(:position, :id)
    render json: taxonomies.map { |taxonomy| taxonomy_payload(taxonomy) }
  end

  def create
    taxonomy = @project.taxonomies.build(taxonomy_params)
    if taxonomy.save
      render json: taxonomy_payload(taxonomy.reload), status: :created
    else
      render json: { errors: taxonomy.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @taxonomy.update(taxonomy_params)
      render json: taxonomy_payload(@taxonomy.reload)
    else
      render json: { errors: @taxonomy.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @taxonomy.destroy
    head :no_content
  end

  def reorder
    ids = params.require(:ordered_taxonomy_ids)
    ids = Array(ids).map(&:to_i).uniq

    if ids.blank?
      render json: { errors: ["ordered_taxonomy_ids cannot be empty"] }, status: :unprocessable_entity
      return
    end

    found_ids = @project.taxonomies.where(id: ids).pluck(:id)
    if found_ids.size != ids.size
      render json: { errors: ["ordered_taxonomy_ids must reference taxonomies for this project"] }, status: :unprocessable_entity
      return
    end

    Taxonomy.transaction do
      ids.each_with_index do |id, idx|
        @project.taxonomies.where(id: id).update_all(position: idx + 100_000)
      end
      ids.each_with_index do |id, idx|
        @project.taxonomies.where(id: id).update_all(position: idx + 1)
      end
    end

    taxonomies = @project.taxonomies.includes(:taxonomy_terms).order(:position, :id)
    render json: taxonomies.map { |taxonomy| taxonomy_payload(taxonomy) }
  end

  private

  def set_taxonomy
    @taxonomy = @project.taxonomies.find(params[:id])
  end

  def taxonomy_params
    params.require(:taxonomy).permit(:name, :cardinality, :single_select_ui, :position, :process_tracking)
  end
end
