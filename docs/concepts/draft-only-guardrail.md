# Draft-Only Guardrail

The human-in-the-loop principle, what the guardrail blocks versus allows, why it denies rather than asks, and how it connects to the execution plugin.

## Human-in-the-Loop Principle

Every piece of outbound text produced by this plugin — a claim comment, a set of maintainer questions, PR feedback, review replies — is a **draft**. The user reviews and edits the draft; the execution/submission plugin performs the actual posting only after explicit approval.

This is not just a convention in the command instructions. It is enforced at the tool level by a `PreToolUse` hook that runs before every `Bash` call and every GitHub MCP tool call.

## How the Guardrail Works

`hooks/hooks.json` registers a `PreToolUse` hook that matches `Bash|mcp__plugin_agentic-contributor_github__.*` and calls `hooks/scripts/guard-outbound.sh` before the tool executes.

The script:
1. Reads the tool-use JSON from stdin.
2. Extracts `tool_name` and `tool_input.command` (using `jq`, then `python3`, then `grep` as a fallback).
3. Checks the tool name and command against the deny patterns below.
4. Exits `2` (deny) with a JSON message on stderr, or exits `0` (allow).

The denial message states:

> "This plugin is DRAFT-ONLY. The drafted content is ready for your review, but sending/posting/pushing is handled by the separate execution/submission plugin. Blocked action: [description]"

## Full Deny / Allow Matrix

### MCP Tools

| Pattern | Decision |
|---|---|
| `mcp__plugin_agentic-contributor_github__create` | DENY |
| `mcp__plugin_agentic-contributor_github__update` | DENY |
| `mcp__plugin_agentic-contributor_github__delete` | DENY |
| `mcp__plugin_agentic-contributor_github__merge` | DENY |
| `mcp__plugin_agentic-contributor_github__add_comment` | DENY |
| `mcp__plugin_agentic-contributor_github__add_issue_comment` | DENY |
| `mcp__plugin_agentic-contributor_github__add_sub_issue` | DENY |
| `mcp__plugin_agentic-contributor_github__push` | DENY |
| `mcp__plugin_agentic-contributor_github__fork` | DENY |
| `mcp__plugin_agentic-contributor_github__assign` | DENY |
| `mcp__plugin_agentic-contributor_github__transfer` | DENY |
| `mcp__plugin_agentic-contributor_github__lock` / `unlock` | DENY |
| `mcp__plugin_agentic-contributor_github__submit` | DENY |
| `mcp__plugin_agentic-contributor_github__dispatch` | DENY |
| `mcp__plugin_agentic-contributor_github__edit` | DENY |
| `mcp__plugin_agentic-contributor_github__create_or_update` | DENY |
| `mcp__plugin_agentic-contributor_github__create_pull_request` | DENY |
| `mcp__plugin_agentic-contributor_github__create_branch` | DENY |
| `mcp__plugin_agentic-contributor_github__create_repository` | DENY |
| `mcp__plugin_agentic-contributor_github__request_copilot` | DENY |
| All other `mcp__plugin_agentic-contributor_github__*` read tools | ALLOW |

### Bash Commands

| Pattern | Decision |
|---|---|
| `git push` (any form, at command position) | DENY |
| `gh pr create / comment / review / edit / merge / close / reopen / lock / unlock / ready / --fill` | DENY |
| `gh issue create / comment / edit / close / reopen / lock / unlock` | DENY |
| `gh release create / edit / delete / upload` | DENY |
| `gh repo create / fork / delete / edit` | DENY |
| `gh gist create` | DENY |
| `gh api` with `-X POST/PUT/PATCH/DELETE` or `--method POST/PUT/PATCH/DELETE` | DENY |
| `gh api` with `-f` / `--field` flags | DENY |
| `curl` with `-X POST/PUT/PATCH/DELETE`, `--request POST/…`, `-d`/`--data`/`--data-raw`, `-F`/`--form` | DENY |
| `wget` with any mutation flag | DENY |
| `gh pr view`, `gh issue list`, `gh release list`, plain `gh api` GET | ALLOW |
| `git clone`, `git status`, `git log`, `git diff`, `git fetch` | ALLOW |
| All other read/build/test commands | ALLOW |

**Command-position matching:** The deny patterns for `git push` and `gh` subcommands match only at command position (start of string or after a real shell separator: `;`, `|`, `&`, `&&`, `||`, `$(`, backtick, newline). This prevents false positives from commands like `echo "git push"`.

## Why Deny, Not Ask

The hook exits `2` (deny) rather than asking a follow-up question. The reasons:

1. **Unambiguous intent:** If a subagent constructs a `gh pr create` call, it has clearly stepped outside the read-only boundary. There is nothing to clarify.
2. **Fail safe:** Denying unconditionally means a bug in command instructions cannot accidentally post on the user's behalf.
3. **User trust:** The user must be in the loop for any outbound action. A denial that refers them to the execution plugin preserves that contract explicitly.

## Local Draft File Writes

The `/oss` command saves all scenario outputs to `.oss-drafts/` in your working directory using
the Write tool. The Write tool is restricted to paths under `.oss-drafts/` only — it is never
used for any other path. This is explicitly permitted and does **not** violate the draft-only
constraint:

- The Write tool writes to the local filesystem only.
- Local file writes cannot reach GitHub, post comments, push branches, or trigger any outbound action.
- The guardrail hook does not intercept Write tool calls (it matches only `Bash` and `mcp__plugin_agentic-contributor_github__*` tools).

The `.oss-drafts/` directory is automatically excluded from version control via `.git/info/exclude`
on the first write (non-invasive — does not dirty the user's tracked `.gitignore`).

See [Draft Files](draft-files.md) for the naming convention, frontmatter schema, and per-scenario
file paths.

## Hand-off to the Execution Plugin

When you are ready to send a reviewed draft, switch to the separate execution/submission plugin. That plugin uses `gh` CLI commands such as `gh issue comment --body "..."` and `gh pr create` to perform the actual actions after your final confirmation.

See [Two-Plugin System](two-plugin-system.md) for the full boundary description.

---

[Back to docs index](../index.md) | Related: [Two-Plugin System](two-plugin-system.md) | [Hooks Reference](../reference/hooks.md) | [GitHub Access](../guides/github-access.md)
