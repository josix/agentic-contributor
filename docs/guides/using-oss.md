# Using /oss

The `/oss` command in depth: intent classification, all 10 scenarios, the claim→engage branch, and draft-review behavior.

## How It Works

`/oss` is the single entry point for all contribution tasks. When you run it, the command:

1. **Reads `$ARGUMENTS`** — the text after `/oss`.
2. **Classifies the scenario** — invokes `oss-scenario-routing` to map your intent to one of the 10 scenarios. If intent is unclear, it asks one clarifying question (the scenario menu).
3. **Dispatches a subagent** — uses the Task tool to launch `oss-researcher` or `oss-claim-analyst` with the target `owner/repo`, the specific item (issue/PR number or query), and the scenario key.
4. **Loads the mapped skill** — applies domain-specific guidance to shape the output.
5. **Presents results** — a timestamped report, ranked list, briefing, guided walkthrough, or labeled DRAFT depending on the scenario.

## The 10 Scenarios in Detail

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

The `issue-matching` skill runs a 5-question intake, directs `oss-researcher` to fetch candidate issues and PRs, applies heuristic scoring, and returns a ranked shortlist of up to 10 items with per-item rationale. The orchestrator saves the shortlist to `.oss-drafts/find-<owner>-<repo>-find-<UTC>.md` and shows: "Saved to `<path>`. Review and edit this report file as needed before using it." Contributors with no merged PRs in the project are steered toward repro, triage, and review work first, and a private readiness summary shows how maintainers are likely to see your PR (say "skip readiness" to omit it). Good first issues that the project reserves for unassisted newcomers are listed in a separate unranked footer. See [Skills Reference](../reference/skills.md) for the scoring rubric.

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

Alongside, `oss-researcher` gathers a private readiness check (your open PRs vs the project's cap, vouch status; advisory, in Private notes only, "skip readiness" to omit). `oss-claim-analyst` checks three signals: assignee, linked open PRs (via "Fixes #N" / "Closes #N"), and recent intent comments (last 30 days). It returns one of two verdicts:

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

**Intent signals:** "respond to review", "reply to review comments", "maintainer left feedback on my PR", "how do I respond to this review"; to lint your own reply: "check my reply", "lint my reply"

**Example:**
```
/oss help me respond to the review on my apache/spark PR #4321
```

The plugin does not write your reply. Maintainers increasingly reject AI-generated review replies, so this scenario helps you understand the feedback and checks the reply you write. The flow is brief, write, lint:

1. **Brief.** `oss-researcher` fetches the review comments (with the diff hunk and timestamp) and the PR's commits. The `smart-questions` skill (Scenario C) writes a private understanding brief per comment: the quoted comment, the code at that line, the likely concern, project conventions, which commits since the comment touch that file, and two or three questions to ask yourself. Each send block contains only `TODO(you): reply in your own words`. The orchestrator saves it to `.oss-drafts/review-reply-<owner>-<repo>-pr<N>-<UTC>.md` and shows the mandatory draft notice.
2. **Write.** Open the file and write your reply in your own words inside the `oss:send` block. If you wrote rough notes or text in another language, you can ask the plugin to translate or tidy that text; it adds no new claims.
3. **Lint.** Run `/oss check my reply in .oss-drafts/review-reply-<…>.md`. The plugin reads your send blocks and adds a Lint section to the private notes: findings (AP1-AP9) with the quoted span and a question, and a pass/fail summary. It never edits your text. Fix what you agree with and re-run.

Only the `oss:send` block is ever posted; the brief and lint findings stay in the private notes.

---

### Scenario 9 — report

**Intent signals:** "report a bug", "file an issue", "draft a bug report", "draft a feature request", "propose a feature", "write up a new issue"

**Example:**
```
/oss draft a bug report for apache/airflow about scheduler crashing on database reconnect
```

`oss-researcher` searches open and closed issues for duplicates, fetches `.github/ISSUE_TEMPLATE/` files (including `config.yml`), and surfaces contribution norms. The `issue-drafting` skill runs its three-step Pre-flight — duplicate search, template fetch, and convention extraction — then drafts a complete issue body using Procedure 2 (bug) or Procedure 3 (feature):

- Missing required evidence (environment info, reproduction steps, stack traces) is marked with `TODO:` placeholders; nothing is fabricated.
- If a strong duplicate is found, the skill recommends commenting on the existing issue instead of filing a new one.
- If `config.yml` redirects the issue type elsewhere (Discussions, SECURITY.md), the skill warns you and links to the right destination.
- The draft includes a suggested title (following the repo's title convention), suggested labels, and a complete body ready to paste.

The orchestrator saves the draft to `.oss-drafts/report-<owner>-<repo>-issue-bug-<UTC>.md` (bug) or `.oss-drafts/report-<owner>-<repo>-issue-feature-<UTC>.md` (feature request) and shows the mandatory draft notice.

---

### Scenario 10 — prepare-pr

**Intent signals:** "prepare a PR", "get my PR ready", "draft a PR description", "open a PR for #N", "I have a patch"; debrief mode: "help me understand what I changed", "debrief my change", "what did the agent change"; track mode: "track …", "start tracking", "stop tracking", "track status", "log this decision"

**Example:**
```
/oss prepare a PR for apache/datafusion fixing #1234
/oss help me understand what I changed in apache/datafusion
/oss track https://github.com/apache/datafusion/issues/1234 scope: datafusion/sql/**
/oss track status
/oss track stop
```

`prepare-pr` helps you understand and own a local change and send the kind of PR maintainers prioritise. The plugin only reads your local git state (`git diff`, `git log`, `git merge-base`, `git remote -v`); it never pushes, opens a PR, edits your code, or runs your tests.

- **Tracked session (`mode: track`)** — while an agent codes, `/oss track` keeps a private decision ledger and an advisory hook asks you to choose at a few reviewer-relevant moments (test weakening, dependencies, opt-in API paths, out-of-scope edits), within a budget of 3 questions; scope-drift alerts (2 at most) and one skippable explain-back question at natural breakpoints (4 at most, 20 minutes apart) are separate pools, and `budget: 0` silences all of them. See [Tracked Sessions & Checkpoints](../concepts/tracked-sessions.md).
- **Change debrief (`mode: debrief`)** — the `change-debrief` skill groups your changes by purpose with `file:line`, traces each to the issue, a commit message, or an agent transcript (only if you point to one), flags anything untraceable as "unexplained, possibly out of scope", lists the agent's implicit decisions, covers impact and test coverage, marks every statement evidenced or inferred, and ends with 2-3 explain-back questions and an Unknowns list. When a tracked-session ledger exists for the branch, its entries are cited as first-hand evidence (`evidenced: ledger`) and skipped or over-budget decisions become Unknowns. It is saved to a private `.oss-drafts/prepare-pr-<owner>-<repo>-debrief-<UTC>.md` and is never paste-ready PR text.
- **Size and shape check** — flags more than 400 changed lines or 10 files (unless CONTRIBUTING says otherwise), mixed concerns, and lockfile noise, and suggests a split.
- **Problem-first scaffold** — inside an `oss:send` block: the problem (linked issue), then Why this approach, What changed, and Unknowns & assumptions as `TODO(you)`. "How it's tested" names tests, never commands that passed. When policy requires AI disclosure you get the unticked checkbox plus neutral options; AI co-author trailers are flagged when forbidden (advice only).
- **Lint** — re-invoke after filling it in to lint your text with the AP1-AP9 rules.

The orchestrator saves the draft to `.oss-drafts/prepare-pr-<owner>-<repo>-issue<N>-<UTC>.md` (or `pr-new` when there is no issue) and shows the mandatory draft notice. Readiness and policy findings are advisory and never block the draft.

---

## The Claim→Engage Branch

When the **claim** scenario dispatches `oss-claim-analyst` and the verdict is **"appears already claimed"**, `/oss` switches to the **engage** scenario automatically:

1. Notifies you of the switch and explains which signal triggered the "claimed" verdict.
2. Dispatches `oss-researcher` to fetch the linked PR's diff, CI status, and discussion thread.
3. Loads `smart-questions` (Scenario B) to draft constructive engagement feedback instead.

This prevents a redundant claim comment on an issue already being worked on and redirects your energy where it is most useful.

## The Issue-First Branch

If you say you want to open a PR (for example "submit a fix for X in apache/datafusion") without naming an issue, `/oss` first checks the project's policy (cached for 7 days). When the project requires an issue first, it switches to the **report** scenario, tells you why and quotes the policy source, and drafts an issue instead. The draft's frontmatter records `routed_from`. Nothing is filed; you can still say you want to continue with the PR, which goes to **prepare-pr**. When an issue is only recommended, or the policy cannot be determined, or you name an issue, the request goes to **prepare-pr** (with a warning in private notes when recommended). To force a fresh policy lookup, say "refresh policy for owner/repo".

## Draft-Review Behavior

All 10 scenarios save their output to `.oss-drafts/` in your current working directory as an editable markdown file. The `.oss-drafts/` directory is automatically excluded from version control via `.git/info/exclude` when `/oss` first writes a file in a git repo.

### Report tier (scenarios 1–4)

Scenarios **status, find, norms, setup** produce read-only reports or guided walkthroughs. After saving, the following notice is shown:

> Saved to `<path>`. Review and edit this report file as needed before using it.

These scenarios never produce outbound text and never trigger any write action toward GitHub.

### Draft tier (scenarios 5–10)

Scenarios **clarify, claim, engage, review-reply, report, prepare-pr** produce outbound text. For each:

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
