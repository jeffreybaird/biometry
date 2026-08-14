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

  # The transcription guard for data/acog_redating.yml, and the only one those
  # numbers will ever have.
  #
  # Every other constant in this library has an independent check: a worked
  # example the equation reproduces, a table the formula regenerates, or a
  # second file quoting the same figure. ACOG's redating thresholds have none.
  # They were reconstructed rather than transcribed, `fixtures:` is empty, and
  # a transposed digit here produces a green suite and a wrong clinical answer.
  #
  # So these examples assert the relationships the guideline implies rather
  # than the values, which no spec may retype: bands contiguous with no gap and
  # no overlap, windows well ordered, thresholds that never narrow as gestation
  # advances, and the two cross-references the file happens to carry — a band's
  # id names its own weeks and its own measurement, which is the closest thing
  # to a second source that exists for these numbers.
  #
  # They live with the loader because they must hold whether or not any service
  # reads them yet, and they must fail the moment data/ changes underneath one.
  describe 'the ACOG redating thresholds' do
    subject(:bands) { redating[:bands] }

    let(:redating) { manifest('acog_redating') }

    def days(edge) = edge && ((edge[:weeks] * 7) + edge[:days])

    def window(band) = [days(band[:ga_from]), days(band[:ga_to])]

    def closed = bands.reject { |band| band[:ga_to].nil? }

    def thresholds = bands.map { |band| band[:threshold_days] }

    it 'publishes a band list in the order the bands are to be searched' do
      expect(bands.map { |band| band[:id] }).to all(be_a(String))
    end

    it 'gives every band a threshold in whole positive days' do
      expect(thresholds).to all(be_an(Integer).and(be_positive))
    end

    # A gap swallows a gestation and reports nothing; an overlap lets the first
    # match hide a band that would have answered differently.
    it 'runs the bands contiguously, with no gap and no overlap between them' do
      starts = bands.drop(1).map { |band| days(band[:ga_from]) }
      ends = closed.map { |band| days(band[:ga_to]) }
      expect(starts).to eq(ends.map { |last_day| last_day + 1 })
    end

    it 'starts the first band at day zero, so no gestation falls below them all' do
      expect(days(bands.first[:ga_from])).to eq(0)
    end

    it 'leaves the last band open-ended, so no gestation falls above them all' do
      expect(bands.last[:ga_to]).to be_nil
    end

    it 'orders every window, so no band ends before it begins' do
      expect(closed.map { |band| window(band) }).to all(satisfy { |from, to| from < to })
    end

    it 'begins every band on a whole week' do
      expect(bands.map { |band| band[:ga_from][:days] }).to all(eq(0))
    end

    it 'ends every closed band on the last day of a week' do
      expect(closed.map { |band| band[:ga_to][:days] }).to all(eq(6))
    end

    # Ultrasound dating degrades as pregnancy advances, so the tolerance can
    # only widen. A threshold that narrows is a transposition.
    it 'never narrows a threshold as the gestation advances' do
      expect(thresholds.each_cons(2).map { |early, late| late - early }).to all(be >= 0)
    end

    it 'widens overall, from the earliest band to the latest' do
      expect(thresholds.last).to be > thresholds.first
    end

    # The one cross-check the file carries: the id names the weeks, and the
    # window states them. A digit transposed in either disagrees with the other.
    it 'agrees with the weeks its own id names' do
      named = bands.select { |band| band[:id].match?(/_(\d+)_(\d+)\z/) }
      expect(named.map { |band| window(band) })
        .to eq(named.map { |band| band[:id].scan(/\d+/).map { |week| week.to_i * 7 } }
                    .map { |from, to| [from, to + 6] })
    end

    it 'agrees with the week its open-ended id names' do
      open = bands.select { |band| band[:id] =~ /_(\d+)_plus\z/ }
      expect(open.map { |band| window(band) })
        .to eq(open.map { |band| [band[:id][/\d+/].to_i * 7, nil] })
    end

    it 'measures each band with the instrument its id names' do
      expect(bands.map { |band| band[:measurement] })
        .to eq(bands.map { |band| band[:id].split('_').first })
    end

    it 'moves from crown-rump length to biometry once and never back' do
      instruments = bands.map { |band| band[:measurement] }
      expect(instruments.chunk_while { |a, b| a == b }.to_a.length).to eq(instruments.uniq.length)
    end

    describe 'the discretionary zone' do
      subject(:zone) { zoned[:discretionary_zone] }

      let(:zoned) { ComposedReport.band_with_zone }

      it 'is published by exactly one band' do
        expect(bands.count { |band| band[:discretionary_zone] }).to eq(1)
      end

      it 'orders its bounds, so the zone is a window rather than a point' do
        expect(zone[:from_days]).to be < zone[:to_days]
      end

      # The zone's upper bound and the band's threshold are the same day: above
      # it the guideline redates, and the zone is what stands between a bare
      # threshold and a 12-day discrepancy reading as "keep".
      it 'runs up to its own band\'s threshold' do
        expect(zone[:to_days]).to eq(zoned[:threshold_days])
      end

      it 'opens no earlier than the threshold of the band before it' do
        earlier = bands[bands.index(zoned) - 1]
        expect(zone[:from_days]).to be >= earlier[:threshold_days]
      end

      it 'counts in whole positive days' do
        expect(zone.values_at(:from_days, :to_days)).to all(be_an(Integer).and(be_positive))
      end
    end

    describe 'the caveats' do
      subject(:caveats) { redating[:caveats] }

      it 'names only bands the file publishes' do
        named = caveats.values.flat_map { |caveat| caveat[:applies_to] }
        expect(named).to all(satisfy { |id| bands.any? { |band| band[:id] == id } })
      end

      # Both directions: a band naming a caveat that names it back. A typo in
      # either reference leaves a caveat that never prints or a band that
      # points at nothing.
      it 'is named back by every band that carries one' do
        carried = bands.select { |band| band[:caveat] }
        expect(carried).to all(satisfy { |band| caveats[band[:caveat].to_sym][:applies_to].include?(band[:id]) })
      end

      it 'carries wording for every caveat a band refers to' do
        referred = bands.filter_map { |band| band[:caveat]&.to_sym }.uniq
        expect(referred.map { |id| caveats[id][:text] })
          .to all(be_a(String).and(satisfy { |text| !text.strip.empty? }))
      end

      # Third-trimester dating carries the widest error, so the caveat belongs
      # to the band with no upper edge rather than to one in the middle.
      it 'attaches the third-trimester caveat to the open-ended band' do
        expect(ComposedReport.band_with_caveat).to eq(bands.last)
      end

      # The one place this file states a threshold twice. The caveat gives the
      # magnitude of third-trimester dating error in prose, and the band's
      # threshold is the lower end of it — so these two numbers check each
      # other, which is more than any other threshold here has. If a correction
      # ever moves one without the other, this fails and a human reads both.
      it 'agrees with the error its own caveat states in words' do
        band = ComposedReport.band_with_caveat
        stated = caveats[band[:caveat].to_sym][:text][%r{\+/-(\d+) to (\d+) days}, 1]
        expect(band[:threshold_days]).to eq(stated.to_i)
      end
    end

    describe 'the clinical rules' do
      subject(:rules) { redating[:rules] }

      it 'publishes wording for every rule it names' do
        expect(rules.values.map { |rule| rule[:text] })
          .to all(be_a(String).and(satisfy { |text| !text.strip.empty? }))
      end

      # The proximity is a number, and it lives only inside this prose. Read it
      # from there rather than retyping it; see the note in the report about
      # promoting it to a key of its own.
      it 'states the boundary proximity in whole days' do
        expect(rules.dig(:boundary_sensitivity, :text)[/within (\d+) days/, 1].to_i).to be_positive
      end

      it 'keeps that proximity narrower than the narrowest band' do
        proximity = rules.dig(:boundary_sensitivity, :text)[/within (\d+) days/, 1].to_i
        widths = closed.map { |band| days(band[:ga_to]) - days(band[:ga_from]) + 1 }
        expect(widths.min).to be > proximity
      end
    end

    # The band is selected by the gestation being tested, not by the new
    # ultrasound estimate. Getting this backwards is quietly wrong in exactly
    # the window where redating matters most.
    it 'records which gestation selects the band' do
      expect(redating[:band_indexed_on]).to eq('established_ga')
    end

    it 'reaches a service whole, with no band, zone, caveat or rule pruned' do
      expect(described_class.load_manifest(Biometry::DATA_ROOT / 'acog_redating.yml').last)
        .to be_empty
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
