---
name: plan
description: >-
  Break work that is already decided into atomic issues someone can pick up in
  whatever order the dependencies allow, with the sequencing reasoning
  attached. Use it when the approach is settled and the open question is
  execution shape: "break this into issues", "file issues for this design",
  "what order should we do these in?", "this is too big for one PR, split it
  up", "what tasks do we need?", "how many issues is this?", or an accepted
  design handed over with "let's start building" — an agent that picks its
  own starting point ships the pieces in an order that does not build. Do NOT
  use it when the feature itself is not worked out and the requirements and
  approach are still open; that whole run is `/scope`, which calls this as its
  last hop. Do NOT use it to sequence FEATURES across an initiative rather
  than issues inside one (`/roadmap`), or to run the resulting plan
  (`/execute`).
argument-hint: '<doc-path-or-topic> [--upstream <roadmap-path>] [--walking-skeleton|--no-skeleton] [--strategic|--tactical] [--intent=continue|stop] [--coordinated|--no-coordinated] [--auto]'
allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh plan 2>&1 || true`

@.claude/shirabe-extensions/plan.md
@.claude/shirabe-extensions/plan.local.md

# Plan Skill

Plans turn accepted designs into implementable work. They define the decomposition
strategy, issue sequencing, and dependency graph that guide implementation through
/work-on. When planning a roadmap, the output is planning issues
(one per feature) rather than code-level issues.

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Lifecycle

**Lifecycle:** Working. Completion condition: the work-on cascade verifies the PLAN-Active state's terminal contract and finalizes the chain.

The lifecycle states are `Draft -> Active -> Done -> DELETED`,
mirroring the working-artifact lifecycle template established in
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`.

**Deleted by:** the work-on cascade's PLAN deletion step.

The PLAN file is removed from disk in the same atomic finalization
commit that transitions BRIEF/PRD to Done and DESIGN to Current.

## PLAN Doc Structure

Plans live at `docs/plans/PLAN-<topic>.md`. See the full specification at
`references/quality/plan-doc-structure.md`.

The required sections depend on the PLAN's shape: outline-shaped (every
`single-pr` PLAN, and a `multi-pr` or `coordinated` one at
`tracking_level: none`) or issue-carrying. The per-shape lists, which match
what `shirabe validate` checks, are under "Required Sections" in
`references/quality/plan-doc-structure.md`.

PLAN docs use a unified Draft -> Active -> Done -> DELETED lifecycle,
identical across execution modes. Only the Draft -> Active gate
differs, and it keys on **whether the transition will create GitHub
issues** -- the resolved Tracking Level -- not on `execution_mode`.
An activation that files issues requires approval, because that
is the moment remote artifacts appear; one that files none auto-fires
when /plan finishes authoring. So a `multi-pr` plan whose tracking
level is `none` auto-fires, and a `single-pr` plan whose level is
`issues` waits for approval. A committed PLAN at `status: Draft` is a
violation in either case. That includes a `/scope` run abandoned while `/plan`
was running: an abandoned run writes no PLAN at all, only its upstream
documents (`docs/decisions/DECISION-contradiction-scope-abandonment-draft-plan-2026-09-28.md`).

**Every path that files issues or a milestone asks first**, whatever the
mode: interactively the author answers the filing question, and "don't
file" writes the PLAN at tracking level `none` with outlines. **Under
`--auto` nobody is asked, so /plan files only when the repository's
CLAUDE.md declares `## Tracking Level: issues` or `issues-and-milestone`**
covering what the PLAN would file (an `issues` header covers no milestone).
Otherwise it writes the work items as outlines in the PLAN and files nothing,
even where the mode's default level would have filed. This is
`docs/decisions/DECISION-contradiction-plan-issue-filing-under-auto-2026-09-28.md`;
Phase 7's "Filing approval" step carries the procedure.

`coordinated` follows the same gate. An outline-shaped coordinated PLAN
(tracking level `none`, coordinated's default) files nothing, so it is
authored at `Active`. A coordinated PLAN at `issues` or
`issues-and-milestone` files issues only behind that filing approval.

## Decomposition Strategies

### Walking Skeleton

A thin vertical slice that exercises the full pipeline end-to-end, followed by issues
that thicken each layer. Use walking skeleton when:

- The design spans multiple components that interact at runtime
- Integration risk is high (new APIs, new data flows, new infrastructure)
- Early feedback on the end-to-end path is more valuable than component depth
- The `--walking-skeleton` flag is passed

### Horizontal Decomposition

Layer-by-layer implementation where each issue builds one component fully before
moving to the next. Use horizontal when:

- Components have clear, stable interfaces between them
- One component is a prerequisite for all others (parser before validator)
- The design describes independent modules with minimal runtime interaction
- The `--no-skeleton` flag is passed

Default behavior when neither flag is set: evaluate the design's component coupling.
Tightly coupled components with unclear interfaces favor walking skeleton. Loosely
coupled components with well-defined boundaries favor horizontal.

## Execution Mode Decision (single-pr vs multi-pr vs coordinated)

**Default: the repo's Delivery Preference.** Resolve
`## Delivery Preference: consolidated|atomic` on the
`flag > CLAUDE.md-header > consolidated` stack. Under `consolidated` -- the
default, and what every repo gets without declaring anything -- reach for one PR.
Anchored on principle P1 (usable value is the unit of work) in
`${CLAUDE_PLUGIN_ROOT}/references/workflow-principles.md`.

**Escape only on a named branch.** The three branches are defined once in
`${CLAUDE_PLUGIN_ROOT}/references/split-triggers.md` (plan profile); this surface
names them, and that file defines them:

1. **Hard Constraint** -- a named, non-optional condition that makes one PR
   impossible: cross-repo landing order; a workflow that must reach the default
   branch before it can be invoked; a merge gate between steps.
2. **Incremental Value** -- each resulting unit is independently useful to a
   reader who meets it alone. "Could be separate PRs" is not the test.
3. **Stated Preference** -- the repo declared `atomic`, and the decomposition
   permits a split. This is where reviewability lives; say so in those terms
   rather than restating it as a value claim.

Whichever branch fires is named in the PLAN's `split_rationale` field, and `L09`
checks it is there. A `single-pr` PLAN under `consolidated` fires no branch and
records nothing; a `single-pr` PLAN under `atomic` *is* the departure and still
owes a branch.

A roadmap input is always multi-pr under **Incremental Value** -- not because the
input is a roadmap, but because each feature is a cohesive deliverable that lands
observable value on its own (P1 again). The mechanism "the input is a roadmap" is
not the reason; the value the feature delivers is.

### Coordinated Mode

`coordinated` lands the work as one PR per repository and PR group, in one or
more repositories, in a recorded merge order behind a coordination PR that
merges last. Its contract (lifecycle, grouping, merge order, done-signal) is
`${CLAUDE_PLUGIN_ROOT}/references/coordination-strategy.md`, which this skill
binds to rather than restates; the PLAN-side
authoring details (the Repo/Group annotation rows, gate-node declarations, and
the contraction + acyclicity behavior) live in
`references/quality/plan-doc-structure.md` under "Coordinated Mode."

Each PR node carries `REPO`, `PR_GROUP`, `ISSUES`, and `ISSUE_SOURCE`
vars; `references/plan-to-tasks-contract.md` documents them.

## Complexity Classification

Each issue gets a complexity (simple, testable, or critical) that determines its
acceptance criteria template. Assign during Phase 3; see `references/phases/phase-3-decomposition.md`
for the full criteria and AC templates.

## Placeholder Conventions

Issues reference each other as `<<ISSUE:N>>`, N being the 1-based local
sequence number (format in `references/templates/agent-prompt.md`). Phase 7
replaces these with actual GitHub issue numbers after creation. In single-pr
mode, placeholders map to outline headings in the PLAN doc's Issue Outlines section.

## Validation Rules by Consumer Phase

See `references/quality/consumer-validation-rules.md` for validation rules that consuming skills must apply to PLAN artifacts.

---

## Planning Workflow

When invoked as `/plan`, this skill drives decomposition of a source document into
implementable issues. The source can be a design doc, PRD, or roadmap. The workflow
produces either GitHub artifacts (multi-pr) or a self-contained PLAN document
(single-pr), depending on execution mode. Roadmaps produce planning issues (one per
feature) rather than code-level issues.

### Input Detection

From `$ARGUMENTS` (after stripping flags):

1. **Empty** -- ask the user what to plan (document path or topic)
2. **Path matching a known pattern** -- use it as the source document:
   - `docs/designs/DESIGN-*.md` -- design doc (input_type: design)
   - `docs/prds/PRD-*.md` -- PRD (input_type: prd)
   - `docs/roadmaps/ROADMAP-*.md` -- roadmap (input_type: roadmap)
3. **Anything else** -- treat as a direct topic (input_type: topic). No upstream
   document is required. Use when /explore produced a clear scope with no open
   decisions, or when planning a well-understood list of capabilities directly.

### Context Resolution

#### 1. Parse Flags

Check `$ARGUMENTS` for flags before extracting the document path. Flags may
appear in any order after the document path.

**Execution mode flags:**
- `--auto` -- non-interactive execution; follow `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md`
  at all decision points; create `wip/plan_<topic>_decisions.md`
- `--interactive` -- force interactive (default)

If no mode flag, read CLAUDE.md `## Execution Mode:` header.

**Scope flags:**
- `--strategic` -- force strategic scope
- `--tactical` -- force tactical scope

**Decomposition flags:**
- `--walking-skeleton` -- force walking skeleton decomposition
- `--no-skeleton` -- force horizontal decomposition

**Upstream flag:**
- `--upstream <path>` -- the ROADMAP whose feature this plan implements. It is
  recorded in the produced PLAN's `upstream:` alongside the source document, and
  it is the reason the PLAN carries it rather than any durable artifact: a
  roadmap is deleted when its features land, and the PLAN is deleted by the same
  cascade and goes first, so the link cannot outlive its target. No durable
  document in the chain may name a roadmap.

**Intent and coordination flags** (direct-use flags; a parent such as `/scope`
forwards them verbatim when its caller passed them):
- `--intent=continue|stop` -- the caller's intent for the work after planning.
  Read only by step 5a, and only when the work splits: `continue` resolves a
  split to `coordinated`, `stop` to `multi-pr`. It never changes whether the work
  splits, and a PLAN that doesn't split is `single-pr` either way.
- `--coordinated` -- resolve a split to `coordinated`, outranking `--intent` and
  the `CLAUDE.md` header.
- `--no-coordinated` -- resolve a split to `multi-pr`, outranking `--intent` and
  the `CLAUDE.md` header.

A run with none of the three behaves exactly as before they existed. Validate
them before anything else runs, and before any `wip/plan_<topic>_*` file is
written. Each of these is a rejection with an error naming the offending flag,
and the run stops without writing anything:

- an `--intent` value other than `continue` or `stop` (`--intent=bogus`, a bare
  `--intent`, `--intent=none`);
- `--intent` given more than once, even with the same value (e.g.
  `--intent=stop --intent=continue`);
- `--coordinated` together with `--no-coordinated`, or either given twice.

If conflicting flags are present (e.g., both `--strategic` and `--tactical`), error
and ask user to pick one. Remove flags from arguments before using the remainder as
the document path.

##### The `--upstream` contract

Same flag, same meaning, same discipline `/brief`, `/prd`, `/roadmap`,
`/strategy` and `/comp` already carry.

**Parse it, and the token after it, before the positional argument is
classified.** The value is never tested as a document path in the input-detection
table, never treated as a topic, and never used to derive the topic slug. That
last part is what keeps the produced PLAN at `PLAN-<topic>.md` rather than
`PLAN-<roadmap-slug>.md`, and it is why the roadmap cannot simply be handed over
positionally: the positional slot is the input classifier and the slug source at
once, so a roadmap there changes what `/plan` is planning.

**A bare `--upstream` is a rejection**, naming the missing argument, before any
phase runs. A second occurrence is rejected the same way: the field records one
roadmap, and silently keeping the last would hide which one the plan named.

**Validate the value in this order.** The order is not cosmetic -- running the
filesystem checks first would reject every cross-repo roadmap and make the
visibility check, the only one that can say anything about such a value,
unreachable.

1. **Cross-repo discrimination.** An `owner/repo:path` value names a file in
   another repository. It is not a working-tree path: skip canonicalization, the
   directory confinement, and the tracked-by-git check, keep the basename rule on
   its file component, and go straight to check 6.
2. **Canonicalize and bounds-check.** Resolve against the repo root, resolve
   symlinks fully, and reject a canonical path outside the working tree. Unlike
   most path arguments this one ends up in a committed field, so a symlink out of
   the tree or a `../`-shaped value is a rejection rather than a curiosity.
3. **Confine to `<repo-root>/docs/roadmaps/`.** Not any `docs/roadmaps/` path
   segment beneath the root -- a fixture tree has one of its own, and a roadmap
   path laundered out of one is exactly what this refuses.
4. **Enforce the `ROADMAP-` basename**, on the file component for a cross-repo
   value.
5. **Reject a path under `wip/`, and reject an untracked path.** Both are
   record-time checks and both apply here, because `/plan` records. (`/brief`
   drops the tracked-by-git half precisely because it does not.)
6. **Omit rather than record** when this repo is Public and the roadmap lives in
   a private repo. Do not write the entry, do not fail, and tell the author the
   link is being dropped and why. Public documents must not reference private
   ones, and no tooling enforces that for a cross-repo value -- `shirabe
   validate` resolves nothing for one, so a public PLAN naming a private roadmap
   validates clean and always will. This check lives here rather than only in a
   parent skill so a standalone `/plan` runs it too.

**Quote it and pass it after `--` in every command it reaches.** The value flows
into `git ls-files` in the Phase 7 hygiene step and inside `shirabe validate`'s
own `R6` upstream resolution; both pass it after `--` so neither a leading dash
nor a shell metacharacter in a filename can change what runs. Validation is not
the guarantee -- the argument boundary is.

#### 2. Detect Visibility

Read the repo's CLAUDE.md (or CLAUDE.local.md) and look for:
```
## Repo Visibility: Private
```
or
```
## Repo Visibility: Public
```

If not found, infer from repo path:
- `private/` in path -- Private
- `public/` in path -- Public
- Unknown -- default to Private (safer)

Visibility is immutable -- public repos must never accidentally include private
references. Flags can't override it.

After detecting visibility, load the appropriate content governance skill:
- **Private repos:** Read `skills/private-content/SKILL.md`
- **Public repos:** Read `skills/public-content/SKILL.md`

#### 3. Detect Default Scope

If no scope flag was provided, read default from CLAUDE.md:
```
## Default Scope: Strategic
```
or
```
## Default Scope: Tactical
```

If not found, default to Tactical.

#### 4. Determine Effective Scope

```
Effective Scope = Flag Override (if present) OR Default Scope
```

#### 5. Log Effective Context

Output before proceeding:
```
Planning in [Strategic|Tactical] scope with [Private|Public] visibility...
```

### Handoff Validation

Only plan documents with the right status: Accepted designs/PRDs, Active roadmaps.
Phase 1 (`references/phases/phase-1-analysis.md`) has the full validation table
with error messages per status. Direct topics skip status validation.

### Resume Logic

Resume is based on topic-scoped wip/ artifacts. Topic is derived from the source
document filename: `DESIGN-foo-bar.md` produces topic `foo-bar`, `ROADMAP-foo-bar.md`
produces topic `foo-bar`.

```
dispatch read plan <topic> prints parent=<session>
                                              -> run under that parent; see ${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md,
                                                 then continue down this ladder
if GitHub issues exist for this design        -> Resume at Phase 7 (verify/complete)
if wip/plan_<topic>_review.md exists          -> Resume at Phase 7
if wip/plan_<topic>_dependencies.md exists    -> Resume at Phase 6
if wip/plan_<topic>_manifest.json exists      -> Resume at Phase 5
if wip/plan_<topic>_decomposition.md exists   -> Resume at Phase 4
if wip/plan_<topic>_milestones.md exists      -> Resume at Phase 3
if wip/plan_<topic>_analysis.md exists        -> Resume at Phase 2
else                                          -> Start at Phase 1
```

To check for existing GitHub issues:
```bash
gh issue list --search "Design: <design-doc-path>" --json number,title,state
```

When resuming, read the existing artifact to restore context before continuing.

**Running under a parent.** The first row runs
`"${CLAUDE_PLUGIN_ROOT}/scripts/skill-session.sh" dispatch read plan <topic>`
with the topic this run works on (derived from the source document's file
name, as above). A printed `parent=<session>` line means `/plan` runs under that parent (`scope-<topic>` or
`charter-<topic>`), with the parent's upfront decision in the `rationale=` and
`suppress_status_aware_prompt=` lines; what changes under a parent is in
`${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`.
Four cases are no match. Three print nothing and exit 0, and the run is a
direct one with the rows below unchanged: no parent session, a finished parent
session, and a parent whose `chain/dispatch` key names another child. The
fourth, two parent sessions that both name `/plan`, exits 3: don't pick one
and don't run directly; stop and report both sessions, which the script names
on stderr, so the author can clear the stale key. Exit 127 (koto not
installed) means no parent can be running, so the run is direct; any other
non-zero exit stops the run with the script's message. `/plan` opens no
session of its own here.

The first row is not a resume point: the rest of the ladder applies the same
way under a parent, and the dispatch key only changes which steps the run
skips, as the next paragraph says.

**Under `/scope`'s dispatch key** `/plan` still reaches its own verdict (the Phase 6
review) and makes its own status transition (Phase 7's step 7.5), but skips
everything that publishes or routes: it pushes nothing, opens no pull request,
creates no branch, makes no cleanup commit, and asks no routing question, so
step 7.6's cleanup is left to `/scope` and step 7.8's upstream-issue question
and its `gh issue edit` are skipped. This is
shape 6, Parent-owned-publishing, in `${CLAUDE_PLUGIN_ROOT}/references/fixes/sub-agent-dispatch.md`,
recorded in `docs/decisions/DECISION-contradiction-child-steps-under-scope-2026-09-28.md`.
Under `--auto` it takes the recommended verdict and names it in its output.

### Workflow Phases

What Phases 4 and 7 produce depends on the execution mode:

- **single-pr**: Phase 4 agents produce structured outlines (not full issue bodies).
  Phase 7 writes them into the PLAN doc's Issue Outlines section. No GitHub issues or
  milestone created. The PLAN is authored at Active.
- **multi-pr**: Phase 4 agents produce full issue body files. At a filing tracking
  level, Phase 7 creates the GitHub issues (and milestone) behind the filing approval
  and populates the Implementation Issues table; at `none`, including an `--auto`
  run whose CLAUDE.md declares no filing level, it writes outlines and files
  nothing. PLAN status set to Active.
- **coordinated**: at tracking level `none` (its default) Phase 4 agents produce
  structured outlines and Phase 7 writes them, each with `**Repo**:` and
  `**Group**:`, into Issue Outlines with nothing filed. At `issues` or
  `issues-and-milestone` agents produce full issue bodies and Phase 7 files them
  behind the filing approval.

### Phase Execution

Execute phases sequentially by reading the corresponding phase file. Use the effective
scope from Context Resolution throughout.

1. **Analysis**: Understand source document scope and components/features
   - Read: `references/phases/phase-1-analysis.md`
   - Artifact: `wip/plan_<topic>_analysis.md`

2. **Milestone**: Derive milestone from source document
   - Read: `references/phases/phase-2-milestone.md`
   - Artifact: `wip/plan_<topic>_milestones.md`

3. **Decomposition**: Break into atomic issues, then value confirmation (3.5a) + execution mode selection (3.6)
   - Read: `references/phases/phase-3-decomposition.md`
   - Artifact: `wip/plan_<topic>_decomposition.md` (includes value-guard result and execution mode decision)

4. **Generation**: Generate rich issue bodies via parallel agents
   - Read: `references/phases/phase-4-agent-generation.md`
   - Artifact: `wip/plan_<topic>_issue_*.md` + `wip/plan_<topic>_manifest.json`

5. **Dependencies**: Map issue dependencies and sequencing
   - Read: `references/phases/phase-5-dependencies.md`
   - Artifact: `wip/plan_<topic>_dependencies.md`

6. **Review**: AI validates completeness, sequencing, and complexity assignments
   - Read: `references/phases/phase-6-review.md`
   - Artifact: `wip/plan_<topic>_review.md`

7. **Creation**: Create PLAN doc and optional GitHub artifacts
   - Read: `references/phases/phase-7-creation.md`
   - Artifact: `docs/plans/PLAN-<topic>.md`
   - multi-pr: GitHub milestone + issues behind the filing approval; outlines at `none`
   - single-pr: PLAN doc with Issue Outlines, no GitHub artifacts unless a stated
     filing level is approved
   - coordinated: PLAN doc with Repo/Group-tagged outlines at `none`; issues with
     Repo/Group rows, behind a filing approval, only at `issues` levels

### Critical Requirements

- **Atomic Issues**: each issue should be independent and completable in one session
- **Topic Scoping**: all wip/ artifacts include `<topic>` in the filename

### Output

Final artifacts depend on execution mode:

**multi-pr mode (design/prd/topic input):**
- `docs/plans/PLAN-<topic>.md` with status Active
- At a filing level, after the filing approval: a GitHub milestone (1:1 with the
  plan, at `issues-and-milestone`) and GitHub issues with complexity labels,
  acceptance criteria, and milestone assignment
- At `none`: Issue Outlines instead, and nothing filed
- Source design doc status updated to "Planned"

**single-pr mode:**
- `docs/plans/PLAN-<topic>.md` with status Active
- Issue Outlines section populated with structured outlines (goal, AC, dependencies)
- No GitHub issues or milestone created, unless a stated `issues` or
  `issues-and-milestone` level is approved at the filing approval
- Source design doc status updated to "Planned"
- Not available for roadmap input (roadmap mode is always multi-pr)

**coordinated mode, tracking level `none` (the default):**
- `docs/plans/PLAN-<topic>.md` with status Active, `execution_mode: coordinated`,
  `split_mode_source`, and `tracking_level: none`
- Issue Outlines, each with `**Repo**:` and `**Group**:`, plus any `### Gate:`
  blocks and a Dependency Graph
- No GitHub issues or milestone created
- Source design doc status updated to "Planned"

**coordinated mode, tracking level `issues` or `issues-and-milestone`:**
- `docs/plans/PLAN-<topic>.md` with status Active and the resolved `tracking_level`
- GitHub issues (and, at `issues-and-milestone`, a milestone), filed only after
  the filing approval
- An Implementation Issues table with a `_Repo: ... | Group: ..._` row under each
  issue and any `_Gate:` rows
- Source design doc status updated to "Planned"

---

## Team Shape

`/plan`'s team shape is declared in [`team.yaml`](./team.yaml) as the
machine-readable contract surface. The child layer spawns one worker
peer role: `decomposer` (worker, upper_bound 20, phase-4-agent-
generation), one decomposer per outline emitted by Phase 3. `/plan`'s
Phase 6 also invokes `/review-plan` as a sub-skill via inline
Skill-tool dispatch; this is a CHILD invocation under the Dispatch
Contract, NOT a peer, and is therefore not declared in team.yaml.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.

## Reference Files

| File | When to load |
|------|-------------|
| `references/templates/agent-prompt.md` | Phase 4 agent spawning (design/prd) |
| `references/templates/agent-prompt-planning.md` | Phase 4 agent spawning (roadmap) |
| `references/templates/ac-critical.md` | Phase 4 critical complexity |
| `references/templates/ac-simple.md` | Phase 4 simple complexity |
| `references/templates/ac-testable.md` | Phase 4 testable complexity |
| `references/templates/walking-skeleton-issue.md` | Phase 4 walking skeleton |
| `references/quality/plan-doc-structure.md` | Phase 7 PLAN doc construction |
| `references/quality/plan-doc-examples.md` | Phase 7 (if examples needed) |
| `references/quality/consumer-validation-rules.md` | When implementing a consuming skill that must validate PLAN artifacts |
| `${CLAUDE_SKILL_DIR}/scripts/resolve-split-mode.sh` | Phase 3 step 5a (split mode) |
| `${CLAUDE_SKILL_DIR}/scripts/build-dependency-graph.sh` | Phase 5 |
| `${CLAUDE_SKILL_DIR}/scripts/create-issues-batch.sh` | Phase 7 multi-pr and coordinated filing (**stable sub-operation** via `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/create-issues-batch.sh`) |
| `${CLAUDE_SKILL_DIR}/scripts/create-issue.sh` | Phase 7 multi-pr (**stable sub-operation** via `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/create-issue.sh`) |
| `${CLAUDE_SKILL_DIR}/scripts/plan-to-tasks.sh` | When emitting koto task-entry JSON from a PLAN doc (**stable sub-operation** via `${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh`) |
| `${CLAUDE_SKILL_DIR}/scripts/render-template.sh` | Phase 4 |
| `${CLAUDE_SKILL_DIR}/scripts/apply-complexity-label.sh` | Phase 7 multi-pr |
