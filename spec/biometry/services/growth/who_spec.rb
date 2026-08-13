# frozen_string_literal: true

# Integration layer. WHO is the second table standard and reads by the same
# two pinned rules as NICHD: the row for the completed week, and linear
# interpolation in weight between the bracketing columns. Those rules are ours
# rather than the source's, and the report names the one it used.
#
# Two things make it unlike NICHD. It publishes a combined chart alongside the
# two sex-specific ones, so an unsupplied sex has a published answer rather
# than a spread. And it is a reference, not a prescriptive standard: WHO
# deliberately retained complicated pregnancies, so its 10th centile does not
# mean what NICHD's does.
#
# Its distribution is also deliberately asymmetric — the Bowley coefficient
# runs from -0.016 at 15 weeks to +0.111 at 40 — which makes linear
# interpolation a worse approximation here than for a log-normal standard.
# That is why the method travels with the number.
RSpec.describe Biometry::Services::Growth::Who do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'who.yml').first
  end
  let(:table) do
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / 'percentiles/who.csv')
  end
  let(:service) { described_class.new(manifest: manifest, table: table) }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def row(sex, week)
    table.find { |r| r[:sex] == sex.to_s && r[:ga_weeks] == week }
  end

  def efw(grams, formula: :hadlock_hc_ac_fl)
    Biometry::Estimate.new(
      value: grams, unit: 'g', formula: formula, inputs: %i[hc ac fl],
      source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x',
                                           formula: formula),
      uncertainty: Biometry::Uncertainty.pooled(8.0)
    )
  end

  def call(grams, ga, sex: nil, formula: :hadlock_hc_ac_fl)
    service.call(estimate: efw(grams, formula: formula), ga: ga, sex: sex)
  end

  def percentile_of(grams, ga, sex: nil) = call(grams, ga, sex: sex).value!.value

  describe 'the way it reads a weight against the table' do
    subject(:percentile) { call(1700, weeks(32)).value! }

    let(:combined32) { row(:combined, 32) }

    it 'reports a weight on a published column as that column' do
      expect(percentile_of(combined32[:p50], weeks(32))).to eq(50.0)
    end

    it 'interpolates linearly in weight between the bracketing columns' do
      expected = 10 + (((1700 - combined32[:p10]) / (combined32[:p25] - combined32[:p10]).to_f) * 15)
      expect(percentile.value).to be_within(1e-9).of(expected)
    end

    it 'names the same interpolation method the other table standard names' do
      expect(percentile.interpolation).to eq(:linear_in_weight)
    end
  end

  # Pinned decision 1, same as NICHD.
  describe 'the week it reads' do
    it 'reads the completed week, so four extra days change nothing' do
      expect(percentile_of(1700, weeks(32, 4))).to eq(percentile_of(1700, weeks(32)))
    end

    it 'names the completed week it read' do
      expect(call(1700, weeks(32, 4)).value!.ga_weeks).to eq(32)
    end

    it 'reads a different row at the next completed week' do
      expect(percentile_of(1700, weeks(33))).not_to eq(percentile_of(1700, weeks(32)))
    end
  end

  describe 'the chart it reads' do
    it 'reads the combined chart when no sex is supplied, and says so' do
      expect(call(1700, weeks(32)).value!.source.stratum).to eq(:combined)
    end

    it 'names the sex-specific chart when a sex is supplied' do
      expect(call(1700, weeks(32), sex: :female).value!.source.stratum).to eq(:female)
    end

    # The manifest records an 84 g median gap at 37 weeks. The same weight is
    # the median for a female fetus and below it for a male one.
    it 'reports the female median as the 50th on the female chart' do
      expect(percentile_of(row(:female, 37)[:p50], weeks(37), sex: :female)).to eq(50.0)
    end

    it 'reports the female median below the 50th on the male chart' do
      expect(percentile_of(row(:female, 37)[:p50], weeks(37), sex: :male)).to be < 50
    end

    it 'refuses a sex the standard does not publish' do
      expect(call(1700, weeks(32), sex: :unknown).failure).to eq(
        [:invalid_input,
         { sex: :unknown, available: manifest[:stratification][:values].map(&:to_sym) }]
      )
    end
  end

  # Tables 14 and 15 genuinely omit the 2.5th and 97.5th columns, and the
  # loader leaves those cells nil because the absence is data. The bracket a
  # weight falls outside therefore depends on which chart was read, and the
  # adapter never widens a sexed row from the combined one.
  describe 'the outermost columns each chart publishes' do
    it 'brackets a very small weight below the 2.5th on the combined chart' do
      low = call(1400, weeks(32)).value!
      expect([low.value, low.bound]).to eq([2.5, :below])
    end

    it 'brackets the same weight below the 5th on the female chart' do
      low = call(1400, weeks(32), sex: :female).value!
      expect([low.value, low.bound]).to eq([5.0, :below])
    end

    it 'reports no interpolation for an open bracket' do
      expect(call(1400, weeks(32), sex: :female).value!.interpolation).to eq(:none)
    end

    it 'brackets a very large weight above the 95th on the male chart' do
      high = call(4600, weeks(32), sex: :male).value!
      expect([high.value, high.bound]).to eq([95.0, :above])
    end
  end

  describe 'the gestational age window it was fitted over' do
    it 'reads the window from the manifest rather than assuming one' do
      expect(manifest[:valid_ga_weeks]).to eq([14, 40])
    end

    it 'accepts the first published week' do
      expect(call(90, weeks(14))).to be_success
    end

    it 'accepts the last published week through its final day' do
      expect(call(3617, weeks(40, 6))).to be_success
    end

    it 'refuses a gestation below the window rather than extrapolating' do
      expect(call(60, weeks(13, 6)).failure).to eq(
        [:out_of_range,
         { standard: :who, ga_weeks: 13, valid_range: manifest[:valid_ga_weeks] }]
      )
    end

    it 'refuses the week after the last published one' do
      expect(call(3617, weeks(41)).failure.first).to eq(:out_of_range)
    end
  end

  describe 'the report it returns' do
    subject(:percentile) { call(1700, weeks(32)).value! }

    it 'is a Percentile' do
      expect(percentile).to be_a(Biometry::Percentile)
    end

    it 'carries the citation the manifest publishes' do
      expect(percentile.source.citation).to eq(manifest[:source][:citation])
    end

    it 'names the standard a reference, because it retained complicated pregnancies' do
      expect(percentile.source.type).to eq(:reference)
    end

    it 'names the formula the chart was built on' do
      expect(percentile.source.formula).to eq(:hadlock_hc_ac_fl)
    end

    it 'reports a number and its source, never a classification' do
      expect(percentile.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end

  describe 'the formula its chart was built on' do
    it 'names the three-parameter Hadlock model, as NICHD does' do
      expect(manifest[:paired_formula].to_sym).to eq(:hadlock_hc_ac_fl)
    end

    it 'refuses an INTERGROWTH weight' do
      expect(call(1700, weeks(32), formula: :intergrowth).failure).to eq(
        [:formula_chart_mismatch,
         { chart: :who, expected: :hadlock_hc_ac_fl, given: :intergrowth }]
      )
    end

    it 'refuses the four-parameter Hadlock weight' do
      expect(call(1700, weeks(32), formula: :hadlock_bpd_hc_ac_fl)).to be_failure
    end
  end

  # Pairing, then range, then stratum — here the stratum is the sex. Same
  # order all four charts answer in; the reasoning lives with the shared group.
  it_behaves_like 'a chart that answers its guards in order',
                  { manifest: 'who.yml', table: 'percentiles/who.csv', stratum_key: :sex }
end
