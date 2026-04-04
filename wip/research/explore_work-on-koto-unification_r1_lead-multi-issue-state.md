# Lead: Multi-issue state in koto

## Findings

### How Koto's Context System Works

Koto uses a **binary content store** with hierarchical string keys, not a JSON state file like workflow-tool. The context system is defined in `/koto/src/session/context.rs`:

- **ContextStore trait**: Agents store/retrieve opaque binary content under string keys (e.g., `scope.md`, `research/r1/lead-cli-ux.md`)
- **LocalBackend**: Stores context files on disk; **CloudBackend** syncs to S3 with manifest caching
- **Manifest metadata**: `ctx/manifest.json` tracks each key's creation timestamp, size, and SHA-256 hash
- **Access pattern**: `add(session, key, content)` / `get(session, key)` / `list_keys(session, prefix)` — no schema validation, no type checking

Critical insight: Koto's context is **opaque**, **per-session**, and **stored on disk** (or S3). It's not designed for querying structured data or multi-field transitions.

### How Koto's State Machine Works

Koto's engine (in `/koto/src/engine/`) is **event-sourced**, persisting a JSONL log of typed events:

- **StateFileHeader**: Records workflow name, template hash, created_at
- **Events**: Typed payloads (WorkflowInitialized, Transitioned, EvidenceSubmitted, GateEvaluated, etc.)
- **Evidence**: Stored as `EvidenceSubmitted { state, fields: HashMap<String, serde_json::Value> }` per event
- **Persistence**: Events append to JSONL; state is derived by replaying the log
- **Validation**: `/koto/src/engine/evidence.rs` validates evidence against `FieldSchema` (string/number/boolean/enum types)

Critical insight: Koto's state comes from **appended events**, not mutable state. Evidence is **loosely typed** (serde_json::Value) until validation time.

### What Workflow-Tool Stores

From `/workflow-tool/internal/state/state.go`, the workflow-tool state file is a **single JSON blob** with:

```
StateFile {
  pr_status: "implementing|completing|qa_validated|docs_validated"
  design_doc: string
  branch: string
  pr_number: null|number
  integrity_hash: "sha256:..."
  issues: [
    {
      number: int
      title: string
      status: "pending|in_progress|implemented|scrutinized|pushed|ci_fixing|ci_blocked|completed"
      issue_type: "code|task"
      dependencies: [int, ...]
      commits: [string, ...]
      agent_type: "coder|webdev|techwriter"
      summary: { files_changed, tests_added, key_decisions }
      reviewer_results: JSON
      qa_results: JSON
      qa_skipped: bool
      testable_scenarios: [string, ...]
    }
  ]
  skipped_issues: [
    { number, reason, label, blocked_by: [int, ...] }
  ]
}
```

Critical insight: Workflow-tool tracks **per-issue progress** (10+ fields), **PR-level progress** (pr_status), and **dependency graphs**. This is a **normalized, queryable structure**, not opaque blobs.

### The Mismatch

**Workflow-tool is issue-centric**:
- Query: "What's the status of issue #47?" → O(1) lookup + field access
- Query: "Show me all issues blocked by issue #10" → Scan dependencies
- State mutation: Set issue #47 status to "implemented", add commits → Atomic write to StateFile

**Koto is session-centric**:
- Context: Store arbitrary markdown/JSON blobs under keys; no schema
- Advancement: Events append to JSONL; state derived by replaying
- Query: "What context was stored under key X?" → Get from LocalBackend; no cross-key relationships

Koto has **no native support for multi-record relationships**. Its evidence model is flat (per-state JSON object) with no way to express "issue #47 has these properties and is blocked by issue #10."

### Evidence vs. Context vs. State

In koto:
- **Evidence**: Structured data submitted at a state (HashMap<String, Value>), validated per state schema, routed via `when` conditions
- **Context**: Opaque blobs stored under hierarchical keys, no validation, primarily for agent-facing content (designs, research notes)
- **State**: Derived from event log replay; current state name is the only queryable field

None of these directly support multi-issue tracking. Evidence could *theoretically* store an issue number as a field, but there's no way to:
1. Query all issues (koto has no cross-key index)
2. Express dependency constraints (evidence is per-state, not per-issue)
3. Resume from an arbitrary issue (koto resumes from the current state, not from issue N)

## Implications

### Option A: Single JSON Context Key (workflow-tool → koto directly)

Store the entire `StateFile` JSON under a context key (e.g., `workflow-state.json`). On each transition, fetch, mutate, and re-store.

**Pros:**
- Familiar schema for team; minimal translation
- Queryable off-line (koto doesn't query it; external tools can)
- Atomic per-update (one file write)

**Cons:**
- Koto has no built-in understanding of issue structure; agents would need to parse and mutate JSON manually
- No compile-time contract (koto template can't declare "I need issue #N status")
- Resume from arbitrary issue becomes a manual koto rewind (awkward CLI)
- No validation (koto doesn't know a `status` field should be one of 10 values)

### Option B: Per-Issue Context Keys

Store each issue under `workflow/issue-<N>-status.md`, `workflow/issue-<N>-summary.json`, etc. Use context keys to simulate per-issue state.

**Pros:**
- Granular: update issue #47 status without touching issue #50
- Koto context system naturally supports hierarchical keys (can use `list_keys("workflow/issue-47")`)
- Clearer separation: each issue is its own artifact

**Cons:**
- N issue queries = N context GET calls (no cross-key indexing)
- Dependency graphs still can't be expressed in koto (no referential integrity)
- Atomicity gone: updating an issue and removing it from a blocked-by list requires two separate writes
- Koto's "current state" doesn't know which issue we're on

### Option C: Hybrid — Structured JSON for tracking, markdown for content

Store `workflow-state.json` (issue metadata + dependency graph) as a context key. Store agent-facing content (designs, decisions, test results) as separate markdown keys.

**Pros:**
- Issue state is queryable via external tools (JSON parsing)
- Content is rendered nicely in GitHub (markdown)
- Dependency graph stays intact
- Agents don't edit the state file directly

**Cons:**
- Koto still doesn't understand the issue structure (gates can't check "issue #47 is completed")
- Two sources of truth (koto events + JSON state file) to keep in sync
- Context list doesn't show issue structure (flat key list, no relationships)

### Option D: External State File + Koto Orchestration

Maintain workflow-tool's state file **outside koto**, managed by a helper script. Koto template orchestrates with:
- `integration` tag pointing to helper script
- Evidence provides issue number and new status
- Script mutates the state file and returns next directive

**Pros:**
- No translation needed; workflow-tool logic unchanged
- Issue queries work (external script has direct file access)
- Dependency graph enforced (external script validates)
- Koto stays single-purpose (template + evidence gating)

**Cons:**
- Not unified: koto state log + external state file = two logs to audit
- Resume complexity: koto rewinds in template space, external script needs to know issue state
- Integration feature (#49) not implemented; deferred to future design
- Adds CLI tool requirement (external helper must be available)

## Surprises

1. **Koto has no multi-record awareness**: The entire engine assumes a single state machine per workflow. Multi-issue workflows would require either (a) per-issue koto sessions, or (b) a parent wrapper orchestrating between issues.

2. **Evidence isn't queryable**: Even though evidence accepts structured JSON, koto never queries across evidence values. You can't ask "show me all states where evidence.issue_status == 'pending'." That would require indexing.

3. **Context is not versioned**: Unlike the state file header (which stores template_hash), context keys have no versioning. An old markdown file under a context key won't be validated against a new schema.

4. **Koto templates don't declare data contracts**: A template's `accepts` block declares what evidence a state *accepts*, but templates can't declare "I need to know the current issue number" or "I maintain a dependency graph." The relationship is one-way: template → evidence, not evidence → template.

## Open Questions

1. **How should issue selection work?** If we're in state "assess," does koto know which issue we're assessing? Option D (external orchestrator) handles this by passing issue# in evidence. Options A-C would need agents to interpret context key names or evidence fields.

2. **Who validates the state file?** In workflow-tool, `state validate` checks integrity_hash and status enum values. In koto, template gates check command outcomes, not JSON schema. Should we add a custom gate type for state file validation, or keep it external?

3. **Can we resume from an arbitrary issue?** Workflow-tool's `rewind <issue-number>` skips issues and sets one as current. Koto's rewind changes state in the template, not issue selection. These are orthogonal concerns. Option D (external) has a natural home for this (helper script's state file). Options A-C would need koto template redesign or a custom action.

4. **Should evidence include issue metadata, or just the issue number?** If we pass `{ issue_number: 47, status: "implemented" }` in evidence, agents could update the state file. But that couples agents to the state schema. Option D pushes this responsibility to the helper script. Options A-C leave it to agents.

## Summary

Koto's context and evidence systems are **fundamentally different** from workflow-tool's unified state file: context is opaque and unindexed, evidence is per-state and loosely typed, and the engine has no native support for multi-record relationships or dependency graphs. The cleanest mapping is **Option D** (external state file + koto integration), which requires implementing the integration runner (currently deferred to issue #49) but preserves workflow-tool's logic and queries. Options A-C attempt to shoehorn multi-issue state into koto's session-centric model and would require significant agent implementation burden (JSON parsing, state file mutation, dependency validation) that koto doesn't provide primitives for.

