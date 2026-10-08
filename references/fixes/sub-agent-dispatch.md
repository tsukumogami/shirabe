# Sub-Agent Dispatch Fallback Resolution

Canonical resolution guidance for child skills (`/brief`, `/prd`,
`/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`)
when they are invoked from a parent chain (`/scope` for tactical,
`/charter` for strategic) rather than directly by a human author.

## Sentinel detection convention

When a parent chain spawns a child, it writes a sentinel into its own
state file (`wip/scope_<topic>_state.md` for `/scope`,
`wip/charter_<topic>_state.md` for `/charter`):

```yaml
parent_orchestration:
  invoking_child: <skill-name>            # brief|prd|design|plan|...
  suppress_status_aware_prompt: true      # skip the re-entry prompt
  rationale: <fresh-chain|revise|repeat>  # routes chain-handoff behavior
```

The three subfields are load-bearing:

- `invoking_child` -- the child the parent is currently driving. The
  child reads this to confirm it was spawned from the expected parent
  context (not, for example, a stale state file from a different
  topic).
- `suppress_status_aware_prompt` -- when `true`, the child skips its
  status-aware re-entry prompt (the question it asks when its artifact
  already exists at a status it recognizes). For `/scope`'s children
  it does not skip the child's own verdict: see shape 6 and "What a
  child keeps and what it skips under /scope" below. `/charter`'s
  children hand back a Draft for the parent to approve (shape 2).
- `rationale` -- routes how the child closes out:
  - `fresh-chain` -- this is the first pass through the chain; the
    child finalizes the artifact and hands control back to the parent.
  - `revise` -- the child was re-spawned to revise an artifact that
    failed downstream review; the child re-runs from the artifact
    altitude rather than starting over.
  - `repeat` -- the child should re-run an already-finalized artifact
    to reflect a downstream change (rare; reserved for tooling-driven
    re-emission).

## What a child keeps and what it skips under /scope

This section binds `/scope`'s children (`/brief`, `/prd`, `/design`,
`/plan`), per
`docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`.
`/charter`'s children keep the Parent-delegated-approval shape below.

Under `/scope`'s sentinel a child still reaches its own verdict and makes its
own status transition. `/design` and `/plan` require their upstream
already `Accepted` when they start, and the parent never transitions
anything, so each hop's approval has to happen inside the hop that
produced the artifact. An interactive run asks the author as the child
always does. An unattended run (`--auto`) takes the recommended option
and says so in its output, naming the verdict it took. The mode is the
parent's: the child is invoked inline, in the parent's own context, and
follows the execution mode the parent is running under at every decision
point, whether or not a mode flag is among its arguments. `/scope` passes
`/brief`, `/prd` and `/design` only the topic or the artifact path above
them, so no mode flag reaches them; `/plan` alone also receives any
`--upstream`, the caller's `--intent` and coordination flag, and
`/scope`'s resolved mode flag (Phase 2's invocation table).

What the child skips is everything that publishes or routes, because the
parent owns those:

- **push** -- no `git push` of any kind;
- **pull request** -- no `gh pr create`, `gh pr edit` or `gh pr ready`;
- **branch creation** -- the child works on the branch it was invoked on
  and never creates or switches branches;
- **cleanup commit** -- no commit removing the child's intermediate
  files, its `wip/research/` scratch included; the parent's cleanup
  phase and publish untrack own that;
- **upstream-issue edits** -- no `gh issue edit` on a source or upstream
  issue, its labels included, since `/scope`'s list of writes has none;
  a `needs-*` label the child would have removed stays for the author
  (who should remove it under `/scope` is tracked as #666);
- **routing prompts** -- no "what next" question (which skill to run
  next, whether to update an upstream issue); a prompt that pairs the
  verdict with a next step, such as `/design`'s "Plan (Recommended)" /
  "Approve only",
  keeps only the verdict. Control returns to the parent, which
  decides the next hop.

`/scope` publishes at most once, at its own exit (a run with no intent
publishes nothing), and its list of writes, in the Security
Considerations section of `skills/scope/SKILL.md`, is the only one that
applies while a child runs under it.

## The six canonical fallback shapes

A child invoked under sub-agent dispatch cannot always perform the
same review or approval mechanics it uses under direct human
invocation (no interactive user, parent owns the prompt UX or
publishing, etc.).
The six canonical fallback shapes encode the resolutions:

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
state (`Draft` for VISION/STRATEGY/ROADMAP) and hands
control back to the parent. The parent presents the chain-level
prompt and triggers the Accepted transition on approval.

**Bindings:** `/charter`'s children (`/vision`, `/strategy`,
`/roadmap`). `/scope`'s children follow shape 6 instead.

### 3. Decision-bypass-with-inline-resolution

Under the parent sentinel, `/design` routes each Phase 2 question by
its tier (per
`docs/decisions/DECISION-contradiction-design-inline-decision-fallback-2026-09-28.md`), a condition it can check rather than a judgment about the
dispatch context:

- a **standard**-tier question (`/decision`'s Tier 3) is resolved
  inline, within `/design`'s own Phase 2 evaluation, with the
  rationale in the Considered Options section;
- a **critical**-tier question (`/decision`'s Tier 4) still goes to
  `/decision`, under a parent as under a direct run.

Each question's Considered Options entry records its provenance,
inline or delegated to `/decision`. When any question was resolved
inline, the design's frontmatter carries
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

### 6. Parent-owned-publishing

The child reaches its own verdict and makes its own status
transition, and leaves publishing to the parent. "What a child keeps
and what it skips under /scope" above is the whole rule.

**Bindings:** `/scope`'s children (`/brief`, `/prd`, `/design`,
`/plan`).

## Per-skill binding table

The seven children bind to the fallback shapes as follows. Each row
lists which shape applies at which phase; absent rows mean the child
does not need a fallback at that phase.

| Skill | Phase | Applicable fallback shapes |
|-------|-------|---------------------------|
| `/brief` | Phase 5 finalize | Parent-owned-publishing |
| `/prd` | Phase 0 setup | Parent-owned-publishing |
| `/prd` | Phase 4 jury | Serial-self-jury, Inline-substitute-review |
| `/prd` | Phase 4 approval and cleanup | Parent-owned-publishing |
| `/design` | Phase 2 decisions | Decision-bypass-with-inline-resolution |
| `/design` | Phase 6 jury | Serial-self-jury, Parent-owned-publishing |
| `/plan` | Phase 6 review | Inline-substitute-review |
| `/plan` | Phase 7 emit | Deterministic-mode-bypass, Parent-owned-publishing |
| `/vision` | Phase finalize | Parent-delegated-approval |
| `/strategy` | Phase 6 jury | Serial-self-jury, Parent-delegated-approval |
| `/roadmap` | Phase 5 populate | Deterministic-mode-bypass, Parent-delegated-approval |

`/work-on` has no row: it reads no sentinel, at Phase 0 or anywhere else
(R9 scopes the seven authoring children for the Resume Logic row). When
`/work-on` runs under a parent chain, it inherits the parent's branch and PR
context but otherwise operates normally.

## Chain-handoff routing by rationale

The parent's `rationale` value determines the post-finalization
routing:

- `rationale: fresh-chain` -- the child finalizes the artifact, the
  parent reads the child's terminal state, and the parent advances
  to the next chain step (e.g. BRIEF -> PRD, PRD -> DESIGN, DESIGN
  -> PLAN). For `/scope`'s children (shape 6) the child made its
  artifact's status transition and the parent owns the move to the
  next step; for `/charter`'s children (shape 2) the parent triggers
  the Accepted transition on approval.
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
within the existing seven-child chain. It does NOT cover dispatch
from a layer above the chain skills, one that hands them mandates
rather than running as a step in the chain. Such a layer brings its
own dispatch semantics, which this contract doesn't define: the
parent-chain sentinel, the rationale values and the ownership rules
above all assume the parent is a chain skill. Dispatch from that
layer is governed by the contract the layer itself publishes.
