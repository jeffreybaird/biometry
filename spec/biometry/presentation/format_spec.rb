# frozen_string_literal: true

# Unit layer. Pure functions from a value to the text that stands for it.
# Nothing here reads a manifest, calls a service or touches a stream.
#
# Two rules are pinned in this file and both are slice 5 decisions rather than
# taste. Text rounds and JSON does not, so a centile of 4.3 reads `4th` here
# while the JSON document keeps 4.3. And an open bracket is rendered as the
# bracket it is — `below 3rd` — never as a bare number the chart did not
# publish.
RSpec.describe Biometry::Presentation::Format do
  def provenance(standard: :nichd, stratum: :white)
    Biometry::Provenance.new(standard: standard, citation: 'Buck Louis et al. 2015',
                             formula: :hadlock_hc_ac_fl, type: :prescriptive, stratum: stratum)
  end

  def percentile(value, bound: :computed)
    Biometry::Percentile.new(value: value, bound: bound, ga_weeks: 32,
                             interpolation: :linear_in_weight, source: provenance)
  end

  def estimate(value, formula: :hadlock_hc_ac_fl, inputs: %i[hc ac fl], sd_pct: 7.5)
    Biometry::Estimate.new(value: value, unit: 'g', formula: formula, inputs: inputs,
                           source: provenance,
                           uncertainty: sd_pct && Biometry::Uncertainty.pooled(sd_pct))
  end

  describe '.centile' do
    # The reader is comparing standards, not reading a decimal place. 4.3 and
    # 31.69 are the values NICHD's white and Asian charts actually return for
    # the same biometry, so the rounding rule is exercised on real ones.
    {
      1.0 => '1st', 2.0 => '2nd', 3.0 => '3rd', 4.3 => '4th',
      11.0 => '11th', 12.4 => '12th', 13.0 => '13th',
      21.0 => '21st', 22.0 => '22nd', 23.0 => '23rd',
      31.691353849999643 => '32nd', 40.32123497637788 => '40th',
      50.468388786621745 => '50th', 97.0 => '97th'
    }.each do |value, text|
      it "renders a computed #{value} as #{text}" do
        expect(described_class.centile(percentile(value))).to eq(text)
      end
    end

    # A weight past the outermost published column is not a percentile the
    # chart printed, so it is not printed as one.
    it 'renders an open bracket below as the bracket rather than as a number' do
      expect(described_class.centile(percentile(3.0, bound: :below))).to eq('below 3rd')
    end

    it 'renders an open bracket above as the bracket rather than as a number' do
      expect(described_class.centile(percentile(97.0, bound: :above))).to eq('above 97th')
    end

    # INTERGROWTH's closed form returns 7.7e-08 for the small scan. There is
    # no 0th centile, and printing one would read as a value the standard
    # published.
    it 'renders a computed value that rounds to zero as below the first centile' do
      expect(described_class.centile(percentile(7.749810250859302e-08))).to eq('<1st')
    end

    it 'renders a computed value that rounds to a hundred as above the ninety-ninth' do
      expect(described_class.centile(percentile(99.97))).to eq('>99th')
    end
  end

  describe '.weight' do
    it 'rounds to the gram and takes its unit from the estimate' do
      expect(described_class.weight(estimate(1833.5012))).to eq('1,834 g')
    end

    it 'groups thousands, because four digits of grams are read at a glance' do
      expect(described_class.weight(estimate(1697.0339))).to eq('1,697 g')
    end

    it 'leaves a three-digit weight ungrouped' do
      expect(described_class.weight(estimate(763.9463))).to eq('764 g')
    end
  end

  describe '.uncertainty' do
    it 'renders a published SD as a signed percentage' do
      expect(described_class.uncertainty(Biometry::Uncertainty.pooled(7.4))).to eq('±7.4%')
    end

    it 'renders a whole-number SD to the same one decimal place' do
      expect(described_class.uncertainty(Biometry::Uncertainty.pooled(8.0))).to eq('±8.0%')
    end

    # INTERGROWTH publishes a mean absolute prediction error, not an SD.
    # Rendering nothing is the whole point: a figure in this column would
    # attribute an SD to a paper that never gave one.
    it 'renders a standard that published no SD as a dash' do
      expect(described_class.uncertainty(nil)).to eq('—')
    end
  end

  describe '.standard' do
    {
      intergrowth21: 'INTERGROWTH-21st', hadlock_1991: 'Hadlock 1991',
      nichd: 'NICHD', who: 'WHO'
    }.each do |symbol, text|
      it "names #{symbol} as #{text}" do
        expect(described_class.standard(symbol)).to eq(text)
      end
    end

    it 'names the chart a stratified row was read from' do
      expect(described_class.standard(:nichd, stratum: :white)).to eq('NICHD (white)')
    end

    it 'names WHO\'s combined chart rather than leaving the row unlabelled' do
      expect(described_class.standard(:who, stratum: :combined)).to eq('WHO (combined)')
    end

    it 'falls back to the symbol for a standard it has no display name for' do
      expect(described_class.standard(:hadlock)).to eq('hadlock')
    end
  end

  # One function owns the label so the two derivations cannot spell "28d
  # cycle" two ways, the same shape as `.standard`. The assumption comes from
  # the estimate's own `parameters`, never from what the caller typed.
  describe '.derivation' do
    it 'names the cycle the menstrual derivation corrected for' do
      expect(described_class.derivation(:lmp, parameters: { cycle_length: 28 }))
        .to eq('LMP (28d cycle)')
    end

    it 'names the cycle actually used rather than the assumed one' do
      expect(described_class.derivation(:lmp, parameters: { cycle_length: 35 }))
        .to eq('LMP (35d cycle)')
    end

    it 'names the embryo day the transfer was counted from' do
      expect(described_class.derivation(:transfer, parameters: { embryo_day: 5 }))
        .to eq('Transfer (day 5)')
    end

    # Day zero is fertilisation itself, and a real transfer day.
    it 'names day zero rather than reading it as an absent value' do
      expect(described_class.derivation(:transfer, parameters: { embryo_day: 0 }))
        .to eq('Transfer (day 0)')
    end

    it 'names a deferred derivation plainly, having no estimate to read' do
      expect(%i[crl biometry].map { |d| described_class.derivation(d) })
        .to eq(%w[CRL Biometry])
    end

    it 'renders a parameter it has no phrasing for rather than dropping it' do
      expect(described_class.derivation(:crl, parameters: { crl_mm: 23 }))
        .to eq('CRL (crl_mm: 23)')
    end
  end

  describe '.inputs' do
    # `inputs` is what tells an AC+HC weight from a four-parameter one without
    # anyone parsing a formula id, and it is what makes three EFW values in
    # one table legible as three.
    it 'names the parameter set a weight was produced from' do
      expect(described_class.inputs(estimate(1833.5012))).to eq('(HC+AC+FL)')
    end

    it 'keeps the order the formula declares' do
      expect(described_class.inputs(estimate(1697.03, inputs: %i[ac hc]))).to eq('(AC+HC)')
    end
  end

  describe '.measurements' do
    it 'renders a scan in centimetres, in the order it was measured' do
      scan = ComposedReport.scan_of
      expect(described_class.measurements(scan)).to eq('BPD 8.2  HC 29.1  AC 27.4  FL 6.2 cm')
    end

    it 'says so when a scan carried nothing rather than rendering an empty column' do
      expect(described_class.measurements(ComposedReport.scan_of({}))).to eq('no measurements')
    end
  end
end
