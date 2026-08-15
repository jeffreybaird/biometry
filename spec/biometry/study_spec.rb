# frozen_string_literal: true

# Unit layer: one study as a report carries it.
#
# A message may report more than one study, and each is read at the gestation
# on its own date. So the gestation belongs to the study rather than to the
# report: a single `ga` at the top of a report carrying two scans would be
# right for one of them and wrong by exactly the days between them for the
# other.
#
# The rows travel with it for the same reason. They were read at that
# gestation, from that scan, and a collection of rows detached from the study
# they belong to is a table a reader cannot attribute.
RSpec.describe 'Biometry::Study' do
  subject(:study) { Biometry::Study.new(scan: scan, ga: ga, growth: growth) }

  let(:scan) { ComposedReport.scan_of }
  let(:ga) { ComposedReport.ga_of }
  let(:growth) { ComposedReport.growth }

  it 'carries the scan it was read from' do
    expect(study.scan).to eq(scan)
  end

  # Not the gestation the caller typed: the gestation on this study's date.
  it 'carries the gestation this study was read at' do
    expect(study.ga).to eq(ga)
  end

  it 'carries the rows read from it' do
    expect(study.growth).to eq(growth)
  end

  # The date is the scan's, not a second copy of it. Two places to write a
  # date is one place for them to disagree.
  it 'is dated by its scan' do
    expect(study.scan.date).to eq(ComposedReport::REFERENCE_DATE)
  end

  it 'is a value, equal to another built from the same parts' do
    expect(study).to eq(Biometry::Study.new(scan: scan, ga: ga, growth: growth))
  end

  it 'is frozen, like every value in this library' do
    expect(study).to be_frozen
  end
end
