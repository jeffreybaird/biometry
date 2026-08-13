# frozen_string_literal: true

RSpec.describe Biometry::Uncertainty do
  subject(:uncertainty) { described_class.new(sd_pct: 7.5, basis: :pooled) }

  it 'carries the spread as a percentage of the value' do
    expect(uncertainty.sd_pct).to eq(7.5)
  end

  describe '.pooled' do
    it 'names the basis, so a reader is never left to assume it' do
      expect(described_class.pooled(7.5)).to eq(uncertainty)
    end
  end

  describe '#to_s' do
    it 'prints the spread and the basis it rests on' do
      expect(uncertainty.to_s).to eq('7.5% SD (pooled)')
    end

    context 'when the figure is stratified rather than pooled' do
      it 'says so, because the two are not interchangeable in the tails' do
        expect(described_class.new(sd_pct: 4.6, basis: :stratified).to_s)
          .to eq('4.6% SD (stratified)')
      end
    end
  end

  describe 'Biometry::UNCERTAINTY_BASES' do
    it 'distinguishes a pooled figure from a stratified one' do
      expect(Biometry::UNCERTAINTY_BASES).to eq(%i[pooled stratified])
    end

    it 'is frozen' do
      expect(Biometry::UNCERTAINTY_BASES).to be_frozen
    end
  end
end
