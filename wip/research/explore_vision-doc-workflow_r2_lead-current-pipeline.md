# Current End-to-End Pipeline: Idea to Merged PR

Research output for the vision-doc-workflow exploration, Round 2.

## Pipeline Overview (ASCII)

```
                          "I have an idea"
                                |
                                v
                    +----------------------+
                    |    /explore          |  "I don't know what I need"
                    |  (6 phases, looped)  |
                    +----------+-----------+
                               |
              Crystallize decides artifact type
                               |
         +----------+----------+----------+----------+----------+
         |          |          |          |          |          |
         v          v          v          v          v          v
      /prd      /design    /plan     Spike     Comp.Anal   No Artifact
     (WHAT)     (HOW)    (ISSUES)   Report    (private)    (just do it)
                                    [format   [format
                                     ref]      ref]
         |          |          |
         v          v          |
    PRD-*.md   DESIGN-*.md     |
    Accepted    Proposed       |
         |          |          |
         +----+-----+          |
              |                |
              v                |
          /design              |
          (if needed)          |
              |                |
              v                |
         DESIGN-*.md           |
          Accepted             |
              |                |
              v                v
         +----------------------+
         |      /plan           |  Decomposes into issues
         |  (7 phases)          |  Produces PLAN-*.md
         +----------+-----------+
                    |
          +---------+---------+
          |                   |
     single-pr            multi-pr
     (PLAN doc             (GitHub
      w/ outlines)          milestone
          |                 + issues)
          |                   |
          v                   v
     /implement          /work-on (per issue)
     (PLAN doc)          or /implement-doc (design)
          |                   |
          v                   v
     Single PR            Per-issue PRs
     w/ all changes       via koto workflow
          |                   |
          v                   v
     CI green             CI green per PR
     PR merged            Issues closed
          |                   |
          v                   v
     /complete-milestone  /complete-milestone
     (cleanup, close)     (cleanup, close)
          |                   |
          v                   v
        /release            /release
     (version, notes,    (version, notes,
      GitHub release)     GitHub release)
```

## Stage-by-Stage Breakdown

### Stage 0: Triage (entry from existing issues)

| Attribute | Value |
|-----------|-------|
| **Command** | `/triage` (private) |
| **Entry** | Issue with `needs-triage` label |
| **Input artifact** | GitHub issue body |
| **Output artifact** | Label applied: `needs-prd`, `needs-design`, `needs-spike`, or no label (ready) |
| **Decisions** | 3-agent parallel assessment: needs investigation, needs breakdown, or ready |
| **Next stage** | Routes to /explore, /prd, /design, or /work-on depending on label |

### Stage 1: Explore (discovery)

| Attribute | Value |
|-----------|-------|
| **Command** | `/explore` (shirabe, public) |
| **Entry** | User says "I don't know what I need" or an issue/topic |
| **Input artifact** | Topic string or issue reference |
| **Output artifact** | `wip/explore_<topic>_crystallize.md` + handoff artifact |
| **Decisions** | Artifact type selection via crystallize framework scoring |
| **Next stage** | Routes to /prd, /design, /plan, /decision, or "no artifact" |

**Internal phases:** Setup -> Scope -> Discover (fan-out agents) -> Converge (loop) -> Crystallize -> Produce

The discover-converge loop can repeat N rounds. Each round fans out research agents on leads, then converges findings with the user.

### Stage 2a: PRD (requirements)

| Attribute | Value |
|-----------|-------|
| **Command** | `/prd` (shirabe, public) |
| **Entry** | Explore handoff, or direct invocation for known requirements |
| **Input artifact** | Topic or explore handoff |
| **Output artifact** | `docs/prds/PRD-<topic>.md` with status "Accepted" |
| **Decisions** | Scope, requirements prioritization, 3-agent jury validation |
| **Next stage** | Suggests /design (complex) or /plan (simple/medium) |

**Internal phases:** Setup -> Scope (conversational) -> Discover (agent fan-out) -> Draft (iterative) -> Validate (jury)

### Stage 2b: Design (architecture)

| Attribute | Value |
|-----------|-------|
| **Command** | `/design` (shirabe, public) |
| **Entry** | Accepted PRD, or explore handoff, or freeform topic |
| **Input artifact** | PRD path or topic string |
| **Output artifact** | `docs/designs/DESIGN-<topic>.md` with status "Proposed" |
| **Decisions** | Decomposed into independent decision questions, each evaluated by /decision sub-operation |
| **Next stage** | Suggests /plan (always) |

**Internal phases:** Setup -> Decompose (identify decision questions) -> Execute (parallel decision agents) -> Cross-Validate -> Investigate (architecture synthesis) -> Security review -> Finalize

The /decision skill is invoked as a sub-operation per decision question, with its own 7-phase workflow (context -> research -> alternatives -> bakeoff -> revision -> examination -> synthesis). Tier 3 decisions skip the adversarial phases 3-5.

### Stage 2c: Decision (standalone)

| Attribute | Value |
|-----------|-------|
| **Command** | `/decision` (shirabe, public) |
| **Entry** | Explore crystallize -> decision record, or direct invocation |
| **Input artifact** | Decision question |
| **Output artifact** | Decision report (wip/ file) or ADR |
| **Decisions** | Multi-phase structured evaluation with optional adversarial bakeoff |
| **Next stage** | Terminal, or feeds into /design if the decision was about technical approach |

### Stage 3: Plan (decomposition)

| Attribute | Value |
|-----------|-------|
| **Command** | `/plan` (shirabe, public) |
| **Entry** | Accepted design doc, accepted PRD, active roadmap, or freeform topic |
| **Input artifact** | DESIGN-*.md, PRD-*.md, ROADMAP-*.md, or topic string |
| **Output artifact** | `docs/plans/PLAN-<topic>.md` + optionally GitHub milestone and issues |
| **Decisions** | Decomposition strategy (walking skeleton vs horizontal), execution mode (single-pr vs multi-pr), complexity classification per issue |
| **Next stage** | /implement (single-pr) or /work-on per issue (multi-pr) |

**Internal phases:** Analysis -> Milestone -> Decomposition (+ execution mode) -> Generation (parallel agents) -> Dependencies -> Review (/review-plan adversarial check) -> Creation

The /review-plan skill runs as Phase 6, adversarially challenging the plan across 4 categories before issues are created.

### Stage 4a: Implement (single-PR from PLAN)

| Attribute | Value |
|-----------|-------|
| **Command** | `/implement` (private) |
| **Entry** | PLAN doc with `execution_mode: single-pr` |
| **Input artifact** | `docs/plans/PLAN-<topic>.md` |
| **Output artifact** | Single PR with all changes, CI green |
| **Decisions** | Agent routing per issue (coder/webdev/techwriter based on deliverable type) |
| **Next stage** | /complete-milestone |

**Internal phases:** Setup (state init, QA/TW planners) -> Controller Loop (implement each issue via capability agents) -> Complete (validate coverage, finalize PR)

State machine per issue: `pending -> in_progress -> implemented -> scrutinized -> pushed -> completed`

### Stage 4b: Work-on (per-issue implementation)

| Attribute | Value |
|-----------|-------|
| **Command** | `/work-on` (shirabe, public) |
| **Entry** | GitHub issue number, milestone reference, or issue URL |
| **Input artifact** | GitHub issue |
| **Output artifact** | Merged PR with passing CI |
| **Decisions** | Implementation approach, test strategy |
| **Next stage** | Next issue in milestone, or /complete-milestone when all done |

Orchestrated via koto workflow templates. Handles blocking labels (needs-design, needs-prd, etc.) by stopping and routing to the appropriate upstream skill.

### Stage 4c: Implement-doc (multi-issue from design doc, legacy)

| Attribute | Value |
|-----------|-------|
| **Command** | `/implement-doc` (private) |
| **Entry** | Design doc with Implementation Issues section |
| **Input artifact** | `docs/designs/DESIGN-<topic>.md` with Mermaid dependency graph |
| **Output artifact** | Single PR implementing all ready issues |
| **Decisions** | Issue ordering based on dependency graph, agent routing |
| **Next stage** | /complete-milestone |

This predates /implement and works directly from design docs rather than PLAN docs. It uses the same state machine and agent hierarchy as /implement.

### Stage 5: Sprint (workspace setup)

| Attribute | Value |
|-----------|-------|
| **Command** | `/sprint` (private) |
| **Entry** | Repo name + issue/milestone reference |
| **Input artifact** | Issue or milestone reference |
| **Output artifact** | Cloned repo in isolated directory on feature branch |
| **Decisions** | Branch naming convention |
| **Next stage** | Hands off to /work-on |

Utility command for setting up isolated development environments, particularly for milestone-based multi-issue work.

### Stage 6: Groom (backlog maintenance)

| Attribute | Value |
|-----------|-------|
| **Command** | `/groom` (private) |
| **Entry** | Open issue backlog |
| **Input artifact** | List of open GitHub issues |
| **Output artifact** | Updated issues (closed, relabeled, or marked ready) |
| **Decisions** | Per-issue: close, update, skip, or mark ready-for-work |
| **Next stage** | Issues flow to /triage or /work-on |

### Stage 7: Complete-milestone (cleanup)

| Attribute | Value |
|-----------|-------|
| **Command** | `/complete-milestone` (private) |
| **Entry** | All issues in milestone closed |
| **Input artifact** | Milestone reference |
| **Output artifact** | Closed milestone, updated design doc status, cleanup changes |
| **Decisions** | 6-phase validation with parallel agents, batched approval |
| **Next stage** | /release |

### Stage 8: Release

| Attribute | Value |
|-----------|-------|
| **Command** | `/release` (shirabe, public) |
| **Entry** | Code ready on main |
| **Input artifact** | Conventional commits since last tag |
| **Output artifact** | GitHub release with version tag and release notes |
| **Decisions** | Version bump recommendation (major/minor/patch) |
| **Next stage** | Terminal |

## Artifact Format References (no creation workflow)

These artifact types have format/structure skills but no dedicated creation workflow:

| Artifact | Skill | Location | Notes |
|----------|-------|----------|-------|
| Roadmap | `/roadmap` (private) | `docs/roadmaps/ROADMAP-*.md` | Format reference only; created manually or via /explore |
| Spike Report | `/spike-report` (private) | `docs/spikes/SPIKE-*.md` | Format reference only; /explore can route to it but no creation workflow |
| Competitive Analysis | `/competitive-analysis` (private) | `docs/competitive/COMP-*.md` | Private repos only; format reference, no creation workflow |
| Decision Record | `/decision-record` (private) | `docs/decisions/ADR-*.md` | Format reference; /decision produces reports that can become ADRs |

## Identified Gaps

### Gap 1: No Pre-PRD "Vision" Stage

The pipeline starts at /explore, which is designed for "I don't know what artifact type I need." But there's no stage for "I have a project thesis but it's not ready for requirements yet." /explore can crystallize to any artifact type, but there's no VISION artifact type in the routing table. The pre-PRD ideation layer is missing.

**Current workaround:** Users either jump straight to /prd (skipping validation of the project thesis) or use /explore with a topic that's too vague, leading to multi-round exploration that could be more structured.

### Gap 2: Spike Reports Have No Creation Workflow

/explore can crystallize to "Spike Report" but Phase 5 routes it to the deferred handler (`phase-5-produce-deferred.md`). There's a format reference skill but no structured workflow for actually running the spike investigation. Users must manually create the spike report following the format reference.

**Current workaround:** Manual spike report creation after /explore recommends it.

### Gap 3: Roadmaps Have No Creation Workflow

Same as spikes -- format reference exists, but no structured creation process. /plan can consume roadmaps (producing planning issues with needs-* labels), but creating the roadmap itself is manual.

**Current workaround:** Manual roadmap authoring, then /plan to decompose.

### Gap 4: Competitive Analysis Has No Creation Workflow

Format reference only. /explore can route to it (private repos), but the actual research and writing is unstructured.

**Current workaround:** Manual creation following the format reference.

### Gap 5: /implement-doc vs /implement Overlap

Two implementation skills exist: /implement-doc (works from design docs directly) and /implement (works from PLAN docs). /implement was built to supersede /implement-doc by routing through PLAN docs as a universal gateway, but /implement-doc still exists and is listed as a skill.

**Current workaround:** Users must know which to use. /implement-doc works for designs with Implementation Issues sections. /implement works for PLAN docs.

### Gap 6: Design Doc Status "Proposed" -> "Accepted" Transition is Manual

/design produces a design doc with status "Proposed." The transition to "Accepted" (required before /plan can consume it) is a manual step. There's a `/docstatus` command but it's not automatically invoked.

**Current workaround:** User manually transitions status or the review process in /design's Phase 6 handles it interactively.

### Gap 7: No Automated Pipeline Stitching

Each skill suggests the next skill at completion (e.g., /prd suggests /design, /design suggests /plan), but the user must manually invoke the next command. There's no "run the full pipeline" command.

**Current workaround:** User manually chains commands. The --auto flag helps within a single skill but doesn't chain across skills.

### Gap 8: Triage -> Upstream Artifact Loop Can Stall

When /triage routes an issue to needs-design or needs-prd, the issue gets labeled but nothing automatically kicks off the upstream artifact creation. The issue sits with a blocking label until someone manually runs the appropriate skill.

**Current workaround:** /work-on detects blocking labels and stops, telling the user to run the upstream skill. But this is reactive, not proactive.

### Gap 9: /explore Deferred Artifacts Are Stub Implementations

Phase 5's deferred handler covers Roadmap, Spike, Competitive Analysis, and Prototype. These all get the same treatment -- a stub that acknowledges the crystallize decision but doesn't have a structured creation workflow. The user gets a recommendation but must create the artifact manually.

### Gap 10: No Feedback Loop from Implementation Back to Design

When implementation reveals that the design was wrong (common), there's no structured process for updating the design doc and re-planning. The implementation skills (/implement, /work-on) don't have a "design revision needed" escape hatch.

**Current workaround:** User manually stops implementation, updates the design doc, and re-plans.

## Skill Inventory

### Public (shirabe)

| Skill | Type | Has Creation Workflow |
|-------|------|---------------------|
| explore | Workflow | Yes (6-phase discovery loop) |
| prd | Workflow | Yes (4-phase requirements) |
| design | Workflow | Yes (6-phase architecture) |
| plan | Workflow | Yes (7-phase decomposition) |
| work-on | Workflow | Yes (koto-backed implementation) |
| decision | Workflow | Yes (7-phase evaluation, also sub-operation) |
| review-plan | Workflow | Yes (adversarial plan review, sub-operation) |
| release | Workflow | Yes (version + notes + dispatch) |
| writing-style | Reference | N/A |
| public-content | Reference | N/A |
| private-content | Reference | N/A |

### Private (tsukumogami)

| Skill | Type | Has Creation Workflow |
|-------|------|---------------------|
| implement | Workflow | Yes (PLAN-based state machine) |
| implement-doc | Workflow | Yes (design-doc-based state machine) |
| sprint | Utility | Yes (workspace setup) |
| triage | Workflow | Yes (3-agent assessment) |
| groom | Workflow | Yes (interactive backlog walk) |
| complete-milestone | Workflow | Yes (6-phase validation) |
| roadmap | Reference | No |
| spike-report | Reference | No |
| competitive-analysis | Reference | No |
| decision-record | Reference | No |
| design-doc | Reference | No |
| issue-drafting | Reference | No |
| issue-filing | Reference | No |
| state-management | Reference | No |
| Various dev skills | Reference | No (go-dev, rust-dev, web-dev, bash-dev, nodejs) |
