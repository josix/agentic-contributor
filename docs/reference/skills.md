# Skills Reference

The 9 skills in the `agentic-contributor` plugin. Each skill is a domain-expertise module loaded by the `/oss` command after scenario classification.

## Overview

| Skill | Trigger scenario | Purpose |
|---|---|---|
| `oss-scenario-routing` | Always (Step 2 of `/oss`) | Classifies intent into one of the 10 scenarios |
| `issue-matching` | find | Contributor intake, heuristic scoring, track-record-first ranked shortlist, policy-reserved footer |
| `contributor-readiness` | claim, find, prepare-pr | Advisory, private self-check of how maintainers will likely see your PR (open PRs vs cap, merged PRs, account age, vouch) |
| `smart-questions` | clarify, claim, engage, review-reply | DRAFT-ONLY contract for outbound-text scenarios 5–8 (prepare-pr uses `pr-preparation`); review-reply is brief + lint, never ghostwritten |
| `contribution-norms` | norms | Surfaces CONTRIBUTING, CLA/DCO, PR conventions, governance |
| `dev-env-setup` | setup | Step-by-step guided local dev environment |
| `issue-drafting` | report | DRAFT-ONLY new issue (bug report or feature request) with pre-flight duplicate search and ISSUE_TEMPLATE application |
| `pr-preparation` | prepare-pr | Size and shape check and a problem-first PR description scaffold you complete; never pushes or opens a PR |
| `change-debrief` | prepare-pr (`mode: debrief`) | Private walkthrough of what changed, why, and impact, with explain-back questions; never PR text |

---

## `oss-scenario-routing`

**Trigger phrases:** "find an issue to contribute", "check project status", "draft a question to maintainers", "understand contribution norms", "set up the project locally", "claim an issue", "give feedback on a PR", "respond to PR review", and close variants.

**What it provides:**
- Matches `$ARGUMENTS` against 10 scenario intent signals. The first strong match wins.
- If no strong match: presents the scenario menu and asks one clarifying question (maximum one question before classifying and proceeding).
- Specifies the skill and subagent to load/dispatch for the classified scenario.
- Handles the claim→engage branch: if `oss-claim-analyst` returns "appears already claimed", the skill directs a switch to the **engage** scenario.
- Enforces the DRAFT-ONLY rule for all 10 scenarios: report tier (1–4) saves to `.oss-drafts/` and shows a "Saved to…" notice; draft tier (5–10) additionally presents the draft in chat with the canonical draft notice.
- Confirms that none of the 10 scenarios ever trigger write actions toward GitHub.

**References:** `skills/oss-scenario-routing/SKILL.md`

---

## `issue-matching`

**Trigger phrases:** "find an issue to work on", "match me to a task", "suggest a good first issue", "what can I contribute", "find a PR I can help with", "show me newcomer-friendly issues", and close variants.

**What it provides:**

1. **Structured intake** — asks up to 5 questions: goal/intent (including reproduce/triage, review, docs/tests), background skills, relationship with the project (use it / contributed before / neither), item type preference (issues/PRs/both), and target projects.
2. **Data gathering** — directs `oss-researcher` to fetch open issues with relevant labels (`good first issue`, `help wanted`, `bug`, `enhancement`, `docs`) and stalled/review-requested PRs.
3. **Exclusion filter** — removes closed, merged, assigned, locked, or "wontfix" items. When the policy block has `gfi_ai_ban: true`, good first issues leave the ranking and appear in an unranked **Policy-reserved** footer.
4. **Heuristic scoring** — ranks items by: newcomer-friendly labels (+3/+2), tech-stack overlap (+2), recent activity (+1), maintainer engagement (+1), clear unblock opportunity for PRs (+1), intent match (+2); good-first-issue bonuses apply only when `gfi_ai_ban` is not `true`; +3 for areas you use, +2 for repro/triage/review work at readiness tier 4-5 (or with 0 merged PRs), -2 for new-code items when at the open-PR cap, +1 for `help wanted` with a clear spec. Triage-labelled issues, un-triaged issues, and review-requested PRs are fetched too.
5. **Ranked shortlist** — top 5–10 items, each with link, type, labels, last-updated date, and a work type (code, repro, triage, review, docs), a track-record value line, and a 1–2 sentence rationale, plus a private Readiness summary at the top. The orchestrator saves the shortlist to `.oss-drafts/find-…` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

**References:** `skills/issue-matching/SKILL.md`

---

## `contributor-readiness`

**Trigger phrases:** "am I ready to contribute", "will maintainers prioritise my PR", "check my readiness", "how do I build a track record". Runs by default inside claim, find, and prepare-pr; say "skip readiness" to opt out. In prepare-pr the block goes in Private notes (Pre-flight section), never inside the paste-ready PR description.

**What it provides:**

1. **Login resolution** — your request (`as @login`), then `contributor.github_login` in the plugin's `config/targets.yaml`, then the authenticated account (`get_me` / `gh api user`). The login used is shown and recorded as `readiness_login`.
2. **Signals** — open PRs in the repo vs the project's cap, merged PRs, prior involvement and `author_association`, account age and activity elsewhere, vouch status, and whether you use the project. About 5 read-only calls, for your own login only.
3. **Tier mapping** (after Andrew Lamb's review-priority ordering) — actual user, prior contributor, endorsed, established account, new to the project, shown as how maintainers are likely to see your PR today, with steps to move up.
4. **Advisory output** — Private notes only, never inside an `oss:send` block, never blocking a draft. Warns at the open-PR cap or when unvouched where vouching is required. Wording is about how maintainers see the contribution, never about you.

**References:** `skills/contributor-readiness/SKILL.md`

---

## `smart-questions`

**Trigger phrases:** "draft a question to maintainers", "I want to ask about this issue", "draft PR feedback", "help me review this PR", "draft a review reply", "respond to maintainer feedback", "check my reply", "lint my reply", "draft a claim comment", "I want to take this issue".

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
| **C — review-reply** | Understanding brief per review comment, then lint of the reply you write | Brief mode: quoted comment, code, likely concern, commit mapping, self-questions, `TODO(you)` placeholder (no prose reply). Lint mode: AP1-AP9 findings as quoted spans + questions, never rewrites. Translates/tidies only your own text, no new claims |
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
7. **AI & contribution-limit policy (step 6b)** — detects AI policy documents, CONTRIBUTING AI sections, PR-template disclosure checkboxes, AI co-author trailer rules, open-PR caps (e.g. `.asf.yaml` `github.pull_requests.creation_cap`), vouch lists (`VOUCHED*`), good-first-issue AI rules, and issue-first rules. The `norms` briefing gets "AI Use Policy" and "Contribution Limits & Trust Gates" sections, each finding with a source and confidence. Absence is reported as "not found", never "no policy". A **Policy Preflight** procedure returns only the `policy` block for other scenarios.
8. **What's missing** — explicitly states when a governing document cannot be found; never fabricates norms. The orchestrator saves the briefing to `.oss-drafts/norms-…` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

**References:** `skills/contribution-norms/SKILL.md`, `skills/contribution-norms/references/apache-governance.md`, `skills/contribution-norms/references/ai-policy-signals.md`

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

## `issue-drafting`

**Trigger phrases:** "draft a bug report", "file a new issue", "report a bug in X", "draft a feature request", "propose a feature", "write up an issue for X", "open an issue about".

**What it provides:**

All output is a DRAFT. The contract:
1. Return the complete draft (suggested title, suggested labels, body) to the orchestrator, which saves it to `.oss-drafts/report-<owner>-<repo>-<item>-<UTC>.md` using the Write tool.
2. The orchestrator presents the draft in chat and adds the mandatory notice: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."
3. Never call any tool that posts, comments, pushes, or creates a GitHub resource.

Three-step Pre-flight (always before drafting):

| Step | Description |
|---|---|
| **Duplicate search** | `oss-researcher` searches open + closed issues with symptom keywords; surfaces top 3–5 candidates with links and similarity assessment; recommends commenting on strong duplicates instead of filing new |
| **Template fetch** | `oss-researcher` fetches `.github/ISSUE_TEMPLATE/` directory + each template file + `config.yml`; warns on security-report redirects and Discussions redirects |
| **Convention extraction** | Identifies title format (component prefixes), label conventions (bug/enhancement), prompts user to pick component in monorepos rather than guessing |

Two drafting procedures:

| Procedure | Issue type | Evidence checklist |
|---|---|---|
| **Procedure 2 — Bug Report** | bug | Environment/version info, minimal reproducible example, exact steps to reproduce, expected vs. actual behavior, error logs/stack traces (fenced), file:line code references, related issue/PR links |
| **Procedure 3 — Feature Request** | feature | Problem statement/motivation, proposed solution, alternatives considered, scope/impact, file:line references to current behavior, related issues/discussions |

Four template-application cases:
- **(a) Markdown template** — fills sections in order, strips HTML comments.
- **(b) YAML issue form** — maps content to form fields by `label`/`id`; flags `required: true` fields.
- **(c) Multiple templates** — picks the type-appropriate template; tells the user which was chosen.
- **(d) No template** — uses built-in structure and notes this in the draft.

Missing evidence is always marked with `TODO:` placeholders; required fields are never fabricated.

**References:** `skills/issue-drafting/SKILL.md`, `skills/smart-questions/references/smart-questions-principles.md`

---

[Back to docs index](../index.md) | Related: [Agents](agents.md) | [Commands](commands.md) | [Scenarios](scenarios.md) | [Draft Files](../concepts/draft-files.md)

---

## `pr-preparation`

**Trigger phrases:** "prepare a PR", "get my PR ready", "draft a PR description", "open a PR for", "submit a fix for", "I have a patch", "send a PR", "track this task", "start tracking", "stop tracking", "track status", "log this decision".

**What it provides:**
- A DRAFT-ONLY contract: the plugin never pushes, opens a PR, edits code, or runs tests; local git reads only (`git diff`, `git status`, `git ls-files`, `git log`, `git merge-base`, `git remote -v`); uncommitted and untracked work is included.
- Pre-flight: policy block, readiness, issue-first check, PR template fetch, duplicate open-PR search, remote/base check.
- Size and shape check: more than 400 changed lines or 10 files (unless CONTRIBUTING says otherwise), mixed concerns, lockfile noise, split advice.
- A problem-first description scaffold in an `oss:send` block: Why this approach, What changed, and Unknowns & assumptions are `TODO(you)`; "How it's tested" names tests, never commands that passed.
- Disclosure text when policy requires it, and advice (never rewrites) on AI co-author trailers when forbidden.
- Lint mode using the AP1-AP9 rules.
- Procedure 0, tracked session (`mode: track`): start / stop / status / log of a private decision ledger; ledger entries become hints in Private notes and seed Unknowns, never the send block.

**References:** `skills/pr-preparation/SKILL.md`, `skills/pr-preparation/references/decision-ledger.md`, `skills/smart-questions/references/smart-questions-principles.md`

---

## `change-debrief`

**Trigger phrases:** "help me understand what I changed", "debrief my change", "what did the agent change".

**What it provides:**
- A private, read-only debrief of a local change, saved to `.oss-drafts/prepare-pr-<owner>-<repo>-debrief-<UTC>.md` with `body_format: 2`, `sendable: false` and no send block, never formatted as PR text.
- Changes grouped by purpose with `file:line`; each traced to the issue, a commit message, or an agent transcript (opt-in only); untraceable changes flagged "unexplained, possibly out of scope".
- The agent's implicit decisions, impact (callers, API/config, compatibility, test coverage), every statement marked evidenced or inferred.
- A tracked-session decision ledger, when present, as first-hand evidence (`evidenced: ledger <id>`); skipped, over-budget, and hook-skipped entries become Unknowns.
- 2-3 explain-back questions and an Unknowns list that seeds the PR description and the `review-reply` brief.

**References:** `skills/change-debrief/SKILL.md`
