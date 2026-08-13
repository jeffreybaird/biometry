# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Weight
      # Estimated fetal weight by INTERGROWTH-21st (Stirnemann 2017).
      #
      # Not parsed from its `equation:` string: that string has parentheses, a
      # cube and a natural log, all outside Equation's grammar. The manifest
      # publishes the four constants as a `coefficients:` block instead, so the
      # functional form lives here and the numbers still come from data/.
      #
      # Femur length is deliberately absent. The authors tested it and did not
      # retain it, arguing it would increase prediction error because FL has
      # the highest observer variability of the three. A scan carrying BPD, AC
      # and FL but no HC therefore cannot produce a value here at all.
      class Intergrowth
        include Dry::Monads[:result]

        STANDARD = :intergrowth21
        FORMULA = :intergrowth

        def initialize(manifest:)
          @required = manifest[:efw][:requires].map(&:to_sym)
          @coefficients = manifest[:efw][:coefficients]
          @source = manifest[:source]
        end

        def call(scan)
          return insufficient(scan) unless scan.supports?(required)

          Success(estimate(scan))
        end

        private

        attr_reader :required, :coefficients, :source

        def insufficient(scan)
          Failure([:insufficient_data, { required: required, given: scan.kinds }])
        end

        def estimate(scan)
          Estimate.new(value: grams(scan), unit: 'g', method: FORMULA,
                       inputs: required, source: provenance)
        end

        def grams(scan) = Math.exp(log_efw(scan.cm(:ac), scan.cm(:hc)))

        # AC and HC are centimetres here; the published form divides both by
        # 100 before use.
        def log_efw(ac, hc)
          coefficients[:intercept] +
            abdominal_terms(ac / 100.0) +
            (coefficients[:hc] * (hc / 100.0))
        end

        # AC enters twice: as a cube, and as that cube weighted by its own log.
        def abdominal_terms(ratio)
          cubed = ratio**3

          (coefficients[:ac_cubed] * cubed) +
            (coefficients[:ac_cubed_log] * cubed * Math.log(ratio))
        end

        def provenance
          Provenance.new(standard: STANDARD, citation: source[:citation], formula: FORMULA,
                         type: source[:type].to_sym, stratum: nil)
        end
      end
    end
  end
end
