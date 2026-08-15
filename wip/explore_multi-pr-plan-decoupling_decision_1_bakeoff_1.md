# Bakeoff: Alternative 1 (Invertible Default)

Advocate position. Alternative under evaluation: P1's single-PR default becomes
repo-invertible via a new `## PR Delivery Preference: consolidated|atomic`
CLAUDE.md header, resolved `flag > header > default` (default `consolidated`).
P1's prose is amended to describe "default to one PR" as the shipped default of
a configurable posture, not a universal.

## 1. Strengths

**It has a shipped, structurally identical precedent, not just an analogous
one.** `## Roadmap Issues: optional|required` (documented at
`references/fixes/claude-md-conventions.md:64-74`, implemented in
`skills/roadmap/references/phases/phase-1-scope.md:13-16` and
`skills/roadmap/SKILL.md:123,153,169`) is exactly this shape: a CLAUDE.md
header that flips which of two mutually exclusive behaviors a skill defaults
to, resolved on the same `flag > header > default` stack Alternative 1 reuses
verbatim, with the same "absent header falls to a stated default" contract.
CLAUDE.md (this repo's own, lines 46-69) already ships two more headers on the
identical stack for the same *kind* of decision — `## PR Grouping Policy:
coarsest-legal` and `## Reviewability Ceiling: default` — both durable
workspace preferences that invert or tune default behavior per repo. Alternative
1 isn't proposing a new pattern; it's the fourth instance of a pattern the repo
already uses for exactly this problem shape: "should this skill's default
posture differ per adopting repo." That's a strong prior in its favor — the
research file's own blast-radius table (Finding in
`wip/explore_multi-pr-plan-decoupling_decision_1_research.md` section 6)
independently ranks it cheapest on P2 grounds among the four options.

**A posture header is more honest than a universal principle papering over a
real cultural difference.** The context file states the author's own position
plainly: "orgs with many reviewers may legitimately prefer small atomic
increments, and want that to be honored configuration rather than a fork of the
skill." P1 as currently written doesn't leave room for that — it's a two-branch
affirmative test (hard constraint, or genuine incremental value) with
reviewability excluded by construction (research Finding 1). Forcing a
many-reviewer org through that test means every legitimately-atomic split has
to be laundered as "genuine incremental value" even when the real reason is
"our review culture doesn't tolerate 2,000-line diffs." That's not a neutral
cost — it's the exact failure mode P4 exists to prevent applied to *prose*
instead of *format*: two organizations doing the same thing for different
reasons, forced to describe it identically because the rule has no vocabulary
for the second reason. An invertible default gives the second reason a name
(`atomic`) instead of asking authors to keep re-deriving a "genuine incremental
value" justification for what is, honestly, a reviewability preference. Stating
the single-PR default as *shipped* default rather than *universal* is a more
accurate description of what the rule actually is once you admit
`consolidated` and `atomic` are both legitimate starting postures — it doesn't
weaken the principle, it scopes its claim to match reality.

**It cleanly separates "which unit counts as the default" from "when do we
deviate from the default," which keeps 3.5a's job unchanged.** This is the
sharpest technical strength and it's a real finding, not just an aesthetic one:
research section 3 shows that Option 2 (reviewability as a P1 trigger) collides
with the 3.5a value-confirmation guard, because a ceiling-triggered split has
no guarantee its slices are independently valuable — you can hit a line-count
ceiling in the middle of a coherent feature. Alternative 1 doesn't have this
problem. Under `atomic`, the *default unit itself* is redefined as "the
smallest independently reviewable increment," and 3.5a still asks its same
question — "is this a standalone, reviewable increment" — of that
differently-sized default unit. The guard isn't bypassed, weakened, or given a
carve-out for one exceptional trigger; it's applied unchanged to a
posture-scaled default. That is a materially smaller, cleaner change to the
decomposition machinery than smuggling a size-based trigger into an
exhaustive two-branch test that was never designed to hold a third,
non-value branch.

## 2. Weaknesses

**The stated cost is real and it is the author's own stated goal that takes
the hit.** The context file's constraint is explicit: "the stated author goal
is that a `multi-pr` plan in a prefer-single repo becomes trustworthy evidence
that no other option existed. Any option that leaves 'multi-pr' ambiguous
between 'was forced' and 'was preferred' fails that goal." Alternative 1 fails
this test as specified, on its own, no hedging available: in an `atomic` repo,
`execution_mode: multi-pr` is what the default posture *produces*, not evidence
anything was forced. A reader auditing a PLAN doc from an `atomic` repo cannot
tell, from `execution_mode: multi-pr` alone, whether this particular plan hit a
hard constraint, delivered genuine incremental value, or is simply what
`atomic` repos always produce by default. The meaning of the enum value itself
becomes repo-conditional. This is not a minor readability nit — it is precisely
the property the author named as the reason for wanting the whole
tracking/decomposition decoupling in the first place. I can't soften this: on
the trust-goal axis specifically, Alternative 1 is the weakest of the four
named options, weaker even than Alternative 4 (defer), which at least leaves
today's binary meaning ("multi-pr always means forced/valuable") fully intact
everywhere.

**It inherits, rather than fixes, the pre-existing "recorded trigger" gap.**
Research Finding 4 established that even where the Coarsest-Legal-Grouping
Rule's four triggers already exist one altitude up, nothing enforces that a
recorded trigger is actually recorded: `grep -n "trigger"
crates/shirabe-validate/src/*.rs` returns zero hits, and the PLAN frontmatter
has no field for it (`execution_mode` is a bare enum per
`skills/plan/references/plan-format.md:27,40`). Alternative 1 does nothing to
close this gap on its own — under `consolidated` repos, "multi-pr means
forced" remains exactly as unverifiable as it is today, a prose-only
obligation. Alternative 1's design as stated doesn't even attempt to fix this;
it only adds a second axis (posture) that makes the *unfixed* gap worse in
`atomic` repos specifically, because there the ambiguity is structural
(default-vs-forced) on top of the pre-existing unenforced one
(forced-vs-actually-recorded).

## 3. Risks

**Consumer blast radius is smaller than it might look, and that's worth
stating precisely rather than hand-waving.** I checked the two named
consumers directly. `/execute` (`skills/execute/SKILL.md:37-44,650-651`) reads
the PLAN's `execution_mode` and re-validates it against the fixed set
`{single-pr, coordinated, multi-pr}` as an "enum-typed input surface."
`/work-on`'s dispatcher (`skills/work-on/SKILL.md:109-113`) does the identical
re-validation against the same three-value set. Alternative 1 does not change
that set — `atomic` and `consolidated` only change *how* Phase 3.6 arrives at
`single-pr` vs. `multi-pr`, not the enum's shape or the values it can hold.
So the risk to these two consumers is low: they are pure consumers of the
already-finalized `execution_mode` value and never see the posture header at
all. The risk is entirely upstream, concentrated in the one producer
(`skills/plan/references/phases/phase-3-decomposition.md` step 3.6) and its
SKILL-surface statement.

**The real risk is silent posture drift going undetected downstream, given the
consumers don't see it.** Because `/execute` and `/work-on` never read the
posture header, there's no consumer-side signal if a plan's `execution_mode`
doesn't match its originating repo's current posture — e.g., a plan authored
under `atomic`, later executed after the repo's CLAUDE.md flips to
`consolidated` (or vice versa, or a coordinated cross-repo effort spanning
repos with different postures). That's not a new failure mode Alternative 1
invents — `## Execution Mode: auto|interactive` and `## Roadmap Issues:` have
the same "resolved once at authoring time, never re-checked at consumption
time" property — but it's worth flagging explicitly since it compounds the
Weakness #1 ambiguity: a stale or cross-repo-inconsistent posture makes
`multi-pr` even less legible after the fact, not just ambiguous but
potentially wrong-for-current-config. Also worth flagging: the "Execution Mode"
name collision the context file calls out is real and confirmed —
`references/fixes/claude-md-conventions.md:61-63` already documents `##
Execution Mode: auto|interactive` for autonomy, so Alternative 1's own naming
choice (`PR Delivery Preference`, not `Execution Mode`) is load-bearing, not
cosmetic; picking a colliding name would be a shipped bug, not a style
choice.

**Validator risk is contained but not zero.** The `PostureClass::DraftTolerable`
mechanism this decision is meant to plug into is real and already shipped
(`crates/shirabe-validate/src/validate.rs:64-134`, currently backing L02/L06/L07),
so landing a new "multi-pr declared without a hard-constraint/value rationale,
and repo isn't `atomic`" finding on that same posture-aware machinery is
low-novelty engineering. But that finding necessarily has to read the CLAUDE.md
header to know which repo posture it's checking against — today's validator
checks (L01/L02, FC-CONVENTIONS) don't cross-reference a CLAUDE.md preference
header against a PLAN artifact's frontmatter in this way, so this is new
wiring, not a copy of an existing check.

## 4. Implementation implications

Concrete files, based on direct reads:

- `references/workflow-principles.md` (P1, lines 12-31): reword "Default to
  one PR" to describe the shipped default of a configurable posture; the
  two-branch escape-condition list stays as-is under `consolidated`, gains a
  posture-aware framing under `atomic` (the default *unit* changes, not the
  test).
- `references/fixes/claude-md-conventions.md` (lines 48-83): new row, `##
  PR Delivery Preference: consolidated|atomic`, parallel to the existing `##
  Execution Mode:` and `## Roadmap Issues:` rows — same table, same
  documentation contract, same "the header does NOT affect X" carve-out style
  already used for `## Roadmap Issues:` at line 70-71 (an equivalent carve-out
  is likely needed here for coordinated mode, which has its own grouping
  policy).
- `CLAUDE.md` (this repo's own, after line 69): add the header itself, next to
  `## PR Grouping Policy:` and `## Reviewability Ceiling:`, if shirabe wants to
  dogfood a non-default posture — otherwise it's absent and defaults to
  `consolidated`.
- `skills/plan/SKILL.md` (Execution Mode Decision section, lines 137-172): the
  always-loaded statement of the default and its escape conditions needs the
  posture read added — this is the section Decision 6 of
  `DESIGN-roadmap-plan-standardization.md` chose to surface P1 on, so this file
  is where the amendment has to actually land, not just the principles doc.
- `skills/plan/references/phases/phase-3-decomposition.md` step 3.6 (and the
  header-read pattern already established at line 258 for `## Execution
  Mode:`): add a `## PR Delivery Preference:` read alongside the existing
  header reads, branching the default before the escape-condition test runs.
- `skills/plan/references/plan-format.md` (frontmatter, lines 27-40): no schema
  change is *required* for Alternative 1 to function, but per research Finding
  2 (P3 gap) and Weakness #1 above, closing the recorded-rationale gap here
  (or explicitly punting it to Alternative 5, see below) is what determines
  whether the trust-goal failure is permanent or fixable.
- `crates/shirabe-validate/src/validate.rs` / `advisory.rs`: new
  `PostureClass::DraftTolerable` finding reading both the CLAUDE.md header and
  the PLAN's `execution_mode`, plus whatever escape-condition/trigger field
  Alternative 5 might add.
- `docs/designs/current/DESIGN-roadmap-plan-standardization.md` Decision 6: needs
  an amendment note (not a reversal) — the "Chosen" outcome's default-and-escape
  shape survives unchanged under `consolidated`; the amendment documents that
  the default itself is now posture-conditional.

## 5. Recommendation

Alternative 1 is the right shape for the actual disagreement being resolved,
and the weakest on the one axis the author said mattered most — both at once,
honestly. The Roadmap Issues precedent isn't decoration; it's proof the repo
already trusts this exact mechanism (posture header, `flag > header > default`
stack, default-flipping) for this exact class of "an org's process culture
should be configurable without forking the skill" problem, and it avoids the
technical trap Option 2 walks into (the 3.5a collision, the exhaustive-test
violation) entirely, for free, by construction. On P2 (lowest ceremony) and
P4 (don't restate shared shape) grounds, verified against the actual research
blast-radius table, it's the cheapest option that still moves the needle on
decomposition, not just tracking.

But shipped alone, it does concede the trust goal in `atomic` repos, and I
don't think that's a defensible final state given the author stated that goal
explicitly as a constraint the decision must resolve, not a nice-to-have. The
honest fix is composition, not substitution: pair Alternative 1 with
Alternative 5 (record-the-reason). Alternative 5's contribution — a durable
PLAN-doc slot for *why* a plan isn't single-pr, plus a `DraftTolerable`
validator check that it's present — is orthogonal to which posture produced the
`multi-pr` outcome. Under `consolidated`, that slot records the hard constraint
or incremental-value justification (today's behavior, now actually enforced
instead of prose-only). Under `atomic`, that same slot can honestly record
"posture: atomic default" as the recorded reason — which is not the same
depth of evidence as a named hard constraint, but it *is* a legible,
machine-checkable distinction between "this repo's default fired" and "this
repo's default was overridden to consolidate anyway" (the `atomic` repo's own
escape hatch, symmetric to `consolidated`'s). That symmetry is what actually
closes the ambiguity Weakness #1 names: `multi-pr` stops being silently
uniform, but it also stops being illegibly ambiguous, because the artifact
itself says which of the two regimes produced it. Alternative 1 without
Alternative 5 is a real, shippable improvement that concedes the trust goal
in half the config space; Alternative 1 with Alternative 5 is the version I'd
actually recommend building.

## Final Position

**1. Posture and tracking are genuinely orthogonal, and this decision doesn't
touch tracking at all.** Confirmed against
`wip/explore_multi-pr-plan-decoupling_findings.md` and `_decisions.md`:
tracking is already scoped as its own axis (T2, accepted), bound to P2 ("a
self-contained PLAN doc over GitHub issues when the work is single-pr"), with
its own precedent-shaped header (`## Roadmap Issues:`-style, likely `## Plan
Issues:`) on the same `flag > header > default` stack. `atomic` does not imply
"and also file GitHub issues" — an `atomic` repo wanting small PRs but no
issue-tracking overhead, or a `consolidated` repo that still wants issues
filed for its rare multi-pr plans, are both valid cells. Validator 4 is
right: tracking can ship independently on the proven precedent, and this
decision should scope to posture/cardinality only. That argues for **two
designs, not one** — or one design with two cleanly separable decision
records, which is the same thing that matters for sequencing.

**2. The tautology objection lands in the modal case, not in general — I
qualify rather than concede.** When the header says `atomic` and the plan's
default fires with no override, recording "posture: atomic default" adds
little beyond what the header already says, agreed. But the slot has to
carry two other states too: a hard-constraint/value justification that would
have applied under *either* posture (fully informative, not tautological),
and an explicit override in the other direction (an `atomic` repo choosing to
consolidate anyway, or a `consolidated` repo choosing to split without a
named constraint). Those override states are exactly where a reader's
trust question is sharpest, and the slot is non-tautological there. There's
a second, independent reason the "tautological" framing undersells the slot
even in the modal case: the header is live and mutable, the PLAN doc is a
point-in-time artifact. Pinning "posture: atomic default, as of authoring"
into the doc protects against exactly the stale-posture drift risk I flagged
under Risks — a reader six months later, after the repo's header has changed,
can't reconstruct which posture was active at authoring time from the header
alone. So: qualify, don't fully concede. The slot is thin evidence in the
unexceptional case and load-bearing evidence in the two cases that matter.

**3. Concrete abandonment condition.** I'd drop Option 1 for Option 2 if
real usage shows `atomic` mode's redefined default unit ("smallest
independently reviewable increment") can't actually be hit without
routinely failing 3.5a's standalone-value bar — i.e., if shrinking the
default unit to satisfy reviewability turns out to *require* the same
value-guard carve-out Option 2 was criticized for, just relocated inside
"the default" instead of named as an explicit trigger. That would erase
Option 1's one clean technical differentiator (3.5a unchanged, applied to a
rescaled unit) and leave Option 2's honest, named, recorded trigger as the
more truthful description of what's actually happening to the value guard.
