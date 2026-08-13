#!/bin/bash
set -euo pipefail

# Full template rather than `mktemp -t biometry-gate`: GNU coreutils rejects a
# template with no XXX and exits 1, which under `set -e` aborts this hook
# before rspec runs — so on Linux the gate silently stops gating.
LOG=$(mktemp "${TMPDIR:-/tmp}/biometry-gate.XXXXXX")
trap 'rm -f "$LOG"' EXIT

if ! bundle exec rspec --failure-exit-code 1 >"$LOG" 2>&1; then
  echo "Suite is red. Fix before completing:" >&2
  tail -20 "$LOG" >&2
  exit 2
fi
