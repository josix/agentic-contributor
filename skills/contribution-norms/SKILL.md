---
name: contribution-norms
description: >
  This skill should be used when the user asks to learn how to contribute to an open-source
  project, understand a project's governance, find out about CLA or DCO requirements, learn the
  correct commit or PR title format, or find out where project decisions happen. Trigger phrases
  include: "how do I contribute to X", "what are the contribution norms", "do I need to sign a
  CLA", "what's the DCO", "where do decisions happen", "what's the governance model",
  "CONTRIBUTING guide", "how should I format my PR title", "what mailing list should I use".
---

# Contribution Norms

To surface a project's contribution norms, follow these steps:

## 1. Locate Governing Documents

Direct the `oss-researcher` agent to fetch:

- `CONTRIBUTING.md` (or `CONTRIBUTING.rst`) at the repository root.
- `CODE_OF_CONDUCT.md` at the repository root.
- `.github/PULL_REQUEST_TEMPLATE.md`, `.github/PULL_REQUEST_TEMPLATE/` directory,
  `docs/pull_request_template.md`, and the `.github/ISSUE_TEMPLATE/` directory.
- AI policy candidates: `AI_POLICY.md`, `.github/AI_POLICY.md`, `docs/**/ai-policy*` (use
  `search_code` or `gh search code --repo <owner/repo> --filename ai-policy`), plus `.asf.yaml`
  and any `VOUCHED*` file at the root, `.github/`, or `docs/`.
- Any `DCO` file or sign-off instructions.
- The project's README for any "contributing" section.

Use `mcp__plugin_agentic-contributor_github__get_file_contents` for each, or fall back to
`gh api repos/<owner/repo>/contents/<path>` if the MCP token is absent.

## 2. Surface Legal Prerequisites

Report clearly:

- Whether an **ICLA** (Individual Contributor License Agreement) is required and how to sign it.
- Whether a **DCO sign-off** (`Signed-off-by:` in each commit) is required.
- What action the user must take before their first PR can be merged.

State what is missing rather than guessing — if the documents do not address ICLA/DCO, say so.

## 3. Describe Where Decisions Happen

Report which channel(s) the project uses:

- GitHub Issues / PRs (default for many modern projects).
- Apache JIRA (common in ASF projects — see `references/apache-governance.md`).
- dev@ mailing list (mandatory for major design decisions in ASF projects).
- Confluence / Wiki for design docs.
- Voting and lazy-consensus rules if applicable.

## 4. Commit and PR Title Conventions

Extract and present:

- Required PR title format (e.g., `[SPARK-NNNN][COMPONENT] Title` or `[AIRFLOW-x] Title`).
- Required commit message format.
- Any automated bot that checks title format (mention that a mismatch will fail CI).
- Whether issues must be linked in the PR description.

## 5. Code of Conduct

Note the project's code of conduct and link to it. For ASF projects, reference the
[ASF Code of Conduct](https://www.apache.org/foundation/policies/conduct).

## 6. Apache-Specific Notes

For projects under the Apache Software Foundation (e.g., apache/airflow, apache/spark), refer to
`references/apache-governance.md` for detailed notes on ICLA, DCO, lazy consensus / voting, JIRA
vs. GitHub workflows, and `[PROJECT-NNNN]`-style title conventions.

## 6b. AI & Contribution-Limit Policy

Detect the project's AI-use policy and contribution limits using the signal catalog and
classification rules in `references/ai-policy-signals.md`: dedicated AI policy files, AI sections
of CONTRIBUTING, PR-template disclosure checkboxes, AI co-author trailer rules, open-PR caps
(`.asf.yaml` `github.pull_requests.creation_cap`), vouch lists (`VOUCHED*`), AI rules for good
first issues, and issue-first rules. For each finding cite the source path or URL and a
`confidence` level. Findings are advisory and never block anything.

Report absence as "not found", never as "no policy". Add: "Policies on the project website,
Discourse, or mailing lists may not be visible here; check the project website." For an ASF
project, also note that `.asf.yaml` is where such caps live (see `references/apache-governance.md`).

## 7. State What's Missing

If any governance document cannot be found, explicitly state:

> "Could not locate <document name> in <owner/repo>. You may need to check the project's website
> or mailing list archives for this information."

Never fabricate norms, processes, or requirements. Accuracy matters more than completeness.

## Output Format

Return the briefing to the orchestrating `/oss` command. The orchestrator saves it to
`.oss-drafts/norms-<owner>-<repo>-norms-<UTC>.md` and shows the user the file path with the
notice: "Saved to `<path>`. Review and edit this report file as needed before using it."

Structure the briefing as:

```
## Contribution Norms: <owner/repo>

### Legal Prerequisites
<ICLA / DCO requirements and action items>

### Where to Engage
<GitHub / JIRA / mailing list — what each is used for>

### PR and Commit Conventions
<title format, commit format, bot checks, linking>

### Code of Conduct
<summary + link>

### AI Use Policy
<ai_policy, disclosure and mechanism, co-author trailer rule, AI on good first issues, issue-first
rule; each with source path/URL and confidence; "not found" where nothing was detected>

### Contribution Limits & Trust Gates
<open-PR cap and who it applies to, vouch requirement and file, each with source; "unknown" where
not found, with the reason>

### What Could Not Be Found
<list any missing documents>
```

## Policy Preflight (for other scenarios)

A lightweight pre-step used by `find`, `clarify`, `claim`, `engage`, `review-reply`, and `report`
(not `status`, `norms`, or `setup`; `norms` computes the full detail). It returns only the `policy`
block from `references/ai-policy-signals.md`, nothing else.

1. Fixed fetch list (about 6-10 GETs, no crawling): `AI_POLICY.md`, `.github/AI_POLICY.md`,
   `CONTRIBUTING.md`, the PR template paths listed in step 1, `.asf.yaml`, and a `VOUCHED*` lookup
   at root and `.github/`. Optionally one `search_code` call for `ai-policy`. Fetch a linked
   docs-site AI policy page only when CONTRIBUTING or the README links one.
2. Classify per `references/ai-policy-signals.md`. Every unfound field is `unknown`/`none-found`.
3. Return the block with `repo` set to `<owner>/<repo>`, the source and quote fields filled for any
   `issue_first` or `open_pr_cap` finding, and `fetched_at` set to the current UTC time.

The orchestrator caches the block in draft frontmatter and reuses it for 7 days.

## References

See `references/apache-governance.md` for Apache-specific governance details and
`references/ai-policy-signals.md` for the AI-policy signal catalog and `policy` block schema.
