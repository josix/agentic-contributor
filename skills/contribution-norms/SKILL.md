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
- `.github/PULL_REQUEST_TEMPLATE.md` and `.github/ISSUE_TEMPLATE/` directory.
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

## 7. State What's Missing

If any governance document cannot be found, explicitly state:

> "Could not locate <document name> in <owner/repo>. You may need to check the project's website
> or mailing list archives for this information."

Never fabricate norms, processes, or requirements. Accuracy matters more than completeness.

## Output Format

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

### What Could Not Be Found
<list any missing documents>
```

## References

See `references/apache-governance.md` for Apache-specific governance details.
