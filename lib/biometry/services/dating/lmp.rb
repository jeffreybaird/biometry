# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Dating
      # Dating from the last menstrual period, by Naegele's rule.
      #
      #   EDD = LMP + 280 + (cycle_length - 28)
      #   GA at a reference date = reference_date - (EDD - 280)
      #
      # The second line is the first read backwards: the cycle correction moves
      # the notional menstrual start, so it moves the gestational age by the
      # same days it moves the due date. A 35-day cycle that shifted the EDD
      # but not the GA would put every downstream percentile a week out.
      #
      # Neither number here is a clinical constant. Gestational age *is*
      # menstrual age by definition and the 40-week due date *is* the
      # definition of an EDD, so nothing is read from data/ and no collaborator
      # is injected.
      class Lmp
        include Dry::Monads[:result]

        STANDARD = :naegele
        DERIVATION = :lmp
        TERM_DAYS = 280
        ASSUMED_CYCLE_DAYS = 28
        CITATION = 'Naegele: EDD = LMP + 280 days, corrected for cycle length'
        REQUIRED = %i[lmp reference_date].freeze

        # Guards answer in order: validity, then range. A range computed from
        # an invalid cycle length means nothing, so reporting it would send the
        # caller after the wrong problem.
        # `cycle_length` defaults to nil rather than to 28 so that a value the
        # caller never supplied is not reported back to them as one they did.
        # A default presented as user input sends a reader looking for where
        # they typed it.
        def call(lmp:, reference_date:, cycle_length: nil)
          given = { lmp: lmp, cycle_length: cycle_length, reference_date: reference_date }
          return insufficient(given) unless REQUIRED.all? { |key| !given[key].nil? }

          invalid = invalid_fields(given)
          return Failure([:invalid_input, invalid]) unless invalid.empty?

          dated(lmp, reference_date, cycle_length || ASSUMED_CYCLE_DAYS)
        end

        private

        # `given` keeps the order the inputs are declared in — derivation
        # inputs first, reference date last — so a caller comparing two
        # derivations' failures sees a stable shape.
        def insufficient(given)
          supplied = given.compact.keys
          Failure([:insufficient_data, { required: REQUIRED, given: supplied }])
        end

        # DateTime is a Date only by inheritance, so instance_of? rather than
        # is_a? — otherwise a zone reaches the arithmetic through the back door.
        # An absent cycle length is not an invalid one: the assumption applies.
        def invalid_fields(given)
          given.compact.select do |key, value|
            key == :cycle_length ? !whole_positive?(value) : !value.instance_of?(Date)
          end
        end

        def whole_positive?(value) = value.is_a?(Integer) && value.positive?

        def dated(lmp, reference_date, cycle_length)
          start = lmp + (cycle_length - ASSUMED_CYCLE_DAYS)
          days = (reference_date - start).to_i
          return out_of_range(days) if days.negative?

          Success(estimate(start + TERM_DAYS, days, reference_date, cycle_length))
        end

        def out_of_range(days)
          Failure([:out_of_range, { standard: STANDARD, ga_weeks: days / 7,
                                    valid_range: [0, nil] }])
        end

        # The cycle length reported is the one actually used, not the assumed
        # default, so a reader can tell a corrected date from an uncorrected
        # one without knowing what was requested.
        def estimate(edd, days, reference_date, cycle_length)
          DatingEstimate.new(edd: edd, ga: GestationalAge.new(days: days),
                             reference_date: reference_date, derivation: DERIVATION,
                             parameters: { cycle_length: cycle_length }, source: provenance)
        end

        def provenance
          Provenance.formula(standard: STANDARD, citation: CITATION, formula: DERIVATION)
        end
      end
    end
  end
end
