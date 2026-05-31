# Phase 3 — Exit Finalization

Phase 3 lands the chain at one of three terminal exit paths and
runs the R9 hard-finalization check. Every chain ends here.
Phase 3's contracts cover the three exit-path bindings, the R8
tie-break for `triggering_child:` on abandonment-forced, the
HTML-comment marker placement for force-materialized partials,
the `git commit -F` discipline for author-supplied prose
written into commits, the public-history disclaimer for in-
chain Reject, and the closed write-target set Phase 3 may
touch.

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
single-pr`; Active when `plan_execution_mode: multi-pr`, with
an accompanying GitHub milestone created by `/plan`). Phase 3
populates the state file with:

```yaml
exit: full-run
chain_completed: <ISO-8601 timestamp>
plan_execution_mode: single-pr | multi-pr
exit_artifacts:
  - path: docs/plans/PLAN-<topic>.md
    status: Draft | Active
```

`plan_execution_mode:` is gated by `/plan` appearing in
`chain_ran:` per R9 Part 3's chain-membership-gated extension
in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`.

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
partial_phase_reached: <phase identifier inside the child>
chain_completed: <ISO-8601 timestamp>
exit_artifacts:
  - path: docs/{briefs|prds|designs|plans}/<TYPE>-<topic>.md
    status: Draft
```

## R8 Tie-Break for `triggering_child:`

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

When NO child has an unfinished intermediate (the bail fired
in Phase 1 with no Phase 2 invocations yet), `triggering_child:`
is set to whichever child Phase 2 was about to invoke when the
bail fired — the first child in `planned_chain:` that has not
yet completed.

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

R9 fires at Phase 3 termination and refuses finalization if any
of the following conditions hold:

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

Phase 3's filesystem write surface is confined to the
enumerated set. Writes outside this set fail the R9 hard-
finalization check.

The allowed write targets:

- `docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`
  — Decision Records on `re-evaluation` exit.
- `docs/{briefs,prds,designs}/{BRIEF,PRD,DESIGN}-<topic>.md` —
  force-materialization only, on `abandonment-forced` exit.
- `wip/scope_<topic>_*` — state file
  (`wip/scope_<topic>_state.md`) and ancillary scratch the
  substrate may write under the same prefix.

The PLAN artifact at `docs/plans/PLAN-<topic>.md` is produced
by `/plan` (not directly by Phase 3); Phase 3's full-run exit
only updates the state file's `exit_artifacts:` list to
reference the PLAN, it does not write the PLAN itself. Phase 3
does NOT remove `wip/{brief,prd,design,plan}_<topic>_*` files
— those removals happen in Phase 4 according to the exit-path
matrix in `phase-4-cleanup.md`. Phase 3 owns the terminal-
artifact finalization act (PLAN reference, Decision Record
write, or abandonment-forced marker placement) but does not
sweep the workflow's child-prefixed intermediates.

## State-File Enum Re-Validation Before Path Interpolation

Before constructing the Decision Record write path on
`re-evaluation` exit, Phase 3 re-validates the gating fields
against their declared enums:

- `boundary:` against `{prd, design}`.
- `decision_record_sub_shape:` against `{re-evaluation, rejection}`.
- `triggering_child:` against `{brief, prd, design, plan}` (when
  the exit is abandonment-forced and the field is interpolated
  into the force-materialization path).
- `plan_execution_mode:` against `{single-pr, multi-pr}` (when
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
- Interface I.2 in `docs/designs/DESIGN-shirabe-scope-skill.md`
  — Decision Record path schema and the four boundary ×
  sub-shape combinations.
- `skills/scope/references/decision-record-{prd|design}-{re-evaluation|rejection}.md`
  — the four Decision Record body templates Phase 3 selects
  between based on `boundary:` + `decision_record_sub_shape:`.
