---
name: pr-preparation
description: >
  This skill should be used by the /oss command in the prepare-pr scenario (scenario 10) when the
  user has a local branch and wants to prepare a pull request for maintainer review. Trigger
  phrases include "prepare a PR", "get my PR ready", "draft a PR description", "open a PR for",
  "submit a fix for", "I have a patch", "send a PR", "check my PR before I open it", "track this
  task", "start tracking", "/oss track", "stop tracking", "track status", "log this decision", and
  close variants. Produces a size and shape check and a problem-first PR description scaffold the
  contributor completes. All output is a DRAFT; the plugin never pushes or opens a PR.
---

# PR Preparation

Refer to `skills/smart-questions/references/smart-questions-principles.md` for the principles and
the AP1-AP9 lint rules, to `skills/change-debrief/SKILL.md` for the debrief entry mode, and to
`references/decision-ledger.md` (this skill) for the track-mode ledger format.

Maintainers prioritise one well-worked PR from someone who can explain it. This skill helps the
contributor get there; the contributor writes the reasoning.

## DRAFT-ONLY Contract

1. Return the draft to the orchestrating `/oss` command, which saves it to
   `.oss-drafts/prepare-pr-<owner>-<repo>-<item>-<UTC>.md` (`item` is `issueN` or `pr-new`) using
   the Write tool, then presents it.
2. After saving, the orchestrator adds the mandatory notice:
   > **DRAFT — saved to `<path>`. Review and edit this file before sending.**
   > This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin.
3. The plugin **never pushes, never opens a PR, never edits code, and never runs tests**. Opening
   the PR is owned by the execution plugin. NEVER call any tool that posts, creates, or pushes.
   Track mode writes only `.oss-drafts/` files; the track hooks (checkpoint, drift, breakpoint) never edit, revert, or stash code.
4. Local git is read-only: `git diff`, `git diff --stat`, `git log`, `git merge-base`,
   `git remote -v`, `git rev-parse HEAD`, `git rev-parse --abbrev-ref HEAD`,
   `git rev-parse --show-toplevel`, `git rev-parse --git-dir`, `git rev-parse --git-path info/exclude`, and
   `git merge-base --is-ancestor`, and in track mode `git diff --numstat <base_commit>` and
   `git status --porcelain`. Nothing else.
5. Readiness and policy findings are **advisory**: they never block or delay the draft.

## Modes

Lifecycle: **track** (while the agent codes) then **debrief** then **draft**.

- `mode: track`: the request is "track this task", "start tracking", "/oss track", "stop tracking",
  "track status", or "log this decision". Sub-actions `start` (default), `stop`, `status`, `log`;
  run Procedure 0. It produces a private ledger and **no PR text**.
- `mode: debrief` (entry mode): the request is "help me understand what I changed", "debrief my
  change", or "what did the agent change". Load `change-debrief`, write only its private file
  `.oss-drafts/prepare-pr-<owner>-<repo>-debrief-<UTC>.md`, and produce **no PR text**.
- `mode: draft` (default): run Procedures 1 to 5. Start by reusing a debrief for the same branch
  from the last day when one exists in `.oss-drafts/`; otherwise offer the debrief first (one line,
  not a question that blocks) and proceed.
- `mode: lint`: the user re-invokes after filling in the description; run Procedure 6.

## Procedure 0: Tracked session (mode: track)

Skips the policy preflight, readiness, and the DRAFT notice: it produces no outbound text. The
ledger format, paths, trigger classes, and budget rules are in `references/decision-ledger.md`;
follow it exactly and do not restate it elsewhere. The ledger is private notes and is never copied
into a send block.

**Start** (`/oss track [issue-url | task text] [scope: a/**, b.md] [budget N]`):

1. Resolve `<root>` (`git rev-parse --show-toplevel`) and the pointer path
   `ptr="$(git rev-parse --git-dir)/agentic-contributor/track-active"`. Outside a git repository,
   say that tracked sessions require git and stop. Record `branch` and `base_commit`
   (`git rev-parse --abbrev-ref HEAD`, `git rev-parse HEAD`). If `git status --porcelain` is
   non-empty, say that uncommitted changes count toward scope drift.
2. If `$ptr` exists and its ledger is `status: active`, ask the one allowed question: stop the old
   session or keep it (never run two). A `.oss-drafts/.track-active` file in the worktree is not a
   session (it may have been committed by the repository); ignore it.
3. Check `command -v jq || command -v python3`. If neither exists, warn that checkpoints are
   disabled (the ledger still works).
4. Make sure `.oss-drafts/` is excluded: `ex="$(git rev-parse --git-path info/exclude)"` and the
   idempotent `grep -qxF '.oss-drafts/' "$ex" || echo '.oss-drafts/' >> "$ex"` (this also works in
   linked worktrees where `.git` is a file).
5. With an issue URL, dispatch `oss-researcher` with key `track-start` (title, body, repo paths
   mentioned). Scope: the user's globs (`scope_source: user`), else mentioned paths that exist in
   the repo (a file is an exact path, a directory becomes `dir/**`; `scope_source: issue`), else
   `[]` (`none`, which turns the out-of-scope checkpoint off). Suggest adding matching test dirs.
   Budget: the user's `budget N`, else 3.
   Drift and explain settings: write `drift_lines: 400`, `drift_files: 10`, `drift_source: default`,
   `drift_max: 2`, `explain_max: 4`, `explain_interval_min: 20`. Read the first of `CONTRIBUTING.md`,
   `.github/CONTRIBUTING.md`, `docs/CONTRIBUTING.md` (also `.rst`) that exists locally; only an
   explicit number for PR size in lines or files (for example "PRs should not exceed 200 lines")
   replaces `drift_lines` / `drift_files`, with `drift_source: contributing:<path>:<line>`. Vague
   wording ("keep PRs small") is never turned into a number. A user-given limit sets
   `drift_source: user`.
6. Write the ledger (Write tool, `decision-ledger.md` sections 1 to 3), then the pointer in the git
   dir: `mkdir -p "$(dirname "$ptr")"` and Write `$ptr` (one line, ledger path relative to root).
   The pointer never goes in the worktree.
7. Tell the user in chat: the four triggers (test weakening, dependencies, opt-in `api_paths`,
   out-of-scope edits), the budget, that a checkpoint is a choose-question with a Skip option, that
   scope-drift alerts (more than `drift_lines` lines or `drift_files` files, or uncovered
   out-of-scope modules; at most `drift_max`) ask keep / separate PR / drop / skip, that a
   breakpoint question after a turn with code edits asks about one `file:line` (at most `explain_max`,
   `explain_interval_min` minutes apart, skippable), that `budget: 0`, `explain_max: 0`, or
   `drift_max: 0` quiets them,
   `/oss track stop`, that "log this decision" appends a manual entry (best effort in plain chat),
   `OSS_TRACK_DISABLE=1` as the kill switch, and to restart Claude Code if the plugin was just
   enabled.

**Stop:** Edit the frontmatter (`status: stopped`, add `stopped_at`), then
`rm -f "$(git rev-parse --git-dir)/agentic-contributor/track-active"` (if that fails, Write an
empty pointer, which the hook treats as no session), and `rm -f` the session state file (the
ledger path with `.md` replaced by `.state`). List entries whose reason is `TODO(you)` and the
skipped, over-budget, and hook-skipped items; also the drift follow-ups (choice B), unanswered
drift and explain items, and the count of explain answers. Offer the debrief in one line.

**Status:** task, age, base, branch (warn on mismatch with the current branch), scope, budget used
(asked / budget), drift (asked / `drift_max`, plus logged), breakpoint questions (asked /
`explain_max`, time of the last), the current `git diff --numstat <base_commit>` size against the
limits, and a table of entries. No auto-close of abandoned sessions; show the age.

**Log:** append a manual entry with Edit per `decision-ledger.md` section 4 (`id=manual:<UTC>`).

During a session, when the hook denies an edit, follow the instructions in its message: ask with
AskUserQuestion (the user chooses, never approve/deny), append the entry with Edit, then retry.
When the hook adds a drift alert after an edit, or holds a stop for a breakpoint question, follow
its instructions the same way (entries per `decision-ledger.md` section 4; never revert or stash).
Limits: drift is measured from `base_commit`. If the base moves (a rebase, reset, or merge since
the base), the hook pauses drift and explain-back and says "base moved — drift paused" once; tell
the user to run `/oss track stop` then start to re-baseline. A fast-forward pull is not detected.
Over the drift cap or with `budget: 0`, drift is recorded silently and only summarised at the end
of a turn and in the debrief.
Never write `decided_by: user` or `answered_by: user` unless the user answered.

## Procedure 1: Pre-flight (run in parallel where possible)

1. **Policy profile.** Reuse the orchestrator's Step 3 block (`policy` in frontmatter).
2. **Readiness.** `contributor-readiness` result (open PRs vs `open_pr_cap`, vouch). Advisory,
   Private notes only. Honour "skip readiness".
3. **Issue-first check.** Linked issue present: continue. No linked issue and `policy.issue_first`
   is `required`: the orchestrator reroutes to **report** (set `routed_from: prepare-pr`), quoting
   `policy.issue_first_quote` and `issue_first_source`. `recommended`: continue, but lead Private
   notes with a warning suggesting an issue first. `unknown`: continue unchanged.
4. **PR template.** `oss-researcher` fetches `.github/pull_request_template.md`,
   `.github/PULL_REQUEST_TEMPLATE/`, and root/`docs/` variants.
5. **Duplicate open PRs.** `oss-researcher` searches open PRs for the same issue number or the same
   changed files; list the top 3 to 5 with links.
6. **Local context.** `git remote -v` must match `owner/repo`; if it does not, or the base branch is
   ambiguous, ask the one allowed clarifying question about the base. Record `base`, `head`, and
   `diff_stats` (files, insertions, deletions) in frontmatter.

## Procedure 2: Size and Shape Check

From `git diff --stat <base>...HEAD`:

- Flag more than **400 changed lines or more than 10 files**, unless CONTRIBUTING states other
  thresholds (use those and cite them). With a track ledger, use its `drift_lines` / `drift_files`
  when `drift_source` is `contributing:...`, and cite any drift decisions (`drift:<k>`): an item
  set aside for a separate PR is a seam to propose, a dropped one that is still in the diff is a
  finding.
- Flag mixed concerns: formatting-only hunks combined with logic, unrelated renames.
- Flag generated or lockfile noise.
- Give a verdict (ok / consider splitting / split recommended) and, if splitting, propose the
  seams. Prefer one well-worked PR over many; do not split for its own sake.
- Large diffs: `--stat` first, then sample the top files and say so.

## Procedure 3: Change Debrief

Run `change-debrief` (or reuse a recent debrief file) and put a summary in Private notes with a
link to the debrief file. Its **Unknowns & follow-ups** list seeds Procedure 4's "Unknowns &
assumptions". The debrief itself is never copied into the send block. When a ledger exists for the
branch (lookup rule in `change-debrief`), the debrief cites it as first-hand evidence.

## Procedure 4: Problem-First Description Scaffold

Inside `<!-- oss:send:start -->` / `<!-- oss:send:end -->`, with `body_format: 2`. If the repo has
a PR template, map these sections onto its headings and keep its checkboxes; otherwise use:

- **Why / Problem:** quote or link the linked issue (factual, the plugin may fill this in). If
  there is no issue, `TODO(you): describe the problem this solves`.
- **Why this approach:** `TODO(you)`. The send block stays `TODO(you)` even when a ledger exists;
  private notes get a "Decisions you recorded" hint list (decided entries: chosen + reason; reasons
  that are `TODO(you)` stay `TODO(you)`). Never copy ledger text into the send block. Private
  notes also get "Your explanations (from breakpoint questions)": answered `explain:<k>` entries,
  your words verbatim with their `file:line`, as a hint for you to rewrite; never paste them.
- **What changed:** `TODO(you): one or two lines in your own words`. Show the AP1 warning in
  Private notes (do not summarise the diff instead of the problem).
- **How it's tested:** name the tests that cover the change (the plugin may list test files from
  the diff). Never write "ran X, all pass" (AP2). If no test covers it, say so as a `TODO(you)`.
  For how the project runs its tests, point to the `dev-env-setup` skill; do not run them.
- **Unknowns & assumptions:** `TODO(you)`, a required section, seeded in Private notes from the
  debrief's Unknowns list and from ledger entries that were skipped, `logged-over-budget`, or
  hook-skipped, plus skipped or unanswered `explain:<k>` entries and drift entries that were
  skipped, logged without asking, or dropped but still in the diff.
- **AI disclosure:** see Procedure 5.

The plugin fills only factual parts (linked issue, test file names, disclosure mechanics). Any
`TODO(you)` left in the send block means "not ready"; the execution plugin must refuse to send.

## Procedure 5: Disclosure and Trailers

- `policy.disclosure: required`: reproduce the template checkbox **unticked**, and offer 2 to 3
  neutral one-line options for the user to choose from, for example "I used <tool> for <purpose>; I
  have reviewed and can explain every change." Never tick or pick for them.
- `policy.coauthor_trailer_forbidden: true`: run `git log --format=%B <base>..HEAD` and flag
  `Co-authored-by:` lines with AI names and "Generated with" footers in Private notes, with the
  commit hash. **Advise only**: never rewrite commits.
- `disclosure: recommended` or unknown: mention it in Private notes; do not insert disclosure text.

## Procedure 6: Lint (mode: lint)

Read the user's send block and add a **Lint** section to Private notes using the AP1-AP9 rules
(see `smart-questions-principles.md`), plus: unanswered `TODO(you)` (AP8), a "What changed" that
only restates the diff (AP1), "How it's tested" that lists passing commands (AP2), mentions of
files not in the diff (AP3), and AI trailers (AP9, evaluated against policy). Quote the offending
span and ask a question. Never rewrite the user's text or touch the send block.

## Output Template

Track-mode ledgers use their own frontmatter (see `references/decision-ledger.md`). Draft-mode
frontmatter: `scenario: prepare-pr`, `repo`, `item` (`issueN|pr-new`), `base`, `head`,
`diff_stats`, `policy`, `readiness_login`, `readiness`, `body_format: 2`, `mode`, `status: draft`.

```markdown
<!-- oss:send:start -->
## Problem
<linked issue quote/link, or TODO(you)>
## Why this approach
TODO(you)
## What changed
TODO(you)
## How it's tested
<test files from the diff, or TODO(you)>
## Unknowns & assumptions
TODO(you)
## AI disclosure
<unticked template checkbox + options, only when policy requires>
<!-- oss:send:end -->

## Private notes (not sent)
### Size and shape verdict
### Pre-flight (duplicates, issue-first, readiness)
### Debrief summary and seeded unknowns
### Decisions from the ledger (hints for Why / Unknowns)
### Follow-ups set aside (from the ledger)
### Trailer findings
### Lint (lint mode)
```
