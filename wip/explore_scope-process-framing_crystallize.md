# Crystallize Decision: scope-process-framing

## Chosen Type

A chain, entering at `/scope`. **Superseded in execution by the author's
election to re-explore under a corrected framing first** -- see Author Override
below. The framework's ranking is recorded in full because the work it names is
the same work; only the framing under which it gets scoped has changed.

## Candidacy

- `/execute`: **not a candidate.** The only PLAN on disk is
  `docs/plans/PLAN-work-on-friction-fixes.md`, whose `execution_mode` is
  `multi-pr`. A `multi-pr` PLAN does not qualify, and the PLAN covers an
  unrelated topic besides.
- Competitive analysis: **not a candidate.** `wip/explore_scope-process-framing_scope.md`
  records `## Visibility: Public`.

## Rationale

The exploration converged on something someone will build, left the central
architectural question open, and made decisions along the way that need a
durable home. That is the chain's signal set, and nothing in the findings
carries a chain anti-signal.

Two of the exploration's most load-bearing outputs are *falsifications* rather
than proposals -- the write-target relocation is theatre, and the sourcing
property is unreachable under either dispatch binding -- which pulls toward a
Rejection Record. But the overall conclusion is proceed, not don't-proceed, and
the stage-1 tiebreaker resolves that pairing to a chain on exactly that ground.
The rejections are inputs to the build, not a verdict against it.

At stage 2 the work is one bounded effort with an open architecture: whether a
conversational parent can be expressed as a koto workflow without losing the
conversation, and whether `/scope` wants full per-child materialization or only
koto's state machine and gating. Requirements are partly settled (the framing
content is drafted; the costs are established) and partly contested (the
materialization question). Filing an issue fails on three anti-signals at once,
and `/charter` fails on the project already existing and the work being one
bounded feature.

## Stage 1 Evidence

### A Chain -- score 5, no anti-signals

Signals present:
- **Converged on something someone will build**: adopting koto for `/scope`,
  carrying the framing content inside it.
- **Requirements, architecture, or sequencing questions remain open**: whether a
  conversational parent survives materialization; whether the state machine and
  the per-child materialization are separable here.
- **Decisions made during exploration need a durable home and downstream work**:
  the two falsified premises, the premise/verdict disclosure rule, and the
  decision to drop the sourcing framing.
- **A scope boundary emerged, not just an answer**: `/scope` only, `#320`
  untouched, and a boundary between what koto buys (sequencing, gating) and what
  it does not (isolation).
- **The core question is "what do we build, and how?"**: after the reframe, that
  is exactly the question.

Anti-signals checked, none present: nothing-left-to-build (no); output is one
choice between named options (no); a feasibility verdict nobody committed to
acting on (no -- the author committed); findings center on external products
(no); the conclusion is that the work should not happen (no).

### Rejection Record -- score 3, no anti-signals

Signals present: specific citable blockers identified with citations
(`parent-skill-security.md:49-73` binding the write-target set to `SKILL.md`;
`parent-skill-pattern.md:495-497` and `:521-528` on key-passing and equal
isolation); re-proposal risk is high (both remedies are the obvious next
suggestions and both are wrong); investigation was multi-round.

Signals absent: no active rejection conclusion about the *work* -- only about
two proposed remedies; no adversarial demand lead ran, because the source
issue's `bug` label tripped the Phase 1 skip.

Anti-signals checked, none present: leads did not run out; the reasoning is not
already documented publicly; the decision is not low-stakes.

### Decision Record -- score 1, demoted

Signals present: future contributors need to understand why (yes); exploration
compared specific alternatives with trade-offs (yes -- three write-target
options, two purpose-statement shapes).

Anti-signal present: **multiple interrelated decisions came with work attached.**
Demoted.

### Spike Report -- score 0, demoted

Signals present: a bounded investigation produced concrete findings; technical
uncertainty partly blocks the koto decision.

Anti-signals present: **the question is "what should we build?"** and
**exploration was broad rather than focused on a specific technical risk** --
eleven leads across framing, prose, evals, design lifecycle and dispatch.
Demoted.

### Ranking

- A chain: 5
- Rejection Record: 3
- Decision Record: 1 (demoted)
- Spike Report: 0 (demoted)
- Competitive Analysis: not a candidate

## Stage 2 Evidence

Stage 2 ran because "a chain" is the top-ranked stage-1 category.

### `/scope` -- score 9, no anti-signals

Signals present: a single coherent feature emerged (koto adoption for `/scope`);
requirements are contested (materialization versus gating-only); user stories and
acceptance criteria are missing; what to build is clear but how is not; technical
decisions need making between approaches; architecture and integration questions
remain (four koto templates, the eight-step loop as states, the resume ladder
reconciliation); exploration surfaced multiple viable implementation paths;
architectural decisions were made during exploration that should be on record;
the core question is "what should we build, and how?".

Anti-signals checked, none present: multiple independent features whose order
affects delivery (no -- one effort); one person can act without a written
contract (no); a qualifying PLAN already covers this work (no); the exploration
produced no work (no).

### `/charter` -- score -2, demoted

One weak signal: the prose fix and the koto adoption have an order between them.

Anti-signals present: the project already exists and the question is about its
next change; the work is one bounded feature however large; specific users and
needs are identified and uncontested. Demoted.

### File an Issue -- score -3, demoted

No signals present.

Anti-signals present: others need documentation to build from; architectural and
structural decisions were made during exploration; scope was debated across
rounds. Demoted.

### Ranking

- `/scope`: 9
- `/charter`: -2 (demoted)
- File an issue: -3 (demoted)
- `/execute`: not a candidate

## Tiebreakers Applied

- **A chain vs Rejection Record** (margin 2, applied for the record rather than
  by necessity): the overall conclusion is *proceed*, so the pairing resolves to
  a chain. The exploration rejected two remedies, not the work.
- No stage-2 tiebreaker was needed; the margin is 11 points after demotion.

## Author Override

The author redirected the line of work during round 2, before this evaluation
ran: the subject is adopting `koto` for `/scope` in a way that resolves the
incident, and the author elected to dispatch a fresh `/shirabe:explore` under
that framing rather than course-correct this run.

That election is compatible with the ranking above rather than in tension with
it. The framework names where this exploration's *work* enters, and the answer
is `/scope`. The author's choice is that the scoping conversation should happen
under the corrected framing, which this run only reached at its end and only
after falsifying two premises the reframe was stated with. Re-exploring is not
skipping ahead: it is running the same chain from a question worth scoping.

The successor brief is `.niwa/dispatch-briefs/scope-koto-adoption.md`. It carries
this run's findings, both falsified premises, the premise/verdict disclosure
rule, the established costs, and the framing content that survives because koto
governs when a directive arrives and never what it says.

## Alternatives Considered

- **Rejection Record**: ranked second and clean of anti-signals. It genuinely
  fits the two falsified remedies, and the re-proposal risk is real -- both are
  the obvious next suggestions and both are wrong. Ranked lower because the
  exploration's conclusion is proceed, and because a rejection artifact would
  strand the affirmative half of the findings. Mitigated instead by recording
  both falsifications prominently in the successor brief.
- **Decision Record**: fits the shape of several individual calls (drop
  sourcing; keep the write-target enumeration; rewrite rather than delete the
  consolidation section) but demoted, because those decisions came with work
  attached rather than standing alone.
- **Spike Report**: the koto lead is feasibility-shaped and produced a real cost
  assessment. Demoted because the exploration as a whole asked what to build,
  and because it was broad rather than focused on one technical risk.
- **File an issue**: the successor brief plays part of this role already, but the
  work needs documentation to build from and the exploration made structural
  decisions, so filing and walking away would lose them.

## Deferred Type

Not applicable. Prototype did not score.
