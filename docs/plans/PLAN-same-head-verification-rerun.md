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
`implementation` after a failed command, or `rerun` at a new exit-5 hold after
an eligible timeout, and the launcher archives the outgoing attempt into a
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
hardens the ledger, and step 4 adds the timeout route: exit 5, its hold and
its edges, which the design requires to land together in one commit.

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

**Goal**: A reviewer reading the PR sees every re-run at the same head: the PR body's Verification section has one re-run line for each attempt in the `verification_attempts` ledger, saying which command failed or timed out, the reason given and what the next attempt showed. `check-pr-output.sh` refuses a body that leaves one out, and with an empty ledger it asks for nothing.

**Acceptance Criteria**:

- [ ] With no `verification_attempts` key (koto context reports it missing), the new `check-pr-output.sh` mode accepts a body whose Verification section has no re-run line, so a run that never re-ran sees no change.
- [ ] With one ledger attempt, a body whose Verification section lacks that attempt's re-run line is refused, with a message naming the missing attempt. The same body with a line giving attempt 1's failed or timed-out command id, its reason and attempt 2's result is accepted.
- [ ] A re-run line holding an absolute path is refused, and the message says why. Ledger log paths are relative to the head directory and stay out of the PR body, which may be public.
- [ ] A re-run line with a command id or reason outside a code span is refused, with its own message.
- [ ] `skills/work-on/SKILL.md`, `references/verification-map.md` and `docs/designs/current/DESIGN-output-gates.md` show the re-run line's format (the command id and reason in code spans, plus the next attempt's result) and say which check refuses a body without it.

**Check**: Run `bash skills/work-on/scripts/check-pr-output_test.sh` from the repo root. It passes, with cases for an empty ledger (accepted, no line asked for), one ledger attempt without and then with its re-run line (refused, then accepted), a line holding an absolute path (refused) and an id or reason outside a code span (refused), each asserting its exit code and message. End to end: take the ledger that step 1's routing case leaves with one archived attempt and run `check-pr-output.sh` in the new mode against a body without the re-run line, then against the same body with it. The first is refused and names attempt 1. The second is accepted.

**Dependencies**: Step 1

**Files**: `skills/work-on/scripts/check-pr-output.sh`, `skills/work-on/scripts/check-pr-output_test.sh`, `skills/work-on/SKILL.md`, `skills/work-on/references/verification-map.md`, `docs/designs/current/DESIGN-output-gates.md`

### Step 3: A third re-run at the same head and merge-base is refused, and the gate says why

The cap of two archived attempts per head and merge-base, with the ledger's integrity guards and the gate's ledger read naming earlier attempts and the over-cap ways out.

### Step 4: An eligible timeout holds at exit 5 and asks for rerun, fix or blocked

The gate's exit 5 and the `rerun`, `fix` and `blocked` edges from it, plus `75 + rerun`, landing together in one commit.

## Implementation Sequence

The steps run in order, each on the one before it: step 1, then 2, then 3,
then 4. None runs side by side with another, since each builds on the
previous step's files. Step 3 is detailed once step 2's work reaches its
terminal, and step 4 once step 3's does, each in a commit that touches only
this plan.
