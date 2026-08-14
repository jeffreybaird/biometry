# frozen_string_literal: true

module Biometry
  REDATING_RECOMMENDATIONS = %i[keep discretionary redate].freeze

  # What the redating policy decided, and the reasoning that produced it.
  #
  # The recommendation is tri-state rather than a boolean. A boolean cannot
  # carry the discretionary zone, and `if decision.redate?` would silently
  # discard exactly the case the guideline most wants a human to look at — so
  # there is deliberately no such predicate and a caller has to read the value.
  #
  # Both dates travel and neither is revised. An established EDD is not
  # casually rewritten; subsequent scans are measured against it, and this
  # object is the reasoning, not a replacement date.
  #
  # `band`, `threshold_days` and `zone` are absent when a clinical rule decided
  # instead — an IVF-dated pregnancy is never redated, and filling those in
  # would report values that played no part.
  RedatingDecision = Data.define(
    :recommendation, :discrepancy_days, :established_edd, :proposed_edd,
    :indexing_ga, :band, :threshold_days, :zone, :caveat, :rule,
    :boundary_sensitivity, :source
  ) do
    def to_s = "#{recommendation} — #{discrepancy_days} day(s) at #{indexing_ga}"
  end
end
