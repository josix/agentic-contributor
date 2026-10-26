# Decision Ledger (track mode)

Single source of truth for the track ledger. `hooks/scripts/track-checkpoint.sh` (PreToolUse
checkpoints) and `hooks/scripts/track-breakpoint.sh` (PostToolUse scope-drift alerts, Stop
breakpoint questions) implement the "Grep/awk contract" below; `pr-preparation` (Procedure 0), `change-debrief`, and the docs cite this
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
body_format: 2            # no send block exists, so nothing is sendable
sendable: false           # private ledger: never send or lint, whatever body_format says
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
drift_lines: 400
drift_files: 10
drift_source: default
drift_max: 2
explain_max: 4
explain_interval_min: 20
generated_at: <ISO-8601 UTC>
---
```

- `status`: `active` or `stopped`. Only `active` arms checkpoints. On stop, set `status: stopped`
  and add a `stopped_at: <ISO-8601 UTC>` line.
- `scope` / `api_paths`: flow list, double-quoted items, may be `[]`. No commas, quotes, or brace
  sets inside a glob. The hook strips `[` `]` `"` and splits on `,`.
- `budget`: non-negative integer. A non-integer means 3. `0` means log-only (nothing is asked) and
  is also **quiet mode** for the whole session: no checkpoint, drift, or breakpoint question is
  asked (drift is still logged with `asked=no`; breakpoint questions are off).
- `drift_lines` (default 400): more than N changed lines since `base_commit` raises a drift alert;
  `0` = that threshold is off. `drift_files` (default 10): more than N changed files; `0` = off.
  `drift_source`: `default`, `contributing:<path>:<line>` (an explicit number found in a local
  CONTRIBUTING file at track start), or `user`. `drift_max` (default 2): drift alerts actually
  asked; `0` = log only. `explain_max` (default 4): breakpoint questions per session; `0` = off.
  `explain_interval_min` (default 20): minimum minutes between breakpoint questions; `0` = no time
  limit. A value that is not a non-negative integer takes its default, and a v0.8.0 ledger without
  these keys works with the defaults. `base_commit` must match `^[0-9a-f]{7,64}$`, otherwise drift
  and breakpoint questions are silent.
- The frontmatter is mutable (for example `scope:` is widened at a scope checkpoint); entries are
  append-only.
- The hook arms only when the frontmatter has `plugin: agentic-contributor` and `mode: track`.

## 3. Body

```markdown
# Decision ledger (private)
Private notes. Not PR text. Do not paste. Entries are appended as they happen; do not rewrite them.

Task: <task> · Issue: <url|none> · Base: <short sha> on <branch> · Scope: <globs|none (out-of-scope checkpoint off)> · Budget: <n> · Drift: <L> lines / <F> files (<source>), <drift_max> alerts · Breakpoint questions: <explain_max>, ≥<interval> min apart

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
- You asked the user (AskUserQuestion): `asked=yes`, whatever they chose (including `Skip`).
- No AskUserQuestion available (headless run, subagent): `status=skipped`, `asked=no`, `chosen: none`,
  `decided_by: agent`, `reason: non-interactive`. `asked=no` means it does not use budget.
- Dependency false positive (the edit changes no dependency, only scripts, version, or metadata):
  `status=not-applicable`, `chosen: not-a-dependency-change`, `decided_by: agent`, `asked=no`. It
  does not settle the id (a later real dependency change still gets a checkpoint), does not count
  toward the budget (each not-applicable entry answers one pending line). The hook matches by
  **count, not time**: an entry is an unused acknowledgement while the number of not-applicable
  entries for the id (capped by its pending lines) exceeds the number of
  `<!-- track:consumed at=<UTC> id=<id> -->` markers. It lets that one acknowledged edit through and
  appends a consumed marker; the next edit to the same id is checkpointed again. `at=` is not
  compared, so same-second entries and copied timestamps behave the same. A not-applicable entry
  written before any pending line acknowledges nothing. **Cap:** after 3 acknowledged edits for one id
  the hook stops asking: it appends `status=logged-over-budget source=hook asked=no reason=na-cap`
  and lets the edit through (an Unknown in the debrief). The debrief shows acknowledged edits under "Agent's
  implicit decisions".
- Manual entries ("log this decision"): `id=manual:<UTC>`, `source=manual`, `asked=no`, trigger
  `manual`, status `decided`.
- `at=` is the current UTC time as `YYYY-MM-DDTHH:MM:SSZ` (take it from `date -u +%Y-%m-%dT%H:%M:%SZ`).
  `at=` is for humans: the hook never compares it, so a wrong value cannot change a decision.

### Drift entries

Written by Claude when a drift alert (section 12) asks the user:

```markdown
### drift:<k> · <UTC>
<!-- track:entry status=<decided|skipped> source=drift asked=<yes|no> at=<UTC> id=drift:<k> -->
- trigger: drift — <n> lines / <n> files[; modules: <m>, …]
- files: <files the question named, at most 10>
- options: A) Keep in this change | B) Set aside for a separate PR | C) Drop | D) Skip — decide later
- chosen: <A|B|C|Skip|none>
- decided_by: <user|user-on-recommendation|agent>
- reason: <user's words verbatim | TODO(you) | non-interactive>
- follow-up: <B only: one line naming the set-aside work and its files>
```

### Explain entries

Written by Claude after a breakpoint question (section 13):

```markdown
### explain:<k> · <UTC>
<!-- track:entry status=<answered|skipped> source=breakpoint asked=<yes|no>[ reason=non-interactive] at=<UTC> id=explain:<k> -->
- trigger: explain — <rel>:<line>
- files: <rel>
- question: <the question exactly as asked>
- chosen: <typed|not-requested|skip|none>
- reason: <user's typed words verbatim | not requested by the user | TODO(you) | non-interactive>
- answered_by: <user|agent>
```

`status=answered` applies to explain entries only. The token ` reason=non-interactive ` in the machine
line is required for non-interactive explain entries (the hook latch reads it); `id=` stays last.
Never write `answered_by: user` unless the user actually answered; never grade or edit the answer.

### Hook-written lines

The hook only ever appends with `>>` at end of file (one atomic line write, no read-modify-write).
It holds a lock directory (`<ledger>.lock`) while it reads the ledger, checks the budget and appends,
so parallel edits cannot spend the same budget slot. The holder writes its pid to `<ledger>.lock/pid`;
a lock whose pid is dead is stale and is broken at once, and a lock with no pid file is stale after
5 seconds. If a live holder keeps the lock busy for about 2 seconds the hook gives up silently (fail open).
These land below the anchor, which is harmless because readers parse by machine line, not position.

```
<!-- track:pending at=<UTC> id=<id> -->
<!-- track:entry status=logged-over-budget source=hook asked=no at=<UTC> id=<id> -->
- logged-over-budget: <class> — <rel> (<UTC>), not asked; budget <n> spent
<!-- track:entry status=skipped source=hook asked=yes reason=no-ledger-entry at=<UTC> id=<id> -->
- skipped (no ledger entry recorded after 2 checkpoint prompts): <class> — <rel>
```

Written by `track-breakpoint.sh` (same lock, same single-append rule; it never writes `track:pending`):

```
<!-- track:drift at=<UTC> lines=<n> files=<n> crossed=<lines|files|lines,files|-> modules=<enc,enc|-> asked=<yes|no> id=drift:<k> -->
- drift alert drift:<k>: <n> changed lines (limit <L>), <n> files (limit <F>)[, out-of-scope modules: <m>, …]; <asked|logged only (drift cap spent)|logged only (budget 0)>
<!-- track:breakpoint at=<UTC> epoch=<unix s> sid=<session_id|-> target=<enc rel>:<line> id=explain:<k> -->
- breakpoint question explain:<k>: <rel>:<line> (<n>-line change)
<!-- track:drift-paused at=<UTC> reason=base-moved -->
- drift and explain-back paused: the base commit moved (rebase, reset, or merge); restart tracking to re-baseline
```

`track:drift-paused` is written at most once per ledger (it is the "said once" state). A control
character in a git-reported file name is replaced with `?` before it reaches a bullet or the output.

`enc` percent-encodes `%` as `%25`, space as `%20`, and `,` as `%2C`. `sid` is kept only if it
matches `^[A-Za-z0-9._-]+$`, otherwise `-`.

## 5. Grep/awk contract (invariants every writer keeps)

- A machine line is exactly one line. It starts with `<!-- track:entry ` or `<!-- track:pending `,
  and **`id=<id> -->` is the final token**, so ids with spaces still match as a literal suffix. The
  id is everything after the **first** ` id=` up to the trailing ` -->`, so an id may itself contain
  ` id=` or spaces (`docs/x id=y.md`); no attribute before `id=` may contain ` id=`. The
  hook matches with awk `index()` against `ENVIRON["TRACK_ID"]` (no regex metacharacters).
- **settled(id)**: a `track:entry` line with `status=decided` or `status=skipped` and the suffix
  ` id=<id> -->`, **and** at least one `track:pending` line for the same id (a hand-written entry
  with no pending line settles nothing).
- **over_logged(id)**: a `track:entry` line with `status=logged-over-budget` and that suffix.
- **pending(id)**: count of `track:pending` lines with that suffix, minus the count of
  `status=not-applicable` entries for the id (never below 0).
- **acknowledged(id)**: min(pending lines, not-applicable entries) > count of `track:consumed` markers.
- **asked** = |distinct ids over pending lines| − |distinct ids with a `track:entry … asked=no`
  line that also have a pending line|.
- **drift_n** = count of `^<!-- track:drift ` lines; **drift_asked** = those containing ` asked=yes `.
  Next drift id = `drift:<drift_n+1>`. **alerted** = union of the `crossed=` and `modules=` items
  over all `track:drift` lines (asked or logged), so a threshold or module alerts once.
- **bp_n** = count of `^<!-- track:breakpoint ` lines; **bp_last** = the maximum `epoch=`. A missing,
  non-numeric, or future epoch counts as 0 (oldest), so errors lean toward asking; the count cap
  still bounds them. Next id = `explain:<bp_n+1>`.
- **latch(sid)**: a breakpoint line with `sid=<sid>` whose id also has a `track:entry` line with
  `source=breakpoint` containing ` reason=non-interactive ` and the suffix ` id=<id> -->`.
- **covered(rel)**: a `track:entry` or `track:pending` line whose final id is
  `<test|dependency|api|scope>:<rel>`, except `status=logged-over-budget` entries (not asked).
- **questions(q)** = (count of `track:pending` lines) + drift_asked, used for the explain watermark.
  Drift and explain never write `track:pending`, so the checkpoint `asked` arithmetic is unchanged.
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

Assertions and skips are counted only for test paths, per line (a token never spans a newline), and
only when the payload and the existing file are at most 512 KiB; above that the test-weakening check
is skipped (fail open).

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
- Separate caps (v0.9.0): checkpoints keep `budget` (3); drift has `drift_max` (2); breakpoint
  questions have `explain_max` (4), at least `explain_interval_min` (20) minutes apart. Worst case
  3+2+4 = 9 questions per session; typical 0 to 3. `budget: 0` is quiet mode for all three.
- Silent with no session (no git-dir pointer, or not a git repository), `status: stopped`, `OSS_TRACK_DISABLE=1`, `permission_mode: plan`, an
  invalid pointer, or any internal error (the hook is advisory and fails open).

## 8. Auto-allow of the ledger Edit

So that a checkpoint costs one interruption (the question) and not two, the hook returns
`permissionDecision: allow` for exactly one case: tool **Edit** (never Write, MultiEdit, or
NotebookEdit) that **appends**: `old_string` is `<!-- track:end -->` (optionally followed by a
newline), `replace_all` is not set, and `new_string` ends with `old_string`, with a prefix that
contains no `<!-- track:end -->`, `<!-- track:pending `, `<!-- track:consumed `, `<!-- track:drift` (also
`track:drift-paused`), `<!-- track:breakpoint` or ` source=hook`.
The `file_path` must name the active ledger from the pointer (after the hook normalizes the path
and compares logical and physical repository roots), and the raw `file_path` must not contain a
`..`, `.` or empty segment. Every other edit of the ledger (frontmatter changes such as widening
`scope:` or `status: stopped`, rewrites of earlier entries, Write, MultiEdit) gets no decision, so
Claude Code's normal permission prompt applies: those changes stay possible but are never silent.
Symlinked ledger or `.oss-drafts/`, pointers outside `.oss-drafts/track-*.md`, and every other
path get no allow.

## 9. Deny reason template (addressed to Claude)

```
[agentic-contributor · tracked session] Decision checkpoint <k>/<budget> before this <tool_name> on <rel>.
Trigger: <trigger sentence: fixed text plus <rel>; never a ledger value>
Checkpoint id: <id>
<retry line, only on the second prompt: "No ledger entry with id=<id> was found after the previous prompt. Write it exactly as below before retrying.">

Do this, then retry the same edit unchanged:
1. Ask the user with AskUserQuestion: ONE question, "<question>", with 2-3 options. Each option gets a one-line trade-off. Put your recommendation first and mark it "(Recommended)". The last option is "Skip — decide later". Ask them to choose, not to approve or deny.
2. Read <rel_ledger>, then use Edit to replace the line `<!-- track:end -->` with the entry (section 4, `asked=yes`) followed by `<!-- track:end -->`.
3. If AskUserQuestion is unavailable: write the entry with status=skipped, asked=no, chosen: none, decided_by: agent, reason: non-interactive (does not use budget).
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

Additions in v0.9.0:

- `explain:<k>` with `status=answered`, `chosen: typed` becomes `[evidenced: ledger explain:<k>]`
  ("you said: ..."). It is the strongest Why source because it is in the user's words.
- `chosen: not-requested`: that group is labelled "unexplained, possibly out of scope (you said you
  did not ask for it)".
- A skipped explain entry, or a breakpoint marker with no entry, becomes the Unknown
  "not explained: <rel>:<line> (ledger explain:<k>)".
- Drift A: evidence "you chose to keep ...". Drift B: listed under Follow-ups (`follow-up:` line).
  Drift C whose files are still in the final diff: Unknown "dropped per ledger drift:<k> but still
  in the diff: ...". A skipped drift entry, a `track:drift` marker without an entry, or an
  `asked=no` marker: Unknown.
- A `track:drift-paused` line: Unknown "scope drift and explain-back were paused after the base
  commit moved; changes since then were not checked".

## 11. Session state file

`<root>/.oss-drafts/<ledger basename without .md>.state`. Plain text, one record per line,
tab-separated, append-only except for compaction. Only `track-breakpoint.sh` writes it; `/oss track stop` deletes it. It
holds repo-relative paths only, never contents. It is disposable: rate-limit and audit state lives
in the ledger, so deleting it cannot lift a cap. A missing, malformed, or symlinked state file means
"no edits" (silent; a symlink disables both features).

```
e<TAB><rel>      PostToolUse: a successful Edit/Write/MultiEdit/NotebookEdit outside .oss-drafts/
d                PostToolUse: a drift check ran (throttle point)
m<TAB><q>        Stop: question watermark (questions(q) at this stop)
b<TAB><id|none>  Stop: breakpoint consumed (explain:<k> asked, none = no target, compacted)
s<TAB><n>        Stop: number of asked=no drift markers already summarised to the user
```

"Edits since the last breakpoint" = `e` lines after the last `b` line. Paths under `.oss-drafts/`
are never logged, so ledger writes never re-arm a breakpoint. The last `m` and `s` values win.

**Compaction.** Above 400 lines the hook (under the ledger lock; skipped if busy) folds all but the
newest 100 lines into a prefix: the last `m` and `s`, one `e` per distinct path edited before the
last dropped `b` (the session-wide set used for untracked-file counting), `b<TAB>compacted`, one
`e` per distinct path after it, and one `d` if any was dropped. Nothing reads line counts, so only
the "edits since the last `d`" throttle can be undercounted, which at most postpones one check. An
`e` line appended by a parallel PostToolUse during the rewrite may be lost (harmless).

## 12. Scope drift

- **Events**: PostToolUse (throttled: a git check runs only when the edited path is new to the
  session's edit log, or after 5 edits since the last check) and Stop (once per turn end, which also
  catches Bash edits to tracked files; files created by Bash are not counted, because counting every untracked file would turn pre-existing scratch files into drift without a recorded baseline). Inside a subagent (`agent_id` present) PostToolUse logs the edit but
  defers the check to the main thread's Stop, without writing a `d` throttle line.
- **Base moved**: before measuring, the hook checks `git merge-base --is-ancestor <base_commit>
  HEAD` and `git rev-list --merges <base_commit>..HEAD`. If the base is no longer an ancestor, or a
  merge commit landed since it (a rebase, reset, or `git pull` with a merge), the diff would count
  upstream changes as drift: drift and explain-back pause, `track:drift-paused` is written once, and
  the user is told "base moved — drift paused; restart tracking (/oss track stop + start) to
  re-baseline" (PostToolUse: `additionalContext` plus `systemMessage`; Stop: `systemMessage` only).
  A fast-forward pull is not detected. If git works but the base commit no longer exists (garbage
  collected, shallow clone) the pause reason is `base-missing` and the user is told "base commit not
  found (garbage-collected or shallow clone) — drift and explain-back paused; restart tracking to
  re-baseline". Any other git failure fails open (silent).
- **Size**: changed lines = added + deleted from `git diff -M --numstat <base_commit>` (base vs
  working tree, renames detected, so a pure rename is 0 lines) plus the line count of untracked text
  files created with Edit/Write (capped at 20000 lines each; untracked binary or empty files, found
  with one `grep -lI`, count as files with 0 lines and are never explain targets). Lock files count
  as files but not lines; binary files count as files with 0 lines; `.oss-drafts/` is excluded.
  Scope and module paths come from a second, rename-free diff so both sides of a rename are literal. Thresholds
  are strictly greater than `drift_lines` / `drift_files`.
- **Modules**: changed paths outside `scope` that no checkpoint covers (covered(rel); an over-budget log does not count), grouped by
  the first two directory segments or `(root)`. Off when `scope: []`. Each module alerts once. The
  alert text lists at most 10 modules (`… (+N more)`); the marker keeps the full list.
- **Delivery**: PostToolUse gives `hookSpecificOutput.additionalContext` (never a block, so the
  agent does not treat the edit as failed and revert). Stop gives `{"decision":"block"}`, and drift
  takes precedence over explain-back at the same stop. **Spacing**: no new drift question is asked
  in a turn that already had a checkpoint or drift question (PostToolUse defers; Stop skips the
  drift check) when the question count exceeds the state `m` watermark. Stop also defers the drift
  check, without recording it, when the agent's last message already asks the user. Stop advances `m`
  on every stop (the state file is created if needed), including one that holds for a drift question
  (`m` is written before the block), even when explain-back is off. If the agent ignores PostToolUse
  context, `emit_json post` can switch to a block (one-line change).
- **Cap**: `drift_max` asked alerts; over the cap, or with `budget: 0`, the marker is written with
  `asked=no` (log only) and nothing is injected after the edit. At the next Stop the user gets one
  `systemMessage` summarising the new `asked=no` markers (counted against the state `s` line), and
  the debrief lists them. That summary is user-facing: the agent does not see it, and with
  `budget: 0` nothing is asked at all. The `track:drift` marker is the
  alerted state, so a missing Claude entry never causes a repeat. Simultaneous crossings are merged
  into one alert.
- **Git safety**: every git call runs with `GIT_OPTIONAL_LOCKS=0 GIT_LITERAL_PATHSPECS=1 git -C
  <root> -c core.quotepath=off ... --no-ext-diff`, plus `--no-renames` (scope and module paths) or `-M` (size totals and the explain-back
  target), and never inside the ledger lock.
  Hooks never revert, stash, reset, or edit code.

## 13. Explain-back at breakpoints

At Stop, when code edits happened since the last breakpoint, the hook blocks once and asks Claude
to put ONE skippable question about a specific `file:line` to the user and record the verbatim
answer. All of these must hold: session active; not plan mode; `stop_hook_active` false;
`budget>0` and `explain_max>0`; at least one edit since the last `b`; no checkpoint or drift
question since the previous stop (the `m` watermark); the last assistant message is not already asking
(its last non-blank line, ignoring trailing markdown emphasis, quotes and brackets, ends in `?` or
full-width `？`, or it ends in a list of options whose lead-in line does); bp_n < `explain_max`; now - bp_last >= `explain_interval_min` x 60; the non-interactive latch
is not set for this `session_id`; a target exists. When a rate limit or deferral applies the edits
are kept, so a later stop can still ask.

- **Target**: the largest hunk (max of old/new line count, from `git diff -U0`) among files edited
  since the last breakpoint, excluding dependency files, covered files (an over-budget log does not cover), and `.oss-drafts/`;
  untracked created files count as one hunk at line 1. Files no earlier question targeted are
  preferred. With no target the hook appends `b<TAB>none` and stays silent.
- **Loop safety**: (1) `stop_hook_active:true` exits before any work; (2) the ledger marker and
  `b<TAB>explain:<k>` are written before the block is emitted; (3) the ledger count and interval
  caps. At most one block per stop.
- **Non-interactive (`-p`)**: the hook cannot detect it. The first block makes Claude record a
  `reason=non-interactive` entry and end the turn; the next stop has `stop_hook_active:true`. The
  latch then silences explain-back for the rest of that `session_id`. Cost: one extra continuation.
- **Channel**: AskUserQuestion with free-text "Other" as the answer, plus "Skip" and "I didn't ask
  for this change". Answers are never graded.

## 14. Drift and explain templates (addressed to Claude)

Drift (PostToolUse context; at Stop the first sentence ends "...before ending your turn:"):

```
[agentic-contributor · tracked session] Scope drift alert <a>/<drift_max>: the change has grown since the session base <short sha>.
Size: <lines> changed lines (limit <L>, <source>), <files> files (limit <F>). Crossed: <lines, files | none>.
Out-of-scope modules with changes no checkpoint covered: <m> (<files>); ...   (line omitted if none)
Largest files: <rel> (<n>), ... (top 5)
Drift id: drift:<k>

This is advisory: nothing was blocked. Before your next edit:
1. Ask the user with AskUserQuestion (header "Scope drift"): ONE question naming the files concerned (at most 10). Options, each with a one-line trade-off, your recommendation first marked "(Recommended)": A) Keep it in this change | B) Set it aside for a separate PR | C) Drop it | D) Skip — decide later
2. Read <rel_ledger>, then use Edit to replace the line `<!-- track:end -->` with the drift entry (section 4) followed by `<!-- track:end -->`. For B write a one-line follow-up. Use status=skipped, reason: TODO(you) for D.
3. If AskUserQuestion is unavailable: status=skipped, asked=no, chosen: none, decided_by: agent, reason: non-interactive.
4. Follow the choice. Never revert, stash, reset, check out, or move changes on your own. For B or C, stop extending that work and tell the user which files hold it; undo edits only if the user explicitly asks, using Edit.
Write "decided_by: user…" only if the user actually answered. The ledger is private: never copy it into any sendable text.
```

Drift logged only: no message to Claude. At Stop, a `systemMessage` to the user:
`agentic-contributor: <n> scope-drift item(s) logged without asking (drift question cap spent or
budget 0); they are in the ledger and the debrief.`

`<source>` is a fixed label (`default`, `set by the user`, `from the project's CONTRIBUTING file`,
`from the ledger`), never the ledger's `drift_source` text.

Explain (Stop block reason):

```
[agentic-contributor · tracked session] Breakpoint question <k>/<explain_max> (explain-back). Before ending your turn:
Target: <rel>:<line>. This is the largest change since the session base (<n> lines) that no checkpoint or earlier question covered.
1. Read <rel> around line <line> and pick the one specific change there.
2. Ask the user with AskUserQuestion (header "Explain"): ONE question, "In one sentence, why does <that specific change>? Type your answer under Other, or pick an option." Do not hint at the answer. Options: A) Skip — not sure (recorded as an Unknown) | B) I didn't ask for this change
3. Read <rel_ledger>, then use Edit to replace the line `<!-- track:end -->` with the explain entry (section 4) followed by `<!-- track:end -->`. Typed answer: status=answered, chosen: typed, reason = their words verbatim. B: status=answered, chosen: not-requested. A: status=skipped, chosen: skip, reason: TODO(you).
4. If AskUserQuestion is unavailable: do not ask. Write the entry with status=skipped asked=no reason=non-interactive, chosen: none, reason: non-interactive, answered_by: agent.
5. Do not grade or correct the answer and make no code edits now. End your turn with one short line.
Write "answered_by: user" only if the user actually answered. The ledger is private: never copy it into any sendable text.
```
