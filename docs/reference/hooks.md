# Hooks Reference

The draft-only `PreToolUse` guardrail: registration, matcher, and the full deny/allow matrix.

## Overview

The `agentic-contributor` plugin registers one hook type: a `PreToolUse` hook that runs before every `Bash` call and every GitHub MCP tool call. It enforces the draft-only contract by denying outbound and mutating actions before they execute.

!!! warning "The guard applies to every session where the plugin is enabled"
    The hook is registered by the plugin, not by `/oss`, so it checks every `Bash` call in every
    Claude Code session while `agentic-contributor` is enabled, including work that has nothing to
    do with `/oss`. In those sessions `git push`, `gh pr create`, and the other commands below are
    denied too, and so are write tools on any GitHub MCP server (for example
    `mcp__github__create_pull_request`). To push or open a PR from Claude Code, run the command yourself in a terminal, or
    disable the plugin via `/plugin` and restart the session (hooks are registered at session
    start); re-enable it the same way.

## Registration (`hooks/hooks.json`)

```json
{
  "description": "Draft-only guardrail: blocks all outbound/mutating actions …",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|mcp__.*[Gg][Ii][Tt][Hh][Uu][Bb].*__.*",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/guard-outbound.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

**Matcher:** `Bash|mcp__.*[Gg][Ii][Tt][Hh][Uu][Bb].*__.*` — matches all Bash tool calls and every GitHub MCP tool call: this plugin's own server and any other MCP server with "github" in its name (for example `mcp__github__*`), so a separately installed GitHub server cannot be used to post.

**Timeout:** 30 seconds. Typical commands finish in well under 1 second (bash string matching plus a few `awk` passes, no network calls). A command that contains none of the trigger words `gh`, `git`, `curl`, or `wget` (checked case-insensitively after deleting quotes, backslashes, and newlines, so `g\it` or `"g"it` still count) is allowed immediately. Segments without a trigger word are skipped one by one, so a 400-line script that runs `git` on every line still finishes in a few seconds. The guard fails closed on very large input rather than running into the timeout (which would allow the command): a command of more than 64 KiB, one with more than 2000 shell separators (`;`, `|`, `&`, parentheses, backticks, newlines, counted before parsing), or one with more than 500 segments that contain a trigger word as a whole word (`height` or `github` do not count), is denied with "command too large to analyse safely; split it into smaller commands (or write a script with the Write tool and run it)". Any analysis still running after 10 seconds is denied the same way, because a timeout would allow the command, so the guard never relies on it. The 30-second timeout leaves headroom for slow machines.

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

- **Forms an agent may write by accident** (covered since v0.5.1): global options before the subcommand (`git -C dir push`, `git -c k=v push`, `gh -R owner/repo pr create`), path-qualified binaries (`/usr/bin/git push`, `./gh pr create`), wrapper prefixes and env assignments (`env git push`, `FOO=1 git push`, `command`, `exec`, `builtin`, `nohup`, `time`, `sudo`, `xargs`, `timeout`, `nice`, `ionice`, `stdbuf`, `setsid`, `caffeinate`, `doas`, `watch`, `unbuffer`, `flock`, `chrt`, `taskset`, `coproc`), dashed git binaries (`/usr/libexec/git-core/git-push`, `git-send-email`), and the extra `gh`, `git`, `curl`, and `wget` write forms listed in the matrix below. Each command segment is normalized (wrappers, assignments, path prefix, and global options removed) and checked in addition to the raw text, so normalization can only add denials.
- **Indirect routes and other tools** (not planned): commands run by another program (`find -exec git push`, `xargs git` with the subcommand on stdin), persistent git aliases (`git config alias.x push` then `git x`), `gh` extensions (`gh extension install …` and running one), and other forge CLIs (`hub`, `glab`). The read-only token is the boundary for these.
- **Deliberate obfuscation** (not planned): variables (`p=push; git $p`), `eval`, aliases, shell functions, `bash -c "…"` strings (and the same class: `flock FILE -c "…"`, `watch "…"`), `$(echo git)`, `IFS` and brace-expansion tricks, quoting tricks inside heredocs, and similar. These are realistic only if the agent is manipulated, for example by a prompt injection hidden in an issue, PR, or comment the plugin reads.

**The real boundary is the credentials.** Give the plugin a GitHub token without write permissions (see [GitHub Access](../guides/github-access.md#use-a-read-only-token)). With a read-only token, GitHub itself rejects any write that slips past the guard. `git push` uses your local git credentials instead, which this plugin cannot restrict; keep Claude Code's permission prompts on for commands you have not allowed.

## Deny / Allow Matrix

### MCP Tools — default DENY, read allowlist

Every GitHub MCP server is **default-deny**: this plugin's own and any other server whose name contains `github` in any case. The script takes the tool-name suffix after the last `__` and allows it only when it names a read tool:

```
get_*  |  list_*  |  search_*  |  issue_read  |  pull_request_read
```

There is no generic `*_read` rule: `mark_all_notifications_read` mutates, so only the two named read tools pass. Even with one of those prefixes, a suffix that contains `write`, `create`, `delete`, `submit`, or `fork` is denied. A suffix with characters other than `a-z`, `0-9`, and `_` is denied too. Every other tool is denied, including tools the upstream GitHub MCP server adds later.

**ALLOW examples:** `get_me`, `get_file_contents`, `get_commit`, `list_issues`, `list_pull_requests`, `list_releases`, `search_code`, `search_issues`, `search_repositories`, `issue_read`, `pull_request_read`.

**DENY examples:** `mark_all_notifications_read`, `dismiss_notification`, `manage_notification_subscription`, `issue_write`, `sub_issue_write`, `pull_request_review_write`, `add_issue_comment`, `add_comment_to_pending_review`, `create_pull_request`, `create_branch`, `create_repository`, `create_or_update_file`, `delete_file`, `push_files`, `merge_pull_request`, `update_pull_request`, `update_pull_request_branch`, `fork_repository`, `assign_copilot_to_issue`, `request_copilot_review`.

### Bash Commands — DENY

| Pattern checked | Blocked example |
|---|---|
| `git push` at command position | `git push origin main` |
| `git push`, `git send-email`, `git send-pack`, `git svn dcommit`, `git subtree push`, `git lfs push`, `git p4 submit`, also after global options (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`, `--no-pager`, …), a path-qualified binary, or a wrapper prefix | `git -C dir push`, `/usr/bin/git push`, `env git push` |
| `env -S` / `--split-string` (any spelling, including `-iS` and abbreviations) in a command that mentions gh/git/curl/wget; the string is not analysed, so it is denied | `env -S "git push origin main"` |
| `git -c alias.<name>=<value>` whose value contains `push`, `send-email`, `send-pack`, or `dcommit`, or starts with `!` (shell alias) | `git -c alias.p=push p origin main` |
| `gh pr create/comment/review/edit/merge/close/reopen/lock/unlock/ready/update-branch/revert/--fill`; built-in aliases are canonicalised first: `new` = `create`, `remove`/`rm` = `delete`, `cs` = `codespace` | `gh pr create --title "…"`, `gh pr new` |
| `gh issue create/comment/edit/close/reopen/lock/unlock/delete/transfer/pin/unpin/develop` | `gh issue comment 123 --body "…"` |
| `gh release create/edit/delete/delete-asset/upload` | `gh release create v1.0` |
| `gh repo create/fork/delete/edit/sync/rename/archive/unarchive`, `gh repo deploy-key add/delete`, `gh repo autolink create/delete` | `gh repo fork apache/airflow` |
| `gh gist create/edit/delete/rename` | `gh gist create file.txt` |
| `gh label create/edit/delete/clone`, `gh workflow run/enable/disable`, `gh run rerun/cancel/delete`, `gh secret set/delete`, `gh variable set/delete`, `gh alias set/delete/import`, `gh codespace create/delete/edit/stop/rebuild`, `gh agent-task` (aliases `agent-tasks`, `agent`, `agents`) with any subcommand other than `list`/`view` (`create` starts a Copilot coding-agent task that opens a PR) | `gh workflow run ci.yml`, `gh agent-task create "…"` |
| `gh project create/edit/delete/close/copy/link/unlink/mark-template/item-add/item-create/item-edit/item-delete/item-archive/field-create/field-delete`, `gh ssh-key add/delete`, `gh gpg-key add/delete`, `gh cache delete` | `gh project item-add 1 --url …` |
| any `gh` form above or `gh api` with `-R`/`--repo`, a wrapper prefix, or a path-qualified binary | `gh -R owner/repo pr create`, `./gh pr create` |
| `gh api` with `-X POST/PUT/PATCH/DELETE` (also `-XPOST`, `-X=POST`, any case) | `gh api repos/… -X POST -f …` |
| `gh api` with `--method POST/PUT/PATCH/DELETE` (also `--method=POST`) | `gh api repos/… --method PATCH` |
| `gh api` with `-f` / `-F` / `--field` / `--raw-field` (unless explicit `-X GET`, or a read-only GraphQL query) | `gh api repos/… -f title=…` |
| `gh api` with `--input` (always) | `gh api repos/… --input body.json` |
| `gh api graphql` containing `mutation`, `=@file`, command substitution, or a `query=$VAR` value | `gh api graphql -f query='mutation {…}'` |
| `curl` with `-X`/`--request` and any method other than GET/HEAD/OPTIONS (any case, also `-XPOST`, `--request=POST`) | `curl -X POST https://api.github.com/…` |
| `curl` with `-d`/`--data`/`--data-raw`/`--data-binary`/`--data-urlencode`/`--data=…`/`-dVALUE`/`--json`, `-F`/`--form`/`--form-string`, `-T`/`--upload-file`, or `-K`/`--config` (also inside short-option bundles such as `-sd`, and the curl 8.3+ `--expand-<option>` forms such as `--expand-data`). Data options combined with `-G`/`--get` are query parameters and are allowed (`curl -G -d q=x …`); `-F`, `--json`, `-T`, `-K` and a non-GET `-X` still deny | `curl -d '{"body":"…"}' …` |
| `wget` with mutation flags (`--method POST/…` in any case, `--post-data`, `--post-file`, `--body-data`, `--body-file`); wget's `-X`, `-d` and `-F` are not mutation options (exclude-dirs, debug, force-html) and are allowed | `wget --post-data '…' …` |

### Bash Commands — ALLOW

Everything not matched by a deny pattern:

- Help only: `git push --help`, `git push -h`, `gh pr create --help` (built-in gh groups only; a gh shell alias given `--help` would run, so it is not exempt)
- `curl -G -d q=x …` (data options under `-G`/`--get` are query parameters)
- `git clone`, `git status`, `git log`, `git diff`, `git fetch`, `git checkout` (local), `git add`, `git commit` (local)
- `gh pr view`, `gh pr list`, `gh pr checks`, `gh pr diff`
- `gh issue view`, `gh issue list`
- `gh release list`, `gh release view`
- `gh project list/view/item-list/field-list`, `gh ssh-key list`, `gh gpg-key list`, `gh cache list`, `gh repo deploy-key list`, `gh repo autolink list`, `gh repo set-default` (local only)
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
