---
schema: brief/v1
status: Draft
problem: |
  shirabe validate answers "does this block the build?" the same way whether
  the work is an early local draft or a finished PR awaiting review. Findings
  that are normal mid-draft hard-fail, the only control is a --strict boolean
  the CI shell sets from the PR's draft state, and the result never explains
  whether a finding is a real blocker or just "not ready yet."
outcome: |
  An author or agent running shirabe validate — locally, on a draft PR, or on
  a ready PR — gets a result that matches where the work is: in-flight work
  passes with advisory guidance about what must become true before it is
  review-ready, only review-ready work is held to the full bar, and the result
  explains itself in terms of posture.
motivating_context: |
  A prior exploration of the lifecycle strict/draft discipline found that the
  L02 orphan check hard-fails on draft PRs (issue #197), and that this is one
  instance of a broader gap: enforcement posture is a single boolean threaded
  from CI, opaque to a local author, and absent from the result's explanation.
---

## Status

Draft

This BRIEF frames the feature at problem/outcome altitude. Solution mechanics —
the CLI interface shape, whether the advisory layer reads PR context from the
environment, and the exact set of lifecycle findings classified as
draft-tolerable — are deferred to the downstream PRD and DESIGN.

## Problem Statement

`shirabe validate` runs in several contexts: an agent drafting an artifact chain
locally before any pull request exists, a draft PR in CI, a ready-for-review PR in
CI, and ad-hoc manual runs. In every one of them, the validator's lifecycle
checking answers the same question — "does this finding block the build?" — with
the same verdict, regardless of where the work actually sits in its lifecycle.

That uniformity is the problem. Work that is legitimately in flight produces
findings that are normal and expected at that stage: a document not yet linked
into its chain, an outline that does not yet carry acceptance criteria, a design
not yet promoted to its final location. On in-flight work these are progress
markers, not defects — but the validator treats them as hard failures and exits
non-zero, so a healthy draft gets a red build (the concrete instance reported in
issue #197).

The only control over this is a single `--strict` boolean that the CI workflow
sets from the pull request's draft state. Three things follow from that shape.
First, an author or agent running the validator by hand has no pull request to
read draft state from, and no way to know which posture is appropriate — the
control assumes a context that local runs do not have. Second, the control names
an *enforcement level* ("strict"), not the author's *intent* ("I am still
drafting" vs "this is ready for review"), so using it correctly requires
reverse-engineering the enforcement model from the draft/ready distinction the
author already understands. Third, when a finding does fire, the result is a bare
pass/fail with no explanation of whether the finding is a genuine blocker or
simply "not ready yet," and no guidance on what would make the check pass. The
author is left to guess.

## User Outcome

An author or agent running `shirabe validate` gets a verdict that matches where
the work actually is in its lifecycle, in whatever context they run it.

When the work is in flight — a local draft with no PR, or a draft PR — the
validator passes it, and tells the author which findings are tolerated for now but
will need to be resolved before the work is review-ready, and what resolving them
looks like. When the work is review-ready, the validator holds it to the full bar.
The author no longer has to translate "I'm still drafting" into an enforcement
flag, no longer gets a red build for being mid-stream, and no longer reads a bare
exit code with no idea what it means: the result explains why it landed where it
did in terms of the work's posture, and what changing that posture would do. The
distinction the author already reasons about — draft versus ready — is the one the
tool speaks back to them.

## User Journeys

### Local-drafting agent (no PR yet)

An agent authoring an artifact chain on disk runs `shirabe validate` before any
pull request exists, to check its work as it goes. The validator treats the work
as in-flight (there is no positive signal that it is review-ready) and passes it,
noting that a few findings are tolerated now but will block once the work is marked
ready, and what each one needs. The agent keeps drafting with a green check and a
to-do list, instead of a red failure it has to decode or silence.

### Draft-PR contributor

A contributor opens a pull request as a draft and pushes commits. CI runs the
lifecycle check, which treats the draft PR as in-flight and passes it. The check's
output names the findings still pending before the PR can be marked ready, so the
contributor knows exactly what stands between the current state and review without
having had to set any flag themselves.

### Ready-PR author

An author marks the pull request ready for review. CI now holds the work to the
full bar. If an in-flight finding still remains, the failure explains that the
finding is one tolerated only while drafting — that flipping the PR back to draft
would let the check pass while the author finishes the chain — and lists what to
resolve to land it review-ready instead. The author gets a failure that tells them
both escape hatches rather than a bare exit code.

### Maintainer auditing the contract

A maintainer reviewing how the validator behaves wants to know which lifecycle
findings are tolerated while drafting and which always block. They find a single
documented classification that answers it, rather than having to read each check's
implementation to discover its posture behavior case by case.

## Scope Boundary

### In

- A posture concept for `shirabe validate`'s lifecycle checking: in-flight (draft)
  versus review-ready (ready), defaulting to in-flight when no positive
  review-ready signal is present.
- A classification of which lifecycle findings are tolerated while the work is
  in flight versus which always block, so the verdict can depend on posture.
- Context-aware, advisory output that explains why a verdict holds and what
  changing posture would do, without itself deciding the pass/fail outcome.
- Resolving issue #197: an in-flight document no longer hard-fails the build on a
  draft PR.

### Out

- The CLI interface shape that expresses posture (a flag, an argument, its naming)
  — that is a DESIGN-altitude decision.
- Changing what counts as a lifecycle finding — the underlying pass/fail *logic*
  of each check (for example, what makes a document an orphan) is settled and is
  not reopened here; only whether and when a finding blocks is in scope.
- The per-file format-check (FC-family) enforcement, which is not part of the
  draft/ready posture today and stays as it is.
- Letting the validator auto-detect pull-request state in order to *decide* the
  verdict: the verdict stays driven by the caller-asserted posture. Reading
  context to *explain* a verdict is in scope; reading it to *gate* is out.
- Coordination with downstream or external consumers beyond shirabe's own
  self-caller workflow.

## References

- Issue #197 — the orphan finding hard-failing on draft PRs (the motivating instance).
- `docs/briefs/BRIEF-lifecycle-draft-ready-discipline.md` — the prior brief that
  introduced the draft/ready posture for the single-pr chain exemption.
- `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md` — the
  accepted interface decision this feature revisits.
