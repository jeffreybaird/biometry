# frozen_string_literal: true

module Biometry
  # What the answer would have been just over a band edge.
  #
  # Reported only when the indexing gestation is close to an edge *and* the
  # recommendation differs on the other side. Proximity alone is not a
  # finding — every gestation is near some edge, and reporting that would be
  # hedging rather than disclosure.
  BoundarySensitivity = Data.define(:adjacent_band, :recommendation, :days_to_edge)
end
