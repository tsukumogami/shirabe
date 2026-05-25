# Decision 3 Report: State-File Schema and Resume-Ladder Ratification vs Abstraction

**Decision researcher:** decision-researcher-3
**Tier:** 4 (critical) — inline walk per SE4 §8 (no nested validator team)
**Phases walked:** 0, 1, 2, inline adversarial pass, 6
**Prefix:** `design_shirabe-progression-authoring_decision_3`

---

## Phase 0: Context

### Question

Does the design ratify the PRD's concrete state-file schema (R10) and resume-ladder ordering (R11), plus the R9 finalization check, as **pattern-level commitments** that every parent skill uses verbatim, or **abstract them to a contract-level form** (named invariants whose concrete realization is parent-specific)?

### Complexity

Critical. Downstream parents (`/scope`, `/work-on`) inherit whatever shape lands. Drift across parents (different field names for the same concept, different ladder ordering for the same condition) is the primary failure mode the PRD's pattern-level tagging is trying to prevent.

### Constraints

- **PRD R9 (hard finalization check).** Whatever the schema is, an `exit:` field validation must fire. Ratifying R9 verbatim makes this portable; abstracting requires naming the universal-required fields.
- **PRD R10 (state file schema).** YAML with `.md` extension, branch-coupled, topic-keyed. Concrete fields enumerated: `topic`, `chain_started`, `chain_completed`, `last_updated`, `planned_chain`, `chain_ran`, `chain_skipped`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, `child_snapshots`, plus conditional fields (`referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`).
- **PRD R11 (resume ladder).** 9-entry ordered ladder; first-match-wins; malformed state file is a hard surface (not silent fall-through). Status-aware re-entry rules referenced upfront in the parent flow (not hijacked by child prompts).
- **AC15, AC17, AC18, AC19, AC20, AC20c trace to R9/R10/R11.** Ratifying verbatim makes acceptance criteria portable; abstracting makes them per-parent.
- **`/scope`'s scope is unknown.** If `/scope` ever needs fields `/charter` doesn't (scope-specific dependency tracking), the contract must accommodate.
- **`/work-on`'s scope is workflow-substrate-dependent.** Likely doesn't use wip/-based state at all; its state lives wherever the substrate lives.
- **Coupling to Decision 2.** D2 sets the substitution surface freeze line. If D2 says "schema is implementation" → D3 leans (b)/(c). If D2 says "schema is contract" → D3 leans (a). Phase 3 cross-validation handles coupling; this report names the dependence as an assumption.

### Known Options (from dispatch)

- (a) Ratify the schema verbatim as pattern-level.
- (b) Abstract to a contract-level form (named invariants).
- (c) Hybrid — minimum-required schema with extension hooks.

---

## Phase 1: Research

### What I looked at

1. **PRD R9, R10, R11 prose** (`docs/prds/PRD-shirabe-charter-skill.md` lines 428–544) — the full schema, the ladder, the malformed-state handling, the asymmetry between `chain_ran` history and `planned_chain`, the snapshot-comparison semantics.
2. **PRD acceptance criteria AC11a–AC20c** (same file, lines ~750–875) — the binary observables that any abstraction must still let downstream parents verify.
3. **Existing shirabe resume-ladder precedents** (`skills/strategy/SKILL.md` lines 158–169; `skills/explore/SKILL.md` lines 186–199) — both are short, topic-keyed, first-match-wins ladders. Neither has a state file like R10; both infer state from artifact presence. This matters: ratifying R10/R11 verbatim is a real *increase* in commitment over what shipped skills do today.
4. **Design skeleton** (`docs/designs/DESIGN-shirabe-progression-authoring.md` lines 198–215, Driver 9) — Driver 9 explicitly names R9/R10/R11 together and asks: ratify or abstract. The skeleton signals "the PRD's pattern-level tagging signals 'ratify'; the design must agree or explain why not."
5. **Coordination manifest** (`wip/design_shirabe-progression-authoring_coordination.json`) — confirms D3 is critical, names D2 as coupled, and frames the three options.

### Findings

**Finding 1: The PRD schema is not generic — it is `/charter`-shaped.**

Fields like `chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`, `decision_record_sub_shape`, `referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child` are tightly coupled to `/charter`'s chain-of-children model and its three exit paths. `/scope` may not have a "chain of children" in the same sense (a scope might be a single-shot artifact production), and `/work-on` almost certainly does not (work-on is an iterative implementation loop, not a chain). Verbatim ratification forces the next two parents to either carry empty/null fields or to redefine "chain" abstractly. This is the strongest argument against pure (a).

**Finding 2: A small core of fields is genuinely universal.**

Every parent needs to know: what topic, when last touched, what phase we're in, and (when the parent finalizes) what outcome was reached. Concretely: `topic`, `last_updated`, `exit`, `exit_artifacts` (or equivalent terminal-artifact pointer) appear inevitable for any parent. The R9 finalization check (some `exit:` field validated against an enum) is a universal contract surface — but the enum values are parent-specific (`/charter`'s `{full-run, re-evaluation, abandonment-forced}` is not `/scope`'s set, whatever that turns out to be).

**Finding 3: Ladder ordering has both universal and parent-specific entries.**

Looking at the 9-entry ladder in R11:
- Entries 1–4 (malformed → discard; exit set → revise/fresh; <7d → resume; ≥7d → 3-option prompt) describe **state-file lifecycle handling**. These are about how the parent treats its own state file regardless of what's in it. **Universal.**
- Entries 5–6 (STRATEGY Accepted/Active → Re-evaluate/Revise/Bail; STRATEGY Draft → continue/start fresh) describe **status-aware re-entry against a specific child artifact**. The artifact type (STRATEGY) and the chain-anchor concept (STRATEGY is `/charter`'s anchor) are `/charter`-specific. **Parent-specific.**
- Entries 7–8 (wip/strategy_discover.md → resume into /strategy; wip/vision_scope.md → resume into /vision) reference **specific child artifacts and specific child entry points**. **Parent-specific.**
- Entry 9 (on topic branch / off topic branch → Phase 1 / Phase 0) is **universal in spirit** but the specific phase numbers may vary.

This suggests the ladder is structurally splittable: a universal *meta-ladder* (lifecycle entries + branch-aware fallback) and a parent-specific *body* (the status-aware and per-child-artifact entries).

**Finding 4: R10's `child_snapshots` and R13's manual-fallback are tightly coupled.**

The R10 `child_snapshots` block exists to support R13 manual-fallback detection (and AC19, AC23). Any abstraction that loses the snapshot semantics breaks R13's pattern-level commitment. So if the design wants R13 to remain pattern-level, the abstraction must explicitly name "per-child snapshot tracking that detects status drift AND content-hash drift" as a contract surface, even if the schema details differ.

**Finding 5: Acceptance criteria become unportable under pure abstraction (b).**

AC15 ("a run that completes without recording a valid exit fails finalization") is portable under (a) or (c) because `exit:` is a named field. Under (b), AC15 becomes "the parent's exit-equivalent contract enforces its finalization rule" — true but useless as a contract surface. AC18 ("when STRATEGY is Accepted/Active, the entry prompt contains Re-evaluate/Revise/Bail substrings") is `/charter`-specific regardless. AC19 (snapshot drift fires when either status OR content-hash differs) is the most interesting: it's testable as written, but it generalizes — every parent that does manual-fallback detection needs the same dual-check rule, which is a *named invariant* even if the field names vary.

**Finding 6: The decision-record sub-shape pattern is `/charter`-only by construction.**

`decision_record_sub_shape: {re-evaluation, rejection}` exists because `/charter`'s re-evaluation exit has two sub-shapes (R8). No other parent has this exact structure. Ratifying this field verbatim as pattern-level is over-commitment.

**Finding 7: The branch-coupling property is universal across the core layer.**

R10's branch-coupling (wip/-based) and R11's branch-aware fallback (on topic branch / off topic branch) are universal to the wip/-based core layer. They are properties of the substrate, not of `/charter`. D2 owns whether the contract permits an amplifier-layer substitute; D3 inherits whatever D2 decides about substrate-specificity.

### Assumptions made

**Assumption A1:** Decision 2 will commit to a "schema-shape is implementation, schema-invariants are contract" framing (i.e., the substitution surface includes the storage substrate, and the contract names invariants like "has a topic-keyed terminal-state record" rather than "has a YAML file at `wip/<parent>_<topic>_state.md`"). **If wrong:** D3's recommendation needs to slide toward (a) — verbatim ratification — because the contract would then bind every parent to the same on-disk shape. **Consequence if wrong:** the report's chosen option remains structurally sound (the hybrid still works under a more committed D2) but the "schema details are implementation, invariants are contract" framing collapses into "schema details are contract" — minimal damage.

**Assumption A2:** `/scope` and `/work-on` will not be co-authored with `/charter`. Each will land later, with `/scope` likely closest in shape to `/charter` (also strategic-ish, child-chain-shaped) and `/work-on` substantially different (implementation loop, possibly substrate-pivoting). **If wrong** (e.g., `/scope` is co-authored): the design has the chance to validate the contract against two consumers immediately, which would let (a) be safely ratified. **Consequence if wrong:** (a) becomes more defensible; my chosen option stays workable but slightly conservative.

**Assumption A3:** "Pattern-level" in PRD R9/R10/R11 means "this is a property of the parent-skill pattern and the design SHOULD lift the relevant commitment into shared scope" — not "this exact schema is the contract." The PRD's `[pattern-level]` tag is a designer-direction signal, not a contract-shape lock-in. **If wrong** (i.e., the PRD intends verbatim lift): my recommendation deviates from PRD intent and the cross-validation phase would surface this. **Consequence if wrong:** the report needs to either justify the deviation explicitly (which it does, below) or revise to (a).

### Clean summary

The PRD provides a fully-specified `/charter`-shaped schema and ladder, tagged `[pattern-level]`. The critical unknown is whether "pattern-level" means **exact-shape ratification** (a) or **invariant lifting** (b/c). The research finds: a small core (topic, last_updated, exit, exit_artifacts) is genuinely universal; another small set (`decision_record_sub_shape`, exit-enum values, chain-related fields) is `/charter`-specific by construction; everything else (`child_snapshots`, ladder lifecycle entries) sits between — *the semantics generalize, the field names and exact ladder positions do not*. The decision turns on whether ratifying `/charter`'s specifics now would over-commit the next two parents.

---

## Phase 2: Alternatives

The dispatch starting point — (a), (b), (c) — turns out to be the right framing. I refine each alternative to be concrete enough that Phase 4's Solution Architecture could write code against it.

### Alternative A: Verbatim ratification (pattern-level commitment is the schema itself)

**Description.** The design lifts R10's complete YAML schema into a pattern-level `references/parent-skill-state-schema.md` document. Every parent's state file MUST contain every named field from R10's schema. Parent-specific additions are allowed (a `/scope`-specific field added below the universal block is fine) but **field name changes are forbidden** — `chain_started` is always `chain_started`, never renamed to `progression_started` or `loop_started`. R11's 9-entry ladder is lifted verbatim into `references/parent-skill-resume-ladder.md`; parents reference it and substitute their child artifact names (STRATEGY → IMPLEMENTATION-PLAN for `/work-on`, etc.) but keep the ordering and the prompt-vocabulary semantics identical. R9's `exit:` field validation is universal; the *enum values* are pattern-specific (each parent declares its enum in its own SKILL.md, but the field name and the hard-finalization check are pattern-level).

**Concretely a designer must commit to:**
- A `references/parent-skill-state-schema.md` listing every R10 field with type and semantics.
- A `references/parent-skill-resume-ladder.md` listing the 9 ordered conditions with placeholders for parent-specific artifact paths.
- A pattern-level statement: "parents MUST NOT rename schema fields; parents MAY add fields below the universal block."

**Source:** Direct PRD ratification.

### Alternative B: Pure contract abstraction (pattern-level commitment is the invariant set)

**Description.** The design lifts named invariants into pattern-level scope without committing to specific field names or specific ordering. R9 becomes: "every parent MUST validate a terminal-state outcome value against the parent's declared exit-outcome enum at finalization." R10 becomes a list of named invariants: every parent's state file MUST track (1) topic identity, (2) last-touched time, (3) phase pointer, (4) outcome at exit, (5) terminal-artifact pointer, (6) per-feeder-artifact snapshot for staleness detection. Field names are parent-specific. R11 becomes an ordering invariant: "the ladder MUST handle malformed-state-file first, MUST consult state file before reading feeder-artifact status, MUST NOT silently fall through" — but the specific 9 conditions are not lifted; each parent authors its own ladder satisfying the invariants.

**Concretely a designer must commit to:**
- A `references/parent-skill-state-invariants.md` naming each invariant (topic identity, last-touched, phase pointer, exit outcome, terminal-artifact pointer, feeder snapshots).
- A `references/parent-skill-resume-invariants.md` naming the ladder properties (malformed-first, state-before-artifacts, no-silent-fallthrough).
- A pattern-level statement: "each parent's state file shape is an implementation detail; the invariants are the contract."

**Source:** Dispatch option (b), refined.

### Alternative C: Hybrid — minimum-required schema with extension hooks

**Description.** The design lifts a **minimum-required field set** as pattern-level schema (specific field names, specific types) AND a separate set of **named invariants** for fields the minimum-required set doesn't cover. The minimum-required set is small and demonstrably universal: `topic` (string), `last_updated` (ISO-8601 timestamp), `phase_pointer` (string naming the parent's current phase), `exit` (string from parent-declared enum), `exit_artifacts` (list of `{path, status}`). The hard finalization check (R9) is lifted verbatim: `exit:` must be set and in the parent's enum at finalization. Beyond the minimum, named invariants govern: per-feeder-artifact staleness detection (each parent decides field name, but the dual-check semantics — status drift OR content-hash drift — are pattern-level), conditional fields gated by exit value (the *gating discipline* is pattern-level: conditional fields MUST be absent when their condition does not hold, not set to null/empty), and chain-tracking (only required for chain-shaped parents like `/charter`; `/work-on` may not have a chain at all).

R11's ladder is split: the **universal meta-ladder** (lifecycle entries 1–4 from R11 — malformed → discard, exit set → revise/fresh, fresh state <7d → resume, stale state ≥7d → 3-option prompt — and entry 9, branch-aware fallback) is lifted verbatim with parent-specific placeholders. The **parent-specific body** (entries 5–8: status-aware re-entry against the parent's chain-anchor or feeder artifact, partial-child-run resume) is authored per-parent against a template that names the required slots: "an entry for each feeder-artifact status (Accepted/Active and Draft, with the parent's prompt vocabulary), and an entry for each child whose partial wip/ artifact triggers resume." Status-aware-re-entry control (R11's "MUST decide upfront whether re-entry is a re-evaluation or a fresh chain; MUST NOT be hijacked by child's prompt") is pattern-level.

`/charter`'s specific R10 fields beyond the minimum (`chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`, `decision_record_sub_shape`, `referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`) all stay in `/charter`'s scope as parent-specific extensions. They satisfy the pattern-level invariants (chain-tracking, conditional-field discipline) but their field names are `/charter`'s call.

**Concretely a designer must commit to:**
- `references/parent-skill-state-schema.md` — the minimum-required field set (5 named fields with types) plus the R9 finalization check spec.
- `references/parent-skill-state-invariants.md` — the named invariants beyond the minimum: feeder-snapshot dual-check semantics; conditional-field gating discipline; chain-tracking (when applicable).
- `references/parent-skill-resume-ladder-template.md` — the universal meta-ladder (4 lifecycle entries + the branch-aware fallback) AND a templated body section naming the required slots for parent-specific entries, with prompt-vocabulary control (status-aware re-entry MUST NOT be hijacked by child prompts).
- A pattern-level statement: "the minimum-required schema is pattern-level (verbatim); fields beyond it are parent-specific extensions governed by named invariants. The meta-ladder is pattern-level (verbatim); the body is parent-specific against a template."

**Source:** Dispatch option (c), refined against the research findings.

### Quick comparison

| Property | A: Verbatim | B: Pure invariants | C: Hybrid |
|----------|-------------|--------------------|-----------|
| AC15 portable as-written? | Yes | No (needs per-parent rewrite) | Yes (`exit:` field is lifted) |
| AC19 portable as-written? | Yes | No (snapshot field names differ) | Mostly (invariant lifted; field names parent-specific) |
| `/scope` over-commitment risk | High (forces chain-shape onto a non-chain parent) | None (invariants only) | Low (chain-tracking is conditional) |
| `/work-on` accommodation | Poor (substrate-locked) | Best (invariants substrate-agnostic) | Good (D2 substitution surface intact) |
| Reader writing code against contract | Easy (concrete fields) | Hard (must interpret invariants per parent) | Easy for minimum; templated for the rest |
| Drift-prevention strength | Strongest (no rename allowed) | Weakest (no shared vocabulary) | Strong (shared minimum vocabulary + invariants) |
| Compatibility with D2 "schema is implementation" | Conflicts | Aligns | Aligns (minimum is the freeze line) |
| Compatibility with D2 "schema is contract" | Aligns | Conflicts | Aligns (minimum is part of the contract) |

### Recommendation from Phase 2 evidence

**Alternative C (Hybrid)** is the lowest-regret position regardless of how D2 lands. It preserves the AC15-portable observable (because `exit:` stays a named field with a hard finalization check), keeps drift-prevention strength on the universally-needed fields, and accommodates parents whose shape diverges from `/charter`'s chain model (like `/work-on`). The dispatch's framing instinct was right.

---

## Inline Adversarial Pass

Per the dispatch's critical-tier instructions, I write a steelman case for each of the three viable alternatives and then a case against, from the perspective of a peer who chose a different one.

### Steelman A — A peer who chose verbatim ratification

**Case for A.** "The PRD did the work. The PRD's R9/R10/R11 are not aspirational sketches — they are the binary observables that AC15, AC17, AC18, AC19, AC20, AC20c trace back to. Lifting them verbatim means every acceptance criterion in `/charter`'s PRD becomes a pattern-level acceptance criterion that `/scope` and `/work-on` inherit *without modification*. Drift across parents is the failure mode we are trying to prevent. The strongest drift-prevention is *no rename ever* — the moment we say 'parents may pick their own field names', we have invited the exact fragmentation we are designing to prevent. The PRD's `[pattern-level]` tag is the designer-direction signal, and the design should honor it. Yes, `/work-on` may not have a 'chain' — but it has a 'progression', and the field names map cleanly (`chain_started` → started-this-progression, etc.). Renames create translation cost; ratification eliminates it. And the eval scenarios in R18 — the slug-rejection scenario, the malformed-state-file scenario, the child-isolation scenario — only work as pattern-level evals if the schema is shared. Abstract them and every parent re-authors them. The cost of (a) is the cost of being principled."

**Case against A** (from C's perspective). The fields you point to as universal are *not* universal — they are `/charter`'s shape. `decision_record_sub_shape` cannot generalize to a parent that doesn't have re-evaluation/rejection sub-shapes; `chain_skipped` cannot generalize to a parent that doesn't have a chain. Forcing `/scope` to carry an empty `decision_record_sub_shape: null` field would be exactly the kind of placeholder PRD R9 forbids ("MUST NOT be set to null, empty string, or placeholder value"). The portability of AC15 is preserved under C just as well — `exit:` is in C's minimum-required set. What you lose under A is the ability to add `/work-on`-specific exit outcomes or `/scope`-specific dependency-tracking fields without a pattern-level revision. That brittleness is the cost of pure ratification.

### Steelman B — A peer who chose pure invariant abstraction

**Case for B.** "Verbatim ratification mistakes the schema for the contract. The contract is the *behavior* the parent must guarantee: every chain ends at a durable artifact, every finalization checks the outcome, every resume detects manual-fallback drift. The schema is one valid implementation of that contract. If we lift the schema, we have lifted the implementation, and we have foreclosed the amplifier-layer substrate where the implementation lives somewhere else entirely (workflow-substrate state, not a YAML file). Decision 2 is about exactly this: where does the freeze line live? If D2 says 'substrate is substitution', then schema cannot be lifted — only invariants can. The clean position is invariants-only: each parent satisfies named invariants in whatever way its substrate supports. The drift you are worried about isn't really about field names; it is about *vocabulary mismatch in author-facing prompts and outputs*. The prompt vocabulary (Re-evaluate/Revise/Bail, the 'chain-proposal' term) is already author-facing; lift *that* into pattern-level, not the storage detail. AC15 generalizes naturally: 'a run that completes without recording a valid exit-equivalent outcome fails finalization.' Yes, the wording is less mechanical, but the *behavior* is the same. Stop confusing how-the-data-looks-on-disk with what-the-parent-must-guarantee."

**Case against B** (from C's perspective). The "vocabulary mismatch in prompts" framing is partial; field-name drift across state files breaks audit trails too. A reviewer looking at `/charter`'s state file and `/scope`'s state file should not have to learn two field-name dictionaries to understand the same concept ("when was this last touched", "what was the outcome"). Naming `last_updated` consistently across parents is a tiny commitment with high-payoff — it doesn't lock substrate, it locks vocabulary. Your "invariants only" position throws this away for ideological cleanness. Furthermore, the acceptance criteria as written in the PRD become unportable under B — every parent has to re-author AC15, AC19, AC20c against its own schema. That is a real cost the design is paying to preserve a flexibility (rename-the-field) that no concrete consumer is asking for.

### Steelman C — A peer who chose hybrid

**Case for C.** "The research finding is decisive: some fields are genuinely universal (`topic`, `last_updated`, `exit`, `exit_artifacts`), some are genuinely `/charter`-specific (`decision_record_sub_shape`, the chain-specific fields), and the rest sit between (the semantics generalize, the field names don't). A binary choice forces you to pretend that boundary doesn't exist. The hybrid says: lift what's universal as a small named-field set, lift what's semantically universal as named invariants, leave what's `/charter`-specific in `/charter`'s scope. R11's ladder splits the same way: lifecycle entries are universal, status-aware-re-entry entries are parent-specific. This isn't fence-sitting — it is reading the seams the PRD already drew (PRD R9 universal; PRD R10's `decision_record_sub_shape` `/charter`-only by construction) and putting the lift line at the same seams. The pattern-level acceptance criteria stay portable for the universally-lifted fields; the parent-specific fields' acceptance criteria stay in the parent. D2's freeze line slots in cleanly: the minimum-required schema is part of the contract (D2 says it's contract); the parent-specific fields are implementation (D2 says they're implementation). Both D2 positions resolve. And there's a concrete cost we are paying under (a) that the dispatch flagged: forcing `/scope` to carry `decision_record_sub_shape: null` is a PRD R9 violation already — A is not just over-committed, it's internally inconsistent with the PRD it claims to ratify."

**Case against C** (from A's perspective). You introduce two reference files where one would do, and the "minimum-required + invariants" framing is itself a small design language the next author has to learn. That language has a maintenance cost: when a sixth requirement comes along, the next designer has to decide which bucket it belongs in (universal field, named invariant, or parent-specific). You have replaced "follow the schema" with "follow the schema, the invariants list, and the templated ladder body." Yes, the seams exist — but you have made them load-bearing. The brittleness of (a) is *predictable* brittleness (renames break things; we ban renames). Your brittleness (designers picking the wrong bucket for the wrong field) is *unpredictable*.

**Case against C** (from B's perspective). You have lifted the schema-detail framing the contract should be free of. Even the minimum-required set (`topic`, `last_updated`, `phase_pointer`, `exit`, `exit_artifacts`) commits to a storage shape — what if `/work-on`'s substrate keeps `last_updated` as a property of the workflow run, not a field in a YAML file? Your minimum-required-set framing forces the substrate to expose those fields by name, which is exactly the over-commitment we are trying to avoid. If you want a contract-level abstraction, abstract all the way; if you want a schema, ratify it. The middle is incoherent.

### Adjudication after the adversarial pass

Where the validators converge:
- **All three agree that R9's hard finalization check generalizes.** `exit:` field validation is a pattern-level concept regardless of framing — they only differ on whether to name the field.
- **All three agree that `decision_record_sub_shape` is `/charter`-specific** (this is consistent with the PRD: R8 names the sub-shapes within `/charter`'s exits; no other parent has them). A's strongest case requires this field be ratified verbatim, which the PRD itself does not support generalizing.

Where the genuine tension remains:
- **A's "predictable brittleness" critique of C is real but bounded.** "Pick the right bucket" is a designer judgment, but the rules ("universal fields are demonstrably needed by every concrete parent in scope") are testable when a new requirement arrives. The risk is bounded because there are only three concrete consumers and the next two are already named.
- **B's "schema commits storage shape" critique of C is real but mitigable.** D2 owns whether the storage shape itself is substitutable. If D2 says "yes — substrate is implementation", then C's minimum-required field set is interpreted as "the substrate exposes a record with these named fields, however the substrate stores them", and `/work-on`'s amplifier-layer substrate fulfills the contract by exposing `last_updated`-equivalent through whatever query interface the substrate has. The minimum-required set is *contract vocabulary*, not *storage layout*. C must be explicit on this point — and the synthesis below makes it explicit.

The adversarial pass strengthens C, weakens A by exposing the internal inconsistency with PRD R9's null-prohibition, and leaves B as a defensible-but-too-pure position that costs portability for ideological cleanness no concrete consumer asks for.

---

## Phase 6: Synthesis

<!-- decision:start id="state-schema-and-resume-ladder" status="assumed" -->

### Decision: Hybrid pattern — minimum-required schema with extension hooks, split resume-ladder

**Context.** The PRD for `/charter` provides a fully-specified concrete state-file schema (R10), a 9-entry resume ladder (R11), and a hard finalization check on `exit:` (R9). All three are tagged `[pattern-level]`. Downstream parents — `/scope` and the `/work-on` migration — will inherit whatever shape this design lands. Schema drift across parents is the primary failure mode the pattern-level tagging is trying to prevent: an author who knows one parent's state-file shape should be able to read another parent's wip/ state without re-learning. The decision is whether to ratify R9/R10/R11 verbatim, abstract them to a contract-level invariant set, or commit to a hybrid that lifts a minimum-required schema and names the rest as invariants. The decision couples to Decision 2 (substitution surface): if D2 says "schema is implementation" the answer leans hybrid/abstraction; if D2 says "schema is contract" the answer leans verbatim.

**Assumptions.**

- **A1 (Decision 2 dependence).** This decision assumes D2 will frame the substitution surface as "substrate-substitutable; the contract is named-field vocabulary plus named invariants; storage layout is implementation." If D2 says "schema layout is part of the contract" instead, the chosen Hybrid still works but its "minimum-required set is contract vocabulary" framing collapses into "minimum-required set is the contract." The chosen architecture is structurally robust to either D2 outcome.
- **A2 (parent shape divergence).** `/scope` and `/work-on` are assumed to land later, not co-authored. `/scope` is assumed structurally similar to `/charter` (parent-of-children, chain-shaped). `/work-on` is assumed substantially different (implementation loop, substrate-pivoting, possibly without a "chain of children" model). If `/scope` is co-authored, verbatim ratification (Alternative A) becomes safer; the hybrid still works but is conservatively scoped.
- **A3 (PRD `[pattern-level]` interpretation).** "Pattern-level" in PRD R9/R10/R11 is interpreted as "the relevant commitment should be lifted into shared scope," not "this exact field list is the contract." The hybrid honors the spirit (lifting commitments that generalize) without honoring the letter (lifting `/charter`-specific fields like `decision_record_sub_shape`). The PRD's own R9 prohibition on null/placeholder conditional fields supports this reading: `/scope` carrying `decision_record_sub_shape: null` would itself be a PRD R9 violation, so the PRD cannot intend `/scope` to carry that field.

**Chosen: Hybrid pattern — minimum-required pattern-level schema with extension hooks, plus a split resume-ladder template.**

The design commits to three pattern-level reference documents and one pattern-level statement.

**Pattern-level reference 1: `references/parent-skill-state-schema.md`.** Defines the minimum-required state-file field set every parent MUST include, with exact field names and types. The set is:

```yaml
topic: <topic-slug>                    # string matching the parent's slug constraint
last_updated: <ISO-8601 timestamp>     # set on every state-file write
phase_pointer: <phase-name>            # the parent's current phase as a string from the parent's phase enum
exit: <exit-outcome>                   # string from the parent's declared exit-outcome enum; UNSET while in progress, SET at finalization
exit_artifacts:                        # list of terminal artifacts the chain landed at
  - path: <artifact-path>
    status: <artifact-status>
```

These five fields are pattern-level **by name and by type**; parents MUST NOT rename them. Each parent declares its own `exit` enum in its SKILL.md (`/charter`'s is `{full-run, re-evaluation, abandonment-forced}`; `/scope`'s and `/work-on`'s enums are their own). The R9 hard finalization check is pattern-level: every parent MUST fail finalization if `exit:` is unset or not in the parent's declared enum. The schema file is YAML-with-`.md`-extension by core-layer convention (D2 owns whether this binding is substrate-substitutable; this design defers the substrate question to D2 and commits only to the *named-field vocabulary*).

**Pattern-level reference 2: `references/parent-skill-state-invariants.md`.** Defines four named invariants that govern fields beyond the minimum-required set:

1. **Per-feeder-artifact snapshot invariant.** Each parent that depends on feeder artifacts (existing docs the parent reads to decide its chain) MUST track per-feeder snapshots in a field named `feeder_snapshots` (top-level) or as a parent-specific extension below the minimum. Each snapshot entry MUST record `{path, status, content_hash}`. Drift detection MUST fire when *either* the live status differs from the snapshot's status OR the live content hash differs from the snapshot's hash (the dual-check rule from PRD R10/AC19 lifted as an invariant). The hash semantics (git blob hash today; substrate-specific equivalent under D2) are pattern-level; the field name and the parent's specific feeder artifacts are parent-specific.

2. **Conditional-field gating discipline.** Fields whose presence is gated by a specific `exit:` outcome value MUST be absent from the state file when their triggering condition does not hold. Parents MUST NOT set conditional fields to null, empty string, or placeholder value. This invariant lifts PRD R9's null-prohibition into pattern-level scope without committing to which conditional fields any specific parent has.

3. **Chain-tracking invariant (conditional).** Parents whose model is a chain of feeder/child invocations (e.g., `/charter`) MUST track `planned_chain` (list of children in scope), `chain_ran` (sub-list of completed children, in order), and `chain_skipped` (list of `{child, reason}` records for children skipped). Field names are pattern-level *for chain-shaped parents*; parents without a chain (`/work-on` if it lands as an implementation loop) are exempt from this invariant entirely. The pattern-level statement is "if your parent has a chain model, use these field names; if not, you have no chain-tracking obligation."

4. **Status-aware re-entry control.** When a parent's resume ladder detects a feeder artifact in a status that would trigger that artifact's own "offer to revise or start fresh" prompt on re-entry, the parent MUST decide upfront whether the re-entry path is a re-evaluation-equivalent exit (write a Decision-Record-equivalent; do not invoke the child) or a fresh chain (signal the child to suppress its status-aware re-entry). The parent's flow MUST NOT be hijacked by the child's resume-time prompt. The signaling mechanism is parent-specific; the *property* is pattern-level. This lifts PRD R11's status-aware-re-entry control as an invariant.

**Pattern-level reference 3: `references/parent-skill-resume-ladder-template.md`.** Defines the **universal meta-ladder** that every parent's resume ladder MUST include, with four pattern-level entries plus a templated body for parent-specific entries.

Universal meta-ladder (verbatim, top to bottom, first-match-wins):

```
state file malformed                                 → Error + offer Discard
state file has exit field set                        → Offer revise-equivalent / fresh based on exit outcome
state file exists, last_updated < <stale-threshold>  → Resume at recorded phase_pointer
state file exists, last_updated ≥ <stale-threshold>  → Offer Resume / Force-materialize / Discard
[parent-specific body: status-aware re-entry entries against feeder artifacts; partial-child-run resume entries]
On branch related to topic                           → Resume at Phase 1
On main or unrelated branch                          → Start at Phase 0
```

The stale-threshold is parent-declared (PRD R16 fixes `/charter`'s at 7 days; other parents may differ). The malformed-state-file handling is pattern-level: parents MUST surface a clear error naming the malformation and MUST offer Discard as a recovery path; ladders MUST NOT silently fall through to Phase 0 (PRD R11/AC20c lifted verbatim).

Parent-specific body: each parent authors entries against feeder-artifact statuses and partial-child wip/ artifacts following the template's slot structure. The template specifies the *required slots* (one entry per feeder artifact status that triggers a status-aware re-entry; one entry per child whose partial-state wip/ artifact triggers a resume) and the *prompt-vocabulary control* (each entry MUST name the parent's prompt vocabulary, e.g., `/charter`'s Re-evaluate/Revise/Bail).

**Pattern-level statement.** "The minimum-required schema is pattern-level: every parent uses these five fields by name. Named invariants govern fields beyond the minimum and the structure of the resume ladder. Parent-specific schema extensions and ladder body entries are each parent's call against the invariants." This statement is the contract surface a reader of Phase 4's Solution Architecture writes code against.

**Rationale.**

- **Honors the PRD's pattern-level intent without forcing PRD-internal contradictions onto downstream parents.** PRD R9's null-prohibition on conditional fields would itself be violated if `/scope` carried `decision_record_sub_shape: null`. The PRD cannot intend verbatim ratification; the hybrid resolves the contradiction.
- **Preserves portability of universal acceptance criteria.** AC15 ("a run that completes without recording a valid `exit:` fails finalization") and AC20c (malformed state file is a hard surface, not silent fall-through) become pattern-level acceptance criteria portable to every parent. AC19 (dual-check drift detection) becomes a pattern-level invariant.
- **Accommodates the next two parents.** `/scope` (chain-shaped, structurally similar to `/charter`) inherits the minimum-required schema, the universal meta-ladder, the chain-tracking invariant, and the status-aware-re-entry control. `/work-on` (implementation loop, possibly substrate-pivoting) inherits the minimum-required schema (with its own enum), the universal meta-ladder, and the invariants that apply to it (not chain-tracking, if its model is not a chain).
- **Compatible with both Decision 2 framings.** If D2 says "schema layout is implementation, substrate is substitutable", the minimum-required set is contract vocabulary the substrate exposes (however internally stored). If D2 says "schema layout is contract, substrate is the wip/-based reference implementation", the minimum-required set is part of the contract layout. Both readings work.
- **Drift-prevention strength is preserved where it matters.** The five universally-named fields can't be renamed; the four named invariants enforce a shared mental model for fields beyond the minimum. The drift the PRD was trying to prevent (different field names for the same concept across parents) is prevented at the five-field core where every parent has the same concept anyway.

**Alternatives Considered.**

- **Alternative A — Verbatim ratification.** The PRD's R10 schema is lifted in full as the pattern-level schema; every parent uses every R10 field by name; field renames are forbidden. **Rejected because** the PRD's own R9 prohibition on null/placeholder conditional fields makes verbatim ratification internally inconsistent: `/scope` cannot reasonably carry `decision_record_sub_shape`, `discard_commit_sha`, or `rejection_rationale` (all `/charter`-specific by construction in R8), and setting them to null violates R9. Verbatim ratification over-commits the next two parents to `/charter`'s chain model and creates the exact failure mode (forced placeholders) the PRD explicitly forbids.

- **Alternative B — Pure invariant abstraction.** No fields lifted by name; only invariants named (every parent tracks topic identity, last-touched, phase, outcome, terminal-artifact, feeder snapshots — by whatever field names the parent chooses). **Rejected because** the cost (every acceptance criterion becomes per-parent; AC15 cannot be authored once and inherited) buys flexibility (rename-the-field) that no concrete consumer is asking for. The drift-prevention surface degrades to zero on the universal fields. Vocabulary drift across state files breaks audit trails for reviewers reading multiple parents' state. The pure-invariants framing is internally coherent but mismatches the concrete need: every concrete consumer wants the same five fields, by the same names, and only the field names beyond that vary.

**Consequences.**

- **Pattern-level scope grows.** Three reference documents (`references/parent-skill-state-schema.md`, `references/parent-skill-state-invariants.md`, `references/parent-skill-resume-ladder-template.md`) ship as pattern-level. Each is short (the schema file ~5 fields + R9 spec; the invariants file ~4 named invariants; the ladder template ~5 universal entries + slot structure). Implementation cost is bounded.
- **`/charter`'s SKILL.md cites pattern-level references.** `/charter`'s state-file schema declaration adds the five minimum-required fields by reference and lists its parent-specific extensions (`chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`, `decision_record_sub_shape`, `referenced_strategy`, `discard_commit_sha`, `rejection_rationale`, `triggering_child`, `partial_phase_reached`). The R10 schema as currently drafted in `/charter`'s PRD is restructured but not contractually weakened — every field stays; only the lift line changes.
- **`/charter`'s acceptance criteria become reusable.** AC15, AC17, AC20c become pattern-level criteria each future parent's eval set inherits (per R18). AC18, AC19, AC20 become criteria with pattern-level scaffolding and parent-specific bindings (the prompt vocabulary in AC18 is parent-specific; the dual-check rule in AC19 is pattern-level). AC11a, AC11b, AC12, AC13, AC14 (exit-specific) stay `/charter`-specific.
- **Drift detection cost is one design-judgment call per new requirement.** When a future requirement arrives, the designer must decide: universally-needed field (lift by name)? generalizable semantic (lift as invariant)? parent-specific (no lift)? This is a real but bounded judgment cost. The three-bucket framing makes the judgment explicit rather than implicit.
- **Eval coverage of pattern-level behavior is sharper.** R18 pattern-level evals (slug rejection, malformed-state-file handling, child-internals isolation, visibility default) now cover the universally-named-field behaviors. Per-parent eval sets cover the parent-specific schema extensions and ladder body entries.
- **Future-amplifier-layer migration is mechanical.** When the workflow-substrate substitution lands (per D2), the amplifier layer's substrate exposes the five minimum-required fields by name (through whatever query interface). The named invariants (snapshot dual-check, conditional-field gating, status-aware-re-entry control) remain semantically equivalent regardless of substrate. Parents migrate by swapping the substrate; the contract surface is unchanged.

<!-- decision:end -->

---

## Phase 6 housekeeping

**Status.** `assumed` (per `references/decision-block-format.md` threshold and decision skill Phase 6.4): three explicit assumptions (A1 D2-coupling, A2 parent-shape divergence, A3 PRD-intent interpretation) inform the decision; the choice was made in `--auto` mode without user confirmation; the chosen architecture is robust to either D2 outcome but the framing language hinges on A1.

**Confidence.** High that the hybrid is the right framing; medium-high that the specific minimum-required field set (5 fields) is the right cut. Phase 3 cross-validation against D2's framing may surface either a wider universal set (if D2 commits more to the schema-as-contract reading) or a narrower one (if D2 commits more to the substrate-is-implementation reading). Either revision is mechanical against this report's structure.

**Intermediate-artifact cleanup.** Per SE4 §12 (wip/ persists as durable evidence) this report does not delete intermediate artifacts — there are none separate from this single report file. The Phase-0 context, Phase-1 research, Phase-2 alternatives, and adversarial pass are all inlined above.

---

## Structured result (for return to coordinator)

```yaml
decision_result:
  status: COMPLETE
  decision_id: 3
  chosen: "Hybrid pattern — minimum-required pattern-level schema with extension hooks, plus split resume-ladder template"
  confidence: "high"
  rationale: |
    Honors PRD pattern-level intent without forcing PRD-internal contradictions
    (Alternative A would require null/placeholder conditional fields the PRD's R9
    explicitly forbids). Preserves portability of universal acceptance criteria
    (AC15, AC20c, AC19's dual-check rule) while leaving /charter-specific fields
    (decision_record_sub_shape, chain-related fields) in /charter's scope.
    Compatible with both Decision 2 framings of the substitution surface.
  assumptions:
    - "A1: Decision 2 frames substitution surface as 'substrate-substitutable; contract is named-field vocabulary plus named invariants.' Hybrid is structurally robust to either D2 outcome; framing language hinges on A1."
    - "A2: /scope and /work-on land later (not co-authored). /scope is chain-shaped (structurally similar to /charter); /work-on is an implementation loop, possibly substrate-pivoting."
    - "A3: PRD '[pattern-level]' tag means 'the relevant commitment should be lifted into shared scope', not 'this exact field list is the contract'. PRD R9's null-prohibition on conditional fields supports this reading."
  rejected:
    - name: "A: Verbatim ratification"
      reason: "Internally inconsistent with PRD R9's null-prohibition. /scope and /work-on cannot reasonably carry /charter-specific conditional fields (decision_record_sub_shape, discard_commit_sha, etc.); setting them to null violates R9. Over-commits next two parents to /charter's chain model."
    - name: "B: Pure invariant abstraction"
      reason: "Loses portability of universal acceptance criteria (AC15 must be re-authored per parent) and degrades drift-prevention on the universal fields to zero. Buys rename-the-field flexibility no concrete consumer asks for. Internally coherent but mismatches concrete need."
  commitments:
    pattern_level_references:
      - "references/parent-skill-state-schema.md (minimum-required 5-field set + R9 finalization check spec)"
      - "references/parent-skill-state-invariants.md (4 named invariants: feeder-snapshot dual-check, conditional-field gating, chain-tracking, status-aware-re-entry control)"
      - "references/parent-skill-resume-ladder-template.md (universal meta-ladder + templated body slots)"
    minimum_required_fields:
      - "topic: string"
      - "last_updated: ISO-8601 timestamp"
      - "phase_pointer: parent-phase-enum string"
      - "exit: parent-exit-enum string (UNSET in progress, SET at finalization)"
      - "exit_artifacts: list of {path, status}"
    pattern_level_invariants:
      - "Per-feeder-artifact snapshot with status-AND-content-hash dual-check drift detection"
      - "Conditional-field gating discipline (absent when condition does not hold; never null/empty/placeholder)"
      - "Chain-tracking (conditional: only for chain-shaped parents; field names planned_chain, chain_ran, chain_skipped)"
      - "Status-aware re-entry control (parent decides upfront; flow never hijacked by child's resume prompt)"
    universal_meta_ladder_entries:
      - "1. state file malformed → Error + offer Discard"
      - "2. state file has exit field set → Offer revise-equivalent / fresh based on exit outcome"
      - "3. state file exists, last_updated < <stale-threshold> → Resume at recorded phase_pointer"
      - "4. state file exists, last_updated ≥ <stale-threshold> → Offer Resume / Force-materialize / Discard"
      - "[parent-specific body slots]"
      - "8. On branch related to topic → Resume at Phase 1"
      - "9. On main or unrelated branch → Start at Phase 0"
  coupling_notes:
    - "Decision 2 (substitution surface) outcome affects framing language but not structural choice. If D2 says 'schema layout is contract', the 5-field minimum is part of contract layout; if D2 says 'substrate is substitutable', the 5-field minimum is contract vocabulary the substrate exposes."
    - "Decision 4 (R12/R13/R14/R17a/R18 ratification) consumes this decision's per-feeder-snapshot invariant for R13 manual-fallback support."
  report_file: "wip/research/design_shirabe-progression-authoring_decision_3_report.md"
```
