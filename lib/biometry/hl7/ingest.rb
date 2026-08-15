# frozen_string_literal: true

module Biometry
  module Hl7
    # What a parsed ORU^R01 yielded, diagnostics included.
    #
    # The diagnostics travel with the scans rather than being raised or
    # dropped. A message is routinely partly readable — one vendor's extra
    # observation, one segment with prose where a number belongs — and
    # discarding the rest of it over either would lose the scan a clinician
    # actually wants. Equally, dropping them silently would present a partial
    # read as a complete one.
    Ingest = Data.define(:scans, :unrecognised, :malformed) do
      def clean? = unrecognised.empty? && malformed.empty?
    end

    # An observation this library could not use. `reason` is :identifier when
    # nothing in the mapping names it, or :units when OBX-6 was neither mm nor
    # cm — the units travel either way, because whoever transcribes the LOINC
    # mapping needs to know what the observation would arrive in.
    Unrecognised = Data.define(:segment, :identifier, :units, :reason)

    # A segment that could not be read, named by its 1-based position in the
    # message and the HL7 field position that failed, so a caller can point at
    # a line rather than at the file.
    Malformed = Data.define(:segment, :field, :reason)
  end
end
