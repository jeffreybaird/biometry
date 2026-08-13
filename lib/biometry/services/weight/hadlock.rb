# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Weight
      # Estimated fetal weight by one of the Hadlock 1985 Table II regressions.
      #
      # The coefficients come from the manifest's `equation:` string by way of
      # Equation; all four models are log base 10, so the inverse applied here
      # is 10**, matching the `log10(W) =` each string declares.
      #
      # This is also where data/hadlock.yml's per-row `verified` flags are
      # enforced. ReferenceData refuses a file whose top-level `verified` is
      # false, but reads no deeper, so a row resting on a single unchecked
      # transcription would otherwise be offered as freely as a confirmed one.
      # Only hc_ac_fl currently has confirmation outside this project.
      #
      # An unverified row is reported as unavailable rather than raised on: the
      # file is sound and one row within it is withheld, which is a condition a
      # caller can reasonably act on.
      class Hadlock
        include Dry::Monads[:result]

        STANDARD = :hadlock

        def initialize(manifest:, formula:)
          @formulas = manifest[:efw_formulas]
          @formula = formula
        end

        def call(scan)
          row = formulas[formula]
          return unsupported unless row && row[:verified]

          required = row[:requires].map(&:to_sym)
          return insufficient(scan, required) unless scan.supports?(required)

          Success(estimate(scan, row, required))
        end

        private

        attr_reader :formulas, :formula

        def available = formulas.select { |_, row| row[:verified] }.keys

        def unsupported
          Failure([:unsupported_standard, { requested: formula, available: available }])
        end

        def insufficient(scan, required)
          Failure([:insufficient_data, { required: required, given: scan.kinds }])
        end

        def estimate(scan, row, required)
          Estimate.new(value: grams(scan, row, required), unit: 'g', method: formula,
                       inputs: required, source: provenance)
        end

        def grams(scan, row, required)
          centimetres = required.to_h { |kind| [kind, scan.cm(kind)] }
          10**Equation.parse(row[:equation]).evaluate(centimetres)
        end

        # data/hadlock.yml carries its citations in YAML comments only, with no
        # machine-readable `source:` block. Left nil rather than supplied from
        # outside data/.
        def provenance
          Provenance.new(standard: STANDARD, citation: nil, formula: formula,
                         type: nil, stratum: nil)
        end
      end
    end
  end
end
