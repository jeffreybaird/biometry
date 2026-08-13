# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Biometry::ReferenceData do
  # data/ is read-only, so every failure path is built from a throwaway file.
  def with_file(name, contents)
    Dir.mktmpdir do |dir|
      path = File.join(dir, name)
      File.write(path, contents)
      yield path
    end
  end

  def with_missing_file(name)
    Dir.mktmpdir { |dir| yield File.join(dir, name) }
  end

  def manifest(name) = described_class.load_manifest(Biometry::DATA_ROOT / "#{name}.yml")

  describe '.load_manifest' do
    it 'loads every manifest committed under data/' do
      names = %w[hadlock intergrowth21 nichd who acog_redating]
      expect(names.map { |name| manifest(name) }).to all(be_a(Hash))
    end

    it 'symbolizes keys, so adapters read the manifest with symbols' do
      expect(manifest('who')).to include(:paired_formula)
    end

    context 'when the manifest writes a date unquoted' do
      it 'loads it as a Date instead of raising Psych::DisallowedClass' do
        dates = manifest('who')[:corrections][:items].map { |item| item[:date] }
        expect(dates).to all(be_a(Date))
      end
    end

    describe 'the structure it returns' do
      it 'is frozen at the top level' do
        expect(manifest('who')).to be_frozen
      end

      it 'is frozen through nested mappings' do
        expect(manifest('who')[:corrections]).to be_frozen
      end

      it 'is frozen through nested arrays' do
        expect(manifest('who')[:valid_ga_weeks]).to be_frozen
      end
    end

    context 'when the file is marked unverified' do
      it 'raises UnverifiedReferenceData rather than returning its values' do
        with_file('draft.yml', "verified: false\nvalid_ga_weeks: [14, 40]\n") do |path|
          expect { described_class.load_manifest(path) }
            .to raise_error(Biometry::UnverifiedReferenceData, /marked unverified/)
        end
      end
    end

    context 'when the file is marked verified' do
      it 'returns the parsed mapping' do
        with_file('ok.yml', "verified: true\nvalid_ga_weeks: [14, 40]\n") do |path|
          expect(described_class.load_manifest(path))
            .to eq(verified: true, valid_ga_weeks: [14, 40])
        end
      end
    end

    context 'when the file carries no verified flag at all' do
      it 'loads it, because only an explicit false is a refusal' do
        with_file('bare.yml', "valid_ga_weeks: [14, 40]\n") do |path|
          expect(described_class.load_manifest(path)).to eq(valid_ga_weeks: [14, 40])
        end
      end
    end

    context 'when the file does not exist' do
      it 'raises MalformedReferenceData' do
        with_missing_file('absent.yml') do |path|
          expect { described_class.load_manifest(path) }
            .to raise_error(Biometry::MalformedReferenceData, /could not be parsed/)
        end
      end
    end

    context 'when the file is not parseable YAML' do
      it 'raises MalformedReferenceData naming the file' do
        with_file('broken.yml', "valid_ga_weeks: [14, 40\n") do |path|
          expect { described_class.load_manifest(path) }
            .to raise_error(Biometry::MalformedReferenceData, /broken\.yml could not be parsed/)
        end
      end
    end

    context 'when the file parses to something other than a mapping' do
      it 'raises MalformedReferenceData' do
        with_file('list.yml', "- hadlock\n- intergrowth21\n") do |path|
          expect { described_class.load_manifest(path) }
            .to raise_error(Biometry::MalformedReferenceData, /did not parse to a mapping/)
        end
      end
    end
  end

  describe '.load_table' do
    subject(:rows) { described_class.load_table(Biometry::DATA_ROOT / 'percentiles/who.csv') }

    let(:female_20w) { rows.find { |row| row[:sex] == 'female' && row[:ga_weeks] == 20 } }
    let(:combined_20w) { rows.find { |row| row[:sex] == 'combined' && row[:ga_weeks] == 20 } }

    it 'symbolizes the header row' do
      expect(rows.first.keys).to include(:sex, :ga_weeks, :p50)
    end

    it 'coerces integer cells to Integer' do
      expect(combined_20w[:ga_weeks]).to be_an(Integer)
    end

    it 'leaves non-numeric cells as strings' do
      expect(combined_20w[:sex]).to eq('combined')
    end

    context 'when a table omits a centile the standard never published' do
      it 'leaves the blank cell nil rather than zero' do
        expect([female_20w[:p2_5], female_20w[:p97_5]]).to eq([nil, nil])
      end

      it 'still reads the centiles that are published' do
        expect(female_20w[:p50]).to be_an(Integer)
      end
    end

    it 'freezes the collection of rows' do
      expect(rows).to be_frozen
    end

    it 'freezes each row' do
      expect(rows).to all(be_frozen)
    end

    context 'when a cell holds a decimal' do
      it 'coerces it to Float' do
        with_file('t.csv', "ga_weeks,z\n30,-1.5\n") do |path|
          expect(described_class.load_table(path).first[:z]).to eq(-1.5)
        end
      end
    end

    context 'when the file does not exist' do
      it 'raises MalformedReferenceData' do
        with_missing_file('absent.csv') do |path|
          expect { described_class.load_table(path) }
            .to raise_error(Biometry::MalformedReferenceData, /could not be read/)
        end
      end
    end
  end
end
