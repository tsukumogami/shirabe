---
status: Accepted
decision: |
  The `--lifecycle` check detects chain posture by reading the PLAN's
  frontmatter `status:` field. PLAN docs use a unified Draft -> Active ->
  Done -> DELETED lifecycle, identical for single-pr and multi-pr; only
  the Draft -> Active gate differs (auto for single-pr, human-approved
  for multi-pr). PLAN present at `Active` is the in-flight posture
  (single-pr mid-PR or multi-pr in-flight); PLAN present at `Done` is
  the work-completing-but-not-yet-deleted posture (the check fails on
  this state, forcing the deletion commit into the same PR); PLAN
  present at `Draft` on a committed branch is a violation (the auto-
  transition for single-pr didn't fire, or the human-approval gate for
  multi-pr never ran); PLAN absent is the at-merge posture. The author's
  gesture for "this PR is the work-completing PR" is the single atomic
  commit set that flips `status: Active` to `status: Done`, deletes the
  PLAN file, and transitions BRIEF/PRD to `Done`.
rationale: |
  Aligns verbatim with the parent PRD R17 forcing-function language already
  in the corpus — the chain-aware reframing in #116 generalizes the same
  mechanism rather than introducing a new one. Stays within the validator's
  doc-tree-only architecture. Distinguishes the "last-child-merging" state
  from the "work-completing" state, which the strikethrough alternative
  cannot. The unified PLAN lifecycle lets single-pr and multi-pr share one
  on-disk state machine, with the gate difference (auto vs human) handled
  out-of-band rather than encoded in a second pair of statuses.
  Implementation is one frontmatter field read per PLAN.
---

# DECISION: PLAN lifecycle posture detection

## Status

Accepted

## Context

The chain-aware `shirabe validate --lifecycle <root>` check has to distinguish two phases of a chain's life:

- **In-flight**: the PR is one of the work-delivering PRs in the chain. PLAN stays at `Active`, BRIEF/PRD stay at `Accepted`, DESIGN stays at `Current`.
- **Work-completing**: the PR is the final verify-then-delete PR. PLAN transitions `Active -> Done -> DELETED`, BRIEF/PRD transition `Accepted -> Done`, all atomically in this one PR.

PLAN docs use a unified Draft -> Active -> Done -> DELETED lifecycle, identical for single-pr and multi-pr. Only the Draft -> Active transition differs: multi-pr requires human approval (GitHub issues + milestone are created on the transition), single-pr auto-fires when `/shirabe:plan` finishes authoring. A committed PLAN's on-disk passing state is `Active` in both modes. Multi-pr is the hard case for detection because the PLAN is present in BOTH in-flight and work-completing phases until the deletion commit lands; single-pr has the same shape on disk during its single PR.

The validator runs doc-tree-only — it reads the working tree files and emits errors without external state lookups (the `gh.rs` precedent for FC09 is a self-disabling external integration, not a foundational dependency). The detection mechanism has to be deterministic from the working tree alone.

Parent PRD R17 today states: "a present Done multi-pr doc means the author marked the work complete but did not delete the doc — Check A failing on that state is the forcing function that drives the deletion." That phrasing already implicitly commits to a status-field detection mechanism. The chain-aware reframing in #116 generalizes the same rule.

## Decision

The `--lifecycle` check detects chain posture from the PLAN's frontmatter `status:` field. The same rules apply to single-pr and multi-pr (the gate difference is out-of-band; the on-disk shape is identical):

| PLAN working-tree state | Posture | Passing states |
|-------------------------|---------|----------------|
| Present, `status: Active` | In-flight | BRIEF/PRD `Accepted`, DESIGN `Current`, PLAN `Active` |
| Present, `status: Draft` | Pre-implementation; auto-transition (single-pr) or human-approval gate (multi-pr) didn't fire | check fails — a committed PLAN must be at `Active`, never `Draft` |
| Present, `status: Done` | Work-completing, deletion missing | BRIEF/PRD `Done`, DESIGN `Current`, PLAN DELETED — check fails to force the deletion |
| Absent | At-merge | BRIEF/PRD `Done`, DESIGN `Current` |

The author's gesture for the work-completing PR is a single atomic commit set:

1. Edit `docs/plans/PLAN-<topic>.md`: change `status: Active` to `status: Done`.
2. Edit `docs/briefs/BRIEF-<topic>.md`: change `status: Accepted` to `status: Done`.
3. Edit `docs/prds/PRD-<topic>.md`: change `status: Accepted` to `status: Done`.
4. `git rm docs/plans/PLAN-<topic>.md`.

The DESIGN already lives in `docs/designs/current/` at `status: Current` (the terminal state for DESIGNs); no DESIGN transition is required at completion. The `--lifecycle` check runs against the resulting working tree, sees PLAN absent + BRIEF/PRD/DESIGN at their target states, and passes.

The intermediate working-tree state where the PLAN is at `Done` but not yet deleted exists momentarily between commits (or persistently if the author forgets to add the deletion). The check fails on this state as the forcing function for the deletion commit — exactly as R17 says today.

## Options Considered

### Option 1: PLAN frontmatter status field (chosen)

Described in the Decision section above. Implementation cost: trivial — one frontmatter field read per multi-pr PLAN, riding on the same parsing already done for `upstream:` traversal.

### Option 2: Strikethrough completeness in the PLAN's issues table

Walk the PLAN's `## Implementation Issues` table, count strikethrough vs non-strikethrough rows; all-strikethrough -> work-completing.

**Rejected.** Conflates the "last child issue's PR just merged but the verify-then-delete PR is not yet opened" state with the "work-completing PR" state. Both have all-strikethrough tables and a PLAN-present working tree; the check cannot tell them apart. The strikethrough state is also dependent on the parent PLAN being updated synchronously with child-issue closures — exactly the drift FC09 emits a notice for, not a clean source of truth. Author has no explicit gesture; the posture flip is implicit and races with child PR merges.

### Option 3: Git introspection

Shell out to `git` for the current branch and diff against `origin/main`; if the PR diff deletes the PLAN, this is the work-completing PR.

**Rejected.** Most accurate ground truth, but adds dependencies the validator architecture today does not assume: a `git` binary, a working `.git/` directory, a known upstream branch name (origin/main vs origin/master vs fork), and special handling for non-git invocations (e.g., koto context running on a copy of the doc tree). The signal is also redundant with Option 1 — Option 1 reads the state just-before the deletion commit (PLAN present at Done); git reads the state just-after (PLAN deleted). The just-before signal is sufficient for the validator's purpose (forcing the deletion to land in the same PR).

## Consequences

What becomes easier:
- The check stays doc-tree-only; no new dependency on git tooling.
- The work-completing PR has a single-gesture author shape (status change + git rm + BRIEF/PRD Done transitions) that's grep-able in PR review.
- Implementation cost is one frontmatter field read per multi-pr PLAN.
- The check's behavior is identical in local-dev pre-commit runs, CI runs, and koto-context runs — no asymmetry from git availability.

What becomes harder:
- Authors must learn that "transition the PLAN to Done" is the gesture marking the work-completing PR. The `shirabe transition` subcommand covers the PLAN lifecycle (Draft -> Active -> Done) under the unified model, so the gesture is discoverable via `shirabe transition --help`; manual frontmatter edits are still accepted as a fallback.
- The check fails on the intermediate "PLAN at Done, still present" working-tree state. That's the intent (forcing function for deletion), but local-dev workflows that pause between the status change and the `git rm` will surface the failure. Remedy: complete the gesture in one commit.

Accepted trade-off:
- A clever author could set PLAN status to Done in one PR (the last in-flight PR) and never produce a work-completing PR with the deletion. The check would fail on every subsequent PR's `--lifecycle` run until the deletion lands. That is the forcing function working as designed.
