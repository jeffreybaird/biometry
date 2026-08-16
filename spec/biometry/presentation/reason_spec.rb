# frozen_string_literal: true

# Unit layer. A Failure is a value the caller branches on; this turns one into
# the sentence a reader sees on the row that refused.
#
# Every phrase names what failed and what would have to change, because a
# refusal that reads as an absence is worse than no row at all — the whole
# reason slice 1 refuses CRL rather than omitting it.
#
# Pure: the payloads are the ones the services already return, and the
# function knows nothing about which of them it came from.
RSpec.describe Biometry::Presentation::Reason do
  describe 'a standard this library has not implemented' do
    subject(:text) do
      described_class.call([:unsupported_standard,
                            { requested: :crl, available: %i[lmp transfer] }])
    end

    it 'says the derivation is unavailable rather than leaving the row blank' do
      expect(text).to include('unavailable')
    end

    it 'names what was asked for and what there is instead' do
      expect(text).to eq('unavailable — crl is not implemented; available: lmp, transfer')
    end
  end

  describe 'a formula the scan could not feed' do
    it 'names what the formula requires and what the scan carried' do
      failure = [:insufficient_data, { required: %i[hc ac fl], given: %i[ac fl] }]
      expect(described_class.call(failure))
        .to eq('insufficient data — requires hc, ac, fl; given ac, fl')
    end

    it 'says none rather than trailing off when the scan carried nothing' do
      failure = [:insufficient_data, { required: %i[ac hc], given: [] }]
      expect(described_class.call(failure))
        .to eq('insufficient data — requires ac, hc; given none')
    end
  end

  # Each adapter reads at its standard's own convention — completed weeks on
  # the tables, exact weeks on the closed forms — so one gestation reaches
  # this function as 41, 41.0 and 41.42857142857143. The conventions are real
  # and the payload keeps them; the sentence should not spell the same
  # gestation three ways in one block. Rendering happens here rather than in
  # the services, so --json still carries the exact value.
  describe 'a gestation outside the window a standard was fitted over' do
    it 'names the standard, its own window and the gestation given' do
      failure = [:out_of_range, { standard: :nichd, ga_weeks: 41, valid_range: [15, 40] }]
      expect(described_class.call(failure))
        .to eq('out of range — nichd covers 15–40 weeks; given 41')
    end

    it 'renders a whole-numbered gestation without its decimal place' do
      failure = [:out_of_range, { standard: :hadlock_1991_equation, ga_weeks: 41.0,
                                  valid_range: [10, 40] }]
      expect(described_class.call(failure)).to end_with('given 41')
    end

    it 'keeps a fractional gestation, to the tenth of a week' do
      failure = [:out_of_range, { standard: :intergrowth21, ga_weeks: 41.42857142857143,
                                  valid_range: [22, 40] }]
      expect(described_class.call(failure)).to end_with('given 41.4')
    end

    it 'spells one gestation one way, whatever convention each standard read it in' do
      given = [41, 41.0, 41.4, 41.42857142857143].map do |weeks|
        described_class.call([:out_of_range,
                              { standard: :who, ga_weeks: weeks, valid_range: [14, 40] }])
      end
      expect(given.map { |text| text[/given .*\z/] }.uniq).to eq(['given 41', 'given 41.4'])
    end

    it 'renders the window the same way, so 22.0 is not a different bound to 22' do
      failure = [:out_of_range, { standard: :intergrowth21, ga_weeks: 41.0,
                                  valid_range: [22.0, 40.0] }]
      expect(described_class.call(failure)).to include('covers 22–40 weeks')
    end

    # Dating has no upper bound: a reference date before the LMP is the only
    # way out of range, so the window is open at the top.
    it 'renders an open-ended window as open ended rather than inventing a bound' do
      failure = [:out_of_range, { standard: :naegele, ga_weeks: -1, valid_range: [0, nil] }]
      expect(described_class.call(failure))
        .to eq('out of range — naegele covers 0 weeks and later; given -1')
    end
  end

  describe 'a chart read from a weight it was not built on' do
    it 'names the pairing the chart requires and the formula it was handed' do
      failure = [:formula_chart_mismatch,
                 { chart: :nichd, expected: :hadlock_hc_ac_fl, given: :intergrowth }]
      expect(described_class.call(failure))
        .to eq('formula mismatch — nichd is read from hadlock_hc_ac_fl; given intergrowth')
    end
  end

  describe 'a centile a chart does not publish' do
    it 'names the centiles that chart does publish' do
      failure = [:unsupported_centile, { standard: :who, requested: 2.5, available: [5, 10, 50] }]
      expect(described_class.call(failure))
        .to eq('unsupported centile — who publishes 5, 10, 50; given 2.5')
    end
  end

  describe 'an input the standard rejected' do
    it 'names the field and, where the service offered one, the alternatives' do
      failure = [:invalid_input, { sex: :martian, available: %i[combined female male] }]
      expect(described_class.call(failure))
        .to eq('invalid input — sex: martian; available: combined, female, male')
    end

    it 'renders a field-by-field payload without assuming an available list' do
      expect(described_class.call([:invalid_input, { cycle_length: 0 }]))
        .to eq('invalid input — cycle_length: 0')
    end
  end

  # A tag added by a later slice must still print. A row that raised on an
  # unrecognised tag would take the whole report to exit 70.
  describe 'a tag it has no phrasing for' do
    it 'renders the tag and its payload rather than raising' do
      expect(described_class.call([:redating_declined, { by_days: 4 }]))
        .to eq('redating declined — by_days: 4')
    end
  end
end
