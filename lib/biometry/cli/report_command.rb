# frozen_string_literal: true

require_relative 'growth_rows'
require_relative 'report_help'
require_relative 'report_options'

module Biometry
  module CLI
    # Composes the library into one report.
    #
    # The imperative shell: it reads the manifests, builds the services, hands
    # their values to presentation/ and writes the string it gets back. No
    # clinical decision is made here — every refusal in the output came from a
    # service.
    class ReportCommand
      MANIFESTS = %i[hadlock_1985 hadlock_1991 intergrowth21 nichd who].freeze
      TABLES = %i[nichd who].freeze

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      HELP_FLAGS = %w[--help -h help].freeze

      # Help is answered before OptionParser sees argv. Its own officious
      # --help writes to the process's real $stdout and calls exit, which
      # bypasses the injected stream and would take a test runner down with
      # it.
      def call(argv)
        rest = argv.drop(1)
        return help if rest.any? { |argument| HELP_FLAGS.include?(argument) }

        options = ReportOptions.parse(rest)
        dating, growth = compose(options)
        stdout.puts(render(dating, growth, options))
        reportable?(dating, growth) ? Main::EXIT_OK : Main::EXIT_FAILURE
      rescue UsageError, OptionParser::ParseError => e
        stderr.puts("biometry report: #{e.message}")
        Main::EXIT_USAGE
      end

      private

      attr_reader :stdout, :stderr

      def help
        stdout.puts(ReportHelp::TEXT)
        Main::EXIT_OK
      end

      def compose(options)
        [dating_for(options), rows_for(options)]
      end

      def dating_for(options)
        Services::Dating::AllDerivations.new.call(
          reference_date: options[:at], lmp: options[:lmp], cycle_length: options[:cycle],
          transfer_date: options[:transfer], embryo_day: options[:embryo_day]
        ).value!
      end

      def rows_for(options)
        GrowthRows.new(manifests: manifests, tables: tables)
                  .call(scan: scan_of(options), ga: options[:ga],
                        sex: options[:sex], stratum: options[:stratum])
      end

      def render(dating, growth, options)
        arguments = { dating: dating, ga: options[:ga], scan: scan_of(options), growth: growth }
        return Presentation::JsonReport.new.call(**arguments) if options[:json]

        Presentation::Report.new(tty: stdout.tty?).call(**arguments)
      end

      # Exit 1 only when nothing at all could be reported. The refusals are the
      # result and still print; CRL and biometry always refuse, so any other
      # rule would make exit 1 permanent.
      def reportable?(dating, growth)
        dating.values.any?(&:success?) || growth.any? { |row| row[:report].success? }
      end

      def scan_of(options)
        measurements = ReportOptions::MEASUREMENTS.filter_map do |kind|
          Measurement.new(kind: kind, mm: options[kind]) if options[kind]
        end
        Scan.new(date: options[:at], measurements: measurements)
      end

      def manifests
        @manifests ||= MANIFESTS.to_h do |name|
          [name, ReferenceData.load_manifest(DATA_ROOT / "#{name}.yml").first]
        end
      end

      def tables
        @tables ||= TABLES.to_h do |name|
          [name, ReferenceData.load_table(DATA_ROOT / "percentiles/#{name}.csv")]
        end
      end
    end
  end
end
