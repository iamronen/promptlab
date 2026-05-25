# frozen_string_literal: true

class TaxonomiesController < ApplicationController
  include TaxonomyJsonPayload
  include ProjectNested

  before_action :set_project
  before_action :set_taxonomy, only: %i[update destroy apply_default_value]

  def index
    taxonomies = @project.taxonomies.includes(:taxonomy_terms).order(:position, :id)
    render json: taxonomies_index_payload(taxonomies)
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
    attrs = taxonomy_update_attrs
    confirm = confirm_deletions_param?

    result = Taxonomies::ApplyBundleSettings.call(
      taxonomy: @taxonomy,
      attrs: attrs,
      confirm_deletions: confirm
    )

    case result.status
    when :ok
      render json: taxonomy_payload(result.taxonomy)
    when :confirmation_required
      render json: {
        confirmation_required: true,
        message: result.confirmation.message,
        bundle_assignment_count: result.confirmation.bundle_assignment_count,
        bundle_pipeline_sequence_assignment_count: result.confirmation.bundle_pipeline_sequence_assignment_count
      }, status: :conflict
    when :invalid
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @taxonomy.destroy
    head :no_content
  end

  def apply_default_value
    result = Taxonomies::ApplyDefaultValue.call(@taxonomy)

    case result.status
    when :ok
      render json: {
        applied_count: result.applied_count,
        taxonomy: taxonomy_payload(@taxonomy.reload)
      }
    when :invalid
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
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
    render json: taxonomies_index_payload(taxonomies)
  end

  def taxonomies_index_payload(taxonomies)
    @project.reload
    {
      taxonomies: taxonomies.map { |taxonomy| taxonomy_payload(taxonomy) },
      default_process_taxonomy_id: @project.default_process_taxonomy_id
    }
  end

  private

  def set_taxonomy
    @taxonomy = @project.taxonomies.find(params[:id])
  end

  def taxonomy_params
    params.require(:taxonomy).permit(
      :name,
      :cardinality,
      :single_select_ui,
      :position,
      :process_tracking,
      :applies_to_sequences,
      :applies_to_bundles,
      :applies_to_bundle_pipeline_sequences,
      :default_value_enabled,
      :default_taxonomy_term_id
    )
  end

  BOOLEAN_TAXONOMY_KEYS = %i[
    process_tracking
    applies_to_sequences
    applies_to_bundles
    applies_to_bundle_pipeline_sequences
    default_value_enabled
  ].freeze

  def taxonomy_update_attrs
    permitted = taxonomy_params.to_h
    raw = params[:taxonomy]
    return permitted unless raw.respond_to?(:key?)

    BOOLEAN_TAXONOMY_KEYS.each do |key|
      next unless raw.key?(key.to_s) || raw.key?(key)

      permitted[key.to_s] = ActiveModel::Type::Boolean.new.cast(raw[key])
    end

    permitted
  end

  def confirm_deletions_param?
    header_value =
      request.headers["X-Confirm-Deletions"].presence ||
      request.get_header("HTTP_X_CONFIRM_DELETIONS")
    return true if header_value.to_s == "1"

    raw = params[:confirm_deletions]
    raw = request.query_parameters[:confirm_deletions] if raw.nil?
    ActiveModel::Type::Boolean.new.cast(raw)
  end
end
