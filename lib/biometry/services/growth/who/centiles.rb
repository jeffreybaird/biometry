# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      class Who
        # The other direction through the WHO tables: given a week and a
        # centile, the weight WHO publishes.
        #
        # Separate from the percentile adapter because it answers a different
        # question, and present in slice 4 because pinned decision 6 is about a
        # centile *request*. Tables 14 and 15 omit the 2.5th and 97.5th
        # columns; answering those from the combined table would put two
        # populations in one row, so the request is refused with what is
        # available. That refusal is the behaviour being pinned, and it is not
        # reachable from the percentile direction — there, a weight past the
        # last column is simply an open bracket.
        class Centiles
          include Dry::Monads[:result]

          def initialize(manifest:, table:)
            @table = table
            @range = manifest[:valid_ga_weeks]
            @paired = manifest[:paired_formula].to_sym
            @published = manifest[:centiles]
            @sexes = manifest[:stratification][:values].map(&:to_sym)
            @source = manifest[:source]
          end

          def call(ga:, centile:, sex: nil)
            chart = sex || COMBINED
            return unknown_sex(sex) unless sexes.include?(chart)

            read(ga.completed_weeks, centile, chart)
          end

          private

          attr_reader :table, :range, :paired, :published, :sexes, :source

          def read(weeks, centile, chart)
            return out_of_range(weeks) unless weeks.between?(range.first, range.last)
            return unsupported(centile, chart) unless available(chart).include?(centile)

            Success(weight(centile, weeks, chart))
          end

          def available(chart)
            published[chart == COMBINED ? :combined : :sex_specific]
          end

          def out_of_range(weeks)
            Failure([:out_of_range, { standard: STANDARD, ga_weeks: weeks, valid_range: range }])
          end

          # A sex WHO does not publish is a caller's mistake, not a bug: it
          # gets a Result to branch on and exit 1, the same shape the
          # percentile adapter returns. Without this the table lookup finds no
          # row and the nil dereference raises, which exe/ maps to exit 70.
          def unknown_sex(sex)
            Failure([:invalid_input, { sex: sex, available: sexes }])
          end

          def unsupported(centile, chart)
            Failure([:unsupported_centile,
                     { standard: STANDARD, requested: centile, available: available(chart) }])
          end

          def weight(centile, weeks, chart)
            row = table.find { |r| r[:sex] == chart.to_s && r[:ga_weeks] == weeks }
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
