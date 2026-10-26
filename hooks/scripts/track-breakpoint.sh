#!/usr/bin/env bash
# track-breakpoint.sh — advisory scope-drift alerts and explain-back breakpoint questions for
# tracked /oss sessions.
#
# Registered as a SEPARATE hook on two events:
#   PostToolUse (Edit|Write|MultiEdit|NotebookEdit)  log the edit; throttled scope-drift check;
#                                                    a new alert is delivered as additionalContext
#                                                    (never a block, never a revert)
#   Stop                                             drift check once per turn end, then at most ONE
#                                                    explain-back question; delivered as a block so
#                                                    the agent asks the user before it finishes
# It is NOT the draft-only safety guard (guard-outbound.sh) and never replaces it. It fails OPEN:
# any internal error means "no output, exit 0". It never edits code, reverts, stashes, or runs git
# commands that write.
#
# Opt-in per session: it does nothing (no output, no subprocess, stdin not read) unless the
# session pointer <gitdir>/agentic-contributor/track-active exists for the repository that
# contains $CLAUDE_PROJECT_DIR (or $PWD); see track-checkpoint.sh. The no-session path uses only
# bash builtins.
#
# Ledger text (scope, drift_source, any frontmatter value) is never echoed into the output: it is
# repository-writable data, so echoing it would be a prompt-injection channel. File paths named in
# the output come from git and the hook input, with control characters rejected or replaced.
#
# Format, ids, caps and loop rules: skills/pr-preparation/references/decision-ledger.md (sections
# 11-14). Blocks between "# --- shared: <name> (keep identical in track-*.sh) ---" and
# "# --- end shared ---" are copied byte for byte from track-checkpoint.sh and checked by
# hooks/tests/run-breakpoint-tests.sh.
#
# Must run on macOS default bash 3.2: no mapfile, no ${x,,}, no associative arrays.

set -u
set -f # never glob-expand patterns such as scope globs

[ "${OSS_TRACK_DISABLE:-}" = 1 ] && exit 0

# --- shared: session lookup (keep identical in track-*.sh) ---
# Builtins only. trk_find_session sets trk_root (worktree root), trk_gitdir, trk_ptr,
# trk_rel_ledger (".oss-drafts/track-*.md") and trk_ledger (absolute); returns 1 when there is
# no valid session. Callers exit 0 with no output on 1 (fail open).
trk_find_repo() { # $1 absolute start dir -> trk_root, trk_gitdir (worktree/submodule .git files ok)
  local d="$1" nd line
  case "$d" in /*) ;; *) return 1 ;; esac
  while [ "$d" != "/" ] && [ "${d%/}" != "$d" ]; do d="${d%/}"; done
  while :; do
    if [[ -d "$d/.git" ]]; then
      trk_root="$d"
      trk_gitdir="$d/.git"
      return 0
    fi
    if [[ -f "$d/.git" ]]; then
      line=""
      IFS= read -r line < "$d/.git" || [ -n "$line" ] || return 1
      line="${line%$'\r'}"
      case "$line" in "gitdir: "?*) line="${line#gitdir: }" ;; *) return 1 ;; esac
      case "$line" in /*) ;; *) line="$d/$line" ;; esac # relative to the .git file's dir
      trk_root="$d"
      trk_gitdir="$line"
      return 0
    fi
    [ "$d" = "/" ] && return 1
    nd="${d%/*}"
    [ -z "$nd" ] && nd="/"
    d="$nd"
  done
}
trk_find_session() {
  local s p re='^\.oss-drafts/track-[A-Za-z0-9._-]+\.md$'
  trk_root=""; trk_gitdir=""; trk_ptr=""; trk_rel_ledger=""; trk_ledger=""
  for s in "${CLAUDE_PROJECT_DIR:-}" "${PWD:-}"; do
    [ -n "$s" ] || continue
    trk_find_repo "$s" || continue
    trk_ptr="$trk_gitdir/agentic-contributor/track-active"
    [[ -f "$trk_ptr" ]] && break
    trk_ptr=""
  done
  [ -n "$trk_ptr" ] || return 1
  # The pointer must be a real file naming a ledger inside this worktree's .oss-drafts/.
  [[ -L "$trk_ptr" ]] && return 1
  p=""
  IFS= read -r p < "$trk_ptr" || [ -n "$p" ] || return 1
  p="${p%$'\r'}"
  case "$p" in "$trk_root"/*) p="${p#"$trk_root"/}" ;; esac # absolute path inside the root is ok
  [[ $p =~ $re ]] || return 1
  case "$p" in *..*) return 1 ;; esac
  trk_rel_ledger="$p"
  trk_ledger="$trk_root/$p"
  # Directory and ledger must be real (non-symlink) paths, so the ledger cannot leave the root.
  [[ -L "$trk_root/.oss-drafts" || -L "$trk_ledger" ]] && return 1
  [[ -f "$trk_ledger" ]] || return 1
  return 0
}
# --- end shared ---

# --- shared: path normalize (keep identical in track-*.sh) ---
# Lexical normalisation (collapse //, ./, ..), then a repo-relative path. trk_relpath sets trk_rel
# ("" when the path is outside the repository). The cheap lexical comparison runs first; the
# physical (pwd -P) comparison, which forks, runs only when it misses, so a symlinked
# CLAUDE_PROJECT_DIR and a real-path file_path (or the reverse) still agree.
trk_norm() { # $1 absolute path -> trk_np
  local IFS=/ c out=""
  for c in $1; do
    case "$c" in '' | .) ;; ..) out="${out%/*}" ;; *) out="$out/$c" ;; esac
  done
  trk_np="${out:-/}"
}
trk_under() { # $1 normalized path, $2 normalized root -> trk_rel on success
  case "$1" in "$2"/*) trk_rel="${1#"$2"/}"; return 0 ;; esac
  return 1
}
trk_relpath() { # $1 absolute path -> trk_rel
  local a r ra p suffix pa full
  trk_rel=""
  trk_norm "$1"; a="$trk_np"
  trk_norm "$trk_root"; r="$trk_np"
  trk_under "$a" "$r" && return 0
  ra="$(cd "$trk_root" 2> /dev/null && pwd -P)" || ra=""
  [ -n "$ra" ] && trk_under "$a" "$ra" && return 0
  # physical path of the nearest existing ancestor (the file itself may not exist yet)
  p="$a"; suffix=""
  while :; do
    pa="$(cd "${p:-/}" 2> /dev/null && pwd -P)" && break
    [ -n "$p" ] || return 0
    suffix="/${p##*/}$suffix"
    p="${p%/*}"
  done
  full="${pa%/}$suffix"
  trk_under "$full" "$r" && return 0
  [ -n "$ra" ] && trk_under "$full" "$ra" && return 0
  return 0
}
# --- end shared ---

# ── FAST PATH: no session pointer -> exit before reading stdin (builtins only) ──
trk_find_session || exit 0

# ── SLOW PATH: a session pointer exists. Any failure below fails open. ───────
input="$(cat 2> /dev/null)" || exit 0
[ -n "$input" ] || exit 0
re_ev='"hook_event_name"[[:space:]]*:[[:space:]]*"(PostToolUse|Stop)"'
[[ $input =~ $re_ev ]] || exit 0
ev="${BASH_REMATCH[1]}"
if [ "$ev" = Stop ]; then
  re_sha='"stop_hook_active"[[:space:]]*:[[:space:]]*true'
  [[ $input =~ $re_sha ]] && exit 0 # loop guard before any parsing or subprocess
fi
root="$trk_root"
ledger="$trk_ledger"
rel_ledger="$trk_rel_ledger"

state="${ledger%.md}.state"
[[ -L "$state" ]] && exit 0

# Frontmatter (builtin reads, no fork).
fm_plugin=""; fm_mode=""; fm_status=""; fm_scope=""; fm_budget=""; fm_base=""
fm_dl=""; fm_df=""; fm_dmax=""; fm_emax=""; fm_eint=""; fm_dsrc=""
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
    "base_commit: "*) v="${line#base_commit: }"; fm_base="${v%%[[:space:]]*}" ;;
    "drift_lines: "*) v="${line#drift_lines: }"; fm_dl="${v%%[[:space:]]*}" ;;
    "drift_files: "*) v="${line#drift_files: }"; fm_df="${v%%[[:space:]]*}" ;;
    "drift_max: "*) v="${line#drift_max: }"; fm_dmax="${v%%[[:space:]]*}" ;;
    "drift_source: "*) v="${line#drift_source: }"; fm_dsrc="${v%%[[:space:]]*}" ;;
    "explain_max: "*) v="${line#explain_max: }"; fm_emax="${v%%[[:space:]]*}" ;;
    "explain_interval_min: "*) v="${line#explain_interval_min: }"; fm_eint="${v%%[[:space:]]*}" ;;
    "scope: "*) fm_scope="${line#scope: }" ;;
  esac
done < "$ledger"
[ "$fm_plugin" = "agentic-contributor" ] && [ "$fm_mode" = "track" ] || exit 0
[ "$fm_status" = "active" ] || exit 0

# --- shared: list cleaning (keep identical in track-*.sh) ---
clean_list() { # strip comment, brackets, quotes
  local v="${1%%#*}"
  v="${v//\[/}"
  v="${v//\]/}"
  v="${v//\"/}"
  printf '%s' "$v"
}
# --- end shared ---
fm_scope="$(clean_list "$fm_scope")"

int_or() { # $1 value, $2 default
  case "$1" in '' | *[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac
}
budget="$(int_or "$fm_budget" 3)"
drift_lines="$(int_or "$fm_dl" 400)"
drift_files="$(int_or "$fm_df" 10)"
drift_max="$(int_or "$fm_dmax" 2)"
explain_max="$(int_or "$fm_emax" 4)"
explain_int="$(int_or "$fm_eint" 20)"
# drift_source is ledger text: only a fixed label derived from it is ever shown
case "${fm_dsrc:-default}" in
  default) drift_src_label="default" ;;
  user) drift_src_label="set by the user" ;;
  contributing:*) drift_src_label="from the project's CONTRIBUTING file" ;;
  *) drift_src_label="from the ledger" ;;
esac
base=""
re_sha7='^[0-9a-f]{7,64}$'
[[ $fm_base =~ $re_sha7 ]] && base="$fm_base"

have_jq=0
have_py=0
command -v jq > /dev/null 2>&1 && have_jq=1
command -v python3 > /dev/null 2>&1 && have_py=1
[ "$have_jq" -eq 1 ] || [ "$have_py" -eq 1 ] || exit 0

# parse_input: US-separated event, path, permission_mode, session_id, stop_hook_active, agent_id,
# asking (1/0), cwd. Any field containing a control character (newline, CR, US, ...) is printed as
# empty, so it can neither shift the fields nor forge ledger/state lines. "asking" is 1 when the
# last assistant message already waits on the user: its last non-blank line (trailing markdown
# emphasis, quotes and brackets ignored) ends in ? or a full-width question mark, or it ends in an
# option list whose lead-in line does (the last 40 non-blank lines are examined).
# last_assistant_message (Stop) and agent_id (PostToolUse in a subagent) need a Claude Code version
# that sends them; without them the "already asking" and subagent checks simply never fire.
parse_input() {
  if [ "$have_jq" -eq 1 ]; then
    printf '%s' "$input" | jq -r '
      def clean: tostring | if test("[\u0000-\u001f\u007f]") then "" else . end;
      def endsq: test("[?\uff1f]$");
      def item: test("^\\s*([0-9]+[.)]|[-*\u2022+]|\\(?[A-Za-z][.)])\\s+");
      def asking:
        ((. // "") | tostring | split("\n") | .[-40:]
         | map(select(test("[^\\s]")) | sub("[\\s*_\\\\`~\"\u0027\u2019\u201d\u00bb)\\]]+$"; ""))) as $L
        | ($L | length) as $n
        | if $n == 0 then false
          elif ($L[-1] | endsq) then true
          else ([range(0; $n)] | map(select(($L[.] | item) | not)) | last) as $j
            | if $j == null or $j == ($n - 1) then false else ($L[$j] | endsq) end
          end;
      (.tool_input // {}) as $ti
      | [(.hook_event_name // ""), ($ti.file_path // $ti.notebook_path // ""), (.permission_mode // ""),
         (.session_id // ""), ((.stop_hook_active // false) | tostring), (.agent_id // ""),
         (.last_assistant_message | asking | if . then "1" else "0" end), (.cwd // "")]
      | map(clean) | join("\u001f")' 2> /dev/null
  else
    printf '%s' "$input" | python3 -c '
import sys, json, re
d = json.load(sys.stdin)
ti = d.get("tool_input") or {}
def clean(v):
    v = str(v or "")
    return "" if re.search("[\x00-\x1f\x7f]", v) else v
def asking(m):
    ls = [re.sub("[\\s*_\\\\`~\"\x27\u2019\u201d\u00bb)\\]]+$", "", l) for l in str(m or "").split("\n")[-40:] if l.strip()]
    if not ls:
        return "0"
    endsq = lambda l: l[-1:] in ("?", "\uff1f")
    if endsq(ls[-1]):
        return "1"
    item = lambda l: re.search("^\\s*([0-9]+[.)]|[-*\u2022+]|\\(?[A-Za-z][.)])\\s+", l)
    j = max([i for i, l in enumerate(ls) if not item(l)], default=None)
    return "1" if j is not None and j < len(ls) - 1 and endsq(ls[j]) else "0"
print("\x1f".join(clean(v) for v in [d.get("hook_event_name"), ti.get("file_path") or ti.get("notebook_path"),
  d.get("permission_mode"), d.get("session_id"),
  "true" if d.get("stop_hook_active") else "false", d.get("agent_id"), asking(d.get("last_assistant_message")), d.get("cwd")]))
' 2> /dev/null
  fi
}

parsed="$(parse_input)" || exit 0
[ -n "$parsed" ] || exit 0
IFS=$'\037' read -r p_ev path perm_mode sid sha_active agent_id asking cwd <<< "$parsed"
case "$path$cwd" in *[[:cntrl:]]*) exit 0 ;; esac # belt and braces: never log a control char
[ "$p_ev" = "$ev" ] || exit 0
[ "$perm_mode" = "plan" ] && exit 0
[ "$ev" = Stop ] && [ "$sha_active" = true ] && exit 0
[ "$ev" = PostToolUse ] && [ -z "$path" ] && exit 0 # missing, or rejected for a control character
re_sid='^[A-Za-z0-9._-]+$'
if ! [[ $sid =~ $re_sid ]]; then sid="-"; fi

# ── helpers ──────────────────────────────────────────────────────────────────
# --- shared: manifest map (keep identical in track-*.sh) ---
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
# --- end shared ---

# --- shared: glob match (keep identical in track-*.sh) ---
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
# --- end shared ---

enc() { # percent-encode % space comma (builtins only)
  local s="$1"
  s="${s//%/%25}"
  s="${s// /%20}"
  s="${s//,/%2C}"
  printf '%s' "$s"
}

gitq() { # read-only git: no index.lock, literal pathspecs, no external diff drivers
  GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 git -C "$root" -c core.quotepath=off "$@"
}

# awk helper: decode Git's C-style quoted paths (core.quotepath=off still quotes \" and \\)
AWK_DQ='function dq(s,   o, i, c, n, m) {
  if (substr(s, 1, 1) != "\"" || length(s) < 2 || substr(s, length(s), 1) != "\"") return s
  s = substr(s, 2, length(s) - 2); o = ""; i = 1; n = length(s)
  while (i <= n) {
    c = substr(s, i, 1)
    if (c != "\\") { o = o c; i++; continue }
    i++; c = substr(s, i, 1)
    if (c ~ /[0-7]/) {
      m = c; i++
      while (length(m) < 3 && substr(s, i, 1) ~ /[0-7]/) { m = m substr(s, i, 1); i++ }
      o = o sprintf("%c", (substr(m, 1, 1) * 64 + (length(m) > 1 ? substr(m, 2, 1) * 8 : 0) + (length(m) > 2 ? substr(m, 3, 1) : 0)))
      continue
    }
    i++
    if (c == "t") o = o "\t"; else if (c == "n") o = o "\n"; else if (c == "a") o = o "\007"
    else if (c == "b") o = o "\b"; else if (c == "f") o = o "\f"; else if (c == "r") o = o "\r"
    else if (c == "v") o = o "\013"; else o = o c
  }
  return o
}'

emit_json() { # $1 = post|stop|note, $2 = text (additionalContext | block reason), $3 = systemMessage
  if [ "$have_jq" -eq 1 ]; then
    jq -nc --arg k "$1" --arg c "$2" --arg u "${3:-}" '
      (if $k == "post" then {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}
       elif $k == "stop" then {decision: "block", reason: $c} else {} end)
      + (if $u != "" then {systemMessage: $u} else {} end)' 2> /dev/null
  else
    python3 -c '
import sys, json
o = {}
if sys.argv[1] == "post":
    o = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": sys.argv[2]}}
elif sys.argv[1] == "stop":
    o = {"decision": "block", "reason": sys.argv[2]}
if sys.argv[3]: o["systemMessage"] = sys.argv[3]
print(json.dumps(o))
' "$1" "$2" "${3:-}" 2> /dev/null
  fi
  exit 0
}

# --- shared: lock helpers (keep identical in track-*.sh) ---
trk_mtime() { # $1 path -> epoch mtime on stdout; GNU stat first (BSD rejects -c), then BSD stat
  local t
  t="$(stat -c %Y "$1" 2> /dev/null)" || t=""
  case "$t" in '' | *[!0-9]*) t="$(stat -f %m "$1" 2> /dev/null)" || t="" ;; esac
  case "$t" in '' | *[!0-9]*) return 1 ;; esac
  printf '%s' "$t"
}
trk_lock() { # $1 lock dir; returns 1 if still busy after ~2s. Caller sets the EXIT trap (trk_unlock).
  local lock="$1" tries=0 lt now hp stale="$1.stale.$$" dead
  until mkdir "$lock" 2> /dev/null; do
    # Stale = the holder pid (written right after mkdir) is dead, or, with no pid file yet, the lock
    # is older than 5s. Rename it to a name unique to this process first, so a fresh lock that
    # another process creates meanwhile is never removed; only the atomic rename can race, and
    # it moves the stale directory at most once.
    dead=0; hp=""
    [ -f "$lock/pid" ] && { IFS= read -r hp < "$lock/pid" 2> /dev/null || true; }
    case "$hp" in
      '' | *[!0-9]*)
        if lt="$(trk_mtime "$lock")" && now="$(date +%s 2> /dev/null)"; then
          case "$now" in '' | *[!0-9]*) ;; *) [ $((now - lt)) -gt 5 ] && dead=1 ;; esac
        fi ;;
      *) kill -0 "$hp" 2> /dev/null || dead=1 ;;
    esac
    if [ "$dead" -eq 1 ]; then
      rm -f "$stale/pid" 2> /dev/null; rmdir "$stale" 2> /dev/null
      mv "$lock" "$stale" 2> /dev/null && { rm -f "$stale/pid" 2> /dev/null; rmdir "$stale" 2> /dev/null; }
      tries=$((tries + 1))
      [ "$tries" -ge 20 ] && return 1
      continue # retry mkdir at once
    fi
    tries=$((tries + 1))
    [ "$tries" -ge 20 ] && return 1
    sleep 0.1 2> /dev/null || return 1
  done
  printf '%s\n' "$$" > "$lock/pid" 2> /dev/null
  return 0
}
trk_unlock() { rm -f "$1/pid" 2> /dev/null; rmdir "$1" 2> /dev/null; }
# --- end shared ---
take_lock() { # exits 0 (fail open) when the lock stays busy
  lock="$ledger.lock"
  trk_lock "$lock" || exit 0
  trap 'trk_unlock "$lock"' EXIT
}
release_lock() { trk_unlock "$lock"; trap - EXIT; }

# ledger_state: one awk pass over the ledger -> globals (see decision-ledger.md section 5)
ledger_state() {
  local out k v
  pend_n=0; drift_n=0; drift_asked=0; drift_logged=0; paused=0; bp_n=0; bp_last=0; latch=0
  alerted_c=","; alerted_m=","; covered=$'\n'; targets="|"
  out="$(TRACK_SID="$sid" TRACK_NOW_S="$now_s" awk '
# The id is everything after the FIRST " id=": the id itself may contain " id=" (e.g. a path).
function lastid(l,   q) {
  if (substr(l, length(l) - 3) != " -->") return "\001"
  l = substr(l, 1, length(l) - 4); q = index(l, " id=")
  return q ? substr(l, q + 4) : "\001"
}
function tok(l, name,   q, r) {
  q = index(l, " " name "="); if (!q) return ""
  r = substr(l, q + length(name) + 2); sub(/ .*/, "", r); return r
}
function mark_cov(i) { if (i ~ /^(test|dependency|api|scope):/) cov[substr(i, index(i, ":") + 1)] = 1 }
/^<!-- track:pending / { pend++; mark_cov(lastid($0)) }
/^<!-- track:entry / {
  i = lastid($0); if (!index($0, " status=logged-over-budget ")) mark_cov(i)
  if (index($0, " source=breakpoint ") && index($0, " reason=non-interactive ")) ni[i] = 1
}
/^<!-- track:drift / {
  dn++; if (index($0, " asked=yes ")) da++; else dl++
  c = tok($0, "crossed"); if (c != "" && c != "-") ac = ac c ","
  m = tok($0, "modules"); if (m != "" && m != "-") am = am m ","
}
/^<!-- track:drift-paused / { dp = 1 }
/^<!-- track:breakpoint / {
  bn++; e = tok($0, "epoch")
  if (e ~ /^[0-9]+$/ && e + 0 <= ENVIRON["TRACK_NOW_S"] + 0 && e + 0 > bl) bl = e + 0
  i = lastid($0); if (i != "\001") bs[i] = tok($0, "sid")
  t = tok($0, "target"); if (t != "") tg[++nt] = t
}
END {
  sid = ENVIRON["TRACK_SID"]; lt = 0
  if (sid != "-" && sid != "") for (i in bs) if (bs[i] == sid && (i in ni)) lt = 1
  print "P\t" pend + 0; print "D\t" dn + 0; print "A\t" da + 0; print "B\t" bn + 0; print "E\t" bl + 0
  print "L\t" lt; print "C\t," ac; print "M\t," am; print "N\t" dl + 0; print "Z\t" dp + 0
  for (r in cov) print "V\t" r
  for (k = 1; k <= nt; k++) print "T\t" tg[k]
}' "$ledger" 2> /dev/null)" || return 1
  while IFS=$'\t' read -r k v; do
    case "$k" in
      P) pend_n="$v" ;; D) drift_n="$v" ;; A) drift_asked="$v" ;; B) bp_n="$v" ;; E) bp_last="$v" ;;
      L) latch="$v" ;; C) alerted_c="$v" ;; M) alerted_m="$v" ;; N) drift_logged="$v" ;; Z) paused="$v" ;;
      V) covered="$covered$v"$'\n' ;; T) targets="$targets$v|" ;;
    esac
  done <<< "$out"
  case "$pend_n$drift_n$drift_asked$drift_logged$paused$bp_n$bp_last$latch" in '' | *[!0-9]*) return 1 ;; esac
  return 0
}

# untracked_scan: $@ = edited paths. Sets ut_tagged: one "\001T<TAB>rel" (text) or "\001B<TAB>rel"
# (binary or empty) line per untracked, non-ignored file among them. Text detection is ONE grep
# fork for all files. Names come NUL-separated from git, so they are never unquoted.
untracked_scan() {
  local p tx nl=$'\n'
  local -a ua
  ut_tagged=""
  ua=()
  while IFS= read -r -d '' p; do
    case "$p" in *[[:cntrl:]]*) continue ;; esac
    ua[${#ua[@]}]="$p"
  done < <(gitq ls-files -z --others --exclude-standard -- "$@" 2> /dev/null)
  [ "${#ua[@]}" -gt 0 ] || return 0
  tx="$(cd "$root" 2> /dev/null && grep -lI -e '' -- "${ua[@]}" 2> /dev/null)"
  for p in "${ua[@]}"; do
    case "$nl$tx$nl" in
      *"$nl$p$nl"*) ut_tagged="$ut_tagged"$'\001'"T"$'\t'"$p$nl" ;;
      *) ut_tagged="$ut_tagged"$'\001'"B"$'\t'"$p$nl" ;;
    esac
  done
}

# drift_eval: sets d_lines d_files d_top d_new_c d_new_m d_mod_detail from git + ledger state.
# Needs ledger_state to have run (alerted_*, covered). Returns 1 when git cannot answer (fail open).
# Scope/module paths are literal (no rename detection); the size totals and "Largest files" use
# rename detection, so a pure rename counts as 0 lines. Untracked binary files count as 0 lines.
drift_eval() {
  local ns nm paths p k v n
  local -a pa
  ns="$(gitq diff --no-ext-diff --no-textconv --no-renames --numstat "$base" -- 2> /dev/null)" || return 1
  nm="$(gitq diff --no-ext-diff --no-textconv -M --numstat "$base" -- 2> /dev/null)" || return 1
  paths="$(awk -F'\t' '$1 == "e" && $2 != "" && !s[$2]++ { print $2 }' "$state" 2> /dev/null)"
  ut_tagged=""
  if [ -n "$paths" ]; then
    pa=()
    while IFS= read -r p; do pa[${#pa[@]}]="$p"; done <<< "$paths"
    untracked_scan "${pa[@]}"
  fi
  d_lines=0; d_files=0; d_top=""; d_new_c=""; d_new_m=""; d_mod_detail=""
  local mlist="" res
  res="$(printf '%s\n\001M\n%s\n%s' "$ns" "$nm" "$ut_tagged" | TRACK_ROOT="$root" awk "$AWK_DQ"'
BEGIN {
  FS = "\t"; mode = 0
  nl = split("yarn.lock package-lock.json pnpm-lock.yaml npm-shrinkwrap.json bun.lockb Cargo.lock go.sum poetry.lock uv.lock Gemfile.lock Pipfile.lock composer.lock mix.lock Package.resolved", lk, " ")
  for (i = 1; i <= nl; i++) islock[lk[i]] = 1
  cc = sprintf("[%c-%c%c]", 1, 31, 127)
  TT = sprintf("%cT", 1); BB = sprintf("%cB", 1); MM = sprintf("%cM", 1)
}
function base(p,   a, m) { m = split(p, a, "/"); return a[m] }
function padd(p,   b) { gsub(cc, "?", p); b = base(p); np++; pn[np] = p; pl[np] = (b in islock) ? 1 : 0 }
function tadd(p, c,   b) { gsub(cc, "?", p); b = base(p); if (b in islock) c = 0; files++; lines += c; nt++; tn[nt] = p; tc[nt] = c }
# the new path of a rename entry: "old => new" or "pre{old => new}suf"
function newpath(s,   i, j, k) {
  k = index(s, " => "); if (!k) return s
  i = index(s, "{"); j = index(s, "}")
  if (i > 0 && j > k && i < k) { s = substr(s, 1, i - 1) substr(s, k + 4, j - k - 4) substr(s, j + 1); gsub("//", "/", s); return s }
  return substr(s, k + 4)
}
$0 == MM { mode = 1; next }
$1 == TT || $1 == BB {
  p = $2
  if (p ~ /^\.oss-drafts\//) next
  c = 0
  if ($1 == TT) {
    f = ENVIRON["TRACK_ROOT"] "/" p
    while (c < 20000 && (getline row < f) > 0) c++
    close(f)
  }
  padd(p); tadd(p, c); next
}
NF == 3 && ($1 ~ /^[0-9]+$/ || $1 == "-") {
  p = dq($3)
  if (mode == 0) { if (p !~ /^\.oss-drafts\//) padd(p) }
  else { p = newpath(p); if (p !~ /^\.oss-drafts\//) tadd(p, ($1 == "-") ? 0 : $1 + $2) }
}
END {
  print "S\t" lines + 0 "\t" files + 0
  for (i = 1; i <= np; i++) print "P\t" pn[i] "\t" pl[i]
  for (k = 1; k <= 5; k++) {
    best = 0; bi = 0
    for (i = 1; i <= nt; i++) if (!used[i] && tc[i] > best) { best = tc[i]; bi = i }
    if (!bi) break
    used[bi] = 1; print "T\t" tn[bi] "\t" best
  }
}' 2> /dev/null)" || return 1
  local cnt=0 dir mod seg2 m_e
  while IFS=$'\t' read -r k v n; do
    case "$k" in
      S) d_lines="$v"; d_files="$n" ;;
      T) d_top="${d_top:+$d_top, }$v ($n)" ;;
      P)
        [ -n "$fm_scope" ] || continue
        [ "$n" = 1 ] && continue # generated lockfiles are noise; a real manifest still counts as a module
        cnt=$((cnt + 1)); [ "$cnt" -gt 2000 ] && continue
        dir=""
        case "$v" in */*) dir="${v%/*}" ;; esac
        if [ -z "$dir" ]; then
          mod="(root)"
        else
          case "$dir" in
            */*) seg2="${dir#*/}"; mod="${dir%%/*}/${seg2%%/*}" ;;
            *) mod="$dir" ;;
          esac
        fi
        m_e="${mod//%/%25}"; m_e="${m_e// /%20}"; m_e="${m_e//,/%2C}"
        case "$alerted_m" in *",$m_e,"*) continue ;; esac # no forks and no glob work for known modules
        glob_match "$v" "$fm_scope" && continue
        case "$covered" in *$'\n'"$v"$'\n'*) continue ;; esac
        mlist="$mlist$m_e"$'\t'"$v"$'\n'
        ;;
    esac
  done <<< "$res"
  case "$d_lines$d_files" in '' | *[!0-9]*) return 1 ;; esac
  if [ "$drift_lines" -gt 0 ] && [ "$d_lines" -gt "$drift_lines" ]; then d_new_c="lines"; fi
  if [ "$drift_files" -gt 0 ] && [ "$d_files" -gt "$drift_files" ]; then d_new_c="${d_new_c:+$d_new_c,}files"; fi
  if [ -n "$mlist" ]; then
    d_mod_detail="$(printf '%s' "$mlist" | awk -F'\t' '
{ c[$1]++; if (c[$1] <= 3) ex[$1] = ex[$1] (ex[$1] == "" ? "" : ", ") $2; if (!($1 in o)) { o[$1] = ++k; nm[k] = $1 } }
END { for (i = 1; i <= k; i++) print nm[i] "\t" ex[nm[i]] }' 2> /dev/null)"
  fi
  filter_alerted
  return 0
}

# filter_alerted: drop crossings/modules already present in the ledger (alerted_c / alerted_m)
filter_alerted() {
  local item rest out="" mdet="" mnames="" k v
  rest="$d_new_c"
  d_new_c=""
  while [ -n "$rest" ]; do
    item="${rest%%,*}"
    if [ "$rest" = "$item" ]; then rest=""; else rest="${rest#*,}"; fi
    case "$alerted_c" in *",$item,"*) ;; *) out="${out:+$out,}$item" ;; esac
  done
  d_new_c="$out"
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] || continue
    case "$alerted_m" in *",$k,"*) continue ;; esac
    mnames="${mnames:+$mnames,}$k"
    mdet="$mdet$k"$'\t'"$v"$'\n'
  done <<< "$d_mod_detail"
  d_new_m="$mnames"
  d_mod_detail="$mdet"
}

dec() { # decode the three enc() escapes
  local s="$1"
  s="${s//%2C/,}"
  s="${s//%20/ }"
  s="${s//%25/%}"
  printf '%s' "$s"
}

mod_text() { # "m (files); m2 (files)" from d_mod_detail; at most 10 modules shown (the marker keeps all)
  local out="" k v n=0
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] || continue
    n=$((n + 1))
    [ "$n" -gt 10 ] && continue
    out="${out:+$out; }$(dec "$k") ($v)"
  done <<< "$d_mod_detail"
  [ "$n" -gt 10 ] && out="$out; … (+$((n - 10)) more)"
  printf '%s' "$out"
}

drift_text() { # $1 = post|stop, $2 = alert number, $3 = drift id number
  local nl=$'\n' crossed mt t
  crossed="${d_new_c//,/, }"
  [ -n "$crossed" ] || crossed="none"
  t="[agentic-contributor · tracked session] Scope drift alert $2/$drift_max: the change has grown since the session base ${base:0:7}."
  [ "$1" = stop ] && t="${t%.} Handle it before ending your turn:"
  t="$t${nl}Size: $d_lines changed lines (limit $drift_lines, $drift_src_label), $d_files files (limit $drift_files). Crossed: $crossed."
  mt="$(mod_text)"
  [ -n "$mt" ] && t="$t${nl}Out-of-scope modules with changes no checkpoint covered: $mt"
  [ -n "$d_top" ] && t="$t${nl}Largest files: $d_top"
  t="$t${nl}Drift id: drift:$3${nl}${nl}This is advisory: nothing was blocked. Before your next edit:${nl}1. Ask the user with AskUserQuestion (header \"Scope drift\"): ONE question, \"The change is growing beyond the task. What should happen to <the part you name>?\", naming the files concerned (at most 10). Options, each with a one-line trade-off, your recommendation first and marked \"(Recommended)\":${nl}   A) Keep it in this change | B) Set it aside for a separate PR | C) Drop it | D) Skip — decide later${nl}2. Read $rel_ledger, then use Edit to replace the line \`<!-- track:end -->\` with this entry followed by \`<!-- track:end -->\`:${nl}### drift:$3 · <UTC now>${nl}<!-- track:entry status=<decided|skipped> source=drift asked=<yes|no> at=<UTC now> id=drift:$3 -->${nl}- trigger: drift — $d_lines lines / $d_files files${nl}- files: <files the question named, at most 10>${nl}- options: A) Keep in this change | B) Set aside for a separate PR | C) Drop | D) Skip — decide later${nl}- chosen: <A|B|C|Skip>${nl}- decided_by: <user|user-on-recommendation>${nl}- reason: <the user's own words, verbatim, or TODO(you) if none>${nl}- follow-up: <B only: one line naming the set-aside work and its files>${nl}   For B, write the follow-up line. Use status=skipped, reason: TODO(you) for D.${nl}3. If AskUserQuestion is unavailable (non-interactive run or subagent): write the entry with status=skipped, asked=no, chosen: none, decided_by: agent, reason: non-interactive.${nl}4. Follow the choice. Never revert, stash, reset, check out, or move changes on your own. For B or C, stop extending that work and tell the user which files hold it; undo edits only if the user explicitly asks, using Edit.${nl}Write \"decided_by: user…\" only if the user actually answered. The ledger is private: never copy it into any sendable text."
  printf '%s' "$t"
}

# record_drift: under the lock, re-read the ledger, re-filter, append marker+bullet.
# Sets rd_asked (yes|no), rd_k, rd_alert; returns 1 when there is nothing left to record.
record_drift() {
  take_lock
  now_utc=""
  read -r now_utc now_s <<< "$(date -u '+%Y-%m-%dT%H:%M:%SZ %s' 2> /dev/null)"
  [ -n "$now_utc" ] || exit 0
  ledger_state || exit 0
  filter_alerted
  if [ -z "$d_new_c$d_new_m" ]; then release_lock; return 1; fi
  rd_asked=no
  rd_why="drift cap $drift_max spent"
  if [ "$budget" -eq 0 ]; then rd_why="budget 0"; fi
  if [ "$budget" -gt 0 ] && [ "$drift_asked" -lt "$drift_max" ]; then rd_asked=yes; fi
  rd_k=$((drift_n + 1))
  rd_alert=$((drift_asked + 1))
  local cm mm bullet
  cm="${d_new_c:--}"
  mm="${d_new_m:--}"
  bullet="- drift alert drift:$rd_k: $d_lines changed lines (limit $drift_lines), $d_files files (limit $drift_files)"
  [ -n "$d_new_m" ] && bullet="$bullet, out-of-scope modules: $(mod_text)"
  if [ "$rd_asked" = yes ]; then bullet="$bullet; asked"; else bullet="$bullet; logged only ($rd_why)"; fi
  printf '%s\n%s\n' \
    "<!-- track:drift at=$now_utc lines=$d_lines files=$d_files crossed=$cm modules=$mm asked=$rd_asked id=drift:$rd_k -->" \
    "$bullet" >> "$ledger" 2> /dev/null || exit 0
  release_lock
  return 0
}

drift_enabled() {
  [ -n "$base" ] && { [ "$drift_lines" -gt 0 ] || [ "$drift_files" -gt 0 ] || [ -n "$fm_scope" ]; }
}

# base_check: 0 = the session base is still the base of HEAD; 1 = it moved (a rebase, reset or
# merge since tracking started, so a diff against it would count upstream changes as drift);
# 2 = git cannot answer (fail open); 3 = the base commit no longer exists in a working repository
# (garbage-collected, or a shallow clone). Result cached for this run.
base_rc=""
base_check() {
  local m
  if [ -z "$base_rc" ]; then
    if ! gitq cat-file -e "$base^{commit}" 2> /dev/null; then
      if gitq rev-parse --git-dir > /dev/null 2>&1; then base_rc=3; else base_rc=2; fi
    elif ! gitq merge-base --is-ancestor "$base" HEAD 2> /dev/null; then
      base_rc=1
    elif ! m="$(gitq rev-list --merges -n 1 "$base..HEAD" 2> /dev/null)"; then
      base_rc=2
    elif [ -n "$m" ]; then
      base_rc=1
    else
      base_rc=0
    fi
  fi
  return "$base_rc"
}

PAUSE_MSG="agentic-contributor: base moved — drift paused; restart tracking (/oss track stop + start) to re-baseline."
PAUSE_CTX="[agentic-contributor · tracked session] The session base commit is no longer the base of HEAD (a rebase, reset, or merge since tracking started), so scope-drift alerts and explain-back questions are paused for this session. Nothing was blocked. Tell the user once: to re-baseline, run /oss track stop, then /oss track start."

MISSING_MSG="agentic-contributor: base commit not found (garbage-collected or shallow clone) — drift and explain-back paused; restart tracking to re-baseline."
MISSING_CTX="[agentic-contributor · tracked session] The session base commit no longer exists in this repository (garbage-collected, or a shallow clone), so scope-drift alerts and explain-back questions are paused for this session. Nothing was blocked. Tell the user once: to re-baseline, run /oss track stop, then /oss track start."

# record_pause: write the one-time drift-paused marker. $1 = base-moved|base-missing.
# Returns 1 if it was already written.
record_pause() {
  take_lock
  read -r now_utc now_s <<< "$(date -u '+%Y-%m-%dT%H:%M:%SZ %s' 2> /dev/null)"
  [ -n "$now_utc" ] || exit 0
  ledger_state || exit 0
  if [ "$paused" -eq 1 ]; then release_lock; return 1; fi
  local why="the base commit moved (rebase, reset, or merge)"
  [ "$1" = base-missing ] && why="the base commit is missing (garbage-collected or shallow clone)"
  printf '%s\n%s\n' "<!-- track:drift-paused at=$now_utc reason=$1 -->" \
    "- drift and explain-back paused: $why; restart tracking to re-baseline" \
    >> "$ledger" 2> /dev/null || exit 0
  release_lock
  return 0
}

# compact_state: keep <ledger>.state bounded. Above STATE_MAX lines, the oldest lines are folded
# into a short prefix that preserves everything the readers use: the last m and s values, every
# distinct edited path (for the session-wide untracked-file count), the last b reset with the
# distinct paths edited after it, and one d (an edit count since the last d may be undercounted,
# which at most postpones one throttled drift check). The newest STATE_KEEP lines stay verbatim.
# Skipped when the ledger lock is busy; an e line appended while it runs may be lost (harmless).
STATE_MAX=400
STATE_KEEP=100
compact_state() { # $1 = current line count
  local tmp="$state.tmp.$$"
  case "$1" in '' | *[!0-9]*) return 0 ;; esac
  [ "$1" -gt "$STATE_MAX" ] || return 0
  trk_lock "$ledger.lock" || return 0
  lock="$ledger.lock"
  trap 'trk_unlock "$lock"' EXIT
  if [[ ! -L "$tmp" ]] && awk -F'\t' -v keep="$STATE_KEEP" '
{ ln[NR] = $0; k[NR] = $1; v[NR] = $2 }
END {
  cut = NR - keep; nb = 0; hd = 0; m = ""; s = ""
  for (i = 1; i <= cut; i++) {
    if (k[i] == "b") nb = i
    else if (k[i] == "d") hd = 1
    else if (k[i] == "m" && v[i] ~ /^[0-9]+$/) m = v[i]
    else if (k[i] == "s" && v[i] ~ /^[0-9]+$/) s = v[i]
  }
  if (m != "") print "m\t" m
  if (s != "") print "s\t" s
  for (i = nb + 1; i <= cut; i++) if (k[i] == "e" && v[i] != "") after[v[i]] = 1
  for (i = 1; i < nb; i++) if (k[i] == "e" && v[i] != "" && !(v[i] in after) && !(v[i] in pre)) { pre[v[i]] = 1; print "e\t" v[i] }
  if (nb) print "b\tcompacted"
  for (i = nb + 1; i <= cut; i++) if (k[i] == "e" && v[i] != "" && !(v[i] in post)) { post[v[i]] = 1; print "e\t" v[i] }
  if (hd) print "d"
  for (i = cut + 1; i <= NR; i++) print ln[i]
}' "$state" > "$tmp" 2> /dev/null; then
    mv -f "$tmp" "$state" 2> /dev/null
  fi
  rm -f "$tmp" 2> /dev/null
  release_lock
}

# ── PostToolUse ──────────────────────────────────────────────────────────────
post_tool_use() {
  local abs="$path" rel st seen since_d nlines qm
  [ -n "$abs" ] || exit 0
  if [ "${abs#/}" = "$abs" ]; then
    [ -n "$cwd" ] || exit 0
    abs="$cwd/$abs"
  fi
  case "$abs" in */.oss-drafts/*) exit 0 ;; esac
  trk_relpath "$abs"
  rel="$trk_rel"
  [ -n "$rel" ] || exit 0
  case "$rel" in *[[:cntrl:]]*) exit 0 ;; esac
  printf 'e\t%s\n' "$rel" >> "$state" 2> /dev/null || exit 0
  drift_enabled || exit 0
  st="$(awk -F'\t' -v r="$rel" '$1 == "e" { if ($2 == r) seen++; since++ } $1 == "d" { since = 0 } $1 == "m" && $2 ~ /^[0-9]+$/ { qm = $2 + 0 } END { print seen + 0, since + 0, NR + 0, qm + 0 }' "$state" 2> /dev/null)" || exit 0
  read -r seen since_d nlines qm <<< "$st"
  case "$seen$since_d$nlines$qm" in '' | *[!0-9]*) exit 0 ;; esac
  compact_state "$nlines"
  # throttle: git only for a path new to the session or every 5th edit
  if [ "$seen" -gt 1 ] && [ "$since_d" -lt 5 ]; then exit 0; fi
  [ -n "$agent_id" ] && exit 0 # subagent: the main thread's Stop checks (no d marker, no git)
  printf 'd\n' >> "$state" 2> /dev/null || exit 0
  now_s=0
  ledger_state || exit 0
  # spacing: a question already interrupted this turn, so a new drift question waits for a later turn
  if [ "$budget" -gt 0 ] && [ "$drift_asked" -lt "$drift_max" ] && [ $((pend_n + drift_asked)) -gt "$qm" ]; then exit 0; fi
  base_check
  case "$base_rc" in
    1)
      [ "$paused" -eq 1 ] && exit 0
      record_pause base-moved || exit 0
      emit_json post "$PAUSE_CTX" "$PAUSE_MSG" ;;
    3)
      [ "$paused" -eq 1 ] && exit 0
      record_pause base-missing || exit 0
      emit_json post "$MISSING_CTX" "$MISSING_MSG" ;;
    2) exit 0 ;;
  esac
  [ "$paused" -eq 1 ] && exit 0 # base is back, but the session stays paused until a restart
  drift_eval || exit 0
  [ -z "$d_new_c$d_new_m" ] && exit 0
  record_drift || exit 0
  # cap spent or quiet mode: the marker is recorded silently and summarised at Stop / debrief
  [ "$rd_asked" = yes ] && emit_json post "$(drift_text post "$rd_alert" "$rd_k")"
  exit 0
}

# pick_target: sets t_rel t_line t_size from the files edited since the last breakpoint
pick_target() { # $1 = newline list of edited rels
  local rel cand="" tagged="" cand_tagged="" d p
  local -a ca
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    case "$rel" in .oss-drafts/*) continue ;; esac
    [ -n "$(manifest_for "${rel##*/}")" ] && continue
    case "$covered" in *$'\n'"$rel"$'\n'*) continue ;; esac
    cand="$cand$rel"$'\n'
  done <<< "$1"
  t_rel=""; t_line=""; t_size=""
  [ -n "$cand" ] || return 1
  ca=()
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    ca[${#ca[@]}]="$rel"
    cand_tagged="$cand_tagged"$'\001'"C"$'\t'"$rel"$'\n'
  done <<< "$cand"
  [ "${#ca[@]}" -gt 0 ] || return 1
  # Rename-aware (-M) and not path-limited: a pathspec of only the new path hides the rename source,
  # so a pure `git mv` would look entirely new. The candidates are filtered in awk instead.
  d="$(gitq diff --no-ext-diff --no-textconv -M --no-color -U0 --src-prefix=a/ --dst-prefix=b/ "$base" -- 2> /dev/null)" || return 1
  untracked_scan "${ca[@]}"
  # binary and empty untracked files (tagged B) are never targets
  while IFS= read -r p; do
    case "$p" in $'\001'T$'\t'*) tagged="$tagged"$'\001'"U"$'\t'"${p#*$'\t'}"$'\n' ;; esac
  done <<< "$ut_tagged"
  res="$(printf '%s\n%s\n%s\n' "$cand_tagged" "$d" "$tagged" | TRACK_ROOT="$root" TRACK_TARGETS="$targets" awk "$AWK_DQ"'
function enc(s) { gsub(/%/, "%25", s); gsub(/ /, "%20", s); gsub(/,/, "%2C", s); return s }
function consider(rel, ln, sz) {
  if (!(rel in iscand)) return
  if (rel ~ sprintf("[%c-%c%c]", 1, 31, 127)) return
  nh++; hr[nh] = rel; hl[nh] = ln; hs[nh] = sz
}
/^\001C\t/ { iscand[substr($0, 4)] = 1; next }
/^\001U\t/ {
  p = substr($0, 4); f = ENVIRON["TRACK_ROOT"] "/" p; c = 0
  while (c < 20000 && (getline row < f) > 0) c++
  close(f); if (c > 0) consider(p, 1, c); next
}
# body lines of a hunk are consumed by count, so added text like "++ x" is never read as a header
inh && /^-/ { ro--; if (ro <= 0 && rn <= 0) inh = 0; next }
inh && /^\+/ { rn--; if (ro <= 0 && rn <= 0) inh = 0; next }
inh && /^\\/ { next }
/^\+\+\+ / {
  inh = 0
  cur = substr($0, 5)
  if (substr(cur, 1, 1) == "\"") cur = dq(cur); else sub(/\t.*$/, "", cur)
  if (cur == "/dev/null") cur = ""; else sub(/^b\//, "", cur)
  next
}
/^@@ / {
  h = $0; sub(/^@@ -/, "", h)
  split(h, parts, " ")
  old = parts[1]; nw = parts[2]; sub(/^\+/, "", nw)
  ob = 1; nb = 1; nline = 1
  if (index(old, ",")) { split(old, o2, ","); ob = o2[2] + 0 }
  if (index(nw, ",")) { split(nw, n2, ","); nline = n2[1] + 0; nb = n2[2] + 0 } else nline = nw + 0
  if (nline < 1) nline = 1
  ro = ob; rn = nb; inh = (ro > 0 || rn > 0) ? 1 : 0
  if (cur != "") consider(cur, nline, (ob > nb) ? ob : nb)
}
END {
  T = ENVIRON["TRACK_TARGETS"]
  for (pass = 1; pass <= 2; pass++) {
    best = 0; bi = 0
    for (i = 1; i <= nh; i++) {
      if (pass == 1 && index(T, "|" enc(hr[i]) ":") > 0) continue
      if (pass == 2 && index(T, "|" enc(hr[i]) ":" hl[i] "|") > 0) continue
      if (hs[i] > best) { best = hs[i]; bi = i }
    }
    if (bi) { print hr[bi] "\t" hl[bi] "\t" hs[bi]; exit }
  }
}' 2> /dev/null)" || return 1
  [ -n "$res" ] || return 1
  IFS=$'\t' read -r t_rel t_line t_size <<< "$res"
  case "$t_line$t_size" in '' | *[!0-9]*) return 1 ;; esac
  [ -n "$t_rel" ] || return 1
  return 0
}

explain_text() { # uses k t_rel t_line t_size
  local nl=$'\n'
  printf '%s' "[agentic-contributor · tracked session] Breakpoint question $1/$explain_max (explain-back). Before ending your turn:${nl}Target: $t_rel:$t_line. This is the largest change since the session base ($t_size lines) that no checkpoint or earlier question covered.${nl}1. Read $t_rel around line $t_line and pick the one specific change there (a function, condition, value, or call).${nl}2. Ask the user with AskUserQuestion (header \"Explain\"): ONE question, \"In one sentence, why does <that specific change>? Type your answer under Other, or pick an option.\" Do not hint at the answer. Options:${nl}   A) Skip — not sure (recorded as an Unknown)${nl}   B) I didn't ask for this change${nl}3. Read $rel_ledger, then use Edit to replace the line \`<!-- track:end -->\` with this entry followed by \`<!-- track:end -->\`:${nl}### explain:$1 · <UTC now>${nl}<!-- track:entry status=<answered|skipped> source=breakpoint asked=<yes|no> at=<UTC now> id=explain:$1 -->${nl}- trigger: explain — $t_rel:$t_line${nl}- files: $t_rel${nl}- question: <the question exactly as asked>${nl}- chosen: <typed|not-requested|skip>${nl}- reason: <the user's typed words verbatim | not requested by the user | TODO(you)>${nl}- answered_by: user${nl}   Typed answer: status=answered, chosen: typed, reason = their words verbatim. B: status=answered, chosen: not-requested, reason: not requested by the user. A: status=skipped, chosen: skip, reason: TODO(you).${nl}4. If AskUserQuestion is unavailable (non-interactive run or subagent): do not ask. Write \`<!-- track:entry status=skipped source=breakpoint asked=no reason=non-interactive at=<UTC now> id=explain:$1 -->\` with chosen: none, reason: non-interactive, answered_by: agent.${nl}5. Do not grade or correct the answer and make no code edits now. End your turn with one short line.${nl}Write \"answered_by: user\" only if the user actually answered. The ledger is private: never copy it into any sendable text."
}

read_edits() { # sets q_mark, s_mark, n_lines, edited from the edit log (a b line resets the list)
  local st line rest
  st="$(awk -F'\t' '
$1 == "b" { n = 0; split("", seen) }
$1 == "e" && $2 != "" && !($2 in seen) { seen[$2] = 1; list[++n] = $2 }
$1 == "m" && $2 ~ /^[0-9]+$/ { qm = $2 + 0 }
$1 == "s" && $2 ~ /^[0-9]+$/ { sm = $2 + 0 }
END { print "M\t" qm + 0; print "S\t" sm + 0; print "N\t" NR + 0; for (i = 1; i <= n; i++) print "R\t" list[i] }' "$state" 2> /dev/null)" || return 1
  q_mark=0; s_mark=0; n_lines=0; edited=""
  while IFS=$'\t' read -r line rest; do
    case "$line" in M) q_mark="$rest" ;; S) s_mark="$rest" ;; N) n_lines="$rest" ;; R) edited="$edited$rest"$'\n' ;; esac
  done <<< "$st"
  case "$q_mark$s_mark$n_lines" in '' | *[!0-9]*) return 1 ;; esac
  return 0
}

# ── Stop ─────────────────────────────────────────────────────────────────────
# A user-facing systemMessage (sys_note) never blocks; it rides along with a block, or is emitted
# alone when the turn ends without one.
finish() {
  [ -n "$sys_note" ] && emit_json note "" "$sys_note"
  exit 0
}

stop_event() {
  local edited edited0 bp0 q_mark s_mark n_lines q_now k had_state why
  sys_note=""
  read -r now_utc now_s <<< "$(date -u '+%Y-%m-%dT%H:%M:%SZ %s' 2> /dev/null)"
  [ -n "$now_utc" ] || exit 0
  ledger_state || exit 0
  [ -n "$base" ] && base_check
  q_mark=0; s_mark=0; n_lines=0; edited=""
  had_state=0
  if [ -f "$state" ]; then
    had_state=1
    read_edits || finish
    compact_state "$n_lines"
  fi
  q_now=$((pend_n + drift_asked))

  # (a) drift, once per newly crossed threshold or module; paused once the base moved or vanished.
  # Skipped when a question already interrupted since the last stop (spacing).
  if [ "$had_state" -eq 1 ] && [ "$q_now" -gt "$q_mark" ]; then
    :
  elif { [ "$base_rc" = 1 ] || [ "$base_rc" = 3 ]; } && [ "$paused" -eq 0 ] && drift_enabled; then
    if [ "$base_rc" = 1 ]; then why=base-moved; else why=base-missing; fi
    if record_pause "$why"; then
      if [ "$base_rc" = 1 ]; then sys_note="$PAUSE_MSG"; else sys_note="$MISSING_MSG"; fi
    fi
    ledger_state || exit 0
  elif [ "$base_rc" = 0 ] && [ "$paused" -eq 0 ] && [ "$asking" != 1 ] && drift_enabled && drift_eval && [ -n "$d_new_c$d_new_m" ]; then
    if record_drift && [ "$rd_asked" = yes ]; then
      # advance the question watermark before blocking, or the next Stop sees this question as new
      ledger_state || exit 0
      printf 'm\t%s\n' "$((pend_n + drift_asked))" >> "$state" 2> /dev/null
      emit_json stop "$(drift_text stop "$rd_alert" "$rd_k")"
    fi
    ledger_state || exit 0
  fi

  # (b) explain-back. The question watermark advances on every stop that has a state file, even
  # when explain-back itself is off, so Post's spacing check stays current.
  q_now=$((pend_n + drift_asked))
  printf 'm\t%s\n' "$q_now" >> "$state" 2> /dev/null || finish
  # drift recorded without asking (cap spent or quiet mode) is summarised here, once per new item;
  # it is a user-facing systemMessage the agent does not see
  if [ "$drift_logged" -gt "$s_mark" ]; then
    printf 's\t%s\n' "$drift_logged" >> "$state" 2> /dev/null &&
      sys_note="${sys_note:+$sys_note }agentic-contributor: $((drift_logged - s_mark)) scope-drift item(s) logged without asking (drift question cap spent or budget 0); they are in the ledger and the debrief."
  fi
  [ "$budget" -gt 0 ] && [ "$explain_max" -gt 0 ] && [ -n "$base" ] || finish
  [ "$base_rc" = 0 ] && [ "$paused" -eq 0 ] || finish # base moved or unknown: explain-back paused
  [ "$had_state" -eq 1 ] || finish                     # no edit logged this session
  [ -n "$edited" ] || finish
  [ "$q_now" -gt "$q_mark" ] && finish # a question already interrupted since the last stop
  [ "$asking" = 1 ] && finish          # the agent is already waiting on the user
  [ "$bp_n" -ge "$explain_max" ] && finish
  if [ "$explain_int" -gt 0 ] && [ $((now_s - bp_last)) -lt $((explain_int * 60)) ]; then finish; fi
  [ "$latch" -eq 1 ] && finish
  if ! pick_target "$edited"; then
    printf 'b\tnone\n' >> "$state" 2> /dev/null
    finish
  fi
  edited0="$edited"; bp0=$bp_n
  take_lock
  read -r now_utc now_s <<< "$(date -u '+%Y-%m-%dT%H:%M:%SZ %s' 2> /dev/null)"
  [ -n "$now_utc" ] || finish
  ledger_state || finish
  [ "$bp_n" -ge "$explain_max" ] && finish
  if [ "$explain_int" -gt 0 ] && [ $((now_s - bp_last)) -lt $((explain_int * 60)) ]; then finish; fi
  [ "$latch" -eq 1 ] && finish
  # revalidate under the lock: a concurrent Stop may have consumed the edits or targeted this spot
  read_edits || finish
  [ -n "$edited" ] || finish
  # no git under the lock: the target picked above stands if nothing changed meanwhile (a concurrent
  # breakpoint bumps bp_n and appends a b line, which changes edited)
  [ "$edited" = "$edited0" ] || finish
  [ "$bp_n" -eq "$bp0" ] || finish
  q_now=$((pend_n + drift_asked))
  [ "$q_now" -gt "$q_mark" ] && finish # a checkpoint/drift question landed after the first check
  k=$((bp_n + 1))
  printf '%s\n%s\n' \
    "<!-- track:breakpoint at=$now_utc epoch=$now_s sid=$sid target=$(enc "$t_rel"):$t_line id=explain:$k -->" \
    "- breakpoint question explain:$k: $t_rel:$t_line (${t_size}-line change)" >> "$ledger" 2> /dev/null || finish
  printf 'b\texplain:%s\n' "$k" >> "$state" 2> /dev/null || finish
  release_lock
  emit_json stop "$(explain_text "$k")" "$sys_note"
}

now_utc=""; now_s=0
case "$ev" in
  PostToolUse) post_tool_use ;;
  Stop) stop_event ;;
esac
exit 0
