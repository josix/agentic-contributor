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

# ── Check Bash commands ───────────────────────────────────────────────────────
if [[ "$tool_name" == "Bash" ]]; then

  # SEP matches "command position": start-of-string or a real shell separator
  # (;  |  &  &&  ||  $(  backtick  newline), optionally followed by whitespace.
  # This prevents plain-space-separated words (e.g. "echo git push") from matching.
  SEP='(^|;|\||&|\&\&|\|\||\$\(|`|'$'\n'')[[:space:]]*'

  # git push (any form)
  if [[ "$command_str" =~ $SEP'git'[[:space:]]+'push'([[:space:]]|$) ]]; then
    deny "git push: $command_str"
  fi

  # gh pr create / comment / review / edit / merge / close / reopen / lock / unlock / ready
  if [[ "$command_str" =~ $SEP'gh'[[:space:]]+'pr'[[:space:]]+(create|comment|review|edit|merge|close|reopen|lock|unlock|ready|--fill)([[:space:]]|$) ]]; then
    deny "gh pr mutating subcommand: $command_str"
  fi

  # gh issue create / comment / edit / close / reopen / lock / unlock
  if [[ "$command_str" =~ $SEP'gh'[[:space:]]+'issue'[[:space:]]+(create|comment|edit|close|reopen|lock|unlock)([[:space:]]|$) ]]; then
    deny "gh issue mutating subcommand: $command_str"
  fi

  # gh release create / edit / delete / upload
  if [[ "$command_str" =~ $SEP'gh'[[:space:]]+'release'[[:space:]]+(create|edit|delete|upload)([[:space:]]|$) ]]; then
    deny "gh release mutating subcommand: $command_str"
  fi

  # gh repo create / fork / delete / edit
  if [[ "$command_str" =~ $SEP'gh'[[:space:]]+'repo'[[:space:]]+(create|fork|delete|edit)([[:space:]]|$) ]]; then
    deny "gh repo mutating subcommand: $command_str"
  fi

  # gh gist create (can post content publicly)
  if [[ "$command_str" =~ $SEP'gh'[[:space:]]+'gist'[[:space:]]+'create'([[:space:]]|$) ]]; then
    deny "gh gist create: $command_str"
  fi

  # gh api with mutating HTTP methods: -X POST/PUT/PATCH/DELETE or --method POST/PUT/PATCH/DELETE
  if [[ "$command_str" =~ $SEP'gh'[[:space:]]+'api'[[:space:]] ]]; then
    if [[ "$command_str" =~ [[:space:]]-X[[:space:]]+(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]]--method[[:space:]]+(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]]-f[[:space:]] ]] || \
       [[ "$command_str" =~ [[:space:]]--field[[:space:]] ]]; then
      deny "gh api mutating call: $command_str"
    fi
  fi

  # curl with mutating methods or data payloads
  if [[ "$command_str" =~ $SEP'curl'[[:space:]] ]]; then
    if [[ "$command_str" =~ [[:space:]]-X[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]]--request[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]](-d|--data|--data-raw)[[:space:]] ]] || \
       [[ "$command_str" =~ [[:space:]](-F|--form)[[:space:]] ]]; then
      deny "curl outbound mutation: $command_str"
    fi
  fi

  # wget with mutating methods or data payloads
  if [[ "$command_str" =~ $SEP'wget'[[:space:]] ]]; then
    if [[ "$command_str" =~ [[:space:]]-X[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]]--request[[:space:]]*(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]](-d|--data|--data-raw)[[:space:]] ]] || \
       [[ "$command_str" =~ [[:space:]](-F|--form)[[:space:]] ]] || \
       [[ "$command_str" =~ [[:space:]]--method[[:space:]]+(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]]--method=(POST|PUT|PATCH|DELETE) ]] || \
       [[ "$command_str" =~ [[:space:]]--post-data[[:space:]=] ]] || \
       [[ "$command_str" =~ [[:space:]]--post-file[[:space:]=] ]]; then
      deny "wget outbound mutation: $command_str"
    fi
  fi

fi

# ── Allow everything else ─────────────────────────────────────────────────────
exit 0
