# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Dating
      # Every way of dating a pregnancy that the inputs support, reported
      # together.
      #
      # There is no winner. LMP and transfer genuinely disagree by days, and
      # that disagreement is the same species as the four growth charts: the
      # caller decides which is established. The aggregate itself always
      # succeeds; the per-derivation Results are the report.
      #
      # CRL and biometry are offered and refused rather than absent. data/
      # carries no dating regression for either, and choosing among
      # Robinson-Fleming, Hadlock 1992 and INTERGROWTH is a clinical decision
      # rather than an implementer's — those standards give materially
      # different ages from the same measurement. A caller must be able to tell
      # "this library cannot do that yet" from "your inputs did not support
      # it", so the refusal is :unsupported_standard and it answers before any
      # question about the request.
      class AllDerivations
        include Dry::Monads[:result]

        OFFERED = %i[lmp transfer].freeze
        DEFERRED = %i[crl biometry].freeze

        def call(reference_date:, lmp: nil, cycle_length: 28,
                 transfer_date: nil, embryo_day: nil, scan: nil)
          _ = scan # accepted so a caller can supply it; both readers are deferred
          Success(
            lmp: Lmp.new.call(lmp: lmp, cycle_length: cycle_length,
                              reference_date: reference_date),
            transfer: Transfer.new.call(transfer_date: transfer_date, embryo_day: embryo_day,
                                        reference_date: reference_date),
            **deferred
          )
        end

        private

        def deferred
          DEFERRED.to_h { |derivation| [derivation, unsupported(derivation)] }
        end

        def unsupported(derivation)
          Failure([:unsupported_standard, { requested: derivation, available: OFFERED }])
        end
      end
    end
  end
end
