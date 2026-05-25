<!-- decision:start id="d8-pattern-doc-edit-surface" status="confirmed" -->
### Decision: Pattern-Doc Edit Surface for Mandatory-with-Auto-Skip and State-Schema Extensions

**Context**

SE7 ships `/scope` as the second parent skill and is required (PRD Decision 1, R10, R11) to land four concrete pattern-level edits inside the existing reference surface that `/charter` ratified:

1. A fourth gate type, **Mandatory-with-auto-skip**, added to the pattern's gate vocabulary (PRD Decision 6 + R5; canonical consumer is `/prd`'s gate).
2. Two new conditional state-file fields — `boundary:` (gated by `exit: re-evaluation`) and `plan_execution_mode: single-pr | multi-pr` (gated by `chain_ran` containing `/plan`) — landed into the schema's extension discipline (PRD R10 + R7).
3. R9 hard-finalization-check additions covering the new conditional fields (PRD R9).
4. Two refuse-and-redirect meta-ladder rows for **PLAN-Active → `/work-on`** and **PLAN-Done → `/release`** (PRD R11, Decision 9).

The four pattern reference files differ in which level of edit they need. The pattern-inheritance-audit lead recommended *verbatim* inheritance for all four references (no reference edits at all, on the theory that body slots, the extension discipline, and the per-parent surface table absorb every `/scope`-specific need). The PRD then overrode that recommendation explicitly for the gate vocabulary (Decision 1 + Decision 6) and implicitly for the meta-ladder (PRD's R11 names PLAN-Active/Done as resume-ladder rows, but does not say whether they sit in the universal meta-ladder or in `/scope`'s body slot 5). The audit's "verbatim" call stands for the child-inspection reference (all four tactical-chain children are doc-emitting and slot into the existing row); the audit's call needs softening on the other three references.

The decision below names the concrete section/line-range for every edit, the wording, and the universal-vs-parent-specific classification for each meta-ladder row.

**Assumptions**

- The four pattern reference files keep their two-layer-contract framing. `boundary:` and `plan_execution_mode:` are parent-specific Layer-2 fields per the existing extension discipline; they extend the schema without re-doing Layer 1.
- `/charter` will get a follow-up back-edit PR (already named in PRD Downstream Artifacts) to cite the new universal meta-ladder rows or to confirm its existing SKILL.md body slot 5 already covers them — this decision does not require touching `/charter`'s SKILL.md from inside SE7.
- The fourth gate type is genuinely pattern-level (Decision 6 explicitly: "Mandatory-with-auto-skip captures `/prd`'s actual semantics; the EITHER-signal unification would mislead future parent-skill authors who consult the pattern doc"). If wrong, the edit can be reverted by collapsing the fourth gate back into EITHER-signal language; the edit shape stays additive.
- The PLAN-Active/Done refuse-and-redirect behavior is universal to any chain whose terminal artifact has an "in-implementation" or "completed" lifecycle state owned by a downstream skill — not `/scope`-specific. `/charter`'s terminal STRATEGY is Accepted-terminal and has no analog (there is no implementation skill that owns "Active STRATEGY"), so for `/charter` the universal rows are vacuous; for `/scope` they are load-bearing. The universal-vs-parent-specific call below treats them as universal-with-vacuous-binding-when-no-downstream-skill-exists.

**Chosen: Surgical reference edits with one universal-meta-ladder addition, three new state-schema fields, two new pattern-doc sections, zero child-inspection edits**

The edit surface across the four pattern reference files:

#### A. `references/parent-skill-pattern.md`

**A.1. Fourth gate type — Mandatory-with-auto-skip — placement.**

**Edit location:** A new top-level section titled **"Gate Vocabulary"** inserted between the existing "Three Exit Paths" section (lines 78-111) and the existing "Conditional Feeder Invocation Shape" section (lines 113-148). Today the pattern doc has no consolidated gate vocabulary surface — the three existing gate shapes (EITHER-signal, ALWAYS, shape-dependent) appear only in `/charter`'s phase-2 doc, not in the pattern reference. Adding a Gate Vocabulary section is the cleanest way to canonicalize all four gates at the pattern level, makes the fourth gate type discoverable to future parent-skill authors (Decision 6's stated motivation), and gives `/charter`'s back-edit a clean target to cite.

**Why NOT inside the existing Conditional Feeder Invocation Shape section:** the feeder shape is a *specific* three-condition gate (signal + skill-exists + visibility). Mandatory-with-auto-skip is a different category of gate — main-chain, not feeder — that doesn't share the three-condition structure. Folding it inside the feeder section would conflate two distinct gate categories and degrade the section's specificity.

**Why NOT a subsection inside Three Exit Paths:** the exit paths describe how chains terminate, not how children are invoked. Gates are an invocation-time concept; exits are a termination-time concept. The two surfaces are orthogonal.

**Wording for the new Gate Vocabulary section:**

```markdown
## Gate Vocabulary

A parent's chain-orchestration logic decides per child whether to
invoke the child. The pattern names four gate shapes; each parent's
phase-2 chain-orchestration reference (see Required SKILL.md
Structural Elements below) binds each of its children to one of the
four shapes plus the per-child predicates.

The four gate shapes:

- **EITHER-signal.** The child is invoked when EITHER of two
  parent-defined signals fires. Signal 1 is typically
  "upstream-artifact-absent" (the child's durable artifact does not
  exist at the published path); signal 2 is typically a
  Phase-1-discovery agent-judgment signal (e.g., a thesis-shift or
  framing-shift signal). The two signals are independently
  sufficient; the gate fires when EITHER holds. Canonical example:
  `/charter`'s `/vision` invocation (R4) and `/scope`'s `/brief`
  invocation (R4).

- **ALWAYS (with no auto-skip).** The child is invoked
  unconditionally whenever the chain reaches it. There is no
  auto-skip-on-existing-artifact semantics; the child's own resume
  logic handles existing-artifact cases. Canonical example:
  `/charter`'s `/strategy` invocation (R6) and `/scope`'s `/plan`
  invocation when the chain reaches it (R7).

- **Mandatory-with-auto-skip.** The child is invoked
  unconditionally UNLESS the child's durable terminal artifact
  already exists at the published path in an accepted-equivalent
  status. In the auto-skip case, the child is recorded in
  `chain_skipped` with a reason citing the existing artifact;
  `chain_ran` does NOT include the child. The parent MUST NOT
  silently overwrite the existing artifact. Canonical example:
  `/scope`'s `/prd` invocation (R5 + Decision 6).

  The shape is structurally distinct from ALWAYS (which has no
  auto-skip) and from EITHER-signal (which would force a contrived
  Phase-1-discovery signal even when none exists in the child's
  resume semantics). Mandatory-with-auto-skip captures the case
  where the child is load-bearing in the new-topic case and
  auto-skippable in the existing-artifact case.

- **Shape-dependent.** The child is invoked when the
  just-produced (or existing) upstream artifact exhibits at least
  one parent-defined shape predicate. Predicates are
  agent-judgment evaluated at Phase 1 against the upstream
  artifact's body (e.g., "the upstream PRD's Requirements section
  contains 2+ requirements that imply architectural
  alternatives"). When NONE of the shape predicates hold, the
  child is skipped and the chain proceeds to the next child with
  the upstream artifact as input. Canonical example: `/charter`'s
  `/roadmap` invocation (R7) and `/scope`'s `/design` invocation
  (R6).

The gate shape a child binds to is parent-specific (each parent's
phase-2 chain-orchestration reference declares per-child gate
shapes); the four shapes themselves are pattern-level vocabulary.

**Auto-skip-vs-skip semantics.** A child recorded in
`chain_skipped` under Mandatory-with-auto-skip (artifact already
exists) is structurally distinct from a child recorded in
`chain_skipped` under shape-dependent (no shape predicate held).
Both are recorded in `chain_skipped` because the chain did not
invoke them; the free-text `reason:` field disambiguates the two
cases for human reviewers. Each parent's phase-2 chain-
orchestration reference SHALL specify the canonical reason text
for each skip path.
```

**Estimated insertion size:** ~50-60 lines including the section header, the four bullet entries, and the auto-skip-vs-skip semantics paragraph. The wording uses neither `/charter` nor `/scope` exclusively — both parents appear as canonical examples — so the section is genuinely pattern-level rather than scope-PRD-leaked.

**A.2. No other edits to `parent-skill-pattern.md`.** The two-layer contract, the seven invariants, the three exit paths, the substitution surfaces, the team-shape declarator, the team-lead operating discipline, and the required SKILL.md structural elements all stay verbatim. The audit's verbatim recommendation holds for everything except the gate vocabulary.

#### B. `references/parent-skill-state-schema.md`

**B.1. New conditional field `boundary:` — gated by `exit: re-evaluation`.**

**Edit location:** A new bullet entry in the **Field Semantics** section (lines 40-68), inserted as the final bullet after `exit_artifacts`. Plus a paragraph addition inside the **Conditional-field gating** subsection (lines 92-103) using `boundary:` as a worked example alongside the existing `triggering_child:` example.

**Why Field Semantics is the right home for the bullet:** The Field Semantics section is the per-field-name table-of-contents for the schema. New fields land here for discoverability. The existing structure (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) extends naturally with a sixth bullet for `boundary:`.

**Wording for the new `boundary:` bullet in Field Semantics:**

```markdown
- **`boundary`** — parent-defined enum string. Conditional field;
  SET when `exit: re-evaluation` AND the parent's re-evaluation
  exit recognizes multiple boundary positions (e.g., `/scope`
  recognizes PRD-boundary and DESIGN-boundary; `/charter`
  recognizes only one boundary and MAY omit the field). UNSET
  otherwise per invariant I-5. The field's allowed values are the
  parent's named re-evaluation boundary identifiers; the
  vocabulary is parent-specific.
```

**B.2. New conditional field `plan_execution_mode:` — gated by `chain_ran` containing `/plan` (or substrate-equivalent execution-mode-bearing child).**

**Edit location:** A second new bullet entry in the **Field Semantics** section, inserted immediately after `boundary:`. Plus an example callout inside the **Chain-tracking** subsection (lines 104-121) noting that per-child output-mode selection is parent-specific extension territory.

**Wording for the new `plan_execution_mode:` bullet in Field Semantics:**

```markdown
- **`plan_execution_mode`** — parent-defined enum string.
  Conditional field; SET when the parent's chain invoked a child
  with multiple terminal output modes (e.g., `/scope` invokes
  `/plan` which has `single-pr` and `multi-pr` modes; the field
  records `/plan`'s selected mode for re-entry status detection).
  UNSET when no such child ran. The field generalizes per-child
  output-mode selection that the chain-tracking unit
  (`planned_chain`/`chain_ran`/`chain_skipped`) does not capture;
  parents whose children all have a single output mode MAY omit
  the field per invariant I-5.
```

**B.3. New paragraph in Chain-tracking subsection** (added between current lines 119 and 121):

```markdown
**Per-child output-mode selection is extension territory.** A
child with multiple terminal output modes (e.g., a child that
produces a Draft doc OR a Draft doc plus a GitHub milestone)
exposes a per-child execution-mode signal that does NOT belong in
the chain-tracking unit (`planned_chain`/`chain_ran`/
`chain_skipped` are invocation-disposition fields, not
output-shape fields). Parents whose chains include such a child
SHALL extend the schema with a parent-specific conditional field
gated by `chain_ran` containing the relevant child; the field
satisfies invariant I-5 like any other conditional extension. The
canonical example is `plan_execution_mode:` for parents that
invoke `/plan`.
```

**B.4. R9 hard-finalization-check additions.**

**Edit location:** The **R9 Hard-Finalization Check Spec** section's three-part list (lines 157-184), specifically Part 2 ("Sub-shape valid when applicable") and Part 3 ("Conditional fields absent when ungated"). Each part gets the new fields added as worked examples.

**Wording — Part 2 expansion (replace lines 169-176, the existing Part 2 body):**

```markdown
2. **Sub-shape valid when applicable.** If the parent defines a
   sub-shape field (e.g., a Decision Record's `re-evaluation` vs
   `rejection` sub-shape) gated on a specific `exit:` value, the
   sub-shape field is set to one of its valid values when the
   gating `exit:` fires. UNSET or out-of-enum sub-shape values
   fail the check. The check applies to ALL sub-shape-style
   conditional fields including `decision_record_sub_shape:` AND
   `boundary:` (when the parent recognizes multiple
   re-evaluation boundary positions). A parent whose re-evaluation
   exit recognizes one boundary may omit the `boundary:` field
   entirely (per invariant I-5); a parent whose re-evaluation
   exit recognizes multiple boundaries MUST set BOTH
   `decision_record_sub_shape:` AND `boundary:` to valid enum
   values when `exit: re-evaluation` fires.
```

**Wording — Part 3 expansion (replace lines 176-179, the existing Part 3 body):**

```markdown
3. **Conditional fields absent when ungated.** Fields whose
   presence is gated by a specific `exit:`, sub-shape, or
   chain-state value are ABSENT from the state file when their
   triggering condition does not hold (invariant I-5). Null,
   empty-string, or placeholder values fail the check. The check
   applies to every conditional field the parent extends with,
   including `boundary:` (gated by `exit: re-evaluation` plus
   the parent's multiple-boundary discriminator),
   `plan_execution_mode:` (gated by `chain_ran` containing the
   execution-mode-bearing child), `referenced_artifact:` (gated
   by re-evaluation sub-shape), `discard_commit_sha:` and
   `rejection_rationale:` (gated by rejection sub-shape), and
   `triggering_child:` and `partial_phase_reached:` (gated by
   `exit: abandonment-forced`).
```

**Estimated total insertion size in state-schema:** ~30-40 lines (two new field bullets, one new paragraph in Chain-tracking, two replaced R9 paragraphs).

#### C. `references/parent-skill-resume-ladder-template.md`

**C.1. Universal-meta-ladder additions for PLAN-Active and PLAN-Done.**

This is the contested choice. There are two viable placements:

**Option C.1.α — Add two rows to the universal meta-ladder.** Insert new rows 4.5 and 4.6 (or renumber: new rows 5 and 6) into the existing 9-row meta-ladder (the table at lines 21-31). The rows are universal because the *behavior* — refuse-and-redirect when re-entering against a terminal artifact whose lifecycle is owned by a downstream skill — applies to any parent whose terminal artifact has post-terminal lifecycle states owned by other skills. For `/charter` (whose terminal STRATEGY is Accepted-only with no implementation skill that owns a downstream lifecycle), the rows are vacuously satisfied (no PLAN-equivalent doc exists to trigger them); for `/scope`, the rows are load-bearing.

**Option C.1.β — Leave the meta-ladder at 9 rows; fold the PLAN-Active/Done behavior into parent-specific body slot 5.** Body slot 5 is the "status-aware re-entry" slot — its specification already says the parent's SKILL.md "names which child doc(s) trigger this slot and what statuses count as triggers" (line 117). PLAN-Active and PLAN-Done are exactly that kind of trigger, just with a non-standard refuse-and-redirect prompt vocabulary (instead of the typical Re-evaluate/Revise/Bail triad). The body slot would simply have multiple rows: PLAN-Draft → continue/start-fresh; PLAN-Active → refuse-and-redirect to `/work-on`; PLAN-Done → refuse-and-redirect to `/release`; PRD-Accepted → Re-evaluate/Revise/Bail (PRD-boundary); DESIGN-Accepted → Re-evaluate/Revise/Bail (DESIGN-boundary).

**Chosen: Option C.1.β (body slot 5).** Reasoning:

- **The refuse-and-redirect behavior is parent-specific in its specifics.** The downstream-skill names (`/work-on`, `/release`) are not pattern-level vocabulary — they are shirabe-skill names that the pattern doc otherwise avoids. Putting `/work-on` and `/release` literals in the universal meta-ladder would leak `/scope`-binding into the pattern.
- **The trigger predicate (terminal-artifact has Active or Done status) is also parent-specific.** Some parents may never have such states. The pattern's meta-ladder rows 1-4 and 8-9 are universal in BOTH behavior AND predicate; PLAN-Active/Done rows would be universal in behavior-shape but parent-specific in predicate. Body slot 5 is the right altitude — universal slot, parent-specific predicates and prompts.
- **Body slot 5's existing spec already supports it.** The slot rule says "the parent's prompt offers prompt vocabulary appropriate to the parent's exit-path bindings (typically a Re-evaluate / Revise / Bail triad against an Accepted upstream artifact)." The word "typically" already admits non-Re-evaluate-triad prompts. PRD R11's refuse-and-redirect prompts fit under "appropriate to the parent's exit-path bindings."
- **Pattern-doc additivity is preserved.** Option α would expand the universal meta-ladder from 9 rows to 11 rows, breaking the established 9-row count cited in lines 8-10 and line 19 ("A reader of any parent's SKILL.md sees the same 9-row ladder shape"). Option β keeps the 9-row meta-ladder intact and adds the behavior in the parent-specific body slot where the existing language already authorizes it.

**Edit location for Option β realization:** Slot 5's specification (lines 105-123) gets a single paragraph appended noting that the slot's prompt vocabulary MAY be a refuse-and-redirect when the parent's terminal artifact has a status owned by a downstream skill.

**Wording for the slot-5 spec addition (append after current line 123):**

```markdown
**Refuse-and-redirect prompts are admissible.** Slot 5's prompt
vocabulary MAY be a refuse-and-redirect (rather than the
Re-evaluate / Revise / Bail triad) when the parent's terminal
artifact has a lifecycle state owned by a downstream skill (e.g.,
a PLAN-Active state owned by an implementation skill, a PLAN-Done
state owned by a release skill). In refuse-and-redirect, the
parent declines to re-enter its own chain-authoring flow and
names the downstream skill that owns the detected state. The
parent's SKILL.md specifies the downstream-skill name as a
literal-substring AC. The refuse-and-redirect behavior preserves
skill-ownership boundaries: a chain-authoring parent does not
re-enter against artifacts whose lifecycle has already passed
into another skill's domain.
```

**C.2. No other edits to `parent-skill-resume-ladder-template.md`.** The 9-row meta-ladder count stays. The stale-session threshold, the malformed-state-file handling, the per-body-slot rules all stay verbatim.

**Estimated insertion size in resume-ladder-template:** ~10-12 lines (one new paragraph appended to slot 5's specification).

#### D. `references/parent-skill-child-inspection.md`

**No edits.** The audit's verbatim recommendation holds. All four tactical-chain children (BRIEF, PRD, DESIGN, PLAN) are doc-emitting; they slot into the existing "doc-emitting" row of the per-parent surface table (line 62). `/plan`'s `multi-pr` mode creates a GitHub milestone, but the milestone is downstream of `/plan`'s terminal artifact (the PLAN doc) — `/scope` inspects the PLAN doc's frontmatter status (Draft / Active / Done) and git blob hash; it does NOT inspect the milestone itself. The milestone's existence is a side-effect captured in `plan_execution_mode:` in the state file, not in the child-inspection surface.

The R14-widened isolation rule, the drift detection, the manual-fallback non-interference framing, and the negative-examples list all transfer verbatim.

#### Summary of total edit surface

| File | Edits | Estimated added lines |
|---|---|---|
| `references/parent-skill-pattern.md` | New "Gate Vocabulary" section between "Three Exit Paths" and "Conditional Feeder Invocation Shape" | ~50-60 |
| `references/parent-skill-state-schema.md` | Two new field bullets in Field Semantics; one new paragraph in Chain-tracking; two replaced R9 paragraphs | ~30-40 |
| `references/parent-skill-resume-ladder-template.md` | One paragraph appended to Slot 5 spec | ~10-12 |
| `references/parent-skill-child-inspection.md` | None | 0 |
| **Total** | **4 distinct insertions across 3 files** | **~90-112 lines** |

**Rationale**

The chosen edit surface satisfies four constraints simultaneously:

- **PRD-mandated edits land in the locations the PRD's own Downstream Artifacts section names.** PRD Downstream Artifacts (lines 1791-1799) explicitly names "Pattern-doc edit: `references/parent-skill-pattern.md`" for the fourth gate type; the chosen Gate Vocabulary section is the natural home. Schema and ladder edits are not enumerated as Downstream Artifacts but are forced by R9 + R10 + R11; landing them in the references the schema and ladder already live in keeps the downstream-artifact list complete by inference.

- **Pattern-vs-parent-specific classification respects the audit's framing.** The audit said the references' two-layer contract, body slots, per-parent surface table, and extension discipline absorb second-parent specifics. The Gate Vocabulary section is genuinely pattern-level (Decision 6 is about a *vocabulary* expansion, not a parent-specific binding). The state-schema field additions are extension-discipline-conformant (parent-specific conditional fields under invariant I-5). The resume-ladder addition stays inside body slot 5 (parent-specific slot the template already names). The audit's "verbatim" stance softens for the gate vocabulary (a vocabulary entry is necessarily pattern-level) but holds for the body-slot-fillable surfaces.

- **9-row meta-ladder count is preserved.** Lines 8-10 and line 19 of the resume-ladder-template explicitly promise "the same 9-row ladder shape" to readers of any parent's SKILL.md. Adding rows to the meta-ladder would break that promise and require ripple edits across `/charter`'s SKILL.md. Slot 5's existing spec already admits the refuse-and-redirect prompt shape (via the word "typically"); the single-paragraph addition makes it explicit without growing the meta-ladder count.

- **`/charter`'s back-edit cost stays bounded.** `/charter`'s SKILL.md will need a citation-style back-edit (the PRD Downstream Artifacts already names this as a follow-up reference-table addition for the new worktree-discipline reference, and the same back-edit can absorb the gate-vocabulary citation). `/charter`'s SKILL.md does NOT need a new body-slot-5 row for refuse-and-redirect — `/charter`'s STRATEGY has no Active/Done analog. The chosen edits leave `/charter`'s body slot 5 vacuously unchanged.

**Alternatives Considered**

- **Alt 1: Add the fourth gate type to the existing Conditional Feeder Invocation Shape section as a subsection.** Rejected because the feeder section's three-condition gate is a *specific* gate shape, not a vocabulary container. Folding Mandatory-with-auto-skip inside the feeder section would conflate main-chain gates with feeder gates and force readers to navigate into the feeder section to find a non-feeder gate. The new Gate Vocabulary section creates a clean home for all four gate shapes.

- **Alt 2: Add the fourth gate type as a paragraph at the end of `parent-skill-pattern.md` rather than a new top-level section.** Rejected because trailing-paragraph placement is less discoverable for future parent-skill authors. The PRD Decision 6 motivation is "future parent-skill authors who consult the pattern doc"; a top-level section is the discoverable surface.

- **Alt 3 (C.1.α): Add PLAN-Active and PLAN-Done as universal meta-ladder rows.** Rejected because the meta-ladder is universal in BOTH behavior and predicate; PLAN-Active/Done rows would be universal in behavior-shape only. Adding them breaks the 9-row count cited in lines 8-10 and line 19. Body slot 5's existing language already admits the prompt shape.

- **Alt 4: Define `boundary:` and `plan_execution_mode:` only in `/scope`'s state-management phase reference, not in the pattern's state schema.** Rejected because the PRD tags R10 as `[pattern-level]` and Downstream Artifacts names the state-schema reference as the inheritance carrier. Leaving the fields in `/scope`-specific docs would force `/work-on` (SE8) and future parents to re-derive the boundary-style and execution-mode-style extension pattern. The state-schema additions are worked examples of the existing extension discipline; they belong in the pattern reference.

- **Alt 5: Add `boundary:` to the 5-field minimum (raising it to a 6-field minimum).** Rejected because most parents recognize one re-evaluation boundary or none. Making `boundary:` minimum-required would force every parent to write `boundary: <single-value>` or `boundary: null` (which violates I-5). Conditional-field-with-extension-discipline is the correct framing.

- **Alt 6: Make R9 Part 2 ("Sub-shape valid when applicable") explicit about `boundary:` only, leaving `plan_execution_mode:` to Part 3.** Adopted partially — `boundary:` is named in BOTH Part 2 and Part 3, because it functions as a sub-shape discriminator alongside `decision_record_sub_shape:` (Part 2) AND as an I-5-conditional field (Part 3). `plan_execution_mode:` is named in Part 3 only because it is not a sub-shape discriminator; it is a chain-state extension.

- **Alt 7: Edit `parent-skill-child-inspection.md` to add a row for "doc-emitting child plus side-effect resource" (PLAN doc plus GitHub milestone).** Rejected because the milestone is not a child-inspection surface — `/scope` does NOT read milestone state to drive its own decisions. `plan_execution_mode:` in the state file records the side-effect's selection; the surface itself stays at the PLAN doc's frontmatter status and git blob hash. The "doc-emitting" row covers this without modification.

**Consequences**

**What gets easier:**

- Future parent-skill authors who consult the pattern doc see all four gate shapes in one place (the new Gate Vocabulary section), can pick the right shape for each of their children, and have canonical examples to anchor on.
- `/work-on` (SE8) inherits the gate vocabulary, the state-schema extension worked examples (`boundary:`, `plan_execution_mode:`), the R9 expansion (covering chain-state extensions, not just sub-shape extensions), and the refuse-and-redirect prompt shape in body slot 5 — all four edits are load-bearing for any parent whose chain crosses multiple boundary or execution-mode contexts.
- R9 enforcement at finalization time catches a wider class of state drift (e.g., a `/scope` run that records `exit: re-evaluation` without `boundary:` will fail finalization with a clear error per the expanded R9 spec).
- Reviewers of `/scope`'s implementation can grep the pattern docs for `Mandatory-with-auto-skip`, `boundary:`, `plan_execution_mode:`, and "refuse-and-redirect" to verify the SKILL.md commitments map to the pattern reference; the L9 PRD pattern-level tagging convention (PRD Decision 5) becomes mechanically reviewable for these specific edits.

**What gets harder:**

- `/charter`'s back-edit PR grows slightly (it now needs to cite the new Gate Vocabulary section in `/charter`'s phase-2 doc, and confirm `/charter`'s body slot 5 has no refuse-and-redirect rows because STRATEGY has no Active/Done analog). The cost is bounded — the PRD's Downstream Artifacts already named this as a follow-up.
- Future parent-skill authors must decide which of the four gate shapes binds to each of their children; the four-way decision is harder than a three-way decision. Mitigation: the Gate Vocabulary section's canonical-example callouts (`/vision` / `/brief` for EITHER-signal, `/strategy` / `/plan-when-reached` for ALWAYS, `/prd` for Mandatory-with-auto-skip, `/roadmap` / `/design` for shape-dependent) give author-mentor examples for every shape.
- The pattern reference files grow by ~90-112 lines total, which is non-trivial for a reference-doc surface. The growth is concentrated in `parent-skill-pattern.md` (~50-60 lines) and `parent-skill-state-schema.md` (~30-40 lines). The lines are all additive — no existing prose is rewritten except R9 Parts 2 and 3, which gain worked-example expansion rather than semantic change.

**What stays the same:**

- The two-layer contract framing across all four references.
- The seven semantic invariants (I-1 through I-7).
- The 5-field minimum schema floor.
- The three-exit contract.
- The 9-row meta-ladder count.
- The R14-widened isolation rule and the per-parent surface table.
- Manual-fallback non-interference (R13) and the negative-examples list.
- Every body-slot specification (slots 5, 6, 7).
- The team-lead operating discipline and the canonical 5-step loop.

**Net assessment:** the edit surface is surgical (four distinct insertions across three files), additive (no semantic-changing rewrites), and minimally invasive (the child-inspection reference is unchanged; the resume-ladder gets one paragraph; the schema gets two field bullets plus one paragraph plus two R9 expansions; the pattern doc gets one new section). The 9-row meta-ladder count and the verbatim-inheritance promise from the audit hold for everything except the gate vocabulary — and the gate vocabulary expansion is precisely what PRD Decision 6 mandated.
<!-- decision:end -->

---

## Open Questions / Flags for Synthesis

1. **`/charter`'s body slot 5 vacuity.** This decision assumes `/charter`'s SKILL.md body slot 5 has no refuse-and-redirect rows because STRATEGY has no Active/Done lifecycle. If a future strategic-chain artifact gains such a lifecycle (e.g., a STRATEGY-Active state owned by an implementation skill), `/charter` would need to add rows. The chosen slot-5 spec addition handles this gracefully — the "MAY" framing admits future strategic-chain expansion without re-editing the pattern doc.

2. **Cross-reference between the new Gate Vocabulary section and the Conditional Feeder Invocation Shape section.** The two sections are now sibling top-level surfaces; the feeder shape is one specific use of the EITHER-signal-with-three-conditions composition. The decision deliberately leaves them as siblings rather than nesting feeder inside gate vocabulary, because feeders have additional structure (degenerate-silence rule, visibility gate) that doesn't belong inside the gate vocabulary surface. A cross-reference at the start of the Conditional Feeder Invocation Shape section ("see Gate Vocabulary above for the four gate shapes; the feeder shape composes an EITHER-signal gate with the three-condition predicate below") would aid navigation; the decision leaves the exact wording to the authoring phase.

3. **R9 hard-finalization-check enforcement mechanism.** The decision specifies *what* R9 checks (the field-presence-vs-absence rules); it does NOT specify *how* the check runs (a SKILL.md prose check, a `shirabe validate` subcommand, an inline state-file linter, etc.). The implementation mechanism is design-team territory beyond this decision's scope; PRD Questions Deferred to Design item 1 is the right home.

4. **Whether `/scope`'s SKILL.md needs to explicitly cite each of the four gate shapes by name.** The decision does not constrain this. Each `/scope` child binding (R4/R5/R6/R7) names its gate shape explicitly in the PRD; the SKILL.md prose can mirror that. The PRD-tagged R1 structural element 5 (Reference Files table) will cite the pattern reference; whether the per-child gate-shape names appear in the SKILL.md body or only in the chain-orchestration phase reference is an authoring-phase choice.
