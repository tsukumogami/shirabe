# /brief Discovery: lifecycle-posture-mode

## Problem Candidate
`shirabe validate`'s lifecycle checking answers "does this block the build?" the
same way regardless of where the work actually is — an early local draft or a
finished PR awaiting review. Findings that are normal mid-draft hard-fail (exit 2),
the only control is a `--strict` boolean the CI shell sets from the PR's draft
state, a person/agent running the CLI by hand has no PR state to read and no
intuition for which posture to assert, and the result never explains whether a
finding is a real blocker or just "not ready yet." The result: red builds on
healthy drafts (issue #197), authors forced to reason about an enforcement knob
instead of their own intent, and no guidance on how to make the check pass.

## Outcome Candidate
An author or agent running `shirabe validate` — locally with no PR, on a draft PR,
or on a ready PR — gets a result that matches where the work is: in-flight work
passes with advisory guidance about what must still become true before it's
review-ready, and only review-ready work is held to the full bar. The result
explains itself in terms of posture and names what changing posture would do, so
the author never reverse-engineers an enforcement flag from the draft/ready
distinction they already understand.

## Grounding Anchor
conversation only (prior /explore of the lifecycle strict/draft discipline; issue #197)

## Journey Sketch
- Local-drafting agent runs validate before any PR exists; gets PASS + "tolerated now, blocks at ready" note.
- Draft-PR contributor: CI passes, output names findings pending before ready.
- Ready-PR author: full bar enforced; a remaining in-flight finding explains the draft escape hatch + what to fix.
- Maintainer auditing the contract finds one documented draft-tolerable-vs-always-enforced classification.

## Open Questions for Drafting
- Keep solution mechanics (interface shape, advisory read-source, exact finding classification) out of the BRIEF; they are PRD/DESIGN altitude.
