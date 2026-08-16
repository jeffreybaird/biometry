# frozen_string_literal: true

module Biometry
  module Services
    module Growth
      # The chart registry, derived from the manifests rather than typed out.
      #
      # A growth manifest is one that names a `paired_formula`; each becomes a
      # chart read through its own adapter. A manifest with a `variants` block
      # becomes one chart per variant — Hadlock 1991's contested dispersion is
      # served as two charts from the one paper, never collapsed to one.
      #
      # Which class implements which standard is code wiring and lives here;
      # everything else about a chart comes from data/.
      class Charts
        ADAPTERS = { intergrowth21: Intergrowth,
                     hadlock_1991: Hadlock1991,
                     nichd: Nichd,
                     who: Who }.freeze

        def initialize(manifests:, tables:)
          @manifests = manifests
          @tables = tables
        end

        def call
          published.flat_map { |key, manifest| entries(key, manifest) }.to_h.freeze
        end

        private

        attr_reader :manifests, :tables

        def published = manifests.select { |_, manifest| manifest[:paired_formula] }

        def entries(key, manifest)
          formula = manifest[:paired_formula].to_sym
          adapters(key, manifest).map do |id, adapter|
            [id, { formula: formula, manifest: manifest, adapter: adapter }.freeze]
          end
        end

        # One adapter per chart id. Without variants the manifest key is the
        # chart id; with them, each variant names its own id and its adapter is
        # built on that variant, so the two readings really differ.
        def adapters(key, manifest)
          return { key => adapter(key, manifest) } unless manifest[:variants]

          manifest[:variants].to_h do |variant, description|
            [description[:id].to_sym,
             ADAPTERS.fetch(key).new(manifest: manifest, variant: variant.to_sym)]
          end
        end

        def adapter(key, manifest)
          klass = ADAPTERS.fetch(key)
          return klass.new(manifest: manifest) unless table?(manifest)

          klass.new(manifest: manifest, table: tables.fetch(key))
        end

        def table?(manifest) = manifest.dig(:source, :access).to_s == 'table'
      end
    end
  end
end
