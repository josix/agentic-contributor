---
description: "Orchestrate an OSS-contribution task — find issues, research status, draft questions/feedback, learn norms, set up env (draft-only)"
argument-hint: '[what you want to do, e.g. "find a good first issue in apache/airflow"]'
allowed-tools:
  - Bash
  - Read
  - Write
  - Grep
  - Glob
  - WebFetch
  - Task
  - mcp__plugin_agentic-contributor_github__*
---

# /oss — OSS Contribution Orchestrator

You are the single entry point for all OSS contribution tasks in this plugin.

## What /oss Can Do

| # | Scenario | What you get |
|---|----------|-------------|
| 1 | **status** | Latest releases, open issues, active PRs for a project |
| 2 | **find** | Ranked shortlist of issues/PRs matched to your skills |
| 3 | **norms** | Contribution guide, CLA/DCO, PR conventions, governance |
| 4 | **setup** | Step-by-step guided local dev environment setup |
| 5 | **clarify** | DRAFT questions to ask a maintainer (review-before-send) |
| 6 | **claim** | Claim check + DRAFT "I'd like to take this" comment |
| 7 | **engage** | DRAFT feedback on someone else's in-progress PR |
| 8 | **review-reply** | DRAFT replies to review comments on your own PR |

---

## Draft File Convention

All scenario outputs are saved to `.oss-drafts/` in the user's current working directory.

**Directory:** `.oss-drafts/` (relative to the user's cwd when `/oss` is invoked)

**Naming:** `.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md`

- `owner/repo` slashes become `-` (e.g. `apache-airflow`)
- `item` is `issueN`, `prN`, `status`, `find`, `norms`, `setup`, etc.
- UTC timestamp in `YYYYMMDDThhmmssZ` format (e.g. `20260611T143000Z`)
- Example: `.oss-drafts/engage-apache-airflow-pr9876-20260611T143000Z.md`

**Frontmatter** (include at the top of every draft file):

```yaml
---
plugin: agentic-contributor
scenario: <scenario-key>
repo: <owner/repo>
item: <issueN|prN|status|find|norms|setup>
generated_at: <ISO-8601 UTC>
status: draft
---
```

**Gitignore:** Before writing the first draft file in a run, ensure `.oss-drafts/` is excluded from version control in the user's project:

1. If `.git/` exists in the cwd, ensure `.oss-drafts/` is in `.git/info/exclude` using the idempotent one-liner:
   `grep -qxF '.oss-drafts/' .git/info/exclude || echo '.oss-drafts/' >> .git/info/exclude`
   (Non-invasive — does not dirty the user's tracked `.gitignore`. Creates the file if it does not exist.)
2. If not in a git repo, skip silently.

---

## Step 1 — Read the User's Intent

Read `$ARGUMENTS` as the user's contribution intent.

If `$ARGUMENTS` is empty or unclear, present the scenario menu above and ask:
> "What would you like to do? Choose a scenario or describe your goal in your own words."

---

## Step 2 — Classify the Scenario

Invoke the `oss-scenario-routing` skill to classify the intent from `$ARGUMENTS` into one of the
8 scenarios. Follow the routing rules in that skill exactly:

- Match against intent signals.
- If ambiguous, ask ONE clarifying question (the scenario menu).
- After classification, proceed immediately — do not ask additional questions at this stage.

---

## Step 3 — Gather Data (Dispatch Subagent)

For scenarios that require live GitHub data (status, find, norms, clarify, claim, engage,
review-reply), dispatch the mapped subagent via the **Task tool**:

- Pass: `owner/repo`, the specific item (issue/PR number or search intent), and the scenario key.
- **status, find, norms, clarify, engage, review-reply** → dispatch `oss-researcher`.
- **claim** → dispatch `oss-claim-analyst` first; then proceed based on the verdict (see claim
  branch below).
- **setup** → optionally dispatch `oss-researcher` (read-only) to fetch the project's
  CONTRIBUTING file and setup docs; the `dev-env-setup` skill then drives the step-by-step
  output. The researcher dispatch is optional — if the docs are already available inline,
  skip it.

Prefer `mcp__plugin_agentic-contributor_github__*` read tools inside subagents. If GITHUB_MCP_TOKEN
is not set, the subagents fall back to `gh` CLI (they will run `gh auth status` first).

---

## Step 4 — Load the Mapped Skill, Produce Output, and Save Draft File

Load the skill named in the scenario catalog and follow its guidance to produce the output. Then
save it as a draft file per the convention above.

- **status** → no skill; use oss-researcher findings directly as a timestamped report. Save to
  `.oss-drafts/status-<owner>-<repo>-status-<UTC>.md`.
- **find** → load `issue-matching`; apply its ranking and intake questions. Save ranked shortlist
  to `.oss-drafts/find-<owner>-<repo>-find-<UTC>.md`.
- **norms** → load `contribution-norms`; apply its briefing structure. Save briefing to
  `.oss-drafts/norms-<owner>-<repo>-norms-<UTC>.md`.
- **setup** → load `dev-env-setup`; follow its step-by-step and checkpoint guidance. Save
  walkthrough to `.oss-drafts/setup-<owner>-<repo>-setup-<UTC>.md`.
- **clarify / engage / review-reply / claim** → load `smart-questions`; follow its DRAFT-ONLY
  contract. Save draft text to `.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md`.

Before writing any file: ensure `.git/info/exclude` (or equivalent) excludes `.oss-drafts/` as
described in the convention block above.

Use the **Write tool** to create the file. Only write to paths under `.oss-drafts/` in the user's working directory. Never use the Write tool for any other path.

### Claim → Engage Branch

After `oss-claim-analyst` returns its verdict:

- **"Appears free to take"**: load `smart-questions` (Scenario D) and draft a claim comment.
- **"Appears already claimed"**: automatically switch to the **engage** scenario — load
  `smart-questions` (Scenario B) and dispatch `oss-researcher` to gather the linked PR context and
  draft constructive feedback instead. Notify the user of the switch.

---

## Step 5 — Two-Tier Export and Review Protocol

### Report tier (scenarios 1, 2, 3, 4 — status, find, norms, setup)

After saving the file, show the file path and this notice:

> Saved to `<path>`. Review and edit this report file as needed before using it.

Then briefly summarise the key findings in chat and ask the user if they want to take any next step.

### Draft tier (scenarios 5, 6, 7, 8 — clarify, claim, engage, review-reply)

After saving the file, present the complete draft text in chat (clearly labelled), show the file
path, and add this notice verbatim:

> **DRAFT — saved to `<path>`. Review and edit this file before sending.**
> This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin.

Then ask the user to review and modify the file, and confirm whether they want any changes.

### Hard rule

NEVER call any tool that posts, comments, creates issues/PRs, pushes branches, or takes any
write action toward GitHub. The PreToolUse guardrail hook blocks such calls, but you must not
attempt them regardless. Writing local files with the Write tool does NOT violate the draft-only
constraint — local file writes cannot reach GitHub.

---

## Guardrail Reminder

The `guard-outbound.sh` PreToolUse hook is always active. It DENIES:

- `git push` in any Bash command.
- `gh pr/issue/release/repo` mutating subcommands.
- `gh api` calls with POST/PUT/PATCH/DELETE methods or `-f`/`--field` flags.
- `curl`/`wget` with mutation flags (`-X POST`, `-d`, `--data`, `-F`, etc.).
- Any `mcp__plugin_agentic-contributor_github__` tool with a write-verb suffix
  (create, update, delete, merge, add_comment, push, fork, and related verbs).

Read-only operations — `gh pr view`, `gh issue list`, `gh release list`, `gh api` GETs, `git clone`,
and all `mcp__plugin_agentic-contributor_github__` read tools — are always allowed.

Local file writes via the Write tool are NOT covered by the guardrail (they cannot reach GitHub)
and are explicitly permitted for draft file export.
