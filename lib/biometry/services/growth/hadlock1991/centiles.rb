# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      class Hadlock1991
        # The other direction through the 1991 standard: given a week and a
        # centile, the weight the closed form gives.
        #
        # Because dispersion is a closed-form function of the median, any
        # centile strictly inside (0, 100) is computable — the same reason the
        # percentile direction has no outermost published column. The variant
        # question is the same one the percentile adapter answers, and it is
        # answered the same way: the id and the SD come from the manifest's
        # `variants` block, and an unknown variant raises because that is a
        # developer error, not a runtime condition.
        class Centiles
          include Dry::Monads[:result]

          def initialize(manifest:, variant: nil)
            select_variant(manifest, variant || manifest[:default].to_sym)
            @coefficients = manifest[:median][:coefficients]
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

          attr_reader :standard, :sd_pct, :coefficients, :range, :paired, :source

          def select_variant(manifest, chosen)
            selected = manifest[:variants].fetch(chosen)
            @standard = selected[:id].to_sym
            @sd_pct = selected[:dispersion][:sd_pct]
          end

          # Strictly inside (0, 100): the 0th and 100th centiles are not
          # weights, and refusing here keeps the quantile's ArgumentError —
          # a bug's exit 70 — for genuine bugs.
          def computable?(centile) = centile.is_a?(Numeric) && centile.positive? && centile < 100

          def out_of_range(weeks)
            Failure([:out_of_range, { standard: standard, ga_weeks: weeks, valid_range: range }])
          end

          def invalid(centile)
            Failure([:invalid_input, { centile: centile, valid_range: [0, 100] }])
          end

          # C(alpha) = median * (1 + Z(alpha) * sd_pct/100), the manifest's own
          # centile form.
          def weight(centile, weeks)
            grams = Median.at(coefficients, weeks) *
                    (1 + (Normal.inverse_cdf(centile / 100.0) * (sd_pct / 100.0)))
            ChartWeight.new(centile: centile, grams: grams, ga_weeks: weeks, source: provenance)
          end

          def provenance
            Provenance.new(standard: standard, citation: source[:citation], formula: paired,
                           type: source[:type].to_sym, stratum: nil)
          end
        end
      end
    end
  end
end
