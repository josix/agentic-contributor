# Tracked Sessions & Decision Checkpoints

How `/oss track` records the decisions you make while a coding agent works, so the debrief and the PR
scaffold start from what you actually chose.

## Why

Reviewers ask "why this approach?" and "what did you consider?". A contributor who let an agent
code often cannot answer, because the decisions went by unseen. A tracked session moves guidance to
the moment of work: at a few reviewer-relevant decisions the agent stops, you **choose**, and your
reasons are written to a private ledger. Choosing between options is a cognitive forcing step;
approving a diff is not.

## Lifecycle

**track** (while the agent codes) then **debrief** then **draft**. Track is a mode of the
`prepare-pr` scenario, not an eleventh scenario.

## Start, status, log, stop

```text
/oss track https://github.com/apache/datafusion/issues/1234 scope: datafusion/sql/** budget 3
/oss track status
/oss track log chose a builder over a constructor because callers vary in arity
/oss track stop
```

- **start** writes a ledger under `.oss-drafts/` and a one-line pointer
  `<gitdir>/agentic-contributor/track-active` (the git dir from `git rev-parse --git-dir`, never the
  worktree), and tells you the triggers, the budget, and how to stop. Tracked sessions require git. Restart Claude Code if the plugin was just enabled.
- **status** shows the task, age, base, branch (with a warning on mismatch), scope, budget used,
  and the entries. Sessions are never auto-closed; the age is shown instead.
- **log** appends a manual entry. In plain chat, "log this decision" means the same thing on a
  best-effort basis (it does not survive context compaction).
- **stop** marks the ledger stopped, removes the pointer, lists entries that still need your
  reason (`TODO(you)`) plus skipped and over-budget items, and offers the debrief.

One session is active per project folder (git toplevel or worktree), not per branch.

## What triggers a checkpoint

The advisory hook `track-checkpoint.sh` fires on Edit, Write, MultiEdit, and NotebookEdit inside a
session. One class per edit, first match wins: test, dependency, api, scope.

| Class | Fires when |
|---|---|
| test | the edit to an existing test file lowers assertions or adds skips (a new test file never triggers) |
| dependency | the edit touches a dependency manifest; a lock file counts as its manifest (`yarn.lock` is `package.json`) |
| api | the path matches the opt-in `api_paths` list (default empty) |
| scope | the path is outside the session `scope` (off when scope is empty) |

## What a checkpoint looks like

The edit is paused and the agent is told to ask you one question with 2 to 3 options, each with a
one-line trade-off, a recommendation first, and a final **Skip, decide later**. You choose; you are
not asked to approve or deny. The agent records the choice and your words in the ledger and retries.
A skipped checkpoint becomes an **Unknown** in the debrief. Once a checkpoint id is settled it is
never asked again. Ids are `<class>:<path>`, and test and dependency ids end in `#<change>`, a
checksum of the lines the edit adds and removes (for example `dependency:package.json#073e0383`).
So retrying the same edit after you chose passes silently, but adding a second dependency to the
same `package.json`, or weakening the same test file in a different way, is a new decision and gets
its own checkpoint.

## Fatigue budget

- Default 3 questions per session, counting questions actually asked. Set it with `budget N`, or
  edit `budget:` in the ledger frontmatter.
- Scope checkpoints have their own budget of the same size. Out-of-scope edits therefore never use
  up the questions for test weakening, dependencies, and API paths; at most `2 × budget` questions
  are asked per session.
- Past the budget, triggers are still logged (`logged-over-budget`) but you are not asked, and the
  agent mentions it at the end.
- `budget: 0` is log-only mode, recommended for headless or CI runs.
- Loop guard: if a checkpoint is retried twice without a ledger entry, the third attempt is not blocked
  (the hook adds context only and normal permission prompts apply) and recorded as skipped. The hook never blocks permanently.

## Scope and api_paths

`scope` comes from what you give at start, else paths mentioned in the issue that exist in the
repo (each as its directory, `dir/**`; a file at the repo root stays exact), else empty. Globs use shell matching where `*` crosses `/` (so `**` equals `*`); a trailing
`/` means prefix. At a scope checkpoint one option is "proceed and add `<dir>/**` to scope", which
edits `scope:` in the ledger frontmatter. `api_paths` uses the same syntax and is opt-in.

## The ledger file

A private markdown file `.oss-drafts/track-<owner>-<repo>-<item>-<UTC>.md`. Full format:
[Draft Files](draft-files.md#track-ledger) and
`skills/pr-preparation/references/decision-ledger.md`.

## Privacy

The ledger is private notes. It is never a send block and never PR text. The hook writes only the
class, path, a checksum of the changed lines (never the lines), counts, and timestamps. It never records prompts, transcripts, keystrokes, or file
contents. The ledger is agent-written, so a checkpoint answer is the agent's report of what you
chose; the debrief marks it as evidence, not proof.

## Headless runs and subagents

Without AskUserQuestion (headless run, subagent), the entry is recorded as skipped with reason
`non-interactive`, and it becomes an Unknown in the debrief.

## Stopping and disabling

`/oss track stop`; `OSS_TRACK_DISABLE=1` in the environment as a kill switch; or delete
`"$(git rev-parse --git-dir)/agentic-contributor/track-active"`. With no session the hook prints
nothing, starts no subprocess, and does not read its input.

The pointer lives in the git dir on purpose: git never clones the git dir, so a repository cannot
ship an active session (a committed `.oss-drafts/.track-active` or ledger is ignored). Each linked
worktree or submodule has its own git dir and so its own session.

## Limits

- Bash commands are not watched: `npm install`, `rm tests/…`, or `git rm` are not caught.
- One session per project folder. Tracked sessions require git: outside a git repository the
  hook is inactive.
- "Log this decision" in plain chat is best effort.
- The ledger is self-reported by the agent.
- The hook is advisory and fails open; it is not a safety boundary. The draft-only guard is separate.

---

[Back to docs index](../index.md) | Related: [Draft Files](draft-files.md) | [Hooks Reference](../reference/hooks.md) | [Using /oss](../guides/using-oss.md)
