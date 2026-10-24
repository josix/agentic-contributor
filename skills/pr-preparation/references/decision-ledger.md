# Decision Ledger (track mode)

Single source of truth for the track ledger. `hooks/scripts/track-checkpoint.sh` implements the
"Grep/awk contract" below; `pr-preparation` (Procedure 0), `change-debrief`, and the docs cite this
file instead of restating the format.

The ledger is **private notes only**. It is never a send block, never PR text, and never pasted
into anything sendable. It records the contributor's decisions while an agent codes; it never
records prompts, transcripts, keystrokes, or file contents.

## 1. Paths

- Ledger: `<root>/.oss-drafts/track-<owner>-<repo>-<item>-<UTC>.md`. `<owner>-<repo>` comes from
  `git remote -v` (upstream, else origin); with no GitHub remote use `local-<basename of root>`.
  `item` is `issueN` or `task`. UTC is `YYYYMMDDThhmmssZ`.
- Pointer: `<gitdir>/agentic-contributor/track-active`, where `<gitdir>` is
  `git rev-parse --git-dir` (absolute or relative to `<root>`; in a linked worktree or submodule it
  is the per-worktree git dir). It lives in the git dir, **never in the worktree**, so a cloned
  repository cannot ship an active session: a committed `.oss-drafts/.track-active` or ledger is
  ignored. One line, the ledger path **relative to root**, for example
  `.oss-drafts/track-apache-datafusion-issue1234-20261024T101500Z.md` (an absolute path inside
  `<root>` is also accepted). The hook accepts it only if it then matches
  `^\.oss-drafts/track-[A-Za-z0-9._-]+\.md$` and contains no `..`. Anything else (paths outside
  the root, `..`, subdirectories) is treated as "no session". The pointer, the `.oss-drafts/`
  directory, and the ledger must not be symlinks.
- `<root>` is the git toplevel. **Tracked sessions require git**: outside a git repository there is
  no git dir for the pointer and the hook stays inactive. One active session per root (a worktree
  is its own root, with its own git dir). The hook finds the repository from `$CLAUDE_PROJECT_DIR`,
  else its working directory, by walking up to the first `.git` (a directory, or a file with a
  `gitdir:` line); it does not read stdin until a pointer is found. The Step 3 policy cache glob will match ledgers, but they carry no `policy:`
  block, so the cache skips them.

## 2. Frontmatter (each key on ONE line)

```yaml
---
plugin: agentic-contributor
scenario: prepare-pr
mode: track
repo: <owner/repo|local>
item: <issueN|task>
task: "<one line, user's words>"
issue: <url|none>
branch: <branch at start>
base_commit: <full sha at start>
started_at: <ISO-8601 UTC>
status: active
scope: ["src/cli/**", "tests/cli/**"]
scope_source: user|issue|none
api_paths: []
budget: 3
generated_at: <ISO-8601 UTC>
---
```

- `status`: `active` or `stopped`. Only `active` arms checkpoints. On stop, set `status: stopped`
  and add a `stopped_at: <ISO-8601 UTC>` line.
- `scope` / `api_paths`: flow list, double-quoted items, may be `[]`. No commas, quotes, or brace
  sets inside a glob. The hook strips `[` `]` `"` and splits on `,`.
- `budget`: non-negative integer. A non-integer means 3. `0` means log-only (nothing is asked).
- The frontmatter is mutable (for example `scope:` is widened at a scope checkpoint); entries are
  append-only.
- The hook arms only when the frontmatter has `plugin: agentic-contributor` and `mode: track`.

## 3. Body

```markdown
# Decision ledger (private)
Private notes. Not PR text. Do not paste. Entries are appended as they happen; do not rewrite them.

Task: <task> · Issue: <url|none> · Base: <short sha> on <branch> · Scope: <globs|none (out-of-scope checkpoint off)> · Budget: <n>

## Decisions
<!-- track:end -->
```

## 4. Entries

Written by Claude with the Edit tool, replacing the anchor line `<!-- track:end -->` with the entry
followed by `<!-- track:end -->`:

```markdown
### <id> · <UTC>
<!-- track:entry status=<decided|skipped|not-applicable> source=<checkpoint|manual> asked=<yes|no> at=<UTC> id=<id> -->
- trigger: <test|dependency|api|scope|manual> — <rel path or "n/a">
- files: <rel path[, …]>
- options: A) <option — trade-off> | B) <…> | C) Skip — decide later
- chosen: <A|B|…|Skip|not-a-dependency-change|none>
- decided_by: <user|user-on-recommendation|agent>
- reason: <user's words verbatim | TODO(you) | non-interactive>
```

Rules:

- Write `decided_by: user…` only if the user actually answered. Never invent a user choice.
- `Skip` means `status=skipped`, `reason: TODO(you)`. The debrief lists it under Unknowns.
- No AskUserQuestion available (headless run, subagent): `status=skipped`, `chosen: none`,
  `decided_by: agent`, `reason: non-interactive`.
- Dependency false positive (the edit changes no dependency, only scripts, version, or metadata):
  `status=not-applicable`, `chosen: not-a-dependency-change`, `decided_by: agent`, `asked=no`. It
  does not settle the id (a later real dependency change still gets a checkpoint), does not count
  toward the budget (it also clears the id's pending line). The hook lets that one acknowledged edit through and appends a `<!-- track:consumed at=<UTC> id=<id> -->` marker; the next edit to the same id is checkpointed again. The debrief shows it under "Agent's
  implicit decisions".
- Manual entries ("log this decision"): `id=manual:<UTC>`, `source=manual`, `asked=no`, trigger
  `manual`, status `decided`.
- `at=` is the current UTC time as `YYYY-MM-DDTHH:MM:SSZ` (take it from `date -u +%Y-%m-%dT%H:%M:%SZ`).
  The hook drops fractional seconds. A missing, malformed or future `at=` is read as the oldest
  possible time, so a bad timestamp can only cause an extra checkpoint, never a skipped one.

### Hook-written lines

The hook only ever appends with `>>` at end of file (one atomic line write, no read-modify-write).
It holds a lock directory (`<ledger>.lock`) while it reads the ledger, checks the budget and appends,
so parallel edits cannot spend the same budget slot. A lock older than 10 seconds is treated as stale;
if the lock stays busy for about 2 seconds the hook gives up silently (fail open).
These land below the anchor, which is harmless because readers parse by machine line, not position.

```
<!-- track:pending at=<UTC> id=<id> -->
<!-- track:entry status=logged-over-budget source=hook asked=no at=<UTC> id=<id> -->
- logged-over-budget: <class> — <rel> (<UTC>), not asked; budget <n> spent
<!-- track:entry status=skipped source=hook asked=yes reason=no-ledger-entry at=<UTC> id=<id> -->
- skipped (no ledger entry recorded after 2 checkpoint prompts): <class> — <rel>
```

## 5. Grep/awk contract (invariants every writer keeps)

- A machine line is exactly one line. It starts with `<!-- track:entry ` or `<!-- track:pending `,
  and **`id=<id> -->` is the final token**, so ids with spaces still match as a literal suffix. The
  hook matches with awk `index()` against `ENVIRON["TRACK_ID"]` (no regex metacharacters).
- **settled(id)**: a `track:entry` line with `status=decided` or `status=skipped` and the suffix
  ` id=<id> -->`.
- **over_logged(id)**: a `track:entry` line with `status=logged-over-budget` and that suffix.
- **pending(id)**: count of `track:pending` lines with that suffix.
- **asked** = |distinct ids over pending lines| − |distinct ids with a `track:entry … asked=no`
  line that also have a pending line|.
- The hook never writes old/new strings or file content into the ledger. It writes only the class,
  the edited file's repo-relative path, counts, and timestamps; a path or cwd containing a control
  character (newline, carriage return, ...) makes it fail open without writing, so a path cannot
  forge a marker line.
- The hook never echoes ledger text (`scope`, `api_paths`, or any other frontmatter value) into
  its messages to Claude: it says "the ledger's scope" or "an API path listed in the ledger" and
  names only the edited file's repo-relative path.

## 6. Trigger classes

One class per edit, first match in priority order **test → dependency → api → scope**. Checkpoint
id is `<class>:<repo-relative path>`.

| Class | Fires when | Id |
|---|---|---|
| test | Edit/MultiEdit/Write on an existing test file lowers the assertion count or raises the skip count. A new test file never triggers. | `test:<rel>` |
| dependency | the edit touches a dependency manifest or lock file | `dependency:<manifest rel>` |
| api | the path matches `api_paths` (opt-in, default `[]`) | `api:<rel>` |
| scope | `scope` is non-empty and the path matches none of it | `scope:<rel>` |

Lock files map to their sibling manifest id: `yarn.lock`, `package-lock.json`, `pnpm-lock.yaml`,
`npm-shrinkwrap.json`, `bun.lockb` → `package.json`; `Cargo.lock` → `Cargo.toml`; `go.sum` →
`go.mod`; `poetry.lock`, `uv.lock` → `pyproject.toml`; `Gemfile.lock` → `Gemfile`; `Pipfile.lock`
→ `Pipfile`; `composer.lock` → `composer.json`; `mix.lock` → `mix.exs`; `Package.resolved` →
`Package.swift`.

Dependency basenames (case-sensitive): `package.json package-lock.json npm-shrinkwrap.json
pnpm-lock.yaml yarn.lock bun.lockb Cargo.toml Cargo.lock go.mod go.sum pyproject.toml setup.py
setup.cfg Pipfile Pipfile.lock poetry.lock uv.lock Gemfile Gemfile.lock pom.xml build.gradle
build.gradle.kts settings.gradle settings.gradle.kts libs.versions.toml composer.json
composer.lock mix.exs mix.lock Package.swift Package.resolved packages.config
Directory.Packages.props environment.yml`, plus `requirements*.txt`, `constraints*.txt`,
`*.gemspec`, `*.csproj`.

Test paths: a directory segment `tests`, `test`, `__tests__`, `spec`, `specs`, or `testing`; or a
basename like `test_*.py`, `*_test.(py|go|rb|exs|ex|dart)`, `*.test.*` / `*.spec.*` for JS/TS,
`*Test(s).(java|kt|scala|cs)`, `*IT.(java|kt|scala|cs)`, `*_spec.rb`, `*Test(s).swift`.

Assertion tokens (jq/Oniguruma and python `re`, identical syntax):
`\bassert[A-Za-z_]*\b|XCTAssert|\bexpect\s*\(|\b(?:it|test|describe|context)\s*\(|\bdef\s+test_|\bfunc\s+Test|#\[test\]|@Test\b|\bt\.(?:Error|Fatal)f?\s*\(|\brequire\.[A-Z][A-Za-z]*\s*\(`

Skip tokens:
`@pytest\.mark\.(?:skip|xfail)|\b(?:xit|xdescribe|xtest)\s*\(|\.skip\s*\(|@Disabled\b|@Ignore\b|#\[ignore\]|\bt\.Skip|\bskipTest\b|unittest\.skip`

Glob semantics (scope and `api_paths`): bash `[[ $rel == $glob ]]`, where `*` crosses `/` (so `**`
behaves like `*`). A trailing `/` means prefix. Comparison is against the repo-relative path.

## 7. Budget and loop rules

- Budget default 3, counting questions actually asked (distinct ids with a pending line, minus
  `asked=no` exemptions). Past the budget the hook adds context only (no permission decision, so normal prompts still apply), appends a
  `logged-over-budget` entry once per id, and tells Claude to mention it at the end. It appears as
  an Unknown in the debrief.
- Each deny appends a `track:pending` line. A retry of the same id with one pending line and no
  settled entry is denied once more (second pending line). The third attempt gets no deny: the
  hook (no permission decision, normal prompts still apply) appends `status=skipped source=hook`
  and says so in `additionalContext` (plus a short `systemMessage` for the user). No deny loops.
- A settled id is never asked again. An over-logged id is silent.
- Silent with no session (no git-dir pointer, or not a git repository), `status: stopped`, `OSS_TRACK_DISABLE=1`, `permission_mode: plan`, an
  invalid pointer, or any internal error (the hook is advisory and fails open).

## 8. Auto-allow of the ledger Edit

So that a checkpoint costs one interruption (the question) and not two, the hook returns
`permissionDecision: allow` for exactly one case: tool **Edit** (never Write, MultiEdit, or
NotebookEdit) whose `file_path`, made absolute, equals the active ledger path read from the
pointer, byte for byte. Paths containing a `..` segment, non-normalized forms, symlinked ledger or
`.oss-drafts/`, pointers outside `.oss-drafts/track-*.md`, and every other path get no allow.

## 9. Deny reason template (addressed to Claude)

```
[agentic-contributor · tracked session] Decision checkpoint <k>/<budget> before this <tool_name> on <rel>.
Trigger: <trigger sentence: fixed text plus <rel>; never a ledger value>
Checkpoint id: <id>
<retry line, only on the second prompt: "No ledger entry with id=<id> was found after the previous prompt. Write it exactly as below before retrying.">

Do this, then retry the same edit unchanged:
1. Ask the user with AskUserQuestion: ONE question, "<question>", with 2-3 options. Each option gets a one-line trade-off. Put your recommendation first and mark it "(Recommended)". The last option is "Skip — decide later". Ask them to choose, not to approve or deny.
2. Read <rel_ledger>, then use Edit to replace the line `<!-- track:end -->` with the entry (section 4) followed by `<!-- track:end -->`.
3. If AskUserQuestion is unavailable: write the entry with status=skipped, chosen: none, decided_by: agent, reason: non-interactive.
4. If the user's choice means not making this edit, do not retry. Follow their choice.
Write "decided_by: user…" only if the user actually answered. The ledger is private: never copy it into any sendable text.
```

The dependency class adds: "If this edit changes no dependency (only scripts, version, or
metadata), do not ask: record status=not-applicable, chosen: not-a-dependency-change, decided_by:
agent, asked=no."

## 10. How other skills read the ledger

`change-debrief` finds the ledger via the pointer `"$(git rev-parse --git-dir)/agentic-contributor/track-active"`, else the newest
`.oss-drafts/track-*.md` whose `branch` equals the current branch and whose `base_commit` is an
ancestor of HEAD. Decided entries become `[evidenced: ledger <id>]`; skipped,
`logged-over-budget`, and hook-skipped entries become Unknowns; `reason: TODO(you)` becomes an
explain-back prompt. The PR scaffold keeps its send block `TODO(you)` and only lists decisions as
hints in Private notes.
