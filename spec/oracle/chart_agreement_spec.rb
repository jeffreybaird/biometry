# frozen_string_literal: true

require 'csv'

# Tier 3b: FetalGPS chart agreement. Corroboration, NOT regression — this file
# is excluded from `rake verify` on purpose and runs only via `rake oracle`.
#
# A mismatch here has three possible causes the suite cannot distinguish: our
# bug, their bug, or a decision we made (Hadlock dispersion, formula/chart
# pairing, range windows). A failure is a question for a human, never a task
# to make green. Do not "fix" code or fixtures from this file alone.
# See docs/FIXTURES.md, tier 3.
#
# The Hadlock chart column is never compared on any row: FetalGPS uses the
# abstract's 12.7% SD, we use the table-implied 13.3% (tier 4 divergence 1).
RSpec.describe 'FetalGPS chart agreement (tier 3b)' do
  def self.rows
    @rows ||= CSV.read(File.expand_path('../fixtures/oracle_charts.csv', __dir__),
                       headers: true)
  end

  # Load-time drift guard: each flag must sum to exactly what we expect. If a
  # sum is wrong the CSV and this spec have drifted apart, and every downstream
  # mismatch would be noise — fail here instead.
  #
  # WHO is 4 short of the other two, and that deficit is the out-of-band
  # exclusion, not an omission. The WHO female chart at 22w publishes only the
  # 5th–95th columns; those four rows' EFW of 560.1 g sits above the 95th's
  # 557 g, where FetalGPSX clamps and FetalGPSR extrapolates, so there is no
  # single FetalGPS answer to agree with. We report "above the 95th" and skip
  # the comparison. See docs/FIXTURES.md.
  { 'compare_who' => 500, 'compare_nichd' => 504, 'compare_intergrowth' => 504 }
    .each do |flag, expected|
      total = rows.sum { |row| row[flag].to_i }
      next if total == expected

      raise "oracle_charts.csv drift: #{flag} sums to #{total}, expected #{expected}"
    end

  def self.manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def self.table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  def self.charts
    @charts ||= {
      nichd: Biometry::Services::Growth::Nichd.new(manifest: manifest('nichd'),
                                                   table: table('nichd')),
      who: Biometry::Services::Growth::Who.new(manifest: manifest('who'),
                                               table: table('who')),
      intergrowth21:
        Biometry::Services::Growth::Intergrowth.new(manifest: manifest('intergrowth21'))
    }
  end

  def self.weights
    @weights ||= {
      hadlock3: Biometry::Services::Weight::Hadlock.new(manifest: manifest('hadlock_1985'),
                                                        formula: :hadlock_hc_ac_fl),
      intergrowth:
        Biometry::Services::Weight::Intergrowth.new(manifest: manifest('intergrowth21'))
    }
  end

  def charts = self.class.charts

  def scan_for(row)
    measurements = { ac: 'ac_mm', hc: 'hc_mm', fl: 'fl_mm' }.map do |kind, column|
      Biometry::Measurement.new(kind: kind, mm: row[column].to_f)
    end
    Biometry::Scan.new(date: Date.new(2026, 1, 1), measurements: measurements)
  end

  def ga_for(row) = Biometry::GestationalAge.new(days: row['ga_days'].to_i)

  def hadlock3_estimate(row) = self.class.weights[:hadlock3].call(scan_for(row)).value!

  def intergrowth_estimate(row) = self.class.weights[:intergrowth].call(scan_for(row)).value!

  def who_centile(row)
    sex = row['sex'] == 'combined' ? nil : row['sex'].to_sym
    charts[:who].call(estimate: hadlock3_estimate(row), ga: ga_for(row), sex: sex).value!.value
  end

  def nichd_centile(row)
    charts[:nichd]
      .call(estimate: hadlock3_estimate(row), ga: ga_for(row), stratum: row['race'].to_sym)
      .value!.first.value
  end

  def intergrowth_centile(row)
    charts[:intergrowth21]
      .call(estimate: intergrowth_estimate(row), ga: ga_for(row))
      .value!.value
  end

  # FetalGPS rounds its EFW to 0.1 g before reading each chart and rounds the
  # centile to 0.1; 0.1 centiles absorbs that rounding and nothing else.
  def tolerance = 0.1

  rows.each_with_index do |row, index|
    description = "row #{index + 2} (#{row['ga_days']}d, #{row['sex']}, #{row['race']})"

    # A flag of 0 generates no example at all rather than a skip: there is
    # nothing pending about a comparison we have decided not to make, and the
    # row's note in the CSV records why.
    if row['compare_who'] == '1'
      it "#{description}: WHO reads #{row['fgps_who']}" do
        expect(who_centile(row)).to be_within(tolerance).of(row['fgps_who'].to_f)
      end
    end

    if row['compare_nichd'] == '1'
      it "#{description}: NICHD #{row['race']} reads #{row['fgps_nichd']}" do
        expect(nichd_centile(row)).to be_within(tolerance).of(row['fgps_nichd'].to_f)
      end
    end

    next unless row['compare_intergrowth'] == '1'

    it "#{description}: INTERGROWTH reads #{row['fgps_intergrowth']}" do
      expect(intergrowth_centile(row)).to be_within(tolerance).of(row['fgps_intergrowth'].to_f)
    end
  end
end
