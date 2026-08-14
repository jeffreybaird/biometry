# frozen_string_literal: true

# Unit layer. The value both dating derivations agree to return.
#
# A due date on its own is not a report. Two derivations of the same pregnancy
# disagree by days, and slice 2 has to decide between them, so each one carries
# the date it was evaluated at, the gestational age there, which derivation
# produced it and the convention that derivation applied. Drop any of those and
# an EDD arrives as a bare number with no way to tell an IVF transfer date from
# a Naegele estimate.
#
# `edd` and `reference_date` are Dates. This library has no times and no zones.
RSpec.describe Biometry::DatingEstimate do
  subject(:dating) do
    described_class.new(edd: Date.new(2026, 10, 8), ga: ga,
                        reference_date: Date.new(2026, 8, 13),
                        derivation: :lmp, parameters: { cycle_length: 28 },
                        source: provenance)
  end

  let(:ga) { Biometry::GestationalAge.from(weeks: 32) }
  let(:provenance) do
    Biometry::Provenance.formula(standard: :naegele,
                                 citation: 'Naegele: EDD = LMP + 280 days',
                                 formula: :lmp)
  end

  it 'carries the estimated due date' do
    expect(dating.edd).to eq(Date.new(2026, 10, 8))
  end

  it 'carries the due date as a Date, so no time or zone travels with it' do
    expect(dating.edd).to be_an_instance_of(Date)
  end

  it 'carries the gestational age as an age, not as a count of days' do
    expect(dating.ga).to eq(Biometry::GestationalAge.from(weeks: 32))
  end

  # A GA that does not say when it was taken cannot be compared with another
  # derivation's, and every caller would otherwise reconstruct the date.
  it 'names the date the gestational age was taken at' do
    expect(dating.reference_date).to eq(Date.new(2026, 8, 13))
  end

  it 'names the derivation that produced it' do
    expect(dating.derivation).to eq(:lmp)
  end

  # The assumption the derivation ran on, for the same reason `reference_date`
  # is here: a 35-day cycle moves the due date by a week, so an EDD printed
  # without the cycle behind it is not a report, and a reader of the output
  # alone should not have to reconstruct it from their own input.
  describe '#parameters' do
    it 'carries the convention the derivation applied' do
      expect(dating.parameters).to eq(cycle_length: 28)
    end

    it 'names a different parameter for a different derivation' do
      other = dating.with(derivation: :transfer, parameters: { embryo_day: 5 })
      expect(other.parameters).to eq(embryo_day: 5)
    end

    it 'survives #with, so a re-derived estimate keeps its assumption' do
      expect(dating.with(edd: Date.new(2026, 10, 15)).parameters).to eq(cycle_length: 28)
    end

    it 'leaves the rest of the estimate alone when only the assumption changes' do
      expect(dating.with(parameters: { cycle_length: 35 }).edd).to eq(dating.edd)
    end
  end

  it 'names the convention it applied through its provenance' do
    expect(dating.source.standard).to eq(:naegele)
  end

  # The provenance's formula and the estimate's derivation are the same claim
  # seen from two directions; a report where they part company is attributing
  # one derivation's arithmetic to another.
  it 'attributes the arithmetic to the derivation that ran it' do
    expect(dating.source.formula).to eq(dating.derivation)
  end

  it 'cites the convention rather than leaving the number unattributed' do
    expect(dating.source.citation).to be_a(String).and(satisfy { |c| !c.empty? })
  end

  # The member is `derivation`, never `method`: Data.define(:method) shadows
  # Object#method and breaks every reflective caller. Estimate and Percentile
  # both carry this regression test for the same reason.
  describe '#method' do
    it 'is Object#method, because no member shadows it' do
      expect(dating.method(:to_s)).to be_a(Method)
    end

    it 'reflects on the instance rather than on the class as a workaround' do
      expect(dating.method(:to_s).call).to eq(dating.to_s)
    end
  end

  describe '#to_s' do
    it 'names the due date' do
      expect(dating.to_s).to include('2026-10-08')
    end

    it 'names the gestational age in weeks and days' do
      expect(dating.to_s).to include('32w0d')
    end

    it 'names the date that gestational age was taken at' do
      expect(dating.to_s).to include('2026-08-13')
    end

    it 'names the derivation, so two rows of a report are told apart' do
      expect(dating.to_s).to include('lmp')
    end

    it 'emits no classification label of any kind' do
      expect(dating.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal|post.?term|preterm/i)
    end

    context 'when the same pregnancy is dated by a different derivation' do
      it 'reads differently, rather than two derivations rendering alike' do
        other = dating.with(derivation: :transfer,
                            source: provenance.with(standard: :ivf_transfer,
                                                    formula: :transfer))
        expect(other.to_s).not_to eq(dating.to_s)
      end
    end
  end
end
