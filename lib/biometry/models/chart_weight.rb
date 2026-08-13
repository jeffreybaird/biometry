# frozen_string_literal: true

module Biometry
  # A weight a chart publishes at a given week and centile — the other
  # direction through a growth standard from Percentile.
  #
  # `ga_weeks` is the week actually read, which for a table standard is the
  # completed week rather than the GA supplied.
  ChartWeight = Data.define(:centile, :grams, :ga_weeks, :source) do
    def to_s = "#{grams} g at the #{centile} centile, #{source}, #{ga_weeks} weeks"
  end
end
