<!-- decision:start id="multi-pr-posture-detection" status="assumed" -->
### Decision: Multi-pr posture detection

**Context**

For multi-pr chains, the `--lifecycle` check must distinguish "in-flight" PRs (where the PLAN stays Active, BRIEF/PRD stay Accepted) from the "work-completing" PR (where the PLAN transitions Active -> Done -> DELETED and BRIEF/PRD transition Accepted -> Done in a single atomic PR). Single-pr chains are trivial — PLAN present means mid-PR, PLAN absent means at-merge. Multi-pr is the hard case because the PLAN is present in BOTH in-flight and work-completing phases until the deletion commit lands.

The validator's architecture is doc-tree-only — it reads files in the working tree and emits errors without external state. The parent PRD R17 already names "a present Done multi-pr doc is the forcing function for the deletion" as the existing rule; the new chain-aware framing in #116 generalizes that rule into a posture-detection signal. Three candidate mechanisms were evaluated: reading the PLAN's frontmatter status, parsing strikethrough completeness in the PLAN's issues table, and shelling out to git for diff context.

**Assumptions**

- The author's gesture for "this PR is the work-completing PR" is editing the PLAN frontmatter `status:` to `Done` AND deleting the PLAN file in the same PR. The validator enforces the deletion's presence by failing on present-Done. If this is wrong (e.g., the author wants a separate explicit "completion" flag), Option 1 fragments and a different signal is needed.
- The validator does not need to introspect git to detect posture. The working tree + PLAN frontmatter status field is sufficient. If this is wrong (e.g., a use case emerges where the working-tree state is ambiguous about posture), Option 3 becomes the fallback.

**Chosen: PLAN frontmatter status field**

The check reads the PLAN's frontmatter `status:` field. The mapping is:

- PLAN present, status `Active` -> in-flight posture. BRIEF/PRD passing = `Accepted`; DESIGN passing = `Current`; PLAN passing = `Active`.
- PLAN present, status `Done` -> work-completing-but-not-yet-deleted. BRIEF/PRD passing = `Done`; DESIGN passing = `Current`; PLAN passing = DELETED. The check fails in this state, forcing the author to add the deletion commit in the same PR.
- PLAN absent -> at-merge multi-pr posture. BRIEF/PRD passing = `Done`; DESIGN passing = `Current`.

The author's gesture is a single grep-able commit hunk: change `status: Active` to `status: Done` in the PLAN frontmatter, then `git rm` the PLAN, then transition BRIEF/PRD to Done — all atomically in the work-completing PR. The check runs against the resulting working tree and verifies every chain member is at its passing state.

**Rationale**

Option 1 aligns verbatim with the parent PRD R17 forcing-function language already in the corpus — the chain-aware reframing in #116 generalizes the same mechanism rather than introducing a new one. It is the only mechanism with an explicit, single-gesture author signal that captures "this is the work-completing PR." It distinguishes the "last-child-merging-but-not-yet-completing" state from the "work-completing" state, which the strikethrough mechanism cannot. And it stays within the validator's doc-tree-only architecture (the `gh.rs` precedent for FC09 notwithstanding — posture detection has a clean doc-tree signal available and does not need an external-state dependency).

Implementation is trivial: the chain-walker already reads frontmatter to follow `upstream:` edges; the posture-detection step is one additional status field read per multi-pr PLAN.

**Alternatives Considered**

- **Strikethrough completeness in PLAN's issues table** (Option 2). Reuses FC07 table-parsing machinery. Rejected because it conflates the "last child issue's PR just merged but the verify-then-delete PR is not yet opened" state with the "work-completing PR" state — both have all-strikethrough tables and a PLAN-present working tree; the check cannot distinguish them. The signal also depends on the parent PLAN being updated synchronously with child-issue closures, which is the drift FC09 emits a notice for, not a clean source of truth.

- **Git introspection** (Option 3). Most accurate ground truth — the actual deletion commit IS the work-completing signal. Rejected because it adds dependencies the validator architecture today does not assume (`git` binary, `.git/` directory, knowable upstream branch name, special handling for non-git invocations like koto context). The signal is also redundant with Option 1: Option 1 reads the state just-before the deletion commit (PLAN present at Done); git reads the state just-after (PLAN deleted). The just-before signal is sufficient for the validator's purpose (forcing the deletion to be included in the same PR).

**Consequences**

What becomes easier:
- The `--lifecycle` check stays doc-tree-only; no new external dependency on git tooling.
- The work-completing PR has a single-gesture author shape (status change + git rm + BRIEF/PRD Done transitions) that's grep-able in PR review.
- Implementation is one additional frontmatter field read per multi-pr PLAN.

What becomes harder:
- Authors must be educated that "edit the PLAN status to Done" is the gesture that marks the work-completing PR. The transition tool today has no plan state machine, so this is a manual frontmatter edit. A future extension of `shirabe transition` to cover plans would make the gesture more discoverable but is out of scope here.
- The check fails on a "PLAN at Done, still present" working-tree state. That's the intent (forcing function for deletion), but local-dev workflows that pause between the status change and the `git rm` will surface the failure intermittently. The remedy is the same as today: complete the gesture in one commit.

Accepted trade-off:
- A clever author could set PLAN status to Done in one PR (the last in-flight PR) and never produce a work-completing PR with the deletion. The check would fail on every subsequent PR's `--lifecycle` run until the deletion lands. That is the forcing function working as designed.
<!-- decision:end -->
