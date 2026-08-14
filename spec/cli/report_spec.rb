# frozen_string_literal: true

require 'json'
require 'stringio'
require 'biometry/cli/main'

# A stream that claims to be a terminal, so the two halves of the CLI contract
# can be asserted without a pty. TTY-ness is the command's to detect and the
# renderer's to be told; nothing under presentation/ sniffs a global.
class TerminalIO < StringIO
  def tty? = true
end

# Acceptance layer: what a user typing the command sees. Exit code, stdout and
# stderr as three separate expectations.
#
# stdout carries the result — the thing you would pipe into another program.
# stderr carries everything else. `--json` goes to stdout undecorated with
# nothing else on that stream.
RSpec.describe 'the biometry report command' do
  def base(at: '2026-08-13', ga: '32w0d', ac: '274', sex: 'female')
    argv = %w[report --bpd 82 --hc 291 --fl 62
              --lmp 2026-01-01 --cycle 28 --transfer 2026-01-17 --embryo-day 5]
    { '--ga' => ga, '--ac' => ac, '--sex' => sex, '--at' => at }.each do |option, value|
      argv += [option, value] if value
    end
    argv
  end

  def call(argv, stdout: StringIO.new)
    stderr = StringIO.new
    status = Biometry::CLI::Main.new(stdout: stdout, stderr: stderr).call(argv)
    [status, stdout.string, stderr.string]
  end

  def growth_rows(out)
    out.gsub(/\e\[[0-9;]*m/, '').lines.grep(/^\s+(INTERGROWTH|Hadlock 1991|WHO|NICHD)/)
  end

  context 'when given a gestation and a full set of measurements' do
    it 'exits 0, prints the report on stdout and says nothing on stderr' do
      status, out, err = call(base)
      expect(status).to eq(0)
      expect(out).to include('NICHD (white)')
      expect(err).to be_empty
    end

    it 'compares every chart, NICHD fanned out to its four' do
      _, out, = call(base)
      expect(growth_rows(out).length).to eq(7)
    end

    it 'prints three distinct weights, because formula and chart are paired' do
      _, out, = call(base)
      expect(out).to include('1,697 g', '1,852 g', '1,834 g')
    end

    it 'prints the derivations it can date by and the ones it refuses' do
      _, out, = call(base)
      expect(out).to include('EDD 2026-10-08')
      expect(out).to match(/CRL\s+unavailable/)
    end

    it 'prints numbers and their sources, never a classification' do
      _, out, = call(base)
      expect(out).to include('prescriptive')
      expect(out)
        .not_to match(/\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i)
    end
  end

  context 'when a race or ethnicity is supplied' do
    it 'prints that NICHD chart alone, so the fan-out is a default and not a flag' do
      _, out, = call(base + %w[--stratum white])
      expect(growth_rows(out).length).to eq(4)
      expect(out).to include('NICHD (white)')
    end
  end

  context 'when a stratum the standard does not publish is supplied' do
    it 'exits 0 and refuses that row alone, naming what WHO publishes' do
      status, out, err = call(base(sex: 'martian'))
      expect(status).to eq(0)
      expect(out).to include('available: combined, female, male')
      expect(err).to be_empty
    end
  end

  context 'when --json is given' do
    it 'exits 0, puts a document on stdout and nothing on stderr' do
      status, out, err = call(base + %w[--json])
      expect(status).to eq(0)
      expect { JSON.parse(out) }.not_to raise_error
      expect(err).to be_empty
    end

    it 'puts nothing but the document on that stream' do
      _, out, = call(base + %w[--json])
      expect(JSON.parse(out)['growth'].length).to eq(7)
    end

    it 'carries the unrounded centile the table rounded' do
      _, out, = call(base + %w[--json])
      values = JSON.parse(out)['growth'].map { |row| row.dig('percentile', 'value') }
      expect(values).to include(a_value_within(1e-9).of(31.691353849999643))
    end

    it 'stays undecorated even when stdout is a terminal' do
      _, out, = call(base + %w[--json], stdout: TerminalIO.new)
      expect(out).not_to include("\e[")
      expect { JSON.parse(out) }.not_to raise_error
    end

    it 'dates the report as of today when no reference date is given' do
      _, out, = call(base(at: nil) + %w[--json])
      expect(JSON.parse(out)['dating'].first['reference_date']).to eq(Date.today.to_s)
    end
  end

  context 'when stdout is a terminal' do
    it 'colours the table' do
      _, out, = call(base, stdout: TerminalIO.new)
      expect(out).to include("\e[")
    end
  end

  context 'when stdout is piped' do
    it 'emits plain lines, with no colour and no progress indicator' do
      _, out, = call(base)
      expect(out).to include('NICHD (white)')
      expect(out).not_to include("\e[")
      expect(out).not_to include("\r")
    end
  end

  # Nothing was reportable: no measurements to weigh and no dates to derive
  # from. The refusals still print — that is the result — and the exit code
  # says an expected problem occurred.
  context 'when nothing the command was asked for could be reported' do
    it 'exits 1, still prints the refusals on stdout and stays off stderr' do
      status, out, err = call(%w[report --ga 32w0d --at 2026-08-13])
      expect(status).to eq(1)
      expect(out).to include('insufficient data')
      expect(err).to be_empty
    end
  end

  context 'when the gestation is missing' do
    it 'exits 2, keeps stdout clean and names the missing option on stderr' do
      status, out, err = call(%w[report --ac 274 --hc 291])
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('--ga')
    end
  end

  context 'when the gestation cannot be read' do
    it 'exits 2 and says what form it wanted' do
      status, out, err = call(base(ga: '32 weeks'))
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('32 weeks')
    end
  end

  context 'when a measurement is not a number' do
    it 'exits 2 rather than weighing a fetus from a typo' do
      status, out, err = call(base(ac: 'abc'))
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('--ac')
    end
  end

  # Every date the command takes reads the same way, so a typo in one is the
  # same usage error as a typo in another rather than a substituted default.
  %w[--lmp --at --transfer].each do |option|
    context "when #{option} is not a date" do
      it 'exits 2, keeps stdout clean and names the option on stderr' do
        status, out, err = call(base + [option, 'notadate'])
        expect(status).to eq(2)
        expect(out).to be_empty
        expect(err).to include(option)
      end
    end
  end

  context 'when an option is misspelled' do
    it 'exits 2 and names the option on stderr' do
      status, out, err = call(base + %w[--wieght])
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('--wieght')
    end
  end
end
