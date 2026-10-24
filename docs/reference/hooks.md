# Hooks Reference

The draft-only `PreToolUse` guardrail (registration, matcher, full deny/allow matrix) the advisory decision-checkpoint hook, and the advisory scope-drift and breakpoint hook.

## Overview

The `agentic-contributor` plugin registers two `PreToolUse` hooks plus a `PostToolUse`, a `Stop`, and a `UserPromptSubmit` hook. The first `PreToolUse` hook is the draft-only guardrail, which runs before every `Bash` call and every GitHub MCP tool call and denies outbound and mutating actions before they execute. The second is an advisory decision-checkpoint hook for Edit/Write. The `PostToolUse`, `Stop` and `UserPromptSubmit` hooks are one advisory script (`track-breakpoint.sh`) for scope-drift alerts, breakpoint questions, and predict-then-reveal (`predict: auto` by default for new sessions: fixed rules switch it on or off; `--predict` / `--no-predict` force it). The advisory hooks are active only inside an `/oss track` session.

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
            "timeout": 30
          }
        ]
      },
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/track-checkpoint.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write|MultiEdit|NotebookEdit",
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/track-breakpoint.sh", "timeout": 10 }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/track-breakpoint.sh", "timeout": 10 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/hooks/scripts/track-breakpoint.sh", "timeout": 15 }
        ]
      }
    ]
  }
}
```

**Matcher:** `Bash|mcp__plugin_agentic-contributor_github__.*` — matches all Bash tool calls and all GitHub MCP tool calls namespaced to this plugin.

**Timeout:** 30 seconds. Typical commands finish in well under 1 second (bash string matching plus a few `awk` passes, no network calls). A command that contains none of the trigger words `gh`, `git`, `curl`, or `wget` (checked case-insensitively after deleting quotes, backslashes, and newlines, so `g\it` or `"g"it` still count) is allowed immediately. Segments without a trigger word are skipped one by one, so a 600-segment one-liner or a 300-line script that runs `git` on every line still finishes in a few seconds. The 30-second timeout leaves headroom for slow machines.

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

### MCP Tools — default DENY, read allowlist

The plugin's GitHub MCP namespace is **default-deny**. The script takes the tool-name suffix after the last `__` and allows it only when it names a read tool:

```
get_*  |  list_*  |  search_*  |  *_read
```

Even with one of those prefixes, a suffix that contains `write`, `create`, `delete`, `submit`, or `fork` is denied. A suffix with characters other than `a-z`, `0-9`, and `_` is denied too. Every other tool is denied, including tools the upstream GitHub MCP server adds later.

**ALLOW examples:** `get_me`, `get_file_contents`, `get_commit`, `list_issues`, `list_pull_requests`, `list_releases`, `search_code`, `search_issues`, `search_repositories`, `issue_read`, `pull_request_read`.

**DENY examples:** `issue_write`, `sub_issue_write`, `pull_request_review_write`, `add_issue_comment`, `add_comment_to_pending_review`, `create_pull_request`, `create_branch`, `create_repository`, `create_or_update_file`, `delete_file`, `push_files`, `merge_pull_request`, `update_pull_request`, `update_pull_request_branch`, `fork_repository`, `assign_copilot_to_issue`, `request_copilot_review`.

### Bash Commands — DENY

| Pattern checked | Blocked example |
|---|---|
| `git push` at command position | `git push origin main` |
| `git push`, `git send-email`, `git send-pack`, `git svn dcommit`, also after global options (`-C`, `-c`, `--git-dir`, `--work-tree`, `--namespace`, `--no-pager`, …), a path-qualified binary, or a wrapper prefix | `git -C dir push`, `/usr/bin/git push`, `env git push` |
| `git -c alias.<name>=<value>` whose value contains `push`, `send-email`, `send-pack`, or `dcommit`, or starts with `!` (shell alias) | `git -c alias.p=push p origin main` |
| `gh pr create/comment/review/edit/merge/close/reopen/lock/unlock/ready/update-branch/revert/--fill` | `gh pr create --title "…"` |
| `gh issue create/comment/edit/close/reopen/lock/unlock/delete/transfer/pin/unpin/develop` | `gh issue comment 123 --body "…"` |
| `gh release create/edit/delete/delete-asset/upload` | `gh release create v1.0` |
| `gh repo create/fork/delete/edit/sync/rename/archive/unarchive`, `gh repo deploy-key add/delete`, `gh repo autolink create/delete` | `gh repo fork apache/airflow` |
| `gh gist create/edit/delete/rename` | `gh gist create file.txt` |
| `gh label create/edit/delete/clone`, `gh workflow run/enable/disable`, `gh run rerun/cancel/delete`, `gh secret set/delete`, `gh variable set/delete`, `gh alias set/delete/import`, `gh codespace create/delete/edit/stop/rebuild` | `gh workflow run ci.yml` |
| `gh project create/edit/delete/close/copy/link/unlink/mark-template/item-add/item-create/item-edit/item-delete/item-archive/field-create/field-delete`, `gh ssh-key add/delete`, `gh gpg-key add/delete`, `gh cache delete` | `gh project item-add 1 --url …` |
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

## `track-checkpoint.sh` (advisory)

**Not a safety boundary.** The guard above is unchanged. This hook turns a few reviewer-relevant edits into "choose, not approve" questions inside a tracked session and records the answers in the private decision ledger. Concept and usage: [Tracked Sessions & Checkpoints](../concepts/tracked-sessions.md). Ledger format: `skills/pr-preparation/references/decision-ledger.md`.

**Matcher:** `Edit|Write|MultiEdit|NotebookEdit`. **Timeout:** 5 seconds. Bash is not watched (`npm install`, `rm` are not caught).

**Opt-in.** The session pointer is `<gitdir>/agentic-contributor/track-active`, in the git dir of the repository containing `$CLAUDE_PROJECT_DIR` (else the hook's working directory). The hook finds it by walking up to the first `.git`; a `.git` file (linked worktree, submodule) is followed through its `gitdir:` line. Without that pointer the hook exits before reading stdin, prints nothing, and spawns no subprocess (builtins only), so large edit payloads cost nothing. Tracked sessions require git: outside a git repository the hook is inactive. A `.oss-drafts/.track-active` file or ledger committed to a repository is ignored, because git never clones the git dir. Kill switch: `OSS_TRACK_DISABLE=1`. Also silent when the ledger says `status: stopped`, in `permission_mode: plan`, when the edited file is outside the repository root, or when the pointer is invalid (it must name `.oss-drafts/track-<name>.md` inside the root, no `..`, no symlinks).

**JSON parsing:** `jq` → `python3` → silent allow (no grep fallback; this hook fails open).

**Output:** one `hookSpecificOutput` JSON object on stdout with exit 0. Exit 2 is never used.

| Situation | Result |
|---|---|
| no session, stopped session, plan mode, any internal error | silent (no output) |
| trigger (test weakening, dependency manifest or lock file, opt-in `api_paths`, outside `scope`), id not yet settled, budget left | `deny` with instructions to ask via AskUserQuestion, append a ledger entry, and retry |
| id already settled, or already logged over budget | silent |
| budget spent (default 3 questions asked), or `budget: 0` | `additionalContext` plus a short `systemMessage` (no permission decision); a `logged-over-budget` line is appended |
| second retry without a ledger entry (loop guard) | `deny` again once; the third attempt gets `additionalContext` plus a `systemMessage` (no permission decision) and a `skipped` line |
| tool `Edit` whose path equals exactly the active ledger path | `allow` (so a checkpoint costs one interruption, not two) |

The ledger auto-allow is deliberately narrow: only `Edit` (never Write, MultiEdit, or NotebookEdit), only the byte-for-byte active ledger path read from the pointer, nothing with a `..` segment, and nothing when the ledger, the pointer, or `.oss-drafts/` is a symlink. Every other path, including other files in `.oss-drafts/`, gets no allow.

Checkpoint ids are `<class>:<repo-relative path>`; a lock file maps to its manifest (`yarn.lock` is `dependency:package.json`). The hook appends only the class, the edited file's repo-relative path, and timestamps with a single `>>`; it never writes old/new strings or file content into the ledger. A path (or `cwd`) containing a control character such as a newline or carriage return makes the hook fail open without writing, so a file name cannot forge ledger marker lines.

**No ledger text in output.** The ledger is repository-writable data, so the hook never echoes `scope`, `api_paths`, or any other frontmatter value into `permissionDecisionReason`, `additionalContext`, or `systemMessage`. Messages say "the ledger's scope" or "an API path listed in the ledger" and name only the edited file's repo-relative path.

**Context-only notices.** The over-budget and loop-guard notices rely on `additionalContext` in a PreToolUse hook without a permission decision, which needs a Claude Code version that supports PreToolUse `additionalContext`. On older versions Claude does not see the note, so the hook also sets a top-level `systemMessage` that the user sees either way.

**Locking.** Reading state, checking the budget, and appending a pending marker happen under a `mkdir` lock (`<ledger>.lock`). A lock older than about 10 seconds is treated as stale: its mtime comes from `stat -c %Y` (GNU) or `stat -f %m` (BSD), validated as a number, and it is renamed to a per-process name before removal so a fresh lock is never deleted. If the lock stays busy for about 2 seconds the hook fails open.

Harness: `bash hooks/tests/run-track-tests.sh` (bash 3.2 compatible; builds a fixture git repo in a temp dir per case).

## `track-breakpoint.sh` (advisory)

A separate, advisory hook for tracked sessions only. Like `track-checkpoint.sh` it is not the safety guard, fails open (any internal error means no output and exit 0), prints nothing and starts no subprocess when no session is active (builtins only), needs `jq` or `python3` (else silent), honours `OSS_TRACK_DISABLE=1` and `permission_mode: plan`, and never reverts, stashes, or edits code. It reads `hook_event_name` and handles three events:

| Event | What it does | Output |
|---|---|---|
| `PostToolUse` (`Edit\|Write\|MultiEdit\|NotebookEdit`) | appends the edited path to the session state file `<ledger>.state` (ledger writes are never logged). Runs a drift check only when the path is new to the session or every 5th edit; skips the check inside a subagent (`agent_id` present) | `hookSpecificOutput.additionalContext` with a "choose: keep / separate PR / drop / skip" alert. Over the drift cap or with `budget: 0` the marker is recorded silently (no output). Never a block |
| `Stop` | exits first when `stop_hook_active` is true. Otherwise runs the drift check once, then at most one explain-back question | `{"decision":"block","reason":...}` with the instructions, at most one block per stop; drift takes precedence. A top-level `systemMessage` (alone, or with the block) summarises drift logged without asking |
| `UserPromptSubmit` | with `predict: true`, or `predict: auto` when the fixed rules (newcomer, skipped explain-back, many prior unknowns; off after two "no idea") compute on, `budget > 0`, an active session, fewer than `predict_max` (default 4) `predict:<n>` ledger entries, and a prompt that is non-empty and does not start with `/`, adds the predict-then-reveal instruction. No git. Only write: in `auto`, a `track:predict-auto` switch marker under the ledger lock (busy lock = skip, fail open) | `hookSpecificOutput.additionalContext` (`hookEventName: "UserPromptSubmit"`), never a block. The text shows `(auto: <reason>)` in auto mode. The instruction is scoped with "only if this prompt asks you to diagnose a problem or propose a plan"; the agent records a `predict:<n>` entry itself. A predict entry counts toward the explain-back watermark |

Caps (separate pools, in the ledger frontmatter): checkpoints `budget` 3, drift `drift_max` 2, breakpoint questions `explain_max` 4 at least `explain_interval_min` 20 minutes apart. `budget: 0` is quiet mode. Drift thresholds are `drift_lines` 400 and `drift_files` 10 (strictly greater), plus out-of-scope modules that no checkpoint covered.

Loop safety: `stop_hook_active` exit, the ledger marker and the state `b` line are written before the block is emitted, ledger-based count and interval caps, and a per-session non-interactive latch so `claude -p` never hangs. Rate-limit state lives in the ledger (`track:drift`, `track:breakpoint`), so the disposable state file cannot lift a cap. Timestamps use the same normalisation as v0.8.0 (a malformed or future `epoch=`/`at=` reads as oldest) and the same `<ledger>.lock` directory (stale after 10 seconds; a busy lock fails open).

Git use is read-only and bounded: `GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 git -C <root> -c core.quotepath=off ... --no-ext-diff --no-textconv --no-renames`, never inside the ledger lock. If the agent does not act on `PostToolUse` context, `emit_post` can switch to a block (a one-line change).

**Opt-in and input.** Same session lookup as `track-checkpoint.sh`: the git-dir pointer is checked before stdin is read; a committed in-worktree pointer is ignored. A `file_path`, `cwd`, or other input field with a control character is treated as empty (fail open, nothing written). Ledger text (`scope`, `drift_source`, any frontmatter value) is never echoed; the drift source is shown as a fixed label.

**Base moved.** If the session base is no longer an ancestor of `HEAD`, or a merge commit landed since it, drift and explain-back pause and the hook says once "base moved — drift paused; restart tracking (/oss track stop + start) to re-baseline" (a `track:drift-paused` ledger line records it). A fast-forward pull is not detected.

**Input fields by Claude Code version.** Two optional fields need a Claude Code version that sends them: `last_assistant_message` on `Stop` (skip the breakpoint question when the agent's last message already ends with `?`) and `agent_id` on `PostToolUse` inside a subagent (defer the drift check to the main thread). Without them the hook still works: a breakpoint question may follow a question the agent just asked, and a subagent's edits run the throttled drift check themselves.

**State file.** `<ledger>.state` is compacted above 400 lines to a short prefix plus the newest 100 lines, preserving what the hook reads (see `decision-ledger.md` section 11).

Code shared with `track-checkpoint.sh` lives between `# --- shared: <name> (keep identical in track-*.sh) ---` and `# --- end shared ---` lines (session lookup, list cleaning, manifest map, glob match, lock helpers) and is checked for byte-equality by the harness.

Harness: `bash hooks/tests/run-breakpoint-tests.sh` (bash 3.2 compatible; fixture git repo per case with the pointer in the git dir, run from the fixture root; loop, parallel-lock, python3-fallback, shared-code, base-moved, compaction, ledger-injection, and `.git`-file worktree checks).

---

[Back to docs index](../index.md) | Related: [Draft-Only Guardrail](../concepts/draft-only-guardrail.md) | [Commands](commands.md) | [GitHub Access](../guides/github-access.md)
