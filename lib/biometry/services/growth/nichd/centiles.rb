# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      class Nichd
        # The other direction through the NICHD tables: given a week, a
        # centile and a chart, the weight the paper publishes.
        #
        # Tabulated centiles only: the seven columns of Table 2 are what the
        # paper printed, and any other centile would have to be invented from
        # a distribution this service does not model. With no stratum it
        # answers with all four charts, for the same reason the percentile
        # adapter does — race/ethnicity is self-reported and never defaulted,
        # and the spread across charts is the paper's own headline finding.
        class Centiles
          include Dry::Monads[:result]

          def initialize(manifest:, table:)
            @table = table
            @range = manifest[:valid_ga_weeks]
            @paired = manifest[:paired_formula].to_sym
            @tabulated = manifest[:centiles][:tabulated]
            @strata = manifest[:stratification][:values].map(&:to_sym)
            @source = manifest[:source]
          end

          # Same precedence as Who::Centiles: range, then stratum, then
          # centile. Without a valid chart there is no centile list to check a
          # request against.
          def call(ga:, centile:, stratum: nil)
            read(ga.completed_weeks, centile, stratum)
          end

          private

          attr_reader :table, :range, :paired, :tabulated, :strata, :source

          def read(weeks, centile, stratum)
            return out_of_range(weeks) unless weeks.between?(range.first, range.last)
            return unknown_stratum(stratum) unless stratum.nil? || strata.include?(stratum)
            return unsupported(centile) unless tabulated.include?(centile)

            answer(weeks, centile, stratum)
          end

          # One chart when one was named, the whole spread when none was.
          def answer(weeks, centile, stratum)
            return Success(weight(centile, weeks, stratum)) if stratum

            Success(strata.map { |chart| weight(centile, weeks, chart) })
          end

          def out_of_range(weeks)
            Failure([:out_of_range, { standard: STANDARD, ga_weeks: weeks, valid_range: range }])
          end

          def unknown_stratum(stratum)
            Failure([:invalid_input, { stratum: stratum, available: strata }])
          end

          def unsupported(centile)
            Failure([:unsupported_centile,
                     { standard: STANDARD, requested: centile, available: tabulated }])
          end

          def weight(centile, weeks, chart)
            row = table.find { |r| r[:group] == chart.to_s && r[:ga_weeks] == weeks }
            ChartWeight.new(centile: centile, grams: row[CENTILES.fetch(centile)],
                            ga_weeks: weeks, source: provenance(chart))
          end

          def provenance(chart)
            Provenance.new(standard: STANDARD, citation: source[:citation], formula: paired,
                           type: source[:type].to_sym, stratum: chart)
          end
        end
      end
    end
  end
end
