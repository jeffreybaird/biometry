# frozen_string_literal: true

# Unit layer: message contents in, an Ingest out. Nothing here opens a file.
# The parser is the shell's reader, not the shell -- it never learns where the
# message came from, and the mapping from OBX-3 to a measurement kind arrives as
# an argument the way every manifest in this library does.
#
# data/ carries no LOINC transcription, so the identifiers below are the specs'
# own. Nothing here asserts on a real code: a code nobody verified, asserted as
# though it had been, is how HC silently becomes AC.
#
# Described by name rather than by constant so that each example fails on its
# own with the constant it wanted, instead of the file collapsing into one load
# error. When Biometry::Hl7::Oru exists this becomes a constant describe and the
# directives come off.
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'the ORU^R01 parser' do
  subject(:parser) { Biometry::Hl7::Oru.new(mapping: Hl7Messages::MAPPING) }

  def ingest(message) = parser.call(message).value!

  def only_scan(message) = ingest(message).scans.first

  def millimetres(scan) = Hl7Messages::MILLIMETRES.keys.to_h { |kind| [kind, scan.mm(kind)] }

  def payload(message) = parser.call(message).failure.last

  it_behaves_like 'a message that answers its guards in order'

  describe 'a message written with the default encoding characters' do
    it 'reads one scan from the one study it reports' do
      expect(ingest(Hl7Messages.full).scans.length).to eq(1)
    end

    it 'reads every parameter its mapping names' do
      expect(only_scan(Hl7Messages.full).kinds).to match_array(Hl7Messages::MILLIMETRES.keys)
    end

    it 'carries the millimetres OBX-5 reported' do
      expect(millimetres(only_scan(Hl7Messages.full))).to eq(Hl7Messages::MILLIMETRES)
    end

    it 'has nothing to report about a message it read whole' do
      expect(ingest(Hl7Messages.full).unrecognised).to be_empty
      expect(ingest(Hl7Messages.full).malformed).to be_empty
    end
  end

  # The example most likely to be skipped, and the one that catches a parser
  # that only ever saw one vendor's output. MSH-2 declares the characters this
  # message is punctuated with; a parser that splits on a hardcoded pipe reads
  # the whole of this one as a single field.
  describe "a message written with a vendor's own encoding characters" do
    let(:vendor) { Hl7Messages.full(enc: Hl7Messages::VENDOR) }

    it 'is not the same text as the default message, or this proves nothing' do
      expect(vendor).not_to eq(Hl7Messages.full)
    end

    it 'reads the same measurements out of it' do
      expect(millimetres(only_scan(vendor))).to eq(Hl7Messages::MILLIMETRES)
    end

    it 'parses to exactly what the default message parses to' do
      expect(ingest(vendor)).to eq(ingest(Hl7Messages.full))
    end
  end

  # HL7 terminates segments with a carriage return; files written by hand and
  # files that crossed a system boundary arrive with newlines.
  describe 'a message whose segments are separated by newlines' do
    it 'parses to what the same message with carriage returns parses to' do
      expect(ingest(Hl7Messages.full.tr("\r", "\n"))).to eq(ingest(Hl7Messages.full))
    end
  end

  describe 'a message reporting two studies' do
    subject(:scans) { ingest(Hl7Messages.two_scans).scans }

    it 'reads two scans rather than one scan with twice the observations' do
      expect(scans.length).to eq(2)
    end

    it 'gives each scan the observations that followed its own OBR' do
      expect(scans.map(&:kinds)).to eq([%i[ac], %i[ac fl]])
    end

    it 'gives each scan the date its own OBR was observed on' do
      expect(scans.map(&:date))
        .to eq([Hl7Messages::EARLIER_SCAN_DATE, Hl7Messages::SCAN_DATE])
    end

    # The two studies report the same parameter at different sizes, so an
    # observation attributed to the wrong OBR shows as a number rather than as
    # a count.
    it 'keeps each measurement with the study it was taken in' do
      expect(scans.map { |scan| scan.mm(:ac) }).to eq([240, 274])
    end
  end

  describe 'the identifier in OBX-3' do
    it 'becomes the measurement kind the injected mapping gives it' do
      expect(only_scan(Hl7Messages.full).kinds).to match_array(Hl7Messages::MILLIMETRES.keys)
    end

    # Nothing about the mapping is the parser's. Handed a different one, it
    # reads the same message differently.
    context 'when a caller supplies a mapping that reads the code as another parameter' do
      subject(:parser) { Biometry::Hl7::Oru.new(mapping: { 'SPEC-AC' => :hc }) }

      it 'reads the kind that mapping named, not the one the code looks like' do
        expect(only_scan(Hl7Messages.full).kinds).to eq(%i[hc])
      end

      it 'carries the value under that kind' do
        expect(only_scan(Hl7Messages.full).mm(:hc)).to eq(274)
      end
    end
  end

  describe 'the units in OBX-6' do
    def scan_in(units) = only_scan(Hl7Messages.in_units(units))

    context 'when the observation is in millimetres' do
      it 'passes the value through, because millimetres are what a Measurement holds' do
        expect(scan_in('mm').mm(:ac)).to eq(274)
      end
    end

    context 'when the observation is in centimetres' do
      it 'multiplies by ten' do
        expect(millimetres(only_scan(Hl7Messages.in_centimetres)))
          .to eq(Hl7Messages::MILLIMETRES)
      end

      # A scanner reports to one decimal place, and 27.45 cm is a real value
      # rather than a rounding of 27.4.
      it 'carries a fractional centimetre through exactly' do
        expect(only_scan(Hl7Messages.in_units('cm', value: '27.45')).mm(:ac)).to eq(274.5)
      end
    end

    context 'when the units are a coded element' do
      it 'reads the unit from its first component' do
        expect(scan_in(%w[mm millimeter UCUM]).mm(:ac)).to eq(274)
      end
    end

    # A unit nothing converts is not a unit to guess at: taken as millimetres,
    # an inch measurement is off by a factor of twenty-five.
    context 'when the units are ones this library does not convert' do
      it 'reads no measurement from the observation' do
        expect(scan_in('in').mm(:ac)).to be_nil
      end

      it 'reports the observation as unrecognised, naming the units it carried' do
        unrecognised = ingest(Hl7Messages.in_units('in')).unrecognised.first
        expect(unrecognised.units).to eq('in')
        expect(unrecognised.reason).to eq(:units)
      end
    end

    # The tenfold error this rule exists to prevent: a bare 274 is 274 mm to
    # one vendor and 274 cm to nobody, but a bare 27.4 is either.
    context 'when the observation carries no units at all' do
      it 'does not take the number for millimetres' do
        expect(scan_in(nil).mm(:ac)).to be_nil
      end

      it 'reports the observation as unrecognised, naming its identifier' do
        unrecognised = ingest(Hl7Messages.in_units(nil)).unrecognised.first
        expect(unrecognised.identifier).to eq(Hl7Messages::CODES[:ac])
        expect(unrecognised.reason).to eq(:units)
      end
    end
  end

  # A message carrying observations this library has no mapping for is a normal
  # message, not a broken one. What it must never be is quietly shorter than it
  # arrived.
  describe 'an observation nothing in the mapping names' do
    subject(:result) { parser.call(Hl7Messages.with_unmapped_observation) }

    let(:unrecognised) { ingest(Hl7Messages.with_unmapped_observation).unrecognised.first }

    it 'parses the message anyway' do
      expect(result).to be_success
    end

    it 'still reads the observations it does recognise' do
      expect(only_scan(Hl7Messages.with_unmapped_observation).mm(:ac)).to eq(274)
    end

    it 'puts nothing in the scan for the one it could not name' do
      expect(only_scan(Hl7Messages.with_unmapped_observation).kinds).to eq(%i[ac])
    end

    it 'reports the identifier exactly as the message wrote it' do
      expect(unrecognised.identifier).to eq(Hl7Messages::UNMAPPED)
      expect(unrecognised.reason).to eq(:identifier)
    end

    # MSH, OBR, the AC observation, then this one: the fourth segment a reader
    # counting down the message arrives at.
    it 'reports which segment it was, counting from one' do
      expect(unrecognised.segment).to eq(4)
    end

    # The units come back too, because a caller transcribing the mapping this
    # observation is missing needs to know what it would arrive in.
    it 'reports the units it carried' do
      expect(unrecognised.units).to eq('cm')
    end
  end

  describe 'a segment this library cannot read' do
    subject(:result) { parser.call(Hl7Messages.with_malformed_observation) }

    let(:malformed) { ingest(Hl7Messages.with_malformed_observation).malformed.first }

    it 'parses the rest of the message rather than discarding it' do
      expect(result).to be_success
    end

    it 'reads the observations that followed the bad one' do
      expect(only_scan(Hl7Messages.with_malformed_observation).mm(:fl)).to eq(62)
    end

    it 'invents no measurement for the one it could not read' do
      expect(only_scan(Hl7Messages.with_malformed_observation).mm(:ac)).to be_nil
    end

    it 'names the segment, counting from one as a reader does' do
      expect(malformed.segment).to eq(3)
    end

    # The segment index alone sends a reader to a line and leaves them to work
    # out which of twelve fields was the problem. OBX-5 is the value.
    it 'names the field position that failed' do
      expect(malformed.field).to eq(5)
      expect(malformed.reason).to eq(:not_a_number)
    end
  end

  # A Scan is a dated set of measurements, and this library has no undated one.
  # So an OBR with nothing in OBR-7 is the malformed segment, and the study it
  # opened is the part of the message that could not be read.
  describe 'a study reported with no observation date' do
    subject(:parsed) { ingest(Hl7Messages.with_undated_study) }

    it 'names the OBR and the field position that failed' do
      expect(parsed.malformed.first.segment).to eq(2)
      expect(parsed.malformed.first.field).to eq(7)
      expect(parsed.malformed.first.reason).to eq(:missing)
    end

    it 'reads no scan from that study rather than dating it from elsewhere' do
      expect(parsed.scans.map(&:date)).to eq([Hl7Messages::SCAN_DATE])
    end

    it 'reads the study that followed it' do
      expect(parsed.scans.first.mm(:ac)).to eq(274)
    end
  end

  # HL7 carries YYYYMMDDHHMMSS. This library has no times and no zones, so the
  # truncation happens here, once, on the way in.
  describe 'the date a scan is given' do
    subject(:date) { only_scan(Hl7Messages.full).date }

    it 'is a Date, with no time and no zone left on it' do
      expect(date).to be_instance_of(Date)
    end

    it 'is the day OBR-7 says the study was observed' do
      expect(date).to eq(Hl7Messages::SCAN_DATE)
    end

    # The message was sent the morning after the study. A parser reading MSH-7
    # would date this scan a day late, and every gestation read off it with it.
    it 'is not the day the message itself was sent' do
      expect(date).not_to eq(Hl7Messages::SENT_DATE)
    end
  end

  # The case this library refuses rather than guesses at. Many OB systems ship
  # the whole report as prose in one TX observation; the numbers are in there,
  # and reading them out of a sentence is how a clinician is handed a
  # confidently wrong weight.
  describe 'a report shipped as narrative text' do
    subject(:result) { parser.call(Hl7Messages.narrative) }

    it 'refuses rather than returning a scan with nothing in it' do
      expect(result).to be_failure
    end

    it 'names the data it did not have' do
      expect(result.failure.first).to eq(:insufficient_data)
    end

    it 'names the narrative case rather than describing it as an empty message' do
      expect(payload(Hl7Messages.narrative))
        .to include(required: :discrete_observations, given: :narrative_text)
    end

    # The prose says 27.4 cm and 1850 g. Neither is a measurement this library
    # read, so neither may come back looking like one.
    it 'scrapes no number out of the prose' do
      expect(payload(Hl7Messages.narrative).to_s).not_to include('1850')
      expect(payload(Hl7Messages.narrative).to_s).not_to include('27.4')
    end
  end

  # The narrative refusal is about a message with nothing discrete in it. A
  # report that ships its impression as prose *and* its biometry as numbers is
  # a message this library can read.
  describe 'a narrative alongside discrete observations' do
    subject(:result) { parser.call(Hl7Messages.narrative_alongside_discrete) }

    it 'parses it' do
      expect(result).to be_success
    end

    it 'reads the discrete observation' do
      expect(only_scan(Hl7Messages.narrative_alongside_discrete).mm(:ac)).to eq(274)
    end

    it 'reports the prose as an identifier it does not recognise' do
      identifiers = result.value!.unrecognised.map(&:identifier)
      expect(identifiers).to all(eq(Hl7Messages::NARRATIVE))
    end
  end

  describe 'a message that is not an ORU^R01 at all' do
    subject(:result) { parser.call(Hl7Messages.not_an_oru) }

    it 'refuses it' do
      expect(result.failure.first).to eq(:invalid_input)
    end

    # The two components, not the string the message wrote them as: the vendor
    # message writes its own separator between them and the refusal should read
    # the same either way.
    it 'names the message type it wanted and the one it was given' do
      expect(payload(Hl7Messages.not_an_oru))
        .to include(expected: Hl7Messages::ORU_R01, given: Hl7Messages::ADT_A01)
    end

    context 'when the message carries no MSH at all' do
      it 'refuses it as invalid rather than reading the segments that follow' do
        expect(parser.call(Hl7Messages.without_msh).failure.first).to eq(:invalid_input)
      end

      it 'says it could not find a message type' do
        expect(payload(Hl7Messages.without_msh)).to include(given: nil)
      end
    end

    # An empty file is a plausible thing to be handed: a transfer that wrote
    # nothing, a message read twice, an export that failed. It has no message
    # type for the same reason a stack of ADT segments has the wrong one, and
    # it is refused the same way rather than raising on a message with no
    # segments in it to look at.
    context 'when the message is empty' do
      it 'refuses it as invalid' do
        expect(parser.call('').failure.first).to eq(:invalid_input)
      end

      it 'says it could not find a message type' do
        expect(payload('')).to include(given: nil)
      end
    end

    context 'when the message is nothing but segment terminators' do
      it 'refuses it as invalid' do
        expect(parser.call("\r\n\r\n").failure.first).to eq(:invalid_input)
      end

      it 'says it could not find a message type' do
        expect(payload("\r\n\r\n")).to include(given: nil)
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
