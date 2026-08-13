# frozen_string_literal: true

require 'csv'
require 'date'
require 'yaml'

module Biometry
  # Reads the hand-transcribed constants under data/ and hands parsed,
  # frozen structures to services as arguments. This is the imperative shell:
  # it is the only place in the library that touches the filesystem, and
  # nothing under services/ or models/ may call it.
  #
  # Returns plain Hashes and Arrays rather than typed manifests. The four
  # manifests do not share a shape — hadlock.yml nests its range and paired
  # formula under `hadlock_1991`, intergrowth21.yml states no paired formula
  # at all — so a common type here would be a guess. Each adapter reads the
  # keys it needs.
  module ReferenceData
    # data/who.yml writes correction dates unquoted, which is legal YAML and
    # loads as a Date. safe_load rejects it unless Date is permitted, and
    # data/ is read-only, so the permission belongs here.
    PERMITTED_CLASSES = [Date].freeze

    module_function

    # Reads a YAML manifest. Raises rather than returning a Failure: an
    # unverified or unreadable constant file is a developer error, not a
    # runtime condition, and no caller should branch on it.
    def load_manifest(path)
      data = parse_yaml(path)
      raise MalformedReferenceData, "#{path} did not parse to a mapping." unless data.is_a?(Hash)

      refuse_unverified(path, data)
      deep_freeze(data)
    end

    # Reads a percentile table. Blank cells stay nil — WHO's sex-specific
    # tables omit 2.5 and 97.5, and that absence is data.
    def load_table(path)
      CSV.read(path, headers: true).map { |row| coerce_row(row) }.freeze
    rescue Errno::ENOENT => e
      raise MalformedReferenceData, "#{path} could not be read: #{e.message}"
    end

    def parse_yaml(path)
      YAML.safe_load_file(path, symbolize_names: true, permitted_classes: PERMITTED_CLASSES)
    rescue Errno::ENOENT, Psych::Exception => e
      raise MalformedReferenceData, "#{path} could not be parsed: #{e.message}"
    end

    def refuse_unverified(path, data)
      return if data[:verified] != false

      raise UnverifiedReferenceData,
            "#{path} is marked unverified. Check every value against the source, " \
            'set verified: true, then re-run.'
    end

    def coerce_row(row)
      row.to_h.transform_keys(&:to_sym).transform_values { |value| coerce(value) }.freeze
    end

    def coerce(value)
      return nil if value.nil? || value.strip.empty?
      return Integer(value, 10) if value.match?(/\A-?\d+\z/)
      return Float(value) if value.match?(/\A-?\d*\.\d+\z/)

      value.freeze
    end

    def deep_freeze(object)
      case object
      when Hash then object.each_value { |v| deep_freeze(v) }.freeze
      when Array then object.each { |v| deep_freeze(v) }.freeze
      else object.freeze
      end
    end
  end
end
