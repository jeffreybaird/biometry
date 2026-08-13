# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      # Growth percentile by INTERGROWTH-21st (Stirnemann 2017).
      #
      # An equation standard: the LMS parameters are closed-form functions of
      # exact decimal weeks, so any centile is computable and there is no
      # outermost published column to bracket against. Those are the two ways
      # it differs from the table adapters, and why a uniform lookup interface
      # across the four would be wrong.
      #
      # Every coefficient comes from the manifest's `lms.*.coefficients`
      # blocks. The functional form is here because the published equations use
      # parentheses, integer exponents and a log, all outside Equation's
      # grammar — the same division of labour as the `efw` block in slice 3.
      #
      # Its pairing is self-referential: INTERGROWTH built its centiles from
      # its own AC+HC formula, so a mismatch means something different in kind
      # from NICHD's and WHO's, which name a foreign Hadlock model.
      class Intergrowth
        include Dry::Monads[:result]

        STANDARD = :intergrowth21

        def initialize(manifest:)
          @lms = manifest[:lms]
          @range = manifest[:valid_ga_weeks]
          @paired = manifest[:paired_formula].to_sym
          @source = manifest[:source]
        end

        def call(estimate:, ga:)
          return mismatch(estimate) unless estimate.formula == paired

          evaluate(estimate.value, ga.exact_weeks)
        end

        private

        attr_reader :lms, :range, :paired, :source

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

        # Table 2's Z-score. The lambda == 0 branch is published alongside the
        # general one; it is unreachable over 22-40 weeks but belongs here
        # because the standard states it.
        def z_score(grams, weeks)
          y = Math.log(grams)
          skew = lambda_at(weeks)
          median = mu(weeks)
          spread = sigma(weeks)
          return Math.log(y / median) / spread if skew.zero?

          (((y / median)**skew) - 1) / (spread * skew)
        end

        def lambda_at(ga)
          coefficients = lms[:lambda][:coefficients]
          coefficients[:intercept] +
            (coefficients[:ga_inv_sq] * (ga**-2)) +
            (coefficients[:ga_cubed] * (ga**3))
        end

        def mu(ga) = cubic_with_log(lms[:mu][:coefficients], ga)

        def sigma(ga)
          coefficients = lms[:sigma][:coefficients]
          coefficients[:scale] * cubic_with_log(coefficients, ga)
        end

        # mu and sigma share a shape: an intercept, a GA-cubed term, and a
        # GA-cubed term weighted by log GA.
        def cubic_with_log(coefficients, ga)
          coefficients[:intercept] +
            (coefficients[:ga_cubed] * (ga**3)) +
            (coefficients[:ga_cubed_log] * (ga**3) * Math.log(ga))
        end

        def provenance
          Provenance.new(standard: STANDARD, citation: source[:citation], formula: paired,
                         type: source[:type].to_sym, stratum: nil)
        end
      end
    end
  end
end
