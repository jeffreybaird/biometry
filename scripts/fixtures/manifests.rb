# frozen_string_literal: true

module Fixtures
  # Every manifest parses through the real loader, declares the fields the
  # adapters read off it, and — the check that would have caught the split
  # going wrong — every `paired_formula` resolves to a formula that exists.
  module Manifests
    FILES = %w[hadlock_1985 hadlock_1991 intergrowth21 nichd who acog_redating].freeze

    # The four growth standards. hadlock_1985.yml holds formulas rather than a
    # chart, and acog_redating.yml is neither, so both are checked separately.
    CHARTS = {
      'hadlock_1991' => { range: [10, 40], pairing: 'hadlock_bpd_hc_ac_fl', access: 'equation' },
      'intergrowth21' => { range: [22, 40], pairing: 'intergrowth', access: 'equation' },
      'nichd' => { range: [15, 40], pairing: 'hadlock_hc_ac_fl', access: 'table' },
      'who' => { range: [14, 40], pairing: 'hadlock_hc_ac_fl', access: 'table' }
    }.freeze

    # Keys every chart manifest must carry. The point is uniformity: an adapter
    # reading stratification.field must not find a bare scalar on one chart.
    CHART_KEYS = %i[valid_ga_weeks paired_formula stratification centiles known_issues].freeze

    module_function

    def call(report)
      report.section('Manifests load through Biometry::ReferenceData')
      loaded = FILES.to_h { |name| [name, load(report, name)] }
      CHARTS.each_key { |name| check_chart(report, name, loaded[name]) if loaded[name] }
      check_pairings(report, loaded)
    end

    def load(report, name)
      data, dropped = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml")
      report.pass("#{name}.yml loads (verified: #{data.fetch(:verified, 'n/a')})")
      dropped.each { |path| report.pending(path.join('.'), 'pruned, marked unverified') }
      data
    rescue Biometry::Error => e
      report.fail_with("#{name}.yml loads", e.message)
      nil
    end

    def check_chart(report, name, data)
      expected = CHARTS.fetch(name)
      report.check("#{name}.yml valid_ga_weeks", data[:valid_ga_weeks], expected[:range])
      report.check("#{name}.yml paired_formula", data[:paired_formula], expected[:pairing])
      report.check("#{name}.yml source.access", data.dig(:source, :access), expected[:access])
      check_schema(report, name, data)
    end

    def check_schema(report, name, data)
      missing = CHART_KEYS.reject { |key| data.key?(key) }
      report.check("#{name}.yml carries every chart key", missing, [])

      block = data[:stratification]
      report.check("#{name}.yml stratification is a block",
                   block.is_a?(Hash) && block.key?(:field), true)
    end

    # Cross-file integrity. A chart naming a formula that no file publishes is
    # how a split or a rename goes wrong silently.
    def check_pairings(report, loaded)
      known = formula_ids(loaded)
      CHARTS.each_key do |name|
        pairing = loaded[name]&.fetch(:paired_formula, nil)
        next unless pairing

        report.check("#{name}.yml pairing #{pairing} resolves", known.include?(pairing), true)
      end
    end

    def formula_ids(loaded)
      (loaded['hadlock_1985']&.fetch(:efw_formulas, {})&.keys || []).map(&:to_s) +
        [loaded['intergrowth21']&.dig(:efw, :id)].compact
    end
  end
end
