# Clarity Review

## Verdict: PASS

The revised PRD is buildable from one consistent reading; the prior soft terms (R11 ceiling, R17 inspection, R18 surface) are now objectified, and residual vagueness is confined to deliberately DESIGN-deferred details rather than requirement ambiguity.

## Ambiguities Found

1. **R8 / AC "the spent PLAN is consumed" / "gone from the record"**: The PRD says the PLAN is a durable document held on the record (R5: "holds the effort's plan ... as durable documents") yet R8/its AC say the PLAN is "consumed" and "gone from the record before it merges." -> Two readers could build opposite end-states: PLAN present on the merged record vs. PLAN deleted from it. The tension is resolvable (working-artifact PLANs retire per the repo's Artifact Lifecycle, durable BRIEF/PRD/DESIGN stay), but the PRD never states that PLAN is the lone working artifact among the four, so the conflict reads as a contradiction in-doc. -> Add one clause to R5 or R8 noting PLAN is a working artifact that retires on consume while BRIEF/PRD/DESIGN are durable and remain, citing the per-skill Artifact Lifecycle.

2. **R10 "carrying its related work" / "related work"**: "one PR carrying its related work" leaves "related" undefined. -> For a repo touched by two unrelated parts of the effort, one reader bundles all repo changes into one PR (coarsest grouping reading), another splits by relatedness. R11's split triggers govern when to split, so the intent is "all of the repo's effort-touched work unless a split trigger fires," but "related work" invites a relatedness judgment R11 does not list as a trigger. -> Replace "its related work" with "all of the effort's changes to that repository (subject to R11 split triggers)."

3. **R11 "independently mergeable, independently reviewable and rollback-able"**: These split-justification conditions are themselves judgment calls with no objective test, unlike the reviewability-ceiling condition which the revision did objectify. -> Two developers could disagree on whether two pieces are "independently mergeable," producing different PR counts for the same PLAN. The AC only checks that *a* documented trigger was recorded, not that the trigger was correctly applied, so the subjectivity is bounded — but the requirement text still reads as four soft triggers plus one hard one. -> Acceptable as-is given the AC checks recording rather than correctness; optionally note that these conditions derive from PLAN dependency data (objective) rather than reviewer taste.

4. **R2b "smart defaults ... activate automatically"**: "Smart" is a soft qualifier. -> The set is enumerated (capstone creation, artifact persistence, sequencing, merge-order tracking) so the scope is fixed, but "smart" adds nothing testable. -> Drop "smart"; "defaults that activate automatically, announce themselves, and are overridable" is fully sufficient and is what R18's AC actually verifies.

5. **R20 "force-materialized or marked"**: The abandonment end-state offers two alternatives ("force-materialized or marked") without saying which applies when. -> A developer could implement either branch; the AC ("left ... in a documented state, not silently orphaned") accepts both, so this is an intentional design latitude, not a defect — but as written it reads as an unresolved either/or. -> Acceptable; the AC's "documented state" is the binary check. Optionally state that the choice is a DESIGN decision so it doesn't read as underspecification.

## Suggested Improvements

1. Resolve the R5-vs-R8 PLAN lifecycle tension explicitly in-doc (improvement 1 above) — this is the only place a careful reader hits an apparent contradiction rather than a deferred detail.
2. Tighten "its related work" (R10) and drop "smart" (R2b) to remove the two residual soft phrasings.
3. The objectified items land well: R11's reviewability ceiling is now a recorded check against a workspace preference, R17's AC is inspection-based ("a single canonical definition ... exists, and ... reference it without restating it"), and R18 names the announcement surface (invocation output) and content (behavior name + override). No further work needed on those.

## Summary

The revised PRD passes clarity review: each of the 22 requirements maps to a binary, objectively verifiable AC, and the revision successfully converted the previously flagged soft terms (R11, R17, R18) into recorded or inspection-based checks. The one substantive issue is an apparent in-doc contradiction between R5 (PLAN held as a durable document) and R8 (PLAN consumed/gone before merge), resolvable via the repo's working-vs-durable artifact lifecycle but not stated in the PRD. Remaining looseness ("related work," "smart," R11's non-ceiling triggers, R20's either/or) is bounded by ACs that check recording or documented-state rather than subjective correctness, and the genuinely open items are correctly fenced into Out of Scope as DESIGN decisions.
