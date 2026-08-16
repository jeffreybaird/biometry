# frozen_string_literal: true

require 'pathname'

require_relative 'biometry/version'
require_relative 'biometry/errors'
require_relative 'biometry/models/boundary_sensitivity'
require_relative 'biometry/models/caveat'
require_relative 'biometry/models/chart_weight'
require_relative 'biometry/models/dating_estimate'
require_relative 'biometry/models/estimate'
require_relative 'biometry/models/percentile'
require_relative 'biometry/models/redating_decision'
require_relative 'biometry/models/gestational_age'
require_relative 'biometry/models/measurement'
require_relative 'biometry/models/provenance'
require_relative 'biometry/models/scan'
require_relative 'biometry/models/study'
require_relative 'biometry/models/uncertainty'
require_relative 'biometry/hl7/ingest'
require_relative 'biometry/hl7/segment'
require_relative 'biometry/hl7/oru'
require_relative 'biometry/reference_data'
require_relative 'biometry/services/weight/equation'
require_relative 'biometry/services/weight/hadlock'
require_relative 'biometry/services/weight/intergrowth'
require_relative 'biometry/services/weight/all_formulas'
require_relative 'biometry/presentation/format'
require_relative 'biometry/presentation/reason'
require_relative 'biometry/presentation/json_report'
require_relative 'biometry/presentation/report'
require_relative 'biometry/services/dating/lmp'
require_relative 'biometry/services/dating/transfer'
require_relative 'biometry/services/dating/all_derivations'
require_relative 'biometry/services/dating/redating'
require_relative 'biometry/services/growth/normal'
require_relative 'biometry/services/growth/interpolation'
require_relative 'biometry/services/growth/hadlock1991'
require_relative 'biometry/services/growth/intergrowth'
require_relative 'biometry/services/growth/nichd'
require_relative 'biometry/services/growth/who'
require_relative 'biometry/services/growth/who/centiles'
require_relative 'biometry/services/growth/charts'
require_relative 'biometry/services/report/growth_rows'
require_relative 'biometry/services/report/studies'

module Biometry
  ROOT = Pathname.new(File.expand_path('..', __dir__)).freeze
  DATA_ROOT = (ROOT / 'data').freeze

  # The failure tags every service may return. Listed here so four adapters
  # cannot invent four spellings of the same condition.
  FAILURE_TAGS = %i[
    insufficient_data
    out_of_range
    unsupported_standard
    unsupported_centile
    formula_chart_mismatch
    invalid_input
  ].freeze
end
