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

  # A document carries one entry per study, and measurement flags describe one.
  def only_study(out) = JSON.parse(out)['studies'].first

  def citation(name) = ComposedReport.manifest(name)[:source][:citation]

  def squeezed(text) = text.gsub(/\s+/, ' ').strip

  # The page with the quoted guideline text taken out of it. See the note on
  # the classification example below.
  def rows_and_values(text)
    ComposedReport.quoted_caveats
                  .reduce(squeezed(text)) { |page, quote| page.sub(squeezed(quote), '') }
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
      expect(growth_rows(out).length).to eq(8)
    end

    # One paper, two dispersion figures, no erratum. The library's job is to
    # put the disagreement in front of the reader rather than to pick a side,
    # and here the two sides are a row apart on the same page: the same weight
    # at the same week, about a percentile apart.
    it 'prints both Hadlock 1991 dispersion figures as their own rows' do
      _, out, = call(base)
      labels = growth_rows(out).filter_map { |line| line[/Hadlock 1991 \(\w+\)/] }
      expect(labels).to eq(['Hadlock 1991 (equation)', 'Hadlock 1991 (table)'])
    end

    it 'reads the same weight two ways, which is the disagreement it exists to show' do
      _, out, = call(base)
      centiles = growth_rows(out).grep(/Hadlock 1991/)
                                 .map { |line| line[/\d+(?:st|nd|rd|th)\b/] }
      expect(centiles.uniq.length).to eq(2)
    end

    it 'cites the one paper behind both rows once' do
      _, out, = call(base)
      expect(out.lines.count { |line| line.include?(citation('hadlock_1991')) }).to eq(1)
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

    # The prohibition is on classifying the pregnancy in front of you, in a
    # value or in a row. A caveat quoted from a guideline, warning what
    # redating risks, labels nobody and prints verbatim — so the quotation is
    # taken out and everything else is held exactly as strictly as before.
    # Slice 2's own acceptance spec is where the quoted case is asserted.
    it 'prints numbers and their sources, never a classification' do
      _, out, = call(base)
      expect(out).to include('prescriptive')
      expect(rows_and_values(out))
        .not_to match(/\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i)
    end
  end

  # A row is on the page and the paper behind it is not. The reader who wants
  # to check the standard that just refused them has nothing to look up, and
  # which paper a chart is does not depend on whether this request could be
  # answered from it.
  context 'when every chart refuses the gestation' do
    def refused = call(base(ga: '41w0d'))

    it 'exits 0 and prints a row for each of the five charts' do
      status, out, err = refused
      expect(status).to eq(0)
      expect(growth_rows(out).length).to eq(5)
      expect(err).to be_empty
    end

    %w[intergrowth21 hadlock_1991 who nichd].each do |name|
      it "cites #{name}, whose row refused" do
        _, out, = refused
        expect(out).to include(citation(name))
      end
    end

    it 'cites the paper behind the weights it did produce as well' do
      _, out, = refused
      expect(out).to include(citation('hadlock_1985'))
    end

    # Completed weeks on the two tables, exact weeks on the three closed
    # forms: two conventions for one gestation, and the block a reader is
    # looking at should not spell 41 weeks two ways.
    it 'names the gestation the same way on every row' do
      _, out, = refused
      expect(growth_rows(out).map { |line| line[/given [\d.]+/] }.uniq).to eq(['given 41'])
    end

    context 'when the gestation is not a whole number of weeks' do
      it 'keeps the fraction, reporting two conventions rather than four spellings' do
        _, out, = call(base(ga: '41w3d'))
        expect(growth_rows(out).map { |line| line[/given [\d.]+/] }.uniq)
          .to contain_exactly('given 41.4', 'given 41')
      end
    end
  end

  # WHO's combined table tops out at 97.5. Rounding the open bracket to 98
  # names a column that does not exist; a published bound is not a computed
  # value and is not rounded.
  context 'when the weight falls above every chart\'s outermost column' do
    def huge(**overrides)
      call(%w[report --ga 32w0d --at 2026-08-13 --lmp 2026-01-01
              --bpd 110 --hc 400 --ac 400 --fl 90] + overrides.flat_map { |k, v| ["--#{k}", v] })
    end

    it 'prints the centile WHO published rather than the one it rounds to' do
      _, out, = huge
      expect(out).to include('above 97.5th')
      expect(out).not_to include('above 98th')
    end

    it 'brackets NICHD against the 97th, which is the column it publishes' do
      _, out, = huge
      expect(out).to include('above 97th')
    end

    # Both closed forms and both tables now say the one thing one way.
    it 'spells every open statement in words, with no comparison symbols' do
      _, out, = huge
      expect(growth_rows(out).join).to include('above 99th')
      expect(growth_rows(out).join).not_to match(/[<>]/)
    end

    it 'brackets a sex-specific chart against the columns that chart published' do
      _, out, = huge(sex: 'female')
      expect(out).to match(/WHO \(female\).*above 95th/)
    end
  end

  # 7.4% is the EFW formula's SD. Standing in a column of its own beside a
  # percentile it reads as the percentile's, whose uncertainty is dominated by
  # the chart's dispersion and is roughly twice as wide.
  context 'when a row carries both a weight and a percentile' do
    it 'renders the weight and its SD as one field, with no column between' do
      _, out, = call(base)
      expect(growth_rows(out).join).to include('1,852 g ±7.4%')
    end

    it 'keeps the SD a column away from the centile it does not describe' do
      _, out, = call(base)
      expect(growth_rows(out).join).to match(/1,852 g ±7\.4% {2,}\d+\w+/)
    end

    it 'says the SD is the weight formula\'s and excludes the chart\'s dispersion' do
      _, out, = call(base)
      note = out.lines.grep(/SD/).join
      expect(note).to match(/formula/i).and match(/chart/i)
    end
  end

  # A default presented as something the caller supplied sends them looking for
  # where they typed it.
  context 'when no cycle length was supplied and the dating cannot be derived' do
    it 'lists only the inputs that were actually supplied' do
      _, out, = call(%w[report --ga 32w0d --at 2026-08-13 --ac 274 --hc 291 --fl 62])
      expect(out).to include('requires lmp, reference_date; given reference_date')
    end

    it 'names a cycle length the caller did type' do
      _, out, = call(%w[report --ga 32w0d --at 2026-08-13 --cycle 35 --ac 274])
      expect(out).to include('given cycle_length, reference_date')
    end

    # The assumption still applies; it is reported as the estimate's own
    # parameter, where it is true, rather than as an input that arrived.
    it 'still assumes 28 days when it can date the pregnancy' do
      _, out, = call(%w[report --ga 32w0d --at 2026-08-13 --lmp 2026-01-01 --ac 274])
      expect(out).to include('LMP (28d cycle)', 'EDD 2026-10-08')
    end
  end

  context 'when a race or ethnicity is supplied' do
    it 'prints that NICHD chart alone, so the fan-out is a default and not a flag' do
      _, out, = call(base + %w[--stratum white])
      expect(growth_rows(out).length).to eq(5)
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
      expect(only_study(out)['growth'].length).to eq(8)
    end

    # A consumer storing `hadlock_1991` would be storing one of two figures
    # with no record of which, so the variant is part of the standard's name
    # rather than a note beside it.
    it 'names each Hadlock variant in the standard field' do
      _, out, = call(base + %w[--json])
      standards = only_study(out)['growth'].map { |row| row['standard'] }
      expect(standards)
        .to eq(%w[intergrowth21 hadlock_1991_equation hadlock_1991_table who
                  nichd nichd nichd nichd])
    end

    it 'carries the unrounded centile the table rounded' do
      _, out, = call(base + %w[--json])
      values = only_study(out)['growth'].map { |row| row.dig('percentile', 'value') }
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

  # Scanners report a millimetre to one decimal place. A value refused for its
  # decimal is one the user rounds by hand before the formula ever sees it, and
  # the rounding then happens where nothing records that it happened.
  context 'when a measurement carries a decimal' do
    it 'exits 0, prints the report on stdout and says nothing on stderr' do
      status, out, err = call(base(ac: '274.5'))
      expect(status).to eq(0)
      expect(out).to include('NICHD (white)')
      expect(err).to be_empty
    end

    it 'prints the centimetres the decimal converts to' do
      _, out, = call(base(ac: '274.5'))
      expect(out).to include('AC 27.45')
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
