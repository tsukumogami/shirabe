# Parent-Skill Worktree Discipline

The rule every parent skill follows when upstream advances mid-chain:
**escalate based on whether upstream changes invalidate the chain's
intent, not on whether the rebase was mechanically clean.** A clean
rebase can silently land a contract change that breaks the chain's
references; a mechanical conflict can be in a file the chain doesn't
care about. The discipline below replaces mechanical-conflict
signals with contextual-impact signals at every step.

Before each Phase 2 child invocation, the parent runs a three-step
flow: rebase, analyze impact, escalate by impact level. Every actor
in the chain operates at its appropriate altitude — sub-agents
handle git mechanics and conflict resolution, the team lead handles
judgment calls about intent, and the author is brought in only when
the original session direction is in question.

Per-parent bindings live in the Binding Notes section at the end;
everything above that section is substrate-agnostic.

Companion references:

- [`parent-skill-pattern.md`](parent-skill-pattern.md) — the contract
  surface this rule sits inside (Phase 2 child invocation loop,
  exit-path enumeration).
- [`parent-skill-state-schema.md`](parent-skill-state-schema.md) — the
  conditional-field extension discipline `worktree_rebases:` and
  `worktree_divergences:` ride on.

## Trigger Condition

The flow fires **before each Phase 2 child invocation** — never once
per parent invocation. Precisely:

1. After the parent's Phase 1 emits its chain-proposal output and the
   author confirms the proposed chain.
2. Before each child invocation in the confirmed `planned_chain`.

The flow runs once per child invocation in the chain. For a parent
with four children in its longest chain, it fires up to four times;
for three children, up to three. Bounded by chain step count, not
wallclock time — a long-running child does not retrigger the flow on
its own. The flow fires after chain-proposal confirmation, not
before, for reasons documented in DESIGN Decision 4.

## Rebase phase

Execute the equivalent of:

```
git fetch
git rebase origin/<tracking-branch>
```

**Clean rebase**: proceed directly to the impact-analysis phase
with the list of upstream commits that landed.

**Conflicted rebase**: the parent's conflict-resolution sub-agent (or
the parent itself in solo mode) attempts to resolve the conflict
from artifact context. BRIEF, PRD, and DESIGN citations frequently
make the correct resolution obvious — if the chain's artifact says
"the input format is X" and upstream changes the format to Y, the
resolution is to align with Y. Resolved conflicts proceed to the
impact-analysis phase with the resolution noted. Conflicts that
cannot be resolved from artifact context proceed to the
impact-analysis phase anyway, carrying the unresolved conflict as
part of the diff the analysis will classify.

## Impact-analysis phase

Read the upstream commits that landed in the rebase phase and
cross-reference them against:

- The chain's authored artifacts at this point (BRIEF, PRD, DESIGN,
  PLAN as they exist).
- The inputs the next child invocation will consume.

Classify the impact at one of three levels:

- **None** — upstream changes touch no path, symbol, or contract the
  chain depends on. Examples: a recipe added to a different package;
  a doc reformatted in a subsystem the chain doesn't reference; a
  test added that the chain doesn't run.

- **Informational** — chain-referenced content was touched, but
  non-substantively. Examples: a typo fix in a doc the BRIEF cites;
  a comment added to a function the DESIGN names; a whitespace
  change in a config file the PLAN references.

- **Intent-changing** — a contract, interface, or fact the chain has
  committed to was altered. Examples: a child skill's input format
  changed (BRIEF/PRD cited the old format); a referenced file was
  renamed or removed; a doc the BRIEF cites was rewritten such that
  the citation no longer supports the BRIEF's claim; a recipe the
  PLAN expects to ship was withdrawn.

The classification is what an analyzer agent would produce after
reading the upstream commits and the chain's artifacts. It is not a
purely syntactic check — it requires judgment about whether a
referenced change is substantive enough to alter what the chain is
doing.

## Escalation phase

**None or Informational**: record the rebase in `worktree_rebases:`
(see Recording) and proceed to child invocation. The team lead is
not prompted; the author is not prompted.

**Intent-changing**: halt and route to the team lead with full
evidence — which authored artifact, which referenced contract, what
specifically changed, and the analyzer's classification reasoning.
The team lead decides whether the original session intent still
holds against the new upstream reality:

- If yes — the chain is still doing the right thing, but a citation
  or a small claim in an artifact needs adjusting — the team lead
  resolves in-place. Update the affected citation or claim, then
  proceed to child invocation. Record in `worktree_rebases:` with
  classification `intent-changing-resolved-in-place`.
- If no — the intent has genuinely shifted — the team lead escalates
  to the author with a three-option prompt:
  - **Re-author affected artifacts** against the new contract, then
    continue the chain.
  - **Proceed against original intent**: keep the chain pointed at
    the prior contract, accept that the eventual PR will need to
    address the divergence at review time. Recorded in
    `worktree_divergences:`.
  - **Bail** per the parent's own bail-handling rule.

## Recording

Per I-5 (see [`parent-skill-state-schema.md`](parent-skill-state-schema.md)), these fields MUST be absent when no rebases or divergences have occurred — never null, empty list, or placeholder.

Two conditional state-file lists, both extensions over the 5-field
minimum schema (see [`parent-skill-state-schema.md`](parent-skill-state-schema.md)).

**`worktree_rebases:`** — appended after every rebase that brought
new upstream commits in (regardless of classification, except when
the chain bailed). Informational. Entries:

```yaml
worktree_rebases:
  - phase: <next-child-name>
    upstream_commits: [<sha>, <sha>, ...]
    impact: none | informational | intent-changing-resolved-in-place
    rebased_at: <ISO-8601 timestamp>
    notes: <optional — e.g., which citation was updated for in-place resolution>
```

**`worktree_divergences:`** — decision audit. Appended only when the
team lead escalated an intent-changing event to the author and the
author chose "proceed against original intent." Absent in the common
case. Entries:

```yaml
worktree_divergences:
  - phase: <next-child-name>
    affected_contracts: [<artifact + cite>, ...]
    upstream_commits: [<sha>, <sha>, ...]
    accepted_at: <ISO-8601 timestamp>
```

Both lists are appended in chronological order and never shrink
within a chain instance. They exist so the parent's finalization
step can surface upstream-interaction history in the terminal
artifact, and so future reviewers can audit how the chain handled
upstream change.

## Binding Notes

The body above is parent-agnostic. Per-parent bindings live here.
New parents inherit the discipline by adding a binding-notes row
rather than re-authoring the body.

| Parent | Status | Chain length | Bail target | Analyzer actor |
|--------|--------|--------------|-------------|----------------|
| `/scope` v1 | load-bearing | 4 children (longest chain in shirabe) | the parent's own bail-handling rule in `skills/scope/SKILL.md` | parent itself (solo mode); team-lead-spawned sub-agent (amplifier mode) |
| `/charter` | load-bearing (back-edit) | 3 children | the parent's own bail-handling rule in `skills/charter/SKILL.md` | parent itself (solo); team-lead-spawned sub-agent (amplifier) |
| `/work-on` | future | TBD | binding deferred to the amplifier-layer parent migration | binding deferred |

The "Analyzer actor" column reflects the team-primitive substitution
surface (see `parent-skill-pattern.md`). In v1's
`single-team-per-leader-no-nested` substrate, the parent skill is
single-agent and does the impact analysis itself. In an amplifier-
layer substrate where the parent can dispatch sub-agents, the
analysis can be delegated to a worktree-sync-analyzer sub-agent that
reports back to the parent. The discipline is identical across
substrates; only the actor changes.
