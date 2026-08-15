# frozen_string_literal: true

require 'json'
require 'stringio'
require 'biometry/cli/main'

# Acceptance layer: what a user asking whether to move a due date sees.
#
#   biometry report --ga 32w0d --established-edd 2026-10-08 \
#                   --established-by lmp --scan-edd 2026-10-20
#
# Exit code, stdout and stderr as three separate expectations, as everywhere.
#
# The three flags go together and are optional together: a report that does not
# ask about redating must be exactly the report it was before this section
# existed, so nobody who never types them sees the page change.
#
# No threshold, band edge, zone bound or caveat is retyped here. The dates in
# the argv are chosen by working backwards from a band's own window, because
# these constants were reconstructed rather than transcribed and a second copy
# in a spec would agree with a transposition rather than catch it.
RSpec.describe 'the biometry report redating' do
  def reference_date = Date.new(2026, 8, 13)

  def manifest = ComposedReport.redating_manifest

  def zoned = ComposedReport.band_with_zone

  def caveated = ComposedReport.band_with_caveat

  # The inverse of the service's indexing: the established EDD that puts the
  # indexing gestation where the example needs it.
  def established_edd(ga_days) = ComposedReport.established_edd(ga_days, at: reference_date)

  # `redating: false` drops the three flags and changes nothing else, which is
  # what lets a spec ask what their presence did to the rest of the page.
  def argv(ga_days: ComposedReport.inside_band(caveated), discrepancy: 12, via: 'lmp',
           redating: true, **extra)
    edd = established_edd(ga_days)
    %w[report --ga 32w0d --bpd 82 --hc 291 --ac 274 --fl 62] +
      ['--at', reference_date.to_s] +
      redating_flags(edd, discrepancy, via, redating) +
      extra.flat_map { |flag, value| ["--#{flag}", value].compact }
  end

  def redating_flags(edd, discrepancy, via, asked)
    return [] unless asked

    ['--established-edd', edd.to_s, '--established-by', via,
     '--scan-edd', (edd + discrepancy).to_s]
  end

  def call(argv)
    stdout = StringIO.new
    stderr = StringIO.new
    status = Biometry::CLI::Main.new(stdout: stdout, stderr: stderr).call(argv)
    [status, stdout.string, stderr.string]
  end

  def out(*arguments) = call(*arguments)[1]

  # One section: the heading and the indented lines under it, up to the next
  # heading. `Dating` does not match `Redating`, the R being capital.
  def block(heading, text)
    body = text.lines.drop_while { |line| !line.start_with?(heading) }
    return '' if body.empty?

    [body.first, *body.drop(1).take_while { |line| !line.match?(/\A\S/) }].join
  end

  def section(text) = block('Redating', text)

  def dating_section(text) = block('Dating', text)

  def squeezed(text) = text.gsub(/\s+/, ' ').strip

  def classification
    /\b(sga|iugr|macrosom\w*|restrict\w*|abnormal|normal|pre-?term|post-?term)\b/i
  end

  def rows_and_values(text)
    ComposedReport.quoted_caveats
                  .reduce(squeezed(text)) { |page, quote| page.sub(squeezed(quote), '') }
  end

  context 'when a report asks about no redating at all' do
    it 'exits 0 and prints the page it printed before this section existed' do
      status, page, err = call(%w[report --ga 32w0d --at 2026-08-13 --ac 274 --hc 291 --fl 62])
      expect(status).to eq(0)
      expect(page).not_to include('Redating')
      expect(err).to be_empty
    end
  end

  context 'when an established date, its derivation and a scan date are given' do
    it 'exits 0, prints the section on stdout and says nothing on stderr' do
      status, page, err = call(argv)
      expect(status).to eq(0)
      expect(section(page)).not_to be_empty
      expect(err).to be_empty
    end

    it 'prints the discrepancy against the threshold that applied' do
      expect(section(out(argv))).to include('12', caveated[:threshold_days].to_s)
    end

    it 'names the band the threshold came from' do
      expect(section(out(argv))).to include(caveated[:id])
    end

    it 'keeps the established date rather than reporting a revised one' do
      expect(section(out(argv))).to include('keep')
    end

    # Asserted as such rather than through a proxy string: the same command
    # with the three flags dropped renders the same Dating section, byte for
    # byte. That catches a row that moved, a column that repadded, or a
    # derivation quietly fed from the established date — which is a thing this
    # command must not do. `--lmp` is supplied because a derivation with no
    # input of its own refuses, and two identical refusals would compare equal
    # without either section ever having rendered a date.
    it 'leaves the dating section it is about untouched' do
      supplied = { lmp: '2026-01-01' }
      expect(dating_section(out(argv(**supplied)))).to include('LMP (28d cycle)')
      expect(dating_section(out(argv(**supplied))))
        .to eq(dating_section(out(argv(redating: false, **supplied))))
    end

    # The established date is the one already in the chart. It is measured
    # against, never derived from: an LMP reconstructed backwards from it would
    # invent an input the caller never gave, under a cycle assumption they
    # never stated, and would collapse the two dates this slice exists to keep
    # apart.
    it 'feeds no derivation from the established date the caller supplied' do
      expect(dating_section(out(argv)))
        .to include('insufficient data', 'requires lmp, reference_date')
    end
  end

  # The band is chosen by the gestation being tested, and the report says which
  # gestation that was — it is not the --ga the growth charts were read at, and
  # a reader must be able to tell.
  context 'when --ga differs from the gestation the established date implies' do
    it 'indexes the band on the established date rather than on --ga' do
      page = out(argv(ga_days: ComposedReport.inside_band(zoned)))
      expect(section(page)).to include(zoned[:id])
    end
  end

  context 'when the discrepancy falls in the discretionary zone' do
    def zone = zoned[:discretionary_zone]

    def deferred
      out(argv(ga_days: ComposedReport.inside_band(zoned), discrepancy: zone[:from_days] + 1))
    end

    it 'says the guideline defers rather than printing a bare yes or no' do
      expect(section(deferred)).to include('discretionary')
    end

    it 'prints the zone the deferral came from' do
      expect(section(deferred)).to include(zone[:from_days].to_s, zone[:to_days].to_s)
    end
  end

  # A pregnancy dated by IVF is not redated by ultrasound. `--established-by
  # transfer` is what says so, which is why the flag is required rather than
  # inferred from whichever dating flags happen to be present.
  context 'when the established date came from an embryo transfer' do
    def ivf = out(argv(via: 'transfer'))

    it 'keeps the established date' do
      expect(section(ivf)).to include('keep')
    end

    it 'names the rule rather than a threshold' do
      expect(section(ivf)).to match(/ivf/i)
    end

    it 'prints no band it never selected' do
      expect(section(ivf)).not_to include(caveated[:id])
    end
  end

  # Quoted from the guideline, printed in full. It warns what redating risks
  # and labels no fetus, which is what makes it the one thing on the page
  # allowed to carry that wording.
  context 'when the band carries the third-trimester caveat' do
    def caveat_text = manifest.dig(:caveats, :third_trimester, :text)

    it 'prints the caveat word for word' do
      expect(squeezed(out(argv))).to include(squeezed(caveat_text))
    end

    it 'keeps every row and value free of a classification even so' do
      expect(rows_and_values(out(argv))).not_to match(classification)
    end
  end

  context 'when the gestation sits near a band edge and the answer would differ' do
    def straddling
      out(argv(ga_days: ComposedReport.edge_days(zoned[:ga_from]),
               discrepancy: zoned[:discretionary_zone][:from_days] + 1))
    end

    it 'discloses the neighbouring band' do
      expect(section(straddling)).to include(ComposedReport.band_before(zoned)[:id])
    end
  end

  describe 'the JSON counterpart' do
    def document(**overrides) = JSON.parse(out(argv(**overrides, json: nil)))

    it 'carries no entry when no redating was asked for' do
      page = out(%w[report --ga 32w0d --at 2026-08-13 --ac 274 --hc 291 --fl 62 --json])
      expect(JSON.parse(page)).not_to have_key('redating')
    end

    it 'carries the recommendation, the discrepancy and the threshold apart' do
      expect(document.fetch('redating').values_at('recommendation', 'discrepancy_days',
                                                  'threshold_days'))
        .to eq(['keep', 12, caveated[:threshold_days]])
    end

    it 'carries the established date unrevised beside the proposed one' do
      edd = established_edd(ComposedReport.inside_band(caveated))
      expect(document.fetch('redating').values_at('established_edd', 'proposed_edd'))
        .to eq([edd.to_s, (edd + 12).to_s])
    end

    it 'stays undecorated, with nothing but the document on that stream' do
      expect(document['studies'].first).to have_key('growth')
    end
  end

  # Three flags, one request. Two of them alone describe a comparison with
  # nothing to compare against, and guessing the third is guessing at the
  # clinical question rather than at a formatting detail.
  describe 'the flags it requires together' do
    def partial(*flags) = call(%w[report --ga 32w0d --at 2026-08-13 --ac 274] + flags)

    it 'exits 2 when an established date arrives without a scan date' do
      status, page, err = partial('--established-edd', '2026-10-08', '--established-by', 'lmp')
      expect(status).to eq(2)
      expect(page).to be_empty
      expect(err).to include('--scan-edd')
    end

    it 'exits 2 when a scan date arrives without an established date' do
      status, _, err = partial('--scan-edd', '2026-10-20', '--established-by', 'lmp')
      expect(status).to eq(2)
      expect(err).to include('--established-edd')
    end

    it 'exits 2 when the derivation is not named, the IVF rule turning on it' do
      status, _, err = partial('--established-edd', '2026-10-08', '--scan-edd', '2026-10-20')
      expect(status).to eq(2)
      expect(err).to include('--established-by')
    end
  end

  # Every date the command takes reads the same way, so a typo in one of these
  # is the usage error a typo in --lmp is rather than a substituted default.
  %w[--established-edd --scan-edd].each do |flag|
    context "when #{flag} is not a date" do
      it 'exits 2, keeps stdout clean and names the option and the value' do
        status, page, err = call(argv + [flag, 'notadate'])
        expect(status).to eq(2)
        expect(page).to be_empty
        expect(err).to include(flag, 'notadate')
      end
    end
  end

  # A derivation this library has no vocabulary for is a user error, not a bug
  # and not a reason to abandon the rest of the page.
  context 'when the derivation named is not one this library knows' do
    it 'exits 0 and refuses that section alone, naming what it does know' do
      status, page, err = call(argv(via: 'martian'))
      expect(status).to eq(0)
      expect(section(page)).to include('martian', 'lmp')
      expect(err).to be_empty
    end
  end
end
