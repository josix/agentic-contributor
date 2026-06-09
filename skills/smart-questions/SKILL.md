---
name: smart-questions
description: >
  This skill should be used when the user asks to draft a question to maintainers, draft PR
  feedback on someone else's in-progress pull request, draft a reply to review comments on their
  own PR, or draft a claim comment for an issue they want to take. Trigger phrases include:
  "draft a question to maintainers", "I want to ask about this issue", "draft PR feedback",
  "help me review this PR", "draft a review reply", "respond to maintainer feedback",
  "draft a claim comment", "I want to take this issue". All output from this skill is a DRAFT
  for the user's review — never posted automatically.
---

# Smart Questions

Refer to `references/smart-questions-principles.md` for the full principle set and a good/bad
example pair before drafting any question, comment, or reply.

## DRAFT-ONLY Contract

Every piece of outbound text this skill produces is a **DRAFT**. The contract is:

1. Present the complete draft text to the user, clearly labelled as a draft.
2. Add the notice: **"Review this draft before sending. This plugin will NOT post it — sending is
   handled by the separate execution/submission plugin."**
3. NEVER call any tool that posts, comments, pushes, or creates a GitHub resource.
4. The user may edit or cancel any draft before they decide to send it through the execution plugin.

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

## Scenario C — Draft Replies to Review Comments on My PR (review-reply)

To draft replies to maintainer review comments on the user's own pull request:

1. For each review comment, draft a reply that:
   - Acknowledges the feedback.
   - States what the user changed in response OR explains (respectfully) why they disagree.
   - Stays concise.
   - Does NOT commit to changes the user has not actually made.
   - Does NOT fabricate code changes.
2. If multiple comments can be grouped (same theme or same file area), offer to draft a combined
   reply covering them all.
3. Optionally produce a single **change-summary comment** recapping how this round of feedback was
   addressed (desirable per story 6 acceptance criteria).
4. Etiquette follows the principles in the references file (acknowledge, state action/rationale,
   stay concise, assume good faith).

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
