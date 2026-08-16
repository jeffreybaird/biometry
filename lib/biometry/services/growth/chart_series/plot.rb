# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      class ChartSeries
        # Plots the one point a reader came to look at, by asking the chart's
        # own forward adapter — the same reading the report table prints. The
        # week it lands on is the week the chart itself read: completed for a
        # table, exact for a closed form.
        class Plot
          include Dry::Monads[:result]

          def initialize(adapter:, base:, sex: nil, stratum: nil)
            @adapter = adapter
            @base = base
            @sex = sex
            @stratum = stratum
          end

          def call(point)
            return Success(nil) unless point

            read(point).fmap { |reading| plotted(unwrap(reading), point) }
          end

          private

          attr_reader :adapter, :base, :sex, :stratum

          def read(point)
            adapter.call(estimate: point[:estimate], ga: point[:ga], **query)
          end

          # The option each chart's adapter takes; the others take none.
          def query
            case base
            when :who then { sex: sex }
            when :nichd then { stratum: stratum }
            else {}
            end
          end

          def plotted(reading, point)
            { ga_weeks: reading.ga_weeks, efw_g: point[:estimate].value,
              percentile: { value: reading.value, bound: reading.bound,
                            interpolation: reading.interpolation } }
          end

          # NICHD answers even a named stratum as a one-element spread.
          def unwrap(reading) = reading.is_a?(Array) ? reading.first : reading
        end
      end
    end
  end
end
