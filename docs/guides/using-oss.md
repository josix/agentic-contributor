# Using /oss

The `/oss` command in depth: intent classification, all 8 scenarios, the claim→engage branch, and draft-review behavior.

## How It Works

`/oss` is the single entry point for all contribution tasks. When you run it, the command:

1. **Reads `$ARGUMENTS`** — the text after `/oss`.
2. **Classifies the scenario** — invokes `oss-scenario-routing` to map your intent to one of the 8 scenarios. If intent is unclear, it asks one clarifying question (the scenario menu).
3. **Dispatches a subagent** — uses the Task tool to launch `oss-researcher` or `oss-claim-analyst` with the target `owner/repo`, the specific item (issue/PR number or query), and the scenario key.
4. **Loads the mapped skill** — applies domain-specific guidance to shape the output.
5. **Presents results** — a timestamped report, ranked list, briefing, guided walkthrough, or labeled DRAFT depending on the scenario.

## The 8 Scenarios in Detail

### Scenario 1 — status

**Intent signals:** "what's new", "latest releases", "recent issues/PRs", "project news", "what's happening in X"

**Example:**
```
/oss what's the latest status of apache/spark?
```

`oss-researcher` fetches recent releases, recently-updated open issues, and recently opened/merged PRs. Output is a timestamped report with direct links, organized by section (Releases / Issues / PRs). No skill is loaded. The orchestrator saves the report to `.oss-drafts/status-<owner>-<repo>-status-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

---

### Scenario 2 — find

**Intent signals:** "find an issue", "match me to a task", "good first issue", "what can I work on", "suggest a PR to help with"

**Example:**
```
/oss find a good first issue in apache/airflow
```

The `issue-matching` skill runs a 5-question intake, directs `oss-researcher` to fetch candidate issues and PRs, applies heuristic scoring, and returns a ranked shortlist of up to 10 items with per-item rationale. The orchestrator saves the shortlist to `.oss-drafts/find-<owner>-<repo>-find-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it." See [Skills Reference](../reference/skills.md) for the scoring rubric.

---

### Scenario 3 — norms

**Intent signals:** "contribution norms", "how do I contribute", "CLA", "DCO", "CONTRIBUTING", "governance", "how decisions are made"

**Example:**
```
/oss how do I contribute to apache/airflow — CLA and PR conventions?
```

`oss-researcher` fetches `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, PR/issue templates, and any DCO file. The `contribution-norms` skill structures the output into: legal prerequisites (ICLA/DCO), where to engage (GitHub / JIRA / mailing list), PR and commit conventions, and code of conduct. Apache-specific governance notes are included for ASF projects. The orchestrator saves the briefing to `.oss-drafts/norms-<owner>-<repo>-norms-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

---

### Scenario 4 — setup

**Intent signals:** "set up locally", "clone and build", "dev environment", "run the tests", "how do I build X"

**Example:**
```
/oss help me set up apache/airflow locally
```

`oss-researcher` optionally fetches `CONTRIBUTING.md` and setup docs. The `dev-env-setup` skill presents official setup steps in order, flags heavy setups (Airflow Breeze, Spark JDK+Maven), defines an "environment ready" checkpoint command, and confirms before any destructive or global system changes. The orchestrator saves the walkthrough to `.oss-drafts/setup-<owner>-<repo>-setup-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

---

### Scenario 5 — clarify

**Intent signals:** "draft a question", "ask the maintainer", "clarify the issue", "what does this issue mean", "I don't understand the design"

**Example:**
```
/oss draft a question about issue #12345 in apache/airflow
```

`oss-researcher` fetches the issue thread and linked docs. The `smart-questions` skill (Scenario A) identifies gaps not already answered in the thread and drafts specific, research-first questions with source citations. The orchestrator saves the draft to `.oss-drafts/clarify-<owner>-<repo>-issue<N>-<UTC>.md`, presents it in chat, and shows the mandatory draft notice: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."

---

### Scenario 6 — claim

**Intent signals:** "claim an issue", "can I take this", "is this issue free", "I want to work on #N"

**Example:**
```
/oss is issue #8765 in apache/spark free to claim?
```

`oss-claim-analyst` checks three signals: assignee, linked open PRs (via "Fixes #N" / "Closes #N"), and recent intent comments (last 30 days). It returns one of two verdicts:

- **"Appears free to take"** → `smart-questions` (Scenario D) drafts a polite claim comment (3–5 sentences; introduces contributor, states intent, asks if there are specific guidelines to keep in mind). The orchestrator saves the draft to `.oss-drafts/claim-<owner>-<repo>-issue<N>-<UTC>.md` and shows the mandatory draft notice.
- **"Appears already claimed"** → the command switches to the **engage** scenario automatically (see claim→engage branch below).

---

### Scenario 7 — engage

**Intent signals:** "give feedback on a PR", "help with someone's PR", "comment on PR", "review an in-progress PR", "there's a linked PR"

**Example:**
```
/oss help me give feedback on apache/airflow PR #9876
```

`oss-researcher` fetches the PR description, changed files/diff, CI status, review status, and the full comment thread. The `smart-questions` skill (Scenario B) identifies the most useful contribution based on PR state (failing CI, review-requested, stalled, needs rebase) and drafts constructive, specific feedback grounded in the actual diff. The orchestrator saves the draft to `.oss-drafts/engage-<owner>-<repo>-pr<N>-<UTC>.md` and shows the mandatory draft notice.

---

### Scenario 8 — review-reply

**Intent signals:** "respond to review", "reply to review comments", "maintainer left feedback on my PR", "how do I respond to this review"

**Example:**
```
/oss help me respond to the review on my apache/spark PR #4321
```

`oss-researcher` fetches the review comments on your PR. The `smart-questions` skill (Scenario C) drafts a reply per comment: acknowledges the feedback, states what was changed or explains the disagreement, stays concise, and does not fabricate changes. It may also produce a combined reply for thematically grouped comments and an optional change-summary comment. The orchestrator saves the draft to `.oss-drafts/review-reply-<owner>-<repo>-pr<N>-<UTC>.md` and shows the mandatory draft notice.

---

## The Claim→Engage Branch

When the **claim** scenario dispatches `oss-claim-analyst` and the verdict is **"appears already claimed"**, `/oss` switches to the **engage** scenario automatically:

1. Notifies you of the switch and explains which signal triggered the "claimed" verdict.
2. Dispatches `oss-researcher` to fetch the linked PR's diff, CI status, and discussion thread.
3. Loads `smart-questions` (Scenario B) to draft constructive engagement feedback instead.

This prevents a redundant claim comment on an issue already being worked on and redirects your energy where it is most useful.

## Draft-Review Behavior

All 8 scenarios save their output to `.oss-drafts/` in your current working directory as an editable markdown file. The `.oss-drafts/` directory is automatically excluded from version control via `.git/info/exclude` when `/oss` first writes a file in a git repo.

### Report tier (scenarios 1–4)

Scenarios **status, find, norms, setup** produce read-only reports or guided walkthroughs. After saving, the following notice is shown:

> Saved to `<path>`. Review and edit this report file as needed before using it.

These scenarios never produce outbound text and never trigger any write action toward GitHub.

### Draft tier (scenarios 5–8)

Scenarios **clarify, claim, engage, review-reply** produce outbound text. For each:

1. The full draft is saved to `.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md`.
2. The draft is presented in chat, clearly labelled.
3. The following notice is shown verbatim:

   > **DRAFT — saved to `<path>`. Review and edit this file before sending.**
   > This plugin will NOT post, comment, push, or send anything. Sending is handled by the
   > separate execution/submission plugin.

4. No tool that posts, comments, creates, or pushes is ever called. The `PreToolUse` guardrail hook enforces this at the tool level even if a bug in the command instructions attempted such a call.

See [Draft Files](../concepts/draft-files.md) for the full naming convention, frontmatter schema, and gitignore-ensure behavior.

---

[Back to docs index](../index.md) | Related: [GitHub Access](github-access.md) | [Draft Files](../concepts/draft-files.md) | [Draft-Only Guardrail](../concepts/draft-only-guardrail.md) | [Scenarios Reference](../reference/scenarios.md)
