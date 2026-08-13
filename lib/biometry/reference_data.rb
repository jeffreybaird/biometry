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
  # chart manifests now share a schema, but hadlock_1985.yml publishes
  # formulas rather than a chart and acog_redating.yml is neither, so a common
  # type here would still be a guess. Each adapter reads the keys it needs;
  # the fixture harness is what holds the chart schema to its shape.
  module ReferenceData
    # data/who.yml writes correction dates unquoted, which is legal YAML and
    # loads as a Date. safe_load rejects it unless Date is permitted, and
    # data/ is read-only, so the permission belongs here.
    PERMITTED_CLASSES = [Date].freeze

    module_function

    # Reads a YAML manifest, returning [data, dropped].
    #
    # A file whose top-level `verified` is false raises: that is a developer
    # error, not a runtime condition, and no caller should branch on it.
    #
    # An entry *within* a file that is marked unverified is pruned instead, so
    # it never reaches a service at all. That collapses "unverified" into
    # "absent", which every adapter already handles — the alternative, a guard
    # each adapter is obliged to remember, is the seam defect that a
    # four-adapter slice exists to produce.
    #
    # `dropped` lists the key paths removed, e.g.
    # [[:efw_formulas, :bpd_hc_ac_fl]]. Pruning silently would be worse than
    # the guard: a caller has to be able to say what is unavailable and why.
    def load_manifest(path)
      data = parse_yaml(path)
      raise MalformedReferenceData, "#{path} did not parse to a mapping." unless data.is_a?(Hash)

      refuse_unverified(path, data)
      pruned, dropped = prune_unverified(data)
      [deep_freeze(pruned), dropped.freeze]
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

    # An entry is unverified only when it says so itself. A missing `verified`
    # key means the surrounding file vouched for it, which is how the four
    # manifests that carry no per-entry flags keep working.
    def unverified?(value) = value.is_a?(Hash) && value[:verified] == false

    def prune_unverified(node, path = [])
      return prune_hash(node, path) if node.is_a?(Hash)
      return prune_array(node, path) if node.is_a?(Array)

      [node, []]
    end

    def prune_hash(hash, path)
      dropped = []
      kept = {}
      hash.each do |key, value|
        child_path = path + [key]
        next dropped << child_path if unverified?(value)

        kept[key], child_dropped = prune_unverified(value, child_path)
        dropped.concat(child_dropped)
      end
      [kept, dropped]
    end

    # Arrays are walked too: ACOG's redating bands are a list, and one
    # unverified band must not reach the service any more than one unverified
    # formula must.
    def prune_array(array, path)
      dropped = []
      kept = []
      array.each_with_index do |value, index|
        child_path = path + [index]
        next dropped << child_path if unverified?(value)

        child, child_dropped = prune_unverified(value, child_path)
        kept << child
        dropped.concat(child_dropped)
      end
      [kept, dropped]
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
