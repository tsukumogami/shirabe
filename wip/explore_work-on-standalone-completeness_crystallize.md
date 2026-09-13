# Crystallize: work-on-standalone-completeness

Scored against the accumulated findings from both discover-converge rounds.

## Step 1: Candidacy

Two arms are off the board before scoring, and are not named in the
recommendation or the alternatives:

- **Competitive analysis** -- precondition fails. `## Visibility` in the scope
  file reads `Public`.
- **`/execute`** -- precondition fails. The only PLAN in the repo is
  `docs/plans/PLAN-work-on-friction-fixes.md`, whose frontmatter is
  `execution_mode: multi-pr`. A multi-pr PLAN does not qualify. It does not
  cover this work in any case; it is a friction-fixes umbrella whose #80 is the
  separate `check-staleness.sh` defect.

## Step 2-3: Stage 1 scoring

| Category | Signals | Anti-signals | Score | Demoted |
|---|---|---|---|---|
| A chain | 6 | 0 | **6** | no |
| Decision record | 4 | 1 | 3 | yes |
| Spike report | 2 | 2 | 0 | yes |
| Rejection record | 0 | 1 | -1 | yes |

**A chain** -- signals matched: the exploration converged on something someone
will build; architecture and sequencing questions remain open; decisions made
during the exploration need a durable home and have downstream work; several
parties need alignment on what to build; a scope boundary emerged rather than
just an answer (what is in: the cascade and the enforcement altitude; what is
out: `cannot_verify`, `check-staleness.sh`, #87, #360, #352); and the core
question became "what do we build, and how?". No anti-signals: the conclusion is
proceed, the output is not merely one choice, and the findings are about this
codebase rather than external products.

**Decision record** -- scored well and is the closest rival. Three named
directions were compared with trade-offs, and future contributors will certainly
need to know why one was chosen. It is demoted on one anti-signal: *multiple
interrelated decisions came with work attached*. The direction choice does not
stand alone -- building the cascade, building the multi-pr last-issue
discriminator, providing a no-chain skip path, and deciding the scope of #352
all ride on it.

Applying the stage-1 tiebreaker for a chain versus a decision record
confirms the same result: the exploration's entire output is **not** one choice
between named options. The choice is one input among several that a build still
needs, which the framework routes to a chain that records the choice as it goes.

**Spike report** -- demoted on two anti-signals: the question was not "can we do
this?" but "what should we build, and how?", and the exploration was broad
(eight leads across two rounds) rather than focused on one technical risk.

## Step 5: Stage 2 runs

A chain is top-ranked by a margin greater than one point.

## Step 6-7: Stage 2 scoring

| Entry point | Signals | Anti-signals | Score | Demoted |
|---|---|---|---|---|
| `/scope` | 10 | 0 | **10** | no |
| `/charter` | 1 | 3 | -2 | yes |
| File an issue | 0 | 4 | -4 | yes |

**`/scope`** -- one coherent feature emerged (a `/work-on` run that finishes its
own work); the requirements are contested, and demonstrably so, since two of the
six in the tracking issue do not survive the code; what to build is clearer than
how to build it; technical decisions between three named approaches remain open;
architecture questions remain; the exploration surfaced multiple viable
implementation paths; and architectural decisions made during the exploration
need to be on the record. No anti-signals: this is one bounded feature rather
than several needing ordering, nobody can act on it without a written contract,
and no qualifying PLAN covers it.

**File an issue** -- four anti-signals. Others need documentation to build from;
more than one party is involved; structural decisions were made during the
exploration; and the scope was debated across two rounds plus an adversarial
review.

**`/charter`** -- three anti-signals. The project exists and the question is
about one part of it; the work is one bounded feature however large; and the
audience and need are already identified and uncontested.

## Recommendation

**A chain, entering at `/scope`.** Command: `/scope work-on-standalone-completeness`

The exploration converged on a single feature -- making a standalone `/work-on`
run finish its own work -- and established that the tracking issue's stated
requirements are partly wrong, which is exactly the contested-requirements
signal the tactical chain exists to settle. Three viable implementation paths
were surfaced and none is settled. The chain writes the requirements before the
architecture and reduces per hop where a document turns out not to be needed.

## Alternatives

- **Decision record (`/decision`)** -- ranked second and genuinely close. It
  matches the direction choice well, but ranks lower because that choice arrives
  with substantial work attached rather than standing alone, and a decision
  record would leave the cascade, the discriminator and the no-chain skip path
  unspecified. Note that the workspace's own protocol routes a contested choice
  through `/shirabe:decision` regardless; that is a process requirement about how
  the direction gets settled, not a competing answer about what this exploration
  produced. The two are compatible: the chain can record the decision as it goes.
- **Spike report** -- ranked lower because the exploration did not answer "can
  we?" and stop. It answered "what is actually broken, and what are the options",
  and someone is committed to acting on it.

## Carried into the chain

- The routing-options framing at
  `wip/explore_work-on-standalone-completeness_routing-options.md`, including the
  three directions and the correction to the coordinator's stated reasoning.
- The three scoping questions round 2 deliberately did not chase: whether the
  discriminator is scoped to the issue-tracked multi-pr shape or waits on the
  unowned issueless-multi-pr driver work; whether multi-pr ROADMAP deletion has
  ever worked; what merges a coordinated run's per-repo child PRs.
- The constraint that any fix must live in `work-on.md` rather than `SKILL.md`
  to reach `/execute`'s children.
- The requirement that cascade states in `/work-on` have a clean no-chain skip
  path.
- Four defects to be handled outside this change: `cannot_verify`,
  `check-staleness.sh`, #87, and the split treatment of #360 and #352.
