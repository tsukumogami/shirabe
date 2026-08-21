# Crystallize Decision: koto-runs-commands

## Chosen Type

A chain, entering at `/scope` — run in `public/koto`, not in shirabe.

Decided in `--auto` mode per the lightweight decision protocol: evidence
gathered from the accumulated findings, recommendation followed, recorded here.
Status: confirmed for the stage-1 outcome and the entry point, assumed for the
repo choice (see Tiebreakers).

## Candidacy

- `/execute`: **not a candidate**. The only PLAN on disk is
  `docs/plans/PLAN-work-on-friction-fixes.md`, whose `execution_mode` is
  `multi-pr`. `/execute` refuses that mode, so the arm does not exist this run.
- Competitive analysis: **not a candidate**. `## Visibility` in the scope file
  is Public.

## Rationale

The exploration set out to answer whether a gap was koto's or shirabe's and
came back with fifteen sized work items across two repositories, a stated
principle for which commands an engine should run, three engine capabilities
with competing designs, and two defects nobody had connected to the question.
That is a body of work with open architecture, not an answer that closes.

It enters at `/scope` rather than as filed issues because the exploration made
architectural choices that need a durable home. `capture_stdout_as` was chosen
over three alternatives on response-contract grounds. Execution anchoring has a
named design — canonicalized `execution_root`, refusal on cwd mismatch,
join-and-canonicalize for `working_dir`, a `koto session bind` verb — with three
unresolved questions (default behavior, pre-existing sessions, equality versus
containment) that a DESIGN has to settle. Failure semantics were deliberately
scoped to plumbing after rejecting an `on_failure:` schema field. None of that
survives in a issue body, and `wip/` is deleted before merge.

It runs in koto because that is where the open design questions live. Every
capability item is koto's; shirabe's items are template edits that follow. The
symptom appeared in shirabe and the research was authored here, but the chain
belongs where the work does.

## Stage 1 Evidence

### Signals Present

- **Converged on something someone will build**: fifteen items, sequenced into
  waves, with sizes grounded in the files each would touch.
- **Requirements, architecture, or sequencing questions remain open**: three
  koto capabilities each carry unresolved design questions; the sequencing lead
  named which must land first and why.
- **Decisions made during exploration need a durable home and downstream work**:
  the conversion principle, the rejection of a blanket read-only rule, the
  rejection of an `on_failure:` field, the choice of `capture_stdout_as` over
  populating `action_output` everywhere.
- **Multiple stakeholders need alignment on what to build**: the work spans two
  repositories with a dependency between them, and one item requires reversing a
  design doc currently marked Current.
- **A scope boundary emerged, not just an answer**: koto runs a step when it is
  isolated, gate-verifiable independent of the action's own exit code, and either
  read-only or a repo-local mutation safe to reach twice.
- **The core question is "what do we build, and how?"**: the original
  missing-versus-unused framing was settled in round 1; rounds 2 and 3 were
  entirely about what to build.

### Anti-Signals Checked

- Nothing was left to build: **not present**.
- The whole output is one choice between named options: **not present**.
- The output is a feasibility verdict nobody has committed to acting on: **not
  present** — the verdict commits to specific work.
- Findings center on external products: **not present**.
- The conclusion is that the work should not happen: **not present**.

### Ranking

- A chain: **6**, no anti-signals.
- Spike Report: 4 signals − 2 anti-signals = 2 *(demoted)*. Feasibility was
  genuinely part of the question and the risks were tested rather than
  speculated, but the exploration was broad rather than focused on one technical
  risk, and its centre of gravity moved to "should we, and which parts".
- Rejection Record: 1, no anti-signals. Multi-round and adversarial, but there is
  no rejection conclusion to record.
- Decision Record: 2 signals − 1 anti-signal = 1 *(demoted)*. Several decisions
  were made and they came with work attached, which is the anti-signal exactly.
- Competitive Analysis: not a candidate.

Margin over the next category is 4 points, so no stage-1 tiebreaker applies.

## Stage 2 Evidence

Stage 2 ran because "a chain" is the top-ranked stage-1 category.

### Signals Present

- **Requirements are unclear or contested**: the two round-2 leads reached
  opposite conclusions and round 3 had to adjudicate.
- **Multiple stakeholders need alignment on what to build**: two repos, plus a
  Current design doc that has to be argued against.
- **User stories or acceptance criteria are missing**: no item has acceptance
  criteria yet.
- **What to build is clear, but how to build it is not**: anchoring's three open
  questions; `capture_stdout_as`'s same-tick staleness trap.
- **Technical decisions need to be made between approaches**: four options were
  costed for output routing alone.
- **Architecture, integration, or system design questions remain**: the response
  contract, the event log, and the state-file header are all touched.
- **Exploration surfaced multiple viable implementation paths**: for output
  routing, for failure detection, for anchoring.
- **Architectural or technical decisions were made during exploration that should
  be on record**: listed in the Rationale.
- **The core question is "what should we build, and how?"**: yes.

### Anti-Signals Checked

- Multiple independent features whose order affects delivery: **present**. The
  work list has waves and a real dependency order. This is the one anti-signal
  against `/scope` and it is why the `/charter` boundary test was applied below.
- One person can act on this without a written contract: not present.
- A qualifying PLAN already covers this work: not present.
- The exploration produced no work: not present.

### Ranking

- `/scope`: 9 signals − 1 anti-signal = **8** *(demoted)*.
- `/charter`: 3 signals − 2 anti-signals = 1 *(demoted)*.
- File an issue: 1 signal − 4 anti-signals = −3 *(demoted)*.
- `/execute`: not a candidate.

## Tiebreakers Applied

The top two are 7 points apart, so no tiebreaker was strictly required. Two were
worked anyway, because each addresses the single anti-signal against the winner
and because the repo choice is not something the framework decides.

- **`/charter` vs `/scope`, the multi-feature boundary**: does the work span more
  than one feature whose order affects delivery? Branch taken: `/scope`. The
  fifteen items are one bounded capability — making koto safe and legible enough
  to run deterministic steps — decomposed into small pieces, most of them defect
  fixes. Sequencing exists because some fixes make others worth more, not because
  separately-deliverable features compete for order. Feature size is not the
  test; the number of separately-sequenced features is, and that number is one.
- **`/charter` vs `/scope`, the existence question**: does the project exist yet?
  Both projects exist and ship. Branch taken: `/scope`.
- **Repo choice (not a framework rule; recorded as a decision)**: koto. All three
  capability items and both defects are koto's, and the design questions that
  make this a chain rather than a set of issues are all koto's. shirabe's five
  items are template edits that depend on koto's, and they warrant their own,
  later run once the koto side lands. The exploration's `wip/` artifacts stay in
  shirabe, on this branch, where they were written.

## Alternatives Considered

- **File an issue**: fits the six defect items well — the pipe drain, the
  migration cleanup, the duplicate CI read, the repeated slug derivation, the
  inert `context_assignments` declarations, the stale koto-author dispatch table.
  Each is a one-file change needing no design. It ranks last overall because it
  is wrong for the other nine: four anti-signals fire, including the decisive one
  that architectural decisions were made during exploration. The right treatment
  is both — file the defects now so they do not wait on a chain, and run the
  chain for the rest. Phase 5 carries that split into the handoff.
- **`/charter`**: has a real claim. The work spans two repositories with an
  ordering between them, which is the sequencing signal `/charter` exists for.
  It ranks lower because the project already exists and the question is about a
  capability inside it, no thesis needs validating, and no strategic argument
  needs making for anyone. What it would add — a VISION and a defensibility bet —
  is not what is missing here.
- **Spike Report**: closest of the terminal outcomes, and the only one that
  scored above 1 before demotion. Feasibility really was open at the start, and
  the probes tested concrete risks rather than reasoning about them. It ranks
  lower because the answer committed someone to building rather than closing the
  question, and because the exploration ranged across two repos and twenty-one
  leads rather than time-boxing one technical risk.
- **Decision Record**: several decisions worth recording, but they are inputs to
  a build rather than the output. The anti-signal — interrelated decisions with
  work attached — is exactly this exploration's shape.
- **Rejection Record**: no rejection was reached. The exploration's conclusion is
  proceed, narrowly and in a specific order.

## Deferred Type

Not applicable. Prototype scored no signals: the mechanism was not
proof-of-concept material, it was already shipped, and the probes verified
behavior rather than demonstrating possibility.
