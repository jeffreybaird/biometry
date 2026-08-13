# frozen_string_literal: true

# Integration layer: the IVF derivation, the GestationalAge type and the
# DatingEstimate it returns.
#
# Gestational age is menstrual age by definition, counted as if from an LMP two
# weeks before conception. So on the day of transfer the pregnancy is already
# 14 days old plus however many days the embryo has been growing:
#
#   GA at transfer = 14 days + the embryo's age at transfer
#
# A day-5 blastocyst is 2w5d on the day it goes back, a day-3 cleavage embryo
# 2w3d. Start either from day zero and every number downstream is about two
# weeks out — far enough that a clinician spots it, near enough that a spec
# written without the convention in mind passes.
#
# The embryo day is required. There is no defensible default: guessing 5 for a
# day-3 transfer is a two-day error, and guessing anything for a caller who
# simply omitted it is a silent one.
RSpec.describe Biometry::Services::Dating::Transfer do
  subject(:result) { call }

  let(:service) { described_class.new }
  let(:transfer_date) { Date.new(2026, 1, 15) }
  let(:dating) { result.value! }

  def call(**overrides)
    defaults = { transfer_date: transfer_date, embryo_day: 5,
                 reference_date: Date.new(2026, 8, 13) }
    service.call(**defaults, **overrides)
  end

  def ga_on(date, **overrides) = call(reference_date: date, **overrides).value!.ga

  context 'when a day-5 blastocyst was transferred' do
    it 'succeeds' do
      expect(result).to be_success
    end

    it 'carries a DatingEstimate' do
      expect(dating).to be_a(Biometry::DatingEstimate)
    end

    it 'counts the pregnancy as 2w5d on the day of transfer, not as day zero' do
      expect(ga_on(transfer_date).to_s).to eq('2w5d')
    end

    it 'puts the due date 280 days after that notional menstrual start' do
      expect(dating.edd).to eq(Date.new(2026, 10, 3))
    end

    it 'reports the age at the reference date as the days elapsed since transfer' do
      expect(dating.ga).to eq(Biometry::GestationalAge.from(weeks: 32, days: 5))
    end

    it 'names the derivation' do
      expect(dating.derivation).to eq(:transfer)
    end

    it 'returns dates, never times, so nothing carries a zone' do
      expect(dating.edd).to be_an_instance_of(Date)
    end
  end

  context 'when a day-3 cleavage embryo was transferred' do
    it 'counts the pregnancy as 2w3d on the day of transfer' do
      expect(ga_on(transfer_date, embryo_day: 3).to_s).to eq('2w3d')
    end

    it 'puts the due date two days later than the same-day blastocyst transfer' do
      expect(call(embryo_day: 3).value!.edd).to eq(Date.new(2026, 10, 5))
    end

    it 'reports an age two days younger than the blastocyst at the same date' do
      expect(ga_on(Date.new(2026, 8, 13), embryo_day: 3).days).to eq(dating.ga.days - 2)
    end
  end

  # The two-week error the convention exists to prevent, stated as an
  # assertion rather than as a comment.
  context 'when the transfer date itself is the reference date' do
    it 'is never day zero, whatever the embryo day' do
      ages = (0..6).map { |day| ga_on(transfer_date, embryo_day: day).days }
      expect(ages).to eq([14, 15, 16, 17, 18, 19, 20])
    end

    it 'is a fortnight ahead of the days the embryo has actually grown' do
      expect(ga_on(transfer_date, embryo_day: 5).days - 5).to eq(14)
    end
  end

  # Off-by-one lives here. Transfer of a day-5 blastocyst on 2026-01-15 reaches
  # 13w6d after 78 days, so the rollover is the day after.
  describe 'the gestational age at a week boundary' do
    it 'reports the day before the rollover as 13w6d' do
      expect(ga_on(transfer_date + 78).to_s).to eq('13w6d')
    end

    it 'reports the rollover itself as a whole week with a zero remainder' do
      expect(ga_on(transfer_date + 79).to_s).to eq('14w0d')
    end

    it 'reports the day after the rollover as 14w1d' do
      expect(ga_on(transfer_date + 80).to_s).to eq('14w1d')
    end

    context 'when the age is read in each convention the standards use' do
      it 'gives 13w6d as 13 completed weeks, 13.857 exact and 13.9 to the tenth' do
        ga = ga_on(transfer_date + 78)
        expect([ga.completed_weeks, ga.exact_weeks.round(3), ga.tenth_weeks])
          .to eq([13, 13.857, 13.9])
      end

      it 'gives the rollover as 14 in all three, with no fractional residue' do
        ga = ga_on(transfer_date + 79)
        expect([ga.completed_weeks, ga.exact_weeks, ga.tenth_weeks]).to eq([14, 14.0, 14.0])
      end

      it 'gives 14w1d as 14 completed weeks, 14.143 exact and 14.1 to the tenth' do
        ga = ga_on(transfer_date + 80)
        expect([ga.completed_weeks, ga.exact_weeks.round(3), ga.tenth_weeks])
          .to eq([14, 14.143, 14.1])
      end
    end
  end

  describe 'the provenance it attaches' do
    it 'names the convention it applied' do
      expect(dating.source.standard).to eq(:ivf_transfer)
    end

    it 'names the derivation as the formula that produced the value' do
      expect(dating.source.formula).to eq(:transfer)
    end

    it 'cites the convention rather than leaving the date unattributed' do
      expect(dating.source.citation).to be_a(String).and(satisfy { |c| !c.empty? })
    end

    it 'claims neither a chart type nor a stratum' do
      expect([dating.source.type, dating.source.stratum]).to eq([nil, nil])
    end

    it 'is told apart from an LMP-derived date by its provenance alone' do
      expect(dating.source.standard).not_to eq(:naegele)
    end
  end

  # Required, and required as a value the caller can be told about rather than
  # as an ArgumentError. A missing embryo day is a user omission, not a bug.
  context 'when the embryo day is not supplied' do
    it 'fails rather than assuming a blastocyst' do
      expect(call(embryo_day: nil)).to be_failure
    end

    it 'names what it required and what it was given' do
      expect(call(embryo_day: nil).failure).to eq(
        [:insufficient_data,
         { required: %i[transfer_date embryo_day reference_date],
           given: %i[transfer_date reference_date] }]
      )
    end

    it 'is refused the same way when the argument is omitted altogether' do
      expect(service.call(transfer_date: transfer_date, reference_date: Date.new(2026, 8, 13))
                    .failure.first).to eq(:insufficient_data)
    end
  end

  context 'when the transfer date is not supplied' do
    it 'names what it required and what it was given' do
      expect(call(transfer_date: nil).failure).to eq(
        [:insufficient_data,
         { required: %i[transfer_date embryo_day reference_date],
           given: %i[embryo_day reference_date] }]
      )
    end
  end

  # An embryo day is a count of whole days since fertilisation. Nothing here
  # bounds it above: no transcribed source in data/ says which days a lab may
  # transfer on, and refusing a day-7 transfer on an invented ceiling would be
  # this library making a clinical rule up.
  describe 'the inputs it refuses' do
    it 'refuses a negative embryo day' do
      expect(call(embryo_day: -1).failure).to eq([:invalid_input, { embryo_day: -1 }])
    end

    it 'refuses a fractional embryo day, since days are whole' do
      expect(call(embryo_day: 5.5).failure).to eq([:invalid_input, { embryo_day: 5.5 }])
    end

    it 'accepts day zero, the day of fertilisation itself' do
      expect(call(embryo_day: 0)).to be_success
    end

    it 'refuses a transfer date that is not a date' do
      expect(call(transfer_date: '2026-01-15').failure)
        .to eq([:invalid_input, { transfer_date: '2026-01-15' }])
    end

    it 'refuses a DateTime, so no zone can reach the arithmetic' do
      expect(call(transfer_date: DateTime.new(2026, 1, 15)).failure.first).to eq(:invalid_input)
    end

    it 'reports every invalid input at once, not the first one it met' do
      expect(call(transfer_date: 'x', embryo_day: -1).failure)
        .to eq([:invalid_input, { transfer_date: 'x', embryo_day: -1 }])
    end
  end

  # The only range this derivation has. The pregnancy begins 14 days plus the
  # embryo's age before the transfer, so a reference date earlier than that
  # describes no pregnancy.
  context 'when the reference date precedes the notional menstrual start' do
    it 'accepts the notional start itself, the first day in range' do
      expect(call(reference_date: transfer_date - 19)).to be_success
    end

    it 'reports that first day as day zero' do
      expect(ga_on(transfer_date - 19).to_s).to eq('0w0d')
    end

    it 'refuses the day before it, one day outside' do
      expect(call(reference_date: transfer_date - 20).failure.first).to eq(:out_of_range)
    end

    it 'names the convention, the age it computed and the range it accepts' do
      expect(call(reference_date: transfer_date - 33).failure).to eq(
        [:out_of_range, { standard: :ivf_transfer, ga_weeks: -2, valid_range: [0, nil] }]
      )
    end

    # The embryo day moves the start, so it moves the edge of the range: a
    # date in range for a day-5 transfer is outside it for a day-3 one.
    it 'moves that first day with the embryo day' do
      expect(call(reference_date: transfer_date - 19, embryo_day: 3).failure.first)
        .to eq(:out_of_range)
    end
  end

  # Validity before range. The reasoning lives with the shared group in
  # spec/support/shared_examples/dating_guard_order.rb.
  context 'when the embryo day is invalid and the reference date is out of range' do
    it 'names the invalid input, because the range is measured from it' do
      expect(call(embryo_day: -1, reference_date: transfer_date - 40).failure.first)
        .to eq(:invalid_input)
    end
  end
end
