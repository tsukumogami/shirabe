---
schema: plan/v1
status: Active
execution_mode: single-pr
milestone: "Session Work Summary Defect Fixes"
issue_count: 5
---

# PLAN: Session Work Summary Defect Fixes

## Status

Active

This plan decomposes the fix for the two defects scoped in the 2026-07-06
amendments to `docs/briefs/BRIEF-session-work-summary.md`,
`docs/prds/PRD-session-work-summary.md`, and
`docs/designs/current/DESIGN-session-work-summary.md`. It's authored as a
self-contained document: the issue outlines below carry the decomposition, and
writing this plan creates no GitHub milestone or issues. The implementation
itself spans three repos (niwa, dot-niwa, shirabe) and, when the team picks it
up as tracked work, lands as a coordinated multi-repo effort — one PR per repo
with a niwa-before-dot-niwa merge gate. That coordinated shape is described in
Decomposition Strategy and Implementation Sequence below rather than spun up as
cross-repo GitHub state here.

## Scope Summary

Fix the two shipped session-work-summary defects: the ambient hooks are opt-in
and miss any workspace that never registered them, and the on-demand summary
under-reports a multi-repo session because an unpopulated ledger forces a
repo-scoped fallback. Both are cured primarily by making capture default-on in
niwa, with supporting work in dot-niwa and shirabe.

## Decomposition Strategy

**Horizontal by repo and concern, sequenced by one cross-repo constraint.** The
work splits cleanly along repository lines, and each piece has a stable interface
to the others (the `shirabe work-summary` CLI surface and the hook registration),
so there's no integration-risk case for a walking skeleton.

Issue 1 (niwa default-on capture) is the root: it's the primary fix for both
defects, because the ambient hooks it injects are what populate the cross-repo
session ledger. Issue 2 (dot-niwa cleanup) depends on it and carries the one real
ordering constraint — the explicit declaration must not be removed until the niwa
default exists, or a window opens with no hooks. Issues 3, 4, and 5 (shirabe) are
independent of niwa and of each other's merge, and can proceed in parallel.

When these outlines become tracked work, the coarsest-legal grouping is one PR
per repo: a niwa PR (Issue 1), a dot-niwa PR (Issue 2), and one shirabe PR
(Issues 3-5), with a coordination PR merging last. The cross-repo merge order is
niwa before dot-niwa; the shirabe PR is independent. That's `coordinated`
execution in shirabe's terms — recorded here in prose so this plan stays a
self-contained review artifact.

## Issue Outlines

### Issue 1: niwa — inject the work-summary hooks by default, with an off switch

**Goal**: Make the three work-summary hook registrations a niwa built-in default
materialized into every provisioned instance, gated by an explicit off switch,
so a workspace gets the ambient summary and a populated cross-repo ledger without
declaring anything.

**Acceptance Criteria**:
- [ ] A freshly provisioned instance materializes all three work-summary hooks
      (PostToolUse capture on `Bash`, UserPromptSubmit absence, SessionStart
      `compact`) with no workspace-level declaration, modeled on the existing
      `SessionHooks` default-injection path in `internal/workspace/materialize.go`.
- [ ] niwa carries the three thin pass-through scripts, each
      `exec shirabe work-summary <mode>` behind a `command -v shirabe || exit 0`
      guard; where `shirabe` is absent from PATH the hook no-ops and never aborts
      a turn.
- [ ] A documented off switch suppresses all three, resolved on
      `flag > CLAUDE.md-header > default` with default on.
- [ ] Default-on injection is idempotent against a workspace that still declares
      the hooks, so no hook double-registers (coordinates with Issue 2).
- [ ] The broadened ambient-hook surface is documented as bounded by the
      fail-safe guard and the off switch.

**Dependencies**: None

**Type**: code
**Files**: `internal/workspace/materialize.go`

### Issue 2: dot-niwa — retire the explicit work-summary hook declarations

**Goal**: Remove the now-redundant work-summary hook entries (and their scripts,
once niwa carries them) from dot-niwa so the registration has a single source and
can't double-register.

**Acceptance Criteria**:
- [ ] The three `[[claude.hooks.*]]` work-summary entries are removed from
      `.niwa/workspace.toml`, and the corresponding `.niwa/hooks/` scripts are
      removed if niwa now provides them.
- [ ] The tsukumogami workspace still emits the ambient summary after the change,
      now via the niwa default rather than the declaration.
- [ ] No work-summary hook is registered twice.
- [ ] The dot-niwa hook tests pass, updated to reflect the source move if needed.

**Dependencies**: Blocked by <<ISSUE:1>> (must merge after the niwa default
exists, or the workspace loses its hooks in the gap — the plan's one cross-repo
merge gate).

**Type**: code
**Files**: `.niwa/workspace.toml`

### Issue 3: shirabe — make the repo-scoped fallback label its own incompleteness

**Goal**: Strengthen the render fallback's in-block stamp into an explicit caveat
that it's a current-repository-only view which may omit this session's PRs in
other repos, keeping it sanitized, fail-closed, and repo-scoped.

**Acceptance Criteria**:
- [ ] In `crates/shirabe/src/work_summary.rs`, the fallback block states plainly
      that it's partial and current-repo-only (extending the existing
      `(repo-scoped fallback: <repo>)` stamp).
- [ ] The caveat text passes the same terminal-safety sanitizer as the rest of
      the block.
- [ ] The fallback stays repo-scoped and fail-closed; no author-scoped cross-repo
      `gh` query is introduced (the path rejected for visibility, PRD R12).
- [ ] A unit test covers the caveat's presence and its sanitizer path.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe/src/work_summary.rs`

### Issue 4: shirabe — forbid PR references outside the block on model-framed paths

**Goal**: Add a checkable guardrail to the `/inflight` skill contract and the
dispatch final-message rule: no PR reference may appear around the emitted block
unless it's a real captured PR the block lists.

**Acceptance Criteria**:
- [ ] `skills/inflight/SKILL.md` states the no-unverified-reference rule
      explicitly, framed as the safety net paired with completeness — not a
      substitute for it.
- [ ] The dispatch final-message rule carries the same prohibition (a cross-repo
      item the component didn't capture is dropped, never narrated from memory).
- [ ] The rule is phrased so a reviewer or a check can decide conformance
      objectively.

**Dependencies**: None

**Type**: docs
**Files**: `skills/inflight/SKILL.md`

### Issue 5: shirabe — verify session-keying consistency between capture and render

**Goal**: Confirm (and harden if needed) that the session identity `render` keys
on and the identity `capture` keys the ledger by are the same in provisioned and
dispatched sessions, so a captured session renders its complete ledger and is
never pushed to the fallback by a keying mismatch (PRD R20). Relates to Issue 1's
default-on capture path, but doesn't block on it.

**Acceptance Criteria**:
- [ ] The two keying sources (`CLAUDE_CODE_SESSION_ID` for render; the
      PostToolUse stdin `session_id` for capture) are documented as identical on
      the default-on provisioning path, or a mismatch is found and fixed.
- [ ] A test or a documented manual check covers a captured session rendering
      from the ledger rather than the fallback.

**Dependencies**: None

**Type**: code
**Files**: `crates/shirabe/src/work_summary.rs`

## Implementation Sequence

**Critical path:** Issue 1 (niwa default-on capture) → Issue 2 (dot-niwa
cleanup). This is the only hard sequence — the niwa default must exist and merge
before dot-niwa removes its explicit declaration, or the tsukumogami workspace
loses its hooks in the gap.

**Parallel:** Issues 1, 3, 4, and 5 can all start immediately. The three shirabe
issues share one PR (coarsest-legal grouping) and are independent of the
niwa/dot-niwa sequence. Within that PR, Issues 3 and 5 both touch
`work_summary.rs`, so they land in one coherent change rather than racing.

**Priority signal:** Issue 1 is the highest-impact starting point — it's the
primary fix for both defects and unblocks Issue 2. The shirabe issues harden the
degraded path; they improve the fallback but don't, on their own, restore
completeness (that comes from Issue 1).

**Coordinated grouping (follow-up).** One PR per repo — niwa (Issue 1), dot-niwa
(Issue 2), shirabe (Issues 3-5) — with a coordination PR merging last if the team
runs this as a tracked multi-repo effort. Merge order: niwa before dot-niwa;
shirabe independent.
