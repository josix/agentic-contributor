# Installation

Install, authenticate, and validate the `agentic-contributor` plugin.

## Install and Enable

### Option A — Local directory (development / try-it-out)

```bash
git clone https://github.com/josix/agentic-contributor.git ~/agentic-contributor
claude --plugin-dir ~/agentic-contributor
```

### Option B — Marketplace

```
/plugin marketplace add josix/agentic-contributor
/plugin install agentic-contributor@josix-plugins
```

After installation, enable the plugin if it is not already active:

```
/plugins enable agentic-contributor
```

## GitHub Authentication

The plugin needs read access to GitHub. Two paths are available.

### Path 1 — GitHub MCP Server (recommended)

Create a GitHub personal access token with **`repo:read`** (or the fine-grained equivalent read-only permission for repositories) and export it:

```bash
export GITHUB_MCP_TOKEN=ghp_your_token_here
```

The MCP server is configured in `.mcp.json` at the plugin root. When the token is present, subagents prefer `mcp__plugin_agentic-contributor_github__*` read tools, which return structured data without shell invocation.

To persist the variable across sessions, add it to your shell profile (`.zshrc`, `.bashrc`, or equivalent).

### Path 2 — `gh` CLI Fallback

If `GITHUB_MCP_TOKEN` is not set, subagents fall back to the `gh` CLI automatically. Before using the fallback path, authenticate once:

```bash
gh auth login
```

Follow the prompts to complete browser-based authentication. Confirm you are logged in:

```bash
gh auth status
```

The fallback path is fully functional for all 8 scenarios; it uses `gh issue list`, `gh pr view`, `gh api`, and related read-only commands.

## Restart Required

> **Important:** Hooks and the MCP server are registered at session start. After installing or enabling the plugin, **restart your Claude Code session** for the `PreToolUse` guardrail hook and the GitHub MCP server to become active.

## Validating Your Installation

Run these checks before your first `/oss` command:

```bash
# 1. plugin.json is valid JSON and version matches marketplace.json
jq .version /path/to/agentic-contributor/.claude-plugin/plugin.json
jq '.plugins[0].version' /path/to/agentic-contributor/.claude-plugin/marketplace.json
# Both should print "0.1.0"

# 2. marketplace.json parses cleanly
jq . /path/to/agentic-contributor/.claude-plugin/marketplace.json

# 3. Guardrail script is executable and has valid syntax
bash -n /path/to/agentic-contributor/hooks/scripts/guard-outbound.sh && echo "syntax OK"

# 4. gh CLI fallback (if not using MCP)
gh auth status
```

If the `/oss` command appears when you type `/oss` in Claude Code and the checks above pass, the plugin is ready.

---

[Back to docs index](../index.md) | Next: [Quick Start](quick-start.md)
