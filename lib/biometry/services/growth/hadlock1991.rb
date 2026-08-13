# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      # Growth percentile by the Hadlock 1991 sonographic weight standard.
      #
      # The second equation standard, and unlike INTERGROWTH in every way that
      # matters here: dispersion is a constant percentage of the median rather
      # than an LMS triple, GA is decimal weeks to the nearest tenth, and the
      # chart pairs with the four-parameter Hadlock model rather than with
      # itself.
      #
      # Dispersion is 13.3%, not the 12.7% the abstract prints. The manifest's
      # `abstract_sd_contradicts_table` records why: Table 1's centiles are
      # exactly median x {0.750, 0.830, 1.170, 1.250} at every week, and 12.7%
      # puts the 3rd centile at 30 weeks 18 g above what the paper prints. The
      # figure is read from the manifest, not chosen here.
      #
      # Because dispersion is closed form there is no outermost published
      # column, so every weight in range gets a computed value.
      class Hadlock1991
        include Dry::Monads[:result]

        STANDARD = :hadlock_1991

        def initialize(manifest:)
          @coefficients = manifest[:median][:coefficients]
          @sd_pct = manifest[:dispersion][:sd_pct]
          @range = manifest[:valid_ga_weeks]
          @paired = manifest[:paired_formula].to_sym
          @source = manifest[:source]
        end

        def call(estimate:, ga:)
          return mismatch(estimate) unless estimate.formula == paired

          evaluate(estimate.value, ga.tenth_weeks)
        end

        private

        attr_reader :coefficients, :sd_pct, :range, :paired, :source

        def evaluate(grams, weeks)
          return out_of_range(weeks) unless weeks.between?(range.first, range.last)

          Success(percentile(grams, weeks))
        end

        def mismatch(estimate)
          Failure([:formula_chart_mismatch,
                   { chart: STANDARD, expected: paired, given: estimate.formula }])
        end

        def out_of_range(weeks)
          Failure([:out_of_range, { standard: STANDARD, ga_weeks: weeks, valid_range: range }])
        end

        def percentile(grams, weeks)
          Percentile.new(value: Normal.cdf(z_score(grams, weeks)) * 100, bound: :computed,
                         ga_weeks: weeks, interpolation: :closed_form, source: provenance)
        end

        # The SD is a percentage of the median, so it widens with gestation
        # while the ratio to the median stays fixed across all 31 weeks.
        def z_score(grams, weeks)
          centre = median(weeks)
          (grams - centre) / (centre * (sd_pct / 100.0))
        end

        # MA is menstrual age in decimal weeks to the nearest tenth.
        def median(weeks)
          Math.exp(coefficients[:intercept] +
                   (coefficients[:ma] * weeks) +
                   (coefficients[:ma_squared] * (weeks**2)))
        end

        def provenance
          Provenance.new(standard: STANDARD, citation: source[:citation], formula: paired,
                         type: source[:type].to_sym, stratum: nil)
        end
      end
    end
  end
end
