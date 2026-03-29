# Koto Capabilities Catalog

Research output for koto gap analysis. Based on koto source code (Rust),
CLI usage guide, design docs, the work-on template, and open GitHub issues.

---

## 1. Templates

**Format**: Markdown files with YAML front-matter. The front-matter declares
metadata (name, version, description), an `initial_state`, variable
declarations, and a `states` block with structured state definitions. The
markdown body provides `## <state-name>` headings whose content becomes the
directive text shown to the agent.

**Compilation**: `koto template compile` parses the markdown/YAML source into
a FormatVersion=1 JSON file, cached by SHA-256 hash in `~/.cache/koto/`. The
compiled JSON is what the engine loads at runtime.

**Validation**: The compiler enforces:
- All transition targets reference declared states
- Every declared state has a corresponding directive in the markdown body
- Gate types are one of `command`, `context-exists`, `context-matches`
- `initial_state` must be a declared state
- Evidence routing validation (when conditions reference declared accepts fields)

**Variables**: Declared in front-matter with `description`, `required`, and
`default` fields. Referenced in directives and gate commands as `{{VAR_NAME}}`.
`SESSION_DIR` is injected at runtime and resolves to the session directory path.
Variables are substituted at `koto init` time or via `--var` flags.

**Visualization**: `koto template export` generates Mermaid stateDiagram-v2
or self-contained interactive HTML (Cytoscape.js) from templates. Supports
`--check` for CI freshness validation.

## 2. Phases/Steps (States and Transitions)

**State machine model**: Workflows are DAGs of named states. Each state has:
- A directive (text instructions for the agent)
- Optional gates (pre-conditions)
- Optional accepts block (evidence schema)
- Optional transitions with `when` conditions for conditional routing
- Optional integration declaration
- Optional default_action (auto-executed command)
- Optional terminal flag

**Sequential flow**: States connect via transitions. An unconditional transition
(no `when` block) auto-advances when all gates pass. Conditional transitions
route based on submitted evidence field values.

**Branching**: Yes, via conditional transitions with `when` blocks. The work-on
template demonstrates this extensively -- the `entry` state branches to
`context_injection` or `task_validation` based on `mode: issue_backed` vs
`mode: free_form`. Multiple `when` conditions on different transitions create
multi-way branches.

**Self-loops**: A state can transition to itself (e.g., `analysis -> analysis`
with `scope_changed_retry`). The engine detects cycles but self-loops via
conditional `when` blocks are permitted.

**No parallel branches**: The state machine is strictly sequential -- one current
state at a time. There is no fork/join or parallel execution primitive.

**Chain limit**: The auto-advancement engine caps at 100 transitions per
`koto next` invocation to prevent runaway template bugs.

## 3. Gates

Three gate types exist, all evaluated without short-circuiting (agent sees
every blocking condition at once):

### command gate
- Spawns a shell command in the working directory
- Configurable timeout (default 30 seconds)
- Results: Passed (exit 0), Failed (non-zero exit code), TimedOut, Error
- Example: `test "$(git rev-parse --abbrev-ref HEAD)" != "main"`

### context-exists gate
- Checks whether a key exists in the session's context store
- No shell execution -- pure content-store lookup
- Example: `key: baseline.md`

### context-matches gate
- Retrieves content from the context store and matches against a regex pattern
- Example: `key: review.md`, `pattern: "## Approved"`

**No evidence-value gates**: Field-based gates (`field_not_empty`,
`field_equals`) were removed. Evidence routing is handled entirely through
`accepts`/`when` conditions on transitions.

**Gate evaluation order**: Gates are evaluated before transitions. If any gate
fails, the response variant is `GateBlocked` and no transition occurs.

## 4. Evidence

**Schema-driven**: Each state optionally declares an `accepts` block defining
typed fields. Supported types: `string`, `number`, `boolean`, `enum` (with
allowed values list). Fields can be `required: true/false`.

**Submission**: Via `koto next <name> --with-data '<json>'`. The payload is
validated against the accepts schema. Validation is non-short-circuiting --
all errors returned at once. Unknown fields are rejected. Payload capped at 1MB.

**Evidence routing**: Submitted evidence is matched against `when` conditions
on transitions. The first matching transition determines the next state.
`NeedsEvidence` is returned when conditional transitions exist but no submitted
evidence matches any condition.

**Persistence**: Evidence is appended as an `evidence_submitted` event in the
JSONL state file with the state name and field values. Evidence for the current
state is derived by looking at events after the most recent state-changing event.

**Directed transitions**: `koto next --to <target>` bypasses evidence matching
and forces a transition to a specific valid target state.

## 5. State Management

**Event log format**: JSONL files at
`~/.koto/sessions/<repo-id>/<name>/koto-<name>.state.jsonl`.

**Header**: First line contains `schema_version`, `workflow` name,
`template_hash` (SHA-256 of compiled template), and `created_at` timestamp.

**Events**: Subsequent lines are typed events with monotonic `seq` numbers and
timestamps. Event types:
- `workflow_initialized` -- records template path and initial variables
- `transitioned` -- state change with from/to/condition_type
- `evidence_submitted` -- evidence payload with state and field values
- `directed_transition` -- forced transition with from/to
- `rewound` -- rollback from/to
- `workflow_cancelled` -- cancellation with state and reason
- `default_action_executed` -- auto-action results (command, exit code, stdout, stderr)
- `decision_recorded` -- advisory decision capture with state and decision payload
- `integration_invoked` -- integration output with state and integration name

**State derivation**: Current state is the `to` field of the last
`transitioned`, `directed_transition`, or `rewound` event (log replay).

**Template integrity**: The template hash is locked at init time. If the
compiled template changes, `koto next` fails. Must reinitialize to use a new
template.

**Atomic writes**: Each event appended with `sync_data()` after write. File
created with mode 0600 on Unix. Truncated final line is recoverable (warning +
events up to last valid). Sequence gaps in non-final lines are treated as
corruption.

**Session management**: `koto session dir`, `koto session list`,
`koto session cleanup`. Auto-cleanup on terminal state (unless `--no-cleanup`).

## 6. Decision Capture

**Implemented** (issue #66, DESIGN-mid-state-decision-capture).

**Mechanism**: `koto decisions record` appends a `DecisionRecorded` event to the
state file without triggering the advancement loop. `koto decisions list`
retrieves decisions for the current state epoch.

**Decision payload**: Free-form JSON value. The parent design recommends
`choice`, `rationale`, `alternatives_considered` fields, but the engine doesn't
enforce structure.

**Epoch-scoped**: Decisions are scoped to the current state epoch. A rewind
clears the epoch boundary, so prior decisions are no longer returned by
`derive_decisions`.

**Advisory**: No template enforcement -- templates don't require a minimum
number of decisions. The work-on template includes `decisions` as an optional
string field in the `analysis` and `implementation` accepts blocks.

## 7. External Process Integration

### Command gates
Shell commands executed with configurable timeouts. The work-on template uses
this for CI checks, staleness checks, and branch validation.

### Default actions
States can declare a `default_action` with a shell command that auto-executes
on state entry. Supports `working_dir`, `requires_confirmation` (pauses for
user approval), and `polling` (interval + timeout for repeated execution).

### Integration declarations
States can declare an `integration` field (string name). The engine checks
if a runner is available and returns either `Integration` (with output) or
`IntegrationUnavailable`. This is the extensibility mechanism for tool-specific
runners.

### Context store
`koto context add/get/exists/list` -- agents submit artifacts through the
context store rather than writing files directly. Supports stdin/file input,
file output, prefix filtering. Content is opaque bytes keyed by hierarchical
path strings.

## 8. Parallel Execution

**Not supported.** The state machine is strictly sequential -- one active state
per workflow. No fork/join, no parallel branches, no concurrent state tracking.

The work-on template works around this by being a single linear path with
conditional branches. Cross-agent delegation (issue #41) is an open design
question.

**Open issue**: Issue #41 "Design: cross-agent delegation (tags + config)" is
the only open issue touching parallelism.

## 9. Resume/Rewind

### Resume
Workflows resume naturally because state is derived from the JSONL event log.
An agent calls `koto next <name>` and gets the current directive based on
replayed state. No special resume command needed -- the event log is the source
of truth.

**Context-exists gates enable skip-on-resume**: If a state's gate checks for
a context artifact that was already submitted, the gate passes on resume and
the engine auto-advances past completed work.

**Truncation recovery**: If the last event line is malformed (e.g., process
killed mid-write), koto recovers by discarding the truncated line and using
events up to the last valid entry.

### Rewind
`koto rewind <name>` appends a `rewound` event (non-destructive -- full audit
trail preserved). Rolls back to the previous state. Multiple rewind calls can
walk back further. Cannot rewind past the initial state.

Evidence submitted in a rewound epoch is not visible after rewind (epoch
boundary). Decisions are similarly epoch-scoped.

## 10. Outputs/Reporting

### CLI JSON output
All commands return structured JSON. `koto next` returns detailed response
objects with `action`, `state`, `directive`, `advanced`, `expects`,
`blocking_conditions`, `integration`, and `error` fields.

### Workflow listing
`koto workflows` lists all active workflows with name, creation timestamp,
and template hash.

### Session listing
`koto session list` returns session metadata as JSON array.

### Context listing
`koto context list` shows all content keys for a session, with optional
prefix filtering.

### Visual export
`koto template export` generates Mermaid diagrams or interactive HTML
visualizations of workflow structure. The `--check` flag enables CI freshness
validation.

### Event log
The raw JSONL state file provides a complete audit trail. No built-in
summarization or reporting command exists beyond what `koto next` returns
for the current state.

### Decision listing
`koto decisions list` returns decisions for the current state epoch.

---

## Open GitHub Issues (8 open)

| # | Title | Relevance |
|---|-------|-----------|
| 102 | UX: "advanced" field name misleads callers about phase state | Cosmetic rename |
| 90 | feat: inline phase details on first visit, omit on subsequent visits | UX improvement for directive display |
| 87 | feat(engine): promote evidence to workflow-scoped variables | Would allow evidence values to propagate across states as variables |
| 73 | feat(shirabe): integrate /work-on skill with koto template | Shirabe integration work |
| 72 | feat(template): write the work-on koto template | Template creation |
| 66 | feat(engine): implement mid-state decision capture | Already implemented |
| 65 | feat(engine): implement template variable substitution (`--var`) | Runtime variable setting |
| 41 | Design: cross-agent delegation (tags + config) | Parallelism/delegation design |

### Key planned features
- **Evidence-to-variable promotion (#87)**: Would let evidence submitted in one
  state become variables accessible in later states. Currently evidence is
  state-scoped only.
- **Cross-agent delegation (#41)**: Design-phase only. Would enable workflows
  to delegate sub-tasks to other agents. No implementation exists.

---

## Capability Summary Matrix

| Capability | Status | Notes |
|------------|--------|-------|
| Template definition (markdown+YAML) | Implemented | Compilation, validation, caching |
| Sequential state machine | Implemented | Auto-advancement engine with chain limit |
| Conditional branching | Implemented | Via `when` conditions on transitions |
| Self-loops | Implemented | With cycle detection safety |
| Command gates | Implemented | Shell execution with timeout |
| Content-aware gates | Implemented | context-exists, context-matches (regex) |
| Typed evidence schema | Implemented | string, number, boolean, enum |
| Evidence routing | Implemented | when-condition matching on transitions |
| JSONL event log | Implemented | Atomic writes, corruption recovery |
| Template integrity | Implemented | SHA-256 hash lock at init |
| Decision capture | Implemented | Advisory, mid-state, epoch-scoped |
| Context store | Implemented | Opaque content by key, CLI add/get/list |
| Default actions | Implemented | Auto-execute commands on state entry |
| Polling actions | Implemented | Interval + timeout for repeated execution |
| Integration declarations | Implemented | Extensibility point for tool runners |
| Rewind | Implemented | Non-destructive, epoch-scoped |
| Resume | Implemented | Event log replay, no special command |
| Visual export | Implemented | Mermaid + interactive HTML |
| Session management | Implemented | Auto-cleanup, manual cleanup, listing |
| Parallel execution | Not supported | Single active state per workflow |
| Cross-agent delegation | Design only | Open issue #41 |
| Evidence-to-variable promotion | Not implemented | Open issue #87 |
| Workflow-level reporting/summary | Not implemented | Only current-state view via `koto next` |
| Conditional gate evaluation | Not supported | All gates always evaluated |
| Time-based triggers/scheduling | Not supported | No cron or timer primitives |
