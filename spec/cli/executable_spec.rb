# frozen_string_literal: true

require 'json'
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

  # The end of the contract that only the real process can show: a piped
  # stdout is not a terminal, so the table arrives as plain lines, and the
  # Result becomes an exit code here and nowhere else.
  context 'when asked for a report' do
    def report(*extra)
      run('report', '--at', '2026-08-13', '--ga', '32w0d', '--bpd', '82', '--hc', '291',
          '--ac', '274', '--fl', '62', '--sex', 'female', '--lmp', '2026-01-01', *extra)
    end

    it 'exits 0, prints the comparison on stdout and says nothing on stderr' do
      stdout, stderr, status = report
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include('NICHD (white)')
      expect(stderr).to be_empty
    end

    it 'emits plain lines when piped, with no escape sequences' do
      stdout, = report
      expect(stdout).to include('NICHD (white)')
      expect(stdout).not_to include("\e[")
    end

    it 'puts a parseable document and nothing else on stdout with --json' do
      stdout, stderr, status = report('--json')
      expect(status.exitstatus).to eq(0)
      expect(JSON.parse(stdout)['studies'].first['growth'].length).to eq(8)
      expect(stderr).to be_empty
    end

    # The subcommand's help is the documentation this library ships, so it
    # travels the same contract as any other result: stdout, exit 0, a quiet
    # stderr — and it explains the flags rather than merely listing them.
    it 'documents the flags when asked for the subcommand help' do
      stdout, stderr, status = run('report', '--help')
      expect(status.exitstatus).to eq(0)
      expect(stdout).to match(/abdominal circumference/i)
      expect(stderr).to be_empty
    end

    it 'accepts a millimetre reported to one decimal place' do
      stdout, stderr, status = run('report', '--at', '2026-08-13', '--ga', '32w0d',
                                   '--hc', '291', '--fl', '62', '--ac', '274.5')
      expect(status.exitstatus).to eq(0)
      expect(stdout).to include('AC 27.45')
      expect(stderr).to be_empty
    end

    it 'exits 2 on a usage error, with no stack trace on stdout' do
      stdout, stderr, status = run('report', '--ac', '274')
      expect(status.exitstatus).to eq(2)
      expect(stdout).to be_empty
      expect(stderr).to include('--ga')
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
