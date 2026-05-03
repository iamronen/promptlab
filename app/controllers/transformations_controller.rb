class TransformationsController < ApplicationController
  include SequenceEditing

  before_action :set_project
  before_action :set_transformation, only: %i[edit update destroy duplicate create_pipeline_sequence]
  before_action :set_sidebar_sequences, only: %i[edit update duplicate]
  before_action :set_transformation_editor_collections, only: %i[edit update]

  def edit
    ensure_steps_placeholder
  end

  def create
    scope = @project.sequences.transformations
    position = scope.maximum(:position).to_i + 1
    sequence = @project.sequences.create!(
      kind: :transformation,
      title: Sequence::TRANSFORMATION_DEFAULT_TITLE,
      intent: Sequence::TRANSFORMATION_DEFAULT_INTENT,
      position: position,
      steps_data: [],
      is_term: false
    )

    redirect_to edit_project_transformation_path(@project, sequence, editor_mode: "edit"),
                notice: "Transformation created."
  rescue ActiveRecord::RecordInvalid
    redirect_to open_project_path(@project), alert: "Could not create transformation."
  end

  def update
    attrs = sequence_params.to_h
    nested_permitted = permit_nested_sequence_updates
    pipeline_ids = steps_payload_from_params(attrs).map { |h| h["sequence_id"].to_i }

    if nested_permitted.keys.map(&:to_i).any? { |id| pipeline_ids.exclude?(id) }
      assign_sequence_attributes
      refresh_pipeline_children_lookup
      @sequence.errors.add(:base, "Cannot edit sequences that are not in this transformation pipeline")
      render :edit, status: :unprocessable_entity
      return
    end

    assign_sequence_attributes
    prereq_ids = prerequisite_transformation_ids_from_params

    saved_ok = false
    prereq_error_msgs = []
    nested_ok = true
    ActiveRecord::Base.transaction do
      saved_ok = @sequence.save
      if saved_ok
        unless @sequence.sync_prerequisite_dependencies!(prereq_ids)
          prereq_error_msgs = @sequence.errors.full_messages.dup
          raise ActiveRecord::Rollback
        end
      end
      if saved_ok && prereq_error_msgs.empty?
        nested_ok = save_nested_generative_sequences!(nested_permitted)
        raise ActiveRecord::Rollback unless nested_ok
      end
    end

    ok = saved_ok && prereq_error_msgs.empty? && nested_ok

    unless ok
      combo = @sequence.errors.full_messages | prereq_error_msgs
      if saved_ok && @sequence.persisted?
        @sequence.reload
        combo.each { |m| @sequence.errors.add(:base, m) }
      else
        prereq_error_msgs.each { |m| @sequence.errors.add(:base, m) }
      end
    end

    if ok
      redirect_to edit_project_transformation_path(@project, @sequence), notice: "Transformation updated."
    else
      refresh_pipeline_children_lookup
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @sequence.destroy
      redirect_after_transformation_destroy
    else
      redirect_to edit_project_transformation_path(@project, @sequence),
                alert:
                  @sequence.errors.full_messages.to_sentence.presence ||
                    "Could not delete transformation."
    end
  end

  def create_pipeline_sequence
    sequence = nil
    scope = @project.sequences.generative_sequences
    position = scope.maximum(:position).to_i + 1
    sequence = @project.sequences.new(
      kind: :sequence,
      title: Sequence::DEFAULT_TITLE,
      intent: Sequence::DEFAULT_INTENT,
      position: position,
      steps_data: [{ "content" => "" }],
      is_term: false
    )
    sequence.save!

    respond_to do |format|
      format.json do
        render json: {
          id: sequence.id,
          title: sequence.title.to_s.truncate(80)
        }, status: :created
      end
    end
  rescue ActiveRecord::RecordInvalid
    msgs = sequence&.errors&.full_messages || ["Could not create sequence."]
    respond_to do |format|
      format.json { render json: { error: msgs }, status: :unprocessable_entity }
    end
  end

  def duplicate
    scope = @project.sequences.transformations
    position = scope.maximum(:position).to_i + 1
    copy = nil
    dup_errors = nil
    ActiveRecord::Base.transaction do
      copy = @project.sequences.create!(
        kind: :transformation,
        is_term: false,
        title: duplicate_sequence_title(@sequence.title, default_title: Sequence::TRANSFORMATION_DEFAULT_TITLE),
        intent: @sequence.intent.to_s,
        position: position,
        steps_data: duplicate_steps_data(@sequence.steps_data)
      )
      unless copy.sync_prerequisite_dependencies!(@sequence.prerequisite_transformation_ids)
        dup_errors = copy.errors.full_messages.to_sentence.presence || "Could not copy prerequisites."
        raise ActiveRecord::Rollback
      end
    end

    if dup_errors
      redirect_to edit_project_transformation_path(@project, @sequence), alert: dup_errors
    else
      redirect_to edit_project_transformation_path(@project, copy), notice: "Transformation duplicated."
    end
  rescue ActiveRecord::RecordInvalid
    redirect_to edit_project_transformation_path(@project, @sequence), alert: "Could not duplicate transformation."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_sidebar_sequences
    @sequences = @project.sequences.generative_sequences.order(:position)
    @terms = @project.sequences.terms.order(:position)
    @transformations = @project.sequences.transformations.order(:position)
  end

  def set_transformation
    @sequence = @project.sequences.transformations.find(params[:id])
  end

  def set_transformation_editor_collections
    @pipeline_sequences = @project.sequences.generative_sequences.order(:position)
    @other_transformations = @project.sequences.transformations.where.not(id: @sequence.id).order(:position)
    refresh_pipeline_children_lookup
  end

  def refresh_pipeline_children_lookup
    ids = @sequence.transformation_step_sequence_ids
    @pipeline_children_by_id = @project.sequences.generative_sequences.where(id: ids).index_by(&:id)
  end

  def ensure_steps_placeholder
    @sequence.steps_data = [] if @sequence.steps_data.blank?
  end

  def steps_payload_from_params(attrs)
    steps_attrs = attrs.fetch("steps_attributes", {})
    rows = steps_attrs.is_a?(Hash) ? steps_attrs.values : []
    remaining = rows.reject do |s|
      next false unless s.is_a?(Hash)

      dv = s["_destroy"] || s[:_destroy]
      ActiveModel::Type::Boolean.new.cast(dv)
    end
    sorted = remaining.sort_by do |s|
      pos = s.is_a?(Hash) ? (s["position"] || s[:position]) : nil
      pos.to_i
    end
    sorted.filter_map do |s|
      next unless s.is_a?(Hash)

      sid = s["sequence_id"] || s[:sequence_id]
      next if sid.blank?

      { "sequence_id" => sid.to_i }
    end
  end

  def duplicate_steps_data(data)
    rows = Array.wrap(data).filter_map do |raw|
      next unless raw.is_a?(Hash)

      sid = raw.stringify_keys["sequence_id"]
      next if sid.blank?

      { "sequence_id" => sid.to_i }
    end
    rows
  end

  def sequence_params
    seq = params.require(:sequence)
    permitted = seq.permit(:title, :intent, prerequisite_transformation_ids: [])
    nested = {}
    seq[:steps_attributes]&.each_pair do |key, attrs|
      next unless attrs.respond_to?(:permit)

      nested[key] = attrs.permit(:sequence_id, :content, :position, :_destroy)
    end
    permitted[:steps_attributes] = nested unless nested.empty?

    permitted
  end

  def prerequisite_transformation_ids_from_params
    raw = params.dig(:sequence, :prerequisite_transformation_ids)
    Array.wrap(raw).map(&:presence).compact.map(&:to_i).uniq - [@sequence.id]
  end

  def permit_nested_sequence_updates
    raw = params[:nested_sequences]
    return {} unless raw.is_a?(ActionController::Parameters)

    out = {}
    raw.each do |seq_id, attrs|
      next unless attrs.respond_to?(:permit)

      top = attrs.permit(:title, :intent)
      steps = attrs[:steps_attributes]
      next unless steps.is_a?(ActionController::Parameters) || steps.is_a?(Hash)

      permitted_steps = {}
      steps.each_pair do |k, step|
        next unless step.respond_to?(:permit)

        permitted_steps[k.to_s] = step.permit(:content, :position, :_destroy)
      end
      out[seq_id.to_s] = top.to_h.merge("steps_attributes" => permitted_steps)
    end
    out
  end

  def save_nested_generative_sequences!(nested_permitted)
    nested_permitted.each do |_id_str, child_attrs|
      id = _id_str.to_i
      child = @project.sequences.generative_sequences.find_by(id: id)
      next unless child

      child.title = child_attrs["title"].to_s if child_attrs.key?("title")
      child.intent = child_attrs["intent"].to_s if child_attrs.key?("intent")

      steps_hash = child_attrs["steps_attributes"] || child_attrs[:steps_attributes]
      child.steps_data = build_generative_steps_data(steps_hash)
      next if child.save

      child.errors.full_messages.each { |m| @sequence.errors.add(:base, "#{child.title}: #{m}") }
      return false
    end
    true
  end

  def redirect_after_transformation_destroy
    next_row = @project.sequences.transformations.order(:position).first
    if next_row
      redirect_to edit_project_transformation_path(@project, next_row), notice: "Transformation deleted."
      return
    end

    redirect_to open_project_path(@project), notice: "Transformation deleted."
  end
end
