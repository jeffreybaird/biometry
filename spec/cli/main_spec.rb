# frozen_string_literal: true

require 'stringio'
require 'biometry/cli/main'

RSpec.describe Biometry::CLI::Main do
  subject(:cli) { described_class.new(stdout: stdout, stderr: stderr) }

  let(:stdout) { StringIO.new }
  let(:stderr) { StringIO.new }

  %w[-h --help help].each do |flag|
    context "when asked for help with #{flag}" do
      it 'exits 0, prints usage on stdout and says nothing on stderr' do
        status = cli.call([flag])
        expect(status).to eq(0)
        expect(stdout.string).to include('Usage: biometry <command> [options]')
        expect(stderr.string).to be_empty
      end
    end
  end

  context 'when given no arguments at all' do
    it 'exits 0, prints usage on stdout and says nothing on stderr' do
      status = cli.call([])
      expect(status).to eq(0)
      expect(stdout.string).to include('Usage: biometry <command> [options]')
      expect(stderr.string).to be_empty
    end
  end

  %w[-v --version].each do |flag|
    context "when asked for the version with #{flag}" do
      it 'exits 0, prints the bare version on stdout and says nothing on stderr' do
        status = cli.call([flag])
        expect(status).to eq(0)
        expect(stdout.string).to eq("#{Biometry::VERSION}\n")
        expect(stderr.string).to be_empty
      end
    end
  end

  context 'when given an unknown subcommand' do
    it 'exits 2, keeps stdout clean and names the command on stderr' do
      status = cli.call(['wieght'])
      expect(status).to eq(2)
      expect(stdout.string).to be_empty
      expect(stderr.string).to include('biometry: unknown command "wieght"')
    end

    it 'follows the error with usage on stderr' do
      cli.call(['wieght'])
      expect(stderr.string).to include('Usage: biometry <command> [options]')
    end
  end

  context 'when given a subcommand no slice has wired yet' do
    it 'exits 2, because an unimplemented command is a usage error' do
      expect(cli.call(['weight'])).to eq(2)
    end
  end

  describe 'the usage text' do
    it 'tells the reader that structured output supports --json' do
      cli.call(['--help'])
      expect(stdout.string).to include('--json')
    end

    it 'names the command slice 5 wired' do
      cli.call(['--help'])
      expect(stdout.string).to include('report')
    end
  end
end
