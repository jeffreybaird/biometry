# frozen_string_literal: true

module Fixtures
  # Every manifest parses through the real loader, and each declares the
  # fields the adapters read off it.
  module Manifests
    FILES = %w[hadlock intergrowth21 nichd who acog_redating].freeze

    # hadlock.yml nests its range and pairing under `hadlock_1991`;
    # intergrowth21.yml declares no paired formula at all. Expected shapes,
    # asserted so a later edit cannot quietly change them.
    RANGES = {
      'hadlock' => [10, 40], 'intergrowth21' => [22, 40],
      'nichd' => [15, 40], 'who' => [14, 40]
    }.freeze

    PAIRINGS = {
      'hadlock' => 'bpd_hc_ac_fl', 'intergrowth21' => nil,
      'nichd' => 'hadlock_hc_ac_fl', 'who' => 'hadlock_hc_ac_fl'
    }.freeze

    module_function

    def call(report)
      report.section('Manifests load through Biometry::ReferenceData')
      FILES.each { |name| check_file(report, name) }
    end

    def check_file(report, name)
      data = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml")
      report.pass("#{name}.yml loads (verified: #{data.fetch(:verified, 'n/a')})")
      return if name == 'acog_redating'

      report.check("#{name}.yml valid_ga_weeks", range(data), RANGES.fetch(name))
      report.check("#{name}.yml paired_formula", pairing(data), PAIRINGS.fetch(name))
    rescue Biometry::Error => e
      report.fail_with("#{name}.yml loads", e.message)
    end

    def range(data) = data[:valid_ga_weeks] || data.dig(:hadlock_1991, :valid_ga_weeks)

    def pairing(data) = data[:paired_formula] || data.dig(:hadlock_1991, :paired_formula)
  end
end
