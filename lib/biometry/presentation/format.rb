# frozen_string_literal: true

module Biometry
  module Presentation
    # Renders single values. Pure string work: it is handed a value and returns
    # text, reads no manifest and calls no service.
    #
    # It exists so the two table sections and the two derivations cannot spell
    # the same thing two ways — "28d cycle" written twice is two chances to
    # drift.
    module Format
      STANDARDS = { intergrowth21: 'INTERGROWTH-21st',
                    hadlock_1991_equation: 'Hadlock 1991 (equation)',
                    hadlock_1991_table: 'Hadlock 1991 (table)',
                    nichd: 'NICHD', who: 'WHO' }.freeze
      DERIVATIONS = { lmp: 'LMP', transfer: 'Transfer', crl: 'CRL',
                      biometry: 'Biometry' }.freeze
      ORDINALS = { 1 => 'st', 2 => 'nd', 3 => 'rd' }.freeze
      TEENS = (11..13)
      ABSENT = '—'

      module_function

      # A reader comparing standards is not reading a decimal place, so the
      # table rounds. --json carries the unrounded value; a program consuming
      # the output must not be handed a precision that was already discarded.
      #
      # One spelling for one statement. "Past the top of what I can report" is
      # `above 99th` whether it came from a closed form that rounded off the
      # end or from a table with no column further out — two spellings for the
      # same sentence is the worse defect. The two cases stay apart in --json,
      # where `bound` is :computed in one and :above in the other, which is
      # what a program should be branching on.
      #
      # A bracket bound is a published column, so it prints verbatim: WHO's
      # combined table tops out at 97.5, and rounding that to 98 would name a
      # column that does not exist. Rounding is for computed values, where the
      # decimal is noise.
      def centile(percentile)
        return "below #{ordinal(percentile.value)}" if percentile.bound == :below
        return "above #{ordinal(percentile.value)}" if percentile.bound == :above

        whole = percentile.value.round
        return "below #{ordinal(1)}" if whole < 1
        return "above #{ordinal(99)}" if whole > 99

        ordinal(whole)
      end

      # A fractional centile keeps its decimal — 97.5th is a column WHO
      # publishes, and 98th is not.
      def ordinal(number)
        whole = number.to_i
        return "#{number}th" unless number == whole

        suffix = TEENS.cover?(whole % 100) ? 'th' : ORDINALS.fetch(whole % 10, 'th')
        "#{whole}#{suffix}"
      end

      # The SD travels in the same field as the weight it belongs to. As its
      # own column it sat next to the percentile and read as the percentile's
      # uncertainty, which is wrong and flattering: a percentile's uncertainty
      # is dominated by the chart's own dispersion — 13.3% for Hadlock 1991 —
      # not by the 7.4% of the formula that produced the weight.
      def weight(estimate)
        "#{thousands(estimate.value.round)} #{estimate.unit} #{uncertainty(estimate.uncertainty)}"
      end

      def thousands(number) = number.to_s.reverse.scan(/\d{1,3}/).join(',').reverse

      # Nil is the absence of a published SD, not a zero. INTERGROWTH reports a
      # mean absolute prediction error, which is a different quantity, and
      # printing it here would attribute an SD to a paper that never gave one.
      def uncertainty(uncertainty)
        return ABSENT if uncertainty.nil?

        "±#{format('%.1f', uncertainty.sd_pct)}%"
      end

      def standard(symbol, stratum: nil)
        name = STANDARDS.fetch(symbol, symbol.to_s)
        stratum ? "#{name} (#{stratum})" : name
      end

      # Deferred derivations arrive with no parameters, so they take the same
      # path rather than making the caller branch on whether a Result
      # succeeded before it can pick a label.
      def derivation(symbol, parameters: nil)
        name = DERIVATIONS.fetch(symbol, symbol.to_s)
        return name if parameters.nil? || parameters.empty?

        "#{name} (#{parameter(parameters)})"
      end

      # An unrecognised parameter renders as `key: value` rather than being
      # dropped: a later derivation will arrive carrying an assumption this
      # function has no phrasing for, and losing it silently is worse than
      # printing it plainly.
      def parameter(parameters)
        key, value = parameters.first
        case key
        when :cycle_length then "#{value}d cycle"
        when :embryo_day then "day #{value}"
        else "#{key}: #{value}"
        end
      end

      def inputs(estimate) = "(#{estimate.inputs.map { |kind| kind.to_s.upcase }.join('+')})"

      def measurements(scan)
        return 'no measurements' if scan.measurements.empty?

        "#{scan.measurements.map { |m| "#{m.kind.to_s.upcase} #{m.cm}" }.join('  ')} cm"
      end
    end
  end
end
