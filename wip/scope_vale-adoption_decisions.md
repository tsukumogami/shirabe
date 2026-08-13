# Chain Decisions: vale-adoption

Decisions taken in `--auto` mode, where the run follows the recommended
default rather than blocking on the author. Each records what was chosen and
why, so a reader can find the judgment rather than inferring it.

## Phase 5 (/brief finalization)

**Open Questions removed at acceptance, carried into the PRD.** The BRIEF
format requires the Open Questions section be empty or removed before Draft
to Accepted, and names the downstream PRD's Decisions and Trade-offs section
as the canonical closure surface. The four questions below were removed from
the BRIEF and are the PRD's inheritance. They are recorded here verbatim so
the transition does not lose them.

1. Must an adopter repo be able to read the single rule source without
   installing shirabe? The answer bounds where that source can live, and the
   PRD can settle the requirement even though the location is a DESIGN
   choice.
2. Does an adopter's vocabulary declaration extend shirabe's rules or replace
   them? Extending keeps adopters on the shared rulebook and lets shirabe
   evolve it; replacing gives adopters full control and forfeits that. The
   PRD should state which, because it decides whether the feature has one
   rulebook or many.
3. Is FC10 replaced or extended? The answer follows from the mechanism
   choice, but the PRD should state which outcome counts as success so the
   DESIGN is not free to leave two overlapping checks in place.
4. What severity does a frequency finding carry on first release, given that
   the corpus does not currently satisfy any threshold worth setting?

**Author approval recorded.** The Phase 5 human-approval gate was satisfied
by explicit author instruction to approve and continue. Jury PASS alone does
not transition status; this was a separate authorization.

**A second majority claim was corrected at acceptance.** The reframe review
caught the frontmatter asserting FC10 "cannot see the files where most
agent-authored prose lives". The same claim appeared in the Problem Statement
body and the review did not flag it there. Measured before transitioning:
FC10 reads 440,003 words of artifact-prefixed prose in `docs/` and skips
about 225,000 (23,437 non-prefixed under `docs/`, 197,538 under `skills/`,
and the root instruction files), so it sees roughly two thirds. The body now
states the leverage argument rather than a volume argument, which is what the
section was actually arguing.

## Phase 2 (chain orchestration, --auto)

**Chain continues without per-child confirmation.** `--auto` suppresses the
blocking prompts at each child boundary. Child invocations still run their own
juries and the validator pass-through still halts the chain on an
error-severity finding; autonomy removes the author's confirmation step, not
the checks.
