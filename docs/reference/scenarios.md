# Scenarios Reference

Canonical 10-scenario table with full detail: intent signals, skill, agent, data source, output type, and guardrail relevance.

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
| 8 | **review-reply** | "respond to review", "reply to review comments", "maintainer left feedback on my PR", "how do I respond to this review" | `smart-questions` (Scenario C) | `oss-researcher` | PR review comments | Understanding brief + lint of your reply (you write the reply) | `.oss-drafts/review-reply-…` |
| 9 | **report** | "report a bug", "file an issue", "draft a bug report", "draft a feature request", "propose a feature", "write up a new issue" | `issue-drafting` | `oss-researcher` | ISSUE_TEMPLATE files + issue search results | DRAFT new issue (bug/feature) | `.oss-drafts/report-…` |
| 10 | **prepare-pr** | "prepare a PR", "get my PR ready", "draft a PR description", "open a PR for", "I have a patch"; debrief: "help me understand what I changed", "debrief my change", "what did the agent change"; track: "track …", "start tracking", "stop tracking", "track status", "log this decision" | `pr-preparation` (+ `change-debrief`) | `oss-researcher` + local read-only git | PR template, duplicate PRs, issue body, local diff | Size check + problem-first PR scaffold (`TODO(you)` sections), private debrief, or private track ledger (`mode: track`) | `.oss-drafts/prepare-pr-…`, `.oss-drafts/track-…` |

All outputs are saved as editable markdown files in `.oss-drafts/` in the user's working
directory. Report-tier scenarios (1–4) show a "Saved to `<path>`" notice. Draft-tier scenarios
(5–10) show the draft in chat plus the mandatory "**DRAFT — saved to `<path>`. Review and edit
this file before sending.**" notice. See [Draft Files](../concepts/draft-files.md) for the full
naming convention and frontmatter schema.

## Scenario Detail Notes

### Scenario 1 — status

No skill is loaded. `oss-researcher` returns findings directly as a timestamped markdown report organized by section (Releases / Issues / PRs). The report includes direct GitHub links and data freshness notes. The orchestrator saves the report to `.oss-drafts/status-<owner>-<repo>-status-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 2 — find

`issue-matching` runs a 5-question structured intake before directing `oss-researcher` to fetch candidates (including triage-labelled issues and review-requested PRs). Items are filtered (no closed, assigned, locked, or wontfix) and scored using a heuristic rubric that favours work that builds a track record (repro, triage, review) for contributors new to the project. When the project's policy bans AI on good first issues, those issues appear in an unranked "Policy-reserved" footer instead of the ranking. An advisory readiness summary (see `contributor-readiness`) is added at the top in private notes; say "skip readiness" to omit it. The shortlist includes up to 10 items; each entry has a rationale sentence linking to the contributor's stated skills and goal. The orchestrator saves the shortlist to `.oss-drafts/find-<owner>-<repo>-find-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 3 — norms

`contribution-norms` directs `oss-researcher` to fetch CONTRIBUTING, CODE_OF_CONDUCT, PR/issue templates, and DCO files. For Apache Software Foundation projects, `references/apache-governance.md` provides additional context on ICLA, JIRA workflows, and lazy-consensus voting. It also detects the project's AI-use policy and contribution limits (AI policy files, CONTRIBUTING AI sections, PR-template disclosure, open-PR caps, vouch lists, co-author trailer rules, good-first-issue AI rules, issue-first rules) in "AI Use Policy" and "Contribution Limits & Trust Gates" sections, each citing its source. Documents or signals that cannot be found are explicitly noted ("not found", never "no policy") — nothing is fabricated. The orchestrator saves the briefing to `.oss-drafts/norms-<owner>-<repo>-norms-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 4 — setup

`dev-env-setup` presents setup steps in the order documented in the official source. Heavy or platform-specific setups are flagged before the user starts (Airflow Breeze, Spark JDK+Maven). An "environment ready" checkpoint command is given. Any step that would make a destructive system change requires explicit yes/no confirmation. Scope ends at a verified, ready dev environment. The orchestrator saves the walkthrough to `.oss-drafts/setup-<owner>-<repo>-setup-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it."

### Scenario 5 — clarify

`smart-questions` (Scenario A): before drafting, the skill summarizes what is already known from the issue thread and linked docs so the draft does not re-ask answered questions. Each drafted question cites the specific part of the issue/PR that prompted it. The orchestrator saves the draft to `.oss-drafts/clarify-<owner>-<repo>-issue<N>-<UTC>.md`, presents it in chat, and shows: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."

### Scenario 6 — claim

`oss-researcher` (key `readiness`) runs in parallel and adds a private, advisory readiness block (open PRs vs the project's cap, vouch status, merged PRs, tier) to Private notes; being at the cap or unvouched adds a warning but never blocks the draft, and "skip readiness" omits it. `oss-claim-analyst` checks: (1) assignee field, (2) linked open PRs via "Fixes #N" / "Closes #N" in PR bodies, (3) intent comments in the last 30 days. Stale claims (comment older than 30 days, no follow-up PR, issue still open and unassigned) are flagged separately. If the verdict is "appears already claimed", the `/oss` command notifies the user and switches automatically to scenario 7 (engage). The orchestrator saves the verdict and draft claim comment (or engage draft) to `.oss-drafts/claim-<owner>-<repo>-issue<N>-<UTC>.md` and shows the mandatory draft-tier notice.

### Scenario 7 — engage

`smart-questions` (Scenario B): the skill identifies the most useful contribution based on PR state — reproducing a CI failure, reviewing specific changed files, offering a rebase for a stalled PR, noting rebase conflicts. Feedback is scoped to the actual diff and discussion; large diffs are handled by scoping to the most relevant files. The orchestrator saves the draft to `.oss-drafts/engage-<owner>-<repo>-pr<N>-<UTC>.md` and shows the mandatory draft-tier notice.

### Scenario 8 — review-reply

`smart-questions` (Scenario C) never writes the reply for you. In **brief mode** (default) it produces a private per-comment understanding brief (the quoted comment, the code at that line, the likely concern, project conventions, a commit-to-comment mapping, and questions to ask yourself), optional bullet-only talking points, and a `TODO(you): reply in your own words` placeholder inside each `oss:send` block. It will translate or tidy text you wrote yourself on request, adding no new claims. In **lint mode** ("check my reply", "lint my reply") it reads your send blocks and reports anti-pattern findings (AP1-AP9) as quoted spans with questions, without rewriting your text. The commit recap "change-summary comment" is no longer produced. See [Maintainer-Friendly Contributing](../concepts/maintainer-friendly-contributing.md). The orchestrator saves the draft to `.oss-drafts/review-reply-<owner>-<repo>-pr<N>-<UTC>.md` and shows the mandatory draft-tier notice.

### Scenario 9 — report

`issue-drafting` runs a three-step Pre-flight before any drafting:

1. **Duplicate search** — `oss-researcher` searches open and closed issues with the user's symptom keywords and surfaces the top 3–5 candidates with links and a similarity assessment. If a strong duplicate exists (open or recently closed), the skill recommends commenting on it instead of filing a new issue. Only proceeds to drafting when the user confirms no duplicate covers the case.
2. **Template fetch** — `oss-researcher` fetches `.github/ISSUE_TEMPLATE/` directory listing, each discovered template file (`.md`, `.yml`, `.yaml`), and `config.yml`. If `config.yml` redirects the issue type (e.g., questions → Discussions, security reports → SECURITY.md), the skill warns the user and links to the appropriate destination.
3. **Convention extraction** — title format (e.g., `[COMPONENT]` prefix), label conventions (bug/enhancement, component labels). For monorepos, the skill prompts the user to pick a component rather than guessing.

After Pre-flight, the skill applies one of four template-application cases:
- **(a) Markdown template (`.md`)** — fills the template's sections in order, stripping HTML comments.
- **(b) YAML issue form (`.yml`/`.yaml` with `body:`)** — maps drafted content to form fields by `label`/`id`; flags `required: true` fields that are missing.
- **(c) Multiple templates** — picks the type-appropriate template (bug vs. feature) and tells the user which was chosen.
- **(d) No template** — uses built-in structure and notes "No issue template found in this repo; used a standard structure."

Missing required evidence is always marked with `TODO:` placeholders — version info, reproduction steps, stack traces are never fabricated.

The draft includes a suggested title (following the repo's convention), suggested labels, and a complete body ready to paste. The orchestrator saves the draft to `.oss-drafts/report-<owner>-<repo>-issue-bug-<UTC>.md` (bug reports) or `.oss-drafts/report-<owner>-<repo>-issue-feature-<UTC>.md` (feature requests) and shows the mandatory draft-tier notice.

### Scenario 10 — prepare-pr

`pr-preparation` (with `change-debrief` as its entry mode) helps you understand and own a local change and send a PR maintainers prioritise. Local git reads only (`git diff`, `git status`, `git ls-files`, `git log`, `git merge-base`, `git remote -v`), and uncommitted and untracked work counts as part of the change; the plugin never pushes, opens a PR, edits code, or runs tests.

- **Track (`mode: track`)**: `start` / `stop` / `status` / `log` a session; a private decision ledger plus an advisory hook that turns dependency, test-weakening, opt-in API, and out-of-scope edits into budgeted "choose" questions. No policy preflight, no PR text. See [Tracked Sessions & Checkpoints](../concepts/tracked-sessions.md).
- **Debrief (`mode: debrief`)**: changes grouped by purpose with `file:line`, each traced to an issue, commit, or an opt-in agent transcript; untraceable changes flagged "unexplained, possibly out of scope"; implicit agent decisions; impact and test coverage; evidenced vs inferred (a tracked-session ledger counts as `evidenced: ledger`); 2-3 explain-back questions; an Unknowns list that includes skipped and over-budget ledger decisions. Saved as a private `.oss-drafts/prepare-pr-<owner>-<repo>-debrief-<UTC>.md`, never PR text.
- **Draft (`mode: draft`)**: size and shape verdict (default 400 lines / 10 files unless CONTRIBUTING says otherwise), then a problem-first scaffold in an `oss:send` block. Why this approach, What changed, and Unknowns & assumptions are `TODO(you)`; "How it's tested" names tests, never passed commands. Disclosure text when policy requires it; AI co-author trailers flagged when forbidden (advice only).
- **Lint (`mode: lint`)**: AP1-AP9 on your filled-in text.

File: `.oss-drafts/prepare-pr-<owner>-<repo>-<item>-<UTC>.md`, `item` is `issueN` or `pr-new`. Track ledger: `.oss-drafts/track-<owner>-<repo>-<item>-<UTC>.md` (`item` is `issueN` or `task`) plus the pointer `<gitdir>/agentic-contributor/track-active` (git dir, not the worktree). Frontmatter adds `base`, `head`, `diff_stats`, `mode`, `policy`, `readiness`.

## Policy Preflight

Before `find`, `clarify`, `claim`, `engage`, `review-reply`, `report`, and `prepare-pr`, `/oss` resolves a `policy` block (AI policy, disclosure, co-author trailer rule, open-PR cap, vouch, issue-first). It reuses the block from the newest `.oss-drafts/` draft for the same repo whose `policy.fetched_at` is under 7 days old; otherwise `oss-researcher` (key `policy-preflight`) does a fixed 6-10 GET lookup. The block is written into every draft's frontmatter. Findings are advisory and never block a draft.

## The Issue-First Branch

When you express PR intent ("open a PR for...", "submit a fix for...") with no issue reference and the project's policy says an issue is required first, `/oss` switches to **report**, quotes the policy source, and sets `routed_from: prepare-pr` in the draft frontmatter. If you name an issue, or the policy is only recommended, unknown, or not found, the request goes to **prepare-pr** (with a leading warning in private notes when an issue is recommended). It never blocks you, and adds no extra clarifying question.

```
/oss I want to submit a fix for <symptom> in apache/datafusion
  → policy preflight: issue_first
  → /oss notifies user, quotes the source
  → load issue-drafting → report DRAFT (routed_from set)
  → (issue named / not required) → prepare-pr
```

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
