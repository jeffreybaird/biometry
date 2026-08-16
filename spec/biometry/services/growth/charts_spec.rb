# frozen_string_literal: true

# The chart registry, derived rather than typed out. Which standards this
# library reads, which formula each one pairs with, and which manifest each one
# reads are all already stated in data/; a hardcoded map beside them is a second
# copy that can disagree with the first, silently, the moment a manifest moves.
#
# So the registry is a function of the loaded manifests. A growth manifest is
# one that names a `paired_formula` — hadlock_1985 publishes formulas and
# acog_redating publishes neither, and neither becomes a chart.
#
# Hadlock 1991 is the case that keeps this from being a rename of the manifest
# keys: one manifest, two charts, because the paper contradicts itself on its
# own dispersion and both readings are served. The two chart ids come from the
# manifest's `variants` block, and so do the two adapters, which must be built
# on different variants or the dispute is reported as one number twice.
RSpec.describe Biometry::Services::Growth::Charts do
  subject(:charts) { described_class.new(manifests: manifests, tables: tables).call }

  let(:growth_manifests) { %i[hadlock_1991 intergrowth21 nichd who] }
  let(:manifests) { growth_manifests.to_h { |name| [name, manifest(name)] } }
  let(:tables) { { nichd: table('nichd'), who: table('who') } }

  def manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  # Both variants read the one 1991 manifest, so the id is the only thing that
  # tells them apart and the manifest is the only authority on what the ids are.
  def hadlock_ids
    manifests[:hadlock_1991][:variants].values.map { |variant| variant[:id].to_sym }
  end

  def manifest_for(id) = hadlock_ids.include?(id) ? manifests[:hadlock_1991] : manifests[id]

  def weeks(weeks, days = 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def efw(grams, formula: :hadlock_bpd_hc_ac_fl, inputs: %i[bpd hc ac fl])
    Biometry::Estimate.new(
      value: grams, unit: 'g', formula: formula, inputs: inputs,
      source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x',
                                           formula: formula),
      uncertainty: Biometry::Uncertainty.pooled(7.4)
    )
  end

  describe 'the charts it derives' do
    it 'serves one chart per growth manifest, and two for the contested one' do
      expect(charts.keys)
        .to match_array(%i[intergrowth21 nichd who] + hadlock_ids)
    end

    it 'names the Hadlock charts as the manifest\'s variants name themselves' do
      expect(charts.keys & hadlock_ids).to eq(hadlock_ids)
    end
  end

  describe 'the formula each chart pairs with' do
    it 'reads the pairing from the manifest rather than restating it' do
      expect(charts.transform_values { |entry| entry[:formula] })
        .to eq(charts.keys.to_h { |id| [id, manifest_for(id)[:paired_formula].to_sym] })
    end

    it 'pairs both Hadlock variants alike, the dispute being about the chart' do
      expect(charts.values_at(*hadlock_ids).map { |entry| entry[:formula] }.uniq.length)
        .to eq(1)
    end
  end

  describe 'the manifest each chart reads' do
    it 'carries the manifest the chart was derived from' do
      expect(charts.transform_values { |entry| entry[:manifest] })
        .to eq(charts.keys.to_h { |id| [id, manifest_for(id)] })
    end

    it 'hands both Hadlock variants the one paper they share' do
      expect(charts.values_at(*hadlock_ids).map { |entry| entry[:manifest] }.uniq.length)
        .to eq(1)
    end
  end

  describe 'the adapter each chart is read through' do
    it 'builds the adapter its standard is implemented by' do
      expected = { intergrowth21: Biometry::Services::Growth::Intergrowth,
                   nichd: Biometry::Services::Growth::Nichd,
                   who: Biometry::Services::Growth::Who }
                 .merge(hadlock_ids.to_h { |id| [id, Biometry::Services::Growth::Hadlock1991] })
      expect(charts.transform_values { |entry| entry[:adapter].class }).to eq(expected)
    end

    # Class alone would pass on a table adapter built without its table, which
    # is exactly the wiring this service owns.
    it 'hands the table standards their published table' do
      report = charts[:nichd][:adapter]
               .call(estimate: efw(1600, formula: :hadlock_hc_ac_fl, inputs: %i[hc ac fl]),
                     ga: weeks(32), stratum: :white)
      expect(report).to be_success
    end

    # The two Hadlock entries are one paper read two ways. Same weight, same
    # week, two percentiles — if they agree, one variant was built twice.
    it 'builds the two Hadlock adapters on different dispersion figures' do
      readings = hadlock_ids.map do |id|
        charts[id][:adapter].call(estimate: efw(1600), ga: weeks(32)).value!.value
      end
      expect(readings.uniq.length).to eq(2)
    end
  end

  describe 'the registry it returns' do
    it 'is frozen, being a description of data/ rather than a scratch hash' do
      expect(charts).to be_frozen
    end

    it 'freezes every entry too' do
      expect(charts.values.map(&:frozen?)).to all(be(true))
    end
  end

  context 'when the manifests include ones that publish no chart' do
    let(:manifests) do
      (growth_manifests + %i[hadlock_1985 acog_redating])
        .to_h { |name| [name, manifest(name)] }
    end

    it 'derives no chart from a manifest that names no paired formula' do
      expect(charts.keys).not_to include(:hadlock_1985, :acog_redating)
    end

    it 'derives the same charts it does without them' do
      expect(charts.keys)
        .to match_array(%i[intergrowth21 nichd who] + hadlock_ids)
    end
  end
end
