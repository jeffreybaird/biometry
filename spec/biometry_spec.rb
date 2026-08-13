# frozen_string_literal: true

RSpec.describe Biometry do
  describe 'VERSION' do
    it 'is a dotted version string' do
      expect(described_class::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
    end
  end

  describe 'DATA_ROOT' do
    it 'points at the committed reference data' do
      expect(described_class::DATA_ROOT).to eq(described_class::ROOT / 'data')
    end

    it 'is where the manifests actually live' do
      expect(described_class::DATA_ROOT / 'who.yml').to exist
    end
  end

  describe 'FAILURE_TAGS' do
    it 'lists every failure tag a service may return' do
      expect(described_class::FAILURE_TAGS).to eq(
        %i[insufficient_data out_of_range unsupported_standard
           unsupported_centile formula_chart_mismatch invalid_input]
      )
    end

    it 'is frozen' do
      expect(described_class::FAILURE_TAGS).to be_frozen
    end
  end

  describe 'the error hierarchy' do
    it 'roots every raised error at StandardError, so exe/ can catch it' do
      expect(described_class::Error.ancestors).to include(StandardError)
    end

    it 'descends UnverifiedReferenceData from Biometry::Error' do
      expect(described_class::UnverifiedReferenceData.superclass).to eq(described_class::Error)
    end

    it 'descends MalformedReferenceData from Biometry::Error' do
      expect(described_class::MalformedReferenceData.superclass).to eq(described_class::Error)
    end
  end
end
