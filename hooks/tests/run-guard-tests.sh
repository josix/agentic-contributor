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
known=0
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

  # known-bypass: documented gap (the guard is a tripwire, not a security
  # boundary). Not counted as a failure; flagged when the guard starts denying
  # it so the row can be promoted to "deny".
  if [ "$expect" = "known-bypass" ]; then
    known=$((known + 1))
    if [ "$rc" -eq 2 ]; then
      printf 'NOTE line %d: known-bypass is now denied; promote to deny: [%s] %s\n' \
        "$lineno" "$tool" "$cmd"
    fi
    continue
  fi

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

# ── extra checks: size / segment cap must fail closed before the hook timeout ──
tmpd="$(mktemp -d "${TMPDIR:-/tmp}/guard-tests.XXXXXX")"
trap 'rm -rf "$tmpd"' EXIT

run_guard_file() { # $1 = file holding the command; sets rc and elapsed seconds
  jq -n --rawfile c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' > "$tmpd/in.json"
  t0=$(date +%s)
  "$runner" "$guard" < "$tmpd/in.json" >/dev/null 2>&1
  rc=$?
  elapsed=$(( $(date +%s) - t0 ))
}

# 2500 harmless git segments (denied by the separator cap) then a mutating gh api: must be denied, quickly.
awk 'BEGIN { for (i = 0; i < 2500; i++) print "git status"; print "gh api -X POST repos/o/r/issues" }' > "$tmpd/big.txt"
run_guard_file "$tmpd/big.txt"
if [ "$rc" -eq 2 ] && [ "$elapsed" -le 12 ]; then
  pass=$((pass + 1))
else
  fail=$((fail + 1)); printf 'FAIL big command: expected rc 2 within 12s, got rc %d in %ds\n' "$rc" "$elapsed"
fi

# A 400-line git script must still be allowed.
awk 'BEGIN { for (i = 0; i < 400; i++) print "git status" }' > "$tmpd/ok.txt"
run_guard_file "$tmpd/ok.txt"
if [ "$rc" -eq 0 ]; then
  pass=$((pass + 1)); printf 'info: 400-line git script allowed in %ds\n' "$elapsed"
else
  fail=$((fail + 1)); printf 'FAIL 400-line git script: expected rc 0, got rc %d\n' "$rc"
fi

# One huge quoted argument then a mutating call: byte cap, no quadratic work.
awk 'BEGIN { printf "git commit -m \""; for (i = 0; i < 70000; i++) printf "x"; print "\"; gh api -X POST repos/o/r/issues" }' > "$tmpd/size1.txt"
run_guard_file "$tmpd/size1.txt"
if [ "$rc" -eq 2 ] && [ "$elapsed" -le 5 ]; then
  pass=$((pass + 1)); printf 'info: 70 KB single segment denied in %ds\n' "$elapsed"
else
  fail=$((fail + 1)); printf 'FAIL size-1: expected rc 2 within 5s, got rc %d in %ds\n' "$rc" "$elapsed"
fi

# Many tiny segments: separator cap denies before any regex/awk work.
awk 'BEGIN { for (i = 0; i < 2500; i++) printf "a;"; print "gh api -X POST repos/o/r/issues" }' > "$tmpd/size2.txt"
run_guard_file "$tmpd/size2.txt"
if [ "$rc" -eq 2 ] && [ "$elapsed" -le 5 ]; then
  pass=$((pass + 1)); printf 'info: 2500-separator command denied in %ds\n' "$elapsed"
else
  fail=$((fail + 1)); printf 'FAIL size-2: expected rc 2 within 5s, got rc %d in %ds\n' "$rc" "$elapsed"
fi

# A css heredoc (height/right contain "gh") must not hit the trigger-segment cap.
awk 'BEGIN { print "cat > style.css <<'"'"'EOF'"'"'"; for (i = 0; i < 600; i++) print ".c" i " { height: 10px }"; print "EOF" }' > "$tmpd/size3.txt"
run_guard_file "$tmpd/size3.txt"
if [ "$rc" -eq 0 ] && [ "$elapsed" -le 10 ]; then
  pass=$((pass + 1)); printf 'info: 600-line css heredoc allowed in %ds\n' "$elapsed"
else
  fail=$((fail + 1)); printf 'FAIL size-3: expected rc 0 within 10s, got rc %d in %ds\n' "$rc" "$elapsed"
fi

total=$((pass + fail))
echo "guard tests ($runner): $pass/$total passed ($known known bypasses documented, see docs/reference/hooks.md)"
[ "$fail" -eq 0 ]
