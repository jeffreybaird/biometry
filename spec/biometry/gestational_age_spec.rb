# frozen_string_literal: true

RSpec.describe Biometry::GestationalAge do
  describe '.from' do
    it 'stores weeks and days as a total number of days' do
      expect(described_class.from(weeks: 30, days: 3).days).to eq(213)
    end

    context 'when no days are given' do
      it 'treats the age as a whole number of weeks' do
        expect(described_class.from(weeks: 30).days).to eq(210)
      end
    end
  end

  describe '#weeks' do
    it 'reports completed weeks only' do
      expect(described_class.from(weeks: 13, days: 6).weeks).to eq(13)
    end
  end

  describe '#remainder_days' do
    it 'reports the days past the last completed week' do
      expect(described_class.from(weeks: 13, days: 6).remainder_days).to eq(6)
    end
  end

  describe '#to_s' do
    it 'prints weeks and remainder days' do
      expect(described_class.from(weeks: 13, days: 6).to_s).to eq('13w6d')
    end

    context 'when the age falls on a whole week' do
      it 'still prints a zero remainder' do
        expect(described_class.from(weeks: 14).to_s).to eq('14w0d')
      end
    end
  end

  describe '#+' do
    context 'when a day is added at a week boundary' do
      subject(:ga) { described_class.from(weeks: 13, days: 6) + 1 }

      it 'rolls over into the next week' do
        expect([ga.weeks, ga.remainder_days]).to eq([14, 0])
      end

      it 'prints as the next whole week' do
        expect(ga.to_s).to eq('14w0d')
      end
    end

    it 'returns a new age rather than mutating the receiver' do
      ga = described_class.from(weeks: 13, days: 6)
      expect(ga + 1).not_to equal(ga)
    end
  end

  describe '#-' do
    context 'when a day is taken off a week boundary' do
      it 'falls back into the previous week' do
        expect((described_class.from(weeks: 14) - 1).to_s).to eq('13w6d')
      end
    end
  end

  # INTERGROWTH-21st reads exact decimal weeks.
  describe '#exact_weeks' do
    it 'expresses 30w3d as an exact fraction of a week' do
      expect(described_class.from(weeks: 30, days: 3).exact_weeks)
        .to be_within(1e-6).of(30.428571)
    end

    context 'when the age falls on a whole week' do
      it 'returns the week as a float' do
        expect(described_class.from(weeks: 30).exact_weeks).to eq(30.0)
      end
    end
  end

  # Hadlock 1991 reads decimal weeks rounded to the nearest tenth.
  describe '#tenth_weeks' do
    it 'expresses 39w3d as 39.4' do
      expect(described_class.from(weeks: 39, days: 3).tenth_weeks).to eq(39.4)
    end

    it 'maps the seven days of a week onto the tenth grid' do
      tenths = (0..6).map { |day| described_class.from(weeks: 39, days: day).tenth_weeks }
      expect(tenths).to eq([39.0, 39.1, 39.3, 39.4, 39.6, 39.7, 39.9])
    end
  end

  # NICHD and WHO read integer completed weeks.
  describe '#completed_weeks' do
    it 'truncates 13w6d rather than rounding it up' do
      expect(described_class.from(weeks: 13, days: 6).completed_weeks).to eq(13)
    end

    it 'returns an Integer, so a chart lookup cannot miss on a float key' do
      expect(described_class.from(weeks: 13, days: 6).completed_weeks).to be_an(Integer)
    end
  end
end
