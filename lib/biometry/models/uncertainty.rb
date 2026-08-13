# frozen_string_literal: true

module Biometry
  # How wrong a value might be, and on what basis.
  #
  # `basis` is not decoration. Hadlock 1985 Table I reports error by
  # birth-weight stratum and the errors are asymmetric — the recommended model
  # runs about 4.6% low below 1500 g and 6.3% high above 4000 g — so a pooled
  # SD understates uncertainty in exactly the tails this library is aimed at.
  # Until those strata are transcribed into data/, every value here is
  # :pooled, and it says so rather than letting a reader assume otherwise.
  UNCERTAINTY_BASES = %i[pooled stratified].freeze

  Uncertainty = Data.define(:sd_pct, :basis) do
    def self.pooled(sd_pct) = new(sd_pct: sd_pct, basis: :pooled)

    def to_s = "#{sd_pct}% SD (#{basis})"
  end
end
