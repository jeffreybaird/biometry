#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates spec/fixtures/published.csv — tiers 1, 2 and 4.
#
# Provenance only. NOT run by the suite: a regression test whose expectations
# are recomputed on every run cannot detect a regression.
#
#   bundle exec ruby scripts/generate_published.rb

require "csv"
require_relative "fetalgps"

ROOT = File.expand_path("..", __dir__)
NICHD_CSV = File.join(ROOT, "data/percentiles/nichd.csv")
WHO_CSV   = File.join(ROOT, "data/percentiles/who.csv")
OUT       = File.join(ROOT, "spec/fixtures/published.csv")

OUR_HADLOCK_SD  = 0.133   # back-calculated from Hadlock 1991 Table 1
THEIR_HADLOCK_SD = 0.127  # the abstract's figure, used by FetalGPS

rows = []
def rows.add(tier, standard, note, inputs, expected)
  push({ tier: tier, standard: standard, note: note }.merge(inputs).merge(expected))
end

# ---- TIER 1: published table knots ----------------------------------------
# Feeding a tabulated value back in must return that exact centile. Not
# circular: this tests the inverse operation — bracketing search, exact-knot
# handling, stratum selection.

CSV.foreach(NICHD_CSV, headers: true) do |r|
  wk = r["ga_weeks"].to_i
  next if wk < 15 # published 10-40, fitted 15-40; the loader rejects below 15

  FetalGPS::NICHD_CENTILES.each_with_index do |c, i|
    rows.add(1, "nichd", "published knot",
             { ga_weeks: wk, stratum: r["group"], efw_g: r[FetalGPS::NICHD_KEYS[i]].to_i },
             { expect_centile: c, tolerance: 0.05 })
  end
end

CSV.foreach(WHO_CSV, headers: true) do |r|
  wk = r["ga_weeks"].to_i
  FetalGPS::WHO_CENTILES.each_with_index do |c, i|
    v = r[FetalGPS::WHO_KEYS[i]]
    next if v.to_s.empty? # sex-specific tables omit 2.5 and 97.5

    rows.add(1, "who", "published knot",
             { ga_weeks: wk, stratum: r["sex"], efw_g: v.to_i },
             { expect_centile: c, tolerance: 0.05 })
  end
end

# Hadlock: assert our equation reproduces the paper's printed Table 1.
# Week 30's 97th is 1,949 here, not the 1,649 the paper prints — that value is
# below its own 90th of 1,824 and is a typo, confirmed against the page scan.
HADLOCK_TABLE1 = {
  20 => [248, 275, 331, 387, 414],
  30 => [1169, 1294, 1559, 1824, 1949],
  32 => [1465, 1621, 1953, 2285, 2441],
  40 => [2714, 3004, 3619, 4234, 4524]
}.freeze

HADLOCK_TABLE1.each do |wk, values|
  [3, 10, 50, 90, 97].each_with_index do |c, i|
    rows.add(1, "hadlock_1991", "published Table 1 value",
             { ga_weeks: wk, efw_g: values[i] },
             { expect_centile: c, tolerance: 0.6 })
  end
end

# ---- TIER 2: worked examples from the papers -------------------------------
# Do NOT add INTERGROWTH's worked Z-score of 0.5617023; its own Table 2
# equations yield 0.5544 from the same inputs.
rows.add(2, "intergrowth", "paper worked example",
         { ac_cm: 26, hc_cm: 29 }, { expect_efw_g: 1499, tolerance: 1 })
rows.add(2, "intergrowth", "paper worked example, 3rd centile at 30w",
         { ga_weeks: 30, centile: 3 }, { expect_efw_g: 1106, tolerance: 1 })

# ---- TIER 4: pinned divergences from FetalGPS ------------------------------
# NEVER resolve one of these by changing the library to agree.
[[20, 300], [30, 1200], [32, 1600], [36, 2300], [40, 2900]].each do |wk, efw|
  ours   = FetalGPS.hadlock_centile(efw, wk.to_f, sd_pct: OUR_HADLOCK_SD)
  theirs = FetalGPS.hadlock_centile(efw, wk.to_f, sd_pct: THEIR_HADLOCK_SD)
  rows.add(4, "hadlock_1991",
           "FetalGPS uses the abstract SD (12.7%); we use the table-implied 13.3%",
           { ga_weeks: wk, efw_g: efw },
           { expect_centile: ours, fetalgps_centile: theirs,
             divergence: (ours - theirs).round(1), tolerance: 0.1 })
end

COLUMNS = %i[tier standard note ga_weeks stratum efw_g ac_cm hc_cm centile
             expect_centile expect_efw_g fetalgps_centile divergence tolerance].freeze

FileUtils = nil # not needed; keep the dependency surface empty
CSV.open(OUT, "w") do |csv|
  csv << COLUMNS
  rows.each { |r| csv << COLUMNS.map { |c| r[c] } }
end

by_tier = rows.group_by { |r| [r[:tier], r[:standard]] }
                 .transform_values(&:size).sort
by_tier.each { |(t, s), n| puts format("  tier %d  %-14s %5d", t, s, n) }
puts "  #{rows.size} rows -> #{OUT}"
