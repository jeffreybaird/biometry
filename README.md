# biometry

A Ruby library and CLI that computes estimated fetal weight and growth
percentiles across the competing international standards — Hadlock, NICHD,
WHO, INTERGROWTH-21st — and shows where they disagree. The disagreement
between standards is this tool's output, not a caveat on it.

Every value returned names the standard it came from and the formula that
produced it. The library reports measurements and their sources; it never
emits a classification (no SGA, IUGR, macrosomia, or any threshold label).

```
bundle exec exe/biometry --help    # run the CLI
bundle exec rake verify            # lint, full suite, coverage, CVE audit
bundle exec rake oracle            # FetalGPS chart-agreement suite (see below)
```

## Validation against FetalGPS

The suite validates this library against the published papers directly
(1,376 fixtures from published tables and worked examples) and against
FetalGPS, the reference implementation accompanying the FetalGPS paper
(588 oracle fixtures generated from a line-by-line Ruby port of FetalGPSR).
The tier model governing what a fixture failure means is in
[docs/FIXTURES.md](docs/FIXTURES.md).

During that validation we found the following discrepancies. Each is
deliberate on our side and pinned by fixtures, so a future change that
silently re-aligns us with FetalGPS will fail the suite.

1. **Hadlock 1991 dispersion: we use 13.3%, FetalGPS uses 12.7%.**
   FetalGPS takes the abstract's figure (`sd = 0.127 × median`). Ours is
   back-calculated from the paper's own Table 1, whose centiles are exactly
   median × {0.750, 0.830, 1.170, 1.250} at every week. Our value reproduces
   the published table at every centile and gestational age; theirs matches
   only at the median. The effect is about one percentile near the SGA
   threshold. The paper's Discussion and Table 3 both say 13%, supporting
   the table over the abstract.

2. **Formula/chart pairing.** FetalGPS selects the EFW formula from which
   measurements are present (BPD absent → three-parameter Hadlock, BPD
   present → four-parameter), applied identically for every chart — so with
   BPD supplied it reads WHO's table from a four-parameter weight, despite
   its own paper claiming otherwise. We pair each chart with the formula its
   source names and reject a mismatch (`:formula_chart_mismatch`).

3. **Off the edge of a tabulated chart, we report a bound; FetalGPS's two
   implementations disagree with each other.** Above the highest (or below
   the lowest) published centile column, FetalGPSX (VBA) clamps to the edge
   while FetalGPSR (R) extrapolates a line through the outermost two
   centiles. There is no single FetalGPS answer there. We report the
   outermost published centile as a bound — "above the 95th" — and never
   extrapolate past what the source printed. The four oracle rows this
   affects (WHO female chart at 22 weeks, which publishes only the 5th–95th
   columns) are excluded from the chart-agreement comparison and marked in
   `spec/fixtures/oracle_charts.csv`.

4. **Gestational-age ranges.** FetalGPS answers outside the ranges the
   source papers publish or fitted (NICHD 10–42 against a table fitted
   15–40; Hadlock 10–41 against a published 10–40). We return
   `:out_of_range` there.

5. **Source defects encoded in `data/`.** Hadlock 1991 Table 1 prints
   1,649 g for the 97th centile at week 30 — below its own 90th; the
   ratio-implied 1,949 g is used, confirmed against the page scan.
   INTERGROWTH's worked Z-score (0.5617023) does not follow from its own
   Table 2 equations (correct: 0.5544) and is not fixtured.

Because a failure means different things per tier — our bug, their bug, or a
decision we made — the FetalGPS chart-agreement suite runs only via
`rake oracle`, never in `rake verify`. A mismatch there is a question for a
human, not a regression to fix. See [docs/FIXTURES.md](docs/FIXTURES.md).
