# frozen_string_literal: true

# Integration layer, and the other direction through INTERGROWTH-21st: given a
# week and a centile, what weight does the standard put there?
#
# An equation standard, so this is not a lookup and there is no table to read.
# Table 2's centile row is the inverse of its Z-score row, and the manifest
# prints both; any centile is computable at any exact decimal week in 22-40,
# which is what makes this direction possible at all for a standard that
# published its centile table only as supplementary material.
#
# Two anchors, and they answer to different authorities. The manifest's
# fixtures are the paper's own numbers and pin the weights; the forward adapter
# pins the round trip, so neither direction's arithmetic is restated here.
# Nothing beyond 33 weeks asserts a published value: the term_tail_divergence
# known_issue records that computed centiles part company with Table S1 above
# about 38 weeks, and a fixture there would pin a disagreement rather than a
# standard.
RSpec.describe Biometry::Services::Growth::Intergrowth::Centiles do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'intergrowth21.yml').first
  end
  let(:service) { described_class.new(manifest: manifest) }

  # Grams out and grams back in are the same LMS triple evaluated in opposite
  # directions, so the round trip is exact to within floating point rather than
  # to within the paper's gram tolerance.
  def round_trip_tolerance = 1e-6

  def forward = Biometry::Services::Growth::Intergrowth.new(manifest: manifest)

  def fixture(name) = manifest[:fixtures].find { |f| f[:name] == name }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def call(centile, ga) = service.call(ga: ga, centile: centile)

  def grams(centile, ga) = call(centile, ga).value!.grams

  # The chart's own pairing — self-referential, INTERGROWTH having built its
  # centiles from its own AC+HC formula — so the weight goes back in through
  # the door it came out of.
  def efw(value)
    Biometry::Estimate.new(
      value: value, unit: 'g', formula: manifest[:paired_formula].to_sym,
      inputs: %i[ac hc], uncertainty: nil,
      source: Biometry::Provenance.formula(standard: :intergrowth21, citation: 'x',
                                           formula: manifest[:paired_formula].to_sym)
    )
  end

  def read_back(value, ga) = forward.call(estimate: efw(value), ga: ga).value!.value

  # c03_g => 3, c50_g => 50, so the centile each fixture key belongs to comes
  # from the key rather than being retyped beside it.
  def centile_of(key) = Integer(key.to_s[/\d+/], 10)

  # ------------------------------------------------------------- the anchors

  describe 'the weights it reproduces' do
    # "Table S1 centiles at 33+0". 33 weeks is the week the manifest records as
    # matching the published supplement to the gram.
    it 'reproduces every Table S1 centile it publishes at 33 weeks' do
      anchor = fixture('Table S1 centiles at 33+0')
      computed = anchor[:expect].to_h { |key, _| [key, grams(centile_of(key), weeks(33))] }
      expect(computed).to match(anchor[:expect].transform_values { |g|
        be_within(anchor[:tolerance_g]).of(g)
      })
    end

    # "3rd centile at 30+0" is the paper working this exact direction: alpha in,
    # 1106 g out. The centile comes from the fixture's own alpha.
    it "reproduces the paper's own worked centile at 30 weeks" do
      anchor = fixture('3rd centile at 30+0')
      expect(grams(anchor[:inputs][:alpha] * 100, weeks(anchor[:inputs][:ga_weeks])))
        .to be_within(anchor[:tolerance_g]).of(anchor[:expect][:efw_g])
    end

    it 'publishes the five centiles Table S1 prints, and answers each of them' do
      expect(manifest[:centiles][:published].map { |c| call(c, weeks(33)) }).to all(be_success)
    end
  end

  # ------------------------------------------------------- the two directions

  # Several weeks and several centiles, two of them off the published five and
  # two on fractional gestations, because the LMS parameters are continuous in
  # exact decimal weeks and the round trip should be too.
  def round_trip_points
    [[22, 0, 3], [26, 5, 10], [30, 3, 50], [33, 0, 42.5], [36, 4, 90], [40, 0, 97]]
  end

  describe 'the weight it returns, read back through the chart' do
    it 'is read back as the centile it was asked for' do
      computed = round_trip_points.to_h do |(wk, day, centile)|
        ga = weeks(wk, day)
        [[wk, day, centile], read_back(grams(centile, ga), ga)]
      end
      expect(computed)
        .to match(round_trip_points.to_h { |p| [p, be_within(round_trip_tolerance).of(p.last)] })
    end

    it 'rises with the centile asked for at a fixed week' do
      computed = manifest[:centiles][:published].map { |c| grams(c, weeks(33)) }
      expect(computed).to eq(computed.sort)
    end

    it 'rises with gestation at a fixed centile' do
      computed = [22, 28, 33, 40].map { |wk| grams(10, weeks(wk)) }
      expect(computed).to eq(computed.sort)
    end

    # Exact decimal weeks, the convention this standard states: three days into
    # a week is a different chart position from the start of it, and the
    # published table's per-completed-week printing does not change that.
    it 'moves between completed weeks rather than reading either of them' do
      expect(grams(50, weeks(30, 3))).to be_between(grams(50, weeks(30)), grams(50, weeks(31)))
    end
  end

  # --------------------------------------------------------- the L == 0 case

  # Table 2 publishes two branches of the centile equation, and both are
  # implemented. Over 22-40 weeks lambda is never zero, so the L == 0 branch is
  # unreachable against the real coefficients, and it is pinned the way the
  # forward adapter pins its mirror image: with a synthetic manifest, rather
  # than by deleting a branch the standard states. A refit or an extended range
  # could reach it, and the specs should already say what it does when it is.
  #
  # The zeroes below are ours. Nothing here transcribes a clinical constant; it
  # replaces three of them with the degenerate case Table 2 names.
  context 'when a chart puts lambda at zero' do
    def with_lambda(coefficients)
      lms = manifest[:lms].merge(lambda: manifest[:lms][:lambda].merge(coefficients: coefficients))
      described_class.new(manifest: manifest.merge(lms: lms))
    end

    def flat = with_lambda(intercept: 0.0, ga_inv_sq: 0.0, ga_cubed: 0.0)

    # Lambda a whisker off zero, so the general branch answers instead.
    def nearly_flat = with_lambda(intercept: 1e-6, ga_inv_sq: 0.0, ga_cubed: 0.0)

    def grams_from(chart) = chart.call(ga: weeks(30), centile: 3).value!.grams

    it 'takes the branch the standard publishes for that case' do
      expect(flat.call(ga: weeks(30), centile: 3)).to be_success
    end

    # A weight, not an infinity or a NaN: the exp form has no 1/lambda in it,
    # which is the whole reason the standard states it separately.
    it 'returns a finite weight rather than dividing by a zero lambda' do
      expect(grams_from(flat)).to be_finite
    end

    it 'returns a weight above zero grams' do
      expect(grams_from(flat)).to be_positive
    end

    # The general branch converges on the L == 0 one as lambda approaches zero.
    # Agreement across the two is what says the published special case was
    # implemented as published rather than guessed at.
    it 'agrees with the general branch as lambda approaches zero' do
      expect(grams_from(flat)).to be_within(1e-6 * grams_from(flat)).of(grams_from(nearly_flat))
    end
  end

  # ------------------------------------------------------------- the domain

  # `computable: any` is the manifest's claim about the LMS equations, and this
  # direction is where it is cashed: no centile is privileged by having been
  # printed in Table S1. The open ends are refused — no finite weight sits at
  # the 0th or the 100th of the distribution — on the same terms and in the
  # same payload shape as Hadlock 1991's centile direction, the two equation
  # standards not being free to spell one condition two ways.
  #
  # PINNED: [:invalid_input, { centile: <as asked>, valid_range: [0, 100] }],
  # both ends exclusive, exclusivity pinned by the examples either side rather
  # than spelled into the payload.
  describe 'the centiles it will compute' do
    it 'computes a centile Table S1 never printed' do
      expect(call(42.5, weeks(33))).to be_success
    end

    it 'computes arbitrarily close to either end' do
      expect([call(0.01, weeks(33)), call(99.99, weeks(33))]).to all(be_success)
    end

    it 'records `computable: any`, which is what the two above are cashing' do
      expect(manifest[:centiles][:computable]).to eq('any')
    end

    it 'refuses the 0th, no finite weight sitting there' do
      expect(call(0, weeks(33)).failure).to eq(
        [:invalid_input, { centile: 0, valid_range: [0, 100] }]
      )
    end

    it 'refuses the 100th for the same reason' do
      expect(call(100, weeks(33)).failure).to eq(
        [:invalid_input, { centile: 100, valid_range: [0, 100] }]
      )
    end

    it 'refuses a negative centile, echoing what it was asked for' do
      expect(call(-1, weeks(33)).failure).to eq(
        [:invalid_input, { centile: -1, valid_range: [0, 100] }]
      )
    end

    it 'refuses a centile past 100' do
      expect(call(101, weeks(33)).failure).to eq(
        [:invalid_input, { centile: 101, valid_range: [0, 100] }]
      )
    end

    # A Failure rather than the ArgumentError Normal#inverse_cdf raises: the
    # services guard their inputs so a caller branches on a value and exits 1,
    # rather than taking the whole run to exit 70 over a typed centile.
    it 'refuses rather than raising out of the quantile function' do
      expect { call(100, weeks(33)) }.not_to raise_error
    end
  end

  describe 'the gestational age window it was fitted over' do
    it 'accepts the first week of the window' do
      expect(call(50, weeks(22))).to be_success
    end

    # No weight asserted here: term_tail_divergence records that computed
    # centiles part company with published Table S1 above ~38 weeks.
    it 'accepts the last week of the window' do
      expect(call(50, weeks(40))).to be_success
    end

    it 'refuses a gestation below the window rather than extrapolating' do
      expect(call(50, weeks(21, 6)).failure).to eq(
        [:out_of_range,
         { standard: :intergrowth21, ga_weeks: weeks(21, 6).exact_weeks,
           valid_range: manifest[:valid_ga_weeks] }]
      )
    end

    # Exact weeks, so one day past 40+0 is already outside. The table standards
    # read completed weeks and behave differently here on purpose.
    it 'refuses a gestation one day past the window' do
      expect(call(50, weeks(40, 1)).failure).to eq(
        [:out_of_range,
         { standard: :intergrowth21, ga_weeks: weeks(40, 1).exact_weeks,
           valid_range: manifest[:valid_ga_weeks] }]
      )
    end

    # The window is answered before the centile: a gestation the standard never
    # fitted has no centiles at all, so refusing the centile there would name
    # the smaller of two problems.
    it 'names the window before the centile when both are wrong' do
      expect(call(0, weeks(41)).failure.first).to eq(:out_of_range)
    end
  end

  describe 'the report it returns' do
    subject(:weight) { call(10, weeks(30, 3)).value! }

    it 'is a ChartWeight' do
      expect(weight).to be_a(Biometry::ChartWeight)
    end

    it 'names the centile it was asked for' do
      expect(weight.centile).to eq(10)
    end

    it 'names the exact decimal week it evaluated at' do
      expect(weight.ga_weeks).to be_within(1e-9).of(30 + (3 / 7.0))
    end

    it 'names the standard' do
      expect(weight.source.standard).to eq(:intergrowth21)
    end

    it 'carries the citation the manifest publishes' do
      expect(weight.source.citation).to eq(manifest[:source][:citation])
    end

    it 'names the formula the chart was built on, which is its own' do
      expect(weight.source.formula).to eq(:intergrowth)
    end

    it 'names the standard as prescriptive, because a reference centile differs' do
      expect(weight.source.type).to eq(:prescriptive)
    end

    it 'claims no stratum, because the standard is unstratified by design' do
      expect(weight.source).not_to be_stratified
    end

    it 'reports a number and its source, never a classification' do
      expect(weight.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end
end
