# frozen_string_literal: true

# One rule, not three facts: the ingestion answers its guards in the same order
# whatever the message looks like.
#
#   1. message validity   ->  :invalid_input
#   2. the narrative case  ->  :insufficient_data
#   3. per-segment handling ->  Success, carrying its diagnostics
#
# Why that order and not another.
#
# Message validity is a question about the message as a whole, and it is asked
# before a single OBX is examined. An ADT admission carrying observations is
# not an ORU^R01 however well formed those observations are, and reporting on
# them tells a caller their observations were the problem when the message was.
#
# The narrative case outranks per-segment handling because it is a statement
# about the message rather than about any one segment. Every OBX in a narrative
# report is individually well formed -- a TX observation with prose in OBX-5 is
# exactly what the standard says it is -- so per-segment handling has nothing to
# report about it and would return a Success with no measurements in it. That
# reads as a scan of a fetus nobody measured rather than as a report this
# library cannot read.
#
# Per-segment handling refuses nothing at all. An unmapped identifier and a
# malformed segment are diagnostics that travel with the scans, so a message
# reaching the third guard is a Success however much of it was unreadable.
RSpec.shared_examples 'a message that answers its guards in order' do
  let(:parser) { Biometry::Hl7::Oru.new(mapping: Hl7Messages::MAPPING) }

  # Composed here rather than in the fixtures, because each of these exists to
  # put two guards in question at once and that pairing is the subject.
  def report(type: Hl7Messages::ORU_R01, observations: [Hl7Messages.obx(:ac, '274')])
    Hl7Messages.message(Hl7Messages.msh(type: type), Hl7Messages.obr, *observations)
  end

  def narrative = Hl7Messages.narrative_obx

  def malformed = [Hl7Messages.malformed_obx]

  def unmapped = [Hl7Messages.unmapped_obx]

  # The tag alone. Which guard answered is the behaviour this group is about;
  # the parser's own spec pins the payload that travels with it.
  def tag_for(**overrides) = parser.call(report(**overrides)).failure.first

  context 'when the message is not an ORU^R01 and its observations are prose' do
    it 'names the message, because the narrative case is a question about an ORU' do
      expect(tag_for(type: Hl7Messages::ADT_A01, observations: narrative)).to eq(:invalid_input)
    end
  end

  context 'when the message is not an ORU^R01 and a segment is malformed' do
    it 'names the message, before any OBX is examined' do
      expect(tag_for(type: Hl7Messages::ADT_A01, observations: malformed)).to eq(:invalid_input)
    end
  end

  # Every guard has something to say, and only the first in the order may.
  context 'when the message is not an ORU^R01, its observations are prose and one is malformed' do
    it 'names the message, the first guard in the order' do
      expect(tag_for(type: Hl7Messages::ADT_A01, observations: narrative + malformed + unmapped))
        .to eq(:invalid_input)
    end
  end

  context 'when the message carries no MSH at all and its observations are prose' do
    it 'names the message rather than what its observations turned out to be' do
      expect(parser.call(Hl7Messages.message(Hl7Messages.obr, *narrative)).failure.first)
        .to eq(:invalid_input)
    end
  end

  context 'when an ORU carries only prose and one of its segments is malformed' do
    it 'names the narrative case, because no segment of it was going to be read' do
      expect(tag_for(observations: narrative + malformed)).to eq(:insufficient_data)
    end
  end

  context 'when an ORU carries only prose and an identifier nothing maps' do
    it 'names the narrative case rather than collecting the identifier' do
      expect(tag_for(observations: narrative + unmapped)).to eq(:insufficient_data)
    end
  end

  # The third guard refuses nothing: it is where the diagnostics come from.
  context 'when an ORU carries a discrete observation, a malformed one and an unmapped one' do
    it 'succeeds, because per-segment trouble is reported rather than refused' do
      expect(parser.call(report(observations: [Hl7Messages.obx(:ac, '274')] + malformed + unmapped)))
        .to be_success
    end
  end
end
