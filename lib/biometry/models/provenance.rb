# frozen_string_literal: true

module Biometry
  # Not decoration. WHO retained complicated pregnancies by design;
  # INTERGROWTH and NICHD excluded them. A 10th centile does not mean the same
  # thing across that boundary, so the distinction travels with the value
  # rather than being reconstructed at the presentation layer.
  PROVENANCE_TYPES = %i[prescriptive reference].freeze

  # Where a number came from. Every Estimate carries one; a value that cannot
  # name its standard and its formula is incomplete.
  Provenance = Data.define(:standard, :citation, :formula, :type, :stratum) do
    def self.formula(standard:, citation:, formula:)
      new(standard:, citation:, formula:, type: nil, stratum: nil)
    end

    def stratified? = !stratum.nil?

    def to_s
      [standard, stratum && "(#{stratum})"].compact.join(' ')
    end
  end
end
