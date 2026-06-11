# Scenarios Reference

Canonical 8-scenario table with full detail: intent signals, skill, agent, data source, output type, and guardrail relevance.

## Scenario Catalog

| # | Key | Intent signals | Skill | Agent | Data source | Output | Draft file |
|---|---|---|---|---|---|---|---|
| 1 | **status** | "what's new", "latest releases", "recent issues/PRs", "project news", "what's happening in X" | none | `oss-researcher` | GitHub API (MCP or gh CLI) | Timestamped report | `.oss-drafts/status-…` |
| 2 | **find** | "find an issue", "match me to a task", "good first issue", "what can I work on", "suggest a PR to help with" | `issue-matching` | `oss-researcher` | GitHub API (MCP or gh CLI) | Ranked shortlist with rationale | `.oss-drafts/find-…` |
| 3 | **norms** | "contribution norms", "how do I contribute", "CLA", "DCO", "CONTRIBUTING", "governance", "how decisions are made" | `contribution-norms` | `oss-researcher` | GitHub repo files via MCP / gh API | Contribution briefing | `.oss-drafts/norms-…` |
| 4 | **setup** | "set up locally", "clone and build", "dev environment", "run the tests", "how do I build X" | `dev-env-setup` | `oss-researcher` (optional) | CONTRIBUTING, README, docs/ | Step-by-step guided walkthrough | `.oss-drafts/setup-…` |
| 5 | **clarify** | "draft a question", "ask the maintainer", "clarify the issue", "what does this issue mean", "I don't understand the design" | `smart-questions` (Scenario A) | `oss-researcher` | Issue thread, linked docs | DRAFT questions | `.oss-drafts/clarify-…` |
| 6 | **claim** | "claim an issue", "can I take this", "is this issue free", "I want to work on #N" | `smart-questions` (Scenario D) | `oss-claim-analyst`; `oss-researcher` on engage branch | Issue details, assignees, linked PRs | Verdict + DRAFT claim comment; or auto-switch to engage | `.oss-drafts/claim-…` |
| 7 | **engage** | "give feedback on a PR", "help with someone's PR", "comment on PR", "review an in-progress PR", "there's a linked PR" | `smart-questions` (Scenario B) | `oss-researcher` | PR diff, CI status, comment thread | DRAFT feedback comment | `.oss-drafts/engage-…` |
| 8 | **review-reply** | "respond to review", "reply to review comments", "maintainer left feedback on my PR", "how do I respond to this review" | `smart-questions` (Scenario C) | `oss-researcher` | PR review comments | DRAFT review replies | `.oss-drafts/review-reply-…` |

All outputs are saved as editable markdown files in `.oss-drafts/` in the user's working
directory. Report-tier scenarios (1–4) show a "Saved to `<path>`" notice. Draft-tier scenarios
(5–8) show the draft in chat plus the mandatory "**DRAFT — saved to `<path>`. Review and edit
this file before sending.**" notice. See [Draft Files](../concepts/draft-files.md) for the full
naming convention and frontmatter schema.

## Scenario Detail Notes

### Scenario 1 — status

No skill is loaded. `oss-researcher` returns findings directly as a timestamped markdown report organized by section (Releases / Issues / PRs). The report includes direct GitHub links and data freshness notes. The orchestrator saves the report to `.oss-drafts/status-<owner>-<repo>-status-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 2 — find

`issue-matching` runs a 5-question structured intake before directing `oss-researcher` to fetch candidates. Items are filtered (no closed, assigned, locked, or wontfix) and scored using a heuristic rubric. The shortlist includes up to 10 items; each entry has a rationale sentence linking to the contributor's stated skills and goal. The orchestrator saves the shortlist to `.oss-drafts/find-<owner>-<repo>-find-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 3 — norms

`contribution-norms` directs `oss-researcher` to fetch CONTRIBUTING, CODE_OF_CONDUCT, PR/issue templates, and DCO files. For Apache Software Foundation projects, `references/apache-governance.md` provides additional context on ICLA, JIRA workflows, and lazy-consensus voting. Documents that cannot be found are explicitly noted — nothing is fabricated. The orchestrator saves the briefing to `.oss-drafts/norms-<owner>-<repo>-norms-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 4 — setup

`dev-env-setup` presents setup steps in the order documented in the official source. Heavy or platform-specific setups are flagged before the user starts (Airflow Breeze, Spark JDK+Maven). An "environment ready" checkpoint command is given. Any step that would make a destructive system change requires explicit yes/no confirmation. Scope ends at a verified, ready dev environment. The orchestrator saves the walkthrough to `.oss-drafts/setup-<owner>-<repo>-setup-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 5 — clarify

`smart-questions` (Scenario A): before drafting, the skill summarizes what is already known from the issue thread and linked docs so the draft does not re-ask answered questions. Each drafted question cites the specific part of the issue/PR that prompted it. The orchestrator saves the draft to `.oss-drafts/clarify-<owner>-<repo>-issue<N>-<UTC>.md`, presents it in chat, and shows: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."

### Scenario 6 — claim

`oss-claim-analyst` checks: (1) assignee field, (2) linked open PRs via "Fixes #N" / "Closes #N" in PR bodies, (3) intent comments in the last 30 days. Stale claims (comment older than 30 days, no follow-up PR, issue still open and unassigned) are flagged separately. If the verdict is "appears already claimed", the `/oss` command notifies the user and switches automatically to scenario 7 (engage). The orchestrator saves the verdict and draft claim comment (or engage draft) to `.oss-drafts/claim-<owner>-<repo>-issue<N>-<UTC>.md` and shows the mandatory draft-tier notice.

### Scenario 7 — engage

`smart-questions` (Scenario B): the skill identifies the most useful contribution based on PR state — reproducing a CI failure, reviewing specific changed files, offering a rebase for a stalled PR, noting rebase conflicts. Feedback is scoped to the actual diff and discussion; large diffs are handled by scoping to the most relevant files. The orchestrator saves the draft to `.oss-drafts/engage-<owner>-<repo>-pr<N>-<UTC>.md` and shows the mandatory draft-tier notice.

### Scenario 8 — review-reply

`smart-questions` (Scenario C): one reply draft per review comment. Thematically grouped comments may be addressed in a combined reply. An optional change-summary comment is offered, recapping how the review round was addressed. Replies acknowledge feedback, state what was changed or explain the disagreement, stay concise, and assume good faith. The orchestrator saves the draft to `.oss-drafts/review-reply-<owner>-<repo>-pr<N>-<UTC>.md` and shows the mandatory draft-tier notice.

## The Claim→Engage Branch

This is a special routing case within scenario 6:

```
/oss claim #N in owner/repo
  → oss-claim-analyst: "appears already claimed"
  → /oss notifies user of the switch
  → dispatch oss-researcher for linked PR context
  → load smart-questions (Scenario B)
  → produce engage DRAFT instead of claim DRAFT
```

The switch is automatic when `oss-claim-analyst` finds an assignee, active linked PR, or a recent intent comment. The user is notified which signal triggered the switch.

---

[Back to docs index](../index.md) | Related: [Commands](commands.md) | [Agents](agents.md) | [Skills](skills.md) | [Using /oss](../guides/using-oss.md)
