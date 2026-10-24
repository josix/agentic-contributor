# Maintainer-Friendly Contributing

Why `/oss` helps you understand and write, instead of writing for you.

## The problem

Maintainers are flooded with plausible-looking but low-effort contributions. Several projects now
state policies against AI-generated communication (for example the Apache DataFusion AI policy
rejects AI-generated review replies), and the "meat proxy" critique names the failure mode: a human
relaying a model's words without understanding them. It wastes the reviewer's time and erodes trust.

The same policies generally allow AI help with *understanding* and *translation*. This plugin sits
on that line.

## What the plugin does

- **Helps you understand.** For each review comment, `review-reply` builds a private brief: the
  quoted comment, the code at that line, the likely concern, project conventions, which commits
  since the comment touch that file, and questions to ask yourself.
- **Leaves the reply to you.** The send block holds only `TODO(you): reply in your own words`.
  There is no option to generate a full reply.
- **Checks your words.** Lint mode runs the anti-pattern rules (AP1-AP9) over what you wrote and
  asks questions about quoted spans. It never rewrites your text.
- **Translates or tidies only your own text**, on request, adding no new claims.

## Anti-patterns checked

| ID | Pattern |
|----|---------|
| AP1 | Summarises the diff instead of answering |
| AP2 | Lists local commands that passed |
| AP3 | Statement that does not fit the PR or thread |
| AP4 | Unanswered direct question |
| AP5 | Claims a change that is not pushed |
| AP6 | Assistant boilerplate ("You're absolutely right", "Great catch!") |
| AP7 | Length out of proportion to the question |
| AP8 | Leftover `TODO(you)` or empty send block |
| AP9 | AI co-author trailer or "Generated with" footer (active when the draft's `policy` shows a co-author trailer ban or an AI policy) |

Bad/good examples for each rule are in `skills/smart-questions/references/smart-questions-principles.md`.

## Sendable vs private

Draft files separate the text you may post (inside `oss:send` markers) from private notes. The
execution plugin posts only the send block and refuses while `TODO(you)` remains. See
[Draft Files](draft-files.md#body-format) and [Two-Plugin System](two-plugin-system.md).

## Project policy awareness

Since v0.5.0 the plugin also detects a project's AI-use policy and contribution limits (AI policy
files, PR-template disclosure, open-PR caps, vouch lists, issue-first rules) and carries them into
every draft as a `policy` block. Examples: Apache DataFusion's AI policy and its cap of 3 open PRs
for non-committers (`.asf.yaml`), and Ghostty's AI policy and vouch list (`.github/VOUCHED.td`).
Reminders appear in private notes only and are advisory. Where a project prefers an issue first, a
PR-intent request is routed to `report`. Not found means "not found", never "no policy"; check the
project website too.

## Contributor readiness and track record

Since v0.6.0, `claim` and `find` add a private, advisory readiness self-check, based on Andrew
Lamb's review-priority tiers: actual users, then prior contributors, then contributors endorsed by a
committer, then established accounts, then newcomers. It reads only your own public data (open PRs
vs the project's cap, merged PRs, account age, vouch status), shows which login it used, and appears
only in private notes. It never blocks a draft, and every gap comes with a next step such as
reviewing a PR, confirming a bug, or finishing an open PR first. `find` then favours that kind of
work when you are new to a project, and lists good first issues reserved for unassisted newcomers
in a separate footer. Say "skip readiness" to opt out.

## Still draft-only

Nothing here posts anything. The plugin saves files under `.oss-drafts/`; sending belongs to the
separate execution plugin and to you.

---

[Back to docs index](../index.md) | Related: [Draft Files](draft-files.md) | [Two-Plugin System](two-plugin-system.md) | [Using /oss](../guides/using-oss.md)
