# frozen_string_literal: true

# What a non-CLI consumer holds: the loaded reference data, and the services
# already wired on it. Every answer here must be the answer the service itself
# gives — the Context is a facade over data/ having been read once, not a second
# place where clinical behaviour is decided.
#
# So each example calls the service directly and compares. A number retyped here
# would pass whether or not the wiring is right.
RSpec.describe Biometry::Context do
  subject(:context) { Biometry.load }

  let(:scan) do
    measurements = { bpd: 85, hc: 290, ac: 260, fl: 55 }.map do |kind, mm|
      Biometry::Measurement.new(kind: kind, mm: mm)
    end
    Biometry::Scan.new(date: Date.new(2026, 8, 13), measurements: measurements)
  end

  def manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  describe '#dating' do
    let(:request) do
      { reference_date: Date.new(2026, 8, 13), lmp: Date.new(2026, 1, 1), cycle_length: 28,
        transfer_date: Date.new(2026, 1, 15), embryo_day: 5 }
    end
    let(:directly) { Biometry::Services::Dating::AllDerivations.new.call(**request) }

    def edds(result) = result.value!.transform_values { |each| each.success? && each.value!.edd }

    it 'offers the derivations the service offers' do
      expect(context.dating(**request).value!.keys).to eq(directly.value!.keys)
    end

    it 'dates the pregnancy as the service dates it' do
      expect(edds(context.dating(**request))).to eq(edds(directly))
    end

    it 'refuses what the service refuses, for the same reason' do
      unsupplied = request.merge(lmp: nil)
      expect(context.dating(**unsupplied).value![:lmp].failure)
        .to eq(Biometry::Services::Dating::AllDerivations.new.call(**unsupplied)
                                                         .value![:lmp].failure)
    end
  end

  describe '#weights' do
    let(:directly) do
      Biometry::Services::Weight::AllFormulas
        .new(hadlock: manifest('hadlock_1985'), intergrowth: manifest('intergrowth21'))
        .call(scan)
    end

    def values(result) = result.value!.transform_values { |each| each.value!.value }

    it 'offers every formula the service offers' do
      expect(context.weights(scan).value!.keys).to match_array(directly.value!.keys)
    end

    it 'weighs the fetus as the service weighs it' do
      expect(values(context.weights(scan))).to eq(values(directly))
    end
  end

  describe '#charts' do
    let(:growth_manifests) { %i[hadlock_1991 intergrowth21 nichd who] }
    let(:directly) do
      Biometry::Services::Growth::Charts.new(
        manifests: growth_manifests.to_h { |name| [name, manifest(name)] },
        tables: { nichd: table('nichd'), who: table('who') }
      ).call
    end

    it 'serves the charts the registry derives from the manifests' do
      expect(context.charts.keys).to match_array(directly.keys)
    end

    it 'pairs each chart with the formula the registry pairs it with' do
      expect(context.charts.transform_values { |entry| entry[:formula] })
        .to eq(directly.transform_values { |entry| entry[:formula] })
    end

    it 'is frozen, being a description of data/ rather than a scratch hash' do
      expect(context.charts).to be_frozen
    end
  end

  # What a web app enumerates before a user has supplied anything. The Context
  # holds it so data/ is described once per process, but it describes the same
  # thing the service does — a catalog assembled here would be a second answer.
  describe '#catalog' do
    let(:directly) { Biometry::Services::Catalog.new(manifests: context.manifests).call }

    it 'lists the standards the service lists' do
      expect(context.catalog.growth_standards.map(&:id))
        .to match_array(directly.growth_standards.map(&:id))
    end

    it 'cites each standard as the service cites it' do
      expect(context.catalog.growth_standards.map { |entry| [entry.id, entry.citation] })
        .to match_array(directly.growth_standards.map { |entry| [entry.id, entry.citation] })
    end

    it 'lists the formulas the service lists' do
      expect(context.catalog.efw_formulas.map(&:id))
        .to match_array(directly.efw_formulas.map(&:id))
    end

    it 'lists the dating methods the service lists, cited alike' do
      expect(context.catalog.dating_methods.map { |entry| [entry.derivation, entry.citation] })
        .to match_array(directly.dating_methods.map { |entry| [entry.derivation, entry.citation] })
    end

    it 'describes the redating policy as the service describes it' do
      expect(context.catalog.redating_policy.citation).to eq(directly.redating_policy.citation)
    end

    it 'is frozen, being a description of data/ rather than a scratch object' do
      expect(context.catalog).to be_frozen
    end
  end

  # The whole report, in one call, from data/ read once. What a web request
  # actually asks for — and the answer must be the builder's answer, wired on
  # this Context's manifests and tables, not a composition assembled here.
  describe '#report' do
    let(:request) do
      { scans: [scan], ga: Biometry::GestationalAge.from(weeks: 32, days: 0),
        at: Date.new(2026, 8, 13), lmp: Date.new(2026, 1, 1), cycle_length: 28,
        transfer_date: Date.new(2026, 1, 15), embryo_day: 5, sex: :female }
    end
    let(:directly) do
      Biometry::Services::Report::Builder
        .new(manifests: context.manifests, tables: context.tables).call(**request)
    end

    def edds(report) = report.dating.transform_values { |each| each.success? && each.value!.edd }

    def standards(report) = report.studies.flat_map { |study| study.growth.map { |r| r[:standard] } }

    it 'answers with the report the builder builds' do
      expect(context.report(**request)).to be_a(Biometry::Report)
    end

    it 'dates the pregnancy as the builder dates it' do
      expect(edds(context.report(**request))).to eq(edds(directly))
    end

    it 'reads the same charts, study for study' do
      expect(standards(context.report(**request))).to eq(standards(directly))
    end

    it 'says whether anything could be reported, as the builder says it' do
      expect(context.report(**request).reportable?).to eq(directly.reportable?)
    end

    it 'carries no redating unless one was asked for' do
      expect(context.report(**request).redating).to be_nil
    end
  end

  # A Context outlives a request. Two callers asking the same question of the
  # same Context must get the same answer, whichever asked first.
  describe 'asking the same question twice' do
    let(:request) do
      { reference_date: Date.new(2026, 8, 13), lmp: Date.new(2026, 1, 1), cycle_length: 28,
        transfer_date: Date.new(2026, 1, 15), embryo_day: 5 }
    end

    it 'dates the pregnancy the same way' do
      first = context.dating(**request).value![:lmp].value!.edd
      expect(context.dating(**request).value![:lmp].value!.edd).to eq(first)
    end

    it 'weighs the fetus the same way' do
      first = context.weights(scan).value!.transform_values { |each| each.value!.value }
      expect(context.weights(scan).value!.transform_values { |each| each.value!.value })
        .to eq(first)
    end

    it 'serves the same charts, and still frozen after a caller has held them' do
      first = context.charts
      expect([context.charts.keys, context.charts.frozen?]).to eq([first.keys, true])
    end

    it 'describes itself the same way, the catalog being memoized not rebuilt' do
      first = context.catalog
      expect(context.catalog.growth_standards.map(&:id)).to eq(first.growth_standards.map(&:id))
    end
  end
end
