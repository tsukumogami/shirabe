# Phase 4: Agent-Based Issue Generation

Generate issue bodies using parallel agents with full design context and downstream awareness.

## Table of Contents

- [Resume Check](#resume-check)
- [Execution Mode](#execution-mode)
- [Prerequisites](#prerequisites)
- [Steps](#steps): 4.1 Build Downstream Mapping, 4.2 Read Design Document, 4.3 Read Agent Prompt Template, 4.4 Prepare Agent Contexts, 4.5 Spawn Agents in Parallel, 4.6 Collect Agent Results, 4.7 Validate Agent Outputs, 4.8 Handle Validation Failures, 4.9 Handle Agent Timeouts, 4.10 Compile Final Manifest, 4.11 Report Summary
- [Success Criteria](#success-criteria)
- [Output](#output)

## Resume Check

If `wip/plan_<topic>_manifest.json` exists, read it and skip to Phase 5. The manifest contains references to all generated issue body files.

This check works for both execution modes -- the manifest tracks outputs regardless of whether agents produced full issue bodies (multi-pr) or structured outlines (single-pr).

## Execution Mode

Read `wip/plan_<topic>_decomposition.md` and parse the YAML frontmatter `execution_mode` field.

- **multi-pr**: Agents write full issue body files with validation scripts, complexity-specific sections (Security Checklist for critical), and downstream deliverables. This is the default and produces artifacts suitable for GitHub issue creation in Phase 7.
- **single-pr**: Agents write lighter structured outlines with goal, acceptance criteria, and dependencies. No validation scripts. No Security Checklist. The template used focuses on outline structure rather than full issue body. Phase 7 produces a PLAN doc instead of GitHub issues.

The execution mode affects:
1. Which instructions are included in the agent prompt (`{{EXECUTION_MODE}}` placeholder)
2. What validation checks are applied to agent output (step 4.7)
3. What sections are required in the output files

## Prerequisites

This phase runs after Phase 3 (Decomposition) and before Phase 5 (Dependencies).

**Read from artifacts:**
1. `wip/plan_<topic>_decomposition.md` - Parse YAML frontmatter to get:
   - `design_doc` - Path to design document
   - `input_type` - "design", "prd", or "roadmap"
   - `decomposition_strategy` - "walking-skeleton", "horizontal", or "feature-by-feature-planning"
   - `issue_count` - Number of issues
   - `execution_mode` - "single-pr" or "multi-pr"
2. Parse the Issue Outlines section to get each issue's: id, title, type, complexity hint, goal, section, dependencies
   - For roadmap issues, also parse: `needs_label`, `Feature`

**Derived values:**
- `skeleton_mode` = true if `decomposition_strategy` is "walking-skeleton"
- `skeleton_id` = "1" (first issue is always skeleton when in skeleton mode)

**Note on IDs**: Issues don't have GitHub numbers yet. Each outline has an internal `id` (e.g., `1`, `2`, `3`) assigned during Phase 3 decomposition. Dependencies reference these internal IDs, not GitHub issue numbers. Phase 7 will map internal IDs to GitHub numbers when creating issues.

**Note on Complexity**: Agents determine the validation complexity for each issue based on scope and risk. The complexity hint from Phase 3 is advisory - agents finalize it.

## Goal

Spawn parallel agents to generate issue bodies that:
- Include full design context
- Are aware of what downstream dependents need
- Use complexity-appropriate validation templates (multi-pr) or structured outlines (single-pr)
- Follow safe execution patterns

## Steps

### 4.1 Build Downstream Mapping

**Skip this step if `input_type` is `roadmap`.** Roadmap planning issues don't need downstream mapping -- each issue independently produces an artifact. Proceed directly to step 4.2.

For design and prd input types, run the dependency graph script to compute what each issue blocks:

```bash
SCRIPT_DIR="../../scripts"
echo '<issue_outlines_json>' | "$SCRIPT_DIR/build-dependency-graph.sh"
```

Store the `downstream` mapping for use in agent prompts.

### 4.2 Read Design Document

Use the Read tool to read the full design document at `<design_doc_path>`.

Store the content for inclusion in agent prompts.

### 4.3 Read Agent Prompt Template

Select the agent prompt template based on `input_type`:

- **roadmap**: `../templates/agent-prompt-planning.md`
- **design** or **prd**: `../templates/agent-prompt.md`

Use the Read tool to read the selected template.

### 4.4 Prepare Agent Contexts

For each issue in `issue_outlines`:

#### Standard issues (input_type: design or prd)

1. Extract issue-specific fields: id, title, section, dependencies
2. Look up downstream dependents from the mapping (built in 4.1)
3. For each downstream dependent, include their title and section summary
4. Build skeleton context (if skeleton_mode is true):
   - `is_skeleton_issue` - true if this is issue ID "1", false otherwise
   - `skeleton_id` - the skeleton issue ID (typically "1")
   - `refinement_sequence` - for non-skeleton issues, their position (2, 3, 4...)
5. Build execution mode context string:
   - multi-pr: `"execution_mode": "multi-pr"` -- full issue body with all complexity-specific sections
   - single-pr: `"execution_mode": "single-pr"` -- lighter structured outline
6. Substitute placeholders in the agent prompt template:
   - `{{DESIGN_DOC_CONTENT}}` - Full design document
   - `{{ISSUE_ID}}` - Internal ID (e.g., "1", "2", "3")
   - `{{ISSUE_TITLE}}` - This issue's title
   - `{{ISSUE_DEPENDENCIES}}` - List of internal IDs this issue depends on (e.g., "1, 2" or "None")
   - `{{ISSUE_SECTION}}` - Design section this issue implements
   - `{{DOWNSTREAM_DEPENDENTS}}` - Formatted list of dependent issues with their IDs and titles
   - `{{SKELETON_CONTEXT}}` - JSON object with skeleton mode info:
     ```json
     {
       "skeleton_mode": true,
       "is_skeleton_issue": false,
       "skeleton_id": "1",
       "refinement_sequence": 2
     }
     ```
     Or if not in skeleton mode: `{"skeleton_mode": false}`
   - `{{EXECUTION_MODE}}` - JSON object: `{"execution_mode": "multi-pr"}` or `{"execution_mode": "single-pr"}`
   - `{{TOPIC}}` - The topic slug used in file paths (e.g., "artifact-workflow")

#### Planning issues (input_type: roadmap)

1. Extract issue-specific fields: id, title, section (feature description), dependencies, needs_label, Feature
2. Downstream dependents: use dependencies from the issue outlines (from step 3.R2) -- no downstream mapping script needed
3. Build execution mode context string (same as standard)
4. Substitute placeholders in the planning agent prompt template:
   - `{{DESIGN_DOC_CONTENT}}` - Full roadmap document
   - `{{ISSUE_ID}}` - Internal ID
   - `{{ISSUE_TITLE}}` - This issue's title
   - `{{ISSUE_DEPENDENCIES}}` - List of internal IDs this issue depends on
   - `{{ISSUE_SECTION}}` - The feature description from the roadmap
   - `{{DOWNSTREAM_DEPENDENTS}}` - Issues that depend on this one (from dependency edges in outlines)
   - `{{NEEDS_LABEL}}` - The per-issue needs label (e.g., "needs-design", "needs-prd")
   - `{{EXECUTION_MODE}}` - JSON object: `{"execution_mode": "multi-pr"}` or `{"execution_mode": "single-pr"}`
   - `{{TOPIC}}` - The topic slug used in file paths

### 4.5 Spawn Agents in Parallel

**Critical**: Launch ALL agents in a single message with multiple Task tool calls --
parallel spawning reduces wall-clock time by N-fold for N agents.

Each agent writes its output to a file and returns only a structured summary to conserve context.

For each issue, invoke Task with:
- `subagent_type`: "general-purpose"
- `run_in_background`: true
- `prompt`: The prepared agent prompt with all context, plus:
  - Output file path: `wip/plan_<topic>_issue_<id>_body.md`
  - Instructions to write the full body to that file
  - Instructions to return ONLY the structured summary

**Agent output instructions** (include in each prompt):
```
Write the complete issue body to: wip/plan_<topic>_issue_<id>_body.md

After writing the file, return ONLY this structured summary.
Do NOT include any part of the issue body in your response.
```
Status: PASS | VALIDATION_FAILED | ERROR
Complexity: <simple|testable|critical>
File: wip/plan_<topic>_issue_<id>_body.md
Sections: <comma-separated list of sections present>
Dependencies: <issue IDs or "none">
```
```

Example pattern:
```
In a single response, invoke Task N times (one per issue):

Task 1: Generate body for "Issue Title 1"
  - run_in_background: true
  - prompt: <prepared prompt with context and file output instructions>

Task 2: Generate body for "Issue Title 2"
  - run_in_background: true
  - prompt: <prepared prompt with context and file output instructions>

... and so on for all issues
```

Record each agent's task_id for result collection.

### 4.6 Collect Agent Results

Use TaskOutput to collect summaries from each agent with timeout handling:

```
For each task_id:
  1. Call TaskOutput with task_id and timeout (60 seconds)
  2. Parse the structured summary (NOT the full body)
  3. Verify the output file exists
  4. Record success/failure status
```

Build results manifest (lightweight, no full bodies):
```json
{
  "issue_id": "1",
  "title": "...",
  "complexity": "testable",
  "file": "wip/plan_<topic>_issue_1_body.md",
  "status": "PASS",
  "agent_id": "abc123"
}
```

### 4.7 Validate Agent Outputs

For each result where the agent reported PASS, read the output file and validate.

**Validation differs by execution mode and input type:**

#### Roadmap planning issue validation (input_type: roadmap)

Planning issues have lighter validation since they are always `simple` complexity:

```
For each result with status=PASS:
  1. Read the file at result.file using the Read tool
  2. Parse YAML front matter to extract complexity
  3. Validate content against planning requirements (below)
  4. Update status to VALIDATION_FAILED if checks fail
```

**Front matter validation**:
- [ ] File starts with `---` (YAML front matter delimiter)
- [ ] Contains `complexity: simple`
- [ ] Contains `complexity_rationale:` field (non-empty)
- [ ] Front matter ends with `---`

**Structural validation**:
- [ ] Contains `## Goal` section
- [ ] Contains `## Context` section
- [ ] Context section contains `Roadmap:` reference line
- [ ] Context section contains `Feature:` reference line
- [ ] Contains `## Acceptance Criteria` section
- [ ] AC items are artifact-oriented (exists, status, format checks -- not code-level)
- [ ] Contains `## Dependencies` section

**No complexity-specific validation**: Planning issues are always simple -- no validation scripts or security checklists.

#### multi-pr mode validation (input_type: design or prd)

```
For each result with status=PASS:
  1. Read the file at result.file using the Read tool
  2. Parse YAML front matter to extract complexity
  3. Validate content against complexity requirements (full checks below)
  4. Update status to VALIDATION_FAILED if checks fail
```

**Front matter validation**:
- [ ] File starts with `---` (YAML front matter delimiter)
- [ ] Contains `complexity:` field with value `simple`, `testable`, or `critical`
- [ ] Contains `complexity_rationale:` field (non-empty)
- [ ] Front matter ends with `---`

**Skeleton-specific front matter validation** (if skeleton_mode is true):
- For skeleton issues (id = skeleton_id):
  - [ ] Contains `skeleton: true`
  - [ ] Complexity is `testable`
- For refinement issues:
  - [ ] Contains `skeleton_refinement: true`
  - [ ] Contains `skeleton_id: <<ISSUE:N>>` where N is the skeleton issue ID

Extract the complexity value and store it in the manifest for this issue.

**Structural validation** (all complexity levels):
- [ ] Contains `## Goal` section
- [ ] Contains `## Context` section
- [ ] Contains `## Acceptance Criteria` section
- [ ] Contains `## Dependencies` section
- [ ] Contains `## Downstream Dependencies` section

**Complexity-specific validation** (based on complexity from front matter):

For **testable** and **critical** complexity levels:
- [ ] Contains `## Validation` section with bash code block
- [ ] Validation script uses `set -euo pipefail`
- [ ] Heredocs use quoted delimiter pattern: `<<'EOF'`
- [ ] No unsafe patterns: `eval`, backticks, `curl | bash`

For **critical** complexity only:
- [ ] Contains `## Security Checklist` section

**Downstream deliverables** (if issue has downstream dependents):
- [ ] Contains explicit deliverable statements: "Must deliver: X (required by #Y)"
- [ ] OR contains placeholder: "Must unblock #Y"

#### single-pr mode validation

```
For each result with status=PASS:
  1. Read the file at result.file using the Read tool
  2. Parse YAML front matter to extract complexity
  3. Validate content against lighter requirements (below)
  4. Update status to VALIDATION_FAILED if checks fail
```

**Front matter validation** (same as multi-pr):
- [ ] File starts with `---` (YAML front matter delimiter)
- [ ] Contains `complexity:` field with value `simple`, `testable`, or `critical`
- [ ] Contains `complexity_rationale:` field (non-empty)
- [ ] Front matter ends with `---`

**Skeleton-specific front matter validation**: Same as multi-pr mode.

**Structural validation** (lighter):
- [ ] Contains `## Goal` section
- [ ] Contains `## Acceptance Criteria` section
- [ ] Contains `## Dependencies` section

**No complexity-specific validation**: Validation scripts and Security Checklists are not required in single-pr mode.

### 4.8 Handle Validation Failures

If validation fails:

1. **First retry**: Re-invoke agent with simplified prompt focusing on the failed validation
2. **Second failure**: Fall back to minimal template generation (use render-template.sh)
3. **Complete failure**: Mark `success: false` with error message

For fallback template generation:
```bash
SCRIPT_DIR="../../scripts"
echo '<minimal_json>' | "$SCRIPT_DIR/render-template.sh"
```

### 4.9 Handle Agent Timeouts

If TaskOutput times out (>60 seconds):

1. Log timeout event with agent_id
2. Fall back to single LLM call without downstream context
3. If fallback also fails, mark `success: false`

### 4.10 Compile Final Manifest

Build final manifest (file references, not bodies):
```json
[
  {
    "issue_id": "1",
    "title": "...",
    "complexity": "testable",
    "file": "wip/plan_<topic>_issue_1_body.md",
    "status": "PASS",
    "agent_id": "abc123"
  },
  {
    "issue_id": "2",
    "title": "...",
    "complexity": "critical",
    "file": "wip/plan_<topic>_issue_2_body.md",
    "status": "VALIDATION_FAILED",
    "agent_id": "def456",
    "error": "missing Security Checklist"
  }
]
```

**For roadmap input type**, include additional fields from the decomposition artifact:
```json
{
  "issue_id": "1",
  "title": "docs(prd): user authentication",
  "complexity": "simple",
  "file": "wip/plan_<topic>_issue_1_body.md",
  "status": "PASS",
  "needs_label": "needs-prd",
  "dependencies": []
}
```

The `needs_label` field is consumed by `create-issues-batch.sh` (Phase 7) to apply per-issue labels.
The `dependencies` array lists internal IDs this issue is blocked by (used for topological sort).

Write this manifest to `wip/plan_<topic>_manifest.json` for Phase 5 to consume.

### 4.11 Report Summary

Output summary for main chat:

```
Agent Generation Complete

Total issues: N
Successful: X
Failed: Y
Execution mode: <single-pr|multi-pr>

Failed issues (require manual creation):
- Issue "Title": <error message>

Proceeding to Phase 5 with X generated issue bodies.
```

## Success Criteria

- [ ] All agents spawned in parallel (single message with multiple Task calls)
- [ ] Results collected from all agents within timeout
- [ ] All successful bodies pass structural validation (mode-appropriate)
- [ ] Complexity-specific validation applied correctly (multi-pr only)
- [ ] Fallback mechanisms handle failures gracefully
- [ ] Final results array contains all issues with success/failure status

## Output

Phase 4 produces these artifacts:

**Files created:**
- `wip/plan_<topic>_issue_<id>_body.md` - One file per issue containing the full body (multi-pr) or structured outline (single-pr)
- `wip/plan_<topic>_manifest.json` - Manifest with file references and status

**For Phase 5:**
- Read `wip/plan_<topic>_manifest.json` to get file paths and complexity levels
- Use for dependency verification

**For Phase 7:**
- Read `wip/plan_<topic>_manifest.json` to get file paths
- For each issue, read the body from `manifest[i].file`
- Use `manifest[i].complexity` for label management
- Skip issues with `status != "PASS"` (report for manual creation)

## Next Phase

Proceed to Phase 5: Dependencies (`phase-5-dependencies.md`)

Failed issues (success=false) should be reported to the user for manual creation after Phase 7 completes.
