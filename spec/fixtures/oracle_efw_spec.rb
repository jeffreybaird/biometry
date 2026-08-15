# frozen_string_literal: true

require 'csv'

# Tier 3a: FetalGPS EFW agreement — regression coverage of the composed path.
# The only fixture that exercises unit conversion (mm in, cm in the formulas),
# formula availability, the formula arithmetic and the gram boundary together.
#
# A mismatch here is unambiguously our bug: the three formulas were diffed
# character-for-character against FetalGPSX (VBA) and FetalGPSR (R), and both
# reproduce the papers' worked examples. See docs/FIXTURES.md, tier 3.
RSpec.describe 'oracle EFW agreement (tier 3a)' do
  def self.rows
    @rows ||= CSV.read(File.expand_path('oracle_efw.csv', __dir__), headers: true)
  end

  def self.manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def self.formulas
    @formulas ||= Biometry::Services::Weight::AllFormulas
                  .new(hadlock: manifest('hadlock_1985'), intergrowth: manifest('intergrowth21'))
  end

  def scan_for(row)
    columns = { ac: 'ac_mm', hc: 'hc_mm', fl: 'fl_mm', bpd: 'bpd_mm' }
    measurements = columns.filter_map do |kind, column|
      value = row[column]
      Biometry::Measurement.new(kind: kind, mm: value.to_f) unless value.to_s.empty?
    end
    Biometry::Scan.new(date: Date.new(2026, 1, 1), measurements: measurements)
  end

  def estimates(row) = self.class.formulas.call(scan_for(row)).value!

  rows.each_with_index do |row, index|
    description = "row #{index + 2} (#{row['case']}, #{row['ga_days']}d)"

    # FetalGPS selects the formula from which inputs are present. Our composed
    # path expresses the same rule as availability: without BPD the
    # four-parameter model must refuse with :insufficient_data, so the
    # three-parameter weight is the only Hadlock weight on offer.
    if row['case'] == 'no_bpd'
      it "#{description}: selects the three-parameter formula, as FetalGPS does" do
        expect(row['fgps_efw_formula']).to eq('hadlock_hc_ac_fl')
        expect(estimates(row)[:hadlock_hc_ac_fl]).to be_success
        expect(estimates(row)[:hadlock_bpd_hc_ac_fl].failure.first).to eq(:insufficient_data)
      end
    else
      it "#{description}: selects the four-parameter formula, as FetalGPS does" do
        expect(row['fgps_efw_formula']).to eq('hadlock_bpd_hc_ac_fl')
        expect(estimates(row)[:hadlock_bpd_hc_ac_fl]).to be_success
      end
    end

    it "#{description}: matches the FetalGPS #{row['fgps_efw_formula']} weight " \
       "of #{row['fgps_efw_g']} g to 0.1 g" do
      expect(estimates(row)[row['fgps_efw_formula'].to_sym].value!.value)
        .to be_within(0.1).of(row['fgps_efw_g'].to_f)
    end

    it "#{description}: matches the FetalGPS INTERGROWTH weight " \
       "of #{row['fgps_efw_intergrowth_g']} g to 0.1 g" do
      expect(estimates(row)[:intergrowth].value!.value)
        .to be_within(0.1).of(row['fgps_efw_intergrowth_g'].to_f)
    end
  end
end
