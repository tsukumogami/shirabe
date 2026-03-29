# Koto Adoption Audit: Non-Koto Shirabe Skills

Audited 7 skills against 8 aspects. Only `/work-on` currently uses koto (via
`koto-templates/work-on.md`). All others enforce structure through prose
instructions, file-existence resume logic, and sequential phase-file loading.

---

## 1. explore

| Aspect | Current Implementation | Koto Equivalent | Gap? |
|--------|----------------------|-----------------|------|
| **State files** | `wip/explore_<topic>_scope.md`, `_findings.md`, `_decisions.md`, `_crystallize.md`, `wip/research/explore_<topic>_r<N>_lead-<name>.md`. All markdown. | Context keys per state (scope, findings, decisions, crystallize). Research files as context artifacts with round+lead composite keys. | Yes -- no schema enforcement on artifact content |
| **Resume logic** | Top-to-bottom file-existence cascade: crystallize exists -> Phase 5, findings has "## Decision: Crystallize" marker -> Phase 4, findings exists -> Phase 3, research files exist -> Phase 3, scope exists -> Phase 2, on topic branch -> Phase 1, else Phase 0. | `gates` with `context-exists` checks on each state. The "Decision: Crystallize" marker would become an enum value in a context key rather than a grep target. | Yes -- string-marker detection ("## Decision: Crystallize") has no koto primitive; needs a context key with enum values |
| **Phase ordering** | Prose: "Execute phases sequentially." Each phase loads a reference file. Loop between Phase 2-3 managed by orchestrator prose. | `states` with `transitions` enforcing order. The discover-converge loop maps to a cycle between discover and converge states with a `when` guard. | Yes -- loop with user-driven exit has no direct koto pattern yet (work-on uses `when` blocks for self-loops) |
| **Gates/checks** | Phase 0: branch check, triage label detection. No CI checks. Visibility detection from CLAUDE.md. | `gates` on entry state (branch-exists, visibility-resolved). Triage label check as a gate on the issue-input path. | Minor -- gates are straightforward to express |
| **Decision capture** | `wip/explore_<topic>_decisions.md` appended per round. Markdown with `## Round N` sections. | Context key `decisions` with structured YAML entries per round. | Yes -- append-per-round pattern needs koto context append semantics or round-scoped keys |
| **Parallel agents** | Phase 2 fans out lead agents (one per lead). Results collected into `wip/research/` files. Phase 3 reads all research files. | `fan_out` on discover state, one agent per lead. Results stored as context artifacts. Converge state reads all. | Yes -- fan_out with dynamic count (number of leads varies per round) |
| **User interaction** | Phase 1 is conversational scoping. Phase 3 presents AskUserQuestion for "explore further" vs "ready to decide". Phase 4 crystallize confirmation. `--auto` mode bypasses all. | `accepts` blocks on converge and crystallize states. Auto mode via variable flag that selects auto-transitions. | Yes -- conversational phases (Phase 1 dialogue) don't map to koto's request/response model |
| **External calls** | `gh issue view` for issue input. `git` for branch operations. No scripts. | Same -- koto doesn't replace external calls, just structures when they run. | No gap |

---

## 2. design

| Aspect | Current Implementation | Koto Equivalent | Gap? |
|--------|----------------------|-----------------|------|
| **State files** | `wip/design_<topic>_summary.md`, `_coordination.json`, `_decision_<N>_report.md`, `_decisions.md`, `wip/research/design_<topic>_phase5_security.md`. Design doc at `docs/designs/DESIGN-<topic>.md`. JSON coordination file tracks decision status. | Context keys for summary, coordination (structured), per-decision reports. Design doc as final output artifact. | Yes -- coordination.json has structured status tracking (pending/complete per decision) that needs koto state per sub-task |
| **Resume logic** | File-existence cascade: design doc status "Accepted" -> offer revise, "Proposed" -> continue, security research exists -> Phase 6, Solution Architecture section exists -> Phase 5, Considered Options exists -> Phase 4, coordination.json all complete -> Phase 3, coordination.json some pending -> Phase 2, summary exists -> Phase 1, else Phase 0. | States with `gates` checking context keys and design doc section presence. | Yes -- checking "section exists in document" is content inspection, not file existence; needs a custom gate type or context key set when section is written |
| **Phase ordering** | 7 phases (0-6), strictly sequential. Each phase loads a reference file. | Linear state chain: setup -> decompose -> execute -> cross_validate -> investigate -> security -> finalize. | No gap -- linear chains are koto's simplest case |
| **Gates/checks** | Phase 0: PRD status must be "Accepted" (PRD mode). Phase 3: cross-validation mandatory. Phase 5: security review mandatory. Phase 6: strawman check on rejected alternatives. | Gates on execute state (PRD accepted), mandatory states for cross_validate and security (no skip transitions). Strawman check as a gate on finalize. | Minor -- mandatory phases just mean no skip transitions exist |
| **Decision capture** | `wip/design_<topic>_decisions.md` for auto-mode decisions. Per-decision reports from the decision sub-skill in `wip/design_<topic>_decision_<N>_report.md`. | Decision context keys. Sub-operation results as context artifacts. | Yes -- sub-operation invocation (calling /decision as a child) needs koto's sub-workflow or nested template support |
| **Parallel agents** | Phase 2 spawns one decision agent per question (parallel). Coordination.json tracks completion. | `fan_out` on execute state, one agent per decision question. Coordination replaced by koto's built-in fan-out tracking. | Yes -- fan_out with structured coordination (track which decisions are complete) |
| **User interaction** | Phase 0: ask topic if empty. Phase 6: AskUserQuestion for plan vs approve-only. `--auto` bypasses. | `accepts` on setup and finalize states. Auto variable for bypass. | Minor |
| **External calls** | `gh` for cross-repo issues. `scripts/transition-status.sh` for status changes. `git` for branch/commit. | Same external calls, structured by state entry/exit. | No gap |

---

## 3. prd

| Aspect | Current Implementation | Koto Equivalent | Gap? |
|--------|----------------------|-----------------|------|
| **State files** | `wip/prd_<topic>_scope.md`, `wip/research/prd_<topic>_phase2_*.md`. PRD at `docs/prds/PRD-<topic>.md`. No JSON state files. | Context keys for scope, research results. PRD as output artifact. | Minor -- simpler state than design |
| **Resume logic** | PRD status "Accepted" -> offer revise, "Draft" -> Phase 3, research files exist -> Phase 3, scope exists -> Phase 2, on topic branch -> Phase 1, else Phase 0. | States with `gates` on context keys and PRD status. | Yes -- PRD status check ("Draft" vs "Accepted") requires document content inspection |
| **Phase ordering** | 5 phases (0-4), sequential. Phase 1 is conversational (may loop). Phase 2-3 may loop back. | Linear with optional cycle between discover and draft states. | Yes -- same loop pattern gap as explore |
| **Gates/checks** | No explicit precondition checks beyond branch state. Phase 4 jury review is mandatory (3 agents). | Mandatory validate state with no skip. Jury agents as fan_out on validate. | Minor |
| **Decision capture** | `wip/prd_<topic>_decisions.md` in auto mode. No structured decision format otherwise. | Context key for decisions in auto mode. | Minor |
| **Parallel agents** | Phase 2: parallel specialist agents for research leads. Phase 4: 3-agent jury review. | Two fan_out points: discover (dynamic count) and validate (fixed 3). | Yes -- same dynamic fan_out gap |
| **User interaction** | Phase 1 is conversational dialogue. Phase 3 user reviews draft. Phase 4 user approves after jury. | `accepts` blocks on scope, draft, and validate states. | Yes -- same conversational phase gap |
| **External calls** | `gh` for issues. `git` for branches. | No gap |

---

## 4. plan

| Aspect | Current Implementation | Koto Equivalent | Gap? |
|--------|----------------------|-----------------|------|
| **State files** | `wip/plan_<topic>_analysis.md`, `_milestones.md`, `_decomposition.md`, `_issue_*.md`, `_manifest.json`, `_dependencies.md`, `_review.md`. PLAN doc at `docs/plans/PLAN-<topic>.md`. Manifest is JSON with issue metadata. | Context keys per phase artifact. Manifest as structured context. Issue files as fan_out artifacts. | Yes -- manifest.json has structured metadata (issue count, complexity distribution) used for downstream decisions |
| **Resume logic** | File-existence cascade over 7+ artifacts. Also checks `gh issue list` for existing GitHub issues. | States with `gates`. GitHub issue existence check needs a custom gate type (external command gate). | Yes -- `gh issue list` as a resume signal is an external-command gate, not a file/context check |
| **Phase ordering** | 7 phases + Phase 3.5 (execution mode selection between decomposition and generation). Strictly sequential. | Linear chain with a branching point after decompose for mode selection. Mode feeds into generation with different behavior. | Minor -- branching on mode is a standard `when` guard |
| **Gates/checks** | Phase 1: source document status validation (Accepted for design/PRD, Active for roadmap). Handoff validation table with per-status error messages. | Gate on analysis state: document-status-accepted. Different gate for roadmap (document-status-active). | Yes -- status validation requires reading document frontmatter, a content-inspection gate |
| **Decision capture** | `wip/plan_<topic>_decisions.md` in auto mode. Execution mode decision (single-pr vs multi-pr) captured in decomposition artifact. | Context keys. Execution mode as an enum variable set after decompose state. | Minor |
| **Parallel agents** | Phase 4: parallel agents generate issue bodies (one per issue). | `fan_out` on generation state. Count determined by decomposition output. | Yes -- dynamic fan_out count from prior phase output |
| **User interaction** | Phase 3.5: user confirms execution mode. Phase 7: implicit (creates GitHub artifacts). | `accepts` on mode_selection state. | Minor |
| **External calls** | `gh issue list`, `gh issue create`, `gh api` for milestones. Scripts: `create-issues-batch.sh`, `create-issue.sh`, `build-dependency-graph.sh`, `render-template.sh`, `apply-complexity-label.sh`. | Same calls, invoked from state entry/exit actions. | No gap -- but many scripts; koto `actions` would structure invocation |

---

## 5. decision

| Aspect | Current Implementation | Koto Equivalent | Gap? |
|--------|----------------------|-----------------|------|
| **State files** | `wip/<prefix>_context.md`, `_research.md`, `_alternatives.md`, `_bakeoff_<N>.md`, `_examination.md`, `_report.md`. Intermediate files deleted after Phase 6 (only report persists). | Context keys per phase. Cleanup as state exit action on synthesis. | Yes -- cleanup of intermediate artifacts needs koto lifecycle hooks or explicit cleanup state |
| **Resume logic** | File-existence cascade: report exists -> complete, examination -> Phase 6, bakeoff files -> Phase 4, alternatives -> Phase 3 (or Phase 6 for fast path), research -> Phase 2, context -> Phase 1, else Phase 0. | States with `gates`. Fast-path skip needs a `when` guard checking tier variable. | Minor -- fast-path is a standard conditional transition |
| **Phase ordering** | 7 phases (0-6). Fast path (Tier 3) skips Phases 3-5. Full path (Tier 4) runs all. | Two paths from alternatives state: fast_path -> synthesis (when tier=standard), full_path -> bakeoff -> revision -> examination -> synthesis (when tier=critical). | Minor -- conditional paths are well-supported by `when` guards |
| **Gates/checks** | No explicit precondition checks. Tier determined by input context (standard vs critical). | Tier as a variable, set in context state. | No gap |
| **Decision capture** | The entire skill IS decision capture. Final report in `wip/<prefix>_report.md` with structured YAML result block. | Report as the terminal context artifact. | No gap |
| **Parallel agents** | Phase 2: N alternative agents (disposable). Phase 3: N validator agents (persistent via SendMessage). Phases 4-5: same validators re-messaged. | Fan_out on alternatives state (disposable). Persistent validators are the hardest gap: Phases 3-5 re-message the SAME agents. | Yes -- **persistent agent re-messaging across states is not supported by koto**. Validators must retain conversation history across bakeoff, revision, and examination. This is the single biggest koto gap across all skills. |
| **User interaction** | Phase 0: ask question if empty. `--auto` bypasses. Mostly non-interactive by design (sub-operation mode). | `accepts` on context state. Auto mode default for sub-operation invocations. | Minor |
| **External calls** | None beyond standard file operations. | No gap |

---

## 6. release

| Aspect | Current Implementation | Koto Equivalent | Gap? |
|--------|----------------------|-----------------|------|
| **State files** | No wip/ artifacts. State is entirely in git tags, GitHub releases, and CI status. Temporary file: `/tmp/release-notes-<version>.md`. | Context keys for version, notes, dispatch_timestamp. But most "state" is external (git tags, GH releases). | Yes -- release has no persistent wip/ state; koto context would need to wrap external state checks |
| **Resume logic** | None explicit. Each phase checks external state (tag exists? draft exists? workflow running?). Re-running the skill re-evaluates from scratch. | States with external-command gates: tag-not-exists, draft-not-exists, ci-green. | Yes -- every gate is an external command check, not a file/context check. This is the most external-state-heavy skill. |
| **Phase ordering** | 6 phases, strictly sequential. Dry-run skips Phases 4-6. | Linear chain with a `when` guard on dry_run variable to skip dispatch/monitor states. | Minor |
| **Gates/checks** | Phase 2 has 6 precondition checks: clean tree, CI green, no existing tag, no existing draft, no release blockers, security PR audit. Most thorough gate set of any skill. | 6 gates on the preconditions state: `git-clean`, `ci-green`, `tag-not-exists`, `draft-not-exists`, `no-blockers`, `security-audit`. All require external commands. | Yes -- koto gates are currently `context-exists` type; release needs `command-succeeds` gate type |
| **Decision capture** | Phase 3: user confirms version and notes. Security PR handling decision in Phase 2. No persistent decision file. | `accepts` on version_confirmation state with enum for version choice. Security handling as `accepts` on preconditions. | Minor |
| **Parallel agents** | None. Single-agent workflow throughout. | N/A | No gap |
| **User interaction** | Phase 1: version recommendation (if no arg). Phase 2: security PR handling. Phase 3: AskUserQuestion for version confirmation + notes editing. Most interactive skill. | Multiple `accepts` blocks. Notes editing loop harder to model (iterative refinement). | Yes -- iterative note editing ("request edits, re-present, confirm") is an unbounded loop |
| **External calls** | Heavy: `git describe`, `git tag`, `git log`, `git status`, `gh release create`, `gh release view`, `gh workflow run`, `gh run list`, `gh issue list`, `gh pr list`, `gh api`. Most external-command-heavy skill. | Same calls, but koto would need to structure ~15 distinct external commands across states. | No structural gap, but high integration surface |

---

## 7. review-plan

| Aspect | Current Implementation | Koto Equivalent | Gap? |
|--------|----------------------|-----------------|------|
| **State files** | `wip/plan_<topic>_review.md` (proceed verdict) or `wip/plan_<topic>_review_loopback.md` (loop-back verdict). Two mutually exclusive output files. | Context key `review_verdict` with enum (proceed, loop_back). Verdict content as context artifact. | Minor -- two-file pattern simplifies to one context key with enum |
| **Resume logic** | `_review.md` exists -> skip (already reviewed). `_review_loopback.md` exists -> execute loop-back. Else start at Phase 0. | Three-state check: reviewed (skip), loopback (execute), none (start). | Minor |
| **Phase ordering** | 7 phases (0-6). Phases 1-4 are review categories, can run in parallel in adversarial mode. Phase 5 synthesizes. Phase 6 only on loop-back. | States: setup -> (scope_gate \| design_fidelity \| ac_discriminability \| sequencing) -> verdict -> optional loop_back. Parallel states for categories. | Yes -- true parallel states (not fan_out of same task, but 4 different tasks running simultaneously) |
| **Gates/checks** | Phase 0: reads plan wip/ artifacts, detects input_type. Phase 6 loop-back: deletes wip/ artifacts back to loop_target and signals /plan to re-enter. | Gate on setup: plan artifacts exist. Loop-back as a state that triggers artifact deletion and parent re-entry. | Yes -- loop-back signaling to parent skill (/plan) has no koto primitive; needs cross-workflow messaging |
| **Decision capture** | Verdict artifact captures all findings with structured `review_result` YAML schema (critical_findings, category scores, verdict enum). | Verdict as structured context with schema validation. | Minor -- YAML schema maps well to koto context schema |
| **Parallel agents** | Fast-path: 1 agent per category (4 total, could parallel). Adversarial: 3 validators per category (12 agents), then cross-examination agents for disagreements. | Fast-path: fan_out with 4 fixed agents. Adversarial: nested fan_out (4 categories x 3 validators), then conditional cross-examination fan_out for disagreements. | Yes -- nested fan_out (fan_out within fan_out) and conditional follow-up agents |
| **User interaction** | None in fast-path (sub-operation). Standalone adversarial: minimal. | Mostly non-interactive. | No gap |
| **External calls** | None beyond file operations. | No gap |

---

## Cross-Cutting Gaps Summary

These gaps recur across multiple skills and represent the core koto capabilities
needed for full adoption:

| Gap | Affected Skills | Priority |
|-----|----------------|----------|
| **Dynamic fan_out count** (count determined by prior phase output) | explore, prd, plan, design | High -- 4/7 skills |
| **Persistent agent re-messaging** (same agent across multiple states) | decision | High -- blocks decision skill entirely |
| **External-command gates** (`gh`, `git` checks as state preconditions) | release, plan, explore | High -- release is ungovernable without this |
| **Content-inspection gates** (check document sections, frontmatter status) | design, prd, plan | Medium -- workaround: set context key when section is written |
| **Conversational phases** (unbounded dialogue before producing an artifact) | explore, prd | Medium -- fundamental mismatch with request/response model |
| **Cross-workflow signaling** (child signals parent to re-enter a state) | review-plan -> plan | Medium -- only one skill pair, but architecturally important |
| **Nested fan_out** (fan_out within fan_out) | review-plan (adversarial) | Low -- only adversarial mode |
| **Iterative refinement loops** (user edits, re-present, confirm) | release, explore | Low -- workaround: model as self-loop state |
| **Intermediate artifact cleanup** (delete wip/ files after synthesis) | decision | Low -- workaround: cleanup state at end of chain |
| **Append-to-context** (accumulate entries across loop iterations) | explore | Low -- workaround: overwrite with full accumulated content |
