# Decision 2 Report — Substitution-Variable Contract Surface (core-layer vs amplifier-layer) and Cross-Branch Boundary

Decision researcher: `decision-researcher-2`
Decision tier: **Critical (Tier 4)** — walked inline per SE4 §8 (no nested validator team)
Phases walked: 0, 1, 2, inline adversarial pass, 6
Date: 2026-05-24

---

## Phase 0 — Context

### Decision question

What is the substitution-variable contract surface between the core-layer (wip/-based) implementation and the future amplifier-layer (workflow-substrate) implementation, including the cross-branch state-file boundary?

Two coupled sub-questions:

- **(a)** Which parts of the parent-skill contract are *storage-agnostic invariants* that must hold across both substrates, vs. *storage-specific* details that substitute as the substrate changes.
- **(b)** Where the cross-branch limitation lives in the contract. Is cross-branch resume an **invariant the amplifier layer MUST preserve** (i.e., v1 names branch-coupling as a wip/-specific limitation, not a contract property), or a **wip/-specific limitation acceptable for v1** (i.e., v1 contract says "resume is branch-scoped; cross-branch out-of-scope and added later by either substrate")?

The coupling is real: the substitution surface IS where cross-branch lives, because cross-branch is purely a property of *where state is stored and how it is keyed* — which is exactly what the substitution variable governs.

### Constraints

- **C1.** The core-layer must ship today against current shirabe patterns: `wip/`-based intermediate storage committed to feature branches, deleted by the wip-hygiene rule before merge, branch-coupled. `/charter` is the concrete v1 consumer.
- **C2.** The amplifier-layer substrate is **not bounded yet**. Whatever substrate the `/work-on` migration lives in is outside this design's shipping scope. The contract MUST NOT foreclose plausible substrates: cloud-backed context stores (koto-style), session-scoped state, multi-leader coordination primitives, transactional state writes.
- **C3.** PRD R10's state schema is fully concrete (named YAML fields: `chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, `child_snapshots`, conditional fields). Decision 2 must say whether the *schema* is contract-level or implementation-level. Decision 3 takes a parallel question one layer down; Phase 3 cross-validation will check for coupling.
- **C4.** Storage-agnostic ≠ semantics-agnostic. Whatever the contract commits to, parents inherit the *semantics*. "Parents MUST record an exit outcome before terminating" is semantics; "exit outcome lives in a YAML field at a specific wip/ path" is implementation. The driver is to draw the line crisply.
- **C5.** The wip-hygiene rule is workspace-wide (workspace `CLAUDE.md` §"The wip-hygiene rule"): wip/ files are non-durable, must not be referenced from committed artifacts, must be removed before merge. This makes wip/-based state inherently ephemeral — it cannot survive a squash-merge, so any cross-branch behavior on top of wip/ is fundamentally impossible without changing storage.
- **C6.** Critical-tier mis-draw is irreversible without redesign:
  - **Over-commit** (lock contract to current wip/ semantics) → forecloses amplifier-layer capabilities.
  - **Under-commit** (abstract beyond verification) → downstream parents have no concrete shape to inherit; pattern fragments.

### Known options (from question framing)

The framing presents two axes that compose into four logical positions. Concrete viable alternatives are derived in Phase 2.

### Background

Authoritative inputs reviewed:
- `docs/designs/DESIGN-shirabe-progression-authoring.md` — design skeleton, "Decision Drivers" §2 (dual-implementation), §4 (cross-branch), §6 (team persistence), Open Questions
- `docs/prds/PRD-shirabe-charter-skill.md` — R9 (finalization check), R10 (concrete schema), R11 (resume ladder), §"Questions Deferred to Design" Q2 + Q4, §"Known Limitations" (state file branch-coupled)
- `public/shirabe/CLAUDE.md` §"Intermediate Storage" — wip/ vs koto-context distinction the workspace already articulates: koto provides cloud-backed storage with the same review and traceability properties; non-koto workflows use wip/
- Workspace `CLAUDE.md` §"The wip-hygiene rule" — cleanup-before-merge, no-orphan-references, workspace-wide

The shirabe CLAUDE.md already names a *concrete* alternative substrate: **koto context** (`koto context add`). This is not a hypothetical — it is a substrate that already exists in the workspace, has explicit storage properties (cloud-backed, reviewable, traceable, branch-independent), and is named as the replacement for wip/ in koto-driven workflows. This grounds the amplifier-layer in something real rather than purely speculative, which raises the bar on "must not foreclose": there is a *specific* substrate the design must accommodate, not just "anything plausible."

### Complexity

**Critical (Tier 4).** Phases 0, 1, 2, inline adversarial reasoning, 6.

---

## Phase 1 — Research

### Critical unknowns

The unknowns that change the outcome if answered differently:

- **U1.** Does the amplifier-layer substrate (koto-context or successor) support **branch-independent state lookup keyed by topic slug**? If yes, the cross-branch limitation is purely wip/-specific. If no (e.g., koto context is itself session-scoped or branch-scoped in some other way), then the cross-branch property cannot be a generic invariant and the contract should not promise it.
- **U2.** Does the amplifier-layer substrate support **transactional state writes** (atomic updates of multiple fields)? wip/ writes are inherently non-transactional (writing a YAML file is read-modify-write with no locking). If the amplifier substrate supports transactions, naming the schema as contract-level could prevent downstream parents from using transactional semantics.
- **U3.** Does the amplifier-layer substrate support **structured field updates** (e.g., "append to chain_ran") vs. **whole-document replace**? wip/ is whole-document. If the amplifier supports field-level, naming the schema as a YAML *file* over-commits to whole-document semantics.
- **U4.** Is `child_snapshots`-style frontmatter+git-blob-hash drift detection **storage-agnostic**, or does it bind to git-as-substrate? If a future amplifier-layer parent resolves children that are NOT committed git artifacts (e.g., a koto-context-only intermediate), the git-blob-hash comparison falls apart.

### Findings

**F1. wip-hygiene makes wip/ structurally incompatible with cross-branch.**
Workspace `CLAUDE.md` is unambiguous: wip/ files are removed before merge. After a child PR merges to main, the wip/ state file is gone from main's tree. Resuming `/charter` on main to invoke the next child cannot read the state file because it no longer exists in any reachable git tree. **Cross-branch resume cannot be added to wip/ as an enhancement; it is structurally precluded.** This means any "the amplifier layer might add cross-branch later to wip/" framing is incoherent — the resolution path is necessarily a substrate change, not a feature addition.

**F2. koto-context is the named alternative and is already branch-independent in the workspace's framing.**
`public/shirabe/CLAUDE.md` §"Intermediate Storage" calls koto context "cloud-backed storage for workflow context with the same review and traceability properties, removing the need to pollute git history with intermediates." Cloud-backed implies branch-independent lookup is at least *possible*. Whether koto-context today actually supports cross-branch resume against the same topic is an implementation question for the koto skill, but the substrate's storage shape makes it plausible. **The amplifier-layer is concrete enough to design against, not purely hypothetical.**

**F3. PRD R10's schema mixes three altitude levels.**
Looking at the field list (`chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, `child_snapshots`, conditional fields), three altitudes are interleaved:

- **Semantic invariants** (what the parent must *know*): "a chain has a planned sequence of children", "a chain records which children ran", "a chain has an exit outcome", "a chain records snapshots of child docs to detect drift". These are storage-agnostic — they describe *what state the parent maintains*, not *how*.
- **Concrete schema** (how the state is named): YAML field names like `chain_ran`, `exit`. These bind the parent to a specific serialization.
- **Storage binding** (where the state lives): `wip/<parent>_<topic>_state.md`. This binds to the wip/ substrate.

The PRD does not separate these. The design must.

**F4. The drift-detection mechanism is two-layer.**
R10's `child_snapshots` block records `{path, status, content_hash}`. Two things are happening:
- (Semantic) "Parent records child-doc identity sufficient to detect out-of-chain edits."
- (Implementation) "Identity is `path + frontmatter status + git blob hash`."

The semantic layer is substrate-independent — a future parent could record "child koto-context-entry ID + content-hash" instead of "path + git blob hash" without changing what the contract *guarantees*. This suggests the contract should name the **semantic capability** (drift detection on child docs) and let the implementation pick the identity mechanism.

**F5. The resume ladder's ordering is partially semantic, partially substrate-bound.**
R11's ladder (state file → child doc snapshots → child wip artifacts → branch context) mixes:
- **Semantic ordering** (first match wins, most-specific-state first): substrate-agnostic.
- **Substrate-specific sources** (`wip/<child>_<topic>_*.md` files, "on branch related to topic"): wip/-bound. A koto-context-backed parent would replace these with substrate-equivalents (koto-context-entry lookup, session-scope check) but the ordering principle holds.

**F6. The single-team-per-leader constraint is orthogonal to substrate.**
Decision 5 covers TeamCreate. For Decision 2, the relevant observation is: substrate choice doesn't change the team-creation primitive. Both wip/-based and koto-context-based parents are bounded by the same Claude Code TeamCreate constraint. This is not a substitution surface — it's a Claude Code primitive constraint, not a substrate property.

### Assumptions made (non-interactive mode)

Documented for the `assumptions` field of the final result:

- **A1.** The amplifier-layer substrate (koto-context or successor) will support *some* form of state persistence keyed by a stable topic identifier — i.e., at least the semantic "I can look up the chain's state given the topic" works. **If wrong:** the contract's "state-by-topic" invariant cannot be promised; the design would have to scope the invariant to "state-by-(topic, scope)" where scope is substrate-defined.
- **A2.** The amplifier-layer will provide *equivalent or stronger* properties for the wip-substrate properties the v1 contract relies on (drift detection on children, resume from partial state, audit trail). It will not regress on these. **If wrong:** the contract names them as invariants that the substrate then violates — a forecloseure direction the question warned against.
- **A3.** koto-context, the named alternative substrate, is not branch-coupled in the sense wip/ is. It may have its own coupling properties (session scope, workspace scope) but not the "deleted-on-squash-merge" property that makes wip/ structurally branch-coupled. **If wrong:** cross-branch is not a wip/-specific limitation but a more general substrate limitation, and the contract should reflect that.
- **A4.** Future parents (`/scope`, `/work-on`) will need to *interoperate* with `/charter` artifacts (read the STRATEGY a `/charter` chain produced, etc.), so the **durable artifact contract** (where children land their durable outputs in `docs/`) is shared infrastructure regardless of substrate. **If wrong:** parents could have isolated artifact namespaces, but this would break the multi-parent storyline the design is committing to.

---

## Phase 2 — Alternatives

Five viable alternatives identified, capping at the skill's limit. They span the two-axis space (contract abstraction level × cross-branch framing):

### Alternative A — "Lock the schema, name wip/ as the implementation, treat cross-branch as a wip/-substrate-specific limitation the amplifier layer will fix"

The pattern-level contract ratifies PRD R10's schema verbatim (every parent uses `chain_started`, `planned_chain`, `chain_ran`, `exit`, etc., with parent-specific extensions on top). The schema IS the contract. The storage location (`wip/<parent>_<topic>_state.md`) is named as the v1 implementation. Cross-branch resume is named as a known wip/-substrate limitation. The contract says: "The amplifier-layer substrate, when it lands, MUST preserve the schema and MUST support cross-branch resume on top of it."

**Substitution surface:** storage location only. Schema is invariant.

### Alternative B — "Two-layer contract: semantic invariants + reference schema, with wip/ as the implementation"

The pattern-level contract names **semantic invariants** (parent records chain plan, ran children, exit outcome, child-doc drift detection, audit trail). PRD R10's schema is named as the **reference implementation** for v1 — every core-layer parent uses it verbatim — but it is not the contract; the invariants are. The amplifier-layer substrate can substitute a different concrete schema (e.g., koto-context entries with different field names, structured updates) as long as the semantic invariants hold. Cross-branch resume is named as a wip/-substrate limitation that the amplifier-layer substrate is expected to resolve, but it is not an invariant the v1 contract promises across substrates.

**Substitution surface:** storage location + concrete schema fields + serialization format. Semantic invariants are the freeze line.

### Alternative C — "Two-layer contract + cross-branch-as-invariant"

Same two-layer structure as B (semantic invariants + reference schema), but cross-branch resume is named as a **semantic invariant** that the amplifier-layer substrate MUST satisfy. The v1 core-layer implementation explicitly does not satisfy this invariant — it is an acknowledged limitation of the wip/ substrate. The contract is forward-looking: "branch-coupling is not a contract property; the v1 substrate fails to meet a contract invariant and the amplifier layer is the resolution surface."

**Substitution surface:** same as B, plus cross-branch is named as a future-required invariant rather than a future-optional capability.

### Alternative D — "Pure invariant contract (no reference schema), parents own their state shape"

The pattern-level contract names only semantic invariants. There is no reference schema; PRD R10's schema is purely a `/charter`-specific implementation detail. Other parents (`/scope`, `/work-on`) author their own state shapes from scratch as long as they satisfy the invariants. Cross-branch resume is named as a substrate-specific property each parent decides for itself.

**Substitution surface:** essentially everything except the semantic invariants. Parents have maximum freedom.

### Alternative E — "Lock the schema, treat cross-branch as out-of-scope-forever"

The schema is the contract (same as A). But cross-branch resume is named as **architecturally out of scope** for the parent-skill pattern — the contract explicitly does not promise it on any substrate. If cross-branch behavior is ever needed, it is a *new pattern*, not an extension of this one.

**Substitution surface:** storage location only (same as A). Cross-branch is not a substitution variable at all.

---

## Inline Adversarial Pass (replaces Phases 3/4/5 per SE4 §8)

For each of the five alternatives, I write a steelman case from the perspective of an advocate, then a case-against from the perspective of a peer who picked a different alternative. This adversarial pass is the closest available substitute for the bakeoff/revision/cross-examination phases without a persistent validator team.

### A — Lock the schema; cross-branch is wip/-specific, amplifier-layer fixes

**Steelman case (advocated by an A-defender).**
The PRD has done the hard work. R10's schema is fully specified, every field has a purpose, the conditional fields encode the exit-shape semantics cleanly. Ratifying it pattern-level means every parent inherits a verified concrete shape; the design's job is to *commit*, not to re-derive abstractions for hypothetical substrates. Critically, locking the schema makes downstream parents' lives easier: `/scope` and `/work-on` open `/charter`'s SKILL.md, see the schema, and use it directly. Abstraction without need is over-engineering. On cross-branch: the wip-hygiene rule (workspace `CLAUDE.md`) literally cleans up wip/ before merge — so the wip/ substrate cannot support cross-branch, full stop. Saying "this is a wip/-specific limitation the amplifier layer will fix" is honest and concrete. The amplifier layer (koto-context) already exists in the workspace's framing; the path to resolution is real.

**Case against (from a B-defender's perspective).**
A conflates the *what* (parent maintains chain state) with the *how* (a YAML file with these named fields). The schema's field names are an artifact of one substrate's properties — wip/ is a whole-document YAML store, so the schema looks like a whole-document YAML. A koto-context-backed parent might prefer structured updates (e.g., append-to-list semantics for `chain_ran`) that no longer look like a YAML document. Forcing the future parent to *look like* a YAML document in a context store is over-committing — the amplifier layer's value proposition includes shape changes the contract should not pre-foreclose. On cross-branch: A's framing is correct that wip/ structurally fails it, but A *also* says the schema is locked and the amplifier layer must preserve it. If the amplifier layer must preserve the YAML-schema *shape* AND also add cross-branch, then we have committed to "future parents must store cross-branch-resumable YAML documents keyed by topic" — which is a much narrower forecloseure than just "future parents must support cross-branch resume." Decoupling the two (cross-branch as invariant, schema as reference) is cleaner.

### B — Two-layer contract: semantic invariants + reference schema, wip/ is v1 impl

**Steelman case (advocated by a B-defender).**
B draws the line where the language already separates it. The PRD describes both *what state must exist* (semantics) and *what fields name it* (implementation), but doesn't separate them. The design's contribution is to do that separation explicitly. The semantic invariants — "parent records chain plan, ran children, exit outcome, child-doc drift" — are exactly the load-bearing claims; they are what makes the pattern coherent across parents. The concrete schema is useful as a starting point but should not be the contract. This matches the workspace's existing language: shirabe's CLAUDE.md already distinguishes "non-koto workflows use wip/" from "koto-driven workflows use koto context" — the workspace itself treats storage substrate as a substitution variable. The design just names the line. Naming the schema as "reference implementation for v1" gives downstream parents a concrete starting point (they can copy `/charter`'s schema as long as it satisfies the invariants) without forcing them to inherit it. On cross-branch: B treats cross-branch as an *expected* property the amplifier layer will deliver, not as an invariant. This is honest: the amplifier substrate is not bounded yet, so promising cross-branch as an invariant the substrate MUST satisfy is over-claiming. Naming it as "expected but not required" leaves space for the amplifier substrate to deliver it in a way the design didn't anticipate.

**Case against (from a C-defender's perspective).**
B's framing of cross-branch as "expected but not contract-invariant" is the worst of both worlds. If it's not an invariant, the amplifier-layer substrate could legitimately ship without cross-branch and still claim contract compliance — at which point the substrate work hasn't actually resolved the limitation the design is supposed to expose. Cross-branch resume is exactly the kind of property that needs to be in the contract precisely so the amplifier-layer work has a forcing function. Without that, the amplifier substrate might focus on other capabilities (parallel team coordination, transactional writes) and leave cross-branch unresolved — and the v1 design has no mechanism to surface that as a regression. C fixes this by naming cross-branch as an invariant that v1 acknowledges it does not satisfy. That asymmetry is the whole point: the contract describes the parent-skill *pattern*, and the pattern wants cross-branch; the v1 *implementation* fails the pattern in this specific way. That's not over-claiming — that's how invariants-with-known-violations work in spec writing.

**Case against (from an A-defender's perspective).**
B's invariant-vs-implementation split sounds clean but is hard to verify. How does a reviewer check that a future parent's schema "satisfies the invariants"? The invariants are prose ("parent records the chain plan"), and verification requires reading the parent's schema and judging compliance. Locking the schema (A) makes verification trivial: "does the parent's state file match R10's schema?" is a grep. B is buying flexibility no one has asked for at the cost of verifiability. The amplifier-layer substrate is one substrate. If/when it lands and needs a different schema, *that's* the time to abstract — not now, when there's exactly one consumer and no concrete demand for shape variance.

### C — Two-layer contract + cross-branch-as-invariant

**Steelman case (advocated by a C-defender).**
C is B with a sharper edge on cross-branch. The design's stated purpose is to expose limitations explicitly rather than paper them over. The wip-hygiene rule structurally precludes cross-branch on the v1 substrate — this is a real architectural property of the v1 implementation. Naming cross-branch as a contract invariant that v1 fails to satisfy is the most honest framing: "the pattern wants this; v1 cannot deliver it; the amplifier layer is the resolution surface." This gives the amplifier-layer work a forcing function (it MUST satisfy cross-branch) and gives reviewers a clear regression signal (if the amplifier ships without cross-branch, the implementation is incomplete relative to the contract). It also pre-justifies the amplifier-layer's existence — the v1 design itself names the gap rather than discovering it later.

**Case against (from a B-defender's perspective).**
C makes a strong claim about a substrate we don't yet have. We don't actually know that cross-branch is technically achievable on the amplifier-layer substrate — koto-context is named as cloud-backed, which is necessary but not sufficient. (It could be cloud-backed and still session-scoped, for example.) Promising cross-branch as an invariant before we've verified the substrate can deliver it risks a forecloseure direction: the amplifier-layer team may land on a substrate that *doesn't* support cross-branch, and now we're stuck either retroactively weakening the contract or rejecting the amplifier-layer work for failing to satisfy an aspirational invariant. The honest framing is B's — name cross-branch as a wip/-specific limitation the amplifier-layer is *expected* to resolve, without promising the resolution is possible until we've checked. C is "designing on optimism" about substrate capabilities.

**Case against (from a D-defender's perspective).**
C and B both lock cross-branch's shape — they assume "cross-branch resume" is even the right framing. Maybe future parents don't need cross-branch *per se* but need a different property (e.g., "state survives squash-merge" or "state is workspace-scoped"). Naming "cross-branch" as the invariant binds the contract to git-as-substrate just like A does in a different way. D's framing — each parent owns its substrate choice — sidesteps this entirely.

### D — Pure invariant contract (no reference schema)

**Steelman case (advocated by a D-defender).**
D is the most honest about what we know and don't know. There's exactly one concrete parent (`/charter`); the other two (`/scope`, `/work-on`) are unbounded. We can write the load-bearing invariants — every parent records chain progress, every parent records an exit outcome, every parent supports drift detection on children, every parent has a resume contract — without committing to a single concrete schema. This gives `/scope` (which may have very different child semantics) and `/work-on` (which is migrating to a different substrate entirely) maximum freedom to author schemas that match their semantics. The schema in R10 is fine for `/charter`; it doesn't need to be the schema for `/work-on` running in a workflow-substrate context.

**Case against (from an A-defender's perspective).**
D's "freedom" is fragmentation. If every parent owns its state shape, then a future shared tool that wants to inspect parent-skill state (a workspace-wide audit tool, a status query, a debugging aid) has to special-case each parent. The whole *value* of the parent-skill pattern is shared shape — that's why the PRD tagged R10 as `[pattern-level]`. D takes the value out of the pattern. Also, D leaves verification entirely up to prose-judgment: nothing in D would catch a parent that satisfied the *letter* of the invariants ("records exit outcome") but in a way no other parent could read.

**Case against (from a B-defender's perspective).**
D throws out the reference schema entirely, which is overkill. B keeps the reference schema as a starting point — parents *should* use R10's schema unless they have a substrate-driven reason to deviate. B gets D's flexibility (substitutability when needed) without D's fragmentation cost (every parent starts from scratch). D is the right answer if we believe the parents will diverge substantially; B is the right answer if we believe they'll converge by default with substitution as the escape hatch. Given that all three parents share the same domain (skill-progression authoring), convergence-by-default is the better prior.

### E — Lock the schema; cross-branch out-of-scope-forever

**Steelman case (advocated by an E-defender).**
E is honest about what the parent-skill pattern is for. The pattern is "walk an author through a chain of children in a single working session." Cross-branch resume is a different feature — "resume a parent across multi-PR child-shipping flows" — and may not actually belong in the same pattern. By naming cross-branch as out-of-scope-forever, E forces the question to be asked explicitly when a future feature needs it: "do we need a new pattern, or extend this one?" That's a healthier design conversation than letting cross-branch creep in as an enhancement to a pattern that wasn't designed for it. E also avoids the temptation to *design* for cross-branch in v1 (e.g., choosing schema field names that hint at cross-branch semantics) when we shouldn't be.

**Case against (from a C-defender's perspective).**
E's "out-of-scope-forever" claim is fragile because the amplifier-layer work is *named* in the PRD as the resolution surface for cross-branch (PRD §"Questions Deferred to Design" Q4, and design Driver 4). The design literally cites cross-branch as a thing the amplifier-layer might fix. Saying "out-of-scope-forever" contradicts the design's own framing of the amplifier-layer. E essentially says "we don't care about this even though we've been talking about it as a thing the amplifier-layer addresses." That's incoherent given the rest of the design. C's framing (invariant the amplifier MUST satisfy) is the natural fit for what the design has already committed to elsewhere.

**Case against (from a B-defender's perspective).**
E shares A's over-locking on the schema side and adds a new over-commitment on the cross-branch side. We don't have enough information about the amplifier-layer substrate to declare cross-branch out of scope forever — it might be a natural property the substrate delivers for free (cloud-backed key-value with topic-keyed lookup is *inherently* branch-independent), in which case E is over-restricting for no benefit.

---

## Adversarial pass summary

After running steelmans and cases-against:

- **A is verifiable but over-commits the schema.** It treats the schema as the contract, which forecloses substrate-driven shape changes. The case-against from a B-defender lands.
- **B is the natural fit for the design's stated framing.** It separates semantic invariants from reference implementation, matches the workspace's existing wip/-vs-koto-context language, and gives `/scope` and `/work-on` room to maneuver. The strongest case-against (from C) is on cross-branch: B's "expected but not invariant" leaves the amplifier-layer too much room to skip cross-branch.
- **C is B + a sharper cross-branch invariant.** It gets credit for honesty about the gap and giving the amplifier layer a forcing function, but the case-against (from B) lands: we don't yet know the amplifier-layer substrate can deliver cross-branch, so naming it as an invariant is designing on optimism. The case-against from D (binding to "cross-branch" framing pre-commits to git-as-substrate) is a weaker challenge but worth noting.
- **D over-corrects.** It throws out the reference schema entirely, which fragments the pattern and removes the verifiability the PRD's `[pattern-level]` tagging was designed to provide. The case-against from B lands cleanly.
- **E is internally incoherent.** "Cross-branch out-of-scope-forever" contradicts the design's own framing of the amplifier-layer as the resolution surface. The case-against from C lands.

**The tightest contest is between B and C.** Both share the two-layer structure (semantic invariants + reference schema), differing only on cross-branch framing. The deciding question is: do we have enough confidence in the amplifier-layer substrate's capabilities to name cross-branch as an invariant it MUST satisfy?

- Naming cross-branch as an invariant (C) is a strong forcing function: it tells the amplifier-layer team "cross-branch is part of the pattern's contract; you cannot ship without satisfying it." But it presumes capabilities we haven't verified (A3 in assumptions).
- Naming cross-branch as a wip/-specific limitation with expected-but-not-required resolution (B) is honest about uncertainty but weakens the design's forcing function on the amplifier-layer work.

The right framing depends on how strongly we want the design to assert what the amplifier-layer is *for*. The design skeleton's Open Questions section already names "amplifier-layer workflow substrate is the expected resolution surface" for the team-persistence question (Decision 5 territory). Applying the same framing to cross-branch is consistent: the amplifier layer is the expected resolution for both gaps. C makes that consistency explicit; B leaves it implicit.

**Resolution.** Choose C with one caveat: name cross-branch as an invariant the **pattern asserts** (not the substrate technically guarantees), so the v1 implementation can honestly say "v1 does not satisfy this invariant; the wip/ substrate structurally cannot, and the amplifier-layer substrate is the resolution surface." This phrasing handles the B case-against (we're not promising the substrate delivers it, we're saying the *pattern* requires it and v1 is incomplete) and the D case-against (we're naming the semantic property, not the substrate mechanism).

The reference schema (R10) stays as B specified — the contract is the semantic invariants; the schema is the reference implementation for core-layer parents.

---

## Phase 6 — Synthesis

### Decision block

<!-- decision:start id="design-2-substitution-contract" status="assumed" -->

### Decision: Substitution-variable contract surface and cross-branch framing

**Context.**
The parent-skill pattern must commit to a contract that holds across two substrates: the core-layer (wip/-based, branch-coupled, current shirabe pattern) shipping today via `/charter`, and a future amplifier-layer substrate (koto-context or successor) the `/work-on` migration will live in. PRD R10 specifies a concrete state-file schema; the design must decide whether the schema is the contract or a reference implementation. Independently, the wip-hygiene rule structurally precludes cross-branch resume on the v1 substrate (wip/ files are cleaned before merge), so cross-branch must be addressed in the contract: as an invariant the amplifier layer must satisfy, a wip/-specific limitation acceptable for v1, or out of scope. These two sub-questions are coupled: the substitution surface IS where cross-branch lives, because cross-branch is a property of state-storage shape.

The five alternatives considered span a two-axis space (contract abstraction × cross-branch framing). The adversarial pass between alternatives B (two-layer contract with cross-branch as wip/-specific limitation) and C (two-layer contract with cross-branch as pattern invariant) was the closest contest; B was honest about substrate uncertainty but weakened the design's forcing function on the amplifier-layer, while C made the cross-branch gap explicit but presumed substrate capabilities not yet verified.

**Assumptions**
- The amplifier-layer substrate (koto-context or successor) will support state persistence keyed by topic slug. If wrong, the contract's state-by-topic invariant cannot be promised across substrates.
- The amplifier-layer will provide equivalent-or-stronger properties for the wip-substrate capabilities the v1 contract relies on (drift detection, resume from partial state, audit trail). It will not regress on these.
- koto-context is not branch-coupled in the way wip/ is (i.e., it is not deleted on squash-merge). Its own coupling properties (session-scope, workspace-scope) may exist but are weaker than wip/'s.
- Future parents (`/scope`, `/work-on`) interoperate via durable artifacts in `docs/` regardless of substrate; the durable artifact contract is shared infrastructure.

**Chosen: C* — Two-layer contract (semantic invariants + reference schema) with cross-branch named as a pattern invariant v1 acknowledges it does not satisfy**

The parent-skill pattern's contract is a **two-layer structure**:

1. **Semantic invariants (the contract surface — substrate-agnostic).** Every parent-skill implementation MUST satisfy:
   - **(I-1) Chain state.** Parent maintains state per (topic) that records: the planned chain of children, the children that have run, the children skipped (with reasons), and the chain's current phase.
   - **(I-2) Exit outcome.** Parent records exactly one terminal exit outcome from a closed enumeration before finalization. Finalization MUST fail if no exit is recorded or the recorded value is outside the enumeration. Conditional metadata bound to the exit shape (sub-shape, references, rationale) MUST be present-when-required and absent-when-not-required; null/empty/placeholder is a violation.
   - **(I-3) Drift detection on children.** Parent records sufficient identity for each child doc named in the planned chain to detect out-of-chain edits between parent runs. The identity mechanism is substrate-dependent (for git-tracked children: path + frontmatter status + git blob hash; for future substrates: substrate-defined equivalents that detect both status-flip and body-edit).
   - **(I-4) Resume contract.** Parent supports resume mid-chain by consulting, in order: (a) its own state, (b) child-doc identity comparisons against snapshots, (c) child-internal substrate-equivalent partial-state. The ordering principle (first-match-wins, most-specific-state-first) is invariant; the concrete sources are substrate-dependent.
   - **(I-5) Audit trail.** Parent's state is inspectable by a human reviewer in the same review surface used for the parent's durable artifacts (for git/wip/-based: branch tree; for substrate-equivalent: substrate's review surface).
   - **(I-6) Branch-independent topic-keyed resume.** A parent's state for a given topic MUST be resumable regardless of which git branch the author is on. **The v1 core-layer implementation does not satisfy this invariant** — the wip/ substrate is structurally branch-coupled (cleaned on merge per the wip-hygiene rule). This is named as a known v1 gap; the amplifier-layer substrate is the expected resolution surface.

2. **Reference implementation (substrate-bound, substitutable).** For core-layer parents shipping today, the reference implementation is:
   - **State storage:** `wip/<parent>_<topic>_state.md` (pure YAML in a `.md` file per shirabe wip/ convention).
   - **Reference schema:** PRD R10's named fields (`chain_started`, `planned_chain`, `chain_ran`, `chain_skipped`, `exit`, `decision_record_sub_shape`, `exit_artifacts`, `child_snapshots`, conditional fields). Every core-layer parent uses this schema verbatim with parent-specific field extensions on top (e.g., `/charter` adds `referenced_strategy`, `discard_commit_sha`).
   - **Drift identity:** `{path, frontmatter status, git blob hash}` per child.
   - **Resume sources:** `wip/<parent>_<topic>_state.md`, child doc frontmatter + git blob hash, `wip/<child>_<topic>_*.md` files, git branch context.

**Substitution surface (what an amplifier-layer parent can substitute).**
An amplifier-layer parent MAY substitute, provided the semantic invariants hold:
- The storage location (e.g., koto-context entry instead of wip/ file).
- The concrete schema field names and serialization format (e.g., structured updates instead of whole-document YAML).
- The drift-identity mechanism (e.g., koto-context-entry hash instead of git blob hash).
- The resume sources (e.g., koto-context lookup instead of wip/ glob).

An amplifier-layer parent MUST NOT regress on the semantic invariants. In particular, **the amplifier-layer substrate is expected to satisfy I-6 (branch-independent resume)** — this is the named resolution surface for the v1 gap. If the amplifier-layer substrate cannot satisfy I-6, the contract requires that fact to be surfaced explicitly (not silently absorbed); the design's expectation that I-6 is the amplifier-layer's resolution surface would need to be revisited.

**Rationale.**

1. **Two-layer is the natural fit for the workspace's own language.** The shirabe CLAUDE.md already distinguishes "non-koto workflows use wip/" from "koto-driven workflows use koto context" with explicit equivalence claims ("same review and traceability properties"). The two-layer contract names exactly this distinction: substrate as substitution variable, semantics as invariant.

2. **The PRD's `[pattern-level]` tagging is preserved.** R9, R10, R11 stay pattern-level — their *semantics* are the invariants (I-1, I-2, I-3, I-4, I-5). The concrete schema is named as the reference implementation, which is what every core-layer parent will actually use; the abstraction is a substitution-surface declaration, not a fragmentation move.

3. **Cross-branch as named invariant with v1 acknowledged gap is the most coherent framing given the design's stated purpose.** The design skeleton already names "the amplifier-layer workflow substrate is the expected resolution surface" for team persistence (Decision 5 territory) and frames limitations as "architectural properties of the core layer, not transient bugs" (Open Questions §1). Applying the same framing to cross-branch is consistent. The alternative — naming cross-branch as merely "expected but not required" (B) — would weaken the design's forcing function on amplifier-layer work and create an asymmetry with how team-persistence is framed in the same document.

4. **Verifiability is preserved.** Every core-layer parent uses R10's schema verbatim, so a "does this parent's state match R10?" check still works for v1. The substitution surface only opens up when an amplifier-layer parent appears, at which point the verification shifts to "does this parent satisfy the semantic invariants?" — a harder check but the right one given the substrate divergence.

5. **The case-against from B (substrate optimism) is mitigated by the framing.** C* names cross-branch as a *pattern* invariant the v1 implementation acknowledges it does not satisfy. This is not a substrate promise — it is a *pattern* property the v1 implementation is incomplete relative to. If the amplifier-layer substrate also cannot satisfy I-6, that is a finding to surface; the contract does not assume away the possibility.

**Alternatives Considered**

- **A (Lock the schema; cross-branch is wip/-specific, amplifier fixes).** Rejected because locking the schema as the contract over-commits to one substrate's serialization shape (whole-document YAML), foreclosing structured-update and field-level-update substrates the amplifier layer may need. The verifiability benefit of locking is preserved by C* through the reference-implementation layer (every core-layer parent still uses the verbatim schema) without paying the foreclosure cost.

- **B (Two-layer; cross-branch as wip/-specific limitation, expected but not required).** Rejected because "expected but not invariant" cross-branch framing weakens the design's forcing function on the amplifier-layer substrate work. The design has already framed the amplifier layer as the resolution surface for related gaps (team persistence); applying inconsistent framing to cross-branch would muddy the design's overall posture. C* keeps B's two-layer structure but tightens the cross-branch framing into a named invariant with an acknowledged v1 gap.

- **D (Pure invariant contract, no reference schema).** Rejected because the parent-skill pattern's value depends on convergence-by-default across parents. All three parents (`/charter`, `/scope`, `/work-on`) share the same domain (skill-progression authoring), so the prior is convergence. D removes the reference schema entirely, which fragments the pattern and removes the verifiability gain the PRD's `[pattern-level]` tagging was designed to provide. The substitution surface C* opens (substrate-driven schema changes) is the right level of flexibility; D's "every parent owns its shape" is over-correction.

- **E (Lock the schema; cross-branch out-of-scope-forever).** Rejected because the design's own framing of the amplifier-layer (PRD Q4, design Driver 4) names cross-branch as a thing the substrate work might resolve. "Out-of-scope-forever" contradicts the design's stated posture toward the amplifier-layer. E is internally incoherent given the document it appears in.

**Consequences**

*What becomes easier:*
- **The amplifier-layer work has a forcing function.** When the workflow-substrate work bounds, it has a named invariant (I-6) to satisfy and a substitution surface (storage, schema, drift identity, resume sources) defined as variables it can fill. The design hands the substrate work a concrete spec instead of a vague "preserve current behavior."
- **Downstream parents (`/scope`, `/work-on`) inherit a clear contract.** `/scope` ships as a core-layer parent using the reference implementation (R10 schema verbatim, wip/ storage); `/work-on` migrates to amplifier-layer with the substitution surface as its migration target.
- **Verification is staged.** Core-layer parents verify by matching R10 (mechanical); amplifier-layer parents verify by satisfying the semantic invariants (review-level).

*What becomes harder:*
- **The design must precisely articulate I-1 through I-6 in the Solution Architecture section.** Vague invariants are worse than no invariants — they create review surfaces with no clear pass/fail. The invariant text is the load-bearing part of the contract.
- **A future "does this amplifier-layer parent satisfy the contract?" review requires substrate-aware judgment.** Unlike core-layer parents (where R10 match is mechanical), amplifier-layer compliance is prose-judgment against the invariants. This is the cost of the substitution surface.
- **The v1 design ships with an explicit known-violated invariant (I-6).** This is by design — it surfaces the gap — but it requires the design's Open Questions section to name the gap clearly and the amplifier-layer pre-justification to land. Readers will see "v1 does not satisfy this pattern invariant" and need the framing to understand why that is intentional.

*Coupling to other decisions:*
- **Decision 3 (schema ratification).** Decision 3 asks whether PRD R10's schema is pattern-level or implementation-level. C* answers it via the two-layer split: the schema's *semantics* (I-1 through I-5) are pattern-level; the *concrete field names and serialization* are the reference implementation. Decision 3 should ratify this split rather than re-litigate it. Phase 3 cross-validation will check coupling.
- **Decision 5 (team-primitive adaptation).** Decision 5 asks how the design surfaces the TeamCreate constraint. C*'s framing (amplifier-layer as resolution surface for named v1 gaps) is consistent with Decision 5's expected outcome (amplifier-layer as resolution surface for team-persistence gaps). The two decisions should mutually reinforce.
- **Decision 1 (shared references location).** The reference implementation (R10 schema, wip/ storage location) becomes content for a shared reference file (Decision 1 territory). Whatever shared reference Decision 1 places at the engine/pattern location should encode the reference implementation alongside the semantic invariants.

<!-- decision:end -->

---

## Result returned to coordinator

```yaml
decision_result:
  status: "COMPLETE"
  chosen: "C* — Two-layer contract (semantic invariants + reference schema) with cross-branch named as a pattern invariant v1 acknowledges it does not satisfy"
  confidence: "medium"
  rationale: >
    The two-layer contract (semantic invariants substrate-agnostic, reference
    implementation substrate-bound) matches the workspace's existing language
    distinguishing wip/-based vs koto-context-based storage with equivalent
    semantics. Cross-branch resume is named as a pattern invariant (I-6) the
    v1 implementation acknowledges it does not satisfy, consistent with how
    the design frames the amplifier-layer as the resolution surface for other
    core-layer gaps (e.g., team persistence). PRD R10's schema is preserved
    as the reference implementation every core-layer parent uses verbatim,
    so verifiability is not lost; the substitution surface only opens for
    amplifier-layer parents. Confidence is medium rather than high because
    A2/A3 (amplifier-layer substrate capabilities) are unverified assumptions.
  assumptions:
    - "Amplifier-layer substrate (koto-context or successor) supports state persistence keyed by topic slug. If wrong, the state-by-topic invariant cannot be promised across substrates."
    - "Amplifier-layer will provide equivalent-or-stronger properties for the wip-substrate capabilities (drift detection, resume from partial state, audit trail). It will not regress."
    - "koto-context is not branch-coupled in the way wip/ is (not deleted on squash-merge). Its session/workspace-scope coupling is weaker than wip/'s branch coupling."
    - "Future parents (/scope, /work-on) interoperate via durable docs/ artifacts; the durable artifact contract is shared infrastructure regardless of substrate."
    - "The semantic invariants (I-1 through I-6) are precise enough that a future amplifier-layer parent can be reviewed for compliance via prose-judgment. If the invariants prove too vague in practice, the design needs to add concrete acceptance tests per invariant."
  rejected:
    - name: "A — Lock the schema; cross-branch is wip/-specific, amplifier fixes"
      reason: "Locking R10 verbatim as the contract over-commits to whole-document YAML serialization, foreclosing structured-update and field-level-update substrates the amplifier layer may need. The verifiability benefit of locking is preserved in C* by keeping R10 as the reference implementation every core-layer parent uses verbatim, without paying the foreclosure cost."
    - name: "B — Two-layer; cross-branch as wip/-specific limitation, expected but not required"
      reason: "Naming cross-branch as 'expected but not invariant' weakens the design's forcing function on the amplifier-layer substrate work and creates inconsistency with how the same design frames the amplifier layer as the resolution surface for team-persistence (Decision 5 territory). C* keeps B's two-layer structure but tightens cross-branch framing into a named invariant with an explicitly acknowledged v1 gap."
    - name: "D — Pure invariant contract (no reference schema)"
      reason: "Removes the reference schema entirely, which fragments the pattern across the three parents. All three parents share the same domain; convergence-by-default is the right prior. The substitution surface in C* (substrate-driven schema changes when needed) is the right flexibility level; D's 'every parent owns its shape' is over-correction. D also removes the verifiability the PRD's [pattern-level] tagging was designed to provide."
    - name: "E — Lock the schema; cross-branch out-of-scope-forever"
      reason: "Internally incoherent given the design's own framing of the amplifier-layer (PRD Q4, design Driver 4) as a thing that might resolve cross-branch. 'Out-of-scope-forever' contradicts the document's stated posture toward the amplifier layer. E also shares A's over-locking of the schema and adds a new over-commitment on cross-branch."
  report_file: "wip/research/design_shirabe-progression-authoring_decision_2_report.md"
```
