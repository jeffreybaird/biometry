# frozen_string_literal: true

require 'biometry/cli/report_options'

# Unit layer: argv in, values out. Nothing here opens a manifest, calls a
# service or touches a stream.
#
# Two quantities the command reads are counted in different things and the
# parser is where that distinction lives. A millimetre is measured, so a
# scanner reporting 274.5 is reporting a real value and rounding it on the way
# in discards precision the formula was going to use. A cycle length and an
# embryo day are counted, so 28.5 days and a day-4.5 embryo are not values that
# were measured imprecisely — they are values that do not exist.
RSpec.describe Biometry::CLI::ReportOptions do
  def parse(*argv) = described_class.parse(%w[--ga 32w0d] + argv)

  describe 'a biometric measurement' do
    context 'when reported to one decimal place, as a scanner reports it' do
      it 'keeps the decimal rather than refusing the measurement' do
        expect(parse('--ac', '274.5')[:ac]).to eq(274.5)
      end

      it 'keeps it for every biometric parameter the parser reads' do
        argv = described_class::MEASUREMENTS.flat_map { |kind| ["--#{kind}", '82.5'] }
        options = parse(*argv)
        expect(described_class::MEASUREMENTS.map { |kind| options[kind] }).to all(eq(82.5))
      end

      it 'reaches the formulas as the centimetres they are published in' do
        millimetres = parse('--ac', '274.5')[:ac]
        expect(Biometry::Measurement.new(kind: :ac, mm: millimetres).cm).to eq(27.45)
      end
    end

    context 'when reported as a whole number' do
      it 'still reads it' do
        expect(parse('--ac', '274')[:ac]).to eq(274)
      end
    end

    context 'when not a number at all' do
      it 'raises a usage error naming the option, rather than weighing from a typo' do
        expect { parse('--ac', 'abc') }.to raise_error(Biometry::CLI::UsageError, /--ac/)
      end
    end

    context 'when the decimal itself is malformed' do
      it 'raises a usage error naming the option' do
        expect { parse('--ac', '274.5.5') }.to raise_error(Biometry::CLI::UsageError, /--ac/)
      end
    end
  end

  # The dating services already refuse a fractional cycle as :invalid_input.
  # The parser refuses it as a usage error before it gets that far, and the two
  # refusals must not drift into one accepting what the other rejects.
  describe 'a count of days' do
    { '--cycle' => :cycle, '--embryo-day' => :embryo_day }.each do |option, key|
      context "when #{option} is a whole number" do
        it 'reads it' do
          expect(parse(option, '3')[key]).to eq(3)
        end
      end

      context "when #{option} carries a decimal" do
        it 'raises a usage error naming the option, because it counts rather than measures' do
          expect { parse(option, '4.5') }.to raise_error(Biometry::CLI::UsageError, /#{option}/)
        end
      end
    end
  end
end
