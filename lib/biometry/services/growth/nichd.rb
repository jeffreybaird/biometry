# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      # Growth percentile by the NICHD Fetal Growth Studies (Buck Louis 2015).
      #
      # A table standard with four race/ethnicity charts and no combined one.
      # With no stratum supplied it returns all four, because race/ethnicity is
      # self-reported and is never inferred or defaulted — and because the
      # spread is the paper's own headline finding: applying the white-derived
      # chart to everyone misclassifies as much as 15% of non-white fetuses as
      # growth restricted at the 5th centile. This is the one adapter that
      # returns several rows from one call, and it returns an Array in both
      # cases so no caller has to branch on the shape.
      #
      # Weeks are read, never interpolated. Table 2 tabulates weeks 10-14 but
      # the curves were fitted from 15, so those rows are refused rather than
      # read; the CSV keeps them so it can be diffed against the published
      # table.
      class Nichd
        include Dry::Monads[:result]

        STANDARD = :nichd
        CENTILES = { 3 => :p3, 5 => :p5, 10 => :p10, 50 => :p50,
                     90 => :p90, 95 => :p95, 97 => :p97 }.freeze

        def initialize(manifest:, table:)
          @table = table
          @range = manifest[:valid_ga_weeks]
          @paired = manifest[:paired_formula].to_sym
          @strata = manifest[:stratification][:values].map(&:to_sym)
          @source = manifest[:source]
        end

        def call(estimate:, ga:, stratum: nil)
          return mismatch(estimate) unless estimate.formula == paired
          return unknown_stratum(stratum) unless known?(stratum)

          read_at(estimate.value, ga.completed_weeks, charts_for(stratum))
        end

        private

        attr_reader :table, :range, :paired, :strata, :source

        def known?(stratum) = stratum.nil? || strata.include?(stratum)

        def charts_for(stratum) = stratum.nil? ? strata : [stratum]

        def mismatch(estimate)
          Failure([:formula_chart_mismatch,
                   { chart: STANDARD, expected: paired, given: estimate.formula }])
        end

        def out_of_range(weeks)
          Failure([:out_of_range, { standard: STANDARD, ga_weeks: weeks, valid_range: range }])
        end

        def unknown_stratum(stratum)
          Failure([:invalid_input, { stratum: stratum, available: strata }])
        end

        def read_at(grams, weeks, charts)
          return out_of_range(weeks) unless weeks.between?(range.first, range.last)

          Success(charts.map { |chart| read(grams, weeks, chart) })
        end

        def read(grams, weeks, chart)
          reading = Interpolation.call(weight: grams, centiles: columns(weeks, chart))
          Percentile.new(value: reading.value, bound: reading.bound, ga_weeks: weeks,
                         interpolation: reading.interpolation, source: provenance(chart))
        end

        def columns(weeks, chart)
          row = table.find { |r| r[:group] == chart.to_s && r[:ga_weeks] == weeks }
          CENTILES.to_h { |centile, key| [centile, row[key]] }
        end

        def provenance(chart)
          Provenance.new(standard: STANDARD, citation: source[:citation], formula: paired,
                         type: source[:type].to_sym, stratum: chart)
        end
      end
    end
  end
end
