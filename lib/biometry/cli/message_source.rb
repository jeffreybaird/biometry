# frozen_string_literal: true

require 'dry/monads'

module Biometry
  module CLI
    # Reads a scan out of an HL7 message on disk.
    #
    # Reading the file is the shell's job, which is why the parser itself takes
    # contents. This is the piece that turns a path into either a Scan the
    # report can use or a reason it could not.
    class MessageSource
      include Dry::Monads[:result]

      def initialize(loinc:, stderr:)
        @loinc = loinc
        @stderr = stderr
      end

      def call(path)
        parsed = Hl7::Oru.new(mapping: loinc).call(File.read(path))
        return parsed if parsed.failure?

        report(parsed.value!)
        usable(parsed.value!)
      end

      private

      attr_reader :loinc, :stderr

      # Every study that yielded a measurement, in the order the message
      # reported them. Choosing among them by segment order would be a choice
      # made by accident of layout; the report shows them all.
      #
      # A study whose observations were all unrecognised leaves the collection
      # rather than becoming a table with no rows — its identifiers are already
      # on stderr, so nothing vanishes silently.
      def usable(ingest)
        scans = ingest.scans.select { |candidate| candidate.measurements.any? }
        return Success(scans) if scans.any?

        Failure([:insufficient_data,
                 { required: :measurements, given: :unreadable_observations }])
      end

      # Diagnostics go to stderr: they are not the result, and a caller piping
      # the report should not find them in it. They are never withheld — an
      # observation this library ignored is something the reader has to know it
      # ignored.
      def report(ingest)
        ingest.unrecognised.each do |item|
          stderr.puts("biometry report: segment #{item.segment} #{item.identifier} " \
                      "not read (#{item.reason})")
        end
        ingest.malformed.each do |item|
          stderr.puts("biometry report: segment #{item.segment} field #{item.field} " \
                      "could not be read (#{item.reason})")
        end
      end
    end
  end
end
