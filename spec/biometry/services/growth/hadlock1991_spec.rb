# frozen_string_literal: true

# Integration layer. Hadlock 1991 is the second equation standard, and it
# differs from INTERGROWTH in every way that matters here: its dispersion is a
# constant percentage of the median rather than an LMS triple, its GA
# convention is decimal weeks to the nearest tenth, and its chart pairs with
# the four-parameter Hadlock model rather than with itself.
#
# One paper, two dispersion figures, no erratum: the abstract prints 12.7% and
# the published Table 1 implies 13.3%. Which is right is a contested clinical
# question rather than a transcription question — two independent 2025-26
# re-analyses favour the abstract — so the standard is served as two variants
# and both are reported. That disagreement is what this library exists to
# surface, and here it sits inside a single standard.
#
# What each variant is, what it is called and what SD it carries all come from
# the manifest's `variants` block. The examples below assert each variant
# against the values *its own* SD produces:
#
#   * the table variant reproduces the paper's Table 1 — its centiles are
#     exactly median x {0.750, 0.830, 1.170, 1.250} at every week;
#   * the equation variant does not, and reads the paper's own 3rd-centile
#     weight as roughly the 2.5th. That spread is the dispute, not a defect,
#     and it is asserted rather than tolerated away.
#
# Everything else — median equation, valid window, pairing, GA convention — is
# shared, so those examples run once against both variants.
RSpec.describe Biometry::Services::Growth::Hadlock1991 do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock_1991.yml').first
  end

  # Percentile points. Wide enough for the fixtures' stated gram tolerance,
  # narrow enough that the two variants can never be read as each other: they
  # sit about half a centile apart at the 3rd and a full centile apart at the
  # 90th.
  def centile_tolerance = 0.3

  def service(variant = nil) = described_class.new(manifest: manifest, variant: variant)

  def variant_of(name) = manifest[:variants][name]

  def sd_pct(name) = variant_of(name)[:dispersion][:sd_pct]

  def identity(name) = variant_of(name)[:id].to_sym

  # The centile fixtures are Table 1 values, so each one names the variant it
  # anchors. The median fixture names none: the median equation is the half of
  # the paper the two variants agree on.
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

  def call(grams, ga, variant: nil, formula: :hadlock_bpd_hc_ac_fl)
    service(variant).call(estimate: efw(grams, formula: formula), ga: ga)
  end

  def percentile_of(grams, ga, variant: nil) = call(grams, ga, variant: variant).value!.value

  # ------------------------------------------------------------ the variants

  describe 'the two dispersion figures it carries' do
    it 'publishes both, because which one is right is contested and unresolved' do
      expect(manifest[:variants].keys).to contain_exactly(:equation, :table)
    end

    it 'names the abstract\'s figure on the equation variant' do
      expect(sd_pct(:equation)).to eq(12.7)
    end

    it 'names the Table 1 figure on the table variant' do
      expect(sd_pct(:table)).to eq(13.3)
    end

    it 'gives each variant a standard identity of its own' do
      expect([identity(:equation), identity(:table)])
        .to eq(%i[hadlock_1991_equation hadlock_1991_table])
    end
  end

  # Which variant a caller gets when it does not say is a decision the paper's
  # readers made, so it is stated in data/ and read from there.
  describe 'the variant it reads when the caller names none' do
    it 'resolves to the variant the manifest states as its default' do
      expect(call(1953, weeks(32)).value!.source.standard)
        .to eq(identity(manifest[:default].to_sym))
    end

    it 'defaults to the equation, which two independent groups now argue for' do
      expect(manifest[:default].to_sym).to eq(:equation)
    end

    it 'reads the same centile as that variant asked for by name' do
      expect(percentile_of(1600, weeks(32)))
        .to eq(percentile_of(1600, weeks(32), variant: manifest[:default].to_sym))
    end
  end

  # A variant this standard does not publish is a bug in the caller, not a
  # condition a caller branches on, so it raises rather than returning a
  # Failure.
  describe 'a variant the manifest does not carry' do
    it 'raises rather than falling back to a figure nobody asked for' do
      expect { service(:the_discussion_section) }.to raise_error(KeyError)
    end
  end

  # -------------------------------------------------------- the table variant

  describe 'the centiles the table variant reproduces' do
    it 'reports every published centile at 32 weeks as its own centile' do
      anchor = fixture('centiles at 32 weeks')[:expect_g]
      computed = anchor.transform_values { |g| percentile_of(g, weeks(32), variant: :table) }
      expect(computed).to match(centile_matchers(anchor.keys))
    end

    it 'reports every published centile at 40 weeks as its own centile' do
      anchor = fixture('centiles at 40 weeks')[:expect_g]
      computed = anchor.transform_values { |g| percentile_of(g, weeks(40), variant: :table) }
      expect(computed).to match(centile_matchers(anchor.keys))
    end

    it 'anchors those fixtures to the table variant, Table 1 being their source' do
      named = manifest[:fixtures].select { |f| f[:variant] }.map { |f| f[:variant].to_sym }
      expect(named.uniq).to eq([:table])
    end

    it 'reads each ratio the published table exhibits as its own centile' do
      median = fixture('centiles at 32 weeks')[:expect_g][:p50]
      computed = variant_of(:table)[:published_ratios]
                 .transform_values { |ratio| percentile_of(median * ratio, weeks(32), variant: :table) }
      expect(computed).to match(centile_matchers(computed.keys))
    end
  end

  # ----------------------------------------------------- the equation variant

  # The dispute, stated as the numbers it produces. 12.7% cannot reproduce the
  # table the same paper printed: the weight Hadlock published as the 3rd
  # centile reads about half a centile lower, and the one he published as the
  # 97th about half a centile higher. Roberts et al. quantify the clinical
  # size of that gap; here it is simply reported, in both directions.
  describe 'the centiles the equation variant reads instead' do
    it 'reads the paper\'s own 3rd-centile weight at 32 weeks as the 2.5th' do
      expect(percentile_of(fixture('centiles at 32 weeks')[:expect_g][:p3],
                           weeks(32), variant: :equation))
        .to be_within(0.1).of(2.5)
    end

    it 'reads the paper\'s own 97th-centile weight at 32 weeks as the 97.5th' do
      expect(percentile_of(fixture('centiles at 32 weeks')[:expect_g][:p97],
                           weeks(32), variant: :equation))
        .to be_within(0.1).of(97.5)
    end

    it 'reads the paper\'s own 3rd-centile weight at 40 weeks as the 2.4th' do
      expect(percentile_of(fixture('centiles at 40 weeks')[:expect_g][:p3],
                           weeks(40), variant: :equation))
        .to be_within(0.1).of(2.4)
    end

    it 'stays below the table variant everywhere under the median' do
      grams = fixture('centiles at 32 weeks')[:expect_g][:p10]
      expect(percentile_of(grams, weeks(32), variant: :equation))
        .to be < percentile_of(grams, weeks(32), variant: :table)
    end

    it 'stays above it everywhere over the median, the narrower SD cutting both ways' do
      grams = fixture('centiles at 32 weeks')[:expect_g][:p90]
      expect(percentile_of(grams, weeks(32), variant: :equation))
        .to be > percentile_of(grams, weeks(32), variant: :table)
    end
  end

  # ------------------------------------------------------- what they share

  describe 'the median equation, which the two variants do not disagree about' do
    # "median equation at selected weeks" spans 10 to 40, i.e. the whole
    # published window, and is the only fixture that exercises the low end.
    %i[equation table].each do |variant|
      it "reports the median weight at every fixtured week as the 50th on the #{variant}" do
        anchor = fixture('median equation at selected weeks')
        computed = anchor[:expect_g].to_h do |wk, g|
          [wk, percentile_of(g, weeks(wk), variant: variant)]
        end
        expect(computed.values).to all(be_within(median_tolerance(anchor, variant)).of(50))
      end
    end

    it 'carries no variant on the median fixture, there being nothing to choose' do
      expect(fixture('median equation at selected weeks')).not_to have_key(:variant)
    end

    it 'places the median at the same centile whichever variant is read' do
      median = fixture('centiles at 32 weeks')[:expect_g][:p50]
      expect(percentile_of(median, weeks(32), variant: :equation))
        .to be_within(0.01).of(percentile_of(median, weeks(32), variant: :table))
    end
  end

  %i[equation table].each do |variant|
    describe "the report the #{variant} variant returns" do
      subject(:percentile) do
        call(fixture('centiles at 32 weeks')[:expect_g][:p50], weeks(32), variant: variant).value!
      end

      it 'is a Percentile' do
        expect(percentile).to be_a(Biometry::Percentile)
      end

      it 'names the closed form rather than an interpolation rule' do
        expect(percentile.interpolation).to eq(:closed_form)
      end

      it 'evaluates at decimal weeks to the nearest tenth, per the paper' do
        expect(call(3000, weeks(39, 3), variant: variant).value!.ga_weeks).to eq(39.4)
      end

      # The variant is the standard, not a footnote on it: a reader handed a
      # centile has to know which of the two figures produced it.
      it 'names the variant as the standard it came from' do
        expect(percentile.source.standard).to eq(identity(variant))
      end

      it 'carries the citation the manifest publishes, one paper behind both' do
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

    context "when the weight is far outside the centiles Table 1 prints (#{variant})" do
      it 'still computes a value, because dispersion is closed form' do
        expect(call(400, weeks(32), variant: variant).value!.bound).to eq(:computed)
      end

      it 'reports a percentile inside the unit range' do
        expect(percentile_of(400, weeks(32), variant: variant)).to be_between(0, 100)
      end
    end

    describe "the gestational age window the #{variant} variant was fitted over" do
      it 'reads the window from the manifest rather than assuming one' do
        expect(manifest[:valid_ga_weeks]).to eq([10, 40])
      end

      it 'accepts the first week of the window' do
        expect(call(35, weeks(10), variant: variant)).to be_success
      end

      it 'accepts the last week of the window' do
        expect(call(3619, weeks(40), variant: variant)).to be_success
      end

      it 'refuses a gestation below the window rather than extrapolating' do
        expect(call(30, weeks(9, 6), variant: variant).failure).to eq(
          [:out_of_range,
           { standard: identity(variant), ga_weeks: 9.9,
             valid_range: manifest[:valid_ga_weeks] }]
        )
      end

      it 'refuses a gestation one day past the window' do
        expect(call(3619, weeks(40, 1), variant: variant).failure).to eq(
          [:out_of_range,
           { standard: identity(variant), ga_weeks: 40.1,
             valid_range: manifest[:valid_ga_weeks] }]
        )
      end
    end

    # The 1991 chart was built on the four-parameter model, identified from
    # the paper's own 0.1% mean error and 7.4% SD. Reading it from the three-
    # parameter weight NICHD and WHO use measures the formula difference and
    # the chart difference at once. The dispersion dispute changes none of
    # that, so both variants pair the same way.
    describe "the formula the #{variant} variant's chart was built on" do
      it 'names the four-parameter Hadlock model as the pairing' do
        expect(manifest[:paired_formula].to_sym).to eq(:hadlock_bpd_hc_ac_fl)
      end

      it 'refuses the three-parameter Hadlock weight, naming the variant' do
        expect(call(1953, weeks(32), variant: variant,
                                     formula: :hadlock_hc_ac_fl).failure).to eq(
                                       [:formula_chart_mismatch,
                                        { chart: identity(variant),
                                          expected: :hadlock_bpd_hc_ac_fl,
                                          given: :hadlock_hc_ac_fl }]
                                     )
      end

      it 'refuses an INTERGROWTH weight' do
        expect(call(1953, weeks(32), variant: variant, formula: :intergrowth)).to be_failure
      end
    end

    # Pairing, then range. This chart is unstratified, so it expresses the
    # first two guards of the shared order and none of the stratum ones, and
    # it expresses them identically on both variants.
    it_behaves_like 'a chart that answers its guards in order',
                    { manifest: 'hadlock_1991.yml', variant: variant }
  end

  # p3 => be_within(x).of(3), and so on, so the expected centile comes from
  # the manifest's own key rather than being retyped alongside it.
  def centile_matchers(keys)
    keys.to_h do |key|
      [key, be_within(centile_tolerance).of(Float(key.to_s.delete_prefix('p')))]
    end
  end

  # The median fixture states its tolerance in per cent of weight. Dividing by
  # the variant's SD turns it into a Z offset, and the normal CDF turns that
  # into the percentile band it corresponds to — a band that is narrower on
  # the equation variant, whose SD is.
  def median_tolerance(anchor, variant)
    z = anchor[:tolerance_pct] / sd_pct(variant)
    (Biometry::Services::Growth::Normal.cdf(z) - 0.5) * 100
  end
end
