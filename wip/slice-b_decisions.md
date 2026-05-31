# Slice B Decisions

Record of decisions taken while implementing #114 (surface the
single-pr/multi-pr decision and add the value-confirmation guard).
Format mirrors Slice A so the two slices read consistently.

<!-- decision:start id="value-guard-placement" status="confirmed" -->
### Decision: Value-confirmation guard runs after decomposition and before execution-mode finalization

**Question:** Where in the workflow does the value-confirmation guard fire?

**Choice:** As a new step `3.5a Value Confirmation`, between
decomposition (step 3.5 / 3.R4) and execution-mode selection (step 3.6).

**Evidence:** Design Decision 6 names the placement: "a separate
value-confirmation step that records-and-proceeds." The decomposition
artifact already exists at this point (issue outlines + features), and
the execution-mode decision in 3.6 needs the guard's output: a roadmap
input always reaches multi-pr because every feature passed, and a plan
input justifies multi-pr only when each PR-shaped unit passed.

**Alternatives considered:** Inline inside step 3.6 (rejected -- mixes
the value question into the mode decision the issue explicitly asks us
to de-conflate). Phase 6 review (rejected -- too late; by then the
decomposition is fixed and re-scoping a unit means redoing Phases 3-5).

**Consequences:** The guard sits one step before mode finalization, so
its findings feed the mode call cleanly. The guard is named separately
from both the work-slicing decision and the mode decision.
<!-- decision:end -->

<!-- decision:start id="surfaced-rule-anchor" status="confirmed" -->
### Decision: Surface the rule on SKILL.md as an always-loaded section anchored on workflow-principles.md P1

**Question:** Where does the lifted single-pr/multi-pr rule live, and
what does it cite?

**Choice:** A new top-level section `## Execution Mode Decision
(single-pr vs multi-pr)` on `skills/plan/SKILL.md`, placed after the
existing Decomposition Strategies section so the two are visibly
separate. The section cites
`${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md` (P1 -- usable
value is the unit of work) explicitly.

**Evidence:** PRD R10 says "lifts the single-pr/multi-pr decision to the
skill surface (out of the lazily loaded reference), anchors it on the
usable-value principle (R1.1), and separates it from the work-slicing
decision it is tangled with today." Design Decision 6 chose "the plan
SKILL.md is the right always-loaded surface" with the assumption
recorded. The principle file already ships with the canonical wording.

**Alternatives considered:** Keep in the phase file with a SKILL pointer
(rejected by the design as "a pointer is not surfacing"). Embed inside
the existing Decomposition Strategies section (rejected -- exactly the
conflation R10 says to remove).

**Consequences:** Authors see the rule the moment the skill loads, with
the principle citation one click away. The phase file shrinks to a thin
pointer for its surfaced part.
<!-- decision:end -->

<!-- decision:start id="auto-guard-status-mapping" status="confirmed" -->
### Decision: --auto guard records `confirmed` on a clear pass and `assumed` at high review priority on any other outcome

**Question:** Which decision-protocol status does the guard write under
`--auto` on each of its three outcomes (pass / ambiguous / fail)?

**Choice:** Pass -> `confirmed`. Ambiguous -> `assumed` at high review
priority. Fail -> `assumed` at high review priority. Both non-pass
outcomes route to the same recorded outcome on purpose.

**Evidence:** PRD R12 names this explicitly: "A unit that fails the
value test (R11 -- not a standalone increment) or that the guard cannot
clearly classify either way (an ambiguous unit) is recorded with
`status='assumed'` and `high` review priority [...] Failing and
ambiguous units route to the same recorded outcome on purpose: both are
units the author must review, neither is waved through." The
decision-block format defines `high` review priority as surfacing in the
terminal summary and PR body, which is the visibility R12 requires.

**Alternatives considered:** Separate `status` per outcome (rejected --
the PRD's deliberate same-bucket framing is the visibility model). Hard
fail under `--auto` (rejected by the PRD's Decision 5 as breaking
`--auto`'s non-interactive contract).

**Consequences:** One `--auto` shape for the guard, symmetric with the
issue-creation approval gate's record-and-proceed in #115.
<!-- decision:end -->
