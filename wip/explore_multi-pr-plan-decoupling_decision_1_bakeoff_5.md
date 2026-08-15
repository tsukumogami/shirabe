# Bakeoff: Alternative 5 -- Record-the-reason first, decide the posture later

## Position

Alternative 5 says: don't answer "should P1 be invertible" yet. Build the
durable slot that records *why* a given plan is `multi-pr`, and a validator
check that a `multi-pr` plan carries one. Everything else -- Option 1's
inversion, Option 2's third branch, Option 3's sibling principle -- can be
layered on top later without touching this slot's shape.

## 1. Strengths

**It closes a gap every other option quietly depends on and none of them
close.** The research doc's Finding 4 is unambiguous: `grep -n "trigger"
crates/shirabe-validate/src/*.rs` returns zero hits
(`wip/explore_multi-pr-plan-decoupling_decision_1_research.md:163-164`). I
re-ran the equivalent search myself against `formats.rs`, `validate.rs`, and
`lifecycle.rs` and confirm it: nothing in the validator checks that a
non-single-pr plan names a constraint. The `plan/v1` `FormatSpec` in
`crates/shirabe-validate/src/formats.rs:336` declares `required_fields:
s(&["status", "execution_mode", "milestone", "issue_count"])` -- no rationale
field, no trigger field. `skills/plan/references/plan-format.md:34-53`
confirms the same from the doc side: the frontmatter contract lists exactly
those four required fields plus optional `upstream`, and nothing else.

**The requirement is already stated, just unenforced.** `skills/plan/SKILL.md`
verified at line 154: "The constraint must be named in the PLAN doc." That
sentence already exists, today, unconditionally -- it doesn't wait on this
decision. Alternative 5 is the option that makes an existing sentence true
rather than the option that adds a new one. That's a meaningfully different
risk profile than Options 1-3, each of which is proposing new prose to write
and hoping it's followed.

**The same gap exists one altitude up, confirming this isn't a one-off.**
`references/coordination-strategy.md:126-138`, the Coarsest-Legal-Grouping
Rule, uses the identical "recorded trigger" language ("A repo splits into
more than one PR only on a recorded trigger... Absent a recorded trigger, do
not split"). I read the coordination PR body template at
`coordination-strategy.md:83-109` in full: the PR Index records
`owner/repo:path#number` and merge-state; the Merge Order block records node
ids and merge-state. Neither has a slot for which of the four triggers fired.
So the "record why you split" obligation is stated at both altitudes and
enforced at neither -- this is a systemic gap in the artifact family, not an
incidental oversight local to `/plan`. Alternative 5 is the one alternative
whose blast radius naturally covers both altitudes with one shape, because
it's fixing the shared underlying defect (missing schema slot) rather than
relitigating the P1-vs-coordination disagreement that sits on top of it.

**It delivers the author's actual stated goal directly.** The context doc is
explicit: "the author's own position... they want multi-pr to be reliable
evidence that no other option existed"
(`wip/explore_multi-pr-plan-decoupling_decision_1_context.md:112-116`). A
recorded, validated reason is that goal, verbatim -- not a proxy for it. A
preference header (Option 1) delivers trust only indirectly and by
assumption: it makes `multi-pr` legible as "the configured default fired,"
but per the research's own Finding 4 framing, it doesn't make the *harder*
claim -- "this specific split was justified" -- checkable at all, because
under `atomic` nothing has to be justified per split, only the posture has
to be set once, org-wide. A recorded-reason slot is checkable per plan,
every time, regardless of which posture produced it.

**It has a ready enforcement home with no new subsystem.** I verified
`crates/shirabe-validate/src/validate.rs:110-113`:

```rust
pub fn posture_class(code: &str) -> PostureClass {
    match code {
        "L02" | "L06" | "L07" => PostureClass::DraftTolerable,
        _ => PostureClass::AlwaysEnforced,
    }
}
```

This is a flat, hardcoded match -- adding a fourth code (say `L09`, next
available per the lifecycle.rs doc comments at lines 20-35 which enumerate
L02/L06/L07 by name) is a one-line addition to this match, not a new
mechanism. `advisory.rs:144` and `:185` already consume `posture_class`
generically via `posture_class(&e.code) == PostureClass::DraftTolerable`, so
the advisory layer needs zero changes -- it already treats any
`DraftTolerable`-classed code as notice-in-draft, error-in-ready. The
`lifecycle.rs` file already has the pattern to copy: L02's orphan check
(`lifecycle.rs:1347-1356`) and L07's location check
(`lifecycle.rs:1368-1406`) are both "does this document's declared state
satisfy an invariant, emit a coded finding if not" -- a new "does this
`multi-pr`/`coordinated` plan's frontmatter or body carry a rationale, emit a
finding if not" check is the same shape, not a new kind of check.

## 2. Weaknesses

**It gives an atomic-preferring org nothing to configure.** This is stated
plainly in the alternatives doc itself
(`wip/explore_multi-pr-plan-decoupling_decision_1_alternatives.md:93`): "it
does not itself give an atomic-preferring org anything to configure." The
context doc is explicit that this matters: "they explicitly recognize that
orgs with many reviewers may legitimately prefer small atomic increments, and
want that to be honored configuration" (`decision_1_context.md:115-116`).
Alternative 5, shipped alone, does not honor that. A many-reviewer org still
gets P1's single-pr default and still has to name a constraint or value
argument for every split, exactly as today -- record-the-reason doesn't
change *when* multi-pr fires, only whether the firing is checkable.

**It may be read as a prerequisite rather than an answer to the question
actually asked.** The decision question is explicitly binary: "Should a
repo-level PR-delivery preference be able to override principle P1's
single-PR default outright, or should reviewability instead become a named
split trigger with a configurable threshold under P1"
(`decision_1_context.md:5-9`). Alternative 5 answers neither branch. If the
synthesis needs a chosen posture-relationship by the end of this decision
(because downstream work -- the decomposition half of the theme, per
`decision_1_context.md:106-110` -- is blocked on exactly this question),
shipping only Alternative 5 leaves that downstream work still blocked. A
sole-contributor author who wants `/plan` to actually decompose differently
in an atomic repo gets nothing actionable from Alternative 5 alone.

**It doesn't resolve the actual contradiction the constraints section names
as the thing that "must" be reconciled.** `decision_1_context.md:22-30` frames
the resolution requirement as reconciling P1's "never by mechanism" against
`coordination-strategy.md`'s shipped reviewability trigger. Recording a
reason for whichever mode gets chosen says nothing about whether
reviewability *is* a legitimate reason. It sidesteps the contradiction rather
than resolving it -- which is fine if the synthesis wants to sequence the
work, but it does not satisfy the constraint as literally written if that
constraint is read as "this decision must pick a resolution."

## 3. Risks

- **Scope-field bikeshed.** Frontmatter field vs. body section vs. table
  column is a real design choice (below) and picking wrong creates the same
  "restated in two places, drifts" failure P4 is written to prevent
  (`decision_1_research.md:88-106`, Finding 2's P4 discussion) -- except now
  applied to the rationale slot itself rather than the trigger list.
- **Under-scoping the check.** A validator check that merely requires the
  field to be *non-empty* (rather than drawn from an enumerated,
  machine-checkable set of named constraints) gives false confidence --
  "recorded" stops meaning "verifiably one of the legitimate reasons" and
  degrades to "some prose exists." Research Finding 4's critique of Option
  2's unbuilt validation applies with equal force to a sloppily built
  Alternative 5: an unenforced or under-enforced field is barely better than
  no field.
- **Silent scope creep into deciding the posture question anyway.** Once a
  rationale field exists, the natural next question -- "which values are
  legal in this field?" -- reintroduces Options 1/2/3's disagreement through
  the back door (an enum of legal reasons *is* a policy about what's allowed
  to force a split). Alternative 5 has to resist populating that enum now, or
  it isn't actually deferring the posture question, just moving it into a
  field-values discussion.
- **Downstream work stays blocked longer than the author may tolerate.** If
  the decomposition half of the theme (per `decision_1_context.md:108`, "the
  decomposition half is blocked on exactly this question") is time-sensitive,
  shipping only the recording mechanism defers the higher-value half of the
  ask to an undetermined follow-up decision.

## 4. Implementation implications

**Where the slot goes: frontmatter field, not a named section.**

Two candidate section-based homes exist and both are wrong fits on inspection:

- `Decomposition Strategy` is a required section in both single-pr and
  multi-pr profiles (`formats.rs:338-345`, `:161-180`
  `plan_execution_mode_sections()`), and its quality guidance
  (`plan-format.md:300-306`) is explicit that it "names the slicing axis...
  and the grouping rule" -- that's a *how the work was cut* question, not a
  *why this plan isn't one PR* question. `skills/plan/SKILL.md:139-142`
  deliberately separates these: "This is a separate decision from the
  Decomposition Strategy above... Don't conflate the two." Putting the
  rationale in that section re-conflates exactly what SKILL.md just
  separated.
- A brand-new required section (`## Execution Mode Rationale` or similar)
  is heavier than necessary for what's typically a one-line fact ("hard
  constraint: X" or "value: Y"), and section-presence checks (FC04) are a
  blunter instrument than field-presence checks (FC01) for something this
  short.

A frontmatter field is the better fit, and it has direct precedent already
in the same `formats()` table: the `Design` `FormatSpec` at `formats.rs:232`
already declares `required_fields: s(&["status", "problem", "decision",
"rationale"])` -- a `rationale` field sitting right next to `decision` is
exactly the shape being proposed here for Plan. This isn't a novel pattern
being introduced into the schema family; it's applying an existing pattern
(justification-as-frontmatter-field) to a format that's missing it.

Concretely:

- `skills/plan/references/plan-format.md:19-53` -- add a `split_rationale`
  (or similarly named) field to the frontmatter block shown at line 23-31,
  documented alongside `execution_mode`, required when `execution_mode !=
  single-pr`, holding either the named hard constraint or the value
  statement from SKILL.md's two-branch test. Free text is enough at this
  stage; do not pre-populate an enum (see Risk 3 above).
- `crates/shirabe-validate/src/formats.rs:336` -- this single line is the
  entire schema-declaration change:
  `required_fields: s(&["status", "execution_mode", "milestone",
  "issue_count", "split_rationale"])` -- except conditioned on
  `execution_mode`, which the existing `required_fields` mechanism doesn't
  support (it's unconditional per the `FormatSpec` struct at lines 68-140).
  That means either (a) a new conditional-field mechanism analogous to
  `execution_mode_required_sections` (`formats.rs:107-112`, already proven
  for sections, would need a sibling for fields), or (b) make the field
  always-present but valid-empty-for-single-pr, checked by a lifecycle-style
  finding rather than FC01. Given `execution_mode_required_sections` already
  exists as a precedent for execution-mode-conditional requirements, (a) is
  the more consistent choice and smaller conceptually, but it is new surface
  the research's blast-radius table for Option 2 did not have to pay
  (`decision_1_research.md:216-219`, the `plan-format.md` / PLAN frontmatter
  row already flags this as "recommended, not required" under every option
  -- Alternative 5 is where it stops being optional).
- `crates/shirabe-validate/src/validate.rs:112` -- add a new lifecycle code
  (next available after L02/L06/L07 per the doc comments at `lifecycle.rs`
  lines 20-35; the file's own numbering suggests something like `L09`, since
  L08 already exists per `lifecycle.rs:3464`'s test reference) to the
  `DraftTolerable` match arm: `"L02" | "L06" | "L07" | "L09" =>
  PostureClass::DraftTolerable`. This reuses the exact
  notice-in-draft/error-in-ready posture the constraints section already
  requires (`decision_1_context.md:42-45`).
- `crates/shirabe-validate/src/lifecycle.rs` -- new check function alongside
  the L02 (`lifecycle.rs:1347-1356`) and L07 (`:1368-1406`) implementations:
  for a document whose `execution_mode` is `multi-pr` or `coordinated`,
  verify `split_rationale` is present and non-empty (or, if section-based
  instead of field-based, verify the named section exists and is non-empty).
  `advisory.rs` needs no change -- it already generalizes over any
  `DraftTolerable` code.
- `references/coordination-strategy.md:83-109` -- the coordination PR body
  template's PR Index row format gains a trigger-name column or inline
  annotation (e.g. `<node-id> | <owner/repo:path#number> | <merge-state> |
  <trigger>`), since this is the one-altitude-up sibling of the same gap
  (Finding 4's second half). This is optional scope for a first cut but
  should at minimum be named as deferred follow-up, not silently dropped,
  given the research explicitly identified it as the same defect.

## 5. Recommendation

Alternative 5 is honestly better understood as a **sequencing answer that
composes with Option 1 or Option 2, not a competitor to either.** It answers
a different question than the one posed. The decision question asks which
*posture relationship* should hold between a repo preference and P1; 
Alternative 5 answers "regardless of which posture relationship you pick,
build the enforcement plumbing that makes the outcome checkable" -- and the
research is clear that plumbing is currently absent under every option, not
just some of them (`decision_1_research.md:174-182`, explicit: "Choosing
Option 2 without also building trigger-recording and validation... delivers
exactly the same trust erosion Option 1 is criticized for"). That sentence
generalizes to Option 1 and Option 3 too: none of the four original options
include this plumbing, so all four benefit from it, and none of them are
made unnecessary by it.

Given that, the honest recommendation is: don't present Alternative 5 as
alternative-5-among-five. Present it as a **P0 sequencing step that precedes
whichever of Options 1/2/3 the synthesis lands on**, sized as its own small
scope (frontmatter field, one FormatSpec line plus a new conditional-field
mechanism, one lifecycle check, one DraftTolerable match arm) that ships
first and is unaffected by which posture-relationship gets chosen afterward.
That framing also resolves Weakness 2 (does it answer the actual question) --
it doesn't, and shouldn't be scored as if it were trying to. If the synthesis
needs a single-answer recommendation to the literal question asked, my
answer is Option 1 for the posture question (cheapest under P2, per
`decision_1_research.md:65-73`, and doesn't collide with the 3.5a
value-confirmation guard the way Option 2 does per Finding 3) -- but ship
Alternative 5 underneath it regardless of which posture option wins, because
Finding 4 shows the trust claim is fiction without it, for every option on
the table, including whichever one is chosen.
