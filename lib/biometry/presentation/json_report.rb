# frozen_string_literal: true

require 'json'

module Biometry
  module Presentation
    # The same report as a machine-readable document.
    #
    # Undecorated: no colour, no alignment, nothing but the JSON. It is not the
    # table with markup stripped — the table rounds a percentile to a whole
    # ordinal because a reader comparing standards is not reading a decimal
    # place, and a program must not be handed a precision that was already
    # discarded. So values here are unrounded and brackets are structured
    # rather than phrased.
    #
    # Refusals travel as a tag and a payload a program can branch on, for the
    # same reason the table prints them: an entry that vanished would read as
    # a standard that was never consulted.
    class JsonReport
      NOTES = ['SD is pooled; per-stratum figures are not transcribed.'].freeze

      def call(dating:, ga:, scan:, growth:)
        JSON.generate(
          gestational_age: { text: ga.to_s, days: ga.days },
          measurements: scan.measurements.map { |m| measurement(m) },
          dating: dating.map { |derivation, result| dated(derivation, result) },
          growth: growth.map { |row| growth_row(row) },
          sources: citations(growth), notes: NOTES
        )
      end

      private

      def measurement(measurement)
        { kind: measurement.kind, mm: measurement.mm, cm: measurement.cm }
      end

      def error(failure)
        tag, details = failure
        { tag: tag, details: details }
      end

      # ---------------------------------------------------------------- dating

      def dated(derivation, result)
        return { derivation: derivation, error: error(result.failure) } if result.failure?

        dating_entry(derivation, result.value!)
      end

      def dating_entry(derivation, estimate)
        { derivation: derivation, edd: estimate.edd.iso8601,
          reference_date: estimate.reference_date.iso8601,
          ga: { text: estimate.ga.to_s, days: estimate.ga.days },
          parameters: estimate.parameters, citation: estimate.source.citation }
      end

      # ---------------------------------------------------------------- growth

      def growth_row(row)
        chart_of(row).merge(readings(row))
      end

      def chart_of(row)
        { standard: row[:standard], stratum: stratum_of(row), type: type_of(row) }
      end

      # A row carries whichever of the three it has. A refused chart still
      # reports the weight it did produce, because that weight is a finding.
      def readings(row)
        failure = failure_of(row)
        { weight: reading(row[:weight]) { |value| weight(value) },
          percentile: reading(row[:report]) { |value| percentile(value) },
          error: failure && error(failure) }.compact
      end

      def reading(result) = result.success? ? yield(result.value!) : nil

      def failure_of(row)
        return row[:weight].failure if row[:weight].failure?

        row[:report].failure if row[:report].failure?
      end

      def stratum_of(row) = row[:report].success? ? row[:report].value!.source.stratum : nil

      def type_of(row) = row[:report].success? ? row[:report].value!.source.type : nil

      def weight(estimate)
        { value: estimate.value, unit: estimate.unit, formula: estimate.formula,
          inputs: estimate.inputs, uncertainty: uncertainty(estimate.uncertainty),
          citation: estimate.source.citation }
      end

      # Null rather than a number: INTERGROWTH publishes a mean absolute
      # prediction error, and a consumer must not find something here to
      # relabel as an SD.
      def uncertainty(uncertainty)
        return nil if uncertainty.nil?

        { sd_pct: uncertainty.sd_pct, basis: uncertainty.basis }
      end

      def percentile(percentile)
        { value: percentile.value, bound: percentile.bound, ga_weeks: percentile.ga_weeks,
          interpolation: percentile.interpolation, citation: percentile.source.citation }
      end

      def citations(growth)
        growth.flat_map { |row| [cited(row[:weight]), cited(row[:report])] }.compact.uniq
      end

      def cited(result) = result.success? ? result.value!.source.citation : nil
    end
  end
end
