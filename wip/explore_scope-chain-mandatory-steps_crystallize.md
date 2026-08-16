# Crystallize Decision: scope-chain-mandatory-steps

## Chosen Type

Tactical chain entry — `/scope scope-chain-mandatory-steps`.

Under the framework as written today the top-scoring supported type is **Design
Doc** (six signals, zero anti-signals; every other type demotes on at least one
anti-signal). Under the four-way router this exploration decided `/explore`
should become, "Design Doc" is not an arm — the arm is `/scope`, which runs
BRIEF → PRD → DESIGN → PLAN and lets the Phase 2 consolidation judgment decide
afterward which of those earned their keep.

The author selected the chain entry over the direct `/design` handoff. Recorded
here as the chosen type because it is the outcome the corpus's own model calls
for; the Design Doc scoring below is what produced it.

## Rationale

The model is settled and the open questions are all "how." `/scope` and
`/execute` already state one model in prose — chain steps are mandatory because a
judgment about whether a document carried anything can only be made against a
document that exists, and reduction happens after the artifacts exist, per hop,
against two bodies. `PRD-scope-artifact-persistence.md` R28 already forbids
reintroducing a pre-artifact worth decision "in any form, including an
author-chosen entry altitude," and eval 17 is its tripwire. Nothing about *what*
to build is open.

What is open is architectural, and the exploration surfaced multiple viable
paths for each: whether the chain-proposal prompt becomes a two-option
confirmation, a pure announcement, or disappears (and where the interactive entry
to R8 bail-handling lives if `Bail` leaves it); whether the direct-invocation
redirect is retired, narrowed, or merely re-justified, given that eval 17 pins it
and "shorter chain" is ambiguous between fewer artifacts and less conversation;
what `/explore`'s handoff artifacts must contain for `/scope` and `/charter` to
skip their Phase 1, since neither has a detection clause today; and how the
pattern document restates the ALWAYS-declination clause so that `/charter`'s
roadmap prompt reads as a preserved instance of the model rather than an
exception to it.

The exploration also made decisions a future contributor needs, and `wip/` is
swept before the branch merges. Four of them are load-bearing: the router is four
handoffs plus a terminal recording set rather than four arms; "never authors
chain artifacts" covers durable artifacts only, so the `wip/` handoff mechanism
survives; `/execute` is a false positive and needs no change on this axis;
porting a consolidation judgment to the strategic chain is deferred rather than
declined. None of those survive in a diff.

Entering at `/scope` rather than `/design` is also the honest choice on this
particular topic. Deciding now that a BRIEF and a PRD would not have carried
anything is the exact judgment the change exists to remove, and it would be made
before either document exists. If they turn out to do no work their successors
don't, Phase 2 absorbs them after both exist.

## Signal Evidence

### Signals Present (Design Doc)

- **What to build is clear, but how to build it is not**: the target model is
  stated in `/scope`'s and `/execute`'s prose and fenced by R28. Every remaining
  question is a choice between named alternatives.
- **Technical decisions need to be made between approaches**: the prompt's
  replacement shape, the redirect's fate, the handoff artifact's contract, and
  the declination clause's rewording each have two or more defensible answers
  surfaced by research.
- **Architecture, integration, or system design questions remain**: the fix site
  turned out to be `references/parent-skill-pattern.md`, a shared contract two
  parents and two eval suites depend on — a structural finding, not an editorial
  one.
- **Exploration surfaced multiple viable implementation paths**: notably for the
  chain proposal (confirmation / announcement / removal) and for the router's
  width (four arms / four plus terminal set / five with `/work-on`).
- **Architectural or technical decisions were made during exploration that should
  be on record**: the four listed above, plus the elimination of `/execute` as a
  fix site with the evidence for it.
- **The core question is "how should we build this?"**: yes — "what" was largely
  given by the author's framing and by R28.

### Anti-Signals Checked

- *What to build is still unclear (route to PRD first)*: not present. The
  four-surface inventory and the target model are both settled.
- *No meaningful technical risk or trade-offs*: not present. Eval 17 pins the
  redirect that two surfaces call stale; removing the triad from one parent but
  not the other only half meets the one-model goal.
- *Problem is operational, not architectural*: not present. The prompt, the gate
  vocabulary, and the `chain_skipped[].reason` vocabulary are contract surfaces.

## Alternatives Considered

- **Plan** — fires two anti-signals: the technical approach is still debated, and
  open architectural decisions need to be made first. A plan cannot sequence work
  whose shape is undecided.
- **PRD** — fires "requirements were provided as input to the exploration." The
  author stated the target model in the opening framing, and R28 states it
  normatively; a PRD would restate what two documents already say. Also partially
  fires "multiple independent features that don't share scope," since the router
  rewrite, the pattern-doc edit, and the eval repairs are separable workstreams.
- **No artifact** — fires the decisive anti-signal: architectural and structural
  decisions were made during exploration, and scope was debated across the three
  narrowing questions. Nothing in a diff would record why the router is four plus
  a terminal set rather than four.
- **Decision Record** — fires "multiple interrelated decisions need a design
  doc." Four coupled decisions, not one.
- **Competitive Analysis** — fires "repo is public"; COMP is private-only.
- **VISION** — fires "project already exists and question is about its next
  feature" and "scope is tactical."
- **Roadmap** — fires "technical approach for individual items is still debated."
  Sequencing four workstreams presupposes their shapes.
- **Spike Report** — fires "the question is what should we build" and
  "exploration was broad, not focused on a specific technical risk." Feasibility
  was never in doubt.
- **Rejection Record** — no rejection conclusion was reached; the exploration
  confirmed the problem rather than refuting it.
- **`/design` directly** — offered and declined. It is the current skill's
  routing answer and enters the tactical chain at its third step, deciding before
  either document exists that a BRIEF and a PRD are not worth writing. That is
  the behavior this change removes.

## Deferred Types

- **Prototype** — not applicable. Nothing here is answered faster by building
  than by deciding.

## Carry-Forward for `/scope`

The chain should read, and not re-derive:

- `wip/explore_scope-chain-mandatory-steps_findings.md` — the accumulated
  understanding, tensions, and gaps.
- `wip/explore_scope-chain-mandatory-steps_decisions.md` — the four decisions
  above and the two eliminations, with rationale.
- `wip/research/explore_scope-chain-mandatory-steps_r1_lead-*.md` — six research
  files with file-and-line evidence for every claim.

Two questions the chain must answer that this exploration deliberately left open:
what "a shorter chain" means to an author now that absorption reduces the
artifact set but not the conversation, and where the interactive entry to R8
bail-handling lives if `Bail` leaves the Phase 1 prompt.

One constraint the chain inherits: no PR-time check reads skill prose, and
`run-evals.yml` runs on a weekly cron rather than on pull requests. Whatever
lands, the same drift can recur unless something checks at PR time.
