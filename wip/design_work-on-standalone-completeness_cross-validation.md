# Phase 3 cross-validation

Five decisions were researched independently. Four of their recommendations
interact. None conflicts outright; three compose cleanly once stated, and one
imposes an ordering.

## 1. Two conditions guard the cascade, and they compose

Decision 2 puts anchor detection in a `command` gate immediately before the
cascade-invoking state. Decision 4 puts the root/child answer in a
`session_role` evidence field on `ci_monitor`, branching into the cascade state
versus straight to `done`. Neither researcher saw the other's recommendation, so
the composition needs stating rather than assuming.

They compose in one order and not the other. `ci_monitor` decides role first: a
child routes straight to `done` and never evaluates the anchor gate at all. A
root routes toward the cascade-entry state, whose gate then searches for an
anchor and routes past the cascade when there is none.

Doing it in that order has a property worth keeping deliberately: a child never
pays for the `docs/plans/` search, because it never reaches the gate that runs
it. Reversing the order would search on every child run and then discard the
answer.

## 2. Both Decision 3 and Decision 4 edit `ci_monitor`

Decision 3 adds a `merge_state_clean` command gate copied from `execute.md`;
Decision 4 adds a `session_role` evidence field and a branching transition. One
coherent edit to one state, not two independent ones.

One constraint binds the gate half: `validate-template-mermaid.sh` check 4
requires a gate name used by more than one template to carry the same command in
all of them, so the merge-cleanliness gate is copied **verbatim** rather than
adapted. The evidence field is not a gate and is not subject to check 4, so
adding `session_role` to `work-on.md`'s `ci_monitor` without a matching field in
`execute.md` is legal.

## 3. The second pull request depends on the first, beyond mere ordering

Decision 1 relocates `run-cascade.sh` under `skills/work-on/scripts/` in the
first pull request. Decision 5's third execution path adds an end-of-run cascade
trigger for multi-pr — new behaviour, since none exists today — which invokes
that script.

So the dependency is not just "completeness first because the migration rewrites
the routing rules". The migration's new cascade trigger must reference the
relocated path, which exists only after the first PR lands. Stated here because
an implementer reading only the ordering rationale would think the sequence was
a convenience.

## 4. Decision 3 gates two obligations the PRD treated as optional, and that is
R6 rather than scope creep

The PRD's R9 offered a choice for the design-diagram obligation: bring it within
one reference-hop with an evidence field, or record it as advisory. Decision 3
gates it, and gates summary-shape too, on the ground that both are objectively
checkable.

That is not an expansion of scope. R6 requires that every obligation resolving
to a fact observable from `gh` or `git` be gate-enforced rather than stated as
prose. If those two are checkable, R6 already obliged gating them, and the
research establishing that they are checkable is what closes R9's choice. The
design records it as R6 applied, not as a discretionary upgrade.

## 5. What none of the five researchers knew

Two constraints arrived from the coordinator after the researchers were
dispatched, and neither is reflected in their reports:

- **The cascade's own steps can report `ok` having changed nothing**, and the
  post-cascade verification reads the working tree rather than the commit
  (VERIFIED at `run-cascade.sh:377-381`, `:1093-1100`). So the cascade state's
  evidence must be the observed post-state, with the commit half read from the
  commit's own paths.
- **Retention changes resume semantics**, and the cascade states are
  terminal-adjacent, so a retained session that reached them must not be treated
  as resumable-from-where-it-stopped.

Both land on the cascade state Decision 2 and Decision 4 route into. They are
folded into the Decision Outcome rather than back into the individual reports,
which stand as the record of what was weighed at the time.

## Assumption carried forward

Decision 4's recommendation rests on a described shape rather than code:
`session-role.sh` is not on this branch. Its mechanical argument holds under any
shape the landing fix takes, but the design records this as an assumption with
an escalation rather than as settled.
