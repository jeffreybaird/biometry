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

        # The manifest is frozen and the formula id is fixed for the life of
        # the instance, so the row and its parsed equation are resolved once
        # here rather than on every call. Equation.parse is pure and its result
        # frozen, so this is the same arithmetic with one parse instead of N.
        def initialize(manifest:, formula:)
          @formulas = manifest[:efw_formulas]
          @citation = manifest.dig(:source, :citation)
          @formula = formula
          @row = @formulas[formula]
          @required = @row[:requires].map(&:to_sym) if @row
          @equation = Equation.parse(@row[:equation]) if @row
        end

        def call(scan)
          return unsupported unless row
          return insufficient(scan) unless scan.supports?(required)

          Success(estimate(scan))
        end

        private

        attr_reader :formulas, :formula, :citation, :row, :required, :equation

        def available = formulas.keys

        def unsupported
          Failure([:unsupported_standard, { requested: formula, available: available }])
        end

        def insufficient(scan)
          Failure([:insufficient_data, { required: required, given: scan.kinds }])
        end

        def estimate(scan)
          Estimate.new(value: grams(scan), unit: 'g', formula: formula,
                       inputs: required, source: provenance,
                       uncertainty: Uncertainty.pooled(row[:sd_pct]))
        end

        def grams(scan)
          10**equation.evaluate(required.to_h { |kind| [kind, scan.cm(kind)] })
        end

        def provenance
          Provenance.new(standard: STANDARD, citation: citation, formula: formula,
                         type: nil, stratum: nil)
        end
      end
    end
  end
end
