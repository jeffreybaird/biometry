# Using the command line

Everything the `biometry` command can do, with worked examples. For what the
numbers *mean*, see [FORMULAS.md](FORMULAS.md); this page is about driving
the tool.

- [Setup](#setup)
- [The report command](#the-report-command)
- [A first report](#a-first-report)
- [Reading the output](#reading-the-output)
- [Every option](#every-option)
- [Dating and redating](#dating-and-redating)
- [JSON output](#json-output)
- [Exit codes and streams](#exit-codes-and-streams)

## Setup

The project is a Ruby library with a bundled command-line executable. From a
checkout:

```sh
bundle install                  # install dependencies
bundle exec exe/biometry --help # confirm it runs
bundle exec rake verify         # optional: run the full test suite
```

Every invocation below is written as `bundle exec exe/biometry …`; if you
install the gem, the command is just `biometry …`.

## The report command

There is one command:

```sh
bundle exec exe/biometry report --ga <weeks>w<days>d [options]
```

It produces a report with up to three sections — Dating, Redating, Growth —
each appearing only when you supplied the inputs it needs. The one required
flag is `--ga`, the gestational age (how far along the pregnancy is, written
as weeks and days, for example `32w0d`). It is required because several
derivations of gestational age can disagree, and choosing between them is
not the tool's decision to make.

## A first report

Four ultrasound measurements at 32 weeks, with fetal sex and the mother's
self-reported race/ethnicity group named so the sex-specific and
group-specific charts can be chosen:

```sh
bundle exec exe/biometry report --ga 32w0d \
  --bpd 81 --hc 296 --ac 279 --fl 61 \
  --sex female --stratum white
```

```
Growth  GA 32w0d  BPD 8.1  HC 29.6  AC 27.9  FL 6.1 cm

  INTERGROWTH-21st         1,799 g —      57th  prescriptive  (AC+HC)
  Hadlock 1991 (equation)  1,881 g ±7.4%  39th  reference     (BPD+HC+AC+FL)
  Hadlock 1991 (table)     1,881 g ±7.4%  39th  reference     (BPD+HC+AC+FL)
  WHO (female)             1,878 g ±7.5%  53rd  reference     (HC+AC+FL)
  NICHD (white)            1,878 g ±7.5%  38th  prescriptive  (HC+AC+FL)

  Sources:
    Stirnemann et al. 2017, Ultrasound Obstet Gynecol 49(4):478-486
    …
```

## Reading the output

Each Growth row is one standard's answer, and the columns are:

1. **Standard** — which growth chart was read, with the chart variant in
   parentheses (the sex for WHO, the race/ethnicity group for NICHD).
   Hadlock 1991 always prints two rows, `(equation)` and `(table)`, because
   its source paper carries two irreconcilable spread figures and which to
   use is a live clinical dispute — see
   [the formulas document](FORMULAS.md#hadlock-1991--an-equation-chart)
   and the README's validation notes. Near the 10th percentile the two rows
   differ by about one percentile.
2. **Weight** — the estimated fetal weight in grams, computed by the formula
   *that chart* was built on. The rows legitimately disagree: each chart is
   paired with its own formula, so the table carries up to three distinct
   weights. See [why each chart is tied to one formula](FORMULAS.md#why-each-chart-is-tied-to-one-weight-formula).
3. **± figure** — the weight formula's typical prediction error (one
   standard deviation, as a percentage). It describes the formula's
   accuracy, not the chart's spread.
4. **Percentile** — where that weight falls on that chart at that age:
   "39th" means heavier than 39% of that standard's reference population.
   No label is ever attached; this library reports numbers and sources, not
   classifications.
5. **prescriptive / reference** — the kind of population behind the chart.
   *Prescriptive* charts (INTERGROWTH-21st, NICHD) describe optimal growth in
   healthy pregnancies; *reference* charts (Hadlock 1991, WHO) describe a
   population as it presented, complications included. Percentiles from the
   two kinds are not interchangeable.
6. **Measurements in parentheses** — which inputs that chart's formula used.

A chart that cannot answer keeps its row and says why — for example
`insufficient data — requires hc, ac, fl; given ac, fl`, or `out of range`
when the gestational age falls outside the chart's published window. A
missing row would look like a chart that was never consulted; a present,
explained refusal is the honest state. If a weight falls outside a table
chart's outermost printed percentile column, the percentile reads as a bound
("above the 95th") rather than an extrapolated number.

## Every option

### Gestation

| Flag | Meaning |
|---|---|
| `--ga WEEKS` | Gestational age to read every chart at, as weeks and days: `32w0d`. **Required.** |
| `--at DATE` | The reference date the report is taken at, ISO format `YYYY-MM-DD`. Defaults to today — which silently changes date-derived answers, so pass it explicitly when reproducing a result. |

### Biometry (the ultrasound measurements, all in millimetres)

| Flag | Full name | What is measured |
|---|---|---|
| `--bpd MM` | Biparietal diameter | Widest side-to-side span of the fetal skull. |
| `--hc MM` | Head circumference | Around the outer perimeter of the skull. |
| `--ac MM` | Abdominal circumference | Around the outer border of the abdomen. |
| `--fl MM` | Femur length | The thigh bone's shaft, excluding the cartilage cap. |

Decimals are allowed. Supply whichever you have; each formula states what it
requires and refuses, with the list of what was missing, when it cannot run.

### Charts

| Flag | Meaning |
|---|---|
| `--sex SEX` | Fetal sex, selecting the WHO chart: `combined`, `female` or `male`. Omitted, the combined table is read. |
| `--stratum GROUP` | NICHD chart: `white`, `black`, `hispanic` or `asian`. This is self-reported race/ethnicity — never inferred, never defaulted. Omitted, **all four** charts print, because NICHD publishes no combined table and the spread between the four is the study's own finding. |

### Dating

| Flag | Meaning |
|---|---|
| `--lmp DATE` | First day of the last menstrual period, `YYYY-MM-DD`. |
| `--cycle DAYS` | Menstrual cycle length in days. The rule assumes 28; a 35-day cycle moves the due date a week later. |
| `--transfer DATE` | Embryo transfer date (in-vitro fertilisation), `YYYY-MM-DD`. |
| `--embryo-day N` | The embryo's age in days on the day of transfer: 3 for a cleavage-stage embryo, 5 for a blastocyst. Required alongside `--transfer`, because guessing it is a two-day error in either direction. |

### Redating

All three flags are required together — two of the three describe a
comparison with nothing to compare against:

| Flag | Meaning |
|---|---|
| `--established-edd DATE` | The due date already established for this pregnancy. |
| `--established-by HOW` | How it was established: `lmp`, `transfer`, `crl` or `biometry`. This decides *whether any threshold applies at all* — a pregnancy dated by in-vitro fertilisation (`transfer`) is never redated by ultrasound. |
| `--scan-edd DATE` | The due date the current scan implies. |

### Messages

| Flag | Meaning |
|---|---|
| `--hl7 PATH` | Read the biometry from an HL7 ORU^R01 observation message (the hospital-interface format for lab and imaging results) at `PATH`, instead of from the measurement flags — one or the other, not both. Each OBR segment (one requested study) becomes one report. Currently refused until `data/loinc.yml` is transcribed: without the LOINC code mapping, no observation identifier can be named. |

### Output

| Flag | Meaning |
|---|---|
| `--json` | Emit the report as JSON on stdout, undecorated. See [JSON output](#json-output). |

## Dating and redating

Give the dating section something to work with and it reports every
derivation it can compute, each with its arithmetic on display:

```sh
bundle exec exe/biometry report --ga 12w0d \
  --lmp 2026-05-22 --at 2026-08-14 \
  --established-edd 2027-02-26 --established-by lmp \
  --scan-edd 2027-03-06
```

```
Dating
  LMP (28d cycle)  EDD 2027-02-26  12w0d
  Transfer         insufficient data — requires transfer_date, embryo_day, …

Redating
  redate  8 day(s) against a 7 day threshold, crl_late at 12w0d
```

The redating line names the recommendation (`redate` or `keep`), the
discrepancy, the threshold it was tested against, and the band that supplied
the threshold (here `crl_late`, the 9–13-week crown–rump-length band; the
full table is in [FORMULAS.md](FORMULAS.md#redating--the-acog-thresholds)).
Nothing is mutated: the established due date stays established, and the
output is a recommendation with its reasoning. In the 22–27-week band a
10–14-day discrepancy reports a discretionary zone rather than a bare
verdict, and from 28 weeks a third-trimester caveat prints alongside.

## JSON output

Every report is available as JSON for piping into other programs:

```sh
bundle exec exe/biometry report --ga 32w0d --hc 296 --ac 279 --fl 61 --json
```

JSON goes to stdout with nothing else on that stream, undecorated, and
carries unrounded values where the table rounds a percentile to a whole
ordinal. The top-level keys are `gestational_age`, `dating`, `redating` (when
requested) and `studies`; each study carries its `measurements` and a
`growth` array with one entry per chart reading, each holding the `standard`,
the full `weight` (value, formula, inputs, citation) and the full
`percentile` (unrounded value, bound, citation). Combine with a tool like
`jq`:

```sh
bundle exec exe/biometry report --ga 32w0d --hc 296 --ac 279 --fl 61 --json \
  | jq '.studies[].growth[] | {standard, weight: .weight.value, percentile: .percentile.value}'
```

## Exit codes and streams

The command follows the usual Unix conventions strictly:

- **stdout** carries the result — the thing you would pipe into another
  program. **stderr** carries everything else: warnings, errors, progress.
- Color and progress indicators appear only when stdout is a terminal;
  piped or CI output is plain lines.

| Exit code | Meaning |
|---|---|
| `0` | A report was produced. |
| `1` | Nothing could be reported — an expected, explained refusal (the explanations still print on stdout). |
| `2` | Usage error: bad flags, missing arguments, unknown subcommand. stdout stays empty; stderr names the problem. |
| `70` | An unhandled exception — a bug. One line on stderr, never a stack trace on stdout. |
