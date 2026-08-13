# frozen_string_literal: true

# Acceptance layer: the behaviour a user of this slice sees. Given a Scan,
# every formula on offer reports — either an Estimate or the reason it could
# not produce one. Choosing between them is the caller's job, so nothing here
# ranks, filters or labels.
#
# On offer means verified: data/hadlock.yml marks three of its four Table II
# rows unverified, and an unverified formula is not offered at all.
RSpec.describe Biometry::Services::Weight::AllFormulas do
  subject(:results) { service.call(scan).value! }

  let(:hadlock) { Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock.yml') }
  let(:intergrowth) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'intergrowth21.yml')
  end
  let(:service) { described_class.new(hadlock: hadlock, intergrowth: intergrowth) }
  let(:offered) { hadlock[:efw_formulas].select { |_, row| row[:verified] }.keys + [:intergrowth] }
  let(:scan) { scan_of(bpd: 85, hc: 290, ac: 260, fl: 55) }

  def scan_of(**millimetres)
    measurements = millimetres.map { |kind, mm| Biometry::Measurement.new(kind: kind, mm: mm) }
    Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
  end

  context 'when the scan carries all four biometric parameters' do
    it 'reports one result per formula the manifests offer' do
      expect(results.keys).to match_array(offered)
    end

    it 'offers two formulas against the data as it stands' do
      expect(results.keys).to match_array(%i[hc_ac_fl intergrowth])
    end

    it 'omits the Hadlock rows that rest on a single unchecked transcription' do
      expect(results.keys).not_to include(:ac_fl, :bpd_ac_fl, :bpd_hc_ac_fl)
    end

    it 'produces an estimate from every formula it offers' do
      expect(results.values.map(&:success?)).to all(be(true))
    end

    it 'has each estimate name the formula that produced it' do
      expect(results.to_h { |id, result| [id, result.value!.method] })
        .to eq(offered.to_h { |id| [id, id] })
    end

    it 'attributes every estimate' do
      expect(results.values.map { |result| result.value!.source })
        .to all(be_a(Biometry::Provenance))
    end

    it 'reports every value in grams' do
      expect(results.values.map { |result| result.value!.unit }).to all(eq('g'))
    end

    it 'reports numbers and sources, never a classification' do
      rendered = results.values.map { |result| result.value!.to_s }.join(' ')
      expect(rendered).not_to match(/sga|iugr|macrosom|restrict|abnormal|normal/i)
    end
  end

  # ARTIFACTS.md section 3. INTERGROWTH needs HC and never reads FL.
  context 'when the scan has BPD, AC and FL but no HC' do
    let(:scan) { scan_of(bpd: 85, ac: 260, fl: 55) }

    it 'still reports one result per formula on offer, skipping none silently' do
      expect(results.keys).to match_array(offered)
    end

    it 'refuses INTERGROWTH, naming what was required and what was given' do
      expect(results[:intergrowth].failure).to eq(
        [:insufficient_data, { required: %i[ac hc], given: %i[bpd ac fl] }]
      )
    end

    it 'refuses the head-based Hadlock model, naming what was missing' do
      expect(results[:hc_ac_fl].failure).to eq(
        [:insufficient_data, { required: %i[hc ac fl], given: %i[bpd ac fl] }]
      )
    end
  end

  context 'when the scan carries nothing any formula can use' do
    let(:scan) { scan_of(crl: 60) }

    it 'is still a Success, because the reasons are the report' do
      expect(service.call(scan)).to be_success
    end

    it 'gives every formula a failure naming the gap' do
      expect(results.values.map { |result| result.failure.first })
        .to all(eq(:insufficient_data))
    end
  end
end
