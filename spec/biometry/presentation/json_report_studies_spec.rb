# frozen_string_literal: true

require 'json'

# Integration layer: the same several-study report as a document.
#
# One entry per study, each carrying its date, the gestation it was read at and
# its rows. The document always has the collection, whether the report carries
# one study or three: a consumer that had to branch on the shape of the
# document to find the rows would get it wrong the first time a message arrived
# with two studies in it.
RSpec.describe Biometry::Presentation::JsonReport do
  subject(:document) { JSON.parse(render) }

  let(:dating) { ComposedReport.dating }
  let(:ga) { ComposedReport.ga_of }
  let(:earlier_ga) { ComposedReport.ga_at(Hl7Messages::EARLIER_SCAN_DATE, supplied: ga) }

  let(:earlier) do
    ComposedReport.study(scan: ComposedReport.scan_of.with(date: Hl7Messages::EARLIER_SCAN_DATE),
                         ga: earlier_ga)
  end

  let(:later) { ComposedReport.study }

  def render(studies: [earlier, later])
    described_class.new.call(dating: dating, ga: ga, studies: studies)
  end

  def studies = document['studies']

  describe 'the studies collection' do
    it 'carries one entry per study, in the order the message reported them' do
      expect(studies.length).to eq(2)
    end

    it 'dates each entry with the day that study was performed' do
      expect(studies.map { |study| study['date'] })
        .to eq([Hl7Messages::EARLIER_SCAN_DATE.iso8601, ComposedReport::REFERENCE_DATE.iso8601])
    end

    # Total days as well as the text, for the same reason the top-level
    # gestation carries both: fractional weeks lose a day.
    it 'carries the gestation each study was read at' do
      expect(studies.map { |study| study.dig('gestational_age', 'days') })
        .to eq([earlier_ga.days, ga.days])
    end

    it 'names the gestation in the form a reader would type' do
      expect(studies.first.dig('gestational_age', 'text')).to eq(earlier_ga.to_s)
    end

    it 'carries the measurements and the rows inside the study they were read from' do
      expect(studies.first.keys).to include('date', 'gestational_age', 'measurements', 'growth')
    end

    it 'carries every row of every study rather than choosing between them' do
      expect(studies.map { |study| study['growth'].length }).to eq([8, 8])
    end
  end

  # The gestation the caller supplied, at the reference date. It is not any
  # one study's, and a consumer needs it to see what the per-study figures were
  # derived from.
  describe 'the gestation at the top of the document' do
    it 'is the one the caller supplied' do
      expect(document.dig('gestational_age', 'days')).to eq(ga.days)
    end
  end

  # Identical biometry, so identical weights: what differs between the entries
  # is the chart reading, and only because the gestations differ.
  describe 'the same measurements read at two gestations' do
    def percentiles(index)
      studies[index]['growth'].map { |row| row.dig('percentile', 'value') }
    end

    def weights(index)
      studies[index]['growth'].map { |row| row.dig('weight', 'value') }
    end

    it 'reports the same weights for both' do
      expect(weights(0)).to eq(weights(1))
    end

    it 'reports different chart readings for them' do
      expect(percentiles(0)).not_to eq(percentiles(1))
    end
  end

  context 'when the report carries a single study' do
    subject(:document) { JSON.parse(render(studies: [later])) }

    it 'still carries a collection, so nothing has to branch on the shape' do
      expect(studies.length).to eq(1)
    end

    it 'dates it, even though there is nothing to tell it from' do
      expect(studies.first['date']).to eq(ComposedReport::REFERENCE_DATE.iso8601)
    end
  end
end
