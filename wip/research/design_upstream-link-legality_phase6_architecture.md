# Architecture Verdict — DESIGN-upstream-link-legality

**Verdict:** FAIL

All ten required changes from the previous round landed, and every one of them
landed correctly — I re-checked each against the code rather than against the
change summary. The architecture is accepted: the declarations belong on
`FormatSpec`, the check belongs where the design puts it, the cross-validation
claim holds, Decision 2's Option A rejection is now honest, and Decision 3's
Option D rejection now leads with the objection that actually decides it.

What fails is the second-order edit. Six new inconsistencies came in with the
revisions, and four of them are checkable: two are internal contradictions where
one part of the document now says something the rest denies, one is a measured
number that is wrong, one is a wrong arity contradicted by this same document
eight paragraphs earlier. Each is a one-line correction. None touches a decision.

---

## Requirement coverage map

| Req | Design element that answers it | Status |
|---|---|---|
| R1 | Context and Problem Statement; *The check*'s predicate paragraph, which now also states where the implemented predicate is narrower than R1's property | Covered |
| R2 | Decision 1 Option A; *The declaration layer* | Covered |
| R3 | Same; empty vector for the two head-of-lineage types | Covered |
| R4 | Decision Outcome, the two unit tests over `formats()` | Covered |
| R5 | Decision Outcome, deferred to the PRD by reference with the brief/plan rows inline | Covered by reference |
| R5.2 | Implementation phase three | Covered |
| R6 | *The check*: names the document, the offending value, the resolved type pair, the property | Covered |
| R7 | Decision 2; *The check* now names `R10` direction, `R11` lifetime | **Covered — newly fixed** |
| R8 | Context; Security ("The check performs no I/O: N/A") | Covered |
| R9 | *The check* (unknown prefix contributes nothing; cross-repo file component judged on its prefix) | Covered |
| R10 | *The check*; phase two's test list | Covered |
| R11 | Decisions 3 and 4; Decision Outcome | Covered |
| R12 | Decision Outcome; flag-path step 6 | Covered |
| R13 | Decision 4; flag path, which now names the two changes to `/brief`'s validation explicitly | Covered |
| R14 | Decision 3; Decision Outcome; flag path | Covered |
| R15 | Implementation phase four, full paragraph | **Covered — newly fixed, and accurate.** Verified: `skills/explore/references/phases/phase-5-produce-roadmap.md:43-49` detects a VISION in the crystallize artifact and passes it as `/shirabe:roadmap <topic> --upstream <vision-path>` |
| R16 | Decision Drivers; Decision 3 Option D; Security | Covered |
| R16.1 | Consequences | Covered |
| R17 | — | Still not affirmatively stated; satisfied by omission. Not worth a round trip |
| R18 | *What does not change* | Covered |
| R19 | *What does not change* | Covered |
| R20 | *What does not change*, new paragraph | **Covered — newly fixed** |
| R21 | Decision Drivers; Context; *The call site*; the non-collision note in *The check* | Covered, including the "not `R5` or `FC99`" clause |
| R22 | Phase five | Covered by reference |
| R23 | *What does not change*; phase five | Covered |
| R24 | Phase two; Consequences | Covered by reference |
| R25 | *The call site*, new paragraph | **Answered, but the answer contains a wrong number — see finding 4** |

No design element answers no requirement. The roadmaps-directory confinement,
which I flagged last round as an unrequirement-backed addition, is now argued in
the flag path and in Security and is properly owned.

---

## New inconsistencies introduced by the revisions

**1. The frontmatter `rationale:` now contradicts Decision 2.** The body was
rewritten to say the strongest two-function form *is* expressible — "the
normalizer returns an ordered vector, so a position in it is a usable key
*inside* a check" — and that what is inexpressible is suppression downstream of
the finding boundary. The frontmatter still reads: "One check function rather
than two is forced by the precedence rule, **which is not expressible across
function boundaries** because a finding carries no entry index." That is the
claim the revision retracted, preserved verbatim in the document's own summary.
The frontmatter is what a reader sees first and what tooling parses. It needs
the same correction the body got.

(The Decision Drivers bullet "A finding carries no entry index" is fine as
written — it speaks about correlating two *findings*, which is exactly the
downstream-of-the-boundary case the body now isolates.)

**2. `ChainRole` is given the wrong arity, and this document says so itself.**
*What does not change* now reads "`ChainRole` models the four tactical roles the
chain walk traverses." It has five variants — `Brief`, `Prd`, `Design`, `Plan`,
`Roadmap` (`crates/shirabe-validate/src/lifecycle.rs:130-136`) — and Decision 1
Option C, in this same document, correctly says the chain model covers "five of
the eight types." The rest of that paragraph is right and is the paragraph I
asked for: the dependency is one-directional, `lifecycle.rs` already depends on
`formats.rs`, unifying is blocked by the no-modified-tests constraint. Only the
number is wrong.

**3. Decision Outcome and the flag path disagree on how many checks `/plan`
runs.** Decision Outcome still says `/plan` is "canonicalized and bounds-checked,
and run through **the three ordered checks**." The flag path now specifies a
numbered list of **six**, and Decision Drivers still describes the flag as
carrying "the same three ordered validation checks" while insisting "a sixth
skill adopting it should adopt the contract, **not a variant of it**." After the
security revision, `/plan` runs a variant: cross-repo discrimination promoted to
step 1 and a directory confinement that no sibling's flag carries today. An
implementer reading Decision Outcome builds three checks; one reading the flag
path builds six. Both the count and the "not a variant" framing need to move to
where the design actually landed — which is defensible, but has to be stated as
the extension it is.

**4. The R25 paragraph's notice count is wrong.** It says the lifecycle command
"exits 0 after the change exactly as it does before, with the same **two** orphan
notices." Measured on the current tree, with both the built binary
(`target/debug/shirabe`) and the installed one, `shirabe validate --lifecycle .
--mode=draft` emits exactly **one** notice and exits 0:

```
::notice file=docs/prds/PRD-koto-adoption.md::[L02] orphan PRD at status 'Accepted' ...
EXIT=0
```

The requirement R25 actually asks about — exit 0, unchanged finding set — is
answered correctly and the reasoning behind it (a separate mode that never calls
the per-file pass) is right. Only the count is wrong, and a wrong count in the
sentence that discharges a compatibility requirement is the kind of thing the
next person measures against.

**5. "Not to the two that read it" names a set that does not exist.** The
sentence appears twice — in the flag path and again in Security: "The
confinement applies to all three skills that hold the value — `/scope`, `/brief`
and `/plan` — not to the two that read it." `/brief` is a reader; that is
Decision 4's entire thesis, and `/brief` is in the three. There is no coherent
pair of skills left to be "the two that read it." If the intended contrast is the
two chain-walking consumers, that is a category error — the confinement is a
flag-validation rule and the walkers never see a flag. The distinction the design
needs is between skills that *validate a supplied path* and skills that *consume
a recorded field*, and it should be drawn in those words.

**6. The "four fixture-tree roadmaps" count reconciles under only one unstated
reading.** Both the flag path and Security cite "a tracked file with a roadmap
basename outside the roadmaps directory, of which this repository has four in its
fixture trees," as the evidence for extending confinement to `/plan`. The repo
has **eight** tracked `ROADMAP-*.md` files, and `docs/roadmaps/` does not exist
at the repo root at all:

- 2 under `crates/shirabe/tests/fixtures/golden/corpus/{real,synthetic}/`
- 4 under `crates/shirabe/tests/fixtures/transition-golden/corpus/*/docs/roadmaps/`
- 2 under `skills/{execute,work-on}/evals/fixtures/roadmaps/`

Under "the canonical path must be under `<root>/docs/roadmaps/`" — the natural
reading given that step 2 canonicalizes and bounds-checks against the working
tree — the count is eight. The count is four only if confinement means "the path
contains a `docs/roadmaps/` segment anywhere," which the design never says. Since
the four transition-golden fixtures sit under nested `docs/roadmaps/` corpora,
this is not pedantry: the two readings accept and reject different files, and the
design has to pick one.

---

## Re-check of the ten fixes

1. **R20** — landed. *What does not change* now states the exemption keeps its
   behaviour and tests, becomes unreachable under the new rule, and that a
   head-of-lineage brief takes the ordinary upstream-less orphan notice.
2. **R25** — landed, reasoning correct, count wrong (finding 4).
3. **R15** — landed and verified accurate against `/explore`'s phase 5.
4. **Decision 2 Option A** — landed. The strongest form is acknowledged and
   rejected on the right ground. Undercut by the stale frontmatter (finding 1).
5. **Decision 3 Option D** — landed. Leads with the closed-write-target-set
   objection and the hard-finalization check, and correctly qualifies the
   layering claim as violating the rule's reason rather than its letter.
6. **The codes** — landed. `R10`/`R11`, non-collision stated, namespace note
   present. Consistent with the negative list the existing selectability test
   pins.
7. **Phase four/five** — landed, cycle resolved. The script fix now sits with the
   skill contracts in phase four, with the hard-dependency reason stated;
   phase five is evals and fixtures alone; "nothing inside phase four depends on
   phase five" closes it. The claim that phases one and two can land first still
   holds.
8. **`/brief`'s two flag-validation changes** — landed, in the flag path, with
   the R13 tension named explicitly.
9. **The `--` claim** — landed and now correct. Verified both sites: the
   pre-flight script quotes but passes no `--`
   (`skills/plan/scripts/validate-plan.sh:161`), and `/plan`'s Phase 7 prose
   specifies `git ls-files <path>` unquoted with no terminator
   (`skills/plan/references/phases/phase-7-creation.md:308`). "The script does
   not have that boundary today and gains it here" is accurate.
10. **FormatId/ChainRole** — landed, with the wrong arity (finding 2). The
    lifetime-predicate-versus-stated-property paragraph in *The check* is right
    and well-bounded.

## Section completeness and order

Pass. All nine sections present in the canonical order from
`skills/design/SKILL.md:68-80`. Frontmatter carries all four required fields. No
`wip/` path is referenced. Considered Options still carries four alternatives per
decision.

---

## Required changes

1. Rewrite the frontmatter `rationale:`'s middle sentence to match the revised
   Decision 2: the precedence rule is not expressible *downstream of the finding
   boundary*, and a shared classifier feeding two emitters is Option B with an
   extra indirection.
2. "four tactical roles" → five, in *What does not change*.
3. Reconcile the check count: Decision Outcome's "the three ordered checks" and
   Decision Drivers' "the same three ordered validation checks ... not a variant
   of it" against the flag path's six. State plainly that `/plan` extends the
   sibling contract with cross-repo discrimination promoted to first and a
   directory confinement, and why.
4. "the same two orphan notices" → one. Measured: a single `[L02]` notice on
   `docs/prds/PRD-koto-adoption.md`, exit 0.
5. Replace "not to the two that read it", in both places, with the real
   distinction — skills that validate a supplied path versus consumers that read
   a recorded field.
6. Say whether confinement means `<root>/docs/roadmaps/` or any `docs/roadmaps/`
   path segment, and make the fixture count agree with the answer. Eight tracked
   `ROADMAP-*.md` files exist and no repo-root `docs/roadmaps/` does.
