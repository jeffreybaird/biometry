# frozen_string_literal: true

# Integration layer: the redating policy read against the manifest it is handed.
#
# Two dates disagree — the one already established and the one this scan
# implies — and ACOG's tolerance for that disagreement widens as pregnancy
# advances, because ultrasound dating degrades as the fetus grows. This service
# decides whether the established date stands. It never rewrites one.
#
# Not one number in this file is retyped. Every threshold, band edge and zone
# bound is read from the manifest, and every gestation is derived from a band's
# own window, because these constants were reconstructed rather than
# transcribed: a spec carrying a second copy of a threshold would agree with a
# transposition instead of catching it. What the file can check is that the
# service honours what is published, exactly and exclusively; the relationships
# that would catch a wrong number are in spec/biometry/reference_data_spec.rb.
RSpec.describe Biometry::Services::Dating::Redating do
  subject(:decision) { call.value! }

  let(:manifest) { ComposedReport.redating_manifest }
  let(:service) { described_class.new(manifest: manifest) }
  let(:reference_date) { Date.new(2026, 8, 13) }

  def bands = manifest[:bands]

  def band_ids = bands.map { |band| band[:id].to_sym }

  def band_from(band) = ComposedReport.edge_days(band[:ga_from])

  def band_to(band) = ComposedReport.edge_days(band[:ga_to])

  def inside(band) = ComposedReport.inside_band(band)

  def zoned = ComposedReport.band_with_zone

  def zone = zoned[:discretionary_zone]

  def caveated = ComposedReport.band_with_caveat

  def before_zoned = ComposedReport.band_before(zoned)

  # The proximity is published only inside the rule's prose. Read from there
  # rather than retyped; see the note about promoting it to a key of its own.
  def proximity = manifest.dig(:rules, :boundary_sensitivity, :text)[/within (\d+) days/, 1].to_i

  def term_days = Biometry::Services::Dating::Lmp::TERM_DAYS

  # The inverse of the service's own indexing. A spec places the pregnancy by
  # choosing the established EDD that puts the indexing gestation where the
  # example needs it:
  #
  #   indexing GA in days = 280 - (established EDD - reference date)
  def edd_for(ga_days) = reference_date + (term_days - ga_days)

  def call(ga_days: inside(caveated), discrepancy: 0, **overrides)
    edd = edd_for(ga_days)
    defaults = { established_edd: edd, established_by: :lmp,
                 proposed_edd: edd + discrepancy, reference_date: reference_date }
    service.call(**defaults, **overrides)
  end

  def recommendation(**arguments) = call(**arguments).value!.recommendation

  it_behaves_like 'a decision that answers its guards in order', ivf: :transfer, banded: :lmp

  it 'succeeds, because a recommendation is a value and not a refusal' do
    expect(call).to be_success
  end

  it 'returns a decision' do
    expect(decision).to be_a(Biometry::RedatingDecision)
  end

  # ------------------------------------------------------------- the band ---

  describe 'the band it selects' do
    it 'selects the band whose window contains the established gestation' do
      expect(bands.map { |band| call(ga_days: inside(band)).value!.band }).to eq(band_ids)
    end

    it 'selects it on the first day of every window' do
      expect(bands.map { |band| call(ga_days: band_from(band)).value!.band }).to eq(band_ids)
    end

    it 'selects it on the last day of every closed window' do
      closed = bands.reject { |band| band[:ga_to].nil? }
      expect(closed.map { |band| call(ga_days: band_to(band)).value!.band })
        .to eq(closed.map { |band| band[:id].to_sym })
    end

    it 'reports the threshold that band publishes, not another band\'s' do
      expect(bands.map { |band| call(ga_days: inside(band)).value!.threshold_days })
        .to eq(bands.map { |band| band[:threshold_days] })
    end

    it 'reports the gestation it indexed on' do
      expect(call(ga_days: inside(zoned)).value!.indexing_ga.days).to eq(inside(zoned))
    end

    # At the moment of the decision you hold two gestations that disagree, and
    # that disagreement is the reason the service was called. `band_indexed_on`
    # says the established one selects the band. Index on the proposal instead
    # and the tool is quietly wrong in the window where redating matters most.
    context 'when the proposed date implies a gestation in a different band' do
      it 'selects the band the established gestation falls in' do
        expect(call(ga_days: band_to(before_zoned), discrepancy: -30).value!.band)
          .to eq(before_zoned[:id].to_sym)
      end

      it 'applies that band\'s threshold rather than the neighbour\'s' do
        expect(call(ga_days: band_to(before_zoned), discrepancy: -30).value!.threshold_days)
          .to eq(before_zoned[:threshold_days])
      end
    end
  end

  # -------------------------------------------------------- the threshold ---

  describe 'the threshold it applies' do
    it 'measures the discrepancy as whole days between the two dates' do
      expect(call(discrepancy: 12).value!.discrepancy_days).to eq(12)
    end

    it 'measures it as a distance, so an earlier proposal counts the same' do
      expect(call(discrepancy: -12).value!.discrepancy_days).to eq(12)
    end

    it 'keeps the established date when the two agree' do
      expect(bands.map { |band| recommendation(ga_days: inside(band)) }).to all(eq(:keep))
    end

    # Exclusive, in every band: the guideline redates when the discrepancy is
    # strictly greater than the threshold, so the threshold day itself is not a
    # redate.
    it 'does not redate on the threshold day itself, in any band' do
      answers = bands.map do |band|
        recommendation(ga_days: inside(band), discrepancy: band[:threshold_days])
      end
      expect(answers).to all(satisfy { |answer| answer != :redate })
    end

    it 'redates one day past the threshold, in every band' do
      answers = bands.map do |band|
        recommendation(ga_days: inside(band), discrepancy: band[:threshold_days] + 1)
      end
      expect(answers).to all(eq(:redate))
    end

    it 'redates on a proposal that is earlier by the same margin' do
      band = bands.first
      expect(recommendation(ga_days: inside(band), discrepancy: -(band[:threshold_days] + 1)))
        .to eq(:redate)
    end
  end

  # ------------------------------------------------- the discretionary zone --

  # The band where the zone and the threshold disagree, and the one a
  # threshold-only implementation gets wrong: without the zone a discrepancy
  # inside it reads :keep on the bare threshold, which is precisely the window
  # the guideline wants a clinician to look at.
  describe 'the discretionary zone' do
    def in_zone(days) = recommendation(ga_days: inside(zoned), discrepancy: days)

    it 'keeps the established date one day below the zone' do
      expect(in_zone(zone[:from_days] - 1)).to eq(:keep)
    end

    it 'defers on the first day of the zone' do
      expect(in_zone(zone[:from_days])).to eq(:discretionary)
    end

    it 'defers on the last day of the zone' do
      expect(in_zone(zone[:to_days])).to eq(:discretionary)
    end

    it 'redates one day past the threshold' do
      expect(in_zone(zoned[:threshold_days] + 1)).to eq(:redate)
    end

    # The whole point, stated as an assertion: a discrepancy the bare threshold
    # would have kept.
    it 'defers on a discrepancy inside the zone that the threshold alone would keep' do
      days = (zone[:from_days] + zone[:to_days]) / 2
      expect([in_zone(days), days < zoned[:threshold_days]]).to eq([:discretionary, true])
    end

    it 'reports the zone as the span of discrepancies it covers' do
      expect(call(ga_days: inside(zoned)).value!.zone)
        .to eq(zone[:from_days]..zone[:to_days])
    end

    # Every other band answers on the threshold alone, so a zone reported there
    # would be a window the guideline never published.
    it 'reports no zone in a band that publishes none' do
      others = bands.reject { |band| band[:discretionary_zone] }
      expect(others.map { |band| call(ga_days: inside(band)).value!.zone }).to all(be_nil)
    end

    it 'answers on the threshold alone in those bands, with no deferral' do
      others = bands.reject { |band| band[:discretionary_zone] }
      answers = others.map do |band|
        recommendation(ga_days: inside(band), discrepancy: band[:threshold_days])
      end
      expect(answers).to all(eq(:keep))
    end
  end

  # ------------------------------------------------------------ the caveat --

  describe 'the caveat it surfaces' do
    it 'carries the caveat the band names' do
      expect(call(ga_days: inside(caveated)).value!.caveat.id)
        .to eq(caveated[:caveat].to_sym)
    end

    it 'carries the guideline\'s wording rather than a summary of it' do
      expect(call(ga_days: inside(caveated)).value!.caveat.text)
        .to eq(manifest.dig(:caveats, caveated[:caveat].to_sym, :text))
    end

    # It attaches to the band, not to the answer: the widest dating error is a
    # fact about the third trimester whatever this discrepancy turned out to be.
    it 'carries it whatever the recommendation was' do
      caveats = [0, caveated[:threshold_days] + 1].map do |days|
        call(ga_days: inside(caveated), discrepancy: days).value!.caveat
      end
      expect(caveats.map { |caveat| caveat&.id }.uniq).to eq([caveated[:caveat].to_sym])
    end

    it 'carries none in a band that names none' do
      others = bands.reject { |band| band[:caveat] }
      expect(others.map { |band| call(ga_days: inside(band)).value!.caveat }).to all(be_nil)
    end
  end

  # --------------------------------------------------------------- the IVF --

  # A pregnancy dated by IVF is not redated by ultrasound: the date is known
  # rather than estimated. The rule answers before a band is selected, so the
  # band, the threshold and the zone are absent rather than filled in with
  # values that played no part in the decision.
  describe 'a pregnancy dated by embryo transfer' do
    def ivf(**overrides) = call(established_by: :transfer, **overrides).value!

    it 'keeps the established date' do
      expect(ivf.recommendation).to eq(:keep)
    end

    it 'names the rule that decided it' do
      expect(ivf.rule).to eq(:ivf_never_redated)
    end

    it 'names a rule the manifest actually publishes' do
      expect(manifest[:rules]).to have_key(ivf.rule)
    end

    it 'selects no band, applies no threshold and reports no zone' do
      expect(ivf.to_h.values_at(:band, :threshold_days, :zone)).to all(be_nil)
    end

    it 'reports no caveat, even at a gestation whose band carries one' do
      expect(ivf(ga_days: inside(caveated)).caveat).to be_nil
    end

    it 'reports no boundary sensitivity, there being no edge it stood near' do
      expect(ivf(ga_days: band_from(zoned)).boundary_sensitivity).to be_nil
    end

    it 'keeps it however large the discrepancy is' do
      widest = bands.map { |band| band[:threshold_days] }.max
      expect(ivf(discrepancy: widest * 2).recommendation).to eq(:keep)
    end

    it 'still reports the discrepancy it measured, which is a finding either way' do
      expect(ivf(discrepancy: 12).discrepancy_days).to eq(12)
    end

    # The rule is about IVF, not about being established: every other
    # derivation reaches band selection as usual.
    it 'leaves every other derivation to the bands' do
      bandeds = %i[lmp crl biometry].map { |by| call(established_by: by).value!.band }
      expect(bandeds).to all(eq(caveated[:id].to_sym))
    end

    it 'names no rule when a band decided it' do
      expect(call(established_by: :lmp).value!.rule).to be_nil
    end
  end

  # ----------------------------------------------- the boundary disclosure ---

  # Two conditions, and both are load-bearing. Proximity alone is not a
  # finding — a gestation near an edge whose answer is the same either side has
  # nothing to disclose — and a difference alone is not one either, because
  # every band differs from its neighbour somewhere.
  describe 'the boundary sensitivity it reports' do
    # One day into the zoned band, and a discrepancy that the earlier band's
    # threshold would redate but this band's zone defers on.
    def straddling = zone[:from_days] + 1

    def near_edge(**overrides) = call(ga_days: band_from(zoned), **overrides).value!

    it 'reports it when the gestation is near an edge and the answer differs across it' do
      expect(near_edge(discrepancy: straddling).boundary_sensitivity).not_to be_nil
    end

    it 'names the band on the other side of that edge' do
      expect(near_edge(discrepancy: straddling).boundary_sensitivity.adjacent_band)
        .to eq(before_zoned[:id].to_sym)
    end

    it 'names what the recommendation would have been there' do
      expect(near_edge(discrepancy: straddling).boundary_sensitivity.recommendation)
        .to eq(:redate)
    end

    it 'counts the days between the gestation and that band' do
      expect(near_edge(discrepancy: straddling).boundary_sensitivity.days_to_edge).to eq(1)
    end

    it 'leaves its own answer standing rather than deferring to the neighbour' do
      expect(near_edge(discrepancy: straddling).recommendation).to eq(:discretionary)
    end

    context 'when the gestation is near an edge but the answer is the same either side' do
      it 'reports nothing, proximity alone being no finding' do
        expect(near_edge(discrepancy: 0).boundary_sensitivity).to be_nil
      end
    end

    context 'when the answer would differ but the gestation is nowhere near an edge' do
      it 'reports nothing, a difference alone being no finding either' do
        expect(call(ga_days: inside(zoned), discrepancy: straddling).value!
                 .boundary_sensitivity).to be_nil
      end
    end

    context 'when the gestation sits at the far limit of the published proximity' do
      it 'reports it on the last day within the window' do
        ga = band_from(zoned) + proximity - 1
        expect(call(ga_days: ga, discrepancy: straddling).value!.boundary_sensitivity)
          .not_to be_nil
      end

      it 'reports nothing one day further in' do
        ga = band_from(zoned) + proximity
        expect(call(ga_days: ga, discrepancy: straddling).value!.boundary_sensitivity).to be_nil
      end
    end

    # Looking the other way over the same edge: the last day of the earlier
    # band, where the neighbour is the later one.
    context 'when the gestation sits on the last day of a band' do
      def looking_forward
        call(ga_days: band_to(before_zoned), discrepancy: straddling).value!
      end

      it 'names the band that begins the next day' do
        expect(looking_forward.boundary_sensitivity.adjacent_band).to eq(zoned[:id].to_sym)
      end

      it 'names the deferral that band would have reached' do
        expect(looking_forward.boundary_sensitivity.recommendation).to eq(:discretionary)
      end

      it 'reaches its own band\'s answer regardless' do
        expect(looking_forward.recommendation).to eq(:redate)
      end
    end

    context 'when there is no band below the one selected' do
      it 'reports nothing at the very first day of the first band' do
        expect(call(ga_days: 0, discrepancy: straddling).value!.boundary_sensitivity).to be_nil
      end
    end

    context 'when there is no band above the one selected' do
      it 'reports nothing deep inside the open-ended band' do
        expect(call(ga_days: band_from(bands.last) + 70, discrepancy: straddling)
                 .value!.boundary_sensitivity).to be_nil
      end
    end
  end

  # --------------------------------------------------- the date it is given --

  # Once an EDD is established it is not casually revised. Subsequent scans are
  # measured against it, and this service returns a recommendation with
  # reasoning; nothing writes a date back.
  describe 'the established date' do
    it 'reports it back exactly as it was given' do
      expect(call(ga_days: inside(zoned)).value!.established_edd)
        .to eq(edd_for(inside(zoned)))
    end

    it 'reports the proposed date beside it rather than in place of it' do
      expect(call(discrepancy: 12).value!.proposed_edd).to eq(edd_for(inside(caveated)) + 12)
    end

    it 'carries no third date, even when it recommends redating' do
      widest = bands.map { |band| band[:threshold_days] }.max + 1
      dates = call(discrepancy: widest).value!.to_h.values.grep(Date)
      expect(dates.uniq.length).to eq(2)
    end

    it 'hands back the very object it was given, unreplaced' do
      edd = edd_for(inside(zoned))
      result = service.call(established_edd: edd, established_by: :lmp,
                            proposed_edd: edd + 12, reference_date: reference_date)
      expect(result.value!.established_edd).to be(edd)
    end
  end

  # ---------------------------------------------------------- the provenance --

  describe 'the provenance it attaches' do
    it 'names the guideline it read' do
      expect(decision.source.standard).to eq(:acog)
    end

    it 'cites it from the manifest rather than leaving the answer unattributed' do
      expect(decision.source.citation).to eq(manifest[:source][:citation])
    end

    it 'names what produced the decision' do
      expect(decision.source.formula).not_to be_nil
    end

    it 'claims neither a chart type nor a stratum' do
      expect([decision.source.type, decision.source.stratum]).to eq([nil, nil])
    end
  end

  # -------------------------------------------------------------- refusals ---

  describe 'the inputs it requires' do
    it 'refuses a request with no established date' do
      expect(call(established_edd: nil).failure).to eq(
        [:insufficient_data,
         { required: %i[established_edd established_by proposed_edd reference_date],
           given: %i[established_by proposed_edd reference_date] }]
      )
    end

    it 'refuses a request with no proposed date' do
      expect(call(proposed_edd: nil).failure.first).to eq(:insufficient_data)
    end

    # Required, because it is what triggers the IVF rule. Defaulting it would
    # quietly redate a pregnancy the guideline says is never redated.
    it 'refuses a request that does not say how the date was established' do
      expect(call(established_by: nil).failure).to eq(
        [:insufficient_data,
         { required: %i[established_edd established_by proposed_edd reference_date],
           given: %i[established_edd proposed_edd reference_date] }]
      )
    end
  end

  describe 'the inputs it refuses' do
    it 'refuses a date that is not a date' do
      expect(call(established_edd: '2026-10-08').failure)
        .to eq([:invalid_input, { established_edd: '2026-10-08' }])
    end

    it 'refuses a DateTime, so no zone can reach the arithmetic' do
      expect(call(reference_date: DateTime.new(2026, 8, 13)).failure.first).to eq(:invalid_input)
    end

    it 'reports every invalid input at once, not the first one it met' do
      expect(call(established_edd: 'x', proposed_edd: 'y').failure)
        .to eq([:invalid_input, { established_edd: 'x', proposed_edd: 'y' }])
    end

    # A derivation this library has no vocabulary for cannot be checked against
    # the IVF rule, and guessing that it is not IVF is the expensive direction
    # to guess wrong in.
    it 'refuses a derivation it does not recognise, naming the ones it does' do
      available = Biometry::Services::Dating::AllDerivations::OFFERED +
                  Biometry::Services::Dating::AllDerivations::DEFERRED
      expect(call(established_by: :martian).failure)
        .to eq([:invalid_input, { established_by: :martian, available: available }])
    end
  end

  # The bands run from day zero upward, so a reference date before the
  # pregnancy began describes a gestation no band covers. Never extrapolated
  # into the first band, which would answer a question about a pregnancy that
  # had not started.
  describe 'the range it accepts' do
    def valid_range
      [ComposedReport.edge_days(bands.first[:ga_from]) / 7,
       ComposedReport.edge_days(bands.last[:ga_to])&.fdiv(7)&.floor]
    end

    it 'accepts day zero, the first day the first band covers' do
      expect(call(ga_days: 0)).to be_success
    end

    it 'refuses the day before it, one day outside' do
      expect(call(ga_days: -1).failure.first).to eq(:out_of_range)
    end

    it 'names the guideline, the age it computed and the range it accepts' do
      expect(call(ga_days: -14).failure)
        .to eq([:out_of_range, { standard: :acog, ga_weeks: -2, valid_range: valid_range }])
    end

    # The last band is open-ended, so a post-dates pregnancy is inside it
    # rather than past the end of the table.
    it 'accepts a gestation past the due date, the last band having no upper edge' do
      expect(call(ga_days: term_days + 14).value!.band).to eq(bands.last[:id].to_sym)
    end

    # data/ publishes an open-ended final band, so the range this service
    # reports ends in nil and the arm that names a closing week never runs.
    # That arm is not decoration: a manifest whose last band closes somewhere
    # must have its range reported as ending there, not as running on for ever.
    #
    # Built by closing the real manifest's last band at the width of the band
    # before it, so no week, threshold or edge is invented in this file — the
    # same way the loader's pruning and INTERGROWTH's degenerate lambda are
    # covered.
    context 'when the last band a manifest publishes is closed' do
      def closed_last_band
        earlier = ComposedReport.band_before(bands.last)
        width = band_to(earlier) - band_from(earlier)
        bands.last.merge(ga_to: { weeks: (band_from(bands.last) + width) / 7, days: 6 })
      end

      def bounded
        described_class.new(manifest: manifest.merge(bands: bands[..-2] + [closed_last_band]))
      end

      def refusal
        edd = edd_for(-14)
        bounded.call(established_edd: edd, established_by: :lmp, proposed_edd: edd,
                     reference_date: reference_date).failure
      end

      it 'names the week that band ends in rather than leaving the range open' do
        last_day = ComposedReport.edge_days(closed_last_band[:ga_to])
        expect(refusal.last[:valid_range].last)
          .to eq(Biometry::GestationalAge.new(days: last_day).completed_weeks)
      end

      it 'still starts the range at the week the first band begins' do
        expect(refusal.last[:valid_range].first).to eq(0)
      end
    end
  end
end
