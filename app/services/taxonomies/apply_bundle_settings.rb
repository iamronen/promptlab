# frozen_string_literal: true

module Taxonomies
  class ApplyBundleSettings
    Result = Struct.new(:status, :taxonomy, :errors, :confirmation, keyword_init: true)
    Confirmation = Struct.new(
      :message,
      :bundle_assignment_count,
      :bundle_pipeline_sequence_assignment_count,
      keyword_init: true
    )

    PERMITTED_KEYS = %w[
      name
      cardinality
      single_select_ui
      position
      process_tracking
      applies_to_sequences
      applies_to_bundles
      applies_to_bundle_pipeline_sequences
      default_value_enabled
      default_taxonomy_term_id
    ].freeze

    def self.call(taxonomy:, attrs:, confirm_deletions: false)
      new(taxonomy:, attrs:, confirm_deletions:).call
    end

    def initialize(taxonomy:, attrs:, confirm_deletions: false)
      @taxonomy = taxonomy
      @attrs = normalize_attrs(attrs)
      @confirm_deletions = confirm_deletions
      @errors = []
    end

    def call
      confirmation = confirmation_for_destructive_changes
      if confirmation
        return Result.new(status: :confirmation_required, confirmation: confirmation)
      end
      was_bundles = @taxonomy.applies_to_bundles?
      was_pipeline = @taxonomy.applies_to_bundle_pipeline_sequences?
      process_enabling =
        @attrs.key?("process_tracking") && !@taxonomy.process_tracking? && @attrs["process_tracking"]

      Taxonomy.transaction do
        @taxonomy.assign_attributes(@attrs)
        unless @taxonomy.save
          @errors = @taxonomy.errors.full_messages
          raise ActiveRecord::Rollback
        end

        apply_side_effects!(
          was_bundles: was_bundles,
          was_pipeline: was_pipeline,
          process_enabling: process_enabling
        )
      end

      if @errors.any?
        Result.new(status: :invalid, errors: @errors)
      else
        Result.new(status: :ok, taxonomy: @taxonomy.reload)
      end
    end

    private

    def normalize_attrs(raw)
      h =
        case raw
        when ActionController::Parameters
          raw.permit(PERMITTED_KEYS).to_h
        when Hash
          raw.stringify_keys.slice(*PERMITTED_KEYS)
        else
          {}
        end

      h.transform_values do |value|
        next value unless [true, false, "true", "false", 1, 0, "1", "0"].include?(value)

        ActiveModel::Type::Boolean.new.cast(value)
      end
    end

    def confirmation_for_destructive_changes
      return nil if @confirm_deletions

      bundle_count = 0
      pipeline_count = 0

      if disabling_bundles?
        bundle_count = AssignmentCleanup.bundle_assignments_for(@taxonomy).size
      end

      if disabling_pipeline_sequences?
        pipeline_count = AssignmentCleanup.pipeline_sequence_assignments_for(@taxonomy).size
      end

      total = bundle_count + pipeline_count
      return nil if total.zero?

      message = confirmation_message(bundle_count:, pipeline_count:)
      Confirmation.new(
        message: message,
        bundle_assignment_count: bundle_count,
        bundle_pipeline_sequence_assignment_count: pipeline_count
      )
    end

    def confirmation_message(bundle_count:, pipeline_count:)
      parts = []
      if bundle_count.positive?
        noun = bundle_count == 1 ? "bundle" : "bundles"
        parts << "#{bundle_count} #{noun}"
      end
      if pipeline_count.positive?
        noun = pipeline_count == 1 ? "sequence" : "sequences"
        parts << "#{pipeline_count} pipeline #{noun}"
      end

      "Changing this setting will remove taxonomy assignments from #{parts.join(' and ')}. This cannot be undone."
    end

    def disabling_bundles?
      return false unless @attrs.key?("applies_to_bundles")

      @taxonomy.applies_to_bundles? && !@attrs["applies_to_bundles"]
    end

    def disabling_pipeline_sequences?
      return false unless @attrs.key?("applies_to_bundle_pipeline_sequences")

      @taxonomy.applies_to_bundle_pipeline_sequences? && !@attrs["applies_to_bundle_pipeline_sequences"]
    end

    def apply_side_effects!(was_bundles:, was_pipeline:, process_enabling:)
      if !was_bundles && @taxonomy.applies_to_bundles?
        BackfillBundleAssignments.call(@taxonomy)
      end

      if was_bundles && !@taxonomy.applies_to_bundles?
        rows = AssignmentCleanup.bundle_assignments_for(@taxonomy)
        AssignmentCleanup.delete_assignments!(rows, taxonomy: @taxonomy)
      end

      pipeline_turned_off =
        (was_pipeline && !@taxonomy.applies_to_bundle_pipeline_sequences? && @taxonomy.applies_to_bundles?) ||
        (process_enabling && was_pipeline)

      if pipeline_turned_off
        rows = AssignmentCleanup.pipeline_sequence_assignments_for(@taxonomy)
        AssignmentCleanup.delete_assignments!(rows, taxonomy: @taxonomy)
      end
    end
  end
end
