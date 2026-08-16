# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Growth
      class ChartSeries
        # Draws the centile curves of one chart: a grid of gestations, each
        # asked of the standard's own weight-at-centile service.
        #
        # A table standard's grid is its published weeks, one point per row; a
        # closed-form standard's is decimal weeks at the caller's step, the
        # end of the window always the last point — a curve must not stop
        # before the standard does.
        class Curves
          include Dry::Monads[:result]

          def initialize(reverse:, entry:, sex: nil, stratum: nil, step: nil)
            @reverse = reverse
            @entry = entry
            @sex = sex
            @stratum = stratum
            @step = step
          end

          def call(centiles)
            drawn = centiles.map { |centile| curve(centile) }
            drawn.find(&:failure?) || Success(drawn.map(&:value!))
          end

          private

          attr_reader :reverse, :entry, :sex, :stratum, :step

          def curve(centile)
            read = grid.map { |ga| ask(ga, centile) }
            failed = read.find(&:failure?)
            return failed if failed

            Success(CentileSeries.new(centile: centile, points: points_of(read)))
          end

          def points_of(read)
            read.map { |weight| { ga_weeks: weight.value!.ga_weeks, grams: weight.value!.grams } }
          end

          def ask(ga, centile)
            case reverse
            when Who::Centiles then reverse.call(ga: ga, centile: centile, sex: sex)
            when Nichd::Centiles then reverse.call(ga: ga, centile: centile, stratum: stratum)
            else reverse.call(ga: ga, centile: centile)
            end
          end

          def grid
            from, to = entry[:manifest][:valid_ga_weeks]
            return (from..to).map { |week| GestationalAge.from(weeks: week) } if table?

            computed(from, to).map { |week| GestationalAge.new(days: week * 7) }
          end

          def computed(from, to)
            weeks = from.to_f.step(by: (step || 1.0).to_f, to: to.to_f).to_a
            weeks << to.to_f if (to - weeks.last).abs > 1e-9
            weeks
          end

          def table? = entry[:manifest].dig(:source, :access).to_s == 'table'
        end
      end
    end
  end
end
