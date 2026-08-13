# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Dating
      # Dating from an embryo transfer or a known conception date.
      #
      # Gestational age is conventionally counted as if from a menstrual period
      # two weeks before conception, so the pregnancy is already 14 days old at
      # conception and 14 days plus the embryo's age at transfer:
      #
      #   GA at transfer = 14 + embryo_day     # day-5 blastocyst => 2w5d
      #
      # Start from day zero instead and every number downstream is about two
      # weeks out — large enough that a clinician spots it immediately, small
      # enough that no unit test you would think to write catches it.
      #
      # `embryo_day` is required and has no default. A day-5 blastocyst read as
      # a day-3 cleavage embryo is a two-day error, and guessing for a caller
      # who simply omitted it is a silent one.
      class Transfer
        include Dry::Monads[:result]

        STANDARD = :ivf_transfer
        DERIVATION = :transfer
        TERM_DAYS = 280
        CONCEPTION_OFFSET_DAYS = 14
        CITATION = 'GA counted from a notional LMP 14 days before conception'
        REQUIRED = %i[transfer_date embryo_day reference_date].freeze

        # Guards answer in order: validity, then range — as in Lmp, and for
        # the same reason.
        def call(transfer_date:, reference_date:, embryo_day: nil)
          given = { transfer_date: transfer_date, embryo_day: embryo_day,
                    reference_date: reference_date }
          return insufficient(given) unless REQUIRED.all? { |key| !given[key].nil? }

          invalid = invalid_fields(given)
          return Failure([:invalid_input, invalid]) unless invalid.empty?

          dated(transfer_date, embryo_day, reference_date)
        end

        private

        # Same ordering convention as Lmp: declaration order, reference date
        # last.
        def insufficient(given)
          supplied = given.compact.keys
          Failure([:insufficient_data, { required: REQUIRED, given: supplied }])
        end

        # DateTime is a Date only by inheritance, so instance_of? rather than
        # is_a? — otherwise a zone reaches the arithmetic through the back door.
        def invalid_fields(given)
          given.select do |key, value|
            key == :embryo_day ? !whole_non_negative?(value) : !value.instance_of?(Date)
          end
        end

        def whole_non_negative?(value) = value.is_a?(Integer) && !value.negative?

        def dated(transfer_date, embryo_day, reference_date)
          start = transfer_date - CONCEPTION_OFFSET_DAYS - embryo_day
          days = (reference_date - start).to_i
          return out_of_range(days) if days.negative?

          Success(estimate(start + TERM_DAYS, days, reference_date))
        end

        def out_of_range(days)
          Failure([:out_of_range, { standard: STANDARD, ga_weeks: days / 7,
                                    valid_range: [0, nil] }])
        end

        def estimate(edd, days, reference_date)
          DatingEstimate.new(edd: edd, ga: GestationalAge.new(days: days),
                             reference_date: reference_date, derivation: DERIVATION,
                             source: provenance)
        end

        def provenance
          Provenance.formula(standard: STANDARD, citation: CITATION, formula: DERIVATION)
        end
      end
    end
  end
end
