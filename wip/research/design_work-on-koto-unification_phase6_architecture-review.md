# Architecture Review: work-on-koto-unification

## Reviewer: Architect

## Scope

Review of Solution Architecture and Implementation Approach sections in
`docs/designs/DESIGN-work-on-koto-unification.md`, evaluated against the
existing shirabe codebase structure.

---

## 1. Is the architecture clear enough to implement?

**Mostly yes, with gaps.**

The three-layer decomposition (koto template / skill layer / queue script) is
well-defined and each component's responsibility boundary is explicit. The key
interfaces section provides concrete schemas for the manifest, script
subcommands, and review panel protocol. An implementer could start Phases 1-4
from this document alone.

### Gaps that would block or slow implementation

**1.1 Cross-issue context assembly is underspecified. Advisory.**

The design says the SKILL.md handles "cross-issue context assembly from koto
context keys" and mentions a `current-context.md` snapshot with "previous 2
issue summaries, cumulative files changed, key decisions." But the mechanism
for assembling this is left entirely to Phase 5 ("Cross-issue context assembly
logic" as a deliverable). The interface section describes the protocol but not
how the SKILL.md should implement the sliding window or how to bound context
size for large plans.

This is the part most likely to cause implementation churn. The queue script
and template work are mechanical; context assembly is the hard design problem.
Consider promoting this to a first-class interface definition with concrete
rules (e.g., "always include the most recent 2 summaries, include any summary
containing a decision that affects the current issue's dependencies, cap total
injected context at N tokens").

**1.2 PLAN doc parsing contract is missing. Advisory.**

The design references "PLAN doc parsing into the manifest" multiple times but
never specifies the PLAN doc format or how parsing works. The `plan/` skill's
`build-dependency-graph.sh` already handles a JSON-based dependency format
(stdin JSON array with `id`, `section`, `dependencies` fields). The design
should reference this existing script or explain why `plan-queue.sh` needs its
own dependency resolution rather than reusing `build-dependency-graph.sh`.

**1.3 Koto workflow naming convention for plan-backed issues. Advisory.**

The manifest schema shows `"koto_workflow": "work-on-issue-1"` but the
existing SKILL.md uses `issue_<N>` as the ARTIFACT_PREFIX convention. The
design should clarify whether `work-on-issue-1` is the koto workflow name
(the `<WF>` argument to `koto init`) while `issue_<N>` remains the
ARTIFACT_PREFIX variable, or whether the naming changes.

---

## 2. Are there missing components or interfaces?

### 2.1 Duplicate dependency graph logic. Blocking.

`skills/plan/scripts/build-dependency-graph.sh` already computes dependency
graphs (downstream dependents, roots, leaves) from a JSON input. The proposed
`scripts/plan-queue.sh next-issue` will need to compute the same thing:
given a set of issues with dependencies and statuses, determine which issues
are unblocked.

The design introduces a parallel pattern: two scripts in two locations that
both resolve dependency graphs. This is the "one pattern per concern"
violation. The plan skill's script is tested and handles the core graph
operations.

**Recommendation:** Either (a) have `plan-queue.sh` call
`build-dependency-graph.sh` for the graph computation and add queue-specific
logic (status tracking, auto-skip) on top, or (b) extract graph operations
into a shared script under `scripts/` that both consumers use. The design
should make this explicit.

### 2.2 Review panel orchestration interface is incomplete. Advisory.

The design describes review panel states in the koto template and says the
skill layer runs panels within the state directive. But the current SKILL.md
has no multi-agent orchestration pattern. The design doesn't specify:
- How agents are spawned (subprocesses? tool calls? agent delegation?)
- How 3 parallel agents' results are aggregated into a single JSON
- What happens if one agent times out or fails
- Where panel instructions live (the design says "shared review panel
  orchestration instructions" as a Phase 6 deliverable, but Phase 2 needs
  them to implement the states)

Phase 2 deliverables include "Updated SKILL.md phase references for panel
orchestration" which implies the instructions exist, but they're not delivered
until Phase 6. This creates a temporal dependency the phasing doesn't account
for.

### 2.3 No manifest-koto reconciliation protocol. Advisory.

The "Consequences" section acknowledges the dual-state risk (manifest tracks
issue status, koto tracks workflow state) and mentions a reconciliation check.
But the Solution Architecture section doesn't define what reconciliation
means concretely:
- What happens if the manifest says "in_progress" but koto has no workflow?
  (Workflow was deleted or never initialized.)
- What happens if koto is at `done` but the manifest says "in_progress"?
  (Script was never called after koto finished.)
- What is the source of truth? Does `plan-queue.sh status` check koto, or
  only the manifest?

These edge cases will determine resume reliability. Define the reconciliation
rules in the Solution Architecture section, not just as a mitigation.

---

## 3. Are the implementation phases correctly sequenced?

### 3.1 Phase 2 depends on Phase 6. Blocking sequencing issue.

Phase 2 adds review panel states to the template and updates SKILL.md phase
references. Phase 6 extracts shared review panel orchestration instructions.
But the review states are non-functional without panel orchestration logic --
the template can define the states, but the SKILL.md needs instructions for
what to do in those states.

Options:
- Move review panel instruction authoring into Phase 2 (write inline first)
  and make Phase 6 purely extraction/refactoring. This is the natural
  sequence: write it, then extract it.
- Alternatively, merge Phases 2 and 6 for review panels specifically.

### 3.2 Phase 3 is low-risk and could parallelize with Phase 1. Advisory.

Phase 3 (plan-backed entry path) adds states to the template. Phase 1
(gate migration) modifies existing states. These touch different parts of
the template and could be developed on parallel branches, then merged. The
linear sequencing isn't wrong but the document implies strict ordering where
it isn't required.

### 3.3 Phase 4 should explicitly depend on the PLAN doc format decision. Advisory.

Phase 4 builds `plan-queue.sh` which initializes manifests from PLAN docs.
Without a specified PLAN doc format, Phase 4 can't implement parsing. The
design should either define the format in the Solution Architecture section
or make "PLAN doc format specification" a Phase 3 deliverable (since Phase 3
already handles plan-backed mode detection for plan document paths).

---

## 4. Are there simpler alternatives we overlooked?

### 4.1 Plan-backed mode as orchestrator-only, no template changes. Considered and correctly rejected.

The design considered "Single template + skill-layer delegation" and rejected
it because per-issue workflows eliminate the multi-issue concern. This is the
right call. With per-issue workflows, the template should know about all three
modes for compile-time validation and resume.

### 4.2 Skip the queue script for the initial implementation. Worth considering.

The existing `work-on` SKILL.md already handles milestone-based issue
selection with a simple rule: "list open issues in the milestone and select
the first unblocked one." For plans with fewer than ~10 issues and simple
linear dependencies, the SKILL.md could use the same approach: parse the
manifest, find the first issue whose dependencies are all completed, execute
it.

The queue script becomes necessary when:
- Auto-skip with transitive propagation is needed
- Plans exceed ~10 issues
- Dependency graphs are complex (diamonds, multiple roots)

An incremental approach: implement plan-backed mode in Phases 1-3 and 5
with SKILL.md-only orchestration for simple plans. Add the queue script
(Phase 4) when complexity demands it. This reduces the initial surface area
and lets the team validate the koto template changes before adding the
orchestration layer.

The design's argument against "SKILL.md-embedded orchestrator" is that
"dependency graph operations in natural language are unreliable for >5
issues." This is valid for complex graphs but may be over-engineering for
the first iteration if most plans are 3-8 issues with linear chains.

### 4.3 Reuse koto's own state as the manifest. Worth considering.

The design creates a separate manifest JSON because koto doesn't track
cross-workflow state. But koto context keys persist per-workflow. The SKILL.md
could maintain a single `plan-progress.json` context key on a "meta" koto
workflow (init'd once per plan, never advanced past entry) that serves as the
manifest. This eliminates the dual-state problem entirely: there's one state
source (koto context), and the queue script reads/writes it via `koto context
get/set`.

Trade-off: it's a slight abuse of koto's context mechanism (using a
never-advancing workflow as a key-value store). But it eliminates an entire
class of reconciliation bugs.

---

## Summary of Findings

| ID | Finding | Severity | Section |
|----|---------|----------|---------|
| 2.1 | Duplicate dependency graph logic with `plan/scripts/build-dependency-graph.sh` | Blocking | Missing Components |
| 3.1 | Phase 2 (review panel states) needs panel instructions that Phase 6 delivers | Blocking (sequencing) | Phase Sequencing |
| 1.1 | Cross-issue context assembly rules are underspecified | Advisory | Clarity |
| 1.2 | PLAN doc format contract is missing | Advisory | Clarity |
| 1.3 | Koto workflow naming convention ambiguity | Advisory | Clarity |
| 2.2 | Review panel multi-agent orchestration interface incomplete | Advisory | Missing Components |
| 2.3 | Manifest-koto reconciliation rules not defined | Advisory | Missing Components |
| 3.2 | Phases 1 and 3 could parallelize | Advisory | Phase Sequencing |
| 3.3 | Phase 4 depends on undocumented PLAN format | Advisory | Phase Sequencing |
| 4.2 | Incremental approach: skip queue script initially | Alternative | Simpler Alternatives |
| 4.3 | Use koto meta-workflow as manifest store | Alternative | Simpler Alternatives |
