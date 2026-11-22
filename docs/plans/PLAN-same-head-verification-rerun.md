---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-same-head-verification-rerun.md
milestone: "Re-running a verification at the same head"
step_count: 4
---

# PLAN: Re-running a verification at the same head

## Status

Active

## Scope Summary

This design gives `/work-on` a named, recorded way to re-run verification at
the same head and merge-base: an agent submits `verification_rerun` at
`implementation` after a failed command, or `rerun` at the gate's existing
exit-5 hold after an eligible timeout with nothing failed, and the launcher archives the outgoing attempt into a
`verification_attempts` ledger before starting a fresh suite in a fresh poll
window, capped at two re-runs per head and merge-base. Logs move to
per-attempt folders from the first run, and the PR body must carry one re-run
line per archived attempt.

## Decomposition Strategy

Walking skeleton, as a step plan delivered in one pull request. Step 1 is the
exit-1 route end to end on one real input: a suite with a failed command at a
head, the agent's `verification_rerun` with a reason, the lap through
`changed_paths_record` back to `verification`, and `--start` turning the
request into an archived attempt and a fresh suite. The eligibility check is
the thinnest one that route needs, and the cap, the integrity guards and the
gate's ledger read are left for later steps. Step 2 makes each archived
attempt visible to a reviewer in the PR body. Step 3 bounds re-runs and
hardens the ledger, and step 4 adds the timeout route: a `rerun` edge at the
gate's existing exit-5 hold and the `75 + rerun` edge, landing together in one
commit.

Step 1 comes first because its lap rests on the design's one assumption that
was traced in koto's source but never run: that a target state's default
action reads an edge's `context_assignments` in the same tick. Step 1's
routing case runs that read against real koto instead of tracing it. If the
assertion fails, the design's fallback applies: the agent runs `--archive`
before it submits, and the `75 + rerun` edge keeps that order routable.

This order departs from the design's own phase order. The design lands the PR
body check (its Phase 3) and the cap and ledger integrity work (its Phase 1)
before any route can trigger a re-run, so each piece is inert until the next
one routes to it. This plan opens the exit-1 route in step 1, adds the PR body
check in step 2 and the cap in step 3. Because all four steps land in the same
pull request, no state between steps ships: the route, the PR body check and
the cap reach users together, as the design's order intends. Step 1's handling
of the reason is provisional until step 3 adds reason cleaning and path
validation.

## Steps

### Step 1: A failed command at the same head re-runs once on request

**Goal**: An agent that judges a failed verification command to be a flake can submit `implementation_status: verification_rerun` with a reason and get a fresh suite at the same head. The step runs one real input, a result with a failed command at head H, through the template edge, the `run-verification.sh --start` launcher and koto context.

**Acceptance Criteria**:

- [ ] After a failed-command result at head H, submitting `implementation_status: verification_rerun` with a reason in `rationale` brings the session back to `verification`, and afterwards `koto context exists` reports `verification_rerun_request` missing.
- [ ] After that lap, `verification_attempts` holds exactly one line that `jq` parses. It names attempt 1, folder 1, head H, the merge-base and the submitted reason. A reason holding a double quote still gives one parseable line.
- [ ] After that lap, attempt 1's `result.json` and `run.json` are under `<head>/attempts/1/` next to its logs, and a new supervisor is running with its command logs under `<head>/attempts/2/`.
- [ ] A first suite at a head writes each command's log under `<head>/attempts/1/` as `<index>-<id>.log`, with every id character outside `[A-Za-z0-9._-]` replaced. The folder is mode `0700`, each log is `0600`, and `result.json` and `run.json` sit at `<head>/`.
- [ ] `run-verification.sh --archive --reason <text>` exits non-zero on an empty reason, a running suite or a passing result. Each time it moves no file and leaves `verification_attempts` unchanged.
- [ ] When `--start` finds `verification_rerun_request` next to a passing result, it removes the key, says why on stderr and reuses the pass as it does today, with no new attempt folder and no ledger line.

**Check**: From the repo root, run `bash skills/work-on/scripts/output-gates-routing_test.sh` and confirm it exits 0. Its new case drives real koto from a failed-command result through `implementation_status: verification_rerun` back to `verification`, calling the real `run-verification.sh` rather than a fake. It then checks the session state, the missing request key, the one ledger line, attempt 1's files under `<head>/attempts/1/` and the running attempt 2 under `<head>/attempts/2/`, so `--start` reads the edge's `context_assignments` in the same tick in a real run. Then run `bash skills/work-on/scripts/run-verification_test.sh` and confirm it exits 0.

**Dependencies**: None

**Files**: `skills/work-on/scripts/verification-eligibility.sh`, `skills/work-on/scripts/run-verification.sh`, `skills/work-on/scripts/run-verification_test.sh`, `skills/work-on/scripts/output-gates-routing_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/SKILL.md`, `skills/work-on/references/verification-map.md`, `skills/work-on/evals/evals.json`

### Step 2: The PR body carries a re-run line for each archived attempt

**Goal**: A reviewer reading the PR sees every re-run at the same head: the PR body's Verification section has one re-run line for each attempt in the `verification_attempts` ledger, saying which command failed or timed out, the reason given and what the next attempt showed. A new `check-pr-output.sh --rerun-record --session <name>` mode reads the ledger from koto context and refuses a body that leaves a line out; with an empty ledger it asks for nothing. `pr_creation` runs it as a gate, so a real session can't open a PR that hides a re-run. A PR the plan's steps share is checked at the owning session's `pr_finalization`, beside the deferral record. On the node push path, `node-push.sh` carries each child's `verification_attempts` lines into the run record at push time, beside the deferral lines, and the collector reads them there.

**Acceptance Criteria**:

- [ ] With no `verification_attempts` key (koto context reports it missing), `--rerun-record` accepts a body whose Verification section has no re-run line, so a run that never re-ran sees no change. A failed koto read is not a missing key: the mode exits non-zero with its own message and accepts nothing.
- [ ] With one ledger attempt, a body whose Verification section lacks that attempt's re-run line is refused, with a message naming the missing attempt by its number and head. The same body with a line giving attempt 1's failed or timed-out command id, its reason and attempt 2's result is accepted. The failed or timed-out ids are the attempt's `commands[]` entries with a non-zero `exit_status` or `timed_out: true`.
- [ ] The next attempt's result comes from the ledger line for the following attempt at the same head and merge-base, or, for the last archived attempt, from `verification_results.json` when its head and merge-base match. When neither holds, the line needs only the command id and reason.
- [ ] A re-run line holding an absolute path is refused, and the message says why. Ledger log paths are relative to the head directory and stay out of the PR body, which may be public.
- [ ] A re-run line with a command id or reason outside a code span is refused, with its own message.
- [ ] `pr_creation` in `skills/work-on/koto-templates/work-on.md` gains a gate that runs `check-pr-output.sh --rerun-record` with the session name, the way the verification gate passes its session.
- [ ] `pr_finalization` in `skills/execute/koto-templates/execute.md` gains a re-run record gate beside `deferral_recorded`. Its collector, `skills/execute/scripts/shared-rerun-record.sh`, is modelled on `shared-deferral-record.sh`: it finds the run's children the same ways, reads each child's `verification_attempts` and runs `check-pr-output.sh --rerun-record` against the owned PR, refusing a shared PR body that lacks a child's re-run line. The state's directive tells the owning session to write each child's re-run lines, and `bash skills/execute/scripts/shared-rerun-record_test.sh` passes.
- [ ] On the node push path, `skills/execute/scripts/node-push.sh` carries each child's `verification_attempts` lines into the run record at push time, beside the deferral lines, and `shared-rerun-record.sh` reads them there. The run record's node entry gains a `reruns` field, always written (an empty list when no child re-ran), which `skills/execute/scripts/run-record.sh` accepts. The node PR that `node-push.sh` opens carries the re-run lines in its Verification section, and an adopted PR is checked for them; a missing re-run line stops the push with its own exit code and error, apart from the deferral record's, which `skills/execute/scripts/coordinated-next.sh` and `skills/execute/koto-templates/execute-coordinated.md` name. Cases in `skills/execute/scripts/node-push_test.sh` and `skills/execute/scripts/run-record_test.sh` cover it.
- [ ] `skills/work-on/SKILL.md`, `references/verification-map.md`, `references/phases/phase-6-pr.md` and `docs/designs/current/DESIGN-output-gates.md` show the re-run line's format (the command id and reason in code spans, plus the next attempt's result) and say which check refuses a body without it.

**Check**: Run `bash skills/work-on/scripts/check-pr-output_test.sh` from the repo root. It passes, with cases (a koto stand-in serving the ledger, as `run-verification_test.sh` does) for a missing ledger key (accepted, no line asked for), a failed ledger read (refused), one ledger attempt without and then with its re-run line (refused, then accepted), a line holding an absolute path (refused) and an id or reason outside a code span (refused), each asserting its exit code and message. End to end: `bash skills/work-on/scripts/output-gates-routing_test.sh` exits 0, and its re-run case, after it checks the one ledger line, runs `check-pr-output.sh --rerun-record` against that session with a body without the re-run line, then with it. The first is refused and names attempt 1. The second is accepted.

**Dependencies**: Step 1

**Files**: `skills/work-on/scripts/check-pr-output.sh`, `skills/work-on/scripts/check-pr-output_test.sh`, `skills/work-on/scripts/output-gates-routing_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/SKILL.md`, `skills/work-on/references/verification-map.md`, `skills/work-on/references/phases/phase-6-pr.md`, `skills/work-on/evals/evals.json`, `docs/designs/current/DESIGN-output-gates.md`, `skills/execute/koto-templates/execute.md`, `skills/execute/scripts/shared-rerun-record.sh`, `skills/execute/scripts/shared-rerun-record_test.sh`, `skills/execute/scripts/node-push.sh`, `skills/execute/scripts/coord-common.sh`, `skills/execute/scripts/node-push_test.sh`, `skills/execute/scripts/run-record.sh`, `skills/execute/scripts/run-record_test.sh`, `skills/execute/koto-templates/execute-coordinated.md`, `skills/execute/scripts/coordinated-next.sh`, `skills/execute/scripts/execute-output-gates-routing_test.sh`, `skills/execute/SKILL.md`

### Step 3: A third re-run at the same head and merge-base is refused, and the gate says why

**Goal**: Re-runs are capped at two archived attempts per head and merge-base, counted from the `verification_attempts` ledger by one function that the launcher and the gate both source. A third request is refused, with nothing moved or written, and the result routes as it does today. The ledger gets the integrity guards the design names, the reason and command ids are cleaned before they're stored, and `check-verification.sh` reads the ledger: its exit-1 message lists the earlier attempts, and over the cap it names the two ways out.

**Acceptance Criteria**:

- [ ] `verification_eligibility <result-file> <ledger-file>` prints `over-cap` for an otherwise eligible result when the ledger holds two lines at the result's head and merge-base; lines at another merge-base don't count, and an unparseable ledger prints `ineligible unreadable`. `check-verification.sh` sources `verification-eligibility.sh` as `run-verification.sh` does.
- [ ] With two ledger lines at the pair, `run-verification.sh --archive --reason <text>` exits 1 with a message naming the cap, moves no file and leaves `verification_attempts` byte-identical. When `--start` finds a third `verification_rerun_request`, it removes the key, says on stderr that the cap is spent and starts no new attempt.
- [ ] `--archive` refuses (exit 1, nothing moved, ledger unchanged) when the count of ledger lines at the pair disagrees with the archived `attempts/*/result.json` files at that pair. Archived results from an earlier merge-base at the same head don't trip it, and ledger lines whose folders were pruned fail closed.
- [ ] When the last ledger line names folder n at the live result's head and merge-base and `attempts/<n>/` holds no `result.json`, `--archive` finishes the move without appending a line. It still refuses a running suite, an ineligible result, and a head or merge-base that doesn't match that line.
- [ ] The eligibility check, the ledger append and the move run under the supervisor lock, and `--start` reads and removes the request key under the same lock.
- [ ] When the ledger read fails for any reason other than a missing key, `--start` refuses the re-run and keeps `verification_rerun_request`.
- [ ] The head and session name must match `[A-Za-z0-9._-]+` and the folder number must be an integer before any of them forms a path for `mv` or `rm`; a `run.json` whose `attempt` isn't an integer refuses the archive. Ledger log paths are stored only in the shape `attempts/<n>/<index>-<name>.log`, and as null otherwise.
- [ ] A reason has control characters, newlines, ANSI escape sequences and Unicode format characters (bidirectional controls included) stripped, and is then capped at 500 characters; a reason that is empty after cleaning is refused. Each command id gets the same cleaning and cap before it's stored.
- [ ] `check-verification.sh` reads `verification_attempts` with `koto context` through its `--session`. A missing key leaves every message unchanged; a failed read exits 2 and settles nothing.
- [ ] On exit 1 with ledger lines at the pair, the gate's message gives the attempt number (lines at the pair plus one), each earlier attempt's failed or timed-out command ids and reason, oldest first and marked as data from earlier runs, and the current attempt's log folder. Over the cap, it says the ways out are a real fix (a new head) or `implementation_status: blocked`. Every other exit's message is unchanged.
- [ ] The `implementation` directive in `skills/work-on/koto-templates/work-on.md` says a re-run is refused once two attempts are archived at the head and merge-base, and names the same two ways out.

**Check**: From the repo root, run `bash skills/work-on/scripts/run-verification_test.sh` and confirm it exits 0. Its new cases, against the koto stand-in, cover the over-cap refusal through `--archive` and through `--start` (each asserting the ledger and files unchanged), an earlier merge-base's lines and folders not counting, the disk disagreement and the pruned-folder refusal, the interrupted-archive recovery, a failed ledger read keeping the request key, a non-integer `run.json` attempt, a reason holding a newline, an ANSI escape, U+202E and 600 characters (stored cleaned and capped as one parseable line) and one that is empty after cleaning (refused), and the gate's exit-1 message with one and with two earlier attempts, its over-cap ways out, and exit 2 on a failed ledger read. Then run `bash skills/work-on/scripts/output-gates-routing_test.sh` and `bash skills/work-on/scripts/verification-route_test.sh` and confirm both exit 0.

**Dependencies**: Step 2

**Files**: `skills/work-on/scripts/verification-eligibility.sh`, `skills/work-on/scripts/run-verification.sh`, `skills/work-on/scripts/check-verification.sh`, `skills/work-on/scripts/run-verification_test.sh`, `skills/work-on/scripts/output-gates-routing_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/references/verification-map.md`, `skills/work-on/SKILL.md`, `skills/work-on/evals/evals.json`

### Step 4: An eligible timeout at the existing exit-5 hold can ask for a re-run

**Goal**: An agent held at the gate's existing exit-5 hold (a timed-out check, none failed, the hosted-of-record route open) can submit `verification_status: rerun` with a reason in `detail` and get a fresh suite at the same head, counted against the same two-re-run cap as the exit-1 route. `rerun` joins `hosted_of_record`, `fix` and `blocked` at that hold, and a `75 + rerun` edge keeps the order where the agent archives first routable; both edges land in one commit. Exit codes don't move: a failed check still outranks a timeout (exit 1), and a timeout with the route closed is still exit 4, with no re-run. A result with both a failed check and a timed-out one, which exits 1, becomes eligible on the exit-1 route, so a flaky failure beside a timeout can be re-run the way either one alone can.

**Acceptance Criteria**:

- [ ] `verification_eligibility <result-file> <ledger-file>` prints `eligible`, or `over-cap` at two ledger lines for the pair, for every result `check-verification.sh` holds at exit 5, a whole-budget stop (`status: timed-out`) with nothing unstarted included, and for a result with failed and timed-out commands. It still prints `ineligible <cause>` for any runaway or not-started command and for every other cause it refuses today, and the cap check uses the one shared counter for both routes.
- [ ] `run-verification.sh --archive --reason <text>` archives a timed-out result as it archives a failed one, and the ledger line's `exit` field is the gate exit the result came through (5 for a timeout held at the hold, 1 otherwise) instead of a fixed 1.
- [ ] At exit 5, `check-verification.sh` reads `verification_attempts` through `--session` as it does on exit 1: a missing key leaves the message unchanged, a failed read exits 2 and settles nothing, and with ledger lines at the pair the message lists the attempt number and each earlier attempt's timed-out or failed command ids and reason, oldest first and marked as data from earlier runs. Under the cap the exit-5 message offers `rerun` beside `hosted_of_record`, `fix` and `blocked`; over the cap it says the cap is spent and offers only the other three. The header comment that says exit 5 never reads the ledger is updated.
- [ ] `check-verification.sh` sets one EXIT trap that removes every temporary file it creates, the jq error file and the ledger file included, instead of a second trap that replaces the first.
- [ ] `verification` in `skills/work-on/koto-templates/work-on.md` accepts `verification_status: rerun`. A `5 + rerun` edge, with `route_reason_given` at 0, returns to `verification` and sets `verification_rerun_request` from `detail`; `--start` archives the timed-out attempt and starts a fresh suite in the next attempt folder in the same tick. `hosted_of_record` still needs `verification_route` at 0, so a `rerun` never takes the hosted route.
- [ ] A `75 + rerun` edge reaches the same lap. After `--archive --reason <text>` at the hold, the gate exits 75, `rerun` routes back to `verification`, and `--start` starts the next attempt with exactly one ledger line for the archived attempt. A `rerun` at 75 while a suite is still running archives nothing, and the request key is gone afterwards. `fix` and `hosted_of_record` are still refused at 75.
- [ ] Over the cap, a `rerun` at the hold leaves the ledger and the attempt folders unchanged: `--start` removes the request, says the cap is spent and starts nothing, and the gate holds at exit 5 again.
- [ ] The mixed failed-plus-timed-out result still exits 1 at block, and its warn-level variants still exit 4. On exit 1 it is eligible, so `verification_rerun` archives it, and over the cap the gate's exit-1 message names the two ways out as it does for a plain failure.
- [ ] `work-on.mermaid.md` draws the `5 + rerun` and `75 + rerun` edges. The `verification` directive's section on the timed-out hold, `skills/work-on/SKILL.md` and `skills/work-on/references/verification-map.md` describe `rerun` at the hold, the shared cap and the mixed result's eligibility. `skills/work-on/evals/evals.json` gains a scenario for an agent at the hold choosing between `rerun` and the other values.
- [ ] `docs/designs/DESIGN-same-head-verification-rerun.md` describes exit 5 as the existing hold (a timed-out check and no failed one, with the route open) to which this feature adds only `rerun` and the `5 + rerun` and `75 + rerun` edges. A failed check beside a timed-out one exits 1 and is eligible on the exit-1 route, and a timeout with the route closed stays exit 4.

**Check**: From the repo root, run `bash skills/work-on/scripts/run-verification_test.sh` and confirm it exits 0. Its new cases, against the koto stand-in, cover eligibility for a per-command timeout, a whole-budget stop and a mixed result (each `eligible` under the cap and `over-cap` at two lines), the archive of a timed-out result with `exit: 5` in its ledger line, the exit-5 message with one and with two earlier attempts (offering `rerun` under the cap, not over it), exit 2 on a failed ledger read at exit 5, the over-cap `rerun` leaving ledger and folders unchanged, the archive-first order through exit 75, and a gate run that reads the ledger leaving none of its temporary files behind. The existing pins on the mixed case (exit 1 at block, 4 at warn) still pass. Then run `bash skills/work-on/scripts/output-gates-routing_test.sh` and confirm it exits 0. Its new case drives real koto from a timed-out result held at exit 5 through `verification_status: rerun` back to `verification`, calling the real `run-verification.sh`, and checks the session state, the missing request key, the one ledger line and the running next attempt, so the self-loop's `context_assignments` reach `--start` in the same tick in a real run. Its existing cases refusing `fix` and `hosted_of_record` at 75 still pass. Then run `bash skills/work-on/scripts/verification-route_test.sh` and confirm it exits 0.

**Dependencies**: Step 3

**Files**: `skills/work-on/scripts/verification-eligibility.sh`, `skills/work-on/scripts/run-verification.sh`, `skills/work-on/scripts/check-verification.sh`, `skills/work-on/scripts/run-verification_test.sh`, `skills/work-on/scripts/output-gates-routing_test.sh`, `skills/work-on/koto-templates/work-on.md`, `skills/work-on/koto-templates/work-on.mermaid.md`, `skills/work-on/SKILL.md`, `skills/work-on/references/verification-map.md`, `skills/work-on/evals/evals.json`, `docs/designs/DESIGN-same-head-verification-rerun.md`

## Implementation Sequence

The steps run in order, each on the one before it: step 1, then 2, then 3,
then 4. None runs side by side with another, since each builds on the
previous step's files. Step 3 is detailed once step 2's work reaches its
terminal, and step 4 once step 3's does, each in a commit that touches only
this plan.
