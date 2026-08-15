# /design Phase 0 summary: work-on-retry-clearing

Upstream: `docs/prds/PRD-work-on-retry-clearing.md` (auto-transitioned
`Accepted -> In Progress` under `/scope`'s `parent_orchestration:` sentinel with
`invoking_child: design`).

## The technical problem, in implementation terms

Three states in `skills/work-on/koto-templates/work-on.md` -- `scrutiny`,
`review`, `qa_validation` -- each declare a `context-exists` gate on a results
key and reference it from the `when` clause of their `passed` transition. Each
also has a `blocking_retry` edge to `implementation`, and `implementation`
routes forward to `scrutiny` for `issue_type: code`.

The technical problem is that koto's engine has no way to invalidate a context
key. Gates read the store; nothing in the template surface writes to it
(`context_assignments:` looks like it would and does not -- see the verified
facts). So the state machine cannot, by itself, distinguish a results artifact
written this round from one written before the retry. Any mechanism has to put
the invalidation in something an agent runs, and then use the gate to make the
invalidated state un-advanceable.

System boundaries involved: shirabe's `skills/work-on/` prose and koto template,
koto's `context` CLI surface and gate evaluator, shirabe's `scripts/` test
surface plus the CI workflows that run it, and `/work-on`'s eval suite.

## Decision drivers, derived from the PRD

- **The guarantee must not rest on prose.** PRD R3. A gate koto evaluates holds
  under an agent that skipped a step; a sentence does not. This is the driver
  that disqualifies any prose-only repair, and it is the lesson the same defect
  class already taught once in `/execute`.
- **The failure has to survive `2>/dev/null`.** PRD R5. koto's migration noise
  makes stderr the stream operators discard, so a diagnostic that lives there is
  a diagnostic that disappears when it matters.
- **All three phases, one contract.** PRD R2 and R6. The invalidation covers
  every panel artifact the retry re-enters, not the raising phase's alone.
- **First-pass behaviour is frozen.** PRD R8. A run reaching a phase for the
  first time must advance exactly as it does today.
- **The failure exits stay reachable.** PRD R4. A run with a broken context
  store must still reach a terminal state.
- **koto's interface is a boundary, not a given.** PRD R1 deliberately allows a
  mechanism that adds a subcommand to koto -- and the workspace's
  coarsest-legal PR-grouping policy makes that a coordinated two-repo effort.
  The cost is real and belongs in the decision, not in a requirement's wording.
- **Blast radius.** The three review states, the three phase files, the
  panel-orchestration summary, a test, and the evals. A mechanism needing new
  template variables, new states, or a general-purpose koto feature is out of
  proportion to the defect.

## Decision decomposition

Two questions after merging, both recorded here before any is executed.

### Decision 1 (critical, Tier 4) -- how a blocking retry forces a fresh verdict

The verb that invalidates and the gate that rejects the invalidated value are
**one question, not two**. `remove` leaves the key absent, which `context-exists`
already reports correctly; an overwrite leaves the key present, which
`context-exists` cannot distinguish from a fresh write, so an overwrite-based
mechanism must also change the gate type. The answer to "which verb" therefore
determines what is viable for "which gate", and Phase 1's merge rule says to
merge rather than pretend they are independent.

Classified critical: experts would genuinely disagree, one option changes another
repository and is expensive to reverse once released, and it is the primary
question this design exists to answer.

### Decision 2 (Tier 2, micro-protocol) -- where the test lives and what it drives

`skills/work-on/` has no `scripts/` directory and there is no
`check-work-on-scripts.yml`; the three existing shell suites (`plan`, `execute`,
`templates`) are registered in `scripts/check-bash-floor.sh` and each has its own
workflow. A clear winner emerges from the evidence (mirror the `execute`
pattern), the choice is cheap to revise, and it is not the question this phase
exists to answer -- Tier 2 under the three-signal checklist in
`references/decision-protocol.md`, which stays in the micro-protocol rather than
escalating.

### Merged away, and why

**"At which edge does the invalidation run?"** was drafted as its own question
and merged into Decision 1. Exit-edge and re-entry-edge placement are not
independent of the mechanism: they change what the gate has to be true of at the
moment `passed` is submitted, which is the same surface Decision 1 settles. It
is carried into Decision 1 as a sub-question rather than evaluated separately.

Two questions is inside the 1-5 band of the scaling heuristic, so the run
proceeds normally.
