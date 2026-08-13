# frozen_string_literal: true

# Acceptance layer: what a user of this slice sees end to end. One request,
# every derivation this library knows how to offer, and a Result for each —
# either a dated pregnancy or the reason there is not one.
#
# There is no winner. LMP and transfer genuinely disagree by days, and that
# disagreement is the same species as the four growth charts: which date is the
# established one is slice 2's decision and ultimately the clinician's, so
# nothing here ranks, filters or labels.
#
# Two of the four are deferred. data/ carries no dating regression for CRL or
# biometry, and Robinson-Fleming, Hadlock 1992 and INTERGROWTH give materially
# different ages from the same CRL, so picking one is the owner's decision.
# They are offered and refused rather than absent — a caller must be able to
# tell "this library cannot do that yet" from "your inputs did not support it".
RSpec.describe Biometry::Services::Dating::AllDerivations do
  subject(:results) { call.value! }

  let(:service) { described_class.new }
  let(:offered) { %i[lmp transfer] }

  def request(**overrides)
    { reference_date: Date.new(2026, 8, 13),
      lmp: Date.new(2026, 1, 1),
      transfer_date: Date.new(2026, 1, 15), embryo_day: 5 }.merge(overrides)
  end

  def call(**overrides) = service.call(**request(**overrides))

  def edds = results.transform_values { |result| result.success? && result.value!.edd }

  context 'when the request carries both a menstrual start and a transfer' do
    it 'is a Success, because the per-derivation Results are the report' do
      expect(call).to be_success
    end

    it 'reports one result per derivation, deferred ones included' do
      expect(results.keys).to eq(%i[lmp transfer crl biometry])
    end

    it 'dates the pregnancy from both derivations it implements' do
      expect(results.values_at(*offered).map(&:success?)).to all(be(true))
    end

    it 'returns a DatingEstimate from each' do
      expect(results.values_at(*offered).map(&:value!)).to all(be_a(Biometry::DatingEstimate))
    end

    it 'names its own derivation on every estimate' do
      expect(results.values_at(*offered).map { |result| result.value!.derivation })
        .to eq(offered)
    end

    it 'attributes each estimate to the convention that produced it' do
      expect(results.values_at(*offered).map { |result| result.value!.source.standard })
        .to eq(%i[naegele ivf_transfer])
    end

    # The output rather than a caveat on it: 280 days from a menstrual start
    # and 261 from a day-5 transfer are five days apart for this request.
    it 'reports both due dates, and they disagree' do
      expect(edds.values_at(*offered)).to eq([Date.new(2026, 10, 8), Date.new(2026, 10, 3)])
    end

    it 'reports both gestational ages at the same reference date' do
      ages = results.values_at(*offered).map { |result| result.value!.ga.to_s }
      expect(ages).to eq(%w[32w0d 32w5d])
    end

    it 'crowns no winner, carrying no key beyond the derivations themselves' do
      expect(results.keys - %i[lmp transfer crl biometry]).to be_empty
    end

    it 'reports dates and their derivations, never a classification' do
      rendered = results.values_at(*offered).map { |result| result.value!.to_s }.join(' ')
      expect(rendered).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal|post.?term/i)
    end
  end

  # Offered and refused. A derivation that vanished from the report would read
  # as one that was never tried.
  describe 'the derivations it does not implement yet' do
    it 'still lists them, rather than dropping them from the report' do
      expect(results.keys).to include(:crl, :biometry)
    end

    it 'refuses both' do
      expect(results.values_at(:crl, :biometry).map(&:failure?)).to all(be(true))
    end

    it 'names what was requested and what it can derive instead, for CRL' do
      expect(results[:crl].failure)
        .to eq([:unsupported_standard, { requested: :crl, available: offered }])
    end

    it 'names what was requested and what it can derive instead, for biometry' do
      expect(results[:biometry].failure)
        .to eq([:unsupported_standard, { requested: :biometry, available: offered }])
    end

    # The distinction this refusal exists to draw. A caller handed
    # :insufficient_data goes and finds a CRL; a caller handed
    # :unsupported_standard knows there is nothing to find.
    it 'refuses on availability even when a CRL measurement was supplied' do
      scan = Biometry::Scan.new(date: Date.new(2026, 3, 1),
                                measurements: [Biometry::Measurement.new(kind: :crl, mm: 60)])
      expect(call(scan: scan).value![:crl].failure.first).to eq(:unsupported_standard)
    end

    it 'refuses on availability when no ultrasound was supplied either' do
      expect(call(scan: nil).value![:crl].failure.first).to eq(:unsupported_standard)
    end
  end

  context 'when only a menstrual start is supplied' do
    subject(:results) { call(transfer_date: nil, embryo_day: nil).value! }

    it 'dates the pregnancy from it' do
      expect(results[:lmp]).to be_success
    end

    it 'reports the transfer derivation as unsupplied rather than dropping it' do
      expect(results[:transfer].failure.first).to eq(:insufficient_data)
    end

    it 'still reports the deferred derivations as unimplemented' do
      expect(results[:crl].failure.first).to eq(:unsupported_standard)
    end
  end

  context 'when only a transfer is supplied' do
    subject(:results) { call(lmp: nil).value! }

    it 'dates the pregnancy from it' do
      expect(results[:transfer]).to be_success
    end

    it 'reports the menstrual derivation as unsupplied' do
      expect(results[:lmp].failure.first).to eq(:insufficient_data)
    end
  end

  context 'when the request carries no dating input at all' do
    subject(:results) { call(lmp: nil, transfer_date: nil, embryo_day: nil).value! }

    it 'is still a Success, because the reasons are the report' do
      expect(call(lmp: nil, transfer_date: nil, embryo_day: nil)).to be_success
    end

    it 'gives every implemented derivation a failure naming the gap' do
      expect(results.values_at(*offered).map { |result| result.failure.first })
        .to all(eq(:insufficient_data))
    end

    it 'gives the deferred ones a failure naming the absent derivation' do
      expect(results.values_at(:crl, :biometry).map { |result| result.failure.first })
        .to all(eq(:unsupported_standard))
    end
  end

  # Cycle length belongs to one derivation. A bad one must not take down the
  # transfer date, which never reads it.
  context 'when the cycle length is nonsense' do
    subject(:results) { call(cycle_length: 0).value! }

    it 'refuses the menstrual derivation' do
      expect(results[:lmp].failure).to eq([:invalid_input, { cycle_length: 0 }])
    end

    it 'still dates the pregnancy from the transfer, which never reads it' do
      expect(results[:transfer]).to be_success
    end

    it 'still refuses CRL on availability rather than on the typo' do
      expect(results[:crl].failure.first).to eq(:unsupported_standard)
    end
  end

  context 'when the cycle length is left out' do
    it 'applies the 28 days Naegele assumes rather than refusing for want of one' do
      expect(edds[:lmp]).to eq(call(cycle_length: 28).value![:lmp].value!.edd)
    end
  end

  # Availability, then validity, then range — the order every derivation
  # answers in. The reasoning lives with the shared group.
  it_behaves_like 'a derivation that answers its guards in order',
                  { derivation: :lmp, available: true, invalid: { cycle_length: 0 } }

  it_behaves_like 'a derivation that answers its guards in order',
                  { derivation: :transfer, available: true, invalid: { embryo_day: -1 } }

  it_behaves_like 'a derivation that answers its guards in order',
                  { derivation: :crl, available: false, invalid: { scan: :not_a_scan } }

  it_behaves_like 'a derivation that answers its guards in order',
                  { derivation: :biometry, available: false, invalid: { scan: :not_a_scan } }
end
