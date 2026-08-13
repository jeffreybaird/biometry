# frozen_string_literal: true

RSpec.describe Biometry::Estimate do
  subject(:estimate) do
    described_class.new(value: 1600, unit: 'g', method: 'hadlock_bpd_hc_ac_fl',
                        inputs: %i[bpd hc ac fl], source: provenance)
  end

  let(:provenance) do
    Biometry::Provenance.formula(standard: 'Hadlock 1991',
                                 citation: 'Radiology 1991;181:129-33',
                                 formula: 'hadlock_bpd_hc_ac_fl')
  end

  describe '#to_s' do
    it 'prints the value, its unit and the formula that produced it' do
      expect(estimate.to_s).to eq('1600 g (hadlock_bpd_hc_ac_fl)')
    end
  end

  it 'carries the measurement set the value was produced from' do
    expect(estimate.inputs).to eq(%i[bpd hc ac fl])
  end

  it 'carries the provenance that attributes the value' do
    expect(estimate.source).to eq(provenance)
  end

  describe '#method' do
    it 'reads the member, not Object#method' do
      expect(estimate.method).to eq('hadlock_bpd_hc_ac_fl')
    end

    context 'when called the way Object#method would be' do
      it 'raises, because the member shadows reflection on an instance' do
        expect { estimate.method(:to_s) }.to raise_error(ArgumentError)
      end
    end

    context 'when reflection is needed anyway' do
      it 'is still reachable through the class' do
        expect(described_class.instance_method(:to_s)).to be_a(UnboundMethod)
      end
    end
  end
end
