# Two-Plugin System

How the research-and-engagement half (this plugin) and the execution/submission half (separate plugin) divide responsibilities, and where the hand-off boundary lies.

## The Two Halves

| Aspect | oss-contribution (this plugin) | Execution/submission plugin (separate) |
|---|---|---|
| Purpose | Research projects, surface issues, draft outbound text | Post comments, create PRs, push branches |
| GitHub access | Read-only (MCP server or `gh` CLI read commands) | Read + write (`gh` CLI mutating commands) |
| Output | Reports, ranked lists, briefings, labeled DRAFTs | Actual GitHub actions |
| Guardrail | `PreToolUse` hook denies all mutations | User confirmation required before each action |
| When it acts | Immediately on `/oss` invocation | Only after user reviews and approves a draft |

## Why Two Plugins?

Separating research from execution provides two safety properties:

1. **You can explore freely.** Running `/oss find ...` or `/oss claim ...` will never accidentally post, push, or mutate anything. There is no "are you sure?" friction during research because the plugin is incapable of sending.

2. **Sending requires a deliberate switch.** Moving to the execution plugin is an explicit step. It cannot happen as a side effect of a research command.

A single plugin that does both would require per-action confirmation dialogs throughout the research flow, or trust that every code path correctly avoids write actions — a much weaker guarantee than the technical separation.

## The Hand-off Boundary

The boundary is the moment the user decides a draft is ready to send.

**This plugin stops at:** presenting a labeled DRAFT with the notice "This plugin will NOT post, comment, push, or send anything."

**The execution plugin starts at:** receiving the approved draft text and performing the `gh` CLI action — for example:

```bash
# Execution plugin posting the claim comment
gh issue comment 8765 --repo apache/spark --body "Hi, I'd like to take this issue…"

# Execution plugin opening a PR after a branch push
gh pr create --repo apache/spark --title "[SPARK-8765] Fix null pointer in SparkContext" --body "…"
```

The user copies (or the execution plugin reads) the draft text from this plugin's output and provides it to the execution plugin as the body of the action.

## What This Plugin Covers

All 8 `/oss` scenarios stay on the research-and-drafting side of the boundary:

- **status, find, norms, setup** — read-only reports and guided walkthroughs; no draft produced.
- **clarify, claim, engage, review-reply** — labeled DRAFTs ready for review; never posted.

## What This Plugin Does Not Cover

- Writing code or tests.
- Committing changes.
- Pushing branches.
- Opening, editing, or closing pull requests or issues.
- Posting comments.
- Any action that mutates GitHub state.

These belong to the execution/submission plugin or to your own local git workflow.

---

[Back to docs index](../index.md) | Related: [Draft-Only Guardrail](draft-only-guardrail.md) | [Using /oss](../guides/using-oss.md)
