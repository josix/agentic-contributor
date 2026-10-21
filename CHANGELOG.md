# Changelog

All notable changes to the agentic-contributor plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] - 2026-10-21

### Security

- **`guard-outbound.sh` now denies the outbound command forms an agent may write by accident.** Each command segment is normalized (leading keywords and `VAR=value` assignments dropped; `env`, `command`, `exec`, `builtin`, `nohup`, `time`, `sudo`, `xargs` and their options stripped; a path-qualified binary reduced to its basename; `git` global options such as `-C`, `-c`, `--git-dir`, `--work-tree` and `gh` `-R`/`--repo` skipped) and checked in addition to the raw text, so no existing deny is loosened. Covers `git -C dir push`, `gh -R o/r pr create`, `/usr/bin/git push`, `env git push`, and `gh api` behind the same prefixes.
- New deny forms: `gh pr update-branch`; `gh label create/edit/delete/clone`; `gh workflow run/enable/disable`; `gh run rerun/cancel/delete`; `gh repo sync/rename/archive/unarchive`; `gh issue delete/transfer/pin/unpin/develop`; `gh secret`/`gh variable set/delete`; `gh gist edit/delete`; `gh alias set`; `gh codespace create`; `git send-email`, `git send-pack`, `git svn dcommit`; `curl --json/--data-binary/--data-urlencode/--data=`, `-dVALUE` and short-option bundles (`-sd`), `-T`/`--upload-file`, `-K`/`--config`, `--request=POST`, lowercase and any non-GET/HEAD/OPTIONS methods; `wget --body-data/--body-file` and lowercase `--method`.
- Heredoc handling and quote-aware segmentation are unchanged.

### Changed

- The 7 accidental-form `known-bypass` rows are promoted to `deny`, with about 130 new deny and allow rows (read-only forms such as `git -C dir log`, `gh -R o/r pr view`, `/usr/bin/git status`, `env git diff`, `gh label list`, `curl` GET still pass). Deliberate obfuscation (variables, `eval`, aliases, `bash -c`, heredoc quote tricks) stays documented as known-bypass.
- `docs/reference/hooks.md` Limits section and the deny matrices updated.

## [0.5.0] - 2026-10-21

### Added

- **Policy detection** in `contribution-norms`: AI policy files, CONTRIBUTING AI sections, PR-template disclosure checkboxes, AI co-author trailer rules, open-PR caps, vouch lists, good-first-issue AI rules, and issue-first rules. The `norms` briefing gains "AI Use Policy" and "Contribution Limits & Trust Gates" sections with sources and confidence. New `references/ai-policy-signals.md` holds the signal catalog, the `policy` block schema, and facts verified against live repos: DataFusion's `.asf.yaml` key `github.pull_requests.creation_cap.max_open_pull_requests`, Ghostty's `.github/VOUCHED.td` format, and the DataFusion AI policy source. Unverified project claims are listed as unverified.
- **Policy Preflight** (`/oss` Step 3a) for `find`, `clarify`, `claim`, `engage`, `review-reply`, and `report`: reuses a `policy` block from `.oss-drafts/` frontmatter when under 7 days old, otherwise dispatches `oss-researcher` (key `policy-preflight`). Advisory only; never blocks a draft. Absence is reported as not found, never "no policy".
- **Issue-first routing**: a PR-intent request with no issue reference routes to `report` when the project requires or recommends an issue first; the draft records `routed_from`. Routing is unchanged when the policy is unknown.
- Frontmatter fields `policy` and `routed_from`.

### Changed

- **AP9** (AI co-author trailer or "Generated with" footer) in review-reply lint is now active when the draft's `policy` has `coauthor_trailer_forbidden: true` or `ai_policy` other than `none-found`; otherwise it is reported as unevaluated.
- `oss-researcher` supports the `policy-preflight` key and may use `search_code` / `gh search code` (read-only).
- `issue-drafting` adds an issue-first / AI-policy note to Private notes and a `routed_from` message.
- Docs, README, and manifests updated for 0.5.0. Still 9 scenarios and a single `/oss` entrypoint.
- **The guard is documented as a tripwire, not a security boundary.** `docs/reference/hooks.md` gains a "Limits" section; `docs/guides/github-access.md` recommends a read-only fine-grained token as the real boundary. The test harness supports `known-bypass` rows: documented gaps that are reported but not counted as failures (9 recorded, including a heredoc-quote case already present in 0.4.0).

### Security

- `gh api graphql` read-only detection now rejects any `$` outside single quotes (positional and special parameters such as `$1`, `$@`, `$*`), not only `$NAME` / `${NAME}`.

## [0.4.0] - 2026-10-21

### Changed

- **`review-reply` no longer ghostwrites replies.** Maintainers (e.g. the Apache DataFusion AI policy, the "meat proxy" critique) reject AI-generated review replies. The default `brief` mode now produces a private per-comment understanding brief (quoted comment, code at the line, likely concern, conventions, commit-to-comment mapping, questions to ask yourself, optional bullet-only talking points) and a `TODO(you): reply in your own words` placeholder. There is no full-prose-reply option.
- The postable "change-summary comment" is removed; a commit-to-comment mapping table in the private brief replaces it.
- Translate/tidy is limited to text the user wrote, with no new claims.
- **Draft-tier files now use `body_format: 2`**: only text inside `<!-- oss:send:start -->` / `<!-- oss:send:end -->` is sendable; a `## Private notes (not sent)` section holds briefs and lint findings. Frontmatter gains `body_format` and (review-reply) `mode: brief|lint`.
- **Coordinated change required:** the separate execution/submission plugin must support `body_format: 2` (post only the send block, refuse while `TODO(you)` remains) before this release is used for posting. Otherwise private notes would be posted.
- `oss-researcher` now fetches PR commits with timestamps and review comments with `diff_hunk`, `path`, `line`, `created_at` for review-reply.

### Added

- **Lint mode** for `review-reply` ("check my reply", "lint my reply"): checks the user's own reply against anti-patterns AP1-AP9 (each with a bad/good pair in `smart-questions-principles.md`), quoting spans and asking questions, never rewriting. AP9 is defined but inactive until a policy profile exists (v0.5.0).
- New concept page `docs/concepts/maintainer-friendly-contributing.md` and nav entry; docs updated for the body format and the brief, write, lint flow.

### Security

- Removed v0.3.1 heredoc-body skipping in `guard-outbound.sh`: it allowed writing a script with a `cat`/`tee` heredoc and then executing it. Heredoc bodies are always checked again; use the Write tool to create files whose text mentions outbound commands.

## [0.3.1] - 2026-10-21

### Fixed

- **`guard-outbound.sh` no longer denies harmless multi-line commands.** `gh api` flags are now evaluated per `gh api` invocation instead of across the whole command string, so a heredoc that merely mentions `gh api`, `git push`, or `gh pr create` as text (e.g. `cat > notes.md <<'EOF' ... EOF`) is allowed. Heredoc bodies are skipped only when they are pure data (consumer is `cat`/`tee`, nothing piped or chained after the delimiter, quoted delimiter or no command substitution in the body, heredoc terminated); bodies fed to `bash`, `sh`, `eval`, `xargs`, `ssh`, `python`, `node`, etc. are still checked.
- **Read-only `gh api graphql` queries are allowed.** Allowed only when the command has no `mutation` keyword (case-insensitive, quote-splitting normalised), no `=@file` reference, no `--input`, no command substitution or unquoted shell expansion, and the `query=` value does not start with a shell variable.
- `gh api -X GET ... -f key=value` is allowed (fields are query parameters for an explicit GET).

### Security

- **Closed `gh api` mutation gaps:** `-F`, `--raw-field`, `--input`, `-XPOST`, `-X=POST`, `--method=POST`, attached `-fkey=value`, and case-insensitive method names are now denied.
- Command segmentation is quote-aware (separators inside quotes are ignored; an unclosed quote falls back to naive splitting, which can only over-deny), so a multi-line quoted `--jq` argument cannot hide a following `-X POST`.
- `gh api` options are now parsed from shell-unquoted tokens (method, fields, `--input`, endpoint), so text inside a `-f` value such as `-X GET` or `graphql` can no longer trigger an allow path; GraphQL is allowed only for the literal `graphql` endpoint, and `@file` values are detected after quote removal.
- Command/process substitutions no longer detach later flags (`--jq "$(...)" -X POST` is denied); heredoc bodies nested inside `$( )`, `<( )`, `( )` or backticks are kept and checked.
- If command segmentation fails, a `gh ... api` command is denied (fail closed) instead of being checked as one unsplit line.
- Any preprocessing failure falls back to the raw command (never fails open).
- **New regression harness** `hooks/tests/run-guard-tests.sh` with `hooks/tests/guard-cases.tsv` (98 allow/deny cases); compatible with macOS bash 3.2. Run with `bash hooks/tests/run-guard-tests.sh`.

## [0.3.0] - 2026-06-12

### Added

- **New `report` scenario (scenario 9).** `/oss draft a bug report for <repo> about <symptom>` and `/oss draft a feature request for <repo>` now route to the new `report` scenario, which drafts a complete, evidence-structured issue (bug or feature) for the user's review. The draft is never posted — it is saved to `.oss-drafts/report-<owner>-<repo>-<item>-<UTC>.md` and presented with the mandatory draft-tier notice.
- **New `issue-drafting` skill** (`skills/issue-drafting/SKILL.md`). Implements a three-step Pre-flight (duplicate search across open+closed issues, ISSUE_TEMPLATE fetch, title/label convention extraction) followed by two procedures: Procedure 2 — Bug Report (environment/version info, minimal reproducible example, steps to reproduce, expected vs. actual, error logs fenced, file:line references) and Procedure 3 — Feature Request (problem statement, proposed solution, alternatives considered, scope/impact, file:line references). Missing required evidence is always marked with `TODO:` placeholders; nothing is fabricated.
- **ISSUE_TEMPLATE application logic.** The skill handles four cases: (a) markdown templates (`.md`) — fills sections, strips HTML comments; (b) YAML issue forms (`.yml`/`.yaml` with `body:`) — maps content to form fields by `label`/`id`, flags `required: true` fields; (c) multiple templates — picks the type-appropriate one and tells the user which was chosen; (d) no template — uses built-in structure and notes this in the draft.
- **Duplicate-search pre-flight.** Before drafting, `oss-researcher` searches open and closed issues with the symptom keywords and surfaces the top 3–5 candidates. If a strong duplicate exists, the skill recommends commenting on the existing issue instead of filing a new one.
- **New user story** (`stories/draft-new-issue-bug-or-feature.md`) covering duplicate search, ISSUE_TEMPLATE application, evidence requirements, monorepo component selection, security/Discussions redirect warnings, and draft-only behavior.
- **Routing, command, and docs updates.** `oss-scenario-routing` SKILL.md, `commands/oss.md`, `docs/reference/scenarios.md`, `docs/reference/skills.md`, `docs/reference/commands.md`, `docs/guides/using-oss.md`, and `docs/concepts/draft-files.md` updated: nine scenarios, draft tier expanded to cover scenarios 5–9, `issue-bug`/`issue-feature` item values added, new examples added.
- **`README.md` updated.** Features list, examples, scenarios table, skills table, and documentation links reflect the new scenario and skill.

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
