#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates spec/fixtures/oracle_efw.csv (tier 3a) and oracle_charts.csv
# (tier 3b) by running the FetalGPS algorithm over a controlled input grid.
#
# Provenance only. NOT run by the suite.
#
#   bundle exec ruby scripts/generate_oracle.rb
#
# The grid is deliberately restricted to the intersection where we and FetalGPS
# compute the same thing, so a mismatch means a real disagreement rather than a
# scope difference:
#
#   * GA 22-40 weeks — INTERGROWTH's window is the binding constraint
#   * biometry from WHO's published medians, perturbed +/-3% so every EFW lands
#     inside the tabulated centile band. Outside that band FetalGPSX clamps and
#     FetalGPSR extrapolates, so there is no single FetalGPS answer to compare.
#   * BPD omitted on the chart rows, so FetalGPS selects the three-parameter
#     Hadlock formula — the one WHO, NICHD and INTERGROWTH's charts pair with.

require "csv"
require_relative "fetalgps"

ROOT = File.expand_path("..", __dir__)
TABLES = FetalGPS::Tables.new(
  nichd_path: File.join(ROOT, "data/percentiles/nichd.csv"),
  who_path:   File.join(ROOT, "data/percentiles/who.csv")
)

# WHO Kiserud 2017 Tables 6-9, 50th centile, mm: [ac, hc, fl, bpd]
MEDIAN = {
  22 => [173, 198, 38, 53], 24 => [197, 222, 43, 60], 26 => [219, 244, 48, 66],
  28 => [240, 264, 52, 72], 30 => [260, 281, 56, 77], 32 => [279, 296, 61, 81],
  34 => [298, 309, 65, 85], 36 => [317, 321, 69, 89], 38 => [338, 332, 72, 92],
  40 => [363, 342, 73, 96]
}.freeze

GA_DAYS = ((22..40).step(2).map { |w| w * 7 } +
           [22 * 7 + 3, 30 * 7 + 3, 32 * 7 + 3, 36 * 7 + 5]).uniq.sort
SCALES  = [0.97, 1.00, 1.03].freeze
RACES   = %w[white black hispanic asian].freeze
SEXES   = ["female", "male", ""].freeze

# Outermost published weight per chart row. Outside that band the two FetalGPS
# implementations disagree with *each other* — FetalGPSX clamps to the edge,
# FetalGPSR extrapolates a line through the outermost two centiles — so there
# is no single FetalGPS answer to compare against. Rows whose EFW falls
# outside a chart's band carry compare_* = 0 and the runner skips them.
# (The +/-3% perturbation keeps most rows inside; the WHO sex-specific charts
# publish only the 5th-95th columns at some weeks, so their band is narrower
# than the combined chart's and a few rows escape it.)
def band(path, key_cols, value_cols)
  CSV.read(path, headers: true).each_with_object({}) do |r, h|
    values = value_cols.filter_map { |c| r[c].to_f unless r[c].to_s.empty? }
    h[key_cols.map { |k| r[k] }] = [values.min, values.max]
  end
end

WHO_BAND   = band(File.join(ROOT, "data/percentiles/who.csv"), %w[sex ga_weeks], FetalGPS::WHO_KEYS)
NICHD_BAND = band(File.join(ROOT, "data/percentiles/nichd.csv"), %w[group ga_weeks], FetalGPS::NICHD_KEYS)

def in_band?(bands, key, efw)
  lo, hi = bands.fetch(key, [nil, nil])
  !lo.nil? && efw.between?(lo, hi)
end

BASE_NOTE = "three-parameter formula; matches what WHO, NICHD and INTERGROWTH pair with"

def note_for(excluded, hadlock_excluded: false)
  suffixes = []
  unless excluded.empty?
    suffixes << "#{excluded.join(' and ')} comparison excluded: EFW outside the " \
                "tabulated centile band, where FetalGPSX and FetalGPSR disagree with each other"
  end
  if hadlock_excluded
    suffixes << "Hadlock comparison excluded: GA is not a whole week, and we read the " \
                "chart at the paper's tenth-of-a-week convention while FetalGPS uses " \
                "unrounded days/7 — a convention difference, not a chart disagreement"
  end
  ([BASE_NOTE] + suffixes).join("; ")
end

# Our Hadlock adapter evaluates at decimal weeks rounded to the nearest tenth,
# the convention the 1991 paper itself states; FetalGPS evaluates at unrounded
# days/7. Where the two GA readings coincide the equation variant agrees with
# FetalGPS to within 0.05 centiles across the whole grid; where they differ
# the gap is the GA convention, so those rows are excluded from comparison.
def hadlock_ga_matches?(gad)
  ((gad / 0.7).round / 10.0) == (gad / 7.0)
end

def biometry(ga_weeks, scale)
  keys = MEDIAN.keys
  lo = keys.select { |k| k <= ga_weeks }.max || keys.first
  hi = keys.select { |k| k >= ga_weeks }.min || keys.last
  base = if lo == hi
           MEDIAN[lo]
         else
           f = (ga_weeks - lo) / (hi - lo).to_f
           MEDIAN[lo].each_with_index.map { |v, i| v + f * (MEDIAN[hi][i] - v) }
         end
  base.map { |b| (b * scale).round(1) }
end

efw_rows = []
chart_rows = []
seen = {}

GA_DAYS.each do |gad|
  ga_weeks = gad / 7.0
  SCALES.each do |scale|
    ac, hc, fl, bpd = biometry(ga_weeks, scale)

    # --- tier 3a: EFW only. Both formulas, deduplicated by biometry since sex
    #     and race do not affect weight.
    [[nil, "no_bpd"], [bpd, "with_bpd"]].each do |bpd_mm, kind|
      key = [gad, ac, hc, fl, bpd_mm]
      next if seen[key]

      seen[key] = true
      r = FetalGPS.call(tables: TABLES, ga_days: gad,
                        ac_mm: ac, hc_mm: hc, fl_mm: fl, bpd_mm: bpd_mm)
      efw_rows << { case: kind, ga_days: gad, ac_mm: ac, hc_mm: hc, fl_mm: fl,
                    bpd_mm: bpd_mm, fgps_efw_g: r[:efw_g],
                    fgps_efw_formula: r[:efw_formula],
                    fgps_efw_intergrowth_g: r[:efw_intergrowth_g] }
    end

    # --- tier 3b: chart percentiles, no BPD so formula selection matches ours
    RACES.product(SEXES).each do |race, sex|
      r = FetalGPS.call(tables: TABLES, ga_days: gad, ac_mm: ac, hc_mm: hc,
                        fl_mm: fl, sex: sex, race: race)
      next if r[:who].nil? || r[:nichd].nil?

      who_chart = %w[male female].include?(sex) ? sex : "combined"
      floor_ga = (gad / 7).to_s
      cmp_who = in_band?(WHO_BAND, [who_chart, floor_ga], r[:efw_g]) ? 1 : 0
      cmp_nichd = in_band?(NICHD_BAND, [race, floor_ga], r[:efw_g]) ? 1 : 0
      excluded = []
      excluded << "WHO" if cmp_who.zero?
      excluded << "NICHD" if cmp_nichd.zero?

      # fgps_hadlock compares against our EQUATION variant, which implements
      # the same 12.7% SD FetalGPS does. The table variant (13.3%) has no
      # FetalGPS counterpart and is validated against Table 1 instead. The
      # chart is closed form, so no band restriction applies — only the GA
      # convention restriction (see hadlock_ga_matches?).
      cmp_hadlock = hadlock_ga_matches?(gad) ? 1 : 0
      chart_rows << {
        case: "no_bpd", ga_days: gad, ac_mm: ac, hc_mm: hc, fl_mm: fl, bpd_mm: nil,
        sex: sex.empty? ? "combined" : sex, race: race,
        fgps_efw_g: r[:efw_g], fgps_who: r[:who], fgps_nichd: r[:nichd],
        fgps_intergrowth: r[:intergrowth21], fgps_hadlock: r[:hadlock],
        compare_who: cmp_who, compare_nichd: cmp_nichd, compare_intergrowth: 1,
        compare_hadlock: cmp_hadlock,
        note: note_for(excluded, hadlock_excluded: cmp_hadlock.zero?)
      }
    end
  end
end

EFW_COLS = %i[case ga_days ac_mm hc_mm fl_mm bpd_mm
              fgps_efw_g fgps_efw_formula fgps_efw_intergrowth_g].freeze
CHART_COLS = %i[case ga_days ac_mm hc_mm fl_mm bpd_mm sex race fgps_efw_g
                fgps_who fgps_nichd fgps_intergrowth fgps_hadlock
                compare_who compare_nichd compare_intergrowth compare_hadlock
                note].freeze

{ "oracle_efw.csv" => [EFW_COLS, efw_rows],
  "oracle_charts.csv" => [CHART_COLS, chart_rows] }.each do |name, (cols, data)|
  path = File.join(ROOT, "spec/fixtures", name)
  CSV.open(path, "w") do |csv|
    csv << cols
    data.each { |r| csv << cols.map { |c| r[c] } }
  end
  puts format("  %-20s %4d rows -> %s", name, data.size, path)
end

puts "  3-param EFW rows: #{efw_rows.count { |r| r[:fgps_efw_formula] == 'hadlock_hc_ac_fl' }}"
puts "  4-param EFW rows: #{efw_rows.count { |r| r[:fgps_efw_formula] == 'hadlock_bpd_hc_ac_fl' }}"
%i[compare_who compare_nichd compare_intergrowth compare_hadlock].each do |c|
  puts "  #{c}: #{chart_rows.sum { |r| r[c] }}"
end
