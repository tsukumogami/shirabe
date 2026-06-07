---
schema: design/v1
status: Current
complexity: Complex
upstream: docs/prds/PRD-shirabe-artifact-decision-contract.md
decision_provenance: inline-resolved
problem: |
  shirabe's seven main-pipeline artifact types (VISION, STRATEGY, ROADMAP,
  BRIEF, PRD, DESIGN, PLAN) plus private-only COMP each carry an implicit
  durable-vs-working decision in their producing skill's cleanup logic. The
  decision is real but undocumented per skill, the cascade hard-codes one
  working artifact (PLAN) without an extension point, and ROADMAPs whose
  features are all Done sit in `docs/roadmaps/` indefinitely.
decision: |
  Each producer-skill gets a new `## Artifact Lifecycle` H2 section that
  states, in a uniform prose template, whether its artifact is durable or
  working and -- for working artifacts -- the completion condition. CLAUDE.md
  gains a `## Artifact Lifecycle: per-skill` convention header pointing
  readers at the per-skill prose. ROADMAP flips to working with lifecycle
  `Draft -> Active -> Done -> DELETED` mirroring PLAN's shape. The cascade
  grows a `handle_roadmap_deletion()` shell function in
  `skills/work-on/scripts/run-cascade.sh` that runs alongside the existing
  PLAN handler inside PR #176's pre-`gh pr ready` window. The completion
  check is deterministic: all features at status Done AND every referenced
  GitHub issue at state CLOSED.
rationale: |
  The H2 section parallels existing per-skill convention headings (Conventions,
  Resume Logic) and is greppable; the prose template stays lazy-loaded so the
  CLI never parses it. Mirroring PLAN's four-state lifecycle exactly lets any
  future `--lifecycle-chain` extension walk ROADMAP chains without a special
  case. The shell-function-in-existing-script choice reuses PR #176's
  finalization window and the validated path/issue plumbing already in
  `run-cascade.sh`, deferring a pluggable handler interface until a third
  working artifact justifies it. Validator/CI surface is explicitly out of
  scope per PRD R9; future amplifier work can pick that up.
---

# DESIGN: shirabe-artifact-decision-contract

## Status

Current

This DESIGN ships the per-skill durable-vs-working contract, flips ROADMAP
from durable to working, and extends the work-on cascade with a
`handle_roadmap_deletion()` step. PR #176's PLAN lifecycle template
(`Draft -> Active -> Done -> DELETED`) and the cascade's pre-`gh pr ready`
window are the foundation; this DESIGN cites them rather than re-deriving
them.

## Context and Problem Statement

shirabe has seven main-pipeline artifact types (VISION, STRATEGY, ROADMAP,
BRIEF, PRD, DESIGN, PLAN) plus a private-only COMP. For each type, an
implicit decision lives in the producing skill's cleanup logic: does this
artifact stay in `docs/` forever as part of the project's audit trail, or
does it disappear once its purpose has been fulfilled?

PR #176 formalized the working-artifact lifecycle template for PLAN
(`Draft -> Active -> Done -> DELETED`) and shipped the cascade script
`skills/work-on/scripts/run-cascade.sh` that performs the atomic
finalization commit -- PLAN `git rm` plus BRIEF/PRD `shirabe transition` to
Done -- in the same window before `gh pr ready` fires. Every other artifact
type stays durable forever, including ROADMAP, even after the work it
sequenced is complete.

Three gaps follow from this implicit, hard-coded decision:

- **ROADMAP-bloat.** A ROADMAP whose features are all Done and whose
  referenced issues are all closed has finished its sequencing job but
  stays in `docs/roadmaps/` indefinitely. The directory accumulates dead
  context that reviewers learn to skim past.
- **No canonical contract.** A skill author has nowhere to read "is this
  artifact durable or working, and what is the completion condition if
  working?" The cleanup behavior is buried inside the cascade's hard-coded
  PLAN branch.
- **No extension point.** The cascade's PLAN-deletion step is a one-off
  branch. Any new working artifact would force a fresh hard-coded branch
  and compound the rationale-lives-nowhere problem.

The PRD names 12 requirements (R1-R12) and 14 acceptance criteria (AC1-AC14)
across these gaps. The architectural surface left to settle is the location
and wire format of the per-skill declaration, ROADMAP's lifecycle shape, the
cascade extension's placement, the completion-condition evaluation
mechanism, the CLAUDE.md convention header shape, and the migration posture
for existing ROADMAP files.

## Decision Drivers

- **D1 Lazy-load principle.** Defensive mechanisms follow the order
  CLI-deterministic > CLI-detects+lazy-pointer > eager-load skill prose. The
  per-skill prose is the lazy-loaded resolution; the deterministic check is
  the CLI-style mechanism. No always-loaded skill body carries eager
  defensive prose.
- **D2 Cite PR #176, do not re-derive.** PLAN's lifecycle template,
  cascade window, and validator behavior were settled in PR #176
  (`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` and
  `docs/designs/current/DESIGN-skill-cascade-lifecycle-check.md`). This
  DESIGN consumes that foundation without re-stating it.
- **D3 Validator/CI surface out of scope.** Per PRD R9 and AC11, no new
  shirabe CLI subcommand, no new validator check, no new schema field, and
  no new artifact type. The contract lives in prose; the cascade extension
  is bash.
- **D4 Idempotent cascade.** Per PRD R10/AC8, every cascade step is safe to
  re-invoke. The ROADMAP deletion handler must be a no-op when no ROADMAP
  exists, when the ROADMAP is already deleted, and when the completion
  condition is unsatisfied.
- **D5 Single PR delivery.** The eight SKILL.md updates, the cascade
  script function, the koto template reference, the CLAUDE.md header, and
  the optional guide ship in one PR. The PLAN driving this work is
  single-pr execution mode.
- **D6 Parallel existing conventions.** New headings parallel existing
  ones (Conventions, Resume Logic, Repo Visibility, Planning Context).
  Reviewers and grep both find the new sections where they look for the
  old ones.

## Considered Options

Seven architectural decisions were inline-resolved per the
`decision-bypass-with-inline-resolution` dispatch fallback shape
(`references/fixes/sub-agent-dispatch.md` shape 3). Each is recorded below
with rejected alternatives and their rejection rationale.

### Decision 1: Where the per-skill durable-vs-working declaration lives

The producer-skill SKILL.md is the right home; the question is the shape
of the slot.

- **Option A (chosen): a new `## Artifact Lifecycle` H2 section.** The
  section sits among the skill's existing structural H2s (e.g.
  `## Conventions`, `## Resume Logic`, `## Lifecycle Management`). It is
  greppable (`grep -l "## Artifact Lifecycle" skills/*/SKILL.md`),
  consistent in placement across the eight producer skills, and reads
  naturally for a skill author landing on the file.
- **Option B (rejected): a new frontmatter field.** Couples the contract to
  schema validation and forces a `schema: skill/v1` extension. Pulls
  validator surface into scope, which PRD R9 forbids.
- **Option C (rejected): a separate manifest file.** Forces the author to
  consult two files for one decision; loses parallelism with explore Phase
  5's decision-lives-in-the-producer precedent.
- **Option D (rejected): inline within an existing section** (e.g. an
  unmarked paragraph under each skill's "File Location"). Loses greppability
  and uniform placement; a future amplifier scanning for the contract would
  need per-skill heuristics rather than a structural query.

Chosen because the H2 section parallels existing convention H2s, is
greppable, follows the lazy-load principle (the CLI does not need to parse
it; the skill itself reads it during author onboarding), and stays within
the prose-only boundary PRD R9 names.

### Decision 2: Wire format for the per-skill declaration

The H2 section needs a uniform shape so authors writing a new producer
skill can copy-paste the template and so reviewers can pattern-match
across skills.

- **Option A (chosen): uniform prose template with bold label.** Each
  section opens with a bold "**Lifecycle:**" label followed by `Durable.`
  or `Working.`. Durable variants add one sentence stating the artifact
  stays in `docs/<dir>/`. Working variants add two further lines naming
  the completion condition and the cascade step that performs the
  deletion. The full template:

  Durable form:
  > **Lifecycle:** Durable. Stays in `docs/<dir>/` after completion as
  > part of the project's audit trail.

  Working form:
  > **Lifecycle:** Working. Completion condition: <condition>. Deleted
  > by: <cascade-step>.

- **Option B (rejected): structured YAML inside a fenced block.** Pulls
  the contract toward machine-parseable shape, which invites validator
  extension (forbidden by PRD R9). Adds visual weight to a section meant
  to read as one-paragraph prose.
- **Option C (rejected): free prose with no template.** Loses
  pattern-matchability across skills; reviewers cannot scan eight skills
  at a glance to verify the contract is in place; new authors have no
  copyable shape.
- **Option D (rejected): structured table per skill.** Over-shapes for a
  one-line decision; tables read poorly as the only content of an H2
  section.

Chosen because the bold-label prose template is greppable
(`grep -A2 "## Artifact Lifecycle" skills/*/SKILL.md`), copy-pasteable,
visually consistent with existing per-skill prose, and stays inside the
prose-only PRD R9 boundary.

### Decision 3: ROADMAP's working-artifact lifecycle

PR #176 established the four-state lifecycle template for PLAN
(`Draft -> Active -> Done -> DELETED`). The question is whether ROADMAP
adopts the same shape or a different one.

- **Option A (chosen): mirror PLAN's `Draft -> Active -> Done -> DELETED`
  exactly.** ROADMAP enters Draft on creation; the Draft -> Active gate
  keeps its existing human-approval semantic (features lock at activation,
  paralleling PLAN's multi-pr gate); the Active -> Done flip is the
  ephemeral in-process marker the cascade applies immediately before
  deletion; Done -> DELETED is the cascade's `git rm`. There is no
  `docs/roadmaps/done/` directory; verify-then-delete is the terminal.
- **Option B (rejected): keep ROADMAP at `Draft -> Active -> Done` and
  add deletion as a post-Done state.** Diverges from PLAN's shape; any
  future `--lifecycle-chain` walker would have to special-case ROADMAP.
- **Option C (rejected): no lifecycle states, just a completion check.**
  Loses the audit-trail Done marker. The cascade commit would `git rm` a
  ROADMAP at status Active, leaving no record of the activation/completion
  transition in the commit history.
- **Option D (rejected): immediate deletion at last-feature-Done with no
  intermediate flip.** Same audit-trail loss as Option C; also breaks
  idempotency (the cascade cannot distinguish "already deleted" from
  "never created" without the Done marker).

Chosen because mirroring PLAN's shape lets the validator's
`--lifecycle-chain` mode later walk ROADMAP chains uniformly (deferred
amplifier work; see PRD R9), preserves the Active -> Done audit-trail
marker, and matches the verify-then-delete forcing function PR #176
established.

### Decision 4: Cascade extension placement

The cascade is shell (`run-cascade.sh`) plus a koto template
(`work-on-plan.md`). The question is where ROADMAP deletion plumbing
lives.

- **Option A (chosen): a `handle_roadmap_deletion()` shell function in
  `skills/work-on/scripts/run-cascade.sh`, called from the existing
  cascade sequence inside the pre-`gh pr ready` window.** The function
  parallels the existing `handle_roadmap()` shape (which currently only
  updates feature status). The koto template
  `skills/work-on/koto-templates/work-on-plan.md` gains a parallel
  reference in its `plan_completion` state's prose pointing at the new
  function.
- **Option B (rejected): a separate script.** Forks the cascade into two
  entry points; reviewers chasing the cascade behavior would have to
  follow two scripts; the post-cascade lifecycle verification probe would
  have to re-orchestrate.
- **Option C (rejected): a separate state in the koto graph.** Pulls
  ROADMAP deletion out of the atomic finalization commit; breaks PR #176's
  "single commit set before `gh pr ready`" guarantee.
- **Option D (rejected): inline in the plan-finalization step (no named
  function).** Loses idempotency clarity; the no-ROADMAP-in-chain no-op
  case becomes harder to read; future maintainers cannot grep for the
  step by name.

Chosen because the shell-function-in-existing-script choice reuses PR
#176's window, reuses the script's path-validation and issue-state
plumbing, stays idempotent by design (the function is the sole owner of
the no-op cases), and keeps the cascade as a single entry point.

### Decision 5: Completion-condition evaluation for ROADMAP deletion

The PRD R5 names the condition: all features on the ROADMAP at status Done
AND all referenced GitHub issues closed. The question is how the cascade
evaluates it.

- **Option A (chosen): a deterministic check executed by the cascade.**
  The function: (1) parses the ROADMAP markdown for feature rows under
  `## Features`, (2) checks each feature's `**Status:**` field is `Done`,
  (3) extracts referenced issue URLs by regex
  (`https://github.com/<owner>/<repo>/issues/<N>`), (4) calls
  `gh issue view <N> --repo <owner>/<repo> --json state --jq '.state'` for
  each, requiring `CLOSED`. All must hold; otherwise the function is a
  no-op (no transition, no `git rm`).
- **Option B (rejected): validator-driven check.** Out of scope per PRD
  R9 -- adds a validator surface.
- **Option C (rejected): manual confirmation prompt.** Breaks
  --auto-mode cascade orchestration; the cascade runs unattended inside
  the koto state machine.
- **Option D (rejected): time-based heuristic** (e.g. "last edit > 30
  days").  Lossy and irreversible; would retire ROADMAPs whose features
  are still in flight but whose ROADMAP doc happens to be stale.

Chosen because the deterministic check is idempotent (re-runs produce the
same outcome on the same chain state), runs in the cascade window, reuses
the `gh` plumbing already in `run-cascade.sh`'s `check_issue_closed`
helper, and stays inside the prose-only/bash-only boundary PRD R9 names.

### Decision 6: CLAUDE.md convention header shape

PR #176 and earlier work established the `## Repo Visibility:` and
`## Planning Context:` headers as the canonical convention-header pattern.
The question is the shape of the new lifecycle header.

- **Option A (chosen): a new `## Artifact Lifecycle: per-skill` header
  that points readers at the per-skill SKILL.md sections as authoritative.**
  The header parallels the existing convention-header pattern (two H2
  headers already follow `<noun>: <value>` shape), names the three-rule
  model in one paragraph, and explicitly defers to per-skill prose for
  per-artifact rules.
- **Option B (rejected): a full table inline in CLAUDE.md.** Duplicates
  the per-skill prose; creates a drift surface (the CLAUDE.md table
  becomes stale every time a skill's section changes); pulls policy into
  the wrong altitude.
- **Option C (rejected): no header at all, relying on the per-skill prose
  to be self-discovering.** Loses the canonical discovery path; an author
  reading CLAUDE.md for project conventions would not find any signal
  that the lifecycle distinction exists.
- **Option D (rejected): a structured manifest file outside CLAUDE.md.**
  Same per-skill-discovery loss; also creates a new file with one known
  consumer (CLAUDE.md readers), violating the "no new substrate" boundary.

Chosen because the header-with-pointer follows the existing convention-
header pattern, stays minimal, points at the per-skill prose as the
single source of truth, and keeps the eager-load surface in CLAUDE.md
bounded to one paragraph.

### Decision 7: Migration of existing ROADMAP files

Several ROADMAPs currently live in `docs/roadmaps/` at status Active. The
question is how the flip from durable to working applies to them.

- **Option A (chosen): lazy migration.** ROADMAPs already in
  `docs/roadmaps/` keep their current state; the cascade's deletion check
  runs against them on the next /work-on cycle that traverses their
  chain. If a status field is missing (older ROADMAPs predate the
  schema), the cascade treats it as Active for the purpose of the
  completion check; no bulk migration commit is needed.
- **Option B (rejected): bulk-migrate all ROADMAPs to Active in this PR.**
  Touches files unrelated to this PR's intent; expands the diff; risks
  breaking unrelated in-flight work that references the ROADMAPs.
- **Option C (rejected): mark all existing ROADMAPs Done-and-skip.**
  Forces a one-time policy decision that does not generalize; future
  ROADMAPs would have to be re-stamped manually.
- **Option D (rejected): require manual re-stamping of every ROADMAP
  before the cascade activates.** Forces author intervention before the
  feature works; the cascade extension becomes opt-in rather than
  default.

Chosen because the cascade is idempotent (Decision 5) -- a ROADMAP whose
completion condition is unsatisfied is a no-op; one whose features are
all Done and whose issues are all closed retires on the next cycle that
runs the cascade through its chain. Bulk migration would touch unrelated
work and expand the PR's diff for no behavioral gain.

## Decision Outcome

The eight producer-skill SKILL.md files (`brief`, `prd`, `design`, `plan`,
`roadmap`, `vision`, `strategy`, `comp`) each gain a new `## Artifact
Lifecycle` H2 section following the Decision 2 prose template. The six
durable skills classify as durable with audit-trail rationale; PLAN
classifies as working and cites
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` as the
lifecycle source; ROADMAP classifies as working with completion condition
"all features Done AND all referenced GitHub issues closed."

ROADMAP's lifecycle becomes `Draft -> Active -> Done -> DELETED` mirroring
PLAN's shape (Decision 3). The existing `Draft -> Active` gate is
preserved -- it keeps its human-approval semantic. The Active -> Done flip
is the ephemeral in-process marker the cascade applies immediately before
deletion; Done -> DELETED is the cascade's `git rm`.

The cascade script `skills/work-on/scripts/run-cascade.sh` grows a
`handle_roadmap_deletion()` shell function (Decision 4) that the existing
`handle_roadmap()` flow calls after the existing feature-status update
when the all-features-Done branch is taken. The function evaluates the
completion condition deterministically (Decision 5): parse Features section
for status, regex-extract issue URLs, `gh issue view` each to require
`CLOSED`. On the all-conditions-hold branch, it transitions ROADMAP
Active -> Done and `git rm`s the file. On any negative branch, it is a
no-op.

CLAUDE.md gains a new `## Artifact Lifecycle: per-skill` convention header
(Decision 6) that names the three-rule durable-vs-working model in one
paragraph and points at the per-skill `## Artifact Lifecycle` sections as
authoritative.

Existing ROADMAPs are not bulk-migrated (Decision 7); they retire
naturally on the next /work-on cycle through their chain.

The validator/CI surface is untouched per PRD R9. The existing
`shirabe validate --lifecycle-chain <plan-path> --strict` pre-cascade
probe and post-cascade verification both continue to run unchanged; their
behavior on ROADMAP-touching chains is unchanged because ROADMAP is not
in the PLAN's tactical-chain `upstream:` walk (the chain walks PLAN ->
DESIGN -> PRD -> BRIEF, then `roadmap_handoff` to the existing
`handle_roadmap()` function which now calls the new
`handle_roadmap_deletion()`).

## Solution Architecture

### Component changes

Twelve components are touched. The first eight are SKILL.md updates that
add the new `## Artifact Lifecycle` section. The next three are the
cascade extension and CLAUDE.md header. The twelfth is an optional
release-notes guide.

```
skills/brief/SKILL.md            # + ## Artifact Lifecycle (durable)
skills/prd/SKILL.md              # + ## Artifact Lifecycle (durable)
skills/design/SKILL.md           # + ## Artifact Lifecycle (durable)
skills/plan/SKILL.md             # + ## Artifact Lifecycle (working, cites PR #176)
skills/roadmap/SKILL.md          # + ## Artifact Lifecycle (working)
                                 # + Lifecycle Management update (add DELETED state)
skills/vision/SKILL.md           # + ## Artifact Lifecycle (durable)
skills/strategy/SKILL.md         # + ## Artifact Lifecycle (durable)
skills/comp/SKILL.md             # + ## Artifact Lifecycle (durable)

skills/work-on/scripts/run-cascade.sh
                                 # + handle_roadmap_deletion() shell function
                                 # called from existing handle_roadmap() when
                                 # all-features-Done branch is taken

skills/work-on/koto-templates/work-on-plan.md
                                 # plan_completion state prose updated to
                                 # mention the new function (no state-machine
                                 # change; the call sits inside run-cascade.sh)

CLAUDE.md                        # + ## Artifact Lifecycle: per-skill header

docs/guides/<release-notes>.md   # optional release-notes doc for the doctrine
                                 # flip (skill-author migration guide). Drop if
                                 # the doctrine flip is captured by an existing
                                 # release-notes flow.
```

### Per-skill prose template instantiations

The eight SKILL.md sections instantiate the Decision 2 template as
follows. Each section sits among the existing per-skill H2s; the precise
ordinal placement is reviewer-discretionary (placement after
`## File Location` is the suggested default, which puts the durability
contract near the directory-structure contract).

**Durable instantiations** (BRIEF, PRD, DESIGN, VISION, STRATEGY, COMP):

```markdown
## Artifact Lifecycle

**Lifecycle:** Durable. Stays in `docs/<dir>/` after completion as part
of the project's audit trail.

<one-paragraph rationale tying to audit-trail durability for this
artifact type>
```

Per-skill `<dir>` values: `briefs/`, `prds/`, `designs/`, `visions/`,
`strategies/`, `competitive/`.

**Working instantiation** for PLAN:

```markdown
## Artifact Lifecycle

**Lifecycle:** Working. Completion condition: the implementing PR's
cascade verifies the chain's terminal state and the PLAN file is deleted
in the atomic finalization commit. Deleted by: the work-on cascade's
PLAN deletion step.

PLAN lifecycle is `Draft -> Active -> Done -> DELETED`. The Draft ->
Active gate auto-fires for single-pr execution mode and is
human-approved for multi-pr. The Active -> Done flip is the ephemeral
in-process marker the cascade applies immediately before deletion. See
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` for
the lifecycle template source.
```

**Working instantiation** for ROADMAP:

```markdown
## Artifact Lifecycle

**Lifecycle:** Working. Completion condition: all features on the
ROADMAP at status Done AND all referenced GitHub issues closed. Deleted
by: the work-on cascade's `handle_roadmap_deletion` step.

ROADMAP lifecycle is `Draft -> Active -> Done -> DELETED`, mirroring
PLAN's shape. The Draft -> Active gate keeps its existing
human-approval semantic (features lock at activation). The Active ->
Done flip is the ephemeral in-process marker the cascade applies
immediately before deletion. See
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` for
the lifecycle template source.
```

### Cascade function shape

The new shell function is appended to `run-cascade.sh` after the existing
`handle_roadmap()` function. The function is called from within
`handle_roadmap()` on the path where all features are Done -- replacing
the current inline `gh issue view` loop with a single named call:

```bash
# ── Handler: handle_roadmap_deletion ──────────────────────────────────
# When the existing handle_roadmap() function has verified all features
# are at status Done AND all referenced GitHub issues are CLOSED,
# transition the ROADMAP Active -> Done and git rm the file in the same
# atomic finalization commit. Idempotent: a no-op when the ROADMAP file
# does not exist, when the chain has no ROADMAP, or when any feature is
# not Done or any referenced issue is not CLOSED.
#
# Usage: handle_roadmap_deletion <roadmap-path> <found-in>

handle_roadmap_deletion() {
    local path="$1"
    local found_in="$2"

    # Idempotency guard: a no-op when the file is already gone.
    if [[ ! -f "$path" ]]; then
        return 0
    fi

    # Confirm all features are Done (re-evaluated here for idempotency
    # on direct re-invocation; the caller in handle_roadmap() already
    # checked, but a direct call should also be safe).
    local all_done=true
    local feature_statuses
    feature_statuses=$(grep "^\*\*Status:\*\*" "$path" \
        | sed 's/\*\*Status:\*\*[[:space:]]*//')
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        if [[ "$line" != "Done" ]]; then
            all_done=false
            break
        fi
    done <<< "$feature_statuses"

    if [[ "$all_done" != "true" ]]; then
        # Some feature is not Done; the ROADMAP stays.
        return 0
    fi

    # Confirm all referenced GitHub issues are closed. Reuses the
    # existing check_issue_closed helper which validates owner/repo
    # against the origin remote.
    local all_closed=true
    local open_issue_url=""
    local issue_urls
    issue_urls=$(grep -oE \
        'https://github\.com/[^/]+/[^/]+/issues/[0-9]+' "$path" || true)
    while IFS= read -r issue_url; do
        [[ -z "$issue_url" ]] && continue
        if ! check_issue_closed "$issue_url"; then
            all_closed=false
            open_issue_url="$issue_url"
            break
        fi
    done <<< "$issue_urls"

    if [[ "$all_closed" != "true" ]]; then
        add_step "delete_roadmap" "$path" "$found_in" "skipped" \
            "$path references issue $open_issue_url which is still open"
        return 0
    fi

    # Active -> Done flip (ephemeral, in-process audit-trail marker).
    if ! "$SHIRABE_BIN" transition "$path" Done > /dev/null 2>&1; then
        log_warn "shirabe transition $path Done failed; proceeding to git rm"
    fi

    # Done -> DELETED via git rm in the same staged commit set.
    if git rm -f "$path" > /dev/null 2>&1; then
        add_step "delete_roadmap" "$path" "$found_in" "ok" ""
        STAGED_FILES+=("$path")
    else
        ANY_FAILED=true
        add_step "delete_roadmap" "$path" "$found_in" "failed" \
            "attempted to git rm $path but the operation failed"
    fi
}
```

The function reuses the existing `check_issue_closed`, `add_step`,
`log_warn`, `STAGED_FILES`, `ANY_FAILED`, and `SHIRABE_BIN` globals from
the surrounding script.

### Cascade call site

The existing `handle_roadmap()` function has an `all_done == "true"`
branch (around line 344 in the current file) that today only triggers a
ROADMAP -> Done transition without deletion. The minimal call-site change
replaces the existing `transition_roadmap` step with a delegation to
`handle_roadmap_deletion`:

```bash
# Inside handle_roadmap(), in the all_done branch:
if [[ "$all_done" == "true" ]]; then
    handle_roadmap_deletion "$path" "$found_in"
fi
```

The existing inline `gh issue view` loop and `shirabe transition <path>
Done` call are removed; the new function owns both. The `transition_roadmap`
step name used in the existing flow is replaced by `delete_roadmap` in
the new function's `add_step` calls. The script's external JSON contract
(`steps[].action` enum) gains `delete_roadmap` as a new value.

### Koto template prose update

The `plan_completion` state's prose in
`skills/work-on/koto-templates/work-on-plan.md` already documents that
the cascade runs the finalization commit. The Decision 4 change adds a
one-sentence parallel reference to the new function in the existing
"Step 1: Run the cascade" prose:

> The cascade also calls `handle_roadmap_deletion` when the chain's
> upstream walk surfaces a ROADMAP node whose features are all Done and
> whose referenced issues are all closed -- transitioning the ROADMAP
> Active -> Done and `git rm`ing the file in the same atomic
> finalization commit.

No state-machine change; the call sits inside `run-cascade.sh`'s
existing flow which is already invoked by the `plan_completion` state.

### CLAUDE.md convention header

The header lands among the existing convention headers (after
`## Repo Visibility:` and `## Planning Context:`, before `## Conventions`).
The wording:

```markdown
## Artifact Lifecycle: per-skill

shirabe artifacts are durable or working. Durable artifacts stay in
`docs/<dir>/` after completion as part of the project's audit trail.
Working artifacts retire when their completion condition holds, deleted
by the work-on cascade. Each producer-skill's SKILL.md names its
artifact's lifecycle in a `## Artifact Lifecycle` section -- the
per-skill prose is authoritative. PLAN and ROADMAP are working; BRIEF,
PRD, DESIGN, VISION, STRATEGY, and COMP are durable.
```

The header points at per-skill prose rather than restating it, matching
the lazy-load principle (D1) and the cite-don't-re-derive driver (D2).

### Data flow

```
work-on cascade reaches plan_completion state
  -> run-cascade.sh --push <plan-doc-path>
     -> pre-cascade strict-mode lifecycle probe (existing)
     -> finalize-chain walks PLAN -> DESIGN -> PRD -> BRIEF (existing)
     -> finalize-chain hands off any ROADMAP node to handle_roadmap()
        -> handle_roadmap() updates feature Status and Downstream (existing)
        -> handle_roadmap() if all features Done:
           -> handle_roadmap_deletion(roadmap-path, found-in)  [NEW]
              -> re-check all features Done (idempotency)
              -> for each issue URL in ROADMAP:
                 -> check_issue_closed(url) — gh issue view --json state
              -> if all closed:
                 -> shirabe transition <path> Done (Active -> Done)
                 -> git rm <path>                  (Done -> DELETED)
                 -> add_step "delete_roadmap" status=ok
              -> if any open:
                 -> add_step "delete_roadmap" status=skipped
     -> git rm PLAN (existing)
     -> git commit + git push (existing)
     -> post-cascade strict-mode lifecycle probe (existing)
  -> gh pr ready (existing)
```

The new function fires inside the existing finalization commit. No new
commit is added to the cascade window. The post-cascade lifecycle probe
runs against the unchanged tactical chain (PLAN-rooted) and is not
affected by ROADMAP deletion.

## Implementation Approach

The PLAN driving this work is single-pr execution mode; the PLAN itself
is deleted at cascade-finalization. The implementation lands in five
logical batches that fit a single PR.

### Batch 1: Per-skill SKILL.md sections

Add the `## Artifact Lifecycle` H2 to each of the eight producer-skill
SKILL.md files. Six use the durable template (BRIEF, PRD, DESIGN, VISION,
STRATEGY, COMP); two use the working template (PLAN, ROADMAP). Each
section's placement follows the suggested default (after
`## File Location`); reviewers may adjust per-skill if a different
placement reads better.

The PLAN section cites
`docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md` as the
authoritative source for the lifecycle template (per PRD R4/R11/AC12) and
does not re-derive the lifecycle from scratch.

### Batch 2: CLAUDE.md convention header

Add the `## Artifact Lifecycle: per-skill` H2 section to CLAUDE.md after
the existing `## Planning Context:` header. The wording is the one-
paragraph prose from the Solution Architecture section above.

### Batch 3: ROADMAP lifecycle skill update

Update `skills/roadmap/SKILL.md`'s `## Lifecycle Management` section to
reflect the four-state shape: replace the existing `Draft -> Active ->
Done` description with `Draft -> Active -> Done -> DELETED`. Add the
Done -> DELETED row to the transition table with verb "cascade" and
precondition "all features Done AND all referenced issues closed,
triggered by work-on cascade." Update the "Forbidden transitions" line
to note that Done -> DELETED is cascade-only (not human-invokable).

### Batch 4: Cascade function and call site

Append `handle_roadmap_deletion()` to `skills/work-on/scripts/run-cascade.sh`
(after the existing `handle_roadmap()` function). Update the existing
`handle_roadmap()`'s all-features-Done branch to delegate to the new
function (replacing the inline `gh issue view` loop and the
`transition_roadmap` step). Add the koto template prose reference per
the Solution Architecture section.

### Batch 5: Optional release-notes guide

The doctrine flip (ROADMAP becoming working) is a behavior change that
existing skill consumers benefit from being told about. Add a brief guide
at `docs/guides/<release-version>-artifact-lifecycle.md` summarizing the
per-skill `## Artifact Lifecycle` convention, the ROADMAP flip, and the
cascade extension. The guide is optional -- if the existing release-
notes flow already produces an equivalent guide, this batch drops.

### Single PR sequencing

The five batches land in a single commit chain on one PR. Validator
self-checks (`shirabe validate --lifecycle-chain` and the
`validate-docs` workflow) run on each batch incrementally during local
development; the final batch's commit is the one that triggers
`gh pr ready` and the at-merge strict-mode lifecycle check.

No multi-PR sequencing is needed; the changes are independent of each
other within the PR (each SKILL.md update is independent; the cascade
script update has no consumer until the koto template prose update lands).

## Security Considerations

The new `handle_roadmap_deletion()` function reuses the existing
`run-cascade.sh` mutation surface and validation plumbing -- no new
authority is granted to the cascade.

### Path-traversal surface

The function operates on the ROADMAP path resolved by
`finalize-chain`'s upstream-frontmatter walker, which is already passed
through `validate_upstream_path()` upstream in `run-cascade.sh`. The path
is constrained to:

- Resolve under `REPO_ROOT` (no parent-directory escape).
- Be a regular file (not a symlink, pipe, device, or directory).
- Be tracked by git.

The new function does not re-validate (the caller has already done so);
it operates on the same `$path` argument the existing `handle_roadmap()`
receives. No new attack surface compared to the existing flow.

### GitHub API surface

The function calls `check_issue_closed`, which is the existing helper
that:

- Parses the issue URL by regex (no shell expansion of user content).
- Validates the URL's owner/repo against the `origin` remote, refusing
  to query foreign-repo issues.
- Calls `gh issue view --repo <owner>/<repo> --json state --jq '.state'`
  with positional args (no shell metacharacter interpolation).

The reuse means no new GitHub API surface and no new injection vector.
The function does not modify GitHub state (no `gh issue edit`, no `gh
issue close`); it only reads issue state.

### Git mutation surface

The function calls `shirabe transition <path> Done` and `git rm -f
<path>`. Both are the same primitives the existing PLAN-deletion branch
uses; both target the path-validated ROADMAP file. The `-f` flag on
`git rm` is required because the file is modified-in-worktree by the
preceding `shirabe transition` call (the same pattern the existing PLAN
deletion uses).

### Failure mode surface

The function fails closed: any negative branch (file gone, features not
all Done, any issue not closed, transition failed) is a no-op or a
recorded `skipped`/`failed` step; the cascade continues. The post-cascade
strict-mode lifecycle probe runs against the PLAN's tactical chain,
which is unchanged by ROADMAP deletion -- a ROADMAP-deletion failure
does not cause the probe to fail.

### Out-of-scope surface

The validator/CI surface is untouched per PRD R9. No new shirabe
subcommand, no new workflow file, no new schema field. Any future
`--lifecycle-chain` extension to walk ROADMAP chains is amplifier-layer
work and lives outside this DESIGN.

## Consequences

### Positive

- **Skill-author onboarding is one read.** A new skill author opens any
  producer-skill SKILL.md and learns the artifact's lifecycle contract
  from the `## Artifact Lifecycle` H2 directly, without consulting
  cleanup-script source or comparing siblings.
- **docs/roadmaps/ stays current.** A reviewer browsing `docs/roadmaps/`
  sees only initiatives still in motion; retired ROADMAPs are removed
  by the cascade.
- **The cascade has a named extension point.** Future working artifacts
  add a `handle_<artifact>_deletion()` shell function alongside the new
  one; the pattern is the contract.
- **PR #176 foundation is reused, not re-derived.** PLAN's lifecycle
  template, the cascade window, and the validator probe all stay
  unchanged; the new work composes with them.
- **No new substrate.** No CLI subcommand, no validator check, no schema
  field. The contract is prose; the extension is bash.

### Negative

- **ROADMAP deletion is irreversible.** Once the cascade `git rm`s a
  ROADMAP, retrieving it requires a `git revert` against the
  finalization commit. The audit trail lives in the commit history, not
  in the working tree.
- **The completion-condition check is structural.** Issues
  closed-as-not-planned, transferred to other repos, or hidden behind
  GitHub renames may register inconsistently. The structural check is
  the simplest first contract; richer evidence is amplifier-layer work.
- **Cascade-ordering non-pluggability persists.** ROADMAP deletion is
  ordered alongside PLAN deletion in the same commit. A third working
  artifact with different ordering constraints would force the cascade
  to grow that ordering inline (acknowledged as structural debt in PRD's
  Known Limitations).
- **No tooling-level enforcement of the contract.** Authors who omit
  the `## Artifact Lifecycle` section in a new producer skill are caught
  only by human review. A future validator extension could fire on the
  section's absence; that is deferred.

### Mitigations

- **Irreversibility:** the commit message names the cascade explicitly
  (`chore(cascade): post-implementation artifact transitions`); the
  commit history is the audit trail. Reverting the cascade commit
  restores the ROADMAP.
- **Structural check fidelity:** the PRD's Out of Scope explicitly
  acknowledges that amplifier-driven evidence is the next layer; the
  structural check is the first contract, not the final one.
- **Ordering non-pluggability:** the function is greppable by name; a
  future maintainer adding a third working artifact will see the
  ordering inline and can re-shape if needed.
- **No tooling enforcement:** the PR-time human review is the gate; the
  PRD names the future validator extension as out of scope and
  deferred.

## References

- PRD: `docs/prds/PRD-shirabe-artifact-decision-contract.md` (upstream
  requirements; 12 R, 14 AC).
- BRIEF: `docs/briefs/BRIEF-shirabe-artifact-decision-contract.md`
  (upstream framing).
- PLAN lifecycle template authority:
  `docs/designs/current/DESIGN-lifecycle-draft-ready-discipline.md`,
  `docs/designs/current/DESIGN-skill-cascade-lifecycle-check.md`,
  `skills/plan/SKILL.md`.
- Cascade implementation:
  `skills/work-on/scripts/run-cascade.sh` (the script the new function
  is appended to),
  `skills/work-on/koto-templates/work-on-plan.md` (the koto template
  whose `plan_completion` state prose gains the new function reference).
- Cascade-trigger rationale:
  `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md`.
- Strict-mode CLI flag rationale:
  `docs/decisions/DECISION-lifecycle-strict-mode-interface-2026-06-06.md`.
- Chain-targeted lifecycle CLI shape:
  `docs/decisions/DECISION-chain-targeted-lifecycle-cli-shape-2026-06-06.md`.
- Sub-agent dispatch contract:
  `references/fixes/sub-agent-dispatch.md` (shape 3
  decision-bypass-with-inline-resolution applied at Phase 2; shape 1
  serial-self-jury applied at Phase 6).
- ROADMAP format reference:
  `skills/roadmap/references/roadmap-format.md`.
- Workflow principles: `references/workflow-principles.md` (P1:
  observable value is the unit of work).
