# frozen_string_literal: true

module Biometry
  module Presentation
    # Turns a Failure into one line of prose.
    #
    # Refusals are content, not omissions. A row that could not be produced
    # says why, because a silently short table looks complete when it is not —
    # the same reason the services refuse rather than skip.
    #
    # An unrecognised tag renders rather than raising. A later slice will
    # introduce one, and a row that raised would take the whole report to exit
    # 70 over a phrasing gap.
    module Reason
      DASH = '—'

      module_function

      def call(failure)
        tag, details = failure
        case tag
        when :unsupported_standard then unsupported(details)
        when :insufficient_data then insufficient(details)
        when :out_of_range then out_of_range(details)
        when :formula_chart_mismatch then mismatch(details)
        when :unsupported_centile then unsupported_centile(details)
        else fallback(tag, details)
        end
      end

      def unsupported(details)
        "unavailable #{DASH} #{details[:requested]} is not implemented; " \
          "available: #{list(details[:available])}"
      end

      def insufficient(details)
        "insufficient data #{DASH} requires #{list(details[:required])}; " \
          "given #{list(details[:given])}"
      end

      # An open upper bound is rendered as open rather than as a number: no
      # published limit on gestation is transcribed, and printing one would
      # invent it.
      def out_of_range(details)
        low, high = details[:valid_range]
        window = high ? "#{low}–#{high} weeks" : "#{low} weeks and later"
        "out of range #{DASH} #{details[:standard]} covers #{window}; " \
          "given #{details[:ga_weeks]}"
      end

      def mismatch(details)
        "formula mismatch #{DASH} #{details[:chart]} is read from " \
          "#{details[:expected]}; given #{details[:given]}"
      end

      def unsupported_centile(details)
        "unsupported centile #{DASH} #{details[:standard]} publishes " \
          "#{list(details[:available])}; given #{details[:requested]}"
      end

      def fallback(tag, details)
        "#{tag.to_s.tr('_', ' ')} #{DASH} #{pairs(details)}"
      end

      # An Array value renders as a list rather than as its inspect form: an
      # unphrased tag carrying `available:` should read like the phrased ones.
      def pairs(details)
        details.map { |key, value| "#{key}: #{value.is_a?(Array) ? list(value) : value}" }
               .join('; ')
      end

      def list(values) = values.nil? || values.empty? ? 'none' : values.join(', ')
    end
  end
end
