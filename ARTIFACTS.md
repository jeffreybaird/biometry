# ARTIFACTS — what exists, where it goes, who reads it

Read this before PROJECT.md. Where the two disagree, this file wins; the
corrections section below lists every point of disagreement.

---

## 1. Inventory

### Repo configuration — you install these once

| Artifact | Path in repo | Read by |
|---|---|---|
| `CLAUDE.md` | `CLAUDE.md` | every agent, every turn |
| `.rubocop.yml` | `.rubocop.yml` | rubocop only; agents see offences, not config |

Both were written for a generic Ruby CLI. Two edits needed before use:

- `.rubocop.yml` — `Naming/MethodParameterName.AllowedNames` currently allows
  grid coordinates (`x`, `y`, `dx`, `dy`). This project wants `ga`, `ac`, `hc`,
  `fl`, `bpd`, `hl`, `efw`, `wk`. Replace the list.
- `CLAUDE.md` — add the no-invented-constants rule (section 3 below). It is the
  single most important rule in this project and it is not in there yet.

### Agent definitions — given inline earlier in the conversation

| File | Model | Purpose |
|---|---|---|
| `.claude/agents/spec-writer.md` | opus | writes failing specs, owns `spec/` |
| `.claude/agents/reviewer.md` | opus | reads merged diff, read-only |
| `.claude/agents/test-runner.md` | haiku | runs a command, reports failures verbatim |
| `.claude/agents/Explore.md` | haiku | overrides built-in Explore to keep it cheap |
| `.claude/settings.json` | — | `PreToolUse` + `TaskCompleted` hook registration |
| `scripts/protect-tests.sh` | — | blocks spec edits by anyone but spec-writer |
| `Rakefile`, `Gemfile` | — | `rake verify` gate |

### Reference data — the authoritative constants

| Artifact | Path in repo | Consumed by |
|---|---|---|
| `hadlock.yml` | `data/hadlock.yml` | slice 3 (EFW), slice 4 (growth) |
| `intergrowth21_efw.yml` | `data/intergrowth21.yml` | slice 3, slice 4 |
| `nichd.yml` | `data/nichd.yml` | slice 4 |
| `nichd_efw_percentiles.csv` | `data/percentiles/nichd.csv` | slice 4 |
| `who.yml` | `data/who.yml` | slice 4 |
| `who_efw_percentiles.csv` | `data/percentiles/who.csv` | slice 4 |

Rename `intergrowth21_efw.yml` → `intergrowth21.yml` on the way in; it now
carries both the formula and the LMS centile equations, so the `_efw` suffix
is misleading.

### Not part of this project

`soa_maternal_participants.csv` and `soa_legend_and_footnotes.csv` are the RSV
protocol table extraction. Unrelated. Keep them out of `data/`.

---

## 2. The authority rule

Add to `CLAUDE.md` verbatim:

```markdown
### Reference data is input, never output

`data/` holds clinical constants transcribed by hand from published sources.
It is read-only to every agent.

Never derive, interpolate, recall, or infer a clinical constant. If a value a
slice needs is not in `data/`, stop and report it. Do not compute it, do not
approximate it, do not supply it from training data.

Every value returned to a caller carries the standard it came from and the
formula that produced it. A number without provenance is incomplete.

This library reports measurements and their sources. It never emits a
classification: no "SGA", "IUGR", "macrosomia", "abnormal", "normal", or any
threshold-crossing label.
```

This is the rule most likely to be silently dropped once a slice gets long.
The reviewer should check for violations explicitly.

---

## 3. Per-slice routing

### Slice 0 — shared types (you, serially, committed first)

Reads nothing. Produces `lib/biometry/models/`, plus the `data/` files copied
in and committed. Everything below is blocked on this.

### Slice 1 — gestational age and EDD

Reads: nothing from `data/`. Pure date arithmetic.

Spec-writer prompt:

> Use spec-writer for slice 1 (gestational age and EDD derivation) per
> PROJECT.md. No reference constants are involved; this is date arithmetic and
> the IVF dating convention. Assert on `GestationalAge` and `Estimate` values.

Watch for: the IVF convention. A day-5 blastocyst transfer is 2w5d at
transfer, not day zero. Getting this wrong shifts everything downstream by
about two weeks.

### Slice 2 — redating policy

Reads: `data/acog_redating.yml` — **DOES NOT EXIST YET. BLOCKING.**

Do not run this slice until you have transcribed ACOG Committee Opinion 700
Table 1 yourself. The thresholds in PROJECT.md came from my memory, were later
confirmed against a secondary source, and have still not been read off the
primary document. Two details that must be captured and are easy to lose:

- The 22w0d–27w6d band has a discretionary zone: changes for discrepancies of
  10–14 days may be appropriate depending on how early in the range the scan
  fell and the reliability of the LMP. It is not a hard line.
- Third-trimester dating carries ±21–30 day accuracy, and redating a small
  fetus risks masking growth restriction. Surface this caveat rather than
  silently applying the 21-day threshold.

### Slice 3 — estimated fetal weight

Reads: `data/hadlock.yml` (four formulas), `data/intergrowth21.yml` (one).

Five formulas total, not four. Each declares its required parameters.

Spec-writer prompt:

> Use spec-writer for slice 3 (EFW) per PROJECT.md. The five formulas and
> their coefficients are in `data/hadlock.yml` and `data/intergrowth21.yml` —
> read them, do not derive or recall any coefficient. Every file carries a
> `fixtures:` block; build specs from those fixtures first, then add
> `:insufficient_data` cases for each formula's missing-parameter paths.

Fixtures already available:

- INTERGROWTH: AC 26 cm, HC 29 cm → log 7.312292, EFW 1499 g
- Hadlock `hc_ac_fl`: the microcephalic case (BPD 5.7, HC 21.3, AC 28.5,
  FL 7.5) → 2415 g against actual 2250 g, a 7.3% error. The paper reports a
  BPD+AC model missing by 46.8% on the same fetus, which is a good regression
  test for formula selection.

Watch for: INTERGROWTH requires AC and HC and has no FL term. A scan with
BPD, AC and FL but no HC cannot produce an INTERGROWTH EFW. That is a real
`:insufficient_data` path, not a hypothetical.

### Slice 4 — growth percentiles

Reads: all four data files. **This slice is not uniform and PROJECT.md is
wrong about it.**

| Standard | Method | Dispersion model | Range | Strata |
|---|---|---|---|---|
| INTERGROWTH-21st | equation | LMS, closed form | 22–40 | none |
| Hadlock 1991 | equation | median × constant 13.3% | 10–40 | none |
| NICHD | table | 3 fitted, 4 log-normally derived | 15–40 | race/ethnicity (4) |
| WHO | table | quantile regression, each centile independent | 14–40 | fetal sex (3) |

Four different dispersion models, two access methods, three different valid
ranges, two different stratification axes. The adapter interface has to carry
all of it. If spec-writer proposes a uniform "lookup" interface, reject it.

Spec-writer prompt:

> Use spec-writer for slice 4 (growth percentiles) per PROJECT.md, corrected by
> ARTIFACTS.md section 3. Four adapters with heterogeneous access methods:
> INTERGROWTH and Hadlock are closed-form equations, NICHD and WHO are lookup
> tables. Read each standard's manifest in `data/` for its valid range,
> stratification axis, available centiles, and paired EFW formula. Do not
> invent an interpolation rule — it is specified below and must be identical
> across both table-based adapters.

Decisions to pin before writing specs, or four agents will pin them four ways:

1. **Interpolation between weeks** — undefined in every source. Pick one rule.
2. **Interpolation between centiles** — same. Note WHO's distribution is
   deliberately asymmetric, so linear interpolation is a worse approximation
   there than for the log-normal standards.
3. **Out of range** — each standard differs. Return `:out_of_range` naming
   the standard and its window; never extrapolate.
4. **NICHD weeks 10–14** — present in the CSV, outside the fitted range.
   The loader must filter them. See `nichd.yml`.
5. **Missing stratum** — WHO combined table exists; NICHD has no unstratified
   table until the 2021 unified standard is added. Decide what NICHD returns
   when race/ethnicity is not supplied.

This is the one slice worth a parallel fan-out. One adapter per file, no shared
logic, and the seam defects (four independent interpolation decisions, four
error shapes) are exactly what the reviewer exists to catch.

### Slice 5 — presentation

Reads: nothing from `data/` directly; renders `Estimate` objects.

The output shape in PROJECT.md is wrong. See corrections below.

### Slice 6 — HL7 ORU^R01

Reads: nothing from `data/`. Unchanged from PROJECT.md.

---

## 4. Corrections to PROJECT.md

Apply these before handing PROJECT.md to spec-writer.

| Section | What's wrong | Correct version |
|---|---|---|
| `data/` layout | Invented file names and a `manifest.yml` that doesn't exist | Per-standard YAML manifests as listed in section 1 |
| Slice 3 | "Hadlock published several EFW regressions" — vague | Four Hadlock (1985 Table II, n=276) plus one INTERGROWTH. Five total. |
| Slice 4 | "percentile lookup per standard" | Two equations, two tables. See the table in section 3. |
| Slice 5 mock | One EFW compared against four charts | Three EFW values. INTERGROWTH uses its own AC+HC formula; Hadlock 1991's chart pairs with the four-parameter model; WHO and NICHD both pair with `hadlock_hc_ac_fl`. |
| Slice 4 note | Percentile tables to be transcribed for Hadlock and INTERGROWTH | Both publish closed-form equations. No tables needed. |

The corrected output shape:

```
GA 32w1d (by CRL 2026-01-14)     AC 27.4 cm  HC 29.1 cm  FL 6.2 cm  BPD 8.2 cm

  INTERGROWTH-21st   EFW 2,180 g  (AC+HC)         11th   prescriptive
  Hadlock 1991       EFW 2,240 g  (BPD+HC+AC+FL)   8th   reference
  WHO (female)       EFW 2,215 g  (HC+AC+FL)      10th   reference
  NICHD (white)      EFW 2,215 g  (HC+AC+FL)       9th   prescriptive

  Sources: Stirnemann 2017; Hadlock 1985/1991; Kiserud 2017; Buck Louis 2015
```

Note the `prescriptive` / `reference` column. WHO deliberately retained
complicated pregnancies; INTERGROWTH and NICHD deliberately excluded them.
A 10th centile does not mean the same thing across that column, and the
tool should say so rather than implying four comparable numbers.

---

## 5. Verification ledger

What has actually been checked, so the reviewer knows what not to re-litigate.

**Verified by independent implementation:**

- INTERGROWTH LMS equations reproduce the paper's worked example exactly
  (λ, μ, σ, EFW 1499 g, 3rd centile 1106 g) and Table S1 at 33 weeks to the
  gram.
- Hadlock 1991 median equation reproduces its own Table 1 to within 0.02%
  from 20 weeks on.
- Hadlock 1991 table centiles are exactly median × {0.750, 0.830, 1.170,
  1.250}, implying SD 13.3%.
- NICHD Table 2: centiles monotonic in every row, every column monotonic in GA.
- WHO Tables 11/14/15: same checks pass; 37-week sex gap is exactly 84 g as
  stated; Table 16's WHO rows match Table 11 at all ten checkpoints.

**Verified across sources:**

- Kiserud Table 16 quotes 40 NICHD values. All 40 match our independent
  transcription of Buck Louis Table 2. Two transcriptions agreeing.
- Hadlock `hc_ac_fl` coefficients match LOINC 11746-5 and INTERGROWTH's 2021
  paper independently.

**Known defects in the published sources — encoded in the manifests:**

- Hadlock 1991 abstract says SD ±12.7%; the table implies 13.3%. Implement
  13.3%. Subject of an active 2025 AJOG exchange.
- Hadlock 1991 Table 1, week 30, 97th centile prints 1,649 g — below its own
  90th of 1,824. Should be ~1,949. Confirmed a typo by inspecting the scan.
- INTERGROWTH worked Z-score of 0.5617023 does not follow from its own Table 2
  equations; correct value is 0.5544. Do not fixture on it.
- INTERGROWTH computed centiles diverge ~20 g from published Table S1 at 40
  weeks in both tails while matching exactly at 33 weeks. Unresolved.
- NICHD Table 2 tabulates weeks 10–40 but was fitted 15–40.
- Buck Louis prose and Table 2 differ by 1 g in four cells. Fixture the table.

**Retracted:** I earlier said the three WHO corrections were a blocker. They
are not. All three affect Fig 1 and the FL/HC and FL/BPD ratio tables. The
EFW tables were never reissued.

---

## 6. Blocking gaps

1. **`data/acog_redating.yml` does not exist.** Slice 2 cannot start. Requires
   reading ACOG Committee Opinion 700 Table 1 directly.
2. **NICHD paired formula is stated but the reference number was not resolved.**
   The Methods say HC, AC and FL via "a Hadlock formula" citing ref 20. The
   parameter set identifies it as `hc_ac_fl`, but confirm ref 20 is Hadlock
   1985 and not the 1984 Radiology paper.
3. **WHO S1 File not pulled.** It is an XLSX with every chart machine-readable.
   Diffing it against `data/percentiles/who.csv` would validate the hand
   transcription mechanically. Worth doing before building on it.
4. **NICHD 2021 unified standard not gathered.** Optional fifth chart. Decide
   whether it is in scope before spec-writer sees slice 4.
5. **Hadlock 1991 equation-vs-table dispute unread.** Roberts et al. 2025 AJOG
   and the published reply. Determines whether the Hadlock adapter implements
   the equation or the table. They are not the same standard.
