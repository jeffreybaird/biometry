# frozen_string_literal: true

require 'json'
require 'stringio'
require 'biometry/cli/main'

# Integration layer: the command object is where the parser, the models, the
# weight services and the renderer meet. A millimetre typed with a decimal has
# to survive every one of those boundaries — parsed as a decimal, carried by
# the Measurement, divided into centimetres and used by the formula — and only
# a run through the whole composition shows that it did.
RSpec.describe Biometry::CLI::ReportCommand do
  def call(*extra)
    stdout = StringIO.new
    stderr = StringIO.new
    argv = %w[report --ga 32w0d --at 2026-08-13 --bpd 82 --hc 291 --fl 62] + extra
    status = described_class.new(stdout: stdout, stderr: stderr).call(argv)
    [status, stdout.string, stderr.string]
  end

  def document(*extra) = JSON.parse(call(*extra, '--json')[1])

  def first_weight(ac)
    document('--ac', ac)['growth'].filter_map { |row| row.dig('weight', 'value') }.first
  end

  context 'when a measurement carries one decimal place' do
    it 'exits 0 and reports, rather than refusing the scanner\'s own precision' do
      status, out, err = call('--ac', '274.5')
      expect(status).to eq(0)
      expect(out).not_to be_empty
      expect(err).to be_empty
    end

    it 'carries the millimetres as typed and the centimetres they convert to' do
      measurement = document('--ac', '274.5')['measurements'].find { |m| m['kind'] == 'ac' }
      expect(measurement).to include('mm' => 274.5, 'cm' => 27.45)
    end

    # The decimal is used, not merely accepted: a value the formula silently
    # rounded would weigh the same as one of its integer neighbours.
    it 'weighs the fetus from the decimal rather than from a rounded stand-in' do
      expect(first_weight('274.5'))
        .to be_between(first_weight('274'), first_weight('275')).exclusive
    end
  end

  context 'when a measurement is not a number' do
    it 'exits 2, keeps stdout clean and names the option on stderr' do
      status, out, err = call('--ac', 'abc')
      expect(status).to eq(2)
      expect(out).to be_empty
      expect(err).to include('--ac')
    end
  end
end
