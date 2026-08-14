# frozen_string_literal: true

# Unit layer. What the redating policy hands back: a recommendation, the
# arithmetic behind it, and the parts of the guideline that produced it.
#
# The recommendation is tri-state rather than a boolean. A boolean cannot carry
# the discretionary zone, and `if decision.redate?` would silently discard
# exactly the case the guideline most wants a human to look at — so the object
# offers no such predicate and a caller has to read the value.
#
# The two dates travel together and neither is revised. An established EDD is
# not casually rewritten; subsequent scans are measured against it, and this
# object is the reasoning, not a replacement date.
#
# The values below are deliberately not ACOG's. This object is handed a band
# and a threshold; it knows nothing about which guideline they came from, and a
# spec that retyped real thresholds into a value object's examples would be
# asserting the guideline in the one place that does not read it.
RSpec.describe Biometry::RedatingDecision do
  subject(:decision) { described_class.new(**banded) }

  let(:established) { Date.new(2026, 10, 8) }
  let(:proposed) { Date.new(2026, 10, 20) }

  def source
    Biometry::Provenance.formula(standard: :acog, citation: 'a committee opinion',
                                 formula: :redating)
  end

  def banded(**overrides)
    { recommendation: :discretionary, discrepancy_days: 12,
      established_edd: established, proposed_edd: proposed,
      indexing_ga: Biometry::GestationalAge.from(weeks: 24), band: :a_published_band,
      threshold_days: 99, zone: (40..99), caveat: nil, rule: nil,
      boundary_sensitivity: nil, source: source }.merge(overrides)
  end

  it 'carries the recommendation' do
    expect(decision.recommendation).to eq(:discretionary)
  end

  it 'carries the discrepancy in whole days' do
    expect(decision.discrepancy_days).to eq(12)
  end

  it 'names the band the threshold came from' do
    expect(decision.band).to eq(:a_published_band)
  end

  it 'names the threshold that applied' do
    expect(decision.threshold_days).to eq(99)
  end

  it 'names the gestation the band was selected on' do
    expect(decision.indexing_ga.to_s).to eq('24w0d')
  end

  it 'names the guideline it came from' do
    expect(decision.source.citation).to eq('a committee opinion')
  end

  # The tri-state is the whole point, so the vocabulary lives in one place
  # rather than being spelled out by each caller that branches on it.
  it 'draws its recommendation from the three the guideline allows' do
    expect(Biometry::REDATING_RECOMMENDATIONS)
      .to contain_exactly(:keep, :discretionary, :redate)
  end

  it 'offers no predicate that would collapse the three into two' do
    expect(decision).not_to respond_to(:redate?)
  end

  describe 'the dates it reports' do
    it 'reports the established date exactly as it was given' do
      expect(decision.established_edd).to eq(established)
    end

    it 'reports the proposed date beside it' do
      expect(decision.proposed_edd).to eq(proposed)
    end

    # Nothing writes a date back. A decision to redate is a recommendation with
    # reasoning; the revised date, if anyone accepts it, is the proposed one
    # they already hold.
    it 'carries no third date for a caller to mistake for a revision' do
      dates = decision.to_h.values.grep(Date)
      expect(dates).to contain_exactly(established, proposed)
    end

    it 'is frozen, so the decision cannot be edited into a different one' do
      expect(decision).to be_frozen
    end
  end

  # The member is `recommendation`, never `method`: Data.define(:method)
  # shadows Object#method and breaks every reflective caller.
  it 'does not shadow Object#method' do
    expect(decision.method(:to_s)).to be_a(Method)
  end

  # The zone changes the answer rather than annotating it, so it is reported as
  # the span of discrepancies it covers rather than as a flag.
  describe 'the discretionary zone' do
    it 'carries the span of discrepancies the guideline defers on' do
      expect(decision.zone).to cover(40, 99)
    end

    context 'when the band publishes no zone' do
      subject(:decision) { described_class.new(**banded(zone: nil, recommendation: :keep)) }

      it 'carries none rather than a span standing in for one' do
        expect(decision.zone).to be_nil
      end
    end
  end

  # A rule outranks a band, and a decision it made answers a question no band
  # was ever asked. Filling the band in afterwards would attribute the answer
  # to a threshold that played no part in it.
  context 'when a clinical rule decided it rather than a band' do
    subject(:decision) do
      described_class.new(**banded(recommendation: :keep, rule: :a_published_rule,
                                   band: nil, threshold_days: nil, zone: nil))
    end

    it 'names the rule' do
      expect(decision.rule).to eq(:a_published_rule)
    end

    it 'leaves the band, the threshold and the zone absent' do
      expect(decision.to_h.values_at(:band, :threshold_days, :zone)).to all(be_nil)
    end

    it 'still reports the discrepancy it measured' do
      expect(decision.discrepancy_days).to eq(12)
    end
  end

  context 'when the band carries a caveat' do
    subject(:decision) { described_class.new(**banded(caveat: caveat)) }

    let(:caveat) { Biometry::Caveat.new(id: :a_caveat, text: 'quoted from the guideline') }

    it 'carries the caveat whole, wording and all' do
      expect(decision.caveat).to eq(caveat)
    end
  end

  context 'when the answer would differ in the neighbouring band' do
    subject(:decision) { described_class.new(**banded(boundary_sensitivity: sensitivity)) }

    let(:sensitivity) do
      Biometry::BoundarySensitivity.new(adjacent_band: :another_band, recommendation: :redate,
                                        days_to_edge: 1)
    end

    it 'carries the disclosure alongside its own answer' do
      expect(decision.boundary_sensitivity).to eq(sensitivity)
    end

    it 'does not let the neighbour overwrite the answer it actually reached' do
      expect(decision.recommendation).to eq(:discretionary)
    end
  end
end
