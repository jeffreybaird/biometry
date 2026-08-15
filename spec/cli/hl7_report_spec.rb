# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'biometry/cli/main'

# Acceptance layer: what a user who has a message from their ultrasound system
# sees when they type the command. Exit code, stdout and stderr as three
# separate expectations.
#
# What they see today is a refusal, and that is the behaviour under test. The
# LOINC mapping is not transcribed, so no message can yield a measurement, and
# the one thing this command must never do is answer with a report shaped like
# an answer. A user reading an empty growth table concludes something about the
# pregnancy; a user reading "this library has no LOINC mapping yet" concludes
# something about the library.
RSpec.describe 'the biometry report command reading an HL7 message' do
  let(:directory) { Dir.mktmpdir('biometry-hl7') }

  after { FileUtils.remove_entry(directory) }

  def message_file(contents = Hl7Messages.full)
    File.join(directory, 'message.hl7').tap { |path| File.write(path, contents) }
  end

  def call(*argv)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Biometry::CLI::Main.new(stdout: stdout, stderr: stderr).call(argv)
    [status, stdout.string, stderr.string]
  end

  def report(*extra) = call(*(%w[report --ga 32w0d --at 2026-08-13] + extra))

  context 'when given a message and this library has no LOINC mapping' do
    it 'exits 1, prints nothing on stdout and refuses on stderr' do
      status, out, err = report('--hl7', message_file)
      expect(status).to eq(1)
      expect(out).to be_empty
      expect(err).not_to be_empty
    end

    it 'names what is missing' do
      _, _, err = report('--hl7', message_file)
      expect(err).to include('loinc.yml')
    end

    # An error message says what failed and what the user can do about it. What
    # they can do today is type the four measurements themselves.
    it 'names the measurements a user can supply instead' do
      _, _, err = report('--hl7', message_file)
      named = Biometry::CLI::ReportOptions::MEASUREMENTS.select { |kind| err.include?("--#{kind}") }
      expect(named).not_to be_empty
    end

    it 'says nothing about a fetus it could not measure' do
      _, _, err = report('--hl7', message_file)
      expect(err).to include('loinc.yml')
      expect(err).not_to match(/\b(sga|iugr|macrosom\w*|abnormal|normal)\b/i)
    end

    # No stack trace on stdout, ever, and none on stderr either: a missing
    # transcription is an expected outcome rather than a bug.
    it 'reports it as a refusal rather than as a crash' do
      _, _, err = report('--hl7', message_file)
      expect(err).to include('loinc.yml')
      expect(err).not_to match(/\.rb:\d+/)
    end
  end

  context 'when given a path that is not there' do
    it 'exits 2, prints nothing on stdout and names the path on stderr' do
      status, out, err = report('--hl7', File.join(directory, 'absent.hl7'))
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('absent.hl7')
    end
  end

  context 'when given both a message and a measurement on the command line' do
    it 'exits 2, prints nothing on stdout and names both on stderr' do
      status, out, err = report('--hl7', message_file, '--ac', '274')
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('--hl7').and include('--ac')
    end
  end
end
