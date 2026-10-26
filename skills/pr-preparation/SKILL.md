---
name: pr-preparation
description: >
  This skill should be used by the /oss command in the prepare-pr scenario (scenario 10) when the
  user has a local branch and wants to prepare a pull request for maintainer review. Trigger
  phrases include "prepare a PR", "get my PR ready", "draft a PR description", "open a PR for",
  "submit a fix for", "I have a patch", "send a PR", "check my PR before I open it", and close
  variants. Produces a size and shape check and a problem-first PR description scaffold the
  contributor completes. All output is a DRAFT; the plugin never pushes or opens a PR.
---

# PR Preparation

Refer to `skills/smart-questions/references/smart-questions-principles.md` for the principles and
the AP1-AP9 lint rules, and to `skills/change-debrief/SKILL.md` for the debrief entry mode.

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
4. Local git is read-only: `git diff`, `git diff --stat`, `git status --porcelain`,
   `git ls-files --others --exclude-standard`, `git log`, `git merge-base`, `git remote -v`.
   Nothing else.
5. Readiness and policy findings are **advisory**: they never block or delay the draft.

## Modes

- `mode: debrief` (entry mode): the request is "help me understand what I changed", "debrief my
  change", or "what did the agent change". Load `change-debrief`, write only its private file
  `.oss-drafts/prepare-pr-<owner>-<repo>-debrief-<UTC>.md`, and produce **no PR text**.
- `mode: draft` (default): run Procedures 1 to 5. Start by reusing a debrief for the same branch
  from the last day when one exists in `.oss-drafts/`; otherwise offer the debrief first (one line,
  not a question that blocks) and proceed.
- `mode: lint`: the user re-invokes after filling in the description; run Procedure 6.

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
   ambiguous, ask the one allowed clarifying question about the base. Run `git status --porcelain`:
   uncommitted (`git diff HEAD`) and untracked (`git ls-files --others --exclude-standard`) work
   is part of the change. Record `base`, `head`, and `diff_stats` (files, insertions, deletions,
   counting committed + uncommitted + untracked) in frontmatter, and say in Private notes when
   uncommitted or untracked files were included, since they must be committed before the PR.

## Procedure 2: Size and Shape Check

From `git diff --stat <base>...HEAD`, or, when Procedure 1 found uncommitted work,
`git diff --stat <base>` (working tree against the base, so committed and uncommitted changes are
counted once) plus the untracked files:

- Flag more than **400 changed lines or more than 10 files**, unless CONTRIBUTING states other
  thresholds (use those and cite them).
- Flag mixed concerns: formatting-only hunks combined with logic, unrelated renames.
- Flag generated or lockfile noise.
- Give a verdict (ok / consider splitting / split recommended) and, if splitting, propose the
  seams. Prefer one well-worked PR over many; do not split for its own sake.
- Large diffs: `--stat` first, then sample the top files and say so.

## Procedure 3: Change Debrief

Run `change-debrief` (or reuse a recent debrief file) and put a summary in Private notes with a
link to the debrief file. Its **Unknowns & follow-ups** list seeds Procedure 4's "Unknowns &
assumptions". The debrief itself is never copied into the send block.

## Procedure 4: Problem-First Description Scaffold

Inside `<!-- oss:send:start -->` / `<!-- oss:send:end -->`, with `body_format: 2`. If the repo has
a PR template, map these sections onto its headings and keep its checkboxes; otherwise use:

- **Why / Problem:** quote or link the linked issue (factual, the plugin may fill this in). If
  there is no issue, `TODO(you): describe the problem this solves`.
- **Why this approach:** `TODO(you)`.
- **What changed:** `TODO(you): one or two lines in your own words`. Show the AP1 warning in
  Private notes (do not summarise the diff instead of the problem).
- **How it's tested:** name the tests that cover the change (the plugin may list test files from
  the diff). Never write "ran X, all pass" (AP2). If no test covers it, say so as a `TODO(you)`.
  For how the project runs its tests, point to the `dev-env-setup` skill; do not run them.
- **Unknowns & assumptions:** `TODO(you)`, a required section, seeded in Private notes from the
  debrief's Unknowns list.
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
- `disclosure: recommended`, `none-found`, or `unknown`: mention it in Private notes (for `unknown`,
  say the policy could not be checked); do not insert disclosure text.

## Procedure 6: Lint (mode: lint)

Read the user's send block and add a **Lint** section to Private notes using the AP1-AP9 rules
(see `smart-questions-principles.md`), plus: unanswered `TODO(you)` (AP8), a "What changed" that
only restates the diff (AP1), "How it's tested" that lists passing commands (AP2), mentions of
files not in the diff (AP3), and AI trailers (AP9, evaluated against policy). Quote the offending
span and ask a question. Never rewrite the user's text or touch the send block.

## Output Template

Frontmatter: `scenario: prepare-pr`, `repo`, `item` (`issueN|pr-new`), `base`, `head`,
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
### Trailer findings
### Lint (lint mode)
```
