# frozen_string_literal: true

# Acceptance layer: what a user of this slice sees end to end. One scan, one
# gestational age, four standards, and the disagreement between them as the
# output rather than a caveat on it.
#
# There is no aggregate service. The four adapters are not uniform — two
# equations and two tables, three dispersion models, three valid windows, two
# stratification axes — so this composes them the way the CLI will, and the
# behaviour asserted is the composed result rather than any orchestration.
#
# Three EFW values feed four charts, because formula and chart are paired:
# INTERGROWTH reads its own AC+HC weight, Hadlock 1991 the four-parameter
# model, and NICHD and WHO both the three-parameter one.
RSpec.describe Biometry::Services::Growth do
  let(:ga) { Biometry::GestationalAge.from(weeks: 32, days: 4) }
  let(:weights) do
    Biometry::Services::Weight::AllFormulas
      .new(hadlock: manifest('hadlock_1985'), intergrowth: manifest('intergrowth21'))
      .call(scan).value!
  end

  def manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  def scan
    measurements = { bpd: 82, hc: 291, ac: 274, fl: 62 }.map do |kind, mm|
      Biometry::Measurement.new(kind: kind, mm: mm)
    end
    Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
  end

  def efw(formula) = weights.fetch(formula).value!

  # Every standard read from the weight its own chart was built on, or from a
  # weight it was not, which is what the mismatch context exercises.
  def reports(paired: true)
    { intergrowth21: intergrowth(paired ? :intergrowth : :hadlock_ac_fl),
      hadlock_1991: hadlock_1991(paired ? :hadlock_bpd_hc_ac_fl : :intergrowth),
      nichd: nichd(paired ? :hadlock_hc_ac_fl : :intergrowth),
      who: who(paired ? :hadlock_hc_ac_fl : :intergrowth) }
  end

  def intergrowth(formula)
    described_class::Intergrowth.new(manifest: manifest('intergrowth21'))
                                .call(estimate: efw(formula), ga: ga)
  end

  def hadlock_1991(formula)
    described_class::Hadlock1991.new(manifest: manifest('hadlock_1991'))
                                .call(estimate: efw(formula), ga: ga)
  end

  def nichd(formula)
    described_class::Nichd.new(manifest: manifest('nichd'), table: table('nichd'))
                          .call(estimate: efw(formula), ga: ga)
  end

  def who(formula)
    described_class::Who.new(manifest: manifest('who'), table: table('who'))
                        .call(estimate: efw(formula), ga: ga, sex: :female)
  end

  # NICHD returns four rows from one call; the other three return one each.
  def rows(**)
    reports(**).values.flat_map { |result| Array(result.value!).flatten }
  end

  context 'when each chart is read from the weight it was built on' do
    it 'reports from every standard' do
      expect(reports.values.map(&:success?)).to all(be(true))
    end

    it 'returns seven rows, because NICHD publishes four charts and no combined one' do
      expect(rows.length).to eq(7)
    end

    it 'names the standard on every row' do
      expect(rows.map { |p| p.source.standard })
        .to match_array(%i[intergrowth21 hadlock_1991 nichd nichd nichd nichd who])
    end

    it 'names the formula that produced the weight on every row' do
      expect(rows.map { |p| p.source.formula }).to all(be_a(Symbol))
    end

    it 'distinguishes prescriptive standards from references' do
      types = reports.transform_values { |r| Array(r.value!).flatten.first.source.type }
      expect(types).to eq(intergrowth21: :prescriptive, hadlock_1991: :reference,
                          nichd: :prescriptive, who: :reference)
    end

    it 'reads three distinct weights, one per pairing' do
      formulas = rows.map { |p| p.source.formula }.uniq
      expect(formulas).to match_array(%i[intergrowth hadlock_bpd_hc_ac_fl hadlock_hc_ac_fl])
    end

    it 'names the same interpolation rule in both table standards' do
      methods = rows.select { |p| %i[nichd who].include?(p.source.standard) }
                    .map(&:interpolation)
      expect(methods.uniq).to eq([:linear_in_weight])
    end

    it 'names a closed form in both equation standards' do
      methods = rows.select { |p| %i[intergrowth21 hadlock_1991].include?(p.source.standard) }
                    .map(&:interpolation)
      expect(methods).to eq(%i[closed_form closed_form])
    end

    # 32w4d is completed week 32 for the tables, 32.571428 exact weeks for
    # INTERGROWTH and 32.6 to the nearest tenth for Hadlock 1991. One
    # gestation, three conventions, converted once on the type.
    it 'reads every standard at the same gestation, each in its own units' do
      expect(rows.map(&:ga_weeks).minmax).to eq([32, 32.6])
    end

    it 'disagrees, which is the output rather than a caveat on it' do
      expect(rows.map { |p| p.value.round(1) }.uniq.length).to be > 1
    end

    it 'reports numbers and their sources, never a classification' do
      rendered = rows.join(' ')
      expect(rendered).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end

  # Feeding one chart another formula's weight measures the chart difference
  # and the formula difference at once, with no way to separate them. Every
  # adapter refuses rather than returning a number that looks right.
  context 'when each chart is read from a weight it was not built on' do
    it 'refuses on every standard' do
      expect(reports(paired: false).values.map(&:failure?)).to all(be(true))
    end

    it 'names the mismatch on every standard' do
      expect(reports(paired: false).values.map { |r| r.failure.first })
        .to all(eq(:formula_chart_mismatch))
    end

    it 'names the chart, what it expected and what it was given' do
      expect(reports(paired: false)[:who].failure.last)
        .to eq(chart: :who, expected: :hadlock_hc_ac_fl, given: :intergrowth)
    end
  end

  # Three windows, three answers to the same gestation. 14 weeks is inside
  # WHO's window, outside NICHD's and INTERGROWTH's, and inside Hadlock 1991's.
  context 'when the gestation falls inside some windows and outside others' do
    let(:ga) { Biometry::GestationalAge.from(weeks: 14, days: 0) }

    it 'reports from the standards whose window covers it' do
      expect(reports.values_at(:hadlock_1991, :who).map(&:success?)).to all(be(true))
    end

    it 'refuses on the standards whose window does not, naming each window' do
      expect(reports.values_at(:intergrowth21, :nichd).map { |r| r.failure.first })
        .to all(eq(:out_of_range))
    end

    it 'names each standard and its own window in the refusal' do
      expect(reports[:nichd].failure.last)
        .to eq(standard: :nichd, ga_weeks: 14, valid_range: [15, 40])
    end
  end
end
