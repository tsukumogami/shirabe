---
status: Accepted
problem: |
  As the single-issue executor, `/work-on` decides one issue is done by the agent's own
  judgment, which accepts "verification authored" for "verification passed" and lets the
  agent introduce caveats or deferrals unilaterally. An issue can be reported done with an
  unverified or quietly deferred acceptance criterion, leaving the human to audit for what
  was skipped. There is no enforced definition of done at the single-issue level.
goals: |
  Make `/work-on`'s single-issue completion a workflow-enforced definition of done:
  verified-by-execution (the verification for what the issue touched runs and passes;
  existence never substitutes for execution; default is the repo's tests), declared by the
  project rather than the generic skill, and no-silent-deferral (any unmet criterion or
  deferral is a surfaced, human-approved decision). shirabe's instance enforces that an
  issue changing a skill has that skill's evals run and passing.
upstream: docs/briefs/BRIEF-work-on-definition-of-done.md
motivating_context: |
  Hit directly: a skill's evals were authored but never executed, the work was reported
  complete, and hedge language shipped — the human caught the shortfall. The fix belongs in
  the workflow at the single-issue altitude `/work-on` now owns.
---

# PRD: work-on Definition of Done

## Status

Accepted

## Problem Statement

`/work-on` takes one issue to a pull request. With plan-level iteration moving to a separate
coordinator, finishing that single issue is `/work-on`'s whole job — and the point at which
it decides the issue is done is governed only by the agent's judgment. That judgment
repeatedly accepts evidence that work was *attempted* in place of evidence that work was
*verified*: a test or eval is authored and committed but never run, or an acceptance
criterion is quietly deferred behind hedge language the agent introduced on its own. The
issue reads done; the human inherits the audit for what was skipped.

This affects the author who hands off an issue and expects a finished result, and the
reviewer or future reader who must otherwise re-verify what the workflow claimed.

## Goals

- Single-issue completion is a workflow gate, not the agent's discretionary judgment.
- "Done" means each acceptance criterion is verified by execution — the relevant verification
  ran and passed — never merely authored or confirmed to exist.
- What verification to run is declared by the project (the generic skill holds the principle;
  the project holds the specifics), with the repo's standard tests as the default.
- No deferral or caveat ships without explicit human approval.
- shirabe's own configuration enforces that an issue changing a skill runs that skill's evals.

## User Stories

- As an **author**, I hand `/work-on` a single issue and trust that "done" means every
  acceptance criterion was verified by execution, so I don't audit for hidden shortfalls.
- As an **author** in a project with its own verification, I want `/work-on` to run that
  verification for what the issue touched and require it to pass, without me wiring it each time.
- As an **author**, when a criterion genuinely can't be met now, I want to be asked to decide
  — approve a deferral or treat the issue as blocked — not handed a result that hides it.
- As a **reviewer**, I want a finished issue's PR to carry no unapproved caveat language and
  no unverified criteria, so I can build on it without re-checking.
- As a **shirabe maintainer**, I want an issue that changes a skill to fail completion unless
  that skill's evals were executed and passing, closing the gap the existence check leaves open.

## Requirements

Functional — the definition-of-done gate (single issue):

- **R1.** Completing a single issue MUST pass a workflow-enforced definition-of-done gate;
  `/work-on` MUST NOT report an issue done on the agent's judgment alone.
- **R2.** Each of the issue's acceptance criteria MUST be backed by verification that has
  actually run and passed during the run. "The verification exists" — authored, committed, or
  satisfying an existence check — MUST NOT satisfy the gate.
- **R3.** The verification the gate runs is determined by what the issue's change touched,
  resolved from a project-declared map (R7–R8); when no project mapping applies, the gate
  falls back to the repository's standard test command.
- **R4.** No silent deferral: `/work-on` MUST NOT report an issue done while any acceptance
  criterion is unmet or deferred. An unmet/deferred criterion halts and is surfaced to the
  human as an explicit decision.
- **R5.** On explicit human approval, a deferral is recorded as the human's decision (an
  audit trail on the issue/PR); without that approval the issue is reported **blocked**, not
  done.
- **R6.** Unapproved caveat or hedge language in the issue's shipped artifacts is disallowed;
  caveat language is permitted only where it records a human-approved deferral or phased step
  (R5).
- **R11.** If the gate cannot determine or run the applicable verification (no project mapping
  and no detectable test command, or the verification cannot execute), it MUST fail closed —
  route to the no-silent-deferral path (R4) for a human decision — rather than passing.

Functional — the project-declared verification surface:

- **R7.** The generic `/work-on` workflow MUST hold the definition-of-done principle (R1–R6,
  R11) without encoding any project-specific verification commands.
- **R8.** A project declares a map from the kinds of change an issue can touch to the
  verification command(s) that must run and pass. The declaration lives in project
  configuration, consumed by `/work-on`; the generic skill carries no project's specifics.
- **R9.** shirabe's own declaration MUST require that an issue changing a skill (`skills/**`)
  has that skill's evals **executed and passing** — not merely present — making `/work-on`
  enforce the existing `CLAUDE.md` `## Skill Evals` rule rather than relying on the
  existence check.

Functional — scope and consistency:

- **R10.** The definition of done applies to **single-issue** execution only; it does not
  define completion for a plan, milestone, or coordinated set (owned by the
  implementation-altitude coordinator).
- **R12.** The gate runs the project's **existing** verification tooling; it introduces no new
  test or eval runner.

Non-functional:

- **R13.** When the gate runs, blocks, or surfaces a deferral decision, `/work-on` announces
  what verification it ran (or why it could not), so the human sees the basis for "done"
  (least astonishment).

## Acceptance Criteria

- [ ] `/work-on` reports a single issue done only after a definition-of-done gate passes; it
      does not report done on judgment alone. (R1)
- [ ] An issue whose change adds a test/eval that was authored but not run is **not** reported
      done until that verification has run and passed. (R2)
- [ ] For an issue touching a kind of change the project maps, the gate runs the mapped
      verification; with no mapping, it runs the repo's standard test command. (R3, R8)
- [ ] An issue with an unmet or deferred acceptance criterion halts and surfaces a human
      decision; it is not silently reported done. (R4)
- [ ] An approved deferral is recorded as the human's decision; an unapproved one yields a
      **blocked** outcome, not done. (R5)
- [ ] A finished issue's shipped artifacts contain no unapproved caveat/hedge language; any
      caveat present maps to a recorded human-approved deferral. (R6)
- [ ] When the gate cannot determine or run verification, it fails closed to a human decision
      rather than passing. (R11)
- [ ] By inspection, the generic `/work-on` skill encodes no project-specific verification
      commands; project specifics live in project configuration. (R7, R8)
- [ ] In shirabe, an issue changing a skill is not reported done unless that skill's evals were
      executed and passing. (R9)
- [ ] Running `/work-on` on a plan/milestone is unaffected by this gate's single-issue scope
      (the gate does not define plan-set completion). (R10)
- [ ] The gate invokes existing verification tooling only; no new runner is added. (R12)
- [ ] `/work-on` announces the verification it ran or why it blocked. (R13)

## Out of Scope

- Plan-level, milestone, and coordinated multi-PR execution and their completion — owned by
  the separate implementation-altitude coordinator (`/execute`). (separate effort)
- The scope reduction that narrows `/work-on` to a single issue — assumed here, performed
  elsewhere.
- The exact encoding of the gate in the koto workflow (new state vs modified finalization vs
  blocking decision gate) and the exact project-declaration mechanism (extension file vs
  CLAUDE.md header vs other config). (DESIGN)
- Defining the verification commands non-shirabe projects should run. The capability lets a
  project declare its map; it does not prescribe other projects' commands.
- Changes to the test/eval runners themselves. (out)

## Known Limitations

- A project that declares no verification map and has no detectable standard test command
  gets the fail-closed path (R11): `/work-on` cannot self-verify and must route to a human
  decision. Making such a project fully automatic requires it to declare a map — by design,
  not a gap.
- Whether unapproved-caveat detection (R6) is enforced mechanically (a check) or by review
  discipline is a DESIGN decision; the requirement is that unapproved hedging not ship, not a
  specific detector.

## Decisions and Trade-offs

- **Principle in the generic skill, specifics in the project (R7–R8).** Alternatives:
  hard-code a verification per language in `/work-on` (couples a general tool to specific
  stacks), or leave verification entirely to per-run judgment (the status quo this PRD
  closes). Chosen so the discipline is universal while the commands stay project-owned —
  matching how `/work-on` already reads a project extension for quality requirements.
- **Fail-closed when verification can't be determined (R11).** Alternative: pass when no
  verification is found (silent-pass — the exact failure mode this PRD exists to prevent).
  Chosen because "can't verify" must never read as "verified."
- **No blanket caveat ban (R6).** A human-approved phased step is legitimate; only unilateral,
  unapproved hedging is disallowed. Banning the word outright would block legitimate
  phased rollouts and miss the real problem, which is *who decided* to defer.
