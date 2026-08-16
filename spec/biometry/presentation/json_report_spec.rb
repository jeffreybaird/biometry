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
  # Absent unless a redating was asked for, and passed only when it was: the
  # argument is optional and its absence is the document as it stood before
  # slice 2.
  let(:redating) { nil }
  let(:json) { redating ? render(redating: redating) : render }

  # A document carries one entry per study. Everything below this line
  # describes the single-study document; the several-study case is in
  # json_studies_spec.rb.
  def render(**arguments)
    described_class.new.call(dating: dating, ga: ga, studies: [study], **arguments)
  end

  def study = Biometry::Study.new(scan: scan, ga: ga, growth: growth)

  # The measurements and the rows now sit inside the study they were read
  # from, rather than at the top of a document that could only ever describe
  # one. The assertions about them are unchanged.
  def only_study = document['studies'].first

  def growth_entries = Array(only_study['growth'])

  def squeezed(text) = text.gsub(/\s+/, ' ').strip

  def classification
    /\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i
  end

  # The document with the quoted guideline text taken out of it. A caveat
  # quoted from ACOG labels nobody and travels verbatim; every value this
  # library produced is held to the rule exactly as strictly as before.
  def values_only(text = json)
    ComposedReport.quoted_caveats.reduce(text) { |page, quote| page.sub(squeezed(quote), '') }
  end

  # A missing entry reads as an empty one, so the failure names the field that
  # was wanted rather than raising on nil.
  def entry(index) = growth_entries.fetch(index, {})

  def percentile(index) = growth[index][:report].value!

  def estimate(index) = growth[index][:weight].value!

  it 'returns a string that parses as a JSON document' do
    expect(document.keys)
      .to include('gestational_age', 'studies', 'dating', 'sources', 'notes')
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
      expect(only_study['measurements'])
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
      expect(growth_entries.length).to eq(8)
    end

    # The variant is part of the standard's name, not a modifier beside it: a
    # consumer storing `hadlock_1991` would be storing a figure the paper
    # gives two of, with no record of which one it got.
    it 'names the standard and the chart within it on every entry' do
      expect(growth_entries.map { |row| [row['standard'], row['stratum']] })
        .to eq([['intergrowth21', nil], ['hadlock_1991_equation', nil],
                ['hadlock_1991_table', nil], %w[who female],
                %w[nichd white], %w[nichd black], %w[nichd hispanic], %w[nichd asian]])
    end

    it 'distinguishes a prescriptive standard from a reference one' do
      expect(growth_entries.map { |row| row['type'] })
        .to eq(%w[prescriptive reference reference reference prescriptive prescriptive
                  prescriptive prescriptive])
    end

    # The disagreement, in the form a program can act on: two entries, one
    # weight, one week, two percentiles about a centile apart.
    describe 'the two Hadlock 1991 entries' do
      def hadlock = growth_entries.select { |row| row['standard'].start_with?('hadlock_1991') }

      it 'carries both dispersion figures as two entries rather than one' do
        expect(hadlock.map { |row| row['standard'] })
          .to eq(%w[hadlock_1991_equation hadlock_1991_table])
      end

      it 'carries the same weight on both, the pairing being shared' do
        expect(hadlock.map { |row| row.dig('weight', 'value') }.uniq.length).to eq(1)
      end

      it 'carries a different percentile on each, unrounded' do
        values = hadlock.map { |row| row.dig('percentile', 'value') }
        expect(values.uniq.length).to eq(2)
      end

      it 'cites the one paper behind both' do
        expect(hadlock.map { |row| row.dig('percentile', 'citation') }.uniq.length).to eq(1)
      end
    end

    # 31.691353849999643, not 32. This is the half of the pinned rounding
    # decision that the table cannot express.
    it 'carries the percentile unrounded' do
      expect(entry(4).dig('percentile', 'value')).to eq(percentile(4).value)
    end

    it 'carries the weight unrounded' do
      expect(entry(4).dig('weight', 'value')).to eq(estimate(4).value)
    end

    it 'names the formula and the parameter set the weight came from' do
      expect(entry(4)['weight'].values_at('formula', 'inputs', 'unit'))
        .to eq(['hadlock_hc_ac_fl', %w[hc ac fl], 'g'])
    end

    it 'names the week the chart was read at and how it was read' do
      expect(entry(4)['percentile'].values_at('ga_weeks', 'bound', 'interpolation'))
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
      expect(entry(4)['weight']['citation']).not_to eq(entry(4)['percentile']['citation'])
    end
  end

  context 'when the weight falls outside the outermost published column' do
    let(:scan) { ComposedReport.scan_of(ComposedReport::SMALL_BIOMETRY) }
    let(:growth) { ComposedReport.growth(scan: scan) }

    it 'carries the bracket as a bracket rather than as prose' do
      expect(entry(4)['percentile'].values_at('bound', 'value')).to eq(['below', 3.0])
    end

    it 'says how it was read, which for an open bracket is not at all' do
      expect(entry(4).dig('percentile', 'interpolation')).to eq('none')
    end

    # Guard rather than a new behaviour, and the reason the table may now spell
    # both statements as words. `below 1st` on a closed form and `below 3rd`
    # on a table used to be told apart by `<` against `below`; here they are
    # told apart structurally, by `bound`, which is the form a program should
    # have been branching on all along.
    it 'keeps a computed value past the printable range apart from a bracket' do
      bounds = [entry(1), entry(4)].map { |row| row.dig('percentile', 'bound') }
      expect(bounds).to eq(%w[computed below])
    end

    it 'carries the computed value itself, which no ordinal could express' do
      expect(entry(1).dig('percentile', 'value')).to be < 1.0
    end
  end

  context 'when a chart refuses the row' do
    let(:ga) { ComposedReport.ga_of(weeks: 41) }
    let(:growth) { ComposedReport.growth(ga: ga) }

    it 'keeps the entry rather than shortening the array' do
      expect(growth_entries.map { |row| row['standard'] })
        .to eq(%w[intergrowth21 hadlock_1991_equation hadlock_1991_table who nichd])
    end

    it 'carries the failure tag and its payload' do
      expect(entry(-1)['error'])
        .to eq('tag' => 'out_of_range',
               'details' => { 'standard' => 'nichd', 'ga_weeks' => 41,
                              'valid_range' => [15, 40] })
    end

    # The refusal names the variant, for the same reason the reading does: a
    # payload saying `hadlock_1991` would not say which of the two refused.
    it 'names each Hadlock variant in its own refusal' do
      standards = [entry(1), entry(2)].map { |row| row.dig('error', 'details', 'standard') }
      expect(standards).to eq(%w[hadlock_1991_equation hadlock_1991_table])
    end

    it 'carries the weight it did produce alongside the refusal' do
      expect(entry(-1).dig('weight', 'value')).to eq(estimate(4).value)
    end

    # The table renders 41.42857142857143 as `41.4` so that one gestation is
    # not spelled two ways in one block. That is a rendering decision and it
    # stops at the renderer: the week the closed forms actually evaluated at
    # is the exact one, and a program must be handed it rather than a tenth.
    context 'when the gestation is not a whole number of weeks' do
      let(:ga) { ComposedReport.ga_of(weeks: 41, days: 3) }

      it 'carries the exact week the standard evaluated at, unrounded' do
        expect(entry(0).dig('error', 'details', 'ga_weeks'))
          .to be_within(1e-9).of(41.42857142857143)
      end

      # Two conventions, not one: the three closed forms evaluate at the exact
      # week and the two tables at the completed one. A document carrying a
      # single figure for all five would be attributing a precision to the
      # tables they never had, and a roundness to the closed forms they never
      # applied.
      it 'carries each standard\'s own convention rather than one shared week' do
        weeks = growth_entries.map { |row| row.dig('error', 'details', 'ga_weeks') }
        expect(weeks).to eq([41.42857142857143, 41.42857142857143, 41.42857142857143, 41, 41])
      end
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
      expect(entry(3).values_at('standard', 'stratum', 'type')).to eq(['who', nil, nil])
    end
  end

  describe 'the notes and the sources' do
    it 'states that every SD carried is pooled' do
      expect(document['notes']).to include(match(/pooled/i))
    end

    it 'lists every paper the document was built from, once each' do
      expect(Array(document['sources']).uniq.length).to eq(5)
    end

    # Eight rows from five papers, and the two Hadlock 1991 variants are one
    # of the five: the list is of sources, not of readings.
    it 'lists the paper behind both Hadlock 1991 entries once' do
      citation = ComposedReport.manifest('hadlock_1991')[:source][:citation]
      expect(Array(document['sources']).count(citation)).to eq(1)
    end
  end

  it 'reports numbers and their sources, never a classification' do
    expect(json).to include('prescriptive')
    expect(values_only).not_to match(classification)
  end

  # Slice 2. Optional, and structured rather than phrased: the table says
  # "12 days against a threshold of 21"; a program branching on the outcome
  # needs the three numbers apart.
  describe 'the redating decision' do
    def entry_for = document['redating']

    def decision = redating.value!

    def zoned = ComposedReport.band_with_zone

    context 'when no redating was asked for' do
      it 'carries no entry for one' do
        expect(document).not_to have_key('redating')
      end

      it 'is otherwise the document it was before the entry existed' do
        expect(render(redating: nil)).to eq(render)
      end
    end

    context 'when a redating was asked for' do
      let(:redating) { ComposedReport.redating(discrepancy: 12) }

      it 'carries the recommendation as one of the three, not as a boolean' do
        expect(entry_for['recommendation']).to eq(decision.recommendation.to_s)
      end

      it 'carries the discrepancy, the threshold and the band apart from each other' do
        expect(entry_for.values_at('discrepancy_days', 'threshold_days', 'band'))
          .to eq([12, decision.threshold_days, decision.band.to_s])
      end

      it 'carries both dates as ISO dates, revising neither' do
        expect(entry_for.values_at('established_edd', 'proposed_edd'))
          .to eq([decision.established_edd.iso8601, decision.proposed_edd.iso8601])
      end

      it 'carries the gestation the band was selected on' do
        expect(entry_for['indexing_ga']).to eq('text' => decision.indexing_ga.to_s,
                                               'days' => decision.indexing_ga.days)
      end

      it 'cites the guideline the decision was read from' do
        expect(entry_for['citation']).to eq(decision.source.citation)
      end

      # Quoted source text. A consumer displaying it is displaying ACOG, which
      # is why it may carry wording the values may not.
      it 'carries the caveat by name and word for word' do
        expect(entry_for['caveat'])
          .to eq('id' => decision.caveat.id.to_s, 'text' => decision.caveat.text)
      end

      it 'keeps every value this library produced free of a classification' do
        expect(values_only).not_to match(classification)
      end
    end

    context 'when the discrepancy falls in the discretionary zone' do
      let(:redating) do
        ComposedReport.redating(ga_days: ComposedReport.inside_band(zoned),
                                discrepancy: zoned[:discretionary_zone][:from_days] + 1)
      end

      it 'carries the zone as its two bounds rather than as prose' do
        zone = zoned[:discretionary_zone]
        expect(entry_for['zone'])
          .to eq('from_days' => zone[:from_days], 'to_days' => zone[:to_days])
      end

      it 'carries the deferral itself as the recommendation' do
        expect(entry_for['recommendation']).to eq('discretionary')
      end
    end

    # Absent rather than null-with-a-story: a band and a threshold here would
    # be readings a program could act on that played no part in the decision.
    context 'when the pregnancy was dated by embryo transfer' do
      let(:redating) { ComposedReport.redating(discrepancy: 12, established_by: :transfer) }

      it 'names the rule that decided it' do
        expect(entry_for['rule']).to eq('ivf_never_redated')
      end

      it 'carries no band, no threshold, no zone and no caveat' do
        absent = %w[band threshold_days zone caveat]
        expect(absent.reject { |key| entry_for.key?(key) }).to eq(absent)
      end

      it 'still carries the discrepancy it measured' do
        expect(entry_for['discrepancy_days']).to eq(12)
      end
    end

    context 'when the answer would differ in the neighbouring band' do
      let(:redating) do
        ComposedReport.redating(ga_days: ComposedReport.edge_days(zoned[:ga_from]),
                                discrepancy: zoned[:discretionary_zone][:from_days] + 1)
      end

      it 'carries the neighbour, its answer and the distance to the edge' do
        sensitivity = decision.boundary_sensitivity
        expect(entry_for['boundary_sensitivity'])
          .to eq('adjacent_band' => sensitivity.adjacent_band.to_s,
                 'recommendation' => sensitivity.recommendation.to_s,
                 'days_to_edge' => sensitivity.days_to_edge)
      end
    end

    # Refusals travel, here as everywhere: an entry that vanished would read as
    # a redating nobody asked for rather than one that could not be answered.
    context 'when the request could not be read at all' do
      let(:redating) { ComposedReport.redating(established_by: :martian) }

      it 'carries the failure tag and its payload' do
        expect(entry_for.dig('error', 'tag')).to eq('invalid_input')
      end

      it 'names the derivation it did not recognise' do
        expect(entry_for.dig('error', 'details', 'established_by')).to eq('martian')
      end
    end
  end
end
