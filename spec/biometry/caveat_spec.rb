# frozen_string_literal: true

# Unit layer. A caveat quoted from a guideline: which one it is, and what it
# says, word for word.
#
# The text is quoted source rather than a finding this library produced, and
# that is the whole reason it may carry wording the rest of the output may not.
# It is therefore carried verbatim: a caveat this library paraphrased would be
# this library speaking, and the exemption would stop applying to it.
RSpec.describe Biometry::Caveat do
  subject(:caveat) { described_class.new(id: :third_trimester, text: text) }

  let(:text) { ComposedReport.redating_manifest.dig(:caveats, :third_trimester, :text) }

  it 'names which caveat it is, so a caller can tell one from another' do
    expect(caveat.id).to eq(:third_trimester)
  end

  it 'carries the guideline\'s wording unaltered' do
    expect(caveat.text).to eq(text)
  end

  # The member is `text`, never `method`: Data.define(:method) shadows
  # Object#method and breaks every reflective caller. Estimate, Percentile and
  # DatingEstimate carry the same regression test for the same reason.
  it 'does not shadow Object#method' do
    expect(caveat.method(:to_s)).to be_a(Method)
  end

  it 'is frozen, so nothing downstream can edit a quotation' do
    expect(caveat).to be_frozen
  end
end
