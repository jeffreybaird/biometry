# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module Services
    module Dating
      # Whether an established due date should be revised in light of a scan.
      #
      # The threshold widens with gestation because ultrasound dating accuracy
      # degrades as pregnancy advances. Which band applies is decided by the
      # *established* gestation, per the manifest's `band_indexed_on`: at the
      # moment of the decision you hold two gestations that disagree, and that
      # disagreement is the reason the service was called.
      #
      # Nothing here mutates a date. The established EDD is handed back
      # unchanged and the decision is the reasoning, not a replacement.
      class Redating
        include Dry::Monads[:result]

        STANDARD = :acog
        DERIVATION = :redating
        REQUIRED = %i[established_edd established_by proposed_edd reference_date].freeze
        IVF_DERIVATION = :transfer
        IVF_RULE = :ivf_never_redated

        def initialize(manifest:)
          @bands = manifest[:bands]
          @caveats = manifest[:caveats]
          @citation = manifest.dig(:source, :citation)
          @proximity = manifest.dig(:rules, :boundary_sensitivity, :within_days)
        end

        # Guards answer in order: validity, then the IVF rule, then range. The
        # rule outranks the band because a band's threshold answers a question
        # IVF dating never asks.
        def call(established_edd:, established_by:, proposed_edd:, reference_date:)
          given = { established_edd: established_edd, established_by: established_by,
                    proposed_edd: proposed_edd, reference_date: reference_date }
          refusal = refuse(given)
          return refusal if refusal

          discrepancy = (proposed_edd - established_edd).to_i.abs
          return Success(by_rule(given, discrepancy)) if established_by == IVF_DERIVATION

          by_band(given, discrepancy)
        end

        private

        attr_reader :bands, :caveats, :citation, :proximity

        # --------------------------------------------------------- refusals ---

        def refuse(given)
          return insufficient(given) unless REQUIRED.all? { |key| !given[key].nil? }

          dates = invalid_dates(given)
          return Failure([:invalid_input, dates]) unless dates.empty?

          unknown_derivation(given[:established_by])
        end

        def insufficient(given)
          Failure([:insufficient_data, { required: REQUIRED, given: given.compact.keys }])
        end

        # DateTime is a Date only by inheritance, so instance_of? rather than
        # is_a? — otherwise a zone reaches the arithmetic.
        def invalid_dates(given)
          given.except(:established_by).reject { |_, value| value.instance_of?(Date) }
        end

        # A derivation this library has no vocabulary for cannot be checked
        # against the IVF rule, and guessing that it is not IVF is the
        # expensive direction to guess wrong in.
        def unknown_derivation(established_by)
          return nil if derivations.include?(established_by)

          Failure([:invalid_input, { established_by: established_by, available: derivations }])
        end

        def derivations = AllDerivations::OFFERED + AllDerivations::DEFERRED

        # ------------------------------------------------------ the decision ---

        def by_rule(given, discrepancy)
          decision(given, discrepancy, recommendation: :keep, rule: IVF_RULE)
        end

        def by_band(given, discrepancy)
          age = indexing_days(given)
          band = band_at(age)
          return out_of_range(age) unless band

          Success(decision(given, discrepancy, band: band,
                                               recommendation: recommend(band, discrepancy),
                                               sensitivity: sensitivity(band, age, discrepancy)))
        end

        def indexing_days(given)
          Lmp::TERM_DAYS - (given[:established_edd] - given[:reference_date]).to_i
        end

        def out_of_range(age)
          Failure([:out_of_range, { standard: STANDARD, ga_weeks: age / 7,
                                    valid_range: [edge(bands.first[:ga_from]) / 7,
                                                  edge(bands.last[:ga_to])&.fdiv(7)&.floor] }])
        end

        def decision(given, discrepancy, band: nil, recommendation: :keep, rule: nil,
                     sensitivity: nil)
          RedatingDecision.new(
            recommendation: recommendation, discrepancy_days: discrepancy,
            established_edd: given[:established_edd], proposed_edd: given[:proposed_edd],
            indexing_ga: GestationalAge.new(days: indexing_days(given)),
            band: band && band[:id].to_sym, threshold_days: band && band[:threshold_days],
            zone: band && zone_of(band), caveat: band && caveat_of(band), rule: rule,
            boundary_sensitivity: sensitivity, source: provenance
          )
        end

        # ---------------------------------------------------------- the rule ---

        # The zone changes the answer rather than annotating it: without it a
        # discrepancy inside the zone reads :keep on the bare threshold, which
        # is precisely the window the guideline wants a clinician to look at.
        def recommend(band, discrepancy)
          zone = zone_of(band)
          return :discretionary if zone&.cover?(discrepancy)
          return :redate if discrepancy > band[:threshold_days]

          :keep
        end

        def zone_of(band)
          zone = band[:discretionary_zone]
          zone && (zone[:from_days]..zone[:to_days])
        end

        def caveat_of(band)
          id = band[:caveat]&.to_sym
          id && Caveat.new(id: id, text: caveats.dig(id, :text))
        end

        # --------------------------------------------------------- the bands ---

        def band_at(age)
          bands.find do |band|
            finish = edge(band[:ga_to])
            age >= edge(band[:ga_from]) && (finish.nil? || age <= finish)
          end
        end

        def edge(bound) = bound && ((bound[:weeks] * 7) + bound[:days])

        # ---------------------------------------------------- the disclosure ---

        # Two conditions, both load-bearing. A gestation near an edge whose
        # answer is the same either side has nothing to disclose, and a
        # difference alone is not a finding either — every band differs from
        # its neighbour somewhere.
        def sensitivity(band, age, discrepancy)
          neighbour, distance = nearest(band, age)
          return nil unless neighbour && distance <= proximity

          answer = recommend(neighbour, discrepancy)
          return nil if answer == recommend(band, discrepancy)

          BoundarySensitivity.new(adjacent_band: neighbour[:id].to_sym,
                                  recommendation: answer, days_to_edge: distance)
        end

        def nearest(band, age)
          index = bands.index(band)
          return [bands[index - 1], from_start(band, age)] if looks_back?(band, age, index)

          after = bands[index + 1]
          after ? [after, edge(after[:ga_from]) - age] : [nil, nil]
        end

        def looks_back?(band, age, index) = index.positive? && from_start(band, age) <= proximity

        def from_start(band, age) = age - edge(band[:ga_from]) + 1

        def provenance
          Provenance.formula(standard: STANDARD, citation: citation, formula: DERIVATION)
        end
      end
    end
  end
end
