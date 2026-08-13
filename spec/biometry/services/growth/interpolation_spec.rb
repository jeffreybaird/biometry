# frozen_string_literal: true

# Unit layer, and the reason it exists is the seam. NICHD and WHO both convert
# a weight to a percentile by interpolating between the bracketing published
# columns, and PROJECT.md pins that rule as identical in both. Two adapters
# each implementing it is two rules; one collaborator with its own specs is
# one.
#
# The rule is linear in weight, undefined in every source, and therefore ours
# rather than the standard's — which is why the result names the method it
# used. Outside the outermost published columns it reports the open bracket
# instead of extrapolating: a table cannot answer further out.
#
# Real columns from data/percentiles/nichd.csv, so the arithmetic is pinned
# against a row a reader can look up rather than a hand-picked toy.
RSpec.describe Biometry::Services::Growth::Interpolation do
  subject(:reading) { described_class.call(weight: weight, centiles: centiles) }

  let(:row) do
    Biometry::ReferenceData
      .load_table(Biometry::DATA_ROOT / 'percentiles/nichd.csv')
      .find { |r| r[:group] == 'white' && r[:ga_weeks] == 32 }
  end

  let(:centiles) do
    { 3 => row[:p3], 5 => row[:p5], 10 => row[:p10], 50 => row[:p50],
      90 => row[:p90], 95 => row[:p95], 97 => row[:p97] }
  end

  describe '.call' do
    context 'when the weight sits exactly on a published centile' do
      let(:weight) { row[:p50] }

      it 'reports that centile' do
        expect(reading.value).to eq(50.0)
      end

      it 'reports it as computed rather than bracketed' do
        expect(reading.bound).to eq(:computed)
      end

      it 'names the method it used' do
        expect(reading.interpolation).to eq(:linear_in_weight)
      end
    end

    context 'when the weight sits between two published centiles' do
      let(:weight) { 1650 }
      let(:expected) do
        5 + (((weight - row[:p5]) / (row[:p10] - row[:p5]).to_f) * (10 - 5))
      end

      it 'interpolates linearly in weight between the bracketing columns' do
        expect(reading.value).to be_within(1e-9).of(expected)
      end

      it 'lands strictly inside the bracket it interpolated across' do
        expect(reading.value).to be_between(5, 10).exclusive
      end

      it 'names the method, because the rule is ours and not the standard' do
        expect(reading.interpolation).to eq(:linear_in_weight)
      end
    end

    context 'when the weight is below the lowest published centile' do
      let(:weight) { row[:p3] - 100 }

      it 'reports the lowest published centile as an open bracket' do
        expect(reading.value).to eq(3.0)
      end

      it 'says the weight lies below it' do
        expect(reading.bound).to eq(:below)
      end

      it 'performs no interpolation, because a table cannot answer further out' do
        expect(reading.interpolation).to eq(:none)
      end
    end

    context 'when the weight is above the highest published centile' do
      let(:weight) { row[:p97] + 100 }

      it 'reports the highest published centile as an open bracket' do
        expect(reading.value).to eq(97.0)
      end

      it 'says the weight lies above it' do
        expect(reading.bound).to eq(:above)
      end

      it 'performs no interpolation' do
        expect(reading.interpolation).to eq(:none)
      end
    end

    # The boundary itself is inside the table, not outside it. Getting this
    # wrong turns every exact 3rd-centile weight into "below the 3rd".
    context 'when the weight is exactly the lowest published centile' do
      let(:weight) { row[:p3] }

      it 'reports it as computed rather than as an open bracket' do
        expect(reading.bound).to eq(:computed)
      end

      it 'reports the centile itself' do
        expect(reading.value).to eq(3.0)
      end
    end

    context 'when the weight is exactly the highest published centile' do
      let(:weight) { row[:p97] }

      it 'reports it as computed rather than as an open bracket' do
        expect(reading.bound).to eq(:computed)
      end
    end

    # WHO's sex-specific tables publish no 2.5th or 97.5th column, so the same
    # weight brackets differently depending on which columns were handed over.
    # The collaborator answers from the columns it was given and never widens
    # the set it was handed.
    context 'when the outermost columns are absent from the set supplied' do
      let(:centiles) { { 5 => row[:p5], 50 => row[:p50], 95 => row[:p95] } }
      let(:weight) { row[:p3] }

      it 'brackets against the narrower set it was given' do
        expect(reading.value).to eq(5.0)
      end

      it 'still reports the bracket as open below' do
        expect(reading.bound).to eq(:below)
      end
    end
  end
end
