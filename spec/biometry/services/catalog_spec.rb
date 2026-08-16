# frozen_string_literal: true

# What this library serves, described rather than typed out. A web app needs to
# enumerate the standards, formulas and derivations on offer before a user has
# supplied anything, and every entry it shows has to name its paper.
#
# Everything the catalog says about a standard is already stated in data/ or in
# the service that owns the behaviour. A literal retyped into this spec would
# pass whether or not the catalog reads the manifest, so each expectation is
# built from the loaded manifest, from the chart registry, or from the dating
# service's own constants.
RSpec.describe Biometry::Services::Catalog do
  subject(:catalog) { described_class.new(manifests: manifests).call }

  let(:manifests) { Biometry::Loader::MANIFESTS.to_h { |name| [name, manifest(name)] } }
  let(:charts) do
    Biometry::Services::Growth::Charts.new(
      manifests: manifests, tables: { nichd: table('nichd'), who: table('who') }
    ).call
  end

  def manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  # Both Hadlock 1991 variants read the one manifest, so the id is the only
  # thing that tells them apart and the manifest is the only authority on what
  # the ids are.
  def hadlock_ids
    manifests[:hadlock_1991][:variants].values.map { |variant| variant[:id].to_sym }
  end

  def manifest_for(id) = hadlock_ids.include?(id) ? manifests[:hadlock_1991] : manifests[id]

  def standard_for(id) = catalog.growth_standards.find { |entry| entry.id == id }

  def formula_for(id) = catalog.efw_formulas.find { |entry| entry.id == id }

  def method_for(derivation) = catalog.dating_methods.find { |entry| entry.derivation == derivation }

  def source_of(id, *keys) = keys.map { |key| manifest_for(id).dig(:source, key) }

  def by_id(field) = catalog.growth_standards.to_h { |entry| [entry.id, entry.public_send(field)] }

  describe 'the growth standards it lists' do
    it 'lists one per chart the registry derives, the contested paper twice' do
      expect(catalog.growth_standards.map(&:id)).to match_array(charts.keys)
    end

    it 'names the manifest each descriptor was read from' do
      expect(by_id(:standard))
        .to eq(charts.keys.to_h { |id| [id, hadlock_ids.include?(id) ? :hadlock_1991 : id] })
    end

    it 'names which reading of the contested paper a Hadlock chart is' do
      variants = manifests[:hadlock_1991][:variants]
                 .to_h { |key, description| [description[:id].to_sym, key] }
      expect(by_id(:variant)).to eq(charts.keys.to_h { |id| [id, variants[id]] })
    end
  end

  describe 'what it says each standard is' do
    it 'reads kind, type and access from the manifest that publishes them' do
      expect(catalog.growth_standards.to_h { |entry| [entry.id, [entry.kind, entry.type, entry.access]] })
        .to eq(charts.keys.to_h { |id| [id, source_of(id, :kind, :type, :access).map { |v| v&.to_sym }] })
    end

    it 'carries the range of gestations the paper covers' do
      expect(by_id(:valid_ga_weeks)).to eq(charts.keys.to_h { |id| [id, manifest_for(id)[:valid_ga_weeks]] })
    end

    # NICHD's manifest states no ga_units, and an absent unit is not
    # `completed_weeks` by default — the catalog reports what the paper says.
    it 'carries the gestational age convention where the paper states one' do
      expect(by_id(:ga_units)).to eq(charts.keys.to_h { |id| [id, manifest_for(id)[:ga_units]&.to_sym] })
    end
  end

  describe 'the citation it carries for each standard' do
    it 'quotes the citation, DOI and PMID the manifest publishes' do
      expect(catalog.growth_standards.to_h { |entry| [entry.id, [entry.citation, entry.doi, entry.pmid]] })
        .to eq(charts.keys.to_h { |id| [id, source_of(id, :citation, :doi, :pmid)] })
    end

    # Hadlock 1991 predates the DOI. Reporting an empty string, or borrowing
    # the 1985 DOI, would send a reader to the wrong paper.
    it 'leaves the DOI absent for a paper that has none' do
      expect(standard_for(hadlock_ids.first).doi).to be_nil
      expect(standard_for(hadlock_ids.first).pmid).to eq(manifests[:hadlock_1991].dig(:source, :pmid))
    end

    it 'carries the DOI for a paper that has one' do
      expect(standard_for(:intergrowth21).doi).not_to be_nil
    end
  end

  describe 'what it says can be asked of each standard' do
    it 'quotes the centiles block verbatim, published and computable alike' do
      expect(by_id(:centiles)).to eq(charts.keys.to_h { |id| [id, manifest_for(id)[:centiles]] })
    end

    it 'quotes the stratification block verbatim' do
      expect(by_id(:stratification)).to eq(charts.keys.to_h { |id| [id, manifest_for(id)[:stratification]] })
    end

    it 'pairs each standard with the formula the registry pairs it with' do
      expect(by_id(:paired_formula)).to eq(charts.transform_values { |entry| entry[:formula] })
    end
  end

  describe 'what it says is wrong with each standard' do
    it 'carries the manifest\'s known issues rather than a summary of them' do
      expect(by_id(:known_issues)).to eq(charts.keys.to_h { |id| [id, manifest_for(id)[:known_issues]] })
    end

    # The two Hadlock charts share a paper and a list of known issues. What
    # separates them is the variant's own note, and a catalog that dropped it
    # would offer a consumer two entries it cannot tell apart.
    it 'carries each variant\'s note, and none where the manifest has no variants' do
      notes = manifests[:hadlock_1991][:variants]
              .to_h { |_, description| [description[:id].to_sym, description[:note]] }
      expect(by_id(:variant_note)).to eq(charts.keys.to_h { |id| [id, notes[id]] })
    end
  end

  describe 'the weight formulas it lists' do
    let(:hadlock_formulas) { manifests[:hadlock_1985][:efw_formulas] }

    it 'lists every formula both publishing manifests offer' do
      expected = hadlock_formulas.values.map { |entry| entry[:id].to_sym }
      expect(catalog.efw_formulas.map(&:id))
        .to match_array(expected + [manifests[:intergrowth21][:efw][:id].to_sym])
    end

    it 'names the measurements each formula is read from' do
      expect(catalog.efw_formulas.to_h { |entry| [entry.id, entry.requires] })
        .to eq(hadlock_formulas.values.to_h { |e| [e[:id].to_sym, e[:requires].map(&:to_sym)] }
                               .merge(intergrowth_requires))
    end

    it 'quotes the equation as the manifest prints it' do
      expect(catalog.efw_formulas.to_h { |entry| [entry.id, entry.equation] })
        .to eq(hadlock_formulas.values.to_h { |e| [e[:id].to_sym, e[:equation]] }
                               .merge(intergrowth_equation))
    end

    def intergrowth_requires
      efw = manifests[:intergrowth21][:efw]
      { efw[:id].to_sym => efw[:requires].map(&:to_sym) }
    end

    def intergrowth_equation
      efw = manifests[:intergrowth21][:efw]
      { efw[:id].to_sym => efw[:equation] }
    end
  end

  describe 'the citation it carries for each formula' do
    def source_citation(name)
      manifests[name][:source].values_at(:citation, :doi, :pmid)
    end

    def cited(id)
      [formula_for(id).citation, formula_for(id).doi, formula_for(id).pmid]
    end

    it 'cites the 1985 paper for the formulas the 1985 paper publishes' do
      id = manifests[:hadlock_1985][:efw_formulas].values.first[:id].to_sym
      expect(cited(id)).to eq(source_citation(:hadlock_1985))
    end

    it 'cites INTERGROWTH for the formula INTERGROWTH publishes' do
      expect(cited(manifests[:intergrowth21][:efw][:id].to_sym))
        .to eq(source_citation(:intergrowth21))
    end
  end

  describe 'the dating methods it lists' do
    let(:lmp) { Biometry::Services::Dating::Lmp }
    let(:transfer) { Biometry::Services::Dating::Transfer }

    it 'lists the derivations the library dates a pregnancy by' do
      expect(catalog.dating_methods.map(&:derivation))
        .to contain_exactly(lmp::DERIVATION, transfer::DERIVATION)
    end

    it 'names the standard each derivation follows' do
      expect(catalog.dating_methods.to_h { |entry| [entry.derivation, entry.standard] })
        .to eq(lmp::DERIVATION => lmp::STANDARD, transfer::DERIVATION => transfer::STANDARD)
    end

    it 'carries the citation the service itself carries' do
      expect(method_for(lmp::DERIVATION).citation).to eq(lmp::CITATION)
      expect(method_for(transfer::DERIVATION).citation).to eq(transfer::CITATION)
    end
  end

  describe 'the redating policy it describes' do
    let(:redating) { Biometry::Services::Dating::Redating }

    it 'names the standard the redating service applies' do
      expect(catalog.redating_policy.standard).to eq(redating::STANDARD)
    end

    it 'cites the committee opinion the thresholds come from' do
      expect(catalog.redating_policy.citation)
        .to eq(manifests[:acog_redating].dig(:source, :citation))
    end

    # A consumer offering redating has to be able to say what is unverified
    # about the policy it is offering.
    it 'carries the policy\'s known issues verbatim' do
      expect(catalog.redating_policy.known_issues).to eq(manifests[:acog_redating][:known_issues])
    end
  end

  describe 'the catalog it returns' do
    it 'is frozen, being a description of data/ rather than a scratch object' do
      expect(catalog).to be_frozen
    end

    it 'freezes every list it hands out' do
      expect([catalog.growth_standards, catalog.efw_formulas, catalog.dating_methods]
               .map(&:frozen?)).to all(be(true))
    end

    it 'freezes the redating policy too' do
      expect(catalog.redating_policy).to be_frozen
    end
  end

  # The catalog is a function of the manifests it is given. Fabricated
  # manifests are the only way to tell "read from data/" apart from "typed out
  # beside data/ and currently in agreement".
  context 'when the manifests describe something other than the published papers' do
    let(:manifests) do
      { hadlock_1985: { source: { citation: 'Fabricated 1985', pmid: '000' },
                        efw_formulas: { only: { id: 'only', requires: %w[ac],
                                                equation: 'W = AC' } } },
        intergrowth21: { source: { citation: 'Fabricated IG' },
                         paired_formula: 'only', ga_units: 'exact_weeks',
                         valid_ga_weeks: [20, 30], centiles: { published: [50] },
                         stratification: { field: nil }, known_issues: [],
                         efw: { id: 'ig_only', requires: %w[ac hc], equation: 'W = AC + HC' } },
        acog_redating: { source: { citation: 'Fabricated ACOG' }, known_issues: [] } }
    end

    it 'lists the standard the fabricated manifest publishes, and only that one' do
      expect(catalog.growth_standards.map(&:id)).to eq([:intergrowth21])
    end

    it 'describes an unvarianted standard as having no variant' do
      expect([standard_for(:intergrowth21).variant, standard_for(:intergrowth21).variant_note])
        .to eq([nil, nil])
    end

    # A manifest that states no type and no access is not descriptive-and-table
    # by default. The catalog reports what the paper states, and absent is nil.
    it 'reports no type and no access where the manifest states neither' do
      expect([standard_for(:intergrowth21).type, standard_for(:intergrowth21).access])
        .to eq([nil, nil])
    end

    it 'quotes the fabricated citation rather than the published one' do
      expect(standard_for(:intergrowth21).citation).to eq('Fabricated IG')
    end

    it 'lists the fabricated formulas' do
      expect(catalog.efw_formulas.map(&:id)).to match_array(%i[only ig_only])
    end

    it 'cites the fabricated redating policy' do
      expect(catalog.redating_policy.citation).to eq('Fabricated ACOG')
    end
  end
end
