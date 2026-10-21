#!/usr/bin/env bash
# run-guard-tests.sh — regression harness for hooks/scripts/guard-outbound.sh.
#
# Usage:  bash hooks/tests/run-guard-tests.sh
#   GUARD_BASH=/bin/bash   interpreter used to run the guard (default: /bin/bash,
#                          i.e. macOS bash 3.2 when present, else bash on PATH)
#
# Reads guard-cases.tsv (expect<TAB>tool_name<TAB>command), builds the PreToolUse
# JSON with jq, pipes it to the guard and checks the exit code (allow=0, deny=2).
# Compatible with bash 3.2.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
guard="$here/../scripts/guard-outbound.sh"
cases="$here/guard-cases.tsv"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to run the guard tests" >&2
  exit 1
fi

runner="${GUARD_BASH:-}"
if [ -z "$runner" ]; then
  if [ -x /bin/bash ]; then runner=/bin/bash; else runner="$(command -v bash)"; fi
fi

pass=0
fail=0
lineno=0
tab="$(printf '\t')"

while IFS="$tab" read -r expect tool cmd || [ -n "${expect:-}" ]; do
  lineno=$((lineno + 1))
  case "$expect" in ''|'#'*) continue ;; esac

  [ "$cmd" = "-" ] && cmd=""
  cmd="${cmd//\\n/$'\n'}"
  cmd="${cmd//\\t/$'\t'}"

  json="$(jq -n --arg t "$tool" --arg c "$cmd" '{tool_name:$t, tool_input:{command:$c}}')"
  printf '%s' "$json" | "$runner" "$guard" >/dev/null 2>&1
  rc=$?

  case "$expect" in
    allow) want=0 ;;
    deny)  want=2 ;;
    *) echo "FAIL line $lineno: bad expectation '$expect'"; fail=$((fail + 1)); continue ;;
  esac

  if [ "$rc" -eq "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL line %d: expected %s (rc %d) got rc %d: [%s] %s\n' \
      "$lineno" "$expect" "$want" "$rc" "$tool" "$cmd"
  fi
done < "$cases"

total=$((pass + fail))
echo "guard tests ($runner): $pass/$total passed"
[ "$fail" -eq 0 ]
