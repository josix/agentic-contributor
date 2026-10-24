# Two-Plugin System

How the research-and-engagement half (this plugin) and the execution/submission half (separate plugin) divide responsibilities, and where the hand-off boundary lies.

## The Two Halves

| Aspect | agentic-contributor (this plugin) | Execution/submission plugin (separate) |
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

**This plugin stops at:** saving the output to a `.oss-drafts/` file and showing: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."

**The execution plugin starts at:** receiving the approved draft file (reading the `status: draft` frontmatter and the body) and performing the `gh` CLI action — for example:

```bash
# Execution plugin posting the claim comment
gh issue comment 8765 --repo apache/spark --body "Hi, I'd like to take this issue…"

# Execution plugin opening a PR after a branch push
gh pr create --repo apache/spark --title "[SPARK-8765] Fix null pointer in SparkContext" --body "…"
```

The execution plugin reads the draft from the `.oss-drafts/` file (the `status: draft` frontmatter identifies it as pending), presents it for final confirmation, and marks it `status: sent` after posting. See [Draft Files](draft-files.md) for the frontmatter schema.

### Body format contract (`body_format: 2`)

From v0.4.0, draft-tier files contain private material (understanding briefs, lint findings) that must never be posted. The execution plugin must therefore:

- Check the `body_format` frontmatter. If it is `private`, refuse: nothing in the file is sendable (change debriefs). If it is absent or `1`, the whole body is sendable (legacy behaviour).
- If it is `2`, post **only** the text between `<!-- oss:send:start -->` and `<!-- oss:send:end -->`. Everything else, including the `## Private notes (not sent)` section, is never posted.
- **Refuse to send** while any `TODO(you):` remains inside a send block, or when a send block is empty.
- Show the exact send-block text for final confirmation before posting.

**Required coordinated change:** the execution/submission plugin lives outside this repository and must adopt `body_format: 2` before the v0.4.0 release is used for posting. Until it does, it would post the private notes along with the reply.

## What This Plugin Covers

All 10 `/oss` scenarios stay on the research-and-drafting side of the boundary:

- **status, find, norms, setup** — read-only reports and guided walkthroughs saved to `.oss-drafts/`; no outbound text produced.
- **clarify, claim, engage** — labeled DRAFTs saved to `.oss-drafts/` and shown for review; never posted.
- **review-reply** — a private understanding brief and a lint of the reply you write; the reply itself is yours, never generated. Saved to `.oss-drafts/`, never posted.
- **prepare-pr** — a private change debrief and a problem-first PR description scaffold you complete, from local read-only git. It never pushes or opens the PR; that belongs to the execution plugin.
- **report** — a labeled DRAFT new-issue body (bug report or feature request) saved to `.oss-drafts/` and shown for review; actually filing the issue (e.g. `gh issue create`) belongs to the execution/submission plugin or the human.

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
