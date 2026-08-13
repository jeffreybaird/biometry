# frozen_string_literal: true

require 'open3'

RSpec.describe 'the biometry executable' do
  def run(*argv)
    Open3.capture3(RbConfig.ruby, Biometry::ROOT.join('exe', 'biometry').to_s, *argv)
  end

  context 'when asked for help' do
    it 'exits 0, prints usage on stdout and says nothing on stderr' do
      stdout, stderr, status = run('--help')
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include('Usage: biometry <command> [options]')
      expect(stderr).to be_empty
    end
  end

  context 'when asked for the version' do
    it 'exits 0, prints the bare version on stdout and says nothing on stderr' do
      stdout, stderr, status = run('--version')
      expect(status.exitstatus).to eq(0)
      expect(stdout).to eq("#{Biometry::VERSION}\n")
      expect(stderr).to be_empty
    end
  end

  context 'when given an unknown subcommand' do
    it 'exits 2, keeps stdout clean and puts the error on stderr' do
      stdout, stderr, status = run('wieght')
      expect(status.exitstatus).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include('unknown command "wieght"')
    end
  end

  context 'when given no arguments' do
    it 'exits 0, prints usage on stdout and says nothing on stderr' do
      stdout, stderr, status = run
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include('Usage: biometry <command> [options]')
      expect(stderr).to be_empty
    end
  end
end
