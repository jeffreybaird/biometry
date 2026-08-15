# frozen_string_literal: true

require 'json'
require 'stringio'
require 'tmpdir'
require 'biometry/cli/main'

# Integration layer: the command is where the file, the parser and the mapping
# meet, and it is the only place in this slice that touches a filesystem.
#
# The guards it answers, in order:
#
#   1. argv          -> exit 2, before anything is opened
#   2. the file      -> exit 2, a path that is not there is the caller's typo
#   3. the mapping   -> exit 1, this library is missing a lookup
#   4. the message   -> whatever the parser says
#
# The third is the one that stands today. data/ carries no LOINC transcription,
# so every OBX-3 in any message would go unrecognised, and a message that parsed
# perfectly would render as a report with an empty growth table. That reads as a
# fetus nobody measured rather than as a library missing a lookup, so `--hl7`
# refuses and says which file is missing.
#
# It sits behind the two usage guards rather than in front of them so that a
# mistyped path is still reported as a mistyped path while the refusal stands.
RSpec.describe Biometry::CLI::ReportCommand do
  let(:directory) { Dir.mktmpdir('biometry-hl7') }

  after { FileUtils.remove_entry(directory) }

  def message_file(contents = Hl7Messages.full)
    File.join(directory, 'message.hl7').tap { |path| File.write(path, contents) }
  end

  # `command` is what the command is built with. Absent, it is built the way
  # exe/ builds it, which is the state every example above this line is in.
  def call(*extra, **command)
    stdout = StringIO.new
    stderr = StringIO.new
    argv = %w[report --ga 32w0d --at 2026-08-13] + extra
    status = described_class.new(stdout: stdout, stderr: stderr, **command).call(argv)
    [status, stdout.string, stderr.string]
  end

  describe 'a message this library has no LOINC mapping to read' do
    it 'exits 1, keeps stdout clean and refuses on stderr' do
      status, out, err = call('--hl7', message_file)
      expect(status).to eq(1)
      expect(out).to be_empty
      expect(err).not_to be_empty
    end

    it 'names the file that is missing and what it would hold' do
      _, _, err = call('--hl7', message_file)
      expect(err).to include('loinc.yml')
      expect(err).to match(/loinc/i)
    end

    # A report with no measurements in it is indistinguishable, on the page,
    # from a report of a fetus nobody measured.
    it 'renders no report at all, empty growth table or otherwise' do
      status, out, = call('--hl7', message_file)
      expect(status).to eq(1)
      expect(out).to be_empty
    end

    # --json is a promise about a stream: whatever goes on stdout parses. An
    # empty document would parse as a report with nothing in it.
    it 'writes nothing on stdout when asked for JSON, rather than an empty document' do
      status, out, err = call('--hl7', message_file, '--json')
      expect(status).to eq(1)
      expect(out).to be_empty
      expect(err).not_to be_empty
    end

    # The refusal is about the mapping, not about the message, and it comes
    # first: with no mapping there is nothing this library can say about what
    # the message contained.
    context 'when the file is not an ORU^R01 either' do
      it 'still refuses on the missing mapping rather than on the message' do
        status, _, err = call('--hl7', message_file(Hl7Messages.not_an_oru))
        expect(status).to eq(1)
        expect(err).to include('loinc.yml')
      end
    end
  end

  context 'when the file does not exist' do
    it 'exits 2, keeps stdout clean and names the path on stderr' do
      status, out, err = call('--hl7', File.join(directory, 'absent.hl7'))
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('absent.hl7')
    end

    # Ahead of the missing mapping: a caller who mistyped a path is told about
    # the typo, not about a transcription they were never going to need.
    it 'reports the path rather than the mapping this library has not got' do
      _, _, err = call('--hl7', File.join(directory, 'absent.hl7'))
      expect(err).to include('absent.hl7')
      expect(err).not_to include('loinc.yml')
    end
  end

  context 'when measurements are given both in a message and on the command line' do
    it 'exits 2, keeps stdout clean and names both sources on stderr' do
      status, out, err = call('--hl7', message_file, '--ac', '274')
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('--hl7').and include('--ac')
    end

    # argv is read before anything is opened, so the conflict is reported even
    # though the path is also wrong.
    it 'reports the conflict even when the path is wrong as well' do
      status, _, err = call('--hl7', File.join(directory, 'absent.hl7'), '--ac', '274')
      expect(status).to eq(2)
      expect(err).to include('--hl7').and include('--ac')
    end
  end

  # The far side of the refusal: the day data/loinc.yml lands.
  #
  # It is reachable only through the seam that file will arrive by. The mapping
  # is a collaborator, injected the way every manifest in this library is and
  # defaulting to the transcription that does not exist yet, so the arm can be
  # exercised without writing to data/ and without a spec asserting on a LOINC
  # code nobody verified. What is injected here is the specs' own mapping.
  #
  # The four examples below are what makes the arm safe to take. A command that
  # stopped refusing and did not read the message would render a report with an
  # empty growth table, which is the outcome the refusal exists to prevent.
  describe 'a message read with a mapping the command was given' do
    def with_mapping(*extra, mapping: Hl7Messages::MAPPING)
      call(*extra, loinc: mapping)
    end

    def document(*extra, **options)
      JSON.parse(with_mapping(*extra, '--json', **options)[1])
    end

    # One entry per study the message reported. This message reports one, and
    # the entry is where its measurements and its rows live: a message is the
    # one input that can carry a second study, so nothing here reaches past the
    # collection to a top level that would only ever describe the first.
    def studies(*extra, **options) = document(*extra, **options)['studies']

    it 'exits 0, prints the report on stdout and says nothing on stderr' do
      status, out, err = with_mapping('--hl7', message_file)
      expect(status).to eq(0)
      expect(out).not_to be_empty
      expect(err).to be_empty
    end

    it 'reports one study, dated the day the message says it was performed' do
      entries = studies('--hl7', message_file)
      expect(entries.length).to eq(1)
      expect(entries.first['date']).to eq(Hl7Messages::SCAN_DATE.iso8601)
    end

    # The whole point of the flag: the numbers come from the message, and the
    # four flags were never typed.
    it 'takes the measurements from the message' do
      measurements = studies('--hl7', message_file).first['measurements']
      expect(measurements.to_h { |m| [m['kind'].to_sym, m['mm']] })
        .to eq(Hl7Messages::MILLIMETRES)
    end

    it 'weighs the fetus the message measured' do
      rows = studies('--hl7', message_file).first['growth']
      expect(rows.filter_map { |row| row.dig('weight', 'value') }).not_to be_empty
    end

    # stdout carries the result, stderr everything else. An identifier nobody
    # mapped is a diagnostic about this library, not a reason to withhold the
    # report the rest of the message supported.
    context 'when the message also carried an observation nothing maps' do
      it 'exits 0, prints the report on stdout and names the identifier on stderr' do
        status, out, err = with_mapping('--hl7',
                                        message_file(Hl7Messages.full_with_unmapped_observation))
        expect(status).to eq(0)
        expect(out).not_to be_empty
        expect(err).to include(Hl7Messages::UNMAPPED)
      end
    end

    # The other diagnostic, and the one a caller can act on. An unnamed
    # identifier is this library's gap; an unreadable segment is a line in
    # their file, and the two numbers that find it have to survive the trip to
    # stderr or they may as well not have been collected.
    context 'when the message also carried a segment that could not be read' do
      let(:sent) { with_mapping('--hl7', message_file(Hl7Messages.full_with_malformed_observation)) }

      it 'exits 0 and still prints the report, because one bad segment is not the message' do
        status, out, err = sent
        expect(status).to eq(0)
        expect(out).not_to be_empty
        expect(err).not_to be_empty
      end

      it 'names the segment and the field position on stderr, so a reader can find the line' do
        expect(sent[2]).to match(/segment\W+7\b/i)
        expect(sent[2]).to match(/field\W+5\b/i)
      end
    end

    # The pinned case, now that it can happen: a message that parsed cleanly and
    # yielded nothing. An empty growth table reads as a fetus nobody measured.
    context 'when the mapping names none of the identifiers in the message' do
      it 'exits 1, keeps stdout clean and names what it could not read on stderr' do
        status, out, err = with_mapping('--hl7', message_file,
                                        mapping: { 'SPEC-NOTHING' => :ac })
        expect(status).to eq(1)
        expect(out).to be_empty
        expect(err).to include(Hl7Messages::CODES[:ac])
      end
    end

    # The parser's own refusal, reaching the user as one.
    context 'when the file is not an ORU^R01' do
      it 'exits 1, keeps stdout clean and names the message type on stderr' do
        status, out, err = with_mapping('--hl7', message_file(Hl7Messages.not_an_oru))
        expect(status).to eq(1)
        expect(out).to be_empty
        expect(err).to include('ADT')
      end
    end
  end
end
