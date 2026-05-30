# Parent-Skill Worktree Discipline

The rule every parent skill follows for keeping its worktree in sync
with upstream across a multi-child chain: before each Phase 2 child
invocation, the parent SHALL attempt `git fetch && git rebase
origin/<tracking-branch>` silently. Clean rebases proceed without
prompting; conflicts route to the team lead. The author is bothered
only when the team lead escalates an unresolved conflict. Per-parent
bindings live in the Binding Notes section at the end; everything
above that section is substrate-agnostic.

Companion references:

- [`parent-skill-pattern.md`](parent-skill-pattern.md) — the contract
  surface this rule sits inside (Phase 2 child invocation loop,
  exit-path enumeration).
- [`parent-skill-state-schema.md`](parent-skill-state-schema.md) — the
  conditional-field extension discipline `worktree_rebases:` and
  `worktree_divergences:` ride on.

## Trigger Condition

The rebase attempt fires **before each Phase 2 child invocation** —
never once per parent invocation. Precisely:

1. After the parent's Phase 1 emits its chain-proposal output and the
   author confirms the proposed chain.
2. Before each child invocation in the confirmed `planned_chain`.

The attempt runs once per child invocation in the chain. For a parent
with four children in its longest chain, it fires up to four times
across a single full-run; for three children, up to three times.
Bounded by chain step count, not wallclock time.

## Default: Silent Rebase

Before each child invocation, the parent SHALL execute the equivalent
of:

```
git fetch
git rebase origin/<tracking-branch>
```

The parent owns the branch during the chain — there is no parallel-
author work to disrupt — so silent rebase is safe by default.

**Clean rebase** (no conflicts): the parent records an informational
entry in `worktree_rebases:` (see Recording below) naming the
upstream commits that landed and proceeds directly to child
invocation. The author is not prompted; the team lead is not
prompted.

**No-op rebase** (upstream had not advanced): the parent proceeds
directly to child invocation. No recording, no prompt — the routine
case.

## Conflict Fallback: Route to Team Lead

When the rebase produces conflicts, the parent SHALL halt the chain
at the pre-invocation point and route the conflict to the team lead
with full context:

- Which files conflict
- The upstream commits involved (SHAs + subjects)
- The conflicted hunks

The team lead applies its standard discipline:

1. Resolve from artifact context — if the BRIEF, PRD, or DESIGN cites
   the conflicted file and the right resolution is obvious from that
   citation, resolve and continue.
2. Delegate investigation — spawn a research agent to read the
   conflicting upstream commits and report whether they change a
   contract the chain depends on.
3. Invoke `/shirabe:decision` — for genuine judgment calls where
   neither artifact context nor code investigation settles the
   question.
4. Escalate to the author — for genuine ambiguity, the team lead
   surfaces a three-option prompt: **Resolve and continue** (the
   author manually resolves, the parent re-runs the rebase, then
   proceeds to child invocation), **Proceed anyway against the
   unrebased base** (the parent abandons the rebase, records the
   divergence per Recording below, and continues to child invocation
   on the original base), or **Bail** (terminate the chain per the
   parent's own bail-handling rule).

The author is brought into the loop only at step 4 — and only when
the team lead cannot decide. Cosmetic upstream PRs, orthogonal
changes, or conflicts the artifact context resolves never reach the
author.

## Recording

Two conditional state-file lists, both extensions over the 5-field
minimum schema (see [`parent-skill-state-schema.md`](parent-skill-state-schema.md)).

**`worktree_rebases:`** — informational. Appended on every clean
rebase that brought new upstream commits in. Absent if no rebase ever
brought commits in.

```yaml
worktree_rebases:
  - phase: <next-child-name>
    upstream_commits: [<sha>, <sha>, ...]
    rebased_at: <ISO-8601 timestamp>
```

**`worktree_divergences:`** — decision audit. Appended only when the
conflict-fallback escalated to the author and the author chose
"Proceed anyway against the unrebased base." Absent in the common
case (no conflict, or conflict resolved without escalation).

```yaml
worktree_divergences:
  - phase: <next-child-name>
    conflict_summary: <files + nature>
    upstream_commits: [<sha>, <sha>, ...]
    accepted_at: <ISO-8601 timestamp>
```

Both lists are appended in chronological order and never shrink
within a chain instance. They exist so the parent's finalization step
can surface upstream-interaction history in the terminal artifact,
and so future reviewers can audit how the chain handled upstream
change.

## Integration with Chain-Proposal Prompt

The rebase attempt fires **after** chain-proposal confirmation, not
before. The chain-proposal prompt itself makes no network calls;
running `git fetch` before the author confirms would pay network
latency on every Phase 1 termination, including the ones the author
rejects or revises. The current order pays the cost only when the
chain is going to run.

## Binding Notes

The body above is parent-agnostic. Per-parent bindings live here. New
parents inherit the discipline by adding a binding-notes row rather
than re-authoring the body.

| Parent | Status | Chain length | Bail target |
|--------|--------|--------------|-------------|
| `/scope` v1 | load-bearing | 4 children (longest chain in shirabe) | the parent's own bail-handling rule in `skills/scope/SKILL.md` |
| `/charter` | load-bearing (back-edit) | 3 children | the parent's own bail-handling rule in `skills/charter/SKILL.md` |
| `/work-on` | future | TBD | binding deferred to the amplifier-layer parent migration |

The "Bail target" column intentionally names the per-parent SKILL.md
rather than reproducing the bail logic here. Naming a specific
parent's bail rule (such as `/scope` R8) inline would couple the
body to one parent's vocabulary.
