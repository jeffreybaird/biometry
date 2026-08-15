# frozen_string_literal: true

# Unit layer: the value the parser returns, and nothing else. No message is
# parsed here.
#
# The three collections travel together because the diagnostics are part of the
# result rather than something on the side. A parser that raised on the second
# and dropped the third would have the same signature, and a caller could not
# tell which it had been handed.
#
# Described by name rather than by constant so that each example fails on its
# own with the constant it wanted, instead of the file collapsing into one load
# error. When Biometry::Hl7 exists these become constant describes.
RSpec.describe 'Biometry::Hl7::Ingest' do
  subject(:ingest) do
    Biometry::Hl7::Ingest.new(scans: [scan], unrecognised: [unrecognised], malformed: [malformed])
  end

  let(:scan) do
    Biometry::Scan.new(date: Date.new(2026, 8, 13),
                       measurements: [Biometry::Measurement.new(kind: :ac, mm: 274)])
  end

  let(:unrecognised) do
    Biometry::Hl7::Unrecognised.new(segment: 4, identifier: 'SPEC-AFI', units: 'cm',
                                    reason: :identifier)
  end

  let(:malformed) { Biometry::Hl7::Malformed.new(segment: 3, field: 5, reason: :not_a_number) }

  it 'carries the scans it read' do
    expect(ingest.scans).to eq([scan])
  end

  it 'carries the identifiers it could not recognise alongside them' do
    expect(ingest.unrecognised).to eq([unrecognised])
  end

  it 'carries the segments it could not read alongside them' do
    expect(ingest.malformed).to eq([malformed])
  end

  it 'is a value, equal to another built from the same parts' do
    expect(ingest).to eq(Biometry::Hl7::Ingest.new(scans: [scan], unrecognised: [unrecognised],
                                                   malformed: [malformed]))
  end

  it 'is frozen, like every value in this library' do
    expect(ingest).to be_frozen
  end

  context 'when a message yielded no diagnostics at all' do
    it 'carries empty collections rather than nil, so a caller may always iterate' do
      clean = Biometry::Hl7::Ingest.new(scans: [scan], unrecognised: [], malformed: [])
      expect(clean.unrecognised + clean.malformed).to be_empty
    end
  end
end
