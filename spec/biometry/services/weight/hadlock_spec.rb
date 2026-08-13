# frozen_string_literal: true

# Integration layer: the adapter, the manifest as Biometry::ReferenceData
# hands it over, and the Scan/Measurement models together. The service is
# constructed with parsed manifest contents, never a path — nothing under
# services/ may touch the filesystem.
#
# Verification is the loader's job, not this service's: load_manifest prunes
# any row marked unverified, so an unconfirmed formula is simply absent from
# the manifest handed over here and takes the unknown-formula path.
RSpec.describe Biometry::Services::Weight::Hadlock do
  subject(:result) { service.call(scan) }

  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock.yml').first
  end
  let(:service) { described_class.new(manifest: manifest, formula: :hc_ac_fl) }
  let(:estimate) { result.value! }

  # Millimetres, because that is what HL7 OBX-5 carries.
  let(:scan) do
    measurements = { bpd: 90, hc: 330, ac: 340, fl: 74 }.map do |kind, mm|
      Biometry::Measurement.new(kind: kind, mm: mm)
    end
    Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
  end

  context 'when the scan carries every parameter the formula requires' do
    it 'succeeds' do
      expect(result).to be_success
    end

    it 'carries an Estimate' do
      expect(estimate).to be_a(Biometry::Estimate)
    end

    it 'reports grams' do
      expect(estimate.unit).to eq('g')
    end

    it 'names the formula that produced the value' do
      expect(estimate.formula).to eq(:hc_ac_fl)
    end

    it 'lists only the measurements the formula actually used' do
      expect(estimate.inputs).to eq(manifest[:efw_formulas][:hc_ac_fl][:requires].map(&:to_sym))
    end

    it 'evaluates the manifest equation over centimetres, not millimetres' do
      log10 = Biometry::Services::Weight::Equation
              .parse(manifest[:efw_formulas][:hc_ac_fl][:equation])
              .evaluate(hc: scan.cm(:hc), ac: scan.cm(:ac), fl: scan.cm(:fl))
      expect(estimate.value).to be_within(1).of(10**log10)
    end
  end

  describe 'the provenance it attaches' do
    it 'names the standard' do
      expect(estimate.source.standard).to eq(:hadlock)
    end

    it 'names the formula' do
      expect(estimate.source.formula).to eq(:hc_ac_fl)
    end

    it 'claims no stratum, because the 1985 models are unstratified' do
      expect(estimate.source).not_to be_stratified
    end

    context 'when the manifest publishes no machine-readable citation' do
      it 'leaves the citation unset rather than supplying one' do
        expect(estimate.source.citation).to be_nil
      end
    end
  end

  # Every formula the manifest still carries, whatever that set becomes as
  # rows are confirmed or withdrawn.
  describe 'the formulas it offers' do
    let(:service) { described_class.new(manifest: manifest, formula: formula) }

    rows, = Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'hadlock.yml')

    rows[:efw_formulas].each_key do |id|
      context "when the requested formula is #{id}" do
        let(:formula) { id }

        it 'produces an estimate naming itself' do
          expect(estimate.formula).to eq(id)
        end
      end
    end
  end

  context 'when a required parameter is absent from the scan' do
    let(:scan) do
      kept = super().measurements.reject { |m| m.kind == :hc }
      Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: kept)
    end

    it 'fails rather than substituting a value' do
      expect(result).to be_failure
    end

    it 'names what was required and what was given' do
      expect(result.failure).to eq(
        [:insufficient_data,
         { required: %i[hc ac fl], given: %i[bpd ac fl] }]
      )
    end
  end

  # An unverified formula was pruned by the loader, so it reaches this service
  # as an absence and is indistinguishable from a formula that never existed.
  context 'when the requested formula is not in the manifest it was handed' do
    let(:service) { described_class.new(manifest: manifest, formula: :bpd_hc_ac_fl) }

    it 'fails rather than reaching for a formula it does not have' do
      expect(result).to be_failure
    end

    it 'names what was requested and what is available' do
      expect(result.failure).to eq(
        [:unsupported_standard,
         { requested: :bpd_hc_ac_fl, available: manifest[:efw_formulas].keys }]
      )
    end
  end
end
