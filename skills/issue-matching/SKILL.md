---
name: issue-matching
description: >
  This skill should be used when the user asks to find or match an issue or PR suited to them in a
  target open-source project. Trigger phrases include: "find an issue to work on", "match me to a
  task", "suggest a good first issue", "what can I contribute", "find a PR I can help with",
  "show me newcomer-friendly issues", and close variants. The skill runs after oss-researcher has
  gathered raw issue/PR data and applies the matching/ranking logic on top of it.
---

# Issue Matching

To match a contributor to the right issue or PR, follow this process:

## 1. Structured Intake

Ask the contributor these questions (as a short numbered list — not open-ended prose):

1. **Intent / goal** — What are you hoping to achieve? (e.g., fix a bug, add a feature, improve
   docs, help an in-progress PR land, general learning)
2. **Background skills** — What languages and frameworks are you comfortable with?
   (e.g., Python, Java/Scala, SQL, Kubernetes, Docker)
3. **Newcomer status** — Is this your first contribution to this project? (yes/no)
4. **Item type preference** — Issues only, PRs only, or both?
5. **Target project(s)** — Which project(s)? (e.g., apache/airflow, apache/spark — or "from my
   targets.yaml list")

Collect answers before running the match. Do not ask more than these 5 questions.

## 2. Data Gathering

Direct the `oss-researcher` agent (dispatched by the `/oss` command) to fetch:

- Open issues with labels: `good first issue`, `help wanted`, `bug`, `enhancement`, `docs`.
- Open PRs that are: stalled (no activity > 14 days), review-requested, or have failing CI.
- For each item: title, number, labels, assignees, language/path hints, last-updated timestamp,
  and direct URL.

## 3. Exclusion Filter

Exclude items that are:

- Closed or merged.
- Assigned to another contributor (issue has assignee; PR has an active author with recent commits).
- Labelled `not accepting contributions`, `wontfix`, `invalid`, or equivalent.
- Locked.

## 4. Heuristic Ranking

Score each remaining item. Higher is better:

| Signal | Score |
|--------|-------|
| `good first issue` or `help wanted` label AND newcomer=yes | +3 |
| `good first issue` or `help wanted` label (any contributor) | +2 |
| Label or file-path overlap with contributor's tech stack | +2 |
| Updated within last 14 days (active discussion) | +1 |
| Maintainer responded recently (comment in last 14 days) | +1 |
| PR: failing CI or review-requested (clear unblock opportunity) | +1 |
| PR: stalled > 30 days (needs someone to pick it up) | +1 |
| Item matches stated intent (bug/feature/docs/etc.) | +2 |

Sort by descending score. Return the **top 5–10 items** (or fewer if not enough qualify).

## 5. Output Format

Return a ranked shortlist. For each item:

```
## #<rank>. [Issue|PR] #<number>: <title>
- Link: <direct GitHub URL>
- Type: Issue / Pull Request
- Labels: <comma-separated>
- Last updated: <date>
- Why it fits: <1–2 sentence rationale linking to contributor's stated skills/goal>
```

End with a brief note if the shortlist is empty (no matching items found) and suggest broadening
the search (different labels, lower skill bar, different item type).

## 6. Notes

- Present issues and PRs in a single ranked list unless the user requested separate sections.
- For PRs, describe what kind of help is most useful: reviewing specific files, reproducing the
  change, offering a rebase, or taking over if stale.
- Do not surface items the contributor cannot realistically act on given their stated skills.
