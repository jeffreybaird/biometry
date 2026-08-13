# frozen_string_literal: true

RSpec.describe Biometry::Provenance do
  subject(:provenance) do
    described_class.new(standard: 'NICHD', citation: 'Buck Louis et al. 2015',
                        formula: 'nichd_table', type: :prescriptive, stratum: 'white')
  end

  describe '.formula' do
    subject(:provenance) do
      described_class.formula(standard: 'Hadlock 1991', citation: 'Radiology 1991;181:129-33',
                              formula: 'hadlock_bpd_hc_ac_fl')
    end

    it 'names the standard and the formula that produced the value' do
      expect([provenance.standard, provenance.formula])
        .to eq(['Hadlock 1991', 'hadlock_bpd_hc_ac_fl'])
    end

    it 'leaves type unset rather than defaulting it' do
      expect(provenance.type).to be_nil
    end

    it 'leaves stratum unset rather than inferring one' do
      expect(provenance.stratum).to be_nil
    end
  end

  describe '#stratified?' do
    context 'when a stratum was actually used' do
      it 'is true' do
        expect(provenance).to be_stratified
      end
    end

    context 'when no stratum was used' do
      it 'is false' do
        expect(described_class.formula(standard: 'Hadlock 1991', citation: 'c', formula: 'f'))
          .not_to be_stratified
      end
    end
  end

  describe '#to_s' do
    context 'when a stratum was actually used' do
      it 'names the stratum alongside the standard' do
        expect(provenance.to_s).to eq('NICHD (white)')
      end
    end

    context 'when no stratum was used' do
      it 'prints the standard alone, with no empty parentheses' do
        expect(described_class.formula(standard: 'Hadlock 1991', citation: 'c', formula: 'f').to_s)
          .to eq('Hadlock 1991')
      end
    end
  end

  describe 'Biometry::PROVENANCE_TYPES' do
    it 'distinguishes a prescriptive standard from a reference' do
      expect(Biometry::PROVENANCE_TYPES).to eq(%i[prescriptive reference])
    end

    it 'is frozen' do
      expect(Biometry::PROVENANCE_TYPES).to be_frozen
    end
  end
end
