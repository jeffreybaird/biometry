# frozen_string_literal: true

# Integration layer. INTERGROWTH's equation has parentheses, a cube and a
# natural log, so it is not parsed: the functional form is code and the four
# constants come from the manifest's `coefficients:` block. The service is
# handed the parsed manifest, never a path.
RSpec.describe Biometry::Services::Weight::Intergrowth do
  subject(:result) { service.call(scan) }

  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / 'intergrowth21.yml').first
  end
  let(:service) { described_class.new(manifest: manifest) }
  let(:estimate) { result.value! }

  # "worked example, EFW": AC 26 cm, HC 29 cm -> 1499 g, tolerance 1 g.
  # Recorded in millimetres, which is what HL7 OBX-5 carries.
  let(:fixture) { manifest[:fixtures].find { |f| f[:name] == 'worked example, EFW' } }
  let(:scan) do
    measurements = fixture[:inputs].map do |key, cm|
      Biometry::Measurement.new(kind: key.to_s.delete_suffix('_cm').to_sym, mm: cm * 10)
    end
    Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
  end

  context 'when the scan carries both AC and HC' do
    it 'succeeds' do
      expect(result).to be_success
    end

    it "reproduces the paper's worked example within the manifest's tolerance" do
      expect(estimate.value)
        .to be_within(fixture[:tolerance_g]).of(fixture[:expect][:efw_g])
    end

    it 'reports grams' do
      expect(estimate.unit).to eq('g')
    end

    it 'names the formula that produced the value' do
      expect(estimate.formula).to eq(:intergrowth)
    end

    # The paper publishes a mean absolute prediction error of 7.6%, which is
    # not a standard deviation. Reporting it as one would relabel a different
    # quantity, so nothing is reported until an SD is transcribed.
    it 'carries no uncertainty, because the standard publishes no SD' do
      expect(estimate.uncertainty).to be_nil
    end

    it 'lists the measurements used, with no femur term' do
      expect(estimate.inputs).to eq(manifest[:efw][:requires].map(&:to_sym))
    end
  end

  # Millimetres in, centimetres in every published formula. Feeding the raw
  # millimetre numbers to a formula defined over centimetres is arithmetically
  # valid and clinically nonsense, so it has to be pinned.
  context 'when the same numbers arrive as millimetres rather than centimetres' do
    let(:scan) do
      measurements = fixture[:inputs].map do |key, value|
        Biometry::Measurement.new(kind: key.to_s.delete_suffix('_cm').to_sym, mm: value)
      end
      Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
    end

    it 'does not reproduce the worked example, because it converts before evaluating' do
      expect(estimate.value)
        .not_to be_within(fixture[:tolerance_g]).of(fixture[:expect][:efw_g])
    end
  end

  describe 'the provenance it attaches' do
    it 'names the standard' do
      expect(estimate.source.standard).to eq(:intergrowth21)
    end

    it 'names the formula' do
      expect(estimate.source.formula).to eq(:intergrowth)
    end

    it 'carries the citation the manifest publishes' do
      expect(estimate.source.citation).to eq(manifest[:source][:citation])
    end

    it 'carries the standard type, because a prescriptive centile is not a reference one' do
      expect(estimate.source.type).to eq(:prescriptive)
    end

    it 'claims no stratum, because the standard is unstratified by design' do
      expect(estimate.source).not_to be_stratified
    end
  end

  # ARTIFACTS.md section 3: a real scan, not a hypothetical. INTERGROWTH needs
  # HC and never reads FL, so BPD+AC+FL cannot produce a value.
  context 'when the scan has BPD, AC and FL but no HC' do
    let(:scan) do
      measurements = { bpd: 85, ac: 260, fl: 55 }.map do |kind, mm|
        Biometry::Measurement.new(kind: kind, mm: mm)
      end
      Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
    end

    it 'fails rather than falling back to a femur-based formula' do
      expect(result).to be_failure
    end

    it 'names what was required and what was given' do
      expect(result.failure).to eq(
        [:insufficient_data,
         { required: %i[ac hc], given: %i[bpd ac fl] }]
      )
    end
  end
end
