---
name: project-consensus-review-themes
description: Recurring defect classes found reviewing the Consensus web UI (/Users/jeffreybaird/src/consensus) — check these first on any review there
metadata:
  type: project
---

Recurring defect classes in Consensus (`/Users/jeffreybaird/src/consensus`), first
catalogued in the 2026-08-16 review of the biometry-UI build (976f27c..HEAD).

**Why:** the suite there is large, exhaustive and green — it asserts the happy path
and the gem's own refusals very thoroughly, so defects concentrate in the places
specs never look: security config, non-String params, and the CLAUDE.md rules that
are policy rather than behavior.

**How to apply:** verify each against current code before reporting (they may be
fixed), but start the review here:

1. **Config that silently does nothing.** `set :erb, escape_html: true` was inert
   because `erubi` was absent from the Gemfile — Tilt fell back to `ERBTemplate`,
   which ignores the option, giving unescaped output. Check that any security or
   behavior flag has a spec proving the *effect*, not the setting.
2. **Non-scalar params.** Services call `.strip`/`.to_sym` on `params[...]`
   assuming Strings; `?field[]=x` yields an Array and raises `NoMethodError` (a
   user-triggerable 500 on an otherwise validating path).
3. **`.value!` on gem Results** inside services — safe only because that particular
   aggregate always succeeds today. Coupling to it turns a future refusal into a 500.
4. **Route-level orchestration** creeping back in: looping every chart id, calling
   gem internals (`Biometry::Services::Report::Document`) directly, `limit(PAGE_SIZE)`
   with no page param. CLAUDE.md's pagination/audit/Instrument rules are stated as
   rules but unimplemented — call the gap out rather than assuming it is accepted.
5. **Missing-panel risks from `.find{}.stratification`** on the catalog: the gem can
   prune entries (`context.dropped`), so an unguarded `find` is a nil crash at boot-
   adjacent code paths.

Clinical-rule compliance (no classification labels, citations present, refusals
rendered) has held up well in every layer reviewed so far — CSS tokens, aria labels
and copy were clean. Contracts: [[reference-biometry-contract-docs]].
