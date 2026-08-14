# frozen_string_literal: true

require 'json'

# Integration layer. The same report as a document a program consumes.
#
# The table rounds because a reader comparing standards does not need a
# decimal place. This must not: a consumer handed a rounded centile cannot get
# the thrown-away digits back, and an open bracket must arrive as a bracket
# rather than as a number the chart never published.
#
# Undecorated by construction — there is no `tty:` here, because JSON is never
# coloured, aligned or annotated.
RSpec.describe Biometry::Presentation::JsonReport do
  subject(:document) { JSON.parse(json) }

  let(:dating) { ComposedReport.dating }
  let(:ga) { ComposedReport.ga_of }
  let(:scan) { ComposedReport.scan_of }
  let(:growth) { ComposedReport.growth }
  let(:json) do
    described_class.new.call(dating: dating, ga: ga, scan: scan, growth: growth)
  end

  # A missing entry reads as an empty one, so the failure names the field that
  # was wanted rather than raising on nil.
  def entry(index) = Array(document['growth']).fetch(index, {})

  def percentile(index) = growth[index][:report].value!

  def estimate(index) = growth[index][:weight].value!

  it 'returns a string that parses as a JSON document' do
    expect(document.keys)
      .to include('gestational_age', 'measurements', 'dating', 'growth', 'sources', 'notes')
  end

  it 'is undecorated: no colour, no alignment padding' do
    expect(json).to include('nichd')
    expect(json).not_to include("\e[")
  end

  describe 'the gestation and the biometry it was read from' do
    it 'names the gestation in the form a reader would type' do
      expect(document.dig('gestational_age', 'text')).to eq('32w0d')
    end

    it 'carries total days, because fractional weeks lose a day' do
      expect(document.dig('gestational_age', 'days')).to eq(224)
    end

    it 'carries each measurement in the millimetres it arrived as' do
      expect(document['measurements'])
        .to include({ 'kind' => 'ac', 'mm' => 274, 'cm' => 27.4 })
    end
  end

  describe 'the dating derivations' do
    it 'carries one entry per derivation, refusals included' do
      expect(document['dating'].map { |row| row['derivation'] })
        .to eq(%w[lmp transfer crl biometry])
    end

    it 'carries the due date and the date it was evaluated at as ISO dates' do
      expect(document['dating'].first.values_at('edd', 'reference_date'))
        .to eq(%w[2026-10-08 2026-08-13])
    end

    # The assumption behind the date, for a consumer that never sees the table.
    it 'carries the parameters the derivation ran on' do
      expect(document['dating'].take(2).map { |row| row['parameters'] })
        .to eq([{ 'cycle_length' => 28 }, { 'embryo_day' => 5 }])
    end

    it 'carries a refusal as a tag a program can branch on' do
      expect(document['dating'][2]['error'])
        .to eq('tag' => 'unsupported_standard',
               'details' => { 'requested' => 'crl', 'available' => %w[lmp transfer] })
    end
  end

  describe 'the growth rows' do
    it 'carries one entry per row, with NICHD fanned out to its four charts' do
      expect(document['growth'].length).to eq(7)
    end

    it 'names the standard and the chart within it on every entry' do
      expect(document['growth'].map { |row| [row['standard'], row['stratum']] })
        .to eq([['intergrowth21', nil], ['hadlock_1991', nil], %w[who female],
                %w[nichd white], %w[nichd black], %w[nichd hispanic], %w[nichd asian]])
    end

    it 'distinguishes a prescriptive standard from a reference one' do
      expect(document['growth'].map { |row| row['type'] })
        .to eq(%w[prescriptive reference reference prescriptive prescriptive
                  prescriptive prescriptive])
    end

    # 31.691353849999643, not 32. This is the half of the pinned rounding
    # decision that the table cannot express.
    it 'carries the percentile unrounded' do
      expect(entry(3).dig('percentile', 'value')).to eq(percentile(3).value)
    end

    it 'carries the weight unrounded' do
      expect(entry(3).dig('weight', 'value')).to eq(estimate(3).value)
    end

    it 'names the formula and the parameter set the weight came from' do
      expect(entry(3)['weight'].values_at('formula', 'inputs', 'unit'))
        .to eq(['hadlock_hc_ac_fl', %w[hc ac fl], 'g'])
    end

    it 'names the week the chart was read at and how it was read' do
      expect(entry(3)['percentile'].values_at('ga_weeks', 'bound', 'interpolation'))
        .to eq([32, 'computed', 'linear_in_weight'])
    end

    it 'carries the SD and the basis it was pooled on' do
      expect(entry(1).dig('weight', 'uncertainty'))
        .to eq('sd_pct' => 7.4, 'basis' => 'pooled')
    end

    # A mean absolute prediction error is not an SD, and a consumer must not
    # find one here to relabel.
    it 'carries null where the standard published no SD' do
      expect(entry(0)['weight'])
        .to include('value' => estimate(0).value, 'uncertainty' => nil)
    end

    it 'names the paper behind the weight and the paper behind the chart' do
      expect(entry(3)['weight']['citation']).not_to eq(entry(3)['percentile']['citation'])
    end
  end

  context 'when the weight falls outside the outermost published column' do
    let(:scan) { ComposedReport.scan_of(ComposedReport::SMALL_BIOMETRY) }
    let(:growth) { ComposedReport.growth(scan: scan) }

    it 'carries the bracket as a bracket rather than as prose' do
      expect(entry(3)['percentile'].values_at('bound', 'value')).to eq(['below', 3.0])
    end

    it 'says how it was read, which for an open bracket is not at all' do
      expect(entry(3).dig('percentile', 'interpolation')).to eq('none')
    end
  end

  context 'when a chart refuses the row' do
    let(:ga) { ComposedReport.ga_of(weeks: 41) }
    let(:growth) { ComposedReport.growth(ga: ga) }

    it 'keeps the entry rather than shortening the array' do
      expect(Array(document['growth']).map { |row| row['standard'] })
        .to eq(%w[intergrowth21 hadlock_1991 who nichd])
    end

    it 'carries the failure tag and its payload' do
      expect(entry(-1)['error'])
        .to eq('tag' => 'out_of_range',
               'details' => { 'standard' => 'nichd', 'ga_weeks' => 41,
                              'valid_range' => [15, 40] })
    end

    it 'carries the weight it did produce alongside the refusal' do
      expect(entry(-1).dig('weight', 'value')).to eq(estimate(3).value)
    end
  end

  # The other refusal shape, and a consumer branching on `error` needs both.
  # A chart that refused still carries the weight it could not place; a weight
  # that was never produced leaves nothing to attribute, so the entry carries
  # no weight at all.
  context 'when the weight a chart pairs with could not be produced' do
    let(:scan) { ComposedReport.scan_of(ac: 274, fl: 62) }
    let(:growth) { ComposedReport.growth(scan: scan) }

    it 'carries the weight\'s own failure rather than the chart\'s' do
      expect(entry(0)['error'])
        .to eq('tag' => 'insufficient_data',
               'details' => { 'required' => %w[ac hc], 'given' => %w[ac fl] })
    end

    it 'carries no weight, where a refused chart carries the one it produced' do
      expect(entry(0)).not_to have_key('weight')
      expect(entry(0)).not_to have_key('percentile')
    end

    it 'names no chart within the standard, because none was ever selected' do
      expect(entry(2).values_at('standard', 'stratum', 'type')).to eq(['who', nil, nil])
    end
  end

  describe 'the notes and the sources' do
    it 'states that every SD carried is pooled' do
      expect(document['notes']).to include(match(/pooled/i))
    end

    it 'lists every paper the document was built from, once each' do
      expect(Array(document['sources']).uniq.length).to eq(5)
    end
  end

  it 'reports numbers and their sources, never a classification' do
    expect(json).to include('prescriptive')
    expect(json)
      .not_to match(/\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i)
  end
end
