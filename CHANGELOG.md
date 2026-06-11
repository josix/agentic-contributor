# Changelog

All notable changes to the agentic-contributor plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-06-12

### Added

- **Draft file export for all 8 scenarios.** The `/oss` orchestrator now writes every scenario output to `.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md` in the user's working directory using the Write tool. All scenarios (including read-only report scenarios 1–4) produce an editable markdown file with YAML frontmatter (`plugin`, `scenario`, `repo`, `item`, `generated_at`, `status: draft`).
- **Two-tier review protocol.** Report tier (scenarios 1–4: status, find, norms, setup) shows "Saved to `<path>`. Review and edit this report file as needed before using it." Draft tier (scenarios 5–8: clarify, claim, engage, review-reply) presents the draft in chat and shows the canonical notice: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."
- **Gitignore-ensure step.** Before writing the first draft file in a run, `/oss` appends `.oss-drafts/` to `.git/info/exclude` in the user's project (non-invasive; does not dirty the tracked `.gitignore`). Falls back gracefully if not in a git repo.
- **`Write` tool added to `/oss` allowed-tools.** Local file writes via Write cannot reach GitHub and do not violate the draft-only constraint.
- **New `docs/concepts/draft-files.md`.** Canonical reference for the draft file convention: directory, naming, frontmatter schema, two-tier review protocol, gitignore-ensure behavior, guardrail safety rationale, and two-plugin handoff via `status: draft`.
- **`.oss-drafts/` added to this plugin repo's `.gitignore`.**

## [0.1.0] - 2026-06-09

### Added

- Single `/oss` orchestrator command with 8-scenario routing and an interactive scenario menu when arguments are omitted.
- 8-scenario coverage: **status** (project news), **find** (issue/PR matching), **norms** (contribution guide + CLA/DCO), **setup** (dev environment walkthrough), **clarify** (draft maintainer questions), **claim** (availability check + draft claim comment), **engage** (draft in-progress PR feedback), **review-reply** (draft replies to review comments).
- `oss-researcher` read-only subagent — fetches GitHub issues, PRs, releases, and contribution docs via the GitHub MCP server or `gh` CLI fallback; paginated, timestamped, never mutates.
- `oss-claim-analyst` read-only subagent — checks assignee, linked open PRs, and recent intent comments; emits an "appears free to take" / "appears already claimed" verdict with an evidence table; automatic claim→engage branch switch when already claimed.
- `oss-scenario-routing` skill — classifies `$ARGUMENTS` into one of the 8 scenarios; handles the claim→engage branch transition; enforces one-question-max clarification.
- `issue-matching` skill — structured contributor intake (5 questions), heuristic scoring, top-5–10 ranked shortlist with per-item rationale.
- `smart-questions` skill — DRAFT-ONLY contract for scenarios clarify, engage, review-reply, and claim; four scenario-specific drafting procedures (A–D) with smart-questions principles.
- `contribution-norms` skill — locates and surfaces CONTRIBUTING, CODE_OF_CONDUCT, DCO, PR templates, and Apache-specific governance notes (ICLA, JIRA, dev@ mailing list, lazy consensus).
- `dev-env-setup` skill — step-by-step guided local setup extracted from official docs; flags heavy setups (Airflow Breeze, Spark JDK+Maven); defines an "environment ready" checkpoint; confirms before destructive actions.
- Draft-only `PreToolUse` guardrail hook (`hooks/hooks.json` + `hooks/scripts/guard-outbound.sh`) — DENIES `git push`, `gh pr/issue/release/repo` mutating subcommands, `gh gist create`, `gh api` write calls, `curl`/`wget` mutation flags, and all MCP write-verb tools; ALLOWS all read operations; denial message explains the two-plugin system.
- GitHub MCP server configuration (`.mcp.json`, `GITHUB_MCP_TOKEN` env var) with `gh` CLI fallback for all subagents.
- Configurable target-projects list (`config/targets.example.yaml`) with per-project label filters and global defaults for recency window, item types, and shortlist size.
