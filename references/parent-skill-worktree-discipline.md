# Parent-Skill Worktree Discipline

The rule every parent skill follows for keeping its working tree in
sync with its tracking branch across a multi-child chain: before each
Phase 2 child invocation, the parent SHALL check whether the upstream
tracking branch has advanced since the chain started, and SHALL
surface a three-option prompt (Rebase / Proceed anyway / Bail) when it
has. The check is parent-agnostic infrastructure: this document
defines the trigger, the prompt shape, the state-file recording
convention for divergence acceptance, and the integration order with
the chain-proposal prompt. Per-parent bindings live in the Binding
Notes section at the end; everything above that section is
substrate-agnostic.

Companion references:

- [`parent-skill-pattern.md`](parent-skill-pattern.md) — the contract surface
  this rule sits inside (Phase 2 child invocation loop, exit-path
  enumeration).
- [`parent-skill-state-schema.md`](parent-skill-state-schema.md) — the
  conditional-field extension discipline the `worktree_divergences:`
  list rides on.

## Trigger Condition

The worktree-staleness check fires **before each Phase 2 child
invocation** — never once per parent invocation. Precisely:

1. After the parent's Phase 1 emits its chain-proposal output and the
   author confirms the proposed chain.
2. Before each child invocation in the confirmed `planned_chain`.

The check therefore runs once per child invocation in the chain. For
a parent with four children in its longest chain, the check fires up
to four times across a single full-run; for a parent with three
children, up to three times. The trigger is bounded by chain step
count, not by wallclock time — a long-running child does not retrigger
the check on its own. The next check fires when the parent moves on
to the next child.

The check itself is two commands against the current branch:

```
git fetch
git status --branch --short
```

If the porcelain output reports the upstream tracking branch is ahead
of the local branch (any non-zero "behind" count), the staleness
condition is met and the prompt below surfaces. Otherwise the parent
proceeds directly to child invocation.

## Three-Option Prompt

When staleness is detected, the parent surfaces a three-option prompt
labeled exactly:

- **Rebase** — bring the worktree forward before invoking the next
  child. The parent emits the commands `git fetch && git rebase` for
  the author and waits for the author's manual approval before running
  them. The parent SHALL NOT auto-rebase: the rebase only runs after
  the author confirms. After a successful rebase, the parent re-runs
  the check (the rebase itself may surface new upstream commits) and
  then proceeds to child invocation.
- **Proceed anyway** — accept the divergence and continue to child
  invocation. The parent SHALL record the divergence event in its
  state file per the Recording section below. The child then runs
  against the diverged worktree.
- **Bail** — terminate the chain at this point. Bail routes per the
  parent's own bail-handling rule. This document does not name the
  bail target inline; it is parent-specific and lives in the parent's
  own SKILL.md (see Binding Notes for the per-parent mapping).

The prompt is presented as a single three-option AskUserQuestion. The
options' labels are stable across parents: "Rebase", "Proceed anyway",
and "Bail". Future parents bind to the same three labels so the
discipline reads identically from the author's perspective regardless
of which chain they are running.

## Recording "Proceed Anyway" Divergence

When the author selects "Proceed anyway", the parent's state file
gains an entry under a conditional list named `worktree_divergences:`.
Each entry has the shape:

```yaml
worktree_divergences:
  - phase: <child-name>
    upstream_ahead_by: <integer>
    accepted_at: <ISO-8601 timestamp>
```

The fields are:

- **`phase`** — the next-child name the parent was about to invoke
  when the divergence was accepted (e.g., the child slot in
  `planned_chain` that the check ran against). The value is the
  child's name, not its index.
- **`upstream_ahead_by`** — the integer commit count by which the
  upstream tracking branch was ahead at the time of acceptance,
  parsed from `git status --branch --short`. Recorded once at
  acceptance time; the parent does not re-poll.
- **`accepted_at`** — ISO-8601 timestamp at which the author selected
  "Proceed anyway".

The list is **conditional** in the sense of the conditional-field
discipline named in `parent-skill-state-schema.md`: the
`worktree_divergences:` key is absent from the state file entirely
when no divergence has been accepted in this chain. The list is
appended to as additional divergence events occur — one entry per
"Proceed anyway" selection, in chronological order. The list never
shrinks within a single chain instance.

The list is a Layer-2 extension over the 5-field minimum schema
(see [`parent-skill-state-schema.md`](parent-skill-state-schema.md)).
It exists so the parent's finalization step can surface divergence
history in the terminal artifact, and so future reviewers can audit
how the chain interacted with upstream change.

## Integration with Chain-Proposal Prompt

The staleness check fires **after** chain-proposal confirmation, not
before. Two checks happen in sequence at the Phase 1 to Phase 2
boundary:

1. The chain-proposal prompt: the parent surfaces the proposed chain
   (which children will run, in what order) and the author confirms,
   revises, or rejects it.
2. The staleness check: only after the author confirms the chain does
   the parent run `git fetch && git status --branch --short` against
   the tracking branch.

The order is load-bearing: `git fetch` adds network latency the
chain-proposal prompt itself does not pay. The current order pays
the cost only when the chain is going to run.

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
rather than reproducing the bail logic here. The body section above
says "the parent's own bail-handling rule" for the same reason —
naming a specific parent's bail rule (such as `/scope` R8) inline
would couple the body to one parent's vocabulary and force a rewrite
when a second parent's bail rule diverges.
