# Draft Files

How the `/oss` command exports every scenario output to a local, editable markdown file in
`.oss-drafts/` — and why this is safe under the draft-only guardrail.

## Overview

Every `/oss` run produces a markdown file in `.oss-drafts/` inside your current working directory.
The file is written by the orchestrator using the Write tool immediately after the subagent and
skill have produced their output. You can open and edit the file in any text editor before
deciding what to do with it.

This applies to all 8 scenarios — both read-only report scenarios (1–4) and outbound-text draft
scenarios (5–8).

## Output Directory

```
<your project cwd>/
└── .oss-drafts/
    ├── find-apache-airflow-find-20260611T143000Z.md
    ├── norms-apache-airflow-norms-20260611T144500Z.md
    └── engage-apache-airflow-pr9876-20260611T150000Z.md
```

The directory is created automatically on the first write.

## File Naming Convention

```
.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md
```

| Part | Description | Example |
|------|-------------|---------|
| `scenario` | One of: `status`, `find`, `norms`, `setup`, `clarify`, `claim`, `engage`, `review-reply` | `engage` |
| `owner` | Repository owner (slashes in `owner/repo` become `-`) | `apache` |
| `repo` | Repository name | `airflow` |
| `item` | `issueN`, `prN`, `status`, `find`, `norms`, or `setup` | `pr9876` |
| `UTC` | Timestamp in `YYYYMMDDThhmmssZ` format | `20260611T143000Z` |

**Examples:**

| Scenario | File |
|----------|------|
| status for apache/airflow | `.oss-drafts/status-apache-airflow-status-20260611T143000Z.md` |
| find in apache/spark | `.oss-drafts/find-apache-spark-find-20260611T143000Z.md` |
| norms for apache/airflow | `.oss-drafts/norms-apache-airflow-norms-20260611T143000Z.md` |
| setup for apache/airflow | `.oss-drafts/setup-apache-airflow-setup-20260611T143000Z.md` |
| clarify issue #12345 in apache/airflow | `.oss-drafts/clarify-apache-airflow-issue12345-20260611T143000Z.md` |
| claim issue #8765 in apache/spark | `.oss-drafts/claim-apache-spark-issue8765-20260611T143000Z.md` |
| engage PR #9876 in apache/airflow | `.oss-drafts/engage-apache-airflow-pr9876-20260611T143000Z.md` |
| review-reply PR #4321 in apache/spark | `.oss-drafts/review-reply-apache-spark-pr4321-20260611T143000Z.md` |

## Frontmatter

Every draft file begins with YAML frontmatter:

```yaml
---
plugin: agentic-contributor
scenario: engage
repo: apache/airflow
item: pr9876
generated_at: 2026-06-11T14:30:00Z
status: draft
---
```

| Field | Value |
|-------|-------|
| `plugin` | Always `agentic-contributor` |
| `scenario` | The scenario key (`status`, `find`, `norms`, `setup`, `clarify`, `claim`, `engage`, `review-reply`) |
| `repo` | `owner/repo` (with slash, not hyphen) |
| `item` | `issueN`, `prN`, `status`, `find`, `norms`, or `setup` |
| `generated_at` | ISO-8601 UTC timestamp |
| `status` | Always `draft` — change to `sent` once the execution plugin posts it |

The `status: draft` field allows the separate execution/submission plugin to identify unreviewed
drafts and prompt for confirmation before acting on them.

## Two-Tier Review Protocol

### Report tier (scenarios 1–4: status, find, norms, setup)

After saving the file, the orchestrator shows:

> Saved to `<path>`. Review and edit this report file as needed before using it.

Then it presents a brief summary in chat and asks if you want to take any next step.

### Draft tier (scenarios 5–8: clarify, claim, engage, review-reply)

After saving the file, the orchestrator presents the complete draft in chat (clearly labelled as a
draft), then shows verbatim:

> **DRAFT — saved to `<path>`. Review and edit this file before sending.**
> This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin.

Then it asks you to review and modify the file before confirming.

## Gitignore-Ensure Behavior

Before writing the first `.oss-drafts/` file in a run, the orchestrator ensures the directory is
excluded from version control in your project:

1. **If your cwd is a git repo** (`.git/` exists): the orchestrator ensures `.oss-drafts/` is in
   `.git/info/exclude` using the idempotent one-liner:
   `grep -qxF '.oss-drafts/' .git/info/exclude || echo '.oss-drafts/' >> .git/info/exclude`
   This is non-invasive — it does not modify your tracked `.gitignore` and does not create a dirty
   working tree. Running `/oss` multiple times will not produce duplicate entries.
2. **If your cwd is not a git repo**: the step is skipped silently.

`.git/info/exclude` has the same syntax as `.gitignore` and applies only to your local clone. It
is already included in git's ignore machinery without any configuration.

## Guardrail Safety

Writing to `.oss-drafts/` uses the Write tool. The `/oss` command only uses the Write tool to
write to paths under `.oss-drafts/` in the user's working directory — never to any other path.

The `PreToolUse` guardrail hook does **not** block Write tool calls — it matches only `Bash` and
`mcp__plugin_agentic-contributor_github__*` tool calls. Therefore:

- Local draft file writes cannot reach GitHub.
- They cannot post comments, push branches, create issues or PRs, or trigger any outbound action.
- Adding Write to the `/oss` command's `allowed-tools` is the only configuration change needed.

See [Draft-Only Guardrail](draft-only-guardrail.md) for the full allow/deny matrix.

## Two-Plugin Handoff

The `status: draft` frontmatter field signals the separate execution/submission plugin that the
file has not yet been acted on. When you are ready to send a reviewed draft:

1. Open the file in your editor, make any final edits.
2. Switch to the execution/submission plugin and point it at the draft file.
3. The execution plugin reads the frontmatter (`repo`, `item`, `scenario`) to determine the
   correct GitHub API action, then asks for your final confirmation before posting.
4. After posting, the execution plugin updates `status: draft` → `status: sent`.

See [Two-Plugin System](two-plugin-system.md) for the full boundary description.

---

[Back to docs index](../index.md) | Related: [Draft-Only Guardrail](draft-only-guardrail.md) | [Two-Plugin System](two-plugin-system.md) | [Using /oss](../guides/using-oss.md)
