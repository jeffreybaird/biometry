# frozen_string_literal: true

# One rule, not three facts: the redating policy answers its guards in the same
# order however it is asked.
#
#   1. input validity  ->  :invalid_input (or :insufficient_data for an absence)
#   2. the IVF rule    ->  Success, :keep, with no band selected
#   3. band selection  ->  :out_of_range, and then a threshold
#
# Why that order and not another.
#
# Validity is first for the reason it is first everywhere in this library: the
# indexing gestation is computed from the established date and the reference
# date, so a range check run on a string date reports on arithmetic nobody
# asked for.
#
# The IVF rule outranks the band because a band's threshold is an answer to a
# question IVF dating never asks. A pregnancy dated from a transfer is not
# redated by ultrasound at all, so "which band is this gestation in" has no
# bearing on the outcome — and a gestation outside every band must not turn a
# rule-decided :keep into a refusal, which is the collision this group exists
# to pin.
#
# Parameterised, because the rule is about a class of derivations rather than
# about one:
#
#   ivf:    a derivation the IVF rule covers
#   banded: a derivation it does not, which therefore reaches band selection
#
# data/ carries one of each today. A retrieval or known-conception derivation
# arriving later gets these examples rather than a second reading of the rule.
RSpec.shared_examples 'a decision that answers its guards in order' do |config|
  let(:manifest) { ComposedReport.redating_manifest }
  let(:policy) { described_class.new(manifest: manifest) }
  let(:on) { Date.new(2026, 8, 13) }
  let(:ivf_derivation) { config[:ivf] }
  let(:banded_derivation) { config[:banded] }

  def term = Biometry::Services::Dating::Lmp::TERM_DAYS

  # Mid-band and mid-window, so nothing below fails for a reason it did not
  # set out to test.
  def established = on + (term - ComposedReport.inside_band(ComposedReport.band_with_caveat))

  def request(**overrides)
    { established_edd: established, established_by: ivf_derivation,
      proposed_edd: established, reference_date: on }.merge(overrides)
  end

  def outcome(**overrides) = policy.call(**request(**overrides))

  # A date this library will not do arithmetic on. The one guard that has to
  # answer before any gestation is computed from it. It is the proposed date
  # rather than the established one so that it can be combined below with an
  # out-of-range established date without either override erasing the other.
  def invalid = { proposed_edd: '2026-10-20' }

  # 280 days plus a fortnight before the reference date is no pregnancy at all,
  # so the indexing gestation lands below every band.
  def before_the_pregnancy = { established_edd: on + term + 14 }

  # Larger than the widest threshold the file publishes, so it redates in every
  # band there is.
  def would_redate
    { proposed_edd: established + manifest[:bands].map { |band| band[:threshold_days] }.max + 1 }
  end

  context 'when the pregnancy was dated by IVF and nothing else is in question' do
    it 'keeps the established date' do
      expect(outcome.value!.recommendation).to eq(:keep)
    end

    it 'names the rule rather than a band' do
      expect(outcome.value!.band).to be_nil
    end
  end

  context 'when the pregnancy was dated by IVF and the discrepancy would redate' do
    it 'keeps it, because the rule answered before any threshold was consulted' do
      expect(outcome(**would_redate).value!.recommendation).to eq(:keep)
    end
  end

  # The collision the ordering exists for: a gestation no band covers, and a
  # rule that never needed one.
  context 'when the pregnancy was dated by IVF and the gestation is outside every band' do
    it 'still keeps it rather than refusing on a range it never had to read' do
      expect(outcome(**before_the_pregnancy).value!.recommendation).to eq(:keep)
    end
  end

  context 'when an input is invalid and the pregnancy was dated by IVF' do
    it 'names the invalid input, because the rule is read from the request' do
      expect(outcome(**invalid).failure.first).to eq(:invalid_input)
    end
  end

  # Every guard has something to say, and only the first in the order may.
  context 'when the input is invalid, the derivation is IVF and the range is out' do
    it 'names the invalid input, the first guard in the order' do
      expect(outcome(**invalid, **before_the_pregnancy).failure.first).to eq(:invalid_input)
    end
  end

  context 'when the pregnancy was not dated by IVF and the gestation is outside every band' do
    it 'names the range, the one guard with something to say' do
      expect(outcome(established_by: banded_derivation, **before_the_pregnancy).failure.first)
        .to eq(:out_of_range)
    end
  end

  context 'when the pregnancy was not dated by IVF and the input is invalid' do
    it 'names the invalid input rather than the range computed from it' do
      expect(outcome(established_by: banded_derivation, **invalid, **before_the_pregnancy)
               .failure.first).to eq(:invalid_input)
    end
  end
end
