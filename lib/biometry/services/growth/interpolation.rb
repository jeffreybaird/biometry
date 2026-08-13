# frozen_string_literal: true

module Biometry
  module Services
    module Growth
      # Converts a weight to a percentile against published centile columns.
      #
      # This exists as one collaborator rather than as a method on each table
      # adapter because PROJECT.md pins the rule as identical in NICHD and WHO.
      # Two adapters each implementing it is two rules, and the divergence
      # would show up only in the tails.
      #
      # The rule is linear in weight, which is undefined in every source and
      # therefore ours rather than the standard's — hence Reading names the
      # method it used. WHO's distribution is deliberately asymmetric, so this
      # approximates worse there than for the log-normal standards; that is
      # stated in output rather than hidden.
      #
      # Outside the outermost column supplied it reports the open bracket. A
      # table cannot answer further out, and extrapolating would invent a
      # centile the paper never published.
      module Interpolation
        Reading = Data.define(:value, :bound, :interpolation)

        module_function

        # `centiles` maps centile => grams. It is answered exactly as given:
        # WHO's sex-specific tables omit the 2.5th and 97.5th, so the same
        # weight brackets differently there, and widening the set handed over
        # would answer from a chart the caller did not ask for.
        def call(weight:, centiles:)
          points = centiles.sort_by { |_, grams| grams }
          return below(points.first) if weight < points.first.last
          return above(points.last) if weight > points.last.last

          interpolate(weight, points)
        end

        def below(point) = Reading.new(value: point.first.to_f, bound: :below, interpolation: :none)

        def above(point) = Reading.new(value: point.first.to_f, bound: :above, interpolation: :none)

        def interpolate(weight, points)
          lower, upper = bracket(weight, points)
          Reading.new(value: between(weight, lower, upper), bound: :computed,
                      interpolation: :linear_in_weight)
        end

        def bracket(weight, points)
          upper_index = points.index { |_, grams| grams >= weight }
          [points[[upper_index - 1, 0].max], points[upper_index]]
        end

        def between(weight, lower, upper)
          lower_centile, lower_grams = lower
          upper_centile, upper_grams = upper
          return lower_centile.to_f if upper_grams == lower_grams

          span = (weight - lower_grams).fdiv(upper_grams - lower_grams)
          lower_centile + (span * (upper_centile - lower_centile))
        end
      end
    end
  end
end
