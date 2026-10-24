# Draft Files

How the `/oss` command exports every scenario output to a local, editable markdown file in
`.oss-drafts/` — and why this is safe under the draft-only guardrail.

## Overview

Every `/oss` run produces a markdown file in `.oss-drafts/` inside your current working directory.
The file is written by the orchestrator using the Write tool immediately after the subagent and
skill have produced their output. You can open and edit the file in any text editor before
deciding what to do with it.

This applies to all 10 scenarios — both read-only report scenarios (1–4) and outbound-text draft
scenarios (5–10).

## Output Directory

```
<your project cwd>/
└── .oss-drafts/
    ├── find-apache-airflow-find-20260611T143000Z.md
    ├── norms-apache-airflow-norms-20260611T144500Z.md
    ├── engage-apache-airflow-pr9876-20260611T150000Z.md
    ├── track-apache-airflow-issue1234-20261024T101500Z.md
    └── track-apache-airflow-issue1234-20261024T101500Z.state
```

A tracked session's one-line pointer is not in `.oss-drafts/`: it lives in the git dir, at
`<gitdir>/agentic-contributor/track-active` (see [Tracked Sessions](tracked-sessions.md)).

The directory is created automatically on the first write.

## File Naming Convention

```
.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md
```

| Part | Description | Example |
|------|-------------|---------|
| `scenario` | One of: `status`, `find`, `norms`, `setup`, `clarify`, `claim`, `engage`, `review-reply`, `report`, `prepare-pr` | `engage` |
| `owner` | Repository owner (slashes in `owner/repo` become `-`) | `apache` |
| `repo` | Repository name | `airflow` |
| `item` | `issueN`, `prN`, `status`, `find`, `norms`, `setup`, `issue-bug`, `issue-feature`, `pr-new`, `debrief`, or `task` (track ledgers) | `pr9876` |
| `UTC` | Timestamp in `YYYYMMDDThhmmssZ` format | `20260611T143000Z` |

Track ledgers (v0.8.0) use the prefix `track-` (a file kind, not a scenario key): `.oss-drafts/track-<owner>-<repo>-<item>-<UTC>.md`.

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
| report bug in apache/airflow | `.oss-drafts/report-apache-airflow-issue-bug-20260612T100000Z.md` |
| report feature request in apache/spark | `.oss-drafts/report-apache-spark-issue-feature-20260612T100000Z.md` |
| prepare-pr for issue #1234 in apache/datafusion | `.oss-drafts/prepare-pr-apache-datafusion-issue1234-20260612T100000Z.md` |
| prepare-pr debrief in apache/datafusion | `.oss-drafts/prepare-pr-apache-datafusion-debrief-20260612T100000Z.md` |
| prepare-pr track ledger for issue #1234 in apache/datafusion | `.oss-drafts/track-apache-datafusion-issue1234-20261024T101500Z.md` (pointer: `<gitdir>/agentic-contributor/track-active`) |

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
body_format: 2
---
```

| Field | Value |
|-------|-------|
| `plugin` | Always `agentic-contributor` |
| `scenario` | The scenario key (`status`, `find`, `norms`, `setup`, `clarify`, `claim`, `engage`, `review-reply`, `report`, `prepare-pr`) |
| `repo` | `owner/repo` (with slash, not hyphen) |
| `item` | `issueN`, `prN`, `status`, `find`, `norms`, `setup`, `issue-bug`, `issue-feature`, `pr-new`, `debrief`, or `task` (track ledgers) |
| `generated_at` | ISO-8601 UTC timestamp |
| `status` | Always `draft` — change to `sent` once the execution plugin posts it |
| `body_format` | Draft tier, v0.4.0+: `2` means only the `oss:send` block is sendable. `private` (change debriefs) means nothing is sendable; consumers must refuse it. Absent or `1` means legacy (whole body sendable) |
| `mode` | `review-reply`: `brief` (default) or `lint`. `prepare-pr`: `track`, `debrief`, `draft` (default), or `lint` |
| `base`, `head`, `diff_stats` | v0.7.0+, `prepare-pr` only: the refs diffed and `{files, insertions, deletions}` |
| `policy` | v0.5.0+, `find`, `norms`, and draft-tier scenarios: the project's detected AI-policy and contribution-limit block (see below) |
| `readiness_login` | v0.6.0+, `claim`, `find`, and `prepare-pr`: the GitHub login the readiness check used (absent when skipped) |
| `readiness` | v0.6.0+, `claim`, `find`, and `prepare-pr`: `{open_prs, cap, merged_prs_in_repo, account_age_days, vouch_status, tier}`; `unknown` for anything not read. Advisory; also shown in private notes, never in a send block |
| `task`, `issue`, `branch`, `base_commit`, `started_at`, `stopped_at`, `scope`, `scope_source`, `api_paths`, `budget` | v0.8.0+, track ledgers only (see below); `status` is `active` or `stopped` there |
| `drift_lines`, `drift_files`, `drift_source`, `drift_max`, `explain_max`, `explain_interval_min` | v0.9.0+, track ledgers only: scope-drift thresholds and caps, and breakpoint-question limits (a v0.8.0 ledger without them uses the defaults 400 / 10 / default / 2 / 4 / 20) |
| `routed_from` | v0.5.0+, only when a PR-intent request was rerouted to `report` (issue-first); names the original scenario |

The `status: draft` field allows the separate execution/submission plugin to identify unreviewed
drafts and prompt for confirmation before acting on them.

### Track ledger

A tracked session (`/oss track`) writes a private ledger with its own frontmatter and an append-only
list of decisions, plus the one-line pointer `"$(git rev-parse --git-dir)/agentic-contributor/track-active"` (in the
git dir, never the worktree, so a cloned repository cannot ship an active session; tracked sessions
require git). It has no send block and is
never PR text. The full format (frontmatter, entries, hook-written lines, trigger classes) lives in
`skills/pr-preparation/references/decision-ledger.md`; see
[Tracked Sessions & Checkpoints](tracked-sessions.md) for how it is used.

From v0.9.0 a tracked session also has a disposable state file `track-...Z.state` next to the ledger.
It is written by `track-breakpoint.sh`, holds only repo-relative paths of edited files and a few
counters (never contents), and is deleted by `/oss track stop`. The caps live in the ledger, not in
the state file.

### The `policy` block

```yaml
policy:
  ai_policy: none-found|disclosure-required|restricted|banned
  ai_policy_sources: [<path-or-url>]
  disclosure: required|recommended|none-found
  disclosure_mechanism: pr-template-checkbox|statement|trailer|unknown
  coauthor_trailer_forbidden: true|false|unknown
  open_pr_cap: <int>|unknown
  open_pr_cap_applies_to: non-committers|all|unknown
  vouch_required: true|false|unknown
  vouch_file: <path>|none-found
  gfi_ai_ban: true|false|unknown
  issue_first: required|recommended|unknown
  confidence: high|medium|low
  fetched_at: 2026-10-21T10:00:00Z
```

Heuristic and advisory: `none-found`/`unknown` means the plugin did not find a signal, not that the
project has no policy. `/oss` reuses the block from the newest draft for the same repo when
`fetched_at` is under 7 days old. Readers that do not know the field ignore it.

## Body Format

Draft-tier files (`body_format: 2`) split sendable text from private notes:

```markdown
<!-- oss:send:start -->
…text you approve for posting…
<!-- oss:send:end -->

## Private notes (not sent)
…understanding brief / lint findings / notes…
```

- Only the text between the markers is ever posted. Private notes are for you.
- A `TODO(you):` inside a send block means the text is not ready; the execution plugin must refuse to send while it remains (and lint reports it as AP8).
- Files with several independent messages (one reply per review comment) use one marker pair per message.
- Files with no `body_format`, or `1`, are legacy: the whole body is sendable.
- Report-tier files have no send block.

This is a handoff contract with the execution plugin; see [Two-Plugin System](two-plugin-system.md).

## Two-Tier Review Protocol

### Report tier (scenarios 1–4: status, find, norms, setup)

After saving the file, the orchestrator shows:

> Saved to `<path>`. Review and edit this report file as needed before using it.

Then it presents a brief summary in chat and asks if you want to take any next step.

### Draft tier (scenarios 5–10: clarify, claim, engage, review-reply, report, prepare-pr)

After saving the file, the orchestrator presents the complete draft in chat (clearly labelled as a
draft), then shows verbatim:

> **DRAFT — saved to `<path>`. Review and edit this file before sending.**
> This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin.

Then it asks you to review and modify the file before confirming. For `review-reply`, the chat shows the understanding brief and `TODO(you)` placeholders; you write the reply yourself in the send block. For `prepare-pr`, the send block is a problem-first scaffold whose Why, What changed, and Unknowns sections are `TODO(you)`; debrief mode writes a private file with no send block.

## Gitignore-Ensure Behavior

Before writing the first `.oss-drafts/` file in a run, the orchestrator ensures the directory is
excluded from version control in your project:

1. **If your cwd is in a git repo**: the orchestrator resolves the exclude file with
   `ex="$(git rev-parse --git-path info/exclude)"` (this also works in linked worktrees and
   submodules, where `.git` is a file) and ensures `.oss-drafts/` is in it using the idempotent
   one-liner: `grep -qxF '.oss-drafts/' "$ex" || echo '.oss-drafts/' >> "$ex"`
   This is non-invasive — it does not modify your tracked `.gitignore` and does not create a dirty
   working tree. Running `/oss` multiple times will not produce duplicate entries.
2. **If your cwd is not a git repo**: the step is skipped silently.

The exclude file (`.git/info/exclude` in a plain clone) has the same syntax as `.gitignore` and applies only to your local clone. It
is already included in git's ignore machinery without any configuration.

## Guardrail Safety

Writing to `.oss-drafts/` uses the Write tool. The `/oss` command only uses the Write tool to
write to paths under `.oss-drafts/` in the user's working directory — never to any other path.

The `PreToolUse` guardrail hook does **not** block Write tool calls — it matches only `Bash` and
`mcp__plugin_agentic-contributor_github__*` tool calls. A separate advisory hook
(`track-checkpoint.sh`, and from v0.9.0 `track-breakpoint.sh` on `PostToolUse`/`Stop`) does match Edit/Write, but only inside a tracked session, and it never acts
on files in `.oss-drafts/` except to auto-allow an Edit of the active ledger. `/oss` gains `Edit` for
the ledger only. Therefore:

- Local draft file writes cannot reach GitHub.
- They cannot post comments, push branches, create issues or PRs, or trigger any outbound action.
- Adding Write to the `/oss` command's `allowed-tools` is the only configuration change needed.

See [Draft-Only Guardrail](draft-only-guardrail.md) for the full allow/deny matrix.

## Two-Plugin Handoff

The `status: draft` frontmatter field signals the separate execution/submission plugin that the
file has not yet been acted on. When you are ready to send a reviewed draft:

1. Open the file in your editor, make any final edits.
2. Switch to the execution/submission plugin and point it at the draft file.
3. The execution plugin reads the frontmatter (`repo`, `item`, `scenario`, `body_format`) to determine the
   correct GitHub API action, posts only the `oss:send` block(s) when `body_format` is `2`, refuses while `TODO(you)` remains, and asks for your final confirmation before posting.
4. After posting, the execution plugin updates `status: draft` → `status: sent`.

See [Two-Plugin System](two-plugin-system.md) for the full boundary description.

---

[Back to docs index](../index.md) | Related: [Draft-Only Guardrail](draft-only-guardrail.md) | [Two-Plugin System](two-plugin-system.md) | [Using /oss](../guides/using-oss.md)
