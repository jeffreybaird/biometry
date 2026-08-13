# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      # Growth percentile by the WHO Fetal Growth Charts (Kiserud 2017).
      #
      # The second table standard, reading by the same two pinned rules as
      # NICHD: the row for the completed week, and linear interpolation in
      # weight. Those rules live in Interpolation so there is one of each
      # rather than two.
      #
      # Unlike NICHD it publishes a combined chart, so an unsupplied sex has a
      # published answer rather than a spread. Also unlike NICHD it is a
      # reference rather than a prescriptive standard — complicated pregnancies
      # were deliberately retained — so its 10th centile does not mean what
      # NICHD's does. That distinction rides in the provenance.
      #
      # Tables 14 and 15 omit the 2.5th and 97.5th columns and the loader
      # leaves those cells nil, because the absence is data. A weight is
      # bracketed against the columns the chart actually read published; a
      # sexed row is never widened from the combined one.
      class Who
        include Dry::Monads[:result]

        STANDARD = :who
        CENTILES = { 2.5 => :p2_5, 5 => :p5, 10 => :p10, 25 => :p25, 50 => :p50,
                     75 => :p75, 90 => :p90, 95 => :p95, 97.5 => :p97_5 }.freeze
        COMBINED = :combined

        def initialize(manifest:, table:)
          @table = table
          @range = manifest[:valid_ga_weeks]
          @paired = manifest[:paired_formula].to_sym
          @sexes = manifest[:stratification][:values].map(&:to_sym)
          @source = manifest[:source]
        end

        def call(estimate:, ga:, sex: nil)
          chart = sex || COMBINED
          return mismatch(estimate) unless estimate.formula == paired
          return unknown_sex(sex) unless sexes.include?(chart)

          read_at(estimate.value, ga.completed_weeks, chart)
        end

        private

        attr_reader :table, :range, :paired, :sexes, :source

        def mismatch(estimate)
          Failure([:formula_chart_mismatch,
                   { chart: STANDARD, expected: paired, given: estimate.formula }])
        end

        def out_of_range(weeks)
          Failure([:out_of_range, { standard: STANDARD, ga_weeks: weeks, valid_range: range }])
        end

        def unknown_sex(sex)
          Failure([:invalid_input, { sex: sex, available: sexes }])
        end

        def read_at(grams, weeks, chart)
          return out_of_range(weeks) unless weeks.between?(range.first, range.last)

          Success(read(grams, weeks, chart))
        end

        def read(grams, weeks, chart)
          reading = Interpolation.call(weight: grams, centiles: columns(weeks, chart))
          Percentile.new(value: reading.value, bound: reading.bound, ga_weeks: weeks,
                         interpolation: reading.interpolation, source: provenance(chart))
        end

        # Omitted columns arrive as nil and are dropped rather than filled, so
        # the bracket reflects what this chart published.
        def columns(weeks, chart)
          row = table.find { |r| r[:sex] == chart.to_s && r[:ga_weeks] == weeks }
          CENTILES.filter_map { |centile, key| [centile, row[key]] if row[key] }.to_h
        end

        def provenance(chart)
          Provenance.new(standard: STANDARD, citation: source[:citation], formula: paired,
                         type: source[:type].to_sym, stratum: chart)
        end
      end
    end
  end
end
