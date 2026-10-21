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

**Per-invocation handling (v0.3.1) and heredoc bodies (v0.4.0):** `gh api` flags are evaluated per `gh api` invocation (the command is split into segments on newline, `;`, `|`, `&`, `(`, `)`, `$(` and backtick, ignoring separators inside quotes and dropping comments). Before the rules run, backslash-newline continuations are joined. Heredoc bodies are **always checked** as ordinary lines (the v0.3.1 heredoc-body skipping was removed in v0.4.0 because `cat > run.sh <<'EOF' ... EOF` followed by `sh run.sh` could execute a script the guard never saw). A note whose heredoc text mentions an outbound command is therefore denied; use the Write tool to create such files. `gh api` options are parsed from unquoted tokens, and if segmentation fails a `gh api` command is denied. Any other preprocessing failure falls back to the raw command. Regression tests: `bash hooks/tests/run-guard-tests.sh`.

### Limits: a tripwire, not a security boundary

`guard-outbound.sh` reads command **text**. A shell command can be written in endlessly many ways, so text matching cannot block every outbound action. The guard is designed to stop an agent from *accidentally* pushing or posting while it follows normal draft-only instructions. It is not designed to stop a command that is deliberately written to get past it.

Known gaps are recorded as `known-bypass` rows in `hooks/tests/guard-cases.tsv`. They are reported, not counted as failures, and the harness prints a note when one starts being denied. Two kinds:

- **Forms an agent may write by accident** (covered since v0.5.1): global options before the subcommand (`git -C dir push`, `git -c k=v push`, `gh -R owner/repo pr create`), path-qualified binaries (`/usr/bin/git push`, `./gh pr create`), wrapper prefixes and env assignments (`env git push`, `FOO=1 git push`, `command`, `exec`, `builtin`, `nohup`, `time`, `sudo`, `xargs`), and the extra `gh`, `git`, `curl`, and `wget` write forms listed in the matrix below. Each command segment is normalized (wrappers, assignments, path prefix, and global options removed) and checked in addition to the raw text, so normalization can only add denials.
- **Deliberate obfuscation** (not planned): variables (`p=push; git $p`), `eval`, aliases, shell functions, `bash -c "…"` strings, `$(echo git)`, `IFS` and brace-expansion tricks, quoting tricks inside heredocs, and similar. These are realistic only if the agent is manipulated, for example by a prompt injection hidden in an issue, PR, or comment the plugin reads.

**The real boundary is the credentials.** Give the plugin a GitHub token without write permissions (see [GitHub Access](../guides/github-access.md#use-a-read-only-token)). With a read-only token, GitHub itself rejects any write that slips past the guard. `git push` uses your local git credentials instead, which this plugin cannot restrict; keep Claude Code's permission prompts on for commands you have not allowed.

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
| `git push`, `git send-email`, `git send-pack`, `git svn dcommit`, also after global options (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`, `--no-pager`, …), a path-qualified binary, or a wrapper prefix | `git -C dir push`, `/usr/bin/git push`, `env git push` |
| `gh pr create/comment/review/edit/merge/close/reopen/lock/unlock/ready/update-branch/--fill` | `gh pr create --title "…"` |
| `gh issue create/comment/edit/close/reopen/lock/unlock/delete/transfer/pin/unpin/develop` | `gh issue comment 123 --body "…"` |
| `gh release create/edit/delete/upload` | `gh release create v1.0` |
| `gh repo create/fork/delete/edit/sync/rename/archive/unarchive` | `gh repo fork apache/airflow` |
| `gh gist create/edit/delete` | `gh gist create file.txt` |
| `gh label create/edit/delete/clone`, `gh workflow run/enable/disable`, `gh run rerun/cancel/delete`, `gh secret set/delete`, `gh variable set/delete`, `gh alias set`, `gh codespace create` | `gh workflow run ci.yml` |
| any `gh` form above or `gh api` with `-R`/`--repo`, a wrapper prefix, or a path-qualified binary | `gh -R owner/repo pr create`, `./gh pr create` |
| `gh api` with `-X POST/PUT/PATCH/DELETE` (also `-XPOST`, `-X=POST`, any case) | `gh api repos/… -X POST -f …` |
| `gh api` with `--method POST/PUT/PATCH/DELETE` (also `--method=POST`) | `gh api repos/… --method PATCH` |
| `gh api` with `-f` / `-F` / `--field` / `--raw-field` (unless explicit `-X GET`, or a read-only GraphQL query) | `gh api repos/… -f title=…` |
| `gh api` with `--input` (always) | `gh api repos/… --input body.json` |
| `gh api graphql` containing `mutation`, `=@file`, command substitution, or a `query=$VAR` value | `gh api graphql -f query='mutation {…}'` |
| `curl` with `-X`/`--request` and any method other than GET/HEAD/OPTIONS (any case, also `-XPOST`, `--request=POST`) | `curl -X POST https://api.github.com/…` |
| `curl` with `-d`/`--data`/`--data-raw`/`--data-binary`/`--data-urlencode`/`--data=…`/`-dVALUE`/`--json`, `-F`/`--form`/`--form-string`, `-T`/`--upload-file`, or `-K`/`--config` (also inside short-option bundles such as `-sd`) | `curl -d '{"body":"…"}' …` |
| `wget` with mutation flags (`-X`, `--request`, `-d`, `--data`, `--data-raw`, `-F`, `--form`, `--method POST/…` in any case, `--post-data`, `--post-file`, `--body-data`, `--body-file`) | `wget --post-data '…' …` |

### Bash Commands — ALLOW

Everything not matched by a deny pattern:

- `git clone`, `git status`, `git log`, `git diff`, `git fetch`, `git checkout` (local), `git add`, `git commit` (local)
- `gh pr view`, `gh pr list`, `gh pr checks`, `gh pr diff`
- `gh issue view`, `gh issue list`
- `gh release list`, `gh release view`
- `gh api repos/…` (plain GET, no write flags)
- `gh api graphql -f query='query {…}'` (read-only query: no `mutation`, no `=@file`, no `--input`)
- `gh api -X GET search/issues -f q=…` (explicit GET; fields are query parameters)
- Heredocs whose body contains no outbound command text, e.g. `cat > notes.md <<'EOF' … EOF` with plain notes (a body that mentions `git push` or `gh pr create` is denied; use the Write tool)
- `gh auth status`
- Read-only forms with the same prefixes: `git -C dir log`, `/usr/bin/git status`, `env git diff`, `gh -R o/r pr view 1`, `gh label list`, `gh workflow list`, `curl -X GET …`
- Build/test commands: `mvn`, `gradle`, `pytest`, `npm test`, `./breeze`, etc.
- `cat`, `grep`, `find`, `jq`, and other read-only shell commands

---

[Back to docs index](../index.md) | Related: [Draft-Only Guardrail](../concepts/draft-only-guardrail.md) | [Commands](commands.md) | [GitHub Access](../guides/github-access.md)
