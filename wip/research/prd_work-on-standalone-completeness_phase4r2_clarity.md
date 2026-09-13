# Clarity Re-Review: PRD-work-on-standalone-completeness

## Verdict

FAIL

## Prior findings — closed or not

**Finding 1 (anchor undefined) — closed.** The new "Term used below" block
(opening the cascade-reachability requirements) defines *Anchor* as the PLAN
that sequences the issue, states when it exists vs. doesn't, and explicitly
rules out BRIEF/PRD/DESIGN as referents. I traced every use of "anchor" in the
document — R2, R3, R4, the R4 and R5a-adjacent acceptance criteria (line
~265), and both the heading and body of the "run with no anchor is a
pass-through" Decisions entry — and all of them read consistently against the
definition. No passage forces a reader back to triangulation. This fix lands.

**Finding 2 (R16 routing-claim binary-ness) — not closed.** The R16a/R16b
split is a real improvement and the definition ("directs a reader or an agent
to one entry point rather than the other... an occurrence that merely names
the mode as a value, a schema field, or a fixture is not one") correctly
disposes of the bulk of the corpus: I grepped the actual repository for
`multi-pr` across docs/, skills/, and references/ and confirmed the
definition cleanly separates true routing claims (README.md's two table
rows; `references/pipeline-model.md`'s "`/work-on` ... runs multi-pr in
place"; `skills/work-on/SKILL.md` and `skills/execute/SKILL.md`'s routing
prose; `DESIGN-execute-skill.md`'s "chosen, R1" dispatcher option;
`PRD-execute-skill.md`'s R7) from pure value/enum occurrences (execution_mode
schema fields, fixture PLAN frontmatter, other Done PRDs discussing
tracking-level or lifecycle-posture mechanics that never say which skill
runs the mode).

But it breaks on exactly the case two reviewers are most likely to hit
together: eval scenario text. `skills/execute/evals/evals.json` (scenario
"dispatcher-multi-pr-one-issue-at-a-time") and `skills/work-on/evals/evals.json`
(scenarios "plan-mode-detection-from-path" and "e2e-cross-mode-no-contamination"
— the three scenarios R17 names) all contain sentences like "Agent hands
single-pr and coordinated PLANs off to /execute rather than running them in
/work-on" and "The dispatcher does NOT hand off to /execute." These are
textbook routing claims under R16a's own wording — they are prose, not a
value, schema field, or fixture datum, and they explicitly direct behavior to
one entry point over the other for a named mode. Yet R17 separately requires
updating exactly these three scenarios, with no stated relationship to R16a's
inventory. A reviewer who reads R16a literally puts these eval hits in the
inventory (they match the definition and aren't excluded); a reviewer who
reads R16a as "the documentation surface, evals are R17's job" leaves them
out. R16b's own re-run check ("confirm every hit is either in the inventory
or is non-routing by the definition above") gives no way to resolve this: the
definition doesn't exclude eval prose, so a literal hit that's absent from
the inventory fails R16b's check, while a reviewer applying the unstated
R16/R17 division treats the same hit as correctly out-of-scope. That's two
reviewers classifying the same grep hit differently — the exact failure mode
this round was supposed to close.

A second, smaller gap in the same area: "the surface" that R16a's inventory
must cover is never bounded. The acceptance criterion names two examples
(README.md, the pipeline-model reference) but the actual corpus of files
mentioning `multi-pr` spans dozens of historical BRIEFs, PRDs, DESIGNs and
DECISION records (confirmed by grep). Most of those turn out to be pure
value/mechanics content the definition correctly excludes, but nothing in
the PRD tells an implementer that historical Done/Accepted documents outside
the two named in R18 are out of scope by design rather than by oversight — a
reviewer has to independently re-derive that boundary the way I just did.

## Per-requirement ambiguity scan

- **Definitions block (Anchor).** Unambiguous; verified consistent everywhere used.
- **R1.** Clear: "resolvable document chain" tracks the anchor definition; testable.
- **R2.** Clear: determine-before-invoke ordering is checkable from behavior.
- **R3.** Clear enough; "cascade-related output" is common-sense scoped to user-visible output.
- **R4.** Clear; pinned to an existing test, no new ambiguity.
- **R5.** Clear; "identically... including the same recovery guidance" is directly comparable.
- **R5a.** Ambiguous in one respect: it says the machinery's *location* "SHALL be decided and recorded before implementation," but the paired Decisions entry decides only the constraint and explicitly defers the location choice to "the design hop." One reading: R5a is satisfied because DESIGN precedes implementation. Another reading: R5a demanded a location decision from this PRD and the Decisions section admits it didn't provide one. The PRD doesn't say which reading is intended.
- **R6.** Clear as a class description; doesn't classify "PR body content beyond the mechanical check" or "commit message convention" (both named in the Problem Statement) into R6 or R7, but that's plausibly intentional since R8 exists to force that classification later — not scoring this as a defect.
- **R7.** Same shape as R6; clear.
- **R7a.** Clear; "concrete referent" is defined at first use with examples.
- **R8.** Clear as a rule, but its acceptance criterion refers to "the classification table" as though one is required to exist as a single artifact — R8's own text only requires "recorded with the obligation," not a table. Two implementers could satisfy R8 with per-obligation inline annotations and never produce anything a reviewer would call "the classification table."
- **R9.** Clear disjunction (bring within one hop + evidence field, or record as advisory).
- **R10.** Clear and testable against the materialized child template.
- **R11.** Clear.
- **R12.** Clear behaviorally; "the existing shared-branch signal" is assumed reader knowledge of the current implementation, acceptable as an existing-system reference rather than a new coined term.
- **R13.** Clear.
- **R14.** Clear.
- **R15.** Clear; cross-references the Decisions entry correctly.
- **R16 / R16a / R16b.** See "Prior findings" above — the eval-scenario overlap with R17 and the unbounded "surface" are live ambiguities.
- **R17.** Clear and well-grounded — I located all three named scenarios in the actual eval files and the description matches them exactly.
- **R18.** Clear in intent, but the "requirement in the plan entry point's own PRD" and "the chosen option in a Current design" are never named in the PRD itself (only inferable — and only because the upstream BRIEF's References section names `PRD-execute-skill.md` R7 and `DESIGN-execute-skill.md`'s "chosen, R1" option). A PRD that's supposed to stand on its own for its Decisions section leans on the BRIEF here.
- **R19.** Clear; scoped correctly against Out of Scope's parallel bullet.
- **R20.** Clear.
- **R21.** Clear, references concrete scripts.
- **R22.** Clear; consistent with the Known Limitations bullet on sequencing.

## Required changes

1. State explicitly whether eval-scenario prose (the three scenarios R17
   names, and any other eval JSON containing routing-directive language)
   counts toward R16a's inventory, or is categorically R17's territory and
   excluded from R16a's grep/inventory scope. Either answer is fine; leaving
   it to inference is what fails this round's specific test.
2. Bound "the surface" for R16a — state whether it includes the historical
   Done/Accepted document corpus (BRIEFs, DECISIONs, superseded-adjacent
   PRDs/DESIGNs) beyond the two documents R18 already names, or is scoped to
   live/operational documentation (skills/, koto-templates/, README,
   references/, and the two R18 documents).
3. Resolve R5a against its own Decisions entry: either have the Decisions
   entry name the actual location (closing R5a in this PRD), or reword R5a to
   say explicitly that the *location* is a design-hop decision and this PRD
   fixes only the constraint.
4. Either drop "the classification table" from the R8 acceptance criterion's
   wording or add a sentence to R8 requiring the classification to be
   recorded in one consolidated, reviewable form (a table or equivalent).
5. Pick one pair of labels for the two obligation classes and use it
   everywhere — R8 says "R6-gateable or R7-evidence," Known Limitations says
   "gateable and judgment-carried." Harmless if intentional, but currently
   reads as drift.

## Observations

Em dash density (33 across ~4000 words, including frontmatter) is close to
but under the rules.yaml threshold — not a finding, just close enough to
mention. No banned-word hits from `rules.yaml` (tier/journey/underscore
correctly unfired per the repo's declared exemptions, and no other listed
term appears). The Problem Statement stands alone well; a reader who never
opens the BRIEF gets the two-part "cascade unreachable / obligations
unenforced" framing in full, including which half was already fixed. User
Stories closely mirror the BRIEF's User Journeys in content and phrasing (and
Goals closely mirrors the BRIEF's Outcome sentence almost verbatim) — this is
defensible as normal required-section derivation rather than the
citation-vs-restatement violation the format spec is aimed at, but it's
close enough to the line that a tighter paraphrase would read better. No
private-repo references or non-public issue numbers found; `source_issue:
361` is this repo's own tracking issue, which is permitted.
