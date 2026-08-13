# frozen_string_literal: true

module Biometry
  # A computed value and everything needed to attribute it.
  #
  # `inputs` is the measurement set the value was produced from, so a reader
  # can tell an INTERGROWTH AC+HC weight from a Hadlock four-parameter one
  # without inferring it from the formula name.
  #
  # The member is `formula`, never `method`: `Data.define(:method)` generates a
  # reader that overrides `Object#method`, which breaks introspection and
  # anything in RSpec or a debugger that reaches for it.
  #
  # `uncertainty` is nil when the standard publishes nothing convertible to
  # one. INTERGROWTH is the live case: it reports a mean absolute prediction
  # error, which is not a standard deviation, and relabelling it as one would
  # be inventing a figure the paper never gave.
  Estimate = Data.define(:value, :unit, :formula, :inputs, :source, :uncertainty) do
    def to_s = "#{value} #{unit} (#{formula})"
  end
end
