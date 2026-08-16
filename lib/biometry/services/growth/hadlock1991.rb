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
      # The paper carries two irreconcilable dispersion figures — 12.7% in the
      # abstract, 13.3% implied by its own Table 1 — and which to use is a
      # contested clinical question (the manifest's `dispersion_contested`
      # known_issue carries the dispute and its citations). So the standard is
      # served as two variants, one per figure, and both are reported: this
      # library's thesis is that disagreements get surfaced, not resolved by
      # picking a side. Everything except the SD — median equation, range,
      # pairing, GA convention — is shared. The variant, its identity and its
      # SD all come from the manifest's `variants` block, never from here, so
      # a corrected figure is a data change only.
      #
      # Because dispersion is closed form there is no outermost published
      # column, so every weight in range gets a computed value.
      class Hadlock1991
        include Dry::Monads[:result]

        # `variant: nil` resolves to the manifest's stated default rather
        # than to an ordering accident. An unknown variant raises: that is a
        # developer error, not a runtime condition for a caller to branch on.
        def initialize(manifest:, variant: nil)
          select_variant(manifest, variant || manifest[:default].to_sym)
          @coefficients = manifest[:median][:coefficients]
          @range = manifest[:valid_ga_weeks]
          @paired = manifest[:paired_formula].to_sym
          @source = manifest[:source]
        end

        def call(estimate:, ga:)
          return mismatch(estimate) unless estimate.formula == paired

          evaluate(estimate.value, ga.tenth_weeks)
        end

        private

        attr_reader :standard, :coefficients, :sd_pct, :range, :paired, :source

        def select_variant(manifest, chosen)
          selected = manifest[:variants].fetch(chosen)
          @standard = selected[:id].to_sym
          @sd_pct = selected[:dispersion][:sd_pct]
        end

        def evaluate(grams, weeks)
          return out_of_range(weeks) unless weeks.between?(range.first, range.last)

          Success(percentile(grams, weeks))
        end

        def mismatch(estimate)
          Failure([:formula_chart_mismatch,
                   { chart: standard, expected: paired, given: estimate.formula }])
        end

        def out_of_range(weeks)
          Failure([:out_of_range, { standard: standard, ga_weeks: weeks, valid_range: range }])
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
          Provenance.new(standard: standard, citation: source[:citation], formula: paired,
                         type: source[:type].to_sym, stratum: nil)
        end
      end
    end
  end
end
