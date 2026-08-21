# Phase 3 — Exit Finalization

Phase 3 lands the chain at one of three terminal exit paths and
runs the R9 hard-finalization check. Every chain that produces a
terminal artifact ends here; a bail taken before any child ran
ends at the clean cancel below instead, which finalizes nothing.
Phase 3's contracts cover the three exit-path bindings, the R8
bail route and its tie-break for `triggering_child:` on
abandonment-forced, the clean cancel and its one deletion, the
HTML-comment marker placement for force-materialized partials,
the `git commit -F` discipline for author-supplied prose
written into commits, the public-history disclaimer for in-
chain Reject, and the closed write-target set Phase 3 may
touch.

## Table of Contents

- [Three Exit Paths](#three-exit-paths)
  - [Full-Run Exit](#full-run-exit)
  - [Re-Evaluation Exit](#re-evaluation-exit)
  - [Abandonment-Forced Exit](#abandonment-forced-exit)
- [R8 Bail Route](#r8-bail-route)
  - [R8 Tie-Break for `triggering_child:`](#r8-tie-break-for-triggering_child)
  - [Clean Cancel](#clean-cancel)
- [HTML-Comment Marker](#html-comment-marker)
- [R9 Hard-Finalization Check](#r9-hard-finalization-check)
- [`git commit -F` Discipline](#git-commit--f-discipline)
- [Public-History Disclaimer](#public-history-disclaimer)
- [Closed Write-Target Set](#closed-write-target-set)
- [State-File Enum Re-Validation Before Path Interpolation](#state-file-enum-re-validation-before-path-interpolation)
- [References](#references)

## Three Exit Paths

The `exit:` field at finalization SHALL be one of three values
from
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`'s
Three Exit Paths section: `full-run`, `re-evaluation`, or
`abandonment-forced`. UNSET, null, or out-of-enum values fail
the R9 hard-finalization check (see below).

### Full-Run Exit

The chain completed through `/plan`. The PLAN already lives at
`docs/plans/PLAN-<topic>.md` (Draft when `plan_execution_mode:
single-pr`; Active when `plan_execution_mode: multi-pr` or
`coordinated`, with an accompanying GitHub milestone created by
`/plan`). Phase 3 populates the state file with:

```yaml
exit: full-run
chain_completed: <ISO-8601 timestamp>
plan_execution_mode: single-pr | multi-pr | coordinated
exit_artifacts:
  - path: docs/plans/PLAN-<topic>.md
    status: Draft | Active
```

`exit_artifacts:` lists every durable artifact the run leaves
behind, not only the PLAN: a chain that produced a BRIEF, a PRD,
and a DESIGN records all three alongside it, and one whose BRIEF
was absorbed records the surviving PRD without it.

`plan_execution_mode:` is gated by `/plan` appearing in
`chain_ran:` per R9 Part 3's chain-membership-gated extension
in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`.

#### Durable record of what the chain produced

Phase 4 removes the state file, so the record of which artifacts
were produced and which were absorbed has to leave `wip/` before
then. Phase 3 writes it into the run's pull-request body: every
artifact in `chain_ran:`, every entry in `chain_skipped:` with its
`child` and its vocabulary `reason`, and every entry in
`consolidation_judgments:` with its verdict, its finding, and —
on a completed absorb — what was absorbed into what.

Without it, a reviewer reading the PR cannot tell an artifact that
was absorbed from one that was never produced. The two look
identical on disk and mean opposite things.

**`consumed_upstream:` goes into that record too, whenever the run
had one.** The roadmap a chain consumed is recorded on the PLAN the
chain produces, and a run that ends before `/plan` has no PLAN and
therefore no legal node to carry it — no durable artifact may name a
working one. On a `re-evaluation` or `abandonment-forced` exit the
roadmap would otherwise be lost with the state file, leaving no trace
of what the chain was scoping under. Name it in the PR body:

> Consumed upstream: `docs/roadmaps/ROADMAP-<name>.md`. Not recorded in
> any produced artifact — the chain ended before its PLAN, and a
> ROADMAP is only ever named by the PLAN.

### Re-Evaluation Exit

The chain ended at a settled-upstream boundary. Phase 3 writes
a Decision Record at the canonical Interface I.2 path:

```
docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md
```

The four boundary × sub-shape combinations bind to the four
templates from
`skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md`:

- `boundary: prd; decision_record_sub_shape: re-evaluation` →
  `skills/scope/references/decision-record-prd-re-evaluation.md`.
- `boundary: prd; decision_record_sub_shape: rejection` →
  `skills/scope/references/decision-record-prd-rejection.md`.
- `boundary: design; decision_record_sub_shape: re-evaluation`
  → `skills/scope/references/decision-record-design-re-evaluation.md`.
- `boundary: design; decision_record_sub_shape: rejection` →
  `skills/scope/references/decision-record-design-rejection.md`.

State file at re-evaluation exit:

```yaml
exit: re-evaluation
boundary: prd | design
decision_record_sub_shape: re-evaluation | rejection
referenced_artifact: <path to the settled-upstream artifact>
chain_completed: <ISO-8601 timestamp>
exit_artifacts:
  - path: docs/decisions/DECISION-...-<YYYY-MM-DD>.md
    status: Accepted
```

On `decision_record_sub_shape: rejection`, the Decision Record
body references the discard commit SHA (substituted from
`discard_commit_sha:` captured in Phase 2) and the author-
supplied rationale (substituted from `rejection_rationale:`).
The Decision Record itself is committed via `git commit -F`
per the discipline below; the rejection rationale and any
other author-supplied prose are passed through stdin or a
tempfile, never interpolated into the commit message via
`git commit -m`.

### Abandonment-Forced Exit

The chain cannot complete the planned terminal artifact. Phase
3 force-materializes the most-recently-running child's
intermediate as a Draft artifact at its canonical durable path
(`docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`,
`docs/designs/DESIGN-<topic>.md`, or
`docs/plans/PLAN-<topic>.md`) and appends the HTML-comment
marker to the END of the artifact's Status section.

State file at abandonment-forced exit:

```yaml
exit: abandonment-forced
triggering_child: brief | prd | design | plan
partial_phase_reached: <the parent's own Phase 2 loop position>
chain_completed: <ISO-8601 timestamp>
exit_artifacts:
  - path: docs/{briefs|prds|designs|plans}/<TYPE>-<topic>.md
    status: Draft
```

## R8 Bail Route

A bail routes on what a child produced. The abandonment-forced
branch is taken when a child intermediate under
`wip/{brief,prd,design,plan}_<topic>_*` or research scratch under
`wip/research/{prd,design}_<topic>_*` exists for the topic;
otherwise the bail is a clean cancel.

Nothing under the parent's own `wip/scope_<topic>_*` prefix counts
toward the abandonment-forced branch, because nothing under that
prefix is a child's output. The test is stated that way rather than
as an exclusion of the state file, so a later file under the same
prefix inherits it: `wip/scope_<topic>_handoff.md` is no more a
child's output than the state file is, and an exclusion naming only
the state file would route a bail on it. `/charter`'s bail step
already tests this way.

### R8 Tie-Break for `triggering_child:`

When more than one child has an unfinished `wip/` intermediate
at the moment of abandonment, the `triggering_child:` field is
set to the child whose Phase 2 invocation began most recently.
The most-recently-running rule reads from the state file's
per-child Phase 2 start timestamps (recorded as the child's
entry in `chain_ran:` includes a started-at timestamp).

The tie-break is deterministic: the most-recent timestamp
wins; ties (timestamps identical at second resolution) are
broken by the child name's order in `planned_chain:` (later in
the chain wins). No author prompt fires; the tie-break is
fully mechanical.

The tie-break runs only where an abandonment-forced exit is
already the outcome — the route above, or a Force-materialize
selected at the resume ladder's stale-session row. A bail with no
child intermediate and no research scratch takes the clean cancel
instead and never names a `triggering_child:` at all.

### Clean Cancel

A bail at Phase 1 is the canonical case: Phase 0 wrote the state
file before returning control, no child has been invoked, and
nothing under `wip/scope_<topic>_*` is a child's output. The bail
is a clean cancel, which means:

- **No terminal artifact.** Nothing is force-materialized, because
  nothing exists to materialize. Abandonment-forced exists to
  preserve a partial artifact; at Phase 1 there is none.
- **No `exit:` value and no `triggering_child:`.** The run records
  neither. There is no chain progress to record.
- **One deletion.** The bail handler removes
  `wip/scope_<topic>_state.md`. Phase 4 does not run on a cancel,
  which is why the disposal is the handler's rather than Phase 4's.

The deletion is one path, not the prefix, and the inverse of the
route test above: the test ignores the whole `wip/scope_<topic>_*`
prefix, the deletion touches a single file inside it.
`wip/scope_<topic>_handoff.md` is NOT removed by a bail — it
belongs to the router rather than to the parent, and leaving it is
what lets a later invocation resume against it instead of starting
cold.

**R9 does not fire.** The check runs at finalization against a
recorded exit, and a clean cancel finalizes nothing: it records no
exit, so it never reaches the check and never trips condition 2's
empty-`exit_artifacts:` refusal. That is not a hole in the
three-exits invariant. The invariant binds every run that produces
a terminal artifact, and a clean cancel produces none — tearing
down the empty state file is the whole of what it leaves behind.

## HTML-Comment Marker

The abandonment-forced exit appends the uniform single-line
HTML-comment marker to the END of the force-materialized
artifact's existing Status section. The literal marker text:

```
<!-- scope-status-block: abandonment-forced; triggering-child: <name>; partial-phase-reached: <phase>; chain-started: <ISO-8601 timestamp> -->
```

Four contract rules bind the marker:

- **(a) Placement.** END of the artifact's existing Status
  section. Phase 3 does NOT add a new required section to host
  the marker; the artifact's existing structure is preserved.
- **(b) Whitespace and field order significance.** The marker
  is a single line. Whitespace inside is significant. The four
  field-value pairs appear in the order shown:
  `triggering-child` → `partial-phase-reached` → `chain-started`.
  The lead identifier `scope-status-block:` precedes them.
- **(c) Substitution sources.** The four `<...>` substitutions
  come from the state file: `<name>` from `triggering_child:`,
  `<phase>` from `partial_phase_reached:`, `<ISO-8601 timestamp>`
  from `chain_started:`.
- **(d) Enum constraint on `<name>`.** `<name>` MUST be one of
  `brief | prd | design | plan`, resolved by R8's tie-break.

The marker uniformly applies to all four artifact types
without per-child variation. The grep-checkable literal
substring downstream consumers assert against is
`scope-status-block: abandonment-forced`.

## R9 Hard-Finalization Check

R9 fires at Phase 3 termination against a run that finalized. A
clean cancel does not reach it — see Clean Cancel above — so the
`exit:` a cancelled run never sets is not a condition-1 violation.
The check refuses finalization if any of the following conditions
hold:

1. **`exit:` UNSET or out-of-enum.** The field is empty, null,
   or carries a value outside `{full-run, re-evaluation,
   abandonment-forced}`.
2. **`exit_artifacts:` empty when exit requires artifacts.**
   `full-run`, `re-evaluation`, and `abandonment-forced` all
   require at least one entry in `exit_artifacts:`. An empty
   list at finalization fails.
3. **Conditional fields gated by `exit:` UNSET or out-of-
   enum.** Each gated field SHALL be set with a valid enum
   value when the gating `exit:` fires; UNSET, null, or out-of-
   enum fails.
4. **Multi-discriminator combination incomplete on
   `re-evaluation`.** Per R9 Part 2 (see
   `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`),
   when `exit: re-evaluation` fires, BOTH `boundary:` AND
   `decision_record_sub_shape:` MUST be set to valid enum
   values. Either UNSET fails.
5. **Chain-membership-gated field mismatch on
   `plan_execution_mode:`.** Per R9 Part 3, the field is
   present if and only if `/plan` appears in `chain_ran:`.
   Presence without `/plan` in `chain_ran:`, or absence with
   `/plan` in `chain_ran:`, fails.

When R9 fails, Phase 3 SHALL surface the specific violation
(naming the offending field and the failing part of the check)
and refuse to record finalization. Silent absorption is itself
a contract violation.

## `git commit -F` Discipline

Any author-supplied free-form string written into a commit
body SHALL be passed to `git commit` via `-F <tmpfile>` or
stdin (`git commit -F -`). Inlining author-supplied prose into
`git commit -m "..."` is forbidden. The discipline covers:

- The **rejection rationale** captured from Phase 2 when
  `/prd` or `/design` Reject fires. The rationale is the
  commit body of the discard commit Phase 2 observes; when
  Phase 3 writes the rejection-sub-shape Decision Record, the
  rationale is rendered into the Decision Record body via
  template substitution (not shell interpolation) and the
  Decision Record file itself is committed via `git commit -F`
  with the file's path or via stdin.
- The **"proceed against original intent" rationale** an
  author may supply during Phase 2's worktree-discipline
  escalation phase. The rationale is recorded into the state
  file (as part of the team-lead's notes for the
  `worktree_divergences:` entry); when finalization writes a
  commit referencing the divergence, the rationale is passed
  through stdin or a tempfile.

The discipline closes the shell-metacharacter injection
surface that would otherwise open if author-supplied prose
flowed through `git commit -m`'s argument parser. `git commit
-F` reads the body content from a file or stdin without
interpreting metacharacters, so a malicious quote, backtick,
or dollar sign in the rationale never reaches a shell.

## Public-History Disclaimer

`/scope` v1 binds to public-repo tactical chains exclusively.
Any rejection rationale or "proceed against original intent"
prose written through the commit-message surface becomes part
of the repository's permanent git history. Phase 3 documents
this contract for traceability — the Phase-N Reject prompt
literal text shipped by `/prd` Phase 4 step 4.5 and `/design`
Phase 6 step 6.7 includes the substring `Rationale will be committed to git history` so the author understands the
disclosure boundary when entering the rationale.

The disclaimer is not a `/scope`-side prompt; it is a contract
`/scope` relies on the children to surface. Phase 3 cites it
here to document the chain-level expectation that the
substring is present in those child prompts.

## Closed Write-Target Set

Phase 3's filesystem write surface is confined to the enumerated
set. Writes outside it fail the R9 hard-finalization check.

**`skills/scope/SKILL.md` is the authoritative declaration.** This
is a restatement for readers working in this phase, and the two
must not diverge — they did before, disagreeing about whether the
PLAN was a Phase 3 write target, and that disagreement was one of
three defects this enumeration corrects.

Phase 3's own writes:

- `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
  — Decision Records on `re-evaluation` exit.
- `docs/{briefs,prds,designs,plans}/{BRIEF,PRD,DESIGN,PLAN}-<topic>.md`
  and `docs/designs/current/DESIGN-<topic>.md` —
  force-materialization only, on `abandonment-forced` exit. Both
  DESIGN locations are named because the canonical DESIGN path is
  the pair; `docs/plans/` is named because the terminal child's
  intermediate force-materializes there like every other child's,
  and its omission from this group while the Mutations group
  carried it was an inconsistency rather than a boundary.
- `wip/scope_<topic>_*` — state file and ancillary scratch under
  the same prefix.

Phase 2's absorb adds two groups, recorded here because the
enumeration is closed across the skill rather than per phase:

- **Deletions:** `docs/briefs/BRIEF-<topic>.md`,
  `docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`.
  The PLAN is never a deletion target of a fold.
- **Mutations:** `docs/{prds,designs,plans}/{PRD,DESIGN,PLAN}-<topic>.md`
  and `docs/designs/current/DESIGN-<topic>.md` — the survivor, at
  whichever hop and at whichever of the two DESIGN locations it
  sits. `docs/plans/` is included because the PLAN is the survivor
  at the terminal hop.

Phase 2's per-hop commit and the absorb's own commit add a third,
which is the group that makes the omissions above matter: every
path an enumeration governing commits leaves out is a live write at
an undeclared target.

- **Commits:** `docs/briefs/BRIEF-<topic>.md`,
  `docs/prds/PRD-<topic>.md`, `docs/designs/DESIGN-<topic>.md`,
  `docs/designs/current/DESIGN-<topic>.md`,
  `docs/plans/PLAN-<topic>.md`. The `.git/` writes are confined to
  `git add` and `git commit` restricted to those pathspecs. Nothing
  pushes.

The workflow session adds an out-of-repo group, neither member of
which is version-controlled or referenced from a committed
artifact:

- **Out-of-repo ephemera:** the koto session store (`~/.koto/sessions/`
  by default) and koto's template compile cache
  (`$XDG_CACHE_HOME/koto`, or `~/.cache/koto` when that variable is
  unset).

R8's clean cancel adds one deletion, enumerated for the same
reason:

- `wip/scope_<topic>_state.md` — the one path a bail removes.
  `wip/scope_<topic>_handoff.md` sits under the same prefix and is
  carved out of that deletion; it is enumerated here and never
  swept by a bail.

Phase 3 does not delete, and on the paths that produce one it does
not write the PLAN: it records the deletion Phase 2 already
performed and lists the terminal artifact's path in
`exit_artifacts:`. Both of those remain true — what changed is that
the phase performing each write is now named, which is what lets
"Phase 3 does not write the PLAN" and "Phase 2's absorb writes it"
both stand. The one exception is the exit that produces no PLAN of
its own: on `abandonment-forced` with `/plan` as the triggering
child, Phase 3 force-materializes that child's intermediate at
`docs/plans/PLAN-<topic>.md`, which is why the path is in the
abandonment group above and why leaving it out was an oversight
rather than a bound.

Every path inside the repository is composed from the validated
topic slug or is a fixed constant, never from author-supplied text,
so the set stays closed and enumerable. The two out-of-repo
locations are resolved by koto from its own configuration; this
skill composes neither.

## State-File Enum Re-Validation Before Path Interpolation

Before constructing the Decision Record write path on
`re-evaluation` exit, Phase 3 re-validates the gating fields
against their declared enums:

- `boundary:` against `{prd, design}`.
- `decision_record_sub_shape:` against `{re-evaluation, rejection}`.
- `triggering_child:` against `{brief, prd, design, plan}` (when
  the exit is abandonment-forced and the field is interpolated
  into the force-materialization path).
- `plan_execution_mode:` against
  `{single-pr, multi-pr, coordinated}` (when
  the field is interpolated into any post-finalization commit
  body).

Out-of-enum values fail finalization and route to R8 bail-
handling. The re-validation is the second of the two enum-
check surfaces (the first is Phase 2's pre-interpolation
check); both surfaces close the state-file-tampering injection
vector at every write-path-construction boundary.

## References

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` —
  Three Exit Paths section (the substrate-agnostic semantics
  of `full-run`, `re-evaluation`, `abandonment-forced`).
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
  — R9 Hard-Finalization Check Spec (Parts 1-3 plus the
  multi-discriminator and chain-membership-gated additions).
- Interface I.2 in `docs/designs/current/DESIGN-shirabe-scope-skill.md`
  — Decision Record path schema and the four boundary ×
  sub-shape combinations.
- `skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md`
  — the four Decision Record body templates Phase 3 selects
  between based on `boundary:` + `decision_record_sub_shape:`.
