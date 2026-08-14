# frozen_string_literal: true

# Unit layer. The disclosure that a decision sits near a band edge and would
# have come out differently on the other side of it.
#
# Three members, and none of them is optional. The adjacent band alone says
# where the edge is but not that anything turns on it; the recommendation alone
# says the answer differs but not that the gestation is anywhere near the line.
# It is the pair that makes this a finding rather than hedging, and the
# distance is what lets a reader judge how close the call was.
#
# The values here are deliberately not ACOG's. This object knows nothing about
# any guideline: it is handed a neighbouring band and what would happen there.
RSpec.describe Biometry::BoundarySensitivity do
  subject(:sensitivity) do
    described_class.new(adjacent_band: :a_neighbouring_band, recommendation: :redate,
                        days_to_edge: 2)
  end

  it 'names the band on the other side of the edge' do
    expect(sensitivity.adjacent_band).to eq(:a_neighbouring_band)
  end

  it 'names what the recommendation would be there' do
    expect(sensitivity.recommendation).to eq(:redate)
  end

  it 'counts how far the indexing gestation sits from that band' do
    expect(sensitivity.days_to_edge).to eq(2)
  end

  # The member is `recommendation`, never `method`: Data.define(:method)
  # shadows Object#method and breaks every reflective caller.
  it 'does not shadow Object#method' do
    expect(sensitivity.method(:to_s)).to be_a(Method)
  end

  it 'is frozen' do
    expect(sensitivity).to be_frozen
  end
end
