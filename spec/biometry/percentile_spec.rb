# frozen_string_literal: true

# Unit layer. The value four heterogeneous adapters agree to return.
#
# It carries three things beyond the number, and each of them is pinned by a
# slice 4 decision rather than by taste: the week actually read or evaluated
# at (no week interpolation), the interpolation method used between centiles,
# and the provenance naming the standard and the chart. A percentile without
# those is not comparable across standards, which is the only reason this
# library exists.
RSpec.describe Biometry::Percentile do
  subject(:percentile) do
    described_class.new(value: 9.4, bound: :computed, ga_weeks: 32,
                        interpolation: :linear_in_weight, source: provenance)
  end

  let(:provenance) do
    Biometry::Provenance.new(standard: :nichd, citation: 'Buck Louis et al. 2015',
                             formula: :hadlock_hc_ac_fl, type: :prescriptive,
                             stratum: :white)
  end

  it 'carries the percentile itself' do
    expect(percentile.value).to eq(9.4)
  end

  it 'names the week it was read at, so no reader has to reconstruct it' do
    expect(percentile.ga_weeks).to eq(32)
  end

  it 'names the interpolation method that produced it' do
    expect(percentile.interpolation).to eq(:linear_in_weight)
  end

  it 'names the standard through its provenance' do
    expect(percentile.source.standard).to eq(:nichd)
  end

  it 'names the chart it was read from' do
    expect(percentile.source.stratum).to eq(:white)
  end

  # The member is `interpolation`, never `method`: Data.define(:method) shadows
  # Object#method and breaks every reflective caller. Estimate carries the same
  # regression test for the same reason.
  it 'does not shadow Object#method' do
    expect(percentile.method(:to_s)).to be_a(Method)
  end

  describe '#to_s' do
    it 'names the standard alongside the number' do
      expect(percentile.to_s).to include('nichd')
    end

    it 'emits no classification label of any kind' do
      expect(percentile.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end

  def bracketed(value, bound)
    described_class.new(value: value, bound: bound, ga_weeks: 32,
                        interpolation: :none, source: provenance)
  end

  # A table cannot answer beyond its outermost published column, so the honest
  # report is the open bracket rather than an extrapolated number. That is the
  # case the no-extrapolation rule produces, which makes it the last one whose
  # rendering should go unread.
  context 'when the weight sits below the lowest published centile' do
    subject(:percentile) { bracketed(3.0, :below) }

    it 'names the published centile the weight lies beyond' do
      expect(percentile.value).to eq(3.0)
    end

    it 'marks the bracket open rather than claiming a computed value' do
      expect(percentile.bound).to eq(:below)
    end

    it 'reports that no interpolation was performed' do
      expect(percentile.interpolation).to eq(:none)
    end

    describe '#to_s' do
      it 'says the weight lies below that centile rather than on it' do
        expect(percentile.to_s).to match(/below/i)
      end

      it 'reads differently from the same centile arrived at exactly' do
        exact = described_class.new(value: 3.0, bound: :computed, ga_weeks: 32,
                                    interpolation: :linear_in_weight, source: provenance)
        expect(percentile.to_s).not_to eq(exact.to_s)
      end

      it 'still names the standard alongside the bracket' do
        expect(percentile.to_s).to include('nichd')
      end

      it 'emits no classification label of any kind' do
        expect(percentile.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
      end
    end
  end

  context 'when the weight sits above the highest published centile' do
    subject(:percentile) { bracketed(97.0, :above) }

    it 'names the published centile the weight lies beyond' do
      expect(percentile.value).to eq(97.0)
    end

    it 'marks the bracket open above' do
      expect(percentile.bound).to eq(:above)
    end

    describe '#to_s' do
      it 'says the weight lies above that centile' do
        expect(percentile.to_s).to match(/above/i)
      end

      # The failure worth guarding against is both open arms rendering the
      # same way. "Above the 97th" and "below the 97th" are opposite readings
      # of the same number.
      it 'reads differently from an open bracket below the same centile' do
        expect(percentile.to_s).not_to eq(bracketed(97.0, :below).to_s)
      end

      it 'emits no classification label of any kind' do
        expect(percentile.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
      end
    end
  end
end
