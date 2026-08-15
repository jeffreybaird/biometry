# frozen_string_literal: true

# Integration layer: the boundary between the shell's reader and the functional
# core. A Scan parsed out of a message has to be the same kind of thing as a
# Scan built by hand -- same model, same units, same date type -- or every
# service downstream of it is being handed a stranger.
#
# The check is a comparison rather than an inspection: the message reports the
# numbers ComposedReport builds its scan from, so the two must weigh the same.
# A parser that read centimetres as millimetres would still produce a Scan that
# looked right and a fetus ten times too small.
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'a scan parsed out of an ORU^R01 message' do
  def parse(message)
    Biometry::Hl7::Oru.new(mapping: Hl7Messages::MAPPING).call(message).value!.scans.first
  end

  def weights(scan) = ComposedReport.weights(scan)

  def grams(scan) = weights(scan).transform_values { |result| result.value!.value }

  # The same numbers, assembled by hand instead of read out of a message.
  def hand_built = ComposedReport.scan_of(Hl7Messages::MILLIMETRES)

  it 'is a Scan, and the models below it can be asked what it supports' do
    expect(parse(Hl7Messages.full).supports?(Hl7Messages::MILLIMETRES.keys)).to be(true)
  end

  it 'is dated with a Date the rest of the library can do arithmetic on' do
    expect(parse(Hl7Messages.full).date).to be_instance_of(Date)
  end

  it 'weighs exactly what the same measurements weigh when they were typed in' do
    expect(grams(parse(Hl7Messages.full))).to eq(grams(hand_built))
  end

  it 'produces an estimate from every formula the measurements support' do
    expect(weights(parse(Hl7Messages.full)).values).to all(be_success)
  end

  # The tenfold error, seen from the far end: the conversion happens at the
  # boundary, so by the time a formula reads centimetres off the Measurement it
  # cannot tell which unit the message used.
  context 'when the message reported its observations in centimetres' do
    it 'weighs what the millimetre message weighs' do
      expect(grams(parse(Hl7Messages.in_centimetres))).to eq(grams(parse(Hl7Messages.full)))
    end
  end

  context 'when the message reported no abdominal circumference' do
    def refusals = weights(parse(Hl7Messages.without_ac)).values.select(&:failure?)

    it 'refuses the formulas that needed one' do
      expect(refusals.map { |result| result.failure.first }).to all(eq(:insufficient_data))
      expect(refusals).not_to be_empty
    end

    # The absence reaches the formula as an absence, not as a zero.
    it 'names what the message did carry rather than a parameter measured as nothing' do
      given = refusals.map { |result| result.failure.last[:given] }
      expect(given).to all(match_array(%i[bpd hc fl]))
    end
  end
end
# rubocop:enable RSpec/DescribeClass
