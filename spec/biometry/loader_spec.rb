# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

# The documented entry point for everything that is not the CLI. A web app
# holds one Context for the life of the process rather than re-reading data/ on
# every request, so the read happens here, once, in the imperative shell.
#
# This spec may touch the filesystem: the loader is the shell, and reading data/
# is the behaviour under test. Nothing it returns may be reloaded lazily by a
# service later — what comes back is the whole of data/, parsed and frozen.
RSpec.describe Biometry, '.load' do
  subject(:context) { described_class.load }

  let(:manifest_names) { %i[acog_redating hadlock_1985 hadlock_1991 intergrowth21 nichd who] }
  let(:table_names) { %i[nichd who] }

  def manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  # A data_root of our own, so the refusal paths are exercised without editing
  # data/, which is read-only.
  def with_data_root
    Dir.mktmpdir do |dir|
      root = Pathname.new(dir) / 'data'
      FileUtils.cp_r(Biometry::DATA_ROOT.to_s, root.to_s)
      yield root
    end
  end

  it 'returns a Context' do
    expect(context).to be_a(Biometry::Context)
  end

  describe 'the manifests it reads' do
    it 'reads every manifest committed under data/' do
      expect(context.manifests.keys).to match_array(manifest_names)
    end

    # Equal to what the loader below it returns, rather than to values retyped
    # here: a constant this spec spelled out would be a second transcription.
    it 'reads each one as ReferenceData reads it' do
      expect(context.manifests).to eq(manifest_names.to_h { |name| [name, manifest(name)] })
    end
  end

  describe 'the tables it reads' do
    it 'reads the percentile table of every standard published as one' do
      expect(context.tables.keys).to match_array(table_names)
    end

    it 'reads each one as ReferenceData reads it' do
      expect(context.tables).to eq(table_names.to_h { |name| [name, table(name)] })
    end
  end

  # Pruning silently would be worse than refusing: a consumer has to be able to
  # say what is unavailable and why, and the CLI is not the only consumer.
  describe 'the entries it reports as dropped' do
    it 'answers for every manifest it read, so no silence reads as nothing lost' do
      expect(context.dropped.keys).to match_array(manifest_names)
    end

    it 'names the pruned paths of each as a list' do
      expect(context.dropped.values).to all(be_an(Array))
    end

    it 'drops nothing from the data as it stands today' do
      expect(context.dropped.values).to all(be_empty)
    end
  end

  # A Context is held for the life of a process and shared across requests, so
  # nothing reachable from it may be mutated by one caller under another.
  describe 'what it returns' do
    it 'is frozen' do
      expect(context).to be_frozen
    end

    it 'freezes the manifests it exposes' do
      expect(context.manifests).to be_frozen
    end

    it 'freezes the tables it exposes' do
      expect(context.tables).to be_frozen
    end

    it 'freezes the record of what it dropped' do
      expect(context.dropped).to be_frozen
    end
  end

  context 'when a data root is given' do
    it 'reads the manifests from there rather than from the default' do
      with_data_root do |root|
        expect(described_class.load(data_root: root).manifests)
          .to eq(context.manifests)
      end
    end

    it 'reads the tables from there too' do
      with_data_root do |root|
        expect(described_class.load(data_root: root).tables).to eq(context.tables)
      end
    end
  end

  # A file marked unverified is a developer error, not a runtime condition: the
  # loader raises rather than returning a Result nobody should branch on, and it
  # does so before any service is wired on values nobody confirmed.
  context 'when a manifest in that root is marked unverified' do
    it 'raises UnverifiedReferenceData rather than building a Context' do
      with_data_root do |root|
        File.write(root / 'nichd.yml', "verified: false\nvalid_ga_weeks: [14, 40]\n")
        expect { described_class.load(data_root: root) }
          .to raise_error(Biometry::UnverifiedReferenceData, /marked unverified/)
      end
    end
  end
end
