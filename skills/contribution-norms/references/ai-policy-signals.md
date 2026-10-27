# AI Policy and Contribution-Limit Signals

Catalog of what to look for, how to classify it, and the fixed `policy` block that every draft
scenario carries. Detection is heuristic and file-based. A signal that is not found is reported as
`none-found` or `unknown`, never as "the project has no policy": policies often live on docs sites,
Discourse, or mailing lists that this plugin cannot see.

## Policy block (fixed shape)

```yaml
policy:
  repo: <owner/repo>                        # exact repository this block describes; required for cache reuse
  ai_policy: unknown|none-found|disclosure-required|restricted|banned   # restricted = e.g. no AI on good first issues; unknown = could not check
  ai_policy_sources: [<path-or-url>, ...]
  disclosure: required|recommended|none-found|unknown   # unknown = could not check
  disclosure_mechanism: pr-template-checkbox|statement|trailer|unknown
  coauthor_trailer_forbidden: true|false|unknown
  open_pr_cap: <int>|unknown
  open_pr_cap_applies_to: non-committers|all|unknown
  open_pr_cap_source: <path-or-url>|none-found   # file (and key or quoted line) the cap came from
  vouch_required: true|false|unknown
  vouch_file: <path>|none-found
  gfi_ai_ban: true|false|unknown
  issue_first: required|recommended|unknown
  issue_first_source: <path-or-url>|none-found   # file where the rule was found
  issue_first_quote: "<short verbatim quote>"|none-found   # the wording routing will quote to the user
  confidence: high|medium|low
  fetched_at: <ISO-8601 UTC>
```

Stance (D8):

- Every field defaults to `unknown` or `none-found`. It becomes `false`/`none` only when a source
  document says so explicitly.
- `none-found` means the sources were read and held no signal; `unknown` means they could not be
  checked (the preflight failed or the fetches errored). A failed preflight sets `ai_policy` and
  `disclosure` to `unknown`, never `none-found`, so consumers keep treating the policy as possibly
  present (AP9 stays active) and tell the user it could not be checked.
- `confidence: high` only when a dedicated policy file or an explicit config key was found.
  `medium` for CONTRIBUTING or template wording matched by keywords. `low` for a single weak hint.
- Findings are advisory. They never block a draft.
- Evidence is part of the block: `issue_first` and `open_pr_cap` are only set to a non-`unknown`
  value together with their `*_source` (and `issue_first_quote`). Routing reads these from the block
  (including cache hits, where no research runs), so it can quote the governing source.
- Always add: "Policies on the project website, Discourse, or mailing lists may not be visible here;
  check the project website."

## Signal catalog

| Signal | Where to look | Interpretation |
|---|---|---|
| Dedicated AI policy | `AI_POLICY.md`, `.github/AI_POLICY.md`, `docs/**/ai-policy*`, `docs/**/*ai*policy*` (find via `search_code`, or `gh search code --repo o/r --filename ai-policy`), plus README/CONTRIBUTING links to a docs-site page (WebFetch the link) | `ai_policy` + `ai_policy_sources`, `confidence: high` |
| CONTRIBUTING AI section | Headings or paragraphs matching `\b(AI\|LLM\|generative\|machine[- ]generated\|Copilot\|ChatGPT\|Claude)\b` | Classify by keyword (below) |
| PR-template disclosure | `.github/PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE/*.md`, `docs/pull_request_template.md`: checkbox lines `- [ ] ... (AI\|LLM\|generated\|assist)` | `disclosure: required`, `disclosure_mechanism: pr-template-checkbox` |
| Co-author trailer rule | CONTRIBUTING / AI policy text about `Co-authored-by` or AI attribution trailers | `coauthor_trailer_forbidden: true` only with explicit restrictive wording ("do not add", "must not", "prohibited", "not allowed", "remove") about the trailer. Text that requires or permits the trailer ("add a Co-authored-by", "please include") means `false`; mere mention without a rule stays `unknown` |
| Open-PR cap | `.asf.yaml` `github.pull_requests.creation_cap` (see Verified facts), plus CONTRIBUTING text like "no more than N open PRs" | `open_pr_cap`, `open_pr_cap_applies_to` |
| Vouch system | A `VOUCHED*` file at root, `.github/`, or `docs/` (see Verified facts), plus CONTRIBUTING mention of "vouch" | `vouch_required`, `vouch_file` |
| GFI AI ban | AI-policy or CONTRIBUTING text tying AI to `good first issue` | `gfi_ai_ban: true` only with explicit restrictive wording ("not accept", "must not", "no AI on good first issues"). Wording that permits or welcomes AI there means `false`; ambiguous wording stays `unknown` |
| Issue-first | CONTRIBUTING / AI policy: "open an issue first", "discuss before PR", "prefer an issue with a minimal reproducer", PR template "we generally require a GitHub issue" | `issue_first: required` (explicit "must/require") or `recommended` (prefer/encourage) |

### Classification keywords

Require an AI term and a policy verb in the **same paragraph** to avoid false positives (for
example an ML library whose CONTRIBUTING mentions "AI" as its product domain).

- `disclosure-required`: "must disclose", "all AI usage ... must be disclosed", "state the tool".
- `restricted`: "not accept", "not welcome", "will be closed", "may be closed", tied to a scope
  (first-timers, good first issues, unreviewed output).
- `banned`: "no AI", "prohibited", "not allowed" with no exemption.
- A policy that welcomes AI help but restricts unreviewed output (e.g. DataFusion) is
  `restricted` only for the restricted scope; say so in the finding and quote the source. Pick the
  closest value and do not over-classify.
- `issue_first: required` needs explicit "must/require/before opening a PR" wording.

## Verified facts (read-only, verified 2026-10-21)

Verified with `gh api` GET requests against the live repositories.

1. **DataFusion open-PR cap.** `.asf.yaml` at the repository root contains:

   ```yaml
   github:
     pull_requests:
       creation_cap:
         enabled: true
         max_open_pull_requests: 3
   ```

   with the comment "Limit open pull requests per user without write access."
   Key path: `github.pull_requests.creation_cap.max_open_pull_requests` (gated by
   `creation_cap.enabled`). Source: https://github.com/apache/datafusion/blob/main/.asf.yaml,
   introduced by https://github.com/apache/datafusion/pull/25973 ("ci: Enforce PR limit to 3 for
   non-committers", merged). Other ASF projects may or may not use the same key; match
   `creation_cap` / `max_open_pull_requests` generically and report the source path.
2. **Ghostty vouch list.** The file is `.github/VOUCHED.td` (not at the repository root).
   Format: one handle per line, no `@`, sorted alphabetically; optional `platform:username`;
   a leading `-` marks a denounced user (`-username`); a space then a comment is allowed.
   Maintainers vouch with `!vouch` and denounce with `!denounce` in a discussion. CONTRIBUTING.md
   links it and says unvouched users' PRs are closed. Sources:
   https://github.com/ghostty-org/ghostty/blob/main/.github/VOUCHED.td and
   https://github.com/ghostty-org/ghostty/blob/main/CONTRIBUTING.md. Detection stays generic
   (`VOUCHED*` at root, `.github/`, `docs/`) because other projects may name it differently.
3. **Ghostty AI policy.** `AI_POLICY.md` at the repository root: all AI usage must be disclosed
   (tool and extent), the human must fully understand the code, and "bad AI drivers will be
   denounced". Source: https://github.com/ghostty-org/ghostty/blob/main/AI_POLICY.md.
4. **DataFusion AI policy.** Generated from the in-repo file
   `docs/source/contributor-guide/ai-policy.md`; the published page
   https://datafusion.apache.org/contributor-guide/ai-policy.html returns HTTP 200. It welcomes
   AI-assisted PRs but not unreviewed "AI dumps", requires the author to understand the PR
   end-to-end, warns that many PRs in a short time by a first-time contributor may be closed as
   spam, and recommends "a high-quality issue with a clear problem statement and a minimal,
   reproducible example" as a better way to contribute. DataFusion's PR template says "We
   generally require a GitHub issue to be filed for all bug fixes and enhancements".
   Source: https://github.com/apache/datafusion/blob/main/docs/source/contributor-guide/ai-policy.md.

## Not verified (do not hardcode)

These were cited in the planning brief but not verified against the live repositories in this
release. Treat as examples of patterns to look for, not as facts:

- Kubernetes: disclosure plus a ban on AI `Co-authored-by` trailers.
- earthaccess (`nsidc/earthaccess`): a PR-template disclosure checkbox.
- LLVM and Mozilla: wording tying AI use to good first issues.

If detection finds none of these in a repository, report `none-found`; do not infer from this list.
