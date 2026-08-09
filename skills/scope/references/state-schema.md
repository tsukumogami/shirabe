# `/scope` State-File Schema

The `/scope` state file lives at `wip/scope_<topic>_state.md` as
YAML-in-`.md` under the `wip-yaml-md` substrate. The schema extends
the pattern's 5-field minimum (`topic`, `last_updated`,
`phase_pointer`, `exit`, `exit_artifacts` — see
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`)
with `/scope`-specific fields. Every conditional field below is
absent from the state file when its triggering condition does not
hold (invariant I-5; see Parent-specific conditional fields in the
state-schema reference).

## Field Enumeration

- **`chain_started`** — ISO-8601 timestamp recorded at Phase 0; used
  for the abandonment-forced marker substitution.
- **`chain_completed`** — ISO-8601 timestamp recorded at Phase 3
  when `exit: full-run` fires.
- **`entry_altitude`** — where the chain starts. Values:
  `brief | prd | design | plan`. Decided once at Phase 1 and
  fixed for the run; the chain invokes every child from this
  altitude through `plan`. Phase 2 re-validates the value against
  the enum before it selects which child receives the topic slug
  and which receive an artifact path.
- **`planned_chain`** — list of child names the chain plans to
  invoke: every child from `entry_altitude` through `plan`, minus
  any held back by re-entry protection (output of Phase 1's
  chain-proposal).
- **`chain_ran`** — list of child names whose invocations
  completed.
- **`chain_skipped`** — list of `{name, reason}` entries for
  children held back by re-entry protection (e.g. `/prd` when an
  Accepted PRD already exists at the canonical path, per the
  Mandatory-with-auto-skip gate from `parent-skill-pattern.md`).
  Phase 1 writes exactly one reason,
  `settled-artifact-at-canonical-path-reentry-protection`; a
  child is never recorded here because the chain judged its
  artifact not worth producing, since `/scope` makes no such
  judgment before an artifact exists. Phase 2 writes one further
  reason when a Reject at a settled-upstream boundary ends the
  chain and the remaining children never run.
- **`consolidation_judgments`** — conditional list. One entry per
  hop at which Phase 2's consolidation judgment ran, appended in
  chain order. Absent when the chain produced fewer than two
  durable artifacts. Each entry records:

  ```yaml
  consolidation_judgments:
    - hop: brief->prd            # <upstream-type>-><downstream-type>
      absorbable: true           # is the required-section mapping total?
      verdict: absorb            # absorb | keep
      carry_check:               # present only when verdict is absorb
        <upstream section>: {target: <downstream section>, carried: <bool>}
      absorbed: docs/briefs/BRIEF-<topic>.md   # present on a completed absorb
      into: docs/prds/PRD-<topic>.md           # present on a completed absorb
      finding: <free text>       # why keep, or which section failed to carry
  ```

  A `keep` entry carries `hop`, `absorbable`, `verdict`, and
  `finding`. An aborted absorb is recorded as `verdict: keep`
  with the carry check that failed, so the abort is auditable
  rather than indistinguishable from a judgment that never
  considered absorbing.
- **`boundary`** — conditional on `exit: re-evaluation`. Values:
  `prd | design`. Discriminates which upstream boundary the
  Decision Record attaches to. Gated per the state-schema
  reference's Parent-specific conditional fields sub-block.
- **`decision_record_sub_shape`** — conditional on
  `exit: re-evaluation`. Values: `re-evaluation | rejection`. The
  second discriminator of the four-combination Decision Record
  matrix; R9 Part 2's multi-discriminator rule requires both
  `boundary:` and `decision_record_sub_shape:` to be set when
  `exit: re-evaluation` fires.
- **`plan_execution_mode`** — conditional on `/plan` appearing in
  `chain_ran`. Values: `single-pr | multi-pr`. Records the
  output-mode selection of the terminal child. Gated per
  state-schema R9 Part 3's chain-membership-gated extension.
- **`referenced_artifact`** — conditional on `exit: re-evaluation`.
  The path of the settled-upstream artifact the Decision Record
  re-evaluates.
- **`discard_commit_sha`** — conditional on a Reject sub-shape
  (`decision_record_sub_shape: rejection` or out-of-chain Reject
  detected via `git log`). Records the commit SHA of the discard
  commit observed on the current branch.
- **`rejection_rationale`** — conditional on `decision_record_sub_shape: rejection`.
  Free-text reason captured from the child's Reject prose.
- **`triggering_child`** — conditional on `exit: abandonment-forced`.
  Values: `brief | prd | design | plan`. Names the most-recently-
  running child per R8's tie-break rule.
- **`partial_phase_reached`** — conditional on `exit: abandonment-forced`.
  Names the phase reached inside the triggering child.
- **`child_snapshots`** — per-child status + content-hash dual-
  check block (one entry per child in `chain_ran`); the
  fingerprint is the git blob hash of the child's durable doc.
  Drift fires when EITHER status or fingerprint changes between
  resumes.
- **`worktree_rebases`** — conditional list. Appended after every
  rebase that brought new upstream commits in, per the worktree-
  discipline reference. Records the post-rebase HEAD SHA and the
  classification enum (`none | informational | intent-changing-resolved-in-place`).
  Absent when no rebases have occurred.
- **`worktree_divergences`** — conditional list. Appended only
  when the worktree-discipline escalation phase produces a
  "proceed against original intent" decision. The list audits
  upstream-divergent points the chain decided to accept rather
  than re-author.
- **`drift_acknowledged`** — conditional list. Appended only
  when the Drift Detection prompt resolves to `Proceed-without`
  (the author kept the original frozen snapshot and proceeded
  against original chain intent despite observed drift). Each
  entry records `{child, original_status, original_content_hash,
  observed_status, observed_content_hash, acknowledged_at}` so a
  future reviewer can audit every intentional divergence. Absent
  when no drift has been acknowledged via `Proceed-without`.
- **`parent_orchestration`** — ephemeral. Present ONLY during in-
  flight child invocation; cleared immediately after the child
  returns. Names the invoking child, the suppress-status-aware-
  prompt boolean, and the rationale (`fresh-chain | revise`) per
  the L13 amendment in `parent-skill-pattern.md`.

Phase 3 copies `chain_ran`, `chain_skipped`, and
`consolidation_judgments` into the run's PR body before Phase 4
removes the state file. The `wip/` copy is scratch; the PR body
is where a reviewer can tell "not produced" from "absorbed into
this other document" after the scratch is gone.

The state file is the externally-visible parent surface children
read at child Phase 0 to consult the `parent_orchestration:`
sentinel; the L13 amendment defines the sentinel as the sole
pattern-level parent-orchestration primitive, so children read it
identically regardless of which parent invoked them.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` —
  5-field minimum, conditional-field gating discipline, R9 hard-
  finalization check spec (Parts 1, 2, 3).
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` — L13
  amendment defining the `parent_orchestration:` sentinel as the
  pattern-level parent-orchestration primitive.
- `skills/scope/references/phases/phase-resume.md` — the drift-
  detection contract that writes `drift_acknowledged:` and the
  per-row Slot 5/6 prompts that read `child_snapshots:`.
