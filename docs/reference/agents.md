# Agents Reference

The two read-only subagents in the `agentic-contributor` plugin.

## Overview

| Agent | Model | Color | Purpose |
|---|---|---|---|
| `oss-researcher` | inherit | cyan | Fetches and analyses GitHub data for all scenarios that need live project information |
| `oss-claim-analyst` | inherit | yellow | Checks whether a GitHub issue is free to claim; emits a free/claimed verdict |

Both agents are read-only. The `PreToolUse` guardrail hook enforces this at the tool level even if a subagent attempted a mutation.

---

## `oss-researcher`

### Purpose

General-purpose GitHub research agent. Fetches issues, pull requests, releases, contribution documents, and repository metadata. Supplies structured, timestamped findings with direct GitHub links to the orchestrating `/oss` command.

### Supported Scenarios

Used in scenarios: **status, find, norms, setup** (optional), **clarify, engage, review-reply**, and as a follow-up dispatch in the **claim→engage** branch.

### Tools

No explicit `tools` field is declared in the agent frontmatter — all tools are available. The `PreToolUse` guardrail hook restricts which tools can actually execute.

| Tool class | Usage |
|---|---|
| `mcp__plugin_agentic-contributor_github__*` read tools | Preferred when `GITHUB_MCP_TOKEN` is set |
| `Bash` (gh CLI) | Fallback when MCP token is absent |
| `Read`, `Grep`, `Glob` | Locally cloned repo files |
| `WebFetch` | Supplementary docs pages |

### MCP vs `gh` CLI

Prefer MCP tools when `GITHUB_MCP_TOKEN` is set:

| Data | MCP tool | `gh` CLI fallback |
|---|---|---|
| Issues | `list_issues` / `search_issues` | `gh issue list --json …` |
| PRs | `get_pull_request` / `list_pull_requests` | `gh pr view --json …` / `gh pr list --json …` |
| Contribution files | `get_file_contents` | `gh api repos/<owner/repo>/contents/<path>` |
| Releases | `list_releases` | `gh release list` |
| Repository metadata | `search_repositories` | `gh api repos/<owner/repo>` |

Before using the `gh` CLI fallback, the agent runs `gh auth status` to confirm authentication.

### Pagination

Fetches in batches of 10–20 items. Never fetches all items in a single call for large repositories. On a 429 or secondary rate-limit error, waits and retries once, then reports the limitation.

### Output Format

Structured markdown with:
- A per-section header (Releases / Issues / PRs / Contribution Docs / etc.)
- Each item: type badge, title, number, direct link, timestamp
- A brief summary paragraph noting data freshness and any gaps

### Hard Constraints

- Never takes any outbound or mutating action (comment, push, fork, create, edit, assign, merge).
- Never fabricates data — if a document or field is absent, says so explicitly.
- Never claims an issue or posts on the user's behalf.

---

## `oss-claim-analyst`

### Purpose

Specialized claim-detection agent. Determines whether a GitHub issue is free to claim by inspecting three signals: assignee status, linked open PRs, and recent intent comments. Returns one of two verdicts and never takes any mutating action.

### Supported Scenarios

Used exclusively for the **claim** scenario (dispatched before `smart-questions`). If the verdict is "appears already claimed", the `/oss` command switches to the **engage** scenario.

### Tools

Declared in frontmatter: `["Bash", "Read", "Grep", "Glob"]`

| Tool | Usage |
|---|---|
| `Bash` (gh CLI) | `gh issue view`, `gh pr list --search "Fixes #N"` |
| `Read`, `Grep`, `Glob` | Locally cloned repo files if available |

No MCP tools are declared for this agent; it uses `gh` CLI exclusively.

### Verdict Format

Returns one of:

- **"Appears free to take"** — no assignee, no linked open PRs, no recent intent comments.
- **"Appears already claimed"** — one or more signals triggered. States which signal.

Additionally flags **stale claims**: a comment older than 30 days with no follow-up PR and the issue remaining open and unassigned is noted as potentially re-claimable.

### Evidence Table

Always included in the output:

| Signal | Found? | Detail |
|---|---|---|
| Assignee | Yes/No | GitHub username or "none" |
| Linked open PRs | Yes/No | PR #N (URL) or "none" |
| Recent intent comment | Yes/No | Author, date, excerpt or "none" |
| Issue state | — | open / closed |
| Accepting contributions | — | yes / no / unknown |

### Hard Constraints

- Never recommends claiming an issue that is assigned, has an active linked PR, or is closed.
- Never posts, comments, assigns, or takes any mutating action.
- States clearly when evidence is ambiguous — does not over-claim certainty.
- If already claimed or has a linked PR, notes that the orchestrator should switch to the **engage** scenario.

---

[Back to docs index](../index.md) | Related: [Commands](commands.md) | [Skills](skills.md) | [GitHub Access](../guides/github-access.md)
