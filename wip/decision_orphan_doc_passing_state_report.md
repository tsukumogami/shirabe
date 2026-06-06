<!-- decision:start id="orphan-doc-passing-state-rule" status="assumed" -->
### Decision: Orphan-doc passing-state rule

**Context**

The chain-aware `shirabe validate --lifecycle <root>` mode walks every PLAN and ROADMAP in the doc tree, inverts each doc's `upstream:` edge to reach the upstream BRIEF/PRD/DESIGN, computes the chain's posture (single-pr vs multi-pr; mid-flight vs work-completing), and verifies each chain member is at its passing state — the frontmatter status correct for this PR to merge with green CI. The model has a hole for docs that have no downstream PLAN/ROADMAP pointing at them. A literal orphan-strict rule (any orphan fails) fails 28+ docs in the current corpus — every DESIGN at `Current` in `docs/designs/current/` is orphan by that definition because the PLAN that drove its work was deleted post-completion, plus two PRDs orphan at non-terminal status because they participate in ROADMAP-rooted multi-pr chains where the downstream lag is normal. A literal orphan-permissive rule (any orphan passes) lets the "framing started but never specified" drift sit silently, which contradicts the issue's premise that the chain-aware check is supposed to catch the same flavor of drift the FC08/FC09 reconciliation exposed.

The choice is between three options: orphan-permissive (skip orphans entirely), orphan-strict-naive (fail every orphan, requires mass corpus migration), and a terminal-aware refinement that tolerates orphans at their target state and fails orphans at non-terminal states with a ROADMAP-rooted exception.

**Assumptions**

- The lifecycle terminal states per artifact type are: BRIEF Done, PRD Done, DESIGN Current (a DESIGN is at terminal state when it lives in `docs/designs/current/`). If this is wrong, the rule needs an explicit per-type target-state map encoded somewhere shared.
- ROADMAP-rooted chains have a normal transient window where downstream PRDs exist at Accepted without their own downstream DESIGN/PLAN, because the ROADMAP is the chain root and per-feature decomposition lags. If this is wrong, the ROADMAP-root exception drops out and the corpus's two non-terminal PRD orphans become genuine violations to address before the check ships.
- The DESIGN-doc lifecycle distinguishes `Planned` (in `docs/designs/`) from `Current` (in `docs/designs/current/`) as the in-flight vs terminal states. If this is wrong, the rule's terminal definition for DESIGNs needs a different signal (frontmatter flag, separate field).

**Chosen: Terminal-aware orphan rule**

An orphan BRIEF, PRD, or DESIGN — a doc with no downstream `upstream:` reference from any other doc — has its passing state defined by its target state:

- If the orphan's current status equals its target state (BRIEF Done, PRD Done, DESIGN Current), the orphan passes. This is the post-completion healthy case: the single-pr chain shipped, the PLAN was deleted, the framing artifact survives at its terminal state.
- If the orphan's current status is non-terminal AND its own `upstream:` points at an Active ROADMAP, the orphan passes. This is the in-flight ROADMAP-rooted PRD case: the ROADMAP is the chain root, the per-PRD downstream lag is allowed.
- Otherwise the orphan fails: a BRIEF stuck at Accepted with no downstream PRD anywhere, a PRD stuck at Accepted with no downstream DESIGN anywhere, a DESIGN stuck at Planned with no downstream PLAN anywhere — these are the "framing started but never specified" drift cases the check is meant to catch.

The check encodes the rule in the chain-walker: when visiting a doc with no inbound `upstream:` reference, compare its current status against its target state and the ROADMAP-rooted exception; emit an `Lnn` error naming the file, its current state, and the expected passing state.

**Rationale**

The terminal-aware rule is the synthesis of the two named candidates and the only one that fits the corpus and the philosophy. Orphan-strict-naive is provably unworkable on day one (28+ failures), and orphan-permissive silently undermines the chain-aware passing-state model's stated reason for existing. Terminal-aware orphan rule:

- Lets the existing corpus pass on day one without mass migration (all 26 DESIGNs at Current pass; the 2 PRD orphans pass via the ROADMAP-root exception or their own terminal status).
- Encodes the same forcing function as "stale Draft PLAN is drift," applied one altitude up: an orphan at non-terminal status forces the author to either drive the chain forward or delete the framing artifact.
- Remains explainable in a single BRIEF CUJ paragraph — readers see the FC09 worked example and the inverted "BRIEF stuck at Accepted with no PRD" example, and immediately grasp the rule.
- Implementation cost is modest: the chain-walker already has to know each artifact type's target state (it uses it for the non-orphan passing-state computation); the ROADMAP-root exception adds one branch.

The accepted trade-off: ROADMAP-rooted chains get a permanent exception, so a PRD-at-Accepted whose upstream ROADMAP becomes stale (the ROADMAP ages out without ever transitioning to Done) creates a second drift case the check does not catch. That second case is a ROADMAP-level lifecycle question, not an orphan-rule question, and is left to future work.

**Alternatives Considered**

- **Orphan-permissive**. Skip orphans entirely; the check only validates docs that participate in a chain rooted at a present PLAN or ROADMAP. Rejected because the FC08/FC09 drift surfacing motivation extends one altitude up — an Accepted BRIEF with no downstream PRD is exactly the silent drift the chain-aware passing-state model exists to catch, and orphan-permissive lets that drift sit indefinitely.

- **Orphan-strict (naive)**. Fail every orphan regardless of status. Rejected because the current corpus has 28+ healthy orphans (26 DESIGN-at-Current docs whose PLANs were deleted post-completion, plus PRD-koto-adoption and PRD-roadmap-plan-standardization which participate in ROADMAP-rooted chains). Shipping this rule would require a corpus mass-migration that exceeds this whole feature's scope, with no clear migration target for the legitimately-completed framing docs.

**Consequences**

What becomes easier:
- Catching the "framing started but never specified" drift case as a CI signal, parallel to "stale Draft is drift."
- Explaining the chain-aware check's behavior in a single BRIEF CUJ paragraph.
- Shipping `--lifecycle` against the current corpus without a parallel migration PR.

What becomes harder:
- The chain-walker has to carry an artifact-type-keyed target-state map and a ROADMAP-root exception branch. Modest, but two more concepts to keep tested.
- A future change to any artifact type's terminal state (e.g., renaming DESIGN's `Current` to something else) requires updating the orphan rule's target-state map alongside.
- The ROADMAP-root exception creates a small loophole: an orphan PRD whose upstream ROADMAP ages out without ever reaching Done sits silently. Addressed by a future ROADMAP-lifecycle check, not by this rule.
<!-- decision:end -->
