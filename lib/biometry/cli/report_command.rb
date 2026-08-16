# frozen_string_literal: true

require_relative 'message_source'
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
      # `loinc` maps OBX-3 identifiers to measurement kinds. It defaults to the
      # transcription in data/, which does not exist yet — injecting it is what
      # lets the message path be exercised before that file lands, without a
      # spec asserting against a code nobody verified.
      #
      # `context` is the loaded reference data; it defaults lazily to
      # Biometry.load so help and usage errors answer without reading data/.
      def initialize(stdout:, stderr:, loinc: nil, context: nil)
        @stdout = stdout
        @stderr = stderr
        @loinc = loinc || transcribed_loinc
        @context = context
      end

      HELP_FLAGS = %w[--help -h help].freeze

      # Help is answered before OptionParser sees argv. Its own officious
      # --help writes to the process's real $stdout and calls exit, which
      # bypasses the injected stream and would take a test runner down with
      # it.
      LOINC = 'loinc.yml'

      def call(argv)
        rest = argv.drop(1)
        return help if rest.any? { |argument| HELP_FLAGS.include?(argument) }

        options = ReportOptions.parse(rest)
        refuse_hl7(options) || measured(options)
      rescue UsageError, OptionParser::ParseError => e
        stderr.puts("biometry report: #{e.message}")
        Main::EXIT_USAGE
      end

      private

      attr_reader :stdout, :stderr, :loinc

      # Where the biometry comes from: a message, or the four flags. A message
      # that could not be read refuses rather than falling back to the flags —
      # the caller asked about this scan, and answering about a different one
      # silently is worse than answering about none.
      def measured(options)
        return produce(options, [scan_of(options)]) unless options[:hl7]

        source = MessageSource.new(loinc: loinc, stderr: stderr)
        source.call(options[:hl7]).either(
          ->(scans) { produce(options, scans) },
          ->(failure) { refuse(Presentation::Reason.call(failure)) }
        )
      end

      def refuse(message)
        stderr.puts("biometry report: #{message}")
        Main::EXIT_FAILURE
      end

      def help
        stdout.puts(ReportHelp::TEXT)
        Main::EXIT_OK
      end

      # A mistyped path is reported as a mistyped path, ahead of a mapping the
      # caller was never going to need. Then the mapping itself: with none, a
      # message that parses perfectly still yields nothing this library can
      # name, and a report with an empty growth table reads as a fetus nobody
      # measured rather than as a lookup nobody transcribed. Exit 1, not 2 —
      # the invocation was well formed and the gap is ours.
      def refuse_hl7(options)
        path = options[:hl7]
        return nil unless path
        return usage("no such message: #{path}") unless File.exist?(path)
        return nil if loinc

        stderr.puts("biometry report: --hl7 needs a LOINC mapping, and data/#{LOINC} " \
                    'has not been transcribed or wired in. Until it is, no OBX identifier ' \
                    'can be named, so no measurement can be read from a message. Supply ' \
                    "#{flags} yourself in the meantime.")
        Main::EXIT_FAILURE
      end

      def usage(message)
        stderr.puts("biometry report: #{message}")
        Main::EXIT_USAGE
      end

      def flags = ReportOptions::MEASUREMENTS.map { |kind| "--#{kind}" }.join(', ')

      def produce(options, scans)
        dating = dating_for(options)
        studies = studied(scans, options)
        stdout.puts(render(dating, studies, options))
        reportable?(dating, studies) ? Main::EXIT_OK : Main::EXIT_FAILURE
      end

      def studied(scans, options)
        rows = Services::Report::GrowthRows.new(manifests: manifests, tables: tables)
        Services::Report::Studies.new(rows: rows)
                                 .call(scans, ga: options[:ga], at: options[:at],
                                              sex: options[:sex], stratum: options[:stratum])
      end

      # Absent unless all three flags arrived, which ReportOptions has already
      # made an all-or-nothing choice.
      def redating_for(options)
        return nil unless options[:established_edd]

        Services::Dating::Redating.new(manifest: manifests[:acog_redating]).call(
          established_edd: options[:established_edd], established_by: options[:established_by],
          proposed_edd: options[:scan_edd], reference_date: options[:at]
        )
      end

      def dating_for(options)
        Services::Dating::AllDerivations.new.call(
          reference_date: options[:at], lmp: options[:lmp], cycle_length: options[:cycle],
          transfer_date: options[:transfer], embryo_day: options[:embryo_day]
        ).value!
      end

      def render(dating, studies, options)
        arguments = { dating: dating, ga: options[:ga], studies: studies,
                      redating: redating_for(options) }
        return Presentation::JsonReport.new.call(**arguments) if options[:json]

        Presentation::Report.new(tty: stdout.tty?).call(**arguments)
      end

      # Exit 1 only when nothing at all could be reported. The refusals are the
      # result and still print; CRL and biometry always refuse, so any other
      # rule would make exit 1 permanent.
      def reportable?(dating, studies)
        rows = studies.flat_map(&:growth)
        dating.values.any?(&:success?) || rows.any? { |row| row[:report].success? }
      end

      def scan_of(options)
        measurements = ReportOptions::MEASUREMENTS.filter_map do |kind|
          Measurement.new(kind: kind, mm: options[kind]) if options[kind]
        end
        Scan.new(date: options[:at], measurements: measurements)
      end

      # No loader yet, deliberately. data/loinc.yml does not exist and its
      # shape has never been decided, so a loader written now would be tested
      # against a schema someone guessed at — which proves nothing about the
      # file that eventually lands. Transcribing the mapping and wiring it here
      # are one piece of work; until then --hl7 refuses and says so.
      def transcribed_loinc = nil

      def context = @context ||= Biometry.load

      def manifests = context.manifests

      def tables = context.tables
    end
  end
end
