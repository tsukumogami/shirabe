---
status: Proposed
problem: |
  After a plan's implementation completes, a sequence of artifact lifecycle
  transitions runs manually: delete the PLAN doc, move the DESIGN to Current,
  mark related PRDs Done, update the ROADMAP feature entry, and transition the
  ROADMAP to Done if all features are complete. The partial automation added to
  work-on-plan.md hardcodes a DESIGN→PRD→ROADMAP chain and omits compression of
  completed DESIGN docs, leaving both a topology bug and the compression goal from
  Feature 8 of the strategic pipeline roadmap unaddressed.
decision: |
  A single Bash script, run-cascade.sh, owns all cascade logic: it walks the
  upstream frontmatter chain generically via per-node type dispatch, calls the
  existing per-skill transition scripts at each node, strips the Implementation
  Issues section from completed DESIGN docs, and updates ROADMAP feature entries.
  All path inputs are validated against the git working tree before use. The
  plan_completion koto state becomes a thin wrapper invoking this script.
rationale: |
  Generic chain walking via type dispatch (case on filename prefix) is simpler
  than hardcoded topology enumeration and handles any current or future artifact
  chain without code changes. A shell script rather than directive prose makes
  the cascade testable with execute-mode evals and gives deterministic failure
  handling via explicit error control. Utility logic is inlined following shirabe's
  established pattern, keeping the script dependency-free.
---

# DESIGN: Completion Cascade

## Status

Proposed

## Context and Problem Statement

When a plan finishes implementation — CI passes, PR is ready — a sequence of
cleanup and lifecycle-transition steps should run automatically: delete the PLAN
doc, transition the upstream DESIGN doc to Current, transition any related PRDs
to Done, update the ROADMAP feature entry, and transition the ROADMAP to Done if
all features are complete. Today every one of these steps is manual, which means
they get skipped or deferred. The partial automation added to `work-on-plan.md`
hard-codes the chain topology (DESIGN → PRD → ROADMAP) and skips compression of
completed artifacts, leaving both a brittle gap and a known gap from Feature 8
of the strategic pipeline roadmap.

An additional concern: completed DESIGN docs accumulate implementation scaffolding
(the Implementation Issues section added by `/plan`, with tables and Mermaid
diagrams) that is useful during active work but becomes dead weight after the work
ships. The same applies to any large boilerplate sections in completed PRDs. This
"dead weight" is never cleaned up because no workflow owns compression.

## Decision Drivers

- The cascade must handle chains that skip intermediate artifact types (e.g.,
  DESIGN whose `upstream` points directly to a ROADMAP with no PRD in between).
- Shirabe is a public repo; it cannot depend on private tools repo scripts at
  runtime. Any reused logic must be ported or reimplemented.
- Cascade failures after a successful CI run should not block `done` — the PR is
  merged; cleanup is best-effort.
- Compression must be safe: it is a lossy operation, and what to preserve must be
  defined precisely so agents don't over-strip.
- The cascade should be testable: eval coverage is required before merge.

## Considered Options

### Decision 1: Chain Walking + Implementation Form

The cascade must traverse the `upstream` chain (PLAN → DESIGN → PRD → ROADMAP
or any sub-sequence thereof) and apply a lifecycle transition at each node. Two
dimensions are coupled: how the traversal is structured, and whether it runs as a
shell script or directive prose interpreted by the agent.

Key assumptions: `upstream` contains a single path (not a list); VISION-* artifacts
terminate the chain without action; `jq` and `bash` 4+ are available (consistent
with existing transition scripts).

#### Chosen: Generic chain walker + shell script

A new script `skills/work-on/scripts/run-cascade.sh` accepts a PLAN doc path,
reads the `upstream` frontmatter field, and walks the chain iteratively. At each
node it dispatches to the matching per-skill `transition-status.sh` based on the
filename prefix (`DESIGN-*`, `PRD-*`, `ROADMAP-*`). The loop terminates when no
`upstream` field is found or a VISION-* node is encountered. The
`plan_completion` directive in `work-on-plan.md` becomes a single bash invocation.

This is the only combination satisfying all four constraints simultaneously:
arbitrary topology coverage (type dispatch per node rather than exhaustive case
enumeration), no private-tools runtime dependency, deterministic failure handling
via explicit `|| true` patterns, and an invocable entry point for execute-mode
eval coverage.

#### Alternatives Considered

- **Generic chain walker + directive prose**: Same topology coverage but no
  isolated entry point for execute-mode evals. Agent variance in failure handling
  violates the determinism requirement. Rejected on testability grounds.

- **Hardcoded sequence + shell script**: Testable but requires pre-detecting chain
  topology (does this chain have a PRD?), which is more complex than per-node type
  dispatch. Any topology outside the enumerated cases silently fails. Rejected
  because the generic walker is strictly simpler and handles future topologies
  without code changes.

- **Hardcoded sequence + directive prose**: The current partial implementation.
  Known broken for DESIGN→ROADMAP topologies. Fails both the topology and
  testability constraints. Rejected as the status quo being replaced.

---

### Decision 2: Compression Strategy

After a plan ships, DESIGN docs accumulate an `## Implementation Issues` section
added by `/plan`. This section — an issues table, a Mermaid diagram, and a `Plan:`
reference line — is fully captured in git history and GitHub once work ships.
The `Plan:` line becomes a broken link after the cascade deletes the PLAN doc.

Key assumptions: the heading is exactly `## Implementation Issues` (confirmed by
two real examples and the creation template); PRD acceptance criteria are
checklist-format, not tables; Open Questions is absent from PRDs by Accepted
status (before cascade runs).

#### Chosen: Strip Implementation Issues from DESIGN; leave PRD body untouched

For DESIGN docs: remove the entire `## Implementation Issues` section using a
single `awk` invocation. The operation is idempotent — if the section is absent
(e.g., `/plan` was never run) the script is a no-op. All durable sections
(decisions, rationale, architecture, consequences) are preserved.

For PRDs: no content removal. The status transition to Done is sufficient signal.
The optional Downstream Artifacts section may carry a broken PLAN doc link, but
removing one stale navigational line from an optional section adds script surface
without meaningful benefit.

#### Alternatives Considered

- **Strip Implementation Issues + patch PLAN link in PRD**: Removes only the broken
  PLAN doc line from Downstream Artifacts. Rejected: one stale line in an optional
  section doesn't justify the added script complexity or the pattern-matching risk.

- **Strip Implementation Issues + remove full Downstream Artifacts section from PRD**:
  Rejected: removes valid links to the DESIGN doc and closed issues, losing the
  reader's navigation path from PRD to implementation artifacts.

- **No stripping; rely on status transitions only**: Rejected: leaves a broken PLAN
  doc link inside every completed DESIGN doc and fails to deliver Feature 8's
  compression goal.

---

### Decision 3: Utilities Sharing

The cascade script needs to read arbitrary frontmatter fields (specifically
`upstream`) and query GitHub issue status. The private tools repo has utilities
for both (`common.sh`, `get-github-status.sh`) but shirabe cannot depend on
them at runtime.

Key assumption: `upstream` field extraction requires a generalization beyond
what existing transition scripts provide (they only read `status`).

#### Chosen: Inline utilities in the cascade script

The cascade script implements `get_frontmatter_field <field> <doc>` (~15 lines)
and `check_issue_closed <url>` (~35 lines) inline, following the same pattern as
the existing transition scripts — which all inline their own frontmatter parsing
rather than sharing a library. Total addition: approximately 50–60 lines in the
utility section of the cascade script.

#### Alternatives Considered

- **Port common.sh into shirabe**: Rejected. `common.sh`'s interface is
  CI-validation-specific (emit_pass/emit_fail) and irrelevant to cascade logic.
  Adding a library layer contradicts shirabe's inlining pattern and introduces
  silent-divergence risk from the private source.

- **Reuse existing transition script side effects**: Rejected. Transition scripts
  don't expose the `upstream` field; making this work would require modifying all
  three transition scripts to accept and return upstream metadata.

- **Agent reads frontmatter directly**: Conditionally viable, but depends on a
  fully agent-driven form (eliminated by Decision 1). Agent-only paths are also
  harder to cover with execute-mode evals.

## Decision Outcome

The three decisions form a coherent whole. A single script,
`skills/work-on/scripts/run-cascade.sh`, owns all cascade logic: it inlines its
own frontmatter and GitHub utilities, walks the upstream chain generically via
type dispatch, and calls the existing per-skill transition scripts at each node.
The DESIGN compression (strip `## Implementation Issues`) runs as part of the
DESIGN node handler before the status transition. The `plan_completion` state in
`work-on-plan.md` becomes a thin wrapper invoking this script, with all topology
and utility concerns removed from the directive prose. A companion test script
and updated evals cover both DESIGN→ROADMAP and DESIGN→PRD→ROADMAP topologies
in execute mode before merge.

## Solution Architecture

### Overview

`run-cascade.sh` is a standalone Bash script that accepts a PLAN doc path,
walks the `upstream` frontmatter chain, and applies the appropriate lifecycle
transition at each node. It is invoked by the `plan_completion` state in
`work-on-plan.md` after CI passes. The script is idempotent: each transition
script it calls checks the current status and skips if already at the target.

### Components

```
work-on-plan.md (plan_completion directive)
  └── run-cascade.sh
        ├── get_frontmatter_field()        # inline: reads any frontmatter field
        ├── validate_upstream_path()       # inline: rejects out-of-tree and untracked paths
        ├── check_issue_closed()           # inline: queries gh for issue state
        ├── strip_implementation_issues()  # inline: awk strip of ## Implementation Issues
        ├── handle_design()                # call strip, then transition → Current
        ├── handle_prd()                   # transition → Done
        ├── handle_roadmap()               # update **Downstream:**, guard Done via check_issue_closed
        └── per-skill transition scripts (called by each handler):
              skills/design/scripts/transition-status.sh
              skills/prd/scripts/transition-status.sh
              skills/roadmap/scripts/transition-status.sh
```

The main loop:

```bash
current="$PLAN_DOC"
while [[ -n "$current" ]]; do
    next=$(get_frontmatter_field "upstream" "$current")
    [[ -z "$next" ]] && break
    case "$(basename "$next")" in
        DESIGN-*)  handle_design  "$next" ;;
        PRD-*)     handle_prd     "$next" ;;
        ROADMAP-*) handle_roadmap "$next"; break ;;  # terminal
        VISION-*)  break ;;                           # no-op terminal
        *)         log_warn "unknown artifact type: $next"; break ;;
    esac
    current="$next"
done
```

### Key Interfaces

**`run-cascade.sh` CLI:**
```bash
run-cascade.sh [--push] <plan-doc-path>
# --push: commit and push changes; without this flag, stages only (dry-run-safe)
# Exit 0: cascade ran (partial or complete)
# Exit 1: PLAN doc not found
# Outputs JSON: { "steps": [...], "cascade_status": "completed|partial|skipped" }
```

The `plan_completion` directive calls `run-cascade.sh --push {{PLAN_DOC}}`. Without
`--push` the script stages changes and prints a per-file summary (each file with its
before-status and after-status) but does not commit or push — enabling dry-run
inspection. The `--push` flag is explicit so the intent is visible in the template
and the script is safe to run manually without side effects.

**`validate_upstream_path`:**
```bash
validate_upstream_path <path>
# 1. Resolves with realpath; rejects if outside $REPO_ROOT.
# 2. Verifies the resolved path is a regular file (not a symlink, pipe, or device).
# 3. Verifies the file is tracked by git (git ls-files --error-unmatch).
# Exits non-zero and logs a warning on any failure. Called before every file
# operation on an upstream-derived path, including the initial git rm of the PLAN doc.
```

**`get_frontmatter_field`:**
```bash
get_frontmatter_field <field-name> <doc-path>
# Reads YAML frontmatter (between first --- pair), extracts named field value.
# Outputs the value or empty string. Never exits non-zero.
```

**`check_issue_closed`:**
```bash
check_issue_closed <github-issue-url>
# Parses the URL to extract owner, repo, and issue number.
# Validates that owner/repo matches the current repository's slug (from git remote).
# Queries via: gh issue view <number> --repo <owner/repo> --json state
# Returns 0 if closed, 1 if open or if URL does not match current repo.
```

**ROADMAP text substitution:**

ROADMAP feature status updates use fixed-string matching. The lookup targets the
`**Downstream:**` field of the feature entry containing the plan slug — not a
grep of the feature body. If no `**Downstream:**` field references the plan slug,
`handle_roadmap` logs a warning, sets `cascade_status: partial`, and skips the
update rather than silently succeeding. All substitutions use `awk` with
`ENVIRON["varname"]` (not `-v`) to avoid backslash interpretation of values.

**`handle_design`:**

1. Call `strip_implementation_issues` — idempotent `awk` strip of `## Implementation Issues` section.
2. Call `skills/design/scripts/transition-status.sh <path> Current`.
3. `git add` the file (or new path if moved), accumulate for final commit.

**`handle_prd`:**

1. Call `skills/prd/scripts/transition-status.sh <path> Done`.
2. `git add` the file.

**`handle_roadmap`:**

1. Locate the feature entry whose `**Downstream:**` field mentions the plan slug.
   Use `grep -F <plan-slug>` to find the line, then walk up to find the enclosing
   `### Feature N:` heading. If not found, emit a warning and return `partial`.
2. Update the feature's `**Status:**` to `Done` and `**Downstream:**` to include
   the DESIGN doc at Current status, using `awk` with `ENVIRON` for literal-safe
   substitution.
3. Guard the ROADMAP Done transition: call `check_issue_closed` on any open issue
   URLs referenced in the feature entry. Only transition if all referenced issues
   are confirmed closed.
4. If all features in the ROADMAP have `**Status:** Done`, call
   `skills/roadmap/scripts/transition-status.sh <path> Done`.
5. `git add` the file.

After all nodes are processed, the script commits and pushes all staged changes
in a single commit: `chore(cascade): post-implementation artifact transitions`.

### Data Flow

```
plan_completion directive
  → run-cascade.sh PLAN-<slug>.md
      → git rm PLAN-<slug>.md
      → get_frontmatter_field upstream PLAN-<slug>.md  → "docs/designs/DESIGN-foo.md"
          → handle_design docs/designs/DESIGN-foo.md
              → strip_implementation_issues
              → transition-status.sh ... Current
              → git add docs/designs/current/DESIGN-foo.md
          → get_frontmatter_field upstream DESIGN-foo.md  → "docs/prds/PRD-foo.md" (or ROADMAP)
          → handle_prd docs/prds/PRD-foo.md
              → transition-status.sh ... Done
              → git add docs/prds/PRD-foo.md
          → get_frontmatter_field upstream PRD-foo.md  → "docs/roadmaps/ROADMAP-bar.md"
          → handle_roadmap docs/roadmaps/ROADMAP-bar.md
              → update feature status + downstream field
              → check all features Done → if yes: transition-status.sh ... Done
              → git add docs/roadmaps/ROADMAP-bar.md
      → git commit + push
  → emit JSON result
  → agent submits cascade_status to koto
```

## Implementation Approach

### Phase 1: run-cascade.sh + test script

Deliverables:
- `skills/work-on/scripts/run-cascade.sh` — full implementation per the architecture above
- `skills/work-on/scripts/run-cascade_test.sh` — test harness using fixture docs; covers:
  - DESIGN→ROADMAP topology (no PRD)
  - DESIGN→PRD→ROADMAP topology
  - Idempotency (cascade runs twice, second run is no-op)
  - Missing upstream (PLAN has no `upstream` field → `cascade_status: skipped`)
  - Partial chain (DESIGN found but upstream PRD does not exist → `cascade_status: partial`)

### Phase 2: Update plan_completion directive

Deliverables:
- `skills/work-on/koto-templates/work-on-plan.md` — replace the current multi-step prose with a single invocation of `run-cascade.sh`, plus error handling
- `skills/work-on/SKILL.md` — update Completion Cascade section to reference the script

### Phase 3: Evals

Deliverables:
- Fixture documents for the two new Tier 2 scenarios:
  - `skills/work-on/evals/fixtures/plans/PLAN-cascade-test-short.md` — no PRD in chain; `upstream` points to a DESIGN doc
  - `skills/work-on/evals/fixtures/designs/DESIGN-cascade-test-short.md` — `upstream` points to ROADMAP fixture
  - `skills/work-on/evals/fixtures/plans/PLAN-cascade-test-full.md` — full chain; `upstream` points to DESIGN with a PRD upstream
  - `skills/work-on/evals/fixtures/designs/DESIGN-cascade-test-full.md` — `upstream` points to PRD fixture
  - `skills/work-on/evals/fixtures/prds/PRD-cascade-test-full.md` — `upstream` points to ROADMAP fixture
  - `skills/work-on/evals/fixtures/roadmaps/ROADMAP-cascade-test.md` — contains a feature entry with `**Downstream:**` referencing each fixture plan slug; all other features at Done
- Two new Tier 2 (execute-mode) eval scenarios in `skills/work-on/evals/`:
  - `e2e-cascade-design-roadmap`: invokes `run-cascade.sh` against the short-chain fixtures; asserts DESIGN transitions to Current and ROADMAP feature status updates
  - `e2e-cascade-design-prd-roadmap`: invokes `run-cascade.sh` against the full-chain fixtures; asserts all three transitions ran
- Updated eval #26 Tier 1 assertion contract: replaces the current prose-step expectations with a single behavioral assertion — "agent invokes `run-cascade.sh --push {{PLAN_DOC}}` as the plan_completion step rather than executing the cascade steps individually"

## Security Considerations

The cascade script reads document-derived values (frontmatter fields, GitHub URLs)
and uses them as filesystem paths and API arguments. Four constraints are required
to prevent input-handling bugs from causing unintended filesystem mutations or
remote state corruption.

**Path traversal via `upstream` field.** The `upstream` frontmatter value is used
as a file path without validation in the naive implementation. A crafted value
(e.g., `../../etc/passwd` or an absolute path outside the repo) could cause the
script to operate on unintended files. Mitigation: `validate_upstream_path`
canonicalizes with `realpath`, rejects any path that resolves outside `$REPO_ROOT`,
verifies the resolved path is a regular file (not a symlink whose target may escape
the tree, a named pipe, or a device), and verifies the file is tracked by git
(`git ls-files --error-unmatch`). This last check prevents a crafted `upstream`
from targeting any arbitrary `DESIGN-*.md` file within the repo that is not part of
the upstream chain being walked. The same guard applies to the PLAN doc path before
`git rm`.

**GitHub URL injection in `check_issue_closed`.** Passing a raw URL string from
frontmatter directly to `gh api` risks command injection if the URL contains shell
metacharacters, and cross-repo token probing if the URL points to a different
repository. Mitigation: the URL is parsed to extract owner, repo, and issue number
separately. The owner/repo is validated against the current repository slug (from
`git remote`). The API call uses `gh issue view <number> --repo <owner/repo>` with
individually validated components, never the raw URL as an opaque argument.

**Auto-push blast radius.** A bug or crafted input that causes the wrong files to
be staged would be pushed to the remote without a confirmation step, making recovery
require a force-push or revert commit. Mitigation: the `--push` flag separates
staging from pushing. Without `--push`, the script stages changes and prints a
summary but does not push. The `plan_completion` directive passes `--push`
explicitly, making the intent visible in the template.

**ROADMAP text substitution with special characters.** If the plan slug contains
sed regex metacharacters, a naive `sed -i` substitution could match unintended
lines or corrupt the file. A subtler issue: `awk -v varname="$value"` interprets
backslash sequences in the assigned string (e.g., `\n` becomes a newline), which
can cause multi-line injection even with `awk` instead of `sed`. Mitigation: all
ROADMAP lookups use `grep -F` (fixed-string), and all substitutions use `awk` with
`ENVIRON["varname"]` to read values from the environment rather than `-v`, which
fully prevents backslash interpretation.

**`--push` summary must be meaningful.** The `--push` flag only provides a
meaningful gate if the summary it prints is specific enough to verify. The summary
must list each file that will be staged with its before-status and after-status
(e.g., `docs/designs/DESIGN-foo.md: Planned → Current`). A vague "cascade
completed" message turns the gate into theater.

Residual risk: the threat model assumes documents in the working tree originate
from trusted contributors under version control. In fork-PR workflows, documents
from external contributors could reach the working tree; the mitigations above
(path validation, git-tracked-file check, URL validation) address these cases. No
externally sourced runtime inputs are processed beyond the git working tree. The
`origin` remote is used as the authoritative source for repository slug validation
in `check_issue_closed`; multi-remote setups should ensure `origin` is the canonical
remote before running the cascade.

## Consequences

### Positive

- Arbitrary chain topologies work correctly without code changes — adding a new
  intermediate artifact type requires one `case` entry in the dispatch table.
- Cascade behavior is deterministic and testable; the topology bug in the current
  directive prose is eliminated.
- DESIGN docs at Current status are clean: no broken PLAN link, no stale
  implementation scaffolding, durable content fully preserved.
- The `plan_completion` directive shrinks from ~60 lines of prose to a single
  invocation, reducing the surface where agent interpretation can diverge.

### Negative

- Cascade logic now lives in two places: the koto template (for state machine
  context) and `run-cascade.sh` (for execution logic). Maintainers must know to
  look in both.
- The ROADMAP feature-update step (step 4 of `handle_roadmap`) requires finding
  the feature entry by plan slug, which is a heuristic text search. If the feature
  entry doesn't mention the plan slug, the update is silently skipped.
- Compression is one-way: once `## Implementation Issues` is stripped from a
  DESIGN doc, it cannot be recovered except from git history.

### Mitigations

- A clear comment in the `plan_completion` directive points maintainers to
  `run-cascade.sh`. This is the same pattern as `plan-to-tasks.sh`.
- The ROADMAP feature lookup logs a warning if no matching entry is found,
  setting `cascade_status: partial` rather than silently succeeding. The agent
  can then surface this to the user.
- The strip operation is idempotent and only removes a section with a known
  deterministic heading. A section-presence check before invoking the `awk` strip
  prevents empty-file bugs if Implementation Issues is the last section.
