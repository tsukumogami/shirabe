# Phase 4 Jury — Clarity and Ambiguity Review

Artifact: `docs/prds/PRD-scope-chain-mandatory-steps.md`
Upstream: `docs/briefs/BRIEF-scope-chain-mandatory-steps.md`
Rubric: `skills/prd/references/prd-format.md`, `skills/writing-style/rules.yaml`

## Verdict

FAIL

The document is well above average for this corpus: the problem statement is
concrete, the requirements name real files and real defects, and every factual
claim I spot-checked against the skills held up (Slot 6.3's glob, `/charter`'s
row 8, the `{name}` / `{child}` key split, the vacuous Slot 7 in both parents,
`/explore`'s four `needs-*` labels, `pipeline-model.md`'s Skip transition). What
fails it is narrower and fixable: one requirement contradicts its own acceptance
criterion against a fact I verified in `evals.json`, and five requirements have
completion conditions that two competent implementers would settle differently
in ways that change what ships. Two of those (R17, R23) decide whether a file
gets renamed and which of two terminal states a bail produces — not stylistic
gaps.

## Per-Criterion

**1. Ambiguous requirements.** Nine flagged, table below. Five are material
(R7, R9, R10+R14 composition, R17, R23); four are minor. R23 is the sharpest:
the requirement diagnoses two broken branches and then says "SHALL execute"
without saying which one fires from Phase 1, and the two repairs are different
work (delete state and stop, versus materialize a partial artifact with an
abandonment marker).

**2. Requirements that smuggle in "how".** Mostly clean, and I want to be
explicit about what I am *not* flagging. This PRD edits documentation, so naming
`references/parent-skill-pattern.md`, `skills/scope/evals/evals.json`, or a
specific eval scenario is the WHAT — those files are the subject. R18's binding
to Slot 7 is likewise legitimate: ladder slot order is evaluation precedence, so
"which slot" is behavior, not layout. Three genuine crossings, all minor:

- **R1** — "at the head of its Gate Vocabulary section" fixes a position inside
  a file. The requirement is that the model be stated somewhere a reader finds
  it; the AC already says exactly that ("a reader can find it without opening a
  skill directory"). Which section hosts it is a drafting decision, and Gate
  Vocabulary is a debatable home for a statement about chain shape.
- **R2** — "SHALL carry a one-sentence note that no behavior changed" specifies
  the length and form of a sentence. The requirement is that a reader must not
  read the restatement as a behavior change.
- **R4** — "Free text SHALL move to an optional sibling field" is schema design.
  The WHAT is that the ground comes from a closed set and free text is never the
  ground; whether the residue lands in a sibling field or is dropped belongs
  downstream.

**3. Two requirements in one.** R15 is the clear case (remove Phase 0's
artifact-type triage; reconcile Phase 0's investigation-versus-breakdown triage
with the router). The first half can land alone and pass an unwary reviewer,
because no acceptance criterion covers either half — the closest AC,
"`/explore` names no chain-internal child as a routing destination", is silent
about `needs-*` labels, which are not chain-internal children. R7 is a softer
case: "name `/execute` in the roster" and "correct every statement enumerating
both v1 parents" are separable, and only the first has an AC.

**4. Undefined terms.** Two.

- **"the corpus's existing grow-by-PR-review convention"** (R4). No such named
  convention exists. The nearest precedent is
  `references/parent-skill-child-inspection.md:65-67` ("The table grows as new
  parents land children with new shapes... new rows go through the parent's own
  PR review"), which is findable only by luck. Cite the file.
- **"The consolidation family"** (R28). `skills/scope/evals/evals.json` has no
  `family` or `group` field — the scenario objects carry `id`, `name`, `prompt`,
  `expected_output`, `files`, `expectations` and nothing else. If the family is
  the `consolidation-` name prefix, then the count is 3 and
  `durable-artifact-floor-is-structural` (one of the three R28 rewrites) is
  outside it, so the constraint is weaker than it reads. If the family is "the
  scenarios about consolidation", membership is a judgment. Name the set.

Everything else I checked resolved: "durable chain artifact" is defined by
exclusion in R14 and given criteria under Decisions ("no upstream field, no
chain-driven lifecycle, nothing downstream consumes them"); "framing-shift
override", "ALWAYS gate", "never-planned", "Slot 6.3", and "row 8" all resolve
against the named files.

**5. Internal contradictions.** One hard contradiction inside the PRD (R31, see
Required Change 1). The reversals are otherwise carried consistently: Goals,
User Stories, R22, R24, R31 and the Decisions section all state the *reversed*
positions (proposal keeps three options; redirect narrowed, not retired), and I
found no residue of the original BRIEF positions anywhere in the PRD.

The BRIEF is where the reversals did not land. Its Status note says it was
edited in place after the PRD and that "the Problem Statement and User Outcome
above carry the corrected reading" — and they do. The sections below them were
not touched:

- **BRIEF User Journeys, "An author entering the tactical chain"**: "They are
  *not presented with an option to adjust a list that cannot change*, and not
  offered a bail whose two branches cannot execute." PRD R22 keeps Adjust, and
  R3 declares that `/scope`'s Adjust specifically cannot change chain
  membership. That is the exact thing the journey says the author will not see.
- **BRIEF Scope Boundary / In, bullet 3**: the terminal recording set
  "rejection record, decision record, spike report, competitive analysis —
  *which stays*". PRD R14 keeps two of the four: competitive analysis becomes a
  route to `/comp` with the inline handler deleted, and decision becomes a route
  to `/decision`.
- **BRIEF Scope Boundary / Out**: "`/explore`'s research loop. *Setup*, scoping,
  discovery, and convergence are... untouched." PRD R15 removes part of Phase 0
  (Setup), and the PRD's own Out of Scope silently narrows the exclusion to
  "Phases 1 through 3". Phase 0 triage appears nowhere in the BRIEF's In list,
  so R15 is scope the BRIEF does not authorize in either direction.
- Smaller: R8 and R9 edit `/charter`'s own Phase 1/Phase 2 and state schema. The
  BRIEF's In list names only the two shared `references/` files plus `/scope`,
  `/explore`, the evals, and `pipeline-model.md`; its only `/charter` entry is an
  exclusion. The PRD's Decisions section justifies the misroute fixes (R20)
  explicitly and well — R8 and R9 get no equivalent.

**6. Writing style.** Clean. Zero hits against `rules.yaml` word lists across
all 33 requirements and every prose section — including the categories that
usually leak (`comprehensive`, `robust`, `leverage`, adverb openers). Em dash
density is 3.5 per thousand scoped words against a threshold of 10. Contractions
present. Burstiness is real (three-word sentences next to thirty-word ones).
On the judgment-only rules: no empty conclusions, no synonym cycling, no forced
rule of three that I could find a different true count for, no attribution
without citation, and demonstratives resolve. The Prose Vocabulary exemption was
not needed — `tier`, `journey`, and `underscore` do not appear.

One low-information passage, and it is a single clause: Known Limitations,
"so the first real use will be the test." The paragraph before it already says
no run exercises the handoff end to end; the clause restates that as a
prediction. Cut it or say what to watch for on first use.

## Ambiguous Requirements

| Req | Ambiguous phrase | Reading A | Reading B |
|---|---|---|---|
| R1 | "SHALL name the grounds on which a child may legitimately not run" | Enumerate R4's closed `chain_skipped[].reason` vocabulary inline, so the pattern and the schema state one list | Describe the three gate shapes in prose (auto-skip on an existing artifact, a feeder whose gate never opened, an author declination) and leave the enum to the schema |
| R4 | "SHALL admit every ground the two parents record today" | The grounds as of the pre-change corpus, including `/charter`'s reason "naming the supplied upstream" — which carries a path, so the enum needs a member plus a sibling value | The grounds as they stand after R8 and R9 have already changed what `/charter` records |
| R7 | "Every statement enumerating 'both v1 parents' or a fixed child count" | Every such statement inside `references/parent-skill-pattern.md` (the requirement's stated subject) | Every such statement across the corpus — the state schema, the resume-ladder template, and both parents' SKILL.md files, which is several times the work |
| R9 | "SHALL NOT permit an author to opt a child out without a recorded ground" | Keep `/charter`'s Adjust able to drop a child, and require it to write a `chain_skipped` entry with a vocabulary member | Remove Adjust's ability to drop a child at all, satisfying the requirement vacuously — which R3 permits, since Adjust's reach into membership is declared per-parent |
| R10 | "the tiebreakers that discriminate between entry points... SHALL survive" | All existing tiebreakers survive, rewritten to discriminate between the four entry points | Only the subset that already discriminates between entry points survives; tiebreakers that separated PRD from DESIGN are deleted with the ten type tables |
| R10 + R14 | "SHALL score chain entry points rather than artifact types. The entry points are: [four]" versus R14's routes to `/comp`, `/decision`, and two `/explore`-authored types | Crystallize scores exactly four entry points, and `/comp`, `/decision`, spike, and rejection are reached by some other mechanism the PRD does not name | Crystallize scores eight destinations — four entry points plus the four non-chain outcomes — and "entry points" in R10 is loose for "routing destinations" |
| R13 | "the file-an-issue arm's stated next step SHALL be `/work-on`" | `/work-on` is prose attached to the issue arm; crystallize still scores four entry points and the AC list (`/scope`, `/charter`, `/execute`) is complete | `/work-on` is a fifth scored destination, and the AC that enumerates the three named skills is missing one |
| R17 | "a path that collides with no *existing* resume-ladder match condition" | "Existing" means the conditions as they stand today, so the `wip/<child>_<topic>_scope.md` convention must change and `/explore`'s handoff filename moves | "Existing" is evaluated after R20 narrows both conditions, in which case the current path already satisfies it and nothing is renamed — which is what the AC literally tests |
| R23 | "Bail at Phase 1 SHALL execute" | Make clean-cancel reachable: Phase 1 bail tears down or marks the state file Phase 0 wrote, and no document is produced | Make abandonment-forced reachable: Phase 1 bail materializes a schema-compliant partial artifact with the abandonment marker so hard finalization has a non-empty artifact list |
| R25, R26 | "SHALL be either specified or removed" | Specify the field / prompt, with a stated reader and a recorded answer | Delete both outright. The disjunction looks deliberate, but neither requirement states a criterion for choosing, so the outcome is not predictable from the PRD |

## Required Changes

1. **Fix R31. It contradicts itself and its own acceptance criterion, on a
   verifiable fact.** R31 says `chain-shape-is-constant` "SHALL keep the three
   expectations that assert the whole chain runs, that skipping a child would be
   a judgment about an unwritten document, and that a redundant artifact is
   removed by consolidation after both exist; *its fourth expectation* SHALL be
   updated to match R24's narrowed redirect." In `skills/scope/evals/evals.json`
   the four expectations are, in order: (1) runs the whole chain, (2) skipping
   the BRIEF is a judgment about an unwritten document, (3) points the author at
   invoking `/design` directly, (4) a redundant BRIEF is removed by Phase 2
   consolidation. The contested one is the **third**, not the fourth — so R31 as
   written orders the fourth expectation both preserved and rewritten. The
   matching AC gets it right ("retains its first, second, and fourth
   expectations verbatim"), which makes requirement and criterion disagree.
   Change "its fourth expectation" to "its third expectation" in R31.

2. **Say which terminal state Bail at Phase 1 reaches (R23).** The requirement
   names both broken branches and requires execution without choosing. Name the
   outcome — clean-cancel with the Phase 0 state file disposed of, or
   abandonment-forced with a partial artifact materialized — or state the rule
   that decides between them. The AC ("reaches a defined terminal state") does
   not discriminate and should be tightened to match.

3. **Decide whether the handoff path moves (R17).** As written, R17's
   requirement and its AC can be satisfied by two different worlds, because R20
   removes the collisions R17 uses to justify the move. Either state that
   `/explore`'s handoff filename changes and R20 is defense in depth, or state
   that the convention is kept and R20 is the whole fix. This is not cosmetic:
   `/charter` writes and reads `wip/vision_<topic>_scope.md` and
   `wip/roadmap_<topic>_scope.md` as its own pre-populated handoffs
   (`skills/charter/references/phases/phase-finalization.md:518`,
   `phase-2-chain-orchestration.md:423`), so a rename forks the convention and
   the receiving-side scenarios R30 preserves need to know which path they see.

4. **Split R15 and give "reconciled" a completion condition.** Make the removal
   of the Phase 0 artifact-type triage one requirement and the reconciliation of
   the investigation-versus-breakdown-versus-ready triage another. For the
   second, say what reconciliation produces: the Stage 1 triage is deleted, or
   it is kept and its outputs feed the Phase 4 router, or the `needs-*` label
   writes stop while the triage question survives. Add at least one acceptance
   criterion — both halves are currently uncovered, and
   `references/label-reference.md` is left unaddressed either way.

5. **Bound R7's second sentence.** State whether "every statement enumerating
   'both v1 parents' or a fixed child count" means within
   `references/parent-skill-pattern.md` or across the corpus. The AC covers only
   the roster, so the larger reading has no criterion behind it.

6. **Make R9 decide.** Say whether `/charter`'s Adjust keeps the ability to drop
   a child (and must record a ground) or loses it. Both readings satisfy the
   present wording and the present AC, and they produce different prompts.

7. **Resolve R10 against R14.** R10 says crystallize scores chain entry points
   and names four; R14 keeps `/comp`, `/decision`, spike reports, and rejection
   records reachable. Say how an author reaches those four once the ten
   per-type signal tables are gone — a fifth scoring category, a pre-scoring
   branch, or scored entry points plus scored terminal outcomes. Same question
   settles R13's `/work-on` arm.

8. **Replace the two undefined terms.** In R4, cite
   `references/parent-skill-child-inspection.md` for the grow-by-PR-review
   precedent instead of referring to an unnamed convention. In R28, define "the
   consolidation family" by enumeration or by the `consolidation-` name prefix
   — `evals.json` has no family field, so the constraint is unverifiable as
   phrased, and `durable-artifact-floor-is-structural` sits outside the prefix
   while being one of the scenarios R28 rewrites.

9. **Reconcile the BRIEF with the reversals it did not absorb.** The BRIEF is
   Accepted and durable, and three of its sections still state the pre-reversal
   positions: the "author entering the tactical chain" journey says the author
   is not presented with an Adjust option on an unchangeable list (R22 and R3
   keep exactly that); the In-scope bullet says all four terminal recording
   types stay (R14 keeps two); the Out-of-scope bullet excludes Setup while R15
   edits Phase 0. Fix the BRIEF, or state in the PRD's Decisions section that
   these three points are superseded and why — the PRD does this well for the
   Open Questions and for the misroute fixes, and these deserve the same
   treatment.

## Optional Improvements

- **R1**: drop "at the head of its Gate Vocabulary section". The AC already
  carries the real constraint (findable without opening a skill directory), and
  the section choice is a drafting call. Gate Vocabulary is a slightly odd home
  for a statement about chain shape rather than about gates.
- **R2**: "a one-sentence note that no behavior changed" prescribes form. State
  the outcome — a reader must not read the restatement as a behavior change.
- **R4**: "an optional sibling field" is schema design. "The ground comes from
  the closed set; free text is never the ground" is the requirement.
- **R22**: the requirement says "keep its three options" but the PRD never names
  the third (Proceed). Goals speak of "the two author affordances". Name all
  three once so the count is checkable.
- **R25 and R26**: both are "specify or remove". If either outcome truly serves,
  say so explicitly; otherwise name the criterion that decides.
- **Known Limitations**: cut "so the first real use will be the test" — it
  restates the preceding sentence as prophecy. Say what would go wrong on first
  use instead.
- **R33**: "SHALL agree with the router" is a soft verb rescued by its AC.
  Pulling the AC's two concrete prohibitions into the requirement would make it
  standalone.
