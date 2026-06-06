---
name: scope
description: >-
  Parent skill for the tactical chain. Walks an author through
  BRIEF → PRD → DESIGN → PLAN as a single conversation, holding state
  across child boundaries and producing a PLAN as the terminal
  artifact. Use when an author needs feature-scope decided in one
  sitting rather than reached for one child skill at a time. Triggers
  on "specify a feature called X", "scope feature Y", "walk me through
  specifying Z", or direct `/scope <topic>` invocations. Do NOT use when the author already
  knows which artifact altitude they want (reach for `/brief`,
  `/prd`, `/design`, or `/plan` directly).
argument-hint: '<topic-slug or freeform topic>'
---

# Scope

`/scope` is the second parent skill in the shirabe parent-skill
pattern, sitting on the tactical chain (BRIEF → PRD → DESIGN → PLAN)
the way `/charter` sits on the strategic chain (VISION → STRATEGY →
ROADMAP). It walks an author through the four tactical-chain
children as a single conversation, holds state across child
boundaries, enforces the pattern-level invariants (state schema,
resume ladder, three exit paths, child inspection, worktree
discipline), and lands at one of three terminal exits: a `full-run`
that produces a PLAN at `docs/plans/PLAN-<topic>.md`, a
`re-evaluation` exit that writes a Decision Record at a settled-
upstream boundary (PRD or DESIGN), or an `abandonment-forced` exit
that force-materializes the most-recently-running child's
intermediate as a Draft artifact.

The pattern-level contract surface is documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` and its
four companion references. `/scope` is the second concrete consumer
after `/charter`; the seven SKILL.md structural elements below align
section-by-section with the pattern's required structural elements,
and the prose contracts after them bind the `/scope`-specific
asymmetries the tactical chain introduces (two settled-upstream
boundaries, a Mandatory-with-auto-skip gate on `/prd`, a refuse-
and-redirect Slot 5 shape for PLAN's downstream-owned lifecycle
states, and a terminal child with two output modes).

## Team Shape

`/scope` runs as a single-agent skill in the v1 core layer — no
team is spawned at the `/scope`-itself layer. The parent-of-the-
parent (the agent invoking the skill) calls `/scope` directly;
there are no peer roles to materialize at team-creation time.

The team-shape declarator is prose per the pattern's v1 form (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` — Team-
Shape Declarator section). When the amplifier-layer substrate
ships, team-emitting parents declare their roster as structured
metadata; single-agent parents like `/scope` keep the prose form.

R19 (the Team-Lead Operating Discipline, semantic invariant I-7 in
the pattern's invariants list) binds at the child-skill-dispatch
layer rather than at the parent-itself layer: each `/brief`,
`/prd`, `/design`, and `/plan` invocation is a dispatch in the
discipline's sense, and `/scope` runs the implementation-pass task
class (120-second window, 10-cycle patience budget) for each child
invocation. At the `/scope`-itself layer the binding is vacuous in
v1 — there are no peers dispatched whose terminal exits the team-
lead drives.

See [`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) Dispatch Contract section for the mechanism that carries each child invocation.

## Input Modes

From `$ARGUMENTS`:

1. **Empty** — surface a cold-start prompt asking the author what
   feature scope they want to settle. The cold-start prompt names
   the three trigger phrases from CLAUDE.md ("specify a feature
   called X", "scope feature Y", "walk me through specifying Z") and
   asks the author
   to re-invoke `/scope <topic-slug>` with a slug that matches the
   topic-slug regex. Phase 0 then stops; there is no auto-retry
   loop.
2. **Non-empty `$ARGUMENTS`** — a freeform topic string that must
   already conform to the topic-slug regex (see Topic-Slug
   Constraint below for the regex source-of-truth and validation
   discipline). On match, the value becomes the topic slug verbatim;
   on mismatch, Phase 0 rejects with a clear error and stops.

Paths to durable artifacts (e.g., `/scope docs/prds/PRD-foo.md`)
fail the regex on slashes / dots / uppercase and are rejected at
Phase 0; they are not treated as upstream pointers. Upstream
artifact references are detected during Phase 1 discovery by
inspecting topic-related child docs in the repo, not by parsing
`$ARGUMENTS`.

## Execution-Mode Flags

`/scope` parses three execution-mode flags from `$ARGUMENTS`:

- `--auto` — non-interactive mode. Decisions follow the recommended
  default based on context; the run does not block on user input.
- `--interactive` (default) — the run blocks on user-input prompts
  at decision points.
- `--max-rounds=N` (default 5) — caps the number of re-evaluation
  re-entries allowed against the same topic. The `/scope` default
  is `--max-rounds=5`, overriding `/charter`'s default of 3 per
  R16.5 / AC16b. Setting `N` causes the (N+1)th re-evaluation to
  be rejected with a clear error naming the cap. Values outside
  the integer 1-or-greater range surface a clear error at Phase 0
  and stop the run.

The execution mode applies to all phases. `--auto` mode does NOT
suppress R9's hard-finalization check; an `--auto` run that cannot
record a valid exit still fails finalization rather than silently
absorbing the violation.

## Topic-Slug Constraint

The topic slug appears in the state-file path
(`wip/scope_<topic>_state.md`), the Decision Record paths
(`docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`),
and downstream child wip/ paths under `wip/{brief,prd,design,plan}_<topic>_*`.
The slug MUST match the regex `^[a-z0-9-]+$` — the pattern-level
constraint canonical in
[`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md)
(Topic-Slug Regex section), including the validation discipline
(AS PROVIDED, no normalization) and the resume-time re-validation
rule. Phase 0's rejection-example table and the slug-handling
procedure live at `skills/scope/references/phases/phase-0-setup.md`.

Slugs recovered from on-disk artifact paths during Slot 5 or Slot 6
ladder matches are re-validated against the same regex before
interpolation into any emitted shell command; the resume-time slug
rule lives in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` (Slug
Re-Validation on Resume section).

## Workflow Phases

```
Phase 0: SETUP  -> Phase 1: DISCOVER  -> Phase 2: CHAIN  -> Phase 3: FINALIZE  -> Phase 4: CLEANUP
(slug validation  (visibility detect +    (orchestrate     (record exit +        (wip cleanup;
 state-file +     child-doc discovery +    child skills     write exit_artifacts;  remove non-
 parent_orch      chain proposal)          one-by-one)      R9 hard-finalization)  durable scratch)
 self-heal)
```

| Phase | Purpose | Reference |
|-------|---------|-----------|
| 0. Setup | Slug validation; state-file creation; stale `parent_orchestration:` self-heal | `skills/scope/references/phases/phase-0-setup.md` |
| 1. Discover + Chain Proposal | Visibility detection; topic-related child-doc discovery; R6 shape-predicate evaluation; R7.5 chain-proposal output | `skills/scope/references/phases/phase-1-discovery.md` |
| 2. Child Invocation Loop | Per-child: worktree-staleness check (Rebase / Impact-analysis / Escalation per `worktree-discipline.md`); write `parent_orchestration:` sentinel; invoke child; structural file-existence check per R20; clear sentinel; capture child snapshot; validator pass-through | `skills/scope/references/phases/phase-2-chain-orchestration.md` |
| 3. Exit Finalization | Set `exit:` field; write `exit_artifacts:`; run R9 hard-finalization check | `skills/scope/references/phases/phase-3-exit-finalization.md` |
| 4. wip Cleanup | Remove the topic's wip/ scratch artifacts; preserve durable Decision Records and force-materialized partials in `docs/` | `skills/scope/references/phases/phase-4-cleanup.md` |

Phase 2 child invocation runs each of `/brief`, `/prd`, `/design`,
`/plan` as a dispatch under the Team-Lead Operating Discipline
documented in `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`
(invariant I-7). The discipline binds the sleep-check-nudge loop,
the filesystem-evidence-first priority ordering, and the PASS /
FAIL / ESCALATE terminal exits; the implementation-pass task
class (120s window, 10-cycle patience budget) applies to each
child invocation.

The per-child worktree-staleness check before each invocation is
the three-phase flow (Rebase phase → Impact-analysis phase →
Escalation phase) defined in
`${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`.
None and Informational impact classifications proceed silently and
record the rebase in `worktree_rebases:`; Intent-changing
classifications halt and route to the team-lead for an intent
judgment, which may resolve in-place or escalate to the author for
a re-author / proceed-against-original-intent / bail decision.

## Resume Logic

`/scope` maintains state at `wip/scope_<topic>_state.md` (one file
per topic, keyed by the topic slug). The full state-file schema,
conditional-field gating discipline, and R9 hard-finalization check
spec are documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`;
the `/scope`-specific field enumeration lives in
`skills/scope/references/state-schema.md`. On re-entry, the resume
ladder consults the state file, the per-child snapshots recorded
in state, and the current branch context to decide where to
re-enter.

The ladder shape follows the universal meta-ladder template at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`:
universal rows 1-4 (malformed → exit set → fresh resume → stale-
session) and rows 8-9 (on-topic branch → main fallback) are the
pattern-level meta-ladder; rows 5-7 are parent-specific body slots
`/scope` fills against its child set (`/brief`, `/prd`, `/design`,
`/plan`).

`/scope`'s stale-session threshold is **7 days**: state with
`last_updated` ≥ 7 days old surfaces the Resume / Force-materialize
/ Discard prompt; fresher state silently resumes. The threshold
inherits the default `/charter` chose for R16; the tactical chain
spans the same conversational profile as the strategic chain.

The full Slot 5 / Slot 6 / Slot 7 row body and the drift-detection
contract (Re-run / Accept / Proceed-without — the three literal
substrings the eval surface grades against) live in
`skills/scope/references/phases/phase-resume.md`. The high-order
shape: Slot 5 has 9 rows evaluated most-downstream-first (with
PLAN-Active and PLAN-Done as refuse-and-redirect rows owned by
downstream skills, and DESIGN-Accepted / PRD-Accepted as the two
settled-upstream boundary rows offering the **Re-evaluate /
Revise / Bail** triad); Slot 6 has 4 partial-child-run rows;
Slot 7 is vacuous in v1.

## Phase Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup** — slug validation, state-file creation, stale
   `parent_orchestration:` self-heal.
   - Instructions: `skills/scope/references/phases/phase-0-setup.md`

1. **Discover + Chain Proposal** — visibility detection, topic-
   related child-doc discovery, R6 shape-predicate evaluation,
   chain-proposal output (Proceed / Adjust / Bail triad).
   - Instructions: `skills/scope/references/phases/phase-1-discovery.md`

2. **Child Invocation Loop** — invoke the planned chain
   (`/brief` → `/prd` → `/design` → `/plan`, skipping per the chain
   plan), running the worktree-staleness check before each
   invocation, writing the `parent_orchestration:` sentinel
   immediately before invoking, clearing the sentinel immediately
   after, capturing the child snapshot, and running the validator
   pass-through against each intermediate.
   - Instructions: `skills/scope/references/phases/phase-2-chain-orchestration.md`

3. **Exit Finalization** — set the `exit:` field to one of
   `full-run`, `re-evaluation`, or `abandonment-forced`; write the
   `exit_artifacts:` list; run the R9 hard-finalization check
   (including R9 Part 2 multi-discriminator and R9 Part 3
   chain-membership-gated extensions from
   `parent-skill-state-schema.md`).
   - Instructions: `skills/scope/references/phases/phase-3-exit-finalization.md`

4. **wip Cleanup** — remove the topic's wip/ scratch artifacts
   (`wip/scope_<topic>_*` plus, on full-run or re-evaluation,
   `wip/{brief,prd,design,plan}_<topic>_*` and
   `wip/research/{prd,design}_<topic>_*`); preserve durable
   artifacts under `docs/`.
   - Instructions: `skills/scope/references/phases/phase-4-cleanup.md`

## Reference Files

| File | When to load |
|------|-------------|
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` | All phases — contract surface, invariants, exit paths, Gate Vocabulary (Mandatory-with-auto-skip), L13 `parent_orchestration:` convention, substitution surfaces |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` | Phase 0 (slug regex), Phase 2 (state writes including `boundary:` and `plan_execution_mode:`), Phase 3 (R9 check, multi-discriminator Part 2, chain-membership-gated Part 3) |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` | Resume Logic — meta-ladder rows 1-4 and 8-9, refuse-and-redirect Slot 5 paragraph |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` | Phase 2 — child-doc inspection (R14 widened rule, dual-check drift detection) |
| `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md` | Phase 2 — per-child worktree-staleness check (Rebase / Impact-analysis / Escalation phases with `worktree_rebases:` and `worktree_divergences:` recording) |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` | All phases — six pattern-level security contract surfaces (slug re-validation, closed write-target set, enum re-validation, self-heal, visibility, no-untrusted-input-interpolation) |
| `skills/scope/references/phases/phase-0-setup.md` | Phase 0 |
| `skills/scope/references/phases/phase-1-discovery.md` | Phase 1 |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | Phase 2 — includes Phase-N Reject in-chain mechanism |
| `skills/scope/references/phases/phase-3-exit-finalization.md` | Phase 3 |
| `skills/scope/references/phases/phase-4-cleanup.md` | Phase 4 |
| `skills/scope/references/phases/phase-resume.md` | Resume Logic — Slot 5 (9 rows), Slot 6 (4 rows), Slot 7 (vacuous), Drift Detection (Re-run / Accept / Proceed-without) |
| `skills/scope/references/state-schema.md` | All phases — `/scope`-specific state-file field enumeration (exit discriminators, worktree audit fields, `drift_acknowledged:`, `parent_orchestration:` sentinel) |

## Chain-Proposal Output

At the end of Phase 1 discovery, `/scope` emits a chain-proposal
output naming the children it intends to invoke, the gate for each
(per the Gate Vocabulary section of `parent-skill-pattern.md`), and
the per-predicate reasons feeding R6's shape-dependent verdict for
`/design`'s decision-roster shape (architectural-alternatives
count, new-component references, Complex classification). The
output ends with a confirmation prompt containing the literal
substrings **Proceed**, **Adjust**, and **Bail** (case-insensitive)
in the offered options.

The three branch behaviors:

- **Proceed** — confirm the proposed chain; advance to Phase 2 and
  begin invoking children in order.
- **Adjust** — return to Phase 1 discovery with the author's
  adjustment input; re-emit the proposal after re-running R6
  predicates against the adjusted scope.
- **Bail** — route to R8 bail-handling. If any wip state exists
  for the topic (the state file, any child intermediate, or any
  research scratch), the bail records `exit: abandonment-forced`
  and force-materializes the most-recently-running child's
  intermediate; if no wip state exists, the bail is a clean
  cancel with no terminal artifact.

The per-predicate reasons feeding the shape-dependent verdict are
surfaced verbatim so the author sees the predicate verdicts
behind the chain shape rather than an opaque "Complex" or
"Simple" label.

## Three Exit Paths

`/scope` terminates through one of the three pattern-level exit
paths (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` Three
Exit Paths section). Each binding below names the durable artifact
the exit produces:

- **`full-run`** — the chain completes through `/plan`. Terminal
  artifact is `docs/plans/PLAN-<topic>.md` (status Draft when
  `plan_execution_mode: single-pr`; status Active when
  `plan_execution_mode: multi-pr`, with an accompanying GitHub
  milestone created by `/plan`). The `exit_artifacts:` list
  records the PLAN doc's path.
- **`re-evaluation`** — the chain ends at a settled-upstream
  boundary with a Decision Record written at
  `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`.
  The four combinations are gated by the `boundary:` discriminator
  (`prd` or `design`) and the `decision_record_sub_shape:`
  discriminator (`re-evaluation` or `rejection`). R9 Part 2's
  multi-discriminator rule requires both discriminators to be set
  when `exit: re-evaluation` fires. Decision Record body templates
  live at `skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md`.
- **`abandonment-forced`** — the chain cannot complete and
  `/scope` force-materializes the most-recently-running child's
  intermediate as a Draft artifact. The artifact's Status section
  ends with the uniform single-line HTML-comment marker (see the
  Abandonment-Forced HTML-Comment Marker section below).

**R8 bail-handling tie-break.** When the chain bails and the
abandonment-forced exit must name a `triggering_child`, the
resolution is the most-recently-running child per the chain's
progression. The tie-break inspects `wip/{brief,prd,design,plan}_<topic>_*`
intermediates and resolves to whichever child holds the most-
recent intermediate; if no intermediate exists, the
`triggering_child` is whichever child Phase 2 was about to
invoke when the bail fired.

## State File Schema

The state file at `wip/scope_<topic>_state.md` is YAML-in-`.md`
under the `wip-yaml-md` substrate, extending the pattern's 5-field
minimum (`topic`, `last_updated`, `phase_pointer`, `exit`,
`exit_artifacts` — see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`)
with `/scope`-specific fields. The full field enumeration —
including the exit-conditioned discriminators (`boundary:`,
`decision_record_sub_shape:`), the Drift-Detection audit field
(`drift_acknowledged:`), the worktree-discipline audit fields
(`worktree_rebases:`, `worktree_divergences:`), and the ephemeral
`parent_orchestration:` sentinel — lives in
`skills/scope/references/state-schema.md`. Every conditional field
is absent from the state file when its triggering condition does
not hold (invariant I-5).

## Visibility Detection

`/scope` reads repo visibility from CLAUDE.md's `## Repo Visibility:`
header, inherited unchanged from the pattern doc's visibility
mechanism (see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`
Conditional Feeder Invocation Shape section, condition 3). When
the header is present and names `Public` or `Private`, that value
is recorded in the state file and routes the visibility-gated
behaviors.

When the `## Repo Visibility:` header is ABSENT from CLAUDE.md,
`/scope` defaults to **Private** and emits a warning containing
the literal phrasing **Default to Private if unknown** naming the
missing `## Repo Visibility:` header. The warning is informational;
the run proceeds against the Private default. Authors who want a
Public-visibility run against a repo without the header SHALL add
the header to CLAUDE.md and re-invoke `/scope`.

## Manual-Fallback Non-Interference

A child invoked directly OUTSIDE `/scope` produces no `/scope`
interference: `/scope` does NOT surface a warning, does NOT block,
and does NOT modify state files when a child runs standalone. The
contract is symmetric — `/scope`'s state is internal to `/scope`'s
chain, and the child's standalone resume ladder does not consult
`/scope`'s state file unless the `parent_orchestration:` sentinel
is present (the L13 convention).

The consequence for Phase-N Reject:

- **In-chain Reject** — `/prd` Phase 4 Reject or `/design` Phase 6
  Reject fired while `/scope`'s `parent_orchestration:` sentinel
  was present. `/scope` writes a rejection-sub-shape Decision
  Record at `docs/decisions/DECISION-{prd|design}-<topic>-rejection-<YYYY-MM-DD>.md`
  immediately, observing the discard commit via `git log`. The
  state file records `exit: re-evaluation`, `boundary: {prd|design}`,
  `decision_record_sub_shape: rejection`, `discard_commit_sha`,
  and `rejection_rationale`.
- **Out-of-chain Reject** — `/prd` or `/design` Reject fired
  outside any `/scope` invocation. The discard commit is the
  durable trace; no retroactive Decision Record is written on a
  later `/scope` resume. A later `/scope` invocation against the
  same topic detects the discard commit but treats it as
  external context — manual-fallback parity preserves the
  contract that `/scope` does not modify state for runs it did
  not orchestrate.

The discard-commit observability mechanism is the same in both
cases — `git log` reads commit metadata regardless of who
invoked the child — so the manual-fallback parity is
mechanically symmetric.

## Validator Pass-Through

Phase 2 runs `shirabe validate --visibility=<repo-visibility>`
against each child's intermediate after the child returns and
before invoking the next child. The validator is the same binary
shirabe ships at `cmd/shirabe/`; the visibility flag inherits the
visibility detection result (see Visibility Detection above).

A failed validation halts the chain immediately and routes via
R8's bail-handling. `/scope` does NOT auto-fix validator failures
— the author is the validator-failure resolver, and the chain
remains halted until the author addresses the failure and
re-invokes `/scope`. The per-phase mechanism (which validator
flag, which intermediate path) lives in the Phase 2 reference at
`skills/scope/references/phases/phase-2-chain-orchestration.md`.

## Phase-N Reject In-Chain Integration

The chain-level mechanism for observing `/prd`'s Phase 4 Reject and
`/design`'s Phase 6 Reject — the `pre_invocation_sha` recording, the
`git log <pre_invocation_sha>..HEAD` read for the discard commit,
the in-chain Decision Record write vs out-of-chain context-only
read — lives in
`skills/scope/references/phases/phase-2-chain-orchestration.md`
(Phase-N Reject Handling section). The asymmetry is solely whether
a Decision Record gets written: in-chain yes, out-of-chain no; the
discard commit itself is the durable signal in both cases.

## Abandonment-Forced HTML-Comment Marker

When `exit: abandonment-forced` fires, `/scope` force-materializes
the most-recently-running child's intermediate as a Draft artifact
at the child's canonical durable path under
`docs/{briefs,prds,designs/current,designs,plans}/<TYPE>-<topic>.md`
(`docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`,
`docs/designs/DESIGN-<topic>.md` or `docs/designs/current/DESIGN-<topic>.md`,
or `docs/plans/PLAN-<topic>.md`). The artifact's existing Status
section ends with the uniform single-line HTML-comment marker:

```
<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->
```

Four contract rules bind the marker:

- **(a) Placement.** The marker is placed at the END of the
  artifact's existing Status section. `/scope` does NOT add a
  new required section to host the marker; existing artifact
  structure is preserved.
- **(b) Whitespace and field order significance.** The marker's
  whitespace and field order are significant. `scope-status-block:`
  is the lead identifier; the four field-value pairs appear in
  the order shown; the closing `-->` follows immediately.
- **(c) Substitution sources.** The four `<...>` substitutions
  are populated from the state file: `<name>` from
  `triggering_child`, `<phase>` from `partial_phase_reached`,
  and `<ISO-8601 timestamp>` from `chain_started`.
- **(d) Enum constraint on `<name>`.** `<name>` MUST be one of
  `brief | prd | design | plan`, resolved by R8's tie-break
  rule.

The marker is the abandonment-forced exit's machine-readable
audit trail. Reviewers and future-`/scope`-resume logic grep
against the literal substring `scope-status-block: abandonment-forced`
to detect a force-materialized partial.

## Security Considerations

`/scope`'s security envelope binds the six pattern-level contract
surfaces enumerated in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` — slug
re-validation on resume, closed write-target set, state-file enum
re-validation, stale `parent_orchestration:` self-heal, visibility
boundary, and no untrusted-input interpolation. `/scope` v1 binds
to public-repo tactical chains exclusively; the closed write-target
set is the concrete enumeration in the pattern reference applied
to `/scope`'s chain shape (Decision Records under
`docs/decisions/`, the terminal PLAN under `docs/plans/`, force-
materialized partials under `docs/{briefs,prds,designs}/`, and
state-file plus child-wip cleanup under `wip/`). Future cross-
visibility extension MUST re-state placement discipline in its
own PR with explicit public-vs-private content-governance review.

## Binding Notes

`/scope` v1 binds the parent-skill pattern's two-substitution
surface at the v1 core-layer values:

- **`storage_substrate: wip-yaml-md`** — state file at
  `wip/scope_<topic>_state.md` as YAML-in-`.md`. The substrate
  does NOT satisfy invariant I-6 (cross-branch resume); resume
  on a different branch starts a fresh chain. Closing the I-6
  gap is the amplifier-layer substrate's mandate.
- **`team_primitive: single-team-per-leader-no-nested`** — no
  nested teams; inline decision walks within `/scope`-itself
  (Phase 1's R6 shape-predicate evaluation walks the predicates
  inline rather than spawning per-predicate validators); upfront
  upper-bound roster declared in the Team Shape section above
  (single-agent in v1).

The substitution surface is documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` (Named
Substitution Surfaces section). The values above are where
`/scope`'s v1 implementation sits on that surface; alternate
values are the amplifier-layer's mandate.

Same-topic concurrent invocations on the same working tree are
an explicit no-go pattern: the state file is topic-keyed
(`wip/scope_<topic>_state.md`), so two concurrent `/scope foo`
invocations would race on the same state file. Two-topic
concurrent invocations (`/scope foo` and `/scope bar`) are safe
because their state files do not contend.

No runtime dependencies are added by this skill; references only
existing pattern files in this repo. No external URL is cited for
download or execution. No secrets, tokens, or credentials are
named.
