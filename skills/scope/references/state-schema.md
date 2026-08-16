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
  when the chain terminates, on every exit path rather than on
  `full-run` alone. The re-evaluation Decision Record templates
  read it for their filename date, and the abandonment-forced
  marker records it alongside `chain_started`, so scoping it to
  one exit would leave the other two writing a field the schema
  says is absent.
- **`visibility`** — the repo visibility Phase 0 detected from
  CLAUDE.md's `## Repo Visibility:` header. Values: `Public |
  Private`, defaulting to `Private` when the header is absent.
  Phase 2's validator pass-through reads it back for
  `shirabe validate --visibility=<value>`, so it is a recorded
  field rather than a per-phase re-detection.
- **`consumed_upstream`** — conditional path string naming an
  upstream artifact this chain consumed but did not produce: the
  value the author supplied with `--upstream <path>`, canonicalized,
  after it passed every check in
  `skills/scope/references/phases/phase-0-setup.md` (bounds check,
  `ROADMAP-` basename, not under `wip/`, tracked by git, and not a
  private artifact named from a public repo). The value is a
  working-tree-relative path, or an `owner/repo:path` cross-repo
  reference. Required iff the invocation supplied `--upstream` and
  the value passed validation; absent otherwise — including when
  the value was dropped by the visibility check, which is
  deliberately indistinguishable from no flag at all, since
  recording a private path in a public repo's state file would leak
  it onto the pushed feature branch. Written at Phase 0 rather than
  at finalization, because its trigger fires at invocation or
  never. Read at Phase 2, where it becomes the `--upstream`
  argument `/scope` hands `/brief`, and re-validated by the resume
  ladder on every re-entry.
- **`planned_chain`** — list of child names the chain plans to
  invoke: the whole tactical chain (`brief`, `prd`, `design`,
  `plan`) in order, on every run. A child held back by re-entry
  protection stays here and is also recorded in `chain_skipped`,
  because the plan was to run it; `chain_ran` is what separates the
  two afterwards. There is no field recording where the chain
  starts, because it always starts at `brief`.
- **`chain_ran`** — list of children whose invocations completed,
  each with the timestamp its invocation began:

  ```yaml
  chain_ran:
    - name: brief              # brief | prd | design | plan
      started_at: <ISO-8601 timestamp>
  ```

  Written by Phase 2's child-invocation loop, in the same step that
  captures the child snapshot. That is the field's only write site,
  and until this change it had none — the field was specified here
  and read in four places by Phase 3 (R9 Part 3's chain-membership
  gate, the PR-body record, the R8 tie-break, and
  `plan_execution_mode:`'s presence condition) while nothing
  appended to it.

  `started_at` is not decoration. Phase 3's R8 tie-break already
  resolves the most-recently-running child from these timestamps,
  a claim this schema previously contradicted by declaring a bare
  name list.

  Entry names are re-validated against `{brief, prd, design, plan}`
  before use, because the consolidation judgment's firing condition
  reads this field. That promotes it from bookkeeping to a gate on
  a destructive operation, and a tampered entry would otherwise put
  a document this run did not produce on the deletion path.
- **`chain_skipped`** — list of `{child, reason}` entries for
  children that were planned and did not run (e.g. `/prd` when an
  Accepted PRD already exists at the canonical path, per the
  Mandatory-with-auto-skip gate from `parent-skill-pattern.md`).
  `child` is the pattern-level entry key, shared with `/charter`;
  `reason` is drawn from the closed vocabulary in
  `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  (Chain-tracking). `/scope` writes three of its four members:
  `settled-artifact-at-canonical-path-reentry-protection` from
  Phase 1, and `prd-boundary-rejection` or
  `design-boundary-rejection` from Phase 2, when a Reject at a
  settled-upstream boundary ends the chain and the children below
  the boundary never run. A child is never recorded here because
  the chain judged its artifact not worth producing, since `/scope`
  makes no such judgment before an artifact exists, and the closed
  vocabulary is what makes that checkable rather than asserted.
- **`consolidation_judgments`** — conditional list. One entry per
  hop at which Phase 2's consolidation judgment ran, appended in
  chain order. Absent when the chain produced fewer than two
  durable artifacts. Each entry records:

  ```yaml
  consolidation_judgments:
    - hop: brief->prd            # <upstream-type>-><downstream-type>
      stage: carry               # preflight | judgment | carry
      verdict: absorb            # absorb | keep
      carry_check:               # present only when verdict is absorb
        <upstream section>: {target: <downstream section>, carried: <bool>}
      absorbed: docs/briefs/BRIEF-<topic>.md   # present on a completed absorb
      into: docs/prds/PRD-<topic>.md           # present on a completed absorb
      finding: <free text>       # why keep, or which section failed to carry
      reverted: true             # present only when a completed absorb was rolled back
  ```

  A `keep` entry carries `hop`, `stage`, `verdict`, and `finding`.
  An aborted absorb is recorded as `verdict: keep` with the carry
  check that failed, so the abort is auditable rather than
  indistinguishable from a judgment that never considered
  absorbing.

  `stage:` names where the verdict settled: `preflight` when the
  citation guard refused, `judgment` when the content question
  reached `keep`, `carry` when the carry check decided. It replaces
  a boolean `absorbable:` that asked whether the required-section
  mapping was total — the type-level question the judgment no
  longer asks, and which under the current rule would be `true` at
  every hop it could ever be written. The replacement is strictly
  more informative: it answers the question a reader of the PR body
  actually has, which is *why* this hop landed where it did.

  Retiring it costs no migration. The absorb procedure has never
  completed a run in this repository — no BRIEF has ever been
  deleted — so there are no entries on disk carrying the old field.

  `reverted:` marks an absorb that completed and was then rolled
  back by the post-absorb re-validation. It is not a third verdict:
  the verdict is `keep`, because nothing was ultimately removed. The
  flag exists so a reverted fold is distinguishable from one that
  aborted before mutating, which is a different and much less
  interesting event.
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
  `chain_ran`. Values: `single-pr | multi-pr | coordinated`.
  Records the output-mode selection of the terminal child.
  `coordinated` is the multi-repo generalization of `multi-pr`
  and is the value a coordinated chain records; the Plan format
  profile recognizes all three
  (`crates/shirabe-validate/src/formats.rs`). Gated per
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
  Names how far the chain got before it stopped. The value is
  `/scope`'s own loop position for the triggering child — which of
  the eight Phase 2 steps had completed when the bail fired — NOT
  a phase read out of the child's internals. Reading the child's
  internal phase would breach the R14 isolation rule, which limits
  `/scope` to the child's durable artifact status and content
  hash, so the field records what the parent observed rather than
  what the child was doing.
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
