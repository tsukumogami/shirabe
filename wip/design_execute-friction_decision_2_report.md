# Decision D2: What is the shape of /execute's pause-before-finalization (PRD R2), composing with autonomy (PRD R8) and DRAFT-before-READY?

## Options Considered

The exploration already established the genuine gap: `/execute` never runs `gh pr
merge`; its single-pr template terminates at `gh pr ready` + green CI, so "implement,
stop before merge" is existing behavior. The PRD-R2 capability that is missing is a
pause BEFORE the `plan_completion` finalization cascade — the atomic, pushed commit
that `git rm`s the PLAN and transitions BRIEF/PRD/DESIGN/ROADMAP. The three candidate
shapes:

**Option (a) — A flag that routes to a new pause terminal after `pr_finalization`,
before `plan_completion`.** `pr_finalization` already does exactly the right thing in
isolation: it assembles and `gh pr edit`s the PR body and is explicitly forbidden from
running `gh pr ready` (template lines 312-325). Today its only `updated` transition is
`-> plan_completion` (line 122). Add a second `updated` edge guarded on a pause flag
that routes to a new non-failure terminal `paused_for_review` instead. The seam is
already cut by the #117 reordering — the cascade was deliberately moved OUT of
`pr_finalization` and INTO `plan_completion` so that `pr_finalization`'s exit is the
exact moment the chain is fully intact but the PR is assembled. This is the seam F3
named: "a new pause terminal out of `pr_finalization`, resumable into
`plan_completion`."

**Option (b) — A new explicit pause STATE in the template (not just a terminal).** A
dedicated `pause_for_review` non-terminal state between `pr_finalization` and
`plan_completion` that the agent submits into and which then waits. Rejected: koto
states advance on submitted evidence; there is no "wait for a human" primitive, so a
mid-machine pause state would either immediately fall through (no pause) or model the
human gate as a koto gate (wrong layer — the gate is the operator re-invoking
`/execute`, which is a fresh session, not an evidence submission). A terminal is the
correct koto encoding of "stop here and hand back to the operator."

**Option (c) — Reframe existing behavior (no mechanism change).** Document that
`gh pr ready` + green CI is already a reviewable stop. Rejected: it stops at the WRONG
place. By the time `ci_monitor`/`done` is reached the cascade has already run — PLAN
deleted, upstreams transitioned. R2 requires the chain "still intact" at the pause, so
the existing terminal does not satisfy R2 no matter how it is documented.

## Chosen Option

**Option (a): a `--pause-for-review` flag (alias `--no-finalize`) parsed in
`/execute`'s SKILL.md Execution-Mode Flags, threaded into the koto template as a
`PAUSE_BEFORE_FINALIZE` variable, routing `pr_finalization` to a new non-failure
terminal `paused_for_review` instead of `plan_completion`. Resume re-invokes `/execute`
on the same topic; the home-PR resume lookup finds the DRAFT PR, and the run re-enters
directly at `plan_completion` (cascade + `gh pr ready`), completing the landing.**

This composes cleanly with DRAFT-before-READY precisely because #117 already did the
hard part: it welded the cascade to `gh pr ready` by moving BOTH into `plan_completion`
and leaving `pr_finalization` as body-assembly-only. The pause therefore needs no new
seam — it reuses the boundary the DRAFT-before-READY reorder created. The cascade and
`gh pr ready` stay welded together inside `plan_completion`; the pause simply stops the
machine one state earlier, before either fires. There is no risk of a half-finalized
chain (cascade run but PR still draft, or PR ready but chain not finalized) because the
pause boundary is upstream of the welded pair, never between its two halves.

## Concrete Mechanism

**File 1 — `skills/execute/SKILL.md`, Execution-Mode Flags section.** Add the flag to
the resolved-flag list alongside `--auto`/`--interactive`:

- `--pause-for-review` (alias `--no-finalize`) — drive every plan issue to the
  assembled DRAFT PR and stop BEFORE the `plan_completion` finalization cascade, with
  the chain intact (PLAN present, BRIEF/PRD/DESIGN not transitioned). Resume by
  re-invoking `/execute <plan>` on the same topic: the home-PR resume lookup finds the
  DRAFT PR and the run re-enters at `plan_completion`, runs the cascade DRAFT-before-
  READY, flips `gh pr ready`, and monitors CI to green.

This flag is orthogonal to the autonomy axis (`--auto` is "how hard do I drive";
`--pause-for-review` is "where do I stop"), so it resolves independently and they
compose (see next section). Per the parent-do-not-extend-child rule, the flag does NOT
reach `/work-on` children — children always drive their issue to its DRAFT-PR-on-
shared-branch terminal regardless; the pause is purely an orchestrator-level routing
decision at `pr_finalization`.

**File 2 — `skills/execute/koto-templates/execute.md`.** Three edits:

1. Declare a new template variable `PAUSE_BEFORE_FINALIZE` (boolean, default `false`),
   set by `/execute` from the resolved flag at `koto init` time (`--var
   PAUSE_BEFORE_FINALIZE=true`), mirroring how `PLAN_DOC` is injected in SKILL.md
   Step 2.

2. In the `pr_finalization` state, split the existing single `updated` transition
   (currently target `plan_completion`, lines 122-124) into two guarded edges:
   - `finalization_status: updated` AND `PAUSE_BEFORE_FINALIZE: false` → `plan_completion`
     (unchanged default behavior).
   - `finalization_status: updated` AND `PAUSE_BEFORE_FINALIZE: true` → `paused_for_review`.
   The `update_failed` → `done_blocked` edge is untouched.

3. Add a new terminal state:
   ```yaml
   paused_for_review:
     terminal: true
   ```
   With a prose section instructing the agent to emit the operator hand-back: the DRAFT
   PR URL, the confirmation that the chain is intact (PLAN present, upstreams
   un-transitioned), and the exact resume instruction (`re-invoke /execute <plan>` to
   run the cascade and land). It is a NON-failure terminal (`failure:` absent) — the
   pause is a successful solicited stop, not a block.

**Resume path.** No new resume machinery is required — `/execute`'s existing home-PR
resume lookup (SKILL.md Resume, rows 8-9) already handles it. On re-invocation the
topic-keyed `gh pr list --state open --search "<topic> in:title"` finds the still-open
DRAFT PR, rebuilds the `wip-yaml-md` projection, and resumes on that branch. The
recorded `phase_pointer` at pause is `pr_finalization`-complete; resume re-enters the
koto loop and, with `PAUSE_BEFORE_FINALIZE` now `false` (the resume invocation is a
finalize invocation — the operator approved), advances `pr_finalization` →
`plan_completion`. `plan_completion` is idempotent on a clean re-run: `run-cascade.sh`'s
pre-probe re-derives state, and its skip/partial/completed contract handles the chain
exactly once. (Resume-time, `/execute` re-submits `pr_finalization` with
`PAUSE_BEFORE_FINALIZE=false`; the PR body is already assembled so this is a cheap
re-assert before the cascade edge fires.)

**Pause exit value (R9 hard-finalization).** The `paused_for_review` koto terminal maps
to `/execute`'s SKILL-level `exit:` field. A solicited pause is NOT one of the three
existing exits semantically — it is neither `full-run` (the home PR is NOT merged and
the chain is NOT finalized), nor `abandonment-forced` (nothing was abandoned; the run
succeeded at exactly what was asked), nor `re-evaluation` (no upstream-must-change
boundary). To satisfy R9 Part 1 ("`exit:` set to one of the valid values") WITHOUT
mislabeling, D2 routes the solicited pause to **`re-evaluation`** is WRONG (that exit
means an upstream must change); instead the pause sets **`exit: full-run` only after
resume completes**, and at the pause itself records a distinct in-flight-but-stopped
state. Two viable encodings, pick per the pattern's exit enum constraint:

- **Preferred:** treat `paused_for_review` as a **deliberate non-terminal hand-back**:
  `exit:` stays UNSET (the run is paused, not finalized), and the R9 hard-finalization
  check is NOT fired at a solicited pause because R9 fires at *termination*, and a
  solicited pause is explicitly a resumable suspension, not a termination. This requires
  one sentence in SKILL.md Exit Paths: "a `--pause-for-review` solicited stop suspends
  the run with `exit:` UNSET and a `paused_for_review` state marker; it is resumable and
  does not fire the R9 hard-finalization check, which fires only at one of the three
  terminal exits." The state file carries a `paused_for_review: true` marker (I-5 gated:
  present only while paused) so resume distinguishes a solicited pause from a crash.
- **Fallback** (if the pattern forbids any UNSET-`exit:` durable terminal): add the
  pause as a fourth *recorded* outcome that maps onto `abandonment-forced`'s
  schema-compliant-partial machinery (DRAFT PR as the review surface, frozen-but-intact
  PLAN), distinguished by a `forced: false` / `solicited: true` discriminator — reusing
  abandonment-forced's "review surface + frozen chain" shape, which is structurally
  identical to a solicited pause, without claiming a failure.

The preferred encoding is cleaner and matches R8's framing of the pause as "solicited"
(a requested suspension, not a terminal outcome). The DESIGN should adopt the preferred
encoding and cite the fallback as the contingency if pattern-conformance review rejects
an UNSET-`exit:` suspension.

## Autonomy + DRAFT-before-READY composition

**R8 (solicited stop under `--auto`).** The two flags are orthogonal and compose by
construction. `--auto` governs `spawn_and_await`'s "drive to terminal, never stop on an
authorized run" mandate; `--pause-for-review` governs the `pr_finalization` routing
edge. Under `--auto --pause-for-review`, the orchestrator drives every issue to its
DRAFT-PR terminal WITHOUT any checkpoint stops (honoring "do not stop on an authorized
autonomous run"), then stops at `paused_for_review` — but this stop is **solicited**:
the operator explicitly asked for it via the flag. It is therefore NOT a violation of
the autonomy mandate, which forbids *unsolicited* advisory stops ("advise a checkpoint,
seek confirmation"). The mandate's own carve-out is that a stop the operator requested
is legitimate; `--pause-for-review` IS that request. So `--auto` drives hard up to the
solicited boundary and stops there cleanly, never mid-issue. Under `--auto` WITHOUT
`--pause-for-review`, the run drives straight through `plan_completion` to `done` — no
pause fires (R8: "the pause fires only when requested").

**DRAFT-before-READY.** The pause sits one state UPSTREAM of the welded cascade/`gh pr
ready` pair, so it never splits the weld. At the pause, the PR is DRAFT (correct — the
chain is not yet finalized, so `gh pr ready` must NOT have fired, exactly what
DRAFT-before-READY requires). On resume, the welded pair runs intact: cascade finalizes
the chain, THEN `gh pr ready` flips it, THEN CI re-runs strict on the finalized chain.
The pause neither weakens nor reorders the #117 discipline; it reuses the seam #117 cut.

## Open Risks

- **`exit:` encoding needs pattern-conformance sign-off.** The preferred UNSET-`exit:`-
  with-suspension-marker encoding assumes the parent-skill pattern permits a durable
  resumable suspension that is not one of the three terminal exits. If
  `references/parent-skill-pattern.md`'s I-1 ("a parent records an exit outcome before
  termination") is read to forbid ANY durable state without a set `exit:`, fall back to
  the `abandonment-forced`-shaped `solicited: true` encoding. This is the one decision
  the DESIGN must confirm against the pattern reference before coding.

- **Resume must re-assert `PAUSE_BEFORE_FINALIZE=false`.** The resume invocation is
  semantically "now finalize." If an operator re-invokes WITH `--pause-for-review` again,
  the run would pause again at the same boundary (a no-op loop). The DESIGN should
  specify that resume from a `paused_for_review` state ignores a re-passed
  `--pause-for-review` (or warns), since the PR body is already assembled and the
  operator's intent on re-invoke is to land.

- **`child_snapshots` fingerprint at pause.** The home-PR durable state must capture
  that children completed but the cascade did not run, so a resume does not re-spawn
  children. The existing `batch_done` gate + koto child dedup handles re-entry, but the
  DESIGN should confirm the `wip-yaml-md` projection records the pause `phase_pointer`
  so a lost-scratch cross-branch resume rebuilds to `pr_finalization`-complete and not
  to `spawn_and_await`.

- **Coordinated path scope.** This decision is specified for the single-pr koto path
  (where `pr_finalization`/`plan_completion` are koto states). The coordinated path has
  no koto session and finalizes per-repo before the merge-last gate; a `--pause-for-
  review` there would pause before the coordination PR's merge-gate. The DESIGN should
  state whether D2 covers coordinated in v1 or scopes the flag to single-pr initially
  (recommended: single-pr first, since R2's "cascade" language is single-pr-shaped).
