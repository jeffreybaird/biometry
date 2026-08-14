# frozen_string_literal: true

require_relative 'report_command'

module Biometry
  module CLI
    # Top-level dispatch. Owns no clinical logic: it parses argv, calls a
    # service, and hands the Result to exe/ to become an exit code.
    #
    # No subcommands are wired yet. Slices 1 and 3 add `date` and `weight`.
    class Main
      EXIT_OK = 0
      EXIT_FAILURE = 1
      EXIT_USAGE = 2

      USAGE = <<~TEXT
        Usage: biometry <command> [options]

        Commands:
          report --ga 32w0d [--bpd|--hc|--ac|--fl MM] [--lmp DATE] [--cycle N]
                 [--transfer DATE] [--embryo-day N] [--sex SEX] [--stratum S]
                 [--at DATE] [--json]

        Options:
          -h, --help       Print this message
          -v, --version    Print the version

        Every command that prints structured data supports --json.
      TEXT

      def initialize(stdout:, stderr:)
        @stdout = stdout
        @stderr = stderr
      end

      def call(argv)
        command, = argv

        case command
        when '-h', '--help', 'help', nil then usage(EXIT_OK)
        when '-v', '--version' then version
        when 'report' then ReportCommand.new(stdout: stdout, stderr: stderr).call(argv)
        else unknown(command)
        end
      end

      private

      attr_reader :stdout, :stderr

      def usage(status)
        (status.zero? ? stdout : stderr).puts(USAGE)
        status
      end

      def version
        stdout.puts(Biometry::VERSION)
        EXIT_OK
      end

      def unknown(command)
        stderr.puts("biometry: unknown command #{command.inspect}")
        usage(EXIT_USAGE)
      end
    end
  end
end
