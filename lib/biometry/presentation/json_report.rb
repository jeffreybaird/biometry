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

      # `redating` is optional, and absent rather than null when nobody asked:
      # a key holding null reads as a question that was asked and could not be
      # answered.
      def call(dating:, ga:, studies:, redating: nil)
        rows = studies.flat_map(&:growth)
        document = sections(dating, ga, studies)
        document[:redating] = redated(redating) if redating
        JSON.generate(document.merge(sources: citations(rows, redating), notes: NOTES))
      end

      private

      # The measurements and the rows sit inside the study they were read from.
      # The collection is present whether there is one study or several: a
      # consumer that had to branch on the document's shape would get it wrong
      # the first time two studies arrived.
      def sections(dating, ga, studies)
        { gestational_age: { text: ga.to_s, days: ga.days },
          dating: dating.map { |derivation, result| dated(derivation, result) },
          studies: studies.map { |study| studied(study) } }
      end

      def studied(study)
        { date: study.date.iso8601,
          gestational_age: { text: study.ga.to_s, days: study.ga.days },
          measurements: study.scan.measurements.map { |m| measurement(m) },
          growth: study.growth.map { |row| growth_row(row) } }
      end

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

      # Same rule as the table: every standard with an entry is cited, whether
      # or not its reading succeeded. A document listing two sources for four
      # entries is the same defect there as here.
      def citations(growth, redating = nil)
        rows = growth.flat_map { |row| [row[:citation], cited(row[:weight])] }
        (rows + [redating && cited(redating)]).compact.uniq
      end

      # ------------------------------------------------------------- redating

      def redated(redating)
        return { error: error(redating.failure) } if redating.failure?

        decision = redating.value!
        decided(decision).merge(banded(decision)).compact
      end

      def decided(decision)
        { recommendation: decision.recommendation, discrepancy_days: decision.discrepancy_days,
          established_edd: decision.established_edd.iso8601,
          proposed_edd: decision.proposed_edd.iso8601,
          indexing_ga: { text: decision.indexing_ga.to_s, days: decision.indexing_ga.days },
          rule: decision.rule, citation: decision.source.citation }
      end

      # Absent rather than null: a band and a threshold a program could act on
      # played no part when a rule decided.
      def banded(decision)
        { band: decision.band, threshold_days: decision.threshold_days,
          zone: zoned(decision.zone), caveat: quoted(decision.caveat),
          boundary_sensitivity: bordering(decision.boundary_sensitivity) }
      end

      def zoned(zone) = zone && { from_days: zone.first, to_days: zone.last }

      def quoted(caveat) = caveat && { id: caveat.id, text: caveat.text }

      def bordering(sensitivity)
        return nil unless sensitivity

        { adjacent_band: sensitivity.adjacent_band, recommendation: sensitivity.recommendation,
          days_to_edge: sensitivity.days_to_edge }
      end

      def cited(result) = result.success? ? result.value!.source.citation : nil
    end
  end
end
