# frozen_string_literal: true

# Unit layer: the other diagnostic an Ingest carries.
#
# A segment index alone sends a reader to a line and leaves them to work out
# which of twelve fields was the problem, so the field position travels with it.
RSpec.describe 'Biometry::Hl7::Malformed' do
  subject(:malformed) { Biometry::Hl7::Malformed.new(segment: 3, field: 5, reason: :not_a_number) }

  it 'names the segment it came from, indexed from one as a reader counts them' do
    expect(malformed.segment).to eq(3)
  end

  it 'names the field position that failed' do
    expect(malformed.field).to eq(5)
  end

  it 'says what was wrong with it' do
    expect(malformed.reason).to eq(:not_a_number)
  end

  it 'is a value, equal to another naming the same failure' do
    expect(malformed).to eq(Biometry::Hl7::Malformed.new(segment: 3, field: 5,
                                                         reason: :not_a_number))
  end
end
