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

  describe '.inverse_cdf' do
    # The inverse is only ever asked for a probability, so the contract is
    # stated as a round trip through .cdf rather than against a table of
    # quantiles someone would have to trust.
    context 'when given a probability inside the unit interval' do
      [1e-6, 1e-4, 0.01, 0.025, 0.1, 0.25, 0.5, 0.75, 0.9, 0.975, 0.99, 0.9999, 1 - 1e-6].each do |p|
        it "returns the z whose cdf is #{p}" do
          expect(described_class.cdf(described_class.inverse_cdf(p))).to be_within(1e-9).of(p)
        end
      end
    end

    it 'is zero at the median' do
      expect(described_class.inverse_cdf(0.5)).to be_within(1e-12).of(0)
    end

    it 'puts the 97.5th percentile at 1.959964 standard deviations' do
      expect(described_class.inverse_cdf(0.975)).to be_within(1e-6).of(1.959964)
    end

    it 'puts the 2.5th percentile at -1.959964 standard deviations' do
      expect(described_class.inverse_cdf(0.025)).to be_within(1e-6).of(-1.959964)
    end

    it 'puts the 90th percentile at 1.281552 standard deviations' do
      expect(described_class.inverse_cdf(0.9)).to be_within(1e-6).of(1.281552)
    end

    context 'when given mirrored probabilities' do
      [0.001, 0.05, 0.1, 0.3, 0.4999].each do |p|
        it "returns opposite z-scores for #{p} and #{1 - p}" do
          expect(described_class.inverse_cdf(p)).to be_within(1e-9).of(-described_class.inverse_cdf(1 - p))
        end
      end
    end

    it 'increases with p' do
      values = [0.001, 0.1, 0.5, 0.9, 0.999].map { |p| described_class.inverse_cdf(p) }
      expect(values).to eq(values.sort)
    end

    # Far into the tails the round trip is limited by double precision rather
    # than by the approximation, and the two tails are limited differently.
    #
    # In the lower tail p is representable to its own relative precision, so
    # 1e-9 relative holds — about six digits of headroom over the ~1e-16 the
    # arithmetic costs, which still pins real accuracy rather than nothing.
    #
    # In the upper tail it does not: doubles just below 1.0 are spaced
    # 1.11e-16 apart, so 1 - cdf(z) is only resolvable to a few of those
    # regardless of how exact the quantile is. 1e-15 absolute is roughly nine
    # of that spacing, and is the honest floor here.
    context 'when given a probability far into a tail' do
      it 'round-trips at 1e-9' do
        p = 1e-9
        expect(described_class.cdf(described_class.inverse_cdf(p))).to be_within(p * 1e-9).of(p)
      end

      it 'round-trips at 1 - 1e-9' do
        p = 1 - 1e-9
        expect(1 - described_class.cdf(described_class.inverse_cdf(p))).to be_within(1e-15).of(1e-9)
      end

      # Below about 1.39e-11 AS241 leaves the tail rational for its third and
      # last one, the far tail — a different set of coefficients that nothing
      # else in the suite reaches. Nothing in the library asks for a centile
      # this extreme, but the branch is live, so it is pinned rather than
      # assumed.
      #
      # The mirror is written as p and its exact complement rather than as
      # 1e-15 and 1 - 1e-15: doubles just below 1.0 are spaced 1.11e-16 apart,
      # so 1 - 1e-15 is really 1 - 9.992e-16, and pairing it with a literal
      # 1e-15 would measure that 8e-4 rounding instead of the quantile.
      it 'is symmetric across the far tails' do
        upper = 1 - 1e-15
        lower = 1 - upper
        expect(described_class.inverse_cdf(lower)).to be_within(1e-9).of(-described_class.inverse_cdf(upper))
      end

      it 'round-trips at 1e-15' do
        p = 1e-15
        expect(described_class.cdf(described_class.inverse_cdf(p))).to be_within(p * 1e-9).of(p)
      end
    end

    # A probability outside (0, 1) cannot come from a percentile the library
    # accepted; it is a bug in the caller, so it raises rather than returning
    # a value the caller would have to inspect. Services guard centile inputs
    # with a Result before reaching here.
    context 'when given a probability outside the open unit interval' do
      [0.0, 1.0, -0.1, 1.5, 2.0].each do |p|
        it "raises for #{p}" do
          expect { described_class.inverse_cdf(p) }.to raise_error(ArgumentError)
        end
      end
    end
  end
end
