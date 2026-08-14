# Architecture Verdict — DESIGN-upstream-link-legality

**Verdict:** FAIL

The structural core is right and I verified it against the code rather than
taking the decision reports' word for it: the declarations belong on
`FormatSpec`, the check belongs in `validate_file`'s cross-format block behind
the schema gate, and the cross-validation claim about lifetime and direction is
correct. What fails is coverage and two rejection arguments. Three requirements
(R15, R20, R25) cannot be answered from the design, one rejected option is
knocked down with an argument its strongest form survives, another is rejected
on the ground its own decision report calls non-decisive, the two check codes
are never named, one security assertion states a property the script does not
have, and the phase graph is circular as written. Each is a paragraph-sized fix.

---

## Requirement coverage map

| Req | Design element that answers it | Status |
|---|---|---|
| R1 | Context and Problem Statement (direction + lifetime as the two properties); Decision Outcome's per-entry branch statement | Covered |
| R2 | Decision 1 Option A; Solution Architecture / The declaration layer (`lifetime: Lifetime`) | Covered |
| R3 | Same; "an empty vector for the two types that head their own lineage" | Covered |
| R4 | Decision Outcome, "two plain unit tests over `formats()` enforce the table verbatim and the durable-names-working prohibition" | Covered |
| R5 | Decision Outcome, "The declared table is the one the requirements fix" — deferred to the PRD by reference, with brief/plan rows called out inline | Covered by reference (acceptable) |
| R5.1 | Not a design element; PRD rationale | N/A |
| R5.2 | Implementation Approach phase three (reference sweep) | Covered |
| R5.3 | Not a design element; PRD rationale | N/A |
| R6 | Solution Architecture / The check, "names the document, the offending value, the resolved type pair, and the property that failed" | Covered |
| R7 | Decision 2 (precedence forces one function); Decision Outcome | **Partial — the two codes are never named anywhere in the design** |
| R8 | Context ("keeps the check out of the document index"); Security ("The check performs no I/O: N/A") | Covered |
| R9 | The check ("An entry whose basename matches no known prefix contributes nothing"; cross-repo file component) | Covered |
| R10 | The check (per-entry, at most one finding per entry); phase two's test list | Covered |
| R11 | Decisions 3 and 4; Decision Outcome | Covered |
| R12 | Decision Outcome, "/brief ... announces the omission with its reason" | Covered |
| R13 | Decision 4; Decision Outcome | Covered |
| R14 | Decision 3; Decision Outcome; Solution Architecture / The flag path | Covered |
| R15 | Implementation Approach phase four — the four words "`/explore`'s roadmap handoff" | **Named, never stated.** A reader cannot learn from the design what the handoff currently passes, what it should pass, or why |
| R16 | Decision Drivers ("The change is authored in each skill's own contract"); Decision 3 Option D; Security (private-upstream restated in `/plan`'s contract) | Covered |
| R16.1 | Consequences ("the consolidation absorb's re-point ... dissolves without a separate guard") | Covered |
| R17 | — | **Not affirmatively answered.** Satisfied by omission, but the design never states that no section, field, or third check is added |
| R18 | Solution Architecture / What does not change | Covered |
| R19 | What does not change ("the finalization walk already dispatches a roadmap node to the roadmap handoff from whichever node names it") | Covered |
| R20 | — | **Absent.** The orphan rule appears twice, both times for R8's strategic-directory point. Nothing says the Active-ROADMAP exemption, its behaviour and its tests are retained, and nothing says a brief authored under the new rule takes the ordinary upstream-less orphan notice |
| R21 | Decision Drivers; Context (the `PRD-roadmap-skill.md` fixture analysis); The call site (three named breaking placements) | Covered — except the "neither code may be `R5` or `FC99`" clause, unverifiable while the codes are unnamed |
| R22 | Phase five, "the five named eval expectations" | Covered by reference |
| R23 | What does not change; phase five ("the new-shape cascade fixture chain beside the frozen old-shape one") | Covered |
| R24 | Phase two ("the phase whose diff is measured against the named list"); Consequences; Mitigations | Covered by reference |
| R25 | — | **Absent.** The `--lifecycle . --mode=draft` exit-0 guarantee is never mentioned |

**Design elements answering no requirement.** One: the confinement of `/brief`'s
`--upstream` canonical path to the roadmaps directory (Security Considerations).
It is a defensible mitigation, but see structural finding 6 — it is a change to
the flag's input surface, and R13 says that surface is unchanged as an input.

---

## Strawman check

### Decision 1 — sound, with one option under-represented

**Option C (derive from the chain model) — not a strawman. Verified.**
`ChainRole` (`crates/shirabe-validate/src/lifecycle.rs:130-136`) has exactly
five variants; `target_state_for` (`lifecycle.rs:281-290`) matches five format
names and returns `TargetState::Unknown` for the rest, so VISION, STRATEGY and
COMP — all Durable under R5 — would derive silently wrong. The design's
rejection is the argument C's strongest form (read the class off
`target_state_for` rather than declaring it) actually dies on, not a weaker
substitute. The design also carries C's real insight forward rather than
discarding it: the terminal-status map is named as a second partial spelling,
with a test asserting agreement on the five shared types and a comment naming
the new field authoritative. That is the right disposition.

**Option B (separate legality module) — thin, but the argument survives.** The
design rejects B in three sentences on optionality. B's strongest support — that
`transition.rs`'s `transition_table()` is exactly this shape and already in the
codebase — appears nowhere in the design. The optionality argument does defeat
that strong form (a `None` from `transition_spec` is a legitimate answer because
the set of transitioning formats is open; legality is total), so this is not a
strawman. But a reader cannot see that B had a precedent, and one clause naming
it would make the rejection land instead of merely assert.

**Option D — fine.** Both stated reasons (I/O inside `validate_file`; the
declaration-level assertion passing vacuously in any tree without `skills/`) are
the strong ones.

### Decision 2 Option A (two functions) — **strawman, and this is the one to fix**

The design says the direction check "has only two ways to find out" the lifetime
verdict: recompute the predicate, or post-filter after both functions return.
The post-filter is then correctly shown to be inexpressible, because
`ValidationError` is `{file, line, code, message}` (`doc.rs:100-107`, verified)
and every per-entry `upstream:` finding sits at the field's single line.

The enumeration is not exhaustive. A third construction — one shared per-entry
classifier returning a verdict per entry, feeding two thin emitters — is neither
recomputation nor a post-filter, and it is expressible without string-matching
anything, because `crate::upstream::field_entries` returns an ordered `Vec`
(`upstream.rs:82-92`) and a position in that vector is a perfectly good
correlation key *inside* the check layer. The absence of an entry index on
`ValidationError` constrains what crosses the finding boundary; it does not
constrain what one module can compute about its own entries.

This does not change the outcome — a shared classifier plus two emitters is
Option B with an extra indirection and no benefit — but the design wins the
argument against a version of A nobody would build. The honest rejection is one
sentence: *a shared classifier feeding two emitters is expressible, and it is
Option B with a layer of ceremony; what is not expressible is the split that the
shared cross-format block invites, where two independent functions each emit and
the suppression has to happen downstream of the finding boundary.*

**Options C and D — genuine.** C's rejection (hardcoded code in a closure, a
`git ls-files` subprocess per entry, output bytes pinned by two golden fixtures)
matches `checks.rs`; D's (removes the finding from the pass an author already
runs) matches `is_known_check_code`'s own documented reason that lifecycle codes
are not `--check`-selectable.

### Decision 3 — one strong rejection, one weak one

**Option B — genuine and well-supported.** Five independent counts, each traced
to `/plan`'s own contract (positional slot is the `input_type` classifier and
the slug source; single value; forced multi-pr; the upstream status gate).

**Option D (`/scope` post-edits the plan) — rejected on the wrong ground.** The
design rejects D "against the parent-child isolation rule: it is a parent
reaching into a child's artifact." The decision report says plainly that D does
*not* violate R16's letter — R16 forbids a parent overriding what a child
records *at the moment the child records it*, and D writes afterwards. The
report's decisive objection is a different one the design omits entirely: the
PLAN is explicitly outside `/scope`'s closed write-target set, and writes outside
that set fail the R9 hard-finalization check. As written, the design's rejection
is the weakest of the four available and is arguably incorrect on its own terms.

**Option C — genuine** (rests on a per-feature downstream field the roadmap
format does not specify, which the PRD's Out of Scope already refuses to
canonicalize).

### Decision 4 — genuine, but see structural finding 6

B and C are rejected jointly on the roadmap-filename-versus-topic-slug argument,
which is the real reason and is mechanically true (`/scope` hands the roadmap
down by flag precisely because the two names normally differ). D is rejected on
the substantive value of the Phase 1 grounding read. No strawman here.

---

## Structural findings

**1. Placement and layering are correct — verified independently.**
`validate_file` (`validate.rs:183-217`) is schema gate → private-only gate (R9,
early return) → FC checks → `check_upstream_resolves` → format dispatch. The
design's three named breaking placements are the right three, and the golden
fixture argument holds: `real/PRD-roadmap-skill.md` carries
`upstream: docs/roadmaps/ROADMAP-strategic-pipeline.md` with no `schema:` field,
and the design's independent proof (that path does not resolve relative to the
corpus directory, so R6 would already be firing if anything ran past the gate)
is sound. The declarations belong on `FormatSpec`; the check belongs where the
design puts it. Nothing is at the wrong layer.

**2. No dependency cycle from `FormatId`, but the ChainRole relationship is
unstated.** `formats.rs` gains a type that references nothing outside itself;
`lifecycle.rs` already depends on `formats.rs` and the direction is preserved.
The crate ends up with two overlapping format-identity enums — `ChainRole`, five
variants, partial by design, in `lifecycle.rs`; `FormatId`, eight variants,
total, in `formats.rs` — and the design never mentions that this is the
situation, let alone why it is acceptable. The next reviewer will ask. One doc
comment stating that `ChainRole` answers "which role in a tactical chain" and
`FormatId` answers "which of the eight formats", and that unifying them is
deliberate future work blocked by R18 and R21, closes it.

**3. The "two spellings of lifetime" is handled well, not deferred badly.** A
test asserting the new field and `target_state_for` agree on the five shared
types, plus a comment naming the new field authoritative, converts the drift risk
into a build failure without deriving either from the other — correct, because
`target_state_for` also encodes *which* status is terminal, which the lifetime
class does not know. The one gap: the design does not say where that test lives,
and it necessarily reaches across both modules.

**4. The cross-validation claim is correct, and the design draws the right
conclusion from it.** I verified it against R5 rather than against the decision
report. Working types are ROADMAP and PLAN. The parent sets of the six Durable
types are `{VISION}`, `{VISION}`, `{}`, `{BRIEF}`, `{PRD, BRIEF}`, `{}` — none
contains a Working type, which is R4 holding. So for a Durable naming document,
target-is-Working implies target-not-in-parent-set, and every lifetime violation
is a direction violation. Strictness of the containment is witnessed by BRIEF
naming DESIGN. The corpus confirms both halves: the two R24 rows predicted as
lifetime violations (`BRIEF-cascade-outline-ac-completeness.md`,
`BRIEF-single-pr-plan-validation.md`) both name
`docs/plans/PLAN-roadmap-plan-standardization.md`, and PLAN is absent from
BRIEF's empty parent set, so both are also direction violations. The conclusion
the design draws — the lifetime code earns its place on message quality and on
being the runtime statement of a declaration-level rule, not on unique yield — is
the right one, and stating the containment as structural rather than incidental
is the right call.

One boundary the design does not name, and should in a clause: the implemented
lifetime predicate is *Durable names Working*, which is narrower than R1's
lifetime property (*the target outlives the naming document, or they are retired
together*). A ROADMAP naming a PLAN fails R1's property — the cascade deletes
the plan before the roadmap — but emits a direction finding rather than a
lifetime one under the implemented predicate. The case is already illegal and can
never be legal, so nothing is missed; only the diagnosis is less specific. Say so
rather than leaving the reader to discover that the runtime predicate and R1 are
not the same statement.

**5. Sequencing: phases four and five are mutually dependent as written.** The
design says "Phase five depends on four" and, in the same paragraph, that the
plan pre-flight script fix inside phase five "is a hard dependency of the flag
rather than a follow-up". Both claims are true — I verified the script's
`get_field` (`skills/plan/scripts/validate-plan.sh:61-72`) matches the first line
beginning `upstream:` and exits, so a block sequence yields an empty value and
the script takes its `[[ -z ]]` branch, logs "no upstream field — skipping
upstream validation" and exits 0, with `.github/workflows/check-plan-docs.yml:23`
running it on every changed PLAN. The conclusion the design does not draw is that
the script fix therefore belongs *in* phase four, not in a phase declared to
depend on it. As stated the phase graph has a cycle.

The claim that phases one and two can land first does hold. Phase one changes no
validation result. Phase two changes the eight named documents' findings, but
`validate-docs.yml` computes its file set from the PR's changed files rather than
scanning `docs/`, so the eight pre-existing illegal edges do not gate CI unless a
PR touches them — and this chain's own artifacts are clean (`BRIEF-upstream-link-legality.md`
carries no `upstream:`; the PRD names the brief; this design names the PRD).

**6. `/brief`'s flag validation changes are announced only in Security
Considerations, and they sit in tension with R13.** Two behavioural changes to
`/brief`'s `--upstream` are decided by this design: the tracked-by-git check is
dropped, and the canonical path is newly confined to the roadmaps directory.
Neither appears in Decision 4, in the Decision Outcome, or in Solution
Architecture's flag path — both live in a Security Considerations paragraph. That
is the wrong home for a contract change, and it means a reader of Decision 4
("keep both input routes and rename what they do") comes away believing the input
surface is untouched. R13 says the flag is "unchanged as *inputs*"; two of its
checks change. Both changes are defensible and the design argues them well; what
is missing is stating them where a reader looks for them and acknowledging the
tension with R13 in a sentence.

**7. The `--` argument-boundary claim is not true of the current script.**
Security Considerations states, in the present tense, that the roadmap value
"reaches a `git ls-files` invocation per entry in the plan pre-flight path. It is
quoted and passed after `--`". The invocation today is
`git -C "$repo_root" ls-files --error-unmatch "$upstream_val"`
(`skills/plan/scripts/validate-plan.sh:161`) — quoted, but with no `--`, so a
value beginning with a dash is parsed as an option. The design is asserting as an
existing property the very thing that has to be built. Since the design's own
sentence says "Validation is not the guarantee here; the argument boundary is",
this matters: the guarantee it leans on does not exist yet.

**8. The two check codes are never named.** The design says "a direction code and
a lifetime code" throughout. R7 requires distinct codes selectable with `--check`;
R21 requires that neither be `R5` or `FC99`; the decision report settled on `R10`
and `R11` and asked that the design state that the validator's check-code
namespace and the PRD's requirement numbering collide by prefix and are
unrelated. None of that is in the document, so two requirement clauses cannot be
checked against it and the reader is left to rediscover the collision.

**9. Section completeness and order: pass.** All nine required sections are
present in the canonical order from `skills/design/SKILL.md:68-80` — Status,
Context and Problem Statement, Decision Drivers, Considered Options, Decision
Outcome, Solution Architecture, Implementation Approach, Security
Considerations, Consequences. Frontmatter carries all four required fields plus
`schema:` and `upstream:`. Considered Options carries at least one alternative
per decision (four each). No `wip/` path is referenced from the document.

---

## Required changes

1. **Answer R20.** State that the orphan rule's Active-ROADMAP exemption, its
   behaviour and its tests are untouched and become unreachable for documents
   authored under the new rule, and that a brief heading its own lineage takes
   the ordinary upstream-less orphan notice. Two sentences in *What does not
   change*.

2. **Answer R25.** State that `shirabe validate --lifecycle . --mode=draft`
   exits 0 after the change and why the traversal is undisturbed. One sentence
   beside the R21 argument in *The call site*.

3. **State R15's change.** Say what `/explore` passes to `/roadmap` today, what
   it passes after, and that a ROADMAP's only legal parent is a STRATEGY.
   Currently only the phrase "`/explore`'s roadmap handoff" appears.

4. **Fix Decision 2's rejection of Option A.** Replace the "only two ways"
   enumeration with the accurate one: a shared per-entry classifier feeding two
   emitters is expressible — `field_entries` returns an ordered vector and a
   position in it is a usable key inside the check — and it is Option B with an
   extra indirection. What is inexpressible is suppression downstream of the
   finding boundary, because `ValidationError` carries no entry index.

5. **Fix Decision 3's rejection of Option D.** Lead with the decisive objection —
   the PLAN is outside `/scope`'s closed write-target set and writes outside it
   fail the R9 hard-finalization check — and either drop the parent-child
   isolation claim or qualify it, since D writes after the child has recorded and
   so does not violate R16's letter.

6. **Name the two check codes**, confirm neither is `R5` or `FC99`, and state
   that the validator's check-code namespace is unrelated to the PRD's
   requirement numbering despite the shared `R` prefix.

7. **Move the script fix into phase four**, or state explicitly that phase five
   splits — the `validate-plan.sh` sequence handling lands with the flag, the
   evals and fixtures land after it. As written the two phases depend on each
   other.

8. **Move `/brief`'s two flag-validation changes** (tracked-by-git dropped,
   roadmaps-directory confinement added) into Decision 4 or the flag path, and
   acknowledge in one sentence that they are changes to an input surface R13
   describes as unchanged.

9. **Correct the `--` claim.** State that the `git ls-files` invocation *gains*
   the `--` boundary as part of the script change; it does not have one today
   (`skills/plan/scripts/validate-plan.sh:161`).

10. **Add one clause on the FormatId/ChainRole relationship** and one naming the
    gap between the implemented lifetime predicate (Durable names Working) and
    R1's stated lifetime property.
