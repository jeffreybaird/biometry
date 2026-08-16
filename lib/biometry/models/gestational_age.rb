# frozen_string_literal: true

module Biometry
  # Total days. Never fractional weeks: float weeks produce off-by-one-day
  # errors that survive every test you would think to write.
  #
  # Each standard expresses GA differently. Conversion happens here, once, so
  # three adapters cannot round three different ways.
  GestationalAge = Data.define(:days) do
    def self.from(weeks:, days: 0) = new(days: (weeks * 7) + days)

    def weeks = days / 7
    def remainder_days = days % 7

    # INTERGROWTH-21st: exact decimal weeks. 30+3 => 30.428571
    def exact_weeks = days / 7.0

    # How the 1991 Hadlock paper coded its cohort's ages: decimal weeks to
    # the nearest tenth, 39w3d => 39.4. Kept as a conversion; no adapter
    # evaluates at it — Hadlock 1991 reads exact_weeks (decided 2026-08-15).
    def tenth_weeks = (days / 0.7).round / 10.0

    # NICHD, WHO: integer completed weeks.
    def completed_weeks = days / 7

    def +(other) = self.class.new(days: days + other)
    def -(other) = self.class.new(days: days - other)

    def to_s = "#{weeks}w#{remainder_days}d"
  end
end
