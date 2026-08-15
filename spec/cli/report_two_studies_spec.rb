# frozen_string_literal: true

require 'json'
require 'stringio'
require 'tmpdir'
require 'biometry/cli/main'

# Acceptance layer: a message reporting two studies, typed at the command line.
#
# Both studies are reported, each at the gestation on its own date:
#
#     GA at a study = the GA supplied - (the reference date - that study's date)
#
# The alternative — reading both tables at the gestation the caller typed —
# prints, for a study taken weeks earlier, a percentile wrong by exactly the
# days between them, with a correct-looking date beside it. The two studies in
# the fixture report identical biometry, so identical tables are precisely the
# symptom of that error.
#
# Every expected gestation here is derived from the fixture dates rather than
# typed, so the arithmetic is stated once and this file cannot agree with a
# transcription of it.
RSpec.describe 'the biometry report command reading a message of two studies' do
  let(:directory) { Dir.mktmpdir('biometry-hl7') }

  after { FileUtils.remove_entry(directory) }

  def message_file(contents = Hl7Messages.two_full_studies)
    File.join(directory, 'message.hl7').tap { |path| File.write(path, contents) }
  end

  def call(*extra, contents: Hl7Messages.two_full_studies)
    stdout = StringIO.new
    stderr = StringIO.new
    argv = %w[report --ga 32w0d --at 2026-08-13 --sex female --hl7] +
           [message_file(contents)] + extra
    status = Biometry::CLI::ReportCommand
             .new(stdout: stdout, stderr: stderr, loinc: Hl7Messages::MAPPING).call(argv)
    [status, stdout.string, stderr.string]
  end

  def document(*extra, **options) = JSON.parse(call(*extra, '--json', **options)[1])

  def supplied = Biometry::GestationalAge.from(weeks: 32)

  def ga_at(date) = ComposedReport.ga_at(date, supplied: supplied)

  def headings(out) = out.gsub(/\e\[[0-9;]*m/, '').lines.select { |l| l.start_with?('Growth') }

  context 'when the message reports two studies' do
    it 'exits 0, prints both tables on stdout and says nothing on stderr' do
      status, out, err = call
      expect(status).to eq(0)
      expect(headings(out).length).to eq(2)
      expect(err).to be_empty
    end

    it 'heads each table with the date that study was performed' do
      _, out, = call
      expect(headings(out).first).to include(Hl7Messages::EARLIER_SCAN_DATE.iso8601)
      expect(headings(out).last).to include(Hl7Messages::SCAN_DATE.iso8601)
    end

    # The shift, on the page. 32w0d was supplied for the reference date; the
    # earlier study is read six weeks and one day back from it.
    it 'reads each study at the gestation on its own date' do
      _, out, = call
      expect(headings(out).first).to include("GA #{ga_at(Hl7Messages::EARLIER_SCAN_DATE)}")
      expect(headings(out).last).to include("GA #{ga_at(Hl7Messages::SCAN_DATE)}")
    end
  end

  describe 'the document it emits' do
    it 'carries one entry per study, dated' do
      expect(document['studies'].map { |study| study['date'] })
        .to eq([Hl7Messages::EARLIER_SCAN_DATE.iso8601, Hl7Messages::SCAN_DATE.iso8601])
    end

    it 'carries the gestation each was read at, in days' do
      expect(document['studies'].map { |study| study.dig('gestational_age', 'days') })
        .to eq([ga_at(Hl7Messages::EARLIER_SCAN_DATE).days, ga_at(Hl7Messages::SCAN_DATE).days])
    end

    # Identical biometry in both studies: same weights, and chart readings that
    # differ only because the gestations do. Equal readings here would mean the
    # shift was never applied.
    it 'weighs them identically and reads them differently' do
      weights, percentiles = %w[weight percentile].map do |key|
        document['studies'].map { |study| study['growth'].map { |row| row.dig(key, 'value') } }
      end
      expect(weights.first).to eq(weights.last)
      expect(percentiles.first).not_to eq(percentiles.last)
    end
  end

  # The realistic way to reach an out-of-range gestation: a message carrying a
  # study from months ago. The adapters refuse it as they refuse any gestation
  # outside a published window, and the study keeps its table.
  context 'when one study falls outside every chart published window' do
    def refused = call(contents: Hl7Messages.two_studies_one_beyond_the_charts)

    it 'exits 0, because the other study could be reported' do
      expect(refused.first).to eq(0)
    end

    it 'still prints both tables' do
      expect(headings(refused[1]).length).to eq(2)
    end

    it 'carries a refusal on the distant study rather than dropping it' do
      studies = JSON.parse(call('--json',
                                contents: Hl7Messages.two_studies_one_beyond_the_charts)[1])
      errors = studies['studies'].first['growth'].map { |row| row.dig('error', 'tag') }
      expect(errors).to all(eq('out_of_range'))
    end
  end

  # A study nothing could be read from does not become a table with no rows in
  # it. It leaves the report and says so on stderr.
  context 'when one study yielded no measurement at all' do
    it 'exits 0, prints the study it could read and names the other on stderr' do
      status, out, err = call(contents: Hl7Messages.two_studies_one_unreadable)
      expect(status).to eq(0)
      expect(headings(out).length).to eq(1)
      expect(err).to include(Hl7Messages::UNMAPPED)
    end
  end
end
