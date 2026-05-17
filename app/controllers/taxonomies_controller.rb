# frozen_string_literal: true

class TaxonomiesController < ApplicationController
  include TaxonomyJsonPayload

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

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_taxonomy
    @taxonomy = @project.taxonomies.find(params[:id])
  end

  def taxonomy_params
    params.require(:taxonomy).permit(:name, :cardinality, :single_select_ui, :position)
  end
end
