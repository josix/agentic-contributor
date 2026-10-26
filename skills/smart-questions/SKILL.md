---
name: smart-questions
description: >
  This skill should be used when the user asks to draft a question to maintainers, draft PR
  feedback on someone else's in-progress pull request, draft a reply to review comments on their
  own PR (understanding brief plus lint of the user's own reply, never a ghostwritten reply), or
  draft a claim comment for an issue they want to take. Trigger phrases include:
  "draft a question to maintainers", "I want to ask about this issue", "draft PR feedback",
  "help me review this PR", "draft a review reply", "respond to maintainer feedback",
  "check my reply", "lint my reply", "review my draft reply",
  "draft a claim comment", "I want to take this issue". All output from this skill is a DRAFT
  for the user's review — never posted automatically.
---

# Smart Questions

Refer to `references/smart-questions-principles.md` for the full principle set and a good/bad
example pair before drafting any question, comment, or reply.

## DRAFT-ONLY Contract

Every piece of outbound text this skill produces is a **DRAFT**. The contract is:

1. Return the complete draft text to the orchestrating `/oss` command. The orchestrator saves it
   to a `.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md` file using the Write tool, then
   presents it to the user.
2. After saving, the orchestrator adds the mandatory notice:
   > **DRAFT — saved to `<path>`. Review and edit this file before sending.**
   > This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin.
3. NEVER call any tool that posts, comments, pushes, or creates a GitHub resource.
4. The user may edit the saved file or cancel the draft before deciding to send it through the
   execution plugin.

This contract applies to every scenario below without exception.

## Scenario A — Draft Questions for Maintainers (clarify)

To draft clarifying questions for a maintainer about an issue or PR:

1. Summarise what is **already known** from the issue/PR thread, linked docs, and the project's
   contributing guide — so questions do not re-ask what is answered.
2. Identify the specific **gaps or ambiguities** in the issue/PR that are worth clarifying (design
   intent, scope boundaries, API choices, preferred approach).
3. Draft each question following the principles in the references file:
   - Research first: cite what was already read.
   - Be specific: reference the exact line/section/comment that prompted the question.
   - Show prior effort: mention what was tried or considered.
   - Ask answerable questions: frame for a concrete answer.
4. For each drafted question, note **which part of the issue/PR** (paragraph, comment, or code
   reference) prompted it so the user can judge relevance.
5. Do NOT include questions that are already answered in the thread, linked issues, or the
   CONTRIBUTING guide.

## Scenario B — Draft Feedback on Someone's In-Progress PR (engage)

To draft constructive feedback on another contributor's pull request:

1. Confirm the oss-researcher has fetched: the PR description, changed files/diff, CI status,
   review status, and the full comment thread.
2. Summarise what the PR does and where it currently stands (awaiting review, failing CI, stalled,
   needs rebase, etc.).
3. Suggest the most useful way the user can help based on the PR's state:
   - Failing CI → offer to investigate/reproduce the failure.
   - Review-requested → offer a specific-file review.
   - Stalled > 30 days → offer to take over or rebase (if appropriate).
   - Needs rebase → note the conflicts.
4. Draft feedback that is:
   - Constructive and specific — grounded in the actual diff and discussion.
   - Not dismissive, duplicative, or based on parts of the PR not shown.
   - Respectful and professional in tone.
5. For large diffs, scope feedback to the most relevant files and state that explicitly.
6. Note which part of the diff or discussion each feedback point addresses.

## Scenario C — Understand Review Comments and Reply in Your Own Words (review-reply)

This scenario does **not** write the reply. It helps the user understand each review comment and
then checks the reply the user writes. It has two modes under the same `review-reply` scenario.
Never produce a full prose reply, a "suggested reply", or a reply assembled from talking points,
even if the user asks; point to the brief and offer lint mode instead.

### Mode detection

- **`mode: brief`** (default): the user wants help responding to review feedback on their own PR
  ("respond to review", "how do I respond to this review").
- **`mode: lint`**: the user asks to check text they wrote ("check my reply", "lint my reply",
  "review my draft reply", or points at an existing `.oss-drafts/review-reply-…md` file).

### Brief mode

For each review comment, produce a **private** brief (it goes in "Private notes (not sent)"):

1. **What the reviewer is asking** — quote the comment.
2. **The code** — the exact code at the referenced `path`/`line` (from the comment's diff hunk).
3. **Likely concern** — correctness, API stability, style, performance, scope, or tests.
4. **Project conventions** that apply (from contribution norms, if known).
5. **What changed since the comment** — a commit-to-comment mapping row. Fetched commit data
   gives authored/committed timestamps, which are **not push times**, so do not claim a commit
   was "pushed after" the comment from them. Instead verify against the remote PR head (read-only:
   compare the PR's current commits/diff for that file with the comment's diff hunk and
   `commit_id`/`original_commit_id`). List commits touching that file that are newer than the
   comment's `created_at` by commit timestamp, and label the timing "push time unknown". Say
   "no commit touches this yet" only when the remote PR head still matches the commented hunk;
   if the remote cannot be checked, say "unknown: could not verify remote changes".
6. **Questions to ask yourself** (2–3) before replying, e.g. "Do I agree? What evidence would
   show it?", "Did I actually change this?".
7. **Talking points** (optional) — short bullets of facts and options only. Never sentences that
   read as a ready-to-post reply; if a bullet list would read as a reply, drop it.

Then, for the sendable part of each comment, write only the placeholder inside the send block:
`TODO(you): reply in your own words`. Do not fill it.

Group comments by theme or file area in the brief when that helps understanding; each grouped
comment still gets its own placeholder.

### Translate and tidy (only on request)

If the user supplies their own rough notes or text (including in another language) and asks for
help, the plugin may translate or tidy **only that text**: fix grammar, translate, tighten.
It must add **no new claims**: no new facts, no new commitments, no new technical reasoning, no
"fixed"/"done" the user did not write. Show the result for the user to accept or edit; keep
anything it changed visible. Project AI policies (e.g. Apache DataFusion) explicitly allow AI help
with understanding and translation.

### Lint mode

0. **Validate the draft format first.** Read the file's frontmatter. Proceed only if
   `body_format: 2` and it contains at least one `oss:send` block. If the file has `sendable: false` (a
   private debrief or track ledger), refuse: it is never sendable or lintable. If `body_format` is absent
   or `1` (legacy: whole body sendable, no send blocks), or no send block is found, do **not**
   lint and do not silently skip. Tell the user the file is legacy and offer two options: (a)
   migrate it, with the user confirming which text is their own reply and moving it into
   `oss:send` markers with `body_format: 2` (never altering the text), or (b) paste the reply
   text to lint directly. Refuse to report any lint result until one is chosen.
1. Read the user-written text inside each `oss:send` block of the named draft file (if it is
   still `TODO(you)` or empty, that is finding AP8).
2. Run the anti-pattern rules AP1–AP9 from `references/smart-questions-principles.md`. AP3
   (needs the full PR diff and thread) and AP5 (needs the remote PR's commits) require fetched
   context; the saved brief holds only selected hunks. In a fresh session, fetch the PR diff,
   thread, and commits (read-only) first. If a fetch is not possible, mark the affected rules
   **unevaluated** in the Lint section rather than passing them, and never report an overall
   pass while any rule is unevaluated. AP9 is active only when the draft frontmatter `policy`
   has `coauthor_trailer_forbidden: true` or `ai_policy` not `none-found`; otherwise it is
   unevaluated, not passed.
3. Report findings in a **Lint** section inside Private notes: for each finding give the rule ID,
   severity (`fix-before-sending` or `consider`), the **quoted span** of the user's text, and a
   **question** back to the user. End with a pass/fail summary.
4. **Never rewrite** the user's text and never touch the send block. Findings are questions, not
   replacements.

### Removed: change-summary comment

The old postable "change-summary comment" is dropped. A commit recap is the "summarise the diff"
anti-pattern (AP1). The commit-to-comment mapping in the brief replaces it, as private notes.

### Why no ghostwriting

Maintainers increasingly reject AI-generated review replies (the Apache DataFusion AI policy, and
the "meat proxy" critique: a human relaying a model's words wastes the reviewer's time and shows no
understanding). The plugin therefore builds the contributor's understanding and checks their own
words, and leaves the reply to the contributor. Etiquette still follows the references file
(acknowledge, state action/rationale, stay concise, assume good faith) as guidance for the user.

## Scenario D — Draft a Claim Comment (claim)

To draft a claim comment for an issue the user wants to take:

1. Confirm the oss-claim-analyst has already assessed the issue as **"appears free to take"**.
   If the issue is claimed, do NOT draft a claim comment — switch to Scenario B (engage) instead.
2. Note the project's preferred claiming mechanism if known from the contribution norms:
   - Some projects prefer a comment ("I'd like to take this").
   - Some prefer self-assign (if the contributor has triage permissions).
   - Apache projects may use JIRA assignment or a dev@ mailing list thread.
3. Draft a polite, brief claim comment following the smart-questions principles:
   - Introduce yourself briefly (optional but friendly for first-time contributors).
   - State your intent to work on the issue.
   - Mention any relevant skills or context that makes you a good fit.
   - Ask if there is anything specific the maintainer would like you to keep in mind.
4. Keep the draft short (3–5 sentences max). Do not over-promise scope or timeline.

## References

See `references/smart-questions-principles.md` for the full principle list and good/bad examples.
Full guide: https://github.com/ryanhanwu/How-To-Ask-Questions-The-Smart-Way
