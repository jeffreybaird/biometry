# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Tier 3b (spec/oracle/) stays out of the default run on purpose: a mismatch
# there is a question for a human, not a regression to fix. See docs/FIXTURES.md.
RSpec::Core::RakeTask.new(:spec) do |t|
  t.exclude_pattern = 'spec/oracle/**/*_spec.rb'
end
RuboCop::RakeTask.new(:rubocop)

desc 'Tier 3b: FetalGPS chart agreement — corroboration, run deliberately'
RSpec::Core::RakeTask.new(:oracle) do |t|
  t.pattern = 'spec/oracle/**/*_spec.rb'
end

desc 'Fail if output calls appear outside presentation/'
task :no_stray_output do
  offenders = Dir.glob('lib/**/*.rb')
                 .reject { |path| path.include?('/presentation/') }
                 .flat_map do |path|
                   File.readlines(path).each_with_index.filter_map do |line, i|
                     "#{path}:#{i + 1}: #{line.strip}" if line.match?(/^\s*(puts|print|pp)\b/)
                   end
                 end

  next if offenders.empty?

  abort "Output calls outside presentation/:\n#{offenders.join("\n")}"
end

desc 'Check dependencies for known CVEs'
task :audit do
  sh 'bundle exec bundle-audit check --update'
end

desc 'Autocorrect safe RuboCop offenses'
RuboCop::RakeTask.new('rubocop:fix') do |t|
  t.options = ['--autocorrect']
end

desc 'Every check that must pass before a commit'
task :verify do
  ENV['COVERAGE_ENFORCE'] = '1'
  Rake::Task[:no_stray_output].invoke
  Rake::Task[:rubocop].invoke
  Rake::Task[:spec].invoke
  Rake::Task[:audit].invoke
end

task default: :verify
