# frozen_string_literal: true

module Biometry
  # One derivation of when a pregnancy is due, and how far along it is.
  #
  # A due date on its own is not a report. Two derivations of the same
  # pregnancy disagree by days, and slice 2 has to decide between them, so each
  # carries the date it was evaluated at, the gestational age there, which
  # derivation produced it and the convention that derivation applied. Drop any
  # of those and an EDD arrives as a bare number with no way to tell an IVF
  # transfer date from a Naegele estimate.
  #
  # `edd` and `reference_date` are Dates. This library has no times and no
  # zones.
  #
  # The member is `derivation`, never `method`: Data.define(:method) shadows
  # Object#method and breaks every reflective caller. Estimate and Percentile
  # carry the same regression test for the same reason.
  DatingEstimate = Data.define(:edd, :ga, :reference_date, :derivation, :source) do
    def to_s
      "EDD #{edd} — #{ga} at #{reference_date} (by #{derivation})"
    end
  end
end
