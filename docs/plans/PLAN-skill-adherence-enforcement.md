---
schema: plan/v1
status: Active
execution_mode: single-pr
upstream: docs/designs/DESIGN-skill-adherence-enforcement.md
milestone: "Skill Adherence Enforcement"
issue_count: 9
---

# PLAN: Skill Adherence Enforcement

## Status

Active

## Scope Summary

Implements the accepted design: a plugin-declared hook that refuses out-of-contract
writes during plan-scale execution, a read-only determination that reports whether a
session ran under the workflow, a conflict recorder that makes a justified departure
visible, and the skill-description repair with its measurement.

## Decomposition Strategy

**Walking skeleton.** The first two issues after the declaration form a thin
vertical slice that exercises the whole pipeline without enforcing anything: the
hook registers, evaluates, and writes a per-session witness; the determination reads
that witness alongside the orchestration records and returns a real verdict. Every
later issue thickens one layer of that path.

This is the right shape here for a reason specific to this feature. The design's
staging requires an observe-only period before denial is enabled, because the
false-positive rate of the arming predicate is the input that decides whether denial
is safe to turn on. A skeleton that runs end-to-end while refusing nothing is
exactly what produces that measurement, so the decomposition and the rollout want
the same first slice.

Horizontal decomposition was rejected: building the hook fully before starting the
determination would leave the determination's liveness input unavailable until late,
and the design already established that a determination without a liveness witness
reports indeterminate for every run and produces no evidence.

## Execution Mode

**single-pr**, and the observe-then-enforce staging does not force otherwise.

The staging gate is operational rather than structural: denial ships behind the
operator switch the requirements already mandate, defaulting to observe-only, and
is enabled by configuration after the false-positive rate has been read from real
sessions. No code needs to reach main before other code can be written, and no
merge gate sits between the units, so neither multi-pr escape condition is met.

The alternative considered was multi-pr with the observe-only hook landing first.
It was rejected because it buys nothing the default-off switch does not already
provide, while adding milestone and issue ceremony and a second review cycle.

## Issue Outlines

### Issue 1: Extract the closed write-target set into a machine-readable declaration

**Goal**: Turn `/execute`'s closed write-target set from prose in its Security
Considerations into a data file shipped with the plugin, so the hook and any other
consumer read one declaration rather than parsing English.

**Acceptance Criteria**:
- [ ] A declaration file ships with the plugin and enumerates every target class the
      skill's Security Considerations currently names in prose: the state file and
      scratch under the skill's wip prefix, the skill's own files, the home pull
      request operations, the finalization cascade's chain transitions under `docs/`,
      and Decision Records on re-evaluation.
- [ ] The skill's prose points at the declaration as the source of truth rather than
      restating the set, so the two cannot drift.
- [ ] A path inside the set and a path outside it are each classified correctly by a
      unit test reading the declaration.
- [ ] The declaration is resolvable from a hook process via the plugin root.

**Dependencies**: None

**Type**: code
**Files**: `skills/execute/SKILL.md`

---

### Issue 2: Register the adherence hook and write the per-session witness

**Goal**: Ship the hook registered on the edit-shaped tools, running a fail-open
subcommand that evaluates nothing yet, always allows, and writes the per-session
witness the determination needs as its liveness input.

**Acceptance Criteria**:
- [ ] The plugin declares a `PreToolUse` hook matching the edit-shaped tools, using a
      command handler, guarded so that an absent binary exits zero without blocking.
- [ ] The handler always allows in this issue; no path denies.
- [ ] A witness file is created once per session, keyed by session, carrying session
      and agent identity, the component's contract version, a first-seen timestamp,
      and the working directory.
- [ ] The witness is created with an exclusive-create operation, so two hook
      processes racing on the same event cannot both create it or corrupt it.
- [ ] The witness is written after a cheap existence check for a plans directory, so
      it is not created in repositories that cannot host plan-scale execution.
- [ ] A session in a repository with no plans directory completes with no witness and
      no measurable delay.
- [ ] Removing the binary from the path leaves sessions running unblocked.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe/src/main.rs`

---

### Issue 3: Implement the arming predicate over prompt-shaped records only

**Goal**: Decide whether a session is performing plan-scale execution in the
orchestrator role, reading only the instructions the session was given.

**Acceptance Criteria**:
- [ ] The scan admits only prompt-shaped received records and excludes tool-result
      payloads and attachment records.
- [ ] A session that merely reads, greps, or reviews a plan file does not arm. This is
      the regression test for the denial-of-service surface the security review found:
      a plan filename appearing in tool output must never arm.
- [ ] A session whose given instructions name a resolvable plan, whose target exists
      and carries the plan schema, arms.
- [ ] A session whose instructions carry a single-issue delegation marker does not arm.
- [ ] A plan whose execution mode is coordinated does not arm.
- [ ] Every failure path allows: missing file, unreadable file, unresolvable
      reference, parse error, over-cap read, over-cap match count.
- [ ] Reads are byte-capped and reference matches are count-capped, with the caps
      stated in the code and exceeding either treated as allow-and-record.
- [ ] The reference is resolved and confined to the working tree, the read operates on
      the resolved handle rather than re-resolving the name, a symlink at the final
      component is refused, and the opened file is confirmed regular.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `crates/shirabe/src/main.rs`

---

### Issue 4: Cache the arming decision as a tail scan with race guards

**Goal**: Keep the arming predicate's cost proportional to newly appended bytes
rather than to transcript size, without freezing a decision that must remain able to
change.

**Acceptance Criteria**:
- [ ] The cache stores a byte offset and the state derived to that offset as one
      atomic pair, and re-folds from whichever pair is read.
- [ ] A stale pair read under concurrency produces a redundant rescan over a superset
      and never a wrong answer.
- [ ] A record file shorter than the stored offset resets to the initial state and
      re-derives from the start.
- [ ] A session that arms and then receives a later instruction re-scoping it to a
      single issue disarms. This is the case a frozen verdict would get wrong.
- [ ] What is cached is the arming decision, not the refusal verdict: two writes to
      different targets in one armed session are evaluated separately.
- [ ] Measured cost per call after the first is proportional to appended bytes.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code
**Files**: `crates/shirabe/src/main.rs`

---

### Issue 5: Implement the determination's registration and delegation counting

**Goal**: Establish, read-only and after the fact, whether a session registered an
orchestration session and whether it delegated every issue.

**Acceptance Criteria**:
- [ ] Registration is read from the session's workflow record, scoped to this
      repository by the encoded project directory, taking the freshest record by
      modification time when a session appears under more than one directory.
- [ ] Delegation is counted from the terminal index scoped by that same encoded
      project directory, and session identities are matched on a delimited boundary
      rather than a bare string prefix.
- [ ] A parent whose name is a prefix of unrelated sessions does not count those
      sessions as its children. This is the regression test for the cross-session
      contamination the security review found.
- [ ] The expected count is read from the plan document.
- [ ] All reads parse the files directly; the determination never shells out to
      another binary to read them.
- [ ] The determination is read-only and writes nothing.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `crates/shirabe/src/adherence_check.rs`

---

### Issue 6: Complete the determination's outcome domain and conflict join

**Goal**: Return one of the six defined outcomes, joining the conflict store so that
a justified departure is distinguished from a silent one.

**Acceptance Criteria**:
- [ ] The outcome is one of conforming, non-conforming, coordinated, departed,
      disabled, or indeterminate.
- [ ] A run that registered and delegated every issue reports conforming.
- [ ] A run that invoked the skill, ran its scripts, and implemented in the
      orchestrator role reports non-conforming.
- [ ] A run that delegated all but one issue reports non-conforming when the shortfall
      is uncovered.
- [ ] A shortfall covered by a conflict record naming that step reports departed, and
      never conforming. Recording a conflict is not sufficient to obtain conforming.
- [ ] A conflict record naming a different step does not cover the shortfall.
- [ ] The conflict join reads the store for the orchestrator and for each child,
      because a child records under its own session identity.
- [ ] A coordinated run reports coordinated, and not conforming and not
      non-conforming.
- [ ] A missing witness reports indeterminate, never non-conforming.
- [ ] A run whose enforcement was switched off reports disabled, distinguishable from
      indeterminate.

**Dependencies**: Blocked by <<ISSUE:5>>, <<ISSUE:8>>

**Type**: code
**Files**: `crates/shirabe/src/adherence_check.rs`

---

### Issue 7: Enable the refusal behind a default-off operator switch

**Goal**: Deny writes outside the declared set when armed, with a reason the refused
session can act on, shipped default-off so the false-positive rate can be measured
first.

**Acceptance Criteria**:
- [ ] When armed and the target falls outside the declaration, the handler denies.
- [ ] The deny reason names the refused target and the sanctioned alternative for
      that target, and two refusals of different targets carry different text.
- [ ] The reason is assembled as a structured string value so a crafted path cannot
      escape it or inject a terminal control sequence.
- [ ] The refused session proceeds correctly on its next attempt with no human input.
- [ ] Denial holds in a permission-bypassing, non-interactive session.
- [ ] A write inside the declared set is permitted while armed.
- [ ] A write from a delegated single-issue session to that issue's files is
      permitted.
- [ ] The refusal defaults to off; enabling it is an operator action requiring no edit
      to skill or workflow content.
- [ ] With the refusal off, the witness is still written and marked disabled, so the
      determination can report disabled rather than indeterminate.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:4>>

**Type**: code
**Files**: `crates/shirabe/src/main.rs`

---

### Issue 8: Ship the conflict recorder with fail-closed redaction

**Goal**: Give a session one route to record a departure before taking it, working
whether or not an orchestration session exists, and surface it to the author.

**Acceptance Criteria**:
- [ ] One subcommand records a conflict, requiring the instruction, the conflicting
      workflow step, and the intended course; it refuses to write with any of the
      three empty.
- [ ] The record is written to a durable machine-local store that survives a reboot,
      keyed by session, append-only, with owner-only permissions.
- [ ] The route works when no orchestration session exists.
- [ ] When an orchestration session does exist, the same invocation also mirrors the
      record into it, best-effort, and a mirror failure does not fail the local write.
- [ ] The published form reuses the existing fail-closed redaction control rather than
      an authored summary, so no path, repository name, or issue number belonging to a
      private repository appears in a public surface.
- [ ] A record written into a public repository is verified free of private-repo
      references by a test.
- [ ] The record reaches the author without the author querying the session.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe/src/conflict_record.rs`

---

### Issue 9: Repair the skill description and measure the change

**Goal**: Make the plan-execution skill's description name the situations in which it
applies, and make that change falsifiable by measuring selection before and after.

**Acceptance Criteria**:
- [ ] A plan-shaped prompt set is committed, separate from the existing behavior eval
      file, in the list shape the evaluation runner parses, with both positive cases
      and genuine near-miss negatives covering the boundary against the single-issue
      workflow.
- [ ] The existing eval-existence CI check still passes, meaning the new file does not
      reuse the filename that check keys on.
- [ ] A committed wrapper runs the measurement and records a quantized per-query pass
      rate with a declared tolerance band.
- [ ] The baseline is measured and recorded against the current description before any
      rewrite.
- [ ] The description is rewritten to name applying situations and to use no term
      absent from the skill's user-facing documentation.
- [ ] The measurement is re-run and both rates are recorded.
- [ ] Two runs over an unchanged set agree within the declared band.

**Dependencies**: None

**Type**: code
**Files**: `skills/execute/evals/trigger-set.json`

---

## Implementation Sequence

Dependencies are declared per outline above rather than as a diagram, which is the
single-pr shape. Restated here as a sequence:

- Issue 2 gates issues 3 and 5.
- Issue 3 gates issue 4; issue 4 gates issue 7.
- Issue 1 gates issue 7.
- Issues 5 and 8 both gate issue 6.

**Critical path**: issue 2, then 3, then 4, then 7. Four issues deep, and it is the
path that ends in denial being possible, which is the highest-risk capability here.

**The walking skeleton is issues 2 and 5.** Together they run the whole pipeline
with nothing enforced: the hook evaluates and records, the determination reads the
record and returns a verdict. Everything after thickens one layer.

**Parallelizable from the start**: issues 1, 2, 8 and 9 have no dependencies. Issue
9 is fully independent of the enforcement work and could be done by a different
person at any time.

**Ordering constraint inside issue 9** that the dependency graph cannot express: the
baseline measurement must be recorded before the description is rewritten. Running
it afterward leaves the change unfalsifiable, which is the entire reason the
measurement exists.

**Operational gate after issue 7**, outside the plan's scope: the refusal ships
default-off and is enabled only once the false-positive rate observed from real
sessions is acceptable. Issues 2 through 6 landing in main is what produces that
rate.
