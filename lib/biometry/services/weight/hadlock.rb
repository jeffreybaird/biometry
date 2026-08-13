# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Weight
      # Estimated fetal weight by one of the Hadlock 1985 Table II regressions.
      #
      # The coefficients come from the manifest's `equation:` string by way of
      # Equation; every Table II model is log base 10, so the inverse applied
      # here is 10**, matching the `log10(W) =` each string declares.
      #
      # There is no verified check here. ReferenceData prunes unverified
      # entries before a manifest reaches a service, so an unverified formula
      # is simply not in `efw_formulas` and takes the same path as a formula
      # id that never existed. That is deliberate: a guard here would be an
      # obligation every future adapter has to remember.
      class Hadlock
        include Dry::Monads[:result]

        STANDARD = :hadlock

        def initialize(manifest:, formula:)
          @formulas = manifest[:efw_formulas]
          @formula = formula
        end

        def call(scan)
          row = formulas[formula]
          return unsupported unless row

          required = row[:requires].map(&:to_sym)
          return insufficient(scan, required) unless scan.supports?(required)

          Success(estimate(scan, row, required))
        end

        private

        attr_reader :formulas, :formula

        def available = formulas.keys

        def unsupported
          Failure([:unsupported_standard, { requested: formula, available: available }])
        end

        def insufficient(scan, required)
          Failure([:insufficient_data, { required: required, given: scan.kinds }])
        end

        def estimate(scan, row, required)
          Estimate.new(value: grams(scan, row, required), unit: 'g', formula: formula,
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
