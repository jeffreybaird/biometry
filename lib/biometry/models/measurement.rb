# frozen_string_literal: true

module Biometry
  # The biometric parameters any formula in this library reads.
  MEASUREMENT_KINDS = %i[bpd hc ac fl hl crl].freeze

  # A single biometric measurement. Millimetres on the way in, because that is
  # what HL7 OBX-5 carries; every published formula wants centimetres, so the
  # conversion is exposed rather than left to each caller.
  Measurement = Data.define(:kind, :mm) do
    def cm = mm / 10.0

    def to_s = "#{kind.to_s.upcase} #{cm} cm"
  end
end
