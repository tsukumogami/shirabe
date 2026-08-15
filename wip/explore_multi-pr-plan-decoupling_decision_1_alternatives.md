# Alternatives: How should a repo-level PR-delivery preference relate to principle P1?

## Alternative 1: Invertible default

P1's "default to one PR" becomes the default *of a default*. A new CLAUDE.md
header -- `## PR Delivery Preference: consolidated|atomic`, resolved
`flag > header > default`, defaulting to `consolidated` -- lets a repo flip the
starting posture. Under `atomic`, `/plan` decomposes into the smallest
independently reviewable increments by default and requires a reason to
consolidate; under `consolidated`, today's behavior holds unchanged. P1's prose is
amended to say the single-PR default is the shipped default, not a universal.

Key characteristic: the preference is a **posture**, and the escape conditions
stay as written. Simple to specify, simple to read. Its cost is that
`execution_mode: multi-pr` stops carrying a uniform meaning across repos -- in an
`atomic` repo it means "the default fired," in a `consolidated` repo it means
"something forced it."

Source: existing knowledge, shaped by the `## Roadmap Issues: optional|required`
precedent, which is exactly this shape (a posture header that flips a default).

## Alternative 2: Reviewability as a named trigger under P1

P1 stays a universal: never split by mechanism, split only on a recorded trigger.
Its closed two-item escape list is widened to three by adding "a single PR would
exceed the configured reviewability ceiling," borrowed from the
Coarsest-Legal-Grouping Rule where it already exists and is already configurable
via the shipped `## Reviewability Ceiling:` header. An org that wants atomic
delivery sets a low ceiling. No principle is inverted; no new header is needed for
the decomposition half.

Key characteristic: `multi-pr` keeps a uniform meaning -- a trigger fired -- and
the plan records which one, which is precisely the author's trust goal. Its cost
is that the ceiling has no definition anywhere in the repo today and would have to
be defined in measurable terms that an agent can evaluate *before* the diff
exists. Research also found that the other three coordination triggers cannot be
lifted verbatim to plan altitude: "independently mergeable" and "independently
rollback-able" over-fire on almost any well-decomposed plan, and the DAG-cycle
trigger is meaningless without a DAG. So this alternative requires authoring a
plan-altitude trigger list, not copying one.

Source: existing knowledge plus research; the trigger and its header are shipped
one altitude up.

## Alternative 3: Sibling principle for review ergonomics

P1 is left untouched. A sixth principle is added covering review ergonomics as a
first-class, org-tunable concern, and the single-pr/multi-pr decision takes two
independent inputs -- value (P1) and reviewability (the new principle) -- rather
than one rule with an exception list. The Coarsest-Legal-Grouping Rule is
re-anchored on the new principle so both altitudes cite one source.

Key characteristic: it is the most honest structural description of what shirabe
already does, since the coordination contract demonstrably treats reviewability as
a legitimate concern. Its cost is that "five principles" is stated as a fixed set
in `workflow-principles.md`'s preamble and cited by count from
`plan-doc-structure.md`, so the amendment ripples; and a second principle
competing with P1 on the same decision reintroduces exactly the fusion this whole
exploration is trying to remove, unless their precedence is specified.

Source: existing knowledge.

## Alternative 4: Defer -- ship tracking decoupling only

Accept that the "should" gate cannot be specified without resolving the principle
question, and decline to resolve it now. Ship the tracking half alone: a
`## Plan Issues:`-shaped header on the proven `flag > header > default` stack, and
the re-keying of the Draft->Active gate onto "does this run create GitHub
artifacts." Leave P1 and the decomposition preference untouched for separate work.

Key characteristic: research established that tracking is a **P2**-derived rule
("a self-contained PLAN doc over GitHub issues when the work is single-pr"), not a
P1 rule, so the two halves of the theme genuinely rest on different principles and
can move independently. This alternative has proven precedent, one consumer, and
the narrowest blast radius of any option. Its cost is that it delivers only half
the author's ask and leaves the fused Phase 3.6 branch exactly as it is.

Source: research finding that P2, not P1, owns the tracking coupling.

## Alternative 5: Record-the-reason first, decide the posture later

Neither amend P1 nor add a preference yet. Instead, build the thing research
showed is missing under every other option: a durable slot in the PLAN recording
*why* this plan is not single-pr -- which named constraint or which trigger fired --
plus a `DraftTolerable` validator check that a non-single-pr plan carries one.
`skills/plan/SKILL.md` already demands this ("the constraint must be named in the
PLAN doc") and no schema slot exists, so this is closing a stated-but-unenforced
requirement rather than adding a new one.

Key characteristic: it delivers the author's actual trust goal -- multi-pr becomes
legible evidence -- without needing the principle question answered, and it makes
whichever preference lands later immediately checkable. Its cost is that it does
not itself give an atomic-preferring org anything to configure.

Source: research finding that "recorded trigger" is aspirational at both
altitudes.
