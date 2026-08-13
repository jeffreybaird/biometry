# frozen_string_literal: true

# Integration layer, and the other direction through the same table: given a
# week and a centile, what weight does WHO publish?
#
# It is a separate service from the percentile adapter because it answers a
# different question, and it exists in slice 4 because pinned decision 6 is
# about a centile *request*: Tables 14 and 15 omit the 2.5th and 97.5th
# columns, and answering those from the combined table would put two
# populations in one row. The refusal is the behaviour being pinned.
RSpec.describe Biometry::Services::Growth::Who::Centiles do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'who.yml').first
  end
  let(:table) do
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / 'percentiles/who.csv')
  end
  let(:service) { described_class.new(manifest: manifest, table: table) }

  def fixture(name) = manifest[:fixtures].find { |f| f[:name] == name }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def call(centile, ga, sex: nil) = service.call(ga: ga, centile: centile, sex: sex)

  def grams(centile, ga, sex: nil) = call(centile, ga, sex: sex).value!.grams

  describe 'the combined chart' do
    it 'publishes the tails the sex-specific tables omit' do
      anchor = fixture('combined EFW at 40 weeks')[:expect]
      computed = { p2_5: grams(2.5, weeks(40)), p50: grams(50, weeks(40)),
                   p97_5: grams(97.5, weeks(40)) }
      expect(computed).to eq(anchor)
    end

    it 'reads the row for the completed week' do
      anchor = fixture('combined EFW, p10 and p90')[:expect]
      computed = anchor.keys.to_h { |wk| [wk, grams(10, weeks(wk, 4))] }
      expect(computed).to eq(anchor.transform_values { |c| c[:p10] })
    end

    it 'names the chart it read' do
      expect(call(50, weeks(40)).value!.source.stratum).to eq(:combined)
    end

    it 'names the centile it was asked for' do
      expect(call(97.5, weeks(40)).value!.centile).to eq(97.5)
    end

    it 'names the week it read' do
      expect(call(50, weeks(40, 3)).value!.ga_weeks).to eq(40)
    end
  end

  describe 'the sex-specific charts' do
    it 'reports the median the manifest records for a female fetus at 37 weeks' do
      expect(grams(50, weeks(37), sex: :female))
        .to eq(fixture('sex difference at 37 weeks (p50)')[:expect][:female])
    end

    it 'reports the median the manifest records for a male fetus at 37 weeks' do
      expect(grams(50, weeks(37), sex: :male))
        .to eq(fixture('sex difference at 37 weeks (p50)')[:expect][:male])
    end

    # Pinned decision 6. Not a fallback to the combined table, not an
    # interpolation between the 5th and the 50th — a refusal naming what is
    # available instead.
    it 'refuses the 2.5th, which Table 14 never published' do
      expect(call(2.5, weeks(32), sex: :female).failure).to eq(
        [:unsupported_centile,
         { standard: :who, requested: 2.5, available: manifest[:centiles][:sex_specific] }]
      )
    end

    it 'refuses the 97.5th, which Table 15 never published' do
      expect(call(97.5, weeks(32), sex: :male).failure).to eq(
        [:unsupported_centile,
         { standard: :who, requested: 97.5, available: manifest[:centiles][:sex_specific] }]
      )
    end

    it 'refuses a sexed request for a tail the combined chart could have answered' do
      expect(call(2.5, weeks(40))).to be_success
      expect(call(2.5, weeks(40), sex: :female)).to be_failure
    end
  end

  context 'when the centile is one no chart publishes' do
    it 'refuses it rather than interpolating between the columns either side' do
      expect(call(42, weeks(32)).failure).to eq(
        [:unsupported_centile,
         { standard: :who, requested: 42, available: manifest[:centiles][:combined] }]
      )
    end
  end

  context 'when the gestation is outside the published window' do
    it 'refuses it, naming the standard and its window' do
      expect(call(50, weeks(13, 6)).failure).to eq(
        [:out_of_range,
         { standard: :who, ga_weeks: 13, valid_range: manifest[:valid_ga_weeks] }]
      )
    end

    # This direction takes no Estimate, so it has no pairing guard and the
    # shared order starts at the window: range, then stratum. A gestation WHO
    # never published cannot be answered off any of its charts, so which chart
    # the caller meant is a question that never arises.
    it 'refuses the window rather than the sex it would have read it on' do
      expect(call(50, weeks(13, 6), sex: :unknown).failure.first).to eq(:out_of_range)
    end
  end

  # A sex WHO does not publish is a caller's mistake, not a bug. It gets a
  # Result to branch on and exit 1, rather than the nil row the table lookup
  # would otherwise dereference on its way to exit 70.
  context 'when the sex is one the standard does not publish' do
    let(:strata) { manifest[:stratification][:values].map(&:to_sym) }
    let(:percentiles) do
      Biometry::Services::Growth::Who.new(manifest: manifest, table: table)
    end
    let(:estimate) do
      Biometry::Estimate.new(
        value: 1700, unit: 'g', formula: manifest[:paired_formula].to_sym,
        inputs: %i[hc ac fl], uncertainty: Biometry::Uncertainty.pooled(8.0),
        source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x',
                                             formula: manifest[:paired_formula].to_sym)
      )
    end
    # A weight this chart was never built to read: INTERGROWTH's own AC+HC
    # model rather than the Hadlock one WHO's centiles came from.
    let(:mismatched) do
      Biometry::Estimate.new(
        value: 1700, unit: 'g', formula: :intergrowth, inputs: %i[ac hc], uncertainty: nil,
        source: Biometry::Provenance.formula(standard: :intergrowth21, citation: 'x',
                                             formula: :intergrowth)
      )
    end

    it 'refuses it, naming the charts it does publish' do
      expect(call(50, weeks(32), sex: :unknown).failure).to eq(
        [:invalid_input, { sex: :unknown, available: strata }]
      )
    end

    # Settled before the centile is looked at: without a chart there is no
    # list of published centiles to refuse the request against.
    it 'refuses the sex rather than the tail that chart would never have published' do
      expect(call(2.5, weeks(32), sex: :unknown).failure).to eq(
        [:invalid_input, { sex: :unknown, available: strata }]
      )
    end

    # The two directions through the same table answered this differently
    # once; a weight request refused it while a centile request raised.
    it 'refuses it on the same terms as the percentile direction' do
      expect(percentiles.call(estimate: estimate, ga: weeks(32), sex: :unknown).failure)
        .to eq(call(50, weeks(32), sex: :unknown).failure)
    end

    # The example above builds its estimate from the manifest's own pairing so
    # that the sex is the only thing wrong with the call. That isolation is
    # achieved by construction and would otherwise go unasserted: the day the
    # pairing stopped being answered first, it would keep passing and say
    # nothing. This is the assertion that makes it a technique rather than an
    # assumption.
    it 'answers the pairing before the sex, so the estimate above isolates the sex' do
      expect(percentiles.call(estimate: mismatched, ga: weeks(32), sex: :unknown).failure.first)
        .to eq(:formula_chart_mismatch)
    end
  end
end
