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
# Opt-in per session: it does nothing (no output, no subprocess) unless
# <root>/.oss-drafts/.track-active exists. The no-session path uses only bash builtins.
#
# Format, ids, caps and loop rules: skills/pr-preparation/references/decision-ledger.md (sections
# 11-14). Blocks marked "shared:<name>" are copied byte for byte from track-checkpoint.sh and
# checked by hooks/tests/run-breakpoint-tests.sh.
#
# Must run on macOS default bash 3.2: no mapfile, no ${x,,}, no associative arrays.

set -u
set -f # never glob-expand patterns such as scope globs

[ "${OSS_TRACK_DISABLE:-}" = 1 ] && exit 0

IFS= read -r -d '' input || true
[ -n "$input" ] || exit 0

# ── FAST PATH: event + session pointer using only builtins ───────────────────
re_ev='"hook_event_name"[[:space:]]*:[[:space:]]*"(PostToolUse|Stop)"'
[[ $input =~ $re_ev ]] || exit 0
ev="${BASH_REMATCH[1]}"
if [ "$ev" = Stop ]; then
  re_sha='"stop_hook_active"[[:space:]]*:[[:space:]]*true'
  [[ $input =~ $re_sha ]] && exit 0 # loop guard first, zero cost
fi

# >>> shared:find-root (keep byte-identical in track-checkpoint.sh; checked by run-breakpoint-tests.sh)
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
if [ "$ev" = PostToolUse ] && [[ $input =~ $re_path ]]; then fp="${BASH_REMATCH[2]}"; fi
if [[ $input =~ $re_cwd ]]; then cwd="${BASH_REMATCH[1]}"; fi
if [ -n "$fp" ] && [ "${fp#/}" = "$fp" ] && [ -n "$cwd" ]; then fp="$cwd/$fp"; fi

root=""
if [ "$ev" = PostToolUse ]; then
  for start in "${fp%/*}" "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
    [ -n "$start" ] && find_root "$start" && break
  done
else
  for start in "$cwd" "${CLAUDE_PROJECT_DIR:-}"; do
    [ -n "$start" ] && find_root "$start" && break
  done
fi
[ -z "$root" ] && exit 0

# ── SLOW PATH: a session pointer exists. Any failure below fails open. ───────
# >>> shared:pointer (keep byte-identical in track-checkpoint.sh; checked by run-breakpoint-tests.sh)
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

# >>> shared:clean-list (keep byte-identical in track-checkpoint.sh; checked by run-breakpoint-tests.sh)
clean_list() { # strip comment, brackets, quotes
  local v="${1%%#*}"
  v="${v//\[/}"
  v="${v//\]/}"
  v="${v//\"/}"
  printf '%s' "$v"
}
# <<< shared:clean-list
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
drift_source="${fm_dsrc:-default}"
base=""
re_sha7='^[0-9a-f]{7,64}$'
[[ $fm_base =~ $re_sha7 ]] && base="$fm_base"

have_jq=0
have_py=0
command -v jq > /dev/null 2>&1 && have_jq=1
command -v python3 > /dev/null 2>&1 && have_py=1
[ "$have_jq" -eq 1 ] || [ "$have_py" -eq 1 ] || exit 0

# parse_input: US-separated event, path, permission_mode, session_id, stop_hook_active, agent_id, last char.
parse_input() {
  if [ "$have_jq" -eq 1 ]; then
    printf '%s' "$input" | jq -r '
      (.tool_input // {}) as $ti
      | [(.hook_event_name // ""), ($ti.file_path // $ti.notebook_path // ""), (.permission_mode // ""),
         (.session_id // ""), ((.stop_hook_active // false) | tostring), (.agent_id // ""),
         ((.last_assistant_message // "") | tostring | sub("[[:space:]]+$"; "") | .[-1:])]
      | map(tostring) | join("\u001f")' 2> /dev/null
  else
    printf '%s' "$input" | python3 -c '
import sys, json
d = json.load(sys.stdin)
ti = d.get("tool_input") or {}
m = str(d.get("last_assistant_message") or "").rstrip()
print("\x1f".join([d.get("hook_event_name") or "", ti.get("file_path") or ti.get("notebook_path") or "",
  d.get("permission_mode") or "", d.get("session_id") or "",
  "true" if d.get("stop_hook_active") else "false", d.get("agent_id") or "", m[-1:]]))
' 2> /dev/null
  fi
}

parsed="$(parse_input)" || exit 0
[ -n "$parsed" ] || exit 0
IFS=$'\037' read -r p_ev path perm_mode sid sha_active agent_id last_char <<< "$parsed"
[ "$p_ev" = "$ev" ] || exit 0
[ "$perm_mode" = "plan" ] && exit 0
[ "$ev" = Stop ] && [ "$sha_active" = true ] && exit 0
re_sid='^[A-Za-z0-9._-]+$'
if ! [[ $sid =~ $re_sid ]]; then sid="-"; fi

# ── helpers ──────────────────────────────────────────────────────────────────
# >>> shared:manifest-map (keep byte-identical in track-checkpoint.sh; checked by run-breakpoint-tests.sh)
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

# >>> shared:glob-match (keep byte-identical in track-checkpoint.sh; checked by run-breakpoint-tests.sh)
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

emit_json() { # $1 = post|stop, $2 = text
  if [ "$have_jq" -eq 1 ]; then
    if [ "$1" = post ]; then
      jq -nc --arg c "$2" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}' 2> /dev/null
    else
      jq -nc --arg c "$2" '{decision: "block", reason: $c}' 2> /dev/null
    fi
  else
    python3 -c '
import sys, json
if sys.argv[1] == "post":
    o = {"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": sys.argv[2]}}
else:
    o = {"decision": "block", "reason": sys.argv[2]}
print(json.dumps(o))
' "$1" "$2" 2> /dev/null
  fi
  exit 0
}

take_lock() {
# >>> shared:lock (keep byte-identical in track-checkpoint.sh; checked by run-breakpoint-tests.sh)
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
}
release_lock() { rmdir "$lock" 2> /dev/null; trap - EXIT; }

# ledger_state: one awk pass over the ledger -> globals (see decision-ledger.md section 5)
ledger_state() {
  local out k v
  pend_n=0; drift_n=0; drift_asked=0; bp_n=0; bp_last=0; latch=0
  alerted_c=","; alerted_m=","; covered=$'\n'; targets="|"
  out="$(TRACK_SID="$sid" TRACK_NOW_S="$now_s" awk '
function lastid(l,   q, res, found) {
  if (substr(l, length(l) - 3) != " -->") return "\001"
  l = substr(l, 1, length(l) - 4); found = 0; res = ""
  while ((q = index(l, " id=")) > 0) { l = substr(l, q + 4); res = l; found = 1 }
  return found ? res : "\001"
}
function tok(l, name,   q, r) {
  q = index(l, " " name "="); if (!q) return ""
  r = substr(l, q + length(name) + 2); sub(/ .*/, "", r); return r
}
function mark_cov(i) { if (i ~ /^(test|dependency|api|scope):/) cov[substr(i, index(i, ":") + 1)] = 1 }
/^<!-- track:pending / { pend++; mark_cov(lastid($0)) }
/^<!-- track:entry / {
  i = lastid($0); mark_cov(i)
  if (index($0, " source=breakpoint ") && index($0, " reason=non-interactive ")) ni[i] = 1
}
/^<!-- track:drift / {
  dn++; if (index($0, " asked=yes ")) da++
  c = tok($0, "crossed"); if (c != "" && c != "-") ac = ac c ","
  m = tok($0, "modules"); if (m != "" && m != "-") am = am m ","
}
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
  print "L\t" lt; print "C\t," ac; print "M\t," am
  for (r in cov) print "V\t" r
  for (k = 1; k <= nt; k++) print "T\t" tg[k]
}' "$ledger" 2> /dev/null)" || return 1
  while IFS=$'\t' read -r k v; do
    case "$k" in
      P) pend_n="$v" ;; D) drift_n="$v" ;; A) drift_asked="$v" ;; B) bp_n="$v" ;; E) bp_last="$v" ;;
      L) latch="$v" ;; C) alerted_c="$v" ;; M) alerted_m="$v" ;;
      V) covered="$covered$v"$'\n' ;; T) targets="$targets$v|" ;;
    esac
  done <<< "$out"
  case "$pend_n$drift_n$drift_asked$bp_n$bp_last$latch" in '' | *[!0-9]*) return 1 ;; esac
  return 0
}

# drift_eval: sets d_lines d_files d_top d_new_c d_new_m d_mod_detail from git + ledger state.
# Needs ledger_state to have run (alerted_*, covered). Returns 1 when git cannot answer (fail open).
drift_eval() {
  local ns paths ut p k v n
  local -a pa
  ns="$(gitq diff --no-ext-diff --no-textconv --no-renames --numstat "$base" -- 2> /dev/null)" || return 1
  paths="$(awk -F'\t' '$1 == "e" && $2 != "" && !s[$2]++ { print $2 }' "$state" 2> /dev/null)"
  ut=""
  if [ -n "$paths" ]; then
    pa=()
    while IFS= read -r p; do pa[${#pa[@]}]="$p"; done <<< "$paths"
    ut="$(gitq ls-files --others --exclude-standard -- "${pa[@]}" 2> /dev/null)"
  fi
  d_lines=0; d_files=0; d_top=""; d_new_c=""; d_new_m=""; d_mod_detail=""
  local mlist="" res
  res="$(printf '%s\n%s\n' "$ns" "$ut" | TRACK_ROOT="$root" awk "$AWK_DQ"'
BEGIN {
  FS = "\t"
  nl = split("yarn.lock package-lock.json pnpm-lock.yaml npm-shrinkwrap.json bun.lockb Cargo.lock go.sum poetry.lock uv.lock Gemfile.lock Pipfile.lock composer.lock mix.lock Package.resolved", lk, " ")
  for (i = 1; i <= nl; i++) islock[lk[i]] = 1
}
function add(p, c,   a, m, b) {
  m = split(p, a, "/"); b = a[m]
  if (b in islock) c = 0
  files++; lines += c; np++; pn[np] = p; pc[np] = c
}
NF == 3 && ($1 ~ /^[0-9]+$/ || $1 == "-") {
  $3 = dq($3)
  if ($3 ~ /^\.oss-drafts\//) next
  add($3, ($1 == "-") ? 0 : $1 + $2); next
}
NF == 1 && $1 != "" {
  $1 = dq($1)
  if ($1 ~ /^\.oss-drafts\//) next
  f = ENVIRON["TRACK_ROOT"] "/" $1; c = 0
  while ((getline row < f) > 0) c++
  close(f); add($1, c)
}
END {
  print "S\t" lines + 0 "\t" files + 0
  for (i = 1; i <= np; i++) print "P\t" pn[i]
  for (k = 1; k <= 5; k++) {
    best = 0; bi = 0
    for (i = 1; i <= np; i++) if (!used[i] && pc[i] > best) { best = pc[i]; bi = i }
    if (!bi) break
    used[bi] = 1; print "T\t" pn[bi] "\t" best
  }
}' 2> /dev/null)" || return 1
  local cnt=0 dir mod seg2 mf
  while IFS=$'\t' read -r k v n; do
    case "$k" in
      S) d_lines="$v"; d_files="$n" ;;
      T) d_top="${d_top:+$d_top, }$v ($n)" ;;
      P)
        [ -n "$fm_scope" ] || continue
        cnt=$((cnt + 1)); [ "$cnt" -gt 2000 ] && continue
        glob_match "$v" "$fm_scope" && continue
        case "$covered" in *$'\n'"$v"$'\n'*) continue ;; esac
        # generated lockfiles are noise; a real manifest (package.json, ...) still counts as a module
        mf="$(manifest_for "${v##*/}")"
        [ -n "$mf" ] && [ "$mf" != "${v##*/}" ] && continue
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
        mlist="$mlist$(enc "$mod")"$'\t'"$v"$'\n'
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

mod_text() { # "m (files); m2 (files)" from d_mod_detail
  local out="" k v
  while IFS=$'\t' read -r k v; do
    [ -n "$k" ] || continue
    out="${out:+$out; }$(dec "$k") ($v)"
  done <<< "$d_mod_detail"
  printf '%s' "$out"
}

drift_text() { # $1 = post|stop, $2 = alert number, $3 = drift id number
  local nl=$'\n' crossed mt t
  crossed="${d_new_c//,/, }"
  [ -n "$crossed" ] || crossed="none"
  t="[agentic-contributor · tracked session] Scope drift alert $2/$drift_max: the change has grown since the session base ${base:0:7}."
  [ "$1" = stop ] && t="${t%.} Handle it before ending your turn:"
  t="$t${nl}Size: $d_lines changed lines (limit $drift_lines, $drift_source), $d_files files (limit $drift_files). Crossed: $crossed."
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

# ── PostToolUse ──────────────────────────────────────────────────────────────
post_tool_use() {
  local abs="$path" rel st seen since_d t
  [ -n "$abs" ] || exit 0
  if [ "${abs#/}" = "$abs" ]; then
    [ -n "$cwd" ] || exit 0
    abs="$cwd/$abs"
  fi
  case "$abs" in */.oss-drafts/*) exit 0 ;; esac
  rel="${abs#"$root"/}"
  [ "$rel" = "$abs" ] && exit 0
  case "$rel" in *$'\n'* | *$'\t'*) exit 0 ;; esac
  printf 'e\t%s\n' "$rel" >> "$state" 2> /dev/null || exit 0
  drift_enabled || exit 0
  st="$(awk -F'\t' -v r="$rel" '$1 == "e" { if ($2 == r) seen++; since++ } $1 == "d" { since = 0 } END { print seen + 0, since + 0 }' "$state" 2> /dev/null)" || exit 0
  read -r seen since_d <<< "$st"
  case "$seen$since_d" in '' | *[!0-9]*) exit 0 ;; esac
  # throttle: git only for a path new to the session or every 5th edit
  if [ "$seen" -gt 1 ] && [ "$since_d" -lt 5 ]; then exit 0; fi
  printf 'd\n' >> "$state" 2> /dev/null || exit 0
  [ -n "$agent_id" ] && exit 0 # subagent: the main thread's Stop checks
  now_s=0
  ledger_state || exit 0
  drift_eval || exit 0
  [ -z "$d_new_c$d_new_m" ] && exit 0
  record_drift || exit 0
  if [ "$rd_asked" = yes ]; then
    emit_json post "$(drift_text post "$rd_alert" "$rd_k")"
  fi
  t="[agentic-contributor · tracked session] Scope drift logged without asking (drift:$rd_k: $d_lines lines / $d_files files"
  [ -n "$d_new_m" ] && t="$t; modules $(mod_text)"
  emit_json post "$t; $rd_why). It will appear in the debrief. Continue, and mention it to the user when you finish."
}

# pick_target: sets t_rel t_line t_size from the files edited since the last breakpoint
pick_target() { # $1 = newline list of edited rels
  local rel cand="" ut="" tagged="" d p
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
  while IFS= read -r rel; do [ -n "$rel" ] && ca[${#ca[@]}]="$rel"; done <<< "$cand"
  [ "${#ca[@]}" -gt 0 ] || return 1
  d="$(gitq diff --no-ext-diff --no-textconv --no-renames --no-color -U0 --src-prefix=a/ --dst-prefix=b/ "$base" -- "${ca[@]}" 2> /dev/null)" || return 1
  ut="$(gitq ls-files --others --exclude-standard -- "${ca[@]}" 2> /dev/null)"
  if [ -n "$ut" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] && tagged="$tagged"$'\001'"U"$'\t'"$p"$'\n'
    done <<< "$ut"
  fi
  res="$(printf '%s\n%s\n' "$d" "$tagged" | TRACK_ROOT="$root" TRACK_TARGETS="$targets" awk "$AWK_DQ"'
function enc(s) { gsub(/%/, "%25", s); gsub(/ /, "%20", s); gsub(/,/, "%2C", s); return s }
function consider(rel, ln, sz) {
  nh++; hr[nh] = rel; hl[nh] = ln; hs[nh] = sz
}
/^\001U\t/ {
  p = dq(substr($0, 4)); f = ENVIRON["TRACK_ROOT"] "/" p; c = 0
  while ((getline row < f) > 0) c++
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

read_edits() { # sets q_mark, edited from the edit log (a breakpoint marker resets the list)
  local st line rest
  st="$(awk -F'\t' '
$1 == "b" { n = 0; split("", seen) }
$1 == "e" && $2 != "" && !($2 in seen) { seen[$2] = 1; list[++n] = $2 }
$1 == "m" && $2 ~ /^[0-9]+$/ { qm = $2 + 0 }
END { print "M\t" qm + 0; for (i = 1; i <= n; i++) print "R\t" list[i] }' "$state" 2> /dev/null)" || return 1
  q_mark=0; edited=""
  while IFS=$'\t' read -r line rest; do
    case "$line" in M) q_mark="$rest" ;; R) edited="$edited$rest"$'\n' ;; esac
  done <<< "$st"
  case "$q_mark" in '' | *[!0-9]*) return 1 ;; esac
  return 0
}

# ── Stop ─────────────────────────────────────────────────────────────────────
stop_event() {
  local edited q_mark q_now k
  read -r now_utc now_s <<< "$(date -u '+%Y-%m-%dT%H:%M:%SZ %s' 2> /dev/null)"
  [ -n "$now_utc" ] || exit 0
  ledger_state || exit 0

  # (a) drift, once per newly crossed threshold or module
  if drift_enabled && drift_eval && [ -n "$d_new_c$d_new_m" ]; then
    if record_drift && [ "$rd_asked" = yes ]; then
      emit_json stop "$(drift_text stop "$rd_alert" "$rd_k")"
    fi
    ledger_state || exit 0
  fi

  # (b) explain-back
  [ "$budget" -gt 0 ] && [ "$explain_max" -gt 0 ] && [ -n "$base" ] || exit 0
  [ -f "$state" ] || exit 0
  read_edits || exit 0
  q_now=$((pend_n + drift_asked))
  printf 'm\t%s\n' "$q_now" >> "$state" 2> /dev/null || exit 0
  [ -n "$edited" ] || exit 0
  [ "$q_now" -gt "$q_mark" ] && exit 0 # a question already interrupted since the last stop
  [ "$last_char" = "?" ] && exit 0     # the agent is already waiting on the user
  [ "$bp_n" -ge "$explain_max" ] && exit 0
  if [ "$explain_int" -gt 0 ] && [ $((now_s - bp_last)) -lt $((explain_int * 60)) ]; then exit 0; fi
  [ "$latch" -eq 1 ] && exit 0
  if ! pick_target "$edited"; then
    printf 'b\tnone\n' >> "$state" 2> /dev/null
    exit 0
  fi
  take_lock
  read -r now_utc now_s <<< "$(date -u '+%Y-%m-%dT%H:%M:%SZ %s' 2> /dev/null)"
  [ -n "$now_utc" ] || exit 0
  ledger_state || exit 0
  [ "$bp_n" -ge "$explain_max" ] && exit 0
  if [ "$explain_int" -gt 0 ] && [ $((now_s - bp_last)) -lt $((explain_int * 60)) ]; then exit 0; fi
  [ "$latch" -eq 1 ] && exit 0
  # revalidate under the lock: a concurrent Stop may have consumed the edits or targeted this spot
  read_edits || exit 0
  [ -n "$edited" ] || exit 0
  q_now=$((pend_n + drift_asked))
  [ "$q_now" -gt "$q_mark" ] && exit 0 # a checkpoint/drift question landed after the first check
  pick_target "$edited" || exit 0
  k=$((bp_n + 1))
  printf '%s\n%s\n' \
    "<!-- track:breakpoint at=$now_utc epoch=$now_s sid=$sid target=$(enc "$t_rel"):$t_line id=explain:$k -->" \
    "- breakpoint question explain:$k: $t_rel:$t_line (${t_size}-line change)" >> "$ledger" 2> /dev/null || exit 0
  printf 'b\texplain:%s\n' "$k" >> "$state" 2> /dev/null || exit 0
  release_lock
  emit_json stop "$(explain_text "$k")"
}

now_utc=""; now_s=0
case "$ev" in
  PostToolUse) post_tool_use ;;
  Stop) stop_event ;;
esac
exit 0
