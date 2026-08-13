# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Weight
      # Every EFW a scan supports, from every formula on offer.
      #
      # Returns a Result per formula rather than a shortlist. The disagreement
      # between formulas is this library's output, and a formula that could not
      # produce a value says why instead of being dropped — a silently missing
      # row reads as a formula that was never tried.
      #
      # The aggregate itself always succeeds. Its Failures live inside, one per
      # formula, because there is no single `required:` that means anything
      # across requirement sets that differ per formula.
      #
      # On offer means verified. data/hadlock.yml marks three of its four
      # Table II rows unverified, and Hadlock withholds those.
      class AllFormulas
        include Dry::Monads[:result]

        def initialize(hadlock:, intergrowth:)
          @services = hadlock[:efw_formulas]
                      .select { |_, row| row[:verified] }
                      .keys
                      .to_h { |id| [id, Hadlock.new(manifest: hadlock, formula: id)] }
                      .merge(Intergrowth::FORMULA => Intergrowth.new(manifest: intergrowth))
        end

        def call(scan)
          Success(@services.transform_values { |service| service.call(scan) })
        end
      end
    end
  end
end
