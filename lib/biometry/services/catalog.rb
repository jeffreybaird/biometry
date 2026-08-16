# frozen_string_literal: true

module Biometry
  module Services
    # Describes what the library serves, read from the manifests and from the
    # services that own the behaviour. Nothing is typed out here: a catalog
    # entry that disagreed with data/ would be a second transcription, wrong
    # in the way that stays green.
    class Catalog
      # The dating derivations are implemented in code, not published in a
      # manifest, so their descriptors read the services' own constants.
      DATING = [Dating::Lmp, Dating::Transfer].freeze

      def initialize(manifests:)
        @manifests = manifests
      end

      def call
        Biometry::Catalog.new(growth_standards: growth_standards.freeze,
                              efw_formulas: efw_formulas.freeze,
                              dating_methods: dating_methods.freeze,
                              redating_policy: redating_policy)
      end

      private

      attr_reader :manifests

      # One descriptor per chart the registry derives: a manifest that names a
      # paired_formula, expanded to one entry per variant where it has any.
      def growth_standards
        manifests.select { |_, manifest| manifest[:paired_formula] }.flat_map do |key, manifest|
          variants_of(manifest).map do |variant, description|
            standard(key, manifest, variant, description)
          end
        end
      end

      def variants_of(manifest) = manifest[:variants] || { nil => nil }

      def standard(key, manifest, variant, description)
        StandardDescriptor.new(
          id: description ? description[:id].to_sym : key,
          standard: key, variant: variant,
          variant_note: description && description[:note],
          paired_formula: manifest[:paired_formula].to_sym,
          **published(manifest)
        )
      end

      def published(manifest)
        cited(manifest[:source])
          .merge(valid_ga_weeks: manifest[:valid_ga_weeks], ga_units: manifest[:ga_units]&.to_sym,
                 centiles: manifest[:centiles], stratification: manifest[:stratification],
                 known_issues: manifest[:known_issues])
      end

      def cited(source)
        { kind: source[:kind]&.to_sym, type: source[:type]&.to_sym, access: source[:access]&.to_sym,
          citation: source[:citation], doi: source[:doi], pmid: source[:pmid] }
      end

      # Every formula any manifest publishes, cited by the manifest that
      # publishes it: hadlock_1985's `efw_formulas` block and any chart
      # manifest carrying its own `efw` (INTERGROWTH-21st).
      def efw_formulas
        manifests.values.flat_map do |manifest|
          entries = (manifest[:efw_formulas]&.values || []) + [manifest[:efw]].compact
          entries.map { |entry| formula(entry, manifest[:source]) }
        end
      end

      def formula(entry, source)
        FormulaDescriptor.new(id: entry[:id].to_sym, requires: entry[:requires].map(&:to_sym),
                              equation: entry[:equation], citation: source[:citation],
                              doi: source[:doi], pmid: source[:pmid])
      end

      def dating_methods
        DATING.map do |service|
          DerivationDescriptor.new(derivation: service::DERIVATION,
                                   standard: service::STANDARD,
                                   citation: service::CITATION)
        end
      end

      def redating_policy
        manifest = manifests[:acog_redating]
        RedatingPolicy.new(standard: Dating::Redating::STANDARD,
                           citation: manifest.dig(:source, :citation),
                           known_issues: manifest[:known_issues])
      end
    end
  end
end
