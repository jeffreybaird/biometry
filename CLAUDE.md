# REI CLI — Ruby CLI

Style and metrics are enforced by `.rubocop.yml`, not by this file. If rubocop
passes, the style is correct. Detail patterns live in `.claude/`.

## Commands

```
bundle exec rspec                          # full suite
bundle exec rspec spec/path_spec.rb:42     # single example
bundle exec rubocop -a                     # lint, autocorrect safe offenses
bundle exec bundle-audit check --update    # dependency CVEs
bundle exec exe/biometry --help              # run the CLI locally
bundle exec rake verify                    # all of the above
```

`rake verify` must pass before any commit.

## Architecture

```
exe/biometry                        CLI entrypoint, exit codes
lib/biometry/
  cli/                              command objects, option parsing
  services/                         all clinical calculation, no IO
    dating/                         GA arithmetic, EDD derivation, redating
    weight/                         EFW formulas
    growth/                         one adapter per standard; two are closed-form equations, two are tables
  models/                           value objects
  presentation/                     formatters, comparison table, --json
  hl7/                              ORU^R01 ingestion (last slice)
data/                               transcribed reference constants, committed
spec/
```

Dependencies run one direction: `cli` → `services` → `models`. `presentation`
is called from `cli` only, never from `services`. `models` requires nothing
from the other directories.

## Reference data

`data/` holds clinical constants transcribed by hand from published papers.
It is read-only. Never edit a file under `data/`.

Never derive, interpolate, recall, or infer a clinical constant. Not from
training data, not by fitting, not by analogy to a neighbouring value. If a
value a slice needs is not in `data/`, stop and report what is missing.

Some files carry `verified: false`. The loader raises on them. Do not flip the
flag to make a slice run.

Every value returned to a caller names the standard it came from and the
formula that produced it. A number without provenance is incomplete.

This library reports measurements and their sources. It never emits a
classification: no SGA, IUGR, macrosomia, abnormal, or normal, and no
threshold-crossing label of any kind.

### Functional core, imperative shell

`models/` and `services/` perform no IO. No `File`, no `$stdout`, no `ENV`, no
`system`, no network. Everything that touches the outside world happens in
`cli/` or in a collaborator passed in as an argument.

A service that needs a file's contents takes the contents, not the path.

### Single responsibility

A service object does one thing and exposes a single `call`. If its description
needs the word "and", split it.

## Results and exit codes

Expected failures are values the caller branches on, not exceptions. Services
return `dry-monads` results:

```ruby
Success(estimate)
Failure([:insufficient_data,       { required: [:ac, :hc], given: [:ac, :fl] }])
Failure([:out_of_range,            { standard:, ga_weeks:, valid_range: }])
Failure([:unsupported_standard,    { requested:, available: }])
Failure([:unsupported_centile,     { standard:, requested:, available: }])
Failure([:formula_chart_mismatch,  { chart:, expected:, given: }])
Failure([:invalid_input,           errors])
```

`exe/` is the only place that translates a Result into an exit code:

```
0    Success
1    Failure — an expected, reportable problem
2    usage error: bad flags, missing arguments, unknown subcommand
70   unhandled exception (a bug)
```

Raise only for genuine bugs and unrecoverable conditions. The top-level rescue
in `exe/` catches `StandardError`, prints one line to stderr, and exits 70.
Never rescue for control flow.

## CLI contract

stdout carries the result — the thing a user would pipe into another program.
stderr carries everything else: progress, warnings, errors, diagnostics.

Check `$stdout.tty?` before emitting color, spinners, or `\r`-based progress.
Piped and CI output must be plain lines. An in-place progress indicator falls
back to silence when not a TTY, never to repeated lines.

Every command that prints structured data supports `--json`. JSON goes to
stdout undecorated, with nothing else on that stream.

Error messages name what failed and what the user can do about it. No stack
traces on stdout, ever.

## Testing

Test first. The spec that defines a behavior exists before the code satisfying
it. Every behavior change ships with a spec.

Existing specs are the contract. A passing spec that fails after your change
means the change is wrong until proven otherwise. Do not edit, weaken, or
delete a spec to reach green — flag it and ask. Deliberate behavior changes are
the only exception, and they get stated explicitly.

Given a bug report, write the failing spec first, then fix. Find the root
cause rather than the shortest route around the error message.

Use `context` blocks for states. The description reads as a sentence with its
context: "when the config file is missing / exits with status 2".

Services are tested directly against their Result values. CLI-level specs
assert on exit code, stdout, and stderr as three separate expectations.

Branch coverage threshold is set in `spec/spec_helper.rb`. An untested
conditional arm fails the suite.

### Work one failure at a time

Implement toward the current failure, never toward the feature.

1. Run the narrowest command that reproduces it, not the full suite.
2. Read the failure and state what it says before writing anything.
3. Make the smallest change that addresses that failure alone.
4. Re-run. A different failure is progress; return to step 2.

Do not write code for a failure you have not seen. Do not fix two failures in
one change. If you catch yourself anticipating the next test, stop.

Run the full suite at slice boundaries, not between iterations.

A hardcoded return that satisfies one assertion is a legitimate intermediate
step. It stops being legitimate the moment no remaining test would force it to
generalize. Never end a slice with a fake still standing — if the tests won't
break it, write the real implementation now.

"Find the root cause, not the shortest route" governs bug reports and
unexpected failures. It does not override taking small steps through a red
suite you deliberately created.

### Agents

Two subagents in `.claude/agents/` carry this workflow. Delegate to them by
name; their frontmatter owns their tools and model.

`spec-writer` opens a feature. Hand it the requirement and it decomposes that
into failing tests at three layers — unit for pure logic, integration for
module boundaries, acceptance for user-visible behavior end to end — matching
the conventions of the specs already in `spec/`. It asserts on observable
behavior and public interfaces only, never on call order, private names, or
intermediate state, which would pin the implementation to a design nobody has
chosen yet. It returns the files it created and an ordering plan grouping them
into slices, with the dependencies between them. It writes specs; it does not
implement against them.

`test-runner` runs the suite, or exactly the single command you give it, and
reports each failure verbatim: example description, file and line, the
expected/actual block, and the first backtrace line pointing into `lib/` or
`spec/`. It does not summarize, rank, diagnose, or fix, and it reads no source
unless asked. Use it for every run, including the narrow repeated ones of
"work one failure at a time", so what you read is what rspec printed.

New specs go to `test-runner` before any implementation starts, to confirm each
fails for the reason it is meant to. A spec that passes on its first run, or
errors before reaching its assertion, specifies nothing yet.

Delegation does not relax the rules above: no agent edits, weakens, or deletes
a spec to reach green.

## Git

Trunk-based off `main`. Short-lived branches, rebase rather than merge, no
merge commits.

Atomic commits: one thing each, only related changes, valid working state,
independently reviewable. Never mix a refactor with a behavior change. No
"WIP" or "misc".

Message prefixes: `feat:` `fix:` `refactor:` `test:` `chore:`

`main` is always releasable.

## Never

- Business logic in `cli/` or `presentation/`
- IO in `services/` or `models/`
- `raise` for an expected outcome
- A bare `true`/`false`/`nil` return where the caller needs to know why
- `puts` outside `presentation/` and `exe/`
- `binding.pry`, `byebug`, or debug output in a commit
- Editing anything under `data/`
- Supplying a clinical constant that is not in `data/`
- Emitting a classification label rather than a number and its source