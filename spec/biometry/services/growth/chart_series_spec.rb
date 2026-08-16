# frozen_string_literal: true

require 'json'

# The data a web app needs to draw a growth chart: the centile curves across
# gestation, and optionally the one point a reader came to look at.
#
# Nothing here is a new reading of a standard. Every gram on every curve is
# what that standard's own Centiles service answers, and the plotted point is
# what its forward adapter answers; this service composes the chart registry
# and arranges those answers into a shape a caller can serialise. The specs
# below therefore compare against those services rather than restating a single
# clinical number — a curve that disagreed with the service it came from would
# be a second transcription of the paper, which is the defect this library
# exists to avoid.
#
# Three layers live in this one file, in order:
#
#   1. the value objects, built by hand from plain members;
#   2. the composition — registry, reverse services, forward adapters, and the
#      failures each of them refuses with;
#   3. the payload a caller receives, `to_h` and all, including the property
#      that it never carries a classification.
#
# PINNED DECISIONS
#
# - `step` is meaningful only where the curve is evaluated rather than read. A
#   table standard given one is refused with
#   [:invalid_input, { step:, standard:, valid_for: :closed_form }] — the chart
#   is named because a caller iterating standards needs to know which one
#   rejected the option, and `valid_for` says what would have accepted it.
# - A non-positive step is refused with [:invalid_input, { step:,
#   valid_range: [0, nil] }], reusing the key :out_of_range and the closed-form
#   Centiles services already use for a domain, with nil for "unbounded above".
#   Both ends' exclusivity is pinned by examples either side rather than spelt
#   into the payload, the same way Hadlock1991::Centiles pins (0, 100).
# - A point the forward adapter refuses fails the whole call. A ChartSeries
#   with `point: nil` is how "no point was asked for" is reported; returning it
#   for "a point was asked for and could not be read" would render as a chart
#   nobody could tell from an unannotated one.
RSpec.describe Biometry::Services::Growth::ChartSeries do
  subject(:service) { described_class.new(manifests: manifests, tables: tables) }

  let(:growth_manifests) { %i[hadlock_1991 intergrowth21 nichd who] }
  let(:manifests) { growth_manifests.to_h { |name| [name, manifest(name)] } }
  let(:tables) { { nichd: table('nichd'), who: table('who') } }

  # ------------------------------------------------------------- the fixtures

  def manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  # The registry this service composes. Which charts exist is its answer, not
  # a list retyped here.
  def registry
    Biometry::Services::Growth::Charts.new(manifests: manifests, tables: tables).call
  end

  def hadlock_id(variant) = manifests[:hadlock_1991][:variants][variant][:id].to_sym

  def strata = manifests[:nichd][:stratification][:values].map(&:to_sym)

  def window(name) = manifests[name][:valid_ga_weeks]

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  # A grid GA is decimal weeks, which is what the closed-form services take.
  def at_week(decimal_weeks) = Biometry::GestationalAge.new(days: decimal_weeks * 7)

  def efw(grams, formula)
    Biometry::Estimate.new(
      value: grams, unit: 'g', formula: formula, inputs: %i[hc ac fl],
      uncertainty: Biometry::Uncertainty.pooled(8.0),
      source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x', formula: formula)
    )
  end

  def paired(name) = manifests[name][:paired_formula].to_sym

  def call(**options) = service.call(**options)

  # -------------------------------------------- the services it must agree with

  def who_centiles
    Biometry::Services::Growth::Who::Centiles.new(manifest: manifests[:who], table: tables[:who])
  end

  def nichd_centiles
    Biometry::Services::Growth::Nichd::Centiles
      .new(manifest: manifests[:nichd], table: tables[:nichd])
  end

  def hadlock_centiles(variant)
    Biometry::Services::Growth::Hadlock1991::Centiles
      .new(manifest: manifests[:hadlock_1991], variant: variant)
  end

  def intergrowth_centiles
    Biometry::Services::Growth::Intergrowth::Centiles.new(manifest: manifests[:intergrowth21])
  end

  def who_adapter
    Biometry::Services::Growth::Who.new(manifest: manifests[:who], table: tables[:who])
  end

  def nichd_adapter
    Biometry::Services::Growth::Nichd.new(manifest: manifests[:nichd], table: tables[:nichd])
  end

  def hadlock_adapter(variant)
    Biometry::Services::Growth::Hadlock1991.new(manifest: manifests[:hadlock_1991],
                                                variant: variant)
  end

  # ----------------------------------------------------------- reading a chart

  def chart_for(standard, **options) = call(standard: standard, **options).value!

  def curve(standard, centile, **options)
    chart_for(standard, centiles: [centile], **options).series.first
  end

  def grid(standard, **options) = curve(standard, 50, **options).points.map { |p| p[:ga_weeks] }

  def curve_grams(standard, centile, **options)
    curve(standard, centile, **options).points.map { |p| p[:grams] }
  end

  def offered_centiles(standard, **options)
    chart_for(standard, **options).series.map(&:centile)
  end

  # --------------------------------------------------------------- walkers

  # Word-boundary matching, and deliberately without the bare word "normal":
  # the manifests and this library's own vocabulary use it for a distribution
  # ("assumed normal distribution of random effects", "additive_normal_pct_of_
  # median"), so denying it would fail on statistics rather than on a verdict.
  # "abnormal" is denied and is a distinct word under \b.
  def denylist = /\b(sga|lga|iugr|fgr|macrosomia|abnormal)\b/i

  def deep_strings(node)
    case node
    when Hash then node.flat_map { |key, value| [key.to_s] + deep_strings(value) }
    when Array then node.flat_map { |value| deep_strings(value) }
    when String, Symbol then [node.to_s]
    else []
    end
  end

  def leaf_classes(node)
    case node
    when Hash then node.flat_map { |key, value| [key.class] + leaf_classes(value) }
    when Array then node.flat_map { |value| leaf_classes(value) }
    else [node.class]
    end
  end

  def serialisable = [Symbol, String, Integer, Float, NilClass, TrueClass, FalseClass]

  # ==========================================================================
  # 1. The value objects
  # ==========================================================================

  describe 'the value objects it is made of' do
    let(:points) { [{ ga_weeks: 22.0, grams: 500.0 }, { ga_weeks: 23.0, grams: 600.0 }] }
    let(:centile_series) { Biometry::CentileSeries.new(centile: 10, points: points) }
    let(:chart_series) do
      Biometry::ChartSeries.new(chart: { standard: :who }, source: { citation: 'x' },
                                series: [centile_series], point: nil, known_issues: [])
    end

    it 'names the centile a curve was drawn at' do
      expect(centile_series.centile).to eq(10)
    end

    it 'carries the curve as points of week and gram' do
      expect(centile_series.points).to eq(points)
    end

    it 'is a value, equal to another built from the same members' do
      expect(centile_series).to eq(Biometry::CentileSeries.new(centile: 10, points: points))
    end

    it 'converts a curve to a plain hash of its members' do
      expect(centile_series.to_h).to eq(centile: 10, points: points)
    end

    it 'carries a chart as exactly these five members' do
      expect(chart_series.to_h.keys).to eq(%i[chart source series point known_issues])
    end

    # Data#to_h is shallow, so a chart whose curves are still Data objects is
    # not the plain nested structure a caller serialises. Whatever produces
    # that is this model's business; that it does is the contract.
    it 'converts a chart the whole way down, curves included' do
      expect(chart_series.to_h[:series]).to eq([{ centile: 10, points: points }])
    end
  end

  # ==========================================================================
  # 2. The composition
  # ==========================================================================

  describe 'the charts it will draw' do
    it 'draws every chart the registry serves' do
      results = registry.keys.map { |id| call(standard: id) }
      expect(results).to all(be_success)
    end

    it 'refuses a standard the registry does not serve' do
      expect(call(standard: :hadlock_1985).failure.first).to eq(:unsupported_standard)
    end

    it 'names what was asked for and every chart id it could have been' do
      expect(call(standard: :hadlock_1985).failure.last)
        .to match(requested: :hadlock_1985, available: match_array(registry.keys))
    end

    # Without a chart there is no basis, so there is nothing to say about a
    # step being wrong for one.
    it 'settles the standard before the options it would have been read with' do
      expect(call(standard: :hadlock_1985, step: 2).failure.first).to eq(:unsupported_standard)
    end
  end

  describe 'the curves it reads off a published table' do
    it 'draws one point per published week, across the whole window' do
      expect(grid(:who)).to eq((window(:who).first..window(:who).last).to_a)
    end

    it 'draws NICHD over its own window, which starts later' do
      expect(grid(:nichd, stratum: :white))
        .to eq((window(:nichd).first..window(:nichd).last).to_a)
    end

    it 'takes every gram from the standard\'s own centile service' do
      expected = grid(:who).map { |wk| who_centiles.call(ga: weeks(wk), centile: 10).value!.grams }
      expect(curve_grams(:who, 10)).to eq(expected)
    end

    it 'takes NICHD\'s grams from NICHD\'s own centile service, per stratum' do
      expected = grid(:nichd, stratum: :black).map do |wk|
        nichd_centiles.call(ga: weeks(wk), centile: 90, stratum: :black).value!.grams
      end
      expect(curve_grams(:nichd, 90, stratum: :black)).to eq(expected)
    end

    it 'reads the sexed table when a sex is named' do
      expected = grid(:who, sex: :male)
                 .map { |wk| who_centiles.call(ga: weeks(wk), centile: 50, sex: :male).value!.grams }
      expect(curve_grams(:who, 50, sex: :male)).to eq(expected)
    end

    it 'puts no point between two published weeks' do
      expect(grid(:who)).to all(be_an(Integer))
    end
  end

  describe 'the curves it evaluates from a closed form' do
    it 'steps a whole week at a time when no step is named' do
      expect(grid(:intergrowth21))
        .to eq((window(:intergrowth21).first..window(:intergrowth21).last).map(&:to_f))
    end

    it 'takes every gram from the standard\'s own centile service' do
      expected = grid(:intergrowth21)
                 .map { |wk| intergrowth_centiles.call(ga: at_week(wk), centile: 3).value!.grams }
      expect(curve_grams(:intergrowth21, 3)).to match(expected.map { |g| be_within(1e-9).of(g) })
    end

    it 'takes Hadlock\'s grams from the variant\'s own centile service' do
      expected = grid(hadlock_id(:table)).map do |wk|
        hadlock_centiles(:table).call(ga: at_week(wk), centile: 90).value!.grams
      end
      expect(curve_grams(hadlock_id(:table), 90))
        .to match(expected.map { |g| be_within(1e-9).of(g) })
    end

    it 'steps at the interval it was given, in exact decimal weeks' do
      expect(grid(:intergrowth21, step: 0.5).take(3)).to eq([22.0, 22.5, 23.0])
    end

    # The last week of the window is the one a reader looks hardest at; a grid
    # that stopped at 36 because 43 is past the end would draw a curve that
    # ends before the standard does.
    it 'includes the end of the window even when the step overshoots it' do
      expect(grid(:intergrowth21, step: 7)).to eq([22.0, 29.0, 36.0, 40.0])
    end

    it 'does not repeat the end of the window when the step lands on it' do
      expect(grid(:intergrowth21, step: 6)).to eq([22.0, 28.0, 34.0, 40.0])
    end

    it 'steps Hadlock from its own window, which starts much earlier' do
      expect(grid(hadlock_id(:equation), step: 10)).to eq([10.0, 20.0, 30.0, 40.0])
    end
  end

  # One paper, two dispersion figures, two charts. A caller drawing both must
  # get two different pictures or the dispute has been quietly resolved.
  describe 'the two Hadlock charts, which the paper contradicts itself about' do
    it 'draws both variants the registry names' do
      expect(registry.keys).to include(hadlock_id(:equation), hadlock_id(:table))
    end

    it 'draws the 3rd centile higher on the equation than on the table' do
      expect(curve_grams(hadlock_id(:equation), 3).first)
        .to be > curve_grams(hadlock_id(:table), 3).first
    end

    it 'names which variant a chart was drawn from' do
      expect(chart_for(hadlock_id(:table)).chart[:variant]).to eq(:table)
    end

    it 'claims no variant for a standard that publishes only one reading' do
      expect(chart_for(:intergrowth21).chart[:variant]).to be_nil
    end
  end

  describe 'the centiles it draws when the caller names none' do
    it 'draws WHO\'s combined columns' do
      expect(offered_centiles(:who)).to eq(manifests[:who][:centiles][:combined])
    end

    it 'draws the sexed columns instead when a sex is named, those tables being narrower' do
      expect(offered_centiles(:who, sex: :female))
        .to eq(manifests[:who][:centiles][:sex_specific])
    end

    it 'draws NICHD\'s tabulated columns' do
      expect(offered_centiles(:nichd, stratum: :white))
        .to eq(manifests[:nichd][:centiles][:tabulated])
    end

    it 'draws the five centiles Hadlock\'s Table 1 prints' do
      expect(offered_centiles(hadlock_id(:equation)))
        .to eq(manifests[:hadlock_1991][:centiles][:published])
    end

    it 'draws the five INTERGROWTH prints in Table S1' do
      expect(offered_centiles(:intergrowth21))
        .to eq(manifests[:intergrowth21][:centiles][:published])
    end
  end

  describe 'the centiles it draws when the caller names some' do
    it 'draws one curve per centile asked for' do
      expect(offered_centiles(:who, centiles: [10, 50, 90])).to eq([10, 50, 90])
    end

    it 'draws them in the order they were asked for, not in the order it reads them' do
      expect(offered_centiles(:who, centiles: [90, 10, 50])).to eq([90, 10, 50])
    end

    it 'draws a centile no table publishes when the standard computes any' do
      expect(offered_centiles(:intergrowth21, centiles: [42.5])).to eq([42.5])
    end
  end

  describe 'the refusals it passes on from the services it reads' do
    it 'refuses a centile a table never published, on that table\'s own terms' do
      expect(call(standard: :who, centiles: [42]).failure)
        .to eq(who_centiles.call(ga: weeks(32), centile: 42).failure)
    end

    it 'refuses a sexed request for a column only the combined table carries' do
      expect(call(standard: :who, centiles: [2.5], sex: :female).failure)
        .to eq(who_centiles.call(ga: weeks(32), centile: 2.5, sex: :female).failure)
    end

    it 'refuses a centile NICHD never tabulated' do
      expect(call(standard: :nichd, centiles: [25], stratum: :asian).failure)
        .to eq(nichd_centiles.call(ga: weeks(32), centile: 25, stratum: :asian).failure)
    end

    it 'refuses a sex WHO does not publish' do
      expect(call(standard: :who, sex: :unknown).failure)
        .to eq(who_centiles.call(ga: weeks(32), centile: 50, sex: :unknown).failure)
    end

    it 'refuses a stratum NICHD does not publish' do
      expect(call(standard: :nichd, stratum: :european).failure)
        .to eq(nichd_centiles.call(ga: weeks(32), centile: 50, stratum: :european).failure)
    end

    it 'refuses the 0th on a closed-form chart, no finite weight sitting there' do
      expect(call(standard: :intergrowth21, centiles: [0]).failure)
        .to eq(intergrowth_centiles.call(ga: at_week(30), centile: 0).failure)
    end

    it 'refuses a centile past 100 on a Hadlock variant' do
      expect(call(standard: hadlock_id(:equation), centiles: [101]).failure)
        .to eq(hadlock_centiles(:equation).call(ga: at_week(30), centile: 101).failure)
    end

    it 'refuses the whole chart when one of several centiles is unavailable' do
      expect(call(standard: :who, centiles: [10, 42, 90])).to be_failure
    end
  end

  # A step is an instruction about where to evaluate a curve. A table standard
  # has no curve to evaluate, only rows to read, so a step there is a caller
  # who believes something false about the chart and is told so.
  describe 'the step, which only a computed curve has' do
    it 'refuses one on WHO, naming the chart and what a step is for' do
      expect(call(standard: :who, step: 0.5).failure)
        .to eq([:invalid_input, { step: 0.5, standard: :who, valid_for: :closed_form }])
    end

    it 'refuses one on NICHD on the same terms' do
      expect(call(standard: :nichd, stratum: :white, step: 2).failure)
        .to eq([:invalid_input, { step: 2, standard: :nichd, valid_for: :closed_form }])
    end

    it 'refuses a step of zero, which names no grid at all' do
      expect(call(standard: :intergrowth21, step: 0).failure)
        .to eq([:invalid_input, { step: 0, valid_range: [0, nil] }])
    end

    it 'refuses a negative step, echoing what it was asked for' do
      expect(call(standard: :intergrowth21, step: -1).failure)
        .to eq([:invalid_input, { step: -1, valid_range: [0, nil] }])
    end

    it 'accepts a step arbitrarily close to zero, the end being open not rounded' do
      expect(call(standard: :intergrowth21, step: 0.25)).to be_success
    end

    it 'accepts a step wider than the window, which leaves the two ends' do
      expect(grid(:intergrowth21, step: 100)).to eq([22.0, 40.0])
    end
  end

  # ==========================================================================
  # 3. The payload
  # ==========================================================================

  describe 'the chart block, which says what was drawn' do
    it 'describes the WHO chart as its manifest describes itself' do
      expect(chart_for(:who).chart).to eq(
        standard: :who, variant: nil, stratum: :combined,
        type: manifests[:who][:source][:type].to_sym,
        ga_units: manifests[:who][:ga_units].to_sym,
        valid_ga_weeks: window(:who), basis: :published_table
      )
    end

    it 'describes a Hadlock variant as its own chart, not as the paper' do
      expect(chart_for(hadlock_id(:equation)).chart).to eq(
        standard: hadlock_id(:equation), variant: :equation, stratum: nil,
        type: manifests[:hadlock_1991][:source][:type].to_sym,
        ga_units: manifests[:hadlock_1991][:ga_units].to_sym,
        valid_ga_weeks: window(:hadlock_1991), basis: :closed_form
      )
    end

    it 'describes the NICHD chart, whose manifest states no GA units' do
      expect(chart_for(:nichd, stratum: :hispanic).chart).to eq(
        standard: :nichd, variant: nil, stratum: :hispanic,
        type: manifests[:nichd][:source][:type].to_sym, ga_units: nil,
        valid_ga_weeks: window(:nichd), basis: :published_table
      )
    end

    it 'leaves the units nil because the NICHD manifest states none, not by choice' do
      expect(manifests[:nichd][:ga_units]).to be_nil
    end

    it 'names the sexed chart it read when a sex was given' do
      expect(chart_for(:who, sex: :male).chart[:stratum]).to eq(:male)
    end

    it 'names INTERGROWTH as a prescriptive standard, WHO being a reference' do
      expect([chart_for(:intergrowth21).chart[:type], chart_for(:who).chart[:type]])
        .to eq(%i[prescriptive reference])
    end
  end

  describe 'the source block, which says where the numbers came from' do
    it 'carries what WHO\'s manifest publishes about itself' do
      expect(chart_for(:who).source).to eq(
        citation: manifests[:who][:source][:citation], doi: manifests[:who][:source][:doi],
        pmid: nil, type: manifests[:who][:source][:type].to_sym
      )
    end

    it 'carries Hadlock\'s PMID, that paper publishing no DOI' do
      expect(chart_for(hadlock_id(:table)).source).to eq(
        citation: manifests[:hadlock_1991][:source][:citation], doi: nil,
        pmid: manifests[:hadlock_1991][:source][:pmid],
        type: manifests[:hadlock_1991][:source][:type].to_sym
      )
    end

    it 'gives both Hadlock variants the one paper behind them' do
      expect(chart_for(hadlock_id(:equation)).source).to eq(chart_for(hadlock_id(:table)).source)
    end
  end

  describe 'the known issues it carries' do
    it 'carries the manifest\'s list verbatim, defects being data' do
      expect(chart_for(hadlock_id(:equation)).known_issues)
        .to eq(manifests[:hadlock_1991][:known_issues])
    end

    it 'carries the contested dispersion onto both variants of that chart' do
      expect(chart_for(hadlock_id(:table)).known_issues.map { |issue| issue[:id] })
        .to include('dispersion_contested')
    end

    it 'carries an empty list where the manifest records none' do
      expect(chart_for(:who).known_issues).to eq([])
    end
  end

  describe 'the point it plots' do
    let(:ga) { weeks(32, 4) }
    let(:estimate) { efw(1600, paired(:who)) }
    let(:point) { chart_for(:who, point: { estimate: estimate, ga: ga }).point }

    it 'plots nothing when nothing was asked to be plotted' do
      expect(chart_for(:who).point).to be_nil
    end

    it 'reports the weight, the week and the reading the chart gives it' do
      reading = who_adapter.call(estimate: estimate, ga: ga).value!
      expect(point).to eq(
        ga_weeks: reading.ga_weeks, efw_g: estimate.value,
        percentile: { value: reading.value, bound: reading.bound,
                      interpolation: reading.interpolation }
      )
    end

    it 'plots at the week the chart itself read, which for a table is the completed one' do
      expect(point[:ga_weeks]).to eq(ga.completed_weeks)
    end

    it 'plots a closed-form chart at exact decimal weeks instead' do
      plotted = chart_for(hadlock_id(:equation),
                          point: { estimate: efw(1600, paired(:hadlock_1991)), ga: ga }).point
      expect(plotted[:ga_weeks]).to eq(ga.exact_weeks)
    end

    it 'reads the sexed chart when a sex was named, as the curves were drawn' do
      sexed = chart_for(:who, sex: :male, point: { estimate: estimate, ga: ga }).point
      expect(sexed[:percentile][:value])
        .to eq(who_adapter.call(estimate: estimate, ga: ga, sex: :male).value!.value)
    end

    it 'reads a different centile off the sexed chart than off the combined one' do
      sexed = chart_for(:who, sex: :male, point: { estimate: estimate, ga: ga }).point
      expect(sexed[:percentile][:value]).not_to eq(point[:percentile][:value])
    end

    it 'agrees with the Hadlock variant\'s own adapter, dispersion and all' do
      weight = efw(1600, paired(:hadlock_1991))
      plotted = chart_for(hadlock_id(:table), point: { estimate: weight, ga: ga }).point
      expect(plotted[:percentile][:value])
        .to eq(hadlock_adapter(:table).call(estimate: weight, ga: ga).value!.value)
    end
  end

  # A chart drawn without the point that was asked for is indistinguishable
  # from one nobody asked a point of, and a reader cannot tell that the weight
  # they came to see was dropped. So the refusal is the whole answer.
  context 'when the point cannot be read off the chart asked for' do
    let(:ga) { weeks(32) }
    let(:mismatched) { efw(1600, :intergrowth) }

    it 'fails rather than drawing the curves without it' do
      expect(call(standard: :who, point: { estimate: mismatched, ga: ga })).to be_failure
    end

    it 'fails on the adapter\'s own terms, naming the pairing the chart expects' do
      expect(call(standard: :who, point: { estimate: mismatched, ga: ga }).failure)
        .to eq(who_adapter.call(estimate: mismatched, ga: ga).failure)
    end

    # INTERGROWTH's pairing is self-referential, so the weight that mismatches
    # WHO is the one it expects; a Hadlock weight is what it cannot read.
    it 'fails the same way on a closed-form chart' do
      foreign = { estimate: efw(1600, paired(:who)), ga: ga }
      expect(call(standard: :intergrowth21, point: foreign).failure.first)
        .to eq(:formula_chart_mismatch)
    end

    it 'fails when the point lies outside the window the curves cover' do
      early = { estimate: efw(300, paired(:who)), ga: weeks(12) }
      expect(call(standard: :who, point: early).failure)
        .to eq(who_adapter.call(estimate: early[:estimate], ga: early[:ga]).failure)
    end

    it 'draws the same chart perfectly well when no point is asked of it' do
      expect(call(standard: :who)).to be_success
    end
  end

  # NICHD's four charts and no combined one, the same convention the adapters
  # keep: an unsupplied race/ethnicity is answered with the spread, never with
  # a default nobody asked for.
  context 'when NICHD is asked for without a stratum' do
    let(:ga) { weeks(32) }
    let(:estimate) { efw(1600, paired(:nichd)) }
    let(:charts) { call(standard: :nichd, point: { estimate: estimate, ga: ga }).value! }

    it 'returns one chart per published stratum' do
      expect(charts.length).to eq(strata.length)
    end

    it 'returns them in the order the manifest publishes' do
      expect(charts.map { |chart| chart.chart[:stratum] }).to eq(strata)
    end

    it 'draws each stratum\'s own curve, none of them the white one twice' do
      medians = charts.map { |chart| chart.series.first.points.first[:grams] }
      expect(medians.uniq.length).to eq(strata.length)
    end

    it 'plots the point on each stratum\'s own chart' do
      expected = nichd_adapter.call(estimate: estimate, ga: ga).value!.map(&:value)
      expect(charts.map { |chart| chart.point[:percentile][:value] }).to eq(expected)
    end

    it 'returns one chart, not four, when a stratum is named' do
      expect(chart_for(:nichd, stratum: :white)).to be_a(Biometry::ChartSeries)
    end

    it 'returns the same chart as the corresponding one of the four' do
      expect(chart_for(:nichd, stratum: :asian).series)
        .to eq(call(standard: :nichd).value!.last.series)
    end
  end

  describe 'the hash a caller serialises' do
    let(:payload) do
      chart_for(:who, centiles: [10, 50],
                      point: { estimate: efw(1600, paired(:who)), ga: weeks(32) }).to_h
    end

    it 'carries the five parts of the chart' do
      expect(payload.keys).to eq(%i[chart source series point known_issues])
    end

    it 'carries the curves as plain hashes rather than as value objects' do
      expect(payload[:series].map(&:class)).to eq([Hash, Hash])
    end

    it 'carries each curve as its centile and its points' do
      expect(payload[:series].first.keys).to eq(%i[centile points])
    end

    it 'carries each point as a week and a gram' do
      expect(payload[:series].first[:points].first.keys).to eq(%i[ga_weeks grams])
    end

    it 'is built entirely of things JSON has a representation for' do
      expect(leaf_classes(payload).uniq - serialisable).to eq([])
    end

    it 'survives a round trip through JSON' do
      expect { JSON.generate(payload) }.not_to raise_error
    end

    it 'says the same of a closed-form chart' do
      other = chart_for(hadlock_id(:equation),
                        point: { estimate: efw(1600, paired(:hadlock_1991)),
                                 ga: weeks(32) }).to_h
      expect(leaf_classes(other).uniq - serialisable).to eq([])
    end
  end

  # The library reports a number and where it came from. It never reports a
  # verdict about the number, in any field, at any depth. Asserted over the
  # flattened payload rather than over a chosen field, because the day a
  # classification appears it will not be in the field anyone thought to check.
  describe 'the classification it never emits' do
    let(:table_payload) do
      chart_for(:who, point: { estimate: efw(1600, paired(:who)), ga: weeks(32) }).to_h
    end
    let(:equation_payload) do
      chart_for(hadlock_id(:equation),
                point: { estimate: efw(1600, paired(:hadlock_1991)), ga: weeks(32) }).to_h
    end

    it 'says nothing of the kind anywhere in a table chart, keys included' do
      expect(deep_strings(table_payload).grep(denylist)).to eq([])
    end

    it 'says nothing of the kind in a closed-form chart with its known issues' do
      expect(deep_strings(equation_payload).grep(denylist)).to eq([])
    end

    # Two guards on the assertion above, which would otherwise pass on an empty
    # walk or a regex that matches nothing.
    it 'walks a payload deep enough to have found one' do
      expect(deep_strings(table_payload).length).to be > 100
    end

    it 'would have caught a verdict had one been there' do
      expect(deep_strings(point: { label: 'SGA' }).grep(denylist)).to eq(['SGA'])
    end

    # The denied words are verdicts. "normal" is a distribution, and the
    # manifests say it about their own statistics, so it is not denied.
    it 'does not deny the statistics the standards describe themselves with' do
      expect(deep_strings(note: 'assumed normal distribution').grep(denylist)).to eq([])
    end
  end
end
