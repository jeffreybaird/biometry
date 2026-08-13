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

  # load_manifest returns [data, dropped]. Most examples care only about the
  # data half; the pruning contract has its own section below.
  def manifest(name)
    described_class.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  describe '.load_manifest' do
    it 'loads every manifest committed under data/' do
      names = %w[hadlock_1985 hadlock_1991 intergrowth21 nichd who acog_redating]
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
      it 'returns the parsed mapping alongside the entries it dropped' do
        with_file('ok.yml', "verified: true\nvalid_ga_weeks: [14, 40]\n") do |path|
          expect(described_class.load_manifest(path))
            .to eq([{ verified: true, valid_ga_weeks: [14, 40] }, []])
        end
      end
    end

    context 'when the file carries no verified flag at all' do
      it 'loads it, because only an explicit false is a refusal' do
        with_file('bare.yml', "valid_ga_weeks: [14, 40]\n") do |path|
          expect(described_class.load_manifest(path).first).to eq(valid_ga_weeks: [14, 40])
        end
      end
    end

    # Pruning rather than guarding: an unverified entry never reaches a
    # service, so "unverified" collapses into "absent" and each adapter's
    # existing missing-entry path handles it, with no obligation for a future
    # adapter to remember. Pruning silently would be worse than the guard was,
    # so the paths removed come back alongside the data.
    describe 'the entries it prunes' do
      let(:nested) do
        <<~YAML
          efw_formulas:
            hc_ac_fl:
              equation: "log10(W) = 1 + 2*AC"
              verified: true
            bpd_hc_ac_fl:
              equation: "log10(W) = 1 + 2*BPD"
              verified: false
        YAML
      end

      context 'when a nested entry is marked unverified' do
        it 'removes it, so no service can be handed an unconfirmed constant' do
          with_file('n.yml', nested) do |path|
            data, = described_class.load_manifest(path)
            expect(data[:efw_formulas].keys).to eq(%i[hc_ac_fl])
          end
        end

        it 'names the path it removed' do
          with_file('n.yml', nested) do |path|
            expect(described_class.load_manifest(path).last)
              .to eq([%i[efw_formulas bpd_hc_ac_fl]])
          end
        end

        it 'leaves its verified siblings intact' do
          with_file('n.yml', nested) do |path|
            data, = described_class.load_manifest(path)
            expect(data.dig(:efw_formulas, :hc_ac_fl, :equation)).to eq('log10(W) = 1 + 2*AC')
          end
        end
      end

      # ACOG's redating thresholds are a list of bands, so an unverified
      # element of an array has to go the same way an unverified formula does.
      context 'when an entry inside a list is marked unverified' do
        let(:bands) do
          <<~YAML
            bands:
              - ga_upper_days: 97
                verified: true
              - ga_upper_days: 153
                verified: false
              - ga_upper_days: 195
                verified: true
                discretionary:
                  threshold_days: 14
                  verified: false
          YAML
        end

        it 'removes it, keeping the verified bands in their published order' do
          with_file('b.yml', bands) do |path|
            data, = described_class.load_manifest(path)
            expect(data[:bands].map { |band| band[:ga_upper_days] }).to eq([97, 195])
          end
        end

        it 'names it by its index in the list as published' do
          with_file('b.yml', bands) do |path|
            expect(described_class.load_manifest(path).last).to include([:bands, 1])
          end
        end

        it 'walks the bands it keeps, pruning an unverified entry inside one' do
          with_file('b.yml', bands) do |path|
            data, = described_class.load_manifest(path)
            expect(data[:bands].last).not_to have_key(:discretionary)
          end
        end

        it 'names a nested removal by the path through the list' do
          with_file('b.yml', bands) do |path|
            expect(described_class.load_manifest(path).last)
              .to include([:bands, 2, :discretionary])
          end
        end
      end

      context 'when a top-level section is marked unverified' do
        it 'removes the section and names it by its one-element path' do
          yaml = "hadlock_1991:\n  verified: false\nvalid_ga_weeks: [10, 40]\n"
          with_file('t.yml', yaml) do |path|
            expect(described_class.load_manifest(path))
              .to eq([{ valid_ga_weeks: [10, 40] }, [[:hadlock_1991]]])
          end
        end
      end

      context 'when every entry is verified' do
        it 'drops nothing' do
          with_file('all.yml', "median:\n  verified: true\n") do |path|
            expect(described_class.load_manifest(path).last).to be_empty
          end
        end
      end

      context "when an entry's verified key holds prose rather than a flag" do
        it 'keeps it, because only an explicit false is a refusal' do
          with_file('p.yml', "median:\n  verified: >\n    Reproduces Table 1.\n") do |path|
            expect(described_class.load_manifest(path).last).to be_empty
          end
        end
      end

      # Nothing under data/ is unverified today, so pruning is a no-op against
      # real data and every manifest reaches its service whole. The tmpdir
      # cases above are what keeps the behaviour pinned for when that changes.
      context 'when the manifests are the ones committed under data/' do
        it 'drops nothing from any of them' do
          dropped = Biometry::DATA_ROOT.glob('*.yml').map do |path|
            described_class.load_manifest(path).last
          end
          expect(dropped).to all(be_empty)
        end

        it 'hands a service every formula hadlock_1985.yml carries' do
          data, = described_class.load_manifest(Biometry::DATA_ROOT / 'hadlock_1985.yml')
          expect(data[:efw_formulas].keys).to eq(
            %i[hadlock_ac_fl hadlock_bpd_ac_fl hadlock_hc_ac_fl hadlock_bpd_hc_ac_fl]
          )
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
