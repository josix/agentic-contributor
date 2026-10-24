---
name: change-debrief
description: >
  This skill should be used by the /oss command (prepare-pr scenario, mode: debrief) to walk a
  contributor through a local change they made with a coding agent: what changed, why, and what it
  affects, with evidence for every claim, ending with explain-back questions. Trigger phrases
  include "help me understand what I changed", "debrief my change", "what did the agent change",
  "walk me through my diff", and close variants. Output is a private notes file, never PR text.
---

# Change Debrief

Helps a contributor who used a coding agent understand and own their change before asking anyone
to review it. It is the entry mode of `prepare-pr` (`mode: debrief`), not a separate scenario, and
`pr-preparation` reuses its Unknowns list.

## Contract (read-only, private)

- The plugin never edits or reverts code, never runs tests, never pushes, never opens a PR, and
  never posts anything.
- Local git reads only: `git diff <base>...HEAD`, `git diff --stat`, `git log`, `git merge-base`,
  `git remote -v`, `git rev-parse --abbrev-ref HEAD`, `git merge-base --is-ancestor`.
- The output is a **private notes file** and is never formatted or offered as paste-ready PR text.
  It has no `oss:send` block. Do not add one.
- Explaining the change is the user's job; this skill gives them the material and asks questions.

## Inputs

1. **Default inputs:** the diff against the base, the commit messages on the branch, and the issue or
   task text (the linked issue if given, otherwise what the user said).
2. **Agent transcript: opt-in only.** Read a session transcript only when the user points to one
   (for example a Claude Code session JSONL path). Never search for one. When no transcript is
   used, state that the "why" is weaker without it.
3. **Decision ledger (when present).** Look for `.oss-drafts/.track-active` first, else the newest
   `.oss-drafts/track-*.md` whose `branch` equals the current branch and whose `base_commit` is an
   ancestor of HEAD (`git merge-base --is-ancestor`). Format: `skills/pr-preparation/references/decision-ledger.md`.
   If the user gives no base, mention the ledger's `base_commit` as the session start. The ledger is
   private; never copy it into anything sendable. From v0.9.0 it can also hold scope-drift entries
   (`drift:<k>`) and breakpoint answers (`explain:<k>`, your own words); read them per section 10
   of the reference.
4. Base branch: `git merge-base HEAD <default-branch>`; confirm with `git remote -v` that the cwd
   matches the target `owner/repo`. If the remote or base is ambiguous, ask the one allowed
   clarifying question about the base.

## Procedure

1. **Scope.** Run `git diff --stat <base>...HEAD`. For large diffs (over roughly 400 lines or 10
   files) summarise the top-level groups first, say that you sampled the top files, and drill down
   on request.
2. **Group by purpose**, not by file. Each group has a one-line label and `file:line` citations.
   Put formatting-only, rename-only, lockfile and generated hunks in their own groups.
3. **Trace the why** for each group to a source and show it: issue/task text, a commit message
   (hash and subject), a ledger entry, or a transcript turn (when opted in). A group with no traceable reason is
   labelled **"unexplained, possibly out of scope"**; never invent a justification.
4. **Mark every statement** as `[evidenced: <citation>]` or `[inferred]`. A ledger entry is
   `[evidenced: ledger <id>]`, stronger than a commit message: prefer it when both exist. Inferred
   reasons are never presented as fact. An answered `explain:<k>` entry (`chosen: typed`) is
   `[evidenced: ledger explain:<k>]` and is quoted as "you said: ...": it is the strongest Why
   source because it is in the user's words, preferred over commit messages. A group whose entry
   says `chosen: not-requested` is labelled "unexplained, possibly out of scope (you said you did
   not ask for it)".
5. **Implicit decisions and assumptions** the agent made: approach chosen over alternatives, inputs
   assumed valid, incidental refactors or formatting. With a transcript, separate "you instructed"
   from "the agent decided". With a ledger, `decided_by` separates "you decided", "you chose the
   agent's recommendation" (`user-on-recommendation`), and "the agent decided" (`asked=no`).
6. **Impact:** affected callers, public API / config / behaviour changes, backward compatibility,
   and which changed paths are or are not covered by tests (name the test files from the diff; do
   not run anything).
7. **Explain-back:** 2 to 3 questions citing the diff (`file:line`) that the user answers in their
   own words as `TODO(you)`. In lint mode, flag unanswered ones. Ledger entries with reason
   `TODO(you)` become explain-back prompts. Do not re-ask a hunk the user already answered at a
   breakpoint; reuse skipped `explain:<k>` entries as prompts.
8. **Unknowns & follow-ups:** a list of open items. `pr-preparation` seeds "Unknowns &
   assumptions" from it, and it can seed a `review-reply` brief. Ledger entries that were skipped,
   `logged-over-budget`, or hook-skipped go here as "not decided: <trigger> on <file> (ledger
   <id>)". Entries for files not in the diff get the note "recorded, file not in final diff".
   Add "not explained: <rel>:<line> (ledger explain:<k>)" for skipped breakpoint questions or a
   `track:breakpoint` marker with no entry. Drift entries: A (keep) is evidence "you chose to keep
   ..."; B (separate PR) goes to follow-ups with its `follow-up:` line; C (drop) whose files are
   still in the final diff is an Unknown "dropped per ledger drift:<k> but still in the diff:
   ..."; a skipped drift entry, a `track:drift` marker with no entry, or an `asked=no` marker is an
   Unknown.

The user may ask follow-ups about any group ("why not use X?"); answer citing code, still read-only.

## Output Template

Save to `.oss-drafts/prepare-pr-<owner>-<repo>-debrief-<UTC>.md` with frontmatter
`scenario: prepare-pr`, `mode: debrief`, `item: debrief`, `base`, `head`, `diff_stats`, `status:
draft`, `body_format: private`. `private` is explicitly non-sendable: no consumer may post any
part of the file, and there is no send block. Lead with: "Private notes. Not PR text. Do not paste."

```markdown
# Change debrief (private)
Inputs: diff <base>...<head>, <N> commits, issue text <#N|none>, ledger <path|none>, transcript <path|not used (why is weaker)>

## What changed (by purpose)
### 1. <purpose> (<file:line>, <file:line>)
- Why: <reason> [evidenced: <source>|inferred]
- Impact: <callers / API / config / compat> [evidenced|inferred]
- Tests: <covered by <test file> | no test touches this path>

### N. <purpose> (<file:line>)
- Why: unexplained, possibly out of scope. Did you ask for this?

## Agent's implicit decisions and assumptions
- <decision> [evidenced|inferred]

## Explain-back (answer in your own words)
1. <question citing file:line> TODO(you)
2. <question> TODO(you)

## Unknowns & follow-ups
- <open item>
```

The `TODO(you)` markers here are private prompts; this file is never sent.
