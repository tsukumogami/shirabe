# Crystallize Decision: skill-preflight-checks

## Chosen Type

Tactical chain via `/scope` (BRIEF -> PRD -> DESIGN -> PLAN), terminal artifact
PLAN, followed by `/execute` to a merge-ready PR. Both runs in `--auto` mode,
with `/decision` invoked at contested choices rather than blocking on the
author.

Author instruction, verbatim: "run the full shirabe:scope and then the
shirabe:execute workflows, in --auto mode. Your goal is to get to a PLAN, and
then execute it to completion, till you have a PR that is ready to review and
merge. Use the shirabe:decision framework from here onwards when you have to
make a decision instead of blocking on me."

## Rationale

Scoring produced two types with clean sheets and a one-point gap -- Design Doc
5 signals / 0 anti-signals, PRD 4 / 0 -- which is precisely the condition
`/scope` exists to resolve. Rather than force the tiebreaker and discard the
losing half, the chain carries both: the PRD fixes what the check must catch
(the presence-versus-skew question the demand lead reopened), and the DESIGN
decides how (mechanism, implementation home, declaration format, install
resolution).

The tiebreaker on its own favored Design Doc: the core requirements were given
as input during Phase 1 scoping (composable per-skill checks, three check
categories, print-and-let-the-agent-decide, shirabe's own skills only) rather
than identified by the exploration. What the exploration *did* identify is that
the stated justification does not hold -- prerequisite prose is 0.43% of the
SKILL.md corpus and zero in always-loaded descriptions -- while a different and
better-evidenced problem sits underneath it: four of five tools invoked
unguarded, and five durable incidents that are all version or subcommand skew.
That reframing is requirements work, and the chain gives it a place to land
instead of smuggling it into a design's problem statement.

## Signal Evidence

### Design Doc -- signals present (5)

- **Technical decisions need to be made between approaches.** Shell shim versus
  binary subcommand versus split; presence check versus per-subcommand `--help`
  capability probe; `metadata:` frontmatter versus a per-skill manifest versus a
  table compiled into the binary; tsuku delegation versus a per-OS install
  matrix.
- **Architecture and integration questions remain.** The check must reconcile
  with two shipped surfaces that disagree: `references/fixes/cli-version-preflight.md`
  rejects semver gating in favor of `--help` probing, while
  `.tsuku-recipes/shirabe.toml` verifies with `shirabe --version`.
- **Exploration surfaced multiple viable implementation paths.** All three
  implementation homes are live; only the pure-binary option is ruled out, and
  for a concrete reason (it cannot report its own absence).
- **Architectural decisions were made during exploration that should be on
  record.** The `` !`cmd` `` mechanism and its two hard constraints (non-zero
  exit aborts the whole invocation; silence on success is load-bearing for
  context dedup) are findings a future contributor cannot re-derive cheaply.
- **The core question is "how should we build this?"** The mechanism question
  that opened the exploration is closed.

### PRD -- signals present (4)

- **Requirements are unclear or contested.** Presence versus skew is unresolved
  and material: all five durable incidents are skew, and a presence check
  catches at most one and a half of them.
- **A single coherent feature emerged.** A load-time prerequisite check for
  shirabe's own skills.
- **The core question is "what should we build and why?"** The stated "why"
  (context tax) was disconfirmed by measurement; a replacement justification
  (unguarded invocation, silent misrouting) needs writing down.
- **Acceptance criteria are missing.** Nothing anywhere states a measurable
  target. The closest is `skills/work-on/evals/evals.json` id 10
  (`koto-not-installed`), which asserts behavior over prose, not over a check.

### Anti-signals checked

- Design Doc, "what to build is still unclear": borderline, judged **not
  present** in a way that blocks -- the shape (a load-time check) is settled;
  what moved is which failures it targets. The chain routes that through the PRD
  anyway, so the risk is absorbed rather than accepted.
- Design Doc, "no meaningful technical risk or trade-offs": not present. Two
  prior decisions must be argued past, not around --
  `DESIGN-shirabe-pattern-v1-ergonomics` Decision 6 rejected per-SKILL inline
  snippets and once-per-chain probes for R30 in favor of lazy prose, and PR #278
  chose a CI matrix over the runtime version guard #270 offered, reasoning that
  "a pattern list only catches what its author remembered."
- PRD, "requirements were provided as input": partially present, which is why
  PRD alone ranked second.
- PRD, "multiple independent features that don't share scope": not present. The
  three concrete defects (the `/inflight` unguarded injection,
  `run-cascade.sh`'s 19 unguarded `jq` calls, the orphaned
  `cli-version-preflight.md`) all share the host-dependency scope.

## Alternatives Considered

- **Design Doc alone** -- ranked second on its own. Would have to carry the
  requirements reframing inside its problem statement, where the
  presence-versus-skew question gets less scrutiny than it deserves.
- **PRD alone** -- ranked third. Correct about the reframing, but leaves four
  contested technical decisions unresolved and would need a DESIGN immediately
  after.
- **Decision Record** -- demoted by the anti-signal "multiple interrelated
  decisions need a design doc." Five surfaced, not one.
- **No artifact, fix the three defects directly** -- demoted by the anti-signal
  "any architectural, dependency, or structural decisions were made during
  exploration." The `` !`cmd` `` constraints and the split-implementation
  reasoning would be lost when `wip/` is cleaned.
- **Plan** -- demoted by "technical approach is still debated" and "open
  architectural decisions need to be made first."
- **Spike Report** -- signals matched at the start of the exploration
  (feasibility of a load-time script blocked the decision) but the question is
  now answered, and the anti-signal "the question is what should we build"
  applies.
- **Rejection Record** -- does not fit. The demand lead landed explicitly on
  *demand partially validated*, and states that neither Decision 6 nor PR #278
  "constitutes positive evidence that host prerequisite checking was evaluated
  and rejected."
- **VISION / Roadmap / Competitive Analysis** -- demoted on repo scope
  (tactical), single-feature scope, and public visibility respectively.

## Handoff Notes for the Chain

Carry these into the BRIEF and PRD as given, not as things to rediscover:

1. The mechanism is settled and already in production in
   `skills/inflight/SKILL.md`. Do not re-litigate it; do record its two
   constraints.
2. The context-tax justification is disconfirmed. Do not restate it. The
   defensible framing is coverage and silent-misrouting prevention.
3. Every existing `!` injection line needs an inline `|| echo "..."` fallback,
   and `/inflight`'s bare injection is a live defect.
4. Composability is per-mode, not per-skill, for six skills; nine skills need
   nothing but `git`.
5. Install advice delegates to tsuku, and "installed but not on PATH" precedes
   every install route.
6. Decision 6 and PR #278 are the two prior positions any proposal must argue
   past.
