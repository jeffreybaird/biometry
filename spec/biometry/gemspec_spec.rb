# frozen_string_literal: true

# The packaging contract. Everything here is a property of the built gem rather
# than of any object in lib/, so it is asserted against the loaded
# Gem::Specification and nothing else.
#
# data/ is the reason this file exists. DATA_ROOT resolves relative to the gem
# root, so a manifest or table left out of spec.files is a file the loader
# raises on at runtime and no spec in this suite would notice -- the checkout
# has the file whether the gem ships it or not. The same holds, less quietly,
# for lib/ and for the executable.
#
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'the biometry gemspec' do
  subject(:gemspec) { Gem::Specification.load(gemspec_path.to_s) }

  let(:gemspec_path) { Biometry::ROOT / 'biometry.gemspec' }

  # The files as the checkout has them, listed the way spec.files lists them:
  # relative to the gem root.
  def checked_in(pattern)
    Dir.chdir(Biometry::ROOT) { Dir[pattern].select { |path| File.file?(path) } }
  end

  it 'loads as a Gem::Specification' do
    expect(gemspec).to be_a(Gem::Specification)
  end

  it 'is published under the name the executable is invoked by' do
    expect(gemspec.name).to eq('biometry')
  end

  it 'carries the version the library reports' do
    expect(gemspec.version.to_s).to eq(Biometry::VERSION)
  end

  describe 'the files it ships' do
    it 'includes every reference file under data/, which the loader reads at runtime' do
      expect(gemspec.files).to include(*checked_in('data/**/*'))
    end

    it 'includes every source file under lib/' do
      expect(gemspec.files).to include(*checked_in('lib/**/*.rb'))
    end
  end

  describe 'the executable it installs' do
    it 'takes its executables from exe/' do
      expect(gemspec.bindir).to eq('exe')
    end

    it 'installs biometry and nothing else' do
      expect(gemspec.executables).to eq(['biometry'])
    end
  end

  describe 'the dependencies it imposes on an installing host' do
    it 'requires dry-monads and csv at runtime, and nothing further' do
      runtime = gemspec.dependencies.select { |dependency| dependency.type == :runtime }
      expect(runtime.map(&:name).sort).to eq(%w[csv dry-monads])
    end
  end
end
# rubocop:enable RSpec/DescribeClass
