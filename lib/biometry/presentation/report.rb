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

      def call(dating:, ga:, scan:, growth:)
        [dating_section(dating), '', growth_section(ga, scan, growth), '',
         footnotes(growth)].join("\n")
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
      def footnotes(growth)
        sources = citations(growth).map { |citation| "    #{citation}" }
        ["  #{POOLED_NOTE}", '  Sources:', *sources].join("\n")
      end

      # Every standard with a row is cited whether or not its reading
      # succeeded — the row is on the page, so the paper behind it belongs in
      # the footer. The weight's paper is cited too, because on three of the
      # four standards it is a different one.
      def citations(growth)
        growth.flat_map { |row| [row[:citation], cited(row[:weight])] }.compact.uniq
      end

      def cited(result) = result.success? ? result.value!.source.citation : nil
    end
  end
end
