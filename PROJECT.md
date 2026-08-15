# biometry — project specification

A Ruby library and CLI that computes estimated fetal weight and growth
percentiles across the competing international standards, and shows where they
disagree.

Every published calculator gives you a number from one standard. The
disagreement between standards is this tool's output, not a caveat on it.

---

## Where the repo stands

**Slice 0 is done.** The library loads, the CLI runs and returns the documented
exit codes, `rake verify` is green — 93 examples, 0 failures, 100% line and
branch coverage, `rubocop` clean across 27 files, no CVEs — and the fixture
harness passes.

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
.claude/settings.json      hook registration
scripts/protect-tests.sh   PreToolUse hook — specs are spec-writer's
scripts/gate.sh            TaskCompleted hook — no completion on a red suite
scripts/fixtures.rb        fixture harness (0e), plus scripts/fixtures/
exe/biometry               entrypoint, exit codes
lib/biometry/              models, cli, reference_data
data/                      reference constants (see below)
```

`spec/` is written and owned by spec-writer. See 0f for how it gets written.

### Reference data, as committed

| file | kind | contents |
|---|---|---|
| `data/hadlock_1985.yml` | formulas | 4 EFW regressions, Table II |
| `data/hadlock_1991.yml` | chart | median + dispersion equations |
| `data/intergrowth21.yml` | chart + formula | EFW formula and LMS centile equations |
| `data/nichd.yml` | chart | manifest for `percentiles/nichd.csv` |
| `data/who.yml` | chart | manifest for `percentiles/who.csv` |
| `data/percentiles/nichd.csv` | table | 4 groups x 31 weeks x 7 centiles |
| `data/percentiles/who.csv` | table | 3 sexes x 27 weeks |
| `data/acog_redating.yml` | thresholds | redating bands, `verified: true` |

**The four chart manifests share a schema**, and the fixture harness holds them
to it: `source.access` (`equation` or `table`), `paired_formula`,
`valid_ga_weeks`, a `stratification` block with a `field` key, `centiles`, and
`known_issues`. `hadlock_1985.yml` publishes formulas rather than a chart and
`acog_redating.yml` is neither, so both sit outside that schema.

**Formula ids are global.** A chart's `paired_formula` names an id published in
some other file — `hadlock_bpd_hc_ac_fl` and `hadlock_hc_ac_fl` in
`hadlock_1985.yml`, `intergrowth` in `intergrowth21.yml`'s own `efw` block. The
harness checks that every pairing resolves, which is how a split or a rename
gets caught.

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

**Status: done and committed.** `.ruby-version`, `.rspec`, `.gitignore`,
`exe/biometry`, `lib/biometry/`, `spec/` and `scripts/fixtures*` are in place;
`rake verify` passes; the repo is a git repository on `main`.

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

  Estimate = Data.define(:value, :unit, :formula, :inputs, :source) do
    def to_s = "#{value} #{unit} (#{formula})"
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

**The member is `:formula`, not `:method`.** The sketch above said `:method`;
that was wrong. `Data.define(:method)` generates a reader that overrides
`Object#method`, and it does not degrade gracefully — `estimate.method(:to_s)`
raised `ArgumentError` for wrong arity rather than falling through, so anything
doing reflection on an `Estimate` (a debugger, a serialiser, an RSpec matcher)
failed with an error pointing nowhere near the cause. Renamed on 2026-08-13,
before slice 3 could spread it further.

`spec/biometry/estimate_spec.rb` keeps a `#method` example as a regression test
against reintroducing any member that shadows `Object#method`.

Note `Provenance` also carries a `formula`, so `estimate.formula` and
`estimate.source.formula` now hold the same value. That redundancy is real and
undecided; slice 5 is the natural place to collapse it.

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

Current state: **53 passed, 0 failed, 6 pending.**

The 6 pending are the growth-standard fixtures — three in `hadlock_1991.yml`
and three in `intergrowth21.yml` — which slice 4 evaluates. They are printed as
PENDING by name rather than skipped, so the pass count cannot be mistaken for
full coverage.

It also holds the four chart manifests to their shared schema and checks that
every `paired_formula` resolves to a formula some file publishes. That
cross-file check is what catches a split or a rename going wrong silently.

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

### 0f. `spec/` — spec-writer's, and only reachable that way

10 files, 93 examples, 100% line and branch coverage. Written by spec-writer,
which is the only agent that can write them.

`scripts/protect-tests.sh` blocks writes to anything matching
`(^|/)(spec|tests?)/|_spec\.rb|_test\.rb` unless the PreToolUse payload carries
`agent_type == "spec-writer"`, or `ALLOW_TEST_EDITS` is set in the hook
process's environment. **This works for a Task-spawned subagent and does not
work for a named teammate**, which is worth knowing before you reach for one:

| caller | `agent_type` in payload | write to `spec/` |
|---|---|---|
| main agent | absent, defaults to `main` | blocked |
| subagent, `subagent_type: spec-writer` | `spec-writer` | allowed |
| subagent, any other type | that type | blocked |
| named teammate | absent | blocked, whatever its role |

Verified by probe, both arms, with the env clean. The named-teammate row is why
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is no longer set in
`.claude/settings.json`: with agent teams on, delegating to spec-writer as a
teammate produces a spec-writer that cannot write specs.

Two traps if you ever do need `ALLOW_TEST_EDITS`:

- Adding it to `settings.json` takes effect mid-session; **removing it does
  not**. The variable stays live in the running process until restart, so the
  guard reads as restored while it is still off. Check with
  `printenv ALLOW_TEST_EDITS` rather than reading the file.
- While it is set, every agent is exempt, including subagents that inherit the
  session environment. It is not a spec-writer override, it is an off switch.

Do not narrow the `SPEC` pattern to `_spec\.rb` alone as a workaround. The block
is keyed on caller identity, not on which part of the pattern matched, so that
would open `spec_helper.rb` and still refuse every `*_spec.rb`.

---

## Slice 1 — gestational age and EDD

**Owns:** `lib/biometry/services/dating/`
**Reads:** nothing from `data/` — but only because half this slice is deferred.
See "Scope" below.

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

### Pinned before spec-writer — decided 2026-08-13

**Scope: LMP and transfer only. CRL and biometry are deferred.**

The claim that this slice reads nothing from `data/` holds for two of its four
inputs. LMP and conception/transfer are arithmetic. CRL and biometry dating
each need a published regression, and `data/` has none — the only CRL mentions
anywhere are ACOG's band labels and a line of WHO prose.

That is not a transcription gap but a clinical choice: Robinson–Fleming 1975,
Hadlock 1992 and INTERGROWTH (Papageorghiou 2014) give materially different
GAs from the same CRL, and ACOG's redating bands assume one of them. Picking
one is the owner's decision, not an implementer's.

Until then, CRL and biometry are **offered and refused**, never silently
absent: `Failure([:unsupported_standard, { requested:, available: }])`. A
missing derivation must read as "this library cannot do that yet", not as
"your inputs did not support it".

**Conventions are not clinical constants.** Two numbers live in code:

- 280 days from LMP to EDD
- 14 days added to conception age to give menstrual age

Both are definitional rather than measured. Gestational age *is* menstrual age
by definition, and the 40-week due date *is* the definition of an EDD, not a
regression fitted to a cohort. Neither is a value transcribed from a paper, so
neither belongs in `data/`. Every number that came out of a study still does.

**Cycle-length correction.** `EDD = LMP + 280 + (cycle_length - 28)`. Naegele
assumes 28 days; a 35-day cycle moves the EDD a week later, and that correction
is common enough in practice to be the default behaviour rather than an option.

**The IVF convention.** GA at transfer = 14 days + the embryo's age at
transfer, so a day-5 blastocyst is 2w5d on transfer day and a day-3 cleavage
embryo is 2w3d. The embryo day is a required input, not a default — guessing it
is a two-week error in either direction.

**Return shape mirrors slice 3.** One service per derivation, plus an
aggregate returning `Success(Hash{derivation => Result})`. The aggregate always
succeeds; the per-derivation Results are the report. There is no winner: LMP
and transfer genuinely disagree, and that disagreement is the same species as
the four growth charts.

**Guard precedence.** Same rule as the growth adapters, minus the steps this
slice has no analogue for: availability (is this derivation implemented at
all), then input validity, then range. Pin it with the same shared-example
approach — the slice 4 defect was a guard reordered to satisfy a metrics cop,
with nothing asserting the order.

**The member is `:derivation`, never `:method`.** `Data.define(:method)`
shadows `Object#method`; `Estimate` and `Percentile` both carry a regression
test against reintroducing it.

---

## Slice 2 — redating policy

**Owns:** `lib/biometry/services/dating/redating.rb`
**Reads:** `data/acog_redating.yml`

> **Unblocked as of 2026-08-13.** Every band, the discretionary zone,
> `band_indexed_on` and the three clinical rules are flagged verified, and the
> loader accepts the file.
>
> `source.guideline_currency.checked` is now `true`. `fixtures:` is still `[]`,
> deliberately: worked examples belong there only once transcribed from CO 700.
>
> Unlike every other constant here, these thresholds have no independent check:
> no computation regenerates them, no second source in `data/` quotes them. A
> wrong threshold produces a passing suite and a wrong clinical answer, so the
> guards slice 2 writes are the only protection those numbers have.
>
> **Measured, not assumed.** Every numeric leaf in the manifest was mutated one
> at a time — 88 mutations across 30 fields, covering digit reversal, an
> appended zero, an order of magnitude and ±1. **82 are caught.** Every
> transposition-class mutation in every field is caught. The six survivors are
> all single-step ±1 on four `threshold_days` and the zone's lower bound, and
> they are unguardable from inside the file: only a transcription from CO 700
> Table 1 closes them.
>
> One genuine second mention exists and is now load-bearing:
> `caveats.third_trimester.text` says the third-trimester error is "+/-21 to 30
> days", and `biometry_28_plus.threshold_days` is 21. That cross-reference alone
> closes three mutations. `rules.boundary_sensitivity` gained `within_days: 3`
> for the same reason — the number was stated only in prose, and regexing a
> constant out of a sentence is fragile in a way nothing else here is.
>
> The `crl_early`/`crl_late` edge at 8w6d/9w0d is the one band boundary held
> only by contiguity, because neither id names its weeks.

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

Return a decision object: the recommendation, discrepancy in days, the
threshold that applied, the band, and any caveat attaching to that band. Also
report boundary sensitivity when the indexing GA sits within a few days of a
band edge and the answer would flip on the other side.

### Pinned before spec-writer — decided 2026-08-13

**The recommendation is tri-state**, not a boolean: `:redate`, `:keep` or
`:discretionary`. A boolean cannot carry the zone, and `if decision.redate?`
would silently discard exactly the case the guideline most wants a human to
look at.

**The discretionary zone changes the answer**, it does not annotate it. In
`biometry_22_27` the zone is 10–14 days and `threshold_days` is also 14, so:

```
discrepancy <  from_days (10)          -> :keep
from_days <= discrepancy <= to_days    -> :discretionary
discrepancy >  threshold_days (14)     -> :redate
```

Without the zone a 12-day discrepancy reads `:keep` on the bare threshold. That
is the window the zone exists for.

**`threshold_days` is exclusive** everywhere: redate when the discrepancy is
strictly greater. Discrepancy is `|proposed EDD − established EDD|` in whole
days.

**The band is indexed on the established GA**, per `band_indexed_on` in the
manifest — not on the ultrasound estimate, and not on whatever `--ga` the
caller typed for the growth charts. Derive it from the established EDD and the
reference date rather than accepting it separately, so the two cannot disagree:

```
indexing GA in days = 280 - (established EDD - reference date)
```

**IVF short-circuits before any band is selected.** A pregnancy dated by
transfer, retrieval or a known conception date is never redated by ultrasound,
so the decision is `:keep` with the rule named and no band, no threshold and no
zone — those fields are absent rather than filled in with values that played no
part.

**Guard precedence**, as everywhere: input validity, then the IVF rule, then
band selection. The rule outranks the band because a band's threshold is an
answer to a question IVF dating never asks.

**Boundary sensitivity** is reported when the indexing GA is within 3 days of a
band edge *and* the recommendation would differ in the adjacent band. Both
conditions, per `rules.boundary_sensitivity` — proximity alone is not a finding.

**The established EDD is never mutated.** The service returns a recommendation
with reasoning; nothing writes a date back.

### The no-classification rule, narrowed

`caveats.third_trimester` reads "risks masking growth restriction", and slice
5's report is asserted to contain no `/restrict\w*/i` anywhere on the page. Two
rules of this project collided.

**The prohibition is on classifying the pregnancy in front of you** — emitting
SGA, IUGR, macrosomia, restricted or normal as a verdict on this fetus, in a
value or in a row. A caveat quoted from the guideline, warning what redating
*risks*, labels nobody. It prints verbatim.

Slice 5's page-wide assertion narrows to the rows and values. The caveat block
is exempt because it is quoted source text, not a finding this library
produced. `CLAUDE.md` still states the rule in its absolute form and should be
brought into line.

### Wired into the report command

    biometry report --ga 32w0d --established-edd 2026-10-08 \
                    --established-by lmp --scan-edd 2026-10-20

`--established-by` names how the established date was arrived at, and is what
triggers the IVF rule; `transfer` is the IVF case. The Redating section prints
the recommendation, the discrepancy against its threshold, the band, and any
zone, caveat or boundary sensitivity that applies.

---

## Slice 3 — estimated fetal weight

**Owns:** `lib/biometry/services/weight/`
**Reads:** `data/hadlock_1985.yml`, `data/intergrowth21.yml`

Given a `Scan`, compute EFW by every formula the available measurements
support, and return all of them. Selecting one is the caller's job.

Missing a required parameter is `Failure([:insufficient_data, ...])` naming
what was missing — not a skipped formula, not a substituted value.

**Status: done.** `Equation`, `Hadlock`, `Intergrowth`, `AllFormulas`. Five
formulas are offered: the four Hadlock 1985 regressions and `intergrowth`.

### Coefficients are parsed, not transcribed

`data/hadlock_1985.yml` publishes no `coefficients:` block. The numbers exist only
inside the `equation:` strings, so `Equation` parses them; retyping one into
Ruby would be supplying a clinical constant from outside `data/`.

The grammar is closed — a sum of signed terms, each a number optionally
multiplied by named variables — and refuses anything else rather than
understanding part of it. That refusal is load-bearing: INTERGROWTH's equation
has parentheses, a cube and a natural log, and a lenient parser would turn it
into a plausible wrong number. INTERGROWTH is built from its `coefficients:`
block instead, with the functional form in code.

### The loader prunes; services have no verified check

`ReferenceData.load_manifest` returns `[data, dropped]`. A file whose
*top-level* `verified` is false still raises. An entry *within* a file that is
marked unverified is pruned, so it never reaches a service:

```ruby
data, dropped = ReferenceData.load_manifest(path)
# dropped => [[:efw_formulas, :some_unverified_row]]
```

**Nothing under `data/` is currently unverified**, so pruning is a no-op
against real data and the specs pin it with tmpdir fixtures instead. The
real-data spec asserts the invariant — every manifest loads with an empty
`dropped` — which fails loudly the day a row is marked unverified. That is the
signal worth having.

That collapses "unverified" into "absent", which every adapter already handles
via its missing-entry path. The rejected alternative was a guard inside each
service — that leaves every future adapter with an obligation to remember,
which is precisely the seam defect a four-adapter slice exists to produce.
**Slice 4 therefore inherits nothing here.** Its adapters need no verified
check.

`dropped` exists so a caller can say what is unavailable and why; pruning
silently would be worse than the guard was. `exe/` should print something like
"1 formula unavailable pending verification" once a command loads a manifest —
no command does yet, so the wiring lands with the first one. The fixture
harness already reports it.

Arrays are walked too: `acog_redating.yml`'s `bands:` is a list, and slice 2
must not receive an unverified band any more than slice 3 may receive an
unverified formula.

### Hadlock has no numeric anchor

`hadlock_1985.yml` carries `fixtures: []`. Its withdrawn fixture claimed
2415 g from inputs that yield 1951.6 g under `hadlock_hc_ac_fl`, and no formula
in the file produces 2415 g from them — see `known_issues`
`microcephalic_fixture_withdrawn`.

**Consequence, and it is the largest open risk in the library.** The four
Hadlock formulas are pinned only by the parser's grammar specs and by the
property that the adapter evaluates the manifest string over centimetres and
exponentiates base 10. A mis-transcribed coefficient would pass the entire
suite. INTERGROWTH's worked example — AC 26 cm, HC 29 cm -> 1499 g within 1 g —
is the only end-to-end numeric anchor anywhere in this library.

Transcribing one worked example per Hadlock formula from the 1985 paper would
close it.

### Uncertainty

`Estimate#uncertainty` carries `Uncertainty(sd_pct:, basis:)`, sourced from the
manifest row's `sd_pct`. `basis` is always `:pooled`: Table I's per-stratum
figures are not transcribed, so `:stratified` is unreachable and must not be
faked. `hadlock_1985.yml`'s `accuracy_strata_not_transcribed` records this.

That matters because Hadlock's errors are asymmetric — about 4.6% low below
1500 g, 6.3% high above 4000 g — so a pooled SD understates uncertainty in
exactly the tails this tool is aimed at. Transcribing Table I is what changes
`basis`.

**INTERGROWTH's `uncertainty` is `nil`, deliberately.** Its `accuracy:` block
publishes a mean absolute prediction error of 7.6% and a coverage interval;
neither is a standard deviation, and reporting either as one would attribute a
figure to the paper it never gave. If that accuracy should reach a reader, it
needs its own type rather than a coerced `sd_pct`.

---

## Slice 4 — growth percentiles

**Owns:** `lib/biometry/services/growth/` — one file per standard
**Reads:** all four manifests plus `data/percentiles/*.csv`

Given an EFW, a GA, and optionally a stratum, return the percentile under each
available standard.

### Pinned before forking — decided 2026-08-13

These are settled. An adapter does not get to answer them again.

**1. No interpolation between weeks.** Both table standards publish per
completed week and both declare `ga_units: completed_weeks`, so read the row
for `GestationalAge#completed_weeks`. Interpolating would synthesise a row the
source never published. The two equation standards evaluate at their own GA
convention — `exact_weeks` for INTERGROWTH, `tenth_weeks` for Hadlock 1991 —
which is why `GestationalAge` carries all three. Output names the week used.

**2. Linear in weight between centiles.** Converting an EFW to a percentile
against a table means interpolating between the bracketing columns; do it
linearly on weight, identically in both table adapters, and state the method in
output. WHO's distribution is deliberately asymmetric (Bowley coefficient
-0.016 at 15 weeks to +0.111 at 40), so this is a worse approximation there
than for the log-normal standards — say so rather than hiding it.

**Outside the published centiles, do not extrapolate.** An EFW below the lowest
or above the highest published column reports the open bracket — "below the
3rd", "above the 97th" — because a table cannot answer further out. Equation
standards compute any centile in closed form and have no such limit.

**3. Out of range** — per standard. `:out_of_range` naming the standard and its
window. Never extrapolate.

**4. NICHD weeks 10–14** — present in the CSV, outside the fitted range. The
adapter rejects them with `:out_of_range`; the CSV keeps them so it can be
diffed against the published table.

**5. NICHD with no stratum returns all four charts.** It publishes no combined
table, and race/ethnicity is never inferred or defaulted — so the honest answer
to an unspecified stratum is the spread itself. That spread is the paper's own
headline finding: applying the white-derived standard to everyone misclassifies
as much as 15% of non-white fetuses as growth restricted at the 5th centile.
This makes NICHD the one adapter that returns several rows from one call. Every
row names its chart.

**6. WHO 2.5th and 97.5th with a sex supplied returns
`:unsupported_centile`** naming the standard, the request and what is
available. Tables 14 and 15 genuinely omit those columns, and answering from
the combined table would put two populations in one row. Do not interpolate
them.

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

### Pinned before spec-writer — decided 2026-08-13

**The mock above is stale.** It predates slices 1, 3 and 4 and is wrong in four
ways: CRL and biometry dating are deferred, there is no `[established]`
concept until slice 2, unstratified NICHD returns four charts rather than one,
and `Estimate#uncertainty` did not exist when it was drawn. Corrected shape:

```
Dating
  LMP (28d cycle)     EDD 2026-10-08   32w0d
  Transfer (day 5)    EDD 2026-10-05   32w3d
  CRL                 unavailable — no dating standard in data/
  Biometry            unavailable — no dating standard in data/

Growth    GA 32w0d    AC 27.4  HC 29.1  FL 6.2  BPD 8.2 cm

  INTERGROWTH-21st  1,697 g    —      40th  prescriptive  (AC+HC)
  Hadlock 1991      1,852 g  ±7.4%    35th  reference     (BPD+HC+AC+FL)
  WHO (female)      1,834 g  ±7.5%    45th  reference     (HC+AC+FL)
  NICHD (white)     1,834 g  ±7.5%    32nd  prescriptive  (HC+AC+FL)
  NICHD (black)     1,834 g  ±7.5%    44th  prescriptive  (HC+AC+FL)
  NICHD (hispanic)  1,834 g  ±7.5%    39th  prescriptive  (HC+AC+FL)
  NICHD (asian)     1,834 g  ±7.5%    46th  prescriptive  (HC+AC+FL)

  SD is pooled; per-stratum figures are not transcribed.
  Sources: <the full citation of every distinct provenance the rows touched>
```

Numbers above are illustrative of the *shape*, not transcribed: the specs
build their inputs from the real services against the real manifests, so the
rendered values are whatever the library actually produces.

**`DatingEstimate` carries the derivation's parameters**, added 2026-08-13:
`{ cycle_length: 28 }` or `{ embryo_day: 5 }`. A 35-day cycle moves the EDD by
a week, so a due date printed without the assumption behind it is not a report
— the same reason the model already carries `reference_date`. The row renders
`LMP (28d cycle)` rather than making a reader reconstruct it from their own
input.

**The parameter set is the formula column.** "Every row names its formula"
above means the row shows which measurements produced its weight —
`(HC+AC+FL)` — which is what `Estimate#inputs` exists for and what makes three
distinct EFW values legible as three rather than as an unexplained
disagreement.

**NICHD prints all four charts whenever no stratum is supplied.** The spread is
the paper's headline finding and the reason this tool exists; hiding it behind
a flag would make the default output understate the disagreement. Supply a
stratum and it is one row like any other standard.

**Uncertainty prints per row.** Otherwise the member reaches no caller and the
slice 3 work is inert. INTERGROWTH renders `—`: its 7.6% is a mean absolute
prediction error, not an SD, and printing it in an SD column would attribute a
figure to the paper it never gave. A footnote states that every SD shown is
pooled, because pooled understates error in the tails, which is where this tool
gets read.

**Refusals print.** Slice 1 refuses CRL and biometry rather than omitting them
so a reader can tell "this library cannot do that yet" from "your inputs did
not support it"; a silently short table throws that away and looks complete
when it is not. The same applies to a growth row that fails — a
`:formula_chart_mismatch` is printed as such, never dropped.

**Presentation returns strings; it does not write them.** `exe/` and `cli/` own
the streams. That keeps colour and alignment decisions testable without
capturing stdout, and TTY-ness arrives as an argument rather than being sniffed
from a global.

**Business logic stays out.** `presentation/` renders values it is handed —
`DatingEstimate`, `Estimate`, `Percentile`, and the Failures beside them. It
computes no weight, reads no manifest and calls no service. `cli/` composes.

**Text rounds, JSON does not.** The table prints a percentile as a whole-number
ordinal (`4.3` → `4th`); `--json` carries the unrounded value. A reader
comparing standards does not need a decimal place, and a program consuming the
output must not be handed one that was thrown away. An open bracket renders as
`below 3rd` / `above 97th` rather than as a number it is not.

**Slice 5 includes the CLI command that calls it.** Otherwise presentation has
no caller and the `--json` and TTY halves of the CLI contract cannot be
asserted end to end. `exe/biometry` currently exits 2 for every subcommand.

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

### Pinned before spec-writer — decided 2026-08-14

**The LOINC mapping is injected, and `data/` does not yet hold one.** OBX-3
identifiers must map to measurement kinds, and no such mapping is transcribed.
A transposed code maps HC onto AC silently and produces a plausible wrong
weight, which is the exact failure the never-recall rule exists to prevent, so
none is supplied from memory.

The parser therefore takes the mapping as an argument, as every service takes
its manifest. Specs supply their own, so nothing is asserted against a code
nobody sourced. `data/loinc.yml` is a transcription for later.

**Until that file exists, `--hl7` refuses.** A message that parses cleanly but
yields no measurements, because nothing could be recognised, must not render as
a report with an empty growth table — that reads as a fetus with no biometry
rather than as a library missing a lookup. The refusal names what is missing.

**The parser takes message contents, never a path.** Reading the file is
`cli/`'s job, as everywhere.

**Timestamps truncate to dates, at this boundary and only here.** HL7 carries
`YYYYMMDDHHMMSS` and this library has no times and no zones. Slice 1 refuses a
`DateTime` rather than truncating it, because there the caller chose to pass
one; here the format is the source's and truncation is the conversion the shell
exists to perform. It happens once, on the way in.

**One `Scan` per OBR.** OBX segments belong to the OBR they follow, and that
grouping is what distinguishes two scans in one message from one scan with
twice the observations.

**The result carries its diagnostics.** Unrecognised identifiers and malformed
segments are collected and returned alongside the scans, never dropped and
never raised:

```ruby
Hl7::Ingest = Data.define(:scans, :unrecognised, :malformed)
```

A malformed segment names its index and the field position that failed, and
parsing continues — one bad segment in a message is not a reason to discard the
rest of it.

**Units are converted, never assumed.** OBX-6 says `mm` or `cm`; anything else
is reported as unrecognised rather than guessed at. A unit-less number is not
silently taken as millimetres.

**Guard precedence**, as everywhere: message-level validity, then the narrative
case, then per-segment handling. A message that is not an ORU^R01 at all is
refused before its OBX segments are examined.

**The narrative test takes two conditions**, decided while building it: there
must be prose, *and* nothing the mapping names may carry a number. A message of
numbers under identifiers nothing maps is not a narrative report — it is one
this library has no vocabulary for, and those identifiers are worth handing
back rather than swallowing behind a refusal about prose.

### A message with two studies — decided 2026-08-15

**Every study is reported, each with its own growth table**, headed by the date
that study was performed. Nothing is chosen on the caller's behalf and nothing
is discarded.

**Each study is read at the gestation on its own date:**

```
GA at a study = the GA supplied − (the reference date − that study's OBR-7)
```

Reading both tables at the typed `--ga` would print, for a study taken weeks
earlier, a percentile wrong by exactly the days between them — a wrong number
with a correct-looking date beside it. The correction is pure date arithmetic
of the kind `GestationalAge` already does, and no clinical constant enters it.

A study whose shifted gestation falls before the pregnancy began, or outside a
chart's window, is refused by the adapters exactly as any other out-of-range
gestation is. That path already exists and needs nothing new.

---

## Sequence

```
0. scaffolding + shared types + loader     done
1. gestational age                         done; CRL and biometry deferred
2. redating                                done; its own fixtures are its only guard
3. EFW                                     done; all 5 formulas offered
4. percentiles                             done; four adapters, one interpolation rule
5. presentation                            done; table and --json
6. HL7                                     in progress; LOINC mapping deferred
```

Slice 3 is done and slice 4 is unblocked: every formula the four charts pair
with is published and verified, and the harness checks each pairing resolves.

**One decision remains before slice 4 forks**, down from four. The others are
settled: the `:method` rename is done, per-row `verified` flags are the
loader's problem rather than each adapter's, and `intergrowth21.yml` now states
`paired_formula: intergrowth`.

1. **The interpolation rule**, between weeks and between centiles. Undefined in
   every source, so it is our choice and must be identical across both
   table-based adapters.

Worth keeping in view while building slice 4: INTERGROWTH's pairing is
self-referential — it built its centiles from its own EFW formula, not a
Hadlock model — so `:formula_chart_mismatch` there means something different in
kind from the NICHD and WHO case, where the chart must be read from a
*foreign* formula. The field is uniform; what it points at is not.