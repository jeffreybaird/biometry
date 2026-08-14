# frozen_string_literal: true

# Integration layer: the derivation, the GestationalAge type and the
# DatingEstimate it returns, together. No reference data is involved — the two
# numbers this slice uses (280 days to the EDD, 28 days of assumed cycle) are
# definitional rather than measured, so nothing under data/ is read and no
# collaborator is injected.
#
#   EDD = LMP + 280 + (cycle_length - 28)
#   GA at a reference date = reference_date - (EDD - 280)
#
# The second line is the first one read backwards: the cycle correction moves
# the notional menstrual start, so it moves the gestational age by the same
# days it moves the due date. A 35-day cycle that shifted the EDD but not the
# GA would put every downstream percentile a week out.
RSpec.describe Biometry::Services::Dating::Lmp do
  subject(:result) { call }

  let(:service) { described_class.new }
  let(:lmp) { Date.new(2026, 1, 1) }
  let(:dating) { result.value! }

  def call(**overrides)
    service.call(lmp: lmp, reference_date: Date.new(2026, 8, 13), **overrides)
  end

  def ga_at(days, **overrides)
    call(reference_date: lmp + days, **overrides).value!.ga
  end

  context 'when the cycle length is left to the assumed 28 days' do
    it 'succeeds' do
      expect(result).to be_success
    end

    it 'carries a DatingEstimate' do
      expect(dating).to be_a(Biometry::DatingEstimate)
    end

    it 'puts the due date 280 days after the menstrual start' do
      expect(dating.edd).to eq(Date.new(2026, 10, 8))
    end

    it 'reports the gestational age as the days since the menstrual start' do
      expect(dating.ga).to eq(Biometry::GestationalAge.from(weeks: 32))
    end

    it 'echoes the date that gestational age was taken at' do
      expect(dating.reference_date).to eq(Date.new(2026, 8, 13))
    end

    it 'names the derivation' do
      expect(dating.derivation).to eq(:lmp)
    end

    # The assumption travels with the estimate rather than staying in the
    # caller's arguments: a due date read without the cycle behind it cannot
    # be told from one derived on a cycle the patient does not have.
    it 'names the cycle length it assumed, rather than leaving it implicit' do
      expect(dating.parameters).to eq(cycle_length: 28)
    end

    it 'returns dates, never times, so nothing carries a zone' do
      expect(dating.edd).to be_an_instance_of(Date)
    end
  end

  # Naegele assumes a 28-day cycle. Correcting for the real one is the default
  # behaviour rather than an option, so the caller who passes nothing gets the
  # assumption and the caller who knows gets the correction.
  describe 'the cycle-length correction' do
    it 'moves the due date a day later for each day of cycle past 28' do
      expect(call(cycle_length: 35).value!.edd).to eq(Date.new(2026, 10, 15))
    end

    it 'moves the due date earlier for a cycle shorter than 28' do
      expect(call(cycle_length: 21).value!.edd).to eq(Date.new(2026, 10, 1))
    end

    it 'reports the same due date at 28 as an uncorrected Naegele estimate' do
      expect(call(cycle_length: 28).value!.edd).to eq(lmp + 280)
    end

    it 'reports the cycle it actually corrected for, not the assumed one' do
      expect(call(cycle_length: 35).value!.parameters).to eq(cycle_length: 35)
    end

    # The trap: a 35-day cycle means ovulation was a week later, so the
    # pregnancy is a week younger, not the same age with a later due date.
    it 'takes the same days off the gestational age it adds to the due date' do
      expect(call(cycle_length: 35).value!.ga)
        .to eq(Biometry::GestationalAge.from(weeks: 31))
    end

    it 'adds to the gestational age for a cycle shorter than 28' do
      expect(call(cycle_length: 21).value!.ga)
        .to eq(Biometry::GestationalAge.from(weeks: 33))
    end
  end

  # Off-by-one lives here. One day either side of a week rollover, read in all
  # three conventions the type publishes.
  describe 'the gestational age at a week boundary' do
    it 'reports the day before the rollover as 13w6d' do
      expect(ga_at(97).to_s).to eq('13w6d')
    end

    it 'reports the rollover itself as a whole week with a zero remainder' do
      expect(ga_at(98).to_s).to eq('14w0d')
    end

    it 'reports the day after the rollover as 14w1d' do
      expect(ga_at(99).to_s).to eq('14w1d')
    end

    it 'reports the menstrual start itself as day zero, not as day one' do
      expect(ga_at(0).to_s).to eq('0w0d')
    end

    context 'when the age is read in each convention the standards use' do
      it 'gives 13w6d as 13 completed weeks, 13.857 exact and 13.9 to the tenth' do
        ga = ga_at(97)
        expect([ga.completed_weeks, ga.exact_weeks.round(3), ga.tenth_weeks])
          .to eq([13, 13.857, 13.9])
      end

      it 'gives the rollover as 14 in all three, with no fractional residue' do
        ga = ga_at(98)
        expect([ga.completed_weeks, ga.exact_weeks, ga.tenth_weeks]).to eq([14, 14.0, 14.0])
      end

      it 'gives 14w1d as 14 completed weeks, 14.143 exact and 14.1 to the tenth' do
        ga = ga_at(99)
        expect([ga.completed_weeks, ga.exact_weeks.round(3), ga.tenth_weeks])
          .to eq([14, 14.143, 14.1])
      end
    end

    context 'when the cycle correction straddles the boundary' do
      it 'lands a 35-day cycle a week short of where 28 days would put it' do
        expect(ga_at(98, cycle_length: 35).to_s).to eq('13w0d')
      end

      it 'rolls a 35-day cycle over a week later than 28 days does' do
        expect(ga_at(105, cycle_length: 35).to_s).to eq('14w0d')
      end
    end
  end

  describe 'the provenance it attaches' do
    it 'names the convention it applied' do
      expect(dating.source.standard).to eq(:naegele)
    end

    it 'names the derivation as the formula that produced the value' do
      expect(dating.source.formula).to eq(:lmp)
    end

    it 'cites the convention rather than leaving the date unattributed' do
      expect(dating.source.citation).to be_a(String).and(satisfy { |c| !c.empty? })
    end

    # Prescriptive and reference are a growth-standard distinction. Naegele's
    # rule is neither, and claiming one would import a meaning it never had.
    it 'claims neither a chart type nor a stratum' do
      expect([dating.source.type, dating.source.stratum]).to eq([nil, nil])
    end
  end

  context 'when the menstrual start is not supplied' do
    it 'fails rather than dating from the reference date alone' do
      expect(call(lmp: nil)).to be_failure
    end

    it 'names what it required and what it was given' do
      expect(call(lmp: nil).failure).to eq(
        [:insufficient_data,
         { required: %i[lmp reference_date], given: %i[cycle_length reference_date] }]
      )
    end
  end

  # A cycle length is a count of whole days. Nothing here bounds it to a
  # physiological window: no such range is transcribed in data/, and inventing
  # one would refuse a real patient on an unsourced threshold.
  describe 'the inputs it refuses' do
    it 'refuses a cycle length of zero' do
      expect(call(cycle_length: 0).failure).to eq([:invalid_input, { cycle_length: 0 }])
    end

    it 'refuses a negative cycle length' do
      expect(call(cycle_length: -5).failure).to eq([:invalid_input, { cycle_length: -5 }])
    end

    it 'refuses a fractional cycle length, since days are whole' do
      expect(call(cycle_length: 28.5).failure).to eq([:invalid_input, { cycle_length: 28.5 }])
    end

    it 'refuses a menstrual start that is not a date' do
      expect(call(lmp: '2026-01-01').failure)
        .to eq([:invalid_input, { lmp: '2026-01-01' }])
    end

    it 'refuses a reference date that is not a date' do
      expect(call(reference_date: '2026-08-13').failure)
        .to eq([:invalid_input, { reference_date: '2026-08-13' }])
    end

    # A Time carries a clock and a zone, and this library has neither. The same
    # goes for a DateTime, which is a Date only by inheritance.
    it 'refuses a Time where a Date belongs' do
      expect(call(lmp: Time.new(2026, 1, 1)).failure.first).to eq(:invalid_input)
    end

    it 'refuses a DateTime, so no zone can reach the arithmetic' do
      expect(call(lmp: DateTime.new(2026, 1, 1)).failure.first).to eq(:invalid_input)
    end

    it 'reports every invalid input at once, not the first one it met' do
      expect(call(lmp: 'x', cycle_length: 0).failure)
        .to eq([:invalid_input, { lmp: 'x', cycle_length: 0 }])
    end
  end

  # The only range this derivation has: a reference date before the menstrual
  # start describes no pregnancy. There is no upper bound, because no published
  # limit on gestation is transcribed in data/.
  context 'when the reference date precedes the menstrual start' do
    it 'refuses rather than reporting a negative age' do
      expect(call(reference_date: lmp - 14)).to be_failure
    end

    it 'names the convention, the age it computed and the range it accepts' do
      expect(call(reference_date: lmp - 14).failure).to eq(
        [:out_of_range, { standard: :naegele, ga_weeks: -2, valid_range: [0, nil] }]
      )
    end

    it 'accepts the menstrual start itself, the first day in range' do
      expect(call(reference_date: lmp)).to be_success
    end

    it 'refuses the day before it, one day outside' do
      expect(call(reference_date: lmp - 1).failure.first).to eq(:out_of_range)
    end

    # The cycle correction moves the notional start, so it moves the edge of
    # the range with it: a reference date that is in range at 28 days is not
    # in range at 35.
    it 'moves that first day with the cycle correction' do
      expect(call(reference_date: lmp + 3, cycle_length: 35).failure.first).to eq(:out_of_range)
    end
  end

  # Validity before range, and the reasoning lives with the shared group in
  # spec/support/shared_examples/dating_guard_order.rb, where the aggregate
  # exercises all three guards including availability.
  context 'when the cycle length is invalid and the reference date is out of range' do
    it 'names the invalid input, because a range computed from it means nothing' do
      expect(call(cycle_length: 0, reference_date: lmp - 14).failure.first).to eq(:invalid_input)
    end
  end
end
