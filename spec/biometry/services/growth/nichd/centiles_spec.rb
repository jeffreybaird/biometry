# frozen_string_literal: true

# Integration layer, and the other direction through Table 2: given a week and
# a centile, what weight does NICHD print?
#
# A separate service from the percentile adapter because it answers a different
# question, and a table one: every gram it returns is a cell of the CSV, never
# a value computed between cells. That is the same pinned decision the
# percentile direction reads under — Buck Louis publishes per completed week
# and seven centile columns, and anything between them would be ours.
#
# It carries the one thing that makes NICHD unlike the other three standards
# in either direction: four race/ethnicity charts and no combined one, so an
# unsupplied stratum is answered with the spread across all four rather than
# with a default nobody asked for.
RSpec.describe Biometry::Services::Growth::Nichd::Centiles do
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'nichd.yml').first
  end
  let(:table) do
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / 'percentiles/nichd.csv')
  end
  let(:service) { described_class.new(manifest: manifest, table: table) }

  # Table 2 prints seven columns. The manifest calls them `tabulated`, and
  # which of them were modelled and which derived is recorded there too; this
  # direction can serve any column the paper printed.
  def tabulated = manifest[:centiles][:tabulated]

  def strata = manifest[:stratification][:values].map(&:to_sym)

  def fixture(name) = manifest[:fixtures].find { |f| f[:name] == name }

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def row(group, week) = table.find { |r| r[:group] == group.to_s && r[:ga_weeks] == week }

  def call(centile, ga, stratum: nil) = service.call(ga: ga, centile: centile, stratum: stratum)

  def grams(centile, ga, stratum:) = call(centile, ga, stratum: stratum).value!.grams

  def charts(centile, ga) = call(centile, ga).value!.to_h { |w| [w.source.stratum, w] }

  # Every published cell of the table, keyed by the centile it belongs to, so
  # an expectation names the column rather than a number transcribed twice.
  def published(group, week) = tabulated.to_h { |c| [c, row(group, week)[:"p#{c}"]] }

  describe 'the weights it reads off Table 2' do
    it 'returns the cell the table prints, not a value computed near it' do
      expect(grams(10, weeks(32), stratum: :white)).to eq(row(:white, 32)[:p10])
    end

    it 'returns every tabulated column verbatim at 32 weeks' do
      computed = tabulated.to_h { |c| [c, grams(c, weeks(32), stratum: :black)] }
      expect(computed).to eq(published(:black, 32))
    end

    it 'returns every tabulated column verbatim at the last published week' do
      computed = tabulated.to_h { |c| [c, grams(c, weeks(40), stratum: :asian)] }
      expect(computed).to eq(published(:asian, 40))
    end

    # The manifest's own fixture, quoted from the paper's Results, standing
    # against the CSV the service reads: the two agree or one of them is wrong.
    it 'agrees with the weights the manifest records for all four charts at 32 weeks' do
      anchor = fixture('32 weeks, all four groups (p5/p50/p95)')[:expect]
      computed = anchor.keys.to_h do |group|
        [group, [5, 50, 95].map { |c| grams(c, weeks(32), stratum: group) }]
      end
      expect(computed).to eq(anchor)
    end

    it 'agrees with them at 39 weeks too' do
      anchor = fixture('39 weeks, all four groups (p5/p50/p95)')[:expect]
      computed = anchor.keys.to_h do |group|
        [group, [5, 50, 95].map { |c| grams(c, weeks(39), stratum: group) }]
      end
      expect(computed).to eq(anchor)
    end
  end

  # Pinned decision 1, in the direction that has no weight to interpolate: the
  # row for the completed week, because a row between two published ones would
  # be ours rather than the standard's.
  describe 'the week it reads' do
    it 'reads the completed week, so four extra days change nothing' do
      expect(grams(50, weeks(32, 4), stratum: :white)).to eq(grams(50, weeks(32), stratum: :white))
    end

    it 'names the completed week it read' do
      expect(call(50, weeks(32, 4), stratum: :white).value!.ga_weeks).to eq(32)
    end

    it 'reads a different row at the next completed week' do
      expect(grams(50, weeks(33), stratum: :white)).not_to eq(grams(50, weeks(32), stratum: :white))
    end
  end

  # Pinned decision 5, and the paper's headline finding, asked from the other
  # side: race/ethnicity is never inferred and never defaulted, and there is no
  # combined table, so the honest answer to an unspecified stratum is all four.
  context 'when no race or ethnicity is supplied' do
    subject(:weights) { call(10, weeks(32)).value! }

    it 'succeeds rather than refusing for want of a stratum' do
      expect(call(10, weeks(32))).to be_success
    end

    it 'returns one weight per published chart' do
      expect(weights.length).to eq(4)
    end

    it 'names the chart on every row, in the order the manifest publishes' do
      expect(weights.map { |w| w.source.stratum }).to eq(strata)
    end

    it 'defaults to no chart, so no row is silently the white one' do
      expect(weights.map(&:grams).uniq.length).to eq(4)
    end

    # The spread the authors quantify, in grams rather than in centiles: the
    # same 10th centile at the same week is a different weight on each chart.
    it 'reads each chart off its own row of the table' do
      expect(charts(10, weeks(32)).transform_values(&:grams))
        .to eq(strata.to_h { |group| [group, row(group, 32)[:p10]] })
    end
  end

  context 'when a race or ethnicity is supplied' do
    it 'returns that chart alone rather than the spread' do
      expect(call(10, weeks(32), stratum: :black).value!).to be_a(Biometry::ChartWeight)
    end

    it 'names the chart it read' do
      expect(call(10, weeks(32), stratum: :black).value!.source.stratum).to eq(:black)
    end

    it 'reports the same weight it reports for that chart unstratified' do
      expect(grams(10, weeks(32), stratum: :black)).to eq(charts(10, weeks(32))[:black].grams)
    end

    it 'refuses a stratum the standard does not publish' do
      expect(call(10, weeks(32), stratum: :other).failure).to eq(
        [:invalid_input, { stratum: :other, available: strata }]
      )
    end
  end

  # A column Table 2 never printed cannot be answered from the columns either
  # side of it without inventing a distribution the paper did not publish, so
  # the request is refused with what is available.
  context 'when the centile is one Table 2 never printed' do
    it 'refuses it rather than interpolating between the columns either side' do
      expect(call(25, weeks(32), stratum: :white).failure).to eq(
        [:unsupported_centile, { standard: :nichd, requested: 25, available: tabulated }]
      )
    end

    it 'refuses it with no stratum supplied too' do
      expect(call(42, weeks(32)).failure).to eq(
        [:unsupported_centile, { standard: :nichd, requested: 42, available: tabulated }]
      )
    end

    it 'publishes the seven the paper tabulates and refuses everything else' do
      expect(tabulated.map { |c| call(c, weeks(32), stratum: :white) }).to all(be_success)
    end
  end

  describe 'the gestational age window it was fitted over' do
    it 'accepts the first fitted week' do
      expect(call(50, weeks(15), stratum: :white)).to be_success
    end

    it 'accepts the last published week through its final day' do
      expect(call(50, weeks(40, 6), stratum: :white)).to be_success
    end

    # Pinned decision 4. The CSV keeps weeks 10-14 so it can be diffed against
    # the published table; the curves were fitted from 15, so this direction
    # must no more read those rows than the percentile direction may.
    it 'still holds the rows the paper never fitted, so the refusal is a decision' do
      expect(row(:white, 14)).not_to be_nil
    end

    it 'refuses them rather than reading a spline extrapolation' do
      expect(call(50, weeks(14, 6), stratum: :white).failure).to eq(
        [:out_of_range,
         { standard: :nichd, ga_weeks: 14, valid_range: manifest[:valid_ga_weeks] }]
      )
    end

    it 'refuses the week after the last published one' do
      expect(call(50, weeks(41), stratum: :white)).to be_failure
    end
  end

  # This direction takes no Estimate, so it has no pairing guard and the shared
  # order starts at the window: range, then stratum, then centile. Both
  # directions through Table 2 must answer the same input the same way.
  describe 'the order it answers its guards in' do
    it 'names the window before the stratum, no chart of its own answering there' do
      expect(call(50, weeks(41), stratum: :other).failure.first).to eq(:out_of_range)
    end

    it 'names the window before the centile, for the same reason' do
      expect(call(42, weeks(41), stratum: :white).failure.first).to eq(:out_of_range)
    end

    # Without a chart there is no list of published centiles to refuse the
    # request against, so a bad stratum would otherwise be reported as
    # :unsupported_centile citing a table the caller never named.
    it 'names the stratum before the centile' do
      expect(call(42, weeks(32), stratum: :other).failure).to eq(
        [:invalid_input, { stratum: :other, available: strata }]
      )
    end
  end

  describe 'the report it returns' do
    subject(:weight) { call(10, weeks(32), stratum: :white).value! }

    it 'is a ChartWeight' do
      expect(weight).to be_a(Biometry::ChartWeight)
    end

    it 'names the centile it was asked for' do
      expect(weight.centile).to eq(10)
    end

    it 'carries the citation the manifest publishes' do
      expect(weight.source.citation).to eq(manifest[:source][:citation])
    end

    it 'names the standard as prescriptive, unlike WHO' do
      expect(weight.source.type).to eq(:prescriptive)
    end

    # The weight is a chart value, and the chart was built on the three-
    # parameter Hadlock model. A reader comparing it with a measured EFW has to
    # know which formula produced the column.
    it 'names the formula the chart was built on' do
      expect(weight.source.formula).to eq(manifest[:paired_formula].to_sym)
    end

    it 'reports a number and its source, never a classification' do
      expect(weight.to_s).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end
end
