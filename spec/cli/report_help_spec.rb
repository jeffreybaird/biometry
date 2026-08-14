# frozen_string_literal: true

require 'stringio'
require 'biometry/cli/main'
require 'biometry/cli/report_options'

# Acceptance layer: `biometry report --help` is the whole of this library's
# documentation, so what it has to contain is a contract and what it says is
# copy. Every assertion here is a property — a quantity named in words, a unit,
# a form, a permitted value — never a sentence, so the prose can be rewritten
# without the suite reading the rewrite as a regression.
#
# Two properties are read from the source rather than retyped: the flags the
# parser accepts, and the strata WHO and NICHD publish. A second hand-kept list
# is the half of a help page that rots, and a help page that is wrong is worse
# than one that is thin.
RSpec.describe 'the biometry report help' do
  # Officious flags print and exit inside OptionParser, and the help flag is
  # trivially accepted by whatever answers it, so neither is part of the pair.
  def officious = %w[--help --version].freeze

  biometric_flags = Biometry::CLI::ReportOptions::MEASUREMENTS.map { |kind| "--#{kind}" }
  flags = %w[--ga --at --json --lmp --cycle --transfer --embryo-day --sex --stratum
             --established-edd --established-by --scan-edd] + biometric_flags

  # The names the report already refuses to print. A help page that explains
  # the command may not introduce the vocabulary the output excludes.
  def classification
    /\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i
  end

  # Help is a result, so it comes back as a status and a string on the stream
  # the command was handed. A command that exits the process from inside its
  # parser would take the runner down with it, so the exit is caught here and
  # reported as the example failure it is.
  def call(argv)
    stdout = StringIO.new
    stderr = StringIO.new
    status = statuses(argv, stdout, stderr)
    [status, stdout.string, stderr.string]
  end

  def statuses(argv, stdout, stderr)
    Biometry::CLI::Main.new(stdout: stdout, stderr: stderr).call(argv)
  rescue SystemExit => e
    raise "exited the process with status #{e.status} instead of returning it"
  end

  # One flag, one entry: the lines from the one naming the flag up to the next
  # flag. Asserting inside the entry is what stops "each of the four says
  # millimetres" from passing on a stray mention elsewhere on the page.
  def entry(flag)
    body = help.lines.drop_while { |line| !names?(line, flag) }
    return '' if body.empty?

    [body.first, *body.drop(1).take_while { |line| !flag?(line) }].join
  end

  def names?(line, flag) = line.strip.match?(/\A#{Regexp.escape(flag)}\b/)

  def flag?(line) = line.strip.start_with?('--')

  # A round trip rather than a second list. A flag the page names and the
  # parser refuses is a lie in the documentation; reading it back through the
  # parser is the only check that cannot fall out of date.
  def parses?(flag)
    Biometry::CLI::ReportOptions.parse(['--ga', '32w0d', flag, '1'])
    true
  rescue Biometry::CLI::UsageError
    true
  rescue OptionParser::ParseError
    false
  end

  def stratification(standard) = ComposedReport.manifest(standard)[:stratification][:values]

  let(:help) { call(%w[report --help])[1] }

  describe 'asking the subcommand for help' do
    it 'exits 0, prints the help on stdout and says nothing on stderr' do
      status, out, err = call(%w[report --help])
      expect(status).to eq(0)
      expect(out).not_to be_empty
      expect(err).to be_empty
    end

    # Help is a result the caller asked for, so it returns a status like every
    # other outcome and writes to the stream it was handed.
    it 'returns rather than exiting the process from inside the parser' do
      expect { call(%w[report --help]) }.not_to raise_error
    end

    it 'does not go looking for a gestation it was not asked to report on' do
      _, out, err = call(%w[report --help])
      expect(err).not_to include('--ga,')
      expect(out).not_to be_empty
    end
  end

  describe 'the flags it lists' do
    flags.each do |flag|
      it "documents #{flag}" do
        expect(entry(flag)).not_to be_empty
      end
    end

    it 'lists no flag the parser would refuse' do
      named = help.scan(/--[a-z][a-z-]*/).uniq - officious
      expect(named.reject { |flag| parses?(flag) }).to be_empty
    end
  end

  describe 'the biometric flags' do
    { bpd: /biparietal diameter/i, hc: /head circumference/i,
      ac: /abdominal circumference/i, fl: /femur length/i }.each do |kind, name|
      it "says in words what --#{kind} measures, rather than leaving the abbreviation" do
        expect(entry("--#{kind}")).to match(name)
      end

      # `MM` as an argument placeholder is not the unit spelled out. A reader
      # who does not already know the unit is the reader this line is for.
      it "says --#{kind} is in millimetres" do
        expect(entry("--#{kind}")).to match(/millimetre|millimeter/i)
      end
    end
  end

  describe 'the gestation' do
    it 'says what --ga means and shows the form it is written in' do
      expect(entry('--ga')).to match(/gestation/i).and include('32w0d')
    end
  end

  describe 'the date flags' do
    { '--lmp' => /last menstrual period/i, '--transfer' => /transfer/i,
      '--at' => /reference date/i }.each do |flag, meaning|
      it "says which date #{flag} is" do
        expect(entry(flag)).to match(meaning)
      end

      it "says #{flag} is written as an ISO date" do
        expect(entry(flag)).to match(/iso|yyyy-mm-dd/i)
      end
    end
  end

  describe 'the counted flags' do
    it 'says --cycle is in days and names the assumption made without it' do
      expect(entry('--cycle')).to match(/\bdays?\b/i).and include('28').and match(/assum|default/i)
    end

    it 'says --embryo-day is in days' do
      expect(entry('--embryo-day')).to match(/\bdays?\b/i)
    end

    # Day 3 and day 5 are the two a reader will type, and which stage each is
    # cannot be inferred from the number.
    it 'says day 3 is a cleavage embryo and day 5 a blastocyst' do
      expect(entry('--embryo-day')).to match(/3[^\n]{0,60}cleavage|cleavage[^\n]{0,60}3/i)
      expect(entry('--embryo-day')).to match(/5[^\n]{0,60}blastocyst|blastocyst[^\n]{0,60}5/i)
    end
  end

  describe 'the chart flags' do
    it 'names every sex WHO published, read from the manifest' do
      missing = stratification('who').reject { |value| entry('--sex').match?(/\b#{value}\b/i) }
      expect(missing).to be_empty
    end

    it 'names every stratum NICHD published, read from the manifest' do
      missing = stratification('nichd').reject { |value| entry('--stratum').match?(/\b#{value}\b/i) }
      expect(missing).to be_empty
    end

    # The manifest is explicit that the field is self-reported and never
    # inferred. A help page that omits that invites the user to supply it from
    # a surname or a photograph.
    it 'says the NICHD stratum is self-reported and never inferred' do
      expect(entry('--stratum')).to match(/self-report|self-identified/i)
      expect(entry('--stratum')).to match(/(never|not|do not|don't)[^\n]{0,30}infer/i)
    end

    it 'says omitting --stratum prints all four charts' do
      expect(entry('--stratum')).to match(/\bfour\b/i).and match(/chart/i)
    end
  end

  # Slice 2. The three that decide whether a due date moves, and the one place
  # a reader learns that naming the derivation is what triggers the IVF rule.
  describe 'the redating flags' do
    def derivations
      Biometry::Services::Dating::AllDerivations::OFFERED +
        Biometry::Services::Dating::AllDerivations::DEFERRED
    end

    { '--established-edd' => /established/i, '--scan-edd' => /scan|ultrasound/i }
      .each do |flag, meaning|
      it "says which date #{flag} is" do
        expect(entry(flag)).to match(meaning)
      end

      it "says #{flag} is written as an ISO date" do
        expect(entry(flag)).to match(/iso|yyyy-mm-dd/i)
      end
    end

    # A second hand-kept list is the half of a help page that rots, so the
    # values are read from the derivations the library actually names.
    it 'names every derivation --established-by accepts' do
      missing = derivations.reject { |value| entry('--established-by').match?(/\b#{value}\b/i) }
      expect(missing).to be_empty
    end

    # The flag looks like documentation of where a date came from. It is the
    # switch that decides whether the pregnancy can be redated at all.
    it 'says a pregnancy dated by IVF is never redated by ultrasound' do
      expect(entry('--established-by')).to match(/ivf|transfer/i)
      expect(entry('--established-by')).to match(/(never|not)[^\n]{0,40}redat/i)
    end

    it 'says the three go together' do
      expect(entry('--established-edd')).to match(/together|all three|alongside|requires/i)
    end
  end

  describe 'the two things a reader cannot infer from the flags' do
    # Three weights on the page look like disagreement until you know a chart
    # may only be read with the formula it was built on.
    it 'says formula and chart are paired, so three weights appear rather than one' do
      expect(help).to match(/pair/i).and match(/\bthree\b/i)
    end

    it 'says --json carries the values the table rounded' do
      expect(entry('--json')).to match(/unrounded|full precision|not rounded/i)
      expect(entry('--json')).to match(/table|round/i)
    end
  end

  it 'explains the command without ever naming a classification' do
    expect(help).not_to match(classification)
  end
end
