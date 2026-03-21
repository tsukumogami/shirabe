# Ask Inventory: All User-Blocking Points in Shirabe Skills

Comprehensive audit of every point where a skill blocks on user input.

## Methodology

Searched all files under `skills/` for:
- Literal `AskUserQuestion` references
- Phrases: "ask the user", "ask whether", "present to the user", "user confirms",
  "user approves", "user selects", "user chooses", "user decides", "confirmation",
  "approval", "before proceeding"
- Decision points where the workflow stops and waits for user response

---

## Inventory by Skill

### explore (11 blocking points)

| # | File | Line | What's Being Asked | Category | Non-Interactive Alternative |
|---|------|------|--------------------|----------|---------------------------|
| E1 | SKILL.md | 78 | Empty input: "ask the user what they want to explore" | (a) researchable | Infer from branch name, recent commits, or open issues; fail with error if no signal |
| E2 | phases/phase-0-setup.md | 110-113 | Triage Stage 1 result (breakdown/ready): "Break down" vs "Implement directly" | (b) judgment | Follow the jury recommendation (majority vote); document assumption |
| E3 | phases/phase-0-setup.md | 184-193 | Triage Stage 2 result: confirm investigation type (needs-prd/design/spike/decision) or override | (b) judgment | Follow the jury recommendation; document assumption and the dissenting view |
| E4 | phases/phase-1-scope.md | 64-69 | Checkpoint: present understanding, user can course-correct | (c) approval | Present understanding as informational log; proceed unless contradictions found in research |
| E5 | phases/phase-3-converge.md | 66-79 | Narrowing question after synthesis (what matters most / what surprised you / what's unclear) | (b) judgment | Auto-answer based on signal strength: pick the direction with strongest research support; document the reasoning |
| E6 | phases/phase-3-converge.md | 91-99 | Capture user decisions after narrowing (scope narrowing, priority choices) | (b) judgment | Infer decisions from research evidence: eliminate weakest options, prioritize by signal count; document all inferred decisions |
| E7 | SKILL.md | 202-211 | Loop decision: "Explore further" vs "Ready to decide" | (b) judgment | Apply recommendation heuristic automatically: if gaps exist, explore further; if sufficient, proceed; document choice |
| E8 | phases/phase-4-crystallize.md | 118-147 | Artifact type recommendation (PRD/Design/Plan/No artifact/None of these) | (b) judgment | Accept the top-scoring recommendation from the crystallize framework; document scores and rationale |
| E9 | phases/phase-5-produce-deferred.md | 23-37 | Prototype unsupported: choose spike report vs design doc | (b) judgment | Follow recommendation heuristic (feasibility -> spike, architecture -> design); document choice |
| E10 | phases/phase-5-produce-deferred.md | 249-259 | Competitive analysis in public repo: choose alternative | (b) judgment | Default to design doc with market context section; document that competitive analysis was blocked by visibility |
| E11 | phases/phase-5-produce-no-artifact.md | 21-31 | Present findings and suggest next steps (informational) | (a) researchable | Output findings as log; no blocking needed since this is purely informational |

### design (10 blocking points)

| # | File | Line | What's Being Asked | Category | Non-Interactive Alternative |
|---|------|------|--------------------|----------|---------------------------|
| D1 | SKILL.md | 131 | Empty input: "ask the user what they want to design" | (a) researchable | Infer from branch name, recent issues, or current context; fail with error if no signal |
| D2 | phases/phase-0-setup-freeform.md | 44-53 | Quick scoping conversation (2-4 questions) then confirm understanding | (a) researchable | Read issue body, linked docs, and codebase to derive problem/scope/constraints; log derived understanding |
| D3 | phases/phase-2-present-approaches.md | 57-62 | Approach selection: recommend strongest, user approves or overrides | (b) judgment | Accept the recommended approach (already evidence-based); document rationale |
| D4 | phases/phase-2-present-approaches.md | 66-72 | Loop-back: "None of these" -- ask what's missing | (a) researchable | Not applicable in non-interactive: if recommendation confidence is low, add a research round automatically |
| D5 | phases/phase-3-deep-investigation.md | 91-101 | Deal-breaker found: return to Phase 2 vs accept risk and continue | (b) judgment | Follow recommendation heuristic (return to Phase 2 if severe; continue if minor); document the risk accepted or the pivot |
| D6 | phases/phase-3-deep-investigation.md | 103-106 | Mid-investigation decision point (choice between alternatives) | (b) judgment | Pick option with strongest research evidence; document as a recorded decision |
| D7 | phases/phase-3-deep-investigation.md | 132-133 | Decision review checkpoint: confirm unrecorded decisions | (c) approval | Record all identified decisions automatically; mark them as "agent-inferred" for later review |
| D8 | phases/phase-4-architecture.md | 89-92 | Implicit decision review: confirm choices baked into prose | (c) approval | Record all implicit decisions automatically; mark as "agent-inferred" |
| D9 | phases/phase-6-final-review.md | 138-141 | Final approval: "Approved" vs "Needs iteration" | (c) approval | Auto-approve if all review checks pass (strawman check, validation, security); document that approval was automatic |
| D10 | SKILL.md | 196-203 | Post-completion routing: "Plan (Recommended)" vs "Approve only" | (b) judgment | Follow recommendation based on complexity assessment; document choice |

### prd (8 blocking points)

| # | File | Line | What's Being Asked | Category | Non-Interactive Alternative |
|---|------|------|--------------------|----------|---------------------------|
| P1 | SKILL.md | 58 | Empty input: "ask the user what feature to specify" | (a) researchable | Infer from branch name, recent issues, or context; fail with error if no signal |
| P2 | SKILL.md | 111 | Unsure if current branch is related: "ask the user" | (a) researchable | Check branch name against topic; if ambiguous, create new branch and log assumption |
| P3 | phases/phase-1-scope.md | 61-69 | Checkpoint: present understanding (problem statement, scope, leads) | (c) approval | Present as informational log; proceed unless research reveals contradictions |
| P4 | phases/phase-2-discover.md | 142-153 | Loop-back decision: "Proceed to Phase 3" vs "Investigate more" vs "Restart scoping" | (b) judgment | Follow recommendation heuristic (proceed if coverage sufficient); document choice |
| P5 | phases/phase-3-draft.md | 68-79 | Surface open questions and trade-offs for user to weigh in on | (b) judgment | Resolve trade-offs using research evidence (pick the option with strongest support); document each decision with "agent-resolved" tag |
| P6 | phases/phase-3-draft.md | 99-105 | Incorporate feedback after draft review | (c) approval | Skip external feedback loop; proceed to validation (jury review catches issues) |
| P7 | phases/phase-4-validate.md | 169-172 | Jury found significant issues: present trade-offs for user decision | (b) judgment | Apply jury recommendations directly; document each fix |
| P8 | phases/phase-4-validate.md | 190-194 | Final approval: "Approve" vs "Request changes" | (c) approval | Auto-approve if all 3 jury agents pass; document automatic approval |

### plan (6 blocking points)

| # | File | Line | What's Being Asked | Category | Non-Interactive Alternative |
|---|------|------|--------------------|----------|---------------------------|
| PL1 | SKILL.md | 121 | Empty input: "ask the user what to plan" | (a) researchable | Infer from branch name or recent accepted designs; fail with error if no signal |
| PL2 | phases/phase-1-analysis.md | 95 | Ambiguous roadmap feature needs_label: AskUserQuestion for each unclear feature | (a) researchable | Apply the heuristic in the phase file (requirements unclear -> needs-prd, approach unclear -> needs-design, etc.); document each inference |
| PL3 | phases/phase-3-decomposition.md | 76-83 | Ambiguous decomposition strategy: walking skeleton vs horizontal | (b) judgment | Apply the heuristic (new e2e flow -> walking skeleton; refactoring/simple -> horizontal); document choice |
| PL4 | phases/phase-3-decomposition.md | 355-366 | Execution mode selection: single-pr vs multi-pr | (b) judgment | Follow the signal-strength heuristic; document tallied signals and recommendation |
| PL5 | phases/phase-6-review.md | 68 | Implicit: "before proceeding to creation" checklist implies user sign-off | (c) approval | Proceed if all automated checks pass; document deferred items |
| PL6 | phases/phase-7-creation.md | 318-324 | Upstream issue update: "Is there an upstream issue?" | (a) researchable | Check issue body for linked upstream references, check `spawned_from` frontmatter; if found, update automatically; if not, skip |

### work-on (4 blocking points)

| # | File | Line | What's Being Asked | Category | Non-Interactive Alternative |
|---|------|------|--------------------|----------|---------------------------|
| W1 | SKILL.md | 23 | needs-triage issue without triage workflow: "ask whether to proceed or reclassify" | (b) judgment | Default to proceed with implementation; document that triage was skipped |
| W2 | phases/phase-2-introspection.md | 78 | Clarify recommendation: "Use AskUserQuestion to resolve ambiguity" | (a) researchable | Attempt to resolve from codebase/docs context; if truly ambiguous, document the ambiguity and proceed with best guess |
| W3 | phases/phase-6-pr.md | 65 | Stuck on CI failures for 2-3 iterations: "ask the user for guidance" | (b) judgment | Document failures with full logs and stop execution (CI failure is a hard stop, not a skippable question) |
| W4 | phases/phase-6-pr.md | 69 | Red check that can't be fixed: "ask the user" about acceptable failures | (c) approval | Never auto-accept failing checks; stop execution and document failures (this is a genuine safety gate) |

---

## Summary by Category

### (a) Info that could be found via research: 11 occurrences

These are questions where the agent could find the answer through codebase analysis,
issue reading, branch inspection, or applying documented heuristics.

| ID | Skill | Summary |
|----|-------|---------|
| E1 | explore | Empty input -- infer topic |
| E11 | explore | No-artifact findings presentation (informational, not truly blocking) |
| D1 | design | Empty input -- infer topic |
| D2 | design | Freeform scoping conversation |
| D4 | design | Loop-back: what approach is missing |
| P1 | prd | Empty input -- infer topic |
| P2 | prd | Branch ambiguity |
| PL1 | plan | Empty input -- infer topic |
| PL2 | plan | Roadmap feature needs_label classification |
| PL6 | plan | Upstream issue identification |
| W2 | work-on | Resolve issue spec ambiguity |

### (b) Genuine judgment calls that benefit from user input: 16 occurrences

These are points where the agent must choose between options with different trade-offs.
In non-interactive mode, the agent should follow the strongest heuristic/evidence and
document the assumption.

| ID | Skill | Summary |
|----|-------|---------|
| E2 | explore | Triage stage 1: break down vs implement |
| E3 | explore | Triage stage 2: investigation type |
| E5 | explore | Narrowing question after convergence |
| E6 | explore | Capture scope decisions |
| E7 | explore | Explore-further vs ready-to-decide loop |
| E8 | explore | Crystallize artifact type selection |
| E9 | explore | Deferred type: spike vs design |
| E10 | explore | Competitive analysis alternative |
| D3 | design | Approach selection |
| D5 | design | Deal-breaker: pivot vs accept risk |
| D6 | design | Mid-investigation decision |
| D10 | design | Post-completion routing (plan vs approve) |
| P4 | prd | Loop-back: proceed vs investigate more |
| P5 | prd | Open questions and trade-offs |
| P7 | prd | Jury significant issues |
| PL3 | plan | Decomposition strategy |
| PL4 | plan | Execution mode (single-pr vs multi-pr) |
| W1 | work-on | needs-triage: proceed vs reclassify |
| W3 | work-on | CI failure stuck |

### (c) Approval gates (user must confirm before irreversible action): 10 occurrences

These are points where the agent produces an artifact and needs confirmation before
committing to it or taking an irreversible action.

| ID | Skill | Summary |
|----|-------|---------|
| E4 | explore | Scope checkpoint |
| D7 | design | Decision review checkpoint |
| D8 | design | Implicit decision review |
| D9 | design | Final design approval |
| P3 | prd | Scope checkpoint |
| P6 | prd | Draft review/feedback |
| P8 | prd | Final PRD approval |
| PL5 | plan | Pre-creation review |
| W4 | work-on | Red CI check acceptance |

---

## Totals

| Category | Count | % |
|----------|-------|---|
| (a) Researchable | 11 | 28% |
| (b) Judgment call | 19 | 49% |
| (c) Approval gate | 10 | 26% |
| **Total** | **39** (corrected: 1 was double-counted) | |

*Note: W3 (CI failure) is categorized as (b) but behaves like an error stop in
non-interactive mode -- the agent should halt, not guess.*

---

## Cross-Cutting Observations

### 1. Empty-input prompts are the simplest to eliminate (4 instances)

E1, D1, P1, PL1 all ask "what do you want to [explore/design/specify/plan]?" when
invoked with no arguments. Non-interactive mode should require arguments or infer
from context. These are the lowest-effort wins.

### 2. Loop decisions dominate explore and prd (5 instances)

E7, P4 (main loops), plus E5/E6 (narrowing within convergence). These control whether
the workflow fans out again or moves forward. The heuristics already exist in the skill
files -- non-interactive mode just needs to follow them without asking.

### 3. Approval gates cluster at workflow boundaries (Phase 0 checkpoints and final phases)

E4/P3 (scope checkpoints) and D9/P8 (final approvals) are structurally similar. The
scope checkpoints are informational and safe to skip. Final approvals are harder --
auto-approving after all review agents pass is defensible but changes the contract.

### 4. Design has the most mid-workflow decision points (D5-D8)

Four of design's ten blocking points happen during Phases 3-4, where research surfaces
new choices. These are the hardest to automate because the questions are emergent, not
predetermined. The agent needs a "record and proceed" strategy for these.

### 5. work-on has the fewest blocks but includes the hardest one

W4 (red CI check) is the only blocking point in the entire system where non-interactive
mode should genuinely halt. This is a safety boundary, not a convenience question.

### 6. Judgment calls already have heuristics in 14 of 19 cases

Most (b)-category items include recommendation heuristics in their phase files. The
non-interactive behavior is largely "follow the recommendation automatically" -- the
infrastructure for autonomous decisions mostly exists; it just isn't wired up.
