#!/bin/bash
INPUT=$(cat)

AGENT=$(jq -r '.agent_type // "main"' <<<"$INPUT")
TOOL=$(jq -r '.tool_name // ""'      <<<"$INPUT")

# spec-writer owns the specs; everyone else is read-only on them
if [ "$AGENT" = "spec-writer" ] || [ -n "${ALLOW_TEST_EDITS:-}" ]; then
  exit 0
fi

SPEC='(^|/)(spec|tests?)/|_spec\.rb|_test\.rb'

block() {
  echo "Blocked: specs are owned by spec-writer. Report the problem instead of editing." >&2
  exit 2
}

case "$TOOL" in
  Write|Edit|NotebookEdit)
    FILE=$(jq -r '.tool_input.file_path // empty' <<<"$INPUT")
    [[ "$FILE" =~ $SPEC ]] && block
    ;;
  Bash|PowerShell)
    CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT")
    # redirect whose target is a spec path
    grep -qE ">>?[[:space:]]*[^[:space:]|&;]*(spec|test)" <<<"$CMD" && block
    # in-place mutators naming a spec path
    if grep -qE '\b(tee|sed[[:space:]]+-i|cp|mv|rm|truncate|dd|patch)\b' <<<"$CMD" \
       && grep -qE "$SPEC" <<<"$CMD"; then
      block
    fi
    # inline interpreters can write anything
    grep -qE '\b(ruby|python3?|perl|node)\b[[:space:]]+-(e|c)\b' <<<"$CMD" && block
    ;;
esac

exit 0