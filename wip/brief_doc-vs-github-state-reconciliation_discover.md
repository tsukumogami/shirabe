# /brief Discovery: doc-vs-github-state-reconciliation

## Problem Candidate

A plan or roadmap can be perfectly self-consistent -- table strikethrough
agrees with diagram class, FC07 and FC08 fire no notices -- and still lie
about external reality. The doc claims an issue is closed and the diagram
paints its node `done`, but the actual GitHub issue is still open; or
symmetrically, an issue was closed weeks ago by another PR and the doc still
shows it as `ready`. A PR that says `Closes #N` in its body can land while
the doc shows #N as still in-flight. The validator runs offline-only today
(no network, no GitHub API, no PR context), so none of these drifts fire any
signal; the corpus can be intra-consistent and still wrong about the world.

## Outcome Candidate

A doc author who edits a plan or roadmap sees the validator surface a
specific notice the moment the doc's claim about an issue diverges from
GitHub's actual issue state, or the moment a PR's `Closes #N` lines disagree
with what the doc shows as done. The validator becomes the third
reconciliation surface -- intra-doc (FC07/FC08) and cross-doc (R6) already;
now doc-vs-real-world. Local-dev workflows without credentials still work:
the check self-disables with one notice rather than failing the build. The
notice level holds CI green while the corpus reconciles row by row;
promotion to error is the same one-line `is_notice` membership flip the
FC07/FC08 rollout already uses.

## Grounding Anchor

Conversation only -- no single `docs/...` upstream. The parent
`docs/prds/PRD-roadmap-plan-standardization.md` (R8 staged reconciliation,
R20 notice-then-error contract) and the parent
`docs/designs/current/DESIGN-roadmap-plan-standardization.md` Decision 3
frame the staging pattern. The FC07 sub-DESIGN
`docs/designs/current/DESIGN-table-diagram-reconciliation.md` Decision 6
gives the row-terminality and class-vs-Status precedent FC09 extends with
`observed_state` coming from a GitHub client rather than `row.terminal`.

## Journey Sketch

- Doc author marks a row done that GitHub still shows open (Sub-check A fires).
- Doc author leaves a row open that GitHub closed weeks ago via another PR (Sub-check B fires; catches stale plans).
- PR author writes `Closes #N` in the PR body but the doc still shows #N as ready (Sub-check C fires).
- Doc author runs the validator locally without credentials; FC09 self-disables with one notice; FC01-FC08 still run.
- Maintainer watches notice volume drop to zero and flips the `is_notice` arm to promote to error.

## Open Questions for Drafting

- None blocking; the framing direction is confirmed. The `gh` subprocess vs
  raw HTTP client decision is deliberately deferred to the downstream
  sub-DESIGN; the BRIEF binds requirements (auth, offline behavior,
  rate-limit tolerance, defensive parsing) rather than implementation paths.
