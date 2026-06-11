# Commands Reference

## `/oss`

The single entry point for all OSS contribution tasks in this plugin.

### Frontmatter

| Field | Value |
|---|---|
| `description` | `Orchestrate an OSS-contribution task — find issues, research status, draft questions/feedback, learn norms, set up env (draft-only)` |
| `argument-hint` | `[what you want to do, e.g. "find a good first issue in apache/airflow"]` |
| `allowed-tools` | `Bash`, `Read`, `Write`, `Grep`, `Glob`, `WebFetch`, `Task`, `mcp__plugin_agentic-contributor_github__*` |

### Arguments

`$ARGUMENTS` is the free-text intent string passed after `/oss`. Examples:

```
find a good first issue in apache/airflow
what's the latest status of apache/spark?
how do I contribute to apache/airflow — CLA and PR conventions?
help me set up apache/airflow locally
draft a question about issue #12345 in apache/airflow
is issue #8765 in apache/spark free to claim?
help me give feedback on apache/airflow PR #9876
help me respond to the review on my apache/spark PR #4321
```

If `$ARGUMENTS` is empty or unclear, `/oss` presents the 8-scenario menu and asks one clarifying question.

### Behavior Steps

#### Step 1 — Read Intent

Read `$ARGUMENTS`. If empty or ambiguous, present the scenario menu and ask which applies.

#### Step 2 — Classify the Scenario

Invoke `oss-scenario-routing`. Match `$ARGUMENTS` against the 8 scenario intent signals. If no strong match, ask one clarifying question (the scenario menu). After classification, proceed immediately.

#### Step 3 — Dispatch Subagent

For scenarios requiring live GitHub data, dispatch via the Task tool:

| Scenario | Subagent |
|---|---|
| status, find, norms, clarify, engage, review-reply | `oss-researcher` |
| claim | `oss-claim-analyst` first; then `oss-researcher` if branch switches to engage |
| setup | `oss-researcher` (optional — only if CONTRIBUTING/setup docs not already available) |

Pass: `owner/repo`, specific item (issue/PR number or query intent), and the scenario key.

Prefer `mcp__plugin_agentic-contributor_github__*` read tools inside subagents. Fall back to `gh` CLI if `GITHUB_MCP_TOKEN` is not set.

#### Step 4 — Load Skill, Produce Output, and Save Draft File

| Scenario | Skill loaded | Output | Draft file |
|---|---|---|---|
| status | none | Timestamped report from `oss-researcher` | `.oss-drafts/status-…` |
| find | `issue-matching` | Ranked shortlist | `.oss-drafts/find-…` |
| norms | `contribution-norms` | Contribution briefing | `.oss-drafts/norms-…` |
| setup | `dev-env-setup` | Step-by-step guided walkthrough | `.oss-drafts/setup-…` |
| clarify, engage, review-reply, claim | `smart-questions` | DRAFT | `.oss-drafts/<scenario>-…` |

Before writing any file, ensure `.git/info/exclude` (or equivalent) excludes `.oss-drafts/` as
described in the Draft File Convention section of `commands/oss.md`. Use the Write tool to create
the file.

**Claim→Engage branch:** If `oss-claim-analyst` returns "appears already claimed", switch to `engage` — load `smart-questions` (Scenario B), dispatch `oss-researcher` for linked PR context, and notify the user of the switch.

#### Step 5 — Two-Tier Export and Review Protocol

**Report tier (scenarios 1–4):** After saving the file, show:

> Saved to `<path>`. Review and edit this report file as needed before using it.

Then briefly summarise key findings and ask the user if they want to take a next step.

**Draft tier (scenarios 5–8):** After saving the file, present the complete draft in chat
(clearly labelled), then add the mandatory notice verbatim:

> **DRAFT — saved to `<path>`. Review and edit this file before sending.**
> This plugin will NOT post, comment, push, or send anything. Sending is handled by the
> separate execution/submission plugin.

Then ask the user to review and modify the file.

Never call any tool that posts, comments, creates, pushes, or mutates GitHub state. The `PreToolUse` guardrail hook blocks such calls, but the command must not attempt them regardless. Writing local files with the Write tool does NOT violate draft-only — local file writes cannot reach GitHub. See [Draft Files](../concepts/draft-files.md) for naming convention and frontmatter.

### Guardrail Reminder

The `guard-outbound.sh` `PreToolUse` hook is always active. It denies: `git push`, `gh pr/issue/release/repo` mutating subcommands, `gh gist create`, `gh api` write calls, `curl`/`wget` mutation flags, and all MCP write-verb tools.

Allowed: `gh pr view`, `gh issue list`, `gh release list`, plain GET `gh api` calls, `git clone`, `git status`, `git log`, and all `mcp__plugin_agentic-contributor_github__` read tools.

---

[Back to docs index](../index.md) | Related: [Agents](agents.md) | [Skills](skills.md) | [Hooks](hooks.md) | [Scenarios](scenarios.md)
