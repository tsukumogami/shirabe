# Phase 1 — Discovery and Chain Proposal

Phase 1 turns the topic slug into a planned chain. It runs the
discovery prompt to surface a framing-shift signal, evaluates
the four child gates per the Gate Vocabulary, walks the R6
shape-predicate inline, captures initial child-snapshots for
any pre-existing durable artifacts, and emits a chain-proposal
output the author confirms (Proceed / Adjust / Bail).

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

The framing-shift answer feeds R4's EITHER-signal for `/brief`.
A positive answer alone fires `/brief` even when an Accepted
BRIEF exists at the canonical path (the framing shift overrides
the upstream-exists signal). The full literal prompt text is
captured here for eval-grep checking against the contract.

## R4 EITHER-Signal Evaluation for `/brief`

The `/brief` invocation gate is an EITHER-signal gate per the
Gate Vocabulary in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`. Two
independent signals open the gate:

1. **No upstream BRIEF at the canonical path** — `docs/briefs/BRIEF-<topic>.md`
   does not exist, or exists at a non-Accepted status.
2. **Framing-shift signal positive** — the author's answer to
   the framing-shift question indicates the topic's framing has
   shifted enough to warrant a fresh BRIEF.

Either signal alone fires `/brief`; both signals holding fires
`/brief` once (not twice). When neither signal holds (Accepted
BRIEF exists AND the framing has not shifted), `/brief` is
recorded in `chain_skipped:` with reason `accepted-brief-at-
canonical-path-with-no-framing-shift`.

## R5 Mandatory-with-Auto-Skip Evaluation for `/prd`

The `/prd` invocation gate is the Mandatory-with-auto-skip shape
from the Gate Vocabulary. The gate semantics:

- If `docs/prds/PRD-<topic>.md` exists at status `Accepted`,
  record `/prd` in `chain_skipped:` with reason
  `accepted-prd-at-canonical-path` and proceed to the next gate.
- If the canonical path has no PRD, OR the PRD is at any non-
  Accepted status (`Draft`, `Proposed`, etc.), the gate fires
  and `/prd` is invoked.

The parent MUST NOT silently overwrite an Accepted durable
artifact. The Mandatory-with-auto-skip shape is the contract
that protects settled-upstream artifacts from being clobbered by
a re-running chain.

## R6 Shape-Predicate Walk for `/design`'s Roster Shape

R6 walks three predicates inline. Each predicate emits a
`fires` or `does-not-fire` verdict and a one-line reason; the
per-predicate verdicts feed R7's gate decision for `/design`
and the chain-proposal's shape-dependent narration.

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

R7 evaluates `/design`'s gate using the R6 per-predicate
verdicts. When one or more R6 predicates fire, `/design` fires
and its sub-shape (which decision-researcher roster, against
which inputs) is determined by which predicates fired. When
zero R6 predicates fire, `/design` is recorded in
`chain_skipped:` with the per-predicate verdicts as the skip
reason (e.g., "P1: does-not-fire (zero alternatives); P2:
does-not-fire (no new components); P3: does-not-fire
(complexity: Simple)").

The shape-dependent identifier is the Gate Vocabulary entry
from `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`;
the predicate verdicts feed both the chain-proposal narration
and `/design`'s decision roster cardinality.

## Chain-Proposal Output

After the four gates evaluate, Phase 1 emits a chain-proposal
output naming the planned children, the gate verdict for each,
the R6 per-predicate verdicts, and the offered options. The
output's options block contains the literal substrings
`Proceed`, `Adjust`, and `Bail` (case-sensitive, exact spelling
per AC9).

Example output skeleton:

> Planned chain:
>   /brief — fires (R4 EITHER-signal: no upstream BRIEF)
>   /prd — fires (R5: no Accepted PRD at canonical path)
>   /design — fires (R7 shape-dependent: P1 fires, P2 fires,
>     P3 does-not-fire)
>   /plan — fires (ALWAYS)
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

Phase 1 writes `planned_chain:` in the state file as the list
of children whose gates fired. Skipped children appear in
`chain_skipped:` with their per-gate skip reason, not in
`planned_chain:`. The two lists together cover the full Phase
1 verdict surface.

```yaml
planned_chain:
  - brief
  - prd
  - design
  - plan
chain_skipped: []
```

When a gate auto-skips, the entry shape is:

```yaml
chain_skipped:
  - name: prd
    reason: accepted-prd-at-canonical-path
```

Phase 2 reads `planned_chain:` and invokes the listed children
in order; it does NOT re-walk Phase 1's gate evaluations per
child. Phase 1's verdicts are the cached chain-shape; Phase 2
consumes them.

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
Re-entry re-runs R6 predicates and re-emits the chain proposal;
the loop continues until the author selects Proceed or Bail.
There is no implicit limit on Adjust iterations; the
`--max-rounds=N` flag governs re-evaluation iterations across
chain instances, not Phase 1 Adjust iterations within a single
chain run.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  Gate Vocabulary (EITHER-signal, ALWAYS, shape-dependent,
  Mandatory-with-auto-skip), Conditional Feeder Invocation Shape.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — `planned_chain:` / `chain_ran:` / `chain_skipped:` triad,
  per-child snapshot dual-check.
