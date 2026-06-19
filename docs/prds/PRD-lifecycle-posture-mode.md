---
schema: prd/v1
status: Accepted
problem: |
  shirabe validate's lifecycle checking returns the same verdict regardless of
  whether the work is an early local draft or a review-ready PR. Findings that
  are normal mid-draft hard-fail (exit 2), the only control is a --strict boolean
  the CI shell sets from PR draft state (unreadable by local runs and naming an
  enforcement level rather than author intent), and the result never explains
  whether a finding is a real blocker or just "not ready yet."
goals: |
  Make the lifecycle verdict match where the work is in its lifecycle: in-flight
  work passes (with advisory guidance on what must become true before it is
  review-ready), review-ready work is held to the full bar, the verdict stays a
  pure function of its inputs, and the result explains itself in posture terms.
upstream: docs/briefs/BRIEF-lifecycle-posture-mode.md
source_issue: 197
---

## Status

Accepted

## Problem Statement

`shirabe validate --lifecycle` is run by several distinct callers: an agent or
author drafting an artifact chain locally before any pull request exists, CI on a
draft PR, CI on a ready-for-review PR, and ad-hoc manual checks. Every caller gets
the same verdict for the same documents, regardless of where the work sits in its
lifecycle.

Work that is legitimately in flight produces lifecycle findings that are normal at
that stage — a document not yet linked into its chain (orphan), an issue outline
that does not yet carry acceptance criteria, a design not yet promoted to its final
directory. The validator treats these as hard failures (exit 2). The result is a
red build on a healthy draft; the concrete instance is issue #197, where the head
of a fresh `/scope` chain (a BRIEF at Draft with no downstream artifact yet)
hard-fails the lifecycle check on a draft PR.

The only existing control is a `--strict` boolean that the CI workflow sets from
`github.event.pull_request.draft`. This shape has three costs. A local caller has
no PR to read draft state from and no way to know which posture is right. The flag
names an enforcement level (`strict`) rather than the author's intent (still
drafting vs ready for review), so using it correctly means reverse-engineering the
enforcement model. And when a finding fires, the output is a bare pass/fail with no
indication of whether it is a genuine blocker or just "not ready yet," and no
guidance toward a passing state.

Affected: shirabe contributors and the agents running its workflows (every `/scope`
and `/charter` chain passes through the lifecycle check), and shirabe's own CI.

## Goals

- A lifecycle verdict that depends on a declared posture — in-flight (draft) vs
  review-ready (ready) — so in-flight work is not failed for being mid-stream.
- In-flight as the safe default: absent a positive review-ready signal, the check
  treats the work as in-flight.
- A documented, single classification of which lifecycle findings are tolerated
  while drafting and which always block.
- Output that explains a verdict in posture terms and points toward a passing
  state, without that explanation ever changing the verdict.
- The verdict remains a pure, reproducible function of the documents and the
  declared posture.
- Issue #197 resolved: a fresh-chain-head document does not hard-fail on a draft PR.

## User Stories

- As an **agent drafting a chain locally**, I want the lifecycle check to pass my
  in-flight work and tell me what still needs resolving before it is review-ready,
  so that I keep a green check and a to-do list instead of a red failure I must
  decode or silence.
- As a **draft-PR contributor**, I want CI to treat my draft as in-flight and name
  the findings still pending before ready, so that I know what stands between the
  current state and review without setting any flag myself.
- As a **ready-PR author**, I want CI to hold my work to the full bar and, if an
  in-flight finding remains, explain that reverting to draft would pass while I
  finish — and what to fix to land it review-ready — so that a failure tells me my
  options rather than just failing.
- As a **maintainer**, I want one documented place that says which lifecycle
  findings are draft-tolerable and which always block, so that I do not have to
  read each check's implementation to learn its posture behavior.

## Requirements

### Functional

- **R1.** The lifecycle check SHALL operate in one of two postures: in-flight
  ("draft") or review-ready ("ready").
- **R2.** Posture SHALL default to in-flight when no positive review-ready signal
  is asserted by the caller. A run with no posture argument behaves as in-flight.
- **R3.** The caller SHALL be able to assert review-ready posture; shirabe's CI
  SHALL assert it only when the pull request is ready-for-review (its draft flag is
  false). (The interface by which posture is asserted is a DESIGN decision; this
  requirement constrains only the behavior.)
- **R4.** Every lifecycle finding SHALL carry a posture classification: either
  "draft-tolerable" or "always-enforced."
- **R5.** In in-flight posture, draft-tolerable findings SHALL NOT fail the run
  (they surface as non-blocking, exit 0); always-enforced findings SHALL still fail
  the run (exit 2).
- **R6.** In review-ready posture, both draft-tolerable and always-enforced
  findings SHALL be enforced (any of them fails the run).
- **R7.** The classification SHALL be: **draft-tolerable** — the orphan /
  chain-connectivity finding (L02), the issue-outline acceptance-criteria finding
  (L06), and the design-location finding (L07); **always-enforced** — the
  dependency-cycle finding (L03), the missing-reference finding (L04), and the
  parse-failure finding (L05). The single-pr-posture finding (L01) remains
  posture-sensitive exactly as it is today. (Glosses, for a reader without the code
  open: L02 fires when a non-terminal doc has no chain link; L03 fires on a
  dependency cycle; L04 on an `upstream:` reference that resolves to nothing; L05 on
  a document that fails to parse; L06 on an issue outline missing acceptance
  criteria; L07 on a design whose on-disk directory disagrees with its status. L01
  today exempts a single-pr chain that is mid-PR — its PLAN still present in the
  tree — from failing while in-flight, and fails it once review-ready; that
  behavior is preserved unchanged.)
- **R8.** The CLI SHALL emit advisory output that explains the verdict in posture
  terms: an in-flight pass SHALL name the draft-tolerable findings being tolerated
  and what each needs before ready; a review-ready failure caused by a
  draft-tolerable finding SHALL state that reverting to draft would pass and name
  what to resolve to stay review-ready.
- **R9.** The advisory output MAY read ambient pull-request context — the
  pull-request signals the runner exposes to a local process, such as the event
  payload file or environment variables — to enrich its phrasing, but that context
  SHALL NOT change the verdict (exit code or machine result). Reading context to
  *explain* is permitted; reading it to *gate* is forbidden. An advisory-context
  read that fails SHALL degrade to less-specific phrasing, never to a changed or
  failed verdict.
- **R10.** The draft-tolerable-vs-always-enforced classification SHALL be
  documented in the repository in a single discoverable place.

### Non-functional

- **R11.** The verdict — the process exit code and the machine-readable
  (`shirabe-validate/v1`) JSON envelope — SHALL be a pure function of the documents
  under check and the declared posture: identical inputs yield an identical verdict
  regardless of environment.
- **R12.** The existing multi-level exit-code contract — 0 clean, 1 tool-error, 2
  violations, 3 I/O error — and the `shirabe-validate/v1` JSON envelope schema SHALL
  remain compatible with current consumers (the `/scope` and cascade pass-throughs).
  Posture handling SHALL NOT introduce a new exit code or change the meaning of an
  existing one.
- **R13.** The gate (verdict) path SHALL be hermetic: it SHALL read only local
  inputs (the documents and the declared posture) and SHALL NOT require a network
  call to produce a verdict. The advisory layer's context reads SHALL likewise be
  local (no network), consistent with R9.

## Acceptance Criteria

- [ ] A document set that triggers only draft-tolerable findings exits 0 in
  in-flight posture.
- [ ] The same document set exits 2 in review-ready posture.
- [ ] A document set that triggers an always-enforced finding (e.g. a parse failure
  or dependency cycle) exits 2 in both postures.
- [ ] Running the lifecycle check with no posture argument behaves as in-flight
  (exits 0 on a draft-tolerable-only set).
- [ ] The issue #197 reproduction — a BRIEF at Draft with no downstream artifact,
  the head of a fresh chain — exits 0 in in-flight posture.
- [ ] A single-pr chain whose PLAN is still present in the tree exits 0 in in-flight
  posture and exits 2 in review-ready posture (L01's preserved posture sensitivity).
- [ ] The `shirabe-validate/v1` JSON envelope still parses under its current schema
  version, and the exit-code contract (0/1/2/3) is unchanged after the change — a
  bad invocation still exits 1 (tool-error), and the `/scope` and cascade JSON
  pass-throughs still parse the envelope.
- [ ] An in-flight pass's advisory output names, by finding code (e.g. `L02`), each
  draft-tolerable finding it tolerated, and states for each what it needs before
  ready.
- [ ] A review-ready failure caused by a draft-tolerable finding names the finding
  code, contains the literal posture word that would make it pass (that draft
  posture would pass), and names what to fix to stay review-ready.
- [ ] Two runs over identical documents with the same declared posture produce the
  same exit code and JSON result in different environments (determinism).
- [ ] Two runs over identical documents with the same declared posture but
  *differing* ambient pull-request context produce the same exit code and JSON
  result (R9 anti-gating: context never changes the verdict).
- [ ] The finding classification is documented in a single discoverable location in
  the repo.

## Out of Scope

- The CLI interface shape and naming by which posture is asserted (flag vs argument,
  the chosen names) — a DESIGN-altitude decision.
- Changing the underlying pass/fail *logic* of any lifecycle finding (for example,
  what makes a document an orphan). Only whether and when a finding blocks is in
  scope; the detection logic is settled upstream.
- The per-file format-check (FC-family) enforcement, which is not part of the
  draft/ready posture today and is unchanged.
- Letting the validator auto-detect pull-request state to *decide* the verdict. The
  verdict stays caller-driven (R9, R11).
- Coordination with downstream or external workflow consumers beyond shirabe's own
  self-caller; the reusable workflow's only consumer today is shirabe itself.
- The handling of a malformed or unknown posture value (reject vs. fall back to
  in-flight) — a DESIGN-altitude decision about the interface's input validation.

## Decisions and Trade-offs

- **Posture is a total function defaulting to in-flight.** Absence of a positive
  review-ready signal is itself the in-flight signal, so local runs and pre-PR work
  default to in-flight with no ceremony. Alternative considered: require the caller
  to always name a posture (no default) — rejected because it breaks the local /
  pre-PR ergonomics the feature exists to fix.
- **The verdict stays a pure function; context is read only to explain.** A
  validator whose verdict depends on ambient PR state would return different
  results for the same command as a PR flips draft→ready, breaking the audit trail
  and determinism. Alternative considered: have the CLI auto-detect PR state to set
  posture — rejected on determinism grounds (and because the draft signal does not
  exist before a PR is opened, so it cannot serve the motivating local case). This
  is consistent with the prior rejection of git introspection for posture detection.
- **Classification: L02/L06/L07 draft-tolerable; L03/L04/L05 always-enforced.**
  Connectivity, outline-ACs, and design-location are normal transient states while
  drafting; cycles, missing references, and parse failures are defects regardless
  of posture. L01 keeps its existing posture sensitivity.
- **Supersession.** This requirement set revisits the accepted
  `DECISION-lifecycle-strict-mode-interface-2026-06-06`, which scoped strictness to
  single-pr-posture re-targeting only and explicitly held the orphan rule
  mode-blind. The interface mechanics of the supersession are a DESIGN decision; the
  PRD records only that the prior mode-blind treatment of L02/L06/L07 is replaced by
  the posture classification above. The fate of the existing `--strict` CI boolean
  (renamed, replaced, or kept as an alias) is a DESIGN decision; the PRD requires
  only that after the change no caller — including shirabe's own CI workflow — is
  left asserting an undefined or unhandled posture (R3, and the malformed-posture
  item in Out of Scope).

## References

- `docs/briefs/BRIEF-lifecycle-posture-mode.md` — upstream framing.
- Issue #197 — the orphan finding hard-failing on draft PRs.
- `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md` — the
  accepted interface decision this PRD revisits.
- `docs/decisions/DECISION-orphan-doc-passing-state-rule-2026-06-06.md` — the
  settled orphan pass/fail logic this PRD does not reopen.
