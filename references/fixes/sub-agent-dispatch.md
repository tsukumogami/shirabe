# Sub-Agent Dispatch Fallback Resolution

Canonical resolution guidance for child skills (`/brief`, `/prd`,
`/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, `/work-on`)
when they are invoked from a parent chain (`/scope` for tactical,
`/charter` for strategic) rather than directly by a human author.

This file is dereferenced on-demand by each child SKILL's Phase 0
detection step and by the Resume Logic row that the parent-chain
sentinel matches. The child skills do NOT eagerly load this prose;
the lazy-load principle holds (DESIGN D1 / D2).

## Sentinel detection convention

When a parent chain spawns a child, it writes a sentinel into its own
state file (`wip/scope_<topic>_state.md` for `/scope`,
`wip/charter_<topic>_state.md` for `/charter`):

```yaml
parent_orchestration:
  invoking_child: <skill-name>            # brief|prd|design|plan|...
  suppress_status_aware_prompt: true      # parent owns the prompt UX
  rationale: <fresh-chain|revise|repeat>  # routes chain-handoff behavior
```

The three subfields are load-bearing:

- `invoking_child` -- the child the parent is currently driving. The
  child reads this to confirm it was spawned from the expected parent
  context (not, for example, a stale state file from a different
  topic).
- `suppress_status_aware_prompt` -- when `true`, the child must skip
  the status-aware approval prompt the parent owns. The parent
  presents the unified prompt at chain boundaries.
- `rationale` -- routes how the child closes out:
  - `fresh-chain` -- this is the first pass through the chain; the
    child finalizes the artifact and hands control back to the parent.
  - `revise` -- the child was re-spawned to revise an artifact that
    failed downstream review; the child re-runs from the artifact
    altitude rather than starting over.
  - `repeat` -- the child should re-run an already-finalized artifact
    to reflect a downstream change (rare; reserved for tooling-driven
    re-emission).

## The five canonical fallback shapes

A child invoked under sub-agent dispatch cannot always perform the
same review or approval mechanics it uses under direct human
invocation (no interactive user, parent owns the prompt UX, etc.).
The five canonical fallback shapes encode the resolutions:

### 1. Serial-self-jury

When the child's normal flow spawns a multi-reviewer jury in parallel
(e.g. `/design`'s Phase 6 architecture + security + structural-format
reviewers), and the dispatch context does not support parallel
sub-agent spawns, the child runs each reviewer serially within the
same process, preserving the rubric set but losing parallelism. The
verdicts are folded into a single feedback table.

**Bindings:** `/design` Phase 6, `/prd` Phase 4 jury, `/strategy`
Phase 6.

### 2. Parent-delegated-approval

When the child would normally prompt the author for an Accepted/
Reject verdict, but the parent chain owns the unified prompt at the
chain boundary, the child writes its draft to disk in a non-Accepted
state (`Draft` for BRIEF/PRD/PLAN; `Proposed` for DESIGN) and hands
control back to the parent. The parent presents the chain-level
prompt and triggers the Accepted transition on approval.

**Bindings:** all seven authoring children (`/brief`, `/prd`,
`/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`).

### 3. Decision-bypass-with-inline-resolution

When `/design`'s decision-evaluation sub-flow would normally
delegate to `/decision` for a contested 3+ alternatives choice, but
the dispatch context routes the decision back through the parent,
the design instead resolves the decision inline within its own Phase
2 evaluation and records the rationale in the Considered Options
section. The bypass is recorded in the design's frontmatter
`decision_provenance: inline-resolved`.

**Bindings:** `/design` Phase 2.

### 4. Inline-substitute-review

When a child would normally invoke a second-pass review (e.g. /plan
re-running Phase 6 on a revised artifact), and the dispatch context
already received a verdict at the parent altitude, the child accepts
the parent's verdict as the substitute and skips the second pass.
The substitute verdict is recorded in the child's wip state file
(`verdict_source: parent-substitute`).

**Bindings:** `/plan` Phase 6 re-runs, `/prd` Phase 4 re-runs.

### 5. Deterministic-mode-bypass

When the child includes a deterministic structural transformation
(e.g. `/plan` Phase 7 single-pr emission) that does not require
review at all under the parent's chain rationale, the child runs the
deterministic path and skips the discretionary phases. The bypass
is signaled by the parent setting `rationale: fresh-chain` with the
deterministic transformation already complete.

**Bindings:** `/plan` Phase 7 single-pr mode, `/roadmap` Phase 5
single-pr populate.

## Per-skill binding table

The eight children bind to the fallback shapes as follows. Each row
lists which shape applies at which phase; absent rows mean the child
does not need a fallback at that phase.

| Skill | Phase | Applicable fallback shapes |
|-------|-------|---------------------------|
| `/brief` | Phase 4 finalize | Parent-delegated-approval |
| `/prd` | Phase 4 jury | Serial-self-jury, Inline-substitute-review |
| `/prd` | Phase 5 finalize | Parent-delegated-approval |
| `/design` | Phase 2 decisions | Decision-bypass-with-inline-resolution |
| `/design` | Phase 6 jury | Serial-self-jury, Parent-delegated-approval |
| `/plan` | Phase 6 review | Inline-substitute-review |
| `/plan` | Phase 7 emit | Deterministic-mode-bypass, Parent-delegated-approval |
| `/vision` | Phase finalize | Parent-delegated-approval |
| `/strategy` | Phase 6 jury | Serial-self-jury, Parent-delegated-approval |
| `/roadmap` | Phase 5 populate | Deterministic-mode-bypass, Parent-delegated-approval |
| `/work-on` | Phase 0 detection only | (no Resume Logic row; sentinel detection only) |

`/work-on` carries only the Phase 0 detection line (R9 scopes the
seven authoring children for the Resume Logic row). When `/work-on`
runs under a parent chain, it inherits the parent's branch and PR
context but otherwise operates normally.

## Chain-handoff routing by rationale

The parent's `rationale` value determines the post-finalization
routing:

- `rationale: fresh-chain` -- the child finalizes the artifact, the
  parent reads the child's terminal state, and the parent advances
  to the next chain step (e.g. BRIEF -> PRD, PRD -> DESIGN, DESIGN
  -> PLAN). The parent owns the transition.
- `rationale: revise` -- the child re-finalizes the revised artifact
  and returns control to the parent at the SAME chain step. The
  parent then re-evaluates whether downstream artifacts need
  re-running.
- `rationale: repeat` -- rare; the child re-emits the artifact under
  a tooling-driven trigger (schema version bump, format-reference
  update). The parent reads the re-emitted artifact but does not
  advance the chain.

## NOT covered (R8 carve-out)

This file documents the resolution guidance for sub-agent dispatch
within the existing seven-child chain. It does NOT cover the
amplifier-layer mandate refinement work tracked at
`tsukumogami/vision#535` Track B. The Track B work introduces a
separate mandate layer above the chain skills; its dispatch
semantics are out of scope here and resolve under a different
contract published when Track B lands.
