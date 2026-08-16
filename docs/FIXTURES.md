# Fixture strategy

Four tiers, distinguished by what a failure *means*. That distinction is the
whole point: tier 1 failing is a bug in our code, tier 4 failing is a bug in
our fixture. Mixing them means an implementer "fixes" a divergence we chose.

| tier | source | authority | failure means | in `rake verify`? |
|---|---|---|---|---|
| 1 | published tables and equations | ground truth | our bug | yes |
| 2 | worked examples in the papers | ground truth | our bug | yes |
| 3a | FetalGPS EFW agreement | arithmetic | our bug | yes |
| 3b | FetalGPS chart agreement | corroboration | investigate | no |
| 4 | known divergences from FetalGPS | our decision | our fixture is stale | yes |

`published.csv` holds tiers 1, 2 and 4 (1,376 rows; tier 4 is currently
empty — see its section). `oracle_efw.csv` holds tier 3a (84 rows) and
`oracle_charts.csv` tier 3b (504). All generated in Ruby with no external
gems: `scripts/fetalgps.rb` is a port of FetalGPSR's algorithm, traced line
by line to their source.

**Tier 3 splits because its two halves fail for different reasons.** The EFW
comparison is pure arithmetic on formulas verified against two independent
implementations of FetalGPS plus the source papers — a mismatch is our bug, so
it belongs in the regression run. The chart comparison carries the
interpolation rule, the range windows and, for the WHO and NICHD tables, the
out-of-band decision — places where we differ from FetalGPS on purpose. That
half stays out.

---

## Tier 1 — published tables (1,374 rows)

**NICHD and WHO: invert the table.** Every published centile value becomes an
input. Feed 1,686 g at 32 weeks on the NICHD white chart and the answer must be
exactly 10.

This is not circular even though the adapter reads the same CSV, because it
tests the inverse operation: the bracketing search, the boundary case where the
value lands exactly on a knot, and the stratum selection. A lookup returning the
table is trivially true; a search returning the right centile is not.

NICHD rows below 15 weeks are excluded — the table publishes them, the model was
fitted 15–40, and our loader rejects them.

**Hadlock 1991: assert the TABLE variant reproduces the published table.**
The table variant computes centiles from the median equation and a 13.3% SD;
Table 1 was printed from the original regression, and agreement between the
two is a real check on the variant's arithmetic. It says nothing about which
variant should be used clinically — that dispute is tier 4's subject below.
The equation variant (12.7%) has no published centile table to anchor to; it
is pinned by the `hadlock_1991_variants` delta rows and by the oracle's
`compare_hadlock` column instead.

Note the week-30 97th centile fixture uses **1,949 g**, not the 1,649 g printed
in the paper. That is a typographical error in the source, confirmed against the
page scan. Documented in `data/hadlock_1991.yml`.

**Tolerance.** 0.05 centiles for table inversion — an exact knot should be
exact. 0.6 centiles for the Hadlock equation-vs-table comparison, which absorbs
the rounding in the published gram values.

---

## Tier 2 — worked examples (2 rows)

INTERGROWTH is the only standard that publishes a fully worked example, and it
reproduces exactly: AC 26 cm, HC 29 cm → log(EFW) 7.312292 → 1,499 g, and the
3rd centile at 30 weeks → 1,106 g.

**Do not add the Z-score from that example.** The paper states 0.5617023; our
own arithmetic applying its Table 2 equations to the same inputs yields
0.5544. The discrepancy has not been checked against any published erratum or
independent source, so treat 0.5544 as our unverified re-derivation, not an
established correction. Neither value is fixtured.

**This tier is thin and that is the honest state.** Hadlock 1985 publishes no
worked example we could locate. A fixture previously in `hadlock_1985.yml`
claiming BPD 5.7 / HC 21.3 / AC 28.5 / FL 7.5 → 2,415 g was withdrawn: the
equation yields 1,951.6 g and no formula in the file produces 2,415 from those
inputs. Do not reinstate without a page reference.

---

## Tier 3 — FetalGPS agreement (generated separately, not committed to verify)

Volume corroboration. FetalGPSR is the only source that exercises the full
biometry → EFW → percentile path across all standards at once.

**Generate with:**

```r
library(devtools); install_github("dw1227/FetalGPSR"); library(FetalGPSR)
# GA in DAYS. Biometry in mm. Sex: "Male"/"Female"/"". Race: White|Black|Hispanic|Asian
input <- read.csv("oracle_inputs.csv")
write.csv(FetalGPS(input), "oracle_expected.csv")
```

**Four controls the harness must apply, or every row disagrees for the wrong
reason:**

1. **Omit BPD when comparing WHO or NICHD.** FetalGPS selects the EFW formula by
   which inputs are present, not by which chart is requested — `data3` (no BPD)
   gets the three-parameter Hadlock, `data4` (BPD present) gets the
   four-parameter, in every standard. Supply BPD and their WHO percentile is
   computed from a four-parameter weight, which our
   `:formula_chart_mismatch` guard would reject. Compare like with like.

2. **Restrict to the intersection of valid ranges.** Theirs are wider than ours
   in three places: NICHD 10–42 against our 15–40, Hadlock 10–41 against our
   10–40, FMF 20–43. Outside our range we return `:out_of_range` and they return
   a number. That is a scope difference, not a disagreement.

3. **Stay inside the tabulated centile band for WHO and NICHD.** Below the
   lowest or above the highest published centile the two FetalGPS
   implementations disagree with *each other*: the VBA clamps to 0/100, the R
   `interp()` extrapolates a line through the outermost two centiles and clamps
   only afterwards. There is no single FetalGPS answer to agree with there.

4. **Compare Hadlock only at whole-week gestational ages.** Our Hadlock 1991
   adapter evaluates at decimal weeks rounded to the nearest tenth, the
   convention the paper itself states; FetalGPS evaluates at unrounded
   days/7. Where the two readings coincide (whole weeks) the equation
   variant agrees with FetalGPS to within 0.05 centiles; where they differ
   the gap is the GA convention, not the chart.

**A tier 3 mismatch is a question, not a task.** Keep it out of `rake verify` so
no implementer resolves it alone.

---

## Tier 4 — known divergences (currently 0 rows)

Cases where we deliberately differ from FetalGPS. Each asserts our value *and*
theirs, so the gap is pinned in both directions. The tier is currently empty:
its only occupant, the Hadlock 1991 dispersion, was reframed as below.

### Hadlock 1991 dispersion — a contested question, served as two variants

The 1991 paper carries two irreconcilable dispersion figures and no erratum:
the abstract states 12.7% (1 SD), while its own Table 1 centiles are exactly
median × {0.750, 0.830, 1.170, 1.250} at all 31 weeks, implying 13.3%.

This repository originally implemented 13.3% only, framed as "ours reproduces
the source, FetalGPS's 12.7% does not". That framing was wrong: reproducing
the published table faithfully means reproducing whatever produced it, and
the table is the artifact under suspicion. Two independent groups have since
recalculated the table from the body-text formula and favour the equation
reading — Roberts AW, Maroufy V, Salazar A, et al., "Revisiting the Hadlock
1991 population reference for estimated fetal weight," AJOG 2025;233:331.e1-11
(who quantify that the table would have underdiagnosed fetal growth
restriction in 5.1% of patients across 176,060 encounters, relative to the
equation), and Gleason et al. at NICHD, AJOG 2026;234:e59-e63. FetalGPS's
`sd = 0.127 * mu` is not a divergence from the source; it implements the
reading those groups favour.

So the library carries **both** as chart variants — `hadlock_1991_equation`
(12.7%) and `hadlock_1991_table` (13.3%), default equation — and reports
both rows. The effect is roughly one percentile near common decision
thresholds: 7.7 (equation) against 8.7 (table) for a 1,600 g fetus at
32 weeks. The fixtures moved accordingly:

- tier 1 still validates the **table** variant against Table 1 (that the
  table implies 13.3% is verified arithmetic either way);
- tier 1 `hadlock_1991_variants` rows pin the gap between the variants, so
  neither can silently become the other — a stronger test than the old
  tier 4 rows, because it pins a decision rather than a disagreement;
- the oracle chart comparison gained a `compare_hadlock` column: the
  **equation** variant now agrees with FetalGPS to within 0.05 centiles at
  every whole-week point of the grid, adding 360 rows of coverage that were
  previously excluded. The 144 rows at non-whole-week gestational ages are
  excluded (`compare_hadlock: 0`): there the residual gap — up to ~1.6
  centiles where the median curve is steep — is our tenth-of-a-week GA
  convention (the paper's own) against FetalGPS's unrounded days/7, a
  documented decision rather than a chart disagreement.

Caveat recorded in `data/hadlock_1991.yml`: that Roberts' "equation" method
uses the abstract's 12.7% is inferred, not yet confirmed against the full
text. The figure lives only in the manifest's `variants` block, so a
correction is a data change.

### Not yet fixtured, but decided

- **Out-of-range**: we return `:out_of_range`; both FetalGPS versions answer.
- **Out-of-centile-band** (decided 2026-08-15): we report the outermost
  published centile as a bound — `Percentile` with `bound: :above`/`:below`
  and the edge column's value, read as "above the 95th" — and never
  extrapolate past what the source printed. The two FetalGPS implementations
  differ here (VBA clamps, R extrapolates), so there was no convention to
  inherit. The four oracle rows this touches (WHO female chart at 22 weeks
  publishes only the 5th–95th columns; the +3% perturbation pushes that EFW
  above the 95th's 557 g) carry `compare_who: 0` in `oracle_charts.csv` and
  are skipped by the tier 3b runner, whose load-time guard expects the
  resulting sums (500/504/504) exactly.
- **Formula/chart pairing**: enforced by us, absent in FetalGPS.

---

## Adding a fixture

Ask what a failure would mean. If the answer is "we're wrong", tiers 1–2. If
"we chose to differ", tier 4, and record both values. If "someone should look at
this", tier 3 and keep it out of `verify`.

Never move a row from tier 4 to tier 3 to make a suite green. That is the
mechanism by which a deliberate decision becomes an accident.
