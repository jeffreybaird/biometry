# frozen_string_literal: true

require 'dry/monads'

# Slice 5's inputs, composed the way the CLI composes them: real manifests,
# real services, real numbers. Hand-typed fixtures here would let the renderer
# agree with a value the library does not actually produce.
#
# A growth row is one printed line — the chart, the chart's citation, the
# weight its pairing requires, and the report read from that weight. NICHD fans
# out to four rows because it publishes four charts and no combined one. A row
# whose weight or whose chart refused keeps its row and carries the Failure,
# because a silently short table looks complete when it is not.
#
# The citation is on the row rather than read back off a successful Result: a
# row that is on the page has a paper behind it whatever its outcome was, and
# presentation/ may not open a manifest to find out which.
module ComposedReport
  extend Dry::Monads[:result]

  REFERENCE_DATE = Date.new(2026, 8, 13)
  LMP_DATE = Date.new(2026, 1, 1)
  TRANSFER_DATE = Date.new(2026, 1, 17)
  EMBRYO_DAY = 5

  # 32w0d biometry that every chart can read.
  FULL_BIOMETRY = { bpd: 82, hc: 291, ac: 274, fl: 62 }.freeze

  # Small enough at 32 weeks to fall below every chart's outermost published
  # column, which is the only way to see an open bracket rendered.
  SMALL_BIOMETRY = { bpd: 70, hc: 240, ac: 200, fl: 50 }.freeze

  # Large enough at 32 weeks to fall above every chart's outermost published
  # column, and past what either closed form can report.
  LARGE_BIOMETRY = { bpd: 110, hc: 400, ac: 400, fl: 90 }.freeze

  module_function

  def manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  def ga_of(weeks: 32, days: 0) = Biometry::GestationalAge.from(weeks: weeks, days: days)

  def scan_of(millimetres = FULL_BIOMETRY)
    measurements = millimetres.map { |kind, mm| Biometry::Measurement.new(kind: kind, mm: mm) }
    Biometry::Scan.new(date: REFERENCE_DATE, measurements: measurements)
  end

  def dating(lmp: LMP_DATE, cycle_length: 28, transfer_date: TRANSFER_DATE,
             embryo_day: EMBRYO_DAY)
    Biometry::Services::Dating::AllDerivations.new.call(
      reference_date: REFERENCE_DATE, lmp: lmp, cycle_length: cycle_length,
      transfer_date: transfer_date, embryo_day: embryo_day
    ).value!
  end

  def weights(scan)
    Biometry::Services::Weight::AllFormulas
      .new(hadlock: manifest('hadlock_1985'), intergrowth: manifest('intergrowth21'))
      .call(scan).value!
  end

  def growth(scan: nil, ga: nil, sex: :female, stratum: nil)
    scan ||= scan_of
    ga ||= ga_of
    computed = weights(scan)
    equation_rows(computed, ga) + table_rows(computed, ga, sex, stratum)
  end

  def equation_rows(computed, ga)
    [row(:intergrowth21, computed[:intergrowth]) { |efw| intergrowth(efw, ga) },
     row(:hadlock_1991, computed[:hadlock_bpd_hc_ac_fl]) { |efw| hadlock1991(efw, ga) }]
  end

  def table_rows(computed, ga, sex, stratum)
    weight = computed[:hadlock_hc_ac_fl]
    [row(:who, weight) { |efw| who(efw, ga, sex) }, *nichd_rows(weight, ga, stratum)]
  end

  # A chart cannot be read from a weight that was never produced, so the row
  # carries the weight's own Failure and the renderer reports that.
  #
  # The citation is known from the manifest whatever the outcome, so it is set
  # here rather than read back off the report.
  def row(standard, weight)
    report = weight.success? ? yield(weight.value!) : weight
    { standard: standard, citation: citation_for(standard), weight: weight, report: report }
  end

  def citation_for(standard) = manifest(standard.to_s)[:source][:citation]

  def nichd_rows(weight, ga, stratum)
    fanned = row(:nichd, weight) { |efw| nichd(efw, ga, stratum) }
    return [fanned] unless fanned[:report].success?

    fanned[:report].value!.map { |percentile| fanned.merge(report: Success(percentile)) }
  end

  def intergrowth(estimate, ga)
    Biometry::Services::Growth::Intergrowth
      .new(manifest: manifest('intergrowth21')).call(estimate: estimate, ga: ga)
  end

  def hadlock1991(estimate, ga)
    Biometry::Services::Growth::Hadlock1991
      .new(manifest: manifest('hadlock_1991')).call(estimate: estimate, ga: ga)
  end

  def who(estimate, ga, sex)
    Biometry::Services::Growth::Who
      .new(manifest: manifest('who'), table: table('who'))
      .call(estimate: estimate, ga: ga, sex: sex)
  end

  def nichd(estimate, ga, stratum)
    Biometry::Services::Growth::Nichd
      .new(manifest: manifest('nichd'), table: table('nichd'))
      .call(estimate: estimate, ga: ga, stratum: stratum)
  end
end
