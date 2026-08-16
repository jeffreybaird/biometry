# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      class Intergrowth
        # The other direction through INTERGROWTH-21st: given a week and a
        # centile, the weight the LMS closed form gives.
        #
        # The inversion is the manifest's own `centile` block — for lambda
        # not zero, log(C) = mu * (Z*sigma*lambda + 1)^(1/lambda); for lambda
        # zero, log(C) = mu * exp(sigma * Z) — the exact mirror of the
        # Z-score the percentile direction evaluates, on the same
        # log-of-grams scale.
        class Centiles
          include Dry::Monads[:result]

          def initialize(manifest:)
            @lms = manifest[:lms]
            @range = manifest[:valid_ga_weeks]
            @paired = manifest[:paired_formula].to_sym
            @source = manifest[:source]
          end

          # Range before centile, mirroring the table services: a chart that
          # cannot answer the week has no business judging the centile.
          def call(ga:, centile:)
            weeks = ga.exact_weeks
            return out_of_range(weeks) unless weeks.between?(range.first, range.last)
            return invalid(centile) unless computable?(centile)

            Success(weight(centile, weeks))
          end

          private

          attr_reader :lms, :range, :paired, :source

          # Strictly inside (0, 100): the 0th and 100th centiles are not
          # weights, and refusing here keeps the quantile's ArgumentError —
          # a bug's exit 70 — for genuine bugs.
          def computable?(centile) = centile.is_a?(Numeric) && centile.positive? && centile < 100

          def out_of_range(weeks)
            Failure([:out_of_range, { standard: STANDARD, ga_weeks: weeks, valid_range: range }])
          end

          def invalid(centile)
            Failure([:invalid_input, { centile: centile, valid_range: [0, 100] }])
          end

          def weight(centile, weeks)
            ChartWeight.new(centile: centile, grams: Math.exp(log_weight(centile, weeks)),
                            ga_weeks: weeks, source: provenance)
          end

          # Y = log(EFW); the lambda == 0 branch is published alongside the
          # general one and belongs here because the standard states it.
          def log_weight(centile, weeks)
            z = Normal.inverse_cdf(centile / 100.0)
            skew, median, spread = Lms.at(lms, weeks)
            return median * Math.exp(spread * z) if skew.zero?

            median * (((z * spread * skew) + 1)**(1.0 / skew))
          end

          def provenance
            Provenance.new(standard: STANDARD, citation: source[:citation], formula: paired,
                           type: source[:type].to_sym, stratum: nil)
          end
        end
      end
    end
  end
end
