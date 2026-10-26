# Draft-Only Guardrail

The human-in-the-loop principle, what the guardrail blocks versus allows, why it denies rather than asks, and how it connects to the execution plugin.

## Human-in-the-Loop Principle

Every piece of outbound text produced by this plugin — a claim comment, a set of maintainer questions, PR feedback, review replies — is a **draft**. The user reviews and edits the draft; the execution/submission plugin performs the actual posting only after explicit approval.

This is not just a convention in the command instructions. It is enforced at the tool level by a `PreToolUse` hook that runs before every `Bash` call and every GitHub MCP tool call.

Advisory hooks (`track-checkpoint.sh`, `track-breakpoint.sh`) are not part of the guardrail; see [Tracked Sessions & Checkpoints](tracked-sessions.md).

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
| Read tools: suffix (after the last `__`) matching `get_*`, `list_*`, `search_*`, or one of the two named read tools `issue_read` and `pull_request_read`, e.g. `get_me`, `get_file_contents`, `list_issues`, `search_code` | ALLOW |
| A read-prefixed suffix that also contains `write`, `create`, `delete`, `submit`, or `fork` | DENY |
| **Every other** `mcp__plugin_agentic-contributor_github__*` tool (default-deny), e.g. `issue_write`, `pull_request_review_write`, `add_issue_comment`, `add_comment_to_pending_review`, `mark_all_notifications_read`, `create_pull_request`, `create_branch`, `create_or_update_file`, `delete_file`, `push_files`, `merge_pull_request`, `update_pull_request`, `fork_repository`, `sub_issue_write`, `assign_copilot_to_issue`, `request_copilot_review`, and any tool added upstream later | DENY |

### Bash Commands

| Pattern | Decision |
|---|---|
| `git push` (any form, at command position, also after global options like `-C`, a path-qualified binary, or a wrapper such as `env`/`sudo`/`xargs`); `git send-email`, `git send-pack`, `git svn dcommit`; `git -c alias.<name>=…` whose value pushes/sends or starts with `!` | DENY |
| `gh pr create / comment / review / edit / merge / close / reopen / lock / unlock / ready / update-branch / revert / --fill` | DENY |
| `gh issue create / comment / edit / close / reopen / lock / unlock / delete / transfer / pin / unpin / develop` | DENY |
| `gh release create / edit / delete / delete-asset / upload` | DENY |
| `gh repo create / fork / delete / edit / sync / rename / archive / unarchive`, `gh repo deploy-key add / delete`, `gh repo autolink create / delete` | DENY |
| `gh gist create / edit / delete / rename` | DENY |
| `gh label create / edit / delete / clone`, `gh workflow run / enable / disable`, `gh run rerun / cancel / delete`, `gh secret` and `gh variable set / delete`, `gh alias set / delete / import`, `gh codespace create / delete / edit / stop / rebuild` (also with `-R`/`--repo`) | DENY |
| `gh project create / edit / delete / close / copy / link / unlink / mark-template / item-add / item-create / item-edit / item-delete / item-archive / field-create / field-delete`, `gh ssh-key add / delete`, `gh gpg-key add / delete`, `gh cache delete` | DENY |
| `gh api` with `-X POST/PUT/PATCH/DELETE` or `--method POST/PUT/PATCH/DELETE` (including `-XPOST`, `--method=POST`) | DENY |
| `gh api` with `-f` / `-F` / `--field` / `--raw-field` (except explicit `-X GET` or a read-only GraphQL query) | DENY |
| `gh api` with `--input`; `gh api graphql` with `mutation`, `=@file`, or shell expansion in the query | DENY |
| `curl` with a non-read `-X`/`--request` method, `-d`/`--data*`/`--json`, `-F`/`--form*`, `-T`/`--upload-file`, or `-K`/`--config` | DENY |
| `wget` with any mutation flag | DENY |
| `git -C dir log`, `/usr/bin/git status`, `env git diff`, `gh -R o/r pr view`, `gh label list`, `gh workflow list`, `curl` GET, `gh pr view`, `gh issue list`, `gh release list`, `gh project list / view`, `gh ssh-key list`, `gh cache list`, `gh repo set-default`, plain `gh api` GET, read-only `gh api graphql` queries, `gh api -X GET ... -f q=...` | ALLOW |
| Heredoc bodies are always checked: a body containing an outbound command (even via `cat > file <<EOF`) | DENY |
| Heredoc whose body has no outbound command text | ALLOW |
| `git clone`, `git status`, `git log`, `git diff`, `git fetch` | ALLOW |
| All other read/build/test commands | ALLOW |

**Command-position matching:** The deny patterns for `git push` and `gh` subcommands match only at command position (start of string or after a real shell separator: `;`, `|`, `&`, `&&`, `||`, `$(`, backtick, newline). This prevents false positives from commands like `echo "git push"`.

## What the Guardrail Does Not Cover

The hook matches command text, so it catches the ordinary ways an agent writes outbound commands, not every possible way. Treat it as a tripwire against accidental pushes and posts. The real boundary is a GitHub token **without write permissions**: with one, GitHub rejects any write that gets past the hook. Known gaps and the recommended setup are listed in [Hooks Reference — Limits](../reference/hooks.md#limits-a-tripwire-not-a-security-boundary).

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

The `.oss-drafts/` directory is automatically excluded from version control via the repo's exclude file
(`git rev-parse --git-path info/exclude`) on the first write (non-invasive — does not dirty the user's tracked `.gitignore`).

See [Draft Files](draft-files.md) for the naming convention, frontmatter schema, and per-scenario
file paths.

## Hand-off to the Execution Plugin

When you are ready to send a reviewed draft, switch to the separate execution/submission plugin. That plugin uses `gh` CLI commands such as `gh issue comment --body "..."` and `gh pr create` to perform the actual actions after your final confirmation.

See [Two-Plugin System](two-plugin-system.md) for the full boundary description.

---

[Back to docs index](../index.md) | Related: [Two-Plugin System](two-plugin-system.md) | [Hooks Reference](../reference/hooks.md) | [GitHub Access](../guides/github-access.md)
