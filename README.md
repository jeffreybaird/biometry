# biometry

A Ruby library and command-line tool for fetal biometry: it takes the
measurements from a pregnancy ultrasound, computes an estimated fetal weight,
and shows where that weight falls on each of the competing international
growth standards — Hadlock, NICHD (the United States National Institute of
Child Health and Human Development), WHO (the World Health Organization) and
INTERGROWTH-21st.

Every published calculator gives you a number from one standard. The
*disagreement between standards* is this tool's output, not a caveat on it:
the same fetus can sit at the 38th percentile on one chart and the 57th on
another, and both numbers are correct answers to differently-posed questions.

Three commitments shape everything here:

- **Numbers with provenance.** Every value names the standard it came from
  and the formula that produced it, down to the paper's citation.
- **No verdicts.** The library reports measurements and their sources. It
  never emits a classification — no "small for gestational age", no
  "abnormal", no threshold label of any kind. Interpreting a percentile is a
  clinician's job.
- **Honest refusals.** When a chart cannot answer — a measurement is
  missing, the gestational age is outside the chart's published range — the
  refusal prints, with the reason, instead of a silently absent row.

## Quick start

```sh
bundle install
bundle exec exe/biometry report --ga 32w0d \
  --bpd 81 --hc 296 --ac 279 --fl 61 --sex female --stratum white
```

```
Growth  GA 32w0d  BPD 8.1  HC 29.6  AC 27.9  FL 6.1 cm

  INTERGROWTH-21st         1,799 g —      57th  prescriptive  (AC+HC)
  Hadlock 1991 (equation)  1,881 g ±7.4%  39th  reference     (BPD+HC+AC+FL)
  Hadlock 1991 (table)     1,881 g ±7.4%  39th  reference     (BPD+HC+AC+FL)
  WHO (female)             1,878 g ±7.5%  53rd  reference     (HC+AC+FL)
  NICHD (white)            1,878 g ±7.5%  38th  prescriptive  (HC+AC+FL)
```

The four measurement flags are the standard ultrasound biometry, in
millimetres: `--bpd` biparietal diameter (skull width), `--hc` head
circumference, `--ac` abdominal circumference, `--fl` femur length. `--ga`
is the gestational age (how far along the pregnancy is), as weeks and days.
Each chart row shows the estimated weight *that chart's own formula*
produces, the formula's typical error, the percentile, and the kind of
population the chart describes — which is why the weights differ between
rows on purpose.

## Documentation

| Document | What it covers |
|---|---|
| [docs/USAGE.md](docs/USAGE.md) | Every command-line option with worked examples: growth reports, pregnancy dating, due-date redating, JSON output, exit codes. |
| [docs/LIBRARY.md](docs/LIBRARY.md) | Using the gem from a Ruby application: `Biometry.load` and the Context, thread safety, the catalog, reports as data, and how a web app maps Results to responses. |
| [docs/CHART_DATA.md](docs/CHART_DATA.md) | The chart-data contract: centile curves per standard, the plotted point, GA-convention rules for the axis, and the refusals a consumer must handle. |
| [docs/FORMULAS.md](docs/FORMULAS.md) | Every formula and variable explained for a non-medical reader: the measurements, the weight formulas, how each growth chart works, the dating arithmetic, the redating thresholds. |
| [docs/FIXTURES.md](docs/FIXTURES.md) | How the test fixtures are tiered by what a failure means, and the rules for adding one. |
| [docs/VALIDATION_TASK.md](docs/VALIDATION_TASK.md) | The brief the validation package was built from, kept as a record: the findings that must survive, and the open decisions with their resolutions. |
| [PROJECT.md](PROJECT.md) | The project specification and slice-by-slice build history. |
| [ARTIFACTS.md](ARTIFACTS.md) | The artifact index and verification ledger. |
| [CLAUDE.md](CLAUDE.md) | The house rules for working on this codebase: architecture, testing discipline, error-handling and output contracts. |

Developing:

```sh
bundle exec rake verify   # lint, full test suite, coverage, dependency audit
bundle exec rake oracle   # FetalGPS chart-agreement suite (see below)
```

## Validation against FetalGPS

The test suite validates this library two ways: against the source papers
directly (1,376 fixtures from published tables and worked examples), and
against FetalGPS, the reference implementation accompanying the FetalGPS
paper (588 oracle fixtures generated from a line-by-line Ruby port of
FetalGPSR, its R-language version). The tier model governing what a fixture
failure means is in [docs/FIXTURES.md](docs/FIXTURES.md).

That validation surfaced the following discrepancies. Each is deliberate on
our side and pinned by fixtures, so a future change that silently re-aligns
us with FetalGPS will fail the suite.

1. **Hadlock 1991's dispersion figure is contested, so we serve both.** The
   Hadlock 1991 growth chart describes its spread as a fixed percentage of
   the median weight — and the paper carries two irreconcilable figures for
   it, with no erratum ever issued. The abstract says 12.7%; the paper's own
   Table 1 percentile columns imply 13.3%. Two independent research groups
   (Roberts et al., American Journal of Obstetrics and Gynecology 2025;
   Gleason et al., same journal, 2026) recalculated the table and favour the
   abstract's figure, with Roberts reporting that the table method would
   have underdiagnosed fetal growth restriction in 5.1% of patients across
   176,060 ultrasound encounters. FetalGPS implements the abstract's figure.
   Because the choice moves results by about one percentile near the
   thresholds clinicians care about most, this library refuses to pick a
   side silently: every report carries two rows, `Hadlock 1991 (equation)`
   (12.7%, the default and the reading the recent literature favours) and
   `Hadlock 1991 (table)` (13.3%, which reproduces the published Table 1
   exactly) — the same treatment disagreements *between* standards get,
   applied to a disagreement inside one.

2. **Formula-and-chart pairing.** Each growth chart was built from weights
   computed by one specific formula ([why this matters](docs/FORMULAS.md#why-each-chart-is-tied-to-one-weight-formula)).
   FetalGPS instead selects its weight formula by which measurements happen
   to be present — supply a biparietal diameter and it reads *every* chart,
   including WHO's, from a four-parameter weight, despite its own paper
   claiming otherwise. We pair each chart with the formula its source names
   and reject a mismatch (`formula_chart_mismatch`).

3. **Off the edge of a table, we report a bound; FetalGPS's two
   implementations disagree with each other.** Above the highest (or below
   the lowest) percentile column a table chart prints, FetalGPSX (the
   Excel/VBA version) clamps to the edge while FetalGPSR (the R version)
   extrapolates a straight line past it. There is no single FetalGPS answer
   there. We report the outermost published percentile as a bound — "above
   the 95th" — and never extrapolate past what the source printed. The four
   oracle fixtures this affects are excluded from the chart-agreement
   comparison and marked in `spec/fixtures/oracle_charts.csv`.

4. **Gestational-age ranges.** FetalGPS answers outside the ranges the
   source papers published or fitted — for example NICHD at 10–42 weeks
   against a model fitted only from week 15 to 40. We refuse with
   `out_of_range` there.

5. **Defects in the source papers, encoded in `data/`.** Hadlock 1991's
   Table 1 prints 1,649 g for the 97th percentile at week 30 — impossibly
   below its own 90th percentile of 1,824 g; the ratio-implied 1,949 g is
   used, confirmed against the page scan. INTERGROWTH-21st's worked Z-score
   (0.5617023) does not follow from its own published equations — our
   re-derivation gives 0.5544, which has not been independently verified —
   so neither value is used as a fixture.

Because a fixture failure means different things per tier — our bug, their
bug, or a decision we made — the FetalGPS chart-agreement suite runs only
via `rake oracle`, never in `rake verify`. A mismatch there is a question
for a human, not a regression to fix.

## What this tool is not

It is not a diagnostic device, it is not a substitute for clinical
judgement, and it deliberately refuses to label any number as normal or
abnormal. It computes published arithmetic, names its sources, and shows
where the sources disagree.
