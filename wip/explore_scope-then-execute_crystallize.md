# Crystallize Decision: scope-then-execute

## Chosen Type
/scope

## Candidacy
- /execute: not a candidate. No PLAN covering this topic exists under `docs/plans/`.
- Competitive analysis: not a candidate (public repo).

## Rationale
The exploration converged on one feature: an intent-aware run from `/scope` to
merged code. The caller declares at launch whether the run continues into
execution; multi-PR splits resolve to `coordinated` (continue) or `multi-pr`
(stop); single-pr is preferred either way. It made decisions that need a durable
home (merge when permitted, intent as the coordinated/multi-pr axis, different
post-scope behavior per mode) and left architectural questions open (where the
continuation lives, how coordinated drops its multi-repo restriction, how intent
reaches `/plan`). The author reviewed the problem shape and solution space and
confirmed `/scope`.

## Stage 1 Evidence
### Signals Present
- Converged on something someone will build: the continuation and its mechanical fixes.
- Architecture and sequencing questions remain open: continuation location, intent plumbing.
- Decisions need a durable home: merge policy, intent axis, per-mode behavior.
- A scope boundary emerged: single-pr and coordinated continue; multi-pr stops.
- Core question is "what do we build, and how?"

### Anti-Signals Checked
- Nothing left to build: not present.
- Whole output is one choice: not present. The intent axis is one input among several.
- Feasibility verdict only: not present.
- Conclusion is don't proceed: not present.

### Ranking
- A chain: 5
- Decision Record: 1 (demoted: multiple interrelated decisions with work attached)
- Spike Report: 0 (demoted: question is "what should we build")
- Rejection Record: 0

## Stage 2 Evidence
### Signals Present
- A single coherent feature emerged.
- What to build is clear-ish, but how to build it is not.
- Technical decisions remain between approaches (flag vs driver vs recipe).
- Architecture questions remain (coordinated redefinition, intent forwarding to `/plan`).
- Decisions were made that should be on record.
- Multiple viable implementation paths surfaced.

### Anti-Signals Checked
- Multiple independent features whose order affects delivery: not present.
  The fixes serve one outcome.
- One person can act without a written contract: not present.
- A qualifying PLAN already covers this: not present.

### Ranking
- /scope: 6
- /charter: 1 (demoted: one bounded feature, project exists)
- File an issue: 0 (demoted: decisions were made, scope debated with the author)

## Tiebreakers Applied
- None needed; margins exceed one point.

## Alternatives Considered
- **/charter**: the work is a sequence of changes serving one outcome, not
  separately valuable features.
- **Decision record for the intent axis first**: offered to the author and
  declined; `/scope`'s DESIGN will record it.
- **Explore further**: the `done_blocked` cascade question and `--auto`
  forwarding are implementation-level and fit inside the chain.
