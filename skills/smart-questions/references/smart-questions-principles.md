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

## Reference

Full guide: https://github.com/ryanhanwu/How-To-Ask-Questions-The-Smart-Way
