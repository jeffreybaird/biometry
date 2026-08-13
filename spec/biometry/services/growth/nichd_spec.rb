# frozen_string_literal: true

# Integration layer. NICHD is a table standard: no published equation, seven
# tabulated centiles per completed week, four race/ethnicity charts and no
# combined one.
#
# Two decisions are pinned here and neither is the source's. Weeks are read,
# never interpolated — the row for GestationalAge#completed_weeks, because
# synthesising a row between them would publish a number Buck Louis never
# printed. Weights between centiles are interpolated linearly, identically to
# WHO.
#
# The service is handed the parsed manifest and the parsed CSV rows, never a
# path.
RSpec.describe Biometry::Services::Growth::Nichd do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'nichd.yml').first
  end
  let(:table) do
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / 'percentiles/nichd.csv')
  end
  let(:service) { described_class.new(manifest: manifest, table: table) }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def row(group, week)
    table.find { |r| r[:group] == group.to_s && r[:ga_weeks] == week }
  end

  def efw(grams, formula: :hadlock_hc_ac_fl)
    Biometry::Estimate.new(
      value: grams, unit: 'g', formula: formula, inputs: %i[hc ac fl],
      source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x',
                                           formula: formula),
      uncertainty: Biometry::Uncertainty.pooled(8.0)
    )
  end

  def call(grams, ga, stratum: nil, formula: :hadlock_hc_ac_fl)
    service.call(estimate: efw(grams, formula: formula), ga: ga, stratum: stratum)
  end

  def charts(grams, ga, stratum: nil)
    call(grams, ga, stratum: stratum).value!.to_h { |p| [p.source.stratum, p] }
  end

  # Pinned decision 5: race/ethnicity is never inferred and never defaulted,
  # and the paper publishes no combined table, so the honest answer to an
  # unspecified stratum is the spread across all four charts.
  context 'when no race or ethnicity is supplied' do
    subject(:reports) { call(1600, weeks(32)).value! }

    it 'succeeds rather than refusing for want of a stratum' do
      expect(call(1600, weeks(32))).to be_success
    end

    it 'returns one report per published chart' do
      expect(reports.length).to eq(4)
    end

    it 'names the chart on every row, in the order the manifest publishes' do
      expect(reports.map { |p| p.source.stratum })
        .to eq(manifest[:stratification][:values].map(&:to_sym))
    end

    it 'defaults to no chart, so no row is silently the white one' do
      expect(reports.map(&:value).uniq.length).to eq(4)
    end

    # The paper's own headline finding. 1600 g at 32 weeks sits near the 4th
    # centile on the white chart and the 13th-14th on the Black and Asian
    # ones; reporting one of those numbers alone is the misclassification the
    # authors quantify at up to 15%.
    it 'separates the charts by several centiles for identical biometry' do
      values = charts(1600, weeks(32)).transform_values { |p| p.value.round(1) }
      expect(values).to eq(white: 4.3, black: 13.3, hispanic: 10.7, asian: 14.1)
    end
  end

  context 'when a race or ethnicity is supplied' do
    it 'returns that chart alone' do
      expect(call(1600, weeks(32), stratum: :black).value!.length).to eq(1)
    end

    it 'names the chart it read' do
      expect(charts(1600, weeks(32), stratum: :black).keys).to eq([:black])
    end

    it 'reports the same value it reports for that chart unstratified' do
      expect(charts(1600, weeks(32), stratum: :black)[:black].value)
        .to eq(charts(1600, weeks(32))[:black].value)
    end

    it 'refuses a stratum the standard does not publish' do
      expect(call(1600, weeks(32), stratum: :other).failure).to eq(
        [:invalid_input,
         { stratum: :other, available: manifest[:stratification][:values].map(&:to_sym) }]
      )
    end
  end

  describe 'the way it reads a weight against the table' do
    subject(:percentile) { charts(1650, weeks(32), stratum: :white)[:white] }

    let(:white32) { row(:white, 32) }

    it 'reports a weight on a published column as that column' do
      expect(charts(white32[:p50], weeks(32), stratum: :white)[:white].value).to eq(50.0)
    end

    it 'interpolates linearly in weight between the bracketing columns' do
      expected = 5 + (((1650 - white32[:p5]) / (white32[:p10] - white32[:p5]).to_f) * 5)
      expect(percentile.value).to be_within(1e-9).of(expected)
    end

    it 'names the interpolation method, because the rule is ours' do
      expect(percentile.interpolation).to eq(:linear_in_weight)
    end

    context 'when the weight is outside the outermost published columns' do
      it 'reports the open bracket below rather than extrapolating' do
        low = charts(white32[:p3] - 50, weeks(32), stratum: :white)[:white]
        expect([low.value, low.bound, low.interpolation]).to eq([3.0, :below, :none])
      end

      it 'reports the open bracket above rather than extrapolating' do
        high = charts(white32[:p97] + 50, weeks(32), stratum: :white)[:white]
        expect([high.value, high.bound, high.interpolation]).to eq([97.0, :above, :none])
      end
    end
  end

  # Pinned decision 1. Buck Louis publishes per completed week; a value between
  # two weeks would be ours, not the standard's.
  describe 'the week it reads' do
    it 'reads the completed week, so four extra days change nothing' do
      expect(charts(1650, weeks(32, 4), stratum: :white)[:white].value)
        .to eq(charts(1650, weeks(32), stratum: :white)[:white].value)
    end

    it 'names the completed week it read' do
      expect(charts(1650, weeks(32, 4), stratum: :white)[:white].ga_weeks).to eq(32)
    end

    it 'reads a different row at the next completed week' do
      expect(charts(1650, weeks(33), stratum: :white)[:white].value)
        .not_to eq(charts(1650, weeks(32), stratum: :white)[:white].value)
    end
  end

  describe 'the gestational age window it was fitted over' do
    it 'reads the window from the manifest rather than assuming one' do
      expect(manifest[:valid_ga_weeks]).to eq([15, 40])
    end

    it 'accepts the first fitted week' do
      expect(call(110, weeks(15), stratum: :white)).to be_success
    end

    it 'accepts the last published week through its final day' do
      expect(call(3700, weeks(40, 6), stratum: :white)).to be_success
    end

    it 'refuses the week after the last published one' do
      expect(call(3700, weeks(41), stratum: :white)).to be_failure
    end

    # Pinned decision 4. Table 2 tabulates weeks 10-14, but the curves were
    # fitted from 15 weeks and the first scan visit is at 16. The CSV keeps
    # those rows so it can be diffed against the published table; the adapter
    # must not read them.
    context 'when the gestation falls in the weeks the CSV keeps but the paper never fitted' do
      it 'still holds those rows, so the refusal is a decision and not an absence' do
        expect(row(:white, 14)).not_to be_nil
      end

      it 'refuses them rather than reading a spline extrapolation' do
        expect(call(88, weeks(14, 6), stratum: :white).failure).to eq(
          [:out_of_range,
           { standard: :nichd, ga_weeks: 14, valid_range: manifest[:valid_ga_weeks] }]
        )
      end

      it 'refuses them with no stratum supplied too' do
        expect(call(88, weeks(10)).failure.first).to eq(:out_of_range)
      end
    end
  end

  describe 'the report it returns' do
    subject(:percentile) { charts(1650, weeks(32), stratum: :white)[:white] }

    it 'is a Percentile' do
      expect(percentile).to be_a(Biometry::Percentile)
    end

    it 'carries the citation the manifest publishes' do
      expect(percentile.source.citation).to eq(manifest[:source][:citation])
    end

    it 'names the standard as prescriptive, unlike WHO' do
      expect(percentile.source.type).to eq(:prescriptive)
    end

    it 'names the formula the chart was built on' do
      expect(percentile.source.formula).to eq(:hadlock_hc_ac_fl)
    end

    it 'reports a number and its source, never a classification' do
      expect(percentile.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end

  describe 'the formula its chart was built on' do
    it 'names the three-parameter Hadlock model as the pairing' do
      expect(manifest[:paired_formula].to_sym).to eq(:hadlock_hc_ac_fl)
    end

    it 'refuses the four-parameter weight the Hadlock 1991 chart pairs with' do
      expect(call(1650, weeks(32), stratum: :white, formula: :hadlock_bpd_hc_ac_fl).failure).to eq(
        [:formula_chart_mismatch,
         { chart: :nichd, expected: :hadlock_hc_ac_fl, given: :hadlock_bpd_hc_ac_fl }]
      )
    end

    it 'refuses an INTERGROWTH weight even with no stratum supplied' do
      expect(call(1650, weeks(32), formula: :intergrowth).failure.first)
        .to eq(:formula_chart_mismatch)
    end
  end

  # Pairing, then range, then stratum — the same order all four charts answer
  # in. The reasoning lives with the shared group.
  it_behaves_like 'a chart that answers its guards in order',
                  { manifest: 'nichd.yml', table: 'percentiles/nichd.csv',
                    stratum_key: :stratum }
end
