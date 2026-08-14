---
name: roadmap
description: >-
  Structured workflow for creating Roadmap documents that sequence a
  strategy's features into a coordinated initiative and serve as the
  progress ledger for its execution. Use when planning work that needs
  dependency tracking, sequencing rationale, and progress monitoring, or
  when a strategy needs a bridge into the tactical chain. Triggers on
  "create a roadmap for X", "plan the rollout of Y", "sequence these
  features", or any request to turn a strategy's work into an ordered,
  tracked plan. Do NOT use for a single feature's requirements (/prd) or
  framing (/brief), strategic justification (/vision), technical
  architecture (/design), or open-ended exploration (/explore). Drives a
  multi-phase workflow: conversational scoping, parallel research agents,
  structured drafting, and jury review.
argument-hint: '<initiative topic>'
---

@.claude/shirabe-extensions/roadmap.md
@.claude/shirabe-extensions/roadmap.local.md

# Roadmap Documents

Roadmap documents sequence features into a coordinated initiative. They
capture the theme (why these features belong together), the features
themselves, dependency relationships, sequencing rationale, and progress.
They are the last link in the strategic chain (VISION -> STRATEGY ->
ROADMAP): a roadmap's upstream is the STRATEGY it sequences -- its
immediate neighbour, never the VISION two levels up -- and downstream of
it sit the BRIEFs and PRDs that frame and define individual features in
detail.

## What a Roadmap Is For

Sequencing is only half a roadmap's job. The other half matters just as
much:

- **It is the progress ledger for a strategy's execution.** The per-feature
  status in the Features and Progress sections is the only place that
  records how far along the work is, and the completion cascade updates it
  as downstream plans land. Without a roadmap, a strategy has no ledger.
- **It is the only bridge from the strategic chain to the tactical one.**
  `/brief` is framed against a ROADMAP -- never a STRATEGY, and never a
  PRD, which sits downstream of a BRIEF rather than above it. The brief
  reads it and records nothing; the crossing is recorded on the PLAN the
  chain produces, because a durable document may not name a ROADMAP that
  the cascade deletes. A strategy
  whose work is a single feature would be stranded if it could not have a
  roadmap: no legal path into `/scope`, and no progress tracking.

Both jobs work with one feature. **A roadmap requires at least one feature;
there is no two-feature floor.** Most roadmaps do sequence several features,
and coordinated multi-feature work is where a roadmap earns the most --
but a one-feature roadmap is a coherent ledger, not a degenerate one, and
refusing to write it strands actionable work for no benefit.

A roadmap with zero features is still malformed: there is nothing to track,
nothing to sequence, and nothing to hand downstream. That is the only count
`shirabe transition` rejects on `Draft -> Active`.

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
know you need a sequenced, tracked feature list for a strategy's execution.
Use an explore workflow when you don't know what artifact type you need yet.

### Input Modes

From `$ARGUMENTS`:

1. **Empty** -- ask the user what initiative or theme they want to create a
   roadmap for
2. **Path to existing ROADMAP** with lifecycle verb (`activate`, `done`) --
   execute the lifecycle transition via `shirabe transition <roadmap-path>
   <status>`
3. **`populate <path>`** -- the issue-filing action, and the way to
   re-populate a roadmap's reserved sections out of band. A normal
   `/roadmap` run already fills those sections issuelessly (Phase 4), so
   the reason to type this is usually to file GitHub issues for an
   already-approved roadmap. Invokes the `shirabe roadmap populate`
   subcommand on the shirabe CLI. The mode resolves on
   `flag > ## Roadmap Issues: header > issueless default`: pass
   `--issues` to create one GitHub issue per feature and key the
   table/diagram on those issues, or `--no-issues` to re-render from
   feature context with no issues created. Issue filing goes through the
   R14 approval gate; issueless population does not. See
   [Populating the Issues Table](#populating-the-issues-table) below.
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
take the value after the colon. Resolve to `required` only when the
value is exactly `required`; resolve to `optional` when the header is
absent or carries any other value (fail-closed toward the path with no
remote side effect). Record the resolved value in the run's context so
the populate phase can branch on it. The validator never reads this
header; it's a skill-only preference. See
`${CLAUDE_PLUGIN_ROOT}/references/fixes/claude-md-conventions.md` for
the header format.

The preference governs one thing only: which mode a human-invoked
`/roadmap populate <path>` picks when they pass no flag. It does NOT
govern the automatic population this workflow performs in Phase 4 and
on the activate path -- those are always issueless, because an
automatic run must never create issues. The full resolution stack is
`flag > ## Roadmap Issues: header > issueless default`.

**Upstream:** check `$ARGUMENTS` for `--upstream <path>`. If present, the
path is stored and written to frontmatter during Phase 3 (draft). It points
to the STRATEGY this roadmap sequences -- the roadmap's immediate neighbour
one level up the strategic chain. `/charter` passes it on every chain it
runs; a user invoking `/roadmap` standalone passes it when a STRATEGY
exists. When no STRATEGY exists, omit the flag rather than reaching past
the neighbour to a VISION; the upstream field is then omitted from
frontmatter. See `references/roadmap-format.md` for the rule and why the
links stay one level deep.

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
| Theme clarity | What initiative, why track it as one thing? |
| Feature identification | What features? Any gaps? |
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
Is there at least one feature to track?

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
- **At Least One Feature**: A roadmap with no features has nothing to
  sequence and nothing to track. One feature is enough -- see [What a
  Roadmap Is For](#what-a-roadmap-is-for) for why there is no two-feature
  floor
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

The subcommand runs in one of two modes. **Always pass one of the two mode
flags explicitly.** The subcommand defaults to issueless when neither is
given, but that default is a backstop for a human at a shell -- no path in
this skill may depend on it:

- **Issueless mode (`--no-issues`).** Creates no issues -- no
  `gh issue create` runs, and no `gh` call of any kind -- and renders the
  sections from feature context: a table keyed on each feature's label (the
  feature's `needs-*` label in the Issues column) and an `F<n>`-node
  diagram, with Dependencies cells naming features by those same `F<n>`
  indices so the column stays narrow while the key column stays readable. A
  label that can't serve as a table key falls back to `F<n>` and the run
  says so on stderr. The R14 gate is skipped, since there are no issues to
  approve (see below). This is what the automatic population in Phase 4 and
  on the activate path uses, unconditionally.
- **Issue-creating mode (`--issues`).** Creates one GitHub issue per
  feature (one `gh issue create` invocation per feature, discrete args),
  then renders an issue-keyed table and diagram. This path goes through the
  R14 approval gate below. Reached only by an explicit human invocation of
  `/roadmap populate <path>`, after the roadmap is approved.

Passing both flags is an error: the subcommand rejects the invocation
during argument parsing, so nothing is written and no `gh` call is made.

### When population happens

1. **Automatically, during a `/roadmap` run.** Phase 4 populates
   issuelessly after the jury findings resolve and before the approval
   walkthrough, so the author reviews a complete roadmap rather than an
   empty skeleton. See `references/phases/phase-4-validate.md`.
2. **Automatically, on the `Draft -> Active` transition.** The activate
   path re-runs the issueless population before `shirabe transition`. This
   catches a Features section edited during review and covers roadmaps
   created before automatic population existed. Populate is idempotent, so
   the re-run is a no-op when nothing changed.
3. **Explicitly, to file issues.** After the roadmap is approved, a human
   runs `/roadmap populate <path> --issues`. This is the only path that
   creates issues, and it regenerates both sections so the table carries
   issue links instead of labels.

The roadmap profile shape (`Feature | Issues | Dependencies | Status`) and
the dependency-diagram convention come from
`${CLAUDE_PLUGIN_ROOT}/references/issues-table.md` and
`${CLAUDE_PLUGIN_ROOT}/references/dependency-diagram.md`.

### Invocation

```
/roadmap populate <path>
```

Or, equivalently, invoking the CLI directly from the project root. The
issue-creating form, used by the post-approval issue-filing action:

```bash
shirabe roadmap populate <roadmap-path> --issues \
    --milestone "<Milestone Name>" \
    --milestone-description "Roadmap: <roadmap-path>" \
    --output-map "<mapping-output-path>"
```

The issueless form drops the milestone and mapping flags -- no issues are
created, so there's nothing to file under a milestone or map:

```bash
shirabe roadmap populate <roadmap-path> --no-issues
```

Both forms name their mode. Never invoke the subcommand from this skill
without one of the two flags, even though the CLI would default to
issueless: the safety property is that the workflow says what it wants,
not that the default happens to be harmless.

Options:
- `--issues` -- issue-creating mode: create one GitHub issue per feature and
  key both reserved sections on those issues. Mutually exclusive with
  `--no-issues`. Required to reach GitHub at all.
- `--no-issues` -- issueless mode: create no issues and render the reserved
  sections from the Features section, keying table rows on feature labels
  and naming dependencies by `F<n>` index. The subcommand's default when
  neither mode flag is given, and named explicitly by every invocation in
  this skill.
- `--milestone <name>` -- milestone for the created issues
- `--milestone-description <desc>` -- milestone description
- `--mapping <file>` -- pre-existing id->github_number mapping (re-render only)
- `--output-map <file>` -- write the final id->github_number mapping
- `--repo <owner/repo>` -- override the repo used when rendering issue links
- `--dry-run` -- skip `gh` invocations; synthesize a deterministic mapping
- `-h, --help` -- print help

### R14 approval gate (lives in this caller, not in the subcommand)

Issue creation is the gated step (R14 in the requirements). The gate lives
in this skill phase, NOT in the subcommand. The subcommand is a primitive
that creates issues when invoked.

**R14 gates issue creation, so it applies only in issue-creating mode.**
Present the gate as described below before any invocation carrying
`--issues`. When the subcommand runs with `--no-issues` -- which is every
automatic population, and any human invocation that resolves to issueless
-- it creates no issues, so there is nothing to approve and the gate is
skipped entirely. Skipping it removes a gate over an action that does not
occur; it does not bypass approval over any side effect.

Because issue creation is now reached only by an explicit `--issues`, the
gate guards a path a human has already chosen deliberately. That does not
make it redundant: the gate is where the author sees the feature count, the
names, and the milestone before anything is filed.

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
