# Shirabe Format Validation & Cascade Error Handling Research

## 1. What Format Does the Cascade Require from Upstream Docs?

### PLAN Frontmatter Requirements
The cascade script (`run-cascade.sh`) expects PLAN documents with these frontmatter fields:
- **schema**: `plan/v1` (required, validated in plan-to-tasks.sh)
- **status**: lifecycle state (required, read by cascade)
- **execution_mode**: `single-pr` or `multi-pr` (required)
- **upstream**: path to source document (optional)
- **milestone**: milestone name (required in PLAN schema)
- **issue_count**: issue count (required in PLAN schema)

### DESIGN Frontmatter Requirements
Designs must have:
- **status**: current state (required; cascade validates it exists)
- **problem**: 1 paragraph (required in design schema)
- **decision**: 1 paragraph (required in design schema)
- **rationale**: 1 paragraph (required in design schema)
- **upstream**: optional path (can point to PRD or ROADMAP)

The cascade uses `get_frontmatter_field()` to extract the `upstream` field via `awk` pattern matching. It strips surrounding quotes and handles multi-line values.

### PRD Frontmatter Requirements
PRDs must have:
- **status**: lifecycle state (required, validated)
- **problem**: 1 paragraph (required)
- **goals**: 1 paragraph (required)
- **upstream**: optional path to ROADMAP
- **source_issue**: optional GitHub issue number

### ROADMAP Frontmatter Requirements
Roadmaps must have:
- **status**: lifecycle state (required)
- **theme**: 1 paragraph describing initiative (required)
- **scope**: 1 paragraph bounding features (required)
- **upstream**: optional path to VISION doc

### Missing or Malformed Fields: Error Handling

**When a field is missing:**
- `run-cascade.sh` reads the `upstream` field using `get_frontmatter_field()` which returns empty string if not found
- If upstream is empty, cascade skips gracefully with `cascade_status: skipped` (line 530-533)
- No errors logged for missing optional upstream field

**When a field is malformed:**
- `get_frontmatter_field()` uses safe `awk` index() matching, avoiding regex injection (lines 63-80)
- Returns empty string for unparseable values, doesn't crash
- Script validates upstream paths with `validate_upstream_path()` which:
  - Checks path is within repo root (no traversal attacks)
  - Validates it's a regular file (not symlink, pipe, device)
  - Checks git tracking status
  - Logs warnings but doesn't exit the cascade (except PLAN level)

**PLAN-level validation failure (blocking):**
- If PLAN doc doesn't exist or fails validation, cascade exits with code 1 and outputs error JSON
- This prevents cascade from attempting upstream chain with broken PLAN

**Mid-chain validation failure (non-blocking):**
- If upstream reference is broken, cascade adds failed step to output JSON with detail message
- Sets `cascade_status: partial` rather than crashing
- Logs detailed failure reasons for user debugging

### Pre-flight Validation

The cascade has **no separate pre-flight validation** before running. Instead, it:
1. Validates PLAN path early (exit 1 if invalid)
2. Discovers problems during chain walk (lines 539-608)
3. Handles each failure gracefully with step detail messages
4. Emits JSON describing what succeeded vs. failed

Missing required fields in non-PLAN docs are discovered mid-run when cascade attempts to read them.

---

## 2. What Format Does plan-to-tasks.sh Require from PLAN Docs?

### Required Frontmatter Fields
`plan-to-tasks.sh` validates these fields before processing (lines 412-429):
- **schema**: must be exactly `plan/v1` (dies with exit code 2 if mismatch)
- **execution_mode**: must be `single-pr` or `multi-pr` (dies with exit code 2 if unknown)

If either is missing or malformed, the script exits immediately with detailed error.

### PLAN Doc Structure by Execution Mode

#### Single-PR Mode
Requires a **## Issue Outlines** section (lines 249-288) with this structure:
```
### Issue N: Title
**Complexity**: simple|testable|critical
**Goal**: <description>
**Acceptance Criteria**:
- [ ] <criteria>
**Dependencies**: None. | Issue N, Issue M, etc.
```

The parser extracts:
- Issue number from heading regex: `^###[[:space:]]+Issue[[:space:]]+([0-9]+):`
- Title from heading (converted to task name via slugify)
- Dependencies from `**Dependencies**:` line (parses "Issue N" references)

Validates that all referenced dependencies are defined (dies exit 2 if undefined issue referenced).

#### Multi-PR Mode
Requires a **## Implementation Issues** table (lines 100-232) with:
- Header row containing "Issue" and "Dependencies" column names
- Data rows starting with `|` containing issue numbers as `#N`
- Dependencies column with `None` or comma-separated `#N` references

Parser extracts:
- Issue number from first cell using regex: `#([0-9]+)`
- Dependencies from Dependencies column (parses `#N` references)

### Missing or Malformed Issue Outlines

**Single-PR missing outline section:**
- `die_schema` exits with code 2: "single-pr PLAN has no issue outlines in ## Issue Outlines section"

**Issue outline missing required fields:**
- Missing `**Dependencies**:` line → current_deps stays empty, treated as "None"
- Missing issue number in heading → continue (skip malformed entry)
- If NO valid outlines found → `die_schema` with exit 2

**Malformed dependency references:**
- References unknown Issue N → `die_schema` with message "references unknown dependency Issue X"
- Exit code 2 (schema error, not input error)

**Multi-PR missing Implementation Issues table:**
- `die_schema` exits with code 2: "multi-pr PLAN has no rows in Implementation Issues table"

**Malformed table rows:**
- Rows without `#N` in first cell are skipped (continue)
- If NO valid rows found after skipping → `die_schema` with exit 2
- Missing Dependencies column → fallback to last non-empty cell in row

### Exit Code Semantics
- Exit 0: Success
- Exit 1: Input error (file not found, not readable, jq missing)
- Exit 2: Schema mismatch or unsanitizable name

---

## 3. Is There Any Document Format Validation in CI or Scripts?

### CI Workflows Validating Frontmatter/Structure

**check-plan-scripts.yml** (lines 1-19):
- Triggered on PR changes to `skills/plan/scripts/**`
- Runs `bash skills/plan/scripts/plan-to-tasks_test.sh`
- Tests both single-pr and multi-pr mode parsing
- Validates generated task names match R9 regex: `^[a-z][a-z0-9-]*$`
- Validates dependency graph integrity (diamond dependencies, circular references)
- **Does NOT validate arbitrary PLAN docs** — only tests the script itself

**check-sentinel.yml** (lines 1-52):
- Validates plugin manifest versions carry `-dev` suffix on main
- NOT related to document format

**validate-templates.yml** (lines 1-38):
- Validates all `**/koto-templates/*.md` files
- Uses `koto template compile <template>` to check syntax
- NOT validating PLAN/DESIGN/PRD/ROADMAP formats

**check-evals.yml** (referenced in scripts/check-evals-exist.sh):
- Checks evaluation files exist
- NOT validating document formats

### Inline Validation in Scripts

**run-cascade.sh** contains the most validation:
- `get_frontmatter_field()` (lines 63-80): safe YAML frontmatter extraction
- `validate_upstream_path()` (lines 82-119): path traversal, symlink, git tracking checks
- `check_issue_closed()` (lines 121-168): validates GitHub issue URLs match current repo
- All validations are error-handling, not pre-flight (discovered during execution)

**plan-to-tasks.sh** validates:
- File existence and readability (lines 403-409)
- Frontmatter starts with `---` (lines 414-417)
- `schema: plan/v1` exact match (lines 419-424)
- `execution_mode` is one of: single-pr, multi-pr (lines 426-429)
- Required sections for execution mode (single-pr or multi-pr)
- Issue outline structure in single-pr mode
- Implementation Issues table structure in multi-pr mode
- Task name validation against R9 regex (lines 53-59)
- All referenced dependencies exist

### Key Finding: NO Pre-Cascade Validation

The shirabe repository has **NO centralized document format validator** that runs before the cascade. Instead:
1. Format validation is distributed across individual scripts
2. Validation is discovery-based (fails during execution, not before)
3. `plan-to-tasks.sh` performs the strictest validation (schema, required fields, references)
4. `run-cascade.sh` performs defensive validation during chain walk (path checks, git checks)
5. CI only tests the validation scripts themselves, not arbitrary docs

There is no CI job that validates all PLAN, DESIGN, PRD, ROADMAP documents in a repo. Format errors are discovered at runtime by the specific skill (plan-to-tasks.sh failing, cascade failing partway through, etc.).

