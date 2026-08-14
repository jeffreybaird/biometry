# frozen_string_literal: true

module Biometry
  module Presentation
    # The comparison table.
    #
    # Returns a string; it does not write one. exe/ and cli/ own the streams,
    # which keeps colour and alignment testable without capturing stdout and
    # lets TTY-ness arrive as an argument rather than be sniffed from a global.
    #
    # It renders values it is handed and computes nothing clinical: no weight,
    # no percentile, no manifest read, no service called.
    #
    # Every row names its standard, its stratum, its parameter set and its
    # type, and no percentile appears without the standard it came from. The
    # disagreement between standards is the output, so nothing here ranks or
    # filters, and a row that could not be produced prints why rather than
    # vanishing.
    class Report
      BOLD = "\e[1m"
      RESET = "\e[0m"
      GAP = '  '
      # Phrased in percentages, not ordinals: an ordinal here would be counted
      # as a centile by anything scanning the output for one.
      POOLED_NOTE = 'SD is the EFW formula\'s, pooled; per-stratum figures are not ' \
                    'transcribed. It does not include the chart\'s own dispersion.'

      def initialize(tty: false)
        @tty = tty
      end

      # `redating` is optional: a report nobody asked a redating question of
      # renders exactly as it did before the section existed.
      def call(dating:, ga:, scan:, growth:, redating: nil)
        [dating_section(dating), '', *redating_section(redating),
         growth_section(ga, scan, growth), '', footnotes(growth, redating)].join("\n")
      end

      private

      attr_reader :tty

      def emphasise(text) = tty ? "#{BOLD}#{text}#{RESET}" : text

      # ---------------------------------------------------------------- dating

      def dating_section(dating)
        rows = dating.map { |derivation, result| dating_row(derivation, result) }
        [emphasise('Dating'), *aligned(rows)].join("\n")
      end

      def dating_row(derivation, result)
        return [Format.derivation(derivation), Reason.call(result.failure)] if result.failure?

        estimate = result.value!
        [Format.derivation(derivation, parameters: estimate.parameters),
         "EDD #{estimate.edd}", estimate.ga.to_s]
      end

      # -------------------------------------------------------------- redating

      def redating_section(redating)
        return [] if redating.nil?

        [emphasise('Redating'), *aligned(redating_rows(redating)), '']
      end

      def redating_rows(redating)
        return [['', Reason.call(redating.failure)]] if redating.failure?

        decision = redating.value!
        [[decision.recommendation.to_s, measured(decision)], *qualifiers(decision)]
      end

      def measured(decision)
        return "#{decision.discrepancy_days} day(s), by #{decision.rule}" if decision.rule

        "#{decision.discrepancy_days} day(s) against a #{decision.threshold_days} day " \
          "threshold, #{decision.band} at #{decision.indexing_ga}"
      end

      # The caveat is printed word for word. A summary would be this library
      # speaking; the whole reason it is exempt from the no-classification rule
      # is that the guideline is speaking here and we are not.
      def qualifiers(decision)
        [zone_row(decision), sensitivity_row(decision), caveat_row(decision)].compact
      end

      def zone_row(decision)
        return nil unless decision.zone

        ['', "the guideline defers between #{decision.zone.first} and " \
             "#{decision.zone.last} days"]
      end

      def sensitivity_row(decision)
        sensitivity = decision.boundary_sensitivity
        return nil unless sensitivity

        ['', "#{sensitivity.days_to_edge} day(s) from #{sensitivity.adjacent_band}, " \
             "where this would be #{sensitivity.recommendation}"]
      end

      def caveat_row(decision) = decision.caveat && ['', decision.caveat.text.strip]

      # ---------------------------------------------------------------- growth

      def growth_section(ga, scan, growth)
        heading = "#{emphasise('Growth')}#{GAP}GA #{ga}#{GAP}#{Format.measurements(scan)}"
        [heading, '', *aligned(growth.map { |row| growth_row(row) })].join("\n")
      end

      # A refusing row keeps the columns it does have and then says why. A
      # weight the chart could not place is still a finding, so it stays on the
      # row — but only when the row is about a chart at all.
      def growth_row(row)
        return refusal(row, row[:weight].failure) if row[:weight].failure?
        return refusal(row, row[:report].failure) if chart_unidentified?(row)

        weight_columns(row) + centile_columns(row)
      end

      def weight_columns(row) = [label_for(row), Format.weight(row[:weight].value!)]

      def refusal(row, failure) = [Format.standard(row[:standard]), Reason.call(failure)]

      # :invalid_input means the request named a stratum the standard does not
      # publish, so no chart was ever selected and there is nothing to attach a
      # weight to. Every other refusal knows which chart it is about.
      def chart_unidentified?(row)
        row[:report].failure? && row[:report].failure.first == :invalid_input
      end

      def centile_columns(row)
        return [Reason.call(row[:report].failure)] if row[:report].failure?

        percentile = row[:report].value!
        [Format.centile(percentile), percentile.source.type.to_s,
         Format.inputs(row[:weight].value!)]
      end

      # The label needs the stratum, which only the chart's provenance knows,
      # so it is filled in once the report is in hand.
      def label_for(row)
        stratum = row[:report].success? ? row[:report].value!.source.stratum : nil
        Format.standard(row[:standard], stratum: stratum)
      end

      # ------------------------------------------------------------ formatting

      # Columns line up so the same field starts at the same offset. Padding is
      # applied whether or not this is a terminal; only colour is conditional.
      def aligned(rows)
        widths = column_widths(rows)
        rows.map { |cells| "  #{pad(cells, widths).join(GAP).rstrip}" }
      end

      # A cell that ends its row does not set a column width: nothing follows
      # it to align against. Without that, a refusal — which is a sentence in
      # the position a short field occupies elsewhere — pads every row above
      # it to the width of the sentence.
      def column_widths(rows)
        Array.new(rows.map(&:length).max || 0) do |index|
          rows.filter_map { |cells| cells[index].length if index < cells.length - 1 }.max || 0
        end
      end

      def pad(cells, widths)
        cells.each_with_index.map { |cell, index| cell.to_s.ljust(widths[index]) }
      end

      # ------------------------------------------------------------- footnotes

      # Every distinct citation the rows touched, chart and weight both: on
      # three of the four standards those are different papers, and a reader
      # checking a number needs the one it actually came from.
      # One citation per line. Joined, the five run to several hundred
      # characters and a reader cannot pick out the paper behind the row they
      # are checking.
      def footnotes(growth, redating)
        sources = citations(growth, redating).map { |citation| "    #{citation}" }
        ["  #{POOLED_NOTE}", '  Sources:', *sources].join("\n")
      end

      # Every standard with a row is cited whether or not its reading
      # succeeded — the row is on the page, so the paper behind it belongs in
      # the footer. The weight's paper is cited too, because on three of the
      # four standards it is a different one, and the guideline behind a
      # redating for the same reason.
      def citations(growth, redating)
        rows = growth.flat_map { |row| [row[:citation], cited(row[:weight])] }
        (rows + [redating && cited(redating)]).compact.uniq
      end

      def cited(result) = result.success? ? result.value!.source.citation : nil
    end
  end
end
