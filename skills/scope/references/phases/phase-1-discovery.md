# Phase 1 — Discovery and Chain Proposal

Phase 1 turns the topic slug into a planned chain. It runs the
discovery prompt to surface a framing-shift signal, walks the R6
shape-predicates inline, decides the chain's **entry altitude**,
evaluates the re-entry protection each child carries, captures
initial child-snapshots for any pre-existing durable artifacts,
and emits a chain-proposal output the author confirms (Proceed /
Adjust / Bail).

## What Phase 1 Decides, and What It Does Not

Phase 1 decides **where the chain starts**. It does not decide,
per hop, whether a child's artifact is worth producing. That
distinction is the point of this phase's shape: a judgment about
whether a document would have carried anything can only be made
against a document that exists, and at Phase 1 none of them do.

Every child from the entry altitude through `/plan` is invoked.
The only thing that stops a child from running is that its
durable artifact is already on disk at a settled status, which is
re-entry protection against overwriting settled work — not a
verdict on the artifact's worth. See "Re-Entry Protection" below.

Reducing the artifact set is Phase 2's job, after the artifacts
exist. See the Consolidation Judgment section of
`skills/scope/references/phases/phase-2-chain-orchestration.md`.

## Discovery Prompt Structure

The discovery prompt opens with the framing-shift question (R4):

> Has the framing of this topic shifted since the upstream
> artifacts were last accepted? Specifically, has the problem
> shape, target audience, scope boundary, or core success
> criterion changed in a way that would invalidate an existing
> BRIEF, PRD, or DESIGN you might find on disk?

The prompt continues with topic-related child-doc discovery —
file globs against `docs/briefs/BRIEF-<topic>.md`,
`docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`,
`docs/designs/current/DESIGN-<topic>.md`, and
`docs/plans/PLAN-<topic>.md`. Any artifact found is named back
to the author with its frontmatter `status:` value, so the
author's framing-shift answer is informed by the current state
of the chain on disk.

The framing-shift answer feeds R4's override for `/brief`. A
positive answer fires `/brief` even when an Accepted BRIEF exists
at the canonical path — the framing shift overrides the auto-skip.
The full literal prompt text is captured here for eval-grep
checking against the contract.

## Cold-Start Projected-PRD Evaluation

On a cold-start invocation (no `wip/scope_<topic>_state.md` and
no on-disk artifacts at the canonical paths), Phase 1 projects
what the downstream PRD's shape will likely be from the
$ARGUMENTS topic-slug alone. The projection is keyword-driven:
inspect the slug for the projection keywords (`feature`, `fix`,
`migration`, `rollout`, `consolidation`) and emit a one-line
projection naming the most likely PRD-altitude work shape. The
projection feeds the discovery-prompt framing (it does NOT
override the author's answer).

When the cold-start discovery yields empty results — no on-disk
artifacts AND the author answers the framing-shift question with
"no signal yet" — Phase 1 short-circuits the rest of the
discovery walk. The state file records `phase-1: empty-cold-start`
and the entry-altitude recommendation resolves to `brief` (the
framing-shift answer is deferred to the BRIEF authoring
conversation).

## Post-`/prd` Re-evaluation Gate

After `/prd` returns Accepted, Phase 1 re-evaluates the R6 shape
predicates against the real PRD body rather than the pre-PRD
projection. If any P1/P2/P3 verdict changed, the gate writes
`chain_revised: true` into the state file and re-narrates
`/design`'s roster shape. The author confirms the revised shape
before Phase 2 proceeds.

When the post-PRD predicates match the pre-PRD projection,
`chain_revised:` stays unset and the chain proceeds without
re-narration.

The re-evaluation changes `/design`'s roster size, never whether
`/design` runs. `planned_chain:` was fixed by the entry altitude
and is not revised here.

## Re-Entry Protection (R4, R5)

Every child in `planned_chain:` carries the same protection: the
parent MUST NOT silently overwrite a settled durable artifact. A
child whose artifact already exists at a settled status at the
canonical path is skipped and recorded in `chain_skipped:` with
reason `settled-artifact-at-canonical-path-reentry-protection`.

The settled statuses per child:

| Child | Canonical path | Settled at |
|---|---|---|
| `/brief` | `docs/briefs/BRIEF-<topic>.md` | Accepted, Done |
| `/prd` | `docs/prds/PRD-<topic>.md` | Accepted, In Progress, Done |
| `/design` | `docs/designs/DESIGN-<topic>.md`, `docs/designs/current/DESIGN-<topic>.md` | Accepted, Planned, Current |
| `/plan` | `docs/plans/PLAN-<topic>.md` | Active, Done |

The gate shape is Mandatory-with-auto-skip per the Gate
Vocabulary in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`.
`/brief` carries the framing-shift override: an Accepted BRIEF on
disk plus an author answer indicating the topic's framing has
shifted fires `/brief` anyway. The override can only ever fire in
the case the auto-skip would otherwise have closed, so a cold
start fires `/brief` whatever the answer says.

**This is not a worth-producing judgment.** The skip means "a
settled document is already here, and re-running would clobber
it." It does not mean "this artifact would not have been worth
writing." Nothing at Phase 1 is in a position to make the second
claim, because the artifact it would be about does not exist. An
earlier revision of this file recorded the same behaviour under
a rationale that read as reader economy; the reason it gives now
is the reason it always had.

An earlier revision also called `/brief`'s gate EITHER-signal, on
the reading that the artifact state and the framing shift were
independent routes into the child. They are not; the shape name
changed 2026-08-08 and the gate fires on exactly the same runs it
always did.

## R6 Shape-Predicate Walk

R6 walks three predicates inline. Each predicate emits a
`fires` or `does-not-fire` verdict and a one-line reason. The
verdicts feed two consumers: the entry-altitude recommendation
below, and `/design`'s decision-roster shape (which
decision-researcher roster fires, against which inputs) when
`/design` runs.

The predicates do **not** decide whether `/design` is invoked.
`/design` runs on every chain entered at or above the design
altitude. R7 previously read these verdicts as a produce-or-skip
gate; that reading is retired, and "shape-dependent" now means
what it says in the Gate Vocabulary — the gate governs *how* a
child is invoked, not whether.

When the PRD does not exist yet (a chain entered at `brief` or
`prd`), the predicates are evaluated against the projected PRD
shape from the cold-start projection and the discovery
conversation, and re-evaluated against the real PRD by the
post-`/prd` gate below.

### P1 — Architectural-Alternatives Count

P1 fires when the PRD names at least one architectural
alternative left open for the DESIGN to settle. Inspection
walks the PRD's named requirements; any requirement that names
multiple acceptable implementations (or leaves an
implementation choice explicitly open) increments the count.

Worked examples:

- **Positive (P1 fires):** the PRD requirement reads "The PRD
  SHALL use TLS for transport; cipher suite to be decided." →
  1 architectural alternative left open (cipher suite). P1
  fires.
- **Positive (P1 fires):** "The system SHALL persist user
  preferences across sessions; the storage backend may be
  filesystem, SQLite, or remote KV." → 3 architectural
  alternatives. P1 fires.
- **Positive (P1 fires):** "Authentication may use either
  OAuth2 or a self-hosted token service." → 2 architectural
  alternatives. P1 fires.
- **Negative (P1 does not fire):** "The PRD SHALL log to stderr
  at INFO level." → 0 architectural alternatives left open. P1
  does not fire.
- **Negative (P1 does not fire):** "The CLI SHALL accept `--help`
  and exit 0 with the help text." → 0 architectural alternatives.
  P1 does not fire.

### P2 — New-Component References

P2 fires when the PRD names a new component (a binary, service,
library, or runtime substrate) not already present in the repo.
Inspection cross-references the PRD's component mentions against
the repo's existing directory structure plus the components
documented in upstream STRATEGY or VISION artifacts.

Worked examples:

- **Positive (P2 fires):** PRD mentions "a new ingest worker
  binary at `cmd/ingestd/`" and the repo has no `cmd/ingestd/`
  directory. → New component. P2 fires.
- **Positive (P2 fires):** PRD mentions "a worker pool
  substrate" and the upstream STRATEGY does not name a worker
  pool. → New substrate. P2 fires.
- **Positive (P2 fires):** PRD references "the message broker"
  but no broker is documented anywhere upstream. → New
  component implied. P2 fires.
- **Negative (P2 does not fire):** PRD mentions "the existing
  `internal/validate` package" and the package exists in the
  repo. → Existing component, not new. P2 does not fire.
- **Negative (P2 does not fire):** PRD names "the shirabe CLI"
  and `cmd/shirabe/` is in the repo. → Existing component. P2
  does not fire.

### P3 — Complex Classification

P3 fires when the PRD carries the explicit `complexity:
Complex` (or analogous) frontmatter classification, or when the
PRD's prose explicitly names architectural complexity warranting
a DESIGN doc (e.g., "this requires a DESIGN per the project's
complexity policy").

Worked examples:

- **Positive (P3 fires):** PRD frontmatter has
  `complexity: Complex`. → Explicit classification. P3 fires.
- **Positive (P3 fires):** PRD body contains "the
  architectural shape of this feature warrants a DESIGN doc
  before implementation". → Explicit prose. P3 fires.
- **Positive (P3 fires):** PRD body contains "see the upcoming
  DESIGN-<topic> for the chosen approach". → Forward reference
  presupposing a DESIGN. P3 fires.
- **Negative (P3 does not fire):** PRD frontmatter has
  `complexity: Simple` or omits the field entirely, AND the
  prose makes no architectural-complexity claim. → No
  classification. P3 does not fire.
- **Negative (P3 does not fire):** PRD body says "implementation
  is mechanical given the requirements". → Explicit not-complex
  statement. P3 does not fire.

## R7 Shape-Dependent Evaluation for `/design`

R7 sizes `/design`'s decision roster from the R6 per-predicate
verdicts: which decision-researcher roster fires, with how many
peers, against which inputs. All-negative verdicts still invoke
`/design`; they size it down to the minimum roster, and the
resulting DESIGN records the one live option and why no
alternative was live. That is a shorter document than a
contested design, and it is a better audit trail than the
silence it replaces.

The shape-dependent identifier is the Gate Vocabulary entry
from `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`;
the predicate verdicts feed both the chain-proposal narration
and `/design`'s decision roster cardinality.

## Entry-Altitude Decision

The chain's entry altitude is decided once, here, and the chain
then runs every child from that altitude through `/plan`. The
four altitudes are `brief`, `prd`, `design`, and `plan`, and the
value is recorded in the state file's `entry_altitude:` field.

The decision is a question about the conversation the author is
having, not about the contents of a document nobody has written.
That is what makes it answerable at Phase 1 when a
worth-producing judgment is not.

**Inputs.** Four, all already gathered by this phase:

- the on-disk survey (which of BRIEF / PRD / DESIGN / PLAN exist
  at the canonical paths, and at what status);
- the R6 predicate verdicts;
- the cold-start projected-PRD keyword projection;
- the author's framing-shift answer.

**Recommendation.** Phase 1 marks exactly one altitude
recommended and states its reasons, per the decision-presentation
convention in
`${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md`: pick
the best option, say why, let the author override. In `--auto`
mode the recommendation is taken without prompting.

| Situation | Recommended entry |
|---|---|
| Nothing on disk and the framing is not settled | `brief` |
| The framing is settled, or a BRIEF is already on disk | `prd` |
| The requirements are settled, or a PRD is already on disk | `design` |
| The architecture is settled, or a DESIGN is already on disk | `plan` |

"Settled" means the author can state the thing without further
conversation, not that it is written down. An author who says
"the problem is obvious, I want to talk about requirements" has a
settled framing; the chain enters at `prd` and the framing is
captured in the PRD's Problem Statement.

**The no-durable-artifact warning.** When the recommendation
resolves to `plan` and no durable artifact exists at any canonical
path for the topic, the proposal SHALL state that the run will
leave no durable artifact behind, because the PLAN is deleted once
its work is implemented. The warning is informational; the author
may proceed. It fires only in that case — a chain entered at
`plan` against an existing DESIGN leaves that DESIGN, so no
warning is surfaced.

No reduction of the artifact set can produce this outcome on its
own: the consolidation judgment in Phase 2 can only absorb at a
hop where the downstream type has a home for every one of the
upstream's required sections, and no hop above `plan` qualifies.
A chain entered above `plan` always leaves a durable artifact.

## Chain-Proposal Output

After the entry altitude is chosen and the re-entry protections
evaluate, Phase 1 emits a chain-proposal output naming the entry
altitude and its reasons, the planned children, the re-entry
verdict for each, the R6 per-predicate verdicts, and the offered
options. The output's options block contains the literal
substrings `Proceed`, `Adjust`, and `Bail` (case-sensitive, exact
spelling per AC9).

Example output skeleton:

> Entry altitude: **brief** (recommended)
>   Nothing on disk for this topic, and the framing-shift answer
>   says the problem shape is still being settled.
>   Alternatives: prd (if the framing is settled and you want to
>   go straight to requirements), design, plan.
>
> Planned chain:
>   /brief — runs (no settled artifact at the canonical path)
>   /prd — runs (no settled artifact at the canonical path)
>   /design — runs; roster shape from P1 fires, P2 does-not-fire,
>     P3 fires
>   /plan — runs (ALWAYS)
>
> Proceed / Adjust / Bail?

The three branch behaviors:

- **Proceed** — confirm the proposed chain; advance to Phase 2
  and begin invoking children in order.
- **Adjust** — return to Phase 1 discovery with the author's
  adjustment input; re-emit the proposal after re-running the
  gates against the adjusted scope.
- **Bail** — route to R8 bail-handling per the parent's own
  bail-handling rule (force-materialize if any wip state exists
  for the topic; clean-cancel otherwise).

## `planned_chain:` Population

Phase 1 writes `planned_chain:` in the state file as every child
from `entry_altitude:` through `plan`, in chain order, minus any
child held back by re-entry protection. Held-back children appear
in `chain_skipped:` with their reason, not in `planned_chain:`.
The two lists together cover the full Phase 1 verdict surface.

```yaml
entry_altitude: brief
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
```

A chain entered at `design` writes the suffix from that altitude:

```yaml
entry_altitude: design
planned_chain:
  - design
  - plan
chain_skipped: []
```

When re-entry protection holds a child back, the entry shape is:

```yaml
chain_skipped:
  - name: prd
    reason: settled-artifact-at-canonical-path-reentry-protection
```

That is the only reason Phase 1 ever writes. A child is never
recorded there because Phase 1 judged its artifact not worth
producing; Phase 1 makes no such judgment. (Phase 2 writes one
other reason, when a Reject at a settled-upstream boundary ends
the chain and the remaining children never run — see the
decision-record templates under `skills/scope/references/`.)

Phase 2 reads `planned_chain:` and invokes the listed children
in order; it does NOT re-walk Phase 1's evaluations per child.
Phase 1's verdicts are the cached chain-shape; Phase 2 consumes
them.

## Initial `child_snapshots:` Capture

For each pre-existing durable artifact discovered during the
discovery prompt (`docs/briefs/BRIEF-<topic>.md`,
`docs/prds/PRD-<topic>.md`,
`docs/designs/current/DESIGN-<topic>.md`,
`docs/plans/PLAN-<topic>.md`), Phase 1 captures an initial
snapshot per R10:

```yaml
child_snapshots:
  prd:
    status: Accepted
    content_hash: <git-blob-hash>
    captured_at: <ISO-8601 timestamp>
```

The dual-check pair (status + content-hash) catches both kinds
of drift on subsequent `/scope` resumes: a status flip and a
body edit at the same status.

## Three-Way Adjust Path

When the author selects Adjust, Phase 1 re-enters at the
discovery prompt with the author's adjustment input merged in.
Adjust is also how an author changes the entry altitude away
from the recommended one. Re-entry re-runs the R6 predicates,
re-derives the recommendation, and re-emits the chain proposal;
the loop continues until the author selects Proceed or Bail.
There is no implicit limit on Adjust iterations; the
`--max-rounds=N` flag governs re-evaluation iterations across
chain instances, not Phase 1 Adjust iterations within a single
chain run.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  Gate Vocabulary (ALWAYS, shape-dependent,
  Mandatory-with-auto-skip), Conditional Feeder Invocation Shape.
- `${CLAUDE_PLUGIN_ROOT}/references/decision-presentation.md` —
  the recommend-then-let-the-author-override shape the
  entry-altitude decision follows.
- `skills/scope/references/phases/phase-2-chain-orchestration.md`
  — the Consolidation Judgment that reduces the artifact set
  after the artifacts exist.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — `planned_chain:` / `chain_ran:` / `chain_skipped:` triad,
  per-child snapshot dual-check.
