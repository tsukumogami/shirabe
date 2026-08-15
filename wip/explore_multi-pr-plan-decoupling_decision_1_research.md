# Decision Research: P1 vs. repo-level PR-delivery preference

## Research conducted

Read in full: `references/workflow-principles.md`, `references/coordination-strategy.md`,
`CLAUDE.md` (shirabe's own), `docs/guides/coordinated-multi-repo.md`,
`skills/plan/SKILL.md` (Execution Mode Decision section),
`skills/plan/references/phases/phase-3-decomposition.md` (3.5a and 3.6 in full),
`skills/plan/references/plan-format.md`, `skills/plan/references/phases/phase-7-creation.md`
(execution_mode wiring), `references/fixes/claude-md-conventions.md`, and
`docs/designs/current/DESIGN-roadmap-plan-standardization.md` Decision 6 in full.

Grepped: `P1` across `skills/`, `references/`, `docs/`; `Reviewability Ceiling` and
`PR Grouping Policy` workspace-wide; `ceiling` workspace-wide (to hunt for a concrete
numeric default); `trigger` across `crates/shirabe-validate/src/*.rs`; `execution_mode`
across `skills/plan/`; `.shirabe.toml` in `DESIGN-roadmap-issueless-preference.md`;
`DraftTolerable`/`PostureClass` in `crates/shirabe-validate/src/validate.rs` and
`advisory.rs`.

## Findings

### 1. What "never by mechanism" actually forbids

P1's full text: "Every PR and every roadmap feature delivers observable value on its
own. Default to one PR; **split only for a hard constraint or genuine incremental
value, never by mechanism** (e.g., 'because the input is a roadmap')."

The rule is structured as an exhaustive two-branch affirmative test -- (A) hard
constraint, (B) genuine incremental value -- with "never by mechanism" as the
closing exclusion. The worked example ("because the input is a roadmap") is a
property of the *input artifact's type*, and `skills/plan/SKILL.md:162` reinforces
this reading verbatim: "The mechanism 'the input is a roadmap' is not the reason;
the value the feature delivers is."

Read narrowly -- "mechanism" means "a property of the input artifact" -- reviewability
is indeed a different category, and the context file's hoped-for reading (P1 silent
rather than prohibitive) is defensible on the letter of the clause alone.

But that narrow reading doesn't survive contact with the rest of P1's own sentence.
The exclusion isn't the operative constraint; the two-branch affirmative test is.
Reviewability satisfies neither branch on its own:
- It isn't a **hard constraint** -- nothing prevents shipping one large PR; it's
  just costlier to review. Phase 3.6's own trigger list for hard constraints is
  concrete and different in kind: cross-repo landing order, a workflow that must
  reach main before invocation, a merge gate between steps. Size-of-diff isn't in
  that family.
- It doesn't establish **genuine incremental value** by itself. A split driven
  purely by "this is too big to review" can produce slices that are not each an
  independent, standalone increment -- exactly the failure mode step 3.5a (Value
  Confirmation) exists to catch: "not 'step 3 of 5' ... but a usable, reviewable,
  end-to-end increment." Splitting a single coherent 2,000-line feature at the
  1,000-line mark to satisfy a ceiling produces two halves that likely both fail
  3.5a's test.

So the precise answer: P1's illustrative example is narrower than its rule.
Reviewability isn't "the same category" as "because the input is a roadmap" in the
sense of both being input-artifact-type mechanisms -- but it's still excluded,
because the rule's actual gate is the two-branch affirmative test, not the
illustrative exclusion. **P1 is prohibitive, not silent, but it prohibits via
exhaustiveness of the two branches rather than via the named example naming
reviewability specifically.** This matters for Option 2's self-description below.

### 2. How P2-P5 constrain the answer

**P2 (lowest ceremony)** favors whichever option adds the least new machinery.
Ranked by surface added: Option 4 (do nothing to P1) is cheapest and solves nothing;
Option 1 (invertible default) needs one new header plus a mode branch in Phase 3.6,
mirroring the already-shipped `## Roadmap Issues: optional|required` and
`## Execution Mode: auto|interactive` pattern; Option 2 (reviewability as a P1
trigger) needs P1's affirmative test widened to three branches, the ceiling threaded
down from coordination-altitude to plan-altitude, a "recorded trigger" field added
somewhere durable, and (per Finding 1) a resolution to the 3.5a conflict -- meaningfully
more surface. On P2 grounds, Option 1 is cheaper than a *correctly executed* Option 2.

**P3 (decisions need a durable home)** exposes a gap that afflicts every option:
the final PLAN doc frontmatter records `execution_mode` as a bare enum
(`skills/plan/references/plan-format.md:27`, `:40` -- "Determines..." with no
rationale field). The rationale currently lives only in
`wip/plan_<topic>_decisions.md` (a `wip/` decision block, deleted under the
wip-hygiene rule before merge) and in the terminal summary / PR body prose --
never in the durable, merged artifact itself. So today, the author's "multi-pr is
reliable evidence" goal already isn't durably checkable from the merged PLAN doc;
it depends on PR-body prose surviving in GitHub, not in-repo. Any option chosen
should also close this gap (add a rationale/trigger field to the PLAN frontmatter
or Implementation Issues table) or the "recorded trigger" promise stays aspirational
regardless of which option wins.

**P4 (one canonical format per concern, defined once)** is the strongest lever in
the set, and it cuts a specific way: not "reviewability should apply everywhere"
in the abstract, but "if a trigger list is shared across altitudes, it must be
*factored out*, not restated." P4's own examples (`issues-table.md`,
`dependency-diagram.md`) are shared references parameterized by altitude profile,
consumed by both plan and roadmap workflows, with the per-skill files trimmed to
profile deltas. If Option 2 is implemented by copy-editing the trigger list's prose
into `workflow-principles.md`'s P1, that *is* the "per-skill restatement... drift
source" P4 exists to prevent -- coordination-strategy.md and workflow-principles.md
would each carry their own copy of "independently mergeable, independently
rollback-able, exceeds ceiling, breaks a cycle," and they will drift the first time
either is edited. Correctly executed under P4, Option 2 requires extracting the
trigger list into a new shared reference (e.g., `references/split-triggers.md`)
that both P1 and the Coarsest-Legal-Grouping Rule cite, parameterized by altitude
(plan-level unit vs. `(repo, pr_group)` unit) the same way the issues-table is
parameterized by profile. This is a real, actionable finding: **P4 doesn't just
permit lifting the rule, it prescribes the specific shape the lift must take** if
Option 2 is chosen -- otherwise Option 2 quietly reintroduces the exact drift risk
P4 was written to remove.

**P5 (strictness tracks blast radius)** supports whichever posture-aware landing
the tooling side gets (see unknown 6) -- both options land the same way (notice in
draft, error in ready, via `PostureClass::DraftTolerable`), so P5 doesn't
discriminate between them.

### 3. Would generalizing the Coarsest-Legal-Grouping Rule actually produce atomic behavior?

Walking the four triggers at plan level:

- **Independently mergeable** / **independently rollback-able**: these already
  cover the cases an atomic-preferring org actually cares about most -- "can this
  land and be reverted on its own" is a stronger, more useful signal than "is it
  small." A trigger-model repo that wants atomicity would rely on these two far
  more than the ceiling.
- **Exceeds reviewability ceiling**: this is the one genuinely new lever a low
  threshold would add. But (per Finding 1) it collides with 3.5a: a ceiling-forced
  split has no guarantee its slices are independently valuable. At coordination
  altitude this collision doesn't exist because there is no altitude-equivalent of
  3.5a's value-confirmation guard in `coordination-strategy.md` -- a per-repo PR is
  already a natural value unit by construction (it's a whole repo's worth of a
  cross-repo effort), so splitting it further for size doesn't have to also clear
  a "is this a standalone increment" bar. Promoting the ceiling to plan level
  imports a trigger into a context that has a guard the coordination context
  lacks, and the two are not obviously reconcilable without either weakening 3.5a
  for ceiling-triggered splits or accepting that ceiling-triggered splits can
  legitimately fail 3.5a (a genuinely different guard behavior than today's, and
  worth naming explicitly rather than glossing over).
- **Breaks a merge-order cycle**: doesn't apply at single-repo plan level; the
  merge-order DAG is a coordination-only concept.

So: **the "independently mergeable/rollback-able" triggers likely already produce
most of what an atomic-preferring org wants**, and the reviewability ceiling is the
one piece of genuinely new, non-overlapping behavior the trigger model would add --
but it's also the one piece with an unresolved conflict against the existing value
guard. An `atomic` inversion (Option 1) sidesteps this because it doesn't add a
third branch to a value-anchored test; it just changes which shape counts as "the
smallest independently reviewable increment" *is* the default unit of work, so the
guard's question ("does this unit deliver standalone value") is asked of a
differently-sized default unit, not bypassed for one exceptional trigger.

**Assumed: no other option-4-style config space was searched for a mechanism that
produces atomic decomposition without touching either P1's test or 3.5a.** If
wrong: there may be a fifth option (e.g., 3.5a itself becomes altitude/repo-aware)
worth surfacing to the decision synthesis.

### 4. Actual cost of an invertible default to the trust goal

Confirmed as stated in the context: under Option 1, `multi-pr` in an `atomic` repo
is the configured default, not evidence anything was forced -- the two meanings
collapse. Under Option 2 (or 3), a split still requires a named trigger to appear
in the plan, which -- *if actually enforced* -- keeps `multi-pr` meaning "something
forced or justified this."

But the "if actually enforced" carries real weight, and here the check came back
negative: **`grep -n "trigger" crates/shirabe-validate/src/*.rs` returns zero
hits.** Nothing in the Rust validator checks that a coordination PR's per-repo
split names one of the four recorded triggers, today, at the altitude where the
rule already exists. And per Finding 2 (P3), the PLAN doc frontmatter has no field
to record a trigger at all -- `execution_mode: multi-pr` is a bare enum. So
"recorded trigger" is current-state **prose obligation only**, not a durable
artifact requirement and not a validated one. The Coarsest-Legal-Grouping Rule's
trigger list lives in `coordination-strategy.md` prose and in the coordination PR
body template's "PR Index" / "Merge Order" sections, neither of which has a
trigger-name slot -- the template shown in `coordination-strategy.md` records node
ids and merge state, not why a repo split.

This is a material finding: **Option 2's headline advantage over Option 1 (a
recorded, checkable trigger preserving the trust signal) does not exist yet, even
where the mechanism it would generalize already ships.** Choosing Option 2 without
also building trigger-recording and validation (a new PLAN/Implementation-Issues
field plus a validator check) delivers exactly the same trust erosion Option 1 is
criticized for -- an unenforced "was this really forced?" that a reader can't
verify from the artifact. If the decision synthesis leans on "Option 2 preserves
the trust goal," that claim should be conditioned on also scoping in the
trigger-recording work, not treated as free.

### 5. Is the reviewability ceiling defined anywhere as a concrete value?

No. `CLAUDE.md:59-66` (shirabe's own) declares `## Reviewability Ceiling: default`
and states "`default` defers to the ceiling defined in
`references/coordination-strategy.md`." But `coordination-strategy.md`'s
Coarsest-Legal-Grouping Rule only ever says "a single PR would exceed the
configured reviewability ceiling" -- it names the trigger, never a number, a line
count, a file count, or any other measurable quantity. `docs/guides/
coordinated-multi-repo.md` repeats the same non-committal language ("Leave the
ceiling at `default` to defer to the contract"). A workspace-wide grep for
`ceiling` across every `.md` file surfaced no numeric default anywhere in the tree
(other design docs use "ceiling" for unrelated byte/timeout bounds, e.g.
`DESIGN-doc-vs-github-state-reconciliation.md`'s 4 MiB subprocess-output ceiling,
which is a different concept entirely).

**This is a material gap for any option that leans on the ceiling as the tunable**
(Option 1's `atomic` mode implicitly and Option 2 explicitly). Today, setting
`## Reviewability Ceiling: default` and even wanting `atomic`-style behavior has
no operative threshold to invert against -- the knob exists syntactically but
resolves to an undefined value. Whichever option is chosen, shipping it requires
either picking a first concrete default (a size metric: files changed? lines
changed? issues bundled?) or explicitly deferring that as separate follow-up work,
named as such rather than assumed solved.

### 6. Blast radius per option

| File / surface | Opt 1 (invertible default) | Opt 2 (reviewability as P1 trigger) | Opt 3 (sibling principle) | Opt 4 (do nothing to P1) |
|---|---|---|---|---|
| `references/workflow-principles.md` (P1) | Reworded: "default to one PR" becomes "default to the repo's preferred default" | Reworded: two-branch test becomes three-branch, citing the (new) shared trigger reference | Untouched | Untouched |
| `references/coordination-strategy.md` | Untouched (already independent) | If done per P4 (Finding 2): trigger list extracted out into a new shared reference this file now cites instead of owning | New sibling principle may cite this file's trigger list as prior art | Untouched |
| New shared reference (e.g. `references/split-triggers.md`) | Not needed | Needed if P4-conformant (else drift risk, Finding 2) | Possibly, if the new principle also wants a trigger list | Not applicable |
| `skills/plan/SKILL.md` (Execution Mode Decision section) | New header documented; escape-condition list gains "or the repo's preference is `atomic`" | Escape-condition list gains the ceiling trigger, citing the shared reference | New paragraph citing the sibling principle as a second, independent input | Untouched |
| `skills/plan/references/phases/phase-3-decomposition.md` (3.5a, 3.6) | 3.6 procedure step 3 gains a repo-preference branch; 3.5a's value question may need repo-preference-aware wording for `atomic` units | 3.6 gains a ceiling check; 3.5a needs an explicit carve-out or reconciliation for ceiling-triggered splits (Finding 3's core tension) | 3.6 gains a second, independent check ("does this also exceed the sibling principle's threshold") layered onto the existing test, cleanly separable from 3.5a | Untouched |
| `skills/plan/references/plan-format.md` / PLAN frontmatter | New field or header cross-reference recommended (not required) to close the P3 gap (Finding 2) | Same, but closing the gap here is closer to load-bearing for Option 2's own trust claim (Finding 4) | Same | No PLAN-format change |
| `CLAUDE.md` conventions doc (`references/fixes/claude-md-conventions.md`) | New header row added (e.g. `## PR Delivery Preference: consolidated|atomic`), alongside the existing `## Roadmap Issues:` / `## Reviewability Ceiling:` rows | `## Reviewability Ceiling:` row's description widens to say it now also gates plan-level splits, not only coordination-level | Possible new header for the sibling principle's threshold | Untouched |
| `crates/shirabe-validate` | Minimal: a `PostureClass::DraftTolerable` finding for "multi-pr declared without a hard constraint or value rationale, and repo isn't `atomic`" | Same finding shape, plus (to make Finding 4's trust claim real) a new check that a ceiling-triggered split actually names its trigger -- new parsing surface, since no `trigger` field exists in any format the validator reads today | Two independent findings, one per axis -- more validator surface than 1 or 2, but each individually simpler | No new check |
| Design docs needing amendment | `DESIGN-roadmap-plan-standardization.md` Decision 6 (owns the current single-pr/multi-pr rule; this reasoning augments it, doesn't replace 6A's chosen shape) | Same, plus arguably `DESIGN-capstone-orchestration.md` (owns the Coarsest-Legal-Grouping Rule's introduction) if the trigger list is extracted out from under it | Decision 6 augmented; a new decision record needed for the sibling principle itself (P3 -- durable home for a new principle) | None (explicitly deferred) |

Option 2's row for `phase-3-decomposition.md` and for `crates/shirabe-validate` are
the two rows where its blast radius is *not* smaller than it looks, contradicting
the "no principle is inverted, an existing trigger's scope widens" framing in the
context file's Option 2 description -- the 3.5a interaction (Finding 3) and the
unbuilt trigger-recording validator surface (Finding 4) are both real, non-trivial
additions, not incidental.

## Assumptions made

- **Assumed:** the search for a numeric reviewability-ceiling default was
  exhaustive enough (a workspace-wide grep on `ceiling` across every `.md` file) to
  conclude none exists. If wrong: a concrete default exists in a file this grep
  pattern missed (e.g., embedded in a script or JSON eval fixture rather than
  prose), and Finding 5's gap is smaller than stated.
- **Assumed:** "recorded trigger" was searched for as a validator-enforced
  requirement (grep for `trigger` in `crates/shirabe-validate/src/*.rs`) and this
  is a complete search of the enforcement surface. If wrong: trigger validation
  exists under a different code-level name (e.g., folded into `checks.rs` under a
  finding code without the literal string "trigger" in a comment) and Finding 4
  overstates the gap.
- **Assumed:** no fifth option exists that reshapes 3.5a itself to be
  altitude/repo-preference-aware rather than choosing among the four given
  options. Flagged explicitly in Finding 3 as worth surfacing, not silently
  substituted for an answer to the asked question.

## Clean summary of the problem and critical unknowns

The plan-level single-pr/multi-pr rule (P1) and the coordination-level
Coarsest-Legal-Grouping Rule already disagree about whether reviewability
legitimately forces a split -- P1's own prose forbids it, `coordination-strategy.md`
already ships it as a named, configurable trigger. The decision is whether to
resolve that by inverting P1's default per-repo (Option 1), promoting reviewability
into P1's affirmative test as a third branch alongside hard-constraint and
incremental-value (Option 2), splitting cardinality and reviewability into two
independent principles (Option 3), or deferring the "should" question entirely
(Option 4).

The research found that Option 2 is less "just widen an existing trigger's scope"
than it presents: P1's two-branch test is exhaustive by construction, reviewability
satisfies neither branch cleanly, and promoting it collides with the 3.5a
value-confirmation guard in a way the coordination altitude never had to face
(because coordination-strategy.md has no altitude-equivalent guard). The trust
claim usually made in Option 2's favor -- "every split records which trigger fired"
-- is not currently true anywhere in the shipped system: no PLAN/coordination
artifact has a trigger field, and the Rust validator has zero enforcement of
"recorded trigger" today. And the reviewability ceiling itself, which both options
1 and 2 would lean on as the tunable, has no concrete default value defined
anywhere in the tree -- it's a header that resolves to an undefined threshold. Any
option chosen needs to either pick a first concrete ceiling value or explicitly
scope that out as follow-up, and needs to close the PLAN-frontmatter recording gap
if the trust-preservation argument is going to hold for real rather than in prose.
