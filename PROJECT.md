# biometry — project specification

A Ruby library and CLI that computes estimated fetal weight and growth
percentiles across the competing international standards, and shows where they
disagree.

Every published calculator gives you a number from one standard. The
disagreement between standards is this tool's output, not a caveat on it.

---

## Where the repo stands

**Slice 0 is built except for `spec/`.** The library loads, the CLI runs and
returns the documented exit codes, `rubocop` is clean across 17 files, and the
fixture harness is green.

```
CLAUDE.md                  house rules, loaded every turn
PROJECT.md                 this file
ARTIFACTS.md               artifact index and verification ledger
Gemfile, Gemfile.lock      dependencies resolved
.ruby-version              3.3.6
.rubocop.yml               style and metrics
.rspec                     --require spec_helper
Rakefile                   rake verify
.claude/agents/            spec-writer, reviewer, test-runner, Explore, implementer
.claude/settings.json      hooks, agent-teams flag
scripts/protect-tests.sh   PreToolUse hook — specs are spec-writer's
scripts/gate.sh            TaskCompleted hook — no completion on a red suite
scripts/fixtures.rb        fixture harness (0e), plus scripts/fixtures/
exe/biometry               entrypoint, exit codes
lib/biometry/              models, cli, reference_data
data/                      reference constants (see below)
```

Still absent: `spec/`. See "Slice 0" below — one hook stands in the way.

### Reference data, as committed

| file | contents | state |
|---|---|---|
| `data/hadlock.yml` | 4 EFW formulas (1985) + growth standard (1991) | ready |
| `data/intergrowth21.yml` | EFW formula + LMS centile equations (2017) | ready |
| `data/nichd.yml` | manifest (2015) | ready |
| `data/who.yml` | manifest (2017) | ready |
| `data/percentiles/nichd.csv` | 4 groups x 31 weeks x 7 centiles | ready |
| `data/percentiles/who.csv` | 3 sexes x 27 weeks | ready |
| `data/acog_redating.yml` | redating thresholds | **`verified: true`** (2026-08-13) |

Every manifest carries `source`, `known_issues`, and `fixtures`. Two fields are
**not** uniform across them, and code must not assume they are:

- `valid_ga_weeks` is top-level in `intergrowth21.yml`, `nichd.yml` and
  `who.yml`, but nested under `hadlock_1991` in `hadlock.yml`.
- `paired_formula` is stated in `hadlock.yml` (nested), `nichd.yml` and
  `who.yml`. **`intergrowth21.yml` has no such key** — the pairing appears only
  in prose. Slice 4's `:formula_chart_mismatch` check needs it from somewhere.

`data/` also holds `soa_maternal_participants.csv` and
`soa_legend_and_footnotes.csv`. Those are the RSV protocol extraction, are
unrelated to this project, and per ARTIFACTS.md §1 should be moved out.

The fixtures are the transcription check. `bundle exec ruby scripts/fixtures.rb`
runs them; see 0e for what it can and cannot check yet.

---

## Non-negotiable constraints

**Reference data is input, never output.** `data/` is read-only to every agent.
Never derive, interpolate, recall, or infer a clinical constant. If a needed
value is not in `data/`, stop and report. This is the rule most likely to be
silently dropped once a slice gets long; the reviewer checks for it explicitly.

**Unverified data does not load.** Any file under `data/` carrying
`verified: false` raises `Biometry::UnverifiedReferenceData` in the loader. Do
not flip the flag to make a slice run. `data/acog_redating.yml` was the one
file in this state; it was verified on 2026-08-13 and now loads.

**No classification.** The library reports "8th percentile by Hadlock 1991,
11th by INTERGROWTH-21st". It never emits SGA, IUGR, macrosomia, abnormal,
normal, or any threshold-crossing label. Reject any spec asserting on one.

**Provenance is part of every result.** A value that does not name the formula,
the standard, and the inputs that produced it is incomplete. Comparison is
impossible without attribution.

**Dates, not times.** Everything is `Date`. No `Time`, no zones.

---

## The domain, as the sources actually leave it

This section exists because the naive shape — one EFW, four charts, uniform
lookup — is wrong in four separate ways. All of it is verified against the
primary papers; see `ARTIFACTS.md` for the ledger.

### Five EFW formulas, not one

| id | parameters | source |
|---|---|---|
| `hadlock_ac_fl` | AC, FL | Hadlock 1985 Table II |
| `hadlock_bpd_ac_fl` | BPD, AC, FL | Hadlock 1985 Table II |
| `hadlock_hc_ac_fl` | HC, AC, FL | Hadlock 1985 Table II |
| `hadlock_bpd_hc_ac_fl` | BPD, HC, AC, FL | Hadlock 1985 Table II |
| `intergrowth` | AC, HC | Stirnemann 2017 |

INTERGROWTH deliberately excludes femur length: it was tested and not
retained, and the authors argue including it would increase prediction error
because FL has the highest observer variability of the three. A scan carrying
BPD, AC and FL but no HC therefore cannot produce an INTERGROWTH EFW at all.

### Four growth standards, and they are not interchangeable

| standard | access | dispersion | range (wk) | strata | paired formula |
|---|---|---|---|---|---|
| INTERGROWTH-21st | equation | LMS, closed form | 22–40 | none | `intergrowth` |
| Hadlock 1991 | equation | median x 13.3% | 10–40 | none | `hadlock_bpd_hc_ac_fl` |
| NICHD | table | 3 fitted, 4 derived | 15–40 | race/ethnicity | `hadlock_hc_ac_fl` |
| WHO | table | quantile regression | 14–40 | fetal sex | `hadlock_hc_ac_fl` |

Two access methods, three dispersion models, three valid ranges, two
stratification axes. The adapter interface carries all of it. A uniform
"lookup" interface is wrong and should be rejected if proposed.

### Formula and chart are paired

A percentile is only meaningful when the EFW was produced by the formula the
chart was built on. Feeding a Hadlock four-parameter weight into INTERGROWTH's
LMS equations measures the chart difference and the formula difference at once,
with no way to separate them.

An adapter given a mismatched EFW returns
`Failure([:formula_chart_mismatch, { chart:, expected:, given: }])`.

### Prescriptive standards and references mean different things

INTERGROWTH and NICHD are prescriptive: healthy cohorts, describing optimal
growth. WHO is deliberately a reference — complicated pregnancies were
retained, on the stated principle that reference intervals should reflect the
population they will be applied to, and the authors explicitly declined to
exclude neonates below the 10th birthweight centile because it would shift the
lowest percentiles toward "supernormal".

A 10th centile does not mean the same thing across that boundary. The output
labels it rather than implying four comparable numbers.

### Gestational age is expressed differently by each source

| standard | GA convention |
|---|---|
| INTERGROWTH | exact decimal weeks (30+3 -> 30.428571) |
| Hadlock 1991 | decimal weeks to the nearest tenth (39w3d -> 39.4) |
| NICHD, WHO | integer completed weeks |

`GestationalAge` stores total days; conversion happens once, on the type. Three
adapters converting independently is three chances to round differently.

### The magnitude of disagreement

At 32 weeks a 1,600 g fetus is 4th percentile on the NICHD white chart and
13th–14th on the Black and Asian charts. Median EFW spread across the NICHD
groups runs 3.8% at 20 weeks to about 8% at term. The authors report that using
the white-derived standard for everyone misclassifies as much as 15% of
non-white fetuses as growth restricted at the 5th centile.

Around the 10th-percentile line this is routinely the difference between a
growth workup and reassurance for identical biometry. The chart is a stated
input, never a default.

---

## Slice 0 — scaffolding and shared types

**You do this yourself, serially, and commit before any agent runs.** It is
not a spec-writer task: there is nothing to decompose, and the value objects
are decisions rather than derivations.

**Status: done except 0f.** `.ruby-version`, `.rspec`, `.gitignore`,
`exe/biometry`, `lib/biometry/`, and `scripts/fixtures*` are in place;
`rubocop` passes; the repo is now a git repository on `main`.

### 0a. Infrastructure

`.rubocop.yml` and `Rakefile` both exist and work — an earlier draft of this
file said otherwise. `Rakefile` already sets `ENV['COVERAGE_ENFORCE'] = '1'`
inside `verify` only, and `verify` runs `no_stray_output`, `rubocop`, `spec`
and `audit` in that order.

Three adjustments made since:

- `.rubocop.yml` `Naming/MethodParameterName` / `BlockParameterName` now allow
  the biometric terms of art (`ga`, `ac`, `hc`, `fl`, `bpd`, `hl`, `crl`,
  `efw`, `wk`) instead of grid coordinates, and `Naming/VariableNumber` allows
  the centile keys (`p2_5`, `p97_5`) and year-suffixed standards
  (`hadlock_1991`) that come out of `data/`.
- `scripts/gate.sh` uses `set -euo pipefail` and a `mktemp` log rather than a
  fixed `/tmp/gate.log`, which two concurrent agents would have raced on.
- `Gemfile` declares `csv` explicitly. It stops being a default gem in Ruby
  3.4, and the deprecation warning it emitted otherwise polluted stderr on
  every CLI invocation.

`spec/spec_helper.rb` needs SimpleCov with the coverage threshold gated on an
env var, so single-file runs during the red-green loop do not fail on coverage:

```ruby
require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter '/spec/'
  minimum_coverage(line: 95, branch: 90) if ENV['COVERAGE_ENFORCE']
end
```

### 0b. Value objects

Built, in `lib/biometry/models/`. `Measurement::KINDS` and `Provenance::TYPES`
became `Biometry::MEASUREMENT_KINDS` and `Biometry::PROVENANCE_TYPES`: a
constant inside a `Data.define` block is a RuboCop `Lint` offence and does not
scope the way it reads.

```ruby
module Biometry
  # Total days. Never fractional weeks — float weeks produce off-by-one-day
  # errors that survive every test you would think to write.
  GestationalAge = Data.define(:days) do
    def self.from(weeks:, days: 0) = new(days: weeks * 7 + days)
    def weeks = days / 7
    def remainder_days = days % 7
    def exact_weeks = days / 7.0                    # INTERGROWTH
    def tenth_weeks = (days / 0.7).round / 10.0     # Hadlock 1991
    def completed_weeks = days / 7                  # NICHD, WHO
    def to_s = "#{weeks}w#{remainder_days}d"
  end

  Measurement = Data.define(:kind, :mm)   # :bpd, :hc, :ac, :fl, :hl, :crl
  Scan        = Data.define(:date, :measurements)

  Estimate = Data.define(:value, :unit, :method, :inputs, :source) do
    def to_s = "#{value} #{unit} (#{method})"
  end
end
```

`Estimate#source` holds a `Provenance`, added here because it was otherwise
undefined and four adapters would each have invented one:

```ruby
Provenance = Data.define(:standard, :citation, :formula, :type, :stratum)
```

`type` is `:prescriptive` or `:reference`, and `stratum` is the NICHD
race/ethnicity or WHO fetal sex actually used — never inferred, never
defaulted, and printed in slice 5's table.

**One hazard left standing.** `Estimate`'s `:method` member overrides
`Data#method`, and RuboCop flags it (`Lint/DataDefineOverride`, disabled inline
at the definition). It does not degrade gracefully: `estimate.method(:to_s)`
raises `ArgumentError` for wrong arity rather than falling through to
`Object#method`, so anything doing reflection on an `Estimate` — a debugger, a
serialiser, a matcher — fails with an error that points nowhere near the cause.
Use `Estimate.instance_method` instead.

It is kept because it is the contract written above. Renaming it to `:formula`
would remove the hazard, and `spec/models/estimate_spec.rb` is the only spec
that would have to change. After slice 3 puts it in every result, it is a wide
change. Decide before slice 3.

### 0c. Result tags

```ruby
Success(estimate)
Failure([:insufficient_data,       { required: [:ac, :hc], given: [:ac, :fl] }])
Failure([:out_of_range,            { standard:, ga_weeks:, valid_range: }])
Failure([:unsupported_standard,    { requested:, available: }])
Failure([:unsupported_centile,     { standard:, requested:, available: }])
Failure([:formula_chart_mismatch,  { chart:, expected:, given: }])
Failure([:invalid_input,           errors])
```

`:out_of_range` matters more than it looks. Every formula and chart has a GA
window it was derived over, and the windows differ. Silent extrapolation is the
most likely way this library produces a wrong number that looks right.

### 0d. The reference loader

`Biometry::ReferenceData`, in `lib/biometry/reference_data.rb`. It sits in the
shell — not `services/`, not `models/` — and is the only place in the library
that touches the filesystem. Services receive parsed structures as arguments.

Two things the sketch in an earlier draft of this file got wrong:

```ruby
YAML.safe_load_file(path, symbolize_names: true)   # raises on data/who.yml
```

`data/who.yml` writes its correction dates unquoted (`date: 2017-03-24`), which
is legal YAML and loads as a `Date`. `safe_load` rejects any class not on its
permitted list, so this raises `Psych::DisallowedClass` before it can even
check the `verified` flag. `data/` is read-only, so the fix belongs in the
loader: `permitted_classes: [Date]`.

Second, the flag check has to happen after a parse that can itself fail. The
loader raises `MalformedReferenceData` for an unreadable or non-mapping file
and `UnverifiedReferenceData` for `verified: false`; both descend from
`Biometry::Error < StandardError`, so `exe/` maps them to exit 70.

It returns frozen plain Hashes and Arrays rather than typed manifests. The four
manifests do not share a shape (see "Reference data, as committed" above), so a
common type here would be a guess. Each adapter reads the keys it needs.

`load_table` parses the percentile CSVs, coercing numerics and leaving blank
cells as `nil` — WHO's sex-specific tables omit 2.5 and 97.5, and that absence
is data, not a gap. It does **not** filter NICHD's weeks 10–14; that is slice
4's range check, and the harness asserts those 20 rows are still present to be
filtered.

Raise rather than return a Result: this is a developer error, not a runtime
condition, and no caller should branch on it.

### 0e. Fixture harness — run before writing any spec

```
bundle exec ruby scripts/fixtures.rb        # exit 0 green, 1 red
```

`scripts/fixtures.rb` plus `scripts/fixtures/`. It lives outside `spec/` on
purpose: it validates `data/` and the loader together, before any spec exists
to be written against them, and `scripts/protect-tests.sh` reserves `spec/`
for spec-writer.

Current state: **35 passed, 0 failed, 8 pending.**

The 8 pending are every fixture backed by an equation — the four in
`hadlock.yml` and the four in `intergrowth21.yml`. Nothing evaluates them until
slices 3 and 4 exist. They are printed as PENDING by name rather than skipped,
so the pass count cannot be mistaken for full coverage.

What is checked now is everything backed by a table, which needs only the CSV:

- all five manifests load through the real loader, and `valid_ga_weeks` /
  `paired_formula` are where each one actually puts them
- NICHD 32-week and 39-week p5/p50/p95 for all four groups, `nichd.yml` against
  `percentiles/nichd.csv` — two independent hand transcriptions of Buck Louis
  Table 2 agreeing
- NICHD and WHO table integrity: centiles ordered across every row, every
  centile column increasing with GA, female median below male at every week
- WHO combined p10/p90 at 20/28/36 weeks, the 84 g sex gap at 37 weeks, and
  p2.5/p50/p97.5 at 40 weeks
- WHO sex-specific tables really are missing p2.5 and p97.5, which is what
  makes `:unsupported_centile` a real path in slice 4
- NICHD weeks 10–14 are still in the CSV for slice 4's loader to reject

**One finding worth recording.** `nichd.yml`'s integrity fixture asserts
"centiles increase left to right in every row". Strictly read, that is false:
`white@10w`, `black@10w` and `hispanic@11w` print equal adjacent centiles
(`white,10,23,23,25,...`). This is rounding, not a transcription error — Table 2
prints whole grams and the median below 12 weeks is under 60 g, so p3 and p5
land on the same integer. All three ties are inside weeks 10–14, which slice 4
rejects anyway. The harness therefore asserts the stronger pair: non-decreasing
across the whole table, strictly increasing within the fitted range 15–40.

### 0f. Not done — `spec/`

`spec/spec_helper.rb` and the slice 0 specs do not exist.
`scripts/protect-tests.sh` blocks every non-spec-writer agent from writing anything matching
`(^|/)(spec|tests?)/`, and this section assigns slice 0 to the main agent
working serially. The two rules contradict each other and the hook wins.

`rake verify` cannot pass until this is resolved: `rspec` has nothing to run,
and `COVERAGE_ENFORCE` would fail the coverage floor on an empty suite.

Pick one:

1. Run the slice 0 spec work with `ALLOW_TEST_EDITS=1`, which the hook honours.
2. Narrow the hook so `spec/spec_helper.rb` and other harness files are not
   spec-writer's, only `*_spec.rb` is.
3. Hand slice 0's specs to spec-writer after all, accepting that it writes
   specs for value objects it did not design.

Then write: `spec/spec_helper.rb` per 0a, plus
specs for `GestationalAge` boundary arithmetic (13w6d + 1 day, the three GA
conventions), `ReferenceData` (the `Date` case, the `verified: false` raise,
blank CSV cells), and `exe/biometry` exit codes 0 and 2.

---

## Slice 1 — gestational age and EDD

**Owns:** `lib/biometry/services/dating/`
**Reads:** nothing from `data/`. Pure arithmetic.

Given any of the following, produce a GA at a reference date and an EDD:

- **LMP** with configurable cycle length. Naegele assumes 28 days; a 35-day
  cycle shifts the EDD by a week, and that correction is common in practice.
- **CRL** at a known scan date. Valid to roughly 14 weeks; beyond that,
  `:out_of_range`, not a silently extrapolated number.
- **Biometry** at a known scan date.
- **Conception or embryo transfer date.** Required for the REI case and the
  highest-confidence source. Its own derivation, not a special case of LMP.

**Return every derivation the inputs support, not a winner.** LMP, CRL and
biometry genuinely disagree, and that disagreement is the same species as the
four growth charts. The caller decides which is established.

**The IVF convention.** GA is conventionally counted as if from an LMP two
weeks before conception, so a day-5 blastocyst transfer starts at 2w5d rather
than day zero. Get this wrong and every downstream number is off by about two
weeks — large enough that a clinician spots it immediately, small enough that
no unit test you would think to write catches it.

Write specs for GA arithmetic boundaries explicitly. "13w6d plus one day" is
where off-by-one bugs live.

---

## Slice 2 — redating policy

**Owns:** `lib/biometry/services/dating/redating.rb`
**Reads:** `data/acog_redating.yml`

> **Unblocked as of 2026-08-13.** Every band, the discretionary zone,
> `band_indexed_on` and the three clinical rules are flagged verified, and the
> loader accepts the file.
>
> Two things are still open in it, and neither blocks the decision logic:
> `source.guideline_currency.checked` is `false` — a committee opinion can be
> reaffirmed, revised or withdrawn, and CO 700's current status has not been
> confirmed — and `fixtures:` is still `[]`, so slice 2 must write its own.
>
> Unlike every other constant here, these thresholds have no independent check:
> no computation regenerates them, no second source in `data/` quotes them. A
> wrong threshold produces a passing suite and a wrong clinical answer, so the
> fixtures slice 2 writes are the only guard there is.

Given an established EDD and a new ultrasound-derived EDD, decide whether the
established date should be revised. The threshold widens with gestational age,
because ultrasound dating accuracy degrades as pregnancy advances.

**Band selection is not a comparison.** Unlike the growth charts, ACOG has one
correct reading; `band_indexed_on` in the data file records which GA selects
the band, and it is itself unverified. Do not display both readings as
alternatives — that presents an implementation gap as a clinical disagreement.
EDD is upstream of every percentile in slice 4; carrying two candidate EDDs
forward doubles the comparison table with no basis for the reader to choose.

Two caveats that must survive into output, because they are the clinically
load-bearing part:

- The 22w0d–27w6d band has a **discretionary zone** where the guideline
  defers to judgment. Report the zone rather than a bare yes or no.
- Third-trimester dating carries the widest error, and redating a small fetus
  risks masking growth restriction. Surface this whenever that band applies.

Two rules that are clinical rather than arithmetic:

1. A pregnancy dated by IVF is never redated by ultrasound.
2. An established EDD is not mutated. Subsequent scans are measured against
   it; the service returns a recommendation with reasoning.

Return a decision object: `redate?`, discrepancy in days, the threshold that
applied, the band, and any caveat attaching to that band. Also report boundary
sensitivity when the indexing GA sits within a few days of a band edge and the
answer would flip on the other side.

---

## Slice 3 — estimated fetal weight

**Owns:** `lib/biometry/services/weight/`
**Reads:** `data/hadlock.yml`, `data/intergrowth21.yml`

Given a `Scan`, compute EFW by every formula the available measurements
support, and return all of them. Selecting one is the caller's job.

Missing a required parameter is `Failure([:insufficient_data, ...])` naming
what was missing — not a skipped formula, not a substituted value.

Fixtures already in the manifests:

- INTERGROWTH: AC 26 cm, HC 29 cm -> log(EFW) 7.312292, EFW 1499 g
- Hadlock `hc_ac_fl`: the microcephalic case from the 1985 discussion
  (BPD 5.7, HC 21.3, AC 28.5, FL 7.5 cm) -> 2415 g against an actual birth
  weight of 2250 g, a 7.3% error. The paper reports a BPD+AC model missing the
  same fetus by 46.8%, making this a regression test for formula selection
  rather than just arithmetic.

**Report error by stratum, not pooled.** Hadlock 1985 Table I gives mean
deviation and SD by birth-weight band, and the errors are asymmetric: the
recommended formula runs about 4.6% low below 1500 g and 6.3% high above
4000 g. Since the point of this tool is the tails, the pooled 7.5% SD
understates uncertainty in exactly the cases that matter.

---

## Slice 4 — growth percentiles

**Owns:** `lib/biometry/services/growth/` — one file per standard
**Reads:** all four manifests plus `data/percentiles/*.csv`

Given an EFW, a GA, and optionally a stratum, return the percentile under each
available standard.

**Pin these before spec-writer runs**, or four adapters will decide them four
different ways:

1. **Interpolation between weeks** — undefined in every source. One rule,
   applied identically across both table-based adapters.
2. **Interpolation between centiles** — same. WHO's distribution is
   deliberately asymmetric (Bowley coefficient -0.016 at 15 weeks to +0.111 at
   40), so linear interpolation is a worse approximation there than for the
   log-normal standards.
3. **Out of range** — differs per standard. `:out_of_range` naming the standard
   and its window. Never extrapolate.
4. **NICHD weeks 10–14** — present in the CSV, outside the fitted range. The
   loader filters them; the CSV keeps them so it can be diffed against the
   published table.
5. **Missing stratum** — WHO has a combined table. NICHD has none. Decide what
   NICHD returns when race/ethnicity is not supplied.
6. **Unavailable centile** — WHO's sex-specific tables omit 2.5 and 97.5.
   Fall back to combined and say so, or return `:unsupported_centile`. Do not
   interpolate them.

**This is the slice worth a parallel fan-out**, and `implementer.md` with
`isolation: worktree` already exists for it. Four files, one shared interface,
no shared logic — and the seam defects (four interpolation decisions, four
error shapes, four range-check styles) are what the reviewer exists to catch.
Commit the shared interface and the interpolation rule before forking.

NICHD's stratification is **self-reported** race/ethnicity, collected by
interview. Optional, nullable, user-supplied. Never inferred, never defaulted,
always named in the output.

---

## Slice 5 — comparison and presentation

**Owns:** `lib/biometry/presentation/`

```
Dating
  LMP (28d cycle)          EDD 2026-07-14      GA 32w1d
  CRL 8w2d, 2026-01-14     EDD 2026-07-11      GA 32w4d   [established]
  Biometry, 2026-06-02     EDD 2026-07-19      GA 31w3d

Growth      GA 32w4d       AC 27.4  HC 29.1  FL 6.2  BPD 8.2 cm

  INTERGROWTH-21st   EFW 2,180 g  (AC+HC)         11th   prescriptive
  Hadlock 1991       EFW 2,240 g  (BPD+HC+AC+FL)   8th   reference
  WHO (female)       EFW 2,215 g  (HC+AC+FL)      10th   reference
  NICHD (white)      EFW 2,215 g  (HC+AC+FL)       9th   prescriptive

  Sources: Stirnemann 2017; Hadlock 1985/1991; Kiserud 2017; Buck Louis 2015
```

Three distinct EFW values, not one — the formulas differ per chart. Every row
names its formula, its stratum, and its type. No percentile is printed without
its standard. No label is printed at all.

Per the CLI contract in `CLAUDE.md`: stdout, `--json` undecorated, colour and
alignment only when `$stdout.tty?`.

---

## Slice 6 — HL7 ORU^R01 ingestion

**Owns:** `lib/biometry/hl7/`

Deliberately last. It is the imperative shell, and no clinical logic depends
on it.

Parse an ORU^R01 message into `Scan` objects. First-pass scope:

- MSH-2 encoding characters read from the message, not hardcoded
- OBR/OBX grouping preserved
- OBX-3 identifier mapped to measurement kind via a LOINC lookup
- OBX-5 value and OBX-6 units, converted to mm
- Unknown OBX identifiers collected and reported, never dropped silently
- Malformed segments reported with segment index and field position; parsing
  continues rather than aborting

Spec this case explicitly: many OB ultrasound systems ship the entire report
as one narrative text OBX rather than discrete observations. Return
`Failure([:insufficient_data, ...])` naming that case rather than attempting to
scrape numbers out of prose.

---

## Sequence

```
0. scaffolding + shared types + loader     built except spec/ — see 0f
1. gestational age                         ready
2. redating                                ready; acog_redating.yml verified 2026-08-13
3. EFW                                     ready; independent of 1 and 2
4. percentiles                             depends on 3; parallel fan-out candidate
5. presentation                            depends on 1, 3 and 4
6. HL7                                     independent; do last
```

Finish 0f and commit before any agent runs, then start with 3. It is
unblocked, it exercises the `data/` loading path everything downstream depends
on, and its fixtures are already written — it is also what turns the 8 pending
entries in the harness green.

Two decisions to make before slice 4 forks, both recorded above rather than
left to four adapters: where INTERGROWTH's paired formula comes from, given
`intergrowth21.yml` does not state one, and whether `Estimate`'s `:method`
member gets renamed.