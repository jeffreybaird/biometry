# frozen_string_literal: true

# Unit layer: one of the two diagnostics an Ingest carries.
#
# It is a type rather than a hash because a caller reporting "SPEC-AFI in
# segment 4 went unread" reads four named fields, and a hash whose keys are
# spelled one way in the parser and another in the caller fails silently as a
# nil.
RSpec.describe 'Biometry::Hl7::Unrecognised' do
  subject(:unrecognised) do
    Biometry::Hl7::Unrecognised.new(segment: 4, identifier: 'SPEC-AFI', units: 'cm',
                                    reason: :identifier)
  end

  # Where in the message, so a caller can point at the line rather than at the
  # file.
  it 'names the segment it came from, indexed from one as a reader counts them' do
    expect(unrecognised.segment).to eq(4)
  end

  it 'names the identifier exactly as the message wrote it' do
    expect(unrecognised.identifier).to eq('SPEC-AFI')
  end

  it 'names the units it carried, which a caller writing the mapping needs' do
    expect(unrecognised.units).to eq('cm')
  end

  # Two different things go unread, and a caller adding to the LOINC mapping
  # needs to know which: an identifier nothing maps is a gap in the mapping, and
  # a unit nothing converts is a gap in this library.
  it 'says which of the two was not recognised' do
    expect(unrecognised.reason).to eq(:identifier)
  end

  it 'is a value, equal to another naming the same observation' do
    same = Biometry::Hl7::Unrecognised.new(segment: 4, identifier: 'SPEC-AFI', units: 'cm',
                                           reason: :identifier)
    expect(unrecognised).to eq(same)
  end
end
