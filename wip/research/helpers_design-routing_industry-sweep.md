# Industry Sweep: Post-Design-Approval Routing and Complexity Assessment

Research sweep for `helpers/design-approval-routing.md`. Covers industry patterns for
post-approval workflow routing, complexity rubric validation, agent workflow chaining,
the `Ref #` vs `Fixes #` convention, and comparable frameworks.

Date: 2026-03-17

---

## 1. Post-Design-Approval Workflow Patterns

### What the industry does

No tooling or documented pattern exists specifically for AI-agent post-design-approval
routing. The concept is novel to the shirabe/tsukumogami workflow. The closest analogues
come from two directions:

**RFC/Design Doc processes at engineering firms**

Companies including Google, Uber, Airbnb, Amazon, and LinkedIn use design docs and RFCs
before implementation, but their post-approval handling is manual:

- The author updates a status field or label in a shared doc/wiki
- Stakeholders move on; there is no automated routing to a planning phase
- Hudl is the only concrete example of requiring an "implementation plan for non-trivial
  projects" as a post-approval step, but they don't define what "non-trivial" means and
  the process is human-driven
- Uber's RFC template includes an "Implementation Plan" section inside the design doc
  itself, rather than as a separate downstream artifact

The RFC literature consistently identifies complexity as the reason to require an
implementation plan — larger scope, cross-team impact, and API surface changes all
trigger more planning overhead — but no rubric is published.

**Document management approval workflow software**

Enterprise tooling (Adobe Workfront, DocuWare, PandaDoc, Cflow) handles post-approval
routing well for contract and compliance documents. Their routing logic is:

- Conditional/dynamic routing based on predefined business rules
- Post-approval triggers: archive, notify, generate next document, kick off a project
- No analogue for "assess complexity then route to planning vs. stop"

The concept of complexity-gated routing after approval does not appear in any of these
tools. They route based on document type or metadata, not implementation complexity.

### What obra/superpowers does

Superpowers (github.com/obra/superpowers, 40.9K stars) is the closest comparable agent
workflow. Its design-to-plan transition is:

1. `brainstorming` skill: drafts a design doc, user approves it
2. `using-git-worktrees` skill: activates on approval, creates isolated workspace
3. `writing-plans` skill: activates with approved design, breaks work into tasks

Critically: **there is no complexity routing step**. Superpowers always proceeds to
planning on approval; there is no "Approve only" path. The binary choice (plan or stop)
that our helper implements is not present in superpowers. Their approach is opinionated:
if you approved a design, you plan it.

The superpowers `writing-plans` skill produces tasks of "2-5 minutes each" with exact
file paths and verification steps — a much more granular output than our `/plan` command.

### Anthropic's guidance (Building Effective Agents)

Anthropic's documentation describes two relevant patterns:

**Routing pattern**: Classify inputs, route to specialized downstream tasks. "Allows
for separation of concerns and building more specialized prompts." Their examples route
by content category, not by complexity. However, the logic generalizes: after approval,
assess the design's category (simple vs. complex) and route accordingly.

**Prompt chaining with gates**: "Add programmatic gates between steps to verify the
process remains on track." This directly validates our approach: the complexity
assessment is a gate between approval and planning.

Anthropic also states: "Start with simple prompts... add multi-step agentic systems only
when simpler solutions fall short." This is the philosophical basis for our "Approve
only" path — for simple designs, skipping to manual implementation is valid.

### Microsoft Azure's orchestration patterns

Azure's AI Agent Orchestration Patterns (updated 2026-02-12) describes a spectrum:

| Level | When to use |
|-------|-------------|
| Direct model call | Single-step tasks |
| Single agent with tools | Varied queries in one domain |
| Multi-agent orchestration | Cross-functional, cross-domain problems |

Their guidance: "Use the lowest level of complexity that reliably meets your
requirements." This is the same principle our helper applies when routing simple designs
to "Approve only" — don't add planning overhead when the implementation is
straightforward.

Sequential orchestration ("also known as: pipeline, prompt chaining, linear delegation")
is the pattern our helper participates in: design → approval → [route] → plan →
implement. Azure explicitly notes this is "suited for workflows that have clear
dependencies and improve output quality through progressive refinement."

### Verdict on post-approval patterns

Our helper implements a pattern that does not exist in industry tools but is well-grounded
in published agent workflow principles (Anthropic, Azure). The complexity gate before
routing is a sound application of prompt-chaining-with-gates. The "Approve only" escape
hatch follows Anthropic's "add complexity only when it demonstrably improves outcomes"
principle.

No better-established pattern was found that we should adopt instead.

---

## 2. Complexity Assessment Rubric

### Our current rubric

| Criterion | Simple | Complex |
|-----------|--------|---------|
| Files to modify | 1-3 | 4+ |
| New tests | Updates only | New test infrastructure |
| API changes | None | Surface changes |
| Cross-package | No | Yes |

### What the industry uses

**Story points / T-shirt sizing** (Agile estimation)

Agile teams assess complexity using three core factors:
- **Complexity**: algorithmic difficulty, structural depth
- **Effort**: raw work volume
- **Uncertainty**: unknowns, risk

T-shirt sizing (XS through XXL) captures all three without reducing to a single number.
"Full API integration" is consistently placed at L or XL. "Refactoring a single function"
is S. This maps roughly to our simple/complex split.

The important finding: **"L" and above items in T-shirt sizing correlate with exactly
the dimensions in our rubric** — API surface area, cross-cutting concerns (authentication,
logging, broad integration), and file count.

**Software complexity metrics (academic/formal)**

Formal complexity metrics include:
- Cyclomatic complexity (McCabe)
- Response For a Class (RFC) — number of methods reachable from a class
- Lack of Cohesion in Methods (LCOM)
- Coupling between objects (CBO)
- Lines of code

None of these are practical for an AI agent assessing a design doc before implementation.
They require the code to exist. Our rubric is necessarily pre-implementation.

**Requirement-Based Complexity**

The CSIT research on requirement-based complexity estimation uses: productivity factors,
environmental complexity factors (ECF), and functional requirements scope. Their ECF
factors include team familiarity, tool maturity, and deployment context — none of which
are design-doc-readable.

**RFC/design doc complexity thresholds**

The closest published guidance comes from RFC differentiation:

- **Mini RFC**: minor features, enhancements, maintenance tasks, limited scope
- **Tech-Spec RFC**: spans multiple teams, introduces significant complexity, has
  long-term implications

This maps directly to our simple/complex split. The trigger dimensions in the RFC
literature: **cross-team scope** and **significant complexity** — both captured in our
rubric via "cross-package" and "files to modify."

### Missing dimensions to consider

Our rubric covers four dimensions. The industry identifies additional ones that could
be relevant:

**Risk/uncertainty**: T-shirt sizing explicitly factors in unknowns. Our rubric does not
include a "known vs. unknown territory" dimension. A 3-file change in a well-understood
module is simpler than a 3-file change in unfamiliar infrastructure.

**Data migrations**: Not mentioned in our rubric. Designs that require data schema
changes or migrations are universally high-complexity in industry practice.

**Reversibility**: Microsoft Azure's pattern guidance distinguishes low-risk vs.
high-risk actions for HITL gating. An irreversible change (schema migration, public API
removal) is a complexity signal.

**Team/domain familiarity**: RFC literature lists this as an ECF (environmental
complexity factor). A cross-package change in well-understood packages differs from one
in unfamiliar ones.

### Verdict on complexity rubric

The four dimensions (files, tests, API changes, cross-package) are sound and align with
industry practice. They correspond to the key signals used in both Agile estimation and
RFC complexity differentiation.

Two additions worth considering:

1. **Uncertainty / unknowns** — if the design involves areas the agent hasn't seen or
   describes functionality with significant ambiguity, that alone should push toward
   Complex regardless of file count.

2. **Data model changes** — schema or migration work is universally a complexity
   multiplier and currently not captured.

The 1-3 / 4+ threshold for files is not validated by any external source (no one
publishes this specific number), but the ordering is correct: more files = more complex.
The threshold is a judgment call and reasonable given our context.

---

## 3. AI Agent Design-to-Plan Workflow Chaining

### Industry patterns

The design → plan → implement chain is well-established in AI agent workflows:

**obra/superpowers**: brainstorm → [approval] → worktrees → writing-plans → subagent
execution → review → merge. Their workflow is mandatory and sequential; no routing.

**Microsoft AutoGen / magentic pattern**: For open-ended complex problems, a manager
agent builds a task ledger dynamically. Goals and subgoals are refined through
collaboration. This is analogous to `/plan` generating implementation issues.

**LangChain/LangGraph**: Prompt chaining is core to LangChain's architecture. Sequential
chains where each step's output is the next step's input are the primary pattern.

**Human-in-the-loop (HITL) approval gates**: Multiple sources confirm approval gates
between design and implementation are standard practice. Microsoft Azure explicitly
states: "Mandatory approval gates make the orchestration synchronous at that step, so
state must be persisted at these checkpoints to allow resumption without replaying prior
agent work." Our helper handles exactly this case — the design PR is the persisted state.

### Our helper vs. industry

Our helper fits the sequential orchestration pattern with an approval gate and
conditional routing. The routing (Plan vs. Approve only) is our addition; most published
workflows are opinionated toward always proceeding to plan. The "Approve only" escape
hatch is pragmatic and follows Anthropic's principle of not adding complexity unless
needed.

One difference from superpowers: they activate planning automatically after approval.
We present a choice. This is appropriate for shirabe's use case where users may have
their own planning preferences or may be using the design doc as documentation rather
than as a prelude to agent-driven implementation.

---

## 4. Ref # vs. Fixes # Convention

### GitHub's official position

GitHub supports exactly nine closing keywords: close, closes, closed, fix, fixes, fixed,
resolve, resolves, resolved. These auto-close the linked issue when the PR merges into
the default branch. No other keywords have this behavior.

`Ref #N` is **not a GitHub-recognized keyword**. It creates a cross-reference (the issue
gets a "mentioned in PR" event in its timeline) but does not auto-close. This is
confirmed behavior.

### Community conventions

The community convention for "linked but not closing" is:
- `Ref #N` — widely used, not official
- `Part of #N` — widely used for partial implementations
- `Related to #N` — widely used
- `Relates to #N` — used
- Bare `#N` mention — works but is less visible

None of these are official GitHub keywords. There is an active GitHub community request
(Discussion #17308 and #23476) for a native non-closing link keyword, but as of 2026-03
GitHub has not shipped one. The repository-level setting to prevent auto-close was
introduced but keyword-level control remains community convention only.

### How our convention holds up

Our convention: use `Ref #N` in the PR body when the design was spawned from an issue,
keep the issue open, convert to `Fixes #N` only after the design reaches "Current" status.

This is **correct and standard practice**:

- `Ref #N` does not auto-close — this is the intended behavior (the source issue stays
  open during design and implementation)
- `Fixes #N` auto-closes on merge — correct for the final state when design is "Current"
  and implementation is done
- The convert-on-promote pattern (Ref → Fixes as status changes) is not documented
  anywhere in the industry, but it is logically sound and no better alternative exists

One minor note: `Part of #N` might be slightly clearer than `Ref #N` for contributors
who don't know the tsukumogami convention, since "Part of" more explicitly signals
"this is not the full fix." However, `Ref #N` is also widely understood and shorter.
Either works; there is no meaningful difference in behavior.

The description in the helper is accurate. The only correction worth considering: the
helper could note that `Ref #N` does create a timeline cross-reference on the issue,
which is useful for tracking. This is not wrong in the current doc, just unmentioned.

---

## 5. Genericity Assessment: Is This Helper Shippable to All Consumers?

### What is workflow-specific

The helper contains two tsukumogami-specific references:
- "Suggest running `/plan <design-doc-path>`" — references a specific skill name
- "After planning, use `/implement <plan-doc-path>`" — references a specific skill name
- "Use the label swap script for issue updates" — references an internal mechanism
- The `spawned_from` frontmatter field — specific to tsukumogami's design doc schema

These are appropriate dependencies IF shirabe ships the `/plan` and `/implement` skills
as part of the plugin. If a consumer installs shirabe without those skills, the "Plan"
routing path would be a dead end.

### What is generic

The complexity rubric, the routing decision structure, and the `Ref #` vs `Fixes #`
convention are entirely generic and applicable to any GitHub-based workflow.

### Verdict

The helper is appropriate for shirabe's own consumers who have the full tsukumogami
skill set. It should not be described as a standalone utility — it is a coordination
helper that assumes `/plan` and `/implement` exist. Documentation should make this
dependency explicit.

As a plugin component, this is fine: shirabe ships all the skills together, so consumers
always have the full chain. The helper is not over-specialized; it's appropriately scoped
to the shirabe skill ecosystem.

---

## Summary Verdict

**Is the helper sound?** Yes. The design-approval-routing helper correctly implements:
- A complexity gate (prompt-chaining-with-gates, per Anthropic)
- Conditional routing (the routing pattern, per Anthropic and Azure)
- Sequential workflow participation (design → approval → plan → implement)
- `Ref #N` convention that is accurate and standard

**What is wrong or improvable:**

1. The complexity rubric is missing two useful dimensions: **uncertainty/unknowns** and
   **data model changes**. Neither is blocking, but both add signal.

2. The file-count threshold (1-3 = simple, 4+ = complex) is a reasonable judgment call
   with no external validation. It should be treated as a starting heuristic, not a
   hard rule. Consider framing it as "typically" rather than a hard cutoff.

3. The "Approve only" recommendation is always presented regardless of complexity
   assessment — both Simple and Complex designs show "(Recommended)" on Plan. This makes
   the rubric feel redundant for routing (the recommendation is the same either way).
   Consider whether "Approve only" should be marked Recommended for Simple and Plan
   marked Recommended for Complex, to make the assessment actually affect the
   recommendation.

4. The helper does not mention that `Ref #N` creates a timeline cross-reference on the
   issue. Adding this would help users understand why the convention is useful beyond
   just "doesn't close the issue."

5. Skill name dependencies (`/plan`, `/implement`) are implicit. A brief note that these
   are required would make the helper self-documenting.

**Are external resources worth adopting?**

- obra/superpowers: worth monitoring for their planning task decomposition approach
  (2-5 minute tasks with file paths and verification steps). Our `/plan` output could
  potentially adopt similar granularity. Not worth adopting their always-plan approach
  (we want the escape hatch).
- Anthropic's Building Effective Agents: already aligned. Our helper is a direct
  application of their routing and prompt-chaining patterns.
- Azure AI Agent Orchestration Patterns: confirms our sequential pattern choice. No
  adoption needed.
- GitHub issue/PR convention: confirmed correct. No changes needed.

---

## Sources

- Anthropic, "Building Effective Agents": https://www.anthropic.com/research/building-effective-agents
- GitHub Docs, "Linking a pull request to an issue": https://docs.github.com/en/issues/tracking-your-work-with-issues/using-issues/linking-a-pull-request-to-an-issue
- GitHub Docs, "Using keywords in issues and pull requests": https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/using-keywords-in-issues-and-pull-requests
- obra/superpowers GitHub: https://github.com/obra/superpowers
- Microsoft Azure AI Agent Orchestration Patterns: https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns
- Pragmatic Engineer, "Software Engineering RFC and Design Doc Examples": https://newsletter.pragmaticengineer.com/p/software-engineering-rfc-and-design
- PointFive Engineering, "Writing Technical Specifications: The Art of Tailoring RFCs": https://www.pointfive.co/engineering/engineering-blog/writing-technical-specifications-the-art-of-tailoring-rfcs
- GitHub Community Discussion #17308, "Prevent issues from being closed by merging linked PRs": https://github.com/orgs/community/discussions/17308
- GitHub Community Discussion #23476, "Feature Request: Prevent issues from being closed by merging linked PRs": https://github.com/orgs/community/discussions/23476
- ACM Software Engineering Assessment Rubric: http://ccecc.acm.org/guidance/software-engineering/rubric/
- vFunction, "What is Software Complexity?": https://vfunction.com/blog/software-complexity/
- Graphite, "Managing pull request keywords and references in GitHub": https://graphite.com/guides/managing-pull-request-keywords-and-references-in-github
- arXiv, "A Practical Guide for Designing, Developing, and Deploying Production-Grade Agentic AI Workflows" (Dec 2025): https://arxiv.org/abs/2512.08769
