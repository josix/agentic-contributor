---
name: oss-scenario-routing
description: >
  This skill should be used when the orchestrator needs to classify a user's open-source
  contribution intent into one of the eight supported scenarios. Trigger phrases include:
  "find an issue to contribute", "check project status", "draft a question to maintainers",
  "understand contribution norms", "set up the project locally", "claim an issue",
  "give feedback on a PR", "respond to PR review", and close variants of each.
---

# OSS Scenario Routing

Classify the user's intent from `$ARGUMENTS` (or from the clarifying answer) into exactly one of
the eight scenarios below, then route to the correct skill and subagent.

## Scenario Catalog

| # | Scenario key | Intent signals | Skill to load | Agent to dispatch | Output type |
|---|---|---|---|---|---|
| 1 | **status** | "what's new", "latest releases", "recent issues/PRs", "project news", "what's happening in X" | — | `oss-researcher` | Timestamped status report |
| 2 | **find** | "find an issue", "match me to a task", "good first issue", "what can I work on", "suggest a PR to help with" | `issue-matching` | `oss-researcher` | Ranked shortlist with rationale |
| 3 | **norms** | "contribution norms", "how do I contribute", "CLA", "DCO", "CONTRIBUTING", "governance", "how decisions are made" | `contribution-norms` | `oss-researcher` | Contribution briefing |
| 4 | **setup** | "set up locally", "clone and build", "dev environment", "run the tests", "how do I build X" | `dev-env-setup` | `oss-researcher` (optional, read-only — to fetch CONTRIBUTING/setup docs) | Step-by-step guided setup |
| 5 | **clarify** | "draft a question", "ask the maintainer", "clarify the issue", "what does this issue mean", "I don't understand the design" | `smart-questions` | `oss-researcher` | DRAFT questions (review-before-send) |
| 6 | **claim** | "claim an issue", "can I take this", "is this issue free", "I want to work on #N" | `smart-questions` | `oss-claim-analyst` | Claim assessment + DRAFT claim comment |
| 7 | **engage** | "give feedback on a PR", "help with someone's PR", "comment on PR", "review an in-progress PR", "there's a linked PR" | `smart-questions` | `oss-researcher` | DRAFT feedback comment |
| 8 | **review-reply** | "respond to review", "reply to review comments", "maintainer left feedback on my PR", "how do I respond to this review" | `smart-questions` | `oss-researcher` | DRAFT review replies |

## Classification Rules

To classify the user's intent:

1. Match the `$ARGUMENTS` text against the intent signals column (exact phrases, close synonyms,
   or paraphrases). The first strong match wins.
2. If no strong match is found, ask **one** clarifying question: present the scenario menu
   (numbered list of the 8 scenarios) and ask the user which applies.
3. Never ask more than one clarifying question. After the answer, classify and proceed.

### Claim → Engage Branch

After dispatching `oss-claim-analyst` for the **claim** scenario:

- If the analyst's verdict is **"appears free to take"**: proceed with the `smart-questions` skill
  to draft a polite claim comment.
- If the analyst's verdict is **"appears already claimed"** (assignee, active PR, or recent intent
  comment): automatically switch to the **engage** scenario — load `smart-questions` and dispatch
  `oss-researcher` to gather the linked PR context and draft constructive feedback instead.

## Routing Steps

Once the scenario is classified, the `/oss` command must:

1. **Load the mapped skill** (by naming it) to apply domain-specific guidance.
2. **Dispatch the mapped subagent** via the Task tool with:
   - The target project (`owner/repo`).
   - The specific item (issue number, PR number, or query intent).
   - The scenario key so the subagent knows its focus.
3. **Produce the scenario's output** as specified in the output-type column.

## DRAFT-ONLY Rule

Scenarios 5, 6, 7, and 8 all produce outbound text. For every one of these scenarios:

- Always present the drafted content (questions, claim comment, feedback, review replies) for the
  user's explicit review before anything is sent.
- Add a clearly visible notice: **"Review this draft before sending. This plugin will NOT post it —
  sending is handled by the separate execution/submission plugin."**
- NEVER call any mutating tool, MCP write method, `gh` posting command, or `git push`. The
  PreToolUse guardrail hook will block such attempts regardless.

Scenarios 1, 2, 3, and 4 are read or guidance outputs only — no draft disclaimer is needed, but
they must equally never trigger any write action.
