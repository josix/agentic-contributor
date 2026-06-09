# Apache Governance Notes

Reference for surfacing contribution norms specific to Apache Software Foundation (ASF) projects
such as apache/airflow and apache/spark.

## Legal Prerequisites

### Apache Individual Contributor License Agreement (ICLA)

- **Required** before a first patch can be committed to most Apache projects.
- The ICLA grants the ASF the rights to distribute your contribution.
- Signing process: download from https://www.apache.org/licenses/icla.pdf, sign (digitally or
  physically), and email to secretary@apache.org.
- First-time contributors should allow a few days for processing.
- Check the project's CONTRIBUTING guide for project-specific instructions — some projects
  (including Airflow) link directly to the ICLA page.

### DCO (Developer Certificate of Origin)

- Some ASF projects (especially those with GitHub-first workflows) also require a DCO sign-off.
- Add `Signed-off-by: Your Name <you@example.com>` to each commit message.
- With Git: `git commit --signoff` (or `-s`).
- Without this sign-off, automated CI checks may block the PR.

---

## Where Decisions Happen

Apache projects use a layered decision-making model. Know which channel to use:

| Channel | Purpose |
|---------|---------|
| **GitHub Issues** | Bug reports, feature requests, task tracking (newer projects like Airflow) |
| **Apache JIRA** (`issues.apache.org/jira`) | Older or more process-heavy projects (e.g., Spark still uses JIRA for some workflows) |
| **dev@ mailing list** | Design discussions, major decisions, votes, CLA/licensing questions |
| **user@ mailing list** | End-user questions (not for contribution discussions) |
| **GitHub PRs** | Code review, implementation discussion |
| **Confluence / Wiki** | Long-form design docs, meeting notes |

Check the project's CONTRIBUTING guide to confirm which channel is canonical. For Airflow, GitHub
is primary; for Spark, JIRA and the spark-dev mailing list are still authoritative.

---

## Lazy Consensus and Voting

- ASF decisions follow **lazy consensus**: a proposal is accepted if no objections are raised
  within a specified time window (typically 72 hours for minor changes).
- **Voting** uses +1 (approve), 0 (neutral/abstain), -1 (veto with reason required).
- PMC (Project Management Committee) members have binding votes; committers and community
  members have advisory votes.
- For significant changes (new features, API breaks, release decisions), a vote on the dev@ list
  may be required.

---

## Issue/PR Title Conventions

### Apache Airflow

- Use the format: `[AIRFLOW-NNNN] Brief description` for issues tracked in JIRA (legacy).
  Newer issues on GitHub often drop the JIRA prefix but may still require a linked JIRA ticket.
- For GitHub-native issues: follow the PR template in `.github/PULL_REQUEST_TEMPLATE.md`.
- PR titles should be concise and imperative: "Add X", "Fix Y", "Refactor Z".
- Link the related issue in the PR description: `Closes #NNNN`.

### Apache Spark

- Historically uses JIRA: `[SPARK-NNNN][COMPONENT] Brief description`.
  Example: `[SPARK-12345][SQL] Fix NPE in DataFrame join when schema is null`
- Component tags: `[CORE]`, `[SQL]`, `[MLlib]`, `[Streaming]`, `[PySpark]`, `[Docs]`, etc.
- PR title format must match the JIRA ticket title; the Spark bot will cross-link them.
- DCO sign-off is typically required (check current CONTRIBUTING.md).

---

## Code of Conduct

All ASF projects are governed by the [ASF Code of Conduct](https://www.apache.org/foundation/policies/conduct).
Contributions must adhere to this; contributors who violate it may be banned from the project.

---

## Commit Sign-off Reminder

For projects requiring DCO:

```bash
git commit --signoff -m "[AIRFLOW-1234] Fix DAG parsing timeout"
# Produces: Signed-off-by: Your Name <your@email.com>
```

For ICLA-only projects, no commit flag is required, but the ICLA must be on file before your PR
can be merged.

---

## Key Links

| Resource | URL |
|----------|-----|
| Apache ICLA | https://www.apache.org/licenses/icla.pdf |
| ASF Code of Conduct | https://www.apache.org/foundation/policies/conduct |
| Airflow Contributing Guide | https://github.com/apache/airflow/blob/main/CONTRIBUTING.rst |
| Spark Contributing Guide | https://github.com/apache/spark/blob/master/CONTRIBUTING.md |
| Airflow dev@ archives | https://lists.apache.org/list.html?dev@airflow.apache.org |
| Spark dev@ archives | https://lists.apache.org/list.html?dev@spark.apache.org |
| Apache JIRA (Spark) | https://issues.apache.org/jira/projects/SPARK |
