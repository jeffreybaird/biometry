# frozen_string_literal: true

# Integration layer: the table when a message reported more than one study.
#
# Every study is printed, each with its own growth table, and nothing is chosen
# on the caller's behalf. Two studies weeks apart are two scans of the same
# pregnancy at two gestations, and the disagreement between them is a finding
# in exactly the way the disagreement between four standards is.
#
# The two studies here carry the identical biometry, so their weights are the
# same to the gram. Everything that differs between the two tables is the
# gestation each was read at — which is the only way to see the shift on the
# page rather than in an argument list.
RSpec.describe Biometry::Presentation::Report do
  subject(:report) { render }

  let(:dating) { ComposedReport.dating }
  let(:ga) { ComposedReport.ga_of }

  # The gestation the caller supplied, at the reference date, is the later
  # study's own. The earlier study is read six weeks back from it, and the
  # figure is derived from the fixture dates rather than typed.
  let(:earlier_ga) { ComposedReport.ga_at(Hl7Messages::EARLIER_SCAN_DATE, supplied: ga) }

  let(:earlier) do
    ComposedReport.study(scan: ComposedReport.scan_of.with(date: Hl7Messages::EARLIER_SCAN_DATE),
                         ga: earlier_ga)
  end

  let(:later) { ComposedReport.study }

  def render(tty: false, studies: [earlier, later])
    described_class.new(tty: tty).call(dating: dating, ga: ga, studies: studies)
  end

  def plain(text) = text.gsub(/\e\[[0-9;]*m/, '')

  def headings(text = report) = plain(text).lines.select { |line| line.start_with?('Growth') }

  def growth_rows(text = report)
    plain(text).lines.grep(/^\s+(INTERGROWTH|Hadlock 1991|WHO|NICHD)/)
  end

  # The rows under one heading and above the next, which is what makes a row
  # attributable to a study at all.
  def table(index)
    sections = plain(report).split(/^Growth/).drop(1)
    sections.fetch(index, '').lines.grep(/^\s+(INTERGROWTH|Hadlock 1991|WHO|NICHD)/)
  end

  def row(label, index) = table(index).find { |line| line.include?(label) }.to_s.squeeze(' ').strip

  describe 'the tables it prints' do
    it 'prints one growth table per study, in the order the message reported them' do
      expect(headings.length).to eq(2)
    end

    it 'prints every row of every study rather than choosing between them' do
      expect(growth_rows.length).to eq(16)
    end

    it 'keeps each study whole, eight rows under its own heading' do
      expect([table(0).length, table(1).length]).to eq([8, 8])
    end
  end

  # Without the date a reader has two tables and no way to tell which scan
  # either belongs to, which is worse than one table: it looks like a
  # disagreement between standards.
  describe 'the heading of each table' do
    it 'names the date the study was performed' do
      expect(headings.first).to include(Hl7Messages::EARLIER_SCAN_DATE.iso8601)
      expect(headings.last).to include(ComposedReport::REFERENCE_DATE.iso8601)
    end

    it 'names the gestation that study was read at, not the one the caller typed' do
      expect(headings.first).to include("GA #{earlier_ga}")
      expect(headings.last).to include("GA #{ga}")
    end

    it 'names the biometry each study reported' do
      expect(headings.first).to include('AC 27.4')
      expect(headings.last).to include('AC 27.4')
    end
  end

  # The point of the shift, seen on the page. The biometry is identical in both
  # studies, so a renderer reading both at the supplied gestation prints two
  # identical tables — and a reader would take that for agreement rather than
  # for arithmetic nobody did.
  describe 'the same measurements read at two gestations' do
    it 'reads the two studies differently' do
      expect(row('WHO', 0)).not_to eq(row('WHO', 1))
    end

    it 'weighs them identically, so the difference is the gestation and nothing else' do
      expect(row('WHO', 0)).to include('1,834 g')
      expect(row('WHO', 1)).to include('1,834 g')
    end
  end

  # A study whose own gestation falls outside a chart's published window is
  # refused by that chart exactly as any other out-of-range gestation is. It
  # keeps its table and its rows say why.
  context 'when one study falls outside every chart' do
    subject(:report) { render(studies: [distant, later]) }

    let(:distant_ga) { ComposedReport.ga_at(Hl7Messages::DISTANT_SCAN_DATE, supplied: ga) }

    let(:distant) do
      ComposedReport.study(scan: ComposedReport.scan_of.with(date: Hl7Messages::DISTANT_SCAN_DATE),
                           ga: distant_ga)
    end

    # Five rows, not eight. NICHD fans out to its four charts only when it
    # could read one; a gestation no chart covers is a single refusal with
    # nothing to fan out, which is what report_spec pins at 41 weeks. The
    # assertion here is that the study keeps a table at all.
    it 'keeps its table rather than dropping the study' do
      expect(table(0).length).to eq(5)
    end

    it 'says on its rows why no chart could answer' do
      expect(row('WHO', 0)).to match(/outside|range/i)
    end

    it 'leaves the study that was inside every window unaffected' do
      expect(row('WHO', 1)).to include('45th')
    end
  end

  # The report every existing spec in this directory describes, and the one the
  # four measurement flags produce. One study, one table, and no date in the
  # heading to explain a gestation that needs no explaining.
  context 'when there is one study, read at the gestation the caller supplied' do
    subject(:report) { render(studies: [later]) }

    it 'prints one table' do
      expect(headings.length).to eq(1)
    end

    it 'heads it with the gestation and the biometry, as it always has' do
      expect(headings.first).to include("GA #{ga}").and include('AC 27.4')
    end

    it 'names no date, because there is no second scan to tell it from' do
      expect(headings.first).not_to include(ComposedReport::REFERENCE_DATE.iso8601)
    end
  end

  # A single study whose gestation is not the one the caller typed. The date is
  # what explains the difference, and without it the page reads as a pregnancy
  # six weeks behind where the caller said it was.
  context 'when there is one study, read at a gestation of its own' do
    subject(:report) { render(studies: [earlier]) }

    it 'names the date the study was performed' do
      expect(headings.first).to include(Hl7Messages::EARLIER_SCAN_DATE.iso8601)
    end

    it 'names the gestation on that date' do
      expect(headings.first).to include("GA #{earlier_ga}")
    end
  end
end
