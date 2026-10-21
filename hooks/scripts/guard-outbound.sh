#!/usr/bin/env bash
# guard-outbound.sh — Draft-only guardrail for the agentic-contributor plugin.
# Reads a tool-use JSON from stdin, inspects the tool name and command,
# and DENIES any outbound/mutating actions.
#
# Exit codes:
#   0 = allow (read-only / safe operation)
#   2 = deny  (outbound/mutating action blocked)
#
# Denial emits JSON to stderr with permissionDecision=deny and a message
# explaining that this plugin is DRAFT-ONLY.
#
# Must run on macOS default bash 3.2 (no mapfile, no associative arrays).

set -euo pipefail

# ── Read all stdin ────────────────────────────────────────────────────────────
input="$(cat)"

# ── Extract tool_name and command ─────────────────────────────────────────────
# Try jq first, fall back to python3, then grep.
if command -v jq &>/dev/null; then
  tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
  command_str="$(printf '%s' "$input" | jq -r '.tool_input.command // ""' 2>/dev/null || true)"
elif command -v python3 &>/dev/null; then
  tool_name="$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_name',''))
except Exception:
    print('')
" 2>/dev/null || true)"
  command_str="$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input',{}).get('command',''))
except Exception:
    print('')
" 2>/dev/null || true)"
else
  # Last resort: grep for quoted string values
  tool_name="$(printf '%s' "$input" | grep -o '"tool_name"\s*:\s*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' || true)"
  command_str="$(printf '%s' "$input" | grep -o '"command"\s*:\s*"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"' || true)"
fi

# ── Helper: emit denial and exit 2 ───────────────────────────────────────────
deny() {
  local offender="$1"
  local msg="This plugin is DRAFT-ONLY. The drafted content is ready for your review, but sending/posting/pushing is handled by the separate execution/submission plugin. Blocked action: ${offender}"
  printf '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":"%s"}' \
    "$(printf '%s' "$msg" | sed 's/"/\\"/g')" >&2
  exit 2
}

# ── Check MCP write tools ─────────────────────────────────────────────────────
# Deny any GitHub MCP tool that performs a write/mutation.
# Write-verb suffixes (after the last '__'):
WRITE_VERBS="create|update|delete|merge|add_comment|add_issue_comment|add_sub_issue|push|fork|request_copilot|create_or_update|create_pull_request|create_branch|create_repository|assign|transfer|lock|unlock|submit|dispatch|edit"

if [[ "$tool_name" == mcp__plugin_agentic-contributor_github__* ]]; then
  suffix="${tool_name##*__}"
  if [[ "$suffix" =~ ^($WRITE_VERBS)$ ]]; then
    deny "$tool_name"
  fi
  # Allow all other MCP read tools
  exit 0
fi

# ── Shell-text preprocessing (awk, bash 3.2 safe) ─────────────────────────────
# AWK_PREPROCESS joins backslash-newline continuations (outside single quotes).
# Heredoc bodies are NOT skipped: they are ordinary lines and are always checked,
# because a body written by cat/tee can be executed later (cat > run.sh <<EOF).
read -r -d '' AWK_PREPROCESS <<'AWK' || true
function endsbs(x,   k, c) {
  k = length(x); c = 0
  while (k > 0 && substr(x, k, 1) == "\\") { c++; k-- }
  return (c % 2 == 1)
}
BEGIN { sq = "\047"; dq = "\042" }
{ L[++n] = $0 }
END {
  q = ""; i = 1
  while (i <= n) {
    line = L[i]; i++
    j = 1; cmt = 0
    while (1) {
      len = length(line)
      while (j <= len) {
        c = substr(line, j, 1)
        if (q == sq) { if (c == sq) q = ""; j++; continue }
        if (c == "\\") { j += 2; continue }
        if (q == dq) { if (c == dq) q = ""; j++; continue }
        if (c == sq || c == dq) { q = c; j++; continue }
        if (c == "#" && (j == 1 || substr(line, j - 1, 1) ~ /[ \t;|&(]/)) { cmt = 1; break }
        j++
      }
      # A backslash at the end of a comment does not continue the line.
      if (cmt || q == sq || !endsbs(line) || i > n) break
      line = substr(line, 1, len - 1) L[i]; i++
      j = len
    }
    print line
  }
}
AWK

# AWK_SEGMENT splits shell text into command segments, one per output line, on
# newline ; | & ( ) backtick and $( -- but NOT inside quotes -- and drops
# comments. If a quote is left open it falls back to naive splitting (which can
# only produce more segments, i.e. over-deny, never under-deny).
read -r -d '' AWK_SEGMENT <<'AWK' || true
function emit() {
  gsub(/\n/, " ", cur)
  if (cur ~ /[^ \t]/) res = res cur "\n"
  cur = ""
}
# Outer mode (-v outer=1): command substitutions / process substitutions are
# collapsed to a placeholder instead of splitting, so flags after a substitution
# stay attached to their invocation. Substitution bodies are checked by the
# normal (inner) pass. Outer mode also prints each substitution body as a
# line prefixed with \002 (newlines encoded as \003) so the caller can
# re-segment it recursively with its own argument boundaries intact.
function addbody(b) {
  gsub(/\n/, "\003", b)
  bodies = bodies "\002" b "\n"
}
function skipsub(   dep, c2, st) {
  i++; dep = 1; i++; st = i
  while (i <= n) {
    c2 = substr(s, i, 1)
    if (c2 == "\\") i++
    else if (c2 == sq) { i++; while (i <= n && substr(s, i, 1) != sq) i++ }
    else if (c2 == dq) { i++; while (i <= n && substr(s, i, 1) != dq) { if (substr(s, i, 1) == "\\") i++; i++ } }
    else if (c2 == "(") dep++
    else if (c2 == ")") { dep--; if (dep == 0) break }
    i++
  }
  addbody(substr(s, st, i - st))
  cur = cur "SUBST"
}
function skipbt(   st) {
  i++; st = i
  while (i <= n && substr(s, i, 1) != "`") { if (substr(s, i, 1) == "\\") i++; i++ }
  addbody(substr(s, st, i - st))
  cur = cur "SUBST"
}
BEGIN { sq = "\047"; dq = "\042" }
{ s = (NR == 1 ? $0 : s "\n" $0) }
END {
  n = length(s); q = ""; cur = ""; res = ""; bodies = ""; lastop = 0
  for (i = 1; i <= n; i++) {
    c = substr(s, i, 1); nx = substr(s, i + 1, 1)
    if (q == sq) { cur = cur c; if (c == sq) q = ""; continue }
    if (c == "\\") { cur = cur c nx; i++; continue }
    if (q == dq) {
      if (c == dq) { q = ""; cur = cur c }
      else if (outer && c == "`") skipbt()
      else if (outer && c == "$" && nx == "(") skipsub()
      else if (c == "`") { emit(); q = "" }
      else if (c == "$" && nx == "(") { emit(); q = ""; i++ }
      else cur = cur c
      continue
    }
    if (c == sq || c == dq) { q = c; cur = cur c; continue }
    if (c == "#" && (cur == "" || substr(cur, length(cur), 1) ~ /[ \t]/)) {
      while (i < n && substr(s, i + 1, 1) != "\n") i++
      continue
    }
    if (outer && c == "`") { skipbt(); continue }
    if (outer && (c == "$" || c == "<" || c == ">") && nx == "(") { skipsub(); continue }
    # `>&2`, `<&3`, `&>file` are redirections, not command separators
    # (only after an unescaped, unquoted operator: `\>&` is a literal > then a separator)
    if (c == ">" || c == "<") lastop = i
    if (c == "&" && ((lastop == i - 1 && i > 1) || nx == ">")) { cur = cur c; continue }
    # `>|` is the clobber redirection, not a pipe
    if (c == "|" && lastop == i - 1 && i > 1 && substr(s, i - 1, 1) == ">") { cur = cur c; continue }
    if (c == "\n" || c == ";" || c == "|" || c == "&" || c == "`" || c == "(" || c == ")") { emit(); continue }
    if (c == "$" && nx == "(") { emit(); i++; continue }
    cur = cur c
  }
  if (q != "") {
    t = s
    gsub(/\$\(/, "\n", t)
    gsub(/[;|&`()]/, "\n", t)
    res = t "\n"
  } else emit()
  printf "%s%s", res, bodies
}
AWK

# AWK_TOKENIZE splits one segment into shell words (one per line) with quote
# removal, so option parsing sees what gh sees.
read -r -d '' AWK_TOKENIZE <<'AWK' || true
BEGIN { sq = "\047"; dq = "\042" }
# Unquoted redirection words are printed with a \001 marker so the parser can
# tell a real redirection from a quoted literal like '>'.
function flush() {
  if (has) print (rd ? "\001" : "") tok
  tok = ""; has = 0; qd = 0; rd = 0
}
{
  n = length($0); tok = ""; has = 0; q = ""; qd = 0; rd = 0
  for (i = 1; i <= n; i++) {
    c = substr($0, i, 1); nx = substr($0, i + 1, 1)
    if (q == sq) { if (c == sq) q = ""; else tok = tok c; continue }
    if (q == dq) {
      if (c == dq) q = ""
      else if (c == "\\" && nx != "" && index("$`\"\\", nx)) { i++; tok = tok nx }
      else tok = tok c
      continue
    }
    if (c == sq || c == dq) { q = c; has = 1; qd = 1; continue }
    if (c == "\\") { i++; tok = tok nx; has = 1; qd = 1; continue }
    if (c == " " || c == "\t") { flush(); continue }
    # an unquoted redirection operator starts a new word (foo>bar -> foo, >bar)
    if (c == "<" || c == ">") {
      if (has && tok !~ /^[0-9]*[<>]+$/ && !(tok ~ /^[0-9]+$/ && !qd)) flush()
      if (!has || tok ~ /^[0-9]*$/) rd = !qd
    }
    tok = tok c; has = 1
  }
  flush()
}
AWK

# Continuation-joined text. Any awk failure -> raw command
# (never fail open).
if ! stripped="$(printf '%s\n' "$command_str" | awk "$AWK_PREPROCESS" 2>/dev/null)"; then
  stripped="$command_str"
fi
if [[ -z "$stripped" && -n "$command_str" ]]; then
  stripped="$command_str"
fi

# Remove leading wrappers/assignments from a segment so `FOO=1 gh api ...` or
# `then gh api ...` is still recognised as a gh api invocation.
strip_prefix() {
  local s="$1" prev="" kw_re
  kw_re='^(\{|!|then|do|else|elif|if|while|until|time|exec|command|builtin|nohup|sudo|env|xargs)([[:space:]]+|$)(.*)$'
  while [[ "$s" != "$prev" ]]; do
    prev="$s"
    s="${s#"${s%%[![:space:]]*}"}"
    if [[ "$s" =~ $kw_re ]]; then
      s="${BASH_REMATCH[3]}"
    elif [[ "$s" =~ ^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+(.*)$ ]]; then
      s="${BASH_REMATCH[1]}"
    fi
  done
  printf '%s' "$s"
}

# Read-only GraphQL allow-path. Returns 0 only when the call cannot mutate.
# $1 = this gh api segment, $2 = the full (continuation-joined) command.
# GH_FIELDS holds the parsed -f/-F/--field/--raw-field values (quotes removed).
graphql_readonly() {
  local seg="$1" full="$2" full_nq unq v lv
  # Lowercase, quotes/backslashes removed so mu""tation cannot hide the keyword.
  full_nq="$(printf '%s' "$full" | tr 'A-Z' 'a-z' | tr -d "\"'\\\\")"
  [[ "$full_nq" == *mutation* ]] && return 1
  [[ "$full" == *'$('* || "$full" == *'`'* ]] && return 1
  # ANSI-C / locale quoting ($'..' $"..") can hide the keyword via escapes
  [[ "$full" == *"\$'"* || "$full" == *'$"'* ]] && return 1
  for v in ${GH_FIELDS[@]+"${GH_FIELDS[@]}"}; do
    [[ "$v" == *=* ]] || return 1
    # gh reads the value from a file when it starts with @ (checked post-unquote)
    [[ "${v#*=}" == @* ]] && return 1
    lv="$(printf '%s' "$v" | tr 'A-Z' 'a-z')"
    [[ "$lv" == *mutation* ]] && return 1
  done
  # query value must not start with a shell variable
  [[ "$seg" =~ query=[\"\']?\$ ]] && return 1
  # no shell expansion outside single quotes ($VAR / ${VAR}); GraphQL $vars
  # inside single quotes are fine.
  unq="$(printf '%s' "$seg" | sed "s/'[^']*'//g")"
  # Any unquoted-by-single-quote `$` (names, positional $1, $@, $*, $#, $?, ...) is
  # an expansion the guard cannot resolve.
  [[ "$unq" == *'$'* ]] && return 1
  return 0
}

# Records a -X/--method value into check_gh_api's locals (bash dynamic scope).
gh_note_method() {
  local lm
  lm="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  if [[ "$lm" == "get" ]]; then get_seen=1; else bad_method=1; fi
}

# Evaluate one `gh api` segment by parsing its options. Calls deny() on a
# mutating invocation.
check_gh_api() {
  local raw="$1" full="$2" seg tok_out t opt val c rest i n hasval
  local RM=$'\001' rr
  local bad_method=0 get_seen=0 has_input=0 has_field=0 endopts=0 endpoint="" have_ep=0
  local toks=()
  GH_FIELDS=()
  if [[ "${3:-}" == norm ]]; then
    # Normalized mode: NT/NA come from normalize_segment (wrappers, path
    # qualified binary and gh -R options already removed). $raw stays the
    # original text for graphql_readonly's quote-sensitive scans.
    [[ "${NT[0]:-}" == gh && "${NT[1]:-}" == api ]] || return 0
    seg="$raw"
    for t in "${NA[@]}"; do toks[${#toks[@]}]="$t"; done
  else
    seg="$(strip_prefix "$raw")"
    [[ "$seg" =~ ^gh[[:space:]]+api([[:space:]]|$) ]] || return 0
    if ! tok_out="$(printf '%s\n' "$seg" | awk "$AWK_TOKENIZE" 2>/dev/null)"; then
      deny "gh api (unparseable): $raw"
    fi
    while IFS= read -r t; do toks[${#toks[@]}]="$t"; done <<< "$tok_out"
  fi
  n=${#toks[@]}
  i=2
  while [[ $i -lt $n ]]; do
    t="${toks[$i]}"; i=$((i + 1))
    if [[ "$t" == "$RM"* ]]; then
      # Redirection: drop the operator and its target before reading options.
      rr="${t#"$RM"}"; rr="${rr#"${rr%%[!0-9]*}"}"
      case "$rr" in
        '&>>'*) rr="${rr#&>>}" ;; '&>'*) rr="${rr#&>}" ;;
        '>>'*) rr="${rr#>>}" ;; '>|'*) rr="${rr#>|}" ;; '>&'*) rr="${rr#>&}" ;; '>'*) rr="${rr#>}" ;;
        '<<<'*) rr="${rr#<<<}" ;; '<<-'*) rr="${rr#<<-}" ;; '<<'*) rr="${rr#<<}" ;;
        '<&'*) rr="${rr#<&}" ;; '<>'*) rr="${rr#<>}" ;; '<'*) rr="${rr#<}" ;;
      esac
      if [[ -z "$rr" && $i -lt $n ]]; then i=$((i + 1)); fi
    elif [[ $endopts -eq 0 && "$t" == "--" ]]; then
      endopts=1
    elif [[ $endopts -eq 0 && "$t" == --* ]]; then
      opt="${t%%=*}"; val=""; hasval=0
      if [[ "$t" == *=* ]]; then val="${t#*=}"; hasval=1; fi
      case "$opt" in
        --method|--field|--raw-field|--input|--header|--jq|--template|--hostname|--preview|--cache)
          if [[ $hasval -eq 0 && $i -lt $n && "${toks[$i]}" != "$RM"* ]]; then val="${toks[$i]}"; i=$((i + 1)); fi ;;
      esac
      case "$opt" in
        --method) gh_note_method "$val" ;;
        --field|--raw-field) has_field=1; GH_FIELDS[${#GH_FIELDS[@]}]="$val" ;;
        --input) has_input=1 ;;
      esac
    elif [[ $endopts -eq 0 && "$t" == -?* ]]; then
      rest="${t#-}"
      while [[ -n "$rest" ]]; do
        c="${rest:0:1}"; rest="${rest:1}"
        case "$c" in
          X|f|F|H|q|t|p)
            val="${rest#=}"
            if [[ -z "$rest" && $i -lt $n && "${toks[$i]}" != "$RM"* ]]; then val="${toks[$i]}"; i=$((i + 1)); fi
            rest=""
            case "$c" in
              X) gh_note_method "$val" ;;
              f|F) has_field=1; GH_FIELDS[${#GH_FIELDS[@]}]="$val" ;;
            esac ;;
        esac
      done
    elif [[ $have_ep -eq 0 ]]; then
      endpoint="$t"; have_ep=1
    fi
  done

  [[ $bad_method -eq 1 ]] && deny "gh api mutating call: $raw"
  [[ $has_input -eq 1 ]] && deny "gh api --input: $raw"
  if [[ $has_field -eq 1 ]]; then
    [[ $get_seen -eq 1 ]] && return 0   # explicit GET: fields are query parameters
    if [[ "$endpoint" == "graphql" ]] && graphql_readonly "$seg" "$full"; then
      return 0   # read-only GraphQL query
    fi
    deny "gh api with request fields: $raw"
  fi
  return 0
}

# ── Segment normalization (accidental-form coverage, v0.5.1) ──────────────────
# Rewrites one command segment into the form the deny rules expect, so wrapper
# prefixes, env assignments, path-qualified binaries and global options do not
# hide the real subcommand:
#   env -i FOO=1 /usr/bin/git -C d -c k=v push   ->  git push
#   command gh -R o/r pr create                   ->  gh pr create
# Results (globals): NT = words without redirections, NA = words including
# redirections (for gh api option parsing). Runs IN ADDITION to the raw-text
# rules, never instead of them, so it can only add denials.
NORM_RM=$'\001'

# True when redirection token $1 carries no target of its own (target is next word).
rd_is_bare() {
  local rr="${1#"$NORM_RM"}"
  rr="${rr#"${rr%%[!0-9]*}"}"
  case "$rr" in
    '&>>'*) rr="${rr#&>>}" ;; '&>'*) rr="${rr#&>}" ;;
    '>>'*) rr="${rr#>>}" ;; '>|'*) rr="${rr#>|}" ;; '>&'*) rr="${rr#>&}" ;; '>'*) rr="${rr#>}" ;;
    '<<<'*) rr="${rr#<<<}" ;; '<<-'*) rr="${rr#<<-}" ;; '<<'*) rr="${rr#<<}" ;;
    '<&'*) rr="${rr#<&}" ;; '<>'*) rr="${rr#<>}" ;; '<'*) rr="${rr#<}" ;;
  esac
  [[ -z "$rr" ]]
}

# Advance p (caller's local) past redirection words (and bare-operator targets).
nt_skip_rd() {
  while [[ $p -lt $n && "${all[$p]}" == "$NORM_RM"* ]]; do
    if rd_is_bare "${all[$p]}"; then p=$((p + 2)); else p=$((p + 1)); fi
  done
}

# Skip the options of wrapper $1 (env, sudo, xargs, ...) starting at p.
nt_skip_wrapper_opts() {
  local argopts="" o
  case "$1" in
    env) argopts=" -u -C -S --unset --chdir --split-string " ;;
    exec) argopts=" -a " ;;
    time) argopts=" -f -o --format --output " ;;
    sudo) argopts=" -u -g -h -p -C -D -r -t -U -R -T --user --group --host --prompt --close-from --chdir --role --type --other-user --chroot " ;;
    xargs) argopts=" -a -d -E -I -L -n -P -s --arg-file --delimiter --eof --max-args --max-lines --max-procs --max-chars " ;;
  esac
  while :; do
    nt_skip_rd
    [[ $p -ge $n ]] && return 0
    o="${all[$p]}"
    if [[ "$o" == "--" ]]; then p=$((p + 1)); return 0; fi
    [[ "$o" == -?* ]] || return 0
    p=$((p + 1))
    if [[ "$argopts" == *" $o "* ]]; then p=$((p + 1)); fi
  done
}

# Skip git global options (before the subcommand) starting at p.
nt_skip_git_globals() {
  local o
  while :; do
    nt_skip_rd
    [[ $p -ge $n ]] && return 0
    o="${all[$p]}"
    [[ "$o" == -?* ]] || return 0
    p=$((p + 1))
    case "$o" in
      -C|-c|--git-dir|--work-tree|--namespace|--super-prefix|--config-env|--attr-source) p=$((p + 1)) ;;
    esac
  done
}

normalize_segment() {
  local seg="$1" tok_out t w base k all=() p=0 n
  NT=(); NA=()
  tok_out="$(printf '%s\n' "$seg" | awk "$AWK_TOKENIZE" 2>/dev/null)" || return 1
  [[ -n "$tok_out" ]] || return 0
  while IFS= read -r t; do all[${#all[@]}]="$t"; done <<< "$tok_out"
  n=${#all[@]}
  # Phase 1: drop leading keywords, assignments, wrappers; find the command word.
  while :; do
    nt_skip_rd
    [[ $p -ge $n ]] && return 0
    w="${all[$p]}"
    if [[ "$w" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then p=$((p + 1)); continue; fi
    base="${w##*/}"
    case "$base" in
      '{'|'!'|then|do|else|elif|if|while|until) p=$((p + 1)) ;;
      env|command|exec|builtin|nohup|time|sudo|xargs)
        p=$((p + 1)); nt_skip_wrapper_opts "$base" ;;
      *) break ;;
    esac
  done
  [[ -n "$base" ]] || return 0
  p=$((p + 1))
  [[ "$base" == git ]] && nt_skip_git_globals
  NT[0]="$base"; NA[0]="$base"
  k=$p
  while [[ $k -lt $n ]]; do
    t="${all[$k]}"; k=$((k + 1))
    if [[ "$t" == "$NORM_RM"* ]]; then
      NA[${#NA[@]}]="$t"
      if rd_is_bare "$t" && [[ $k -lt $n ]]; then NA[${#NA[@]}]="${all[$k]}"; k=$((k + 1)); fi
      continue
    fi
    if [[ "$base" == gh ]]; then
      case "$t" in
        -R|--repo) k=$((k + 1)); continue ;;
        --repo=*|-R?*) continue ;;
      esac
    fi
    NT[${#NT[@]}]="$t"; NA[${#NA[@]}]="$t"
  done
  return 0
}

# gh group/verb pairs that write to GitHub (or the local gh config).
gh_is_write() {
  local verbs=""
  case "$1" in
    pr) verbs=" create comment review edit merge close reopen lock unlock ready update-branch --fill " ;;
    issue) verbs=" create comment edit close reopen lock unlock delete transfer pin unpin develop " ;;
    release) verbs=" create edit delete upload " ;;
    repo) verbs=" create fork delete edit sync rename archive unarchive " ;;
    gist) verbs=" create edit delete " ;;
    label) verbs=" create edit delete clone " ;;
    workflow) verbs=" run enable disable " ;;
    run) verbs=" rerun cancel delete " ;;
    secret|variable) verbs=" set delete " ;;
    alias) verbs=" set " ;;
    codespace) verbs=" create " ;;
  esac
  [[ -n "$verbs" && "$verbs" == *" $2 "* ]]
}

curl_mutating_method() {
  local lm
  lm="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  [[ "$lm" != get && "$lm" != head && "$lm" != options ]]
}

# curl: any payload / upload / config-file / non-read method option denies.
check_curl_norm() {
  local raw="$1" i=1 n=${#NT[@]} t rest c val
  while [[ $i -lt $n ]]; do
    t="${NT[$i]}"; i=$((i + 1))
    case "$t" in
      --) break ;;
      --request|--request=*)
        if [[ "$t" == --request ]]; then val="${NT[$i]:-}"; i=$((i + 1)); else val="${t#*=}"; fi
        curl_mutating_method "$val" && deny "curl non-read method: $raw" ;;
      --data|--data=*|--data-*|--json|--json=*|--form|--form=*|--form-*|--upload-file|--upload-file=*|--config|--config=*)
        deny "curl outbound mutation: $raw" ;;
      --*) ;;
      -?*)
        rest="${t#-}"
        while [[ -n "$rest" ]]; do
          c="${rest:0:1}"; rest="${rest:1}"
          case "$c" in
            d|F|T|K) deny "curl outbound mutation: $raw" ;;
            X)
              val="$rest"
              if [[ -z "$val" ]]; then val="${NT[$i]:-}"; i=$((i + 1)); fi
              curl_mutating_method "$val" && deny "curl non-read method: $raw"
              rest="" ;;
            A|b|c|C|D|e|E|H|m|o|P|Q|r|t|u|U|w|x|y|Y|z)
              if [[ -z "$rest" ]]; then i=$((i + 1)); fi
              rest="" ;;
          esac
        done ;;
    esac
  done
  return 0
}

check_wget_norm() {
  local raw="$1" i=1 n=${#NT[@]} t val
  while [[ $i -lt $n ]]; do
    t="${NT[$i]}"; i=$((i + 1))
    case "$t" in
      --body-data|--body-data=*|--body-file|--body-file=*|--post-data|--post-data=*|--post-file|--post-file=*)
        deny "wget outbound mutation: $raw" ;;
      --method|--method=*)
        if [[ "$t" == --method ]]; then val="${NT[$i]:-}"; i=$((i + 1)); else val="${t#*=}"; fi
        curl_mutating_method "$val" && deny "wget non-read method: $raw" ;;
    esac
  done
  return 0
}

# Deny rules on the normalized segment (NT). $1 = original segment text.
check_norm_rules() {
  local raw="$1"
  case "${NT[0]:-}" in
    git)
      case "${NT[1]:-}" in
        push|send-email|send-pack) deny "git ${NT[1]}: $raw" ;;
        svn) [[ "${NT[2]:-}" == dcommit ]] && deny "git svn dcommit: $raw" ;;
      esac ;;
    gh)
      if gh_is_write "${NT[1]:-}" "${NT[2]:-}"; then deny "gh ${NT[1]} ${NT[2]}: $raw"; fi ;;
    curl) check_curl_norm "$raw" ;;
    wget) check_wget_norm "$raw" ;;
  esac
  return 0
}

# Raw (original) and normalized checks for one segment.
check_segment() {
  local seg="$1" full="$2"
  check_gh_api "$seg" "$full"
  [[ "$seg" =~ [^[:space:]] ]] || return 0
  normalize_segment "$seg" || deny "command segment could not be analysed: $seg"
  [[ ${#NT[@]} -gt 0 ]] || return 0
  check_norm_rules "$seg"
  check_gh_api "$seg" "$full" norm
}

# Segment $1 (outer + inner pass) and check every segment, recursing into
# substitution bodies. $2 = full stripped command. Returns 1 if awk fails.
check_cmd_text() {
  local text="$1" full="$2" segments outer_out segment body
  segments="$(printf '%s\n' "$text" | awk "$AWK_SEGMENT" 2>/dev/null)" || return 1
  outer_out="$(printf '%s\n' "$text" | awk -v outer=1 "$AWK_SEGMENT" 2>/dev/null)" || return 1
  while IFS= read -r segment; do
    check_segment "$segment" "$full"
  done <<< "$segments"
  while IFS= read -r segment; do
    if [[ "$segment" == $'\002'* ]]; then
      body="${segment#?}"; body="${body//$'\003'/$'\n'}"
      check_cmd_text "$body" "$full" || return 1
    else
      check_segment "$segment" "$full"
    fi
  done <<< "$outer_out"
  return 0
}

# ── Check Bash commands ───────────────────────────────────────────────────────
if [[ "$tool_name" == "Bash" ]]; then

  # SEP matches "command position": start-of-string or a real shell separator
  # (;  |  &  &&  ||  $(  backtick  newline), optionally followed by whitespace.
  # This prevents plain-space-separated words (e.g. "echo git push") from matching.
  SEP='(^|;|\||&|\&\&|\|\||\$\(|`|'$'\n'')[[:space:]]*'

  # The rules below run on the continuation-joined text; heredoc bodies are
  # included, so text mentioning outbound commands is denied (use the Write tool).

  # git push (any form)
  if [[ "$stripped" =~ $SEP'git'[[:space:]]+'push'([[:space:]]|$) ]]; then
    deny "git push: $command_str"
  fi

  # gh pr create / comment / review / edit / merge / close / reopen / lock / unlock / ready
  if [[ "$stripped" =~ $SEP'gh'[[:space:]]+'pr'[[:space:]]+(create|comment|review|edit|merge|close|reopen|lock|unlock|ready|--fill)([[:space:]]|$) ]]; then
    deny "gh pr mutating subcommand: $command_str"
  fi

  # gh issue create / comment / edit / close / reopen / lock / unlock
  if [[ "$stripped" =~ $SEP'gh'[[:space:]]+'issue'[[:space:]]+(create|comment|edit|close|reopen|lock|unlock)([[:space:]]|$) ]]; then
    deny "gh issue mutating subcommand: $command_str"
  fi

  # gh release create / edit / delete / upload
  if [[ "$stripped" =~ $SEP'gh'[[:space:]]+'release'[[:space:]]+(create|edit|delete|upload)([[:space:]]|$) ]]; then
    deny "gh release mutating subcommand: $command_str"
  fi

  # gh repo create / fork / delete / edit
  if [[ "$stripped" =~ $SEP'gh'[[:space:]]+'repo'[[:space:]]+(create|fork|delete|edit)([[:space:]]|$) ]]; then
    deny "gh repo mutating subcommand: $command_str"
  fi

  # gh gist create (can post content publicly)
  if [[ "$stripped" =~ $SEP'gh'[[:space:]]+'gist'[[:space:]]+'create'([[:space:]]|$) ]]; then
    deny "gh gist create: $command_str"
  fi

  # gh api: evaluated per invocation (segment), not across the whole string.
  # Inner pass splits on substitutions; outer pass keeps substitutions inline so
  # flags after them stay attached, and check_cmd_text recurses into each
  # substitution body the same way. Segmenter failure fails closed.
  # The same walk also runs the normalized-segment rules (wrappers, path-qualified
  # binaries, git/gh global options) for git, gh, curl and wget.
  if ! check_cmd_text "$stripped" "$stripped" &&
     [[ "$stripped" =~ (^|[^[:alnum:]_.-])(gh|git|curl|wget)[[:space:]] ]]; then
    deny "command could not be analysed: $command_str"
  fi

  # curl with mutating methods or data payloads
  if [[ "$stripped" =~ $SEP'curl'[[:space:]] ]]; then
    if [[ "$stripped" =~ [[:space:]]-X[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$stripped" =~ [[:space:]]--request[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$stripped" =~ [[:space:]](-d|--data|--data-raw)[[:space:]] ]] || \
       [[ "$stripped" =~ [[:space:]](-F|--form)[[:space:]] ]]; then
      deny "curl outbound mutation: $command_str"
    fi
  fi

  # wget with mutating methods or data payloads
  if [[ "$stripped" =~ $SEP'wget'[[:space:]] ]]; then
    if [[ "$stripped" =~ [[:space:]]-X[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$stripped" =~ [[:space:]]--request[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$stripped" =~ [[:space:]](-d|--data|--data-raw)[[:space:]] ]] || \
       [[ "$stripped" =~ [[:space:]](-F|--form)[[:space:]] ]] || \
       [[ "$stripped" =~ [[:space:]]--method[[:space:]]+(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$stripped" =~ [[:space:]]--method=(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$stripped" =~ [[:space:]]--post-data[[:space:]=] ]] || \
       [[ "$stripped" =~ [[:space:]]--post-file[[:space:]=] ]]; then
      deny "wget outbound mutation: $command_str"
    fi
  fi

fi

# ── Allow everything else ─────────────────────────────────────────────────────
exit 0
