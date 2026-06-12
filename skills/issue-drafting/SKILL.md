---
name: issue-drafting
description: >
  This skill should be used when the user asks to draft a bug report, file a new issue, report a
  bug in a project, draft a feature request, propose a feature, write up an issue for a project,
  or open an issue about a problem or improvement. Trigger phrases include: "draft a bug report",
  "file a new issue", "report a bug in X", "draft a feature request", "propose a feature",
  "write up an issue for X", "open an issue about". All output from this skill is a DRAFT for the
  user's review — never posted automatically.
---

# Issue Drafting

Refer to `skills/smart-questions/references/smart-questions-principles.md` for the full principle
set (research-first, be specific, cite source, concise) before drafting any issue body.

## DRAFT-ONLY Contract

Every issue draft this skill produces is a **DRAFT**. The contract is:

1. Return the complete draft (suggested title, suggested labels, and body) to the orchestrating
   `/oss` command. The orchestrator saves it to a
   `.oss-drafts/report-<owner>-<repo>-<item>-<UTC>.md` file using the Write tool, then presents it
   to the user.
2. After saving, the orchestrator adds the mandatory notice:
   > **DRAFT — saved to `<path>`. Review and edit this file before sending.**
   > This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin.
3. NEVER call any tool that posts, comments, pushes, or creates a GitHub resource.
4. The user may edit the saved file or cancel the draft before deciding to send it through the
   execution plugin.

This contract applies to every procedure below without exception.

## Procedure 1 — Pre-flight (always run before drafting)

Run the following steps before producing any draft content. Complete all three steps in parallel
where possible.

### a. Duplicate Search

Direct `oss-researcher` to run `search_issues` against the target repo with symptom keywords from
the user's description. Search **both open and closed** issues to catch resolved duplicates that
may cover the same ground.

- Surface the top 3–5 candidate duplicates as a numbered list with issue number, title, status
  (open/closed), and direct link.
- Assess similarity: for each candidate, note whether it is an exact match, a partial overlap, or
  only loosely related.
- If a **strong duplicate** exists (exact or near-exact match, still open or recently closed):
  recommend the user **comment on the existing issue** rather than file a new one, and suggest
  routing to the **clarify** or **engage** scenario. Do not proceed to drafting a new issue unless
  the user confirms they want to continue.
- If only partial overlaps or unrelated results exist: note them in the draft under "Related
  Issues" and proceed.

### b. Template Fetch

Direct `oss-researcher` to fetch:

- The `.github/ISSUE_TEMPLATE/` directory listing (to discover available templates).
- Each template file found (`.md`, `.yml`, `.yaml`).
- `.github/ISSUE_TEMPLATE/config.yml` (for `blank_issues_enabled` and `contact_links`).

Apply the following routing logic:

- If `config.yml` sets `blank_issues_enabled: false` and lists a `contact_links` URL for the issue
  type (e.g., a Discussions link for questions, a security policy for vulnerability reports): warn
  the user that the repo redirects this issue type elsewhere and show the relevant link. Proceed
  only if the user confirms.
- If the template directory contains a security-report template or `SECURITY.md` exists and the
  issue is a potential vulnerability: warn the user that security reports belong in
  `SECURITY.md` / the private disclosure process, not a public issue. Do not draft a public issue
  for security vulnerabilities without explicit user confirmation.

### c. Convention Extraction

Use the fetched template metadata and any available `contribution-norms` output (if already gathered in a prior run of the **norms** scenario — otherwise, infer conventions from the templates alone) to identify:

- **Title format:** component prefixes (e.g., `[COMPONENT]`, `[SPARK-NNNN]`), type prefixes (e.g.,
  `bug:`, `feat:`), or other required patterns.
- **Label conventions:** which labels the project uses for bugs (e.g., `bug`, `type:bug`) and
  feature requests (e.g., `enhancement`, `type:feature`, `feature-request`), and any
  component-level labels.
- **Monorepo handling:** if the repo is a monorepo with multiple components, prompt the user to
  pick a component when the symptom is ambiguous rather than guessing. Present the available
  component labels or prefixes and ask the user which applies before drafting.

## Procedure 2 — Bug Report

After Pre-flight completes, draft a bug report with the following evidence checklist. Map each
item onto the corresponding section in the fetched template when one exists; use the built-in
structure when no template is found.

**Evidence checklist:**

- **Environment / version info** — OS, language runtime version, package version, relevant
  dependency versions. If the user has not provided this, mark the field `TODO: add environment
  details (OS, version of <package>, runtime version)`.
- **Minimal reproducible example** — the smallest code snippet or sequence of steps that reliably
  triggers the bug. If missing, mark `TODO: provide a minimal reproducible example`.
- **Exact steps to reproduce** — numbered list, starting from a clean state.
- **Expected behavior** — what should happen.
- **Actual behavior** — what actually happens (include exact error output).
- **Error logs / stack traces** — include verbatim in a fenced code block (` ```text `). If none
  provided, mark `TODO: attach error log or stack trace if available`.
- **File:line code references** — cite the specific file and line number in the repo source that
  is most likely the root cause or that the bug manifests in, if identifiable from the symptom
  description.
- **Related issue / PR links** — list any related items found in the duplicate search.

**Missing evidence rule:** Mark required-but-missing fields with `TODO:` placeholders. Never
fabricate environment details, version numbers, stack traces, or reproduction steps.

## Procedure 3 — Feature Request

After Pre-flight completes, draft a feature request with the following structure. Map each item
onto the corresponding section in the fetched template when one exists; use the built-in structure
when no template is found.

**Structure:**

- **Problem statement / motivation** — describe the current limitation or pain point. Be specific:
  what can you not do today, and why does it matter? Cite a concrete use case.
- **Proposed solution** — describe the desired behavior or new capability. Be as specific as
  possible; a code sketch or API design is welcome if the user provides one.
- **Alternatives considered** — what workarounds or alternative approaches exist today? Why are
  they insufficient?
- **Scope / impact** — who is affected (all users, a specific integration, a specific platform)?
  Is this a breaking change?
- **File:line references to current behavior** — cite the specific file and line in the repo that
  would need to change, if identifiable.
- **Related issues / discussions** — list related items found in the duplicate search, plus any
  linked discussion threads.

**Missing evidence rule:** Mark required-but-missing fields with `TODO:` placeholders. Never
fabricate motivation, user counts, or design details.

## Template-Application Logic

Apply one of the following cases based on what the template fetch returns:

### (a) Markdown template (`.md` file)

Fill the template's sections in order. Strip HTML comment blocks (`<!-- ... -->`). Preserve all
section headings. Use `TODO:` placeholders for any required information the user has not provided.

### (b) YAML issue form (`.yml` / `.yaml` file with a `body:` key)

Map the drafted content to each form field by the field's `label` or `id`. Flag any field marked
`required: true` that has not been filled — mark it prominently with `TODO: [required field] —
<label>`. Preserve `validations` context (e.g., `required: true`) as a comment in the draft so
the user knows which fields cannot be left blank.

### (c) Multiple templates

Pick the template that matches the issue type:

- For bug reports: prefer a template whose filename or label contains "bug".
- For feature requests: prefer a template whose filename or label contains "feature",
  "enhancement", or "request".

Tell the user which template was chosen and why. If no type-specific template exists, use the
default template or fall back to (d).

### (d) No template

Use the built-in structure from Procedure 2 or 3 and note in the draft:

> _No issue template found in this repo; used a standard structure._

## Output Format

Return the complete draft to the orchestrator for saving and the mandatory draft-tier notice. The
draft must include all three of:

1. **Suggested title** — one line, following the title convention from Pre-flight step (c). If no
   convention was found, use a concise, descriptive title.
2. **Suggested labels** — a comma-separated list of label names following the project's label
   conventions. If no convention was found, suggest `bug` or `enhancement` as appropriate.
3. **Body** — the full issue body, ready to paste, with `TODO:` placeholders for any missing
   required fields.

Format the output as:

```markdown
## Suggested Title

<title here>

## Suggested Labels

<label1>, <label2>

## Issue Body

<full body here>
```

## References

See `skills/smart-questions/references/smart-questions-principles.md` for the full principle list
(research-first, be specific, cite source, concise) and good/bad examples.
