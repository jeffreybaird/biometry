# frozen_string_literal: true

RSpec.describe Biometry::Estimate do
  subject(:estimate) do
    described_class.new(value: 1600, unit: 'g', formula: 'hadlock_bpd_hc_ac_fl',
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

  describe '#formula' do
    it 'names the formula that produced the value' do
      expect(estimate.formula).to eq('hadlock_bpd_hc_ac_fl')
    end
  end

  # The member was `method` until slice 3. `Data.define(:method)` generates a
  # reader that overrides Object#method, so reflection on an instance raised
  # ArgumentError for wrong arity and pointed nowhere near the cause.
  describe '#method' do
    it 'is Object#method, because no member shadows it' do
      expect(estimate.method(:to_s)).to be_a(Method)
    end

    it 'reflects on the instance, not on the class as a workaround' do
      expect(estimate.method(:to_s).call).to eq('1600 g (hadlock_bpd_hc_ac_fl)')
    end
  end
end
