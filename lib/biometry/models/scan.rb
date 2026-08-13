# frozen_string_literal: true

module Biometry
  # A dated set of measurements. `date` is a Date; this library has no times
  # and no zones.
  Scan = Data.define(:date, :measurements) do
    def kinds = measurements.map(&:kind)

    def [](kind) = measurements.find { |m| m.kind == kind }

    def mm(kind) = self[kind]&.mm
    def cm(kind) = self[kind]&.cm

    def supports?(required) = (required - kinds).empty?

    def missing(required) = required - kinds
  end
end
