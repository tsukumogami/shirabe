# Lead: What does `skills/scope/SKILL.md` tell an agent the chain is for, and which text carries that message?

All paths relative to `public/shirabe` unless noted. Line numbers are from
`skills/scope/SKILL.md` at branch `docs/scope-process-framing` (968 lines).

## Findings

### 1. The incident report's core claim holds, but it needs a sharper statement

The claim "the skill states exactly one motivated purpose and that purpose is
artifact reduction" is **true if you scope it to purpose**, and **false if you
scope it to argumentation in general**. SKILL.md argues in several places. What
it never does anywhere is argue for the chain.

Distinguish two kinds of argument in the file:

- **Rule-justification** — "here is why this rule is written the way it is."
  Plentiful. `## Security Considerations` (822-934, 113 lines) is the file's
  longest section and is heavily argued: why `docs/plans/` belongs in the
  mutation list (849-854), why three pre-existing defects were folded into the
  enumeration (872-881), why cross-repo upstreams are accepted rather than
  rejected (929-933). `## Validator Pass-Through` argues envelope-before-exit-code
  precedence at 709-719. `## Upstream Flag` argues the lifetime rule at 152-157
  and the inbound/outbound asymmetry at 166-171.
- **Value-of-the-outcome argument** — "here is why this outcome is worth
  wanting." There is exactly one instance in the file, and it is
  `## Why the Artifact Set Shrinks` (472-531, 60 lines), whose opening sentence
  is a reader-benefit claim: "Three documents that restate one problem at three
  altitudes cost a reader three reads for one idea, and an obvious concept
  articulated three times reads as ceremony. Sparing the reader that is worth
  doing" (474-477).

So the file contains no competing claim of the form "running the steps is worth
doing because X." The one thing SKILL.md tells a reader is *worth doing* is
ending with fewer documents. That is the asymmetry, and it survives the
narrower reading.

### 2. Section-by-section inventory (argue vs. tabulate)

Measured with `awk` over `## ` boundaries. "Reason markers" counts lines
containing `because | the reason is | so that | deliberate | worth doing |
which is what | rather than a | the point of` — crude, but it separates prose
that justifies from prose that enumerates.

| Section | Start | Lines | Reason markers | Character |
|---|---|---|---|---|
| (lede, no heading) | 19 | 30 | 0 | tabulate — what the skill is, which exits exist |
| Team Shape | 49 | 25 | 1 | tabulate |
| Input Modes | 74 | 28 | 0 | tabulate |
| Execution-Mode Flags | 102 | 21 | 0 | tabulate |
| Upstream Flag | 123 | 50 | 3 | mixed — rule-justification |
| Coordination Intent | 173 | 91 | 1 | mostly tabulate + binding |
| Topic-Slug Constraint | 264 | 21 | 0 | tabulate |
| **Workflow Phases** | 285 | 37 | **0** | **pure tabulate** |
| Resume Logic | 322 | 40 | 0 | tabulate |
| **Phase Execution** | 362 | 41 | **0** | **pure tabulate** |
| **Reference Files** | 403 | 18 | **0** | **pure table** |
| Chain-Proposal Output | 421 | 51 | 3 | mixed — 436-445 argue the no-shorter-chain rule |
| **Why the Artifact Set Shrinks** | 472 | **60** | 3 | **pure argument, value-of-outcome** |
| Consolidation Judgment | 532 | 47 | 0 | rule statement + some justification |
| Three Exit Paths | 579 | 47 | 3 | mixed |
| State File Schema | 626 | 19 | 0 | tabulate |
| Visibility Detection | 645 | 19 | 0 | tabulate |
| Manual-Fallback Non-Interference | 664 | 34 | 0 | tabulate |
| Validator Pass-Through | 698 | 48 | 2 | mixed — rule-justification |
| Phase-N Reject In-Chain | 746 | 12 | 0 | pointer |
| Abandonment-Forced Marker | 758 | 64 | 0 | tabulate |
| Security Considerations | 822 | 113 | 6 | mixed — rule-justification |
| Binding Notes | 935 | 34 | 1 | tabulate |

The measurable asymmetry: **the five sections that describe what the chain
actually does — Workflow Phases (37), Resume Logic (40), Phase Execution (41),
Reference Files (18), State File Schema (19), 155 lines total — contain zero
reason markers between them.** Not one line in any of them says what a step
buys. Meanwhile the artifact-set block (`Chain-Proposal Output` second half +
`Why the Artifact Set Shrinks` + `Consolidation Judgment`, roughly 421-578,
~158 lines, of which ~120 are about the size of the artifact set) carries the
file's only sustained argument about what a run is for.

The `## Workflow Phases` table (295-301) confirms the report's characterisation
exactly. Its "Purpose" column is mechanical operations, not purposes:

    | 0. Setup | Slug validation; visibility detection; state-file creation;
                 stale `parent_orchestration:` self-heal | ... |
    | 2. Child Invocation Loop | Per-child: worktree-staleness check ...; write
                 `parent_orchestration:` sentinel; invoke child ...; capture
                 child snapshot; validator pass-through; consolidation
                 judgment | ... |

Phase 2 — the phase that runs the entire chain — is described as a list of
bookkeeping operations wrapped around the word "invoke child." Nothing states
what invoking the child produces beyond a file.

### 3. There is no text anywhere in SKILL.md stating why the steps are run

Confirmed by search rather than by impression:

    grep -in 'bakeoff|jury|adversar|cross-examin' skills/scope/SKILL.md   -> 0 hits
    grep -rin 'bakeoff|jury|adversar' skills/scope/references/            -> 0 hits
    grep -rin 'bakeoff|jury|adversar' references/parent-skill-*.md        -> 0 hits

The vocabulary of what the chain buys does not appear in `/scope`'s surface at
all, nor in the shared parent-skill pattern references. It appears only in the
child skills, and only sparsely:

- `skills/prd/SKILL.md:142` is the **only** explicit "why the step is run"
  statement I found in the tactical chain: "**Jury Validation**: Phase 4 is not
  optional -- authors consistently miss ambiguity and testability gaps in their
  own writing, so all PRDs get reviewed by 3 agents." That is exactly the shape
  of statement `/scope` lacks, and it exists one level down.
- `skills/brief/SKILL.md:94, 228, 284` describe the two-reviewer jury
  mechanically (what it is, how it is spawned), not what it buys.
- `skills/design/SKILL.md:262` names the Phase 6 jury in one clause.
- `skills/plan/SKILL.md` — no hits at all.

**Would an agent holding only SKILL.md reach any of it? No.** SKILL.md's
`## Reference Files` table (403-419) lists thirteen files. Every one is either a
pattern contract surface or a `/scope` phase procedure. **No child SKILL.md is
named anywhere in `/scope`'s SKILL.md.** The only route to `/prd`'s jury
rationale is to actually invoke `/prd` — which is precisely the act the agent
skipped. The rationale is downstream of the decision it should have governed.

The `${CLAUDE_PLUGIN_ROOT}` shared references are no better. Two candidates
exist and neither closes the gap:

- `references/parent-skill-pattern.md:3-7` defines a parent skill purely
  mechanically: "A parent skill walks an author through a sequence of child
  skills, holds state across child boundaries, and enforces invariants that span
  the chain." Mechanism, not purpose.
- `references/workflow-principles.md` (115 lines) is the closest thing shirabe
  has to a statement of values — and **`/scope`'s SKILL.md never cites it.**
  Grepping the citation list in SKILL.md gives: parent-skill-pattern (9),
  coordination-strategy (6), parent-skill-state-schema (5), state-schema (3),
  parent-skill-security (3), worktree-discipline (2), tool-declaration-policy
  (2), pipeline-model (2), resume-ladder-template (2), cross-repo-references (2),
  child-inspection (1). `workflow-principles.md` appears zero times.

That last point cuts *against* the fix as well as for it. If an agent did reach
`workflow-principles.md`, the second principle it would read is
**`## P2: Default to the lowest ceremony`** (line 41): "Reach for the least
machinery the work needs. Escalate only when a named condition forces it." That
is a third piece of reduction-leaning prose, and it is the framework's own
stated principle. Any rewrite of `/scope` needs to say why P2 does not license
skipping hops, or P2 becomes the next available justification.

### 4. Undefined vocabulary: "contribution"

SKILL.md uses the word "contribution" eight times (494, 495, 542, 552, 553, 557,
568, 852) — "Each type declares one contribution to the chain" (552) — and
**never says what any type's contribution is.** The reader is handed the
vocabulary of a step-output model with the model itself missing. The definition
of what a contribution is in operational terms lives only in
`skills/scope/references/phases/phase-2-chain-orchestration.md:597-600`, inside
Stage 2 of the judgment.

This matters for the fix: the sink-and-source framing the author wants is
already half-present in SKILL.md's vocabulary. It needs stating, not inventing.

### 5. The justification is duplicated, and the copy at the decision point is better

This is the most actionable finding in the lead.

`skills/scope/references/phases/phase-2-chain-orchestration.md:488-500` already
carries the argument, at the hop where the judgment fires, under an explicit
`**Why it exists.**` label:

    ## Consolidation Judgment

    Step 8 is where the artifact set shrinks.

    **Why it exists.** Three documents restating one problem at three
    altitudes cost a reader three reads for one idea, and an obvious
    concept articulated three times reads as ceremony. Reducing the
    set is worth doing for the reader. It is only honest to do it
    *here* — against two bodies that exist, where the question "does
    the upstream do work the downstream does not?" has an answer. The
    same question asked at Phase 1, before either document is
    written, has no answer, and answering it anyway is how content
    gets lost.

Compare SKILL.md:474-484. It is the same argument, near-verbatim on the first
sentence, hoisted to the parent file. **SKILL.md's `## Why the Artifact Set
Shrinks` is a duplicate of text that already sits correctly placed one level
down.** Deleting it from SKILL.md loses nothing the chain needs, because the
Phase 2 reference already states it at the point of use, scoped to the two
documents in hand — which is the placement the issue argues for. The cost of the
placement half of the fix is closer to a deletion than to a rewrite.

The same duplication holds for the Phase 1 half.
`skills/scope/references/phases/phase-1-discovery.md:11-36` carries
`## What Phase 1 Decides, and What It Does Not`, which states the no-shorter-chain
rule and the withdrawn-entry-altitude history in full, at the phase where it
binds. SKILL.md:436-445 and 499-506 restate it.

### 6. Past-tense withdrawn-design narration — full inventory

The pattern is real and there are **six instances in SKILL.md**, three of them
concentrated in the reduction argument.

1. **472-489, `## Why the Artifact Set Shrinks`** — the known one. "An earlier
   revision of this skill decided per hop, before each artifact existed, whether
   the child was worth invoking; the party making that call was the one that
   benefited from not doing the work, and nothing it read could tell it what was
   being lost." (485-489) Written as an obituary for a withdrawn design. It
   describes the reading agent's situation exactly and addresses it to nobody.

2. **499-506** — "A briefly-shipped revision of this skill also let Phase 1
   choose an entry altitude for the chain. **It was withdrawn.** The question it
   asked the author was more answerable than the per-hop gates it replaced [...]
   but it was still a decision that shrank the artifact set before any artifact
   existed, and having two reduction mechanisms fire at different times meant
   neither read as the rule." Same shape: settled history, no live instruction.

3. **508-517** — "What it no longer is, is the route to a smaller artifact set
   [...] **Two rules, stated separately, because** collapsing them puts the
   artifact-set decision back where no artifact exists." The "two rules, stated
   separately, because..." construction is maintainer-to-maintainer editorial
   note explaining a document's structure, not an instruction to an executing
   agent.

4. **519-530** — "What it no longer means is a fixed outcome [...] There is no
   durable-artifact floor; the prohibition on reintroducing one lives beside the
   judgment in Phase 2 [...] it is recorded under its own name **so the two never
   blur again**." "Never blur again" narrates a past confusion; the actual
   prohibition is explicitly relocated elsewhere.

5. **872-881, `## Security Considerations`** — "Three corrections are folded into
   that enumeration, each a **pre-existing defect** rather than a consequence of
   this change. The deletion set named `docs/briefs/` alone, which was the
   type-level floor written into the security surface [...] And this file and the
   Phase 3 reference **disagreed** about whether the PLAN was a Phase 3 write
   target." Ten lines of changelog inside the authoritative security
   declaration.

6. **813** — "the lifecycle this abandonment short-cuts" (minor; a mechanism
   note, listed for completeness).

The same pattern recurs in the reference files, so it is a house style rather
than a slip: `phase-1-discovery.md:21` ("An earlier revision let Phase 1 choose
an entry altitude for the chain; it was removed for exactly this reason"),
`:175`, `:179`, `:308-319` ("This section previously stated a durable-artifact
floor [...] All three of those rested on the type-level absorbability test, which
is gone"); `phase-2-chain-orchestration.md:714-717` ("It replaces the retired
`absorbable:` boolean"), `:827-841` ("**`chain_ran:` is the reason the previous
paragraph here had to go.** It used to read that..."); and
`references/pipeline-model.md:83-87` ("An earlier version of this file called the
strategic chain strict and the tactical chain loose; both halves were wrong").

The count is worth stating plainly: in the 60-line section that carries the
file's only motivated purpose, roughly **30 lines (485-530) are past-tense
narration of designs that no longer exist.** Half the purpose-bearing section is
history. What survives as live instruction is the reader-benefit claim at
474-478 — the half the incident agent acted on.

Notably, `phase-2-chain-orchestration.md:719-739` shows the counter-example of
how to write this in the present imperative: "**Do not add a guard that forces
`keep` on the ground that the survivor would be the last artifact.** The
single-mechanism rule will not catch such a guard [...] so this prohibition has to
be written down rather than derived." Addressed to the reader, in the imperative,
with the reason for its own existence attached. The same content in SKILL.md is
written as an epitaph.

### 7. The write-target enumeration is unique to `/scope`

Verifying the issue's parity claim, since it bears on the recommended fix.
`/charter`'s `## Security Considerations` (`skills/charter/SKILL.md:289-352`)
names "closed write-target set" as one of the six bound pattern surfaces and
then covers only the two `/charter`-specific ones (interpolation discipline, the
flag's value reaching a committed field). **It enumerates no artifact paths.**

`/scope`'s section (835-870) enumerates `docs/briefs/BRIEF-<topic>.md`,
`docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md` as deletions and
`docs/{prds,designs,plans}/{PRD,DESIGN,PLAN}-<topic>.md` as mutations (847),
plus the force-materialize paths at 763-765 which name every canonical durable
path in the chain a second time. So SKILL.md publishes each artifact's address
twice, in two separate sections, and `/charter` publishes none. This is a
`/scope`-only divergence, and it can be narrowed without touching the pattern or
`/charter`.

It is a genuine bounding declaration, though: 830-833 states "This is the
authoritative declaration of the closed write-target set; the Phase 3 reference
restates it and the Phase 4 reference reads it back, and neither may diverge from
it." Two downstream files bind to this text as the source of truth, so the fix
here is a relocation with three files to keep consistent, not a deletion.

### 8. What a reader takes away from SKILL.md alone

Reading only this file, in order, an agent forms this picture:

`/scope` is a state machine. It validates a slug, detects visibility, writes a
state file, walks four children while writing and clearing a sentinel around each
one, runs a validator, records an exit, and deletes its scratch. The four
children are `/brief`, `/prd`, `/design`, `/plan`; the file never says what any
of them does. Then, sixty lines in the middle of the file, in the file's only
passage that argues the value of anything, the skill explains that ending with
fewer documents is worth doing for the reader, that three documents restating one
problem is ceremony, and that a sanctioned mechanism exists to reduce the set.
It closes by printing the exact path of every artifact in the chain, terminal one
included.

An agent asked what this skill is *for* has one answer available: it produces a
PLAN, and it prefers to produce as few of the other documents as it honestly can.
The constraint that reduction happens only after artifacts exist is stated — three
times, at 438-440, 480-484, and 499-506 — but every statement of it is entangled
with narration of designs that were withdrawn, so it reads as an explanation of
the file's own edit history rather than as a rule binding the current reader. The
one thing stated as a live, motivated good is the smaller set.

## Implications

**The intervention has a natural shape, and it is smaller than a rewrite.**
`## Why the Artifact Set Shrinks` (472-531) is duplicated content whose
correctly-placed original already exists at
`phase-2-chain-orchestration.md:488-500` under a `**Why it exists.**` label.
Deleting the SKILL.md copy costs nothing and resolves the placement defect. The
harder half is what replaces it.

**What replaces it should sit where the reader looks for purpose, which is the
lede, not the middle.** SKILL.md:21-47 currently spends thirty lines on
mechanism and asymmetries. The process-is-the-product framing belongs there — an
artifact is the sink for the step that made it and the source for the step that
follows; running the chain is not a way to obtain four documents. If it lands at
472 it inherits the position that caused the problem.

**Naming what each hop buys is now a gap, not a nicety.** The file uses
"contribution" eight times without defining it, and the only real statement of
step-value in the whole tactical chain is `skills/prd/SKILL.md:142`. Adding a
short statement of what each child produces and why — three or four lines in the
Workflow Phases area — turns "contribution" from an undefined token into the
thing the sink-and-source framing refers to. This is prose in `/scope` only, so
it stays inside the stated blast radius.

**The past-tense narration is a systematic style, and only the instances inside
the purpose-bearing text need fixing.** Six instances in SKILL.md, more in the
references. Converting all of them is out of proportion; converting 485-530 (the
~30 history lines inside the purpose section) is the part that changes what an
agent believes. 872-881 is in a security declaration where changelog is at worst
noise, and it can be left.

**`workflow-principles.md` P2 is an unaddressed flank.** "Default to the lowest
ceremony" is the framework's own principle and reads as license for exactly the
move that happened. `/scope` does not cite the file today, so the flank is only
open to an agent that finds it independently — but a rewrite that says "the
process is the product" without reconciling against P2 leaves the contradiction
in the corpus.

**The write-target enumeration is fixable within the blast radius but has
dependents.** It is `/scope`-only (charter enumerates nothing), so narrowing it
restores parity rather than breaking it. But SKILL.md:830-833 declares itself
authoritative and two phase references bind to it, so relocating the paths means
updating `phase-3-exit-finalization.md` and `phase-4-cleanup.md` in step. Also
note 763-765 publishes the same paths again in the abandonment section — halving
the enumeration in Security while leaving the abandonment copy intact achieves
nothing.

## Surprises

**The argument is duplicated, not merely misplaced.** I expected to find the
justification only in SKILL.md and to have to invent its Phase 2 form. Instead
`phase-2-chain-orchestration.md:492-500` already carries it, near-verbatim,
labelled `**Why it exists.**`, scoped to two documents that exist. The issue's
recommendation to "deliver the persistence justification at the hop where the
judgment fires" is already implemented. The defect is purely that the parent file
also hoists it. That makes the placement half of the fix a deletion.

**`workflow-principles.md` contains a second, independent reduction argument that
nobody has connected to this incident.** P2, "Default to the lowest ceremony,"
is a framework-level principle stating that reaching for less machinery is the
default. `/scope` does not cite it, so it did not cause this incident — but it is
the argument a future agent finds if the SKILL.md one is removed and it goes
looking.

**The one good example of the target register is already in the corpus.**
`phase-2-chain-orchestration.md:719-739` ("Do not add a guard that... so this
prohibition has to be written down rather than derived") is present-imperative,
addressed to the reader, reason attached. The rewrite has an in-house model to
copy rather than a style to invent.

**The report slightly overstates one thing.** "There is no section anywhere in
the skill arguing why the steps are run" is exactly right, but "the argumentation
in SKILL.md is one-sided" reads as though the file argues little else. It argues
a great deal — Security Considerations at 113 lines is the longest section in the
file and is dense with justification. The precise claim is that all of that
argues about *rule correctness*, and only one passage argues about *what is worth
wanting*. Stating it the loose way invites a rebuttal that the file is full of
reasons, which is true and beside the point.

**Where the report understates.** It cites one past-tense passage. There are six
in SKILL.md, and roughly half of the purpose-bearing section's 60 lines are
history rather than instruction.

## Open Questions

1. **Where exactly in the disclosure order does the framing go?** The lede
   (21-47) is where a reader looks for purpose, but it is currently a
   pattern-conformance statement aligned section-by-section with the parent-skill
   pattern's required structural elements (38-39). Does inserting a purpose
   paragraph before Team Shape break that alignment, or does the pattern permit a
   preamble? `references/parent-skill-pattern.md:674` (`## Required SKILL.md
   Structural Elements`) is the file to check — I did not read it.

2. **Does removing `## Why the Artifact Set Shrinks` break an eval?**
   `phase-1-discovery.md:326` names "eval 17" as grading the entry-altitude
   shortcut. If any eval greps SKILL.md for the section heading or its phrasing,
   deletion is not free. Needs a pass over the eval suite.

3. **How is P2 reconciled?** Does "default to the lowest ceremony" get an
   explicit carve-out for the chain, or does the `/scope` prose simply not
   engage it? Leaving it unaddressed leaves the next agent an argument.

4. **Is one statement of purpose enough, or does each hop need one?** The
   author's framing implies the sink-and-source property is general. But the
   `/prd` jury rationale (`skills/prd/SKILL.md:142`) suggests per-step value
   statements are what actually persuade. Whether `/scope` should name what each
   of the four hops buys, or state the general property once, is a real fork —
   the second is shorter, the first is what an agent can act on.

5. **How far does the write-target relocation go?** Bounding what the skill may
   write is worth keeping and two references bind to this declaration as
   authoritative. Options range from moving the paths to `parent-skill-security.md`
   to expressing them as a shape (`docs/<type>/<TYPE>-<topic>.md`) rather than an
   enumeration. Out of this lead's scope but it is the one part of the issue's
   suggested direction with mechanical consequences.

## Summary

The incident report's central claim holds under its precise reading: SKILL.md
argues a great deal about rule correctness — `## Security Considerations` alone
runs 113 argued lines — but `## Why the Artifact Set Shrinks` (472-531) is the
only passage in 968 lines that argues any outcome is *worth wanting*, and the 155
lines that describe what the chain actually does (Workflow Phases, Resume Logic,
Phase Execution, Reference Files, State File Schema) contain zero reason-giving
prose; the word "contribution" appears eight times undefined, no child SKILL.md
is reachable from SKILL.md's reference table, and the only real step-value
statement in the tactical chain sits at `skills/prd/SKILL.md:142` where a skipping
agent never sees it. The main implication is that the placement half of the fix
is a deletion rather than a rewrite — `phase-2-chain-orchestration.md:492-500`
already carries the same argument, near-verbatim, at the decision point under a
`**Why it exists.**` heading — so the real work is stating the process-is-the-product
framing in the lede (21-47) and converting the ~30 lines of withdrawn-design
obituary at 485-530 (six such passages exist in the file, not one) into present-tense
instruction, for which `phase-2-chain-orchestration.md:719-739` is an in-house model.
The biggest open question is `references/workflow-principles.md` P2, "Default to the
lowest ceremony" — a framework-level principle `/scope` never cites that reads as
license for exactly this shortcut, and that a purpose statement will have to
reconcile against or leave standing as the next available justification.
