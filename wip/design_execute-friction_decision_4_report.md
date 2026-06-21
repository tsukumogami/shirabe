# Decision D4: Where and what is the manual/fallback "finalization not done" guard (PRD R5)?

PRD R5 (`docs/prds/PRD-execute-friction.md:130-133`): a run whose finalization did
not complete through the automated path SHALL be detectable mechanically — a check,
invokable both by a human from the CLI and in CI, that reports whether the chain's
finalization is complete.

The question is concretely *which* CLI surface owns the check and *what* it inspects.
The exploration's framing ("a new `shirabe validate` mode") is correct in spirit, but
the source shows the mechanism already exists: it is `shirabe validate --lifecycle-chain
<doc> --mode=ready`. The decision is therefore not "build a new mode" but "promote an
existing internal probe to a first-class R5 guard, seeded on a durable doc."

## Options Considered

1. **New dedicated validate mode `--finalization-complete <doc>`.** A fresh flag with
   its own check body that asserts PLAN-deleted + BRIEF/PRD→Done + DESIGN→Current.
   Rejected: it would duplicate the passing-state logic already implemented in
   `crates/shirabe-validate/src/lifecycle.rs` (`run_lifecycle_chain_check`,
   `PassingState`, `target_state_for`). Two code paths computing "is the chain
   finalized?" drift apart. Violates the workspace single-source preference.

2. **A new renderer/subcommand (`shirabe finalization-status`).** Rejected outright by
   the CLI-Surface contract (`CLAUDE.md:161-183`): compiled CLI logic is justified only
   for deterministic validation/feedback and gh-backed live checks; new correctness
   rules "belong here as checks or modes ... never in a renderer." A standalone
   subcommand that reports chain posture is a validation concern, so it must be a
   `validate` mode, not a sibling command.

3. **Reuse `--lifecycle-chain <doc> --mode=ready` as-is, documented and CI-wired as the
   R5 guard.** Chosen. The negation of the finalized terminal is exactly what ready
   posture already fails on.

## Chosen Option (the validate mode)

**Reuse the existing `shirabe validate --lifecycle-chain <doc> --mode=ready` mode as the
R5 finalization-not-done guard.** No new flag, no new subcommand. The DESIGN should name
this mode as R5's mechanism and add (a) a one-line CLI-help note that ready-posture
`--lifecycle-chain` *is* the finalization guard and (b) a CI step that runs it on the
chain's surviving seed doc.

Why this mode is sufficient — what "finalization complete" MEANS, and how the validator
already encodes its negation (`crates/shirabe-validate/src/lifecycle.rs`):

- `target_state_for` (lines 227-236) fixes the per-type terminal: PLAN → Deleted,
  ROADMAP → Deleted, BRIEF → Done, PRD → Done, DESIGN → Current. This is exactly the
  cascade's finalized terminal that `run-cascade.sh` produces (PLAN git-rm'd, BRIEF/PRD
  transitioned Done, DESIGN promoted to `docs/designs/current/`; see
  `skills/execute/scripts/run-cascade.sh:684-866`).
- Under `--mode=ready` (`ReviewPosture::Ready`), the single-pr mid-PR exemption is
  disabled, so a **present** PLAN (at Active *or* Done) and a BRIEF/PRD still at
  Accepted fail **L01** — the umbrella state-vs-posture code (lifecycle.rs L01 doc
  comment lines 13-18). A manual/fallback run that skipped finalization leaves the PLAN
  on disk and the upstreams untransitioned: that is precisely the L01-failing state.
- The cascade itself already trusts this equivalence: its inline `lifecycle_probe`
  (`run-cascade.sh:263-321`) runs `validate --lifecycle-chain "$PLAN_DOC" --format json
  --mode=ready` and treats a non-zero exit as "chain not yet finalized" (pre-probe) and
  exit 0 as "chain finalized" (post-probe). R5 is the same probe invoked by a human/CI
  instead of by the cascade.

So "finalization complete" == ready-posture clean pass (exit 0); "finalization not done"
== ready-posture failure (exit 2, L01). The check the PRD asks for is the one the
cascade already self-verifies with.

## Concrete Mechanism (flag, what it checks, exit codes, CLI+CI invocation)

**Flag / mode:** `shirabe validate --lifecycle-chain <seed-doc> --mode=ready
--format <human|json>`

**What it inspects:** `run_lifecycle_chain_check` (lifecycle.rs:1010+) canonicalizes the
seed doc, derives the chain root by stripping the `docs/{briefs,prds,designs,
designs/current,plans,roadmaps}/` suffix, builds the doc index, filters to the one chain
containing the seed, infers posture from the PLAN's `execution_mode`/`status`, and under
ready posture verifies every member is at its passing state. Returns empty (clean) when
the chain is at its finalized terminal; returns L01 (state-vs-posture mismatch) for a
present PLAN / un-transitioned BRIEF/PRD/DESIGN, L02-L05 for orphan/cycle/missing-upstream/
parse faults.

**Exit-code contract** (`crates/shirabe/src/main.rs:335-401`, `ValidateOutcome`,
shared verbatim with `transition`/`finalize-chain`):

| Exit | Meaning | R5 interpretation |
|------|---------|-------------------|
| 0 | clean | Finalization **complete** — chain at its terminal |
| 1 | tool-error | Bad invocation / unreadable input — inconclusive, not a pass |
| 2 | violations (L01...) | Finalization **NOT done** — the guard fires |
| 3 | io | reserved, not emitted by validate |

JSON consumers read the versioned `shirabe-validate/v1` envelope
(`main.rs:154-189`); the `outcome` label is `clean` / `violations` / `tool-error`. Exit
code alone is the branch signal — JSON is for diagnostics (matching how
`lifecycle_probe` consumes it).

**Seed-doc choice (the one real design constraint).** `run_lifecycle_chain_check` seeds
on a path that must exist: a missing seed returns L05 / exit 2 (lifecycle.rs:1018-1029).
A finalized chain has its PLAN deleted, so a human cannot seed on the PLAN after the
fact. Two clean cases, both serviceable:

- **The manual/fallback run the guard targets**: finalization did *not* complete, so the
  PLAN is still on disk. Seed on the PLAN — it exists, and ready posture fails L01. This
  is the exact scenario R5 names ("a manual or fallback run"), and the natural seed is
  available by construction.
- **General CI use** where you want a green pass on a finalized chain too: seed on a
  *durable* surviving member — the DESIGN (terminal `docs/designs/current/DESIGN-*.md`)
  or BRIEF/PRD (terminal Done, never deleted). These survive finalization, so the same
  invocation returns exit 0 on a complete chain and exit 2 on an incomplete one.

  Recommendation: DESIGN prescribes **seed on the DESIGN doc** for the CI guard (always
  present in a finalized chain, unambiguous chain anchor) and notes the PLAN as the
  seed for the human-run "did my manual finalization land?" check.

**Human (CLI) invocation:**
```
shirabe validate --lifecycle-chain docs/plans/PLAN-<slug>.md --mode=ready --format human
# exit 0 = finalized; exit 2 + L01 = finalization not done (PLAN still present, etc.)
```
After a finalized run, seed on the surviving anchor instead:
```
shirabe validate --lifecycle-chain docs/designs/current/DESIGN-<slug>.md --mode=ready
```

**CI invocation** (extends the existing `.github/workflows/validate-docs.yml` pattern,
which already shells `shirabe validate` at lines 97-100). Add a chain-finalization step
gated on ready-for-review, mirroring the posture convention in `main.rs:225-227`
(assert `ready` only when `github.event.pull_request.draft == false`):
```yaml
- name: Finalization guard (R5)
  if: github.event.pull_request.draft == false
  run: |
    for d in $(git diff --name-only ... | grep -E 'docs/designs/current/DESIGN-'); do
      shirabe validate --lifecycle-chain "$d" --mode=ready --format human || exit 2
    done
```
On a draft PR the default `--mode=draft` posture applies (the cascade is legitimately
mid-flight), so the guard does not false-fire — identical to how the lifecycle CI step
already gates ready posture.

## Why a validate mode, not a subcommand

The CLI-Surface contract (`CLAUDE.md:161-183`) is explicit: artifacts are authored by
skills; `shirabe validate` is the feedback/correctness engine and new correctness rules
"belong here as checks or modes ... never in a renderer." It even records the removed
`shirabe coordination create/status/sync` subcommand as the cautionary precedent. "Is
this chain finalized?" is a deterministic read-only correctness judgment over on-disk
frontmatter — the textbook validate concern. A `finalization-status` subcommand would
re-litigate a settled anti-pattern. Reusing `--lifecycle-chain` goes one better than a
new mode: it adds zero CLI surface and keeps a single implementation of "finalized
terminal" shared between the cascade's self-check and the human/CI guard.

## Open Risks

- **Seed-doc availability after finalization.** A fully finalized chain has no PLAN; a
  human who seeds on the deleted PLAN path gets L05/exit 2 (looks like a failure). Must
  be documented: post-finalization, seed on the DESIGN/BRIEF/PRD anchor. The DESIGN
  should state the seed-selection rule plainly so the guard is not mis-invoked.
- **L05 conflates "chain not found" with "finalization not done."** Both map to exit 2.
  A wrong path and an unfinalized chain are indistinguishable by exit code alone;
  callers that care must inspect the JSON `code` field (L05 vs L01). Acceptable for a
  guard whose pass/fail signal is binary, but worth a one-line note.
- **No new test surface, but a new *contract* surface.** Promoting an internal probe to
  a documented R5 guard means the ready-posture L01 semantics are now an external
  promise. Any future change to posture inference (`Posture` in lifecycle.rs) must hold
  R5's "present PLAN ⇒ fail" invariant. Add an explicit test asserting the R5
  invocation shape (seed on DESIGN of a finalized chain ⇒ exit 0; seed on a chain with a
  present PLAN ⇒ exit 2 / L01) so the guarantee is pinned independently of the cascade's
  own probe tests.
- **Multi-pr vs single-pr posture.** Ready posture re-targets single-pr mid-PR to
  single-pr at-merge; multi-pr postures are unchanged (lifecycle.rs:1005-1009). A
  multi-pr chain mid-effort legitimately has a present PLAN and would read as "not done"
  — correct for R5 (it genuinely isn't finalized) but the DESIGN should confirm the
  guard is meant to run at finalization time, not mid-effort, to avoid noise.
