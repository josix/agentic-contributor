# Quick Start

A first `/oss` walkthrough — from command to reviewed draft.

## Before You Begin

Complete [Installation](installation.md) and restart your Claude Code session so the guardrail hook and MCP server are active.

## Walk Through: Finding a Good First Issue

This walkthrough uses the **find** scenario to locate a beginner-friendly issue in `apache/airflow`.

### Step 1 — Run `/oss`

In Claude Code, type:

```
/oss find a good first issue in apache/airflow
```

The `/oss` command reads your intent, invokes the `oss-scenario-routing` skill, and classifies it as the **find** scenario.

### Step 2 — Answer the Intake Questions

The `issue-matching` skill asks up to 5 short questions before fetching data:

```
1. What are you hoping to achieve? (bug fix, feature, docs, learning, …)
2. What languages/frameworks are you comfortable with?
3. Is this your first contribution to apache/airflow? (yes/no)
4. Issues only, PRs only, or both?
5. Any other target projects to include?
```

Answer each question. The more specific your answers, the better the ranking.

### Step 3 — Watch the Research

The `oss-researcher` subagent fetches live data from GitHub (via MCP or `gh` CLI). You will see it paginate through open issues labelled `good first issue` and `help wanted`, filtering out locked, assigned, or closed items.

### Step 4 — Review the Ranked Shortlist

The skill returns a ranked list of up to 10 issues with rationale:

```
## #1. Issue #42345: Add docstring examples to BaseSensor.poke()
- Link: https://github.com/apache/airflow/issues/42345
- Type: Issue
- Labels: good first issue, area:docs
- Last updated: 2026-06-07
- Why it fits: Docs task; matches your stated goal of learning and Python comfort.
```

This is a **read-only report** — no draft notice is shown because no outbound text was produced.

### Step 5 — Continue with a Draft Scenario (Optional)

Once you pick an issue, you can use a draft scenario:

```
/oss is issue #42345 in apache/airflow free to claim?
```

The **claim** scenario dispatches `oss-claim-analyst`, which checks assignees, linked PRs, and recent intent comments, then returns a verdict. If the issue is free, `smart-questions` drafts a claim comment:

```
DRAFT — Review before sending.
---
Hi, I'm [your name], a Python developer interested in contributing to Airflow.
I'd like to work on issue #42345 (Add docstring examples to BaseSensor.poke()).
Is there anything specific you'd like me to keep in mind? Happy to discuss the approach first.
---
This plugin will NOT post, comment, push, or send anything. Sending is handled by the
separate execution/submission plugin. Edit or cancel this draft as needed.
```

The plugin stops here. To actually post the comment, use the execution/submission plugin.

## What the Plugin Will Never Do

- Post a comment on GitHub.
- Create or close an issue or PR.
- Push a branch.
- Send any outbound request with mutation intent.

All such attempts are blocked by the `PreToolUse` guardrail hook — see [Draft-Only Guardrail](../concepts/draft-only-guardrail.md).

---

[Back to docs index](../index.md) | [Installation](installation.md) | Next: [Using /oss](../guides/using-oss.md)
