# Hooks Reference

The draft-only `PreToolUse` guardrail: registration, matcher, and the full deny/allow matrix.

## Overview

The `agentic-contributor` plugin registers one hook type: a `PreToolUse` hook that runs before every `Bash` call and every GitHub MCP tool call. It enforces the draft-only contract by denying outbound and mutating actions before they execute.

## Registration (`hooks/hooks.json`)

```json
{
  "description": "Draft-only guardrail: blocks all outbound/mutating actions …",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|mcp__plugin_agentic-contributor_github__.*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/guard-outbound.sh",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Matcher:** `Bash|mcp__plugin_agentic-contributor_github__.*` — matches all Bash tool calls and all GitHub MCP tool calls namespaced to this plugin.

**Timeout:** 10 seconds. The script runs in well under 1 second in practice (pure bash string matching, no network calls).

## `guard-outbound.sh` Logic

The script reads the tool-use JSON from stdin, extracts `tool_name` and `tool_input.command`, then checks against deny patterns.

**JSON parsing order:** `jq` → `python3` → `grep` (last resort). This ensures the script works even when `jq` is not installed, though `jq` is the recommended prerequisite.

**Exit codes:**
- `0` = allow (read-only / safe operation)
- `2` = deny (outbound/mutating action blocked)

**Denial output:** JSON emitted to stderr with `permissionDecision: "deny"` and a message explaining the draft-only contract and the existence of the execution/submission plugin.

**Command-position safety:** Deny patterns for `git push` and `gh` subcommands use a shell regex that matches only at real command positions (start of string or after `;`, `|`, `&`, `&&`, `||`, `$(`, backtick, newline). This prevents false positives from strings like `echo "gh issue create"`.

## Deny / Allow Matrix

### MCP Write Tools — DENY

The script extracts the suffix after the last `__` and matches it against the write-verb list:

```
create | update | delete | merge | add_comment | add_issue_comment | add_sub_issue |
push | fork | request_copilot | create_or_update | create_pull_request |
create_branch | create_repository | assign | transfer | lock | unlock |
submit | dispatch | edit
```

Any `mcp__plugin_agentic-contributor_github__` tool whose suffix matches any of these verbs is denied. All other MCP tools (all read tools) are allowed immediately.

### MCP Read Tools — ALLOW

Any `mcp__plugin_agentic-contributor_github__` tool whose suffix does not match a write verb. Examples: `list_issues`, `get_pull_request`, `get_file_contents`, `list_releases`, `search_repositories`, `search_issues`, `list_pull_requests`.

### Bash Commands — DENY

| Pattern checked | Blocked example |
|---|---|
| `git push` at command position | `git push origin main` |
| `gh pr create/comment/review/edit/merge/close/reopen/lock/unlock/ready/--fill` | `gh pr create --title "…"` |
| `gh issue create/comment/edit/close/reopen/lock/unlock` | `gh issue comment 123 --body "…"` |
| `gh release create/edit/delete/upload` | `gh release create v1.0` |
| `gh repo create/fork/delete/edit` | `gh repo fork apache/airflow` |
| `gh gist create` | `gh gist create file.txt` |
| `gh api` with `-X POST/PUT/PATCH/DELETE` | `gh api repos/… -X POST -f …` |
| `gh api` with `--method POST/PUT/PATCH/DELETE` | `gh api repos/… --method PATCH` |
| `gh api` with `-f` / `--field` flags | `gh api repos/… -f title=…` |
| `curl` with `-X POST/PUT/PATCH/DELETE` or `--request POST/…` | `curl -X POST https://api.github.com/…` |
| `curl` with `-d`/`--data`/`--data-raw` or `-F`/`--form` | `curl -d '{"body":"…"}' …` |
| `wget` with mutation flags (`-X`, `--request`, `-d`, `--data`, `--data-raw`, `-F`, `--form`, `--method POST/…`, `--post-data`, `--post-file`) | `wget --post-data '…' …` |

### Bash Commands — ALLOW

Everything not matched by a deny pattern:

- `git clone`, `git status`, `git log`, `git diff`, `git fetch`, `git checkout` (local), `git add`, `git commit` (local)
- `gh pr view`, `gh pr list`, `gh pr checks`, `gh pr diff`
- `gh issue view`, `gh issue list`
- `gh release list`, `gh release view`
- `gh api repos/…` (plain GET, no write flags)
- `gh auth status`
- Build/test commands: `mvn`, `gradle`, `pytest`, `npm test`, `./breeze`, etc.
- `cat`, `grep`, `find`, `jq`, and other read-only shell commands

---

[Back to docs index](../index.md) | Related: [Draft-Only Guardrail](../concepts/draft-only-guardrail.md) | [Commands](commands.md) | [GitHub Access](../guides/github-access.md)
