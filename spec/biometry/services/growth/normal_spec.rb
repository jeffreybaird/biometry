# frozen_string_literal: true

# Unit layer, pure mathematics. Both equation standards turn a Z-score into a
# percentile, and doing that twice is two chances to differ in the tails —
# which is exactly where this library gets read.
#
# Nothing here is a clinical constant. These are properties of the standard
# normal distribution, so asserting them is not transcribing a value out of a
# paper.
RSpec.describe Biometry::Services::Growth::Normal do
  describe '.cdf' do
    it 'is one half at the mean' do
      expect(described_class.cdf(0)).to be_within(1e-12).of(0.5)
    end

    it 'is symmetric about the mean' do
      expect(described_class.cdf(-1.3) + described_class.cdf(1.3)).to be_within(1e-12).of(1.0)
    end

    it 'puts 95% of the distribution within 1.959964 standard deviations' do
      covered = described_class.cdf(1.959964) - described_class.cdf(-1.959964)
      expect(covered).to be_within(1e-6).of(0.95)
    end

    it 'increases with z' do
      values = [-3, -1, 0, 1, 3].map { |z| described_class.cdf(z) }
      expect(values).to eq(values.sort)
    end

    # Hadlock 1991 is valid from 10 weeks, where the median is 35 g. A weight
    # far into either tail has to produce a number rather than a NaN or a
    # value outside 0..1.
    it 'stays inside the unit interval far into the lower tail' do
      expect(described_class.cdf(-8)).to be_between(0.0, 1e-14)
    end

    it 'stays inside the unit interval far into the upper tail' do
      expect(described_class.cdf(8)).to be_between(1 - 1e-14, 1.0)
    end
  end
end
