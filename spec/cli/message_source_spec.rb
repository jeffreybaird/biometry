# frozen_string_literal: true

require 'stringio'
require 'tmpdir'
require 'biometry/cli/main'

# Integration layer: the piece that turns a path into studies the report can
# use, or a reason it could not.
#
# It returns every study the message reported, in the order the message
# reported them. Taking one of several — the first, the last, the one with the
# most observations — would be a choice made on the caller's behalf by segment
# ordering rather than by rule, and the caller would never see the one that was
# dropped.
RSpec.describe Biometry::CLI::MessageSource do
  subject(:source) { described_class.new(loinc: Hl7Messages::MAPPING, stderr: stderr) }

  let(:stderr) { StringIO.new }
  let(:directory) { Dir.mktmpdir('biometry-hl7') }

  after { FileUtils.remove_entry(directory) }

  def path_to(contents)
    File.join(directory, 'message.hl7').tap { |path| File.write(path, contents) }
  end

  def scans(contents) = source.call(path_to(contents)).value!

  describe 'a message reporting two studies' do
    it 'returns both, rather than choosing between them' do
      expect(scans(Hl7Messages.two_full_studies).length).to eq(2)
    end

    it 'returns them in the order the message reported them' do
      expect(scans(Hl7Messages.two_full_studies).map(&:date))
        .to eq([Hl7Messages::EARLIER_SCAN_DATE, Hl7Messages::SCAN_DATE])
    end

    it 'gives each the measurements taken in it' do
      expect(scans(Hl7Messages.two_full_studies).map { |scan| scan.mm(:ac) })
        .to all(eq(Hl7Messages::MILLIMETRES[:ac]))
    end
  end

  describe 'a message reporting one study' do
    it 'returns a collection of one, so a caller need not branch on the count' do
      expect(scans(Hl7Messages.full).map(&:date)).to eq([Hl7Messages::SCAN_DATE])
    end
  end

  # A study nothing could be read from is not a scan of a fetus nobody
  # measured. It leaves the collection, and the identifiers it carried are on
  # stderr where the reader can see what went unread.
  context 'when one study yielded no measurement at all' do
    it 'returns only the study that did' do
      expect(scans(Hl7Messages.two_studies_one_unreadable).map(&:date))
        .to eq([Hl7Messages::SCAN_DATE])
    end

    it 'names on stderr what it could not read' do
      scans(Hl7Messages.two_studies_one_unreadable)
      expect(stderr.string).to include(Hl7Messages::UNMAPPED)
    end
  end

  context 'when no study yielded a measurement' do
    subject(:result) { source.call(path_to(Hl7Messages.with_unmapped_observation)) }

    let(:source) { described_class.new(loinc: { 'SPEC-NOTHING' => :ac }, stderr: stderr) }

    it 'refuses rather than returning an empty collection' do
      expect(result.failure.first).to eq(:insufficient_data)
    end
  end

  context 'when the message is not one this library can read' do
    it 'returns the parser refusal as it stands' do
      expect(source.call(path_to(Hl7Messages.not_an_oru)).failure.first).to eq(:invalid_input)
    end
  end
end
