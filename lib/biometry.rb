# frozen_string_literal: true

require 'pathname'

require_relative 'biometry/errors'
require_relative 'biometry/models/estimate'
require_relative 'biometry/models/gestational_age'
require_relative 'biometry/models/measurement'
require_relative 'biometry/models/provenance'
require_relative 'biometry/models/scan'
require_relative 'biometry/reference_data'
require_relative 'biometry/services/weight/equation'
require_relative 'biometry/services/weight/hadlock'
require_relative 'biometry/services/weight/intergrowth'
require_relative 'biometry/services/weight/all_formulas'

module Biometry
  VERSION = '0.1.0'

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
