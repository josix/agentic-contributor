# Skills Reference

The five skills in the `agentic-contributor` plugin. Each skill is a domain-expertise module loaded by the `/oss` command after scenario classification.

## Overview

| Skill | Trigger scenario | Purpose |
|---|---|---|
| `oss-scenario-routing` | Always (Step 2 of `/oss`) | Classifies intent into one of the 8 scenarios |
| `issue-matching` | find | Contributor intake, heuristic scoring, ranked shortlist |
| `smart-questions` | clarify, claim, engage, review-reply | DRAFT-ONLY contract for all outbound-text scenarios |
| `contribution-norms` | norms | Surfaces CONTRIBUTING, CLA/DCO, PR conventions, governance |
| `dev-env-setup` | setup | Step-by-step guided local dev environment |

---

## `oss-scenario-routing`

**Trigger phrases:** "find an issue to contribute", "check project status", "draft a question to maintainers", "understand contribution norms", "set up the project locally", "claim an issue", "give feedback on a PR", "respond to PR review", and close variants.

**What it provides:**
- Matches `$ARGUMENTS` against 8 scenario intent signals. The first strong match wins.
- If no strong match: presents the scenario menu and asks one clarifying question (maximum one question before classifying and proceeding).
- Specifies the skill and subagent to load/dispatch for the classified scenario.
- Handles the claim→engage branch: if `oss-claim-analyst` returns "appears already claimed", the skill directs a switch to the **engage** scenario.
- Enforces the DRAFT-ONLY rule for all 8 scenarios: report tier (1–4) saves to `.oss-drafts/` and shows a "Saved to…" notice; draft tier (5–8) additionally presents the draft in chat with the canonical draft notice.
- Confirms that none of the 8 scenarios ever trigger write actions toward GitHub.

**References:** `skills/oss-scenario-routing/SKILL.md`

---

## `issue-matching`

**Trigger phrases:** "find an issue to work on", "match me to a task", "suggest a good first issue", "what can I contribute", "find a PR I can help with", "show me newcomer-friendly issues", and close variants.

**What it provides:**

1. **Structured intake** — asks up to 5 questions: goal/intent, background skills, newcomer status, item type preference (issues/PRs/both), and target projects.
2. **Data gathering** — directs `oss-researcher` to fetch open issues with relevant labels (`good first issue`, `help wanted`, `bug`, `enhancement`, `docs`) and stalled/review-requested PRs.
3. **Exclusion filter** — removes closed, merged, assigned, locked, or "wontfix" items.
4. **Heuristic scoring** — ranks items by: newcomer-friendly labels (+3/+2), tech-stack overlap (+2), recent activity (+1), maintainer engagement (+1), clear unblock opportunity for PRs (+1), intent match (+2).
5. **Ranked shortlist** — top 5–10 items, each with link, type, labels, last-updated date, and a 1–2 sentence rationale. The orchestrator saves the shortlist to `.oss-drafts/find-…` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

**References:** `skills/issue-matching/SKILL.md`

---

## `smart-questions`

**Trigger phrases:** "draft a question to maintainers", "I want to ask about this issue", "draft PR feedback", "help me review this PR", "draft a review reply", "respond to maintainer feedback", "draft a claim comment", "I want to take this issue".

**What it provides:**

All output is a DRAFT. The contract:
1. Return the complete draft to the orchestrator, which saves it to `.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md` using the Write tool.
2. The orchestrator presents the draft in chat and adds the mandatory notice: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."
3. Never call any tool that posts, comments, pushes, or creates a GitHub resource.

Four scenario-specific procedures:

| Scenario | Procedure | Key behavior |
|---|---|---|
| **A — clarify** | Draft questions for maintainers | Summarizes what is already known; drafts specific, research-first questions with source citations |
| **B — engage** | Draft feedback on someone's PR | Scoped to the actual diff; identifies the most useful contribution based on PR state |
| **C — review-reply** | Draft replies to review comments on your PR | Acknowledges feedback, states action or rationale, stays concise, never fabricates changes |
| **D — claim** | Draft a claim comment | Only proceeds if `oss-claim-analyst` returns "free to take"; 3–5 sentences; follows project's preferred claiming mechanism |

**References:** `skills/smart-questions/SKILL.md`, `skills/smart-questions/references/smart-questions-principles.md`

---

## `contribution-norms`

**Trigger phrases:** "how do I contribute to X", "what are the contribution norms", "do I need to sign a CLA", "what's the DCO", "where do decisions happen", "what's the governance model", "CONTRIBUTING guide", "how should I format my PR title", "what mailing list should I use".

**What it provides:**

1. **Governing documents** — locates and fetches `CONTRIBUTING.md` (or `.rst`), `CODE_OF_CONDUCT.md`, `.github/PULL_REQUEST_TEMPLATE.md`, any DCO file, and README contributing sections.
2. **Legal prerequisites** — ICLA / DCO requirements and what action is required before a first PR can be merged.
3. **Where decisions happen** — GitHub Issues/PRs, Apache JIRA, dev@ mailing list, Confluence/Wiki, voting and lazy-consensus rules.
4. **Commit and PR title conventions** — required title format (e.g., `[SPARK-NNNN][COMPONENT]`), commit message format, bot checks, required issue links.
5. **Code of conduct** — summary and link (ASF CoC for Apache projects).
6. **Apache-specific notes** — ICLA, DCO sign-off, JIRA vs GitHub workflow, lazy consensus, and `[PROJECT-NNNN]`-style title conventions from `references/apache-governance.md`.
7. **What's missing** — explicitly states when a governing document cannot be found; never fabricates norms. The orchestrator saves the briefing to `.oss-drafts/norms-…` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

**References:** `skills/contribution-norms/SKILL.md`, `skills/contribution-norms/references/apache-governance.md`

---

## `dev-env-setup`

**Trigger phrases:** "set up the project locally", "how do I clone and build X", "help me get the dev environment running", "how do I run the tests for X", "I can't get the build to work", "set up apache/airflow locally", "set up apache/spark locally", "what are the prerequisites for X".

**What it provides:**

1. **Official steps** — extracts setup steps from `CONTRIBUTING.md`, `README.md`, and `docs/` in order. Never improvises steps not in the documentation.
2. **Heavy-setup flags** — warns before the user starts about known heavy setups: Airflow Breeze (Docker-based, several GB, 15–30 min), Spark JDK+Maven (JDK 8/11/17, 10–30 min full build).
3. **Environment-ready checkpoint** — presents the specific verification command (e.g., `pytest tests/unit/`, `./gradlew test`) and what a passing result looks like.
4. **Failure diagnosis** — identifies which requirement or version constraint is not met; refers back to documented prerequisites; never suggests changes that could break other projects without explicit confirmation.
5. **Destructive-action confirmation** — presents a yes/no confirmation step before any action that would upgrade a system package, change `$PATH` permanently, or remove existing virtual environments.
6. **Scope boundary** — explicitly states that writing code, committing, opening PRs, and pushing branches are out of scope and belong to the execution/submission plugin. The orchestrator saves the walkthrough to `.oss-drafts/setup-…` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

**References:** `skills/dev-env-setup/SKILL.md`

---

[Back to docs index](../index.md) | Related: [Agents](agents.md) | [Commands](commands.md) | [Scenarios](scenarios.md) | [Draft Files](../concepts/draft-files.md)
