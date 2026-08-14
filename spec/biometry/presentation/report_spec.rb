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
  subject(:report) { render }

  let(:dating) { ComposedReport.dating }
  let(:ga) { ComposedReport.ga_of }
  let(:scan) { ComposedReport.scan_of }
  let(:growth) { ComposedReport.growth }

  def render(tty: false)
    described_class.new(tty: tty).call(dating: dating, ga: ga, scan: scan, growth: growth)
  end

  def plain(text) = text.gsub(/\e\[[0-9;]*m/, '')

  def growth_rows(text = report)
    plain(text).lines.grep(/^\s+(INTERGROWTH|Hadlock 1991|WHO|NICHD)/)
  end

  def row(label, text = report)
    tidy(growth_rows(text).find { |line| line.include?(label) }, label)
  end

  def dating_row(label)
    tidy(plain(report).lines.find { |line| line.match?(/^\s+#{label}\s/) }, label)
  end

  # A missing row is a failure worth reading, not a NoMethodError on nil.
  def tidy(line, label) = line ? line.squeeze(' ').strip : "no row for #{label}"

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
      expect(growth_rows.length).to eq(7)
    end

    it 'keeps the order it was handed rather than ranking the standards' do
      expect(growth_rows.map { |line| line[/INTERGROWTH|Hadlock 1991|WHO|NICHD/] })
        .to eq(['INTERGROWTH', 'Hadlock 1991', 'WHO', 'NICHD', 'NICHD', 'NICHD', 'NICHD'])
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
      expect(row('Hadlock 1991'))
        .to eq('Hadlock 1991 1,852 g ±7.4% 35th reference (BPD+HC+AC+FL)')
    end

    it 'prints three distinct weights across the four standards' do
      weights = growth_rows.map { |line| line[/[\d,]+ g/] }
      expect(weights.uniq).to contain_exactly('1,697 g', '1,852 g', '1,834 g')
    end

    it 'prints no percentile without the standard it came from' do
      ordinals = plain(report).lines.grep(/\d(st|nd|rd|th)\b/)
      expect(ordinals.length).to eq(7)
      expect(ordinals).to all(match(/^\s+(INTERGROWTH|Hadlock 1991|WHO|NICHD)/))
    end

    # Text rounds; --json carries the unrounded value. 31.691... reads 32nd.
    it 'rounds the centile to a whole ordinal' do
      expect(row('NICHD (white)')).to include('32nd')
      expect(row('NICHD (white)')).not_to include('31.69')
    end
  end

  describe 'the footnotes' do
    it 'states that every SD shown is pooled, because pooling hides the tails' do
      expect(report).to match(/SD .*pooled/i)
    end

    it 'names every chart the rows were read from' do
      papers = %w[intergrowth21 hadlock_1991 who nichd]
      citations = papers.map { |name| ComposedReport.manifest(name)[:source][:citation] }
      expect(citations).to all(satisfy { |citation| report.include?(citation) })
    end

    # The weight and the chart come from different papers on three of the four
    # rows, and a reader checking a number needs both.
    it 'names the paper the weights came from as well' do
      expect(report)
        .to include('Sources', ComposedReport.manifest('hadlock_1985')[:source][:citation])
    end
  end

  # The last place a classification could enter, and the only place a reader
  # would see one.
  it 'reports numbers and their sources, never a classification' do
    expect(report).to include('NICHD (white)', 'prescriptive')
    expect(report)
      .not_to match(/\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i)
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
      expect(growth_rows.length).to eq(4)
    end

    it 'prints the refusal, naming the window that chart was fitted over' do
      expect(row('NICHD')).to eq('NICHD 1,834 g ±7.5% out of range — nichd covers 15–40 weeks; given 41')
    end

    it 'names each chart\'s own window rather than one shared range' do
      expect(row('INTERGROWTH-21st')).to include('covers 22–40 weeks')
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

    it 'prints a closed-form value that rounds to zero as below the first centile' do
      expect(row('Hadlock 1991')).to include('<1st')
    end
  end

  context 'when a stratum the standard does not publish is asked for' do
    let(:growth) { ComposedReport.growth(sex: :martian) }

    it 'refuses that row and names the charts WHO does publish' do
      expect(row('WHO'))
        .to eq('WHO invalid input — sex: martian; available: combined, female, male')
    end

    it 'leaves the other six rows reporting' do
      expect(growth_rows.length).to eq(7)
    end
  end
end
