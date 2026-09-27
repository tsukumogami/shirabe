---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-coordinate-record.md
milestone: "coordinate-record"
issue_count: 9
---

# PLAN: coordinate-record

## Status

Active

## Scope Summary

Decomposes `DESIGN-coordinate-record` into nine outlines that turn the prose `/coordinate`
skill into a koto workflow with the record's tooling, all in the shirabe repository, landing as
one pull request.

## Decomposition Strategy

**Horizontal.** The design fixes every interface between the parts (the record codec's JSON,
`coord-log.sh`'s subcommands, each check script's verdict tokens and exit codes, and
`record-holding.sh`'s arguments), so each outline builds one layer to completion in the order the
design's Implementation Approach gives. The one integration risk, whether koto behaves as the
check-state contract assumes, is retired early by Issue 2's skeleton template rather than by a
walking skeleton across every layer. The template (Issue 7) comes after the scripts because it
names all of them.

## Issue Outlines

### Issue 1: feat(coordinate): record codec, renderer and parser

**Goal**: Give the record one codec that renders and parses the four sections and the discipline
handoff file with a byte-exact round trip, and run the skill's script tests in CI from the start.

**Acceptance Criteria**:
- [ ] `skills/coordinate/scripts/record-codec.jq`, `record-render.sh` and `record-parse.sh`
      render and parse the record body (declaration line, `Written:` time, Holdings, Deferrals,
      Side effects in flight, Reversals with the design's columns) and the handoff file
      (`--format handoff`, reasoning verbatim, predecessor copy with the fixed sentence).
- [ ] A rendered body parses back to its input, and two renders differ only in `Written:`.
- [ ] A cell holding a pipe, a newline, a backtick run or a fence opener round-trips unchanged
      and every row keeps its column count.
- [ ] The renderer refuses status, CI or merge-state keys; Worker values containing `/`, a UUID
      or 32-hex run, a `session_` prefix, a `+`, or only digits; a Phase other than
      `scoping-ahead`/`executing`; a Dispatch status other than
      `dispatching`/`dispatched`/`dispatch-failed`; a Return path other than `message` or
      `leg <request-id>:<leg>`; and any structured cell outside its grammar. It accepts a
      dispatch topic and an empty Branch.
- [ ] `references/record-template.md` shows the new columns and the Disposition forms.
- [ ] `.github/workflows/check-coordinate-scripts.yml` runs every `skills/coordinate/scripts/*_test.sh`
      on Linux and macOS; `requires.tsv` declares `jq`.
- [ ] Each script has a passing `_test.sh`, bash 3.2 clean.

**Dependencies**: None

**Type**: code
**Files**: `skills/coordinate/scripts/record-*`, `skills/coordinate/references/record-template.md`, `.github/workflows/check-coordinate-scripts.yml`, `skills/coordinate/requires.tsv`

### Issue 2: feat(coordinate): session-log helper, verdict gate and a skeleton template

**Goal**: Build the shared seal helper and the gate helper, and prove the koto behaviour the
check-state contract relies on against a skeleton template driven by real koto.

**Acceptance Criteria**:
- [ ] `coord-log.sh` implements `seal`, `check`, `capture [--for]`, `directed-since`,
      `run-facts`, `run-start`, `provenance` and `live-session`, each with exit codes and usage.
- [ ] `coord-verdict.sh <state> <capture>` checks the seal and exits with the verdict's code.
- [ ] An engine test drives a three-state skeleton template and shows: a capture reaches the same
      state's command gate in one advance; a token sealed at one visit fails `check` after a later
      entry into that state; an unrouted verdict leaves the state blocked; `koto next --to` leaves
      a `directed_transition` event `directed-since 0` finds; `provenance` fails for a session
      started from an edited copy of the template.
- [ ] The engine test uses the path workaround for a plugin root containing `+`, and skips (never
      passes silently) when koto is absent; CI asserts the koto floor first.

**Dependencies**: <<ISSUE:1>>

**Type**: code
**Files**: `skills/coordinate/scripts/coord-log.sh`, `coord-verdict.sh`, their tests and `testdata/`

### Issue 3: feat(coordinate): find, open, write and confirm the record; start and posture reads

**Goal**: Implement the record's lifecycle scripts and the start reads, each a check script that
prints one sealed token or an agent-run write that re-reads GitHub and the log first.

**Acceptance Criteria**:
- [ ] `record-find.sh` (roadmap scope) lists every open issue through a paginated read, matches
      the title exactly, needs the declaration line and an author and last editor with write
      access (failing closed on a failed permission read), checks the four sections, and prints
      `found`, `none`, `ambiguous`, `no-declaration`, `malformed` or `unauthorized`; a stand-in
      `gh` that serves 150 open issues and fails any search path passes every case (record among
      150, closed issue ignored, `-v2` title ignored, two matches).
- [ ] At discipline scope it prints `found`, `predecessor`, `foreign`, `ambiguous`,
      `stale-branch`, `unopened` or `none`, ignores a pull request from another branch or a fork,
      and parses the rotation title's dates.
- [ ] `record-open.sh`, `record-write.sh` (whole body, `--end`, `--close`) and `record-holding.sh`
      (`--session`, `--topic`, `--row-file` or `--read`) behave as the design's interface says,
      with its exit codes; each refuses on failed provenance or a directed transition in the run;
      `record-holding.sh` replaces a topic's row rather than adding a second.
- [ ] `record-confirm.sh` derives the expected change from the source state in the log and
      confirms it on GitHub with a newer `Written:` time, for every source the design lists.
- [ ] `start-check.sh` reads the roadmap's status from the host's default branch;
      `posture-read.sh` reads the workspace and instance settings and hooks without running any,
      and reports `permit`, `deny`, `confirm` or `unread` for merge, close and teardown.
- [ ] No check script makes a `gh api` call without `--method GET` or sends a GraphQL mutation.

**Dependencies**: <<ISSUE:1>>, <<ISSUE:2>>

**Type**: code
**Files**: `skills/coordinate/scripts/record-find.sh`, `record-open.sh`, `record-write.sh`, `record-holding.sh`, `record-confirm.sh`, `start-check.sh`, `posture-read.sh`, tests

### Issue 4: feat(coordinate): board read, land check and merges

**Goal**: Read and judge the CI board at a pull request's head, re-read it at land, and merge or
confirm a merge only against the verified head.

**Acceptance Criteria**:
- [ ] `board-verdict.sh` prints one JSON verdict with the design's reason codes; `board-record.sh`
      turns it into a sealed `verified`, `unverified` or `pending` token and writes
      `coord/board.json`.
- [ ] A complete board where every job ran on a named runner with a succeeded step verifies; a
      non-required skipped job and a re-run that passed both verify, and the report lists them.
- [ ] Each of zero runs, runs only for another sha, `startup_failure`, a queued run, a job without a
      runner, a job whose steps were all skipped, a `failure`/`cancelled`/`neutral` job, a required
      check missing or skipped, and merge state `DIRTY` records no head.
- [ ] `land-check.sh` refuses a head that moved since the unit's own verify capture;
      `land-merge.sh` reads land's capture from the log, re-reads the posture, refuses on a
      directed transition, and calls `skills/execute/scripts/merge-exec.sh`; `--closeout` does
      the same for a rotation's record pull request.
- [ ] `merge-confirm.sh` and `merged-facts.sh` compare the default branch's blobs with the unit's
      verified head and report merged or unconfirmed.
- [ ] A change under `.github/workflows/` or `.github/actions/` is reason code `workflows-changed`.

**Dependencies**: <<ISSUE:2>>, <<ISSUE:3>>

**Type**: code
**Files**: `skills/coordinate/scripts/board-*.sh`, `land-check.sh`, `land-merge.sh`, `merge-confirm.sh`, `merged-facts.sh`, tests

### Issue 5: feat(coordinate): rotation and roadmap close-outs

**Goal**: Read each close-out stage from GitHub and make every close-out write an agent-run step.

**Acceptance Criteria**:
- [ ] `predecessor-handoff.sh` renders a predecessor's handoff from its record body, with its
      tables under "not re-checked" and the fixed reasoning sentence.
- [ ] `closeout-read.sh --scope discipline` reports `handoff-missing`, `title-stale`, `land`
      (only when the record pull request's board verifies), `merged`, `handed-over` or
      `closed-unmerged`; `--predecessor` checks the copied tables; `--scope roadmap` reports
      `ready`, `features-open`, `holdings`, `side-effects`, `deferrals` or `closed`.
- [ ] `rotation-close.sh --step handoff|ready|delete-branch` refuses when a fresh read disagrees.
- [ ] Tests cover early end-date correction, a hand-over, a predecessor close, and a roadmap with
      one feature not Done or one undisposed deferral.

**Dependencies**: <<ISSUE:1>>, <<ISSUE:3>>, <<ISSUE:4>>

**Type**: code
**Files**: `skills/coordinate/scripts/predecessor-handoff.sh`, `closeout-read.sh`, `rotation-close.sh`, tests

### Issue 6: feat(coordinate): deferral check, pick and report facts, quiet sweep

**Goal**: Implement the turn's and the spokes' check scripts.

**Acceptance Criteria**:
- [ ] `deferral-check.sh` passes rows disposed as `filed #12` (an existing issue),
      `closed: <reason>` and `carried <time after run start>: <reason>`, and a `None.` section; it
      refuses an earlier carry time, `filed` without a number, an empty Disposition, and a
      predecessor handoff deferral missing from the record (read from the host's default branch,
      compared until the first pass in the run); it reports `at-cap` at the cap or the parked
      bound, where `send_execution` adds no active worker.
- [ ] `pick-facts.sh` prints `pick`, `scope-complete` or `rotation-over` and writes
      `coord/pick.json`; `report-facts.sh` finds a holding by topic, refuses an out-of-scope
      repository, a fork head, or a mismatched Branch (skipped while Branch and Pull request are
      both empty), and writes `coord/report.json`.
- [ ] `quiet-check.sh` counts silent checks per topic from the log and reports first and second
      silences without any teardown.

**Dependencies**: <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:5>>

**Type**: code
**Files**: `skills/coordinate/scripts/deferral-check.sh`, `pick-facts.sh`, `report-facts.sh`, `quiet-check.sh`, tests

### Issue 7: feat(coordinate): the coordinate workflow template

**Goal**: Carry the loop as `skills/coordinate/koto-templates/coordinate.md`, with every state the
design lists, the check-state contract, and the two shadow deciders.

**Acceptance Criteria**:
- [ ] `coordinate.md` and `coordinate.mermaid.md` pass compile, directives, mermaid freshness,
      interpolation, decider declarations, init sites and entry floor; the template carries the
      `# koto-floor: pinned` marker.
- [ ] Every check state has no `accepts`, one non-overridable command gate over its capture, and no
      context gate beyond a decider input's `context-exists`; a structure test enforces it and fails
      if a write script appears in any default action or gate, or a directive names
      `merge-exec.sh`.
- [ ] Shadow deciders on `pick.choice` and `classify_report.classification`, with fixtures (at least
      ten per value and forty per decider) and rows in `scripts/decider-declarations.tsv`.
- [ ] Engine tests against a stand-in `gh`: dispatch unreachable without exactly one record;
      unreachable with an undisposed deferral and reachable once disposed; land unreachable until a
      verified head is recorded; a moved head refused at land; `koto overrides record` refused on
      every check gate with and without data; evidence contradicting the stand-in doesn't change a
      check; every `wait` event reaches its spoke without a `template_error`.
- [ ] Each state's longer guidance sits behind a details marker, carries its rules from the prose
      skill, and names the reference it uses; the pick guidance states the cap of five kept full,
      scoping ahead, asking up, the parked bound of three, and what doesn't count.

**Dependencies**: <<ISSUE:3>>, <<ISSUE:4>>, <<ISSUE:5>>, <<ISSUE:6>>

**Type**: code
**Files**: `skills/coordinate/koto-templates/*`, `scripts/decider-declarations.tsv`, template tests

### Issue 8: feat(coordinate): thin skill contract, opener and report

**Goal**: Make `SKILL.md` the thin contract and give the skill its opener and report.

**Acceptance Criteria**:
- [ ] `coordinate-open.sh` maps the invocation to variables with `jq`, sets the host at roadmap
      scope, asks once (and opens nothing) at discipline scope without `--host`, cancels without
      cleaning any live run of the same scope, and opens a fresh per-run session through
      `scripts/koto-open.sh`; malformed arguments are refused before any session exists.
- [ ] `coordinate-report.sh` prints the report from the terminal result through closed patterns.
- [ ] `SKILL.md` states the flags, how to open, tick (with `--no-cleanup` on every tick), report and
      the final states, holds no step procedure, and carries Known Limitations naming shirabe#395,
      #396, #398, koto#250, koto#251 and shirabe#401 with what each costs.
- [ ] The bounds section states the cap of five and the parked bound of three; `brief-template.md`
      states that a koto session binds to the directory it starts in, so a worker starts it where it
      will work; "What This Version Leaves for Later" names the dispatch path and reconcile.
- [ ] `references/koto-session-retention.md` gains an adopters row.
- [ ] A rule-coverage fixture lists every rule of the prose skill against the state or file that
      carries it, and a test checks each key phrase is present there.
- [ ] A hygiene test over the skill's files finds no `wip/` path, private repository name, session
      id, instance name or UUID-shaped string.

**Dependencies**: <<ISSUE:7>>

**Type**: code
**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/references/*`, `skills/coordinate/scripts/coordinate-open.sh`, `coordinate-report.sh`, `references/koto-session-retention.md`, tests

### Issue 9: feat(coordinate): requirements, CI lists and evals

**Goal**: Declare what the skill needs, wire it into the koto CI lists, and bring its evals up to the
template.

**Acceptance Criteria**:
- [ ] `requires.tsv` declares the koto floor and every tool and koto subcommand the skill's files
      call; `check-skill-requires.sh` and preflight pass.
- [ ] `check-koto-entry-floor.yml` compiles `coordinate.md` and runs the skill's engine suites.
- [ ] `evals/evals.json` keeps the nine scenarios, tightened per shirabe#403, and adds: the record
      found instead of duplicated after a restart; a deferral blocking the first dispatch; a verified
      head recorded before a land step; pick filling the cap, scoping ahead, and asking up; three
      parked workers stopping new dispatches.
- [ ] An eval run passes every scenario.

**Dependencies**: <<ISSUE:8>>

**Type**: code
**Files**: `skills/coordinate/requires.tsv`, `skills/coordinate/evals/*`, `.github/workflows/check-koto-entry-floor.yml`

## Implementation Sequence

Dependencies: 2 on 1; 3 on 1 and 2; 4 on 2 and 3; 5 on 1, 3 and 4; 6 on 2, 3 and 5; 7 on 3 to 6;
8 on 7; 9 on 8.

Critical path: 1, 2, 3, 4, 5, 6, 7, 8, 9. Issues 4 and 6 depend only loosely on each other through
Issue 5, so after Issue 3 the board work (4) and the deferral and facts work (6, less its
predecessor comparison) can proceed side by side, rejoining before the template.
