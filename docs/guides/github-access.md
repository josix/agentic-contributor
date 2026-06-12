# GitHub Access

How the plugin reads GitHub data: the MCP server, the `gh` CLI fallback, when each is used, and how to configure them.

## Two Access Paths

The plugin always uses read-only GitHub access. There are two paths, and subagents choose between them automatically based on whether `GITHUB_MCP_TOKEN` is set.

| Path | When used | Tools |
|---|---|---|
| GitHub MCP server | `GITHUB_MCP_TOKEN` is set | `mcp__plugin_agentic-contributor_github__*` read tools |
| `gh` CLI fallback | `GITHUB_MCP_TOKEN` not set | `gh issue list`, `gh pr view`, `gh api` GET, etc. |

## GitHub MCP Server

The MCP server is configured in `.mcp.json` at the plugin root:

```json
{
  "github": {
    "type": "http",
    "url": "https://api.githubcopilot.com/mcp/",
    "headers": { "Authorization": "Bearer ${GITHUB_MCP_TOKEN}" }
  }
}
```

When the token is present, all `mcp__plugin_agentic-contributor_github__*` read tools are available to subagents. The MCP server returns structured JSON data without shell invocations — it is faster and avoids shell-quoting edge cases.

Read tools used by `oss-researcher`:

| MCP tool | Purpose |
|---|---|
| `list_issues` / `search_issues` | Issue queries |
| `get_pull_request` / `list_pull_requests` | PR data |
| `get_file_contents` | CONTRIBUTING, CODE_OF_CONDUCT, etc. |
| `list_releases` | Release and tag history |
| `search_repositories` | Repository metadata |

The guardrail hook (`guard-outbound.sh`) checks the MCP tool name suffix against a list of write verbs and denies any tool ending in `create`, `update`, `delete`, `merge`, `add_comment`, `push`, `fork`, `assign`, and related verbs. All other MCP tools are allowed.

### Token Setup

```bash
export GITHUB_MCP_TOKEN=ghp_your_token_here
```

Use a personal access token (classic) with **`repo:read`** scope, or a fine-grained token with read-only repository permissions. No write permissions are needed or used.

Persist across sessions by adding the export to your shell profile.

## `gh` CLI Fallback

When `GITHUB_MCP_TOKEN` is absent, subagents run `gh auth status` first to confirm authentication, then use read-only `gh` commands:

```bash
gh issue list   --repo <owner/repo> --limit 20 --json number,title,labels,assignees,updatedAt,url
gh pr list      --repo <owner/repo> --limit 20 --json number,title,state,reviewDecision,updatedAt,url
gh release list --repo <owner/repo> --limit 10
gh pr view      <number> --repo <owner/repo> --json body,files,reviews,comments,statusCheckRollup
gh api          repos/<owner/repo>/contents/CONTRIBUTING.md
```

Authenticate once with:

```bash
gh auth login
```

The fallback path is fully functional for all 9 scenarios. It is slightly slower than MCP because each command spawns a subprocess, but produces equivalent results.

## Pagination

Both paths paginate in small batches (10–20 items per request). Subagents never fetch all items in a single call for large repositories. If a 429 (rate-limit) or secondary rate-limit error occurs, the subagent waits and retries once, then reports the limitation rather than failing silently.

## Rate Limits

- **Authenticated requests (MCP or `gh`):** GitHub's standard rate limit of 5,000 requests per hour per token applies.
- **Unauthenticated requests:** 60 requests per hour — avoid by always authenticating.
- **Secondary rate limits:** Triggered by high request frequency in a short window; the subagents respect these by backing off and retrying once.

If you hit rate limits during a session, the subagent will report the error and how many items were fetched before the limit was reached.

## Non-GitHub Sources

GitHub-hosted repositories are the only data source fetched directly in v0.1. Non-GitHub sources — Apache JIRA, dev@ mailing lists, Confluence wikis — are referenced in `skills/contribution-norms/references/apache-governance.md` as links but are not fetched.

---

[Back to docs index](../index.md) | Related: [Draft-Only Guardrail](../concepts/draft-only-guardrail.md) | [Installation](../getting-started/installation.md) | [Hooks Reference](../reference/hooks.md)
