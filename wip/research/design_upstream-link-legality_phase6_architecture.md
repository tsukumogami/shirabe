# Architecture Verdict — DESIGN-upstream-link-legality

**Verdict:** PASS

All six second-order corrections landed and each is accurate against the tree. No
correction introduced a further inconsistency. Two wording residues remain; both
are noted below as nits and neither would mislead an implementer, since the
substance is stated correctly in three other places in each case.

---

## Verification of the six corrections

**1. Frontmatter `rationale:` — fixed, and now matches the body.** It reads "a
shared classifier feeding two emitters is that one function with an extra
indirection, while suppression downstream of the finding boundary is not
expressible at all: a finding carries no entry index." That is the revised
Decision 2's argument in miniature, with the retracted "not expressible across
function boundaries" claim gone. The Decision Drivers bullet on entry indices
remains correct as written, because it speaks about correlating two *findings*.

**2. `ChainRole` arity — fixed and accurate.** "the five roles the chain walk
traverses" matches `crates/shirabe-validate/src/lifecycle.rs:130-136` (`Brief`,
`Prd`, `Design`, `Plan`, `Roadmap`) and no longer contradicts Decision 1 Option
C's "five of the eight types." The claim that the walk traverses all five is
right: `discover_chains` stops at `Brief` and `Roadmap` *after* pushing them, so
both are members.

**3. Check count — reconciled.** The three-versus-six contradiction is gone.
Decision Outcome dropped the number, says the contract "is extended rather than
merely adopted", names both extensions with a reason for each, and points at the
flag path's ordered list. Decision Drivers keeps "the same three ordered
validation checks" as a description of what the five sibling skills ship today —
which is correct and is no longer in tension, because the same bullet now adds
that an extension applies to every skill holding the value rather than the new
one alone. Consequences' reference to `/scope`'s "three ordered checks" is about
`/scope`'s own pre-existing promise and is untouched, correctly.

**4. Orphan notice count — fixed and matches measurement.** "the same single
orphan notice." I re-measured on the current tree: one `[L02]` on
`docs/prds/PRD-koto-adoption.md`, exit 0, identical from both
`target/debug/shirabe` and the installed binary. The R25 answer and its reasoning
(a separate mode that never calls the per-file pass) were already right; the
number now agrees.

**5. "The two that read it" — replaced in both places, and the replacement is
coherent.** The flag path and Security now both say the confinement applies to
"every skill that validates a supplied path — `/scope`, `/brief` and `/plan`" and
to none of "the consumers that later read a recorded field, which judge what is
written rather than what was typed." That is the real distinction, it names a set
that exists, and the follow-on "confining only the two that do not record" is
right — `/scope` and `/brief` do not record, `/plan` does.

**6. Confinement definition — fixed, and every number checks out.** The design
now defines "the roadmaps directory" as `<root>/docs/roadmaps/` for the
repository root the value was canonicalized against, explicitly not any
`docs/roadmaps/` path segment beneath it, and gives the reason: a path-segment
reading would let a fixture tree launder a roadmap path into a real chain.
Verified against the tree:

- 8 tracked `ROADMAP-*.md` files (the 14 `git ls-files` hits include 6
  `.exit`/`.stderr`/`.stdout` expected-output files, which are not roadmaps).
- No `docs/roadmaps/` at the repository root, so all 8 sit outside the
  confinement under the root reading — as the design says.
- Exactly 4 sit under a nested `docs/roadmaps/` inside
  `crates/shirabe/tests/fixtures/transition-golden/corpus/*/`, which is the 4 a
  path-segment reading would admit — as the design says.

Security's count moved from four to eight and now agrees with the flag path. The
definition is also consistent with flag-path step 1: a cross-repo value is never
canonicalized, and step 1 has it skip check 3, so "for whichever repository root
the value was canonicalized against" has no gap in it.

---

## Requirement coverage map

Unchanged from the previous round except where noted; every requirement is
answerable from the document.

| Req | Design element | Status |
|---|---|---|
| R1 | Context and Problem Statement; *The check*'s predicate paragraph, which bounds where the implemented predicate is narrower than the stated property | Covered |
| R2, R3 | Decision 1 Option A; *The declaration layer* | Covered |
| R4 | Decision Outcome's two unit tests over `formats()` | Covered |
| R5, R5.2 | Decision Outcome (by reference to the PRD's table); Implementation phase three | Covered |
| R6 | *The check* | Covered |
| R7 | Decision 2; `R10` direction and `R11` lifetime named in *The check*, with the namespace note | Covered |
| R8 | Context; Security ("The check performs no I/O: N/A") | Covered |
| R9, R10 | *The check*; phase two's test list | Covered |
| R11, R12 | Decisions 3 and 4; Decision Outcome; flag-path step 6 | Covered |
| R13 | Decision 4; flag path, which names the two changes to `/brief`'s validation rather than leaving them inside "unchanged as inputs" | Covered |
| R14 | Decision 3; Decision Outcome; flag path | Covered |
| R15 | Implementation phase four; verified against `skills/explore/references/phases/phase-5-produce-roadmap.md:43-49` | Covered |
| R16, R16.1 | Decision Drivers; Decision 3 Option D; Consequences | Covered |
| R17 | — | Satisfied by omission; not worth a further round |
| R18, R19 | *What does not change* | Covered |
| R20 | *What does not change*, the orphan-rule paragraph | Covered |
| R21 | Decision Drivers; Context; *The call site*; the non-collision note | Covered, including the "not `R5` or `FC99`" clause |
| R22, R23 | Phase five; *What does not change* | Covered |
| R24 | Phase two; Consequences | Covered |
| R25 | *The call site*, with the corrected count | Covered |

No design element answers no requirement.

## Section completeness and order

Pass. All nine required sections present in the canonical order from
`skills/design/SKILL.md:68-80`: Status, Context and Problem Statement, Decision
Drivers, Considered Options, Decision Outcome, Solution Architecture,
Implementation Approach, Security Considerations, Consequences. Frontmatter
carries all four required fields plus `schema:` and a legal `upstream:` (a PRD,
which is in DESIGN's declared parent set). Four alternatives per decision. No
`wip/` path is referenced from the document.

---

## Nits — not blocking, fix if the document is opened again

**The flag path's lead-in still overclaims by one clause.** It says `/plan`
validates the value "against the full record-time set its five sibling skills
run, in this order", but check 3 (directory confinement) is not something the
siblings' flags run today — it is being added, which Decision Outcome now
correctly calls an extension. The sentence lags the fix by one word; the six
numbered checks immediately below it and the "two of these are changes to
`/brief`'s flag validation" paragraph twenty lines later both say the right
thing, so nothing downstream is misled. Replacing "the full record-time set its
five sibling skills run" with "the record-time set its five sibling skills run,
extended as Decision Outcome describes" closes it.

**One terminology drift between Decision Drivers and everywhere else.** Decision
Drivers says the extension "applies to every skill that **holds the value**";
Decision Outcome, the flag path and Security all say "every skill that
**validates a supplied path**." The two phrases denote the same set — `/scope`,
`/brief`, `/plan` — so this is wording, not substance, but the second phrasing is
the one correction 5 settled on and the first is the phrasing it replaced
elsewhere.

---

## Standing assessment of the architecture

Unchanged and accepted, restated here so the verdict is self-contained. The two
declarations belong on `FormatSpec`: the referent set is closed, a field makes
the declaration total where a side table would make it optional, and the
maintainer journey is what forces that. The check belongs where the design puts
it — I verified `validate_file`'s order (schema gate, private-only gate, FC
checks, `check_upstream_resolves`, format dispatch) and the golden-fixture
argument for `real/PRD-roadmap-skill.md`, including the independent proof that
the schema gate rather than luck is what protects it. `FormatId` creates no
cycle; `lifecycle.rs` already depends on `formats.rs` and nothing new points
back. The cross-validation claim holds on its own terms — no Durable type's
declared parent set contains a Working type, so every lifetime violation is
necessarily a direction violation, strictly, with the corpus confirming both
halves — and the design draws the right conclusion from it and now also bounds
where the implemented predicate and the stated property would diverge. The five
phases are genuinely independent where claimed, the script fix sits with the flag
it is a hard dependency of, and the phase graph has no cycle.
