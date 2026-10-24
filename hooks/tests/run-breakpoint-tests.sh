#!/usr/bin/env bash
# run-breakpoint-tests.sh — regression harness for hooks/scripts/track-breakpoint.sh.
#
# Usage:  bash hooks/tests/run-breakpoint-tests.sh
#   TRACK_BASH=/bin/bash   interpreter used to run the hooks (default: /bin/bash,
#                          i.e. macOS bash 3.2 when present, else bash on PATH)
#
# Reads breakpoint-cases.tsv, builds a fixture git repo per case, writes a ledger, pointer and
# optional state file for the named profile, pipes PostToolUse/Stop JSON to the hook and checks
# stdout, exit code, ledger and state changes. Also checks that the code blocks shared with
# track-checkpoint.sh are byte-identical. Compatible with bash 3.2. Never touches the real tree.

set -u

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
hook="$here/../scripts/track-breakpoint.sh"
chook="$here/../scripts/track-checkpoint.sh"
cases="$here/breakpoint-cases.tsv"

if ! command -v jq > /dev/null 2>&1; then
  echo "jq is required to run the breakpoint tests" >&2
  exit 1
fi

runner="${TRACK_BASH:-}"
if [ -z "$runner" ]; then
  if [ -x /bin/bash ]; then runner=/bin/bash; else runner="$(command -v bash)"; fi
fi

pass=0
fail=0
tab="$(printf '\t')"
LEDGER_NAME="track-test-repo-task-20261024T000000Z.md"
T="2026-10-24T00:00:00Z"
tmps=""

cleanup() { [ -n "$tmps" ] && rm -rf $tmps; }
trap cleanup EXIT

ok() { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL %s\n' "$1"; }

# ── fixture ───────────────────────────────────────────────────────────────────
write_ledger() { # $1 file  $2 status  $3 scope  $4 budget  $5 base  $6 extra frontmatter lines
  cat > "$1" << LEDGER
---
plugin: agentic-contributor
scenario: prepare-pr
mode: track
repo: local
item: task
task: "fixture"
issue: none
branch: main
base_commit: $5
started_at: $T
status: $2
scope: $3
scope_source: user
api_paths: []
budget: $4
$6
generated_at: $T
---
# Decision ledger (private)
Private notes. Not PR text. Do not paste.

## Decisions
<!-- track:end -->
LEDGER
}
bp_marker() { # epoch sid id target
  printf '<!-- track:breakpoint at=%s epoch=%s sid=%s target=%s id=%s -->\n- breakpoint question %s\n' "$T" "$1" "$2" "$4" "$3" "$3" >> "$ledger"
}
drift_marker() { # crossed modules asked id
  printf '<!-- track:drift at=%s lines=1 files=1 crossed=%s modules=%s asked=%s id=%s -->\n- drift alert %s\n' "$T" "$1" "$2" "$3" "$4" "$4" >> "$ledger"
}
predict_entry() { # n status
  printf '<!-- track:entry status=%s source=predict asked=yes at=%s id=predict:%s -->\n- phase: diagnosis\n' "$2" "$T" "$1" >> "$ledger"
}
predict_noidea() { # n
  printf '<!-- track:entry status=answered source=predict asked=yes at=%s id=predict:%s -->\n- phase: diagnosis\n- prediction: No idea\n' "$T" "$1" >> "$ledger"
}
explain_entry() { # k status chosen
  printf '<!-- track:entry status=%s source=breakpoint asked=yes at=%s id=explain:%s -->\n- chosen: %s\n' "$2" "$T" "$1" "$3" >> "$ledger"
}
auto_marker() { # state reason
  printf '<!-- track:predict-auto at=%s state=%s reason=%s -->\n- predict auto: %s (%s)\n' "$T" "$1" "$2" "$1" "$2" >> "$ledger"
}
st_add() { printf "$@" >> "$state"; }
gen_lines() { # $1 prefix $2 count
  awk -v p="$1" -v n="$2" 'BEGIN { for (i = 1; i <= n; i++) print p " " i }'
}
chg_range() { # $1 file $2 first $3 last: rewrite those lines so git sees a hunk
  awk -v a="$2" -v b="$3" 'NR >= a && NR <= b { print "changed " NR; next } { print }' "$root/$1" > "$root/$1.tmp" && mv "$root/$1.tmp" "$root/$1"
}
big_lines() { gen_lines extra 450 >> "$root/src/app.js"; }
hunk_app() { chg_range src/app.js 40 69; st_add 'e\tsrc/app.js\n'; }

setup() { # $1 profile -> sets d root ledger pointer state evil env_extra perm
  local p="$1" status=active scope='["src/**"]' budget=3 base extra="" sha
  d="$(mktemp -d)"
  tmps="$tmps $d"
  root="$d/repo"
  env_extra=""
  perm=default
  mkdir -p "$root/src" "$root/docs" "$root/.oss-drafts"
  (
    cd "$root" || exit 1
    git init -q 2> /dev/null
    gen_lines line 100 > src/app.js
    gen_lines a 100 > src/a.js
    gen_lines b 100 > src/b.js
    printf 'x\n' > docs/x.md
    printf '{"name":"x"}\n' > package.json
    printf 'x\n' > yarn.lock
    git add -A > /dev/null 2>&1
    git -c user.email=t@t -c user.name=t commit -q -m init > /dev/null 2>&1
  )
  sha="$(cd "$root" && git rev-parse HEAD)"
  base="$sha"
  ledger="$root/.oss-drafts/$LEDGER_NAME"
  pointer="$root/.oss-drafts/.track-active"
  state="${ledger%.md}.state"
  evil="$d/evil.state"
  printf 'orig\n' > "$evil"
  case "$p" in
    stopped) status=stopped ;;
    budget0-big | budget0-hunk) budget=0 ;;
    scope-empty-docs) scope='[]' ;;
    badbase) base=zzz ;;
    unknown-sha) base=1234567890abcdef1234567890abcdef12345678 ;;
    explain0) extra="explain_max: 0" ;;
    predict-on | predict-2 | predict-full | predict-stop | predict-mixed) extra="predict: true" ;;
    predict-max2) extra=$'predict: true\npredict_max: 2' ;;
    predict-off) extra="predict: false" ;;
    predict-b0) extra="predict: true"; budget=0 ;;
    predict-stopped) extra="predict: true"; status=stopped ;;
    auto-new | auto-busy | auto-slash | auto-dedup) extra=$'predict: auto\nuser_commits: 2\nprior_unknowns: 0' ;;
    auto-new-b0) extra=$'predict: auto\nuser_commits: 2'; budget=0 ;;
    auto-new-cap) extra=$'predict: auto\npredict_max: 2\nuser_commits: 2' ;;
    auto-vet | auto-vet-marker | auto-explain-skip | auto-explain-nr | auto-noidea | auto-noidea-marker) extra=$'predict: auto\nuser_commits: 50\nprior_unknowns: 0' ;;
    auto-prior3) extra=$'predict: auto\nuser_commits: 50\nprior_unknowns: 3' ;;
    auto-unknown) extra=$'predict: auto\nuser_commits: -1\nprior_unknowns: 2' ;;
    auto-nokey) extra=$'user_commits: 2\nprior_unknowns: 5' ;;
    auto-alias-on) extra=$'predict: on' ;;
    auto-alias-off) extra=$'predict: off\nuser_commits: 2' ;;
  esac
  case "$p" in
    none) ;;
    nofm)
      printf '# no frontmatter\n<!-- track:end -->\n' > "$ledger"
      printf '.oss-drafts/%s\n' "$LEDGER_NAME" > "$pointer" ;;
    *)
      write_ledger "$ledger" "$status" "$scope" "$budget" "$base" "$extra"
      printf '.oss-drafts/%s\n' "$LEDGER_NAME" > "$pointer" ;;
  esac
  local now old
  now="$(date +%s)"
  old=$((now - 100000))
  case "$p" in
    disabled) env_extra="OSS_TRACK_DISABLE=1"; big_lines ;;
    small) chg_range src/app.js 1 10 ;;
    big-lines | budget0-big) big_lines ;;
    big-lines-marked) big_lines; drift_marker lines - yes drift:1 ;;
    throttled) big_lines; st_add 'e\tsrc/app.js\nd\n' ;;
    many-files | big-both | drift-capped)
      [ "$p" != many-files ] && big_lines
      local i=1
      while [ "$i" -le 11 ]; do
        printf 'n\n' > "$root/src/f$i.js"
        st_add 'e\tsrc/f%s.js\n' "$i"
        i=$((i + 1))
      done
      [ "$p" = drift-capped ] && { drift_marker lines - yes drift:1; drift_marker - other yes drift:2; } ;;
    manifest-drift) printf '{"name":"y"}\n' > "$root/package.json" ;;
    plus-hunk)
      awk 'NR == 10 { print "++ counter;"; next } NR >= 60 && NR <= 89 { print "changed " NR; next } { print }' "$root/src/app.js" > "$root/src/app.js.tmp" && mv "$root/src/app.js.tmp" "$root/src/app.js"
      st_add 'e\tsrc/app.js\n' ;;
    lock-only) gen_lines lock 2000 >> "$root/yarn.lock" ;;
    scoped-docs | scoped-docs-covered)
      printf 'changed\n' > "$root/docs/x.md"
      [ "$p" = scoped-docs-covered ] && printf '<!-- track:entry status=decided source=checkpoint asked=yes at=%s id=scope:docs/x.md -->\n' "$T" >> "$ledger" ;;
    scope-empty-docs) printf 'changed\n' > "$root/docs/x.md" ;;
    edits-big) big_lines; st_add 'e\tsrc/app.js\n' ;;
    after-b) hunk_app; st_add 'b\texplain:1\n' ;;
    hunk | explain0 | budget0-hunk | plan-hunk | latch | bp4 | bp-recent | bp-1300 | bp-abc | bp-future | pending-m0 | pending-m1 | stale-lock | busy-lock)
      hunk_app ;;
    junk-state) printf 'junk\nmore junk\n' > "$state" ;;
    two-files | two-files-covered | two-files-targeted)
      chg_range src/a.js 20 24; chg_range src/b.js 10 49; st_add 'e\tsrc/a.js\ne\tsrc/b.js\n' ;;
    only-lock) gen_lines lock 3 >> "$root/yarn.lock"; st_add 'e\tyarn.lock\n' ;;
    untracked) gen_lines new 25 > "$root/src/new.js"; st_add 'e\tsrc/new.js\n' ;;
    predict-stop) hunk_app ;;
    state-symlink) ln -s "$evil" "$state" ;;
  esac
  case "$p" in
    bp4) bp_marker "$old" s0 explain:1 src/x:1; bp_marker "$old" s0 explain:2 src/x:2
      bp_marker "$old" s0 explain:3 src/x:3; bp_marker "$old" s0 explain:4 src/x:4 ;;
    bp-recent) bp_marker $((now - 60)) s0 explain:1 src/x:1 ;;
    bp-1300) bp_marker $((now - 1300)) s0 explain:1 src/x:1 ;;
    bp-abc) bp_marker abc s0 explain:1 src/x:1 ;;
    bp-future) bp_marker $((now + 99999)) s0 explain:1 src/x:1 ;;
    pending-noedit) printf 'm\t0\n' > "$state"; printf '<!-- track:pending at=%s id=dependency:package.json -->\n' "$T" >> "$ledger" ;;
    pending-m0 | pending-m1)
      printf '<!-- track:pending at=%s id=dependency:package.json -->\n' "$T" >> "$ledger"
      # the watermark line comes before the edit line
      printf 'm\t%s\n' "${p#pending-m}" > "$state.tmp"
      cat "$state" >> "$state.tmp"; mv "$state.tmp" "$state" ;;
    latch)
      bp_marker "$old" s1 explain:1 src/x:1
      printf '<!-- track:entry status=skipped source=breakpoint asked=no reason=non-interactive at=%s id=explain:1 -->\n' "$T" >> "$ledger" ;;
    two-files-covered) printf '<!-- track:entry status=decided source=checkpoint asked=yes at=%s id=scope:src/b.js -->\n' "$T" >> "$ledger" ;;
    two-files-targeted) bp_marker "$old" s0 explain:1 src/b.js:10 ;;
    stale-lock) mkdir "$ledger.lock"; touch -t 202001010000 "$ledger.lock" ;;
    busy-lock) mkdir "$ledger.lock" ;;
    plan-hunk) perm=plan ;;
    predict-2 | predict-max2) predict_entry 1 answered; predict_entry 2 skipped ;;
    predict-full) predict_entry 1 answered; predict_entry 2 answered; predict_entry 3 skipped; predict_entry 4 answered ;;
    predict-stop) predict_entry 1 answered ;;
    auto-noidea) predict_noidea 1; predict_noidea 2 ;;
    auto-noidea-marker) auto_marker on newcomer; predict_noidea 1; predict_noidea 2 ;;
    auto-vet-marker) auto_marker on newcomer ;;
    auto-explain-skip) explain_entry 1 skipped skip ;;
    auto-explain-nr) explain_entry 1 answered not-requested ;;
    auto-busy) mkdir "$ledger.lock" ;;
    auto-new-cap) predict_entry 1 answered; predict_entry 2 answered ;;
    predict-mixed) predict_entry 1 answered; printf '<!-- track:entry status=decided source=checkpoint asked=yes at=%s id=test:package.json -->\n' "$T" >> "$ledger" ;;
  esac
  return 0
}

build_post() { # path [agent_id]
  jq -nc --arg c "$root" --arg p "$1" --arg m "$perm" --arg a "${2:-}" \
    '{session_id:"s1",cwd:$c,permission_mode:$m,hook_event_name:"PostToolUse",tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"},tool_response:{filePath:$p,success:true},tool_use_id:"t"} + (if $a != "" then {agent_id:$a} else {} end)'
}
build_stop() { # sid active msg
  jq -nc --arg c "$root" --arg m "$perm" --arg s "$1" --argjson act "$2" --arg msg "${3:-done.}" \
    '{session_id:$s,cwd:$c,permission_mode:$m,hook_event_name:"Stop",stop_hook_active:$act,transcript_path:"/nonexistent",last_assistant_message:$msg}'
}

build_prompt() { # prompt text
  jq -nc --arg c "$root" --arg m "$perm" --arg p "$1" \
    '{session_id:"s1",cwd:$c,permission_mode:$m,hook_event_name:"UserPromptSubmit",prompt:$p}'
}

run_hook() { # json on $1 -> out rc
  out="$(printf '%s' "$1" | env -u CLAUDE_PROJECT_DIR $env_extra "$runner" "$hook" 2> /dev/null)"
  rc=$?
}

lsize() { if [ -f "$1" ]; then wc -c < "$1" | tr -d " "; else echo 0; fi; }
jqf() { printf '%s' "$out" | jq -r "$1" 2> /dev/null; }
resolve_path() {
  case "$1" in
    @ledger) printf '%s' "$ledger" ;;
    -) printf '' ;;
    *) printf '%s' "$root/$1" ;;
  esac
}

# ── table-driven cases ────────────────────────────────────────────────────────
lineno=0
while IFS="$tab" read -r expect profile event ptoken want || [ -n "${expect:-}" ]; do
  lineno=$((lineno + 1))
  case "$expect" in '' | '#'*) continue ;; esac
  label="line $lineno [$expect/$profile/$event]"
  setup "$profile"
  case "$event" in
    Post) json="$(build_post "$(resolve_path "$ptoken")")" ;;
    PostAgent) json="$(build_post "$(resolve_path "$ptoken")" agent-1)" ;;
    Stop) json="$(build_stop s1 false)" ;;
    StopActive) json="$(build_stop s1 true)" ;;
    Prompt) json="$(build_prompt 'Why does the build fail?')" ;;
    PromptSlash) json="$(build_prompt '/oss track predict off')" ;;
    PromptSpaceSlash) json="$(build_prompt '  /help')" ;;
    PromptEmpty) json="$(build_prompt '')" ;;
    StopQ) json="$(build_stop s1 false 'Should I continue?')" ;;
    StopS2) json="$(build_stop s2 false)" ;;
    RAW) r="$ptoken"; [ "$r" = "-" ] && r=""; json="${r//<root>/$root}" ;;
  esac
  l_before="$(lsize "$ledger")"
  s_before="$(lsize "$state")"
  evil_before="$(cat "$evil")"
  run_hook "$json"
  l_after="$(lsize "$ledger")"
  s_after="$(lsize "$state")"
  good=1
  [ "$rc" -eq 0 ] || { bad "$label rc=$rc"; good=0; }
  [ "$(cat "$evil")" = "$evil_before" ] || { bad "$label wrote through a symlink"; good=0; }
  if [ "$good" -eq 1 ] && [ "$profile" != busy-lock ] && [ "$profile" != auto-busy ] && [ -d "$ledger.lock" ]; then bad "$label left the ledger lock behind"; good=0; fi
  k="${want%% *}"
  if [ "$good" -eq 1 ]; then
    case "$expect" in
      noop)
        if [ -n "$out" ] || [ "$l_before" != "$l_after" ] || [ "$s_before" != "$s_after" ]; then bad "$label expected noop, got: $out"; good=0; fi
        if [ "$profile" = none ] && [ -e "$state" ]; then bad "$label created a state file outside a session"; good=0; fi ;;
      silent)
        if [ -n "$out" ] || [ "$l_before" != "$l_after" ]; then bad "$label expected silent, got: $out"; good=0
        elif [ "$want" = "state has e line" ] && ! grep -q "^e$tab" "$state" 2> /dev/null; then bad "$label edit not logged"; good=0
        elif [ "$want" = "m advanced" ] && ! grep -q "^m${tab}1\$" "$state"; then bad "$label watermark not advanced"; good=0
        elif [ "$want" = "m1 and edits kept" ] && { ! grep -q "^m${tab}1\$" "$state" || grep -q '^b' "$state"; }; then bad "$label watermark/edits wrong"; good=0
        elif [ "$profile" = badbase ] && ! grep -q "^e$tab" "$state"; then bad "$label edit not logged"; good=0; fi ;;
      drift-ctx | drift-log)
        extra="${want#* }"; [ "$extra" = "$want" ] && extra=""
        marker="$(grep "^<!-- track:drift .* id=drift:$k -->\$" "$ledger" | tail -1)"
        if [ -z "$marker" ] || { [ -n "$extra" ] && ! printf '%s' "$marker" | grep -qF -- "$extra"; }; then bad "$label expected marker drift:$k ($extra), got: $marker"; good=0
        elif [ "$(jqf '.decision // empty')" != "" ] || ! printf '%s' "$out" | jq -e '.hookSpecificOutput.hookEventName == "PostToolUse" and (.hookSpecificOutput.additionalContext | length > 0)' > /dev/null 2>&1; then
          bad "$label expected additionalContext only, got: $out"; good=0
        elif [ "$expect" = drift-ctx ] && { ! printf '%s' "$marker" | grep -q ' asked=yes ' || ! printf '%s' "$out" | jq -e --arg w "Drift id: drift:$k" '.hookSpecificOutput.additionalContext | contains($w)' > /dev/null 2>&1; }; then
          bad "$label expected asked=yes with drift id in context, got: $out"; good=0
        elif [ "$expect" = drift-log ] && ! printf '%s' "$marker" | grep -q ' asked=no '; then bad "$label expected asked=no"; good=0; fi ;;
      drift-block)
        if [ "$(jqf '.decision // empty')" != block ] || ! printf '%s' "$out" | jq -e --arg w "Drift id: drift:$k" '.reason | contains($w) and (contains("Breakpoint question") | not)' > /dev/null 2>&1; then
          bad "$label expected drift block, got: $out"; good=0
        elif ! grep -q " id=drift:$k -->\$" "$ledger"; then bad "$label no drift marker"; good=0; fi ;;
      explain-block)
        if [ "$(jqf '.decision // empty')" != block ] || ! printf '%s' "$out" | jq -e --arg w "Target: $want" '.reason | contains($w)' > /dev/null 2>&1; then
          bad "$label expected explain block for $want, got: $out"; good=0
        elif [ "$(grep -c '^<!-- track:breakpoint ' "$ledger")" -lt 1 ] || ! tail -1 "$state" | grep -q "^b${tab}explain:[0-9]"; then
          bad "$label marker/state not written before the block"; good=0; fi ;;
      predict-ctx)
        pu="${want%% *}"; pn="${want#* }"
        if [ "$l_before" != "$l_after" ] || [ "$s_before" != "$s_after" ]; then bad "$label hook wrote to ledger/state"; good=0
        elif [ "$(jqf '.decision // empty')" != "" ] || ! printf '%s' "$out" | jq -e --arg a "Predict mode is on ($pu used)" --arg n "id=$pn -->" '.hookSpecificOutput.hookEventName == "UserPromptSubmit" and (.hookSpecificOutput.additionalContext | contains($a) and contains($n) and contains("Only if this prompt asks you to diagnose") and contains("never copy it into any sendable text"))' > /dev/null 2>&1; then
          bad "$label expected predict context ($want), got: $out"; good=0; fi ;;
      auto-ctx)
        # want: "<reason> <markers>"; markers = count of predict-auto markers after the run
        ar="${want%% *}"; am="${want#* }"
        if [ "$(grep -c '^<!-- track:predict-auto ' "$ledger")" != "$am" ]; then bad "$label expected $am marker(s)"; good=0
        elif [ "$am" != 0 ] && ! tail -2 "$ledger" | head -1 | grep -q "^<!-- track:predict-auto at=[0-9TZ:-]* state=on reason=$ar -->\$"; then bad "$label last marker not on/$ar: $(tail -2 "$ledger")"; good=0
        elif [ "$am" != 0 ] && ! tail -1 "$ledger" | grep -qx -- "- predict auto: on ($ar)"; then bad "$label missing human line"; good=0
        elif [ "$(jqf '.decision // empty')" != "" ] || ! printf '%s' "$out" | jq -e --arg a "Predict mode is on (auto: $ar) (" '.hookSpecificOutput.hookEventName == "UserPromptSubmit" and (.hookSpecificOutput.additionalContext | contains($a) and contains("never copy it into any sendable text"))' > /dev/null 2>&1; then
          bad "$label expected auto context ($want), got: $out"; good=0; fi ;;
      auto-silent)
        # want: "<markers> [last marker state]"
        am="${want%% *}"; as="${want#* }"; [ "$as" = "$want" ] && as=""
        if [ -n "$out" ]; then bad "$label expected silent, got: $out"; good=0
        elif [ "$(grep -c '^<!-- track:predict-auto ' "$ledger")" != "$am" ]; then bad "$label expected $am marker(s)"; good=0
        elif [ -n "$as" ] && ! grep '^<!-- track:predict-auto ' "$ledger" | tail -1 | grep -q " state=$as "; then bad "$label last marker not state=$as"; good=0; fi ;;
      consume)
        if [ -n "$out" ] || ! tail -1 "$state" | grep -q "^b${tab}none\$"; then bad "$label expected consume, got: $out"; good=0; fi ;;
      *) bad "$label unknown expectation"; good=0 ;;
    esac
  fi
  [ "$good" -eq 1 ] && ok
done < "$cases"

# ── extra checks ──────────────────────────────────────────────────────────────
# (a) loop safety: after an explain block the next stop is silent; stop_hook_active is a no-op.
setup hunk
run_hook "$(build_stop s1 false)"
if printf '%s' "$out" | jq -e '.decision == "block"' > /dev/null 2>&1; then
  l1="$(lsize "$ledger")"
  run_hook "$(build_stop s1 false)"
  r2="$out"
  run_hook "$(build_stop s1 true)"
  r3="$out"
  { [ -z "$r2" ] && [ -z "$r3" ] && [ "$(lsize "$ledger")" = "$l1" ]; } && ok || bad "(a) loop: second stop not silent: [$r2] [$r3]"
else
  bad "(a) loop: first stop did not block: $out"
fi

# (b) parallel PostToolUse on two new paths: exactly one drift marker and one output.
setup big-lines
json1="$(build_post "$root/src/x1.js")"
json2="$(build_post "$root/src/x2.js")"
printf '%s' "$json1" | env -u CLAUDE_PROJECT_DIR "$runner" "$hook" > "$d/p1.out" 2> /dev/null &
printf '%s' "$json2" | env -u CLAUDE_PROJECT_DIR "$runner" "$hook" > "$d/p2.out" 2> /dev/null &
wait
nm="$(grep -c '^<!-- track:drift ' "$ledger")"
no=0
for f in "$d/p1.out" "$d/p2.out"; do [ -s "$f" ] && no=$((no + 1)); done
{ [ "$nm" -eq 1 ] && [ "$no" -eq 1 ] && [ ! -d "$ledger.lock" ]; } && ok || bad "(b) parallel drift: markers=$nm outputs=$no lock-left=$([ -d "$ledger.lock" ] && echo yes || echo no)"

# (b2) concurrent v0.8.0 PreToolUse and a Stop: both finish, no lock left.
setup hunk
cj="$(jq -nc --arg c "$root" --arg p "$root/package.json" '{session_id:"s",cwd:$c,permission_mode:"default",hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}')"
printf '%s' "$cj" | env -u CLAUDE_PROJECT_DIR "$runner" "$chook" > "$d/c1.out" 2> /dev/null &
printf '%s' "$(build_stop s1 false)" | env -u CLAUDE_PROJECT_DIR "$runner" "$hook" > "$d/c2.out" 2> /dev/null &
wait
{ [ ! -d "$ledger.lock" ] && jq -e '.hookSpecificOutput.permissionDecision == "deny"' "$d/c1.out" > /dev/null 2>&1 && { jq -e '.decision == "block"' "$d/c2.out" > /dev/null 2>&1 || [ ! -s "$d/c2.out" ]; }; } \
  && ok || bad "(b2) concurrent checkpoint + breakpoint: $(cat "$d/c1.out" "$d/c2.out" 2> /dev/null)"

# (c) shared code blocks are byte-identical in both scripts.
for name in find-root pointer clean-list manifest-map glob-match lock; do
  ex() { awk -v n="$name" 'index($0, "# >>> shared:" n " ") == 1 { p = 1; next } $0 == "# <<< shared:" n { p = 0 } p' "$1"; }
  a="$(ex "$chook")"
  b="$(ex "$hook")"
  { [ -n "$a" ] && [ "$a" = "$b" ]; } && ok || bad "(c) shared block '$name' differs between track-checkpoint.sh and track-breakpoint.sh"
done

# (d) the v0.8.0 checkpoint budget is unaffected by drift and explain entries.
setup active
drift_marker lines - yes drift:1
bp_marker "$(date +%s)" s1 explain:1 src/app.js:1
printf '<!-- track:entry status=answered source=breakpoint asked=yes at=%s id=explain:1 -->\n' "$T" >> "$ledger"
cj="$(jq -nc --arg c "$root" --arg p "$root/package.json" '{session_id:"s",cwd:$c,permission_mode:"default",hook_event_name:"PreToolUse",tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"}}')"
cout="$(printf '%s' "$cj" | env -u CLAUDE_PROJECT_DIR "$runner" "$chook" 2> /dev/null)"
printf '%s' "$cout" | jq -e '.hookSpecificOutput.permissionDecisionReason | contains("Decision checkpoint 1/3")' > /dev/null 2>&1 \
  && ok || bad "(d) checkpoint budget affected by drift/explain entries: $cout"

# (e) latency (informational; warns above 20 ms for the no-session paths).
setup none
n=50
TIMEFORMAT=%R
for ev in post stop; do
  if [ "$ev" = post ]; then json="$(build_post "$root/src/app.js")"; else json="$(build_stop s1 false)"; fi
  secs="$( { time (i=0; while [ "$i" -lt "$n" ]; do printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR "$runner" "$hook" > /dev/null 2>&1; i=$((i + 1)); done) ; } 2>&1 )"
  avg_ms="$(awk -v s="$secs" -v n="$n" 'BEGIN { printf "%.1f", s * 1000 / n }')"
  echo "info: no-session $ev path averages ${avg_ms} ms/run incl. bash startup ($n runs)"
  awk -v a="$avg_ms" 'BEGIN { exit !(a > 20) }' && echo "WARN: no-session $ev path above 20 ms"
done
setup throttled
json="$(build_post "$root/src/app.js")"
secs="$( { time (i=0; while [ "$i" -lt 20 ]; do printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR "$runner" "$hook" > /dev/null 2>&1; i=$((i + 1)); done) ; } 2>&1 )"
echo "info: in-session throttled PostToolUse averages $(awk -v s="$secs" 'BEGIN { printf "%.1f", s * 1000 / 20 }') ms/run (20 runs)"
setup big-lines
json="$(build_stop s1 false)"
secs="$( { time (i=0; while [ "$i" -lt 10 ]; do printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR OSS_TRACK_DISABLE= "$runner" "$hook" > /dev/null 2>&1; i=$((i + 1)); done) ; } 2>&1 )"
echo "info: in-session Stop with git averages $(awk -v s="$secs" 'BEGIN { printf "%.1f", s * 1000 / 10 }') ms/run (10 runs)"

# (e2) latency of the no-session UserPromptSubmit path (runs on every prompt in every project).
setup none
json="$(build_prompt 'Why does the build fail?')"
secs="$( { time (i=0; while [ "$i" -lt "$n" ]; do printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR "$runner" "$hook" > /dev/null 2>&1; i=$((i + 1)); done) ; } 2>&1 )"
avg_ms="$(awk -v s="$secs" -v n="$n" 'BEGIN { printf "%.1f", s * 1000 / n }')"
echo "info: no-session prompt path averages ${avg_ms} ms/run incl. bash startup ($n runs)"
awk -v a="$avg_ms" 'BEGIN { exit !(a > 20) }' && echo "WARN: no-session prompt path above 20 ms"

# (f) python3 fallback: a PATH with git and python3 but no jq.
fb="$(mktemp -d)"
tmps="$tmps $fb"
ln -s "$(command -v git)" "$fb/git"
py_real="$(python3 -c 'import sys; print(sys.executable)' 2> /dev/null)"
[ -x "$py_real" ] && ln -s "$py_real" "$fb/python3"
nojq_path="$fb:/usr/bin:/bin"
hash -r
if PATH="$nojq_path" command -v python3 > /dev/null 2>&1 && ! PATH="$nojq_path" command -v jq > /dev/null 2>&1 \
  && PATH="$nojq_path" python3 -c 'import json' > /dev/null 2>&1; then
  setup hunk
  json="$(build_stop s1 false)"
  out="$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR PATH="$nojq_path" "$runner" "$hook" 2> /dev/null)"
  printf '%s' "$out" | python3 -c 'import sys,json; r=json.load(sys.stdin); assert r["decision"]=="block" and "Target: src/app.js:40" in r["reason"]' 2> /dev/null \
    && ok || bad "(f) python3 fallback expected explain block, got: $out"
  setup big-lines
  json="$(build_post "$root/src/app.js")"
  out="$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR PATH="$nojq_path" "$runner" "$hook" 2> /dev/null)"
  printf '%s' "$out" | python3 -c 'import sys,json; r=json.load(sys.stdin); assert "Drift id: drift:1" in r["hookSpecificOutput"]["additionalContext"]' 2> /dev/null \
    && ok || bad "(f) python3 fallback expected drift context, got: $out"
  setup predict-on
  json="$(build_prompt 'Why does the build fail?')"
  out="$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR PATH="$nojq_path" "$runner" "$hook" 2> /dev/null)"
  printf '%s' "$out" | python3 -c 'import sys,json; r=json.load(sys.stdin); h=r["hookSpecificOutput"]; assert h["hookEventName"]=="UserPromptSubmit" and "Predict mode is on (0/4" in h["additionalContext"]' 2> /dev/null \
    && ok || bad "(f) python3 fallback expected predict context, got: $out"
  setup auto-new
  json="$(build_prompt 'Why does the build fail?')"
  out="$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR PATH="$nojq_path" "$runner" "$hook" 2> /dev/null)"
  printf '%s' "$out" | python3 -c 'import sys,json; r=json.load(sys.stdin); assert "Predict mode is on (auto: newcomer) (0/4" in r["hookSpecificOutput"]["additionalContext"]' 2> /dev/null \
    && [ "$(grep -c '^<!-- track:predict-auto ' "$ledger")" = 1 ] && ok || bad "(f) python3 fallback expected auto context, got: $out"
  json="$(build_prompt '/oss track predict off')"
  out="$(printf '%s' "$json" | env -u CLAUDE_PROJECT_DIR PATH="$nojq_path" "$runner" "$hook" 2> /dev/null)"
  [ -z "$out" ] && ok || bad "(f) python3 fallback slash prompt not silent: $out"
else
  echo "info: (f) python3 fallback skipped (no jq-free PATH with a working python3)"
fi

# (g) path with a space: marker target is percent-encoded, the reason is plain.
setup active
gen_lines sp 30 > "$root/src/my file.js"
st_add 'e\tsrc/my file.js\n'
run_hook "$(build_stop s1 false)"
if grep -q '^<!-- track:breakpoint .* target=src/my%20file.js:1 id=explain:1 -->$' "$ledger" \
  && printf '%s' "$out" | jq -e '.reason | contains("Target: src/my file.js:1")' > /dev/null 2>&1; then ok; else bad "(g) space path: $out"; fi

# (h) path with a double quote and a backslash: git quotes it; the target must be the decoded name.
setup active
gen_lines qb 30 > "$root/src/q\"b\\c.js"
st_add 'e\tsrc/q"b\\c.js\n'
run_hook "$(build_stop s1 false)"
if printf '%s' "$out" | jq -e '.reason | contains("Target: src/q\"b\\c.js:1")' > /dev/null 2>&1; then ok; else bad "(h) quoted path: $out"; fi

# (i) auto: a second prompt in the same state writes no new marker; busy lock is left untouched.
setup auto-dedup
run_hook "$(build_prompt 'Why does the build fail?')"
c1="$(grep -c '^<!-- track:predict-auto ' "$ledger")"
l1="$(lsize "$ledger")"
run_hook "$(build_prompt 'Fix the failing test')"
{ [ "$c1" = 1 ] && [ "$(lsize "$ledger")" = "$l1" ] && printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("(auto: newcomer)")' > /dev/null 2>&1; } \
  && ok || bad "(i) auto dedup: markers=$c1 size $l1 -> $(lsize "$ledger")"
setup auto-busy
run_hook "$(build_prompt 'Why does the build fail?')"
{ [ -d "$ledger.lock" ] && [ "$(grep -c '^<!-- track:predict-auto ' "$ledger")" = 0 ]; } && ok || bad "(i) busy lock: lock removed or marker written"

# (j) auto: concurrent prompts in one switch produce exactly one marker.
setup auto-dedup
for i in 1 2 3; do
  printf '%s' "$(build_prompt 'Why does the build fail?')" | env -u CLAUDE_PROJECT_DIR "$runner" "$hook" > "$d/q$i.out" 2> /dev/null &
done
wait
nm="$(grep -c '^<!-- track:predict-auto ' "$ledger")"
{ [ "$nm" -le 1 ] && [ "$nm" -ge 1 ] && [ ! -d "$ledger.lock" ]; } && ok || bad "(j) concurrent auto prompts: markers=$nm lock-left=$([ -d "$ledger.lock" ] && echo yes || echo no)"

# (k) auto: on -> off -> on transitions each log one marker (newcomer on, two no-idea off).
setup auto-new
run_hook "$(build_prompt 'Why does the build fail?')"
predict_noidea 1; predict_noidea 2
run_hook "$(build_prompt 'Why does the build fail?')"
{ [ -z "$out" ] && [ "$(grep -c '^<!-- track:predict-auto ' "$ledger")" = 2 ] && grep '^<!-- track:predict-auto ' "$ledger" | tail -1 | grep -q 'state=off reason=two-no-idea'; } \
  && ok || bad "(k) on->off transition: [$out] $(grep '^<!-- track:predict-auto' "$ledger")"

total=$((pass + fail))
echo "breakpoint tests ($runner): $pass/$total passed"
[ "$fail" -eq 0 ]
