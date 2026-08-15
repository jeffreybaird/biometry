# Validation package — task brief

The library is built through slice 6. This package adds the validation layer:
1,964 fixtures, plus the findings that must not be silently reverted by anyone
making a suite green.

Most of it runs on every `rake verify` as regression coverage. One slice of it
does not, for a specific reason set out below.

Nothing here needs R, a network, or any tool not already in the repo.

---

## Files

| file | goes to | what it is |
|---|---|---|
| `FIXTURES.md` | `docs/FIXTURES.md` | the tier model — read first |
| `published.csv` | `spec/fixtures/` | 1,376 rows, tiers 1/2/4 |
| `oracle_efw.csv` | `spec/fixtures/` | 84 rows, tier 3a composed EFW path |
| `oracle_charts.csv` | `spec/fixtures/` | 504 rows, tier 3b chart percentiles |
| `fetalgps.rb` | `scripts/` | Ruby port of FetalGPSR's algorithm |
| `generate_published.rb` | `scripts/` | regenerates `published.csv` |
| `generate_oracle.rb` | `scripts/` | regenerates both oracle CSVs |

All Ruby, no external gems — `Math.erfc` for the normal CDF and an inline
Acklam approximation for its inverse.

The three CSVs are the deliverable; the generators are provenance. **Do not
wire the generators into the suite.** A regression test whose expectations are
recomputed on every run cannot detect a regression: fix a bug in `fetalgps.rb`
and every expected value shifts with it, silently.

`generate_oracle.rb` reads `data/percentiles/*.csv` and writes to
`spec/fixtures/`; `generate_published.rb` does the same. Both take paths
relative to the repo root, so run them from anywhere via
`bundle exec ruby scripts/generate_published.rb`.

---

## The tier model, in one paragraph

A fixture's tier is defined by what a failure *means*, not by where the data
came from. Tier 1 and 2 are ground truth from published papers: a failure is our
bug. Tier 3 is corroboration from a third-party implementation: a failure is a
question for a human. Tier 4 pins places where we deliberately differ from that
implementation: a failure means the fixture is stale, never that the code should
change to match. Full detail in `FIXTURES.md`.

**The reason this matters.** We differ from FetalGPS on Hadlock's dispersion by
about one percentile near the SGA threshold. Our value reproduces Hadlock's
published Table 1 exactly at every centile and every gestational age; theirs
does not. Put that comparison in a suite an agent can "fix" and the finding
reverts.

---

## What to build

### 1. Tier 1/2/4 runner — `spec/fixtures/published_spec.rb`

Reads `published.csv`. Columns: `tier`, `standard`, `note`, inputs
(`ga_weeks`, `stratum`, `efw_g`, `ac_cm`, `hc_cm`, `centile`), expectations
(`expect_centile`, `expect_efw_g`, `tolerance`), and for tier 4
(`fetalgps_centile`, `divergence`).

- **tier 1, nichd/who** — feed `efw_g` at `ga_weeks` with `stratum`; assert the
  returned centile equals `expect_centile` within `tolerance` (0.05). These are
  published knots, so an exact hit is the expected property.
- **tier 1, hadlock_1991** — same shape, tolerance 0.6, absorbing rounding in
  the published gram values.
- **tier 2** — worked examples; assert `expect_efw_g`.
- **tier 4** — assert our value AND record theirs. Failure means re-derive, not
  re-align.

Runs in `rake verify`.

### 2. Tier 3a runner — `spec/fixtures/oracle_efw_spec.rb` (IN `rake verify`)

Reads `oracle_efw.csv`. 84 rows, deduplicated by biometry since sex and race do
not affect EFW. Biometry in **mm**, GA in **days**.

Assert our EFW equals `fgps_efw_g` to 0.1 g. Also assert our formula selection
equals `fgps_efw_formula` — 42 rows have no BPD and must select the
three-parameter model, 42 have BPD and must select the four-parameter.
`fgps_efw_intergrowth_g` is the INTERGROWTH formula on the same biometry.

**This is regression coverage of the composed path**, and it is the only fixture
that exercises unit conversion, formula selection, the formula itself, and the
mm-to-cm boundary together. Everything else tests one link.

A failure here is unambiguously our bug. The three formulas have been diffed
character-for-character against both FetalGPSX (VBA) and FetalGPSR (R), and both
reproduce the paper's worked example. There is no third interpretation.

### 3. Tier 3b runner — `spec/oracle/chart_agreement_spec.rb` (NOT in `verify`)

Reads `oracle_charts.csv`. 504 rows, all with `compare_who`, `compare_nichd` and
`compare_intergrowth` set to 1 — no BPD is supplied, so FetalGPS selects the
same three-parameter formula those charts pair with.

**Assert the flag counts at load time.** All three must sum to 504. If they do
not, the CSV and the spec have drifted apart and every subsequent failure is
noise.

**Excluded from `verify` deliberately.** A failure here has three possible
causes and the suite cannot distinguish them: our bug, their bug, or a decision
we made. We already know all three exist — the Hadlock dispersion, the
formula-selection difference, and the fact that their own two implementations
disagree in the tails. Put this in the default run and the first red row gets
resolved by whoever is looking, under pressure to reach green, and a finding
that took reading Table 1's ratios to establish reverts silently.

Add `rake oracle` and run it deliberately.

**Not compared:** the Hadlock chart column, on every row. See divergence 1.

---

## Findings that must survive

### 1. Hadlock 1991 dispersion — 13.3%, not 12.7%

`FetalGPS.R` computes `sd = 0.127 * mu`, the abstract's figure. Ours is 13.3%,
back-calculated from Table 1's centile ratios (median x {0.750, 0.830, 1.170,
1.250}, constant across all 31 weeks).

| GA | centile | published | ours | FetalGPS |
|---|---|---|---|---|
| 30 | 3rd | 1,169 | 1,169 | 1,187 |
| 30 | 97th | 1,949 | 1,949 | 1,932 |
| 40 | 3rd | 2,714 | 2,714 | 2,755 |

Ours reproduces the source at every point; theirs matches only at the median.
The paper's Discussion and Table 3 both say 13%, supporting the table over the
abstract. Active 2025 AJOG exchange.

### 2. Formula selection is by input, not by chart

FetalGPS picks the EFW formula from which measurements are present — BPD absent
gives three-parameter, BPD present gives four — applied identically for every
standard. Their own paper claims otherwise. Supply BPD and ask for WHO and they
read WHO's table from a four-parameter weight, which our
`:formula_chart_mismatch` guard rejects. That guard is a genuine difference
from the published tool, not a quirk.

### 3. Their two implementations disagree with each other

Outside the tabulated centile band, FetalGPSX (VBA) clamps to 0/100 while
FetalGPSR (R) extrapolates a line through the outermost two centiles and clamps
afterwards. Same authors, same paper. There is no FetalGPS convention to
inherit, which is why the oracle vectors all sit inside the band.

### 4. Their ranges exceed the published tables

NICHD 10-42 against a table published 10-40 and fitted 15-40; Hadlock 10-41;
FMF 20-43. We return `:out_of_range` where they answer.

### 5. Source defects already encoded in `data/`

- Hadlock 1991 Table 1, week 30, 97th centile prints 1,649 g — below its own
  90th of 1,824. Ratio-implied 1,949. Typo, confirmed against the page scan.
  Fixtures use 1,949.
- INTERGROWTH's worked Z-score of 0.5617023 does not follow from its own
  Table 2; correct value 0.5544. Not fixtured.
- Buck Louis prose and Table 2 differ by 1 g in four cells. Fixture the table.

---

## Decisions still open

1. **Out-of-centile-band behaviour.** Clamp, extrapolate, or `:out_of_range`?
   The two FetalGPS implementations differ, so nothing to inherit. Recommend
   `:out_of_range` — "below the 3rd" is honest and an extrapolation off the end
   of a table is a number nobody published.
   *Resolved 2026-08-15: report the outermost published centile as a bound
   ("above the 95th"), never extrapolate. Out-of-band oracle rows are excluded
   from comparison. See FIXTURES.md, tier 4.*
2. **Interpolation between weeks** for NICHD and WHO. FetalGPS floors GA to the
   completed week. If we do the same, `32w0d` and `32w6d` return identical
   percentiles, which the oracle vectors will show.
3. **NICHD with no stratum.** They require race; we have no unstratified table
   until the 2021 unified standard is added.
4. **Whether to add FMF as a fifth chart.** The formula is in
   `scripts/fetalgps.rb`: `mn = 3.0893 + 0.00835x - 0.00002965x^2 -
   0.00000006062x^3` where `x = GA_days - 199`, `sd = 0.02464 +
   0.0000564*GA_days`, z on `log10(EFW)`. Nicolaides 2018, UOG 52:44-51.

---

## Suggested first prompt

```
Read docs/FIXTURES.md, then build the three fixture runners described in
VALIDATION_TASK.md sections 1-3.

In rake verify:
  spec/fixtures/published_spec.rb    (tiers 1, 2, 4)
  spec/fixtures/oracle_efw_spec.rb   (tier 3a, composed EFW path)

Behind a separate rake oracle task, NOT in verify:
  spec/oracle/chart_agreement_spec.rb  (tier 3b)

In the 3b spec, assert at load time that compare_who, compare_nichd and
compare_intergrowth each sum to 504. If they don't, fail immediately rather
than reporting hundreds of downstream mismatches.

Report failures grouped by tier. Do not fix anything yet — I want to see
which tiers are red before deciding what each failure means.
```

That last instruction is the important one. A tier 1 failure and a tier 4
failure call for opposite responses, and the first run is where an agent is
most likely to flatten the distinction.
