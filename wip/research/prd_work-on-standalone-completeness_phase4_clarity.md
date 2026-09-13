# Clarity Review: PRD-work-on-standalone-completeness

## Verdict

FAIL

## Per-requirement ambiguity scan

- **R1.** Mostly clear ("resolvable document chain" → pull to terminal state before PR is mergeable). Relies on "resolvable document chain" being understood as the complement of both R3's "no anchor" and R4's "anchor resolves to no upstream chain" cases, which is never stated as a closed three-way partition — see the anchor-terminology finding below.
- **R2.** Ambiguous. "Anchor document" is used here for the first time in the whole PRD with no definition. Reading A: anchor = any of BRIEF/PRD/DESIGN/PLAN found above the issue. Reading B: anchor = specifically the PLAN (the only "plan-shaped document path" the cascade script accepts, per the Problem Statement). The two readings diverge on an issue whose chain exists but bottoms out below a PLAN. Resolvable only by outside knowledge that /plan is what files issues, which isn't stated in this PRD.
- **R3.** Same "anchor" ambiguity as R2. Internally consistent with R2 once anchor is defined, but the definition still isn't given.
- **R4.** Clear on its own (matches Problem Statement's worked example almost verbatim), but uses "anchor" for what the Problem Statement calls "a plan" — a silent narrowing of the term that R2/R3 use generically.
- **R5.** Clear; testable by direct comparison against the plan entry point's existing handling.
- **R6.** Clear rule, with two concrete examples. Whether an obligation is "observable from gh or git" is left to the classification exercise in R8, which is appropriate delegation, not ambiguity.
- **R7.** Clear rule, two concrete examples; same appropriate delegation to R8 for the rest.
- **R8.** Clear. Note the classification labels it introduces ("R6-gateable", "R7-evidence") are not the same labels used later in Known Limitations ("gateable and judgment-carried") — see terminology-drift finding below.
- **R9.** Understandable from context ("reference-hop" = a citation/inclusion step between the koto template and a reference file) but the counting unit itself is never operationalized — a minor ambiguity, low real-world risk since R10 gives the same idea a harder, file-path-based test.
- **R10.** Clear and concrete: names the exact two files.
- **R11.** Clear.
- **R12.** Clear behaviorally; the "distinct signal" is appropriately left as a design choice.
- **R13.** Clear.
- **R14.** Clear on outcome, though "reusing its existing per-issue dispatch loop and its single end-of-run cascade call" reads as an implementation instruction (a "how") inside a functional requirement rather than an observable behavior — a content-boundary flag, not an ambiguity.
- **R15.** Clear; correctly delegates the actual disposition to the Decisions section by cross-reference rather than restating it.
- **R16.** Ambiguous. "Load-bearing routing claim" is genre-standard vocabulary elsewhere in this repo's PRDs (used loosely to mean "something other things actually depend on"), but its acceptance criterion converts a mechanical grep into a criterion that says "no particular count is required," which only works if "load-bearing" has a fixed test. Two implementers could reasonably disagree on whether a code comment, a fixture string, or a changelog line counts, and each could believe the requirement is satisfied.
- **R17.** Clear and specific (three named scenarios).
- **R18.** Clear as an obligation, though the two documents it names ("a requirement in the plan entry point's own PRD," "the chosen option in a Current design") are never given as concrete paths inside this PRD, unlike R16's citations. Resolvable via the BRIEF/exploration but not from this document alone.
- **R19.** Clear; scope is explicitly bounded to states this feature adds.
- **R20.** Clear, factual, testable.
- **R21.** Clear; delegates to existing linter rules by reference.
- **R22.** Clear ordering requirement with a stated reason.

## Per-criterion findings

- The AC for R2/R3 ("no BRIEF, PRD, DESIGN or PLAN") is the only place in the document that operationally defines "no anchor," and it does so only in the Acceptance Criteria, after the term has already been used three times in Requirements without definition. A reader working requirement-first meets the undefined term before its only definitional anchor.
- The AC for R16 inherits R16's ambiguity: "a repository-wide search... returns none" is stated as if mechanically decidable, but deciding what to search for depends on the undefined "load-bearing" filter. This acceptance criterion is not the binary, judgment-free check the PRD format requires ("Binary pass/fail — no subjective judgment").
- The AC for R9 ("either... or explicitly recorded as advisory with the reason") is well-formed as a binary either/or and does not inherit the "reference-hop" counting ambiguity in a harmful way, since compliance can be checked concretely against R10's file-path test.
- No acceptance criterion contradicts the requirement it cites; all criteria I checked map 1:1 to their cited R-numbers.

## The anchor / no-anchor / anchor-with-no-chain distinction (specific scrutiny item)

The three-way split the PRD needs — (a) no anchor at all, (b) an anchor that resolves to no upstream chain, (c) an anchor that resolves to a real chain — is narratively very well handled: the Problem Statement states explicitly that these are two different things needing different fixes, gives a worked example of each, and the Decisions section devotes a named subsection to exactly the (a)-vs-(b) distinction ("A run with no anchor is a pass-through, not a skipped cascade"). At the narrative level the risk named in the task — conflating "missing work" with "already works" — is avoided.

The gap is at the requirements level: "anchor document" is the pivot term for this entire distinction (R1–R4, both Decisions subsections) and is never defined anywhere in the document. Its scope is inferable only by triangulating three separate passages — the Problem Statement's aside that the cascade script takes "a plan-shaped document path," R4's "anchor" being a "plan," and the R2/R3 acceptance criterion's "no BRIEF, PRD, DESIGN or PLAN" — and even after triangulating, a reader is left to independently conclude (from outside knowledge of how issues get filed by /plan) that "anchor" is synonymous with "the PLAN a chain bottoms out in," never "any of BRIEF/PRD/DESIGN/PLAN" as R2/R3's generic phrasing would suggest read in isolation. This is precisely the kind of ambiguity the task asked to be exacting about, because a requirement that determines whether cascade output appears at all (R3: "SHALL NOT emit cascade-related output") is exactly where conflating the two cases would surface as a visible behavioral bug.

## Undefined terms

- **anchor document** — load-bearing across R1–R4 and both Decisions subsections; never defined. See above.
- **load-bearing routing claim** (R16) — an established idiom elsewhere in this repo's PRDs, but not defined locally, and it undermines the binary-ness of R16's own acceptance criterion.
- **judgment-carried** (Known Limitations) vs. **R7-evidence** (R8) — two different labels for what appears to be the same classification bucket, never explicitly equated.
- **finishing obligation**, **pass-through**, **gateable** — each is self-evident from surrounding worked examples (closing keyword, merge/rebase cleanliness, code cleanup, summary shape) and is used consistently; no flag.
- **reference-hop** (R9, Problem Statement) — understandable from context, counting mechanism left undefined; low severity given R10's harder test covers the same ground.
- "the plan entry point" / "the single-issue entry point" are used consistently throughout as stable role names and never tied to concrete skill names (e.g., `/execute`) inside this PRD. Internally consistent and likely deliberate (the BRIEF, not this PRD, names `/execute`), but it means R16/R18's file-hunting work requires outside knowledge this document doesn't supply.

## Problem Statement standalone check

Passes. A cold reader gets: what's broken (a `/work-on` run opens a PR and stops), concrete cost evidence (three field runs, two days, three repos, with specifics of what each run needed), the two-part diagnosis (cascade unreachable vs. obligations unenforced), which half of the cascade problem is already fixed and which isn't, the structural reason obligations must live in the koto template rather than SKILL.md, and the multi-pr routing problem. Nothing here requires opening the BRIEF.

## Citation vs. restatement

No violation found. The Goals section closely tracks the BRIEF's User Outcome in substance, but that is the Goals section doing its own job ("what success looks like at a high level"), not a redundant restatement placed alongside a citation — the PRD does not also carry a separate paragraph merely summarizing the BRIEF. User Stories are compressed into "As a / I want / so that" form rather than reproducing the BRIEF's User Journeys narratively. The Decisions and Trade-offs section correctly closes the three questions the BRIEF explicitly deferred to it, which is the documented convention, not restatement.

## Writing style

No banned-word hits from `skills/writing-style/rules.yaml` (checked the full word list: tier/tiered, robust, comprehensive, leverage, facilitate, seamless, journey, etc. — zero matches, and the repo's own carve-outs for tier/journey/underscore as terms of art weren't needed). Em dash density is roughly 8.4 per 1,000 words (27 dashes / ~3,199 words), under the 10-per-1,000 threshold. No "it's worth noting," "furthermore," or similar adverb-opener patterns. Sentence length varies naturally; the document reads as narrative prose in its Problem Statement/Goals/Decisions sections and appropriately shifts to enumerated form only in Requirements/Acceptance Criteria/Out of Scope, consistent with the format.

One content-boundary note, not a style defect: R14's "reusing its existing per-issue dispatch loop and its single end-of-run cascade call" states implementation shape inside a functional requirement — arguably a "how" that belongs to the design doc.

## Internal consistency

- R1 (single-issue runs pull the chain) and R11 (child runs must not) are not contradictory — R11 is a stated, explicit exception for the child-dispatch case — but R1 never forward-references R11, so a reader of R1 alone would not know the exception exists until reaching R11. Minor, not a contradiction.
- No requirement contradicts another; no acceptance criterion contradicts its cited requirement; the Decisions section does not contradict any requirement it touches.
- Terminology drift noted above (R7-evidence vs. judgment-carried) is the one internal-consistency wrinkle found.

## Public-visibility cleanliness

Clean. No private-repo names, no internal-only resource references. `source_issue: 361` is a same-repo (shirabe) issue number, which is permitted.

## Required changes

1. Define "anchor document" explicitly at its first use (R2), stating plainly that it is the PLAN a chain bottoms out in (or whatever the correct scope is) — not left to be triangulated across the Problem Statement, R4, and the R2/R3 acceptance criterion.
2. Either define "load-bearing" for the purposes of R16 (e.g., "a claim in prose, a docstring, or a comment that a person or agent would act on — not test fixture data or historical changelog text") or drop the qualifier and accept the larger literal surface, so the R16 acceptance criterion is a true binary grep-style check rather than one gated by an undefined filter.
3. Reconcile "judgment-carried" (Known Limitations) with "R7-evidence" (R8) — use one label for the same bucket, or state explicitly that they are the same thing.
4. Optional but recommended: add a one-clause forward reference from R1 to R11's exception, so the general rule and its carve-out are visibly linked.

## Observations

The document is unusually disciplined for a PRD of this size — every requirement maps 1:1 to an acceptance criterion, the two "already correct, don't regress" cases (R4, the multi-pr eval scenarios) are called out so implementers don't rediscover and re-break them, and the Decisions section closes exactly the three questions the upstream BRIEF deferred, with alternatives and reasoning recorded rather than asserted. The failures above are concentrated in one seam — the vocabulary around "anchor" and "routing claim" — rather than being spread across the document, which suggests they are a tightening pass away from clean rather than evidence of a document that doesn't know what it's asking for.
