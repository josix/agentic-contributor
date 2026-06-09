# oss-contribution

Research-and-engagement assistant for contributing to open-source projects — draft-only, human-in-the-loop.

This is the **research-and-engagement half** of a two-plugin system. It surfaces issues, researches project status, and drafts all outbound text for your review. It **never posts, pushes, or sends anything.**

## Features

- **Single `/oss` entrypoint** — one command handles all 8 contribution scenarios; presents an interactive menu if arguments are omitted.
- **8 built-in scenarios** — project status, issue/PR matching, contribution norms, dev environment setup, maintainer questions, issue claiming, PR feedback, and review-reply drafting.
- **Read-only GitHub research** — `oss-researcher` and `oss-claim-analyst` subagents access GitHub via the MCP server or `gh` CLI; neither ever mutates.
- **Draft-only guardrail** — a `PreToolUse` hook actively denies all outbound and mutating actions; drafts are presented for human review before any separate execution step.
- **MCP + `gh` fallback** — prefers the structured GitHub MCP server when `GITHUB_MCP_TOKEN` is set; falls back to `gh` CLI automatically.
- **Configurable target projects** — copy `config/targets.example.yaml` to `config/targets.yaml` to set a personal shortlist of repos.

## Prerequisites

| Requirement | Version | Purpose |
|---|---|---|
| Claude Code CLI | latest | Plugin host |
| GitHub CLI (`gh`) | any | `gh` fallback authentication and read commands |
| `GITHUB_MCP_TOKEN` env var | — | GitHub personal access token for MCP server (optional but recommended) |
| `jq` | any | Guardrail script JSON parsing |

## Installation

### Local install (development)

```bash
git clone https://github.com/josix/oss-contribution.git
claude --plugin-dir /path/to/oss-contribution
```

### Enable after cloning

```
/plugins enable oss-contribution
```

### Marketplace

```
/plugin marketplace add josix/oss-contribution
/plugin install oss-contribution@josix-plugins
```

### Validating Your Installation

Confirm the plugin loaded correctly before your first `/oss` run:

```bash
# 1. Confirm plugin.json and marketplace.json are valid JSON
jq . /path/to/oss-contribution/.claude-plugin/plugin.json
jq . /path/to/oss-contribution/.claude-plugin/marketplace.json

# 2. Confirm the /oss command appears in Claude Code
# (type /oss in Claude Code and verify the command is suggested)

# 3. Confirm gh CLI auth (fallback path)
gh auth status
```

> **Note:** Hooks and the MCP server are registered at session start. After enabling the plugin, restart your Claude Code session for the `PreToolUse` guardrail hook and the GitHub MCP server to take effect.

## Usage

### The `/oss` Command

`/oss` is the single entry point for all OSS contribution tasks.

```
/oss [what you want to do]
```

**Examples:**

```
/oss find a good first issue in apache/airflow
/oss what's the latest status of apache/spark?
/oss how do I contribute to apache/airflow — CLA and PR conventions?
/oss help me set up apache/airflow locally
/oss draft a question about issue #12345 in apache/airflow
/oss is issue #8765 in apache/spark free to claim?
/oss help me give feedback on apache/airflow PR #9876
/oss help me respond to the review on my apache/spark PR #4321
```

If you omit arguments, `/oss` presents the full scenario menu and asks which applies.

## Scenarios

| # | Scenario | Intent | Skill | Agent | Output |
|---|---|---|---|---|---|
| 1 | **status** | Latest releases, open issues, active PRs | — | `oss-researcher` | Timestamped report |
| 2 | **find** | Match issues/PRs to your skills | `issue-matching` | `oss-researcher` | Ranked shortlist |
| 3 | **norms** | Contribution guide, CLA/DCO, PR conventions | `contribution-norms` | `oss-researcher` | Contribution briefing |
| 4 | **setup** | Step-by-step local dev environment guide | `dev-env-setup` | `oss-researcher` (optional) | Guided walkthrough |
| 5 | **clarify** | Draft questions for a maintainer | `smart-questions` | `oss-researcher` | DRAFT (review-before-send) |
| 6 | **claim** | Issue availability check + draft claim comment | `smart-questions` | `oss-claim-analyst` | Assessment + DRAFT |
| 7 | **engage** | Draft feedback on someone else's PR | `smart-questions` | `oss-researcher` | DRAFT (review-before-send) |
| 8 | **review-reply** | Draft replies to review comments on your PR | `smart-questions` | `oss-researcher` | DRAFT (review-before-send) |

Scenarios 5–8 produce outbound-text drafts. Every draft is presented to you with a clear notice that the plugin will NOT send it — sending is the execution plugin's job.

## Agents

| Agent | Model | Purpose |
|---|---|---|
| `oss-researcher` | inherit | Read-only GitHub research: fetches issues, PRs, releases, and contribution docs via MCP or `gh` CLI |
| `oss-claim-analyst` | inherit | Claim detection: checks assignees, linked open PRs, and recent intent comments; emits a free/claimed verdict |

Both agents are read-only. The `PreToolUse` guardrail hook enforces this at the tool level.

## Skills

| Skill | Purpose |
|---|---|
| `oss-scenario-routing` | Classifies intent into one of the 8 scenarios; handles the claim→engage branch switch |
| `issue-matching` | Structured contributor intake (5 questions), heuristic scoring, ranked shortlist |
| `smart-questions` | DRAFT-ONLY contract for clarify, engage, review-reply, and claim scenarios |
| `contribution-norms` | Surfaces CONTRIBUTING, CLA/DCO, PR/commit conventions, and Apache governance |
| `dev-env-setup` | Step-by-step guided local setup from official docs with a verifiable checkpoint |

## Hooks

The `PreToolUse` guardrail hook (`hooks/hooks.json` + `hooks/scripts/guard-outbound.sh`) runs before every `Bash` call and every GitHub MCP tool call. It enforces draft-only behavior.

| Action | Decision |
|---|---|
| `git push` (any form) | DENY |
| `gh pr create / comment / review / edit / merge / close / reopen / lock / unlock / ready / --fill` | DENY |
| `gh issue create / comment / edit / close / reopen / lock / unlock` | DENY |
| `gh release create / edit / delete / upload` | DENY |
| `gh repo create / fork / delete / edit` | DENY |
| `gh gist create` | DENY |
| `gh api` with `-X POST/PUT/PATCH/DELETE`, `--method POST/PUT/PATCH/DELETE`, or `-f`/`--field` | DENY |
| `curl` / `wget` with mutation flags (`-X POST`, `-d`, `--data`, `-F`) | DENY |
| GitHub MCP write tools (`create`, `update`, `delete`, `merge`, `add_comment`, `push`, `fork`, …) | DENY |
| `gh pr view`, `gh issue list`, `gh release list`, `gh api` GET, `git clone`, `git status`, `git log` | ALLOW |
| All `mcp__plugin_oss-contribution_github__` read tools | ALLOW |

The denial message explains that the plugin is draft-only and that the execution/submission plugin handles sending.

## Architecture Principles

### Draft-Only / Human-in-the-Loop

Every piece of outbound text (comments, claim messages, review replies) is a draft shown to you for review. The plugin will never post, comment, push, or send on your behalf. This is enforced at two levels: the command instructions (Step 5 in `commands/oss.md`) and the `PreToolUse` guardrail hook.

### Two-Plugin System

This plugin covers research and drafting. A separate execution/submission plugin (using `gh` CLI) handles the actual posting and pushing after you review and approve a draft. See [docs/concepts/two-plugin-system.md](docs/concepts/two-plugin-system.md) for the boundary.

### Read-Only GitHub Access

All GitHub data access is read-only. The MCP server is configured with a `repo:read`-scoped token. The `gh` CLI fallback uses only read subcommands. The guardrail hook provides a technical safety net on top of both.

## Documentation

- [docs/index.md](docs/index.md) — overview, component diagram, quick links
- [docs/getting-started/installation.md](docs/getting-started/installation.md) — install, auth, validation
- [docs/getting-started/quick-start.md](docs/getting-started/quick-start.md) — first `/oss` walkthrough
- [docs/guides/using-oss.md](docs/guides/using-oss.md) — `/oss` command in depth, all 8 scenarios
- [docs/guides/github-access.md](docs/guides/github-access.md) — MCP vs `gh` CLI, token setup, rate limits
- [docs/concepts/draft-only-guardrail.md](docs/concepts/draft-only-guardrail.md) — guardrail internals, full deny/allow matrix
- [docs/concepts/two-plugin-system.md](docs/concepts/two-plugin-system.md) — research half vs execution half
- [docs/reference/commands.md](docs/reference/commands.md) — `/oss` frontmatter and behavior steps
- [docs/reference/agents.md](docs/reference/agents.md) — `oss-researcher` and `oss-claim-analyst` specs
- [docs/reference/skills.md](docs/reference/skills.md) — all 5 skills with trigger phrases
- [docs/reference/hooks.md](docs/reference/hooks.md) — guardrail registration and deny/allow matrix
- [docs/reference/scenarios.md](docs/reference/scenarios.md) — canonical 8-scenario table with full detail
- [CHANGELOG.md](CHANGELOG.md) — version history

## License

MIT — see [LICENSE](LICENSE).
