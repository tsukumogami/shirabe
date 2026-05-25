# Decision 5 Report — Cross-Boundary State-Snapshot Semantics on Decision Record Write

## Decision

**ID 5 (standard)**: When `/scope` writes a re-evaluation Decision Record, does the per-child `child_snapshots` block advance to record the Decision Record path, or stay frozen on the referenced upstream artifact (the Accepted PRD or DESIGN at the boundary)?

## Source

- PRD: R10 `child_snapshots` schema, R11 drift detection / resume ladder, Questions Deferred Q5
- Pattern references:
  - `references/parent-skill-state-schema.md` (per-child snapshot dual-check, conditional-field gating)
  - `references/parent-skill-child-inspection.md` (drift detection on doc-emitting children: `status:` + git blob hash)
- `/charter` analog: `skills/charter/references/phases/phase-finalization.md` Exit 2 re-evaluation sub-shape (state-field assignments), `skills/charter/references/phases/phase-resume.md` Drift-Detection section.

## Recommendation

**`child_snapshots` STAYS FROZEN on the referenced upstream artifact at the boundary's snapshot moment. `child_snapshots` is NOT advanced to point at the Decision Record path.** The Decision Record is recorded exclusively in `exit_artifacts:` (with `status: Accepted`) and in `referenced_artifact:` (which names the boundary's upstream artifact, not the Decision Record). The `child_snapshots` entry for the boundary's child (PRD on PRD-boundary; DESIGN on DESIGN-boundary) retains the `{path, status, content_hash}` triple captured at the moment the chain last advanced past or exited at that child. Downstream children (those past the boundary) retain their snapshots from the last chain run that touched them — typically `Absent` if the chain never reached them, or the values from the prior full-run that produced them.

## Reasoning

### Why freezing is correct

1. **The Decision Record is not a chain child.** `child_snapshots` is a per-child block keyed by the four named children in `planned_chain` (`brief`, `prd`, `design`, `plan`). The Decision Record is an exit artifact, not a child — it's emitted by `/scope` itself at finalization, not by an invoked child skill. R10's schema explicitly enumerates the four children; the Decision Record path has no slot to advance INTO. Putting the Decision Record path into a `child_snapshots` entry overloads the field's contract (it would mean "either the child's durable doc OR the parent's own exit artifact," which breaks the dual-check semantics — what blob hash do you compare against on the next resume?).

2. **Drift detection's purpose is preserved by freezing.** R11 and the child-inspection reference both anchor drift to "out-of-chain edits on the child's durable doc." Subsequent `/scope` resumes against the same topic — for instance, a year later when conditions change again and the author wants to re-evaluate the boundary anew — need to detect whether the upstream PRD (or DESIGN) was edited in the intervening period. If `child_snapshots.prd` was advanced to point at the Decision Record path, drift detection would compare the Decision Record's hash to the live Decision Record (immutable in practice, since Decision Records are append-only) and would NEVER fire even if the PRD was rewritten three times. The signal goes dead.

3. **The `referenced_artifact:` field already carries the upstream pointer.** The `/charter` analog confirms this binding: Exit 2 re-evaluation sub-shape sets `referenced_strategy:` to the upstream STRATEGY path and `exit_artifacts:` to the Decision Record path. Two distinct fields, two distinct roles. `/scope`'s `referenced_artifact:` (gated on `decision_record_sub_shape: re-evaluation`) plays the same role for PRD-boundary or DESIGN-boundary. The Decision Record body cites the upstream via `referenced_artifact:`; `child_snapshots` independently tracks the upstream child's drift surface. No data is lost by freezing — both fields together preserve the full audit trail.

4. **R14 child-inspection rule (widened) reinforces this.** The rule binds `/scope`'s read surface to "durable externally-visible status surface of each invoked child." The boundary's PRD or DESIGN remains the durable externally-visible artifact for that child slot regardless of whether `/scope` wrote a Decision Record about it. Advancing `child_snapshots` to a Decision Record path would mean the parent's drift check stops looking at the child's surface and starts looking at the parent's own exit artifact — a category confusion that violates the isolation rule.

5. **Invariant I-5 (conditional-field gating) is satisfied cleanly.** `referenced_artifact:` is conditional on `decision_record_sub_shape: re-evaluation` and SHALL be present then; `child_snapshots` is unconditional (always present once the chain has touched at least one child). The two fields don't fight each other: one is the exit-binding pointer, the other is the per-child drift baseline. Freezing keeps both fields semantically pure.

### Why advancing is wrong

Advancing `child_snapshots` to the Decision Record path was the tempting alternative. It would feel symmetric ("the most recent thing `/scope` produced for this slot is the Decision Record, so snapshot it"). But it fails three ways:

- **Loss of drift signal.** As above — the snapshot's job is to detect upstream change between resumes. Advancing to the Decision Record path moves the dual-check target onto an artifact that doesn't change, killing the signal.
- **Field-meaning collision.** `child_snapshots` is named per-child for a reason. Each entry is keyed by a child name (`brief`, `prd`, `design`, `plan`), and the path field is expected to be a child-doc path. Stuffing a Decision Record path under `child_snapshots.prd.path` makes the field's meaning ambiguous on read — is `prd.path` the PRD or the Decision Record about the PRD? The schema's clarity erodes.
- **Resume-ladder ambiguity.** R11's resume ladder reads `child_snapshots` to compute drift via the per-parent surface table (frontmatter `status:` + git blob hash for doc-emitting children). The Decision Record IS a doc-emitting artifact with frontmatter `status:`, so the dual-check would superficially still work — but it would now be computing drift against the wrong thing. The resume ladder would mis-route on subsequent invocations (treating an unchanged Decision Record as "PRD has not drifted" even after the upstream PRD was rewritten).

## Concrete Scenarios

The decision rule's behavior under three realistic flows:

### Scenario A — PRD-boundary re-evaluation, no subsequent edits

Flow: full-run reaches `PRD-feature-x.md` Accepted, DESIGN walks Phase 1, all PRD requirements still hold, author selects Re-evaluate. `/scope` writes Decision Record, exits.

State file after exit:

```yaml
exit: re-evaluation
boundary: prd
decision_record_sub_shape: re-evaluation
referenced_artifact: docs/prds/PRD-feature-x.md
exit_artifacts:
  - path: docs/decisions/DECISION-prd-feature-x-re-evaluation-2026-05-25.md
    status: Accepted
child_snapshots:
  prd:    { path: docs/prds/PRD-feature-x.md, status: Accepted, content_hash: abc123… }
  brief:  { path: docs/briefs/BRIEF-feature-x.md, status: Accepted, content_hash: def456… }
  design: <absent — chain bailed at PRD boundary before producing DESIGN>
  plan:   <absent>
```

The `prd` snapshot is frozen at `(Accepted, abc123…)`. On a `/scope` resume four months later, the ladder reads the live `PRD-feature-x.md` — if its `status:` is still `Accepted` AND its blob hash is still `abc123…`, no drift, and the resume can proceed against the same Accepted PRD. If the PRD was edited in the interim (e.g., the author tightened a requirement out-of-chain), the live blob hash differs from `abc123…`, drift fires, and the three-option prompt surfaces. **This is the desired behavior.** If `child_snapshots.prd` had been advanced to the Decision Record path, neither check would catch the PRD edit.

### Scenario B — DESIGN-boundary re-evaluation followed by upstream PRD edit and later resume

Flow: full-run reaches `DESIGN-feature-y.md` Accepted, PLAN walks Phase 1, all DESIGN trade-offs still hold, author selects Re-evaluate at DESIGN-boundary. `/scope` writes Decision Record, exits. Three weeks later, author manually invokes `/prd <PRD-feature-y.md>` outside `/scope` to tighten a requirement (R13 manual-fallback path). PRD's `status:` flips Draft (then back to Accepted on a `/prd … accept`), and its blob hash changes. Author later runs `/scope feature-y`.

With freezing, `child_snapshots.prd` is `{path: docs/prds/PRD-feature-y.md, status: Accepted, content_hash: <old-hash>}`. Live PRD is `(Accepted, <new-hash>)`. Drift fires on `content_hash`. Resume ladder surfaces the three-option staleness prompt (Re-run downstream / Accept downstream / Proceed without). Author can then choose to re-invoke `/design` against the tightened PRD, accept the existing DESIGN as still-valid despite the PRD edit, or skip. **Signal preserved across re-evaluation exit.**

With advancement, `child_snapshots.prd` would point at the Decision Record. The PRD's manual edit is invisible to the resume ladder. The author re-enters `/scope` with no warning that the upstream changed underneath the Decision Record. The audit trail breaks silently. **Signal lost.**

### Scenario C — Rejection sub-shape (not re-evaluation, but adjacent)

Flow: `/scope` invokes `/design`, the author works through Phase N and selects Reject. `/design` runs the discard procedure (git rm of the Draft DESIGN, cleanup of `wip/design_*.md`). `/scope` captures discard-commit SHA, writes Decision Record with rejection sub-shape.

The boundary in this case is DESIGN (the rejected child). `child_snapshots.design` was potentially populated when the Draft DESIGN was written but is now stale — the Draft DESIGN no longer exists at the recorded path (it was git-rm'd). The contract here is parallel to re-evaluation: `child_snapshots.design` should NOT be advanced to the Decision Record path. Two reasonable options:

- **Freeze with the pre-discard snapshot** (`status: Draft, content_hash: <pre-discard hash>`). On a later `/scope` resume, the live read fails (file doesn't exist) — the resume ladder MUST handle "snapshot exists but live file is missing" as a distinct case (treat as drift, fall through to the discard-commit SHA in state to confirm the rejection is the recorded reason, and offer Start-fresh).
- **Remove the snapshot entry** (i.e., set `child_snapshots.design` to absent, matching the absence of the durable artifact). Cleaner — the schema's I-5 invariant (absent fields when ungated) accommodates this. On later resume, no snapshot means no drift check; the discard-commit SHA in state is the durable signal.

The rejection sub-shape isn't strictly Decision 5's scope (Q5 asks about re-evaluation sub-shape specifically), but the symmetry is worth noting for Phase 3 cross-validation: in both sub-shapes, `child_snapshots` does not absorb the Decision Record. The rejection-sub-shape variant raises a separate sub-question (freeze pre-discard versus remove entirely) that the design doc should resolve when authoring the state-management reference.

## Edge Cases and Open Sub-Points for Cross-Validation

1. **Snapshot update on Accept-acknowledgment path.** Per the `/charter` Drift-Detection section, when an author chooses "Accept" on the three-option staleness prompt, the snapshot is UPDATED to match the live values. This is a separate write path from re-evaluation exit and does not conflict with the freeze rule for re-evaluation — but the design doc should state both rules together so the implementer doesn't conflate them ("we update on Accept; we freeze on re-evaluation exit").

2. **Snapshot for downstream-of-boundary children.** When PRD-boundary re-evaluation fires, the DESIGN and PLAN children may never have been invoked (the chain bailed at the PRD boundary). Their `child_snapshots` entries should be ABSENT (per I-5). The design doc should specify this absence rather than allowing `null` or empty-object placeholders. The state-schema reference's I-5 wording covers this; restating it for the re-evaluation case avoids ambiguity.

3. **Last-touched-but-bailed children.** A boundary at PRD means the chain ran `/brief` and `/prd` to completion. Both `child_snapshots.brief` and `child_snapshots.prd` should be FROZEN at the values captured at the moment of exit. The chain didn't advance past PRD; the snapshots aren't outdated, they're just at the boundary. Same freeze rule, no special case.

4. **Topic-rerun after a successful re-evaluation exit.** A subsequent `/scope` invocation finds a state file with `exit: re-evaluation` set. The resume ladder's row "state file has exit field set" fires first and offers revise/fresh routing. The frozen `child_snapshots` is consulted by the drift dual-check during that prompt's routing — drift detection works AS EXPECTED on the frozen snapshot. The freezing rule and the resume-ladder ordering interact cleanly.

## Implication for Design-Doc Authoring

The state-management reference (or the section of `references/parent-skill-state-schema.md` that `/scope` extends) should add explicit prose:

> On the `re-evaluation` exit path, `child_snapshots` SHALL retain the per-child `{path, status, content_hash}` values captured at the moment the chain last advanced past or exited at each child. The Decision Record's path is recorded in `exit_artifacts:`; the referenced upstream artifact is recorded in `referenced_artifact:`. `child_snapshots` SHALL NOT be advanced to the Decision Record path. This preserves drift-detection signal on subsequent resumes against the same topic.

The pattern-doc edit surface (Decision 8) should consider whether this rule lifts to pattern-level (`/charter` and `/scope` both write Decision Records on re-evaluation; both want the same freeze semantics) — provisional recommendation: **yes, lift to pattern-level**, with the wording above generalized to "the parent's children" and "the parent's exit-artifact path." Confirmation belongs in cross-validation Phase 3.

## Risks if the Recommendation Is Wrong

- **If we freeze and it should have advanced:** Author re-enters `/scope` post-re-evaluation, drift fires spuriously because the upstream PRD was lightly edited in passing (a typo fix) even though the Decision Record's substantive judgment still holds. The Accept option on the three-option prompt resolves the spurious drift by updating the snapshot to live, so the cost is one extra prompt per cosmetic edit. **Recoverable; cost is one extra interaction.**

- **If we advance and it should have frozen:** Author re-enters `/scope` post-re-evaluation many months later. The upstream PRD has been substantively rewritten out-of-chain. The resume ladder sees no drift (because it's comparing Decision Record to Decision Record), proceeds against a stale baseline, and either produces a downstream that contradicts the new PRD or silently revalidates a Decision Record whose foundational PRD is no longer the document it referenced. **Catastrophic for audit trail; cost is unbounded.**

The asymmetry of consequences strongly favors freezing.
