# Chart data

What a consumer receives to draw a growth chart: the centile curves across
gestation and, optionally, the one point a reader came to look at. Produced by
`Services::Growth::ChartSeries`, reachable from a loaded context:

```ruby
context = Biometry.load

result = context.chart_series(
  standard: :who,           # any chart id the catalog lists
  centiles: [10, 50, 90],   # optional; defaults to the standard's published columns
  sex: nil,                 # WHO only: :male, :female, or nil for the combined chart
  stratum: nil,             # NICHD only: :white, :black, :hispanic, :asian
  step: nil,                # closed-form charts only; grid interval in decimal weeks
  point: nil                # optional { estimate: Biometry::Estimate, ga: GestationalAge }
)
```

`result` is a dry-monads Result. On success it wraps one `Biometry::ChartSeries`
— except NICHD asked for without a stratum, which wraps an **array** of four,
one per published race/ethnicity chart, because this library never defaults a
self-reported field. Callers branch on the Result; expected problems are never
exceptions.

## The payload

`ChartSeries#to_h` is plain hashes the whole way down, JSON-ready:

```ruby
{
  chart: {
    standard: :who,             # the chart id drawn
    variant: nil,               # :equation / :table for the two Hadlock 1991 readings
    stratum: :combined,         # which of the standard's charts was read
    type: :reference,           # :prescriptive or :reference, as the paper describes itself
    ga_units: :completed_weeks, # the standard's own GA convention (see below)
    valid_ga_weeks: [14, 40],
    basis: :published_table     # or :closed_form
  },
  source: { citation: "Kiserud et al. 2017, ...", doi: "10.1371/...", pmid: nil,
            type: :reference },
  series: [
    { centile: 10, points: [{ ga_weeks: 14, grams: 79 }, ...] },
    ...
  ],
  point: {                      # only when a point was asked for
    ga_weeks: 32,               # in the chart's own GA convention
    efw_g: 1600,
    percentile: { value: 47.3, bound: :computed, interpolation: :linear_in_weight }
  },
  known_issues: [...]           # the manifest's list, verbatim — defects are data
}
```

## Rules

**Table standards (`basis: :published_table`) — WHO, NICHD.** The curve is the
published rows verbatim: one point per integer completed week across
`valid_ga_weeks`, nothing interpolated between weeks. Only published columns
can be drawn; asking for another centile fails with `:unsupported_centile`
naming what is available. WHO's sex-specific tables omit the 2.5th and 97.5th
columns and refuse them for the same reason the tables do. A `step` on a table
standard fails with `:invalid_input` — there is no curve to evaluate, only rows
to read.

**Closed-form standards (`basis: :closed_form`) — INTERGROWTH-21st, both
Hadlock 1991 variants.** The curve is the published equation evaluated on a
grid of exact decimal weeks: from the start of `valid_ga_weeks` at `step`
(default 1.0), with the end of the window always the last point. Any centile
strictly inside (0, 100) is computable; 0 and 100 fail with `:invalid_input`.

**`ga_units` drives the x-axis.** Completed weeks and exact weeks are different
conventions; a chart's curves and its plotted point both use the chart's own,
and mixing charts on one axis without checking this field will misplace points
by up to six days. NICHD's manifest states no convention, so its `ga_units` is
`nil` — report absence, never a default.

**The point is read by the chart's own forward adapter** — the same reading the
report prints, formula pairing enforced. A point the chart refuses (wrong
paired formula, GA outside the window) fails the whole call: a chart drawn
without the point that was asked for is indistinguishable from one nobody
asked a point of.

**Hadlock 1991 is two charts.** The paper's dispersion is contested (12.7% in
the abstract, 13.3% implied by its Table 1; see the `dispersion_contested`
known issue carried in the payload). Both `hadlock_1991_equation` and
`hadlock_1991_table` are served, and a consumer showing one should say which —
never collapse them.

**No classification, ever.** The payload contains numbers, sources and
refusals. No SGA/LGA/IUGR/macrosomia/abnormal label appears in any field at any
depth, and none may be added. Whether to shade a region or flag a threshold is
a clinical decision that belongs to the consuming application and its users,
not to this library's output.

## Failures

All failures use the library's standard tags and travel as
`[tag, details]` inside the Failure:

| tag | when |
| --- | --- |
| `:unsupported_standard` | chart id the registry does not serve; names the available ids |
| `:unsupported_centile` | centile a table never published; names the available columns |
| `:invalid_input` | bad sex/stratum, centile outside (0, 100), step on a table, non-positive step |
| `:out_of_range` | point GA outside the chart's window |
| `:formula_chart_mismatch` | point estimate from a formula the chart does not pair with |
