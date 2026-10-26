---
name: oss-scenario-routing
description: >
  This skill should be used when the orchestrator needs to classify a user's open-source
  contribution intent into one of the ten supported scenarios. Trigger phrases include:
  "find an issue to contribute", "check project status", "draft a question to maintainers",
  "understand contribution norms", "set up the project locally", "claim an issue",
  "give feedback on a PR", "respond to PR review", "draft a bug report", "file a new issue",
  "propose a feature", "prepare a PR", "help me understand what I changed", and close variants of each.
---

# OSS Scenario Routing

Classify the user's intent from `$ARGUMENTS` (or from the clarifying answer) into exactly one of
the ten scenarios below, then route to the correct skill and subagent.

## Scenario Catalog

| # | Scenario key | Intent signals | Skill to load | Agent to dispatch | Output type |
|---|---|---|---|---|---|
| 1 | **status** | "what's new", "latest releases", "recent issues/PRs", "project news", "what's happening in X" | — | `oss-researcher` | Timestamped status report saved to `.oss-drafts/` |
| 2 | **find** | "find an issue", "match me to a task", "good first issue", "what can I work on", "suggest a PR to help with" | `issue-matching` | `oss-researcher` | Ranked shortlist with rationale saved to `.oss-drafts/` |
| 3 | **norms** | "contribution norms", "how do I contribute", "CLA", "DCO", "CONTRIBUTING", "governance", "how decisions are made" | `contribution-norms` | `oss-researcher` | Contribution briefing saved to `.oss-drafts/` |
| 4 | **setup** | "set up locally", "clone and build", "dev environment", "run the tests", "how do I build X" | `dev-env-setup` | `oss-researcher` (optional, read-only — to fetch CONTRIBUTING/setup docs) | Step-by-step guided walkthrough saved to `.oss-drafts/` |
| 5 | **clarify** | "draft a question", "ask the maintainer", "clarify the issue", "what does this issue mean", "I don't understand the design" | `smart-questions` | `oss-researcher` | DRAFT questions saved to `.oss-drafts/` (review-before-send) |
| 6 | **claim** | "claim an issue", "can I take this", "is this issue free", "I want to work on #N" | `smart-questions` | `oss-claim-analyst` | Claim assessment + DRAFT claim comment saved to `.oss-drafts/` |
| 7 | **engage** | "give feedback on a PR", "help with someone's PR", "comment on PR", "review an in-progress PR", "there's a linked PR" | `smart-questions` | `oss-researcher` | DRAFT feedback comment saved to `.oss-drafts/` |
| 8 | **review-reply** | "respond to review", "reply to review comments", "maintainer left feedback on my PR", "how do I respond to this review"; lint mode: "check my reply", "lint my reply", "review my draft reply" | `smart-questions` | `oss-researcher` (skipped in lint mode unless commit data is needed) | Per-comment understanding brief + `TODO(you)` placeholders (brief mode) or a Lint section for your own reply (lint mode), saved to `.oss-drafts/` |
| 9 | **report** | "report a bug", "file an issue", "draft a bug report", "draft a feature request", "propose a feature", "write up a new issue" | `issue-drafting` | `oss-researcher` | DRAFT new issue (bug/feature) saved to `.oss-drafts/` |
| 10 | **prepare-pr** | "prepare a PR", "get my PR ready", "draft a PR description", "open a PR for", "submit a fix for", "I have a patch", "send a PR"; debrief mode: "help me understand what I changed", "debrief my change", "what did the agent change"; lint mode: "lint my PR description", "check my PR description" | `pr-preparation` (+ `change-debrief` in debrief mode, `contributor-readiness`) | `oss-researcher` (PR template, duplicate PRs, issue body) plus local read-only git by the orchestrator | Size check + problem-first PR description scaffold with `TODO(you)` sections (draft mode), or a private change debrief with no PR text (`mode: debrief`), saved to `.oss-drafts/` |

## Classification Rules

To classify the user's intent:

1. Match the `$ARGUMENTS` text against the intent signals column (exact phrases, close synonyms,
   or paraphrases). The first strong match wins.
2. If no strong match is found, ask **one** clarifying question: present the scenario menu
   (numbered list of the 10 scenarios) and ask the user which applies.
3. Never ask more than one clarifying question. After the answer, classify and proceed.
4. **PR intent** ("open a PR for...", "submit a fix for...", "I have a patch...", "send a PR")
   with no issue number or URL triggers the policy preflight (Step 3 in `commands/oss.md`)
   **before** final routing. This is the only place routing is policy-aware; see the Issue-First
   Branch below.
5. **Debrief signals** ("help me understand what I changed", "debrief my change", "what did the
   agent change") route to scenario 10 with `mode: debrief`. This is an entry mode of `prepare-pr`,
   not an 11th scenario.
6. **Review/lint disambiguation:** the user's own reply to review comments ("my reply", "my draft
   reply", "my response to the review") routes to review-reply lint. The user's own PR text ("my PR
   description", "lint my PR", "check my PR before I open it") routes to prepare-pr lint. Someone
   else's PR ("review this PR", "help me review PR #N", no "my") routes to engage. If still
   ambiguous ("review my draft"), ask the one clarifying question with exactly these three options.

### Claim → Engage Branch

After dispatching `oss-claim-analyst` for the **claim** scenario:

- If the analyst's verdict is **"appears free to take"**: proceed with the `smart-questions` skill
  to draft a polite claim comment.
- If the analyst's verdict is **"appears already claimed"** (assignee, active PR, or recent intent
  comment): automatically switch to the **engage** scenario — load `smart-questions` and dispatch
  `oss-researcher` to gather the linked PR context and draft constructive feedback instead.

### Issue-First Branch

Mirrors the claim → engage branch. For PR intent, after the policy preflight:

- An issue number or URL is given: route to **prepare-pr**.
- No issue reference and `policy.issue_first` is `required`: switch to **report** (load
  `issue-drafting`), notify the user why and quote the policy source, and set
  `routed_from: prepare-pr` in the draft frontmatter. The user is never blocked: if they say they
  want to continue with the PR anyway, continue with **prepare-pr** (`item: pr-new`) and lead
  Private notes with the warning.
- No issue reference and `policy.issue_first` is `recommended`: route to **prepare-pr**, with a
  leading warning in Private notes suggesting an issue first.
- No issue reference and `policy.issue_first` is `unknown`: route to **prepare-pr** (`pr-new`).
- This adds no clarifying question; the 1-question limit still holds.

## Routing Steps

Once the scenario is classified, the `/oss` command must:

1. **Load the mapped skill** (by naming it) to apply domain-specific guidance.
2. **Dispatch the mapped subagent** via the Task tool with:
   - The target project (`owner/repo`).
   - The specific item (issue number, PR number, or query intent).
   - The scenario key so the subagent knows its focus.
3. **Produce the scenario's output** as specified in the output-type column.

## DRAFT-ONLY Rule

All 10 scenarios save their output to `.oss-drafts/` in the user's working directory. The
orchestrator uses the Write tool to persist the file; subagents remain read-only.

### Report tier (scenarios 1–4)

The orchestrator saves the output file and shows:

> Saved to `<path>`. Review and edit this report file as needed before using it.

These scenarios never produce outbound text and never trigger any write action toward GitHub.

### Draft tier (scenarios 5–10)

The orchestrator saves the draft file and shows the complete draft in chat, then adds:

> **DRAFT — saved to `<path>`. Review and edit this file before sending.**
> This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin.

- Always present the drafted content (questions, claim comment, feedback, review replies) for the
  user's explicit review.
- NEVER call any mutating tool, MCP write method, `gh` posting command, or `git push`. The
  PreToolUse guardrail hook will block such attempts regardless.
- Writing local `.oss-drafts/` files with the Write tool does NOT violate draft-only — local
  file writes cannot reach GitHub.
