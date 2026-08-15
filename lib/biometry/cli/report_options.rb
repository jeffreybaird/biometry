# frozen_string_literal: true

require 'date'
require 'optparse'

module Biometry
  module CLI
    # A malformed command line, reported to the user rather than raised as a
    # bug. exe/ maps it to exit 2.
    class UsageError < StandardError; end

    # Reads argv into the values the report needs.
    #
    # Every parse failure is a usage error, never a substituted value: a
    # measurement that is not a number would otherwise weigh a fetus from a
    # typo.
    class ReportOptions
      MEASUREMENTS = %i[bpd hc ac fl].freeze
      GA = /\A(\d+)w(\d+)d\z/

      # Three flags, one request. Two of them alone describe a comparison with
      # nothing to compare against, and guessing the third means guessing at
      # the clinical question rather than at a formatting detail — not least
      # because --established-by is what decides whether the pregnancy may be
      # redated at all.
      REDATING = %i[established_edd established_by scan_edd].freeze

      def self.parse(argv)
        new.parse(argv)
      end

      def parse(argv)
        # No default cycle: an unsupplied one stays absent all the way to the
        # derivation, which applies the assumption and says so in its
        # parameters rather than reporting it back as user input.
        options = { at: Date.today }
        parser(options).parse(argv)
        raise UsageError, 'missing --ga, which no derivation may choose for you' unless options[:ga]

        require_redating_together(options)
        require_one_source(options)
        options
      end

      private

      def parser(options)
        OptionParser.new do |parser|
          measurements(parser, options)
          dating(parser, options)
          redating(parser, options)
          charts(parser, options)
          report(parser, options)
        end
      end

      def report(parser, options)
        parser.on('--ga GA') { |value| options[:ga] = gestational_age(value) }
        parser.on('--at DATE') { |value| options[:at] = date(value, '--at') }
        parser.on('--hl7 PATH') { |value| options[:hl7] = value }
        parser.on('--json') { options[:json] = true }
      end

      def measurements(parser, options)
        MEASUREMENTS.each do |kind|
          parser.on("--#{kind} MM") { |value| options[kind] = millimetres(value, "--#{kind}") }
        end
      end

      def redating(parser, options)
        parser.on('--established-edd DATE') do |value|
          options[:established_edd] = date(value, '--established-edd')
        end
        parser.on('--established-by DERIVATION') { |v| options[:established_by] = v.to_sym }
        parser.on('--scan-edd DATE') { |v| options[:scan_edd] = date(v, '--scan-edd') }
      end

      def require_redating_together(options)
        supplied = REDATING.select { |key| options[key] }
        return if supplied.empty? || supplied.length == REDATING.length

        missing = (REDATING - supplied).map { |key| "--#{key.to_s.tr('_', '-')}" }
        raise UsageError, "#{missing.join(' and ')} must be given alongside the others"
      end

      def dating(parser, options)
        parser.on('--lmp DATE') { |value| options[:lmp] = date(value, '--lmp') }
        parser.on('--cycle DAYS') { |value| options[:cycle] = whole(value, '--cycle') }
        parser.on('--transfer DATE') { |value| options[:transfer] = date(value, '--transfer') }
        parser.on('--embryo-day DAY') do |value|
          options[:embryo_day] = whole(value, '--embryo-day')
        end
      end

      # Measurements come from the message *instead of* the flags. Both at once
      # is a request with two answers to the same question, and picking one
      # silently is picking which biometry the report is of.
      def require_one_source(options)
        return unless options[:hl7] && MEASUREMENTS.any? { |kind| options[kind] }

        supplied = MEASUREMENTS.select { |kind| options[kind] }.map { |kind| "--#{kind}" }
        raise UsageError,
              "--hl7 supplies the measurements, so #{supplied.join(' and ')} cannot also"
      end

      def charts(parser, options)
        parser.on('--sex SEX') { |value| options[:sex] = value.to_sym }
        parser.on('--stratum STRATUM') { |value| options[:stratum] = value.to_sym }
      end

      def gestational_age(value)
        match = GA.match(value)
        if match.nil?
          raise UsageError,
                "could not read #{value.inspect} as a gestation; expected 32w0d"
        end

        GestationalAge.from(weeks: Integer(match[1]), days: Integer(match[2]))
      end

      def date(value, option)
        Date.iso8601(value)
      rescue ArgumentError, TypeError
        raise UsageError, "could not read #{value.inspect} as a date for #{option}"
      end

      # Decimals allowed: scanners report millimetres to one decimal place, and
      # rejecting 274.5 would make the caller round before the library does,
      # which is a rounding nobody recorded.
      def millimetres(value, option)
        Float(value, exception: false) ||
          raise(UsageError, "#{option} wanted a measurement in millimetres, got #{value.inspect}")
      end

      def whole(value, option)
        Integer(value, exception: false) ||
          raise(UsageError, "#{option} wanted a whole number, got #{value.inspect}")
      end
    end
  end
end
