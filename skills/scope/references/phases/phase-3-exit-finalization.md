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
chain Reject. The closed write-target set Phase 3 may touch is
declared in `skills/scope/SKILL.md` (Security Considerations).

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
`docs/plans/PLAN-<topic>.md`, committed at the status `/plan` writes
for it. A committed PLAN is never Draft: its Draft -> Active
transition fires when `/plan` finishes authoring, or, when the
transition files GitHub issues, after the filing approval. By mode:

- **`single-pr`** — Active. The work lives in `## Issue Outlines`;
  no issue or milestone is filed.
- **`multi-pr`** — Active, with the issues (and, at
  `issues-and-milestone`, the milestone) `/plan` filed; an issueless
  `multi-pr` PLAN at tracking level `none` is Active with outlines.
- **`coordinated`** — Active. The outline-shaped coordinated PLAN
  (tracking level `none`, the coordinated default) files nothing and
  is authored at Active; at `issues` or `issues-and-milestone` it is
  Active once its filing approval has run.

Phase 3 populates the state file with:

```yaml
exit: full-run
chain_completed: <ISO-8601 timestamp>
plan_execution_mode: single-pr | multi-pr | coordinated
exit_artifacts:
  - path: docs/plans/PLAN-<topic>.md
    status: Active
```

On an intent run the exit is followed by the publish step before
cleanup (the publish states in `skills/scope/koto-templates/scope.md`):
the branch is pushed and one PR opened, a draft for `single-pr` and
`coordinated` and ready for `multi-pr` (R9). A publish that fails
records `publish_error: scope:push` or `publish_error:
scope:pr-create` in the state file and ends the run with that step;
the state file keeps `exit:` and its fields, and the next invocation
retries the publish.

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
then. On an intent run the PR body is the publish script's fixed
template -- the slug, exit, outcome, `intent=`, mode, the `docs/`
artifact paths that survive, and the work-item IDs, with no
free-text field -- so the list of surviving artifacts is what it
carries. On a run without intent, where the author opens the PR,
Phase 3 writes the fuller record into the run's pull-request body: every
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

The chain cannot complete the planned terminal artifact. An
abandoned run writes no PLAN, only the upstream documents: a
committed Draft PLAN fails the lifecycle check, and a PLAN that
never finished holds little a later run could reuse.

- When the triggering child is `/brief`, `/prd` or `/design`,
  Phase 3 force-materializes that child's intermediate as a Draft
  artifact at its canonical durable path
  (`docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`, or
  `docs/designs/DESIGN-<topic>.md`) and appends the HTML-comment
  marker to the END of its Status section.
- When the triggering child is `/plan`, nothing is
  force-materialized and `docs/plans/PLAN-<topic>.md` is not
  written. The marker goes at the END of the Status section of
  the nearest upstream document the chain left on disk (the
  DESIGN, or the PRD or BRIEF when the DESIGN was absorbed), and
  `exit_artifacts:` lists the upstream documents at their current
  status. `/plan`'s intermediate files stay where they are for a
  resumed run, as every abandoned child's do.

State file at abandonment-forced exit:

```yaml
exit: abandonment-forced
triggering_child: brief | prd | design | plan
partial_phase_reached: <the parent's own Phase 2 loop position>
chain_completed: <ISO-8601 timestamp>
exit_artifacts:
  - path: docs/{briefs|prds|designs}/<TYPE>-<topic>.md
    status: Draft   # or the upstream document's own status when /plan triggered
```

#### Coordinated abandonment closes the coordination PR

On a run where coordination intent resolved, abandonment **closes the
coordination PR without merging it** — `gh pr close`, the same `gh`
surface that authored and posted the body.

This has an external side effect and is the one part of abandonment
that reaches outside the repository, which is why it is stated rather
than left to follow from the exit name. Abandonment never merges the
coordination PR, and never leaves it open either: an open coordination
PR is merge-eligible, and merging it lands the plan the run just
abandoned. Closing it unmerged leaves the partial state auditable —
the closed PR's durable body records what was coordinated, and the
marked document records how far the chain got.

A single-repo run has no coordination PR and skips this.

An intent run skips it too, and makes no `gh pr close` call at all. A run
whose recorded `intent:` is `continue` or `stop` never creates a
coordination PR up front (see Coordination Intent in `SKILL.md`): the
publish step opens one at exit, once the PLAN's mode is known, and an
abandoned run has not reached it. So before exit there is no coordination
PR to close. Only a run with `intent: none` whose coordination intent
resolved on, which did create one up front, closes it here.

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
artifact's existing Status section, or, when `/plan` was the
triggering child, of the nearest upstream document's. The literal
marker text:

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

The marker uniformly applies to the three upstream artifact
types without per-child variation. The grep-checkable literal
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
