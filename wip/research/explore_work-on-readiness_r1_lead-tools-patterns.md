# Work-on Skill Readiness Research: Lead Tools Patterns

**Date**: 2026-04-15  
**Scope**: Patterns from lead tools repo relevant to work-on robustness in shirabe  
**Note**: This document analyzes internal patterns for robustness improvements; specific tool repo references are redacted from public use.

---

## 1. Deterministic Document Parsing Patterns

### 1.1 Modular Validation Scripts

The lead tools repo uses a **composable validation architecture** with:

- **Common interface** (`common.sh`): Shared utilities for all check scripts
  - Exit code contract: `0=pass, 1=fail, 2=operational error`
  - Output format: `[PASS]` / `[FAIL]` messages (quiet mode supported)
  - Exported functions: `extract_frontmatter()`, `get_frontmatter_status()`, `has_frontmatter()`

- **Modular check scripts** in `checks/` directory:
  - `frontmatter.sh`: Validates YAML frontmatter (FM01-FM03): presence, status value, sync with body
  - `sections.sh`: Validates 9 required H2 sections in correct order (SC01-SC03)
  - `mermaid.sh`: Complex diagram validation (MM01-MM21): syntax, class assignments, GitHub status sync
  - `implementation-issues.sh`: Validates issues table format (II00-II08): columns, links, strikethrough consistency
  - `issue-status.sh`: Cross-validates strikethrough against actual GitHub issue state
  - `status-directory.sh`: Validates document path matches status
  - `strikethrough-all-docs.sh`: Batch checker for closing-issues consistency across docs

### 1.2 Parsing Strategy

- **AWK for structured extraction**: Section headers, table headers, frontmatter boundaries
  - Handles code block skipping (fenced blocks not parsed)
  - Handles case variations (e.g., `**Status:** value` vs `**Status: Value**`)
- **Grandfathering pattern**: File creation date checks allow phased rollout
  - `get-file-creation-commit.sh` queries git history
  - Cutoff dates per check category (e.g., II_CHECK_CUTOFF="2026-01-01")
  - Skip validation for files predating cutoff

### 1.3 Helper Scripts

- `extract-design-issues.sh`: Parses Implementation Issues table from doc
- `extract-closing-issues.sh`: Identifies issues being closed by a PR
- `get-github-status.sh`: Batch-queries GitHub API for issue/milestone state
- `check-issue-status.sh`: Single-issue diagram status checker

---

## 2. CI Checks in Lead Tools Repo

### 2.1 Workflow Structure

**ci.yml** (main CI):
- Enforces: `wip/` directory not committed (breaks on `wip/` or deprecated `issue_work/`)
- Script sync check: `.github/scripts/` must not diverge from `scripts/ci/` (canonical source)
- Runs: Mermaid golden file tests (`tests/run-mermaid-golden.sh`)
- Verifies: Install script works with mock workspace structure

**Dedicated validation workflows**:
- `validate-design-docs.yml`: Runs full document validation on all `DESIGN-*.md` files
- `validate-issue-status.yml`: Checks strikethrough formatting matches GitHub state for changed docs
- `validate-diagram-status.yml`: Ensures issues being closed are marked `done` in diagrams
- `validate-closing-issues.yml`: Cross-doc consistency for closing issues
- `sync-ci-scripts.yml`: Syncs canonical `scripts/ci/` to `.github/scripts/`

### 2.2 Test Harnesses in CI

- **Golden file tests**: Pre-computed fixture files with expected pass/fail outcomes
  - `run-mermaid-golden.sh`: 80+ tests covering MM01-MM21 rules
  - `run-ii-golden.sh`: Tests for implementation-issues validation
  - Both use exit code comparison (no string matching on output)
  - JSON files provide mock GitHub state for status checks
- **No explicit test step in main CI**: Tests run via shell scripts in `tests/` directory

### 2.3 Checks Shirabe Lacks

- **Document format validation**: frontmatter, sections, structure
- **Diagram validation**: Mermaid syntax, class/label consistency
- **Cross-document consistency**: Closing issues marked complete in all docs
- **strikethrough-GitHub sync**: Explicit validation that marked items match actual state
- **WIP directory enforcement**: No check preventing `wip/` commits

---

## 3. Work-on Skill Structure Patterns in Lead Tools

### 3.1 Phase-Based Workflow Architecture

The legacy work-on skill uses **7 sequential phases** with **resumability artifacts**:

| Phase | Artifact | Purpose |
|-------|----------|---------|
| 0 | IMPLEMENTATION_CONTEXT.md (ephemeral) | Surface design context |
| 1 | wip/issue_<N>_baseline.md | Test/coverage baseline |
| 2 | wip/issue_<N>_introspection.md | Issue staleness check |
| 3 | wip/issue_<N>_plan.md | Implementation planning |
| 4 | Working code + commits | Implementation |
| 5 | wip/issue_<N>_summary.md | Summary before PR |
| 6 | Merged PR | Final delivery |

**Resume logic**: Check artifact existence AND git commit history to determine current phase.

### 3.2 Input Resolution & Blocking Checks

**Before Phase 0**:
1. Resolve input (issue #N, M<milestone>, or URL)
2. For milestone input: Select first unblocked issue (dependencies checked in Dependencies section)
3. Read issue with `gh issue view`
4. Check for blocking labels and **stop execution**:
   - `tracks-design`/`tracks-plan` → route to `/implement-doc`
   - `needs-design` → route to `/explore`
   - `needs-prd`, `needs-spike`, `needs-decision` → specialized routing

### 3.3 Guard Rails

- **Explicit phase documentation**: Each phase has dedicated instructions
- **Artifact pattern detection**: File existence indicates step completion
- **Atomic commit strategy**: Commit after logical unit of work
- **Quality gates**: Each phase has explicit success criteria
- **CI completion requirement**: PR not done until all CI checks pass
- **Introspection phase**: Validates issue spec hasn't become stale before implementation

### 3.4 Helper Skills Invoked

- `go-development`, `nodejs`, `rust-development`: Language-specific requirements
- `pr-creation`: PR creation and CI monitoring
- `upstream-context`: Gathers context for triaged issues
- `triage`: Jury-based assessment (needs-design vs breakdown vs ready)

---

## 4. Patterns Worth Porting to Shirabe Work-on

### 4.1 Pre-Flight Checks (High Priority)

1. **Blocking label detection**: Stop if `tracks-design`, `tracks-plan`, or `needs-*` labels present
   - Prevents workflow on issues that need upstream resolution
   - Provides clear routing messages

2. **Introspection phase**: Detect stale issue specs before coding
   - Uses `/tsukumogami:issue-staleness` skill (private tools repo has this)
   - Validates context is current

3. **Input resolution**: Handle issue, milestone, and URL inputs uniformly
   - Resolve milestone to first unblocked issue
   - Pre-check dependencies

### 4.2 Artifact & Resumability (High Priority)

1. **Artifact-based phase tracking**:
   - Use `wip/issue_<N>_*` files as resume markers
   - Check both file existence and commit history
   - Enables resumption after interruption

2. **Baseline artifact**: Establish test/coverage baseline at Phase 1
   - Enables detection of regressions
   - Provides context for implementation

3. **Summary artifact**: Create human-readable summary before PR
   - Documents decisions made
   - Facilitates code review

### 4.3 Document Validation (Medium Priority)

1. **Deterministic parsing library**: Adapt `common.sh` pattern to bash/TypeScript
   - Centralized frontmatter/section extraction
   - Consistent error handling and output

2. **Golden file tests**: Create fixture-based test suite
   - Pre-computed expected outcomes
   - Enables CI validation without manual review

3. **Grandfathering pattern**: Phased rollout of new checks
   - Skip validation for files predating cutoff
   - Allows incremental adoption

### 4.4 CI Improvements (Medium Priority)

1. **WIP directory enforcement**: Fail if `wip/` committed to main
   - One-line check in main CI workflow

2. **Script sync verification**: If CI scripts are canonical, verify `.github/workflows/` stays in sync

3. **Golden file tests in CI**: Run structured test harness in main CI
   - Validates document format expectations
   - Catches regressions early

---

## 5. Error Handling & Recovery Patterns

### 5.1 Graceful Degradation

- **Issue-status.sh**: Gracefully degrades if GitHub API unavailable
  - Warns but doesn't fail
  - Requires `gh` CLI and `jq` but handles missing tools
- **Mermaid check**: `--skip-status-check` flag for offline validation

### 5.2 Self-Loops for Retry

- Koto templates use conditional self-loops instead of explicit retry logic
- Prevents cycle detection from failing
- Examples: `scope_changed_retry`, `partial_tests_failing_retry`

---

## 6. Implementation Priority for Shirabe Work-on

**Phase 1 (Unblock main workflow)**:
- Blocking label detection (pre-flight)
- Input resolution with unblocked issue selection
- Phase-based artifact tracking

**Phase 2 (Enable resumability)**:
- Baseline & summary artifacts
- Commit history-based phase detection
- Graceful handling of missing tools

**Phase 3 (Add robustness)**:
- Document validation library (if PLAN docs are in scope)
- Golden file tests
- CI enforcement (wip directory)

**Phase 4 (Improve UX)**:
- Introspection phase for issue staleness
- Enhanced error messages
- Self-loop retry patterns

---

## 7. Key Takeaway

The lead tools repo demonstrates that **modular, composable validation** with **grandfathering and artifact-based tracking** provides both robustness and resumability. The pattern of separating concerns (parsing, validation, GitHub sync) makes each component testable independently and reduces friction for adding new checks.

For shirabe's work-on skill, the highest-impact improvements are:
1. **Blocking label routing** (prevents wasted effort)
2. **Artifact-based resumability** (enables interruption/resumption)
3. **Pre-flight input validation** (catches issues early)
