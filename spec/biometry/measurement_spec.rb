# frozen_string_literal: true

RSpec.describe Biometry::Measurement do
  subject(:measurement) { described_class.new(kind: :ac, mm: 305) }

  it 'keeps the millimetres it was given, because that is what HL7 carries' do
    expect(measurement.mm).to eq(305)
  end

  # Millimetres are Numeric, not Integer: scanners report to one decimal place
  # and a measurement rounded on the way in loses precision the formula was
  # going to use.
  it 'keeps a fractional millimetre, because that is what a scanner reports' do
    expect(described_class.new(kind: :ac, mm: 274.5).mm).to eq(274.5)
  end

  describe '#cm' do
    it 'converts to the centimetres every published formula wants' do
      expect(measurement.cm).to eq(30.5)
    end

    it 'returns a Float, so an odd millimetre does not truncate' do
      expect(described_class.new(kind: :ac, mm: 305).cm).to be_a(Float)
    end

    it 'carries a fractional millimetre through to centimetres' do
      expect(described_class.new(kind: :ac, mm: 274.5).cm).to eq(27.45)
    end
  end

  describe '#to_s' do
    it 'prints the parameter upcased with its centimetre value' do
      expect(measurement.to_s).to eq('AC 30.5 cm')
    end
  end

  describe 'Biometry::MEASUREMENT_KINDS' do
    it 'names every biometric parameter a formula in this library reads' do
      expect(Biometry::MEASUREMENT_KINDS).to eq(%i[bpd hc ac fl hl crl])
    end

    it 'is frozen' do
      expect(Biometry::MEASUREMENT_KINDS).to be_frozen
    end
  end
end
