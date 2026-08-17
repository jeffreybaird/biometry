---
name: reference-biometry-contract-docs
description: Where the biometry gem's consumer-facing contracts live (LIBRARY.md, CHART_DATA.md) and what they bind in the Consensus web UI
metadata:
  type: reference
---

The gem's consumer contracts are `/Users/jeffreybaird/src/rei_calc/docs/LIBRARY.md`
(Context loading, thread safety, `Report::Document` for JSON, Results-not-exceptions)
and `/Users/jeffreybaird/src/rei_calc/docs/CHART_DATA.md` (chart payload shape,
`ga_units` rules, NICHD-without-stratum returning an **array** of four ChartSeries,
point conventions, "no classification, ever").

Review any downstream chart/report code against these two files, not just against
the app's own specs. Related: [[project-consensus-review-themes]].
