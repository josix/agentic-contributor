# Commands Reference

## `/oss`

The single entry point for all OSS contribution tasks in this plugin.

### Frontmatter

| Field | Value |
|---|---|
| `description` | `Orchestrate an OSS-contribution task — find issues, research status, draft questions/feedback, learn norms, set up env (draft-only)` |
| `argument-hint` | `[what you want to do, e.g. "find a good first issue in apache/airflow"]` |
| `allowed-tools` | `Bash`, `Read`, `Grep`, `Glob`, `WebFetch`, `Task`, `mcp__plugin_oss-contribution_github__*` |

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

Prefer `mcp__plugin_oss-contribution_github__*` read tools inside subagents. Fall back to `gh` CLI if `GITHUB_MCP_TOKEN` is not set.

#### Step 4 — Load Skill and Produce Output

| Scenario | Skill loaded | Output |
|---|---|---|
| status | none | Timestamped report from `oss-researcher` |
| find | `issue-matching` | Ranked shortlist |
| norms | `contribution-norms` | Contribution briefing |
| setup | `dev-env-setup` | Step-by-step guided walkthrough |
| clarify, engage, review-reply, claim | `smart-questions` | DRAFT |

**Claim→Engage branch:** If `oss-claim-analyst` returns "appears already claimed", switch to `engage` — load `smart-questions` (Scenario B), dispatch `oss-researcher` for linked PR context, and notify the user of the switch.

#### Step 5 — Draft Notice (scenarios 5–8)

For any scenario that produces outbound text:

1. Present the complete draft, clearly labelled.
2. Append the mandatory review notice:

   > **DRAFT — Review before sending.**
   > This plugin will NOT post, comment, push, or send anything. Sending is handled by the
   > separate execution/submission plugin. Edit or cancel this draft as needed.

3. Never call any tool that posts, comments, creates, pushes, or mutates GitHub state. The `PreToolUse` guardrail hook blocks such calls, but the command must not attempt them regardless.

### Guardrail Reminder

The `guard-outbound.sh` `PreToolUse` hook is always active. It denies: `git push`, `gh pr/issue/release/repo` mutating subcommands, `gh gist create`, `gh api` write calls, `curl`/`wget` mutation flags, and all MCP write-verb tools.

Allowed: `gh pr view`, `gh issue list`, `gh release list`, plain GET `gh api` calls, `git clone`, `git status`, `git log`, and all `mcp__plugin_oss-contribution_github__` read tools.

---

[Back to docs index](../index.md) | Related: [Agents](agents.md) | [Skills](skills.md) | [Hooks](hooks.md) | [Scenarios](scenarios.md)
