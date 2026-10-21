---
name: contributor-readiness
description: >
  This skill should be used by the /oss command in the claim and find scenarios to give the
  contributor a private, advisory self-check of how a project's maintainers are likely to see their
  contribution today: open PRs versus the project's cap, prior merged PRs, account age, vouch
  status, and whether they use the project. Trigger phrases include "am I ready to contribute",
  "will maintainers prioritise my PR", "check my readiness", "how do I build a track record", and
  close variants. Runs by default in claim and find; the user can opt out with "skip readiness".
---

# Contributor Readiness

Maintainers of busy projects prioritise review time roughly in this order: actual users, prior
contributors, contributors endorsed by a committer, established accounts, then newcomers. This skill
shows the contributor where they stand today and how to move up. It is **advisory**: it never
blocks, delays, or changes a draft.

The data is gathered by `oss-researcher` with scenario key `readiness` (dispatched in parallel with
the normal fetch). This skill turns the result into the output below.

## 1. Login Resolution

Use the first that applies:

1. Explicit in the request (`as @login`).
2. `contributor.github_login` in `config/targets.yaml` (local-only).
3. The authenticated identity: MCP `get_me`, falling back to `gh api user --jq .login`.

Always print the login used, and record it in the draft frontmatter as `readiness_login`, so a wrong
identity (for example a bot token) is visible and can be overridden. Do not ask an extra clarifying
question for this. If no login can be resolved, skip the check and say so in one line.

## 2. Signals

All reads are GETs, for the contributor's own login only. Spend about 5 calls (search API limit is
30/min): use `per_page=1` and read `total_count` where only a count is needed.

| Signal | MCP (preferred) | gh fallback |
|---|---|---|
| Open PRs in repo vs cap | `search_pull_requests` `repo:o/r author:<login> is:open` | `gh pr list --repo o/r --author <login> --state open --json number,title,createdAt` |
| Merged PRs in repo | `search_pull_requests` `repo:o/r author:<login> is:merged` | `gh search prs --repo o/r --author <login> --merged --limit 20 --json number,closedAt` |
| Prior issues/reviews/comments in repo | `search_issues` `repo:o/r involves:<login>` | `gh api 'search/issues?q=repo:o/r+involves:<login>&per_page=1' --jq .total_count` |
| `author_association` | from the items above (`CONTRIBUTOR`, `COLLABORATOR`, `MEMBER`, `FIRST_TIME_CONTRIBUTOR`, `NONE`) | same |
| Account age and activity elsewhere | `get_me` (own login) | `gh api users/<login> --jq '{created_at,public_repos}'`; `gh api 'search/issues?q=author:<login>+type:pr+is:merged&per_page=1' --jq .total_count` |
| Vouch status | `get_file_contents` on `policy.vouch_file`, look for the login (vouched / denounced / absent) | `gh api repos/o/r/contents/<vouch_file>` |
| Uses the project | self-reported in the find intake, or `contributor.uses` in `targets.yaml` | none |

`open_pr_cap`, `vouch_required`, and `vouch_file` come from the `policy` block (Step 3a policy
preflight). When they are `unknown`, say so; do not assume "no cap" or "no vouch". A missing signal
is `unknown`, never `0` or `false`.

## 3. Tier Mapping

Show as "how maintainers are likely to see your PR today". Pick the highest that applies:

1. **Actual user**: you use the project (self-reported or `contributor.uses`).
2. **Prior contributor**: at least one merged PR in the repo, or `author_association` of
   `CONTRIBUTOR` or higher.
3. **Endorsed**: vouched in the project's vouch file, or you report a committer endorsement.
4. **Established account**: account over 1 year old with public activity elsewhere.
5. **New to the project**.

Tiers 4 and 5 are the "build a track record" tiers; find uses them to boost repro, triage, and
review work. If the contributor is a prior contributor or committer (`COLLABORATOR`/`MEMBER`), say
so and do not give newcomer advice.

## 4. Advisory Output Template

Goes in **Private notes only** (claim) or the "Readiness summary" at the top of the report file
(find). It never appears inside an `oss:send` block.

```markdown
### Readiness (advisory, private)
Login used: @<login> (from <arguments|config|authenticated account>). Wrong account? Say "as @other".

| Signal | Value |
|---|---|
| Open PRs in <owner/repo> | <N> of cap <cap|unknown> |
| Merged PRs in repo | <N|unknown> |
| Relationship to repo | <author_association or unknown> |
| Account age | <years> |
| Vouch | <vouched|not listed|denounced|not required|unknown> |

**How maintainers are likely to see your PR today:** tier <n>, <name>.
**How to move up:** <1-3 concrete steps from section 6>
```

Warnings (lead the readiness block; the draft is still produced):

- `open_prs >= open_pr_cap`: "At the project's open-PR cap (<N>/<cap>). Consider finishing
  <#A>/<#B> first; the project may close or hold new PRs until then."
- `vouch_required: true` and the login is not vouched: "This project closes PRs from unvouched
  contributors. See <vouch path>. Taking part first (reviewing, confirming bugs, asking a
  clarifying question) is how contributors usually earn a vouch."

Frontmatter: `readiness_login: <login>` and
`readiness: {open_prs, cap, merged_prs_in_repo, account_age_days, vouch_status, tier}` with
`unknown` for anything not read.

## 5. Wording Rules

- Talk about how maintainers see the contribution, never about the contributor's worth or ability.
  Say "projects like this prioritise contributors with a track record; here is how to build one",
  never "you are not trusted/qualified".
- Every gap comes with a constructive next step.
- State uncertainty plainly: "not found" is not "none".
- Never discourage; never block. The draft is always produced.

## 6. How to Move Up (next steps)

- Review or test an open PR; confirm a bug report with a minimal reproducer.
- Triage: reproduce, add version info, narrow the cause on an un-triaged issue.
- Improve docs or tests in an area you use.
- Finish or close your open PRs before starting another (when at the cap).
- Take part in discussion so a committer can vouch for you (when vouching is used).

In find, these map to the `repro`, `triage`, `review`, and `docs` work types.

## 7. Privacy and Opt-Out

- Public data only, and only for the contributor's own login. Never look up other users.
- Nothing is stored outside `.oss-drafts/`; there is no cache of the user's activity elsewhere.
- Opt-out: if the request contains "skip readiness", do not dispatch the readiness read and omit
  the section and the `readiness*` frontmatter.
