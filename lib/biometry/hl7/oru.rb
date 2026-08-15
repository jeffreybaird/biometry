# frozen_string_literal: true

require 'date'
require 'dry/monads'

module Biometry
  module Hl7
    # Parses an ORU^R01 observation message into Scans.
    #
    # The imperative shell: it is handed the message contents, never a path.
    #
    # The LOINC mapping is injected rather than known. No mapping is
    # transcribed in data/, and a transposed code maps HC onto AC silently,
    # producing a plausible wrong weight — so the codes are the caller's and
    # this class only applies them.
    #
    # Nothing here guesses. A unit it cannot convert, an identifier it cannot
    # name and a value that is not a number are each reported rather than
    # assumed, because every one of those guesses is wrong by a factor a
    # reader would not notice.
    class Oru
      include Dry::Monads[:result]

      MESSAGE_TYPE = %w[ORU R01].freeze
      TERMINATORS = /\r\n|\r|\n/
      CONVERSIONS = { 'mm' => 1, 'cm' => 10 }.freeze
      TIMESTAMP = /\A(\d{4})(\d{2})(\d{2})/

      # OBX-5 is the value, OBX-6 the units; OBR-7 is when the study was
      # observed, which is not when the message was sent.
      VALUE = 5
      UNITS = 6
      OBSERVED_AT = 7

      def initialize(mapping:)
        @mapping = mapping
      end

      # Guards answer in order: is this an ORU at all, then is it narrative,
      # then the segments. A message that is not an ORU is refused before its
      # observations are examined — they are answers to a question nobody asked
      # of this message.
      def call(contents)
        segments = segments_of(contents)
        header = segments.first
        return wrong_message(header) unless ours?(header)
        return narrative if narrative?(segments)

        Success(read(segments))
      end

      private

      attr_reader :mapping

      # --------------------------------------------------------- the message -

      # MSH-1 is the field separator itself and MSH-2 the remaining encoding
      # characters, so both are read off the message rather than assumed. A
      # parser that hardcodes |^~\& reads exactly one vendor's output.
      def segments_of(contents)
        lines = contents.to_s.split(TERMINATORS).reject(&:empty?)
        field = lines.first.to_s[3]
        lines.map { |line| Segment.new(line, field, lines.first.to_s[4]) }
      end

      def ours?(header) = header && header.type == MESSAGE_TYPE

      def wrong_message(header)
        Failure([:invalid_input, { expected: MESSAGE_TYPE, given: header&.type }])
      end

      # Prose with no discrete observation is the case this library refuses
      # rather than guesses at. The numbers are in the sentence, and reading
      # them out of it is how a clinician is handed a confidently wrong weight.
      # The test is whether anything this library *names* carries a number.
      # Prose alongside an amniotic fluid index is still prose as far as
      # biometry goes, and an observation in units nothing converts is a
      # discrete observation that happens to be unusable — a different problem,
      # reported per segment rather than refused.
      # Two conditions. There has to be prose — a message of numbers under
      # identifiers nothing maps is not a narrative report, it is a report this
      # library has no vocabulary for, and those identifiers are worth handing
      # back. And nothing the mapping names may carry a number, or the prose is
      # commentary alongside discrete observations rather than instead of them.
      def narrative?(segments)
        observations = segments.select(&:observation?)
        observations.any? { |obx| !numeric?(obx.field(VALUE)) } &&
          observations.none? { |obx| discrete?(obx) }
      end

      def discrete?(observation)
        mapping[observation.identifier] && numeric?(observation.field(VALUE))
      end

      def narrative
        Failure([:insufficient_data,
                 { required: :discrete_observations, given: :narrative_text }])
      end

      def numeric?(value) = !Float(value.to_s, exception: false).nil?

      # -------------------------------------------------------- the segments -

      def read(segments)
        state = { scans: [], unrecognised: [], malformed: [], date: nil, open: false,
                  measurements: [] }
        segments.each_with_index { |segment, index| consume(state, segment, index + 1) }
        close(state)
        Ingest.new(scans: state[:scans], unrecognised: state[:unrecognised],
                   malformed: state[:malformed])
      end

      def consume(state, segment, position)
        return start_study(state, segment, position) if segment.study?
        return unless segment.observation?

        observe(state, segment, position)
      end

      # One Scan per OBR: the observations belong to the study they follow, and
      # that grouping is what tells two scans in a message from one scan with
      # twice the observations.
      def start_study(state, segment, position)
        close(state)
        state[:open] = true
        state[:date] = date_of(segment.field(OBSERVED_AT))
        return if state[:date]

        state[:malformed] << Malformed.new(segment: position, field: OBSERVED_AT,
                                           reason: :missing)
      end

      # A Scan is a dated set of measurements and this library has no undated
      # one, so an OBR with no observation date yields no scan rather than
      # borrowing one from the message header or the next study — and its
      # observations are discarded with it rather than drifting onto whichever
      # scan comes next.
      #
      # A dated study with nothing usable in it is still a scan. The study
      # happened; that its observations could not be read is what the
      # diagnostics are for.
      def close(state)
        measurements = state[:measurements]
        state[:measurements] = []
        return unless state[:open] && state[:date]

        state[:scans] << Scan.new(date: state[:date], measurements: measurements)
      end

      # Order matters. A mapped observation whose value is prose is a segment
      # this library could not read; one whose units are unconvertible is an
      # observation it could read and will not use. Reporting the second as the
      # first would send a reader looking for a typo in a field that was fine.
      def observe(state, segment, position)
        kind = mapping[segment.identifier]
        return state[:unrecognised] << unnamed(segment, position) unless kind

        measured(state, segment, position, kind)
      end

      def measured(state, segment, position, kind)
        return state[:malformed] << not_a_number(position) unless numeric?(segment.field(VALUE))

        millimetres = millimetres_of(segment)
        return state[:unrecognised] << unconvertible(segment, position) unless millimetres

        state[:measurements] << Measurement.new(kind: kind, mm: millimetres)
      end

      def millimetres_of(segment)
        scale = CONVERSIONS[segment.units]
        value = Float(segment.field(VALUE).to_s, exception: false)
        return nil unless scale && value

        scaled = value * scale
        scaled == scaled.to_i ? scaled.to_i : scaled
      end

      # ------------------------------------------------------ the complaints -

      def unnamed(segment, position)
        Unrecognised.new(segment: position, identifier: segment.identifier,
                         units: segment.units, reason: :identifier)
      end

      def unconvertible(segment, position)
        Unrecognised.new(segment: position, identifier: segment.identifier,
                         units: segment.units, reason: :units)
      end

      def not_a_number(position)
        Malformed.new(segment: position, field: VALUE, reason: :not_a_number)
      end

      def date_of(timestamp)
        match = TIMESTAMP.match(timestamp.to_s)
        # Base 10 explicitly: "08" is not octal, it is August.
        match && Date.new(*match.captures.map { |part| Integer(part, 10) })
      end
    end
  end
end
