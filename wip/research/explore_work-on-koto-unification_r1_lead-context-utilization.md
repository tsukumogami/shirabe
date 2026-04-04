# Lead: Context utilization for multi-issue execution

## Findings

### Koto's Context System Architecture

Koto implements a binary content store (`ContextStore` trait in `src/session/context.rs`) with hierarchical string keys stored on disk in `~/.koto/sessions/{repo-id}/{name}/ctx/`. The design (DESIGN-local-session-storage.md) provides:

1. **Storage model**: Files on disk per context key with a `ctx/manifest.json` tracking metadata (creation timestamp, size, SHA-256 hash)
2. **Access pattern**: CLI commands (`koto context add/get/exists/list <session> <key>`) manage all content
3. **Key format**: Hierarchical path strings like `scope.md`, `research/r1/lead-cli-ux.md`, supporting prefix filtering via `--prefix`
4. **Per-session scoping**: Each workflow gets one session directory; context keys are scoped to that session

Critical: Koto context is opaque (no schema validation), unversioned (unlike state file headers which store template_hash), and unindexed (no cross-key queries). The manifest is a write-ordered convenience index, not a queryable database.

### Size Constraints and Performance

- Manifest atomicity: Content written first, manifest updated second via atomic rename. Per-key advisory flock prevents concurrent writes to the same key.
- No explicit size limits documented in CLI or design docs. Content must fit in available disk (manifests use JSON with all keys in one file, no per-key sharding).
- Gates evaluate context existence in O(1) via manifest lookup; content-matches gates apply regex to retrieved content.

### Namespacing Strategy: Hierarchical Keys with Prefix Filtering

Koto's design explicitly supports namespacing through `/`-separated hierarchical keys:

```
research/r1/lead-cli-ux.md
research/r1/lead-concurrency.md
research/r2/lead-optimization.md
issue-47/summary.json
issue-48/summary.json
```

The `koto context list <session> --prefix "research/"` command filters keys by prefix, enabling organized storage. Each issue could use a prefix like `issue-<N>/` for its artifacts. This maps naturally to the mapping in DESIGN-local-session-storage.md Decision 12.

### Current Work-On Context Usage

The work-on template uses koto context keys for phase outputs:
- `context.md` (context_injection phase gate)
- `baseline.md` (setup phase gate)
- `introspection.md` (introspection phase gate)
- `plan.md` (analysis phase gate)
- `summary.md` (finalization phase gate)

These are stored per-workflow (per-issue with `--var ARTIFACT_PREFIX=issue_<N>`). The template has no native mechanism to read context from prior issues; each issue's workflow is independent.

### Multi-Issue Context: The Challenge

Koto's architecture (from controller-loop research) requires per-issue state files: `koto-issue-#42.state.jsonl`, `koto-issue-#43.state.jsonl`, etc. A skill-level orchestrator manages the queue and calls `koto next --state koto-issue-#42.state.jsonl` for each issue.

The multi-issue state research (explore_work-on-koto-unification_r1_lead-multi-issue-state.md) identified the gap: workflow-tool's state file is a normalized JSON with per-issue status, commits, reviewer results, and dependency graphs. Koto has no native multi-record awareness. Evidence is per-state (not per-issue), context is opaque (not indexed), and there's no built-in dependency resolver.

### Cross-Issue Context Transfer Patterns

Three options from multi-issue-state research, analyzed for context window impact:

**Option A: Single JSON Context Key (Unified State File)**
- Store entire `workflow-state.json` (issue array + dependency graph) under one context key in a central session
- On each issue transition, fetch, mutate, and re-store
- Con: No schema validation in koto; agents parse and mutate JSON manually
- Con: Requires coordinating a single manifest-tracked state file across all orchestrator operations
- Context window: One large JSON per state transition; payload size grows with N issues

**Option B: Per-Issue Context Keys**
- Store `issue-<N>/status.json`, `issue-<N>/summary.md`, etc. under hierarchical keys in a central session
- Orchestrator fetches needed keys and agents read via `koto context list --prefix "issue-47/"`
- Pro: Granular updates; no need to read/mutate all issues to update one
- Con: N issues = N context list calls; no cross-key indexing for dependency resolution
- Con: Atomicity lost (updating issue #47 and removing it from blocked-by list requires two writes)
- Context window: N context reads per workflow step; O(N) payload

**Option C: Hybrid — Structured JSON Tracking + Markdown Content**
- Central `workflow-state.json` for metadata and dependency graph
- Separate markdown keys under `issue-<N>/design.md`, `issue-<N>/plan.md`, etc. for agent-facing content
- Pro: Issue state queryable externally (JSON parsing); content rendered nicely (markdown)
- Con: Two sources of truth to keep in sync (koto events + JSON state)
- Con: Koto gates can't check issue structure ("is issue #47 completed?")
- Context window: Core state JSON per transition + selected issue content on demand

**Option D: External State File + Koto Integration (Not Currently Feasible)**
- Maintain workflow-tool's state file outside koto, managed by helper script
- Koto templates call `integration` (feature #49, deferred) to query and mutate state
- Pro: No translation; workflow-tool logic unchanged; issue queries work
- Con: Requires implementing koto's integration runner (not shipped)
- Con: Two logs to audit (koto state + external state file)

### Context Window Optimization Strategies

From analysis of the four options:

1. **Sliding window (summarization)**
   - Keep full context only for current and previous N issues (e.g., N=2)
   - Summarize older issues: "Issues #40-45: 5 completed, 2 blocked by design doc"
   - Store summary as `history/summarized-up-to-issue-<N>.md`
   - Pro: Bounded context growth even with 100+ issues
   - Con: Agent must re-read old issues if a dependency changes late in the plan
   - Con: Requires explicit summarization logic (not automatic in koto)

2. **Lazy context loading**
   - Store only the current issue's full context + a manifest of what's available
   - Orchestrator passes issue number; agent calls `koto context get issue-<N>/plan.md` on demand
   - Pro: Minimal per-state context; scales to unlimited issues
   - Con: Agents must know when to fetch (extra CLI calls)
   - Con: No automatic dependency checking (agent asks orchestrator, not koto)

3. **Script-generated context snapshot**
   - Before each issue transition, a helper script computes and stores `current-context.md`
   - Snapshot includes: current issue number, title, previous N summaries, files_changed across all prior issues, key_decisions from design/analysis phases
   - Agent reads `current-context.md` in the directive
   - Pro: Deterministic context per state; agent doesn't parse JSON
   - Con: Requires helper script; adds an extra computation step per transition
   - Con: Stale once computed (if dependency information changes between transitions)

4. **Per-issue context namespacing with prefix-scoped gates**
   - Use `issue-<N>/` prefix for each issue's context under a central session
   - Koto gates: `context-exists` and `context-matches` with keys like `issue-47/plan.md`
   - Orchestrator fetches only needed keys: `koto context list central --prefix "issue-47/"`
   - Pro: Clean separation; gate evaluation stays in koto
   - Con: Still O(N) context fetches if many issues' context is needed
   - Con: No built-in dependency validation in koto

### Resume Behavior and State Recovery

- **Per-issue state files**: Each issue has its own JSONL log at `koto-issue-#42.state.jsonl`. On resume, orchestrator calls `koto workflows` to find active workflows, then `koto next --state koto-issue-#42.state.jsonl` to continue.
- **Central context**: All context lives in one session's `ctx/` directory. On resume, context is immediately available to any issue; no per-issue recovery needed.
- **Hybrid (Option C)**: Central context reads are safe; local state file per issue means recovery is per-issue. Dependency graph in central JSON must match koto event log (manual consistency).

### Scalability to 10+ Issues

- **Option A (single JSON)**: Read-modify-write of growing JSON per state transition. With 50 issues, manifest size stays small, but JSON payload = O(N). At 10 issues, ~1-5 KB per issue (title, status, commits) = 10-50 KB per transition. Acceptable.
- **Option B (per-issue keys)**: 50+ context list calls to check all issues' statuses. Manifest grows to 50+ entries (still fast, JSON lookup O(1) per key). Per-issue write remains O(1). Acceptable up to 100s of issues.
- **Option C (hybrid)**: Central JSON < 50 KB, issue markdown varies. Two-source consistency risk. Scales to 100+ issues but requires tooling to keep in sync.
- **Option D (external)**: Native workflow-tool scaling (proven at 100+ issues). Deferred implementation.

Koto context store itself (filesystem manifest + file storage) has no documented limit; filesystem performance dominates. At 1000 keys, manifest JSON ~100 KB. Acceptable.

## Implications

### For Multi-Issue Context Design

1. **Koto's namespacing is sufficient**: Hierarchical keys with prefix filtering directly support per-issue context. No need for per-issue session directories (unless agent isolation is desired, which it isn't for a single orchestrated workflow).

2. **Central session, per-issue context keys** (Option B modified) is simplest:
   - Initialize one koto session for the entire multi-issue plan: `koto init plan-123 --template orchestrator.md`
   - Each issue's context lives under `issue-<N>/summary.md`, `issue-<N>/plan.md`, etc.
   - Orchestrator fetches relevant context for the current issue via `koto context list plan-123 --prefix "issue-47/"`
   - On resume, all context is intact; no per-issue state file recovery needed
   - Issue window remains bounded by fetching only needed keys

3. **PREVIOUS_SUMMARY pattern** from /implement should map to:
   - Store `issue-<N>/summary.json` with fields: `files_changed`, `key_decisions`, `approach`
   - Before transitioning to issue N+1, agent calls `koto context list plan-123 --prefix "issue-N/"` to fetch summary
   - Template variable or directive text can reference this summary without parsing — agent extracts relevant parts

4. **Avoid manifests in manifests**: Don't store a manifest-of-issues as a context key. It duplicates koto's built-in `context list` and risks desync. Let koto's manifest be the source of truth.

### For Context Window Protection

1. **Script-generated snapshot is the best fit for koto**:
   - Before a critical state (e.g., "analysis" or "implementation"), a helper script generates `current-context.md`
   - Contents: current issue title/number, previous 2 issue summaries (if they exist), files changed across all prior issues (1-line summary), list of key_decisions from prior design phases
   - Agent reads this one file in the directive, no multi-fetch needed
   - Snapshot is discarded after state transition; next state generates a fresh snapshot
   - Keeps context window bounded even with 50+ issues

2. **Sliding window for decisions**:
   - Store decisions as `issue-<N>/decisions.json` (already part of work-on evidence schema)
   - Summarizer script: "Issues #1-40 made 150 decisions. Key patterns: 7 cache invalidation decisions, 5 schema changes. Full list in `decisions/summarized-1-40.md`"
   - Agent reads summary instead of 150 individual decisions
   - Trades precision for context window; suitable for reference, not initial analysis

## Surprises

1. **Koto context list is already hierarchical**: The prefix filtering feature (--prefix "issue-47/") means Option B is cheaper than expected. No need for a parallel manifest or helper script to query issue status. Koto's built-in list command does it.

2. **No need for per-issue sessions**: The multi-issue-state research hinted at per-issue session directories, but with shared context prefixes, a single session + per-issue state files (for the deterministic loop) is simpler and more efficient. Context store is shared; state machines are independent.

3. **Manifest atomicity is write-ordered, not transactional**: Multiple agents can submit context concurrently to different keys. If two agents write to the same key, the last write wins (per-key advisory flock prevents corruption, but not conflicts). This is acceptable for multi-issue because each issue owns its `issue-<N>/` prefix; no concurrent writes to the same prefix.

4. **Evidence isn't the right place for cross-issue context**: The multi-issue research suggested storing issue state in evidence, but evidence is per-state and loosely typed. Context keys are the right fit: opaque, persistent, indexed by prefix, and independently queryable.

## Open Questions

1. **Should the snapshot be versioned?** If issue #47's analysis reveals a problem with issue #46's summary, should we regenerate the snapshot, or keep it fixed until the next state transition? Current proposal: fixed until next state (snapshot is consumed in the directive and discarded).

2. **How much history to keep?** Summarize issues > N old, or summarize all completed issues? If 100 issues are complete and 1 is in progress, do we load 100 summaries or 1? Current proposal: load all completed issue summaries for the current issue's analysis, summarize issues > 5 completed ago.

3. **Can gates check across-issues?** With per-issue keys, can a gate check "is issue #47 complete?" A gate expression like `context-matches issue-47/status "completed"` would work, but the gate name hardcodes #47. Should we support variables in gate keys, or is that out of scope? Current: out of scope (gates are compiled once; variables are per-invocation).

4. **Who manages per-issue key naming conventions?** The orchestrator creates new issues; should it also decide key names (e.g., `issue-<N>/summary.md` vs. `run-<N>/summary.md`)? Should this be configurable in the orchestrator template? Current proposal: standardize on `issue-<N>/` for GitHub issues, `task-<slug>/` for free-form tasks.

## Summary

Koto's context system natively supports hierarchical key namespacing with prefix filtering, enabling per-issue context storage under a central session without per-issue session overhead. A script-generated context snapshot (current issue + recent prior summaries + change summary) can keep context window bounded to ~5 KB per state transition even with 50+ issues, by trading complete history for a curated summary. Per-issue evidence submission (via existing `--with-data` mechanism) preserves the orchestrator's decision trees and deterministic state progression, while koto's context store (not evidence) becomes the system of record for cross-issue state tracking. This design aligns with koto's architecture (context is opaque and prefix-scoped, gates evaluate existence/content, per-issue state files advance independently) and allows the orchestrator to remain optional — simpler plans with 1-2 issues can omit central context entirely.
