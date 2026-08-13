# frozen_string_literal: true

RSpec.describe Biometry::Scan do
  subject(:scan) { described_class.new(date: Date.new(2026, 8, 13), measurements: [ac, fl]) }

  let(:ac) { Biometry::Measurement.new(kind: :ac, mm: 305) }
  let(:fl) { Biometry::Measurement.new(kind: :fl, mm: 68) }

  it 'is dated, with no time and no zone' do
    expect(scan.date).to eq(Date.new(2026, 8, 13))
  end

  describe '#kinds' do
    it 'lists the parameters present, in the order given' do
      expect(scan.kinds).to eq(%i[ac fl])
    end
  end

  describe '#[]' do
    it 'finds the measurement of the requested kind' do
      expect(scan[:fl]).to eq(fl)
    end

    context 'when the scan carries no measurement of that kind' do
      it 'returns nil' do
        expect(scan[:hc]).to be_nil
      end
    end
  end

  describe '#mm' do
    it 'reads the millimetre value of the requested kind' do
      expect(scan.mm(:ac)).to eq(305)
    end

    context 'when the scan carries no measurement of that kind' do
      it 'returns nil' do
        expect(scan.mm(:hc)).to be_nil
      end
    end
  end

  describe '#cm' do
    it 'reads the centimetre value of the requested kind' do
      expect(scan.cm(:fl)).to eq(6.8)
    end

    context 'when the scan carries no measurement of that kind' do
      it 'returns nil' do
        expect(scan.cm(:hc)).to be_nil
      end
    end
  end

  describe '#supports?' do
    context 'when every required parameter is present' do
      it 'is true' do
        expect(scan.supports?(%i[ac fl])).to be(true)
      end
    end

    context 'when a required parameter is absent' do
      it 'is false' do
        expect(scan.supports?(%i[hc ac fl])).to be(false)
      end
    end

    context 'when nothing is required' do
      it 'is true' do
        expect(scan.supports?([])).to be(true)
      end
    end
  end

  describe '#missing' do
    context 'when a required parameter is absent' do
      it 'names what a caller would have to add' do
        expect(scan.missing(%i[hc ac fl])).to eq(%i[hc])
      end
    end

    context 'when every required parameter is present' do
      it 'names nothing' do
        expect(scan.missing(%i[ac fl])).to eq([])
      end
    end
  end
end
