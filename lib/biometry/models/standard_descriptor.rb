# frozen_string_literal: true

module Biometry
  # One growth chart as its manifest describes it. `id` is the chart id the
  # registry serves; `standard` is the manifest it was read from — they differ
  # only where one paper is served as several variants, and `variant` and
  # `variant_note` then say which reading this is.
  #
  # Absent fields are nil, never a default: a manifest that states no ga_units
  # is reported as stating none.
  StandardDescriptor = Data.define(
    :id, :standard, :variant,
    :kind, :type, :access,
    :citation, :doi, :pmid,
    :valid_ga_weeks, :ga_units,
    :centiles, :stratification, :paired_formula,
    :known_issues, :variant_note
  )
end
