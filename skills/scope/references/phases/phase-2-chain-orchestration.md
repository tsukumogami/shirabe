# Phase 2 — Child Invocation Loop

Phase 2 walks `planned_chain:` from Phase 1, invoking each
child in order. Before each invocation, Phase 2 runs the
worktree-staleness check from the canonical worktree-discipline
reference; immediately around the invocation, Phase 2 writes
and clears the `parent_orchestration:` sentinel; after each
invocation Phase 2 runs the R20 structural file-existence check,
captures the child snapshot, and routes through the validator
pass-through. Phase-N Reject from `/prd` or `/design` is
observed via `git log` against the discard commit.

## Per-Child Invocation Loop Ordering

For each child name in `planned_chain:` in order, Phase 2 runs
seven steps in sequence:

1. **Worktree-staleness check.** Run the three-phase flow
   (Rebase phase → Impact-analysis phase → Escalation phase)
   from
   `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md`.
2. **`parent_orchestration:` sentinel write.** Write the block
   to the state file immediately before invoking the child.
3. **Child invocation.** Invoke the child via its existing
   input mode (topic-slug argument).
4. **R20 structural file-existence check.** Confirm the child's
   canonical durable artifact exists after the child returns.
5. **`parent_orchestration:` cleanup.** Remove the sentinel
   block from the state file (regardless of child outcome).
6. **Child-snapshot capture.** Record the child's status +
   content-hash dual-check pair in `child_snapshots:`.
7. **Validator pass-through.** Run `shirabe validate` against
   the new intermediate; failed validation halts the chain.

The seven-step ordering is the contract. Steps that depend on
the state file (write/clear of `parent_orchestration:`, child-
snapshot capture) bracket the child invocation in a way that
keeps the sentinel ephemeral: present ONLY while a child is in
flight; cleared the moment the child returns.

## Worktree-Staleness Check Before Each Child Invocation

The check runs the three-phase flow defined in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md`:

- **Rebase phase.** Execute the equivalent of `git fetch && git
  rebase origin/<tracking-branch>`. Clean rebase proceeds to
  Impact-analysis with the list of upstream commits that
  landed. Conflicted rebase invokes the conflict-resolution
  sub-agent (or the parent itself in solo mode), resolving from
  artifact context where the chain's BRIEF / PRD / DESIGN
  citations make the correct resolution obvious; unresolved
  conflicts proceed to Impact-analysis carrying the unresolved
  diff for classification.
- **Impact-analysis phase.** Cross-reference the upstream
  commits against the chain's authored artifacts and the next
  child's expected inputs. Classify impact at one of three
  levels: `None` (changes touch no path, symbol, or contract
  the chain depends on), `Informational` (chain-referenced
  content was touched non-substantively — typo fix, comment
  addition, whitespace change), or `Intent-changing` (a
  contract, interface, or fact the chain has committed to was
  altered — child input format changed; cited file renamed or
  removed; doc cite no longer supports the chain's claim;
  expected recipe withdrawn).
- **Escalation phase.** None / Informational proceeds silently;
  the rebase is recorded in `worktree_rebases:` and Phase 2
  advances to step 2 (sentinel write). Intent-changing halts and
  routes to the team lead for an intent judgment. The team
  lead decides whether the original session intent still holds:
  yes routes to in-place resolution (update the affected
  citation or claim, then proceed; classification recorded as
  `intent-changing-resolved-in-place`); no escalates to the
  author with a three-option prompt (re-author affected
  artifacts; proceed against original intent — recorded in
  `worktree_divergences:`; bail per R8's bail-handling rule).

The check's recording fields follow the canonical schema:

```yaml
worktree_rebases:
  - phase: <next-child-name>
    upstream_commits: [<sha>, <sha>, ...]
    impact: none | informational | intent-changing-resolved-in-place
    rebased_at: <ISO-8601 timestamp>
    notes: <optional — e.g., which citation was updated>
```

```yaml
worktree_divergences:
  - phase: <next-child-name>
    affected_contracts: [<artifact + cite>, ...]
    upstream_commits: [<sha>, <sha>, ...]
    accepted_at: <ISO-8601 timestamp>
```

`worktree_divergences:` is the audit list — appended only when
the team lead escalated and the author chose "proceed against
original intent." It is absent in the common case per I-5.

Author-supplied prose (e.g., the team-lead's note about an
in-place resolution, or the author's reason for choosing to
proceed against original intent) is committed via the
`git commit -F` discipline documented in Phase 3, never
interpolated into `git commit -m "..."`.

## `parent_orchestration:` Sentinel Write

Immediately before invoking the child, Phase 2 writes the
sentinel block to the state file:

```yaml
parent_orchestration:
  invoking_child: brief | prd | design | plan
  suppress_status_aware_prompt: true
  rationale: fresh-chain | revise
```

The `invoking_child:` field names the child Phase 2 is about to
invoke; the `rationale:` field carries the upfront decision
about whether the run is a fresh chain or a revision (read by
the child to route its own Slot 2 behavior).

## Child Invocation

Phase 2 invokes the child via the child's existing input mode:
`/<child-name> <topic-slug>`. R14 child-isolation is preserved
— `/scope` reads only the child's durable artifact's
frontmatter `status:` value plus the artifact's git blob hash;
`/scope` does NOT extend the child's `$ARGUMENTS` parser, does
NOT add env-var consumption, does NOT add flags or arguments per
the L13 amendment in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`. The
sentinel is the pattern-level convention every child reads
identically; the child's input surface is untouched.

## R20 Structural File-Existence Check

After the child returns, Phase 2 confirms the child's canonical
durable artifact exists at:

- `docs/briefs/BRIEF-<topic>.md` for `/brief`.
- `docs/prds/PRD-<topic>.md` for `/prd`.
- `docs/designs/DESIGN-<topic>.md` for `/design`.
- `docs/plans/PLAN-<topic>.md` for `/plan`.

When the artifact is present, Phase 2 proceeds to sentinel
cleanup and snapshot capture. When the artifact is absent —
PASS-with-no-artifact (the child reported success but the
canonical durable file does not exist on disk) — the outcome
is mapped to STALE and routed via R8's bail-handling using the
most-recently-running tie-break to resolve `triggering_child:`.

The structural check closes a class of silent failure where a
child reports success but does not actually write its terminal
artifact. R20's surface is the canonical path test, not a
content read.

## `parent_orchestration:` Cleanup

Phase 2 removes the entire `parent_orchestration:` block from
the state file immediately after the child returns —
regardless of the child's outcome (PASS / Reject via discard
commit / STALE). The block is ephemeral within a chain
instance; it MUST NOT persist into the next loop iteration or
into any post-chain state.

The cleanup is unconditional and silent. No prompt fires, no
warning surfaces. The sentinel's job is done the moment the
child returns.

## Child-Snapshot Capture

For each child that completed (the durable artifact exists
post-R20), Phase 2 records a snapshot in `child_snapshots:`:

```yaml
child_snapshots:
  <child>:
    status: <frontmatter-status>
    content_hash: <git-blob-hash>
    captured_at: <ISO-8601 timestamp>
```

The pair (status + content-hash) is the dual-check the resume
ladder consults on subsequent re-entries to detect drift between
the snapshot and the current artifact. Per Decision 5, the
snapshot stays frozen on a re-evaluation Decision Record write
— the existing upstream is the comparison point, not the
Decision Record's own path.

## Phase-N Reject Handling

When `/prd` Phase 4 Reject or `/design` Phase 6 Reject fires
in-chain, the child returns control to `/scope` after producing
a discard commit (per Component 7.7). The discard commit's
shape is canonical:

- `docs(prd): discard PRD draft for <topic>` for `/prd` Phase 4
  Reject.
- `docs(design): discard DESIGN draft for <topic>` for
  `/design` Phase 6 Reject.

The implementation pattern at the chain level:

1. Before each in-chain `/prd` or `/design` invocation, Phase 2
   records the current branch's HEAD SHA as `pre_invocation_sha`.
2. After the child returns, Phase 2 reads
   `git log <pre_invocation_sha>..HEAD` for any discard commit (a
   commit whose message conforms to the Reject contract shapes
   above). The commit's SHA is captured into
   `discard_commit_sha:` and the commit body's rejection-rationale
   prose is captured into `rejection_rationale:` in the state
   file.
3. If a discard commit is observed, Phase 2 SHALL advance the
   state file with:

```yaml
exit: re-evaluation
boundary: prd | design          # gated by which child rejected
decision_record_sub_shape: rejection
discard_commit_sha: <sha>
rejection_rationale: <free-text from commit body>
```

The R20 structural file-existence check post-Reject confirms
the durable artifact was removed (the discard commit's intent
was to delete the Draft from disk); the absence is expected,
not a STALE condition.

### In-Chain vs Out-of-Chain Reject

The `git log`-based observability mechanism preserves R13
manual-fallback parity: the discard commit is the durable signal
regardless of in-chain or out-of-chain invocation, so a child
that Rejects without `/scope` orchestrating still leaves a
re-grepable trace. The asymmetry is solely whether a Decision
Record gets written.

- **In-chain Reject** — `/prd` Phase 4 Reject or `/design`
  Phase 6 Reject fired while `/scope`'s `parent_orchestration:`
  sentinel was present. `/scope` writes a rejection-sub-shape
  Decision Record at
  `docs/decisions/DECISION-{prd|design}-<topic>-rejection-<YYYY-MM-DD>.md`
  immediately, observing the discard commit via the `git log
  <pre_invocation_sha>..HEAD` mechanism above.
- **Out-of-chain Reject** — `/prd` or `/design` Reject fired
  outside any `/scope` invocation. The discard commit is the
  durable trace; no retroactive Decision Record is written on a
  later `/scope` resume. A later `/scope` invocation against the
  same topic detects the discard commit but treats it as
  external context — manual-fallback parity preserves the
  contract that `/scope` does not modify state for runs it did
  not orchestrate.

The discard-commit observability mechanism is the same in both
cases — `git log` reads commit metadata regardless of who
invoked the child — so the manual-fallback parity is
mechanically symmetric.

## Validator Pass-Through

After the structural check passes, Phase 2 runs
`shirabe validate --visibility=<repo-visibility>` against the
new intermediate. The `<repo-visibility>` value is the one
detected in Phase 0 from CLAUDE.md's `## Repo Visibility:`
header (default Private if absent).

The validator runs the `shirabe` binary at `cmd/shirabe/` —
the same binary humans invoke for ad-hoc validation. A passing
validator clears the iteration; the loop advances to the next
child in `planned_chain:`. A failing validator halts the chain
immediately and routes to R8's bail-handling.

`/scope` does NOT auto-fix validator failures. The author is
the validator-failure resolver; the chain remains halted until
the author addresses the failure (typically by re-running the
child with corrections, or by re-invoking `/scope` from the
beginning with a re-framed topic).

## Per-Child Gates from `planned_chain:`, Not Re-Walked

Phase 2 reads `planned_chain:` from the state file (populated
by Phase 1) and invokes the listed children in order. The
per-child gate-evaluation rules (`/brief` R4 EITHER-signal,
`/prd` R5 Mandatory-with-auto-skip, `/design` R6/R7 shape-
dependent, `/plan` ALWAYS) are NOT re-walked at Phase 2 — they
are cached in Phase 1's verdicts. The state-file fields driving
the cache:

- `planned_chain:` — children whose gates fired in Phase 1.
- `chain_skipped:` — children whose gates auto-skipped in
  Phase 1 (e.g., `/prd` skipped against an Accepted PRD).
- `child_snapshots:` — initial snapshots of pre-existing
  durable artifacts Phase 1 discovered.

Phase 2's job is iterative invocation against the cached
chain shape, not re-evaluation of the gate decisions.

## State-File Enum Re-Validation Before Path Interpolation

Before constructing any write path that interpolates a state-
file field (Decision Record path on Reject; force-
materialization path on STALE; `wip/` removal paths on chain
finalization), Phase 2 re-validates the field's value against
its declared enum:

- `boundary:` against `{prd, design}`.
- `decision_record_sub_shape:` against
  `{re-evaluation, rejection}`.
- `triggering_child:` against `{brief, prd, design, plan}`.
- `plan_execution_mode:` against `{single-pr, multi-pr}`.

Out-of-enum values fail the operation and route to R8 bail-
handling. The re-validation closes the state-file-tampering
surface where an attacker would otherwise inject a shell
metacharacter into a field that later becomes a path component.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  Gate Vocabulary; L13 amendment defining the
  `parent_orchestration:` sentinel as the pattern-level parent-
  orchestration primitive; semantic invariant I-7 (Team-Lead
  Operating Discipline) for the child-invocation task class
  (120s window, 10-cycle patience budget).
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-worktree-discipline.md`
  — the three-phase Rebase / Impact-analysis / Escalation flow
  the per-child loop runs before each invocation, the
  `worktree_rebases:` and `worktree_divergences:` recording
  schema.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`
  — R14 widened isolation rule and the per-parent inspection
  surface table.
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — `child_snapshots:`, `parent_orchestration:`,
  `chain_ran:` semantics consumed by this phase.
