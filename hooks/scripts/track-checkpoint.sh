#!/usr/bin/env bash
# track-checkpoint.sh — advisory decision checkpoints for tracked /oss sessions.
#
# Registered as a SEPARATE PreToolUse hook for Edit|Write|MultiEdit|NotebookEdit. It is NOT the
# draft-only safety guard (guard-outbound.sh) and never replaces it. It fails OPEN: any internal
# error means "no output, exit 0", which Claude Code treats as allow.
#
# Opt-in per session: it does nothing (no output, no subprocess) unless
# <root>/.oss-drafts/.track-active exists. The no-session path uses only bash builtins.
#
# Output: one JSON object on stdout with hookSpecificOutput, always exit 0.
#   deny            ask the user a "choose" question and record it in the ledger, then retry
#   allow + context over budget / loop fallback: log it, do not ask
#   allow           ONLY Edit on exactly the active ledger file (so a checkpoint costs one
#                   interruption, not two); see decision-ledger.md section 8
#
# Format, ids, budget and loop rules: skills/pr-preparation/references/decision-ledger.md
#
# Must run on macOS default bash 3.2: no mapfile, no ${x,,}, no associative arrays.

set -u
set -f # never glob-expand patterns such as scope globs

[ "${OSS_TRACK_DISABLE:-}" = 1 ] && exit 0

IFS= read -r -d '' input || true
[ -n "$input" ] || exit 0

# ── FAST PATH: locate a session pointer using only builtins ──────────────────
# >>> shared:find-root (keep byte-identical in track-breakpoint.sh; checked by run-breakpoint-tests.sh)
find_root() { # $1 = start dir; walks up to the first .git boundary
  local d="$1" nd
  case "$d" in /*) ;; *) return 1 ;; esac
  while [ -n "$d" ]; do
    if [[ -f "$d/.oss-drafts/.track-active" ]]; then
      root="$d"
      return 0
    fi
    [[ -e "$d/.git" ]] && return 1
    [ "$d" = "/" ] && return 1
    nd="${d%/*}"
    [ -z "$nd" ] && nd="/"
    d="$nd"
  done
  return 1
}
# <<< shared:find-root

re_path='"(file_path|notebook_path)"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
re_cwd='"cwd"[[:space:]]*:[[:space:]]*"([^"\\]*)"'
fp=""
cwd=""
if [[ $input =~ $re_path ]]; then fp="${BASH_REMATCH[2]}"; fi
if [[ $input =~ $re_cwd ]]; then cwd="${BASH_REMATCH[1]}"; fi
if [ -n "$fp" ] && [ "${fp#/}" = "$fp" ] && [ -n "$cwd" ]; then fp="$cwd/$fp"; fi

root=""
for start in "${fp%/*}" "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
  [ -n "$start" ] && find_root "$start" && break
done
[ -z "$root" ] && exit 0

# ── SLOW PATH: a session pointer exists. Any failure below fails open. ───────
# >>> shared:pointer (keep byte-identical in track-breakpoint.sh; checked by run-breakpoint-tests.sh)
rel_ledger=""
IFS= read -r rel_ledger < "$root/.oss-drafts/.track-active" || [ -n "$rel_ledger" ] || exit 0
re_ptr='^\.oss-drafts/track-[A-Za-z0-9._-]+\.md$'
[[ $rel_ledger =~ $re_ptr ]] || exit 0
case "$rel_ledger" in *..*) exit 0 ;; esac
ledger="$root/$rel_ledger"
# Pointer, directory and ledger must be real (non-symlink) paths.
[[ -L "$root/.oss-drafts" || -L "$root/.oss-drafts/.track-active" || -L "$ledger" ]] && exit 0
[[ -f "$ledger" ]] || exit 0
# <<< shared:pointer

# Frontmatter (builtin reads, no fork).
fm_plugin=""; fm_mode=""; fm_status=""; fm_scope=""; fm_api=""; fm_budget=""
n=0
while IFS= read -r line; do
  n=$((n + 1))
  if [ "$n" -eq 1 ]; then
    [ "$line" = "---" ] || exit 0
    continue
  fi
  [ "$line" = "---" ] && break
  [ "$n" -gt 80 ] && break
  case "$line" in
    "plugin: "*) v="${line#plugin: }"; fm_plugin="${v%%[[:space:]]*}" ;;
    "mode: "*) v="${line#mode: }"; fm_mode="${v%%[[:space:]]*}" ;;
    "status: "*) v="${line#status: }"; fm_status="${v%%[[:space:]]*}" ;;
    "budget: "*) v="${line#budget: }"; fm_budget="${v%%[[:space:]]*}" ;;
    "scope: "*) fm_scope="${line#scope: }" ;;
    "api_paths: "*) fm_api="${line#api_paths: }" ;;
  esac
done < "$ledger"
[ "$fm_plugin" = "agentic-contributor" ] && [ "$fm_mode" = "track" ] || exit 0

# >>> shared:clean-list (keep byte-identical in track-breakpoint.sh; checked by run-breakpoint-tests.sh)
clean_list() { # strip comment, brackets, quotes
  local v="${1%%#*}"
  v="${v//\[/}"
  v="${v//\]/}"
  v="${v//\"/}"
  printf '%s' "$v"
}
# <<< shared:clean-list
fm_scope="$(clean_list "$fm_scope")"
fm_api="$(clean_list "$fm_api")"
case "$fm_budget" in '' | *[!0-9]*) fm_budget=3 ;; esac

ASSERT_RE='\bassert[A-Za-z_]*\b|XCTAssert|\bexpect\s*\(|\b(?:it|test|describe|context)\s*\(|\bdef\s+test_|\bfunc\s+Test|#\[test\]|@Test\b|\bt\.(?:Error|Fatal)f?\s*\(|\brequire\.[A-Z][A-Za-z]*\s*\('
SKIP_RE='@pytest\.mark\.(?:skip|xfail)|\b(?:xit|xdescribe|xtest)\s*\(|\.skip\s*\(|@Disabled\b|@Ignore\b|#\[ignore\]|\bt\.Skip|\bskipTest\b|unittest\.skip'

have_jq=0
have_py=0
command -v jq > /dev/null 2>&1 && have_jq=1
command -v python3 > /dev/null 2>&1 && have_py=1
[ "$have_jq" -eq 1 ] || [ "$have_py" -eq 1 ] || exit 0

# parse_input: prints US-separated tool, path, permission_mode, old/new assert, old/new skip counts.
parse_input() {
  if [ "$have_jq" -eq 1 ]; then
    printf '%s' "$input" | jq -r --arg a "$ASSERT_RE" --arg s "$SKIP_RE" '
      def cnt($re): [match($re; "g")] | length;
      . as $d | ($d.tool_input // {}) as $ti | ($d.tool_name // "") as $t
      | (if $t == "Edit" then [$ti] elif $t == "MultiEdit" then ($ti.edits // []) else [] end) as $es
      | ($es | map((.old_string // "") | cnt($a)) | add // 0) as $oa
      | ($es | map((.new_string // "") | cnt($a)) | add // 0) as $na
      | ($es | map((.old_string // "") | cnt($s)) | add // 0) as $os
      | ($es | map((.new_string // "") | cnt($s)) | add // 0) as $ns
      | (if $t == "Write" then (($ti.content // "") | cnt($a)) else $na end) as $na2
      | (if $t == "Write" then (($ti.content // "") | cnt($s)) else $ns end) as $ns2
      | [$t, ($ti.file_path // $ti.notebook_path // ""), ($d.permission_mode // ""),
         $oa, $na2, $os, $ns2] | map(tostring) | join("\u001f")' 2> /dev/null
  else
    printf '%s' "$input" | python3 -c '
import sys, json, re
A = re.compile(sys.argv[1]); S = re.compile(sys.argv[2])
d = json.load(sys.stdin)
ti = d.get("tool_input") or {}
t = d.get("tool_name") or ""
es = [ti] if t == "Edit" else (ti.get("edits") or [] if t == "MultiEdit" else [])
def tot(rx, k): return sum(len(rx.findall(e.get(k) or "")) for e in es)
oa, na, os_, ns = tot(A, "old_string"), tot(A, "new_string"), tot(S, "old_string"), tot(S, "new_string")
if t == "Write":
    c = ti.get("content") or ""
    na, ns = len(A.findall(c)), len(S.findall(c))
p = ti.get("file_path") or ti.get("notebook_path") or ""
print("\x1f".join([t, p, d.get("permission_mode") or "", str(oa), str(na), str(os_), str(ns)]))
' "$ASSERT_RE" "$SKIP_RE" 2> /dev/null
  fi
}

count_file() { # $1 file, $2 regex -> match count on stdout
  if [ "$have_jq" -eq 1 ]; then
    jq -Rs --arg re "$2" '[match($re; "g")] | length' < "$1" 2> /dev/null
  else
    python3 -c '
import sys, re
print(len(re.findall(sys.argv[1], open(sys.argv[2], errors="replace").read())))
' "$2" "$1" 2> /dev/null
  fi
}

parsed="$(parse_input)" || exit 0
[ -n "$parsed" ] || exit 0
IFS=$'\037' read -r tool_name path perm_mode old_a new_a old_s new_s <<< "$parsed"
[ -n "$path" ] || exit 0
[ "$perm_mode" = "plan" ] && exit 0

abs="$path"
if [ "${abs#/}" = "$abs" ]; then
  [ -n "$cwd" ] || exit 0
  abs="$cwd/$abs"
fi

emit() { # $1 decision, $2 reason (may be empty), $3 additionalContext (may be empty)
  if [ "$have_jq" -eq 1 ]; then
    jq -n --arg d "$1" --arg r "$2" --arg c "$3" '
      {hookSpecificOutput: ({hookEventName: "PreToolUse"}
        + (if $d != "" then {permissionDecision: $d} else {} end)
        + (if $r != "" then {permissionDecisionReason: $r} else {} end)
        + (if $c != "" then {additionalContext: $c} else {} end))}' 2> /dev/null
  else
    python3 -c '
import sys, json
o = {"hookEventName": "PreToolUse"}
if sys.argv[1]: o["permissionDecision"] = sys.argv[1]
if sys.argv[2]: o["permissionDecisionReason"] = sys.argv[2]
if sys.argv[3]: o["additionalContext"] = sys.argv[3]
print(json.dumps({"hookSpecificOutput": o}))
' "$1" "$2" "$3" 2> /dev/null
  fi
  exit 0
}

# Auto-allow: Edit, exact byte-for-byte path of the active ledger, no ".." segment.
case "$abs" in
  */.oss-drafts/*)
    if [ "$tool_name" = "Edit" ] && [ "$abs" = "$ledger" ]; then
      case "$path" in *..*) exit 0 ;; esac
      emit allow "agentic-contributor: append to the active decision ledger" ""
    fi
    exit 0
    ;;
esac

[ "$fm_status" = "active" ] || exit 0

rel="${abs#"$root"/}"
[ "$rel" = "$abs" ] && exit 0

# ── classify (first match wins): test -> dependency -> api -> scope ──────────
base="${rel##*/}"
dir=""
case "$rel" in */*) dir="${rel%/*}/" ;; esac

re_testdir='(^|/)(tests?|__tests__|specs?|testing)/'
re_testfile='^test_.*\.py$|_test\.(py|go|rb|exs?|dart)$|\.(test|spec)\.(m?[jt]sx?|cjs)$|(Tests?|IT)\.(java|kt|scala|cs)$|_spec\.rb$|Tests?\.swift$'
is_test_path() { [[ $1 =~ $re_testdir ]] || [[ ${1##*/} =~ $re_testfile ]]; }

# >>> shared:manifest-map (keep byte-identical in track-breakpoint.sh; checked by run-breakpoint-tests.sh)
manifest_for() { # echoes the manifest basename if $1 is a dependency file, else nothing
  case "$1" in
    yarn.lock | package-lock.json | pnpm-lock.yaml | npm-shrinkwrap.json | bun.lockb) echo package.json ;;
    Cargo.lock) echo Cargo.toml ;;
    go.sum) echo go.mod ;;
    poetry.lock | uv.lock) echo pyproject.toml ;;
    Gemfile.lock) echo Gemfile ;;
    Pipfile.lock) echo Pipfile ;;
    composer.lock) echo composer.json ;;
    mix.lock) echo mix.exs ;;
    Package.resolved) echo Package.swift ;;
    package.json | Cargo.toml | go.mod | pyproject.toml | setup.py | setup.cfg | Pipfile | Gemfile | \
      pom.xml | build.gradle | build.gradle.kts | settings.gradle | settings.gradle.kts | \
      libs.versions.toml | composer.json | mix.exs | Package.swift | packages.config | \
      Directory.Packages.props | environment.yml | requirements*.txt | constraints*.txt | \
      *.gemspec | *.csproj) echo "$1" ;;
  esac
}
# <<< shared:manifest-map

# >>> shared:glob-match (keep byte-identical in track-breakpoint.sh; checked by run-breakpoint-tests.sh)
glob_match() { # $1 rel, $2 comma list
  local g list="$2" IFS=,
  for g in $list; do
    while [ "${g# }" != "$g" ]; do g="${g# }"; done
    while [ "${g% }" != "$g" ]; do g="${g% }"; done
    [ -n "$g" ] || continue
    if [ "${g%/}" != "$g" ] && [ "${1#"$g"}" != "$1" ]; then return 0; fi
    # shellcheck disable=SC2053 # unquoted RHS: glob match is intended
    [[ $1 == $g ]] && return 0
  done
  return 1
}
# <<< shared:glob-match

class=""
key="$rel"
trig=""
if is_test_path "$rel" && { [ "$tool_name" = "Edit" ] || [ "$tool_name" = "MultiEdit" ] || [ "$tool_name" = "Write" ]; }; then
  if [ "$tool_name" = "Write" ]; then
    if [ -f "$abs" ]; then
      old_a="$(count_file "$abs" "$ASSERT_RE")"
      old_s="$(count_file "$abs" "$SKIP_RE")"
    else
      old_a=0; old_s=0; new_a=0; new_s=0 # a new test file never triggers
    fi
  fi
  case "$old_a$new_a$old_s$new_s" in '' | *[!0-9]*) exit 0 ;; esac
  if [ "$new_a" -lt "$old_a" ] || [ "$new_s" -gt "$old_s" ]; then
    class="test"
    trig="the edit lowers assertions in a test file (asserts $old_a->$new_a, skips $old_s->$new_s)."
  fi
fi
if [ -z "$class" ]; then
  m="$(manifest_for "$base")"
  if [ -n "$m" ]; then
    class=dependency
    key="$dir$m"
    trig="the edit touches dependency manifest $key (a lock file counts as its manifest)."
  fi
fi
if [ -z "$class" ] && [ -n "$fm_api" ] && glob_match "$rel" "$fm_api"; then
  class=api
  trig="$rel is listed in the session's api_paths (public API/config)."
fi
if [ -z "$class" ] && [ -n "$fm_scope" ] && ! glob_match "$rel" "$fm_scope"; then
  class=scope
  trig="$rel is outside the session scope ($fm_scope)."
fi
[ -z "$class" ] && exit 0
id="$class:$key"

# ── lock: reading state, checking the budget and appending a pending marker are one step,
# so parallel edits cannot both spend the same budget slot. Fail open if the lock is busy.
# >>> shared:lock (keep byte-identical in track-breakpoint.sh; checked by run-breakpoint-tests.sh)
lock="$ledger.lock"
tries=0
until mkdir "$lock" 2> /dev/null; do
  # a lock older than ~10s is stale (a crashed hook); remove it once and retry
  lt="$(stat -f %m "$lock" 2> /dev/null || stat -c %Y "$lock" 2> /dev/null)"
  case "$lt" in '' | *[!0-9]*) ;; *) [ $(($(date +%s) - lt)) -gt 10 ] && rmdir "$lock" 2> /dev/null ;; esac
  tries=$((tries + 1))
  [ "$tries" -ge 20 ] && exit 0
  sleep 0.1 2> /dev/null || exit 0
done
trap 'rmdir "$lock" 2> /dev/null' EXIT
# <<< shared:lock

now="$(date -u +%Y-%m-%dT%H:%M:%SZ 2> /dev/null)" || exit 0

# ── ledger state: settled / over-logged / pending count / asked ──────────────
state="$(TRACK_ID="$id" TRACK_NOW="$now" awk '
function lastid(l,   q, res, found) {
  if (substr(l, length(l) - 3) != " -->") return "\001"
  l = substr(l, 1, length(l) - 4); found = 0; res = ""
  while ((q = index(l, " id=")) > 0) { l = substr(l, q + 4); res = l; found = 1 }
  return found ? res : "\001"
}
# Normalise at= to YYYY-MM-DDTHH:MM:SSZ (fractional seconds dropped). A missing, malformed or
# future value sorts as "0" (oldest), so it can never outrank later markers: errors lean toward asking.
function atof(l,   q, r) {
  q = index(l, " at="); if (!q) return "0"
  r = substr(l, q + 4); sub(/[ ].*/, "", r)
  sub(/\.[0-9]+Z$/, "Z", r)
  if (r !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$/) return "0"
  if (r > ENVIRON["TRACK_NOW"]) return "0"
  return r
}
/^<!-- track:pending / { i = lastid($0); if (i != "\001") { n++; pid[n] = i; pat[n] = atof($0); a = atof($0); if (!(i in lp) || a > lp[i]) lp[i] = a } }
/^<!-- track:consumed / { i = lastid($0); if (i != "\001") { a = atof($0); if (!(i in cons) || a > cons[i]) cons[i] = a } }
/^<!-- track:entry /   {
  i = lastid($0); if (i == "\001") next
  if (index($0, " status=not-applicable ")) { a = atof($0); if (!(i in na) || a > na[i]) na[i] = a; next }
  if (index($0, " status=decided ") || index($0, " status=skipped ")) settled[i] = 1
  else if (index($0, " status=logged-over-budget ")) over[i] = 1
  if (index($0, " asked=no ")) exempt[i] = 1
}
END {
  t = ENVIRON["TRACK_ID"]; asked = 0
  # a not-applicable entry clears only pendings at or before its own time, wherever it sits in the file
  for (k = 1; k <= n; k++) { i = pid[k]; if (!(i in na) || pat[k] > na[i]) pend[i]++ }
  for (i in pend) if (pend[i] > 0) { asked++; if (i in exempt) asked-- }
  # unconsumed acknowledgement: a not-applicable entry at or after the latest pending for the id, not yet used to pass an edit
  ack = 0
  if ((t in na) && (!(t in lp) || lp[t] <= na[t]) && !((t in cons) && cons[t] >= na[t])) ack = 1
  print ((t in settled) ? 1 : 0), ((t in over) ? 1 : 0), ((t in pend) ? pend[t] : 0), asked, ack
}' "$ledger" 2> /dev/null)" || exit 0
read -r settled over pend_n asked ack <<< "$state"
case "$settled$over$pend_n$asked$ack" in '' | *[!0-9]*) exit 0 ;; esac

[ "$settled" -eq 1 ] && exit 0
[ "$over" -eq 1 ] && exit 0

append() { printf '%s\n' "$@" >> "$ledger" 2> /dev/null || true; }

# not-applicable acknowledgement: let this one edit through silently and mark it used,
# so a later real change to the same id is checkpointed again
if [ "$ack" -eq 1 ]; then
  append "<!-- track:consumed at=$now id=$id -->"
  exit 0
fi

# budget 0 is quiet mode: never ask or retry, even with a pending marker
if [ "$fm_budget" -eq 0 ] || { [ "$pend_n" -eq 0 ] && [ "$asked" -ge "$fm_budget" ]; }; then
  append "<!-- track:entry status=logged-over-budget source=hook asked=no at=$now id=$id -->" \
    "- logged-over-budget: $class — $rel ($now), not asked; budget $fm_budget spent"
  emit "" "" "[agentic-contributor · tracked session] Checkpoint budget $fm_budget/$fm_budget is spent. Logged $id ($class, $rel) to $rel_ledger as logged-over-budget without asking. It will appear as an Unknown in the debrief. Continue, and mention it to the user when you finish."
fi

if [ "$pend_n" -ge 2 ]; then
  append "<!-- track:entry status=skipped source=hook asked=yes reason=no-ledger-entry at=$now id=$id -->" \
    "- skipped (no ledger entry recorded after 2 checkpoint prompts): $class — $rel"
  emit "" "" "[agentic-contributor · tracked session] No ledger entry for $id after 2 checkpoint prompts. The hook recorded it as skipped and allowed this edit. Tell the user that this decision was not recorded."
fi

retry=""
if [ "$pend_n" -eq 1 ]; then
  k="$asked"
  retry="No ledger entry with id=$id was found after the previous prompt. Write it exactly as below before retrying."
else
  k=$((asked + 1))
fi
append "<!-- track:pending at=$now id=$id -->"

case "$class" in
  test)
    question="How should this test change be handled?"
    opts="keep the tests and change the code / update the assertions to the new behaviour / remove or skip the test (state why)" ;;
  dependency)
    question="Add or change this dependency?"
    opts="use it / implement without it / use an existing dependency" ;;
  api)
    question="How should this public API/config change land?"
    opts="backward-compatible / breaking with a migration note / avoid the change" ;;
  *)
    question="This file is outside the task scope. What should happen?"
    opts="proceed and add <dir>/** to scope (edit scope: in the ledger frontmatter) / proceed for this file only / leave it and stay in scope" ;;
esac
depnote=""
if [ "$class" = dependency ]; then
  depnote=" If this edit changes no dependency (only scripts, version, or metadata), do not ask: record the entry with status=not-applicable (not decided, so later real dependency changes still get a checkpoint), chosen: not-a-dependency-change, decided_by: agent, asked=no, and give the reason in your own words."
fi
nl=$'\n'
reason="[agentic-contributor · tracked session] Decision checkpoint $k/$fm_budget before this $tool_name on $rel.${nl}Trigger: $trig${nl}Checkpoint id: $id"
[ -n "$retry" ] && reason="$reason${nl}$retry"
reason="$reason${nl}${nl}Do this, then retry the same edit unchanged:${nl}1. Ask the user with AskUserQuestion: ONE question, \"$question\", with 2-3 options (suggested: $opts). Each option gets a one-line trade-off. Put your recommendation first and mark it \"(Recommended)\". The last option is \"Skip — decide later\". Ask them to choose, not to approve or deny.$depnote${nl}2. Read $ledger, then use Edit to replace the line \`<!-- track:end -->\` with this entry followed by \`<!-- track:end -->\`:${nl}### $id · <UTC now>${nl}<!-- track:entry status=<decided|skipped> source=checkpoint asked=<yes|no> at=<UTC now> id=$id -->${nl}- trigger: $class — $rel${nl}- files: $rel${nl}- options: A) … | B) … | C) Skip — decide later${nl}- chosen: <letter|Skip>${nl}- decided_by: <user-on-recommendation if they picked your recommendation | user otherwise>${nl}- reason: <the user's own words, verbatim, or TODO(you) if they gave none>${nl}   Use status=skipped (reason: TODO(you)) if they pick Skip.${nl}3. If AskUserQuestion is unavailable (non-interactive run or subagent): write the entry with status=skipped, chosen: none, decided_by: agent, reason: non-interactive.${nl}4. If the user's choice means not making this edit, do not retry. Follow their choice.${nl}Write \"decided_by: user…\" only if the user actually answered. The ledger is private: never copy it into any sendable text."
emit deny "$reason" ""
