#!/usr/bin/env bash
# track-breakpoint.sh — advisory scope-drift alerts and explain-back breakpoint questions for
# tracked /oss sessions.
#
# Registered as a SEPARATE hook on three events:
#   PostToolUse (Edit|Write|MultiEdit|NotebookEdit)  log the edit; throttled scope-drift check;
#                                                    a new alert is delivered as additionalContext
#                                                    (never a block, never a revert)
#   Stop                                             drift check once per turn end, then at most ONE
#                                                    explain-back question; delivered as a block so
#                                                    the agent asks the user before it finishes
#   UserPromptSubmit                                 predict-then-reveal (predict: auto | true | false):
#                                                    additionalContext asking the agent to collect the
#                                                    user's prediction first; never blocks, no git. Writes:
#                                                    a predict-auto switch marker (ledger lock, fail open)
#                                                    and a `p<TAB>sid` line in the state file (full note sent). It does not depend on
#                                                    the session base, so it keeps running when drift
#                                                    and explain-back are paused (base moved).
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
re_ev='"hook_event_name"[[:space:]]*:[[:space:]]*"(PostToolUse|Stop|UserPromptSubmit)"'
[[ $input =~ $re_ev ]] || exit 0
ev="${BASH_REMATCH[1]}"
if [ "$ev" = Stop ]; then
  re_sha='"stop_hook_active"[[:space:]]*:[[:space:]]*true'
  [[ $input =~ $re_sha ]] && exit 0 # loop guard before any parsing or subprocess
fi
root="$trk_root"
ledger="$trk_ledger"
# shellcheck disable=SC2034 # set by the shared lookup; instructions use the absolute $ledger
rel_ledger="$trk_rel_ledger"

state="${ledger%.md}.state"
[[ -L "$state" ]] && exit 0

# Frontmatter (builtin reads, no fork).
fm_plugin=""; fm_mode=""; fm_status=""; fm_scope=""; fm_budget=""; fm_base=""
fm_dl=""; fm_df=""; fm_dmax=""; fm_emax=""; fm_eint=""; fm_dsrc=""
fm_predict=""; fm_pmax=""; fm_ucommits=""; fm_punk=""
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
    # values may be column-padded (wc -l on macOS pads): trim leading whitespace first
    "predict: "*) v="${line#predict: }"; v="${v#"${v%%[![:space:]]*}"}"; fm_predict="${v%%[[:space:]]*}" ;;
    "predict_max: "*) v="${line#predict_max: }"; v="${v#"${v%%[![:space:]]*}"}"; fm_pmax="${v%%[[:space:]]*}" ;;
    "user_commits: "*) v="${line#user_commits: }"; v="${v#"${v%%[![:space:]]*}"}"; fm_ucommits="${v%%[[:space:]]*}" ;;
    "prior_unknowns: "*) v="${line#prior_unknowns: }"; v="${v#"${v%%[![:space:]]*}"}"; fm_punk="${v%%[[:space:]]*}" ;;
    "explain_max: "*) v="${line#explain_max: }"; fm_emax="${v%%[[:space:]]*}" ;;
    "explain_interval_min: "*) v="${line#explain_interval_min: }"; fm_eint="${v%%[[:space:]]*}" ;;
    "scope: "*) fm_scope="${line#scope: }" ;;
  esac
done < "$ledger"
[ "$fm_plugin" = "agentic-contributor" ] && [ "$fm_mode" = "track" ] || exit 0
[ "$fm_status" = "active" ] || exit 0
# Predict off (no key, false, anything else): a prompt costs no JSON parse and no further subprocess (stdin is read once).
if [ "$ev" = UserPromptSubmit ]; then
  case "$fm_predict" in true | on | auto) ;; *) exit 0 ;; esac
fi

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
predict_max="$(int_or "$fm_pmax" 4)"
# drift_source is ledger text: only a fixed label derived from it is ever shown. It is labelled
# per limit: a limit left at its default value says "default" even when the other one was set.
case "${fm_dsrc:-default}" in
  default) drift_src_label="default" ;;
  user) drift_src_label="set by the user" ;;
  contributing:*) drift_src_label="from the project's CONTRIBUTING file" ;;
  *) drift_src_label="from the ledger" ;;
esac
dl_label="$drift_src_label"; [ "$drift_lines" = 400 ] && dl_label="default"
df_label="$drift_src_label"; [ "$drift_files" = 10 ] && df_label="default"
base=""
re_sha7='^[0-9a-f]{7,64}$'
[[ $fm_base =~ $re_sha7 ]] && base="$fm_base"

have_jq=0
have_py=0
command -v jq > /dev/null 2>&1 && have_jq=1
command -v python3 > /dev/null 2>&1 && have_py=1
[ "$have_jq" -eq 1 ] || [ "$have_py" -eq 1 ] || exit 0

# parse_input: US-separated event, path, permission_mode, session_id, stop_hook_active, agent_id,
# asking (1/0), cwd, prompt kind (empty|slash|text; slash = "/name" followed by space or end, so a
# path like /src/a.c:4 is text), trivial (1 for a short prompt of 24 UTF-8 bytes or fewer with no question
# mark and no diagnosis/planning keyword). Any field containing a control character (newline, CR, US, ...) is printed as
# empty, so it can neither shift the fields nor forge ledger/state lines. "asking" is 1 when the
# last assistant message already waits on the user: its last non-blank line (trailing markdown
# emphasis, quotes and brackets ignored) ends in ? or a full-width question mark, or it ends in an
# option list whose lead-in line does (the last 40 non-blank lines are examined).
# last_assistant_message (Stop) and agent_id (PostToolUse in a subagent) need a Claude Code version
# that sends them; without them the "already asking" and subagent checks simply never fire.
KW_RE='bug|fail|error|crash|broken|wrong|why|fix|plan|approach|design|implement|refactor|debug|problem|issue|slow|leak|panic|exception|hangs|hanging|hung|flaky|stuck|timeout|broke'
parse_input() {
  if [ "$have_jq" -eq 1 ]; then
    printf '%s' "$input" | jq -r --arg kw "$KW_RE" '
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
         (.last_assistant_message | asking | if . then "1" else "0" end), (.cwd // ""),
         (((.prompt // "") | tostring | sub("^[[:space:]]+"; "") | sub("[[:space:]]+$"; "")) as $p
          | (if $p == "" then "empty" elif ($p | test("^/[A-Za-z0-9_:-]+(\\s|$)")) then "slash" else "text" end),
            (if ($p | utf8bytelength) <= 24 and ($p | test("[?\uff1f]") | not) and ($p | test($kw; "i") | not) then "1" else "0" end))]
      | map(clean) | join("\u001f")' 2> /dev/null
  else
    printf '%s' "$input" | python3 -c '
import sys, json, re
d = json.load(sys.stdin)
ti = d.get("tool_input") or {}
pr = str(d.get("prompt") or "").strip()
pk = "empty" if not pr else ("slash" if re.match(r"/[A-Za-z0-9_:-]+(\s|$)", pr) else "text")
pt = "1" if len(pr.encode("utf-8")) <= 24 and not re.search("[?\uff1f]", pr) and not re.search(sys.argv[1], pr, re.I) else "0"
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
  "true" if d.get("stop_hook_active") else "false", d.get("agent_id"), asking(d.get("last_assistant_message")), d.get("cwd"), pk, pt]))
' "$KW_RE" 2> /dev/null
  fi
}

parsed="$(parse_input)" || exit 0
[ -n "$parsed" ] || exit 0
IFS=$'\037' read -r p_ev path perm_mode sid sha_active agent_id asking cwd p_kind p_trivial <<< "$parsed"
case "$path$cwd" in *[[:cntrl:]]*) exit 0 ;; esac # belt and braces: never log a control char
[ "$p_ev" = "$ev" ] || exit 0
# plan mode: no checkpoint/drift/explain questions, but a planning prompt is exactly when to predict
[ "$perm_mode" = "plan" ] && [ "$ev" != UserPromptSubmit ] && exit 0
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

emit_json() { # $1 = post|prompt|stop|note, $2 = text (additionalContext | block reason), $3 = systemMessage
  if [ "$have_jq" -eq 1 ]; then
    jq -nc --arg k "$1" --arg c "$2" --arg u "${3:-}" '
      (if $k == "post" then {hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}
       elif $k == "prompt" then {hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}
       elif $k == "stop" then {decision: "block", reason: $c} else {} end)
      + (if $u != "" then {systemMessage: $u} else {} end)' 2> /dev/null
  else
    python3 -c '
import sys, json
o = {}
if sys.argv[1] == "post":
    o = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": sys.argv[2]}}
elif sys.argv[1] == "prompt":
    o = {"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": sys.argv[2]}}
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
  pend_n=0; drift_n=0; drift_asked=0; drift_logged=0; paused=0; bp_n=0; bp_last=0; latch=0; predict_n=0
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
function mark_cov(i,  r) { # test/dependency ids may end in #<8 hex change checksum>
  if (i !~ /^(test|dependency|api|scope):/) return
  r = substr(i, index(i, ":") + 1); sub(/#[0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]$/, "", r)
  cov[r] = 1
}
/^<!-- track:pending / { pend++; mark_cov(lastid($0)) }
/^<!-- track:entry / {
  i = lastid($0); if (!index($0, " status=logged-over-budget ")) mark_cov(i)
  if (index($0, " source=breakpoint ") && index($0, " reason=non-interactive ")) ni[i] = 1
  if (i ~ /^predict:/) pn++
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
  print "L\t" lt; print "C\t," ac; print "M\t," am; print "N\t" dl + 0; print "Z\t" dp + 0; print "R\t" pn + 0
  for (r in cov) print "V\t" r
  for (k = 1; k <= nt; k++) print "T\t" tg[k]
}' "$ledger" 2> /dev/null)" || return 1
  while IFS=$'\t' read -r k v; do
    case "$k" in
      P) pend_n="$v" ;; D) drift_n="$v" ;; A) drift_asked="$v" ;; B) bp_n="$v" ;; E) bp_last="$v" ;;
      L) latch="$v" ;; C) alerted_c="$v" ;; M) alerted_m="$v" ;; N) drift_logged="$v" ;; Z) paused="$v" ;; R) predict_n="$v" ;;
      V) covered="$covered$v"$'\n' ;; T) targets="$targets$v|" ;;
    esac
  done <<< "$out"
  case "$pend_n$drift_n$drift_asked$drift_logged$paused$bp_n$bp_last$latch$predict_n" in '' | *[!0-9]*) return 1 ;; esac
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
  [ "$1" = stop ] && t="$t Handle it before ending your turn:"
  t="$t${nl}Size: $d_lines changed lines (limit $drift_lines, $dl_label), $d_files files (limit $drift_files, $df_label). Crossed: $crossed."
  mt="$(mod_text)"
  [ -n "$mt" ] && t="$t${nl}Out-of-scope modules with changes no checkpoint covered: $mt"
  [ -n "$d_top" ] && t="$t${nl}Largest files: $d_top"
  t="$t${nl}Drift id: drift:$3${nl}${nl}This is advisory: nothing was blocked. Before your next edit:${nl}1. Ask the user with AskUserQuestion (header \"Scope drift\"): ONE question, \"The change is growing beyond the task. What should happen to <the part you name>?\", naming the files concerned (at most 10). Options, each with a one-line trade-off, your recommendation first and marked \"(Recommended)\":${nl}   A) Keep it in this change | B) Set it aside for a separate PR | C) Drop it | D) Skip — decide later${nl}2. Read $ledger, then use Edit to replace the line \`<!-- track:end -->\` with this entry followed by \`<!-- track:end -->\`:${nl}### drift:$3 · <UTC now>${nl}<!-- track:entry status=<decided|skipped> source=drift asked=<yes|no> at=<UTC now> id=drift:$3 -->${nl}- trigger: drift — $d_lines lines / $d_files files${nl}- files: <files the question named, at most 10>${nl}- options: A) Keep in this change | B) Set aside for a separate PR | C) Drop | D) Skip — decide later${nl}- chosen: <A|B|C|Skip>${nl}- decided_by: <user|user-on-recommendation>${nl}- reason: <the user's own words, verbatim, or TODO(you) if none>${nl}- follow-up: <B only: one line naming the set-aside work and its files>${nl}   For B, write the follow-up line. Use status=skipped, reason: TODO(you) for D.${nl}3. If AskUserQuestion is unavailable (non-interactive run or subagent): write the entry with status=skipped, asked=no, chosen: none, decided_by: agent, reason: non-interactive.${nl}4. Follow the choice. Never revert, stash, reset, check out, or move changes on your own. For B or C, stop extending that work and tell the user which files hold it; undo edits only if the user explicitly asks, using Edit.${nl}Write \"decided_by: user…\" only if the user actually answered. The ledger is private: never copy it into any sendable text."
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
# distinct paths edited after it, every distinct p (predict note already sent to a session), and one d (an edit count since the last d may be undercounted,
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
  for (i = 1; i <= cut; i++) if (k[i] == "p" && v[i] != "" && !(v[i] in ps)) { ps[v[i]] = 1; print "p\t" v[i] }
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
  if [ "$budget" -gt 0 ] && [ "$drift_asked" -lt "$drift_max" ] && [ $((pend_n + drift_asked + predict_n)) -gt "$qm" ]; then exit 0; fi
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

# Smallest change worth an explain-back question: a hunk (max of old/new line counts) or an
# untracked text file with fewer lines is never a target.
EXPLAIN_MIN_LINES=5

# pick_target: sets t_rel t_line t_size from the files edited since the last breakpoint; returns 1
# when no candidate has a change of at least EXPLAIN_MIN_LINES lines
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
  res="$(printf '%s\n%s\n%s\n' "$cand_tagged" "$d" "$tagged" | TRACK_ROOT="$root" TRACK_TARGETS="$targets" TRACK_MIN="$EXPLAIN_MIN_LINES" awk "$AWK_DQ"'
function enc(s) { gsub(/%/, "%25", s); gsub(/ /, "%20", s); gsub(/,/, "%2C", s); return s }
function consider(rel, ln, sz) {
  if (!(rel in iscand)) return
  if (rel ~ sprintf("[%c-%c%c]", 1, 31, 127)) return
  if (sz < ENVIRON["TRACK_MIN"] + 0) return
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
  printf '%s' "[agentic-contributor · tracked session] Breakpoint question $1/$explain_max (explain-back). Before ending your turn:${nl}Target: $t_rel:$t_line. This is the largest change since the session base ($t_size lines) that no checkpoint or earlier question covered.${nl}1. Read $t_rel around line $t_line and pick the one specific change there (a function, condition, value, or call).${nl}2. Ask the user with AskUserQuestion (header \"Explain\"): ONE question, \"In one sentence, why does <that specific change>? Type your answer under Other, or pick an option.\" Do not hint at the answer. Options:${nl}   A) Skip — not sure (recorded as an Unknown)${nl}   B) I didn't ask for this change${nl}3. Read $ledger, then use Edit to replace the line \`<!-- track:end -->\` with this entry followed by \`<!-- track:end -->\`:${nl}### explain:$1 · <UTC now>${nl}<!-- track:entry status=<answered|skipped> source=breakpoint asked=<yes|no> at=<UTC now> id=explain:$1 -->${nl}- trigger: explain — $t_rel:$t_line${nl}- files: $t_rel${nl}- question: <the question exactly as asked>${nl}- chosen: <typed|not-requested|skip>${nl}- reason: <the user's typed words verbatim | not requested by the user | TODO(you)>${nl}- answered_by: user${nl}   Typed answer: status=answered, chosen: typed, reason = their words verbatim. B: status=answered, chosen: not-requested, reason: not requested by the user. A: status=skipped, chosen: skip, reason: TODO(you).${nl}4. If AskUserQuestion is unavailable (non-interactive run or subagent): do not ask. Write \`<!-- track:entry status=skipped source=breakpoint asked=no reason=non-interactive at=<UTC now> id=explain:$1 -->\` with chosen: none, reason: non-interactive, answered_by: agent.${nl}5. Do not grade or correct the answer and make no code edits now. End your turn with one short line.${nl}Write \"answered_by: user\" only if the user actually answered. The ledger is private: never copy it into any sendable text."
}

# read_edits: sets q_mark, s_mark, n_lines, edited from the edit log (a b line resets the list) and
# turn_edits, the number of edits since the last m line (every Stop writes one, so it marks the
# previous stop)
read_edits() {
  local st line rest
  st="$(awk -F'\t' '
$1 == "b" { n = 0; split("", seen) }
$1 == "e" && $2 != "" { te++; if (!($2 in seen)) { seen[$2] = 1; list[++n] = $2 } }
$1 == "m" && $2 ~ /^[0-9]+$/ { qm = $2 + 0; te = 0 }
$1 == "s" && $2 ~ /^[0-9]+$/ { sm = $2 + 0 }
END { print "M\t" qm + 0; print "S\t" sm + 0; print "N\t" NR + 0; print "E\t" te + 0; for (i = 1; i <= n; i++) print "R\t" list[i] }' "$state" 2> /dev/null)" || return 1
  q_mark=0; s_mark=0; n_lines=0; turn_edits=0; edited=""
  while IFS=$'\t' read -r line rest; do
    case "$line" in M) q_mark="$rest" ;; S) s_mark="$rest" ;; N) n_lines="$rest" ;; E) turn_edits="$rest" ;; R) edited="$edited$rest"$'\n' ;; esac
  done <<< "$st"
  case "$q_mark$s_mark$n_lines$turn_edits" in '' | *[!0-9]*) return 1 ;; esac
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
  local edited edited0 bp0 q_mark s_mark n_lines turn_edits q_now k had_state why
  sys_note=""
  read -r now_utc now_s <<< "$(date -u '+%Y-%m-%dT%H:%M:%SZ %s' 2> /dev/null)"
  [ -n "$now_utc" ] || exit 0
  ledger_state || exit 0
  [ -n "$base" ] && base_check
  q_mark=0; s_mark=0; n_lines=0; turn_edits=0; edited=""
  had_state=0
  if [ -f "$state" ]; then
    had_state=1
    read_edits || finish
    compact_state "$n_lines"
  fi
  q_now=$((pend_n + drift_asked + predict_n))

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
      printf 'm\t%s\n' "$((pend_n + drift_asked + predict_n))" >> "$state" 2> /dev/null
      emit_json stop "$(drift_text stop "$rd_alert" "$rd_k")"
    fi
    ledger_state || exit 0
  fi

  # (b) explain-back. The question watermark advances on every stop that has a state file, even
  # when explain-back itself is off, so Post's spacing check stays current.
  q_now=$((pend_n + drift_asked + predict_n))
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
  # no edit since the previous stop (a chat-only turn): edits deferred earlier wait for the next
  # turn that edits again, so a question never interrupts a turn that changed nothing
  [ "$turn_edits" -gt 0 ] || finish
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
  q_now=$((pend_n + drift_asked + predict_n))
  [ "$q_now" -gt "$q_mark" ] && finish # a checkpoint/drift question landed after the first check
  k=$((bp_n + 1))
  printf '%s\n%s\n' \
    "<!-- track:breakpoint at=$now_utc epoch=$now_s sid=$sid target=$(enc "$t_rel"):$t_line id=explain:$k -->" \
    "- breakpoint question explain:$k: $t_rel:$t_line (${t_size}-line change)" >> "$ledger" 2> /dev/null || finish
  printf 'b\texplain:%s\n' "$k" >> "$state" 2> /dev/null || finish
  release_lock
  emit_json stop "$(explain_text "$k")" "$sys_note"
}

predict_text() { # $1 = used count, $2 = auto reason label (empty when explicit)
  local nl=$'\n' k=$(($1 + 1)) plan=""
  [ "$perm_mode" = plan ] && plan="${nl}You are in plan mode: write the predict entry as soon as plan mode ends, before any other edit."
  printf '%s' "[agentic-contributor · tracked session] Predict mode is on${2:+ (auto: $2)} ($1/$predict_max used). Only if this prompt asks you to diagnose a problem (a bug, failure, or unexpected behaviour) or to propose a plan or approach for a code change, and you have not already asked for a prediction about this same problem in this conversation:${nl}1. Before investigating deeply or revealing your diagnosis or plan, ask the user with AskUserQuestion (header \"Predict\"): ONE question. For a diagnosis: \"Where do you think the problem is?\" For a plan: \"Which files or parts do you expect need to change?\" Options: A) No idea — go ahead | B) Skip predictions for this session. Ask them to type their guess under Other. Do not hint.${nl}2. Right after the answer, before investigating, read $ledger, then use Edit to replace the line \`<!-- track:end -->\` with this entry followed by \`<!-- track:end -->\`:${nl}### predict:$k · <UTC now>${nl}<!-- track:entry status=<answered|skipped> source=predict asked=yes at=<UTC now> id=predict:$k -->${nl}- phase: <diagnosis|plan>${nl}- prediction: <the user's typed words verbatim | no idea>${nl}- outcome: pending${nl}- answered_by: user${nl}   Typed guess: status=answered, prediction = their words verbatim. A: status=answered, prediction: exactly \`no idea\`. B: status=skipped, prediction: none, and also set \`predict: false\` in the ledger frontmatter (the user opted out for the rest of this session).${nl}3. Do the work. When you reveal your diagnosis or plan, add a short \"Your prediction vs. what I found\" section: where the prediction matched and where it differed, each with file:line. Never score or judge it. Then append, the same way (replace \`<!-- track:end -->\` with the block followed by \`<!-- track:end -->\`), and never edit the earlier entry:${nl}### predict:$k outcome${nl}<!-- track:outcome at=<UTC now> id=predict:$k -->${nl}- outcome: <one line: matched / partly / differed, with file:line>${nl}4. If AskUserQuestion is unavailable (non-interactive run or subagent): do not ask and do not record anything.${plan}${nl}Otherwise ignore this note. The ledger is private: never copy it into any sendable text."
}

# Short repeat of the note, sent after the full one has gone out once in this session.
predict_text_short() { # $1 = used count, $2 = auto reason label
  local nl=$'\n' k=$(($1 + 1)) plan=""
  [ "$perm_mode" = plan ] && plan=" You are in plan mode: record it as soon as plan mode ends, before any other edit."
  printf '%s' "[agentic-contributor · tracked session] Predict mode is on${2:+ (auto: $2)} ($1/$predict_max used). Only if this prompt asks you to diagnose a problem or propose a plan for a code change and you have not asked yet: first ask ONE AskUserQuestion (header \"Predict\"; \"Where do you think the problem is?\" or \"Which files or parts do you expect need to change?\"; A) No idea — go ahead | B) Skip predictions for this session; guess under Other), no hints. Record predict:$k right after the answer in $ledger, reveal with \"Your prediction vs. what I found\" (format: ${BASH_SOURCE[0]%/hooks/scripts/*}/skills/pr-preparation/references/decision-ledger.md section 4, \"Predict entries\"; rules: section 15).${plan}${nl}The ledger is private: never copy it into any sendable text."
}

# ── UserPromptSubmit ─────────────────────────────────────────────────────────
# predict: auto rules (decision-ledger.md section 15). Facts: user_commits and prior_unknowns from the
# frontmatter, explain/predict entries and the last predict-auto marker from one awk pass. No git.
# Sets a_state (on|off), a_reason (a fixed label), a_last (state of the last marker; none = off).
# A prediction counts as "no idea" only when, lowercased and stripped of surrounding spaces, quotes and
# punctuation, it is exactly "no idea" or "no idea — go ahead" (option A's label, any dash or comma);
# "No idea, maybe lexer.c" is a guess and does not count.
auto_eval() {
  local out k v uc pu a_expl a_noidea
  a_expl=""; a_noidea=0; a_last=off
  out="$(awk '
function lastid(l,   q) {
  if (substr(l, length(l) - 3) != " -->") return ""
  l = substr(l, 1, length(l) - 4); q = index(l, " id=")
  return q ? substr(l, q + 4) : ""
}
function tok(l, name,   q, r) {
  q = index(l, " " name "="); if (!q) return ""
  r = substr(l, q + length(name) + 2); sub(/ .*/, "", r); return r
}
/^<!-- track:entry / { cur = lastid($0); next }
/^<!-- track:predict-auto / { s = tok($0, "state"); if (s == "on" || s == "off") last = s; cur = ""; next }
/^<!--/ || /^### / { cur = ""; next }
cur ~ /^explain:/ && /^- chosen: (skip|not-requested)[ \t]*$/ {
  if (expl == "") { expl = ($0 ~ /not-requested/) ? "explain-not-requested" : "explain-skipped" }
  next
}
cur ~ /^predict:/ && /^- prediction: / {
  v = tolower($0); sub(/^- prediction: */, "", v); sub(/^[^a-z0-9]+/, "", v); sub(/[^a-z0-9]+$/, "", v)
  np++; pred[np] = (v == "no idea" || v ~ /^no idea *(—|–|-|,|\.)? *go ahead$/) ? 1 : 0
}
END {
  print "X\t" expl; print "N\t" (np >= 2 && pred[np] && pred[np - 1] ? 1 : 0); print "S\t" (last == "" ? "off" : last)
}' "$ledger" 2> /dev/null)" || return 1
  while IFS=$'\t' read -r k v; do
    case "$k" in X) a_expl="$v" ;; N) a_noidea="$v" ;; S) a_last="$v" ;; esac
  done <<< "$out"
  case "$a_expl" in '' | explain-skipped | explain-not-requested) ;; *) a_expl="" ;; esac
  uc="$fm_ucommits"; pu="$(int_or "$fm_punk" 0)"
  case "$uc" in -1) ;; '' | *[!0-9]* | ???????????*) uc=-1 ;; esac
  case "$pu" in ???????????*) pu=0 ;; esac
  if [ "$a_noidea" = 1 ]; then a_state=off; a_reason=two-no-idea
  elif [ "$uc" -ge 0 ] && [ "$uc" -lt 5 ]; then a_state=on; a_reason=newcomer
  elif [ -n "$a_expl" ]; then a_state=on; a_reason="$a_expl"
  elif [ "$pu" -ge 3 ]; then a_state=on; a_reason=prior-unknowns
  else a_state=off; a_reason=no-signal; fi
  return 0
}

# log_auto_switch: when the computed state differs from the last marker, append marker + line under the
# lock, re-checking inside it so concurrent prompts write one marker. Fail open: any problem skips the write.
log_auto_switch() {
  local nu
  [ "$a_state" != "$a_last" ] || return 0
  trk_lock "$ledger.lock" || return 0
  lock="$ledger.lock"
  trap 'trk_unlock "$lock"' EXIT
  if auto_eval && [ "$a_state" != "$a_last" ]; then
    nu="$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2> /dev/null)"
    [ -n "$nu" ] && printf '<!-- track:predict-auto at=%s state=%s reason=%s -->\n- predict auto: %s (%s)\n' \
      "$nu" "$a_state" "$a_reason" "$a_state" "$a_reason" >> "$ledger" 2> /dev/null
  fi
  release_lock
  return 0
}

# Silent unless every gate passes. No git (so a paused session still predicts). Explicit true/false
# never write.
prompt_submit() {
  local mode reason=""
  case "$fm_predict" in true | on) mode=on ;; auto) mode=auto ;; *) exit 0 ;; esac
  [ "$budget" -gt 0 ] || exit 0
  [ "$p_kind" = text ] || exit 0
  [ "$p_trivial" = 1 ] && exit 0
  now_s=0
  ledger_state || exit 0
  [ "$predict_n" -lt "$predict_max" ] || exit 0
  if [ "$mode" = auto ]; then
    auto_eval || exit 0
    log_auto_switch
    [ "$a_state" = on ] || exit 0
    reason="$a_reason"
  fi
  # The full note goes out once per session (a `p<TAB><sid>` state line); later prompts get the short one.
  local full=1 line=""
  if [ "$sid" != "-" ] && [ -f "$state" ]; then
    while IFS= read -r line; do
      [ "$line" = "p"$'\t'"$sid" ] && { full=0; break; }
    done < "$state"
  fi
  if [ "$full" -eq 1 ]; then
    [ "$sid" != "-" ] && printf 'p\t%s\n' "$sid" >> "$state" 2> /dev/null
    emit_json prompt "$(predict_text "$predict_n" "$reason")"
  else
    emit_json prompt "$(predict_text_short "$predict_n" "$reason")"
  fi
}

now_utc=""; now_s=0
case "$ev" in
  UserPromptSubmit) prompt_submit ;;
  PostToolUse) post_tool_use ;;
  Stop) stop_event ;;
esac
exit 0
