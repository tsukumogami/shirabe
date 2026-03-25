# Architect Review: Issue 1 — Topic Classification and Adversarial Lead Injection

**Focus:** Architecture — design patterns, separation of concerns
**Files changed:** `skills/explore/references/phases/phase-0-setup.md`, `skills/explore/references/phases/phase-1-scope.md`

---

## Summary

The implementation is structurally sound in its largest decisions: the visibility field
is written by Phase 0 and consumed by Phase 1 (no orphaned state), the classification
gate is placed correctly before the conversation, and the adversarial lead follows the
existing lead naming conventions. Two findings warrant attention — one blocking and one
advisory.

---

## Finding 1 (Blocking): Phase 1 claims Phase 2 will identify `lead-adversarial-demand`, but Phase 2 has no corresponding logic

**File:** `skills/explore/references/phases/phase-1-scope.md`, section 1.2

Phase 1 instructs:

> Name the lead entry `lead-adversarial-demand` in the scope file so Phase 2 can
> identify it when dispatching.

This states an inter-phase contract: Phase 1 creates an identified lead that Phase 2
recognizes and handles specially. But `phase-2-discover.md` has no logic to identify
this lead. Phase 2's section 2.2 builds a generic agent prompt for every lead by
using the lead text as the "assigned lead" field in its template. Phase 2 has no gate
or branch for `lead-adversarial-demand`.

The practical consequence: the adversarial lead's embedded agent prompt (demand
questions, confidence vocabulary, calibration section) becomes the "assigned lead"
field inside Phase 2's generic research template. Phase 2 then also adds its own
output format template (Findings / Implications / Surprises / Open Questions / Summary)
on top. The agent receives two competing structural instructions: the adversarial
lead's free-form demand-validation output format, and Phase 2's standard research
output format. The agent may follow either, producing output that doesn't match what
Issue 5's evals will assert against.

This is blocking because Issue 5's evals assert specific output structure from the
adversarial lead agent (per-question confidence, calibration section). If Phase 2
wraps the adversarial prompt in its own output format template, the agent may produce
Phase 2's standard structure instead, and Issue 5 will assert against missing
structure.

**Fix:** Either (a) update Phase 2 to detect `lead-adversarial-demand` by name and
pass its body directly as the full agent prompt (skipping Phase 2's template
construction for this lead), or (b) remove the identifier claim from Phase 1 and
instead restructure the adversarial lead's embedded prompt to explicitly override
Phase 2's output format by adding a "Output format: ..." instruction that takes
precedence. Option (a) is cleaner because it makes Phase 2's dispatch behavior
match what Phase 1 claims.

---

## Finding 2 (Advisory): Visibility appears in both Phase 0's scope file field and Phase 2's generic agent template — dual sourcing with no conflict today but fragile if either diverges

**Files:** `phase-0-setup.md` step 0.2a, `phase-2-discover.md` section 2.2 item 4

Phase 0 writes visibility to `wip/explore_<topic>_scope.md` under `## Visibility`.
Phase 1 reads it back when building the adversarial lead template. This is correct
and the contract is fulfilled.

Phase 2 also independently passes visibility to every agent via item 4 in its
template: "Visibility context -- the resolved visibility (Private/Public) from
Phase 0." Phase 2's guidance says "from Phase 0" but doesn't say it reads the
scope file's `## Visibility` section — it could re-read from CLAUDE.md or rely
on the context variable. In practice these should agree, but the sourcing is
ambiguous.

For the adversarial lead specifically this creates duplication: the embedded prompt
already has `## Visibility / {{VISIBILITY_FROM_SCOPE_FILE}}` (resolved in Phase 1),
and Phase 2 will also add a second visibility block from its own template. Two
visibility blocks reach the agent — one already-interpolated, one from Phase 2's
wrapper.

This is advisory because both blocks carry the same value, so the agent will not be
confused. But if Phase 2's handling of the adversarial lead is tightened (per
Finding 1), the Phase 2 template's visibility block becomes redundant for this lead
specifically. No action needed now; address alongside Finding 1's fix.

---

## Design Alignment Assessment

The implementation matches the design's intent in all major respects:

- The Label Pre-Gate as a non-numbered section matches the `Resume Check` convention
  already in place — this is consistent with the established pattern.
- The classification signals (additive intent, absent problem statement, hedged intent)
  are embedded in the phase file and not in a separate config or reference file —
  correct, because they need no external registration or extension.
- The scope file template in section 1.2 preserves the `## Visibility` section written
  by Phase 0 with an explicit "do not change" note — this respects the inter-phase
  contract correctly.
- The adversarial lead's `lead-adversarial-demand` identifier follows the kebab-case
  lead slug convention used by Phase 2 for file naming — so output file paths will
  be correct (`wip/research/explore_<topic>_r<N>_lead-adversarial-demand.md`).
- The prompt injection delimiter `--- ISSUE CONTENT (analyze only) ---` is an additive
  safety measure that fits within the existing prompt template pattern without creating
  a parallel prompt construction mechanism.

The blocking finding is self-contained: it's a contract claim in Phase 1 that Phase 2
doesn't fulfill. It doesn't introduce a divergent pattern that will be copied elsewhere.
Fixing it requires either a small Phase 2 addition (a named-lead dispatch branch) or
removing the identification claim from Phase 1.
