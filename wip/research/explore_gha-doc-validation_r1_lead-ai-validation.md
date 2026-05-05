# Lead: AI-powered doc validation design

## Findings

### Check Types by Doc Format

Each format has a core question it answers. An LLM validator checks whether the
document actually answers that question, not just whether the sections are present.

**Design Doc** — "How should we build this?"

The document answers this by making choices between alternatives. Semantic checks:
- Considered Options has a genuine decision question (not just a list of alternatives
  without context). The question section should explain why the decision matters before
  options appear.
- Each alternative is genuinely viable. The strawman check is real work: an LLM can
  detect when a "rejected" option has no real description and the rejection rationale is
  generic ("less flexible", "more complex") rather than tied to specific decision drivers.
- Decision Outcome weaves the decisions into a coherent narrative. A bad outcome just
  lists "we chose 1B + 2A"; a good one explains how the choices interact and what a
  developer needs to know to implement.
- Security Considerations isn't bare "N/A". A completed design must either document
  risks per dimension or write an explicit justification for non-applicability. An LLM
  can distinguish "N/A" (one word, no reasoning) from "Not applicable because this
  design only produces markdown files and executes no external code."

**PRD** — "What should we build and why?"

- Problem Statement states a problem, not a solution. "We need a CLI flag" is a
  solution. "Users can't X without Y" is a problem. An LLM catches this reliably.
- Requirements are independently testable. The LLM checks for vague language
  ("appropriate", "reasonable", "as needed") that make requirements uncheckable.
- Acceptance Criteria are binary pass/fail. Subjective criteria ("the UX should be
  intuitive") are detectable.
- Out of Scope exclusions are explained. Each exclusion should say why it's excluded,
  not just list it.

**VISION** — "Should this project exist?"

- Thesis is a hypothesis, not a problem statement. The format is "We believe [audience]
  needs [capability] because [insight]." If it reads like "The problem is...", it's
  wrong. An LLM can check this pattern.
- Audience describes a situation, not a label. "Backend engineers" fails; "Backend
  engineers at mid-size companies managing 10+ microservices who maintain ad-hoc
  install scripts" passes. The distinction is whether friction is described.
- Value Proposition is one level above features. "Provides a CLI with install,
  update, and remove commands" describes features. "Reduces operational burden of
  managing developer tool installations" describes value. LLMs handle this
  abstraction-level check well.
- Success Criteria measure project outcomes, not feature completion. "Install command
  exits with 0" is a feature criterion. "10 recipes contributed by external users
  within 6 months" is an outcome.
- Non-Goals explain identity, not just scope. Each non-goal should tie back to the
  thesis to explain why the project won't do something, not just list what it skips.

**Plan Doc** — "In what order do we build this?"

- Scope Summary is genuinely one or two sentences, not a paragraph.
- Decomposition Strategy names the strategy (walking skeleton, horizontal,
  feature-by-feature) and explains why that strategy fits.
- Issue descriptions build on each other. Reading descriptions top-to-bottom should
  give a coherent narrative of the build sequence. An LLM can check whether each
  description references what came before.
- Dependency rationale: if Issue B depends on Issue A, the descriptions should make
  that dependency legible without reading issue bodies.

**Roadmap** — "What order do we build across features?"

- Features are independently describable in 1-2 sentences (not a grab-bag of
  unrelated items).
- Sequencing Rationale distinguishes hard dependencies from soft preferences.
  An LLM can catch rationale that just lists the order without explaining why.
- Features reference what artifact they need next (PRD, design, spike) when they're
  not ready for direct implementation.

### Dev-Time Content: What Should Be Absent from a Completed Doc

A "completed" doc (Accepted PRD, Accepted/Active VISION, Accepted DESIGN, Active
PLAN) should not contain:

- **Open Questions section with content.** The lifecycle rules for PRD, VISION, and
  DESIGN all require that Open Questions be resolved (section removed or emptied)
  before transitioning out of Draft. A completed doc with a populated Open Questions
  section is a lifecycle error.
- **Placeholder text.** Patterns like "TODO", "TBD", "[describe here]", "coming soon",
  or angle-bracket placeholders like `<topic>` in section bodies signal unfilled
  templates rather than authored content.
- **wip/ file references.** Document bodies should not reference `wip/` paths.
  These are working artifacts, not permanent references.
- **Draft-only sections in a non-Draft doc.** Open Questions is explicitly Draft-only
  for PRD and VISION. If it has content in an Accepted doc, that's a problem.
- **Strawman alternatives.** In completed design docs: alternatives that have a
  one-word description and a generic rejection ("less good", "not chosen") were never
  genuinely considered. These indicate the options section was filled as a formality.
- **Frontmatter/body status mismatch.** All format references explicitly call this
  out as causing silent errors in agent workflows. A completed doc with mismatched
  status fields is broken.

### Practical Constraints: Calling Anthropic API from GHA

**Secret handling.** GitHub Actions supports repository secrets natively. Setting
`ANTHROPIC_API_KEY` as a repository secret and passing it as `env:
ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}` is the standard pattern.
The existing `run-evals.yml` in shirabe already uses exactly this pattern. The
key is never echoed in logs unless you explicitly print it.

**Availability gating.** When the secret isn't set, `secrets.ANTHROPIC_API_KEY`
evaluates to an empty string. A workflow step can check: `if: env.ANTHROPIC_API_KEY
!= ''`. This is the practical gating mechanism. If the secret is absent, the
AI tier either skips cleanly or the job is conditional at the job level with
`if: secrets.ANTHROPIC_API_KEY != ''`. The latter is safer because the entire
job is skipped rather than individual steps.

**Cost.** A single document validation call with Haiku is roughly $0.001–0.003
per doc. A PR touching 3 documents costs under $0.01. Claude Sonnet is 5–10x more
expensive but still negligible at per-PR scale (under $0.10). Using Haiku for the
AI tier is the practical default; callers can override the model via workflow input.

**Latency.** Haiku response for a validation prompt is typically 5–15 seconds.
Sonnet is 10–30 seconds. For a PR with a few changed docs, the AI tier adds 30–90
seconds of wall time. This is acceptable for a non-blocking annotation job but
would be frustrating if it gates merging on a slow response.

**Rate limits.** Anthropic imposes per-minute token limits that scale with usage
tier. A single document validation call (a few thousand input tokens, a few hundred
output tokens) is well within Tier 1 limits even for parallel calls. At shirabe's
scale (a handful of contributors, PRs not every minute), rate limits are not a
practical concern.

**Streaming vs. non-streaming.** For CI validation, non-streaming is simpler: make
an API call, parse the JSON response. The `anthropic` Python SDK or a plain `curl`
call to the Messages API both work without streaming. Streaming adds complexity for
no benefit here.

**Shell vs. SDK invocation.** From a bash GHA step, `curl` to the Messages API
is the simplest approach: no runtime dependencies, no pip install. A Python script
with the `anthropic` SDK is more readable and handles edge cases (retry logic,
error parsing) better, but requires Python and a pip install step. The tradeoff:
curl is fast to add but fragile; SDK adds 10–15s of setup time but is more
maintainable.

**Model selection.** For semantic checks that don't require deep reasoning
(placeholder detection, pattern matching against quality guidance), Haiku is
sufficient. For the strawman check or "does this answer the design question", Haiku
can also handle this but Sonnet produces more nuanced feedback. A pragmatic default
is Haiku for speed and cost, with Sonnet available via workflow input.

**Prompt caching.** Quality guidance documents (vision-format.md, prd-format.md,
lifecycle.md, considered-options-structure.md) are stable and can be placed in the
system prompt or a cache-control block to reduce token costs across multiple
validation calls in the same job run. The Anthropic API supports prompt caching
for the Messages API.

### Failure Mode: Block or Annotate?

**The existing static tier always blocks.** `check-plan-docs.yml` exits non-zero
on validation failure; the PR can't merge. This is appropriate for structural
checks where the rules are deterministic and binary.

**The AI tier should annotate, not block.** Several reasons:

1. LLM judgment isn't infallible. A false positive that blocks a PR creates
   immediate friction with no recourse except disabling the check entirely.
2. AI feedback is most useful as a review comment that a human can accept or
   dismiss, not as a hard gate.
3. The ANTHROPIC_API_KEY is optional. A team without the secret enabled shouldn't
   be prevented from merging; they just don't get AI feedback.
4. Latency: if the AI job is in the required checks set, a 60-second API call
   delays every PR. As an optional annotation job, it runs in parallel and fails
   gracefully.

**The annotation mechanism.** GHA supports posting PR review comments via the
GitHub API. A step can call `gh pr review --comment` or use the Pull Request
Review API to post inline comments on specific files. This produces a visible
annotation in the PR diff without blocking merge.

**Escalation path.** The annotation approach can include a severity signal:
"WARNING: placeholder text detected in acceptance criteria" vs "INFO: some
acceptance criteria could be more specific." Only warnings would appear in the
PR summary; info-level findings would go into the job log. The repo maintainer
can decide what to escalate over time.

## Implications

**The AI tier has a clear scope.** Static checks handle structure (required
sections present, frontmatter fields valid, schema version correct, upstream
status correct). The AI tier handles semantics: is this section actually doing
what it's supposed to do? The boundary is clean.

**Each doc type needs a focused prompt, not a generic one.** The quality criteria
differ substantially across formats. A VISION prompt checks for hypothesis structure;
a PRD prompt checks for requirement testability; a design prompt checks for strawman
alternatives. Sharing a prompt across formats would weaken all of them. The practical
approach: one system prompt per doc type, each loading the relevant format reference
as context.

**The "completed doc, dev-time content trimmed" check is mostly about status
transitions.** Most of the "shouldn't be in a completed doc" items are already
gated by the lifecycle: Open Questions must be removed before Accepted. The AI
check here is a safety net for cases where the transition happened but the doc
body wasn't fully cleaned up. The static tier catches the frontmatter mismatch;
the AI tier catches the body content issues.

**Non-blocking is not optional.** Given the API key gating, the latency, and the
inherent judgment involved, the AI tier must be non-blocking. Framing it as a
"quality reviewer" rather than a "gate" aligns with how it's used during the
drafting skills (the 3-agent jury in PRD and VISION phases already runs this way).

**Haiku is sufficient for most checks.** The quality checks are mostly
pattern-matching against well-specified criteria, not complex reasoning. Haiku
handles "is this a hypothesis or a problem statement" and "does this contain
placeholder text" well. The strawman check (evaluating whether a rejected
alternative has genuine depth) might benefit from Sonnet, but not enough to
warrant the cost increase by default.

**Prompt caching pays off.** The format reference documents are stable across all
PRs. Caching them reduces per-validation token costs substantially (the input side
of each call is mostly the format reference, which is 1,000–4,000 tokens per doc
type). This matters at scale but also just makes the AI calls faster.

## Surprises

**The existing jury-validation pattern in PRD and VISION skills already maps
directly to what GHA AI validation would do.** The 3-agent jury prompts in
`skills/prd/references/phases/phase-4-validate.md` and
`skills/vision/references/phases/phase-4-validate.md` are essentially the
validation prompt templates. The GHA AI tier is the CI version of the same
quality checks that run interactively during skill execution. The criteria are
already written; they just need to be adapted for a non-interactive, single-call
context.

**The `run-evals.yml` workflow already sets the precedent for API key gating.**
It uses `ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}` exactly as the AI
validation tier would. The secret-handling pattern is already in the repo.

**Placeholder detection is partially static.** Patterns like "TODO", "TBD",
`<topic>`, `[describe here]` can be caught by `grep` before calling the API.
The static tier could handle these, and they should be there. The AI tier adds
value on top: detecting more subtle incompleteness like a section that's
syntactically complete but semantically empty ("This section covers security
considerations." — one sentence, no actual consideration).

**The PLAN doc is the most AI-resistant format.** Most PLAN quality criteria are
structural: Mermaid syntax, table formatting, dependency graph consistency. The
one AI-appropriate check is whether issue descriptions build a coherent build
narrative, which is semantic. But this is less critical than the structural
correctness, which is already handled by `validate-plan.sh`.

## Open Questions

1. **Which formats trigger AI validation?** All formats (DESIGN, PRD, VISION,
   PLAN, ROADMAP) could have AI checks, but the per-format effort varies. Should
   the first iteration focus on the highest-value formats (DESIGN strawman check,
   PRD testability, VISION thesis quality)?

2. **How does the AI tier communicate failures?** PR review comments with specific
   line references require knowing which line a problem is on, which is hard for
   semantic issues that span sections. An alternative: a single job summary comment
   listing issues by section. Which UX is better?

3. **Does the AI tier run on all PRs or only on docs-touching PRs?** The static
   tier already uses `paths:` triggers. The AI tier should too. But if a doc is
   changed in a PR that's primarily about code, should AI validation run? Probably
   yes, on the changed doc files.

4. **What model policy do downstream consumers need?** A downstream repo using the
   reusable workflow needs to pass their own `ANTHROPIC_API_KEY`. Should the
   workflow accept a model input parameter so callers can choose Haiku vs. Sonnet?

5. **How do you test the AI validation prompts?** The eval framework used for
   skills could validate the GHA AI tier too, but adapting it for non-interactive
   validation would require fixture doc examples for each quality dimension. This
   is non-trivial work.

6. **Status-aware validation.** The AI tier should only check "dev-time content
   trimmed" for docs at or past Accepted status. For Draft docs, Open Questions are
   expected. Does the workflow need to read frontmatter status before deciding which
   checks to run?

## Summary

The existing quality criteria embedded in the jury-validation phases of the PRD and
VISION skills are essentially ready-made prompts for the GHA AI tier — the work is
translating them from interactive agent instructions into single-call API prompts
that emit structured findings. The practical constraint is clear: the AI tier must
be non-blocking (annotate, not gate) because API key availability is optional, LLM
judgment has false-positive risk, and 30–90 seconds of latency is unacceptable on a
required check. The biggest open question is which specific doc types and quality
dimensions to prioritize in a first iteration, since building per-format prompts for
all five formats at once is a larger effort than starting with the two or three where
semantic checks add the most value beyond what static analysis already catches.
