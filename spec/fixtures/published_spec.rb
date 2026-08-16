# frozen_string_literal: true

require 'csv'

# Fixture runner for published.csv — tiers 1 and 2. See docs/FIXTURES.md for
# the tier model. What a failure means differs by tier:
#
#   tier 1 — published tables and equations. Ground truth; a failure is a bug
#            in our code.
#   tier 2 — worked examples printed in the papers. Same authority as tier 1.
#
# Tier 4 — places we deliberately diverge from FetalGPS — currently has no
# rows. Its only entries were the Hadlock 1991 dispersion divergence, and that
# has been reframed: 12.7% and 13.3% are no longer our figure against theirs
# but two variants of one standard, both reported. Nothing is being tolerated
# there any more, so the assertion moved to tier 1, where the equation
# variant's centile and the gap between the two variants are ground truth read
# off the paper's own numbers. The tier still exists in docs/FIXTURES.md and
# takes rows again the moment we choose to differ from someone.
#
# Tier 3 lives in oracle_efw_spec.rb (3a, in verify) and
# spec/oracle/chart_agreement_spec.rb (3b, `rake oracle` only).
RSpec.describe 'published fixtures (tiers 1, 2)' do
  def self.rows
    @rows ||= CSV.read(File.expand_path('published.csv', __dir__), headers: true)
  end

  def self.tier(number) = rows.select { |row| row['tier'] == number.to_s }

  def self.manifest(name)
    Biometry::ReferenceData.load_manifest(Biometry::DATA_ROOT / "#{name}.yml").first
  end

  def self.table(name)
    Biometry::ReferenceData.load_table(Biometry::DATA_ROOT / "percentiles/#{name}.csv")
  end

  def self.charts
    @charts ||= {
      'nichd' => Biometry::Services::Growth::Nichd.new(manifest: manifest('nichd'),
                                                       table: table('nichd')),
      'who' => Biometry::Services::Growth::Who.new(manifest: manifest('who'),
                                                   table: table('who')),
      # One paper, two dispersion figures, both reported. The Table 1 rows
      # anchor the table variant, because Table 1 is what it reproduces; the
      # equation variant has no published table of its own, so it is asserted
      # against the paper's stated 12.7% and against its distance from the
      # other variant.
      'hadlock_1991_equation' =>
        Biometry::Services::Growth::Hadlock1991.new(manifest: manifest('hadlock_1991'),
                                                    variant: :equation),
      'hadlock_1991_table' =>
        Biometry::Services::Growth::Hadlock1991.new(manifest: manifest('hadlock_1991'),
                                                    variant: :table),
      'intergrowth21' =>
        Biometry::Services::Growth::Intergrowth.new(manifest: manifest('intergrowth21'))
    }
  end

  def self.weight_intergrowth
    @weight_intergrowth ||=
      Biometry::Services::Weight::Intergrowth.new(manifest: manifest('intergrowth21'))
  end

  def charts = self.class.charts

  def inputs_for(formula)
    { hadlock_hc_ac_fl: %i[hc ac fl], hadlock_bpd_hc_ac_fl: %i[bpd hc ac fl],
      intergrowth: %i[ac hc] }.fetch(formula)
  end

  def estimate(grams, formula:)
    Biometry::Estimate.new(
      value: grams, unit: 'g', formula: formula, inputs: inputs_for(formula),
      source: Biometry::Provenance.formula(standard: :fixture, citation: 'fixture',
                                           formula: formula),
      uncertainty: nil
    )
  end

  def weeks(count) = Biometry::GestationalAge.from(weeks: count.to_i)

  def centile_of(row)
    grams = row['efw_g'].to_f
    ga = weeks(row['ga_weeks'])
    case row['standard']
    when 'nichd' then nichd_centile(grams, ga, row['stratum'].to_sym)
    when 'who' then who_centile(grams, ga, row['stratum'])
    when 'hadlock_1991_table' then hadlock_centile(grams, ga, :table)
    when 'hadlock_1991_equation' then hadlock_centile(grams, ga, :equation)
    end
  end

  def nichd_centile(grams, ga, stratum)
    charts['nichd']
      .call(estimate: estimate(grams, formula: :hadlock_hc_ac_fl), ga: ga, stratum: stratum)
      .value!.first.value
  end

  def who_centile(grams, ga, stratum)
    sex = stratum == 'combined' ? nil : stratum.to_sym
    charts['who']
      .call(estimate: estimate(grams, formula: :hadlock_hc_ac_fl), ga: ga, sex: sex)
      .value!.value
  end

  def hadlock_centile(grams, ga, variant)
    charts["hadlock_1991_#{variant}"]
      .call(estimate: estimate(grams, formula: :hadlock_bpd_hc_ac_fl), ga: ga)
      .value!.value
  end

  def intergrowth_centile_of(grams, ga)
    charts['intergrowth21']
      .call(estimate: estimate(grams, formula: :intergrowth), ga: ga)
      .value!.value
  end

  # Monotone in grams, so a bisection recovers the weight at a centile without
  # the library needing an inverse it does not expose.
  def intergrowth_efw_at(centile, ga)
    bounds = 40.times.reduce([100.0, 6000.0]) do |(lo, hi), _|
      mid = (lo + hi) / 2.0
      intergrowth_centile_of(mid, ga) < centile ? [mid, hi] : [lo, mid]
    end
    bounds.sum / 2.0
  end

  def intergrowth_weight(ac_cm, hc_cm)
    scan = Biometry::Scan.new(
      date: Date.new(2026, 1, 1),
      measurements: [Biometry::Measurement.new(kind: :ac, mm: ac_cm * 10.0),
                     Biometry::Measurement.new(kind: :hc, mm: hc_cm * 10.0)]
    )
    self.class.weight_intergrowth.call(scan).value!.value
  end

  # The variant rows are tier 1 too, but they assert a pair of readings rather
  # than one, so they generate their own examples below.
  def self.variant_rows = tier(1).select { |row| row['standard'] == 'hadlock_1991_variants' }

  def self.chart_rows = tier(1) - variant_rows

  describe 'tier 1 — published tables and equations (a failure is our bug)' do
    chart_rows.each do |row|
      it "#{row['standard']}/#{row['stratum'] || 'unstratified'}: #{row['efw_g']} g at " \
         "#{row['ga_weeks']}w reads as the #{row['expect_centile']} centile " \
         "(#{row['note']})" do
        expect(centile_of(row))
          .to be_within(row['tolerance'].to_f).of(row['expect_centile'].to_f)
      end
    end
  end

  describe 'tier 2 — worked examples from the papers (a failure is our bug)' do
    tier(2).each do |row|
      if row['ac_cm']
        it "intergrowth: AC #{row['ac_cm']} cm, HC #{row['hc_cm']} cm weighs " \
           "#{row['expect_efw_g']} g (#{row['note']})" do
          expect(intergrowth_weight(row['ac_cm'].to_f, row['hc_cm'].to_f))
            .to be_within(row['tolerance'].to_f).of(row['expect_efw_g'].to_f)
        end
      else
        it "intergrowth: the #{row['centile']}rd centile at #{row['ga_weeks']}w weighs " \
           "#{row['expect_efw_g']} g (#{row['note']})" do
          expect(intergrowth_efw_at(row['centile'].to_f, weeks(row['ga_weeks'])))
            .to be_within(row['tolerance'].to_f).of(row['expect_efw_g'].to_f)
        end
      end
    end
  end

  # Tier 1 as well, and the rows that hold the decision itself: the two
  # dispersion figures are two variants of one standard, and neither may
  # quietly become the other. Each row asserts the equation variant's centile
  # and the gap between the variants at the same weight, so collapsing them —
  # in either direction — fails here whichever figure the collapse chose.
  #
  # The gap is negative throughout the lower tail: the narrower SD puts a
  # small fetus lower. That is the direction Roberts et al. quantify as 5.1%
  # of patients, and it is pinned as a signed number rather than a magnitude.
  describe 'tier 1 — the two Hadlock 1991 variants stay distinct ' \
           '(a failure means one has become the other)' do
    variant_rows.each do |row|
      it "hadlock_1991: #{row['efw_g']} g at #{row['ga_weeks']}w reads as the " \
         "#{row['expect_centile']} centile on the equation variant" do
        expect(hadlock_centile(row['efw_g'].to_f, weeks(row['ga_weeks']), :equation))
          .to be_within(row['tolerance'].to_f).of(row['expect_centile'].to_f)
      end

      it "hadlock_1991: at #{row['ga_weeks']}w the equation variant sits " \
         "#{row['expect_delta']} centiles from the table variant" do
        grams = row['efw_g'].to_f
        ga = weeks(row['ga_weeks'])
        delta = hadlock_centile(grams, ga, :equation) - hadlock_centile(grams, ga, :table)
        expect(delta).to be_within(row['tolerance'].to_f).of(row['expect_delta'].to_f)
      end
    end
  end
end
