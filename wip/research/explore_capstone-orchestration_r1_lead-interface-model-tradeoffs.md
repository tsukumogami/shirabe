# Lead: Which of the author's session conventions are best expressed as durable workspace preferences, which as per-invocation intent/flags, and which as smart defaults — and what are the trade-offs?

## Findings

### Precedent survey: how shirabe skills already take input

shirabe skills already use three distinct interface models, with established
conventions for each. This matters because the recommendation should fit
existing patterns, not invent a fourth model.

**1. Per-invocation flags (parsed from `$ARGUMENTS`).** The dominant model for
"what do I want *this run* to do."

- `/explore` parses `--auto` / `--interactive`, `--strategic` / `--tactical`,
  and `--max-rounds=N`
  (`skills/explore/SKILL.md` lines 125-168 "Context Resolution").
- `/scope` parses `--auto`, `--interactive`, `--max-rounds=N` (default 5,
  overriding /charter's 3) in a dedicated `## Execution-Mode Flags` section
  (`skills/scope/SKILL.md` lines 93-113).
- `/plan` parses `--auto`/`--interactive`, plus decomposition-strategy flags
  `--walking-skeleton` (`skills/plan/SKILL.md` lines 229-241).
- `/work-on` parses `--auto`/`--interactive` and the `-- plan-backed` child-mode
  prefix (`skills/work-on/SKILL.md` lines 55, 259-261).

**2. Durable CLAUDE.md headers (read once per repo).** The model for "what is
true about this repo, always."

- `## Repo Visibility: Public|Private` — read by explore, scope, plan, roadmap,
  comp, strategy, vision, review-plan. Notably **immutable**: explore states
  visibility "must never accidentally include private references, even if a user
  passes --private. Flags can't override it" (`skills/explore/SKILL.md` line
  153-154). This is the precedent for a preference that flags deliberately
  *cannot* override.
- `## Default Scope: Strategic|Tactical` — read when no `--strategic`/`--tactical`
  flag present (`skills/explore/SKILL.md` lines 160-168; `skills/plan/SKILL.md`
  275-279).
- `## Execution Mode: auto|interactive` — read when no `--auto`/`--interactive`
  flag present (explore line 125-131, plan line 234, work-on line 259-261).
- `## Planning Context: Tactical`, `## Artifact Lifecycle: per-skill`,
  `## Release Notes Convention: docs/guides/` (shirabe's own CLAUDE.md).

The key precedent here is the **flag-overrides-header layering**: a flag, if
present, wins; otherwise fall back to a CLAUDE.md header; otherwise a hard-coded
default. This is the exact "preference + flag + smart default" stack the lead is
asking about — shirabe already runs it for execution mode and scope.

**3. Smart defaults (workflow infers and acts, override to opt out).** The model
for "the workflow knows the right thing; don't make me say it."

- `/plan` execution-mode decision: "**Default: single-pr.** Reach for one PR...
  Escape to multi-pr only when a named condition forces it" (`skills/plan/SKILL.md`
  lines 137-160). The workflow infers single vs multi from coupling/ordering
  conditions; the author overrides only at a named escape hatch. **This is the
  closest existing analog to the capstone.**
- `/work-on` **Branch Context Evaluation** (`skills/work-on/SKILL.md` lines
  43-50, 92-119, 201-208): before creating a branch it checks three signals —
  current branch name matching `impl/<slug>`, an open PR on that branch, and any
  explicit user instruction — and submits `status: override` to *reuse* rather
  than create. This is a smart default that infers "we already have the right
  worktree/PR" from filesystem + git + PR state. **Directly relevant to
  conventions 1 and 4** — it is already an ad-hoc, single-repo version of
  capstone detection.
- `/work-on` plan-orchestrator mode already drives **multiple issues through one
  shared branch and one draft PR** (`SKILL.md` lines 40-167): `orchestrator_setup`
  creates `impl/<slug>` + draft PR, children commit to `SHARED_BRANCH` and submit
  `pr_status: shared`, `pr_finalization` assembles the PR body, and
  `plan_completion` runs the cascade then `gh pr ready`. This is the single-repo
  capstone in miniature.
- The single-pr PLAN lifecycle (`Draft → Active → Done → DELETED`, the PLAN file
  deleted in the same commit set that finishes the work, CI-enforced) is exactly
  the "fully consumed before merge" property convention 1 wants
  (`skills/plan/SKILL.md` lines 29, 58-86).
- `/plan` already emits a **Dependency Graph** (Mermaid) and an **Implementation
  Sequence** with critical path and parallelization
  (`skills/plan/SKILL.md` lines 51-52, 354) — the raw data a merge order needs.
- The **worktree-discipline** reference (`references/worktree-discipline.md`)
  already governs ≤1-worktree-per-chain rebase/impact/escalate behavior for
  /scope and /charter; /work-on is listed as "future" (Binding Notes table). This
  is the natural home for a per-repo worktree policy.

### Classification of the 5 conventions

| # | Convention | Recommended model | Why |
|---|------------|-------------------|-----|
| 1 | Capstone PR exists | **Smart default + per-session flag to opt in/out** | Whether a capstone is active is *session intent*, not a repo fact. It mirrors /plan's single-pr default and /work-on's branch-reuse detection. Best shape: a smart default that *detects* an active capstone (branch/PR/state present) and reconnects, plus a flag (`--capstone` / `--no-capstone`) to start/suppress one. Not a CLAUDE.md preference — it changes per session. |
| 2 | Planning artifacts persist to the capstone branch | **Implied by 1 (not separately configurable)** | This is a *consequence* of a capstone existing, not an independent choice. If a capstone is active, artifacts land on its branch; if not, they land per existing skill behavior. Making it a separate knob invites incoherent states (capstone on, artifacts scattered). Bind it to convention 1's state. |
| 3 | Sequencing (artifacts via /scope first, then reconcile) | **Smart default (workflow ordering), not user-facing** | This is the *internal phase order* of the chain. /scope already enforces BRIEF→PRD→DESIGN→PLAN ordering and Phase-2 child sequencing. "Reconcile related artifacts" maps to the worktree-discipline impact-analysis already in /scope Phase 2. Bake it into the workflow; do not expose a flag. An escape (skip-reconcile) would only undermine the chain's invariants. |
| 4 | ≤1 worktree per repo (unless genuinely independent) | **Durable CLAUDE.md preference, with a per-invocation override flag** | This is a stable property of *how this workspace is organized*, true across sessions — exactly the Repo Visibility / Default Scope shape. Propose a header like `## Worktree Policy: one-per-repo`. The "unless genuinely independent" carve-out is the per-invocation override (`--independent-worktrees` or similar). Layering: flag > header > default, matching the existing execution-mode/scope stack. |
| 5 | Explicit merge order across per-repo PRs | **Smart default (computed) + per-session override** | The order is *derived data*, not a preference. /plan already produces the dependency graph and Implementation Sequence; the cross-repo merge order is the topological extension of that. Compute it, surface it, let the author reorder for this session (per-invocation override). Storing a fixed merge order as a preference would be wrong — it changes with every plan. |

### How conventions interact

- **1 → 2 are one decision.** "Capstone exists" implies "artifacts persist
  there." Treat 2 as a derived property of 1's state, never an independent knob.
  This matches how /plan's single-pr mode implies "PLAN doc is self-contained and
  deleted before merge" — you don't separately toggle the deletion.
- **1 → 5.** Merge order only exists *because* there's a capstone coordinating
  per-repo PRs. The capstone's state is the natural home for the computed order
  and any session override.
- **3 → 1.** "Produce artifacts via /scope first" is the sequencing inside the
  capstone session; it presupposes the capstone is the place artifacts land
  (convention 2). So 3 also depends on 1 being active.
- **4 is the most independent.** A one-worktree-per-repo policy is meaningful
  even without a capstone (it's how /work-on already wants to reuse `impl/<slug>`).
  That independence is exactly why it's the best fit for a durable preference
  rather than session state.

## Implications

- **The capstone is a generalization of two things shirabe already does**:
  /plan's single-pr-default lifecycle (consume-before-merge) and /work-on's
  shared-branch plan-orchestrator mode (one branch + one PR for many issues). The
  capstone lifts those from single-repo to multi-repo. This means conventions
  1, 2, 3, 5 are best modeled as *smart defaults inferred by the workflow*, with
  thin per-session overrides — not as a pile of preferences the author sets up
  front. Only convention 4 (worktree policy) is genuinely durable config.
- **Use the existing flag > header > default layering.** Don't invent a new
  config surface. Convention 4's preference rides the same mechanism as
  `## Repo Visibility` / `## Default Scope` / `## Execution Mode`. Convention 1's
  opt-in/out is a flag on top of detection, exactly like
  `--strategic` over `## Default Scope`.
- **Detection (reconnect-across-resets) is the load-bearing piece.** /work-on's
  Branch Context Evaluation (current-branch + open-PR + user-instruction signals)
  is the proven pattern for "remember we have a capstone active." A capstone needs
  the same: detect from branch/PR/wip-state and reconnect, rather than asking the
  author to re-declare each invocation. This is a smart default by construction.
- **Merge order is computed, not configured.** /plan's dependency graph +
  Implementation Sequence is the source; the cross-repo order is its topological
  extension. The interface is "show the computed order, allow a session reorder,"
  not "set a merge order preference."

### Comparison: preference vs flag vs smart default

| Dimension | Durable preference (CLAUDE.md header) | Per-invocation flag | Smart default (infer + act, override to opt out) |
|-----------|----------------------------------------|---------------------|---------------------------------------------------|
| **Discoverability** | Medium — visible in CLAUDE.md but only if you read it; needs a documented header name (FC-CONVENTIONS validator can enforce existence, as it does for the other headers) | Low — invisible unless documented in `argument-hint` / SKILL.md; user must know the flag exists | High *if the workflow announces what it inferred* (e.g. explore's "Exploring with Public visibility in Tactical scope..." log line); low if silent |
| **Least astonishment** | High for stable facts (visibility never surprises); **wrong** for session-varying intent (a stale header silently changes a new session's behavior) | High — explicit, the author said it this run; zero hidden state | Risk of astonishment when the inference is wrong; mitigated by announce-what-I-did + an obvious override. /plan's single-pr default + named escape is the good model |
| **Statefulness across a multi-step session** | Persists across the whole session and beyond (that's the point) — good for convention 4, bad for "this session's capstone" | Zero persistence — must be repeated every invocation, which is *exactly the friction the author is complaining about* (re-pasting the contract) | Persists for the session via detected state (branch/PR/wip), reconnects across resets — the only model that solves the re-paste problem without making the author re-declare |
| **Testability** | Easy — set header, assert behavior; binary input. Existing evals already exercise visibility/scope headers | Easy — pass flag, assert behavior; pure function of args | Harder — must fixture branch/PR/wip state to trigger the inference, and test both the happy path and the override; /work-on's branch-context logic shows this is doable but more setup |

**Reading of the trade-off for this lead specifically:** the author's pain is
*re-pasting a contract every session*. That rules out the pure-flag model for the
session-shaped conventions (1, 2, 3, 5) — flags have zero statefulness and would
just move the re-pasting into re-typing flags. It also rules out a durable
preference for those four, because they vary per session and a stale header is an
astonishment hazard. The residual is the smart-default model with detection +
announce + override, which is precisely what /plan (single-pr default) and
/work-on (branch reuse) already demonstrate. Convention 4 alone is the stable
fact that earns a durable preference.

## Surprises

- **shirabe already runs the full three-layer stack** (flag > CLAUDE.md header >
  hard default) for execution mode and scope. The lead's "preference vs flag vs
  smart default" framing isn't a choice between three options — the codebase
  treats them as a *layered fallback chain*, and the real design question per
  convention is "which layers participate," not "pick one."
- **/work-on already contains a single-repo capstone.** Plan-orchestrator mode
  (shared branch, one draft PR, children commit to `SHARED_BRANCH`, cascade +
  `gh pr ready`) is the capstone pattern minus the cross-repo dimension. The
  capstone work is largely "lift this from one repo to N repos," not green-field.
- **Visibility is an explicitly non-overridable preference** ("Flags can't
  override it"). This establishes that shirabe already distinguishes preferences
  that flags *may* override (scope, execution mode) from preferences that they
  *may not* (visibility) — a useful precedent if any capstone property must be
  locked (e.g. you may not want `--no-consume-before-merge` to be expressible).
- **/plan already produces the merge-order data** (dependency graph + critical
  path). Convention 5 may need almost no new computation — just a cross-repo
  topological pass over data /plan already emits.

## Open Questions

- Where does capstone session state live so it reconnects across resets? Candidates
  (from the scope file): a `wip/` artifact, niwa workspace state (`instance.json`),
  or the capstone branch itself. The detection precedent (/work-on branch-context)
  reads git + PR + branch-name; a multi-repo capstone needs a workspace-level
  anchor. This is lead 5's territory — flagging the dependency.
- Should the worktree-policy preference (convention 4) live in each repo's
  CLAUDE.md or at the workspace root (`workspace-context.md` / overlay)? A
  per-repo policy fits the existing header mechanism; a workspace-wide policy needs
  a new read location shirabe skills don't currently consult.
- Does the capstone opt-in want to be a flag (`--capstone`) or a smart default
  that *always* engages when /scope→/work-on spans multiple repos? The author's
  framing ("the implementation of a single-pr plan on a multi-repo org") leans
  toward: capstone is the default behavior when the plan touches multiple repos,
  with `--no-capstone` to opt out. That would make it a pure smart default with no
  opt-in flag at all — worth deciding at crystallize.
- Can the immutable-preference precedent (visibility) tell us whether
  "consume-before-merge" should be locked? If the capstone's whole value is the
  completion signal, allowing a flag to disable consumption may be an anti-feature.

## Summary

shirabe already runs a layered flag > CLAUDE.md-header > hard-default stack (proven for execution mode and scope), and already contains a single-repo capstone in /work-on's shared-branch plan-orchestrator mode plus /plan's single-pr "consume-before-merge" lifecycle — so the capstone is a generalization, not green-field. Conventions 1, 2, 3, and 5 are session-shaped and best modeled as smart defaults (infer + announce + override), because the author's pain is re-pasting a contract and only smart defaults carry session state without forcing re-declaration; convention 2 is a derived property of 1, convention 3 is internal phase ordering, and convention 5 is computed from data /plan already emits. Only convention 4 (≤1 worktree per repo) is a stable fact that earns a durable CLAUDE.md preference with a per-invocation override, riding the exact mechanism that Repo Visibility and Default Scope already use.
