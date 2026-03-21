# Decision Point Manifest

Pre-classified tier assignments for all known decision points across shirabe
workflow skills. The agent reads this manifest at the start of execution to
know the tier for each decision point without runtime classification.

For emergent decisions (not listed here), use the three-signal checklist in
`decision-protocol.md`.

## explore (11 points)

| ID | Phase File | Category | Tier | Interactive | --auto |
|----|-----------|----------|------|-------------|--------|
| E1 | SKILL.md:78 | researchable | 1 | Ask topic | Infer from branch/issues; error if no signal |
| E2 | phase-0-setup.md:110 | judgment | 2 | Present jury result | Follow jury majority; document |
| E3 | phase-0-setup.md:184 | judgment | 2 | Confirm triage type | Follow jury recommendation; document |
| E4 | phase-1-scope.md:64 | approval | 2 | Checkpoint: confirm understanding | Log understanding; proceed |
| E5 | phase-3-converge.md:66 | judgment | 2 | Narrowing question | Auto-answer by signal strength; document |
| E6 | phase-3-converge.md:91 | judgment | 2 | Capture scope decisions | Infer from evidence; document |
| E7 | SKILL.md:202 | judgment | 2 | Explore further vs crystallize | Apply gap heuristic; document |
| E8 | phase-4-crystallize.md:118 | judgment | 2 | Artifact type selection | Accept top score; document |
| E9 | phase-5-produce-deferred.md:23 | judgment | 2 | Prototype unsupported fallback | Follow heuristic; document |
| E10 | phase-5-produce-deferred.md:249 | judgment | 2 | Competitive analysis in public repo | Default to design doc; document |
| E11 | phase-5-produce-no-artifact.md:21 | researchable | 1 | Present findings | Log findings; no blocking |

## design (10 points)

| ID | Phase File | Category | Tier | Interactive | --auto |
|----|-----------|----------|------|-------------|--------|
| D1 | SKILL.md:131 | researchable | 1 | Ask topic | Infer from context; error if no signal |
| D2 | phase-0-setup-freeform.md:44 | researchable | 1 | Scoping conversation | Derive from issue/docs/codebase; log |
| D3 | phase-2-present-approaches.md:57 | judgment | 3 | Approach selection | Accept recommendation; document |
| D4 | phase-2-present-approaches.md:66 | researchable | 2 | "None of these" loop-back | Add research round if confidence low |
| D5 | phase-3-deep-investigation.md:91 | judgment | 2 | Deal-breaker handling | Follow heuristic; document risk |
| D6 | phase-3-deep-investigation.md:103 | judgment | 2 | Mid-investigation choice | Pick by evidence; document |
| D7 | phase-3-deep-investigation.md:132 | approval | 2 | Decision review checkpoint | Auto-record; mark agent-inferred |
| D8 | phase-4-architecture.md:89 | approval | 2 | Implicit decision review | Auto-record; mark agent-inferred |
| D9 | phase-6-final-review.md:138 | approval | 2 | Final approval | Auto-approve if validation passes; document |
| D10 | SKILL.md:196 | judgment | 2 | Post-completion routing | Follow complexity assessment; document |

## prd (8 points)

| ID | Phase File | Category | Tier | Interactive | --auto |
|----|-----------|----------|------|-------------|--------|
| P1 | SKILL.md:58 | researchable | 1 | Ask topic | Infer; error if no signal |
| P2 | SKILL.md:111 | researchable | 1 | Ask about branch | Check branch name; create if ambiguous |
| P3 | phase-1-scope.md:61 | approval | 2 | Scope checkpoint | Log; proceed unless contradictions |
| P4 | phase-2-discover.md:142 | judgment | 2 | Loop-back decision | Follow coverage heuristic; document |
| P5 | phase-3-draft.md:68 | judgment | 2 | Open questions / trade-offs | Resolve by evidence; document |
| P6 | phase-3-draft.md:99 | approval | 2 | Post-draft feedback | Skip to jury review; document |
| P7 | phase-4-validate.md:169 | judgment | 2 | Jury issue resolution | Apply jury recommendations; document |
| P8 | phase-4-validate.md:190 | approval | 2 | Final approval | Auto-approve if jury passes; document |

## plan (6 points)

| ID | Phase File | Category | Tier | Interactive | --auto |
|----|-----------|----------|------|-------------|--------|
| PL1 | SKILL.md:121 | researchable | 1 | Ask what to plan | Infer; error if no signal |
| PL2 | phase-1-analysis.md:95 | researchable | 1 | Ambiguous needs_label | Apply heuristic; document |
| PL3 | phase-3-decomposition.md:76 | judgment | 2 | Decomposition strategy | Apply coupling heuristic; document |
| PL4 | phase-3-decomposition.md:355 | judgment | 2 | Execution mode | Follow signal-strength heuristic; document |
| PL5 | phase-6-review.md:68 | approval | 2 | Pre-creation sign-off | Proceed if checks pass; document |
| PL6 | phase-7-creation.md:318 | researchable | 1 | Upstream issue check | Check frontmatter/body; auto-update or skip |

## work-on (4 points)

| ID | Phase File | Category | Tier | Interactive | --auto |
|----|-----------|----------|------|-------------|--------|
| W1 | SKILL.md:23 | judgment | 2 | needs-triage handling | Default to proceed; document |
| W2 | phase-2-introspection.md:78 | researchable | 1 | Clarify ambiguity | Resolve from context; document |
| W3 | phase-6-pr.md:65 | safety | -- | CI failure guidance | HALT (never auto-proceed) |
| W4 | phase-6-pr.md:69 | safety | -- | Red check acceptance | HALT (never auto-accept) |

## Summary

| Category | Count | --auto behavior |
|----------|-------|----------------|
| Researchable | 11 | Agent finds the answer; Tier 1 (no record) or confirmed |
| Judgment | 19 | Agent follows heuristic; Tier 2-3 with decision block |
| Approval | 7 | Agent auto-approves if validation passes; assumed status |
| Safety | 2 | HALT in both modes (CI failures only) |
| **Total** | **39** | |
