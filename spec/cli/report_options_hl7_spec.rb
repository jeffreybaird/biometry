# frozen_string_literal: true

require 'biometry/cli/report_options'

# Unit layer: argv in, values out. The parser learns that a message was asked
# for and where it is; it does not open it. Reading a file is the command's
# job, and a parser that stats the filesystem is a parser that cannot be tested
# without one.
RSpec.describe Biometry::CLI::ReportOptions do
  def parse(*argv) = described_class.parse(%w[--ga 32w0d] + argv)

  describe '--hl7' do
    it 'reads the path it was given' do
      expect(parse('--hl7', 'message.hl7')[:hl7]).to eq('message.hl7')
    end

    # Nothing here checks that the file is there. A path that does not exist is
    # a value the command reports on, not a parse failure.
    it 'reads a path that does not exist, leaving the reading to the command' do
      expect(parse('--hl7', 'no/such/message.hl7')[:hl7]).to eq('no/such/message.hl7')
    end

    it 'supplies no measurement of its own' do
      options = parse('--hl7', 'message.hl7')
      expect(described_class::MEASUREMENTS.map { |kind| options[kind] }).to all(be_nil)
    end

    # The gestation is still the caller's to state. Nothing in a message this
    # library reads decides which of the disagreeing derivations to date by.
    it 'does not relieve the caller of naming the gestation' do
      expect { described_class.parse(%w[--hl7 message.hl7]) }
        .to raise_error(Biometry::CLI::UsageError, /--ga/)
    end
  end

  # Two sources for one measurement, and preferring either one silently weighs
  # the fetus from a number the caller did not think they had supplied.
  describe '--hl7 alongside a measurement flag' do
    Biometry::CLI::ReportOptions::MEASUREMENTS.each do |kind|
      context "when --#{kind} is given as well" do
        it 'raises a usage error naming both, rather than choosing between them' do
          expect { parse('--hl7', 'message.hl7', "--#{kind}", '274') }
            .to raise_error(Biometry::CLI::UsageError, /--hl7/)
          expect { parse('--hl7', 'message.hl7', "--#{kind}", '274') }
            .to raise_error(Biometry::CLI::UsageError, /--#{kind}/)
        end
      end
    end

    context 'when every measurement flag is given as well' do
      it 'raises a usage error' do
        argv = described_class::MEASUREMENTS.flat_map { |kind| ["--#{kind}", '82'] }
        expect { parse('--hl7', 'message.hl7', *argv) }
          .to raise_error(Biometry::CLI::UsageError, /--hl7/)
      end
    end
  end
end
