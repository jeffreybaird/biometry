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
      STANDARDS = { intergrowth21: 'INTERGROWTH-21st', hadlock_1991: 'Hadlock 1991',
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
      # An open bracket is not a percentile the chart printed, so it is not
      # printed as one.
      def centile(percentile)
        whole = percentile.value.round
        return "<#{ordinal(1)}" if whole < 1
        return ">#{ordinal(99)}" if whole > 99
        return ordinal(whole) if percentile.computed?

        "#{percentile.bound} #{ordinal(whole)}"
      end

      def ordinal(number)
        suffix = TEENS.cover?(number % 100) ? 'th' : ORDINALS.fetch(number % 10, 'th')
        "#{number}#{suffix}"
      end

      def weight(estimate) = "#{thousands(estimate.value.round)} #{estimate.unit}"

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
