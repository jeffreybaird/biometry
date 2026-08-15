# frozen_string_literal: true

module Biometry
  module Hl7
    # One line of a message, split with the separators the message declared.
    #
    # Field positions are HL7's own 1-based numbering, so a spec and a reader
    # both count the way the standard does. MSH is the exception the standard
    # itself makes: its separator occupies the position a first field would,
    # so its fields sit one place further along than the numbering suggests.
    class Segment
      MSH = 'MSH'
      UNITS_FIELD = 6

      def initialize(line, field_separator, component_separator)
        @fields = line.split(field_separator, -1)
        @component = component_separator
      end

      def name = fields.first

      def header? = name == MSH

      def study? = name == 'OBR'

      def observation? = name == 'OBX'

      # MSH-9 is the message type, whose first two components are the message
      # code and the trigger event. Read as components so a vendor writing its
      # own component separator is understood.
      def type = header? ? components(9).first(2) : nil

      # Only OBX-3's first component names the observation; the rest is the
      # text a human reads and the coding system it came from.
      def identifier = components(3).first

      # OBX-6 may be a plain string or a coded element, in which case the unit
      # is its first component.
      def units = components(UNITS_FIELD).first

      def field(position) = presence(raw(position))

      private

      attr_reader :fields, :component

      # MSH-1 is the field separator itself, so MSH-n lands one earlier in the
      # split than every other segment's does.
      def raw(position) = fields[header? ? position - 1 : position]

      def components(position) = presence(raw(position)).to_s.split(component, -1)

      def presence(value) = value.nil? || value.empty? ? nil : value
    end
  end
end
