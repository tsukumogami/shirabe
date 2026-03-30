# Phased Koto Adoption Plan for Shirabe Skills

Research output for the koto-adoption PRD. Analyzes 7 non-koto skills against
koto's current and planned capabilities, produces a priority-ordered conversion
table, and maps the dependency graph between koto features and skill conversions.

---

## Per-Skill Assessment

### 1. review-plan

| Dimension | Assessment |
|-----------|------------|
| **Koto readiness** | Convertible with current koto for fast-path mode. Adversarial mode needs parallel states. |
| **Blocking koto features** | Fast-path: none. Adversarial: nested fan_out (no issue). Cross-workflow signaling for loop-back to /plan (no issue). |
| **Conversion complexity** | Low (fast-path), High (adversarial mode) |
| **Value delivered** | Resume reliability for interrupted reviews. Verdict captured as structured context rather than file-existence detection. Phase enforcement prevents skipping mandatory review categories. |
| **Recommended phase** | Phase 1 (fast-path only). Phase 3 (adversarial mode + loop-back signaling). |

**Details**: The fast-path is a linear 7-state chain (setup, scope_gate,
design_fidelity, ac_discriminability, sequencing, verdict, optional loop_back).
No fan_out, no persistent agents, no external commands. Gates are purely
context-exists checks on plan artifacts. The two-file output pattern
(review.md vs review_loopback.md) maps cleanly to an enum evidence field on
the verdict state. Adversarial mode's 4 parallel review categories and nested
fan_out (3 validators per category) require parallel execution that koto
doesn't support.

### 2. decision

| Dimension | Assessment |
|-----------|------------|
| **Koto readiness** | Mostly convertible. The fast-path (Tier 3) and full-path (Tier 4) both map to conditional linear chains. |
| **Blocking koto features** | Persistent agent re-messaging across states (no issue -- biggest single gap). Dynamic fan_out for alternative generation (no issue). |
| **Conversion complexity** | Medium (core flow), High (persistent validators) |
| **Value delivered** | Tier routing enforced by engine rather than prose. Resume across the 7-phase chain eliminates re-running completed bakeoff rounds. Decision report structure validated by evidence schema. Intermediate artifact cleanup modeled as exit action on synthesis state. |
| **Recommended phase** | Phase 1 (without persistent validators -- disposable agents only). Phase 3 (full validator re-messaging). |

**Details**: The core decision flow is two conditional paths from the
alternatives state: fast_path (tier=standard) skips bakeoff/revision/examination,
full_path (tier=critical) runs all. `when` guards handle this cleanly. The
hard part is Phases 3-5: validators must retain conversation history across
bakeoff, revision, and examination states. Koto has no concept of persistent
agents that span multiple states. For Phase 1, disposable agents per state
(losing cross-state memory) is a workable degradation.

### 3. prd

| Dimension | Assessment |
|-----------|------------|
| **Koto readiness** | Partially convertible. Linear core blocked by dynamic fan_out and conversational Phase 1. |
| **Blocking koto features** | Dynamic fan_out count (#41 partly). Conversational scoping phase (no issue). Content-inspection gates for PRD status (workaround: context key). |
| **Conversion complexity** | Medium |
| **Value delivered** | Resume across 5 phases. Jury review (Phase 4) enforced as mandatory state with no skip transition. Scope and research artifacts tracked as context keys. |
| **Recommended phase** | Phase 2 (after #65/#87 enable variable passing; fan_out handled outside koto). |

**Details**: The 5-phase structure maps to: setup -> scope -> discover -> draft
-> validate. The discover-draft cycle needs bounded iteration (max rounds).
Phase 2 research leads use dynamic fan_out (agent count varies). Phase 4 jury
review uses fixed fan_out (3 agents). Both fan_out points would remain
skill-layer orchestrated, with koto gating on "all research artifacts exist"
via context-exists checks. PRD status detection ("Draft" vs "Accepted") needs
content-inspection -- workaround is setting a context key when status changes.

### 4. plan

| Dimension | Assessment |
|-----------|------------|
| **Koto readiness** | Partially convertible. Needs #65 for variable substitution in gate commands, #87 for evidence promotion. |
| **Blocking koto features** | koto #65 (--var for document paths, issue prefixes). koto #87 (promote execution mode from decompose to generation). External-command gates for `gh issue list` resume checks. Dynamic fan_out for parallel issue generation. |
| **Conversion complexity** | Medium-High |
| **Value delivered** | Resume across 7+ phases. Execution mode (single-pr vs multi-pr) captured as engine-level variable. Source document validation (Accepted/Active status) enforced by gates. Issue generation tracking via context artifacts replaces manifest.json. |
| **Recommended phase** | Phase 2 (after #65/#87). |

**Details**: Plan has the highest external-command surface of any non-release
skill: `gh issue list`, `gh issue create`, `gh api` for milestones, plus 5
helper scripts. Gate commands need variable substitution for document paths
and topic names. The Phase 3.5 execution mode branch maps to a `when` guard
after decompose. Parallel issue body generation (Phase 4) stays skill-layer.

### 5. explore

| Dimension | Assessment |
|-----------|------------|
| **Koto readiness** | Needs multiple features that don't exist yet. Most complex conversion. |
| **Blocking koto features** | Bounded iteration / loop counters (no issue). Dynamic fan_out (no issue / partly #41). Conversational scoping phase (no issue). Append-to-context for accumulated findings (workaround: overwrite). |
| **Conversion complexity** | High |
| **Value delivered** | Discover-converge loop enforced with max rounds. Research agent results tracked as context artifacts. Resume detects exact position in multi-round exploration. Round counter and scope narrowing visible in event log. |
| **Recommended phase** | Phase 2 (basic structure with fan_out outside koto). Phase 3 (full loop counter enforcement). |

**Details**: Explore's discover-converge loop is the most structurally complex
pattern across all skills. The loop (Phase 2 fan_out -> Phase 3 converge ->
decision point -> loop or proceed) needs bounded iteration that koto can't
express. The "Decision: Crystallize" string marker maps to an enum context key.
Conversational Phase 1 (unbounded dialogue) doesn't fit koto's
request/response model. Phase 2's dynamic fan_out (up to 8 leads, count varies)
stays skill-layer.

### 6. design

| Dimension | Assessment |
|-----------|------------|
| **Koto readiness** | Needs #65, #87, and sub-workflow invocation for /decision delegation. |
| **Blocking koto features** | koto #65 (--var for topic, prefix). koto #87 (promote decision results across states). Sub-workflow / nested template invocation (no issue -- for calling /decision as child). Dynamic fan_out for parallel decisions. Content-inspection gates for section existence. |
| **Conversion complexity** | High |
| **Value delivered** | 7-phase linear chain enforced. Cross-validation and security review mandatory (no skip transitions). Decision coordination tracked by engine rather than coordination.json. PRD prerequisite enforced by gate. |
| **Recommended phase** | Phase 2 (linear structure, fan_out outside koto). Phase 3 (sub-workflow delegation to /decision). |

**Details**: Design's 7 phases map to a linear chain, but Phase 2 spawns
parallel decision agents (one per question) that invoke the /decision skill.
This is nested skill invocation -- koto would need sub-workflow support or
template composition. Coordination.json (structured status tracking per
decision) would be replaced by context artifacts per decision. The section-
existence resume checks ("Solution Architecture section exists?") need
content-inspection gates or context keys set on section completion.

### 7. release

| Dimension | Assessment |
|-----------|------------|
| **Koto readiness** | Hardest to convert. Almost all state is external (git, GitHub). |
| **Blocking koto features** | External-command gates at scale (6 precondition checks, all shell-based). Polling gate type (CI monitoring). Iterative refinement loop for release notes editing. koto #65 (--var for version). |
| **Conversion complexity** | High |
| **Value delivered** | 6 precondition checks enforced as gates (clean tree, CI green, no existing tag, no draft, no blockers, security audit). Dispatch-monitor sequence structured. Dry-run mode as conditional skip. Release state visible in event log for audit. |
| **Recommended phase** | Phase 3 (after polling gates and external-command infrastructure mature). |

**Details**: Release is the most external-state-heavy skill. It has no wip/
artifacts -- state lives entirely in git tags, GitHub releases, and CI status.
Every gate is an external command check. The 6 precondition checks in Phase 2
are the most thorough gate set of any skill. Phase 6 polls CI workflow status
every 10 seconds for up to 5 minutes. Release notes editing is an unbounded
iterative loop. All of these patterns push against koto's current boundaries.

---

## Priority-Ordered Conversion Table

| Priority | Skill | Phase | Complexity | Blocking Features | Primary Value |
|----------|-------|-------|------------|-------------------|---------------|
| 1 | review-plan (fast-path) | Phase 1 | Low | None | Resume reliability, mandatory review enforcement |
| 2 | decision (without persistent validators) | Phase 1 | Medium | None | Tier routing enforcement, resume across 7 phases |
| 3 | prd | Phase 2 | Medium | #65, #87 | Resume, mandatory jury enforcement |
| 4 | plan | Phase 2 | Medium-High | #65, #87 | Resume across 7+ phases, mode capture |
| 5 | explore (basic) | Phase 2 | High | #65, #87 | Resume, round tracking, scope narrowing |
| 6 | design | Phase 2-3 | High | #65, #87, sub-workflows | Mandatory cross-validation/security, decision coordination |
| 7 | release | Phase 3 | High | Polling gates, external-command infra | Precondition enforcement, dispatch audit trail |
| 8 | review-plan (adversarial) | Phase 3 | High | Parallel states, nested fan_out | Full adversarial review with cross-examination |
| 9 | decision (persistent validators) | Phase 3 | High | Persistent agent re-messaging | Cross-state validator memory |
| 10 | explore (full loop enforcement) | Phase 3 | High | Bounded iteration primitives | Engine-enforced max rounds |

---

## Dependency Graph

```
Koto Features                          Skill Conversions
==============                         =================

[Current koto] ─────────────────────── review-plan (fast-path)
       │                                       │
       └───────────────────────────── decision (degraded validators)

[koto #65: --var support] ──────┐
                                ├───── prd
[koto #87: evidence promotion] ─┤
                                ├───── plan
                                │
                                ├───── explore (basic structure)
                                │
                                └───── design (linear chain)

[Polling gate type] ────────────┐
  (new issue needed)            │
                                ├───── release
[External-command gate infra]───┘
  (extends #87)

[Bounded iteration] ───────────────── explore (full loop enforcement)
  (new issue needed)

[Sub-workflow invocation] ─────────── design (decision delegation)
  (extends #41)

[Parallel state execution] ────┬───── review-plan (adversarial)
  (extends #41)                │
                               └───── decision (persistent validators)

[Cross-workflow signaling] ────────── review-plan (loop-back to /plan)
  (new issue needed)
```

### Feature dependency chain:

```
#65 (--var) ──┐
              ├── Phase 2 skills (prd, plan, explore-basic, design-linear)
#87 (promote) ┘
                    │
                    v
           Polling gate (new) ──── release
           Bounded iteration (new) ── explore-full
           Sub-workflows (#41) ──── design-full
           Parallel states (#41) ── review-plan-adversarial, decision-full
           Cross-workflow (new) ── review-plan-loopback
```

---

## Phase Definitions

### Phase 1: Current Koto (no new features needed)

**Skills**: review-plan (fast-path), decision (degraded)

**Scope**: Convert skills that map to linear/branching state chains without
variable substitution or parallel execution. Both skills work as sub-operations
(called by other skills), so their conversion validates koto's template model
for the simplest cases.

**New koto issues needed**: None.

**Effort**: ~2-3 days per skill template + evals.

### Phase 2: After #65 and #87 (variable infrastructure)

**Skills**: prd, plan, explore (basic), design (linear chain)

**Scope**: These skills need `--var` for topic names, artifact prefixes, and
document paths in gate commands. They need evidence promotion to carry forward
values like execution mode, PR URLs, and document status across states.
Parallel fan_out stays skill-layer orchestrated; koto gates on "all artifacts
exist" via context-exists.

**Koto prerequisites**:
- koto #65: `--var` support on `koto init`
- koto #87: evidence-to-variable promotion

**New koto issues needed**:
- Content-inspection gate convenience (or document as pattern: set context key
  when writing document sections, gate on context key rather than file content)

**Effort**: ~3-5 days per skill template + evals. #65 and #87 estimated at
medium complexity (days each) per the gaps analysis.

### Phase 3: Advanced Capabilities (new koto features)

**Skills**: release, review-plan (adversarial), decision (persistent validators),
explore (full loop enforcement), design (sub-workflow delegation)

**Scope**: These conversions need features that don't exist in koto and have
no open issues. Each represents a meaningful architectural addition.

**New koto issues needed**:
- **Polling gate type**: Re-run a gate command on interval until pass or timeout.
  The polling action infrastructure exists; extending it to gates is mechanical.
  Blocks: release.
- **Bounded iteration primitive**: Loop counter or `max_visits` on states.
  Blocks: explore full loop enforcement.
- **Cross-workflow signaling**: Child workflow signals parent to re-enter a
  state. Blocks: review-plan loop-back to /plan.
- **Parallel state execution** (extends #41): Fork/join for concurrent state
  branches. Blocks: review-plan adversarial, decision persistent validators.

**Effort**: Hard to estimate. Polling gate is hours. Bounded iteration is days.
Cross-workflow and parallel execution are architectural (weeks).

---

## Recommendations

1. **Start Phase 1 immediately.** review-plan (fast-path) and decision
   (degraded) need zero koto changes. They validate the template authoring
   workflow and build confidence in koto's model.

2. **Prioritize koto #65 over #87.** Variable substitution unblocks more
   skills than evidence promotion. #87 is important but has workarounds
   (re-derive values with shell commands).

3. **Don't block on parallel execution.** Skills already handle fan_out via
   Claude Code's Task agents. Koto gates on artifact completion
   (context-exists) rather than orchestrating parallelism. This is a
   sustainable pattern.

4. **File 3 new koto issues** after Phase 1 validates the approach: polling
   gate, bounded iteration, cross-workflow signaling. Don't file parallel
   execution yet -- it's the hardest and least urgent.

5. **Convert release last.** It has the highest external-state surface, the
   most user interaction, and needs features from every category. It's also
   the least frequently run skill, so the ROI of koto enforcement is lowest.
