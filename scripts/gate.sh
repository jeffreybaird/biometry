#!/bin/bash
set -euo pipefail

LOG=$(mktemp -t biometry-gate)
trap 'rm -f "$LOG"' EXIT

if ! bundle exec rspec --failure-exit-code 1 >"$LOG" 2>&1; then
  echo "Suite is red. Fix before completing:" >&2
  tail -20 "$LOG" >&2
  exit 2
fi
