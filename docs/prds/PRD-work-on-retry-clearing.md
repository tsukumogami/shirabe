---
schema: prd/v1
status: In Progress
problem: |
  Six gates in /work-on demand an artifact that a re-entry can supply from the
  previous round. What prevents a stale pass today is the agent submitting an
  outcome that describes the round that just ran -- prose an agent can skip, on
  the workflow where skipping a step is the failure mode in question. One phase
  file says so and also records that the structural fix is impossible because
  koto has no removal verb; koto has had one since v0.11.5.
goals: |
  The refusal becomes structural: a phase re-entered after a retry cannot
  advance until this round's artifact exists, because the key it gates on is
  gone. Every gate whose key survives a re-entry is cleared on the path that
  re-enters it, a clearing step that fails is distinguishable from one that
  worked, and no phase file tells the next author the fix is impossible.
upstream: docs/briefs/BRIEF-work-on-retry-clearing.md
source_issue: 304
---

## Status

In Progress

## Problem Statement

`/work-on` gates twelve states on `context-exists` over a context key. The gate
reports whether the key is present and nothing else. That is correct for a state
waiting for an artifact to appear for the first time and wrong for a state that
can be entered twice, because on the second entry the key is present with the
previous round's content.

Six of the twelve can be entered twice:

| Gate | Key | Re-entered via |
|---|---|---|
| `scrutiny_results` | `scrutiny_results.json` | any `blocking_retry` → `implementation` → `scrutiny` |
| `review_results` | `review_results.json` | a retry raised at `review` or below |
| `qa_results` | `qa_results.json` | a retry raised at `qa_validation` |
| `plan_artifact` | `plan.md` | `implementation` → `scope_expanded_retry` → `analysis` |
| `summary_exists` (finalization) | `summary.md` | `finalization` → `issues_found` → … → `finalization` |
| `summary_exists` (deferral_approval) | `summary.md` | reached once, from a `finalization` that sits on a cycle |

The remaining six sit on the pre-implementation spine — `context.md` twice,
`baseline.md` three times, `introspection.md`. Each is reached only from strictly
upstream states and evaluated once in a run's life. They are correct as presence
gates and are out of scope.

`deferral_approval` is the case that fixes the rule's wording. Exactly one
transition targets it and nothing routes back, so a state-shaped test calls it
sound; but `finalization` upstream sits on a cycle, so its single entry can
happen with a `summary.md` written before the fix. The property is about the
**key**, not the state: presence gating is sound only when the key cannot
survive from one evaluation of that gate into another, **by any path**.

**What currently prevents the stale pass, and why it is not enough.**
`phase-4a-scrutiny.md` is the only one of the six with prose on the subject. It
tells the agent to ignore the stale artifact, states that "koto has no verb that
removes a key", and closes: "what keeps an earlier pass from advancing the
workflow is the `scrutiny_outcome` you submit, which must always describe the
round that just ran."

That is an accurate description of today's mechanism and it is the defect. The
guarantee is an agent following an instruction, on the one workflow whose
failure mode is an agent not following one. The gate cannot distinguish the
rounds, so nothing structural refuses a `passed` submission carried by last
round's artifact. The other five gates have no such prose at all.

The claim about koto was true when written and is false now: `koto context
remove` shipped in v0.11.5, and shirabe's `.tsuku.toml` pins
`"tsukumogami/koto" = "latest"`, so the verb is present wherever shirabe runs.

## Goals

- A phase re-entered after a retry cannot advance on the previous round's
  artifact, and the refusal comes from the workflow rather than from prose.
- Every gate whose key can survive a re-entry is cleared by the path that
  re-enters it: all six, not the subset one mechanism happened to reach.
- A clearing step that fails is distinguishable from one that worked, on a
  stream that survives `2>/dev/null`, and does not present as success.
- No phase file records that the structural fix is impossible, and every phase
  file with a re-entrant gate says what happens to its artifact.
- The gate declarations do not change. A presence gate is the right gate once
  the key can be removed.

## User Stories

**As an orchestrating agent driving a retry**, I want the phases I re-enter to
refuse a `passed` outcome until this round's artifact exists, so that I cannot
close a panel on a verdict recorded before the fix even if I skip a step.

**As an agent whose run loops back to rewrite its plan**, I want `analysis` not
to be gated on the `plan.md` I am being re-entered to replace.

**As an operator reading output with koto's stderr redirected**, I want a failed
clearing step to print a sentence naming the key and what not to submit, so I
learn about it from the run rather than from a merged PR.

**As the next author to open `phase-4a-scrutiny.md`**, I want it to describe the
mechanism the workflow actually has, so I do not inherit a note saying the fix I
am about to write is impossible.

## Requirements

### Functional

- **R1. The six re-entrant keys are removed on the path that re-enters them.**
  A `blocking_retry` from any panel removes `scrutiny_results.json`,
  `review_results.json` and `qa_results.json`. A `scope_expanded_retry` removes
  `plan.md`. An `issues_found` from `finalization` removes `summary.md`.
- **R2. Removal covers every key the re-entry will re-read, not only the
  raising phase's.** A retry raised at `qa_validation` re-enters `scrutiny` and
  `review`, and the code both reviewed is about to change, so their verdicts are
  stale too.
- **R3. The clearing step verifies its own effect.** After removing, the step
  confirms the key is absent via `koto context exists` and stops if it is not.
  A failed removal leaves the key present and the gate satisfied, so an
  unverified removal is indistinguishable from a successful one at the point it
  matters.
- **R4. A failed clearing step announces itself on stdout**, names the key, says
  which outcome not to submit, and names the escalate outcome that still reaches
  a terminal state. stderr is the stream operators redirect away from koto's
  migration noise.
- **R5. The gate declarations are unchanged.** All twelve stay
  `type: context-exists`. Removal makes a presence gate correct rather than
  requiring a different gate type, so `work-on.md`'s gates are not edited.
- **R6. A broken context store must not brick the run.** The clearing step runs
  on the retry path, so a failure there must still leave a terminal state
  reachable. Naming the transitions rather than gesturing at them, because an
  earlier draft of this requirement said "the equivalent exits at `analysis` and
  `finalization`" and `finalization` has no escalate edge at all:

  | State | Exit that must stay reachable | Target |
  |---|---|---|
  | `scrutiny` / `review` / `qa_validation` | `blocking_escalate` | `done_blocked` |
  | `analysis` | `scope_changed_escalate`, `blocked_missing_context` | `done_blocked` |
  | `finalization` | `deferral_requested` | `deferral_approval` |

  Concretely: the clearing step must not be a precondition for submitting
  evidence at all. An implementation that aborts before `koto next` on a
  clearing failure — and stops there — leaves an operator with a run that can
  reach no terminal state on a store that cannot be written. R4's diagnostic
  therefore names the escalate outcome as the way out, not only the outcome to
  avoid.
- **R7. First-pass behaviour is unchanged.** A run reaching any of these phases
  for the first time, with no prior artifact, behaves exactly as it does today.
- **R8. Every phase file with a re-entrant gate states the contract**, and
  `phase-4a-scrutiny.md`'s claim that koto has no removal verb is corrected
  rather than left as a note to the next author.
- **R9. `review-panel-orchestration.md` states what a retry does to the three
  panel artifacts**, since it is the summary a reader meets before the phase
  files.

### Non-functional

- **R10. Demonstrated against real koto, not asserted.** A test drives real
  koto sessions and shows the gate's behaviour on both sides of the removal.
- **R11. The test runs the shipped text.** The clearing block is extracted from
  the phase files at run time rather than pasted into the test, so an edit that
  breaks the contract fails the test.
- **R12. `koto template compile` on `work-on.md` exits 0 with no new warning.**
  R5 means the template is untouched, so this is a regression check rather than
  a change check.
- **R13. `/work-on`'s evals reflect the changed contract, and are run.** Any
  assertion describing retry or gate behaviour is updated, and
  `scripts/run-evals.sh work-on` is executed with its result reported. A failing
  assertion is reported rather than rewritten to match.

## Acceptance Criteria

- [ ] For each of the six gates: with its key removed, submitting the phase's
      advancing outcome does not advance the workflow, and koto's response names
      the gate as the failing condition. Captured as test output.
- [ ] For each of the six: with the key present, the advancing outcome advances
      the workflow — the first-pass path is unchanged.
- [ ] **Traversal.** After a `blocking_retry` raised at `qa_validation`, all
      three panel keys are absent, and neither `scrutiny` nor `review` advances
      on `passed` — though neither raised the retry.
- [ ] **Traversal, from each entry point.** The same holds for a retry raised at
      `review` and at `scrutiny`.
- [ ] After a `scope_expanded_retry`, `plan.md` is absent and `analysis` does
      not advance on `plan_ready`.
- [ ] After `finalization` submits `issues_found`, `summary.md` is absent and
      neither `finalization` nor `deferral_approval` advances on it.
- [ ] The clearing step exits 0 when a key it is asked to remove was never
      written.
- [ ] With the context store unwritable, the clearing step exits non-zero,
      prints a diagnostic naming the key on **stdout** with stderr redirected to
      `/dev/null`, and says which outcome not to submit.
- [ ] The step's verification is `koto context exists` returning absent, not the
      removal's exit status alone, checked by extracting the shipped block.
- [ ] **A broken store still reaches a terminal state (R6).** With the context
      store unwritable so the clearing step fails, submitting the phase's
      escalate outcome still advances: `blocking_escalate` reaches `done_blocked`
      from each panel, `scope_changed_escalate` and `blocked_missing_context`
      reach `done_blocked` from `analysis`, and `deferral_requested` reaches
      `deferral_approval` from `finalization`. Exercised against real koto, not
      inferred from the template.
- [ ] The failed-clearing diagnostic names the escalate outcome, so an operator
      reading it knows the way out and not merely the way forward that is closed.
- [ ] `grep -c "koto has no verb that removes a key" skills/` returns 0.
- [ ] Every phase file holding a re-entrant gate states what happens to its
      artifact on re-entry: the three panel files, `phase-3-analysis.md`,
      `phase-5-finalization.md`.
- [ ] `review-panel-orchestration.md` states that a retry removes all three
      panel artifacts.
- [ ] `git diff origin/main...HEAD -- skills/work-on/koto-templates/work-on.md`
      is empty. A boundary check on the PR's own diff rather than a before/after
      test: it cannot fail before an implementation commit exists, and it is
      what catches a later change that reaches for the gate again.
- [ ] `koto template compile skills/work-on/koto-templates/work-on.md` exits 0
      with no new warning relative to `main`.
- [ ] The test extracts the clearing block from the shipped phase files at run
      time; editing a block to break the contract fails the test.
- [ ] `cargo test --workspace` passes with no existing test modified.
- [ ] `scripts/run-evals.sh work-on` has been run and its result reported,
      including any failing assertion.
- [ ] `shirabe validate --lifecycle . --mode=ready` exits 0 on the finalized
      chain.

## Out of Scope

- **Changing any gate type.** R5. The presence gate is correct once removal
  exists; converting it would be work that buys nothing.
- **The six sound gates.** `context.md`, `baseline.md` ×3, `introspection.md`.
  Each is evaluated once in a run's life, on the pre-implementation spine.
- **Adding anything to koto.** The verb shipped in v0.11.5.
- **`context_assignments:` being a no-op.** koto's `Transition` carries `target`
  and `when` only; the block is dropped at compile time, so every
  `failure_reason` assignment in `work-on.md` does nothing. Real, wider than
  this PRD, and named here so the design does not build on it.
- **The rest of `/work-on`.**

## Known Limitations

- **The clearing step is agent-performed, and koto cannot make it otherwise.**
  koto's engine never writes to the context store: `context_assignments:` is
  dropped at compile time, and a gate's `key:` is a static literal. So the
  removal lives in something an agent runs, and an agent that skips it entirely
  leaves the artifact in place. This is strictly better than today. The current
  guarantee is an agent submitting the right *outcome*, which is a judgment;
  the new one is an agent running a command sitting on the same path as the
  submission. It is not absolute, though, and R3's verification bounds a *failed*
  removal rather than a skipped one.

- **`koto overrides record` can advance past a failing gate**, whether or not the
  gate declares `override_default`. That is correct and auditable behaviour, but
  it means "structural" here means "structural modulo a recorded override".

## Decisions and Trade-offs

**Removal rather than overwrite-to-clear.** An earlier chain on this topic
settled on writing a sentinel value over the key and converting the gate to
`context-matches` so the sentinel failed it. That was the right answer when koto
had no removal verb, and it is not now. Removal is content-agnostic, so it
reaches `plan.md` and `summary.md` — markdown written `--from-file` — which no
pattern shaped around a JSON results artifact can match. It also removes the
sentinel from the artifact namespace entirely, and with it the failure mode
where a sentinel and a pattern drift into agreement and the gate silently starts
accepting cleared values.

**Verification is `context exists`, not the removal's exit status.**
`koto context exists` calls `store.ctx_exists`, and the `context-exists` gate
evaluator calls the same `store.ctx_exists`. They are the same predicate over
the same state, so "exists reports absent" is not a proxy for "the gate will
fail": it is that condition. The removal's own exit status is a weaker signal:
its implementation deletes the content file, then the lock file, then updates
the manifest, so a failure after the content is gone would report non-zero on a
removal whose gate-relevant effect had already landed.

**The gates are not touched.** It would be possible to reach the same guarantee
by converting them, and an earlier design did. Leaving them alone is better on
every axis available here: no template edit, no mermaid regeneration, no eval
fixture churn, and a smaller diff for a reviewer to hold. The gate that main
already ships turns out to be the right one.
