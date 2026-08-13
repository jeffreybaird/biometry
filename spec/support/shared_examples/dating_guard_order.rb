# frozen_string_literal: true

# One rule, not four facts: every dating derivation answers its guards in the
# same order.
#
#   1. availability   ->  :unsupported_standard
#   2. input validity ->  :invalid_input  (or :insufficient_data for an absence)
#   3. range          ->  :out_of_range
#
# Why that order and not another.
#
# Availability is a question about this library, not about the request. CRL and
# biometry dating are deferred: data/ carries no dating regression for either,
# and choosing among the published ones is a clinical decision rather than an
# implementer's. So the answer to a CRL request is "this library cannot do that
# yet" whatever the request looked like. Validate first and a caller is told to
# fix a typo in a request that was never going to be answered — they fix it,
# resubmit, and only then learn the derivation does not exist. Two round trips
# for one submission, and the same defect slice 4 shipped when a guard was
# reordered to satisfy a metrics cop with nothing asserting the order.
#
# Range sits last because it is computed. A gestational age is only outside the
# range once the inputs that produced it can be trusted; a range check run on a
# cycle length of zero reports on arithmetic nobody asked for.
#
# The group is parameterised, because the derivations differ in which input is
# theirs to validate:
#
#   derivation: the key its Result appears under in the aggregate's report
#   available:  whether this slice implements it at all
#   invalid:    a request override that makes this derivation's own input bad
#
# A deferred derivation gets the examples that make sense for it and none of
# the ones that do not.
RSpec.shared_examples 'a derivation that answers its guards in order' do |config|
  let(:service) { described_class.new }
  let(:derivation) { config[:derivation] }
  let(:invalid_input) { config[:invalid] }

  # Every input the aggregate accepts, all of them well formed, so that any
  # failure below is caused by the override under test and nothing else.
  def well_formed
    { reference_date: Date.new(2026, 8, 13),
      lmp: Date.new(2026, 1, 1), cycle_length: 28,
      transfer_date: Date.new(2026, 1, 15), embryo_day: 5,
      scan: ultrasound }
  end

  def ultrasound
    Biometry::Scan.new(date: Date.new(2026, 3, 1),
                       measurements: [Biometry::Measurement.new(kind: :crl, mm: 60),
                                      Biometry::Measurement.new(kind: :ac, mm: 130)])
  end

  # Before every derivation's start: before the menstrual start, and before the
  # notional one a day-5 transfer implies.
  def before_the_pregnancy = { reference_date: Date.new(2025, 1, 1) }

  # The tag alone. Which guard answered is the behaviour this group is about;
  # each derivation's own spec pins the payload that travels with it.
  def tag_for(**overrides)
    service.call(**well_formed, **overrides).value!.fetch(derivation).failure.first
  end

  if config[:available]
    context 'when only its own input is invalid' do
      it 'names the invalid input' do
        expect(tag_for(**invalid_input)).to eq(:invalid_input)
      end
    end

    context 'when only the reference date falls before the pregnancy began' do
      it 'names the range, the one guard with something to say' do
        expect(tag_for(**before_the_pregnancy)).to eq(:out_of_range)
      end
    end

    # The case a reordering has room to hide in: both guards have something to
    # say and only the first in the order may answer.
    context 'when its own input is invalid and the reference date is out of range' do
      it 'names the invalid input, because the range is computed from it' do
        expect(tag_for(**invalid_input, **before_the_pregnancy)).to eq(:invalid_input)
      end
    end
  else
    context 'when the request is otherwise well formed' do
      it 'reports that this library cannot derive a date that way yet' do
        expect(tag_for).to eq(:unsupported_standard)
      end
    end

    context 'when its own input is invalid' do
      it 'names the derivation it does not offer, not the typo in the request' do
        expect(tag_for(**invalid_input)).to eq(:unsupported_standard)
      end
    end

    # The distinction the refusal exists to draw: "this library cannot do that
    # yet" must not reach a caller as "your inputs did not support it".
    context 'when no input for it was supplied at all' do
      it 'still refuses on availability rather than on what was missing' do
        expect(tag_for(scan: nil)).to eq(:unsupported_standard)
      end
    end

    context 'when the reference date falls before the pregnancy began' do
      it 'names the derivation it does not offer, not the range' do
        expect(tag_for(**before_the_pregnancy)).to eq(:unsupported_standard)
      end
    end

    context 'when availability, validity and range are all in question at once' do
      it 'names availability, the first guard in the order' do
        expect(tag_for(**invalid_input, **before_the_pregnancy)).to eq(:unsupported_standard)
      end
    end
  end
end
