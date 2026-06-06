# Decision 1: Sub-agent fallback section format

**Dispatch context:** Walked as serial-self under sub-agent dispatch (`/scope` → `/design`); independence-loss caveat applies — one agent evaluating multiple alternatives against criteria; no cross-contamination because each option is judged against its own lens.

## Question

Where does the "Running as a sub-agent" fallback section live in each child SKILL.md, what shape does it take, and what specific fallback patterns does it name (serial-self-jury per R1/R2, parent-delegated-approval per R3, decision-bypass per R4, execution-mode-hint per R5, inline-substitute review per R6, deterministic-mode bypass per R7, NOT-covered carve-out per R8)? What is anchored at the pattern level so the seven children inherit consistently?

## Constraints (from Decision Drivers)

- **Composability** — one shape across seven children (`/brief`, `/prd`, `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap`, plus `/work-on` for R7).
- **R31** — direct invocation behavior unchanged.
- **R32 sequencing** — pattern-level edits land before per-skill consumers.
- **D2** — serial-self-jury contract is fixed at the PRD; design picks placement only.

## Options Considered

### Option A — Pattern-level canonical section + per-skill citations

Add one canonical "Running as a Sub-Agent" section to `references/parent-skill-pattern.md` that names the four pattern-level fallback shapes (serial-self-jury, parent-delegated-approval, inline-substitute-review, deterministic-mode-bypass). Each child SKILL.md grows a short section (4-8 lines) under its existing "Critical Requirements" subsection that cites the pattern-level reference and names the skill-specific binding (which phase fans out, which approval gate exists, which sub-skill it dispatches). The NOT-covered carve-out (R8) lives once in the pattern reference; each child's section cites it by reference rather than repeating it.

**Pros:** R32 sequencing falls out automatically — the pattern reference edit is the upstream change, the per-skill edits are downstream consumers. Cross-skill consistency is preserved by construction (one canonical statement). The four fallback shapes are named pattern-side so a future child inherits the vocabulary. R31 backward compatibility is preserved — the section describes sub-agent behavior, not direct-invocation behavior; direct-invocation paths are unchanged.

**Cons:** A reader of one child SKILL.md must follow one extra hop to read the canonical contract. The hop is single (the child cites one reference path) and the pattern reference is already cited from every child's existing prose.

### Option B — Inline-only per-skill sections, no pattern-level section

Add a "Running as a Sub-Agent" section to each child SKILL.md that names the skill-specific fallback in full. No pattern-level canonical section; the four fallback shapes are restated in each child.

**Pros:** A reader of one child SKILL.md sees the full contract without following a citation.

**Cons:** Composability fails — seven children with seven slightly-divergent restatements of the same contract is the failure shape the BRIEF named. Cross-skill consistency requires every future edit to update seven files in lockstep. R32 sequencing has nothing pattern-level to land first. Drift between children's wordings is inevitable; the BRIEF's "audit trail matches execution" goal degrades when two children describe the same fallback shape in two different ways.

### Option C — Pattern-level section only, no per-skill mention

Add the canonical fallback contract to `references/parent-skill-pattern.md`; do not edit any child SKILL.md. Children inherit by virtue of the pattern reference being cited at the top of each SKILL.md.

**Pros:** Single source; no per-skill duplication.

**Cons:** AC1.1, AC1.3, AC1.4, AC1.5, AC1.6, AC1.7, AC1.8 explicitly require sections "in each of skills/<name>/SKILL.md" — a reader checking the ACs grep for the section, doesn't find it, and the AC fails. Skill-specific bindings (which phase fans out, which approval gate exists) cannot be inferred from the pattern reference alone — the binding is per-skill data.

## Chosen: Option A — Pattern-level canonical section + per-skill citations

**Rationale.** Option A satisfies all eight ACs in Cluster 1, discharges R32 sequencing structurally (pattern-level edit is the upstream change), and discharges the BRIEF's "composability" framing. Option B fails composability; Option C fails the AC-grep test and elides the per-skill bindings.

**Placement details.**

The pattern-level canonical section lives in `references/parent-skill-pattern.md` as a new section titled `## Sub-Agent Dispatch Fallbacks`, positioned after the existing `## Team-Lead Operating Discipline` section. It names four canonical fallback shapes:

1. **serial-self-jury** — when a Phase-N parallel-agent jury site cannot fan out (the substrate has no Agent-tool surface for parallel reviewer spawning), the dispatched child runs each reviewer's rubric serially within its own context, evaluating each role's criteria against the role's specific lens without cross-contamination. The verdict artifact's preamble surfaces the operating context (`serial-self-jury under sub-agent dispatch`) and the independence-loss caveat (`a downstream reader should treat the PASS as serial-self-jury PASS, not parallel-jury PASS`).
2. **parent-delegated-approval** — when a child's `AskUserQuestion` approval gate cannot fire (the substrate has no user-at-terminal surface), the approval transitions to the parent's exit-path discipline — the child does NOT auto-promote the artifact's status; it leaves the artifact at the pre-approval status (`Proposed` for DESIGN, `Draft` for BRIEF/PRD) and writes the operating context into the artifact's `## Status` section prose. The parent runs the approval gate at its own boundary and transitions the status when the chain reaches the parent's exit path.
3. **inline-substitute-review** — when a child dispatches a nested sub-skill that cannot recursively dispatch under sub-agent (e.g., `/plan` Phase 6's `/review-plan` dispatch), the child runs an inline single-pass review variant that evaluates the same review rubric against the same artifact, without spawning the sub-skill. The variant is named in the child's prose; the artifact records `review_mode: inline-substitute` to preserve the audit trail.
4. **deterministic-mode-bypass** — when a child's koto state machine (e.g., `/work-on`'s plan-orchestrator loop) is asked to drive a chain whose decomposition, cascade timing, and push timing are supplied upfront by the parent's dispatch contract, the child SHALL surface a deterministic-mode bypass that executes the named steps in order without consulting the state machine. The bypass condition is `parent_orchestration.deterministic_mode: true` in the parent's state file; the audit trail records `chain_mode: deterministic-bypass`.

The section also names a fifth fallback shape per R4:

5. **decision-bypass with inline-resolution** — when `/design`'s per-decision `/decision` dispatch loop is asked to resolve a decision whose alternatives and recommended direction are enumerated in the upstream PRD's Decisions and Trade-offs section, the child SHALL surface an inline-resolution variant that records the bypass in the DESIGN's Considered Options preamble (`Decision N resolved inline per PRD §<section> per <reviewer-count> reviewer agreement`). The bypass condition is two-part: PRD names alternatives explicitly AND the reviewer count is acceptable inline (one or two reviewers under sub-agent dispatch).

The NOT-covered carve-out (R8) lives in a closing paragraph of the same section:

> Nested-team spawning remains Track B (`tsukumogami/vision#535`) and is not addressed by the inside-pattern fallbacks above. The fallbacks substitute serial behavior for parallel behavior at the pattern's existing fan-out and approval sites; they do not extend the pattern with new nested-team primitives. When a child's contract requires nested-team spawning the inside pattern cannot supply, the discipline routes to the parent's `abandonment-forced` exit path with `triggering_child:` recording which child's contract required the unsupplied primitive.

**Per-skill section placement.** Each child SKILL.md grows a `### Sub-Agent Dispatch Fallback` subsection under its existing `### Critical Requirements` section (the existing position where chain-wide invariants are stated). The subsection body is 4-8 lines and follows this shape:

```markdown
### Sub-Agent Dispatch Fallback

Under sub-agent dispatch (`parent_orchestration:` sentinel present in the parent's state file), this skill's <phase-N> <fan-out|approval-gate|nested-dispatch> follows the <fallback-shape-name> fallback from `references/parent-skill-pattern.md` (Sub-Agent Dispatch Fallbacks section). The verdict artifact's preamble surfaces the operating context and the independence-loss caveat per the canonical statement. Nested-team spawning is not covered (`tsukumogami/vision#535`).
```

The per-skill bindings:

| Skill | Fan-out / gate | Fallback shape | Per-skill section name |
|---|---|---|---|
| `/brief` | Phase 4 two-reviewer jury | serial-self-jury | `### Sub-Agent Dispatch Fallback` |
| `/prd` | Phase 4 three-reviewer jury | serial-self-jury | `### Sub-Agent Dispatch Fallback` |
| `/design` | Phase 6 jury + Phase 1-3 decision loop | serial-self-jury + decision-bypass | `### Sub-Agent Dispatch Fallback` |
| `/plan` | Phase 6 `/review-plan` + Phase 3 AskUserQuestion | inline-substitute-review + execution-mode-hint | `### Sub-Agent Dispatch Fallback` |
| `/vision` | Phase 4 jury | serial-self-jury | `### Sub-Agent Dispatch Fallback` |
| `/strategy` | Phase 4 jury | serial-self-jury | `### Sub-Agent Dispatch Fallback` |
| `/roadmap` | Phase 4 jury | serial-self-jury | `### Sub-Agent Dispatch Fallback` |
| `/work-on` | koto plan-orchestrator | deterministic-mode-bypass | `### Sub-Agent Dispatch Fallback` |

The execution-mode-hint variant for `/plan` Phase 3 (R5) is named in `/plan`'s section as a sub-bullet of the inline-substitute-review entry — it's a related variant of the same shape (reading the parent's state-file hint instead of prompting).

## Assumptions

- Each child SKILL.md already has a `### Critical Requirements` section that the new subsection can hang from. Verified for `/brief` (`skills/brief/SKILL.md:183`), `/prd` (`skills/prd/SKILL.md:116`), `/design` (`skills/design/SKILL.md:181`), `/plan` (`skills/plan/SKILL.md`, has equivalent `### Critical Requirements` section per grep).
- The pattern reference at `references/parent-skill-pattern.md` is the right anchor — confirmed it is the canonical contract surface and the existing `## Team-Lead Operating Discipline` section is the natural neighbor.
- The four canonical fallback shapes cover R1-R7. R8's carve-out is captured at the pattern level once.

## Status

complete
