---
name: roadmap
description: >-
  Structured workflow for creating Roadmap documents that sequence multiple
  features into a coordinated initiative. Use when planning multi-feature
  work that needs dependency tracking, sequencing rationale, and progress
  monitoring. Triggers on "create a roadmap for X", "plan the rollout of Y",
  "sequence these features", or any request to coordinate multiple features
  into an ordered plan. Do NOT use for single-feature requirements (/prd),
  strategic justification (/vision), technical architecture (/design), or
  open-ended exploration (/explore). Drives a multi-phase workflow:
  conversational scoping, parallel research agents, structured drafting,
  and jury review.
argument-hint: '<initiative topic>'
---

@.claude/shirabe-extensions/roadmap.md
@.claude/shirabe-extensions/roadmap.local.md

# Roadmap Documents

Roadmap documents sequence multiple features into a coordinated initiative.
They capture the theme (why these features belong together), the features
themselves, dependency relationships, sequencing rationale, and progress.
They sit downstream of VISIONs (which justify why a project exists) and
upstream of PRDs (which define individual features in detail).

**Writing style:** Read `skills/writing-style/SKILL.md` for guidance.

## Artifact Lifecycle

**Lifecycle:** Working. Completion condition: all features on the ROADMAP are at status Done AND all referenced GitHub issues are closed.

The lifecycle states are `Draft -> Active -> Done -> DELETED`,
mirroring the working-artifact lifecycle template established in
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`.

**Deleted by:** the work-on cascade's handle_roadmap_deletion step.


The handle_roadmap_deletion step is the new cascade extension shipped
alongside this contract. It runs after the existing PLAN finalization
step, inside the same cascade window the work-on flow already uses.

## Roadmap Format

See `references/roadmap-format.md` for the full format specification:
frontmatter schema, required and optional sections, lifecycle states,
validation rules, and quality guidance. Load it during Phases 3 and 4.

## File Location

Roadmap documents live at `docs/roadmaps/ROADMAP-<topic>.md` (kebab-case).
No directory movement at any lifecycle stage -- all roadmaps stay in
`docs/roadmaps/` regardless of status. Stable paths keep cross-references
durable and git blame readable.

---

## Creating a Roadmap Document

When invoked as `/roadmap`, this skill drives a structured creation workflow
that scopes the initiative conversationally, fans out research agents to
validate features and dependencies, drafts the ROADMAP with section-level
review, and validates through jury review.

Unlike an explore workflow (which is open-ended and can produce any artifact
type), /roadmap always produces a ROADMAP document. Use /roadmap when you
know you need to sequence multiple features. Use an explore workflow when
you don't know what artifact type you need yet.

### Input Modes

From `$ARGUMENTS`:

1. **Empty** -- ask the user what initiative or theme they want to create a
   roadmap for
2. **Path to existing ROADMAP** with lifecycle verb (`activate`, `done`) --
   execute the lifecycle transition via `shirabe transition <roadmap-path>
   <status>`
3. **`populate <path>`** -- populate the roadmap's reserved Implementation
   Issues and Dependency Graph sections by invoking the
   `shirabe roadmap populate` subcommand on the shirabe CLI. Native to the
   roadmap; replaces the plan re-entry path that rewrote these sections by
   prose substitution. Two modes, selected by the `## Roadmap Issues:`
   preference: under `required` (or absent header) the subcommand creates
   one GitHub issue per feature and the table/diagram key on those issues;
   under `optional` it renders the sections from feature context with no
   issues created. See [Populating the Issues Table](#populating-the-issues-table)
   below.
4. **Anything else** -- use as the starting topic for Phase 1 scoping

### Standalone Entry and Handoff Detection

/roadmap works both standalone and as a handoff target from /explore.

On startup, check for `wip/roadmap_<topic>_scope.md`. If it exists, an
/explore session already ran Phase 5 and wrote the handoff artifact with
synthesized findings (theme statement, candidate features, coverage notes).
Skip Phase 1 (scoping) and proceed directly to Phase 2 (discover) -- the
scope file provides the theme and candidate features as investigation
targets.

If no handoff artifact exists, start from Phase 1.

### Context Resolution

**Execution mode:** check `$ARGUMENTS` for `--auto` or `--interactive`
flags, then CLAUDE.md `## Execution Mode:` header (default: `interactive`).
Also parse `--max-rounds=N` (default: 2 for roadmap's discover loop). In
--auto mode, follow decision-protocol conventions -- make decisions based on
evidence rather than blocking on user input. Create
`wip/roadmap_<topic>_decisions.md` to track decisions.

**Roadmap issues preference:** read CLAUDE.md's `## Roadmap Issues:`
header the same way `## Execution Mode:` is read -- grep the header,
take the value after the colon. Resolve to `required` when the header
is absent or the value is anything other than `optional` (fail-closed
toward the issue-creating, human-gated path). Record the resolved
value (`optional` or `required`) in the run's context so the populate
phase can branch on it. The validator never reads this header; it's a
skill-only preference. See
`${CLAUDE_PLUGIN_ROOT}/references/fixes/claude-md-conventions.md` for
the header format.

**Upstream:** check `$ARGUMENTS` for `--upstream <path>`. If present, the
path is stored and written to frontmatter during Phase 3 (draft). Typically
points to a VISION document. Passed by /explore when it identified a VISION
during crystallization, or by the user in standalone invocation. When not
provided, the upstream field is omitted from frontmatter.

Log: `Drafting roadmap...`

### Workflow Phases

```
Phase 0: SETUP --> Phase 1: SCOPE --> Phase 2: DISCOVER --> Phase 3: DRAFT --> Phase 4: VALIDATE
(branch)          (conversational)   (agents fan out)     (iterative)        (jury review)
                       |                                       ^
                       |                                       |
                       +--- may loop back to DISCOVER or DRAFT-+
```

| Phase | Purpose | Artifact |
|-------|---------|----------|
| 0. Setup | Create feature branch, detect context | On topic branch |
| 1. Scope | Conversational scoping (or skip if handoff exists) | Theme + candidate features + coverage dimensions |
| 2. Discover | Parallel research agents investigate features | Research findings in wip/ |
| 3. Draft | Produce ROADMAP draft | Complete ROADMAP draft |
| 4. Validate | Jury review (theme coherence, sequencing, annotations) | Validated ROADMAP |

Phase 1 tracks 6 roadmap-specific coverage dimensions:

| Dimension | What to understand |
|-----------|-------------------|
| Theme clarity | What initiative, why coordinated sequencing? |
| Feature identification | What features, at least 2? Any gaps? |
| Dependency awareness | Which features depend on each other? |
| Sequencing constraints | Hard blockers vs soft preferences? |
| Downstream artifact state | What does each feature need next (needs-*)? |
| Scope boundaries | What's in this roadmap vs excluded? |

Phase 2 agents investigate: feature completeness (gaps, granularity),
dependency accuracy (hidden dependencies, stated dependency validation),
and sequencing justification (ordering rationale, parallelization
opportunities, needs-* annotation accuracy).

Phase 4 jury focuses on roadmap-specific quality: Do features belong
together under the theme? Are dependencies explicit, not implied? Is there
circular dependency? Do needs-* labels match feature descriptions? Does the
roadmap avoid downstream content (requirements, architecture, timelines)?
Are there at least 2 features?

### Resume Logic

```
parent_orchestration sentinel in wip/scope_<topic>_state.md or wip/charter_<topic>_state.md
                                                           -> see references/fixes/sub-agent-dispatch.md
ROADMAP exists with status "Active" or "Done"              -> Offer to revise or start fresh
ROADMAP exists with status "Draft"                         -> Offer to continue from Phase 3
wip/research/roadmap_<topic>_phase2_*.md files exist       -> Resume at Phase 3
wip/roadmap_<topic>_scope.md exists                        -> Resume at Phase 2
On a branch related to the topic                           -> Resume at Phase 1
On main or unrelated branch                                -> Start at Phase 0
```

Phase 0 detection: if the parent-chain sentinel is present in
`wip/scope_<topic>_state.md` (tactical) or `wip/charter_<topic>_state.md`
(strategic), see `references/fixes/sub-agent-dispatch.md` for the
fallback shape that applies. Behavior under direct invocation is
unchanged when the sentinel is absent.

### Critical Requirements

- **Conversational First**: Phase 1 is a dialogue, not a form to fill out
- **Research Before Drafting**: Don't draft sequencing you haven't validated
- **Minimum 2 Features**: Single-feature work doesn't need a roadmap -- use
  a PRD instead
- **User Review**: Never finalize a ROADMAP the user hasn't reviewed and
  given feedback on
- **Jury Validation**: Phase 4 is not optional -- theme coherence,
  sequencing validity, and annotation accuracy all get checked

### Execution

Execute phases sequentially by reading the corresponding phase file:

0. **Setup**: Ensure work happens on a feature branch
   - If already on a branch that matches the topic, skip branch creation
   - If on `main` or an unrelated branch, create `docs/<topic>` (kebab-case)
   - If unsure whether the current branch is related, ask the user

1. **Scope**: Conversational scoping
   - Instructions: `references/phases/phase-1-scope.md`
   - Skipped when handoff artifact (`wip/roadmap_<topic>_scope.md`) exists

2. **Discover**: Parallel research agents investigate features
   - Instructions: `references/phases/phase-2-discover.md`

3. **Draft**: Produce ROADMAP draft and walk through with user
   - Instructions: `references/phases/phase-3-draft.md`

4. **Validate**: Jury review and finalization
   - Instructions: `references/phases/phase-4-validate.md`

### Output

Final artifact: `docs/roadmaps/ROADMAP-<topic>.md`, created in Draft status.
After user approval, transition to Active via `shirabe transition
<roadmap-path> Active`.

A roadmap must be Active before merging to main. Draft roadmaps should not
appear on the default branch -- the transition to Active signals that the
feature list is locked and the sequencing is approved.

After activation, suggest next steps:

| Situation | Suggestion |
|-----------|-----------|
| Features need requirements | /prd for individual features |
| Features need technical design | /design for architecture decisions |
| Ready to break into issues | /plan to decompose into implementation work |

---

## Lifecycle Management

Roadmaps use the four-state working lifecycle: Draft -> Active -> Done -> DELETED.

| Transition | Verb | Precondition |
|------------|------|-------------|
| Draft -> Active | `activate` | Feature list complete, human approval |
| Active -> Done | `done` | All features terminal (delivered or dropped) |
| Done -> DELETED | `cascade` | All features Done AND all referenced issues closed, triggered by work-on cascade |

**Forbidden transitions:** Active -> Draft (no regression), Draft -> Done
(can't skip Active). Done -> DELETED is cascade-only -- it runs from the
work-on cascade's `handle_roadmap_deletion` step and is not human-invokable;
no `shirabe transition <path> DELETED` form exists.

Done roadmaps retain all content: features, sequencing rationale, progress,
and any Implementation Issues table or Mermaid dependency graph added by
/plan. Nothing is stripped. Done roadmaps are historical artifacts that
remain on disk until the cascade deletes them.

The four-state machinery here mirrors the working-artifact lifecycle template
established in `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`,
matching the contract recorded in the `## Artifact Lifecycle` section above.

Lifecycle verbs are invoked as:
```
/roadmap activate docs/roadmaps/ROADMAP-<topic>.md
/roadmap done docs/roadmaps/ROADMAP-<topic>.md
```

Both delegate to `shirabe transition`. The cascade-only DELETED transition
has no `/roadmap` verb form.

### Chain CI Gate (DRAFT-vs-READY Discipline)

The `lifecycle.yml` reusable workflow runs on every PR with strictness
conditional on the PR's `draft` state. A DRAFT PR passes against
mid-PR chain states; a READY PR requires the chain to be at one of
its terminals — single-pr at-merge (PLAN deleted, BRIEF/PRD Done,
DESIGN Current) or multi-pr in-flight (BRIEF Accepted, PRD
Accepted/In Progress, DESIGN Current, PLAN Active) for intermediate
multi-pr PRs, or multi-pr at-merge for the final verify-then-delete
PR. ROADMAP-rooted multi-pr chains follow the same shape — the
final per-feature PR in the chain runs the work-on cascade, which
performs the atomic PLAN-delete plus BRIEF/PRD/DESIGN-transition
commit before `gh pr ready` fires. The CI gate is the backstop for
authors who bypass the cascade.

See `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`
and `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`
for the rationale on the `--strict` CLI flag and the cascade
trigger mechanism.

---

## Populating the Issues Table

The roadmap's reserved Implementation Issues and Dependency Graph sections
are populated by the `shirabe roadmap populate` subcommand on the
`shirabe` CLI. This is a roadmap-native path: the subcommand reads the
Features section using the shared `shirabe-validate` parser, builds a
per-feature manifest, then renders the canonical table and dependency
diagram and writes both into the reserved sections by **structural section
replacement** (the body between each section's heading and the next `##`
heading is replaced; the heading itself is preserved).

The subcommand runs in one of two modes, selected by the `## Roadmap
Issues:` preference resolved during setup ([Context
Resolution](#context-resolution)):

- **`required` (or absent header) -- issue-creating mode.** The default,
  and behaviorally unchanged from before this preference existed. The
  subcommand creates one GitHub issue per feature (one `gh issue create`
  invocation per feature, discrete args), then renders an issue-keyed
  table and diagram. This path goes through the R14 approval gate below.
- **`optional` -- issueless mode.** Invoke the subcommand with
  `--no-issues`. It creates no issues -- no `gh issue create` runs -- and
  renders the sections from feature context: a feature-keyed table (the
  feature's `needs-*` label in the Issues column) and an `F<n>`-node
  diagram, with Dependencies cells as bare feature keys. The R14 gate is
  skipped, since there are no issues to approve (see below).

The roadmap profile shape (`Feature | Issues | Dependencies | Status`) and
the dependency-diagram convention come from
`${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` and
`${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md`.

### Invocation

```
/roadmap populate <path>
```

Or, equivalently, invoking the CLI directly from the project root. The
issue-creating form (`## Roadmap Issues: required`):

```bash
shirabe roadmap populate <roadmap-path> \
    --milestone "<Milestone Name>" \
    --milestone-description "Roadmap: <roadmap-path>" \
    --output-map "<mapping-output-path>"
```

The issueless form (`## Roadmap Issues: optional`) drops the milestone and
mapping flags -- no issues are created, so there's nothing to file under a
milestone or map:

```bash
shirabe roadmap populate <roadmap-path> --no-issues
```

Options:
- `--milestone <name>` -- milestone for the created issues
- `--milestone-description <desc>` -- milestone description
- `--mapping <file>` -- pre-existing id->github_number mapping (re-render only)
- `--output-map <file>` -- write the final id->github_number mapping
- `--repo <owner/repo>` -- override the repo used when rendering issue links
- `--no-issues` -- issueless mode: create no issues and render the reserved
  sections feature-keyed from the Features section. Set by the skill when
  `## Roadmap Issues:` resolves to `optional`.
- `--dry-run` -- skip `gh` invocations; synthesize a deterministic mapping
- `-h, --help` -- print help

### R14 approval gate (lives in this caller, not in the subcommand)

Issue creation is the gated step (R14 in the requirements). The gate lives
in this skill phase, NOT in the subcommand. The subcommand is a primitive
that creates issues when invoked.

**R14 gates issue creation, so it applies only in issue-creating mode.**
Under `## Roadmap Issues: required` (or an absent header), present the gate
as described below before invoking the subcommand. Under `## Roadmap
Issues: optional`, the subcommand runs with `--no-issues` and creates no
issues -- there is nothing to approve, so skip the gate entirely. Skipping
it removes a gate over an action that does not occur; it does not bypass
approval over any side effect.

The rest of this section describes the gate as it applies in
issue-creating mode.

**Interactive runs.** Before invoking the subcommand without `--dry-run`,
present a summary of the features that will be turned into issues (count,
names, the planned milestone). Stop for the author's approval. On
approval, invoke the subcommand. On rejection, abort without calling it.

**`--auto` runs.** Record an `assumed` approval decision block per
`${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` at high review
priority (the block surfaces in the terminal summary and the PR body),
then invoke the subcommand. The non-interactive guarantee is preserved.

A separate `--dry-run` invocation is available for the skill to inspect
what the subcommand will write before the gate is reached; under
`--dry-run` no GitHub API calls are made.

### Security guarantees

- Manifest values (feature names, titles) are passed to `gh` as discrete
  `Command::arg(...)` arguments by Rust's `std::process::Command`. No
  shell is invoked, so content with shell metacharacters cannot inject a
  command -- the title round-trips verbatim into the issue and the
  rendered table.
- Section-replacement writes are atomic: render into a temp file inside
  the roadmap's parent directory, then `std::fs::rename` over the
  original. A failed run leaves the roadmap unchanged byte-for-byte.

---

## Team Shape

`/roadmap`'s team shape is declared in [`team.yaml`](./team.yaml) as
the machine-readable contract surface. The child layer spawns three
reviewer peers at Phase 4 (`theme-coherence-reviewer`,
`sequencing-and-dependency-reviewer`,
`annotation-and-boundary-reviewer`) to validate the drafted ROADMAP.

See [Dispatch Contract](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md) for v1 parent-side consumption rules.

## Reference Files

| File | When to load |
|------|-------------|
| `references/roadmap-format.md` | Phase 3 (drafting) and Phase 4 (validation) |
| `references/phases/phase-1-scope.md` | Phase 1 |
| `references/phases/phase-2-discover.md` | Phase 2 |
| `references/phases/phase-3-draft.md` | Phase 3 |
| `references/phases/phase-4-validate.md` | Phase 4 |
| `${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` | Populating reserved sections |
| `${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md` | Populating reserved sections |
| `${CLAUDE_PLUGIN_ROOT}/references/decision-protocol.md` | R14 approval gate under `--auto` |
