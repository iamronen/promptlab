class SequencesController < ApplicationController
  include SequenceEditing

  before_action :set_project
  before_action :set_sidebar_sequences, only: %i[edit update duplicate add_to_terms remove_from_terms]
  before_action :set_sequence, only: %i[edit update destroy duplicate add_to_terms remove_from_terms]

  def edit
    ensure_steps_placeholder
  end

  def create
    wants_term = create_wants_term?
    scope = @project.sequences.generative_sequences
    position = scope.maximum(:position).to_i + 1
    sequence = @project.sequences.create!(
      kind: :sequence,
      title: Sequence::DEFAULT_TITLE,
      intent: Sequence::DEFAULT_INTENT,
      position: position,
      steps_data: [{ "content" => "" }],
      is_term: wants_term
    )

    redirect_to edit_project_sequence_path(@project, sequence, editor_mode: "edit"),
                notice: wants_term ? "Term created." : "Sequence created."
  rescue ActiveRecord::RecordInvalid
    redirect_to open_project_path(@project),
                alert: wants_term ? "Could not create term." : "Could not create sequence."
  end

  def update
    assign_sequence_attributes

    if @sequence.save
      redirect_to edit_project_sequence_path(@project, @sequence), notice: "Sequence updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @sequence.destroy
      redirect_after_generative_sequence_destroy
    else
      redirect_to edit_project_sequence_path(@project, @sequence),
                  alert:
                    @sequence.errors.full_messages.to_sentence.presence ||
                      "Could not delete sequence."
    end
  end

  def duplicate
    scope = @project.sequences.generative_sequences
    position = scope.maximum(:position).to_i + 1
    copy = @project.sequences.create!(
      kind: :sequence,
      is_term: @sequence.is_term,
      title: duplicate_sequence_title(@sequence.title),
      intent: @sequence.intent.to_s,
      position: position,
      steps_data: duplicate_steps_data(@sequence.steps_data)
    )
    redirect_to edit_project_sequence_path(@project, copy), notice: "Sequence duplicated."
  rescue ActiveRecord::RecordInvalid
    redirect_to edit_project_sequence_path(@project, @sequence), alert: "Could not duplicate sequence."
  end

  def add_to_terms
    if @sequence.update(is_term: true)
      redirect_to edit_project_sequence_path(@project, @sequence), notice: "Added to terms."
    else
      redirect_to edit_project_sequence_path(@project, @sequence),
                  alert: @sequence.errors.full_messages.to_sentence.presence || "Could not add to terms."
    end
  end

  def remove_from_terms
    if @sequence.update(is_term: false)
      redirect_to edit_project_sequence_path(@project, @sequence), notice: "Removed from terms."
    else
      redirect_to edit_project_sequence_path(@project, @sequence),
                  alert: @sequence.errors.full_messages.to_sentence.presence || "Could not remove from terms."
    end
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

  def set_sequence
    @sequence = @project.sequences.generative_sequences.find(params[:id])
  end

  def create_wants_term?
    ActiveModel::Type::Boolean.new.cast(params.dig(:sequence, :is_term))
  end

  def redirect_after_generative_sequence_destroy
    next_seq = @project.sequences.generative_sequences.order(:position).first
    if next_seq
      redirect_to edit_project_sequence_path(@project, next_seq), notice: "Sequence deleted."
      return
    end

    redirect_to open_project_path(@project), notice: "Sequence deleted."
  end
end
