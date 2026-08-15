# Category C: FAIL

Method: pattern-pass keyword scan run over the full plan text (fixture terms: zero
hits, no false positives possible; failure/edge terms: hits only in Issues 3 and 4 —
"error" at Issue 3 AC2, "conflicting"/"failing" at Issue 4 AC3/AC5), plus adversarial
reasoning against patterns 2/4/5/6 for every other AC, plus targeted construction of
concrete wrong implementations for the ACs the reviewer flagged for special attention.

---

## Issue 1: Author the shared split-triggers reference

**Finding 1 — Pattern 7 (existence-without-correctness).** AC1: "`references/split-triggers.md`
exists with a shared-core section and two profile sections, following the structure
`references/issues-table.md` uses." Wrong implementation: a file with three empty
headings —
```
## Shared Core
TODO

## Plan Profile
TODO

## Coordinated Profile
TODO
```
— satisfies "exists," "shared-core section," "two profile sections," and arguably
"follows the structure" (headings mirror `issues-table.md`'s shape) while containing
none of the three branch names or their definitions.

*Corrected AC1:* "`references/split-triggers.md` exists with a shared-core section
naming and defining all three branches (Hard Constraint, Incremental Value, Stated
Preference) with the same specificity `references/issues-table.md`'s shared core
uses, plus a plan-profile section stating it takes all three as-is and a
coordinated-profile section stating it adds Merge-Order Necessity as a fourth branch
— not merely matching section headings."

**Finding 2 — Pattern 3 (happy-path only, issue-level, automated).** No AC in Issue 1
mentions any failure/rejection/omission scenario. A wrong implementation that creates
the new file and adds citations but leaves the retired triggers ("independently
mergeable," "independently rollback-able," the free-standing reviewability trigger)
duplicated in their old locations passes every existing AC.

*Add:* "After the edit, 'independently mergeable' and 'independently rollback-able'
appear only inside Hard Constraint's coordinated examples in the new reference — not
as free-standing bullets in `coordination-strategy.md` — and the reviewability
ceiling appears as a trigger nowhere outside the Stated Preference branch (this
strengthens, and is checkable by, existing AC4)."

---

## Issue 2: Document split_rationale and emit its branch

**Finding — weak conditional (adjacent to Pattern 7).** AC1: "`plan-format.md`
documents the field, its condition, and the requirement that the entry name its
branch." The real condition is a two-disjunct OR (`execution_mode != single-pr` OR
`single-pr` departing from an `atomic` preference). A wrong implementation that
documents only the first disjunct ("required when execution_mode is multi-pr")
satisfies "documents...its condition" literally while omitting the departure case
Issue 4 depends on.

*Corrected AC1:* "`plan-format.md` documents `split_rationale` as required exactly
when `execution_mode` is not `single-pr`, OR when `execution_mode` is `single-pr`
and the repository's resolved Delivery Preference is `atomic` — both disjuncts
stated explicitly — and documents that the entry must name one of the three
`split-triggers.md` branches by name."

**Finding — Pattern 3 (happy-path only, issue-level, automated).** No AC covers the
invalid case: a `split_rationale` present but naming none of the three branches.

*Add:* "The doc states that a `split_rationale` value present but not naming one of
the three branches fails `L09` (Issue 3) — so the format contract and the check
agree on what 'names a branch' requires."

---

## Issue 3: Implement the L09 record check

**Finding — incomplete branch coverage (the reviewer's specific concern, confirmed).**
AC3: "`L09` does not fire on a `single-pr` PLAN with no field, in a repository
stating no delivery preference." This is not discriminating at Issue 3's point in the
sequence, and not for the reason "the field doesn't exist yet" — `resolve_claude_md_header`
is a generic walker (already shipped, used by `resolve_doc_visibility`) that matches
literal header text regardless of whether Issue 4 has documented `Delivery Preference`
in the registry. A CLAUDE.md stating `## Delivery Preference: atomic` could be
constructed for a test today. The gap is that AC3 only exercises the "no header"
input. A wrong implementation that stubs the departure branch to always report
`consolidated` — i.e., never calls the resolver, or discards its result — passes AC3
identically to a correct implementation, because neither is asked to prove the
resolver returns `atomic` when a CLAUDE.md says so. That positive test only appears
later, in Issue 4 AC6 ("`L09` fires on a `single-pr` plan in an `atomic` repository
with no record") — meaning between Issue 3 and Issue 4 landing, nothing in Issue 3's
own test suite proves the departure branch's resolver call is wired up at all.

*Corrected AC3 (add the missing direction, don't just keep the negative one):*
"`L09` does not fire on a `single-pr` PLAN with no field, in a repository stating no
delivery preference; AND `L09` fires on a `single-pr` PLAN with no field, in a
repository whose CLAUDE.md states `## Delivery Preference: atomic` — constructed
directly in the test fixture for this issue, independent of whether Issue 4 has yet
added the header to the registry documentation, since `resolve_claude_md_header`
only needs the literal header text to exist."

---

## Issue 4: Add the delivery-preference header

**Finding — Pattern 5 (integration scope gap) plus unchecked wording (the reviewer's
specific concern, confirmed).** AC2: "A repository declaring `atomic` produces a
multi-PR shape... the same change in a `consolidated` repository produces
`single-pr`. The two runs differ only in the header." This behavior lives entirely in
skill prose (step 3.6 is LLM-followed guidance, not code), so it is only observable
by actually running `/plan` twice — there is no unit-testable surface, which is a
legitimate Pattern 5 case (integration is the only observable path; the guard for
"could a unit test also catch it" fails here because there is no unit under test).
Separately, "the two runs differ only in the header" is ambiguous: read literally it
would mean the *outputs* differ only in the header, which is false (execution_mode
and everything downstream necessarily differ) — it must mean the *inputs* differ only
in the header, but as written it doesn't pin the causal chain to the header-parsing
step specifically. A wrong implementation that branches on something incidentally
correlated with the two test fixtures (e.g., repo path, file size, presence of any
second-level heading) rather than the parsed header value could still produce two
differently-shaped runs across two repos that happen to differ only in that one line,
and nothing in AC2 as stated would catch that the causal link ran through the actual
header parse rather than a coincidence of the fixture.

*Corrected AC2:* "Using two CLAUDE.md files identical except for the `Delivery
Preference` header value (`atomic` vs `consolidated`), and the same decomposition
input, step 3.6 resolves a different preference value in each case, and the
`execution_mode` recommendation differs solely as a function of that resolved value —
verified by inspecting the value step 3.6 recorded as having consulted (e.g., the
branch name written into the decomposition artifact), not only by comparing the two
plans' final shapes end to end."

---

## Issue 5: Add the tracking-level header and gate issue creation on it

No AC-level findings — AC2's "confirmed by what was created" already bakes in the
three distinct expected outcomes per combination, which is discriminating.

**Finding — Pattern 3 (happy-path only, issue-level, automated).** No AC covers an
unrecognized/malformed header value. The design's own Security Considerations section
states the required mitigation explicitly ("an unrecognized value falls through to
the default rather than being used") but no Issue 5 AC tests it.

*Add:* "A repository whose CLAUDE.md states `## Tracking Level:` with a value outside
`none|issues|issues-and-milestone` falls back to the default rather than being used or
causing an error, matching the design's stated mitigation for untrusted
configuration."

---

## Issue 6: Re-key the approval gate and amend its decision record (REVISED — re-judged against the new text)

The AC is now a concrete command: `grep -rn "human approval\|human-approval"
skills/ crates/ docs/` must return only the amendment's own quotation. This is
mechanically executable, which resolves half of my earlier concern — but running
it against the actual current tree shows the pattern itself has confirmed,
demonstrable false negatives, and the Goal's own site count is wrong, which
together make the AC pass for an incomplete fix.

**Finding — the grep pattern misses two of the sites the Goal names, by exact
line, verified against current source:**

1. `crates/shirabe-validate/src/lifecycle.rs:764` — `/// (human-approved for
   multi-pr, auto-fired for single-pr), so the` — reads "human-approved"
   (participle), not "human approval" or "human-approval" (noun). The regex
   `human approval\|human-approval` does not match "human-approved." This is a
   *separate* comment from the module doc (lines 45-61, which does use matching
   phrasing at 52 and 61) — the Goal's phrase "lifecycle.rs's module doc" names
   only the module doc, so this second site in the same file isn't even
   identified as something to fix, let alone written in a form the grep catches.
2. `skills/plan/references/phases/phase-7-creation.md:263` — "no multi-pr-style
   **approval gate** fires" — no word "human" appears in or near this sentence at
   all, so it can't match either alternative in the pattern. This is one of the
   Goal's own "five... in skill and format prose" sites, and it evades the AC's
   verification command entirely.

A wrong implementation that re-keys every site the grep can see, and leaves these
two exactly as they are today (still stating the old `execution_mode`-keyed rule
in different words), passes `grep -rn "human approval\|human-approval" skills/
crates/ docs/` cleanly — it returns nothing outside the amendment's quotation,
because it never sees either site.

**Finding — the Goal's site count is wrong, independent of the grep issue.**
"Two in Rust doc comments (`lifecycle.rs`'s module doc and two comment sites in
`transition.rs`)" undercounts what's actually in the tree today:
`crates/shirabe-validate/src/transition.rs` carries the same rule at four sites
(lines 263, 469, 1960, 2011 — confirmed by reading each: all are comments
describing the Draft→Active gate firing "under human approval" for multi-pr),
not two. `lifecycle.rs` carries it at two sites (the module doc, and the
separate comment at line 764), not one. Real total is 5 prose + 6 Rust = 11
sites, not the stated 7. An implementer who edits exactly what the Goal lists
(module doc + two `transition.rs` comments) leaves two `transition.rs` sites
(469, one of 263/1960/2011 depending on which two were picked) untouched, and —
per the finding above — the grep AC would not reliably catch the miss either,
since it depends on which two of the four got picked and whether their exact
wording matches the pattern.

*Corrected AC4:* "`grep -rn -i \"human.approv\" skills/ crates/ docs/` (note:
`.` not a literal space/hyphen, so it also matches `human-approved`) returns
nothing outside the amendment's own quotation of the old text — AND every one of
the following eleven sites has been re-keyed, enumerated explicitly rather than
left to the Goal's undercount: the five prose sites, `lifecycle.rs`'s module doc
(lines 52, 61) and its line-764 comment, and all four `transition.rs` comment
sites (lines 263, 469, 1960, 2011)."

**Finding — Pattern 3 (happy-path only, issue-level, automated).** No AC verifies the
gate's actual runtime behavior — only that the tables and prose say the right thing.
Given the gate is human-mediated prose with no code implementation (per the design),
this is largely unavoidable, but the two new reachable combinations deserve a
behavioral check where one exists (Phase 7's issue-creation call, which *is* code).

*Add:* "Attempting a Draft→Active transition whose resolved tracking level is not
`none` is blocked without recorded approval, and a `multi-pr` + `none` transition
proceeds without requiring it — verified against Phase 7's actual issue-creation gate,
not only the transition-table prose."

---

## Issue 7: Emit issueless multi-pr work items from the plan's outlines

**Finding — vacuous pass via empty edge set.** AC1: "every dependency edge resolves
to a declared work item, with no unresolved keys." This is a universally-quantified
claim over the set of dependency edges; if that set is empty the claim is vacuously
true. A wrong implementation that fails to parse or emit any `Dependencies` edges at
all — turning every `plan_item` into an isolated node — satisfies AC1 exactly as well
as a correct implementation, unless the test plan is guaranteed to contain at least
one real dependency edge (most real plans do, including this one).

*Corrected AC1:* "A `multi-pr` plan with tracking `none`, containing at least one
outline whose `Dependencies` field references another outline by title, yields a task
graph in which every dependency edge resolves to a declared work item with no
unresolved keys — AND an outline whose `Dependencies` field references a title not
present in the outline list produces an unresolved-key error rather than a silently
dropped edge."

**Finding — Pattern 3 (happy-path only, issue-level, automated).** Confirms the above:
no AC in the issue covers the failure/edge case of an unresolvable dependency
reference; folded into the corrected AC1 above rather than listed separately.

---

## Issue 8: Amend Decision 6 of the roadmap-plan-standardization design

**Finding 1 — reasoned Pattern-7 analog (the reviewer's specific concern, confirmed).**
AC1: "Decision 6 carries an amendment naming what changed and what did not." A wrong
implementation could add: "Note: this decision has been updated — see
DESIGN-multi-pr-plan-decoupling.md for details," which "carries an amendment" and
gestures at "what changed" only by reference, never stating in Decision 6's own text
either the specific change or what is preserved.

*Corrected AC1:* "Decision 6 carries an amendment that states, in its own text: (a)
the single-pr default is now conditional on the repository's resolved Delivery
Preference, and (b) the decomposition-strategy/execution-mode de-conflation and the
value-based re-anchoring of the roadmap case are unchanged — not a generic pointer to
'see the other design.'"

**Finding 2 — unbounded comparative constraint.** AC2: "The amendment cites this
design rather than restating its reasoning." Nothing bounds how much restatement is
disqualifying; a wrong implementation could restate most of Decision A/Decision
Outcome's reasoning in its own words while also including a citation link, and
literally satisfy "cites this design" (true) without falsifying "rather than
restating" (unbounded, so unenforceable as written).

*Corrected AC2:* "The amendment cites `DESIGN-multi-pr-plan-decoupling.md` for the
reasoning behind the conditional default and is no more than two or three sentences —
it does not independently re-argue why the header exists or reproduce the design's
alternatives analysis."

**Finding 3 — Pattern 3 (happy-path only, issue-level, automated).** No AC covers what
the amendment must *not* do beyond deletion (AC3 already covers deletion). A wrong
implementation could splice amendment content into the middle of the original
decision's paragraphs, disguised as if it were part of the original text, satisfying
"nothing is deleted" while still altering how the original reads.

*Add:* "The amendment is appended as a clearly separated section (not interleaved
into the original decision's paragraphs) and is not phrased as superseding the
decision."

---

## Summary

8/8 issues carry at least one Category C finding. Pattern 3 (happy-path-only,
automated) affects six of eight issues — only Issue 3 (has "error") and Issue 4
(has "conflicting"/"failing") avoid it, and Issue 4 still has a separate Pattern 5
finding. The reviewer's four flagged concerns all confirmed as genuine findings:
Issue 1's existence-only AC1, Issue 3's vacuous departure-branch test, Issue 4's
unchecked causal wording, and Issue 6's grep — which, now that the AC gives a
concrete command, was checked against the actual current source and confirmed to
miss two real sites by exact line (`lifecycle.rs:764` uses "human-approved," which
the pattern doesn't match; `phase-7-creation.md:263` says "approval gate" with no
"human" nearby at all) plus a wrong site count in the Goal (`transition.rs` has
four occurrences, not two). Issue 8's three ACs are indeed all prose-presence
checks, two of which are under-specified enough to pass a non-answer. Issue 5's
Dependencies and tracking_level-persistence changes were re-checked against the
current plan text and don't introduce or resolve any AC-discriminability finding —
the persistence AC (line 214-216) remains solid as written.
