# frozen_string_literal: true

module Fixtures
  # The growth-standard fixtures became checkable when slice 4 landed. Each is
  # driven through the real adapter in the percentile direction: feed the
  # weight the paper publishes for a centile, expect that centile back.
  module Growth
    TOLERANCE = 0.3 # centile points

    module_function

    def call(report)
      report.section('Growth standards (slice 4 — checkable now)')
      hadlock(report)
      intergrowth(report)
    end

    def hadlock(report)
      manifest, = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock_1991.yml')
      service = Biometry::Services::Growth::Hadlock1991.new(manifest: manifest)
      formula = manifest[:paired_formula].to_sym

      median_fixture(report, manifest, service, formula)
      manifest[:fixtures].select { |f| f[:inputs] }.each do |fixture|
        centile_fixture(report, service, formula, fixture)
      end
    end

    # expect_g maps week => the median weight at that week, so every entry
    # should read back as the 50th. The stated tolerance is in per cent of
    # weight; dividing by the SD turns it into centile points.
    def median_fixture(report, manifest, service, formula)
      fixture = manifest[:fixtures].find { |f| f[:expect_g] && !f[:inputs] }
      tolerance = centile_points(fixture[:tolerance_pct], manifest[:dispersion][:sd_pct])

      fixture[:expect_g].each do |week, grams|
        check(report, service, name: "hadlock_1991 median at #{week} wk", formula: formula,
                               grams: grams, week: week, expected: 50, tolerance: tolerance)
      end
    end

    def centile_points(tolerance_pct, sd_pct)
      (Biometry::Services::Growth::Normal.cdf(tolerance_pct / sd_pct) - 0.5) * 100
    end

    def centile_fixture(report, service, formula, fixture)
      week = fixture[:inputs][:ga_weeks]
      fixture[:expect_g].each do |key, grams|
        check(report, service, name: "hadlock_1991 #{key} at #{week} wk", formula: formula,
                               grams: grams, week: week,
                               expected: Float(key.to_s.delete_prefix('p')))
      end
    end

    def intergrowth(report)
      manifest, = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'intergrowth21.yml')
      service = Biometry::Services::Growth::Intergrowth.new(manifest: manifest)
      formula = manifest[:paired_formula].to_sym

      third_centile(report, manifest, service, formula)
      table_s1(report, manifest, service, formula)
    end

    def third_centile(report, manifest, service, formula)
      fixture = manifest[:fixtures].find { |f| f[:name] == '3rd centile at 30+0' }
      week = fixture[:inputs][:ga_weeks]
      check(report, service, name: "intergrowth 3rd centile at #{week} wk", formula: formula,
                             grams: fixture[:expect][:efw_g], week: week, expected: 3)
    end

    # 33 weeks is the week the manifest records as matching published Table S1
    # to the gram; term_tail_divergence warns off anything above ~38.
    def table_s1(report, manifest, service, formula)
      fixture = manifest[:fixtures].find { |f| f[:name] == 'Table S1 centiles at 33+0' }
      week = fixture[:inputs][:ga_weeks]
      { c03_g: 3, c50_g: 50, c97_g: 97 }.each do |key, expected|
        check(report, service, name: "intergrowth #{expected}th centile at #{week} wk",
                               formula: formula, grams: fixture[:expect][key], week: week,
                               expected: expected)
      end
    end

    def check(report, service, name:, formula:, grams:, week:, expected:, tolerance: TOLERANCE)
      ga = Biometry::GestationalAge.from(weeks: week)
      actual = service.call(estimate: estimate(grams, formula), ga: ga).value!.value
      return report.pass("#{name} -> #{expected}th") if (actual - expected).abs <= tolerance

      report.fail_with("#{name} -> #{expected}th", "got #{actual.round(2)}")
    end

    def estimate(grams, formula)
      Biometry::Estimate.new(value: grams, unit: 'g', formula: formula, inputs: [],
                             source: Biometry::Provenance.formula(standard: :fixture,
                                                                  citation: nil, formula: formula),
                             uncertainty: nil)
    end
  end
end
