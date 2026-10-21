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
# AWK_PREPROCESS joins backslash-newline continuations and drops a heredoc body
# ONLY when it is pure data: consumer is cat/tee, nothing piped or chained after
# the delimiter, no quotes before the operator, no command substitution that
# could execute, and the heredoc is terminated. Bodies fed to bash/sh/zsh/eval/
# xargs/ssh/python/node (or anything else) are kept and still checked.
read -r -d '' AWK_PREPROCESS <<'AWK' || true
function trim(x) { sub(/^[ \t]+/, "", x); sub(/[ \t]+$/, "", x); return x }
function endsbs(x,   k, c) {
  k = length(x); c = 0
  while (k > 0 && substr(x, k, 1) == "\\") { c++; k-- }
  return (c % 2 == 1)
}
function firstword(x) {
  x = trim(x)
  while (match(x, /^[A-Za-z_][A-Za-z0-9_]*=[^ \t]*[ \t]+/)) x = substr(x, RLENGTH + 1)
  if (match(x, /^[^ \t]+/)) return substr(x, 1, RLENGTH)
  return ""
}
function ok_consumer(pre,   k, idx, piece, w) {
  if (index(pre, "(") || index(pre, "`") || index(pre, "'") || index(pre, "\"") || index(pre, "\\")) return 0
  idx = 0
  for (k = length(pre); k >= 1; k--) {
    if (index(";|&", substr(pre, k, 1))) { idx = k; break }
  }
  piece = substr(pre, idx + 1)
  w = firstword(piece)
  return (w == "cat" || w == "tee")
}
function ok_rest(rest) {
  gsub(/[0-9]*>&[0-9-]*/, "", rest)
  if (rest ~ /[|;&`$()<'"\\]/) return 0
  return 1
}
BEGIN { sq = "\047"; dq = "\042" }
{ L[++n] = $0 }
END {
  q = ""; nodrop = 0; i = 1; cnt = 0; pdepth = 0; bt = 0
  while (i <= n) {
    line = L[i]; i++
    d0 = pdepth; bt0 = bt
    while (q != sq && endsbs(line) && i <= n) { line = substr(line, 1, length(line) - 1) L[i]; i++ }
    len = length(line); j = 1; hd = 0
    while (j <= len) {
      c = substr(line, j, 1)
      if (q == sq) { if (c == sq) q = ""; j++; continue }
      if (c == "\\") { j += 2; continue }
      if (q == dq) {
        if (c == dq) q = ""
        else if (c == "`" || (c == "$" && substr(line, j + 1, 1) == "(")) nodrop = 1
        j++; continue
      }
      if (c == sq || c == dq) { q = c; j++; continue }
      if (c == "(") pdepth++
      else if (c == ")") { if (pdepth > 0) pdepth-- }
      else if (c == "`") bt = !bt
      if (c == "#" && (j == 1 || substr(line, j - 1, 1) ~ /[ \t;|&(]/)) break
      if (c == "<" && substr(line, j + 1, 1) == "<" && substr(line, j - 1, 1) != "<" && substr(line, j + 2, 1) != "<") {
        if (hd) { nodrop = 1; j += 2; continue }
        k = j + 2; tabs = 0
        if (substr(line, k, 1) == "-") { tabs = 1; k++ }
        while (substr(line, k, 1) == " " || substr(line, k, 1) == "\t") k++
        delim = ""; quoted = 0; qq = ""
        while (k <= len) {
          ch = substr(line, k, 1)
          if (qq != "") { if (ch == qq) qq = ""; else delim = delim ch; k++; continue }
          if (ch == sq || ch == dq) { qq = ch; quoted = 1; k++; continue }
          if (ch == "\\") { quoted = 1; k++; delim = delim substr(line, k, 1); k++; continue }
          if (ch ~ /[ \t;|&<>()]/) break
          delim = delim ch; k++
        }
        if (qq != "") nodrop = 1
        if (delim != "" && qq == "") { hd = 1; hpos = j; jend = k }
        j = (k > j + 2 ? k : j + 2); continue
      }
      j++
    }
    out[++cnt] = line
    # Inside an enclosing $( ), <( ), ( ) or backtick the body may be consumed
    # by an outer command (e.g. bash < <(cat <<EOF ...)): keep it.
    if (hd && q == "") {
      t = 0
      for (m = i; m <= n; m++) {
        cmp = L[m]
        if (tabs) sub(/^\t+/, "", cmp)
        if (cmp == delim) { t = m; break }
      }
      if (t) {
        drop = !nodrop && d0 == 0 && !bt0 && ok_consumer(substr(line, 1, hpos - 1)) && ok_rest(substr(line, jend))
        if (drop && !quoted) {
          for (m = i; m < t; m++) if (index(L[m], "$(") || index(L[m], "`")) { drop = 0; break }
        }
        if (!drop) { for (m = i; m <= t; m++) out[++cnt] = L[m] }
        i = t + 1
      }
    }
  }
  for (m = 1; m <= cnt; m++) print out[m]
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

# Heredoc-stripped, continuation-joined text. Any awk failure -> raw command
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
# $1 = this gh api segment, $2 = the full (heredoc-stripped) command.
# GH_FIELDS holds the parsed -f/-F/--field/--raw-field values (quotes removed).
graphql_readonly() {
  local seg="$1" full="$2" full_nq unq v lv
  # Lowercase, quotes/backslashes removed so mu""tation cannot hide the keyword.
  full_nq="$(printf '%s' "$full" | tr 'A-Z' 'a-z' | tr -d "\"'\\\\")"
  [[ "$full_nq" == *mutation* ]] && return 1
  [[ "$full" == *'$('* || "$full" == *'`'* ]] && return 1
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
  [[ "$unq" =~ \$[A-Za-z_\{] ]] && return 1
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
  seg="$(strip_prefix "$raw")"
  [[ "$seg" =~ ^gh[[:space:]]+api([[:space:]]|$) ]] || return 0

  if ! tok_out="$(printf '%s\n' "$seg" | awk "$AWK_TOKENIZE" 2>/dev/null)"; then
    deny "gh api (unparseable): $raw"
  fi
  while IFS= read -r t; do toks[${#toks[@]}]="$t"; done <<< "$tok_out"
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

# Segment $1 (outer + inner pass) and check every gh api invocation, recursing
# into substitution bodies. $2 = full stripped command. Returns 1 if awk fails.
check_gh_text() {
  local text="$1" full="$2" segments outer_out segment body
  segments="$(printf '%s\n' "$text" | awk "$AWK_SEGMENT" 2>/dev/null)" || return 1
  outer_out="$(printf '%s\n' "$text" | awk -v outer=1 "$AWK_SEGMENT" 2>/dev/null)" || return 1
  while IFS= read -r segment; do
    check_gh_api "$segment" "$full"
  done <<< "$segments"
  while IFS= read -r segment; do
    if [[ "$segment" == $'\002'* ]]; then
      body="${segment#?}"; body="${body//$'\003'/$'\n'}"
      check_gh_text "$body" "$full" || return 1
    else
      check_gh_api "$segment" "$full"
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

  # The rules below run on the heredoc-stripped text so that data written via
  # `cat > file <<'EOF'` is not mistaken for commands.

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
  # flags after them stay attached, and check_gh_text recurses into each
  # substitution body the same way. Segmenter failure fails closed.
  if [[ "$stripped" == *api* ]]; then
    if ! check_gh_text "$stripped" "$stripped" &&
       [[ "$stripped" =~ (^|[^[:alnum:]_.-])gh[[:space:]] ]]; then
      deny "gh api (command could not be analysed): $command_str"
    fi
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
