# frozen_string_literal: true

module Biometry
  # One centile curve: the centile it was drawn at and its points, each a
  # plain hash of ga_weeks and grams.
  CentileSeries = Data.define(:centile, :points)
end
