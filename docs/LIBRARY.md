# Using biometry as a library

How a Ruby application — a Rails app, a background worker, anything that is
not the bundled CLI — consumes this gem. The CLI is one consumer of the same
API described here; nothing below is a second code path.

- [Installing](#installing)
- [Loading: one Context per process](#loading-one-context-per-process)
- [Thread safety](#thread-safety)
- [The catalog: what is on offer](#the-catalog-what-is-on-offer)
- [Reports as data](#reports-as-data)
- [Chart data](#chart-data)
- [Individual services](#individual-services)
- [Results, not exceptions](#results-not-exceptions)
- [Display names](#display-names)

## Installing

```ruby
# Gemfile
gem 'biometry', git: 'https://github.com/jeffreybaird/rei_calc'
# or, from a checkout:
gem 'biometry', path: '../rei_calc'
```

`require 'biometry'` loads the whole library. The gem ships its `data/`
directory — the hand-transcribed reference constants every calculation reads —
and resolves it relative to its own install root; nothing needs configuring.

## Loading: one Context per process

All reference data is read once, at boot, by the imperative shell:

```ruby
# config/initializers/biometry.rb
BIOMETRY = Biometry.load
```

`Biometry.load` reads every manifest and percentile table through
`Biometry::ReferenceData`, wires the services on them, and returns a frozen
`Biometry::Context`. Hold it for the life of the process; nothing else in the
library touches the filesystem. It raises at boot — deliberately, before any
request is served — if a data file is marked unverified or malformed.
`context.dropped` names any entries pruning removed, so an application can
report what is unavailable and why.

## Thread safety

A Context is safe to share across threads (Puma, Sidekiq, anything):
`ReferenceData` deep-freezes everything it loads, every service is immutable
after construction, and the Context itself is frozen with all its services
built eagerly. There is no lazy loading and no mutation after `Biometry.load`
returns.

## The catalog: what is on offer

`context.catalog` describes everything the library serves, before a user has
supplied anything — the enumeration a web form or an API index renders:

```ruby
context.catalog.growth_standards
# => [#<data Biometry::StandardDescriptor id=:intergrowth21, standard=:intergrowth21,
#      variant=nil, type=:prescriptive, access=:equation,
#      citation="Stirnemann et al. 2017, ...", doi="10.1002/uog.17347", pmid=nil,
#      valid_ga_weeks=[22, 40], ga_units=:exact_weeks,
#      centiles={published: [3, 10, 50, 90, 97], computable: "any", ...},
#      stratification={...}, paired_formula=:intergrowth,
#      known_issues=[...], variant_note=nil>, ...]

context.catalog.efw_formulas    # every weight formula: id, required measurements,
                                #   the equation verbatim, the paper's citation
context.catalog.dating_methods  # LMP and IVF-transfer dating, cited
context.catalog.redating_policy # ACOG CO 700, with its known issues verbatim
```

Hadlock 1991 appears twice — `:hadlock_1991_equation` and
`:hadlock_1991_table` — because the paper carries two irreconcilable
dispersion figures and the library reports both sides of the dispute rather
than picking one. Each descriptor's `variant_note` says which reading it is.
Every field is read from the data manifests; absent fields (a 1991 paper has
no DOI) are `nil`, never a default.

## Reports as data

The composed report the CLI prints is available as a value:

```ruby
report = context.report(
  scans: [Biometry::Scan.new(date: Date.today, measurements: [
    Biometry::Measurement.new(kind: :bpd, mm: 81),
    Biometry::Measurement.new(kind: :hc, mm: 296),
    Biometry::Measurement.new(kind: :ac, mm: 279),
    Biometry::Measurement.new(kind: :fl, mm: 61)
  ])],
  ga: Biometry::GestationalAge.from(weeks: 32),
  at: Date.today,
  lmp: Date.today - 224,     # optional dating inputs
  sex: :female, stratum: nil # optional chart options
)

report.dating      # { lmp: Result, transfer: Result, crl: Result, biometry: Result }
report.studies     # one Study per scan, growth rows inside, every row cited
report.redating    # a Result when the three redating inputs were given, else nil
report.reportable? # false only when every derivation and every row refused
```

For a JSON API, `Services::Report::Document` turns a report into the plain
hash the CLI's `--json` serializes — same shape, same keys:

```ruby
render json: Biometry::Services::Report::Document.new.call(**report.to_h)
```

## Chart data

`context.chart_series` produces what a growth chart is drawn from — centile
curves plus an optional plotted point. The full contract, including the
GA-convention rules a chart axis must respect, is in
[CHART_DATA.md](CHART_DATA.md):

```ruby
context.chart_series(
  standard: :intergrowth21,
  point: { estimate: some_estimate, ga: Biometry::GestationalAge.from(weeks: 32) }
).value!.to_h  # JSON-ready
```

## Individual services

The finer-grained questions are on the Context too:

```ruby
context.dating(reference_date: Date.today, lmp: lmp_date)  # all derivations
context.weights(scan)   # every EFW formula's estimate for one scan
context.charts          # the chart registry derived from the manifests
```

## Results, not exceptions

Every service returns a `dry-monads` Result. Expected problems — a missing
measurement, a gestation outside a chart's window, an unpublished centile —
are `Failure([tag, details])` values the caller branches on, with tags drawn
from `Biometry::FAILURE_TAGS`. Exceptions are reserved for genuine bugs and
boot-time data errors. A web application should map Failures to 4xx responses
and let exceptions be its 500s.

Two things the API will never hand you, by design: a bare `nil` where the
reason matters, and a classification label. Percentiles come back as numbers
with provenance; whether 3.2 warrants a flag is the consuming application's
clinical decision, not this library's output.

## Display names

The library returns identifiers (`:intergrowth21`, `:hadlock_1991_equation`)
and citations, not display strings — `Presentation::Format`'s names belong to
the CLI. A web application supplies its own labels, keyed by the catalog's
ids.
