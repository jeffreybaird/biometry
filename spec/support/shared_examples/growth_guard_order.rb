# frozen_string_literal: true

# One rule, not four facts: every growth adapter answers its guards in the
# same order.
#
#   1. formula/chart pairing  ->  :formula_chart_mismatch
#   2. gestational age range  ->  :out_of_range
#   3. stratum                ->  :invalid_input
#
# Why that order and not another.
#
# A mismatched formula means the weight the caller handed over is not a value
# this chart can interpret at all. The stratum selects *which* of the chart's
# tables to read — a question that only arises once the weight is admissible.
# Checking the stratum first answers a question about a number the chart was
# never going to accept. Range sits in the middle for the same reason: a
# gestation outside the fitted window means the chart cannot answer, whichever
# stratum you would have used.
#
# The second argument is about what the caller does with the answer.
# :formula_chart_mismatch names a bug in the caller's pipeline — something
# computed an EFW with one formula and asked for a percentile from a chart
# built on another. :invalid_input on an unknown stratum names a user typo.
# Report the typo first and the caller fixes the typo, re-runs, and only then
# discovers the pipeline was wrong: two round trips for one submission.
#
# The adapters differ in constructor arity, in call signature and in GA
# convention, so the group is parameterised:
#
#   manifest:    the manifest file under data/
#   table:       the CSV under data/, for the two table standards, else nil
#   stratum_key: :stratum, :sex, or nil for the two unstratified charts
#   variant:     the chart variant, for the one standard served as two, else
#                nil. Hadlock 1991 carries two irreconcilable dispersion
#                figures and reports both, and the guard order is a property
#                of the adapter rather than of the figure it read, so each
#                variant is put through this group in its own right.
#
# An adapter with no stratum gets the examples that make sense for it and
# none of the ones that do not.
RSpec.shared_examples 'a chart that answers its guards in order' do |config|
  let(:manifest) do
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / config[:manifest]).first
  end
  let(:table) do
    config[:table] && Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / config[:table])
  end
  let(:service) do
    next described_class.new(manifest: manifest, table: table) unless table.nil?
    next described_class.new(manifest: manifest, variant: config[:variant]) if config[:variant]

    described_class.new(manifest: manifest)
  end
  let(:stratum_key) { config[:stratum_key] }

  def paired = manifest[:paired_formula].to_sym

  # Both ends come from the manifest's own window, so no adapter's range is
  # restated here. Two weeks past the last fitted one is outside it under
  # either convention a chart evaluates at — completed and exact weeks alike.
  def out_of_window = Biometry::GestationalAge.from(weeks: manifest[:valid_ga_weeks].last + 2)

  def in_window = Biometry::GestationalAge.from(weeks: manifest[:valid_ga_weeks].first + 1)

  # The mismatch is another published chart's pairing rather than an invented
  # symbol, so the case under test is the one the failure names: a weight
  # computed for a different chart.
  def mismatched_formula
    %w[intergrowth21.yml hadlock_1991.yml]
      .map { |file| Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / file).first }
      .map { |other| other[:paired_formula].to_sym }
      .find { |formula| formula != paired }
  end

  # Not in any manifest's stratification.values, and not a plausible typo for
  # one either, so nothing here depends on which strata a chart publishes.
  def unpublished_stratum = :not_a_chart_this_standard_publishes

  def efw(formula)
    Biometry::Estimate.new(
      value: 1500, unit: 'g', formula: formula, inputs: %i[hc ac fl],
      source: Biometry::Provenance.formula(standard: :hadlock, citation: 'x', formula: formula),
      uncertainty: nil
    )
  end

  # The tag alone. Which guard answered is the behaviour this group is about;
  # each adapter's own spec pins the payload that travels with it.
  def tag_for(formula:, ga:, stratum: nil)
    args = { estimate: efw(formula), ga: ga }
    args[stratum_key] = stratum if stratum_key && stratum
    service.call(**args).failure.first
  end

  context 'when the weight was computed for another chart and the gestation is out of range' do
    it 'names the pairing, because a weight it cannot read poses no window question' do
      expect(tag_for(formula: mismatched_formula, ga: out_of_window))
        .to eq(:formula_chart_mismatch)
    end
  end

  if config[:stratum_key]
    context 'when the weight was computed for another chart and the stratum is unpublished' do
      it 'names the pairing, because the stratum only chooses among tables it could read' do
        expect(tag_for(formula: mismatched_formula, ga: in_window,
                       stratum: unpublished_stratum))
          .to eq(:formula_chart_mismatch)
      end
    end

    context 'when the gestation is out of range and the stratum is unpublished' do
      it 'names the window, because no chart of its own answers there' do
        expect(tag_for(formula: paired, ga: out_of_window, stratum: unpublished_stratum))
          .to eq(:out_of_range)
      end
    end

    # The case a reordering of the guard clauses has the most room to hide in:
    # every guard has something to say, and only the first in the order may.
    # For the two unstratified charts this collapses into the pairing-beats-
    # range example above, which is the whole collision they can express.
    context 'when the pairing, the window and the stratum are all wrong at once' do
      it 'names the pairing, the first guard in the order' do
        expect(tag_for(formula: mismatched_formula, ga: out_of_window,
                       stratum: unpublished_stratum))
          .to eq(:formula_chart_mismatch)
      end
    end
  end
end
