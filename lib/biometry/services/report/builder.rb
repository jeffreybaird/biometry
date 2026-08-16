# frozen_string_literal: true

module Biometry
  module Services
    module Report
      # Composes one report from the services that own each part of it: the
      # dating derivations, the studies read at the gestation on each scan's
      # own date, and the redating decision when one was asked for.
      #
      # This is what the CLI's report command knew how to do, extracted so a
      # caller that is not the CLI composes the same report the same way. No
      # clinical decision is made here — every refusal in the report came from
      # a service.
      class Builder
        def initialize(manifests:, tables:)
          @manifests = manifests
          @tables = tables
        end

        def call(scans:, ga:, at:, lmp: nil, cycle_length: nil, transfer_date: nil,
                 embryo_day: nil, sex: nil, stratum: nil,
                 established_edd: nil, established_by: nil, proposed_edd: nil)
          Biometry::Report.new(
            dating: dated(at: at, lmp: lmp, cycle_length: cycle_length,
                          transfer_date: transfer_date, embryo_day: embryo_day),
            ga: ga,
            studies: studied(scans, ga: ga, at: at, sex: sex, stratum: stratum),
            redating: redated(established_edd, established_by, proposed_edd, at)
          )
        end

        private

        attr_reader :manifests, :tables

        def dated(at:, lmp:, cycle_length:, transfer_date:, embryo_day:)
          Dating::AllDerivations.new.call(
            reference_date: at, lmp: lmp, cycle_length: cycle_length,
            transfer_date: transfer_date, embryo_day: embryo_day
          ).value!
        end

        def studied(scans, ga:, at:, sex:, stratum:)
          rows = GrowthRows.new(manifests: manifests, tables: tables)
          Studies.new(rows: rows).call(scans, ga: ga, at: at, sex: sex, stratum: stratum)
        end

        # Absent rather than refused when nobody asked: a report carrying a
        # failed redating nobody requested reads as a question that was asked.
        def redated(established_edd, established_by, proposed_edd, at)
          return nil unless established_edd

          Dating::Redating.new(manifest: manifests[:acog_redating]).call(
            established_edd: established_edd, established_by: established_by,
            proposed_edd: proposed_edd, reference_date: at
          )
        end
      end
    end
  end
end
