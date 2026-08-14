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

        options
      end

      private

      def parser(options)
        OptionParser.new do |parser|
          measurements(parser, options)
          dating(parser, options)
          charts(parser, options)
          parser.on('--ga GA') { |value| options[:ga] = gestational_age(value) }
          parser.on('--at DATE') { |value| options[:at] = date(value, '--at') }
          parser.on('--json') { options[:json] = true }
        end
      end

      def measurements(parser, options)
        MEASUREMENTS.each do |kind|
          parser.on("--#{kind} MM") { |value| options[kind] = millimetres(value, "--#{kind}") }
        end
      end

      def dating(parser, options)
        parser.on('--lmp DATE') { |value| options[:lmp] = date(value, '--lmp') }
        parser.on('--cycle DAYS') { |value| options[:cycle] = whole(value, '--cycle') }
        parser.on('--transfer DATE') { |value| options[:transfer] = date(value, '--transfer') }
        parser.on('--embryo-day DAY') do |value|
          options[:embryo_day] = whole(value, '--embryo-day')
        end
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

      def millimetres(value, option)
        whole(value, option) ||
          raise(UsageError, "#{option} wanted a measurement in millimetres, got #{value.inspect}")
      end

      def whole(value, option)
        Integer(value, exception: false) ||
          raise(UsageError, "#{option} wanted a whole number, got #{value.inspect}")
      end
    end
  end
end
