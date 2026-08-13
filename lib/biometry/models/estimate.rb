# frozen_string_literal: true

module Biometry
  # A computed value and everything needed to attribute it.
  #
  # `inputs` is the measurement set the value was produced from, so a reader
  # can tell an INTERGROWTH AC+HC weight from a Hadlock four-parameter one
  # without inferring it from the formula name.
  #
  # NB: the member `method` overrides Data#method on instances, so reflection
  # (`estimate.method(:to_s)`) does not work on one of these — use
  # `Estimate.instance_method` instead. Kept because it is the pinned contract
  # in PROJECT.md 0b; renaming it to :formula would remove the hazard and is
  # worth doing before slice 3 puts it in every result.
  # rubocop:disable Lint/DataDefineOverride
  Estimate = Data.define(:value, :unit, :method, :inputs, :source) do
    # rubocop:enable Lint/DataDefineOverride
    def to_s = "#{value} #{unit} (#{method})"
  end
end
