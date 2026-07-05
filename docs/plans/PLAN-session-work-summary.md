---
schema: plan/v1
status: Draft
execution_mode: coordinated
upstream: docs/designs/DESIGN-session-work-summary.md
milestone: "Session Work Summary"
issue_count: 5
---

# PLAN: Session Work Summary

## Status

Draft

Decomposition is complete and committed; GitHub issue creation is deliberately
deferred. Coordinated mode has no validated single-command cross-repo issue
fan-out in this skill version, and the three target repos each need their own
issues and (per-repo) milestone. Issue creation happens at implementation time —
per-repo `/work-on` or manual `gh` — at which point the Issue Outlines below
become the created issues and this PLAN transitions to Active. The coordination
PR merges last per the merge order.

## Scope Summary

Implements the deterministic work-in-flight PR summary across three repositories:
the `shirabe work-summary` CLI subcommand and `/inflight` command in shirabe, the
thin hooks in dot-niwa, and the enabling niwa capabilities (materializer dedup +
SessionStart-merge fix, dispatch-brief rule). The `shirabe` binary is already on
PATH, so the hooks and `/inflight` invoke the subcommand directly with no path
resolution.

## Decomposition Strategy

**Horizontal.** The components are loosely coupled across repositories with
defined interfaces: the `shirabe work-summary` subcommand is the single
implementation everything else invokes, so it is the prerequisite; the niwa
capabilities are independent enablers; the dot-niwa hooks are thin shims that
depend on both. This is a set of
components with clear boundaries built to a settled design, which is the
horizontal case rather than a single end-to-end runtime slice.

**Execution mode: coordinated.** The work spans three separate git repositories
(`tsukumogami/shirabe`, `tsukumogami/niwa`, `tsukumogami/dot-niwa`) and cannot land
as one PR. Each per-repo PR is independently useful — the shirabe PR ships a
working `/inflight` command on its own, the niwa PR repairs a live materializer
bug and adds standalone capabilities, and the dot-niwa PR delivers the ambient
display once its prerequisites land. A coordination PR (this branch) merges last.

## Issue Outlines

### Issue 1: feat: port the work-summary logic into the `shirabe work-summary` CLI subcommand

**Goal**: Ship the single reusable implementation (capture parsing, ledger,
two-level gate, renderer, terminal-safety sanitizer, hook-JSON emission) as a
`shirabe work-summary {capture,absence,compact,render,spec}` subcommand of the
compiled `shirabe` binary (Rust) that every surface invokes bare from PATH. The
security-critical, determinism-focused logic lives in typed Rust, not bash.

**Acceptance Criteria**:
- [ ] `shirabe work-summary capture` parses a PR URL from `gh pr create` output,
      validates it against the anchored
      `^https://github\.com/<owner>/<repo>/pull/[0-9]+$` pattern (rejecting
      non-matches and the `git push` `/pull/new/` hint), and appends a ledger row
      (repo, number, URL, first-seen, `terminal_shown`).
- [ ] `shirabe work-summary render <session-id>` reads the ledger, refreshes each
      item via live `gh`, and prints the `=== WORK IN FLIGHT ===` block with
      attention-first ordering, terminal-drop, section escalation above six items,
      and a freshness line. `spec` prints the format spec.
- [ ] `capture`/`absence` emit the hook JSON (systemMessage + neutral nonce-fenced
      additionalContext) directly from the binary; `compact` emits
      additionalContext only. The hooks carry no JSON/nonce/fence logic.
- [ ] The terminal-safety sanitizer strips control/ANSI bytes (before truncation),
      removes newlines and `|`, and forbids the marker substring in any cell.
- [ ] Two-level gate: cheap ledger-hash check every call; rendered-hash recompute
      only on ledger change or `WS_RENDER_INTERVAL`; `last_activity` refreshed on
      every call including suppressed ones; state writes `flock`-protected.
- [ ] Ledger and gate state stored per-user (dir 0700, files 0600), no symlink
      follow. Offline `gh` degrades to a best-effort ledger-only block.
- [ ] Unit tests cover the capture regex fixtures and the sanitizer.

**Dependencies**: None

**Repo / Group**: tsukumogami/shirabe / default
**Type**: code

### Issue 2: feat: /inflight on-demand work-summary command

**Goal**: A shirabe `/inflight` skill that regenerates the block on demand from
the same subcommand.

**Acceptance Criteria**:
- [ ] Calls `shirabe work-summary render` (on PATH) through `!` dynamic
      injection and relays its output verbatim.
- [ ] On unreachable live state, falls back to a repo-scoped `gh` listing
      (never author-scoped cross-repo) following the same block spec, with F1
      fail-closed redaction for unconfirmed-visibility items.
- [ ] `disable-model-invocation: true` so only the user invokes it.

**Dependencies**: Blocked by <<ISSUE:1>>

**Repo / Group**: tsukumogami/shirabe / default
**Type**: code

### Issue 3: fix: materializer hook-registration hygiene (dedup + SessionStart merge)

**Goal**: Fix the two niwa materializer defects that gate the ambient hooks: a
hook registered through both declared config and auto-discovery is installed
twice with a lost matcher, and the SessionStart provisioning hook clobbers an
installed `session_start` hook under ephemeral-session mode.

**Acceptance Criteria**:
- [ ] `runRepoMaterializers` (or its merge step) dedups by resolved script path so
      a script present in both channels registers once with its declared matcher.
- [ ] Regression test: a hook declared in `workspace.toml` with `matcher: Bash`
      and present under `.niwa/hooks/` materializes exactly one settings entry
      that retains the `Bash` matcher.
- [ ] SessionStart merge: an installed `session_start` hook survives
      ephemeral-session mode — the SessionStart provisioning hook merges with,
      rather than overwrites, a registered work-summary `compact` hook.
- [ ] Regression test: with ephemeral-session mode enabled, a registered
      `session_start` `compact` hook is still present in the materialized
      `settings.json` alongside the provisioning hook.

**Dependencies**: None

**Repo / Group**: tsukumogami/niwa / default
**Type**: code

### Issue 4: feat: dispatch-brief work-in-flight final-message rule

**Goal**: Require a dispatched worker's final message to carry the work-in-flight
block, via the niwa dispatch rootskill brief.

**Acceptance Criteria**:
- [ ] The dispatch brief template instructs the worker to end its final message
      with the standardized block (the same sanitization contract applies to the
      model-authored block).
- [ ] The rule references the block spec from the DESIGN, not a duplicated format.

**Dependencies**: None

**Repo / Group**: tsukumogami/niwa / default
**Type**: docs

### Issue 5: feat: thin work-summary hooks and registration

**Goal**: Ship the thin dot-niwa hooks that pass through to the on-PATH `shirabe
work-summary` subcommand, which does the emission.

**Acceptance Criteria**:
- [ ] PostToolUse capture hook (matcher on PR-affecting `gh` commands), a
      UserPromptSubmit return hook, and a SessionStart(`compact`) re-injection
      hook, registered via one channel in `workspace.toml`/`.niwa/hooks/`.
- [ ] Each hook is a pure pass-through: `exec shirabe work-summary <mode>`
      (`capture`/`absence`/`compact`) with a `command -v shirabe || exit 0`
      fail-safe guard. No `[[claude.plugin_path_env]]` reference and no
      JSON/nonce/fence logic in the hook — the binary emits `systemMessage` plus
      the neutral `additionalContext` echo.
- [ ] Hooks are idempotent and tool-type tolerant (defensive against the
      pre-fix double-registration behavior) and no-op when `shirabe` is absent
      from PATH.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:3>>

**Repo / Group**: tsukumogami/dot-niwa / default
**Type**: code

## Implementation Issues

Issues are not yet created. Coordinated mode has no validated single-command
cross-repo issue fan-out in this skill version, and the three target repos each
require their own issues (GitHub milestones are per-repo). The decomposition,
per-issue `Repo`/`Group` tags, and complexity live in the Issue Outlines above;
the cross-repo landing order lives in the Merge Order block below. At
implementation time each outline becomes a created issue in its target repo and
this table is populated with links, transitioning the PLAN to Active.

## Dependency Graph

```mermaid
graph TD
    I1["#1 shirabe: work-summary subcommand"]
    I2["#2 shirabe: /inflight"]
    I3["#3 niwa: materializer hygiene"]
    I4["#4 niwa: dispatch rule"]
    I5["#5 dot-niwa: thin hooks"]

    I1 --> I2
    I1 --> I5
    I3 --> I5

    class I1,I2,I3,I4,I5 ready;

    classDef done fill:#d4edda,stroke:#28a745,color:#333;
    classDef ready fill:#fff3cd,stroke:#d39e00,color:#333;
    classDef blocked fill:#f8d7da,stroke:#dc3545,color:#333;
```

**Legend**: done (merged), ready (unblocked), blocked (waiting on a dependency).
All five issues are `ready` (nothing created yet; no blockers exist at rest).

## Merge Order

```merge-order
# Two-node (repo, pr_group)-level DAG, one node per line.
shirabe-default | unopened
niwa-default | unopened
dot-niwa-default | unopened
```

`shirabe-default` and `niwa-default` have no cross-repo predecessors and may land
in parallel. `dot-niwa-default` merges only after both (it needs the
`shirabe work-summary` subcommand from shirabe and the materializer hygiene fix
from niwa). The coordination PR merges last, after all three per-repo PRs.

## Implementation Sequence

**Critical path:** Issue 1 (shirabe `work-summary` subcommand) → Issue 5 (dot-niwa
hooks) → coordination PR. The subcommand gates the hooks; the hooks are the last
per-repo work.

**Parallelizable:**
- The niwa work (Issues 3, 4) runs concurrently with the shirabe work
  (Issues 1, 2) — no cross-repo dependency between them.
- Within shirabe, Issue 2 follows Issue 1.
- Within niwa, the two issues are independent of each other.

**Prerequisites first:** Issue 3 (materializer hygiene — dedup + SessionStart
merge) is the niwa enabler the dot-niwa hooks require; landing it before Issue 5
keeps the dot-niwa PR unblocked as soon as shirabe lands.
