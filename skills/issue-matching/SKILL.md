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

1. **Intent / goal** — What are you hoping to achieve? (e.g., fix a bug, add a feature,
   reproduce/triage bugs, review PRs, improve docs/tests, help an in-progress PR land, general
   learning)
2. **Background skills** — What languages and frameworks are you comfortable with?
   (e.g., Python, Java/Scala, SQL, Kubernetes, Docker)
3. **Your relationship with this project** — (a) I use it (how? which features/areas), (b) I've
   contributed before, or (c) neither. (Merges newcomer status and usage.)
4. **Item type preference** — Issues only, PRs only, or both?
5. **Target project(s)** — Which project(s)? (e.g., apache/airflow, apache/spark — or "from my
   targets.yaml list", read from `${CLAUDE_PLUGIN_ROOT}/config/targets.yaml`)

Collect answers before running the match. Do not ask more than these 5 questions. The advisory
`contributor-readiness` check (see `skills/contributor-readiness/SKILL.md`) runs alongside, unless
the user says "skip readiness"; it adds no question. "Newcomer" below means answer (c), or readiness
tier 5.

## 2. Data Gathering

Direct the `oss-researcher` agent (dispatched by the `/oss` command) to fetch:

- Open issues with labels: `good first issue`, `help wanted`, `bug`, `enhancement`, `docs`.
- Triage-needed issues: labels `needs-repro`, `needs reproduction`, `needs triage`, `triage`,
  `question`, `waiting-for-reporter`, `cannot reproduce`, and recently filed un-triaged issues
  (no labels, under 14 days old).
- Open PRs with a review requested.
- Open PRs that are: stalled (no activity > 14 days), review-requested, or have failing CI.
- For each item: title, number, labels, assignees, language/path hints, last-updated timestamp,
  and direct URL.

## 3. Exclusion Filter

Exclude items that are:

- Closed or merged.
- Assigned to another contributor (issue has assignee; PR has an active author with recent commits).
- Labelled `not accepting contributions`, `wontfix`, `invalid`, or equivalent.
- Locked.

### Policy-reserved bucket

When the `policy` block has `gfi_ai_ban: true`, remove `good first issue` items from the ranking and
list them in a separate, unranked footer (section 5). Do not hide them: the footer is the
information. `gfi_ai_ban: unknown` or `false` leaves GFIs in the ranking.

## 4. Heuristic Ranking

Score each remaining item. Higher is better:

| Signal | Score |
|--------|-------|
| `good first issue` or `help wanted` label AND newcomer=yes (only when `gfi_ai_ban` is not `true`) | +3 |
| `good first issue` or `help wanted` label (any contributor; only when `gfi_ai_ban` is not `true`) | +2 |
| Area or feature the contributor said they use | +3 |
| Repro / triage / review work type AND readiness tier 4-5 (or 0 merged PRs) | +2 |
| New-code item AND open PRs >= `open_pr_cap` (review/repro items are not penalised) | -2 |
| Maintainer-labelled `help wanted` with a clear spec | +1 |
| Label or file-path overlap with contributor's tech stack | +2 |
| Updated within last 14 days (active discussion) | +1 |
| Maintainer responded recently (comment in last 14 days) | +1 |
| PR: failing CI or review-requested (clear unblock opportunity) | +1 |
| PR: stalled > 30 days (needs someone to pick it up) | +1 |
| Item matches stated intent (bug/feature/docs/etc.) | +2 |

Sort by descending score. Return the **top 5–10 items** (or fewer if not enough qualify). For a
contributor with 0 merged PRs in the project, make sure the top 3 include at least one repro,
triage, or review item when such items exist: they build the track record maintainers prioritise.

## 5. Output Format

Return the ranked shortlist to the orchestrating `/oss` command. The orchestrator saves it to
`.oss-drafts/find-<owner>-<repo>-find-<UTC>.md` and shows the user the file path with the notice:
"Saved to `<path>`. Review and edit this report file as needed before using it."

For each item:

```
## #<rank>. [Issue|PR] #<number>: <title>
- Link: <direct GitHub URL>
- Type: Issue / Pull Request
- Labels: <comma-separated>
- Last updated: <date>
- Work type: code | repro | triage | review | docs
- Track-record value: <1 line: what this does for your standing with the maintainers>
- Why it fits: <1–2 sentence rationale linking to contributor's stated skills/goal>
```

At the top of the file, a **Readiness summary** (Private notes: login used, open PRs vs cap, tier,
how to move up; omitted on "skip readiness"). If the user is at the open-PR cap, say so there and
point to review/repro items. Wording is about how maintainers see the contribution, never about the
contributor's worth.

At the bottom, when `gfi_ai_ban: true` and good first issues were removed, a footer:

```
## Policy-reserved (unranked)
Reserved for unassisted newcomers. Only take these if you will do them without AI code generation.
Source: <policy.ai_policy_sources>
- #<number>: <title> (<url>)
```

End with a brief note if the shortlist is empty (no matching items found) and suggest broadening
the search (different labels, lower skill bar, different item type).

## 6. Notes

- Present issues and PRs in a single ranked list unless the user requested separate sections.
- For PRs, describe what kind of help is most useful: reviewing specific files, reproducing the
  change, offering a rebase, or taking over if stale.
- Do not surface items the contributor cannot realistically act on given their stated skills.
