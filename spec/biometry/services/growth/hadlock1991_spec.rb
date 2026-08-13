# frozen_string_literal: true

# Integration layer. Hadlock 1991 is the second equation standard, and it
# differs from INTERGROWTH in every way that matters here: its dispersion is a
# constant percentage of the median rather than an LMS triple, its GA
# convention is decimal weeks to the nearest tenth, and its chart pairs with
# the four-parameter Hadlock model rather than with itself.
#
# The dispersion is 13.3%, not the 12.7% the abstract prints. The manifest's
# `abstract_sd_contradicts_table` known_issue records why: the published Table
# 1 centiles are exactly median x {0.750, 0.830, 1.170, 1.250} at every week,
# and 12.7% would put the 3rd centile at 30 weeks 18 g above what the paper
# prints. The published_ratios examples below are what hold that.
RSpec.describe Biometry::Services::Growth::Hadlock1991 do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock_1991.yml').first
  end
  let(:service) { described_class.new(manifest: manifest) }

  # Percentile points. Wide enough for the fixtures' stated gram tolerance,
  # narrow enough to reject a 12.7% implementation: 12.7% reads the paper's
  # own 3rd-centile weight at 32 weeks as the 2.46th.
  def centile_tolerance = 0.3

  def fixture(name) = manifest[:fixtures].find { |f| f[:name] == name }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def efw(grams, formula: :hadlock_bpd_hc_ac_fl)
    Biometry::Estimate.new(
      value: grams, unit: 'g', formula: formula, inputs: %i[bpd hc ac fl],
      source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x',
                                           formula: formula),
      uncertainty: Biometry::Uncertainty.pooled(7.4)
    )
  end

  def call(grams, ga, formula: :hadlock_bpd_hc_ac_fl)
    service.call(estimate: efw(grams, formula: formula), ga: ga)
  end

  def percentile_of(grams, ga) = call(grams, ga).value!.value

  describe 'the centiles it reproduces' do
    it 'reports every published centile at 32 weeks as its own centile' do
      anchor = fixture('centiles at 32 weeks')[:expect_g]
      computed = anchor.transform_values { |g| percentile_of(g, weeks(32)) }
      expect(computed).to match(centile_matchers(anchor.keys))
    end

    it 'reports every published centile at 40 weeks as its own centile' do
      anchor = fixture('centiles at 40 weeks')[:expect_g]
      computed = anchor.transform_values { |g| percentile_of(g, weeks(40)) }
      expect(computed).to match(centile_matchers(anchor.keys))
    end

    # "median equation at selected weeks" spans 10 to 40, i.e. the whole
    # published window, and is the only fixture that exercises the low end.
    it 'reports the median weight at every fixtured week as the 50th' do
      anchor = fixture('median equation at selected weeks')
      computed = anchor[:expect_g].to_h { |wk, g| [wk, percentile_of(g, weeks(wk))] }
      expect(computed.values).to all(be_within(median_tolerance(anchor)).of(50))
    end
  end

  # The dispersion model, stated as the ratios the paper's own table exhibits.
  # This is what distinguishes a 13.3% implementation from a 12.7% one.
  describe 'the dispersion it applies' do
    it 'publishes a constant SD as a percentage of the median' do
      expect(manifest[:dispersion][:sd_pct]).to eq(13.3)
    end

    it 'reads each published ratio of the median as its own centile' do
      median = fixture('centiles at 32 weeks')[:expect_g][:p50]
      computed = manifest[:dispersion][:published_ratios]
                 .transform_values { |ratio| percentile_of(median * ratio, weeks(32)) }
      expect(computed).to match(centile_matchers(computed.keys))
    end
  end

  describe 'the report it returns' do
    subject(:percentile) { call(fixture('centiles at 32 weeks')[:expect_g][:p50], weeks(32)).value! }

    it 'is a Percentile' do
      expect(percentile).to be_a(Biometry::Percentile)
    end

    it 'names the closed form rather than an interpolation rule' do
      expect(percentile.interpolation).to eq(:closed_form)
    end

    it 'evaluates at decimal weeks to the nearest tenth, per the paper' do
      expect(call(3000, weeks(39, 3)).value!.ga_weeks).to eq(39.4)
    end

    it 'names the standard' do
      expect(percentile.source.standard).to eq(:hadlock_1991)
    end

    it 'carries the citation the manifest publishes' do
      expect(percentile.source.citation).to eq(manifest[:source][:citation])
    end

    it 'names the standard as a reference, not a prescriptive one' do
      expect(percentile.source.type).to eq(:reference)
    end

    it 'claims no stratum, because the 1991 chart is unstratified' do
      expect(percentile.source).not_to be_stratified
    end

    it 'reports a number and its source, never a classification' do
      expect(percentile.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end

  context 'when the weight is far outside the centiles Table 1 prints' do
    it 'still computes a value, because dispersion is closed form' do
      expect(call(400, weeks(32)).value!.bound).to eq(:computed)
    end

    it 'reports a percentile inside the unit range' do
      expect(percentile_of(400, weeks(32))).to be_between(0, 100)
    end
  end

  describe 'the gestational age window it was fitted over' do
    it 'reads the window from the manifest rather than assuming one' do
      expect(manifest[:valid_ga_weeks]).to eq([10, 40])
    end

    it 'accepts the first week of the window' do
      expect(call(35, weeks(10))).to be_success
    end

    it 'accepts the last week of the window' do
      expect(call(3619, weeks(40))).to be_success
    end

    it 'refuses a gestation below the window rather than extrapolating' do
      expect(call(30, weeks(9, 6)).failure).to eq(
        [:out_of_range,
         { standard: :hadlock_1991, ga_weeks: 9.9, valid_range: manifest[:valid_ga_weeks] }]
      )
    end

    it 'refuses a gestation one day past the window' do
      expect(call(3619, weeks(40, 1)).failure).to eq(
        [:out_of_range,
         { standard: :hadlock_1991, ga_weeks: 40.1, valid_range: manifest[:valid_ga_weeks] }]
      )
    end
  end

  # The 1991 chart was built on the four-parameter model, identified from the
  # paper's own 0.1% mean error and 7.4% SD. Reading it from the three-
  # parameter weight NICHD and WHO use measures the formula difference and the
  # chart difference at once.
  describe 'the formula its chart was built on' do
    it 'names the four-parameter Hadlock model as the pairing' do
      expect(manifest[:paired_formula].to_sym).to eq(:hadlock_bpd_hc_ac_fl)
    end

    it 'refuses the three-parameter Hadlock weight' do
      expect(call(1953, weeks(32), formula: :hadlock_hc_ac_fl).failure).to eq(
        [:formula_chart_mismatch,
         { chart: :hadlock_1991, expected: :hadlock_bpd_hc_ac_fl, given: :hadlock_hc_ac_fl }]
      )
    end

    it 'refuses an INTERGROWTH weight' do
      expect(call(1953, weeks(32), formula: :intergrowth)).to be_failure
    end
  end

  # p3 => be_within(x).of(3), and so on, so the expected centile comes from
  # the manifest's own key rather than being retyped alongside it.
  def centile_matchers(keys)
    keys.to_h do |key|
      [key, be_within(centile_tolerance).of(Float(key.to_s.delete_prefix('p')))]
    end
  end

  # The median fixture states its tolerance in per cent of weight. Dividing by
  # the SD turns it into a Z offset, and the normal CDF turns that into the
  # percentile band it corresponds to.
  def median_tolerance(anchor)
    z = anchor[:tolerance_pct] / manifest[:dispersion][:sd_pct]
    (Biometry::Services::Growth::Normal.cdf(z) - 0.5) * 100
  end
end
