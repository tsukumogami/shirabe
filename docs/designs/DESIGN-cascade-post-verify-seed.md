---
schema: design/v1
status: Accepted
problem: |
  `lifecycle_probe()` hardcodes `$PLAN_DOC` as the seed for both its
  invocations, so the post-cascade call validates a path the cascade deleted
  sixty lines earlier and reports L05 on every successful run. The seed has to
  become a parameter, something has to choose it from what the cascade recorded,
  and the no-survivor case has to be told apart from a failure — all in bash 3.2,
  inside a function whose only branch input today is an exit code.
decision: |
  Give `lifecycle_probe` a seed argument, add a `resolve_anchor` helper that
  walks `STAGED_FILES` in reverse-precedence order keeping the last surviving
  match per type, and split the post-verification into three arms: anchor found
  and clean, anchor found and dirty, no anchor. Two adjacent one-word fixes ride
  along because no `--push` test can assert anything without them: `git commit -q`
  so stdout carries only the report, and `--argjson` for `add_step`'s target so
  the no-anchor arm can emit null.
rationale: |
  Anchor selection lives in the script rather than in the validator because no
  tolerate-missing-seed mode exists in the CLI and adding one would make the
  check pass on a missing seed, which is the blocked-node hole. Selection reads
  the cascade's own record rather than recomputing canonical paths because the
  record is the only thing that knows which candidates were deleted. The
  three-arm split beats an L05-code branch because a code branch still seeds on
  a document that is gone and therefore verifies nothing.
upstream: docs/prds/PRD-cascade-post-verify-seed.md
user_visible_surface: false
---

# DESIGN: Cascade post-verify seed

## Status

Accepted

## Context and Problem Statement

`skills/execute/scripts/run-cascade.sh` is a 942-line bash script that walks a
finished chain to its terminal state and then checks its own work. The check is
`lifecycle_probe()`, at lines 289-321, and it takes one argument: the mode,
`pre` or `post`. The seed it validates is not an argument at all — line 297
interpolates `"$PLAN_DOC"` directly, so both invocations validate the same path.

For the pre-cascade call that is right. For the post-cascade call at line 907 it
is wrong, because line 873 has already run `git rm -f "$PLAN_DOC"` and line 885
has committed the removal. `run_lifecycle_chain_check` opens with
`fs::canonicalize`, fails, and returns a single `L05` finding at exit 2. The
probe branches on the exit code alone — its own comment at lines 280-282 says
so — and the post arm reports a cascade bug.

The technical problem is therefore threefold. The seed has to become a
parameter. Something has to choose that parameter from what the cascade knows
about its own output. And the case where nothing survives has to be
distinguished from the case where the cascade failed, using evidence available
inside a bash function whose only current branch input is `$?`.

Two constraints shape every answer. The script runs on the bash 3.2 floor, so
associative arrays, `mapfile`, namerefs and negative subscripts are unavailable.
And nothing in the post-verification may rescue a run that already failed: five
sites set `ANY_FAILED=true` before line 906 is reached, and the fix has to leave
all five standing.

Two further defects surfaced during review and are in scope only because the
work is untestable without them. `git commit` at line 885 writes its summary to
stdout ahead of `emit_result`, so under `--push` the script's captured output is
not valid JSON at all — the usage block's promise of "Output: JSON to stdout"
has never held on that path. And `add_step` builds `target` with `--arg`, which
always yields a string, so the no-anchor arm cannot emit an explicit null
without the `--argjson` treatment `found_in` already has.

## Decision Drivers

- **D1.** The post-cascade seed must be a document that survives the
  finalization commit (PRD R1, R2).
- **D2.** A chain that did not finalize must still fail, including the
  blocked-node case that `finalize-chain` reports as exit 0 (PRD R5, R6).
- **D3.** A chain that folded every artifact away must read as complete, and
  must say so distinguishably rather than as a pass (PRD R4).
- **D4.** No filter may disqualify a surviving candidate; type discrimination
  orders survivors and never removes one (PRD R2).
- **D5.** bash 3.2 floor, both for the script and the harness (PRD R11).
- **D6.** The `--lifecycle-chain` CLI surface is fixed. No tolerate-missing-seed
  mode exists and none is being added (PRD R9).
- **D7.** Every new `--push` scenario must be able to parse the run's stdout as
  JSON (PRD R7a).
- **D8.** The change must be small enough to review against a 942-line script
  whose other 900 lines are correct.

## Considered Options

### Option 1: Branch on the `L05` finding code, keep seeding on the PLAN

The validator's seed gates short-circuit: a missing seed returns exactly one
finding with `code == "L05"`, and it can never appear alongside the `L01`
findings a real chain violation produces. So the script could keep its current
seed and read the envelope it already captures in `LIFECYCLE_PROBE_OUTPUT`,
treating a lone `L05` as success and anything else as failure.

This is the cheapest change on the page — one `jq` call, no new helper, no
change to `lifecycle_probe`'s signature. It was rejected because it verifies
nothing. The PLAN is missing on *every* successful run, so an `L05`-tolerant
check seeded on the PLAN returns "success" unconditionally, exactly as the
current code returns "failure" unconditionally. The blocked-node case, which is
the only defect this guard is positioned to catch, would still ship as
`completed`. The finding-code distinction is real and worth knowing; it is not a
fix.

### Option 2: Recompute the anchor from canonical paths

Derive the slug from `$PLAN_DOC`, then test `docs/designs/current/DESIGN-<slug>.md`,
`docs/prds/PRD-<slug>.md` and `docs/briefs/BRIEF-<slug>.md` in order and seed on
the first that exists.

Rejected on two grounds. It reconstructs a slug-to-path mapping the cascade
already holds, and it silently assumes every chain document shares the PLAN's
slug — which is exactly the assumption `/scope`'s `--upstream` flag exists to
break. More seriously, it cannot see the ROADMAP, which is a legitimate anchor
when a chain has no tactical members left, and it cannot tell a document the
cascade deleted from one it never touched.

### Option 3: Skip the verification when the PLAN is absent

Guard the whole block on `[[ -f "$PLAN_DOC" ]]`.

Rejected outright. The PLAN is absent on every successful run, so this deletes
the verification rather than fixing it, and D2 fails completely.

### Option 4: Read `blocked` / `blocked_by` from the finalize-chain report

The report already carries the truth about a blocked node. The script could read
those fields and fail the run directly, without any anchor at all.

Rejected as out of scope, not as wrong. It is a cleaner fix to a *different*
defect — the step that records `"ok"` on a blocked node at line 798 — and it
would leave the post-verification still seeded on a deleted PLAN. It belongs in
its own change, and the PRD's Out of Scope says so.

### Option 5: Seed on a surviving candidate from the cascade's own record

Give `lifecycle_probe` a seed parameter, choose that seed from `STAGED_FILES`
filtered by on-disk existence and ordered by document type, and split the post
arm three ways.

Chosen. It is the only option that satisfies D1 through D4 together: it seeds on
something that exists, it catches the blocked node because that node's DESIGN
survives at its un-moved path and fails `L01`, it treats an empty survivor set
as completion, and it never disqualifies a survivor.

## Decision Outcome

`lifecycle_probe` gains a second parameter, the seed path, and line 297
interpolates that instead of `$PLAN_DOC`. The pre call passes `$PLAN_DOC` and is
otherwise untouched. The post call passes whatever `resolve_anchor` returns.

`resolve_anchor` is a new helper that walks `STAGED_FILES`, keeps only entries
that pass `[[ -f ]]`, and returns the highest-precedence survivor by document
type: DESIGN, then PRD, then BRIEF, then ROADMAP. It writes the chosen path to
stdout and returns 1 with empty output when nothing survives. The precedence is
by basename prefix, which is type discrimination for ordering only — every
survivor stays eligible, and the ROADMAP is last rather than excluded because it
sits above the chain and can surface sibling features' in-flight PLANs as
`L01`.

The post-verification block becomes three arms. With an anchor and a clean
check, the step records `ok` with `target` set to the anchor. With an anchor and
a non-clean check, it records `failed`, sets `ANY_FAILED=true`, and carries the
validator's findings summary in `detail` as it does today. With no anchor, it
records `skipped` with `target` null and the literal detail `no recorded chain
document survived to verify against`, and does not touch `ANY_FAILED`.

Two one-word changes ride along. `git commit` at line 885 gains `-q` so stdout
carries only the report. `add_step`'s `target` moves from `--arg` to `--argjson`
with the same JSON-or-quoted-string treatment `found_in` already gets at lines
334-337, so the no-anchor arm can emit a real null.

## Solution Architecture

```
                    ┌─ pre  ── seed: $PLAN_DOC ─────────────┐
lifecycle_probe ────┤                                        ├── validate --lifecycle-chain <seed> --mode=ready
  (mode, seed)      └─ post ── seed: $(resolve_anchor) ──────┘
                                      │
                                      ▼
                        ┌─────────────────────────────┐
                        │ resolve_anchor              │
                        │  for f in STAGED_FILES:     │
                        │    [[ -f $f ]] || continue  │
                        │    classify by basename     │
                        │  return best of             │
                        │  DESIGN>PRD>BRIEF>ROADMAP   │
                        └─────────────────────────────┘
                                      │
                 ┌────────────────────┼────────────────────┐
                 ▼                    ▼                    ▼
          anchor + clean       anchor + dirty         no anchor
          step: ok             step: failed           step: skipped
          target: anchor       ANY_FAILED=true        target: null
                               target: anchor         ANY_FAILED untouched
```

### `resolve_anchor`

Signature: no arguments, reads `STAGED_FILES` from scope. Writes the chosen path
to stdout, returns 0. Writes nothing and returns 1 when no candidate survives.

The bash 3.2 floor rules out an associative array keyed by type, so the helper
holds four scalars — `_a_design`, `_a_prd`, `_a_brief`, `_a_roadmap` — and
assigns each as it walks, keeping the last match per type. No current append
site can produce two entries of one type in a single run — line 497 is guarded
by `[[ -f "$path" ]]`, which is already false once line 577 has removed the
file, and both would append the identical path anyway — so last-match versus
first-match is not a live choice today. It is written as last-match because a
later duplicate is the more recent statement of what happened, which is the
safer default if a sixth append site ever appears. Selection then tests the four
scalars in precedence order.

Classification is on the basename prefix, using `case` rather than `[[ =~ ]]` —
3.2's regex handling differs across versions when the pattern is inline, and a
glob `case` has no such ambiguity:

```bash
resolve_anchor() {
    local f base
    local _a_design="" _a_prd="" _a_brief="" _a_roadmap=""
    for f in ${STAGED_FILES[@]:+"${STAGED_FILES[@]}"}; do
        [[ -f "$f" ]] || continue
        base=$(basename "$f")
        case "$base" in
            DESIGN-*)  _a_design="$f" ;;
            PRD-*)     _a_prd="$f" ;;
            BRIEF-*)   _a_brief="$f" ;;
            ROADMAP-*) _a_roadmap="$f" ;;
        esac
    done
    for f in "$_a_design" "$_a_prd" "$_a_brief" "$_a_roadmap"; do
        if [[ -n "$f" ]]; then printf '%s\n' "$f"; return 0; fi
    done
    return 1
}
```

The `${STAGED_FILES[@]:+...}` guard is the same one line 300 already carries and
for the same reason: 3.2 errors on an empty array spread under `set -u`.

### `lifecycle_probe`'s new signature

```bash
lifecycle_probe() {
    local mode="$1"
    local seed="$2"
    ...
    LIFECYCLE_PROBE_OUTPUT=$("$SHIRABE_BIN" validate \
        --lifecycle-chain "$seed" \
        ...
```

The `pre` and `post` arms are otherwise unchanged, except that the post arm's
warning text drops "(cascade bug)" — with a real anchor, a failure here is a
statement about the chain, not about the script.

### The post-verification block

```bash
if [[ "$PUSH" == "true" ]] && [[ ${#STAGED_FILES[@]} -gt 0 ]]; then
    if ANCHOR=$(resolve_anchor); then
        if ! lifecycle_probe "post" "$ANCHOR"; then
            ANY_FAILED=true
            add_step "lifecycle_post_verify" "$ANCHOR" "null" "failed" \
                "post-cascade lifecycle check failed in ready posture against $ANCHOR: ..."
        else
            add_step "lifecycle_post_verify" "$ANCHOR" "null" "ok" "$L06_SUPPRESSED_DETAIL"
        fi
    else
        add_step "lifecycle_post_verify" "null" "null" "skipped" \
            "no recorded chain document survived to verify against"
    fi
fi
```

`ANY_FAILED` is written in exactly one place in this block and only ever set to
`true`. Nothing here clears it, which is what keeps the five earlier failure
sites intact.

### `add_step`'s nullable target

`target` currently passes through `--arg`, which JSON-quotes unconditionally.
The change mirrors `found_in`'s existing treatment: pass the literal token
`null` through `--argjson`, anything else through `--arg`. This is a two-line
edit in `add_step` and does not alter any existing call site, because every one
of them passes a real path.

## Implementation Approach

Four units, in dependency order. Each is independently reviewable and the first
two are prerequisites for any test at all.

**Unit 1: make `--push` output parseable.** `git commit -q` at line 885, and
`add_step`'s `--argjson` treatment for `target`. Nothing else in the script
changes. Without this no `--push` scenario can assert anything, so it goes
first.

**Unit 2: the seed parameter and `resolve_anchor`.** Add the helper, add the
second parameter, update both call sites, split the post block three ways. This
is the fix proper.

**Unit 3: the `--push` scenarios.** Seven new scenarios plus a pass-through
logging stub variant, covering the six fixture shapes and AC8's argv assertion.
Each establishes tracking with `git push -u origin HEAD` after `commit_all`,
because `setup_test_repo` creates a bare origin but sets no upstream branch and
the cascade's bare `git push` would otherwise abort the script under `set -e`.

**Unit 4: mutation verification and triage.** Restore the PLAN seed at the post
call site, run the suite, record which scenarios fail by name, revert. Then file
the two adjacent defects and close the duplicate issues.

The order matters: unit 3 cannot be written before unit 1 lands, and unit 4's
mutation is meaningless before unit 2. Units 1 and 2 could merge into one commit
without harm; they are separated here because unit 1 fixes a defect that is not
this PRD's subject and a reviewer should be able to see it alone.

## Security Considerations

The change reads paths the cascade itself recorded and tests them with `[[ -f ]]`
before handing them to a subprocess. Three surfaces are worth naming.

**Path injection into the validator call.** `resolve_anchor` returns an element
of `STAGED_FILES`, and every element arrives from `finalize-chain`'s report or
from the script's own roadmap handler — not from user input. Each is quoted at
the point of use (`--lifecycle-chain "$seed"`), so a path containing whitespace
or shell metacharacters is passed as one argument. The existing
`validate_upstream_path` already confines the PLAN to the repo work tree, and
`finalize-chain` validates each node path before reporting it.

**Symlink swap between the existence test and the validator call.** `[[ -f ]]`
follows symlinks, and the validator canonicalizes independently. A path that
passed the test and was replaced by a symlink out of the tree before the
validator ran would be caught by the validator's own root-escape check
(`lifecycle.rs:420-425`, `path escapes lifecycle root after canonicalization`),
which returns `L05` and fails the step. The window is a local race in a
developer's own working tree, and the failure mode is a false negative that
reports failure rather than a false pass.

**Command substitution in the helper.** `basename` is called on paths from the
record. Its output is assigned, never evaluated, and the `case` patterns are
literal globs.

No new network surface, no new file writes, no new environment variables. The
verification reads the working tree and calls a local binary.

## Consequences

**Positive.** The guard starts working: a chain that finalized reports
`completed`, a chain that did not reports `partial` and says which document is
wrong. The blocked-node case, which has been shipping as a clean run, starts
failing. The `--push` path gains test coverage for the first time, which closes
the gap that let a deterministic defect survive ten weeks and three filings. And
`run-cascade.sh` starts keeping its documented promise that stdout carries JSON.

**Negative.** The post-verification inherits the chain's own false-positive
surface: chain-targeted ready-posture validation reports every member, so a
sibling PLAN legitimately in flight surfaces as `L01` against the anchor and
fails the step. This is not new — the old seed sat in the same chain — but the
old seed failed unconditionally, so the surface was invisible. Mitigated by
ranking the ROADMAP last, since it is the anchor whose chain membership is
widest, and by constraining test fixtures to one PLAN per chain. It is not
eliminated, and a genuine `partial` from this cause will look like a bug to
whoever hits it first.

**Negative.** The script grows a helper and the post block grows an arm, in a
file already at 942 lines. The mitigation is that `resolve_anchor` is pure — it
reads one array and writes one path — and is the only new function.

**Negative.** Two of the four units fix defects that are not this PRD's subject.
Bundling them is a scope compromise made because the test coverage that is this
PRD's subject cannot be written without them; the alternative was a separate
prerequisite pull request, which for a one-word `-q` and a two-line `--argjson`
would have cost more review than it saved.

**Accepted risk.** `delete_plan` still never enters the record, so a chain whose
only action is the PLAN deletion still stages that deletion and never commits it
under `--push`. That defect is filed separately and left alone here. It bounds
what a no-anchor fixture can look like, which is why the no-anchor scenario is
built on a deleted ROADMAP rather than on a no-upstream PLAN.
