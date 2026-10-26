# Changelog

All notable changes to the agentic-contributor plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.10.0] - 2026-10-24

### Added

- **Predict-then-reveal** inside tracked sessions, `predict: auto` by default for new sessions: fixed rules switch it on (newcomer to the repo, a skipped or not-requested explain-back, 3+ unknowns in the previous session) and off (two consecutive "no idea" predictions, sticky), and every switch is logged in the ledger with its reason when auto is evaluated. Flags: `--predict[=on|off|auto]`, `--no-predict`; `/oss track predict on|off|auto` (that frontmatter edit gets the normal permission prompt; only appends at `<!-- track:end -->` are auto-allowed). A ledger without a `predict` key (v0.9.0) or with `predict: false` stays off and exits after the builtin frontmatter read, before any jq/python3 parse.
- A `UserPromptSubmit` hook (handled by `track-breakpoint.sh`) adds an `additionalContext` instruction so that, only for diagnosis or planning prompts, the agent asks for your prediction first, then shows where it matched or differed (`file:line`) and records it privately (`predict:<n>`). Never blocks, never scores; it writes only the auto switch marker (under the shared ledger lock, fail open) and a one-line `p<TAB><sid>` session note in the state file (kept by state compaction). The full note is sent once per session; later prompts get a short reminder that names the ledger path and decision-ledger.md sections 4 (entry format) and 15 (rules), so it still works after context compaction. Silent when predict is off, `budget: 0`, the cap `predict_max` (default 4) is reached, the prompt is a `/name` command (a path like `/src/parser.c:42 crashes, why?` is text) or trivial (`thanks!`: 24 UTF-8 bytes or fewer, no `?`, no diagnosis or planning keyword such as `hangs`, `hung`, `flaky`, `stuck`, `timeout`, `broke`), or on any parse error or control character. Plan mode still predicts (the note says to write the entry once plan mode ends), and so does a session whose drift and explain-back are paused (it never diffs against the base).
- Predict entries: written right after the answer (`outcome: pending`) so they count at ask time, with the outcome as a separate appended `track:outcome` block. Option A records exactly `prediction: no idea`; option B reads "Skip predictions for this session" and sets `predict: false`. The "two no-idea" rule is an exact match after lowercasing and trimming spaces, quotes and punctuation ("No idea — go ahead" and "No idea." count, "No idea, maybe lexer.c" is a guess). An appended `track:predict-auto` marker is hook-only and never auto-allowed.
- Ledger: frontmatter `predict`, `predict_max`, `user_commits`, `prior_unknowns` (column-padded numbers parse); `track:predict-auto` marker; predict entry format; `change-debrief` gets a private "Your predictions" subsection. `user_commits` counts commits whose author email is exactly `git config user.email` (`git rev-list --count -F --author="<$email>" HEAD`; a bare email or name match would also count `xalex@…` or `Alexander`), and is `-1` on a shallow clone or with no email. `prior_unknowns` counts only Unknowns the user left: non-interactive, drift and predict (option B) skips are excluded.
- Harness cases for the new event in `hooks/tests/run-breakpoint-tests.sh` (including a multi-author `user_commits` fixture with substring-collision authors), and guard allow cases for the `user_commits` recipe commands.

### Changed

- A predict entry counts as a question in the Stop explain-back watermark, so a prediction and an explain-back are not asked in the same turn. The documented worst-case question count is 3+3+2+4+4 = 16 (scope checkpoints have their own budget pool).
- `hooks/hooks.json` registers `UserPromptSubmit`.
- `change-debrief` scope covers the whole session: committed changes plus staged/unstaged working-tree changes (`git diff <base>`) and untracked files (`git status --porcelain`), so a file the ledger names is never reported absent before all three are checked.
- Checkpoint, drift and explain-back instructions give the ledger's absolute path (`trk_ledger`, from the git-dir session pointer), so they work when the agent runs from a subdirectory.
- Docs (`draft-files.md`, `hooks.md`, `hooks.json` description) describe predict as `auto` by default and list `user_commits` and `prior_unknowns` with the frontmatter.

### Notes

- Guard script untouched by this release; its harness gains allow cases for the `user_commits` recipe. No scenario or skill count change.

## [0.9.0] - 2026-10-24

### Added

- `track-breakpoint.sh` pauses with the checkpoint hook (shared `pause check` block): on another branch or past `OSS_TRACK_MAX_AGE_HOURS` it sends no drift alert, explain-back question or predict note.
- Question spacing holds on a session's first stop: a checkpoint asked in the same turn (its edit denied, so no state file existed yet) now postpones the drift question instead of asking two questions in one turn.
- **Scope-drift alerts** inside tracked sessions: a new advisory hook `hooks/scripts/track-breakpoint.sh` (registered on `PostToolUse` for `Edit|Write|MultiEdit|NotebookEdit` and on `Stop`) compares the working tree with the session base commit. A change that grows past `drift_lines` (default 400) or `drift_files` (default 10), or touches out-of-scope modules that no v0.8.0 checkpoint covered, raises one alert that asks keep / separate PR / drop / skip, and the choice is recorded in the ledger (`drift:<k>`). Mid-turn alerts use `additionalContext` (never a block); at Stop the alert is a single block. Thresholds come from explicit numbers in a local CONTRIBUTING file at track start, else the defaults; the alert labels each limit with its own source (a limit at its default value says `default`).
- **Explain-back at natural breakpoints**: when the agent stops after code edits (at least one edit since its previous stop, so a chat-only turn is never interrupted; edits whose question was deferred wait for the next turn that edits again), one skippable question about a specific `file:line` (the largest uncovered hunk of at least 5 lines, `EXPLAIN_MIN_LINES`; smaller changes are never asked about) is put to the user, and the verbatim answer is recorded (`explain:<k>`). At most 4 per session, at least 20 minutes apart, never right after another question, with a per-session non-interactive latch so `claude -p` never hangs.
- Ledger additions: frontmatter keys `drift_lines`, `drift_files`, `drift_source`, `drift_max`, `explain_max`, `explain_interval_min`; hook markers `track:drift` and `track:breakpoint`; a disposable session state file `<ledger>.state` (paths only); sections 11 to 14 in `decision-ledger.md`.
- Harness `hooks/tests/run-breakpoint-tests.sh` with `hooks/tests/breakpoint-cases.tsv` (bash 3.2), including a check that the code shared with `track-checkpoint.sh` stays byte-identical.
- Base-moved pause: scope drift never counts upstream changes after a mid-session rebase, reset, or merge: when the base commit is not an ancestor of `HEAD` or a merge commit landed since it, drift and explain-back pause and the user is told once (`track:drift-paused`) to restart tracking to re-baseline. A fast-forward pull is not detected (documented limit).
- Over the drift question cap or with `budget: 0`, newly seen out-of-scope modules are recorded silently (no `additionalContext` after each edit); the next Stop gives the user one `systemMessage` summary, and the debrief lists them.
- The session state file `<ledger>.state` stays bounded: above 400 lines it is compacted (under the ledger lock) to a prefix that keeps the last `m`/`s` values, the distinct edited paths, and the last breakpoint reset, plus the newest 100 lines.
- Inside a subagent, PostToolUse checks `agent_id` before writing the `d` throttle marker, so a subagent edit never postpones the main thread's next drift check.
- `track-breakpoint.sh` carries the v0.8.0 security measures: the git-dir session pointer (shared lookup block, checked before stdin is read; the `stop_hook_active` guard still runs before any parsing), control characters in `file_path`/`cwd` or other input fields fail open without writing, control characters in git-reported file names are replaced, and no ledger text is echoed (the drift source is shown as a fixed label, never the ledger's `drift_source` value).
- `docs/reference/hooks.md` documents that `last_assistant_message` (Stop) and `agent_id` (PostToolUse in a subagent) need a Claude Code version that sends them, and what degrades without them.
- Harness breakpoint checks (gitdir pointer fixtures run from the fixture root; committed in-worktree pointer, `.git`-file worktree, injection text in `scope`/`drift_source`, control characters in input, rebased and merged base, quiet-mode summary, state compaction, subagent `d` marker, a tracked path with a space in the explain target, `$CLAUDE_PROJECT_DIR` lookup, a 3 MB no-session payload); also pass with GNU `stat` on `PATH`. The byte-identity check uses the new block delimiters and also compares the set of shared block names.
- `track-breakpoint.sh` details: the drift loop runs without per-path forks (a 2000-file out-of-scope change takes about 1 s) and lists at most 10 modules in the alert text; the "agent is already asking" check recognises markdown-wrapped, full-width and option-list questions; untracked binary or empty files count as 0 lines and are never explain targets (text files are capped at 20000 lines); a pure rename counts as 0 lines; no drift question is asked in a turn that already asked one, and the question watermark advances on every stop; a base commit that was garbage-collected or is missing from a shallow clone pauses drift once with a clear notice (`reason=base-missing`) instead of failing silently.
- Docs: `PostToolUse` drift context is never a block while `Stop` may hold the stop once; the quiet-drift summary is a user-facing `systemMessage` the agent does not see (and `budget: 0` asks nothing); files created by Bash are not counted (a documented limit).
- Harness: 121 breakpoint checks (also the asking forms, binary and renamed files, spacing, base-missing, a 2000-path timing check, chat-only turns after a deferred question, the minimum explain-back change size, and per-limit drift source labels).
- The explain-back target (`pick_target`) is rename-aware like the drift totals: a pure `git mv` of an unchanged file contributes 0 lines and a rename with edits counts only the edited lines, so a renamed file is never picked as the "largest change" (single `-M` diff, candidates filtered in awk, no per-path forks).
- Hook-only markers: ledger appends of `track:drift` (also `track:drift-paused`) and `track:breakpoint` markers are never auto-allowed; a Stop that holds for a drift question advances the `m` watermark first and always writes it (the state file is created if needed); Stop defers the drift question while the agent's last message already asks the user; a `logged-over-budget` entry does not count as covered, so out-of-scope files past the checkpoint budget can still raise module drift; no `git` call runs inside the ledger lock at Stop; the breakpoint ledger-id parser takes everything after the first ` id=` like `track-checkpoint.sh`. Docs: lock staleness, `--no-renames`/`-M`, `emit_json`, and who sees over-budget notes.

### Changed

- Separate caps: checkpoints 3 (unchanged), drift 2, explain-back 4. `budget: 0` is now quiet mode for the whole session (no checkpoint, drift, or explain questions; drift is still logged).
- `change-debrief` and the `prepare-pr` scaffold use explain answers as the strongest Why evidence and turn skipped or unanswered drift and explain items into Unknowns and follow-ups. `/oss track status` and `/oss track stop` report the new counts; `stop` also deletes the state file.
- `hooks/hooks.json` registers `PostToolUse` and `Stop`.
- `track-checkpoint.sh` behaviour: with `budget: 0`, an edit that already has a pending marker is now logged as `logged-over-budget` (with the notice) instead of getting a retry/skip prompt, so quiet mode never asks. Its shared code sits in `# --- shared: <name> (keep identical in track-*.sh) ---` blocks (list cleaning, manifest map, glob match added to the v0.8.0 session lookup and lock helpers). Its harness gains a `budget0-pending` case (125/125).

### Notes

- Guard untouched (`guard-outbound.sh`, its harness and cases; 442/442). No scenario or skill count change.
- Hooks never revert, stash, or edit code. Limits: Bash-created untracked files are not counted, `SubagentStop` is not covered, and `Stop` does not run on interrupt.

## [0.8.0] - 2026-10-24

### Added

- **Tracked sessions** (`/oss track`, a `prepare-pr` mode with `start`, `stop`, `status`, `resume`, `log`): a private, append-only **decision ledger** `<git toplevel>/.oss-drafts/track-<owner>-<repo>-<item>-<UTC>.md` plus a pointer `<gitdir>/agentic-contributor/track-active` in the git dir, never the worktree, so a cloned repository cannot ship an active session (a committed pointer or ledger is ignored). The pointer is resolved without forking by walking up to `.git` (a directory, or a `.git` file's `gitdir:` line for linked worktrees and submodules); a pointer naming a ledger outside the repository root, or a symlinked pointer, ledger or `.oss-drafts/`, means no session. One active session per project folder; tracked sessions require git. The `.oss-drafts/` exclude step uses `git rev-parse --git-path info/exclude`.
- **Decision checkpoints**: a new, separate, advisory `PreToolUse` hook `hooks/scripts/track-checkpoint.sh` for `Edit|Write|MultiEdit|NotebookEdit`. Opt-in per session: with no session it checks only for the pointer (from `$CLAUDE_PROJECT_DIR`, else `$PWD`) with bash builtins and exits without reading stdin or starting a subprocess. Fails open; `jq`, then `python3`, else silent allow. Four trigger classes (test weakening, dependency manifests and lock files, opt-in `api_paths`, out-of-scope edits) become "choose, not approve" questions with a Skip option.
- **Checkpoint ids name the change**: `<class>:<repo-relative path>`, and test and dependency ids end in `#<change>`, the `cksum` of the edit's changed-line set (`dependency:package.json#073e0383`). Retrying the same edit after a decision passes silently; a second dependency in an already-decided manifest, or a second, different weakening of the same test file, is a new checkpoint. Paths are normalized (`//`, `./`, `..`; logical and physical repo roots), so `src/../package.json` and a symlinked `$CLAUDE_PROJECT_DIR` give the same id; a path outside the repository gets no checkpoint. A lock file maps to its manifest.
- **Sessions pause instead of following you around**: the hook asks nothing and records nothing while the checked-out branch differs from the ledger's `branch` (not checked for a session started on a detached HEAD) or the pointer is older than `OSS_TRACK_MAX_AGE_HOURS` (default 24, `0` = off). The first would-be checkpoint shows a one-time notice; `/oss track resume` re-arms an age-paused session, and `status` says whether the session is paused. Before, a forgotten session interrupted every later Claude Code session in the repository, on any branch, and mixed their answers into its ledger.
- **Fatigue budget**: default 3 questions actually asked, `budget N` to change it, `budget: 0` log-only mode. Scope checkpoints have their own budget of the same size, so out-of-scope edits never use up the questions for test, dependency, and api checkpoints. Past the budget the trigger is logged (`logged-over-budget`) with `additionalContext` and a top-level `systemMessage`, and no permission decision.
- **Loop guard**: a checkpoint retried without a ledger entry is denied once more, then let through as `skipped source=hook`. Dependency false positives (scripts or metadata only) are recorded as `not-applicable` acknowledgements, matched by count (pending / not-applicable / consumed per id), never by timestamp, and capped at 3 per id (`reason=na-cap`). A `decided`/`skipped` entry settles an id only if the hook asked about it. Ledger ids are parsed from the first ` id=`, so ids with spaces or ` id=` in the path work. The deny text says which `asked=` value to use, including `status=skipped, asked=no` when AskUserQuestion is unavailable.
- **Test-weakening detection**: assertions and skips counted per line in one linear pass, only for test paths, with comment-only lines (`//`, `#`, `* `, `/* ... */`) excluded so commenting out an assert counts as removing it; a payload or existing test file over 512 KiB skips the check (fail open). Same logic on the jq and python3 paths.
- The hook auto-allows `Edit` only for an append-shaped edit of the exact active ledger path (one entry inserted at `<!-- track:end -->`, no `..`, no symlinks) so a checkpoint costs one interruption; frontmatter edits and rewrites of earlier entries get Claude Code's normal permission prompt. `/oss` itself pre-approves `Edit` only under `.oss-drafts/`, so its own ledger updates (such as `stop`) do not prompt, and edits elsewhere do.
- Hook safety properties: it never echoes ledger text (`scope`, `api_paths`, any frontmatter value) into its output, so the ledger is not a prompt-injection channel; a `file_path` or `cwd` with a control character makes it fail open without writing, so a file name cannot forge ledger marker lines; it writes only class, path, a change checksum, counts, and timestamps. Ledger state and budget are read and updated under a `mkdir` lock with a pid file; a dead holder's lock is broken at once, a pid-less lock is stale after 5 s (`stat -c %Y`, then `stat -f %m`), and a stale lock is renamed before removal.
- Harness `hooks/tests/run-track-tests.sh` with `hooks/tests/track-cases.tsv` (bash 3.2, fixture git repo per case, python3 fallback, jq/python3 id parity, lock, symlink, injection and performance checks).
- `oss-researcher` scenario key `track-start`; reference `skills/pr-preparation/references/decision-ledger.md` (canonical ledger format); concept page `docs/concepts/tracked-sessions.md`. Scope from an issue uses the mentioned paths as `dir/**` (a file contributes its directory; a file at the repo root stays exact).

### Changed

- `change-debrief` and the `prepare-pr` scaffold read the ledger as first-hand evidence (`evidenced: ledger <id>`); skipped, over-budget, and hook-skipped decisions become Unknowns; the send block stays `TODO(you)`. `change-debrief` lists `git rev-parse --git-dir` among its local git reads.
- The decision ledger frontmatter carries `body_format: 2` and `sendable: false` (no send block), so consumers never post or lint it.
- `/oss` allowed-tools adds `Edit` (active ledger only); the `mode` list adds `track`; `item` adds `task`. `commands/oss.md` notes that the ledger always lives in the repository root's `.oss-drafts/`.

### Notes

- No guard changes; no scenario or skill count change. Bash commands (`npm install`, `rm`) are not watched; documented as a limit.

## [0.7.0] - 2026-10-21

### Added

- **Scenario 10, `prepare-pr`**, with the new **`pr-preparation` skill**: a size and shape check (default 400 lines / 10 files unless CONTRIBUTING says otherwise) and a problem-first PR description scaffold in an `oss:send` block. "Why this approach", "What changed", and "Unknowns & assumptions" are `TODO(you)`; the plugin fills only factual parts, and "How it's tested" names tests rather than commands that passed. Adds disclosure text when policy requires it, advice on AI co-author trailers when forbidden, and a lint mode (AP1-AP9). It reads local git only and never pushes, opens a PR, edits code, or runs tests.
- **`change-debrief` skill** and `prepare-pr` `mode: debrief` ("help me understand what I changed", "debrief my change", "what did the agent change"): changes grouped by purpose with `file:line`, traced to issue/commit/opt-in agent transcript, untraceable changes flagged as possibly out of scope, evidenced vs inferred, impact and test coverage, explain-back questions, and an Unknowns list. Saved as a private `.oss-drafts/prepare-pr-<owner>-<repo>-debrief-<UTC>.md`, never PR text.
- Frontmatter fields `base`, `head`, `diff_stats`; `mode` gains `debrief|draft|lint` for prepare-pr; `item` gains `pr-new` and `debrief`.
- `oss-researcher` scenario key `prepare-pr` (PR template, duplicate open PRs, linked issue body).

### Changed

- The issue-first branch now covers `prepare-pr`: PR intent with an issue goes to prepare-pr; with no issue and `issue_first: required` it reroutes to `report` (`routed_from: prepare-pr`); `recommended` or `unknown` goes to prepare-pr (with a warning for `recommended`).
- Scenario count 9 to 10 and skill count 7 to 9 across README, docs, commands, skills, and agents.
- `/oss` steps renumbered so they run in order: Step 3 is now Policy Preflight (was Step 3a), Gather Data is Step 4, Load Skill is Step 5, and the Two-Tier Export is Step 6. Cross-references in README, docs, and skills updated.

### Fixed

- **Guard: GitHub MCP tools are now default-deny.** The write-verb check matched the whole tool suffix, so real write tools passed (`issue_write`, `pull_request_review_write`, `add_comment_to_pending_review`, `push_files`, `merge_pull_request`, `update_pull_request`, `update_pull_request_branch`, `fork_repository`, `create_or_update_file`, `delete_file`, `sub_issue_write`, `assign_copilot_to_issue`, `create_branch`, `create_pull_request`, `create_repository`, `request_copilot_review`). Only `get_*`, `list_*`, `search_*`, and the named read tools `issue_read` and `pull_request_read` are allowed now, unless the name also contains `write`, `create`, `delete`, `submit`, or `fork`.
- **Guard: every GitHub MCP server, not only this plugin's.** The matcher is now `Bash|mcp__.*[Gg][Ii][Tt][Hh][Uu][Bb].*__.*` and the read allowlist applies to any MCP server with `github` in its name, so a separately installed server (`mcp__github__add_issue_comment`, `mcp__claude_ai_GitHub__issue_write`) can no longer post. The `oss-researcher` comment no longer claims the hook covers all tools.
- **Report-tier files are never sendable.** status, find, norms and setup files now set `body_format: 2` and `sendable: false`. Before, they omitted `body_format`, which the contract defines as legacy "whole body sendable".
- **Guard: more `gh` write subcommands denied:** `gh pr revert`, `gh project` create/edit/delete/close/copy/link/unlink/mark-template/item-add/item-create/item-edit/item-delete/item-archive/field-create/field-delete, `gh ssh-key add/delete`, `gh gpg-key add/delete`, `gh repo deploy-key add/delete`, `gh repo autolink create/delete`, `gh cache delete`, `gh release delete-asset`, `gh gist rename`, `gh alias delete/import`, `gh codespace delete/edit/stop/rebuild`. Read forms (`gh project list/view`, `gh ssh-key list`, `gh cache list`, …) and `gh repo set-default` stay allowed.
- **Guard: inline git aliases.** `git -c alias.<name>=<value> <name>` is denied when the value pushes or sends (`push`, `send-email`, `send-pack`, `dcommit`) or is a shell alias (`!…`).
- **Guard performance.** Commands with none of the trigger words `gh`/`git`/`curl`/`wget` (checked after deleting quotes, backslashes, and newlines) are allowed immediately; segments without a trigger word are skipped; the duplicate outer segmentation pass is skipped when a command has no substitutions. A 600-segment one-liner went from about 10 s to 0.3 s and a 300-line `git` script from about 7 s to 1.6 s. The hook timeout is raised from 10 to 30 seconds.
- `contributor-readiness` and the skills reference now say readiness also runs in `prepare-pr`, with an explicit placement rule (Private notes, Pre-flight section; never in the PR description).
- `/oss` Step 4 now lists `report` and `prepare-pr` among the scenarios that dispatch `oss-researcher`.
- Docs (hooks reference, draft-only guardrail, GitHub access, commands reference, `/oss` Guardrail Reminder) describe the MCP allowlist instead of "all other MCP tools are allowed".
- Guard tests: 271 to 360 cases; 3 new known-bypass rows (`g$(true)it push`, `$'\x67'it push`, `git --config-env alias.p=ENV p`).
- **Guard review fixes (gh aliases):** `gh` built-in aliases are canonicalised before the write check (`new` = `create`, `remove`/`rm` = `delete`, `cs` = `codespace`), so `gh pr new`, `gh secret remove`, and `gh cs create` are denied.
- **Guard review fixes (wrappers):** more wrapper prefixes are looked through (`timeout`, `nice`, `ionice`, `stdbuf`, `setsid`, `caffeinate`, `doas`, `watch`, `unbuffer`, `flock`, `chrt`, `taskset`, `coproc`), and dashed git binaries (`/usr/libexec/git-core/git-push`, `git-send-email`) are treated as `git <cmd>`. `flock -c '…'` and `watch '…'` string commands are documented known bypasses.
- **Guard review fixes (git):** `git subtree push`, `git lfs push`, and `git p4 submit` are denied.
- **Guard review fixes (size cap):** a command over 64 KiB, with more than 2000 shell separators (counted before parsing), or with more than 500 whole-word trigger segments is denied instead of running into the hook timeout (which allowed it). Any analysis still running after 10 seconds is denied too. Segments are gated on whole-word `gh`/`git`/`curl`/`wget`, so `height`/`right`/`github` no longer count toward the cap.
- **Guard review fixes (env -S):** `env -S` / `--split-string` (any spelling) in a command that mentions gh/git/curl/wget is denied, since the guard cannot analyse the command string; `env -P` is skipped as an option with an argument.
- **Known bypasses added:** `find -exec`, `xargs`, persistent git aliases, `gh` extensions, and `hub`/`glab` are documented as not planned.
- **Guard review fixes (MCP):** the `*_read` suffix rule is replaced by the explicit `issue_read` and `pull_request_read`; `mark_all_notifications_read` and similar mutating tools are denied.
- **Guard review fixes (curl/wget):** `curl --expand-<option>` (curl 8.3+) is normalised to the plain option. wget `-X`/`-d`/`-F`/`--data`/`--form` are no longer treated as mutation (they are exclude-dirs/debug/force-html); `--body-data`/`--body-file` are denied. `curl -G`/`--get` with `-d`/`--data*` (query parameters) is allowed.
- **Guard review fixes (false positives):** help-only invocations of push-like commands and built-in gh groups (`git push --help`, `gh pr create --help`) are allowed.
- **Private debrief is not sendable:** the debrief file now carries `body_format: 2` and `sendable: false`; contract text says `body_format: 2` with no send block means nothing is sendable and `sendable: false` means never send.
- **issue-drafting** output uses `body_format: 2` with an `oss:send` block around the issue body, a trailing `## Private notes (not sent)`, and `TODO(you):` placeholders so unfilled drafts are refused.
- **Routing:** new rule 6 disambiguates review-reply lint, prepare-pr lint, and engage; row 10 lists lint-mode phrases.
- Guard tests: 360 to 442 cases (new regression rows plus size-cap checks).
- **Uncommitted work in debrief and prepare-pr:** `change-debrief` and `pr-preparation` may now run `git status --porcelain`, `git diff HEAD`, and `git ls-files --others --exclude-standard`, and include uncommitted and untracked changes in the debrief, the size check, and `diff_stats` (right after a coding-agent session the edits are often not committed yet). The draft says when uncommitted work was included.
- **GitHub MCP tool names:** `oss-researcher` and the docs named tools the current GitHub MCP server does not have (`get_pull_request`, `get_pull_request_files`, `get_pull_request_comments`). They now use `pull_request_read` with a `method` (`get`, `get_diff`, `get_files`, `get_review_comments`, `get_reviews`, `get_comments`, `get_status`) and `issue_read`; the `gh` fallback is unchanged.
- **Policy `unknown`:** `ai_policy` and `disclosure` gain an `unknown` value for "could not be checked". A failed preflight now sets `unknown` instead of `none-found`, so AP9 stays active and the user is told the policy could not be checked.
- **Guard: `gh agent-task`** (aliases `agent-tasks`, `agent`, `agents`) is denied for every subcommand except `list` and `view`; `gh agent-task create` starts a Copilot coding-agent task that opens a PR.
- **Routing:** rule 4 (PR intent) now lists "prepare a PR", matching `/oss`; the `/oss` description (shown in `/help`) mentions prepare-pr and debrief.
- **Docs:** README and the hooks reference note that the guard applies to every session where the plugin is enabled, and how to disable it via `/plugin`.
- Guard tests: 442 to 461 cases (`gh agent-task` and the new local git reads).

## [0.6.0] - 2026-10-21

### Added

- **`contributor-readiness` skill** and an advisory, private readiness self-check in `claim` and `find`, based on Andrew Lamb's review-priority tiers. It reads only the user's own public data (open PRs vs the project's cap, merged PRs, account age, vouch status, whether they use the project), shows which login was used (request, then `contributor.github_login`, then the authenticated account), maps to a tier, and gives constructive "how to move up" steps. Appears only in Private notes, never in an `oss:send` block, never blocks a draft. "skip readiness" opts out.
- `oss-researcher` scenario key `readiness` (dispatched in parallel with `oss-claim-analyst` in claim and with the normal fetch in find).
- Frontmatter fields `readiness_login` and `readiness`.
- Optional `contributor:` block (`github_login`, `uses`) and per-project `uses` in `config/targets.example.yaml` (local-only).
- `find` favours track-record work: repro, triage, and review items, a work-type and track-record-value line per item, triage-labelled issues and review-requested PRs in the fetch, and a score boost for areas you use.

### Changed

- `find` intake: Q1 adds reproduce/triage, review, and docs/tests; Q3 becomes "your relationship with this project" (still 5 questions).
- `find` ranking: good-first-issue bonuses apply only when `gfi_ai_ban` is not `true`; when it is, good first issues go in an unranked "Policy-reserved" footer with the policy source. New -2 for new-code items at the open-PR cap.
- `claim` leads Private notes with an open-PR-cap or vouch warning when applicable; the claim draft is still produced.
- Docs, README, and `oss-claim-analyst` (note only) updated. No guard changes; no new scenarios.

## [0.5.1] - 2026-10-21

### Security

- **`guard-outbound.sh` now denies the outbound command forms an agent may write by accident.** Each command segment is normalized (leading keywords and `VAR=value` assignments dropped; `env`, `command`, `exec`, `builtin`, `nohup`, `time`, `sudo`, `xargs` and their options stripped; a path-qualified binary reduced to its basename; `git` global options such as `-C`, `-c`, `--git-dir`, `--work-tree` and `gh` `-R`/`--repo` skipped) and checked in addition to the raw text, so no existing deny is loosened. Covers `git -C dir push`, `gh -R o/r pr create`, `/usr/bin/git push`, `env git push`, and `gh api` behind the same prefixes.
- New deny forms: `gh pr update-branch`; `gh label create/edit/delete/clone`; `gh workflow run/enable/disable`; `gh run rerun/cancel/delete`; `gh repo sync/rename/archive/unarchive`; `gh issue delete/transfer/pin/unpin/develop`; `gh secret`/`gh variable set/delete`; `gh gist edit/delete`; `gh alias set`; `gh codespace create`; `git send-email`, `git send-pack`, `git svn dcommit`; `curl --json/--data-binary/--data-urlencode/--data=`, `-dVALUE` and short-option bundles (`-sd`), `-T`/`--upload-file`, `-K`/`--config`, `--request=POST`, lowercase and any non-GET/HEAD/OPTIONS methods; `wget --body-data/--body-file` and lowercase `--method`.
- Heredoc handling and quote-aware segmentation are unchanged.

### Changed

- The 7 accidental-form `known-bypass` rows are promoted to `deny`, with about 130 new deny and allow rows (read-only forms such as `git -C dir log`, `gh -R o/r pr view`, `/usr/bin/git status`, `env git diff`, `gh label list`, `curl` GET still pass). Deliberate obfuscation (variables, `eval`, aliases, `bash -c`, heredoc quote tricks) stays documented as known-bypass.
- `docs/reference/hooks.md` Limits section and the deny matrices updated.

## [0.5.0] - 2026-10-21

### Added

- **Policy detection** in `contribution-norms`: AI policy files, CONTRIBUTING AI sections, PR-template disclosure checkboxes, AI co-author trailer rules, open-PR caps, vouch lists, good-first-issue AI rules, and issue-first rules. The `norms` briefing gains "AI Use Policy" and "Contribution Limits & Trust Gates" sections with sources and confidence. New `references/ai-policy-signals.md` holds the signal catalog, the `policy` block schema, and facts verified against live repos: DataFusion's `.asf.yaml` key `github.pull_requests.creation_cap.max_open_pull_requests`, Ghostty's `.github/VOUCHED.td` format, and the DataFusion AI policy source. Unverified project claims are listed as unverified.
- **Policy Preflight** (`/oss` Step 3a) for `find`, `clarify`, `claim`, `engage`, `review-reply`, and `report`: reuses a `policy` block from `.oss-drafts/` frontmatter when under 7 days old, otherwise dispatches `oss-researcher` (key `policy-preflight`). Advisory only; never blocks a draft. Absence is reported as not found, never "no policy".
- **Issue-first routing**: a PR-intent request with no issue reference routes to `report` when the project requires or recommends an issue first; the draft records `routed_from`. Routing is unchanged when the policy is unknown.
- Frontmatter fields `policy` and `routed_from`.

### Changed

- **AP9** (AI co-author trailer or "Generated with" footer) in review-reply lint is now active when the draft's `policy` has `coauthor_trailer_forbidden: true` or `ai_policy` other than `none-found`; otherwise it is reported as unevaluated.
- `oss-researcher` supports the `policy-preflight` key and may use `search_code` / `gh search code` (read-only).
- `issue-drafting` adds an issue-first / AI-policy note to Private notes and a `routed_from` message.
- Docs, README, and manifests updated for 0.5.0. Still 9 scenarios and a single `/oss` entrypoint.
- **The guard is documented as a tripwire, not a security boundary.** `docs/reference/hooks.md` gains a "Limits" section; `docs/guides/github-access.md` recommends a read-only fine-grained token as the real boundary. The test harness supports `known-bypass` rows: documented gaps that are reported but not counted as failures (9 recorded, including a heredoc-quote case already present in 0.4.0).

### Security

- `gh api graphql` read-only detection now rejects any `$` outside single quotes (positional and special parameters such as `$1`, `$@`, `$*`), not only `$NAME` / `${NAME}`.

## [0.4.0] - 2026-10-21

### Changed

- **`review-reply` no longer ghostwrites replies.** Maintainers (e.g. the Apache DataFusion AI policy, the "meat proxy" critique) reject AI-generated review replies. The default `brief` mode now produces a private per-comment understanding brief (quoted comment, code at the line, likely concern, conventions, commit-to-comment mapping, questions to ask yourself, optional bullet-only talking points) and a `TODO(you): reply in your own words` placeholder. There is no full-prose-reply option.
- The postable "change-summary comment" is removed; a commit-to-comment mapping table in the private brief replaces it.
- Translate/tidy is limited to text the user wrote, with no new claims.
- **Draft-tier files now use `body_format: 2`**: only text inside `<!-- oss:send:start -->` / `<!-- oss:send:end -->` is sendable; a `## Private notes (not sent)` section holds briefs and lint findings. Frontmatter gains `body_format` and (review-reply) `mode: brief|lint`.
- **Coordinated change required:** the separate execution/submission plugin must support `body_format: 2` (post only the send block, refuse while `TODO(you)` remains) before this release is used for posting. Otherwise private notes would be posted.
- `oss-researcher` now fetches PR commits with timestamps and review comments with `diff_hunk`, `path`, `line`, `created_at` for review-reply.

### Added

- **Lint mode** for `review-reply` ("check my reply", "lint my reply"): checks the user's own reply against anti-patterns AP1-AP9 (each with a bad/good pair in `smart-questions-principles.md`), quoting spans and asking questions, never rewriting. AP9 is defined but inactive until a policy profile exists (v0.5.0).
- New concept page `docs/concepts/maintainer-friendly-contributing.md` and nav entry; docs updated for the body format and the brief, write, lint flow.

### Security

- Removed v0.3.1 heredoc-body skipping in `guard-outbound.sh`: it allowed writing a script with a `cat`/`tee` heredoc and then executing it. Heredoc bodies are always checked again; use the Write tool to create files whose text mentions outbound commands.

## [0.3.1] - 2026-10-21

### Fixed

- **`guard-outbound.sh` no longer denies harmless multi-line commands.** `gh api` flags are now evaluated per `gh api` invocation instead of across the whole command string, so a heredoc that merely mentions `gh api`, `git push`, or `gh pr create` as text (e.g. `cat > notes.md <<'EOF' ... EOF`) is allowed. Heredoc bodies are skipped only when they are pure data (consumer is `cat`/`tee`, nothing piped or chained after the delimiter, quoted delimiter or no command substitution in the body, heredoc terminated); bodies fed to `bash`, `sh`, `eval`, `xargs`, `ssh`, `python`, `node`, etc. are still checked.
- **Read-only `gh api graphql` queries are allowed.** Allowed only when the command has no `mutation` keyword (case-insensitive, quote-splitting normalised), no `=@file` reference, no `--input`, no command substitution or unquoted shell expansion, and the `query=` value does not start with a shell variable.
- `gh api -X GET ... -f key=value` is allowed (fields are query parameters for an explicit GET).

### Security

- **Closed `gh api` mutation gaps:** `-F`, `--raw-field`, `--input`, `-XPOST`, `-X=POST`, `--method=POST`, attached `-fkey=value`, and case-insensitive method names are now denied.
- Command segmentation is quote-aware (separators inside quotes are ignored; an unclosed quote falls back to naive splitting, which can only over-deny), so a multi-line quoted `--jq` argument cannot hide a following `-X POST`.
- `gh api` options are now parsed from shell-unquoted tokens (method, fields, `--input`, endpoint), so text inside a `-f` value such as `-X GET` or `graphql` can no longer trigger an allow path; GraphQL is allowed only for the literal `graphql` endpoint, and `@file` values are detected after quote removal.
- Command/process substitutions no longer detach later flags (`--jq "$(...)" -X POST` is denied); heredoc bodies nested inside `$( )`, `<( )`, `( )` or backticks are kept and checked.
- If command segmentation fails, a `gh ... api` command is denied (fail closed) instead of being checked as one unsplit line.
- Any preprocessing failure falls back to the raw command (never fails open).
- **New regression harness** `hooks/tests/run-guard-tests.sh` with `hooks/tests/guard-cases.tsv` (98 allow/deny cases); compatible with macOS bash 3.2. Run with `bash hooks/tests/run-guard-tests.sh`.

## [0.3.0] - 2026-06-12

### Added

- **New `report` scenario (scenario 9).** `/oss draft a bug report for <repo> about <symptom>` and `/oss draft a feature request for <repo>` now route to the new `report` scenario, which drafts a complete, evidence-structured issue (bug or feature) for the user's review. The draft is never posted — it is saved to `.oss-drafts/report-<owner>-<repo>-<item>-<UTC>.md` and presented with the mandatory draft-tier notice.
- **New `issue-drafting` skill** (`skills/issue-drafting/SKILL.md`). Implements a three-step Pre-flight (duplicate search across open+closed issues, ISSUE_TEMPLATE fetch, title/label convention extraction) followed by two procedures: Procedure 2 — Bug Report (environment/version info, minimal reproducible example, steps to reproduce, expected vs. actual, error logs fenced, file:line references) and Procedure 3 — Feature Request (problem statement, proposed solution, alternatives considered, scope/impact, file:line references). Missing required evidence is always marked with `TODO:` placeholders; nothing is fabricated.
- **ISSUE_TEMPLATE application logic.** The skill handles four cases: (a) markdown templates (`.md`) — fills sections, strips HTML comments; (b) YAML issue forms (`.yml`/`.yaml` with `body:`) — maps content to form fields by `label`/`id`, flags `required: true` fields; (c) multiple templates — picks the type-appropriate one and tells the user which was chosen; (d) no template — uses built-in structure and notes this in the draft.
- **Duplicate-search pre-flight.** Before drafting, `oss-researcher` searches open and closed issues with the symptom keywords and surfaces the top 3–5 candidates. If a strong duplicate exists, the skill recommends commenting on the existing issue instead of filing a new one.
- **New user story** (`stories/draft-new-issue-bug-or-feature.md`) covering duplicate search, ISSUE_TEMPLATE application, evidence requirements, monorepo component selection, security/Discussions redirect warnings, and draft-only behavior.
- **Routing, command, and docs updates.** `oss-scenario-routing` SKILL.md, `commands/oss.md`, `docs/reference/scenarios.md`, `docs/reference/skills.md`, `docs/reference/commands.md`, `docs/guides/using-oss.md`, and `docs/concepts/draft-files.md` updated: nine scenarios, draft tier expanded to cover scenarios 5–9, `issue-bug`/`issue-feature` item values added, new examples added.
- **`README.md` updated.** Features list, examples, scenarios table, skills table, and documentation links reflect the new scenario and skill.

## [0.2.0] - 2026-06-12

### Added

- **Draft file export for all 8 scenarios.** The `/oss` orchestrator now writes every scenario output to `.oss-drafts/<scenario>-<owner>-<repo>-<item>-<UTC>.md` in the user's working directory using the Write tool. All scenarios (including read-only report scenarios 1–4) produce an editable markdown file with YAML frontmatter (`plugin`, `scenario`, `repo`, `item`, `generated_at`, `status: draft`).
- **Two-tier review protocol.** Report tier (scenarios 1–4: status, find, norms, setup) shows "Saved to `<path>`. Review and edit this report file as needed before using it." Draft tier (scenarios 5–8: clarify, claim, engage, review-reply) presents the draft in chat and shows the canonical notice: "**DRAFT — saved to `<path>`. Review and edit this file before sending.** This plugin will NOT post, comment, push, or send anything. Sending is handled by the separate execution/submission plugin."
- **Gitignore-ensure step.** Before writing the first draft file in a run, `/oss` appends `.oss-drafts/` to `.git/info/exclude` in the user's project (non-invasive; does not dirty the tracked `.gitignore`). Falls back gracefully if not in a git repo.
- **`Write` tool added to `/oss` allowed-tools.** Local file writes via Write cannot reach GitHub and do not violate the draft-only constraint.
- **New `docs/concepts/draft-files.md`.** Canonical reference for the draft file convention: directory, naming, frontmatter schema, two-tier review protocol, gitignore-ensure behavior, guardrail safety rationale, and two-plugin handoff via `status: draft`.
- **`.oss-drafts/` added to this plugin repo's `.gitignore`.**

## [0.1.0] - 2026-06-09

### Added

- Single `/oss` orchestrator command with 8-scenario routing and an interactive scenario menu when arguments are omitted.
- 8-scenario coverage: **status** (project news), **find** (issue/PR matching), **norms** (contribution guide + CLA/DCO), **setup** (dev environment walkthrough), **clarify** (draft maintainer questions), **claim** (availability check + draft claim comment), **engage** (draft in-progress PR feedback), **review-reply** (draft replies to review comments).
- `oss-researcher` read-only subagent — fetches GitHub issues, PRs, releases, and contribution docs via the GitHub MCP server or `gh` CLI fallback; paginated, timestamped, never mutates.
- `oss-claim-analyst` read-only subagent — checks assignee, linked open PRs, and recent intent comments; emits an "appears free to take" / "appears already claimed" verdict with an evidence table; automatic claim→engage branch switch when already claimed.
- `oss-scenario-routing` skill — classifies `$ARGUMENTS` into one of the 8 scenarios; handles the claim→engage branch transition; enforces one-question-max clarification.
- `issue-matching` skill — structured contributor intake (5 questions), heuristic scoring, top-5–10 ranked shortlist with per-item rationale.
- `smart-questions` skill — DRAFT-ONLY contract for scenarios clarify, engage, review-reply, and claim; four scenario-specific drafting procedures (A–D) with smart-questions principles.
- `contribution-norms` skill — locates and surfaces CONTRIBUTING, CODE_OF_CONDUCT, DCO, PR templates, and Apache-specific governance notes (ICLA, JIRA, dev@ mailing list, lazy consensus).
- `dev-env-setup` skill — step-by-step guided local setup extracted from official docs; flags heavy setups (Airflow Breeze, Spark JDK+Maven); defines an "environment ready" checkpoint; confirms before destructive actions.
- Draft-only `PreToolUse` guardrail hook (`hooks/hooks.json` + `hooks/scripts/guard-outbound.sh`) — DENIES `git push`, `gh pr/issue/release/repo` mutating subcommands, `gh gist create`, `gh api` write calls, `curl`/`wget` mutation flags, and all MCP write-verb tools; ALLOWS all read operations; denial message explains the two-plugin system.
- GitHub MCP server configuration (`.mcp.json`, `GITHUB_MCP_TOKEN` env var) with `gh` CLI fallback for all subagents.
- Configurable target-projects list (`config/targets.example.yaml`) with per-project label filters and global defaults for recency window, item types, and shortlist size.
