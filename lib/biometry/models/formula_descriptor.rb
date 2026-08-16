# frozen_string_literal: true

module Biometry
  # One estimated-fetal-weight formula: the measurements it is read from, the
  # equation as its paper prints it, and the citation of the manifest that
  # publishes it.
  FormulaDescriptor = Data.define(:id, :requires, :equation, :citation, :doi, :pmid)
end
