# frozen_string_literal: true

# Integration layer, and the other direction through Hadlock 1991: given a week
# and a centile, what weight does the standard put there?
#
# An equation standard, so this direction is not a lookup. The median comes
# from the paper's own closed form and the dispersion is a fixed percentage of
# it, which makes every centile in (0, 100) computable and none of them
# published in the sense a table column is.
#
# The dispersion dispute rides along unchanged: 12.7% in the abstract, 13.3%
# implied by Table 1, no erratum, so the standard is served as two variants and
# a weight-at-centile is asked of one of them, never of "Hadlock 1991". The
# variants agree exactly on the median and nowhere else, and that agreement is
# asserted rather than assumed — it is the half of the paper the dispute does
# not touch.
#
# The anchors are Table 1 by way of the manifest's fixtures, which name the
# table variant because Table 1 is what they are. Everything not anchored to a
# published number is anchored to the forward adapter instead: a weight this
# service returns for the 10th, read back through Hadlock1991, is the 10th.
# That round trip is the property worth pinning, and it holds without either
# direction's arithmetic being restated here.
RSpec.describe Biometry::Services::Growth::Hadlock1991::Centiles do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock_1991.yml').first
  end

  # Grams out and grams back in are the same closed form evaluated in opposite
  # directions, so the round trip is exact to within floating point rather than
  # to within a clinical tolerance.
  def round_trip_tolerance = 1e-6

  def service(variant = nil) = described_class.new(manifest: manifest, variant: variant)

  def forward(variant = nil)
    Biometry::Services::Growth::Hadlock1991.new(manifest: manifest, variant: variant)
  end

  def variant_of(name) = manifest[:variants][name]

  def identity(name) = variant_of(name)[:id].to_sym

  def fixture(name) = manifest[:fixtures].find { |f| f[:name] == name }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def call(centile, ga, variant: nil) = service(variant).call(ga: ga, centile: centile)

  def grams(centile, ga, variant: nil) = call(centile, ga, variant: variant).value!.grams

  # The chart's own pairing, so the weight goes back in through the same door
  # it came out of and the pairing guard is not what is being measured.
  def efw(value)
    Biometry::Estimate.new(
      value: value, unit: 'g', formula: manifest[:paired_formula].to_sym,
      inputs: %i[bpd hc ac fl], uncertainty: Biometry::Uncertainty.pooled(7.4),
      source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x',
                                           formula: manifest[:paired_formula].to_sym)
    )
  end

  def read_back(value, ga, variant: nil)
    forward(variant).call(estimate: efw(value), ga: ga).value!.value
  end

  # p3 => 3, so the centile asked for comes from the manifest's own key rather
  # than being retyped beside it.
  def centile_of(key) = Float(key.to_s.delete_prefix('p'))

  # ------------------------------------------------------------- the anchors

  # Table 1 is the table variant's, and only its. The equation variant has no
  # published centile column to be anchored to, which is the whole dispute.
  describe 'the weights the table variant reproduces' do
    [32, 40].each do |week|
      it "prints every centile Table 1 prints at #{week} weeks" do
        anchor = fixture("centiles at #{week} weeks")
        computed = anchor[:expect_g]
                   .to_h { |key, _| [key, grams(centile_of(key), weeks(week), variant: :table)] }
        expect(computed).to match(within_g(anchor))
      end
    end

    it 'anchors those fixtures to the table variant, Table 1 being their source' do
      named = manifest[:fixtures].select { |f| f[:variant] }.map { |f| f[:variant].to_sym }
      expect(named.uniq).to eq([:table])
    end

    # Table 1's centiles are median x {0.750, 0.830, 1.170, 1.250} at every
    # week, which is where the 13.3% was back-calculated from. The ratios are
    # the manifest's; the weights are this service's.
    it 'reproduces the constant ratios to the median the published table exhibits' do
      median = grams(50, weeks(32), variant: :table)
      computed = variant_of(:table)[:published_ratios]
                 .to_h { |key, _| [key, grams(centile_of(key), weeks(32), variant: :table) / median] }
      expect(computed).to match(variant_of(:table)[:published_ratios]
                                  .transform_values { |ratio| be_within(1e-3).of(ratio) })
    end
  end

  # The half of the paper the two variants do not disagree about. Z is zero at
  # the 50th, so the dispersion figure drops out entirely and both variants
  # must return the same gram — not nearly the same one.
  describe 'the median, which the dispersion dispute does not touch' do
    it 'places the same weight at the 50th whichever variant is read' do
      expect(grams(50, weeks(32), variant: :equation))
        .to be_within(1e-9).of(grams(50, weeks(32), variant: :table))
    end

    %i[equation table].each do |variant|
      it "reproduces the median fixture at every week it names, on the #{variant}" do
        anchor = fixture('median equation at selected weeks')
        computed = anchor[:expect_g].to_h { |wk, _| [wk, grams(50, weeks(wk), variant: variant)] }
        expect(computed).to match(anchor[:expect_g].transform_values { |g|
          be_within(g * anchor[:tolerance_pct] / 100.0).of(g)
        })
      end
    end
  end

  # ------------------------------------------------------- the two directions

  # Several weeks and several centiles, including two off the published five
  # and one on a fractional gestation, because the closed form is defined
  # everywhere in the window and the round trip should be too.
  def round_trip_points
    [[20, 0, 3], [26, 4, 10], [32, 0, 50], [35, 3, 90], [38, 2, 42.5], [40, 0, 97]]
  end

  %i[equation table].each do |variant|
    describe "the weight the #{variant} variant returns, read back through the chart" do
      it 'is read back as the centile it was asked for' do
        computed = round_trip_points.to_h do |(wk, day, centile)|
          ga = weeks(wk, day)
          [[wk, day, centile], read_back(grams(centile, ga, variant: variant), ga, variant: variant)]
        end
        expect(computed)
          .to match(round_trip_points.to_h { |p| [p, be_within(round_trip_tolerance).of(p.last)] })
      end

      it 'rises with the centile asked for at a fixed week' do
        computed = [3, 10, 50, 90, 97].map { |c| grams(c, weeks(32), variant: variant) }
        expect(computed).to eq(computed.sort)
      end

      it 'rises with gestation at a fixed centile' do
        computed = [20, 28, 32, 40].map { |wk| grams(10, weeks(wk), variant: variant) }
        expect(computed).to eq(computed.sort)
      end
    end
  end

  # The dispute, stated in grams. The narrower SD pulls both tails toward the
  # median, so the equation variant puts more weight at the 3rd and less at the
  # 97th than the table it cannot reproduce.
  describe 'the two dispersion figures, seen from this direction' do
    it 'puts the 3rd centile higher on the equation variant than on the table' do
      expect(grams(3, weeks(32), variant: :equation))
        .to be > grams(3, weeks(32), variant: :table)
    end

    it 'puts the 97th centile lower on it, the narrower SD cutting both ways' do
      expect(grams(97, weeks(32), variant: :equation))
        .to be < grams(97, weeks(32), variant: :table)
    end

    it 'reads the paper\'s own 3rd-centile weight as a lower centile on the equation' do
      published = fixture('centiles at 32 weeks')[:expect_g][:p3]
      expect(read_back(published, weeks(32), variant: :equation)).to be < 3
    end
  end

  # ------------------------------------------------------------ the variants

  describe 'the variant it reads when the caller names none' do
    it 'resolves to the variant the manifest states as its default' do
      expect(call(50, weeks(32)).value!.source.standard)
        .to eq(identity(manifest[:default].to_sym))
    end

    it 'returns the same weight as that variant asked for by name' do
      expect(grams(10, weeks(32)))
        .to eq(grams(10, weeks(32), variant: manifest[:default].to_sym))
    end

    # A variant this standard does not publish is a bug in the caller, not a
    # condition a caller branches on, so it raises rather than returning a
    # Failure — the same as the percentile direction.
    it 'raises on a variant the manifest does not carry, rather than falling back' do
      expect { service(:the_discussion_section) }.to raise_error(KeyError)
    end
  end

  # ------------------------------------------------------------- the domain

  # The manifest records `computable: any`, and this direction is where that
  # claim is cashed: no column is privileged, so the 42.5th is as answerable as
  # the 10th. The open ends are not, and they are not a clinical judgement —
  # no finite weight sits at the 0th or the 100th of a normal distribution.
  #
  # PINNED: the refusal is [:invalid_input, { centile: <as asked>,
  # valid_range: [0, 100] }], with both ends exclusive. `valid_range` is the
  # key :out_of_range already uses for a window, and the exclusivity is pinned
  # by the examples either side of each end rather than spelled into the
  # payload.
  describe 'the centiles it will compute' do
    it 'computes a centile no table publishes, dispersion being closed form' do
      expect(call(42.5, weeks(32))).to be_success
    end

    it 'computes arbitrarily close to either end' do
      expect([call(0.01, weeks(32)), call(99.99, weeks(32))]).to all(be_success)
    end

    it 'records `computable: any`, which is what the two above are cashing' do
      expect(manifest[:centiles][:computable]).to eq('any')
    end

    it 'refuses the 0th, no finite weight sitting there' do
      expect(call(0, weeks(32)).failure).to eq(
        [:invalid_input, { centile: 0, valid_range: [0, 100] }]
      )
    end

    it 'refuses the 100th for the same reason' do
      expect(call(100, weeks(32)).failure).to eq(
        [:invalid_input, { centile: 100, valid_range: [0, 100] }]
      )
    end

    it 'refuses a negative centile, echoing what it was asked for' do
      expect(call(-1, weeks(32)).failure).to eq(
        [:invalid_input, { centile: -1, valid_range: [0, 100] }]
      )
    end

    it 'refuses a centile past 100' do
      expect(call(101, weeks(32)).failure).to eq(
        [:invalid_input, { centile: 101, valid_range: [0, 100] }]
      )
    end

    # A Failure rather than the ArgumentError Normal#inverse_cdf raises: the
    # services guard their inputs so a caller branches on a value and exits 1,
    # rather than taking the whole run to exit 70 over a typed centile.
    it 'refuses rather than raising out of the quantile function' do
      expect { call(0, weeks(32)) }.not_to raise_error
    end
  end

  %i[equation table].each do |variant|
    describe "the gestational age window the #{variant} variant was fitted over" do
      it 'accepts the first week of the window' do
        expect(call(50, weeks(10), variant: variant)).to be_success
      end

      it 'accepts the last week of the window' do
        expect(call(50, weeks(40), variant: variant)).to be_success
      end

      # Exact decimal weeks, unrounded, the same convention the percentile
      # direction evaluates at: 9w6d is 9.857, not 9.9, and the payload carries
      # the week the chart was actually asked about.
      it 'refuses a gestation below the window rather than extrapolating' do
        expect(call(50, weeks(9, 6), variant: variant).failure).to eq(
          [:out_of_range,
           { standard: identity(variant), ga_weeks: weeks(9, 6).exact_weeks,
             valid_range: manifest[:valid_ga_weeks] }]
        )
      end

      it 'refuses a gestation one day past the window' do
        expect(call(50, weeks(40, 1), variant: variant).failure).to eq(
          [:out_of_range,
           { standard: identity(variant), ga_weeks: weeks(40, 1).exact_weeks,
             valid_range: manifest[:valid_ga_weeks] }]
        )
      end

      # The window is answered before the centile: a gestation the paper never
      # fitted has no centiles at all, so refusing the centile there would name
      # the smaller of two problems.
      it 'names the window before the centile when both are wrong' do
        expect(call(0, weeks(41), variant: variant).failure.first).to eq(:out_of_range)
      end
    end

    describe "the report the #{variant} variant returns" do
      subject(:weight) { call(10, weeks(32, 3), variant: variant).value! }

      it 'is a ChartWeight' do
        expect(weight).to be_a(Biometry::ChartWeight)
      end

      it 'names the centile it was asked for' do
        expect(weight.centile).to eq(10)
      end

      it 'names the exact decimal week it evaluated at, unrounded' do
        expect(weight.ga_weeks).to eq(weeks(32, 3).exact_weeks)
      end

      # The variant is the standard, not a footnote on it: a reader handed a
      # weight has to know which of the two figures produced it.
      it 'names the variant as the standard it came from' do
        expect(weight.source.standard).to eq(identity(variant))
      end

      it 'carries the citation the manifest publishes, one paper behind both' do
        expect(weight.source.citation).to eq(manifest[:source][:citation])
      end

      it 'names the formula the chart was built on' do
        expect(weight.source.formula).to eq(manifest[:paired_formula].to_sym)
      end

      it 'names the standard as a reference, not a prescriptive one' do
        expect(weight.source.type).to eq(:reference)
      end

      it 'claims no stratum, because the 1991 chart is unstratified' do
        expect(weight.source).not_to be_stratified
      end

      it 'reports a number and its source, never a classification' do
        expect(weight.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
      end
    end
  end

  # p3 => be_within(3).of(1465), the tolerance and the weight both the
  # fixture's own.
  def within_g(anchor)
    anchor[:expect_g].transform_values { |g| be_within(anchor[:tolerance_g]).of(g) }
  end
end
