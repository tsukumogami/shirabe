---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: flag
split_rationale: |
  Hard Constraint. The window value is a change to another repository, niwa,
  and it can land only after another plan's first four steps reach niwa main;
  worker switch-on then waits on a niwa release. One pull request, or a
  coordinated set merging behind a last one, would hold every shirabe step
  behind that external work. Each shirabe step is also useful on its own.
tracking_level: none
upstream: docs/designs/DESIGN-handoff-brief.md
milestone: "Handoff brief"
step_count: 9
---

# PLAN: Handoff brief

## Status

Active

## Scope Summary

shirabe ships the pieces that let a session compact in place and still find
its way back, and that let a session that stops hand its reasoning and files
forward. A brief script writes one verified brief into the session's koto
session, with small named files stored inside it, two named limits, and a keep
record only where a workspace asks for one. A closing step checks the worktree
before the brief at a run's end. A compaction note, kept current in koto,
feeds two hook commands in the shirabe binary: `shirabe compaction
pre-compact` shapes the summary and flags a stale note, and `shirabe
compaction re-anchor` sends a compacted session back to its skills, its koto
run and its note. A context reader reports the size right after a compaction,
with its boundaries and the window in force, and a thrash check reads only
that report.

niwa gains one generic value on its planned dispatch profiles,
`auto_compact_window`, and a workspace default profile, so a window follows
the role a session is dispatched in. That change is its own niwa pull request
and knows nothing of shirabe; shirabe's pieces call no niwa command and read
no niwa file, and a session without niwa sets the window in its own settings.
Roles then switch on in order: workers, coordinators once their workflow
re-anchors and a superseding decision exists, and supervising sessions last.
Nothing is filed: the steps are the work items.

## Decomposition Strategy

Walking skeleton. Step 1 runs one background session through a real
compaction at a low test window, launched by hand with the window in a
`--settings` document's `env` block, the same carrier niwa will use. It
crosses the note writer, the ledger, both hooks and Claude Code's compaction,
and reads the session's id and liveness before, during and after; that is
the identity read every switch-on waits on. Step 2 adds the brief at a run's
end that another session reads, with every refusal that keeps a secret out of
a koto key. Each later step adds one behaviour on top: the brief's limits and
opt-in keep record, the stale-note flag and ledger checks, the
post-compaction reader and thrash check, the niwa window value, and then each
role switching on in order.

## Steps

### Step 1: A compacted background session comes back to its own skill and run under the same session id

**Goal**: Cross the note writer, the ledger, both `shirabe compaction` hooks and Claude Code's compaction on one real input: a `--bg` session launched by hand in a test instance, with `CLAUDE_CODE_AUTO_COMPACT_WINDOW` set in a `--settings` document's `env` block to a stated test value no lower than the instance's measured harness floor plus 90K (about 150K, and never under Claude Code's 100K minimum) and the two hooks installed as instance hooks by absolute path, running a koto-backed skill. After its compaction the session keeps its id, stays live, and goes back to the skill it was running and that skill's koto session before doing anything else. A minimal `handoff-brief.sh note` writes `compaction/note.md` and a ledger entry with one `skill:` line, `shirabe compaction pre-compact` prints the summary instruction, and `shirabe compaction re-anchor` prints the re-read list. The stale flag, grammar checks beyond the session id, and the generic no-entry line come in later steps.

**Acceptance Criteria**:

- [ ] Run from inside the koto-backed skill, `handoff-brief.sh note --reasoning <file> --skill "<name> <args> <SKILL.md path>"` exits 0. Reading `compaction/note.md` back from the skill's koto session prints the reasoning text. The ledger file `$XDG_STATE_HOME/shirabe/compaction/<session-id>` (or the same path under `$HOME/.local/state`) is mode 0600 in a 0700 directory and holds one line each for the koto session, note key, branch and pull request, plus exactly one `skill:` line with that skill's name, arguments and `SKILL.md` path.
- [ ] Given a hook input carrying that session id on stdin, `shirabe compaction pre-compact` exits 0 and prints a summary instruction that names the koto session, branch, pull request, note key and the recorded `SKILL.md` path.
- [ ] Given the same input, `shirabe compaction re-anchor` exits 0 and prints a block that says to re-read the recorded `SKILL.md` path, then run `koto status` on the named koto session, then read the named note key. Piped through `wc -c`, the output is under 10,000 characters, and it contains neither the note's text nor the skill's text.
- [ ] Both hooks never block a compaction. With the ledger entry deleted, each exits 0 and prints nothing that came from the hook input. With the shirabe binary moved away from the absolute path the installed hook script names, each hook script exits 0 and prints nothing. A session id that fails its grammar (one holding `/`, `..` or a newline) also gets exit 0 and no output, and no file outside the ledger directory is opened.
- [ ] Across one real compaction of the `--bg` session, the job state file is read three times: before the compaction, while it runs, and after. At every read its `sessionId` equals the launch id, its `state` is a live one (such as `working` or `idle`), and `firstTerminalAt` is still null; a read where the id differs, the state is terminal or `firstTerminalAt` is set fails the step. `niwa list --json` may be read alongside, but its record is noted only as what niwa shows for the instance and never counts as evidence the session is live, since niwa keeps that record whether or not the session runs. Because the session's own process writes the job state file, a stale file proves nothing alone: the records after the `compact_boundary` record sit in the launch transcript file and carry the launch `sessionId`, no job directory for any other session id appears during the window, the process that owns the state file is alive after the boundary, and the session makes at least one tool call after it.
- [ ] In the session's transcript, the records after the `compact_boundary` record carry the re-anchor text. The session's first tool calls after it are a read of the recorded `SKILL.md` and `koto status` on the recorded koto session, before any other tool call.
- [ ] Before the launch, the harness floor in the test instance is read and recorded, and the window used is stated next to it and is at least that floor plus 90K. The session reaches exactly one compaction boundary in the window it is given; two or more boundaries within 30 assistant turns fail the step as thrash rather than being recorded as a carrier result.
- [ ] `references/handoff-brief.md` states the identity result (id unchanged or changed, session live or not), whether the invoked skill's text survived in the summary, and whether the window reached the session from the settings document, including what `printenv CLAUDE_CODE_AUTO_COMPACT_WINDOW` prints from a command the test session runs. The reference also says no role switches on until the identity result shows the id unchanged and the session live.

**Check**: In a test instance, install the two hook scripts as instance hooks (`pre_compact`, and `session_start` matched on `compact`), each naming the shirabe binary by absolute path. Read the harness floor in the test instance (the size of a fresh session before its first task) and write a settings document whose `env` block sets `CLAUDE_CODE_AUTO_COMPACT_WINDOW` to a stated value of at least that floor plus 90K. Launch a `--bg` session by hand with `--settings` pointing at that document, and give it a koto-backed skill to run. Note the launch id, read the job state file's `sessionId`, `state` and `firstTerminalAt`, and confirm the session ran `handoff-brief.sh note` and the ledger entry exists. Let the session pass the test window once, reading the job state file's `sessionId`, `state` and `firstTerminalAt` again while the compaction runs. Afterwards read them a third time. At all three reads the id must equal the launch id and the session must be live (a live `state` and a null `firstTerminalAt`); if any read shows a different id, a terminal state or a set `firstTerminalAt`, the check fails. Record what `niwa list --json` shows for the instance at each read as niwa's view only, not as a liveness result. After the boundary, confirm the post-boundary records are in the launch transcript file under the launch `sessionId`, that no new job directory for another session id appeared, that the state file's owning process is alive and that the session made a tool call; count the boundaries and fail on two or more within 30 turns. Have the session run `printenv CLAUDE_CODE_AUTO_COMPACT_WINDOW` and record what it prints. Open the transcript, find the `compact_boundary` record, and confirm the re-anchor text follows it and that the next tool calls are a read of the recorded `SKILL.md` and `koto status` before anything else. Look in the summary for the invoked skill's text, and check whether the compaction fired at the test window, which shows the window reached the session from the settings document. Then run both hooks by hand once with the ledger entry deleted and once with the binary moved, and check each exits 0 with no output. Write all of it into `references/handoff-brief.md`.

**Dependencies**: None

**Files**: `scripts/handoff-brief.sh`, `crates/shirabe/src/compaction.rs`, `crates/shirabe/src/main.rs`, `references/handoff-brief.md`

### Step 2: A run's end hands forward a brief that another session reads, and refuses anything secret-shaped

**Goal**: `closing-step.sh <worktree>` blocks on a stray file or an unpushed commit and passes otherwise; `handoff-brief.sh write --event end` then stores `brief/brief.md` with Reasoning, Pointers, Files and Standing rules and one named scratch file inline at `brief/files/<sha256>`, refusing an empty reasoning, a bad path (not a regular file, a symlink, a link count above 1, outside scratch, any dot-directory at the instance root), a credential basename, or a token-shaped hit in a file, the reasoning or a watch value. `handoff-brief.sh read` from another session prints the brief with the reasoning in a fresh fence and the file's hash verified. No keep record is written (the opt-in record, the two limits, park and resume are step 3).

**Acceptance Criteria**:

- [ ] `closing-step.sh <worktree>` with an untracked file that `git check-ignore` doesn't match prints `closing=blocked` and a line naming that file, and exits 1. With a commit not yet on the upstream, or a branch with no upstream, it prints `closing=blocked` with a line naming the unpushed commit or missing upstream, and exits 1. Once both are resolved it prints `closing=pass` and the instance root and exits 0, the worktree still exists at the pushed head, and it reports done only when the caller's working directory is outside the worktree. With `git` not on `PATH` it exits 2.
- [ ] With a koto run, `write --event end` exits 0 and `koto context get <session> brief/brief.md` returns a brief with the four sections in order: Reasoning holds the planted concluded, ruled-out (with its reason) and next-step markers verbatim; Pointers shows the koto session, `branch` equal to `git branch --show-current`, `pushed_head` equal to the remote branch's commit (the remote's commit when local HEAD is one ahead), and each `--watch` label with its exact re-arm command; Standing rules reads `None stated.` when no rules file is given. Afterwards no file under the instance, the worktree or the system temp directory holds the reasoning marker.
- [ ] With a stub `gh` on `PATH` that reports an open pull request with a known number, the brief's Pointers show `pull_request` equal to that number. With a stub `gh` that reports no open pull request for the branch, `write --event end` still exits 0, the brief is stored at `brief/brief.md` with all four sections, and Pointers show `pull_request: none`.
- [ ] Each named file is stored at `brief/files/<sha256>` holding its exact bytes, and the Files line shows its scratch path, a sha256 equal to `sha256sum` and its byte count at write time, including for a file rewritten after the session chose it; an empty file shows 0 bytes and the sha256 of empty input. An unnamed scratch file's path and content appear in no `brief/` key, and no keep record file is created anywhere.
- [ ] With `KOTO_SESSION` unset and a job id present, `write` opens a plain koto session `handoff-<job-id>`, prints its name and the key `brief/brief.md`, and leaves it closed `done`; from a new session, `koto context get handoff-<job-id> brief/brief.md` still returns the brief. With no job id but a session id, the session is `handoff-<session-id>`. With no koto run, no job id and no session id, `write` exits 1 naming the missing identity and opens no koto session.
- [ ] Reasoning that is empty or whitespace-only exits 1 naming the empty reasoning, and no `brief/` key exists afterwards. A reasoning or watch value with a line beginning `## `, a watch value holding a shell operator, a tab or a control character, and a token-shaped string in the reasoning or a watch value each exit 1 naming the cause, with no key written.
- [ ] Naming a directory, a symlink, a path with a symlink in it, a file with a link count above 1, a missing or unreadable file, a file inside a repository worktree, or a file under a dot-directory at the instance root (such as `.claude/`) each exits 1 naming the path and the reason, with no `brief/` key written.
- [ ] Naming a file whose basename matches a credential pattern (`.env`, `id_rsa`, a `*.pem` file) exits 1 naming the basename rule; naming a scratch file whose content holds a token of any shape the reference lists (`ghp_`, `gho_`, `ghs_` and `github_pat_` GitHub tokens, an `sk-ant-` key, an `AKIA` access key id), a PEM private key block or a JWT-shaped string exits 1 naming the file and the kind of match. In each case no `brief/` key is written. Reasoning that quotes a 40-hex git commit id or a 64-hex sha256 is not refused.
- [ ] `read --session <name>` from another session prints the brief with the Files section after the free text and the reasoning between delimiters that differ on each call, so a reasoning line copying an earlier call's delimiter stays inside the fence. It reports each inline file's hash as verified, and reports a mismatch when a stored file key's bytes are altered. It prints a watch's re-arm command as text without running it (a watch command that would create a marker file leaves no file), marks control and format characters, and writes no file bytes to disk.
- [ ] Every `handoff-brief.sh` subcommand exits 0 when done, 1 when it refuses with a named cause and nothing written, and 2 when koto, git or gh is unavailable. With `gh` absent from `PATH`, `write` exits 2 and no `brief/` key is written, which stays distinct from a `gh` that runs and finds no open pull request (exit 0, `pull_request: none`).

**Check**: Run the tests for both scripts, which build a test instance with a repository worktree pushed to a local bare remote and two scratch files, one named. Plant a stray file and an unpushed commit and see `closing-step.sh` print `closing=blocked` naming each and exit 1; clear the file, push, and see `closing=pass` with the instance root and exit 0. Then, with a stub `gh` on `PATH` that reports pull request 42, run `handoff-brief.sh write --event end` with a reasoning file holding three markers, the named file and one `--watch`, and from a second session run `handoff-brief.sh read --session <name>`: it shows the markers, the branch, `pull_request: 42` and the pushed head, the watch command as text, and the named file with a sha256 equal to `sha256sum` of that file, while `grep` for the unnamed file's path and content over every `brief/` key finds nothing. Swap the stub for one that reports no open pull request and run `write` again: it exits 0 and `read` shows `pull_request: none`. Remove `gh` from `PATH` and run `write`: it exits 2 and `koto context` lists no new `brief/` key. Repeat `write` naming in turn a planted `.env`, a scratch file holding a `ghp_`-prefixed 36-character string, a symlink and a hard link: each exits 1 with a message naming the cause, and `koto context` lists no new `brief/` key. A whitespace-only reasoning file exits 1 and leaves no `brief/brief.md`.

**Dependencies**: None

**Files**: `scripts/handoff-brief.sh`, `scripts/handoff-brief_test.sh`, `scripts/closing-step.sh`, `scripts/closing-step_test.sh`, `references/handoff-brief.md`

### Step 3: Named files obey the two limits, and a workspace that opts in gets a keep record

Inline size and record cap enforced by name, `--keep-record`/`HANDOFF_KEEP_RECORD` writing the record under its lock with computed `protects`, and park, resume and `brief/resumed` voiding a hold.

### Step 4: A compaction over a stale note says so, and only a valid ledger entry reaches the model

The pre-compact stale flag from koto's latest seq and the branch's newest commit, the ledger's permissions, no-follow open, grammar and `KOTO_SESSION` checks, cleanup after 30 days, and the generic re-anchor line pointing at `read --note`.

### Step 5: A session and its supervisor read the size right after a compaction and see when compaction stopped helping

`context-size.sh` prints context_tokens, boundaries, boundary_turns, window and hard_stop from any directory, and `thrash-check.sh` reports can't-continue on three boundaries in 30 turns or a size over the hard stop.

### Step 6: A niwa dispatch profile gives one role a compaction window at dispatch

In niwa, its own pull request once the dispatch-profile plan's first four steps are on niwa main: `auto_compact_window`, `[session] default_dispatch_profile`, the load refusals, the launch-settings render, the inherited-window drop, resume and retask carrying the recorded window, the guide, then a niwa release.

### Step 7: Workers compact in place in production

A workspace configuration sets the worker window in its default profile, gives the coordinator profile none, installs both hooks and, in the same switch-on, moves the workspace's stop rule for workers from 280K to the 350K hard stop, and a worker passes 280K with no brief and no successor, stopping only at its 350K hard stop.

### Step 8: Coordinators compact in place

Once coordinate re-anchors, writes on arrival, re-reads its record, re-arms its watches and prints the window at its start (R19), and the superseding decision exists (R23), coordinators switch on with their window and 375K stop checked against measured post-compaction size and the largest single-turn growth, and the workspace's stop rule for coordinators moves from 300K to the 375K hard stop in the same switch-on.

### Step 9: Supervising sessions compact in place

Supervising sessions above coordinators switch on last, each with a window set from its measured post-compaction size and a hard stop at 1.25 times it.

## Implementation Sequence

Steps 1 and 2 start at once, in shirabe. After step 1, step 5 can run beside
step 3 (which follows step 2), and step 4 follows steps 1 and 2. Step 6 is a
niwa pull request that starts once the dispatch-profile plan's first four
steps are on niwa main, and it can run beside every shirabe step. Step 7
waits on steps 1 to 6 and a niwa release carrying step 6; steps 8 and 9 follow
in order.
