---
status: Accepted
decision: |
  When behind main, catch up by merging origin/main into the branch, never
  rebasing, and push without force, in both work-on and execute. Every place
  the inventory names as rebase text becomes merge text, including
  worktree-discipline.md and scope's phase-2 rebase section. Any gate that
  means 'rebased' (execute's worktree_sync, rebased_on_main) must test ancestry
  (origin/main is an ancestor of HEAD); any gate or script asserting linear
  history or no merge commits changes in the same item.
rationale: |
  The skills disagreed about what happens when a branch falls behind main.
  /work-on's phase-6 reference said to rebase and push with --force-with-lease,
  while /work-on's template pushes plainly, /execute says nothing it runs
  force-pushes, and push-and-record.sh refuses a force push. Merging main in
  keeps a branch current without rewriting history, so the no-force rule holds
  for both callers, no shared branch several children commit to gets rewritten,
  and a plain push is always enough. Gates that stood for "rebased" have to
  mean "current with main" instead, which ancestry tests directly.
---

# DECISION: catch up with main by merging, never force-push

## Status

Accepted on 2026-09-28. The policy owner answered this item of the
contradiction-settlement inventory (coordination PR shirabe#507).

## Context

This is the `force-push-after-rebase` item: force-push after a rebase. It
touches /work-on and /execute's single-PR runs.

`skills/work-on/references/phases/phase-6-pr.md`, which /work-on loads at
`pr_creation` and /execute loads at every `ci_monitor` visit, tells the agent
to rebase on latest main when behind and, after a rebase, push with
`--force-with-lease`. The rest of the tree says otherwise:

- `skills/work-on/koto-templates/work-on.md`'s `pr_creation` pushes with a
  plain `git push -u origin {{BRANCH}}`.
- `skills/execute/SKILL.md` says every push goes through
  `scripts/push-and-record.sh`, and that script pushes an explicit refspec
  and never with a force option.
- `skills/work-on/references/finishing-obligations.md` treats rebase currency
  beyond mergeability as deliberately advisory.
- `pre_pr_evidence` in `work-on.md` assumes history is final before it runs;
  a later rebase leaves what it checked unverified.

An agent following phase-6 either gets a rejected push under /execute or
rewrites a shared branch. Under /work-on, a rebase after `pre_pr_evidence`
means the gate judged a tip that no longer ships.

## Decision

When behind main, catch up by merging origin/main into the branch, never
rebasing, and push without force, in both work-on and execute. Every place
the inventory names as rebase text becomes merge text, including
worktree-discipline.md and scope's phase-2 rebase section. Any gate that
means 'rebased' (execute's worktree_sync, rebased_on_main) must test ancestry
(origin/main is an ancestor of HEAD); any gate or script asserting linear
history or no merge commits changes in the same item.

## Implementation notes

These notes are not part of the decision.

- This is a new option. The DESIGN listed three: never rebase at PR time and
  never force-push (option 1), rebase if behind before verification with a
  plain push only (option 2, the recommendation), and allow
  `--force-with-lease` inside `push-and-record.sh` (option 3). The answer
  shares option 1's no-rebase, no-force rule and option 2's catching up with
  main, and does the catching up by merge.
- The inventory's rebase text spans `skills/work-on/`, `skills/execute/`,
  `references/worktree-discipline.md` and /scope's Phase 2 rebase section, so
  the change lands in the work-on, execute and scope pull requests of the
  contradiction-settlement PLAN.
- An ancestry test is `git merge-base --is-ancestor origin/main HEAD`.

## Options Considered

- **Option 1: Never rebase at PR time and never force-push.** Matches the code
  today, but a branch that falls behind main stays behind until a person
  merges main in.
- **Option 2: Rebase if behind, before verification, with a plain push only.**
  Keeps the no-force rule for both callers, but still rewrites the branch's
  history before the push.
- **Option 3: Allow `--force-with-lease` inside `push-and-record.sh`, leased on
  `expected_head`.** Keeps rebase-then-push working but rewrites history on a
  branch several children commit to.
- **Chosen: merge origin/main in, never rebase, plain push.**

## Consequences

Until this record merges, the statements it governs stay as they are. After
it merges, the skill changes that apply it replace every rebase instruction
the inventory lists with a merge, and every "rebased" gate with an ancestry
test. Branches carry merge commits from main; any check that asserted linear
history changes with them.

## References

- shirabe#507 (the contradiction-settlement DESIGN, PLAN and inventory)
- `skills/work-on/references/phases/phase-6-pr.md`
- `skills/execute/scripts/push-and-record.sh`
- `references/worktree-discipline.md`
