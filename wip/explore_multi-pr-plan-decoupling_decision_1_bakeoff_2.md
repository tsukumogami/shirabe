# Bakeoff: Alternative 2 -- Reviewability as a named trigger under P1

Validator position: arguing FOR this alternative.

## 1. Strengths

**P4 is the strongest argument for this shape, and it's stronger than the
alternatives text gives it credit for.** `references/workflow-principles.md`
P4 states the rule directly: "Each shared shape... has a single source both
workflows consume. Per-skill restatement is the drift source the
standardization removes." Today, `references/coordination-strategy.md`'s
Coarsest-Legal-Grouping Rule (lines 126-138) already contains a trigger list
with "a single PR would exceed the configured reviewability ceiling" as a
named, first-class member, sitting directly alongside "independently
mergeable," "independently rollback-able," and "breaks a merge-order cycle."
`workflow-principles.md` P1 (lines 12-17) governs the exact same
single-PR-vs-split question one altitude down and excludes reviewability by
construction. That is not two principles that happen to overlap -- it is one
concern (when does a delivery unit legitimately split) defined twice, once
per altitude, disagreeing with itself. P4 doesn't merely permit fixing that;
it names this specific shape of problem as the one it exists to prevent.
Alternative 1 and Alternative 3 both leave the duplication in place (Option 1
introduces a third framing -- posture inversion -- alongside two existing
trigger lists that still disagree; Option 3 adds a second principle
competing with P1 without addressing that coordination-strategy.md's trigger
list still sits unfactored). Alternative 2 is the only option whose premise
is "these are the same rule, phrased at two altitudes" rather than "these are
different rules that can coexist."

**`multi-pr` keeps a uniform meaning.** This is the concrete form of the
author's stated trust goal (context file, "Any option that leaves 'multi-pr'
ambiguous between 'was forced' and 'was preferred' fails that goal"). Under
Alternative 1, `execution_mode: multi-pr` means "the repo default fired" in
an `atomic` repo and "something forced it" in a `consolidated` repo -- the
same enum value carries two different claims depending on a header the
reader may not have open. Under Alternative 2, `multi-pr` always means "a
named trigger fired," full stop, everywhere. A reader auditing a plan asks
one question regardless of which repo they're in: which of the three
branches fired, and is it named. That invariance is worth defending even
where (see Weakness 4(b) below) the trigger itself needs sharper definition.

**Widening a closed list is a smaller, more honest amendment than reversing
a prohibition.** P1's affirmative test (hard constraint OR incremental
value) is exhaustive by construction -- the research document's Finding 1
confirms this reading and even the context file's own framing agrees P1 is
"a closed escape list." Reversing a prohibition (Alternative 1's move: "the
single-PR default is the shipped default, not a universal") changes what P1
*asserts about the world* -- it stops being a claim that only two things
justify a split and becomes a claim that depends on unstated per-repo
configuration to even parse. Widening the list to three items changes what
P1 *permits* while leaving its assertion structure (a closed, named,
checkable set) completely intact. The amendment is textually smaller (one
new bullet under an existing two-item list, versus a rewritten opening
sentence) and semantically smaller (P1 continues to say exactly what it said
before for every repo that doesn't set a low ceiling) than Alternative 1's
move.

**No new CLAUDE.md header, no naming collision.** I verified directly:
`skills/plan/SKILL.md:258` already reads `## Execution Mode:` for the
`auto|interactive` autonomy setting, confirming the context file's stated
naming collision is real and already shipped. Alternative 1 needs an
entirely new header (`## PR Delivery Preference: consolidated|atomic`) to
avoid that collision -- new surface, new precedence resolution, new doc
section in `references/fixes/claude-md-conventions.md`. Alternative 2 needs
none of that: `## Reviewability Ceiling:` already exists in shirabe's own
`CLAUDE.md` (lines 59-69) with the `flag > CLAUDE.md-header > default`
precedence chain already wired, already documented as "a durable workspace
preference." An org that wants atomic-leaning behavior sets a low ceiling in
a header that already ships. This is the cheapest possible tunable: zero new
config surface, one existing header whose scope widens from
coordination-only to coordination-and-plan.

## 2. Weaknesses -- confronted directly

### 2(a): The reviewability ceiling has no definition anywhere in the repo

I verified this myself and it is exactly as stated in the research. I read
`CLAUDE.md:59-69` in full: `## Reviewability Ceiling: default` resolves to
"the ceiling defined in `references/coordination-strategy.md`." I then read
`coordination-strategy.md` in full (`references/coordination-strategy.md`)
-- the Coarsest-Legal-Grouping Rule (lines 126-138) says only "a single PR
would exceed the configured reviewability ceiling." No number, no line
count, no file count, no issue count, anywhere in that file or in
`docs/guides/coordinated-multi-repo.md`. The header is a knob wired to
nothing. This is a real blocker for Alternative 2 specifically, more than
for Alternative 1 or 3, because Alternative 2 makes the ceiling the
*operative test in a principle*, not an optional coordination-level
refinement -- P1 is cited by name across skill surfaces and a prior design
decision (`DESIGN-roadmap-plan-standardization.md` Decision 6); shipping a
principle whose third branch resolves to an undefined threshold is worse
than shipping a coordination-level nicety that quietly does nothing.

**Concrete proposal, not a concession.** The ceiling needs a metric an agent
can evaluate *before the diff exists* -- at Phase 3.6, decomposition is
already artifact-shaped (an issue table with per-issue file lists, from
`skills/plan/references/plan-format.md`'s Implementation Issues table
contract: "Files field names the files the issue touches"). Two candidate
pre-diff proxies are already sitting in that artifact:

- **Files-touched count**, summed across the PR-shaped unit's constituent
  issues' `Files` fields. This is directly readable from the decomposition
  artifact at 3.6, before any code is written, and correlates with review
  burden better than line count (a 40-file mechanical rename reviews faster
  than a 4-file algorithmic change, but file count is at least an honest,
  cheap, pre-diff signal -- unlike line count, which cannot be known before
  the diff exists at all).
- **Issue count bundled into one PR-shaped unit.** Simpler, already present
  as `issue_count` in PLAN frontmatter (`plan-format.md:34`), and avoids
  needing per-issue file estimates to be accurate.

Recommend: `## Reviewability Ceiling: <N files>` (default e.g. `15`, an
explicit placeholder value scoped as follow-up calibration, not a blocker to
shipping the mechanism) evaluated as "sum of `Files` entries across a
PR-shaped unit's issues, pre-decomposition-collapse." This is measurable,
cheap, and available at exactly the point 3.6 needs it. I am proposing this
rather than conceding the blocker, but I'll be direct about its weakness:
files-touched is a proxy for reviewability, not identical to it, and the
default numeric value is asserted here, not derived from any existing
practice in the repo -- that calibration is real follow-up work, named as
such rather than assumed solved, per the research document's Finding 5
closing recommendation.

### 2(b): A pre-implementation estimate is itself mechanism-derived splitting

This is the sharper of the two objections and I will not soften it: the
research document's Finding 3 is right that promoting the ceiling to plan
altitude collides with 3.5a (`skills/plan/references/phases/phase-3-
decomposition.md:403-486`), and I read 3.5a in full to check this myself.
3.5a's test is "if this unit landed alone, would a reader observe value, or
only a building block someone has to wait on" -- a question about the
*shape of the resulting PR*, asked independently of why it was split. A
ceiling-triggered split at 1,000 lines of a coherent 2,000-line feature does
not, by construction, guarantee the two halves clear that bar -- the
research is correct that this is a real, unresolved collision, not a minor
wrinkle.

But I don't think this makes the ceiling *itself* mechanism-derived
splitting in the sense P1's "never by mechanism" clause targets. P1's own
worked example -- "because the input is a roadmap" -- excludes reasoning
from a property of the *input artifact's type* to a split decision, with no
reference to value at all. The reviewability ceiling is different in kind:
it's a property of the *output the split would produce* (how much a
reviewer has to hold in their head), and Alternative 2's own design keeps
3.5a downstream and mandatory regardless of which branch fired ("Apply this
check whether or not a hard constraint also forces the split," phase-3-
decomposition.md:427). So the honest framing is: the ceiling is a
legitimate, non-mechanism *reason to attempt* a split, but it is not by
itself sufficient to *justify* the resulting shape -- 3.5a still has to pass
on each half. Where I side with the research over the alternatives-doc
framing: this makes Alternative 2 more expensive than advertised, because it
requires 3.5a to gain an explicit answer for what happens when a
ceiling-triggered split *fails* the value guard. Today 3.5a's failure path
(interactive: re-scope or merge with a neighbor; `--auto`: recorded
`assumed` at high review priority, decision-protocol.md) already exists and
generalizes without a rewrite -- a ceiling-forced split that fails 3.5a
routes to the same `assumed`-high-review-priority record any other failing
unit gets, surfaced in the PR body per `decision-block-format.md`. That is
not a new guard behavior; it's the existing guard applied to a case it
wasn't previously reachable from. I'll state the position plainly rather
than hedge: this closes the collision, it doesn't dodge it -- a
ceiling-triggered split that can't produce independently valuable halves
gets flagged, not silently split anyway, exactly as 3.5a already does for
every other case. If the decision synthesis wants a stronger guarantee than
"flagged for human/agent review," that is a real scope decision to make
explicitly, not a gap in this proposal.

### The other three triggers cannot be lifted verbatim

Confirmed directly against the alternatives document's own claim and the
research's Finding 3, which I re-derived independently: "independently
mergeable" and "independently rollback-able" are properties that hold for
almost any well-decomposed multi-issue plan -- at plan altitude, unlike
coordination altitude, there is no natural "one repo's worth of work"
boundary keeping the unit coarse by default, so these two triggers would
fire on nearly every plan with more than one issue, defeating the P2
lowest-ceremony default entirely. The fourth trigger (breaks a merge-order
cycle) is meaningless without a DAG -- `coordination-strategy.md`'s
Merge-Order Model (lines 140-158) is explicitly a two-node `(repo,
pr_group)` structure that doesn't exist at single-repo plan altitude.
**Conceding this precisely:** Alternative 2 is not "lift the
Coarsest-Legal-Grouping Rule's trigger list up a level." It is "author a new,
plan-altitude trigger list that shares exactly one member (the reviewability
ceiling) with the coordination-altitude list, and extract that one shared
member into a common reference per P4." The other two plan-altitude branches
(hard constraint, incremental value) are already P1's own two branches,
unchanged. So the "lift" is real for one trigger and fictional for the
other three -- the alternatives document's phrasing ("The trigger list is
lifted... up to plan level") overstates by implying a four-item transplant;
it's a one-item transplant into an otherwise-unchanged two-item test.

## 3. Risks

- **Undefined ceiling ships as a no-op.** If `## Reviewability Ceiling:
  default` remains textually undefined when Alternative 2 ships, the third
  branch is decorative -- P1 gains a clause an agent can never actually
  trigger, which is worse than not adding it, because it reads as covered
  when it isn't. This must not ship without Weakness 2(a)'s concrete metric
  landing in the same PR.
- **3.5a becomes a silent escape hatch if its failure path isn't wired for
  the new branch.** If a ceiling-triggered split is allowed to bypass 3.5a
  (rather than routing through the existing assumed/high-review-priority
  path), Alternative 2 reintroduces exactly the "split by mechanism, value
  unconfirmed" failure P1 exists to prevent -- just gated by a size number
  instead of an artifact-type check. The fix in 2(b) must be implemented,
  not merely described.
- **P4-conformant extraction is optional-in-practice unless enforced.**
  Nothing stops an implementer from copy-pasting the ceiling clause into
  `workflow-principles.md` prose instead of extracting a shared
  `references/split-triggers.md` (or equivalent). The research's Finding 2
  is explicit that this is the P4-violating failure mode. Recommend the
  PLAN for this work names the extraction as an explicit acceptance
  criterion, not an implementer's judgment call.
- **The trust claim is not free.** Per the research's Finding 4, which I
  confirmed independently below, "recorded trigger" has zero enforcement
  today anywhere in the tree. Alternative 2's headline advantage over
  Alternative 1 (a checkable trust signal) is currently aspirational. Ship
  Alternative 2 without the recording/validation work and it delivers no
  more trust than Alternative 1 -- prose that a reader has to take on faith.

## 4. Implementation implications

I traced the concrete surface myself rather than relying on the research
table alone:

- **`references/workflow-principles.md` P1** (lines 12-17): the two-branch
  test becomes three branches. New bullet under "Rules derived from this"
  (line 19 onward): "Multi-pr requires a named escape condition: a hard
  constraint forces multiple PRs... or each PR is independently useful...
  or the PR-shaped unit would exceed the configured reviewability ceiling."

- **New shared reference** (P4-conformant extraction, per Weakness/Finding
  2): e.g. `references/split-triggers.md`, holding the ceiling trigger's
  definition and the concrete pre-diff metric proposed in 2(a). Both
  `workflow-principles.md` P1 and `coordination-strategy.md`'s
  Coarsest-Legal-Grouping Rule (lines 126-138) cite it instead of each
  independently stating "exceeds the configured reviewability ceiling."

- **`CLAUDE.md:59-69` (`## Reviewability Ceiling:`)**: description widens
  from "the configured reviewability ceiling for a coordinated effort" to
  cover plan-level splits too, and gains the concrete metric and default
  value from 2(a) instead of "default defers to the ceiling defined in
  `references/coordination-strategy.md`" with no value behind it.

- **`skills/plan/SKILL.md`** "Execution Mode Decision" section (lines
  137-172): the escape-condition list (lines 150-159) gains a third
  numbered item citing the new shared reference. No new header needed here
  (confirmed: `## Execution Mode:` at line 258 is unrelated autonomy
  config, already collided-with by Alternative 1, untouched by Alternative
  2).

- **`skills/plan/references/phases/phase-3-decomposition.md`**:
  - 3.6 (lines 490-538): step 3 ("Recommend a mode," lines 514-522) gains a
    fourth bullet: PR-shaped unit exceeds the reviewability ceiling ->
    multi-pr with the ceiling trigger named.
  - 3.5a (lines 400-486): needs the explicit wiring from Weakness 2(b) --
    the existing pass/ambiguous/fail bucketing and the existing
    interactive/`--auto` failure paths (lines 446-475) already generalize;
    what's missing is a sentence stating explicitly that a ceiling-triggered
    split is subject to 3.5a exactly like a value-triggered split, with no
    carve-out. This is a documentation change, not new guard logic, but it
    must be written, not assumed.

- **`skills/plan/references/plan-format.md` frontmatter and the PLAN schema
  slot**: I confirmed the current schema has no place to record which
  branch fired. `required_fields: s(&["status", "execution_mode",
  "milestone", "issue_count"])` in `crates/shirabe-validate/src/
  formats.rs:336` -- `execution_mode` is a bare enum, and `plan-format.md`
  (lines 19-32) shows the same four required fields, no fifth. This is the
  gap the research's Finding 2 (P3) and Finding 4 identify, and it is more
  load-bearing for Alternative 2 than for Alternative 1, because
  Alternative 2's whole "uniform meaning" argument depends on the trigger
  being recorded and checkable, not just asserted in prose. Recommend
  adding a required field when `execution_mode != single-pr`, e.g.
  `split_trigger: hard-constraint | incremental-value | reviewability-
  ceiling`, or a per-unit annotation in the Implementation Issues table
  (parallel to the existing `_Repo: owner/repo \| Group: <pr-group>_`
  annotation row coordinated mode already uses, `phase-3-decomposition.md:
  189-190` -- precedent for exactly this kind of per-issue metadata row
  already exists and could be reused as `_Split trigger: <name>_`).

- **`FormatSpec` entry in `crates/shirabe-validate/src/formats.rs`**: I read
  the Plan spec in full (lines 322-349). Two changes:
  1. `required_fields` (line 336) gains `split_trigger` -- but only
     conditionally, since single-pr plans have nothing to record. This
     likely wants the same conditional-requirement pattern the file already
     uses for `execution_mode_required_sections` (lines 104-112,
     `plan_execution_mode_sections()` at line 161): a new
     `execution_mode_required_fields: Option<HashMap<String, Vec<String>>>`
     analog, or a dedicated FC check (a new FCxx, following the FC01-FC09 +
     FC11/FC15 numbering already in use per `plan-format.md`'s Validation
     Rules section) that fires only when `execution_mode != "single-pr"`
     and no trigger field/annotation is present.
  2. A new validator check enforcing "recorded trigger" as more than prose
     -- this is the piece Finding 4 confirms doesn't exist anywhere today (I
     re-ran `grep -rn "trigger" crates/shirabe-validate/src/*.rs` myself:
     the only hits are unrelated uses of the English word "trigger" in
     comments -- rate-limit triggers, directory-move triggers, mermaid
     issue triggers -- none reference a recorded split-trigger field). This
     check would live alongside the existing `PostureClass::DraftTolerable`
     pattern (`crates/shirabe-validate/src/advisory.rs:144,185` --
     `posture_class(&e.code) == PostureClass::DraftTolerable`), landing as
     a notice under draft, error under ready, consistent with P5.

## 5. Recommendation

Alternative 2 is the more honest fix to the actual defect the research
surfaced: two principles governing the same question at two altitudes,
disagreeing. It is not free -- it requires authoring a genuinely new
plan-altitude trigger (not a verbatim lift), defining a ceiling metric that
does not exist today, and wiring a 3.5a interaction that the research
correctly flags as unresolved in the naive reading. But every one of those
costs is closeable with existing machinery already shipped elsewhere in this
codebase: the `PostureClass::DraftTolerable` notice/error pattern for the
new validator check, the coordinated-mode per-issue annotation row pattern
for the trigger-recording slot, and 3.5a's own existing
pass/ambiguous/fail/`assumed` machinery for the value-guard interaction.
None of these costs require inventing a new mechanism; they require
extending three mechanisms that already exist for exactly this shape of
problem.

I recommend Alternative 2 **conditioned on scoping in, in the same unit of
work, not as deferred follow-up**: (1) the concrete pre-diff reviewability
metric from 2(a), (2) the explicit 3.5a wiring from 2(b), (3) the
`split_trigger` field/annotation and its validator check from Section 4, and
(4) the P4-conformant extraction into a shared trigger reference. Shipping
the P1 principle change alone, without these four, produces a principle
that reads as fixed but isn't -- an undefined ceiling, an unguarded value
collision, and an unenforced trust claim, which is a worse state than not
touching P1 at all. If the team is not willing to scope in all four
alongside the principle change, Alternative 4 (defer) or Alternative 5
(record-the-reason first) are more honest interim positions than shipping
Alternative 2's principle text without its enforcement.
