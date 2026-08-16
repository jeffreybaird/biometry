# frozen_string_literal: true

# Integration layer. The renderer against the values the library actually
# produces: real manifests, real services, real numbers, composed the way the
# CLI composes them.
#
# It is handed values and returns a String. It writes nothing, reads no
# manifest, calls no service and computes no clinical number — so TTY-ness
# arrives as an argument and colour is testable without capturing a stream.
#
# Rows are asserted with runs of spaces squeezed out. Column *content* and
# column *order* are the contract; the padding between them is alignment, and
# alignment is a TTY decision.
RSpec.describe Biometry::Presentation::Report do
  # A redating is passed only when one was asked for, which is how the command
  # calls it: the argument is optional and its absence is the default report.
  subject(:report) { redating ? render(redating: redating) : render }

  let(:dating) { ComposedReport.dating }
  let(:ga) { ComposedReport.ga_of }
  let(:scan) { ComposedReport.scan_of }
  let(:growth) { ComposedReport.growth }
  # Absent unless a redating was asked for. A report without the established
  # date flags must read exactly as it did before slice 2 existed.
  let(:redating) { nil }

  # A report carries one study per scan it was given. Everything below this
  # line describes the single-study report, which is what the four measurement
  # flags produce and what this file has always asserted; the several-study
  # case is in studies_spec.rb.
  def render(tty: false, **arguments)
    described_class.new(tty: tty).call(dating: dating, ga: ga, studies: [study], **arguments)
  end

  def study = Biometry::Study.new(scan: scan, ga: ga, growth: growth)

  def plain(text) = text.gsub(/\e\[[0-9;]*m/, '')

  def growth_rows(text = report)
    plain(text).lines.grep(/^\s+(INTERGROWTH|Hadlock 1991|WHO|NICHD)/)
  end

  def row(label, text = report)
    tidy(growth_rows(text).find { |line| line.include?(label) }, label)
  end

  # The unsqueezed line. Padding is alignment and normally not the contract,
  # but a field is only one field if nothing can be inserted into it.
  def raw_row(label)
    growth_rows.find { |line| line.include?(label) }.to_s.strip
  end

  def dating_row(label)
    tidy(plain(report).lines.find { |line| line.match?(/^\s+#{label}\s/) }, label)
  end

  # A missing row is a failure worth reading, not a NoMethodError on nil.
  def tidy(line, label) = line ? line.squeeze(' ').strip : "no row for #{label}"

  # The names this library will not apply to the pregnancy in front of it.
  def classification
    /\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i
  end

  def squeezed(text) = text.gsub(/\s+/, ' ').strip

  # The page with the quoted guideline text taken out of it.
  #
  # The prohibition is on classifying this fetus — SGA, IUGR, macrosomia,
  # restricted or normal as a verdict, in a value or in a row. A caveat quoted
  # from ACOG, warning what redating risks, labels nobody, and it prints
  # verbatim because a caveat this library paraphrased would be this library
  # speaking. So the quotation is removed and everything else on the page is
  # held to the rule exactly as strictly as before: a classification appearing
  # in a row or a value still fails here, whether or not the caveat is present.
  def rows_and_values(text = report)
    ComposedReport.quoted_caveats
                  .reduce(squeezed(plain(text))) { |page, quote| page.sub(squeezed(quote), '') }
  end

  # One section, the way the help page reads one flag's entry: the heading and
  # the indented lines under it, up to the next heading.
  def section(heading, text = report)
    body = plain(text).lines.drop_while { |line| !line.start_with?(heading) }
    return '' if body.empty?

    [body.first, *body.drop(1).take_while { |line| !line.match?(/\A\S/) }].join
  end

  it 'returns a string rather than writing one to a stream' do
    expect(report).to be_a(String).and(start_with('Dating'))
  end

  describe 'the dating section' do
    it 'offers every derivation, including the two this library defers' do
      labels = %w[LMP Transfer CRL Biometry]
      expect(labels.map { |label| dating_row(label).split.first }).to eq(labels)
    end

    it 'names the due date, the gestational age and the assumption behind them' do
      expect(dating_row('LMP')).to eq('LMP (28d cycle) EDD 2026-10-08 32w0d')
    end

    # LMP and transfer disagree by three days here. The disagreement is the
    # output, not a caveat on it, and slice 2 is what decides between them.
    it 'prints each derivation rather than choosing between them' do
      expect(dating_row('Transfer')).to eq('Transfer (day 5) EDD 2026-10-05 32w3d')
    end

    # Read from the estimate's own parameters, not from what the caller typed:
    # a 35-day cycle moves the due date by a week, and a reader of the output
    # alone should not have to reconstruct that.
    context 'when the cycle was not the assumed 28 days' do
      let(:dating) { ComposedReport.dating(cycle_length: 35) }

      it 'names the cycle the estimate was actually derived on' do
        expect(dating_row('LMP')).to eq('LMP (35d cycle) EDD 2026-10-15 31w0d')
      end
    end

    # A silently short table looks complete when it is not, which is exactly
    # why slice 1 refuses CRL rather than omitting it.
    it 'prints the refusal for a derivation no standard in data/ supports' do
      expect(dating_row('CRL'))
        .to eq('CRL unavailable — crl is not implemented; available: lmp, transfer')
    end

    it 'prints the same refusal for biometry dating' do
      expect(dating_row('Biometry')).to include('unavailable')
    end
  end

  describe 'the growth heading' do
    subject(:heading) { plain(report).lines.find { |line| line.start_with?('Growth') }.to_s }

    it 'names the gestation every chart was read at' do
      expect(heading).to include('GA 32w0d')
    end

    it 'names the biometry the weights were produced from' do
      expect(heading).to include('BPD 8.2', 'HC 29.1', 'AC 27.4', 'FL 6.2')
    end
  end

  describe 'the growth rows' do
    it 'prints one row per chart, with NICHD fanned out to its four' do
      expect(growth_rows.length).to eq(8)
    end

    it 'keeps the order it was handed rather than ranking the standards' do
      expect(growth_rows.map { |line| line[/INTERGROWTH|Hadlock 1991 \(\w+\)|WHO|NICHD/] })
        .to eq(['INTERGROWTH', 'Hadlock 1991 (equation)', 'Hadlock 1991 (table)', 'WHO',
                'NICHD', 'NICHD', 'NICHD', 'NICHD'])
    end

    it 'names the standard, weight, SD, centile, type and parameter set' do
      expect(row('WHO (female)'))
        .to eq('WHO (female) 1,834 g ±7.5% 45th reference (HC+AC+FL)')
    end

    it 'names the chart on every NICHD row, so no row is silently the white one' do
      expect(row('NICHD (asian)'))
        .to eq('NICHD (asian) 1,834 g ±7.5% 50th prescriptive (HC+AC+FL)')
    end

    # INTERGROWTH's 7.6% is a mean absolute prediction error. Printing it in an
    # SD column would attribute an SD to a paper that never gave one.
    it 'leaves the SD column empty for the standard that published no SD' do
      expect(row('INTERGROWTH-21st'))
        .to eq('INTERGROWTH-21st 1,697 g — 40th prescriptive (AC+HC)')
    end

    # Three EFW values, not one: formula and chart are paired.
    it 'prints the weight each chart pairs with, not one weight for all four' do
      expect(row('Hadlock 1991 (equation)'))
        .to eq('Hadlock 1991 (equation) 1,852 g ±7.4% 34th reference (BPD+HC+AC+FL)')
    end

    # One paper, two dispersion figures, no erratum, and no way to choose
    # between them from the paper itself. Both are printed, and the reader
    # sees the gap the 2025-26 exchange is about: about one percentile near
    # the threshold where it matters, from the same weight at the same week.
    describe 'the two Hadlock 1991 rows' do
      it 'prints the abstract\'s figure and the table\'s figure as two rows' do
        labels = growth_rows.filter_map { |line| line[/Hadlock 1991 \(\w+\)/] }
        expect(labels).to eq(['Hadlock 1991 (equation)', 'Hadlock 1991 (table)'])
      end

      it 'prints the table variant\'s reading of the same weight' do
        expect(row('Hadlock 1991 (table)'))
          .to eq('Hadlock 1991 (table) 1,852 g ±7.4% 35th reference (BPD+HC+AC+FL)')
      end

      it 'reads one weight at one week two ways, which is the disagreement' do
        centiles = ['Hadlock 1991 (equation)', 'Hadlock 1991 (table)']
                   .map { |label| row(label)[/\d+(?:st|nd|rd|th)\b/] }
        expect(centiles.uniq.length).to eq(2)
      end

      it 'weighs both from the four-parameter model the chart pairs with' do
        weights = ['Hadlock 1991 (equation)', 'Hadlock 1991 (table)']
                  .map { |label| row(label)[/[\d,]+ g/] }
        expect(weights).to eq(['1,852 g', '1,852 g'])
      end
    end

    it 'prints three distinct weights across the four standards' do
      weights = growth_rows.map { |line| line[/[\d,]+ g/] }
      expect(weights.uniq).to contain_exactly('1,697 g', '1,852 g', '1,834 g')
    end

    # The SD is the EFW formula's. In a column of its own it reads as the
    # neighbouring percentile's, and the percentile's uncertainty is dominated
    # by the chart's dispersion — 12.7% or 13.3% for Hadlock 1991, depending
    # which of the paper's two figures you read, against the formula's 7.4%.
    # So it is one field with the weight, with no alignment padding able to
    # come between them.
    it 'renders the weight and its SD as one field rather than two columns' do
      expect(raw_row('Hadlock 1991 (equation)')).to include('1,852 g ±7.4%')
    end

    it 'keeps that field together on a row whose SD differs' do
      expect(raw_row('WHO (female)')).to include('1,834 g ±7.5%')
    end

    # The SD sits inside the weight's field, so the gap between it and the
    # centile is a column boundary and not a single space. That is what stops
    # the two reading as one statement.
    it 'separates the SD from the centile by a column, not by a space' do
      expect(raw_row('WHO (female)')).to match(/1,834 g ±7\.5% {2,}45th/)
    end

    it 'still says which standard published no SD rather than leaving it blank' do
      expect(raw_row('INTERGROWTH-21st')).to include('1,697 g —')
    end

    it 'prints no percentile without the standard it came from' do
      ordinals = plain(report).lines.grep(/\d(st|nd|rd|th)\b/)
      expect(ordinals.length).to eq(8)
      expect(ordinals).to all(match(/^\s+(INTERGROWTH|Hadlock 1991|WHO|NICHD)/))
    end

    # Text rounds; --json carries the unrounded value. 31.691... reads 32nd.
    it 'rounds the centile to a whole ordinal' do
      expect(row('NICHD (white)')).to include('32nd')
      expect(row('NICHD (white)')).not_to include('31.69')
    end
  end

  describe 'the footnotes' do
    def notes = plain(report).lines.grep(/SD/).join

    it 'states that every SD shown is pooled, because pooling hides the tails' do
      expect(report).to match(/SD .*pooled/i)
    end

    # 7.4% is the EFW formula's SD. The percentile's uncertainty is dominated
    # by the chart's own dispersion — 12.7% or 13.3% for Hadlock 1991 — so a
    # note that left the SD unattributed would imply a tighter number than
    # this library can support.
    it 'says the SD belongs to the weight formula' do
      expect(notes).to match(/formula/i)
    end

    it 'says the SD does not include the chart\'s dispersion' do
      expect(notes).to match(/chart/i)
    end

    it 'names every chart the rows were read from' do
      papers = %w[intergrowth21 hadlock_1991 who nichd]
      citations = papers.map { |name| ComposedReport.manifest(name)[:source][:citation] }
      expect(citations).to all(satisfy { |citation| report.include?(citation) })
    end

    # Two rows, one paper. The footer lists papers, not rows: a citation
    # printed twice reads as two sources that happen to agree, when what the
    # two rows show is one source disagreeing with itself.
    it 'lists the paper behind both Hadlock 1991 rows once' do
      citation = ComposedReport.manifest('hadlock_1991')[:source][:citation]
      expect(plain(report).lines.count { |line| line.include?(citation) }).to eq(1)
    end

    # The weight and the chart come from different papers on three of the four
    # rows, and a reader checking a number needs both.
    it 'names the paper the weights came from as well' do
      expect(report)
        .to include('Sources', ComposedReport.manifest('hadlock_1985')[:source][:citation])
    end
  end

  # A row is on the page and the paper behind it is not: the reader has no way
  # to check the standard that just refused them. Whether a chart could be read
  # is a fact about this request; which paper it is is a fact about the chart,
  # known from its manifest either way. So the row carries its citation and
  # every standard with a row is cited.
  describe 'the citation on a row that could not be read' do
    let(:ga) { ComposedReport.ga_of(weeks: 41) }
    let(:growth) { ComposedReport.growth(ga: ga) }

    %w[who nichd hadlock_1991].each do |name|
      it "cites #{name}, whose row refused" do
        expect(report).to include(ComposedReport.manifest(name)[:source][:citation])
      end
    end

    it 'cites every standard on the page, refusals and all' do
      papers = %w[intergrowth21 hadlock_1991 who nichd hadlock_1985]
      citations = papers.map { |name| ComposedReport.manifest(name)[:source][:citation] }
      expect(citations).to all(satisfy { |citation| report.include?(citation) })
    end
  end

  context 'when no weight could be produced for a row at all' do
    let(:scan) { ComposedReport.scan_of(ac: 274, fl: 62) }
    let(:growth) { ComposedReport.growth(scan: scan) }

    it 'still cites the chart the row names, there being a row to check' do
      expect(report).to include(ComposedReport.manifest('who')[:source][:citation])
    end
  end

  # The last place a classification could enter, and the only place a reader
  # would see one.
  it 'reports numbers and their sources, never a classification' do
    expect(report).to include('NICHD (white)', 'prescriptive')
    expect(rows_and_values).not_to match(classification)
  end

  # Slice 2. Optional: the section exists only when a redating was asked for,
  # and its absence must leave the rest of the page exactly as it was.
  describe 'the redating section' do
    def redating_section(text = report) = section('Redating', text)

    def decision = redating.value!

    def band = ComposedReport.band_with_caveat

    def zoned = ComposedReport.band_with_zone

    context 'when no redating was asked for' do
      it 'prints no section for it' do
        expect(report).not_to include('Redating')
      end

      it 'renders exactly the report it rendered before the section existed' do
        expect(render(redating: nil)).to eq(render)
      end
    end

    context 'when a redating was asked for' do
      let(:redating) { ComposedReport.redating(discrepancy: 12) }

      it 'prints the section beside the dating it is about' do
        expect(redating_section).to start_with('Redating')
      end

      it 'places it after the dating and before the growth table' do
        offsets = %w[Dating Redating Growth].map { |heading| plain(report).index(heading) }
        expect(offsets).to eq(offsets.compact.sort)
      end

      it 'names the recommendation rather than leaving a reader to infer it' do
        expect(redating_section).to include(decision.recommendation.to_s)
      end

      it 'prints the discrepancy against the threshold it was measured on' do
        expect(redating_section)
          .to include(decision.discrepancy_days.to_s, decision.threshold_days.to_s)
      end

      it 'names the band the threshold came from' do
        expect(redating_section).to include(band[:id])
      end

      it 'names the guideline it came from' do
        expect(report).to include(decision.source.citation)
      end
    end

    # Refusals print, here as everywhere: a section that vanished would read as
    # a redating nobody asked for rather than one that could not be answered.
    context 'when the request could not be read at all' do
      let(:redating) { ComposedReport.redating(established_by: :martian) }

      it 'keeps the section and says why it could not answer' do
        expect(redating_section).to include('martian')
      end

      it 'names the derivations it does recognise' do
        expect(redating_section).to include('lmp')
      end
    end

    # Quoted source text, printed in full. A summary would be this library
    # speaking, and the exemption from the no-classification rule is precisely
    # that the guideline is speaking here and not us.
    context 'when the band carries the guideline\'s caveat' do
      let(:redating) { ComposedReport.redating(discrepancy: 12) }

      it 'prints the caveat word for word' do
        expect(squeezed(plain(report))).to include(squeezed(decision.caveat.text))
      end

      it 'keeps every row and value free of a classification even so' do
        expect(rows_and_values).not_to match(classification)
      end

      # The narrowing, stated as an assertion: the quotation is the only place
      # the word appears, and taking it out leaves a page that still passes.
      it 'is the only place on the page that wording appears' do
        expect(plain(report)).to match(classification)
      end
    end

    context 'when the discrepancy falls in the discretionary zone' do
      let(:redating) do
        ComposedReport.redating(ga_days: ComposedReport.inside_band(zoned),
                                discrepancy: zoned[:discretionary_zone][:from_days] + 1)
      end

      it 'says the guideline defers rather than printing a bare yes or no' do
        expect(redating_section).to include('discretionary')
      end

      it 'prints the zone the deferral came from' do
        zone = zoned[:discretionary_zone]
        expect(redating_section)
          .to include(zone[:from_days].to_s, zone[:to_days].to_s)
      end
    end

    context 'when the pregnancy was dated by embryo transfer' do
      let(:redating) { ComposedReport.redating(discrepancy: 12, established_by: :transfer) }

      it 'says the established date stands' do
        expect(redating_section).to include('keep')
      end

      it 'names the rule that decided it' do
        expect(redating_section).to match(/ivf/i)
      end

      # Absent, not blank: a band and a threshold printed here would attribute
      # the answer to a reading that played no part in it.
      it 'prints no band it never selected' do
        expect(redating_section).not_to include(band[:id])
      end

      it 'prints no threshold that played no part in the decision' do
        expect(redating_section).not_to include(band[:threshold_days].to_s)
      end

      it 'prints no caveat belonging to a band it never selected' do
        expect(squeezed(plain(report))).not_to include(squeezed(redating_caveat_text))
      end
    end

    context 'when the answer would differ in the neighbouring band' do
      let(:redating) do
        ComposedReport.redating(ga_days: ComposedReport.edge_days(zoned[:ga_from]),
                                discrepancy: zoned[:discretionary_zone][:from_days] + 1)
      end

      it 'names the band on the other side of the edge' do
        expect(redating_section).to include(decision.boundary_sensitivity.adjacent_band.to_s)
      end

      it 'names what the recommendation would have been there' do
        expect(redating_section)
          .to include(decision.boundary_sensitivity.recommendation.to_s)
      end
    end
  end

  def redating_caveat_text
    ComposedReport.redating_manifest.dig(:caveats, :third_trimester, :text)
  end

  describe 'when the stream is not a terminal' do
    it 'emits plain lines with no escape sequences' do
      expect(report).to include('NICHD (white)')
      expect(report).not_to include("\e[")
    end
  end

  describe 'when the stream is a terminal' do
    subject(:coloured) { render(tty: true) }

    it 'colours the output' do
      expect(coloured).to include("\e[")
    end

    it 'aligns the columns, so the same field starts at the same offset' do
      offsets = growth_rows(coloured).map { |line| line.rindex('(') }
      expect(offsets.uniq.length).to eq(1)
    end

    it 'says the same things it says when piped' do
      expect(plain(coloured)).to include('1,697 g', '40th', 'prescriptive')
    end
  end

  context 'when the gestation is outside every chart\'s window' do
    let(:ga) { ComposedReport.ga_of(weeks: 41) }
    let(:growth) { ComposedReport.growth(ga: ga) }

    it 'keeps a row for every chart rather than printing a short table' do
      expect(growth_rows.length).to eq(5)
    end

    # The two variants refuse the same window for the same reason, and each
    # says so under its own name.
    it 'names each Hadlock variant on its own refusal' do
      expect([row('Hadlock 1991 (equation)'), row('Hadlock 1991 (table)')])
        .to all(include('out of range'))
    end

    it 'prints the refusal, naming the window that chart was fitted over' do
      expect(row('NICHD')).to eq('NICHD 1,834 g ±7.5% out of range — nichd covers 15–40 weeks; given 41')
    end

    it 'names each chart\'s own window rather than one shared range' do
      expect(row('INTERGROWTH-21st')).to include('covers 22–40 weeks')
    end

    # Three conventions reach the renderer for one gestation: completed weeks
    # from the tables, tenth weeks from Hadlock 1991, exact weeks from
    # INTERGROWTH. The conventions are real and --json keeps them; the block a
    # reader is looking at should not spell 41 weeks two ways.
    it 'names the gestation the same way on every row' do
      given = growth_rows.map { |line| line[/given [\d.]+/] }
      expect(given.uniq).to eq(['given 41'])
    end

    context 'when the gestation is not a whole number of weeks' do
      let(:ga) { ComposedReport.ga_of(weeks: 41, days: 3) }

      it 'keeps the fraction on the standards that evaluate between weeks' do
        expect(row('INTERGROWTH-21st')).to end_with('given 41.4')
      end

      # 41w3d is 41.428... exact and 41.4 to the tenth on the two closed forms,
      # and the completed week 41 on the two tables. Two statements, not four.
      it 'reports the two conventions as two, rather than as four spellings' do
        expect(growth_rows.map { |line| line[/given [\d.]+/] }.uniq)
          .to contain_exactly('given 41.4', 'given 41')
      end
    end
  end

  context 'when the scan cannot feed the formulas the charts pair with' do
    let(:scan) { ComposedReport.scan_of(ac: 274, fl: 62) }
    let(:growth) { ComposedReport.growth(scan: scan) }

    it 'prints the refusal in place of a weight it could not produce' do
      expect(row('WHO')).to eq('WHO insufficient data — requires hc, ac, fl; given ac, fl')
    end

    it 'names what INTERGROWTH needed, which is not what Hadlock needed' do
      expect(row('INTERGROWTH-21st')).to include('requires ac, hc')
    end
  end

  context 'when the weight falls outside the outermost published column' do
    let(:scan) { ComposedReport.scan_of(ComposedReport::SMALL_BIOMETRY) }
    let(:growth) { ComposedReport.growth(scan: scan) }

    it 'prints the open bracket rather than a centile the chart never published' do
      expect(row('NICHD (white)')).to eq('NICHD (white) 837 g ±7.5% below 3rd prescriptive (HC+AC+FL)')
    end

    # WHO's sex-specific tables omit the 2.5th column, so the same weight
    # brackets one column further in than it does on NICHD.
    it 'brackets against the columns that chart actually published' do
      expect(row('WHO (female)')).to include('below 5th')
    end

    # Inverted from `<1st`. The two statements were spelled two ways in one
    # block — `<1st` and `>99th` from the closed forms, `below 3rd` and
    # `above 97th` from the tables — and both mean "past the outermost thing I
    # can report". One spelling, in words.
    it 'prints a closed-form value that rounds to zero as below the first centile' do
      expect(row('Hadlock 1991 (equation)')).to include('below 1st')
    end

    it 'says it the same way on the other dispersion figure' do
      expect(row('Hadlock 1991 (table)')).to include('below 1st')
    end

    it 'uses no comparison symbols anywhere in the block' do
      expect(growth_rows.join).not_to match(/[<>]/)
    end
  end

  # The upper half of the same rule, and the one that showed WHO reporting a
  # column it does not publish: the combined table tops out at 97.5, and
  # rounding an open bracket to 98 names a column that does not exist.
  context 'when the weight falls above the outermost published column' do
    let(:scan) { ComposedReport.scan_of(ComposedReport::LARGE_BIOMETRY) }
    let(:growth) { ComposedReport.growth(scan: scan, sex: :combined) }

    it 'prints the published bound verbatim rather than rounding it to a column' do
      expect(row('WHO (combined)'))
        .to eq('WHO (combined) 5,681 g ±7.5% above 97.5th reference (HC+AC+FL)')
    end

    it 'brackets NICHD against its own outermost column, which is the 97th' do
      expect(row('NICHD (white)')).to include('above 97th')
    end

    it 'prints a closed-form value that rounds past a hundred as above the ninety-ninth' do
      expect(row('Hadlock 1991 (equation)')).to include('above 99th')
    end

    it 'says it the same way on the other dispersion figure' do
      expect(row('Hadlock 1991 (table)')).to include('above 99th')
    end

    it 'says it the same way on the other closed form' do
      expect(row('INTERGROWTH-21st')).to include('above 99th')
    end

    it 'uses no comparison symbols here either' do
      expect(growth_rows.join).not_to match(/[<>]/)
    end

    context 'when the chart read is a sex-specific one' do
      let(:growth) { ComposedReport.growth(scan: scan, sex: :female) }

      # WHO's sex-specific tables omit the 97.5th column, so the same weight
      # brackets one column further in than it does on the combined chart.
      it 'brackets against the columns that chart actually published' do
        expect(row('WHO (female)')).to include('above 95th')
      end
    end
  end

  context 'when a stratum the standard does not publish is asked for' do
    let(:growth) { ComposedReport.growth(sex: :martian) }

    it 'refuses that row and names the charts WHO does publish' do
      expect(row('WHO'))
        .to eq('WHO invalid input — sex: martian; available: combined, female, male')
    end

    it 'leaves the other seven rows reporting' do
      expect(growth_rows.length).to eq(8)
    end
  end
end
