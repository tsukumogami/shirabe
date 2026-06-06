# Completeness Review

## Verdict: PASS

Every BRIEF problem element, journey, IN-scope item, and OUT-of-scope item is bound by a PRD requirement or restated in Out of Scope; every requirement has at least one binary acceptance criterion.

## Coverage Matrix

### BRIEF problem elements → PRD requirements

| BRIEF problem element | Requirement |
|---|---|
| Doc-claims-done forward defect (author ahead of reality) | R1 Sub-check A |
| Doc-claims-open stale defect (parallel PR closed it weeks ago) | R1 Sub-check B |
| PR body `Closes #N` disagrees with doc, both directions | R1 Sub-check C + R13 asymmetry |
| Offline-binary baseline preserved (FC01-FC08 untouched) | R6/R7/R8/R9 self-disable + R16 no new binary |
| Cross-repo PR closures (issue closes through another repo's PR) | R9 cross-repo per-row skip; issue-number-keyed reconciliation in R1/R2 |
| Check contract that crosses the offline boundary cleanly | R3 trait + R6-R9 graceful self-disable |

### BRIEF journeys (5) → addressable by requirement

| Journey | Bound by |
|---|---|
| J1 Doc author marks row done while GH still open | R1 Sub-check A (AC #1) |
| J2 Maintainer finds row still `ready` after parallel close | R1 Sub-check B (AC #2) |
| J3 PR `Closes` disagrees with doc, both directions | R1 Sub-check C + R13 (ACs #3, #4) |
| J4 Local-dev without credentials | R6 (AC #11) |
| J5 Maintainer corpus cleanup and promotion | R10 (AC #15) + R11 (AC #16) |

### BRIEF Scope Boundary IN items → bound by requirement

| BRIEF IN item | Requirement |
|---|---|
| `check_fc09` dispatched in plan + roadmap arms, three sub-checks A/B/C | R1 + R2 |
| GitHub client surface as trait, auth via `GITHUB_TOKEN`/`gh auth status` | R3 (trait) + R4 (auth) + R5 (PR-context env) |
| Four self-disable paths (credentials, PR context, rate-limit, cross-repo 403/404) | R6, R7, R8, R9 |
| Per-defect notice messages in FC05/FC06/FC07 voice | R12 |
| Notice-level shipping via `is_notice` + one-line promotion seam | R10 + R11 |
| Bounded behavior over arbitrary external input | R15 |
| Downstream sub-DESIGN handoff (meta) | Downstream Artifacts section + R3 transport-deferral note |

(Team-lead's hint of 6 IN items lines up with the six binding items; the sub-DESIGN bullet is a handoff, not a binding requirement, and is acknowledged in Downstream Artifacts.)

### BRIEF Scope Boundary OUT items → restated in PRD Out of Scope

| BRIEF OUT item | PRD Out of Scope bullet |
|---|---|
| Promotion of FC09 to error-level | Bullet 1 (matches verbatim shape, refers to R11) |
| Retrofit of the committed corpus | Bullet 2 |
| Choice between `gh` subprocess and raw HTTP | Bullet 3 |
| General GitHub-API mock framework for the workspace | Bullet 4 |
| Pipeline-stage class reconciliation against GitHub | Bullet 5 |
| Cross-repo refs the token cannot access (beyond per-row skip) | Bullet 6 |
| General PR-context plumbing layer for the validator | Bullet 7 |
| Network behavior anywhere outside FC09 | Bullet 8 |

PRD adds a ninth Out of Scope bullet (issue-tracker integration outside GitHub) that the BRIEF does not name — a defensible safety bullet, not a defect.

### Requirements → acceptance criteria (every R has at least one AC)

| Req | ACs |
|---|---|
| R1 | #1, #2, #3, #4 |
| R2 | #1, #2, #5, #6, #7 |
| R3 | #8 |
| R4 | #9 |
| R5 | #10 |
| R6 | #11 |
| R7 | #10, #12 |
| R8 | #13 |
| R9 | #14 |
| R10 | #15 |
| R11 | #16 |
| R12 | #17, #18 |
| R13 | #19 |
| R14 | #20 |
| R15 | #21, #22, #23 |
| R16 | #24 |
| R17 | #25 |

23 acceptance criteria covering 17 requirements; AC density (≈1.35 AC/R, with the heavy reqs R1/R2/R15 each carrying multiple ACs) is comparable to the FC07 sub-PRD precedent (~12 reqs / 26 ACs).

## Per-axis verdicts

- **brief-coverage: PASS** — every concrete BRIEF Problem Statement and User Outcome element is bound by a requirement (forward defect, reverse stale defect, PR `Closes` both directions, offline preservation, cross-repo PR closures, offline-boundary contract).
- **journey-addressability: PASS** — all five BRIEF journeys (J1 forward, J2 stale, J3 PR-Closes both directions, J4 offline self-disable, J5 maintainer corpus cleanup + promotion) map to at least one requirement and at least one acceptance criterion.
- **in-scope-binding: PASS** — all six binding IN items from the BRIEF Scope Boundary (check + sub-checks, client trait + auth, four self-disable paths, per-defect notice voice, `is_notice` shipping + seam, bounded behavior) are bound by R1-R17.
- **out-of-scope-acknowledged: PASS** — all eight BRIEF OUT items are restated in the PRD Out of Scope section. PRD adds one extra safe exclusion (non-GitHub trackers).
- **open-questions: N/A** — the PRD carries no Open Questions section; the BRIEF settled every framing question and the PRD defers HOW decisions (transport, exact notice strings, timeouts, fixture mechanism, module layout) cleanly to the sub-DESIGN via R3, the Out of Scope section bullet 3, and Downstream Artifacts.

## Issues Found

None at completeness altitude.

## Suggested Improvements

1. **R12 split for self-disable notice distinguishability.** R12 bundles both the per-defect notice voice and the per-self-disable-path notice-string distinguishability into one requirement. Splitting them into R12a (per-defect voice) and R12b (four self-disable notice strings distinguishable from one another) would let the AC scan target each contract independently. Not a completeness defect — AC #17 covers the voice and AC #18 covers the four distinct strings — but a structural sharpening that would help a downstream implementer who skims R12 and misses the second clause.

2. **R2's malformed-doc fallback clause.** R2 ends with "A doc whose Diagram or Table is malformed enough that FC07 emits structural notices is reconciled by FC09 only over the subset FC07 successfully extracted." This is a behavior contract but has no corresponding AC. Adding a binary AC (something like: "Given a doc where FC07 emits a malformed-diagram notice on one node, FC09 reconciles only the remaining well-formed nodes and produces no FC09 notice for the malformed one") would close the AC-per-R-clause loop. Again, not a completeness defect at the R-level — the requirement clause is present — but the AC surface for this clause is implicit.

3. **R5's `SHIRABE_PR_NUMBER` override has no AC of its own.** AC #10 covers `GITHUB_REPOSITORY` + `GITHUB_REF` plus the `SHIRABE_PR_NUMBER` override in one bullet; an explicit standalone AC for the local-invocation-with-override case would be a minor sharpening for the sub-DESIGN, but is not required for completeness.

## Summary

The PRD covers every BRIEF problem element, all five user journeys, all six binding IN-scope items, and all eight OUT-of-scope items, with 17 numbered requirements and 23 acceptance criteria. Coverage and AC density match the FC07 sub-PRD precedent. The suggestions above are structural sharpenings, not gaps — no completeness defect blocks Accepted.
