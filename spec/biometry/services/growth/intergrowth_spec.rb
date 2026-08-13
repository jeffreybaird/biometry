# frozen_string_literal: true

# Integration layer: the adapter, the manifest as ReferenceData hands it over,
# and the slice 3 Estimate together. The service is constructed from parsed
# manifest contents, never a path.
#
# INTERGROWTH is an equation standard. Its LMS parameters are closed-form
# functions of exact decimal weeks, so any centile is computable and there is
# no outermost published column to bracket against — the two ways this adapter
# differs from the table standards.
#
# The anchors are the manifest's own `fixtures:` block, read from the YAML
# rather than retyped. Two known_issues constrain what may be fixtured: the
# paper's quoted Z-score of 0.5617023 does not follow from its own Table 2 and
# is not used here, and computed centiles diverge from published Table S1
# above ~38 weeks, so nothing beyond 33 weeks asserts a value.
RSpec.describe Biometry::Services::Growth::Intergrowth do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'intergrowth21.yml').first
  end
  let(:service) { described_class.new(manifest: manifest) }

  # Percentile points. 1 g of the manifest's stated gram tolerance moves the
  # percentile by well under this at every fixtured week.
  def tolerance = 0.2

  def fixture(name) = manifest[:fixtures].find { |f| f[:name] == name }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def efw(grams, formula: :intergrowth)
    Biometry::Estimate.new(
      value: grams, unit: 'g', formula: formula, inputs: %i[ac hc],
      source: Biometry::Provenance.formula(standard: :intergrowth21, citation: 'x',
                                           formula: formula),
      uncertainty: nil
    )
  end

  def call(grams, ga, formula: :intergrowth)
    service.call(estimate: efw(grams, formula: formula), ga: ga)
  end

  def percentile_of(grams, ga) = call(grams, ga).value!.value

  describe 'the centiles it reproduces' do
    # "3rd centile at 30+0": the paper's own worked example, 1106 g.
    it "reports the paper's worked 3rd centile weight as the 3rd percentile" do
      anchor = fixture('3rd centile at 30+0')
      expect(percentile_of(anchor[:expect][:efw_g], weeks(30)))
        .to be_within(tolerance).of(3)
    end

    # "Table S1 centiles at 33+0". 33 weeks is the week the manifest records as
    # matching the published supplement to the gram.
    it 'reproduces every Table S1 centile it publishes at 33 weeks' do
      anchor = fixture('Table S1 centiles at 33+0')[:expect]
      weights = { 3 => anchor[:c03_g], 50 => anchor[:c50_g], 97 => anchor[:c97_g] }
      computed = weights.transform_values { |g| percentile_of(g, weeks(33)) }
      expect(computed).to match(weights.keys.to_h { |c| [c, be_within(tolerance).of(c)] })
    end
  end

  describe 'the report it returns' do
    subject(:percentile) { call(fixture('3rd centile at 30+0')[:expect][:efw_g], ga).value! }

    let(:ga) { weeks(30) }

    it 'is a Percentile' do
      expect(percentile).to be_a(Biometry::Percentile)
    end

    it 'names the closed form rather than an interpolation rule' do
      expect(percentile.interpolation).to eq(:closed_form)
    end

    it 'evaluates at exact decimal weeks, the convention this standard uses' do
      expect(call(1500, weeks(30, 3)).value!.ga_weeks).to be_within(1e-9).of(30 + (3 / 7.0))
    end

    it 'names the standard' do
      expect(percentile.source.standard).to eq(:intergrowth21)
    end

    it 'carries the citation the manifest publishes' do
      expect(percentile.source.citation).to eq(manifest[:source][:citation])
    end

    it 'names the standard as prescriptive, because a reference centile differs' do
      expect(percentile.source.type).to eq(:prescriptive)
    end

    it 'claims no stratum, because the standard is unstratified by design' do
      expect(percentile.source).not_to be_stratified
    end

    it 'reports a number and its source, never a classification' do
      expect(percentile.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end

  # An equation standard has no outermost published column, so there is
  # nothing to bracket against and every weight in range gets a number.
  context 'when the weight is far outside the centiles Table S1 prints' do
    it 'still computes a value rather than reporting an open bracket' do
      expect(call(400, weeks(30)).value!.bound).to eq(:computed)
    end

    it 'reports a percentile inside the unit range' do
      expect(percentile_of(400, weeks(30))).to be_between(0, 100)
    end
  end

  # Table 2 publishes two branches of the Z-score, and both are implemented.
  # Over 22-40 weeks lambda is never zero, so the L == 0 branch is unreachable
  # against the real coefficients — the same position the loader's pruning is
  # in, and pinned the same way: with a synthetic manifest rather than by
  # deleting a branch the standard states. A refit or an extended range could
  # reach it, and the specs should already say what it does when it is.
  #
  # The zeroes below are ours. Nothing here transcribes a clinical constant;
  # it replaces three of them with the degenerate case Table 2 names.
  context 'when a chart puts lambda at zero' do
    def with_lambda(coefficients)
      lms = manifest[:lms].merge(lambda: manifest[:lms][:lambda].merge(coefficients: coefficients))
      described_class.new(manifest: manifest.merge(lms: lms))
    end

    def flat = with_lambda(intercept: 0.0, ga_inv_sq: 0.0, ga_cubed: 0.0)

    # Lambda a whisker off zero, so the general branch answers instead.
    def nearly_flat = with_lambda(intercept: 1e-6, ga_inv_sq: 0.0, ga_cubed: 0.0)

    def value_from(adapter) = adapter.call(estimate: efw(1500), ga: weeks(30)).value!.value

    it 'takes the branch the standard publishes for that case' do
      expect(flat.call(estimate: efw(1500), ga: weeks(30))).to be_success
    end

    it 'reports a percentile rather than dividing by a zero lambda' do
      expect(value_from(flat)).to be_between(0, 100)
    end

    # The general branch converges on the L == 0 one as lambda approaches
    # zero. Agreement across the two is what says the published special case
    # was implemented as published rather than guessed at.
    it 'agrees with the general branch as lambda approaches zero' do
      expect(value_from(flat)).to be_within(1e-4).of(value_from(nearly_flat))
    end
  end

  describe 'the gestational age window it was fitted over' do
    it 'reads the window from the manifest rather than assuming one' do
      expect(manifest[:valid_ga_weeks]).to eq([22, 40])
    end

    it 'accepts the first week of the window' do
      expect(call(500, weeks(22))).to be_success
    end

    # No value asserted here: term_tail_divergence records that computed
    # centiles part company with published Table S1 above ~38 weeks.
    it 'accepts the last week of the window' do
      expect(call(3400, weeks(40))).to be_success
    end

    it 'refuses a gestation below the window rather than extrapolating' do
      expect(call(400, weeks(21, 6)).failure).to eq(
        [:out_of_range,
         { standard: :intergrowth21, ga_weeks: 21 + (6 / 7.0),
           valid_range: manifest[:valid_ga_weeks] }]
      )
    end

    # Exact weeks, so one day past 40+0 is already outside. The table
    # standards read completed weeks and behave differently here on purpose.
    it 'refuses a gestation one day past the window' do
      expect(call(3400, weeks(40, 1))).to be_failure
    end
  end

  # This standard's pairing is self-referential: it built its centiles from
  # its own AC+HC formula, so a mismatch here means something different in
  # kind from NICHD's and WHO's, which name a foreign Hadlock model.
  describe 'the formula its chart was built on' do
    it 'names its own formula as the pairing' do
      expect(manifest[:paired_formula].to_sym).to eq(:intergrowth)
    end

    it 'refuses a weight produced by a Hadlock formula' do
      expect(call(1500, weeks(30), formula: :hadlock_hc_ac_fl).failure).to eq(
        [:formula_chart_mismatch,
         { chart: :intergrowth21, expected: :intergrowth, given: :hadlock_hc_ac_fl }]
      )
    end

    it 'refuses the four-parameter Hadlock weight the 1991 chart pairs with' do
      expect(call(1500, weeks(30), formula: :hadlock_bpd_hc_ac_fl)).to be_failure
    end
  end
end
