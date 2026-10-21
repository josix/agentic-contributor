# Smart Questions Principles

Adapted from [How-To-Ask-Questions-The-Smart-Way](https://github.com/ryanhanwu/How-To-Ask-Questions-The-Smart-Way)
by Eric S. Raymond and Rick Moen.

## Core Principles

1. **Research before asking.** Search the issue tracker, documentation, existing closed issues,
   and the project's mailing list/forum before drafting a question. State what you found (or didn't
   find) when you ask.

2. **Be specific and precise.** Describe your problem, goal, or confusion in concrete terms.
   Vague questions ("this doesn't work") receive vague answers. Include exact error messages,
   version numbers, and reproduction steps when relevant.

3. **Show prior effort.** Explain what you already tried and why it didn't resolve the question.
   This respects the maintainer's time and demonstrates you are not asking them to do your homework.

4. **Ask answerable questions.** Frame questions so they have a concrete answer. "What is the
   intended behaviour when X happens?" is answerable. "Can you help me with this?" is not.

5. **Be concise and respect the reader's time.** One well-formed question is better than five
   half-formed ones. Edit ruthlessly; remove context that is not relevant to the specific question.

6. **Be respectful and assume good faith.** Maintainers volunteer their time. Use a polite,
   professional tone. Do not demand, guilt-trip, or imply neglect.

7. **Don't ask what's already answered.** Read the issue/PR thread in full, check the
   CONTRIBUTING guide, and search linked docs before asking. Asking about something already
   explained in the thread wastes maintainer time and signals you haven't read the material.

8. **Cite the source of your confusion.** Reference the specific line, section, or comment that
   prompted your question. This lets the maintainer answer precisely without guessing context.

9. **Acknowledge the issue/PR's existing discussion.** Briefly summarise what you understand from
   the existing thread before asking your question. This shows you engaged with prior work.

10. **One question at a time (or a tight, numbered list).** If you must ask multiple things,
    number them and keep each one focused. Three tightly-scoped questions in one comment is fine;
    ten sprawling questions is not.

---

## Good vs. Bad Example

### Bad question (do NOT draft like this)

> Hi, I'm new here. I want to work on this issue but I don't really understand it. Can you explain
> everything I need to know? Also how do I set up the dev environment? Thanks

**Problems:** No research shown, vague scope, multiple unrelated asks, no specific confusion
identified, no reference to what they already read.

---

### Good question (draft like this)

> Hi @maintainer-name, I'm looking at issue #1234 (stale DAG state on database reconnect).
>
> I've read the issue thread and the `_execute_task_with_callbacks` docstring. I understand the
> proposed fix involves retrying the session after a `OperationalError`. My specific question is
> about the scope: should the retry logic live in the scheduler loop or in the task runner? The
> issue description mentions both places, and I want to make sure I target the right one before I
> write the fix.
>
> I've also checked the existing retry utilities in `airflow/utils/db.py` — would those be the
> right building block here, or is something else preferred?

**Why this works:** Research shown, specific confusion cited with file reference, one concrete
question with a proposed starting point, respectful and concise.

---

## Review-reply & PR-description anti-patterns (lint rules)

Used by `review-reply` lint mode. Each finding quotes the user's text, gives a severity
(`fix-before-sending` or `consider`), and asks a question. Lint never rewrites the user's text.

### AP1 — Summarises the diff instead of answering
Detect: restates what changed but never addresses the reviewer's question or concern.
Ask: "What was the reviewer's concern here, and where does this sentence answer it?"
- Bad: "I updated `parse()`, renamed two variables and added a test."
- Good: "You're right that a null input could reach `parse()`; I now return early and cover it in `test_parse_null`."

### AP2 — Lists local commands that passed
Detect: "ran cargo fmt / cargo test / pytest, all pass".
Ask: "Which specific test covers the concern the reviewer raised?"
- Bad: "Ran cargo fmt, cargo clippy and cargo test, all green."
- Good: "`test_retry_on_timeout` now covers the case you described."

### AP3 — Statement that does not fit the context
Detect: mentions files, APIs, or behaviour not in the PR diff or thread.
Ask: "Where in this PR or thread does that appear?"
- Bad: "This also fixes the cache invalidation in `Scheduler.flush`." (not in the diff)
- Good: "This only changes `Executor.run`; `Scheduler.flush` is untouched."

### AP4 — Unanswered direct question
Detect: the reviewer's comment contains `?` and the reply does not answer it.
Ask: "The reviewer asked '…?'. Which sentence answers it?"
- Bad: (reviewer: "Why not reuse `retry_utils`?") "Updated, thanks."
- Good: "`retry_utils` swallows `OperationalError`, which we need to surface, so I kept a local loop."

### AP5 — Claims a change that is not pushed
Detect: "fixed", "done", "updated" where the referenced change is not on the remote PR branch.
Commit timestamps do not establish push times (a fix committed before the comment may be pushed
after it), so verify against the PR itself: check the PR's commit list or diff for the change.
If only local or timestamp evidence exists, treat the result as inconclusive, not as a failure.
Ask: "Which commit on the PR makes this change? I cannot confirm one touching `<path>` is pushed."
- Bad: "Done." (no new commit)
- Good: "Fixed in `abc1234`." (commit exists), or "I'll push that change shortly."

### AP6 — Assistant boilerplate
Detect: "You're absolutely right", filler "Great catch!", "I apologize for the oversight",
"Certainly!", headers or bullet walls in a one-line answer.
Ask: "Is this how you would say it to this reviewer?"
- Bad: "Great catch! You're absolutely right, I apologize for the oversight."
- Good: "Good point, I missed the empty-list case."

### AP7 — Length out of proportion to the question
Detect: a long reply to a short question, or several paragraphs for a nit.
Ask: "Could the answer to this one-line comment fit in one or two sentences?"
- Bad: Three paragraphs answering "nit: rename to `count`".
- Good: "Renamed."  (when it is true and pushed)

### AP8 — Leftover `TODO(you)` or empty send block
Detect: `TODO(you)` remains inside an `oss:send` block, or the block is empty.
Ask: "This reply is not written yet. Is it ready to send?" Severity: `fix-before-sending`.
- Bad: `TODO(you): reply in your own words`
- Good: the user's own sentences.

### AP9 — AI co-author trailer or "Generated with…" footer (active from v0.5.0)
Inactive until a policy profile exists (v0.5.0). Then it applies when
`policy.coauthor_trailer_forbidden` is true or `policy.ai_policy` is not `none-found`.
Ask: "This project's policy restricts AI attribution trailers. Do you want this footer here?"
- Bad: "Co-Authored-By: Claude …" in a reply or PR description.
- Good: no trailer, or the disclosure the project's policy asks for.

---

## Reference

Full guide: https://github.com/ryanhanwu/How-To-Ask-Questions-The-Smart-Way
