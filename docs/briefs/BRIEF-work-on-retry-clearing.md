---
schema: brief/v1
status: Done
problem: |
  Six gates in /work-on demand an artifact that a re-entry can supply from a
  previous round, so a phase re-entered after a retry can advance on work that
  predates the fix. What holds the line today is the agent submitting the right
  outcome, which is prose an agent can skip; one phase file says so, and also
  says the structural fix is impossible because koto has no removal verb. It
  has had one since v0.11.5.
outcome: |
  A phase that must redo its work is stopped from skipping it by the workflow
  rather than by an instruction. Every gate whose key can survive a re-entry is
  cleared on the path that re-enters it, and the phase files describe the
  mechanics they actually have.
---

# BRIEF: /work-on Retry Clearing

## Status

Done

Second framing of this topic. The first was written while koto had no way to
remove a context key, and against a phase file that has since been rewritten; it
is superseded. See Problem Statement for what is actually on disk now.

## Problem Statement

`/work-on` gates twelve of its states on `context-exists` over a context key.
The gate asks whether the key is present and nothing else, which is exactly
right for a state that waits for an artifact to appear for the first time, and
wrong for a state that can be entered twice.

Six of the twelve can be entered twice, and each one then finds an artifact from
the previous round sitting under its key:

- the three review panels — `scrutiny`, `review`, `qa_validation` — every
  `blocking_retry` returns to `implementation`, which routes forward into
  `scrutiny`, so a retry re-enters every panel at or above the one that raised
  it, and each finds the verdict it recorded before the code changed;
- `analysis`, whose `plan_artifact` gate holds `plan.md`, re-entered on
  `scope_expanded_retry` — a state whose whole purpose on that edge is to
  rewrite the plan, gated on the plan it is meant to replace;
- `finalization` and `deferral_approval`, both gating on `summary.md`, reached
  again after `finalization` submits `issues_found` and the run comes back
  through `verification`.

`deferral_approval` is worth naming separately because it looks safe and is not.
Exactly one transition targets it and nothing routes back into it, so the state
is entered once — but `finalization` upstream of it sits on a cycle, so that
single entry can happen with a `summary.md` written before the fix. The property
that matters is about the key, not the state: presence gating is sound only when
the key cannot survive from one evaluation of that gate into another, *by any
path*.

**One of the six has prose about this, and that prose is now wrong.**
`phase-4a-scrutiny.md` carries a Retry Loop section telling the agent to ignore
the stale artifact, and then:

> Do not try to delete it. `koto context` advertises `add`, `get`, `exists`, and
> `list` — koto has no verb that removes a key.

koto has had one since v0.11.5. The section closes by naming what actually holds
the line today:

> what keeps an earlier pass from advancing the workflow is the
> `scrutiny_outcome` you submit, which must always describe the round that just
> ran.

That sentence is accurate about the current mechanism and is the problem. The
guarantee is the agent's submitted outcome — prose an agent can skip — on the
one workflow where an agent skipping a step is the failure mode that produced
this defect. Nothing structural stops a `passed` submission from advancing on
last round's artifact, because the gate cannot tell the rounds apart.

The other five gates have no clearing prose at all. `phase-4b-review.md`,
`phase-4c-qa.md`, `phase-3-analysis.md` and `phase-5-finalization.md` say
nothing about what happens to their artifact on a re-entry, so the same
staleness sits there unnamed.

**Why this brief is being written a second time.** An earlier version of it was
scoped when the defect was a phase file instructing `koto context remove`, a
subcommand koto did not have. That instruction is gone — it was replaced by the
prose above — so the literal complaint in the filed issue is resolved. What
replaced it substituted an agent-discipline guarantee for a structural one and
documented the structural fix as impossible. It is now possible.

## User Outcome

An agent whose work is sent back gets a genuinely fresh verdict on the next pass.
The phases the run re-enters refuse to advance until this round's artifact
exists, and they refuse structurally — the workflow declines the submission
rather than the prose discouraging it. A run that loops back to rewrite its plan
is not gated on the plan it is replacing, and a finalization reached a second
time is not satisfied by the first summary.

When the clearing step cannot do its job, the run says so in a sentence an
operator can act on, on a stream that survives the `2>/dev/null` they are already
typing, and stops rather than continuing under a false success.

A maintainer reading any of these phase files can predict the workflow's
behaviour from the prose, including which direction the dependency runs between
the clearing step and the gate.

## User Journeys

### A review panel sends the work back

A `/work-on` run reaches `qa_validation`, the tester finds a defect, and the
agent submits `qa_outcome: blocking_retry`. The trigger is the return trip: the
run goes to `implementation`, a coder agent fixes the defect, and the run walks
forward through `scrutiny` and `review` before reaching `qa_validation` again.
The outcome shape: none of the three panels advances on the verdict it recorded
last round. Each one's key was cleared on the way out, so each demands a fresh
artifact — including the two that passed and never raised anything.

### A plan is rewritten mid-implementation

The same run discovers the scope expanded, and `implementation` submits
`scope_expanded_retry`, returning to `analysis`. The trigger is a loop-back to a
state whose job is to produce a *replacement* artifact. The outcome shape:
`analysis` does not advance on the `plan.md` it is being re-entered to rewrite.
This journey is distinct because the stale artifact is not a verdict about code
— it is the very document the phase exists to replace, which is the sharpest
form of the defect.

### A finalization comes back around

`finalization` finds unmet criteria and submits `issues_found`. The run returns
to `implementation`, then `verification`, then `finalization` again — and may
proceed from there into `deferral_approval` for the first and only time. The
trigger is re-entry through a cycle rather than into it. The outcome shape:
neither state is satisfied by the `summary.md` written before the fix, including
`deferral_approval`, which a state-shaped reading of the rule would wrongly call
safe.

### The clearing step cannot do its job

An agent on a machine where koto cannot write to the session store reaches any
of the retries above, with koto's stderr redirected as usual. The trigger is the
clearing step failing rather than succeeding. The outcome shape: the failure
announces itself on stdout, names the key, tells the agent what not to submit,
and stops the run. A failure that presents as success is the one outcome this
journey rules out.

### A maintainer edits a clearing step later

Someone changing how a phase records its results opens the phase file and edits
the block that clears the previous round. The trigger is the edit, not a run.
The outcome shape: a test that reads the shipped text out of the phase file and
drives it against a real koto session fails, so the edit is caught before it
merges. A pasted copy inside a test would keep passing after the shipped text
drifted, which is this defect class's whole failure mode.

## Scope Boundary

### In

- The clearing contract for **all six** gates whose key can survive a re-entry:
  `scrutiny_results.json`, `review_results.json`, `qa_results.json`, `plan.md`,
  and `summary.md` at both of its gates.
- The prose that states it, in the three panel phase files, in
  `phase-3-analysis.md`, in `phase-5-finalization.md`, and in
  `review-panel-orchestration.md`.
- **Correcting `phase-4a-scrutiny.md`'s claim that koto has no removal verb**,
  and replacing its agent-discipline guarantee with the structural one. Both
  sentences were true when written and are the reason the defect survived a fix;
  leaving them would leave a file that tells the next author the fix is
  impossible.
- A failure mode for the clearing step that does not present as success, with
  its diagnostic on a stream that survives `2>/dev/null`.
- Test coverage that drives the shipped text against real koto sessions rather
  than asserting the contract in prose.
- `/work-on`'s evals, updated where the phase contract changed, and run.

Six gates rather than three because the mechanism now reaches all six. The first
framing scoped to the three panels, and had to: it gated on artifact *content*,
and `plan.md` and `summary.md` are markdown written `--from-file`, which no
content pattern shaped around a results artifact can match. Removal does not
read the value, so one step covers every key.

**This is not a re-fix of the filed issue.** That issue reported a phase file
instructing a subcommand koto did not have, and that instruction is gone from
the tree. What is in scope here is the defect the instruction was aimed at,
which outlived it: six gates that cannot tell one round's artifact from the
next, currently guarded by asking the agent to be careful.

### Out

- **Changing any gate.** All twelve stay `type: context-exists`. With removal
  available a presence gate is the correct gate for "this phase must produce a
  fresh artifact", so `work-on.md`'s gate declarations are not touched.
- **The six sound gates** — `context.md`, `baseline.md` at three states, and
  `introspection.md`. Each sits on the pre-implementation spine, reached only
  from strictly upstream states and evaluated once in a run's life. They are
  correct as presence gates and stay as they are.
- **Adding anything to koto.** The verb this work needs shipped in v0.11.5. Any
  further koto change is a separate effort.
- **`context_assignments:` being a no-op.** koto's `Transition` carries `target`
  and `when` only; the block is dropped at compile time, so every
  `failure_reason` assignment in `work-on.md` does nothing. Real, wider than
  this brief, and recorded so the design does not build on it.
- **The rest of `/work-on`.** Every other phase, gate and directive stays as it
  is.

## References

- `tsukumogami/koto#196` — the merged change that added `koto context remove`,
  released in koto v0.11.5.
