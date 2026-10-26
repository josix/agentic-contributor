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
A skipped checkpoint becomes an **Unknown** in the debrief. Once an id is settled it is never asked
again.

## Scope-drift alerts

A second advisory hook, `track-breakpoint.sh`, watches how big the change has become. After an edit
(PostToolUse) and once at the end of each turn (Stop) it compares the working tree with the session
base commit. It raises **one alert** when the change crosses:

- more than `drift_lines` changed lines (default 400), or more than `drift_files` files (default 10).
  Lock files count as files but not as lines; files the agent created count too.
- a module (first two directory segments) outside `scope` that no checkpoint already asked about (an over-budget log does not count). This
  mostly catches changes made outside Edit, such as formatters or generators, and Bash edits to
  tracked files; files created by Bash are not counted.

The agent is told to ask you what to do with the part that grew: **keep** it, **set it aside for a
separate PR**, **drop** it, or **skip** (decide later). Your choice is recorded as `drift:<k>` in
the ledger; a separate-PR choice adds a follow-up line that the debrief and the PR scaffold list.
Mid-turn alerts are context for the agent (never a block, so it does not think the edit failed);
at the end of a turn the alert holds the stop once (deferred while the agent's last message already asks you something). The hook never reverts, stashes, or edits code.

Each threshold and each module alerts once. If your project's CONTRIBUTING file states an explicit
size limit, `/oss track` start uses that number (recorded as `drift_source`); vague wording is never
turned into a number. The check is throttled (new file or every 5th edit), so it adds little work.

## Breakpoint questions (explain-back)

When the agent stops after code edits, the hook may hold the stop **once** and ask you one question
about a specific `file:line`: the largest change since the base that no checkpoint or earlier
question covered. You answer in your own words (the free-text "Other" option), skip, or say you did
not ask for the change. Your answer is recorded verbatim as `explain:<k>`; it is never graded. The
debrief and the PR scaffold use it as your own Why, and skipped ones become Unknowns.

It asks only when all hold: edits since the last breakpoint, fewer than `explain_max` (4) asked,
at least `explain_interval_min` (20) minutes since the last one, no checkpoint or drift question
since the previous stop, and the agent is not already waiting on you.

## Fatigue budget

- Three separate pools: checkpoints **3** (`budget N`), drift alerts **2** (`drift_max`), breakpoint
  questions **4** (`explain_max`, at least 20 minutes apart). The worst case is 13 questions in a
  session (3+2+4, plus up to 4 predictions); a typical session sees 0 to 3. Edit the keys in the ledger frontmatter.
- Past a cap, events are still logged (`logged-over-budget`, or `asked=no` for drift) but you are
  not asked. A checkpoint past its budget is noted to the agent, which mentions it when it finishes;
  drift logged without asking is summarised to you in a one-line notice at the end of the turn (the
  agent does not see it); both appear in the debrief.
- `budget: 0` is **quiet mode** for the whole session: no checkpoint, drift, or breakpoint question
  is asked (drift is still logged). Recommended for headless or CI runs.
- `drift_max: 0` logs drift only; `explain_max: 0` turns breakpoint questions off;
  `drift_lines: 0` or `drift_files: 0` turns that threshold off.
- Loop guard: if a checkpoint is retried twice without a ledger entry, the third attempt is not blocked
  (the hook adds context only and normal permission prompts apply) and recorded as skipped. The hook never blocks permanently.

## Scope and api_paths

`scope` comes from what you give at start, else paths mentioned in the issue that exist in the
repo, else empty. Globs use shell matching where `*` crosses `/` (so `**` equals `*`); a trailing
`/` means prefix. At a scope checkpoint one option is "proceed and add `<dir>/**` to scope", which
edits `scope:` in the ledger frontmatter. `api_paths` uses the same syntax and is opt-in.

## The ledger file

A private markdown file `.oss-drafts/track-<owner>-<repo>-<item>-<UTC>.md`. Full format:
[Draft Files](draft-files.md#track-ledger) and
`skills/pr-preparation/references/decision-ledger.md`.

## Privacy

The ledger is private notes. It is never a send block and never PR text. The hook writes only the
class, path, counts, and timestamps. It never records prompts, transcripts, keystrokes, or file
contents. The session state file `<ledger>.state` holds only repo-relative paths of edited files and
a few counters; `/oss track stop` deletes it, and deleting it cannot lift a cap (the caps live in the
ledger). The ledger is agent-written, so a checkpoint answer is the agent's report of what you
chose; the debrief marks it as evidence, not proof.

## Predict mode (auto by default)

Predict mode makes the agent ask for your guess before it shows its own. For a prompt that asks it
to diagnose a problem or propose a plan, it asks one question ("Where do you think the problem is?"
or "Which files or parts do you expect need to change?"), does the work, then adds a short "Your
prediction vs. what I found" section that shows where you matched and where you differed, each with
`file:line`. It never scores you. The exchange is recorded privately in the ledger (`predict:<n>`)
and appears in the debrief under "Your predictions"; it never goes into PR text.

New tracked sessions start with `predict: auto`. Fixed rules switch it:

- On when you are new to the repo (fewer than 5 commits there with exactly your `git config user.email`), after you skipped or did
  not request an explain-back answer in this session, or when your previous session ended with 3 or
  more unknowns you left yourself (skips and over-budget items; not non-interactive, drift, or
  predict skips).
- Off after two "no idea" predictions in a row (sticky for the session). Picking "No idea — go ahead" records `prediction: no idea`; only an exact "no idea" (or "No idea — go ahead") counts, so "No idea, maybe lexer.c" does not.
- Otherwise off. If your commit count cannot be read (shallow clone, no `user.email`), that alone does not turn it on.

Every switch is logged in the ledger with its reason (`predict auto: on (newcomer)`), and the
injected note says `(auto: <reason>)`. Force it with `--predict` / `--predict=on` (always),
`--no-predict` / `--predict=off` (never) or `--predict=auto`; change it in a running session with
`/oss track predict on|off|auto`. A ledger from before v0.10.0 has no `predict` key and stays off.

- At most `predict_max` (default 4) per session; "Skip predictions for this session" turns it off
  for the rest of the session.
  `budget: 0` (quiet mode), slash commands and trivial prompts ("thanks!") keep it silent; plan mode does not.
- A `UserPromptSubmit` hook adds the instruction to your prompt as context. It never blocks a prompt
  and runs no git. Its writes are the auto switch marker (under the ledger lock; if the lock is
  busy it skips the write; logged when auto is evaluated) and a one-line session note so the full
  instruction is sent once and later prompts get a short reminder. With predict off or no session it prints nothing.
- A prediction counts as a question for explain-back, so you are not asked both in one turn.
- Headless runs and subagents cannot ask, so nothing is recorded.
- `/oss track predict off` or `OSS_TRACK_DISABLE=1` turns it off.

## Headless runs and subagents

Without AskUserQuestion (headless run, subagent), the entry is recorded as skipped with reason
`non-interactive`, and it becomes an Unknown in the debrief. A breakpoint question costs at most one
extra continuation in a `claude -p` run: after the agent records the non-interactive skip, a
per-session latch keeps explain-back silent for the rest of that session, and the next stop is never
held again. A subagent's edits are logged, and the main thread's Stop does the drift check.

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
- Files created by Bash are not counted toward drift size, `SubagentStop` is not covered, and
  Stop does not run when you interrupt the agent.
- Drift is measured against the session base commit. If the base stops being the base of `HEAD`
  (a rebase, a reset, or a merge commit since the base, for example `git pull` without
  `--rebase`), drift alerts and explain-back questions pause and you are told once: "base moved —
  drift paused; restart tracking (`/oss track stop` + start) to re-baseline". A fast-forward pull
  of upstream commits is not detected and still counts as drift; restart tracking after pulling.
  Predict-then-reveal compares your guess with the agent's own findings, not with a diff against
  the base, so it keeps running while drift is paused.
  Git work runs only inside a session, throttled, and can take longer on huge repos.
- After the drift question cap is spent, or with `budget: 0`, new drift (including each newly seen
  out-of-scope module) is recorded silently and summarised once at the end of the turn and in the
  debrief, never injected after every edit. The end-of-turn summary is a `systemMessage` shown to
  you only; the agent does not see it. With `budget: 0` nothing is asked.
- Binary and empty untracked files count as 0 lines, a pure rename counts as 0 lines, and an
  untracked text file is counted up to 20 000 lines. If the base commit no longer exists (garbage
  collected, or a shallow clone) drift and explain-back pause with a one-time "base commit not found"
  notice; restart tracking to re-baseline. No drift question is asked in a turn that already asked
  one; it waits for a later turn.
- The "agent is already asking" check needs `last_assistant_message` in the Stop input, and the
  subagent deferral needs `agent_id` in the PostToolUse input. On a Claude Code version that does
  not send them, a breakpoint question may follow a question the agent just asked, and a
  subagent's edits run the drift check themselves.
- The hook is advisory and fails open; it is not a safety boundary. The draft-only guard is separate.

---

[Back to docs index](../index.md) | Related: [Draft Files](draft-files.md) | [Hooks Reference](../reference/hooks.md) | [Using /oss](../guides/using-oss.md)
