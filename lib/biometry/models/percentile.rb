# frozen_string_literal: true

module Biometry
  # Where a weight falls on one growth standard.
  #
  # The three members beyond the number are each pinned by a slice 4 decision
  # rather than by taste:
  #
  # - `ga_weeks` is the week actually read or evaluated at, in that standard's
  #   own units. Table standards read a completed week because that is what
  #   they publish; the equation standards evaluate at exact or tenth weeks.
  #   Naming it means no reader has to reconstruct which convention applied.
  # - `interpolation` names the method between centiles, because linear-in-
  #   weight is our rule and not the standard's.
  # - `source` names the standard and the chart. A percentile without it is not
  #   comparable across standards, which is the only reason this library
  #   exists.
  #
  # `bound` is :computed, or :below/:above when the weight lies outside the
  # outermost published column and `value` is that column rather than an
  # extrapolation.
  #
  # The member is `interpolation`, never `method`: Data.define(:method) shadows
  # Object#method and breaks every reflective caller.
  PERCENTILE_BOUNDS = %i[computed below above].freeze
  INTERPOLATION_METHODS = %i[closed_form linear_in_weight none].freeze

  Percentile = Data.define(:value, :bound, :ga_weeks, :interpolation, :source) do
    def computed? = bound == :computed

    # Reports a number and its source, never a threshold verdict.
    def to_s
      "#{prefix}#{format('%.1f', value)} centile, #{source} at #{ga_weeks} weeks"
    end

    private

    def prefix
      case bound
      when :below then 'below '
      when :above then 'above '
      else ''
      end
    end
  end
end
