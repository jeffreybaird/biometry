# frozen_string_literal: true

require_relative 'lib/biometry/version'

Gem::Specification.new do |spec|
  spec.name = 'biometry'
  spec.version = Biometry::VERSION
  spec.authors = ['Jeffrey Baird']
  spec.email = ['jeffreybaird@hey.com']

  spec.summary = 'Fetal biometry: dating, EFW and growth percentiles with provenance.'
  spec.description = 'Reports fetal measurements against published dating, EFW and growth ' \
                     'standards. Every value names the standard and formula that produced it. ' \
                     'No classification labels are ever emitted.'
  spec.homepage = 'https://github.com/jeffreybaird/rei_calc'
  spec.license = 'MIT'
  spec.required_ruby_version = '~> 3.3'

  # data/ ships in the gem: DATA_ROOT resolves relative to the installed gem
  # root, so a build without it fails only at runtime, at the first load.
  spec.files = Dir['lib/**/*.rb', 'data/**/*', 'exe/*', 'README.md', 'LICENSE*']
               .select { |f| File.file?(f) }
  spec.bindir = 'exe'
  spec.executables = ['biometry']
  spec.require_paths = ['lib']

  spec.add_dependency 'csv', '~> 3.3'
  spec.add_dependency 'dry-monads', '~> 1.6'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
