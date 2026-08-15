<!-- decision:start id="contribution-section-authorship" status="assumed" -->
### Decision: Who authors a contribution section

**Context**

R4 puts an absorbed ancestor's contribution into the survivor as one
fixed-heading section, and R13 requires the carry check to run against text that
already exists. Neither names the actor. The fork as posed was child-at-drafting
versus parent-at-fold, with the stakes framed as: child authoring rides an
existing quality jury but writes every document a section speculatively, before
anyone knows a fold is coming; parent authoring writes sections only where an
absorb happens but leaves the mover as the verifier.

Three verified facts reshape that framing before the alternatives can be scored.

*Parent and child are the same agent context.* The dispatch contract
(`references/parent-skill-pattern.md:395-403`) binds child invocation to "the
**Skill tool**, called inline from the parent's own agent context ... the parent
owns no team at its own layer; the child runs in the parent's agent context." So
the fork is not about which agent holds the pen. It is about which instruction
file holds the drafting instruction, and therefore whether the child's jury —
which *is* a separate set of Agent-tool spawns, at the child layer — sees the
section before it lands.

*The tactical juries do not receive the upstream document.* `/prd`'s three
reviewer prompts carry the PRD and `wip/prd_<topic>_scope.md` and nothing else
(`prd/phase-4-validate.md:50-54, 92-93, 131-132`). `/design`'s three carry
excerpts of the DESIGN (`design/phase-6-final-review.md:35, 51, 89`). `/brief`'s
two carry the BRIEF, the visibility context and the format reference
(`brief/phase-4-validate.md:112-113, 193-199`). Only `/strategy`'s altitude
reviewer is handed its upstream (`strategy/phase-4-validate.md:193-197`), and
`/plan` gets a partial version through `/review-plan`'s design-fidelity check
(`review-plan/phase-2-design-fidelity.md:11, 28`). This falsifies the premise the
exploration's D1 leaned on — "wherever the child authors the contribution, the
child's own jury reads the upstream and the draft together ... with a spawn
already budgeted." That is true of the strategic chain and false of the tactical
one. Child authoring never got the two-sided comparison for free; it would have
needed an upstream context block added to four reviewer prompts. That was the
alternative's headline advantage and it does not exist.

*A child cannot know at drafting time whether its upstream will be absorbed.*
The consolidation judgment is step 8 of Phase 2's eight-step per-child loop
(`scope/phase-2-chain-orchestration.md:38-66`), reached after child invocation
(step 3), artifact existence (4), snapshot (6) and validator pass-through (7).
The verdict for hop X→Y is therefore reached strictly after Y has been drafted,
juried, landed and validated.

**Assumptions**

- **The dispatch contract's v1 binding holds for the life of this work.** The
  parent-and-child-share-one-agent-context finding rests on
  `parent-skill-pattern.md:395-403`, which explicitly labels the Skill tool a
  Layer-2 binding "replaceable when the amplifier layer ships via the
  `team_primitive` substitution surface." If that substitution lands and children
  become out-of-context agents, the authoring split recommended here is
  unaffected — the parent still composes — but the claim that this costs no spawn
  becomes a claim about the Layer-1 element instead.
- **`/design` and `/plan` gain child-side consumption instructions comparable to
  `/prd` Phase 3.2's.** The file count below assumes the DESIGN's body-assembly
  step is `design/phases/phase-2-execution.md` and the PLAN's is
  `plan/phases/phase-7-creation.md`, identified by grepping for the canonical
  artifact path. If either skill assembles its body across more than one phase
  file, the child-side count rises by one or two, not more.
- **R10's carve-out is intended to permit exactly the restatement this
  recommendation produces.** The contribution section distills material that also
  remains in the survivor's ordinary required sections. R10 exempts "the absorbed
  case," which reads as covering this; if the DESIGN instead intends the material
  to be *moved* rather than restated, the recommendation is unchanged but the
  carve-out wording must say move, and the child-side consumption instructions
  become load-bearing for a second reason.
- **No independent reviewer of the contribution prose is added.** This mirrors
  R12's disposition of the verdict rather than re-deciding it. Verified as a
  structural bar, not a preference: grep for `Agent tool`, `subagent`, `Task
  tool` and `spawn` across all six `skills/scope/references/phases/*.md` returns
  zero matches, and `/scope`'s Team Shape declares the parent single-agent.
- **Issue #280's body was not readable from this worktree.** Framing is taken
  from the PRD and the exploration artifacts; every structural claim above is
  read from committed files.

**Chosen: Parent composes at fold time from the survivor's own body; the child
owns the consumption instruction that puts the material there**

The two halves are separable and the decision assigns them differently.

*Child side — consumption, not authoring.* Each child's drafting phase is
instructed to read its upstream and carry that upstream's content forward into
its own ordinary required sections, sharpened to its own altitude rather than
quoted. This is precisely what `/prd` Phase 3.2 already does
(`prd/phase-3-draft.md:63-85`): a four-row mapping table, "draw those four
sections from the brief's body, not from this PRD's own Phase 1 conversation,"
and an explicit statement that carrying the framing forward "is also what makes
the downstream consolidation judgment usable." Read carefully, that shipped
precedent is a consumption instruction. It does not author a labelled section and
never has — the carried content lands in the PRD's ordinary Problem Statement,
Goals, User Stories and Requirements/Out of Scope. The precedent supports the
child side of this split and does not support child-authored contribution
sections, which have never existed anywhere in the corpus.

*Parent side — composition at fold time.* On verdict `absorb`, `/scope` composes
the fixed-heading contribution section by distilling material the survivor
already carries, places it after `## Status` per R4 and R6, writes R21's
frontmatter declaration and `## Status` line, and only then runs R14's carry
check against it. The source of the prose is the survivor, not the doomed
original. That is the load-bearing constraint and the DESIGN should state it as
one: the parent is compressing and relocating text a jury has already read, not
composing an original claim about a document only the parent ever saw.

The parent writing into the survivor is not a new concession. It is settled
already by R17 (splice `upstream:`), R21 (frontmatter field plus one pinned-shape
`## Status` line) and R18 (a revert that removes the declaration, the `## Status`
line and the contribution section). None of those can be child work, for the same
sequencing reason. R19's extension of the closed write-target set covers the
prose write alongside them; the set as it stands today
(`scope/phase-3-exit-finalization.md:277-297`) already understates the parent's
reach, since the existing `upstream:` re-point writes the survivor and is not
listed.

**Rationale**

Unconditional child authoring is eliminated by requirements that are already
settled, not outscored by a judgment call. R4 says "a document that **absorbs** an
ancestor SHALL carry that ancestor's contribution as a single section." A child
writing that section at drafting time writes it before the verdict exists, so on
every `keep` the survivor is left carrying a contribution section for a document
that still sits on disk. That falls outside R10's carve-out, which is scoped to
"the absorbed case" specifically, and it is duplication of a living document under
the very content-boundary rule R10 amends. It also collides with the validator:
`crates/shirabe-validate/src/formats.rs`'s `FormatSpec` has `required_sections:
Vec<String>` and one Plan-specific `execution_mode_required_sections` override,
with no general per-section optionality primitive — so an always-present
contribution section is the only shape the current validator expresses, and it is
the wrong shape.

Given that, the live question is narrower than posed: where does the prose come
from, and what has reviewed it. Composing from the survivor rather than from the
original is what makes the non-independence tolerable. The material was reviewed
by the child's jury when it landed in the survivor's ordinary sections; the
parent's act is compression of reviewed prose. The residual failure — the parent
under-distills — leaves the omitted content still visible in the survivor's own
body, recoverable by a reader. Composing from the doomed original has no such
property: whatever the parent fails to carry is gone at `git rm`, and after
squash-merge it never existed on the default branch, which the PRD already
records as a Known Limitation.

A fold-time reviewer is unavailable for the same structural reason R12 cited, and
that reason is verified rather than assumed: zero spawn sites across `/scope`'s
six phase files, and a dispatch contract declaring the parent owns no team at its
own layer under `team_primitive: single-team-per-leader-no-nested`. Adding one
would be `/scope`'s first team, contradicting a declared binding rather than
merely spending an unbudgeted spawn. The honest accounting is that the
contribution prose is self-graded, that this is the same self-grading the PRD
already books under "Static validation buys presence, not fidelity," and that
sourcing from the survivor narrows it rather than closing it.

The accepted trade-off is that the section is written once, by one agent, with no
second reader — and the two-sided R7 criterion is applied by its own author. What
buys back some of that is R14: the carry check itemizes each of the ancestor's
required sections plus every contribution it inherited, and any failure aborts to
`keep` and deletes nothing. The check is mechanical about coverage even where it
is self-graded about quality.

**Alternatives Considered**

- **Child authors unconditionally at drafting time.** Every BRIEF/PRD/DESIGN/PLAN
  writes a contribution section for its upstream as part of its normal draft
  phase. Rejected because it contradicts settled requirements rather than merely
  costing more: a child cannot know the verdict at drafting time (judgment is step
  8 of eight), so `keep` runs leave an orphan section that R4 does not sanction
  and R10's carve-out does not cover, and the validator has no per-section
  optionality primitive to express a conditional one. Its stated advantage —
  riding a jury that already sees the upstream — was verified false for `/brief`,
  `/prd` and `/design`.

- **Parent authors at fold time from the doomed original.** `/scope` reads the
  artifact it is about to delete and composes a distillation of it. Rejected as
  the weaker half of the chosen option: it puts the same single authoring site in
  the same unreviewed position, but sources the prose from content that ceases to
  exist the moment the `git rm` lands, so an omission is unrecoverable rather than
  still visible in the survivor's body.

- **Parent re-invokes the child in a bounded authoring mode.** On `absorb`,
  `/scope` calls the survivor's own skill again with a narrow "author the
  contribution section" input mode. Rejected because it buys no independence
  unless the child's jury re-runs for one section — which *is* a new spawn, inside
  the child, for a paragraph — while adding a fifth input mode to each child and a
  ninth step to a loop whose "eight-step ordering is the contract."

- **Lazy propagation: the child authors only inherited contributions.** A document
  writes a contribution section only for an ancestor already absorbed into its
  upstream and therefore visible at drafting time. Rejected as incomplete rather
  than wrong: it never touches the base case, so the section for the ancestor being
  absorbed right now still has no author, and it splits one section family across
  two authoring sites under two different instructions. Its useful content — that
  a child must read contribution sections its upstream already carries — is kept,
  as part of the child-side consumption instruction.

- **Independent fold-time reviewer (D1's Alternative 3, revived).** The
  exploration held this open pending exactly this fork, expecting it to become
  correct if the parent authored. Still rejected: the structural bar R12 found is
  verified and applies identically to prose review, and the non-independence the
  reviewer would address is materially smaller once the prose is sourced from
  already-reviewed material in the survivor.

**Consequences**

The DESIGN must state the parent's composition step as sourcing from the
survivor's own body, and must place that step before the carry-table step so R13
holds and the PRD's `[insp]` criterion ("the absorb procedure's authoring step
precedes its carry-table step") has something to read.

Each child that sits below an absorbable hop needs a consumption instruction of
its own. **Yes** to the secondary question, and the count is bounded. `/prd`
already has one and needs amending, not writing: `phase-3-draft.md:82-85`
currently justifies itself by "`/scope` checks section by section whether this PRD
carries the brief's four concerns," which is the type-level mapping model R1
deletes. `/design` and `/plan` need new blocks, since R1 makes PRD→DESIGN and
DESIGN→PLAN absorbable and neither child is told to carry its upstream forward
today — `/design` reads the PRD at `phase-0-setup-prd.md:25-27` and `/plan` reads
its source at `phase-1-analysis.md:33`, both as inputs to their own work rather
than as content to carry. `/brief` needs none: nothing absorbs into a BRIEF, which
is the same reason the PRD's criteria exclude BRIEF from R10's carve-out.

Instruction-file footprint, enumerated for the PLAN's decomposition:

| Group | Files | Paths |
|---|---|---|
| Child consumption instructions | 3 | `skills/prd/references/phases/phase-3-draft.md` (amend), `skills/design/references/phases/phase-2-execution.md` (new), `skills/plan/references/phases/phase-7-creation.md` (new) |
| Format references | 4 | `skills/{brief,prd,design,plan}/references/*-format.md` — R3 declaration, R5 fixed heading, R4/R6 placement, R7 two-sided criterion, R10 carve-out (3 of 4; BRIEF excluded) |
| `/scope` procedure | 2 | `skills/scope/references/phases/phase-2-chain-orchestration.md` (Stages 1-3, authoring step, carry check, citation check, record), `skills/scope/references/phases/phase-3-exit-finalization.md` (R19 write-target set) |
| Child jury prompts | 0 | Not required under this recommendation |

Roughly nine instruction files, against roughly thirteen under child authoring —
the difference being the four jury prompts that would have needed an upstream
context block, plus a jury criterion each. Validator, state-schema and eval work
(R8, R9, R16, R24, R25, R26) is common to either answer and is not counted here.

What becomes harder: the contribution prose has exactly one author and no second
reader, and R7's two-sided criterion is applied by that author to their own text.
That is the self-grading limitation the PRD already books, now located precisely
rather than left to the DESIGN to discover. The DESIGN should say plainly that
sourcing from the survivor narrows the omission vector without closing it.

What becomes easier: no document carries a section for a fold that never happened;
the validator needs no per-section optionality primitive it does not have; `/scope`
needs no team, no ninth loop step and no new child input mode; and D1's chosen
adequacy criterion survives unchanged in wording, relocated from the child's jury
(which could not have applied it as written) to the format reference and the
parent's carry check.

One correction propagates into D1's own record. Its rejected Alternative 3 says
the independence a fold-time reviewer would buy "already exists one phase earlier:
wherever the child authors the contribution, the child's own jury reads the
upstream and the draft together." That is true for `/strategy` and false for
`/brief`, `/prd` and `/design`. The conclusion — no fold-time reviewer — still
holds, on the structural ground R12 established rather than on the
already-purchased-independence ground D1 gave. The DESIGN should carry the
corrected reason.
<!-- decision:end -->
