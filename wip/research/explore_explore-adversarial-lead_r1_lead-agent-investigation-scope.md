# Lead: Adversarial Agent Investigation Scope

## Findings

### How the six demand-validation questions map to code-readable sources

The scope file frames six questions from office-hours tooling: is demand real? what
do people do today? who specifically asked? what behavior change counts as success?
(plus two implied: is this already built? is this already planned?). Each maps to
concrete sources an agent can read in a typical code-oriented repo.

**Is demand real?**
Primary source: GitHub issues. An agent can search for open issues that express the
same need, look for "+1" comments or "this is blocking me" language, count how many
distinct reporters filed related requests, and check whether the issue is linked from
PRs or referenced in other discussions. In shirabe specifically, issue #9 itself
demonstrates this pattern: it was filed with a clear goal statement, acceptance
criteria, and a `needs-design` label — all signals the need is considered real enough
to track. Absence of linked duplicates or referenced work-arounds is also a signal
(demand may be narrow).

The credibility test: multiple distinct issue filers > one author filing many issues.
Linked PRs that tried to address the same need and were closed > issue thread
speculation. Labels like `needs-design` or `in-progress` assigned by maintainers >
user-added `enhancement` labels.

**What do people do today instead?**
Primary sources: existing code + docs. An agent can look for workarounds already in
the codebase (commented code, TODO notes, duplicated logic that a proposed feature
would unify), check whether the README or docs advise users to do something manually
that the feature would automate, and scan closed issues for "workaround: do X instead"
responses. In shirabe, for example, the absence of any adversarial framing in
phase-1-scope.md or phase-2-discover.md shows exactly what users do today: they get
no null-hypothesis challenge.

Credibility: documented workarounds in official docs are high-confidence evidence.
Code comments like `# TODO: this should be automated` are medium-confidence. PR review
threads suggesting a workaround are lower-confidence but still readable.

**Who specifically asked?**
Primary sources: issue reporters, PR authors, comment threads. An agent can list the
unique GitHub handles who filed related issues or commented requesting the feature,
check whether any are maintainers vs. external contributors (maintainer demand implies
different weight), and look at PR review conversations for "I wish this did X" notes.

Credibility: named contributors with linked context > anonymous "+1". Maintainer
filed > external filed. Issue referenced in a merged PR > standalone open issue.

**What behavior change counts as success?**
Primary sources: acceptance criteria in issues, test files, and CI definitions. An
agent can read the ACs directly from the issue (issue #9 has five explicit ACs),
check whether any existing tests define the expected outcome, and look at CI configs
to see if any checks would directly validate the behavior. If no ACs exist, the
absence itself is a finding (demand may not be well-defined enough to pursue).

Credibility: ACs in the issue body written by the author > inferred from issue title.
Existing failing tests that would pass with the change > no test baseline.

**Is this already built?**
Primary sources: existing code and docs. An agent searches the codebase for the
proposed functionality. In shirabe's case, a search for adversarial, demand-validation,
or null-hypothesis in the skills directory would confirm the feature doesn't exist yet.
Checking phase-1-scope.md for conditional lead injection logic, and phase-2-discover.md
for any special-casing of directional topics, directly answers this.

Credibility: code search with negative result + doc search with negative result = high
confidence not built. Finding partial implementation = medium (partially built; need
context on why it stopped).

**Is this already planned elsewhere?**
Primary sources: ROADMAP files, design docs, open issues with `in-progress` or
`planned` labels, PR history for related branches. In shirabe, the `/explore`
skill's references directory holds no design doc for adversarial leads. The issue
tracker shows issue #9 in OPEN state with `needs-design` label — planned but not
designed. A DESIGN doc at `docs/designs/DESIGN-explore-adversarial-lead.md` (named
in the ACs) doesn't exist yet, confirming it's open work.

### What sources exist in a code-oriented repo

Ranked by availability and signal strength:

1. **GitHub issues** — highest value. Contain stated demand, AC definitions, prior
   discussion, and maintainer classification signals (labels, assignees). Always
   present in active repos.
2. **Existing code and tests** — definitively answers "is it built?" and "what do
   users do today?" without speculation.
3. **Docs and README** — answers "what does the project commit to?" and surfaces
   documented workarounds.
4. **PR history (merged and closed)** — shows what was recently attempted, rejected,
   or deferred. Closed PRs with "not now" comments are direct evidence of deferred
   demand.
5. **Design docs and ROADMAP** — answers "is this already planned?" High credibility
   if they exist; absence is meaningful only if the project normally maintains these.
6. **Commit messages and branch names** — lower signal, but occasionally shows
   historical attempts at similar features.

Sources an agent cannot read without external access: user interviews, support
tickets, survey data, analytics. The adversarial lead is structurally limited to
the repo-readable evidence. This is a feature, not a limitation — it keeps findings
grounded in durable artifacts rather than hearsay.

### What makes findings credible vs. speculative

Credible:
- Direct quotes or file paths cited ("phase-2-discover.md contains no conditional
  branching on topic type")
- Negative search results with explicit queries stated ("searched skills/ for
  'adversarial', 'null-hypothesis', 'demand-validation'; no matches")
- Maintainer-authored labels, ACs, or comments (vs. requester self-assessment)
- Cross-references: same need appearing in multiple independent issues

Speculative:
- "Users probably want this because..."
- Inferring demand from absence of complaints ("nobody complained, so it's fine")
- Extrapolating from one data point to a pattern
- Treating a proposed solution in an issue as evidence the problem exists

The line: speculative findings draw conclusions about user behavior or future
outcomes without citing durable artifacts. Credible findings report what the
artifacts say and let the convergence phase interpret meaning.

## Implications

### The adversarial agent has a concrete, bounded investigation scope

The six demand-validation questions are not abstract — each maps to a specific
source type the agent can read. The agent doesn't need user interviews or external
data. The investigation is: search issues, read ACs, check existing code, read docs,
check PR history. This is a normal research task, not a fundamentally different kind
of work from other Phase 2 agents.

The agent prompt template from phase-2-discover.md works for this lead with one
addition: explicit grounding instructions to cite only what it found, not what it
inferred. The existing "cite file paths and specific content" instruction is a good
foundation; the adversarial lead just needs to hold this standard more strictly
because the stakes of a false negative (suppressing a good idea) are high.

### The agent needs an honest-assessment posture, not a skeptic posture

The risk of reflexive negativity is real. An agent instructed to "challenge this" will
find ways to challenge it even when the evidence doesn't support doing so — because
the instruction itself frames skepticism as the expected output.

The correct framing is: "Investigate whether evidence supports pursuing this. Report
what you found. If evidence is thin, say so. If evidence is strong, say so." The
agent is a reporter, not an advocate for either pursuing or abandoning. The verdict
belongs to convergence and the user, not to the adversarial agent itself.

Concrete operationalization: the agent should report a finding for each of the six
questions, with a confidence indicator (high/medium/low/absent), and explicitly flag
where evidence was absent rather than extrapolating. "I searched for workarounds in
the docs and found none" is a finding; "therefore users don't need this" is an
overreach.

### "Demand isn't validated" vs. "demand is validated as absent"

These are meaningfully different conclusions and the adversarial lead should
distinguish them:

- **Demand not validated**: the evidence is thin or absent, but absence of evidence
  is not evidence of absence. The right response is flagging the gap, not recommending
  abandonment. Further investigation — or a user response in convergence — could
  surface what the agent couldn't find in the repo.

- **Demand validated as absent**: positive evidence that demand doesn't exist or was
  already considered and rejected. A closed PR with "not building this, here's why"
  is positive evidence. A design doc that explicitly de-scoped the feature is positive
  evidence. These warrant a stronger "don't pursue" signal than merely missing issues.

The adversarial lead's findings need a calibration section that states which
conclusion applies, because the crystallize path branches on this distinction. Thin
evidence recommends another discover round or user clarification. Positive evidence
of absence recommends the "don't pursue" crystallize outcome.

### The "no artifact" path in crystallize currently covers "don't pursue" as a fallback, not a first-class outcome

The current phase-5-produce-no-artifact.md says: "Only appropriate when exploration
produced no new decisions — it confirmed what was already known, or validated that a
simple, clearly-understood task can proceed." This framing is for low-stakes confirmed
work, not for adversarial demand-validation conclusions. A finding that "demand is
absent" is a new decision — it requires capturing why so future contributors don't
re-open the same question. The current "no artifact" path explicitly says no commit
is needed, which would lose the adversarial finding entirely.

This means "don't pursue this" needs a distinct output format that produces a
durable artifact (likely a decision record) explaining why the topic was abandoned
with evidence. The crystallize framework's deferred types include "Decision Record"
as closest to "Design Doc," but the scoring table doesn't currently include demand-
absence as a signal. This is a gap the design doc will need to address.

## Surprises

**The investigation scope is narrower than it first appears.** The six demand-
validation questions sound open-ended, but in a code-oriented repo they reduce to:
search issues, read code, read docs, read PR history. The adversarial agent's work
is structurally similar to other Phase 2 agents. This is reassuring — it means the
agent can use the same prompt template without major rearchitecting.

**The current "no artifact" path actively works against preserving adversarial findings.**
Its guidance ("no commit needed") would cause the adversarial agent's findings to
be cleaned with wip/ before the PR merges. If the adversarial lead concludes "don't
pursue this," that conclusion needs a permanent artifact or it will be re-discovered
and re-investigated by future contributors. The current system has no path for this.

**Reflexive negativity is a prompt-engineering problem, not a structural one.**
The framing of the agent's instructions determines the failure mode. "Challenge this
topic" -> reflexive negativity. "Report what evidence you found for and against
demand" -> honest assessment. The fix is in the adversarial lead's prompt, not in
the Phase 2 dispatch logic.

**Phase 2 already has the right infrastructure.** The agent prompt template, file
naming, and parallel dispatch all work for an adversarial lead. The only change
needed is: inject this lead automatically for directional topics (a Phase 1 concern),
and add a crystallize path that handles "demand absent" as a distinct outcome (a
Phase 4/5 concern). Phase 2 itself needs no changes.

## Open Questions

1. **What is the right confidence vocabulary?** If the adversarial lead uses
   high/medium/low/absent for evidence confidence, what threshold maps to each
   crystallize recommendation? This needs a decision so convergence doesn't require
   re-adjudicating confidence levels.

2. **How does the adversarial lead interact with multi-round discovery?** If Round 1
   finds thin demand evidence, does the adversarial lead re-run in Round 2 with a
   tighter brief, or does it only run in Round 1? Running it repeatedly risks
   accumulating bias toward negativity over iterations.

3. **Who owns the "demand validated as absent" decision record?** The adversarial
   lead produces evidence. The design doc (AC: "reaches accepted status") captures
   the decision. But there's a gap: if exploration concludes don't-pursue before
   reaching the design doc phase, what artifact format captures why?

4. **Can the adversarial lead validate demand positively, or only challenge it?**
   The framing so far is demand challenge. But if the agent finds five issues filed
   by distinct users with clear ACs and a maintainer label, that's positive demand
   evidence. Should the adversarial lead also return "demand is well-evidenced;
   proceed with confidence," and if so, how does that affect the crystallize scoring?

5. **Does thin evidence justify "don't pursue" or "needs more information"?** This
   distinction matters for the crystallize outcome. The current framework doesn't
   distinguish these — both currently resolve to "another round" or "no artifact."

## Summary

An adversarial agent in a code-oriented codebase has a concrete, bounded investigation
scope: the six demand-validation questions map directly to readable sources (issues,
existing code, docs, PR history), and the agent's work is structurally similar to
other Phase 2 leads. The critical design decisions are not in Phase 2 but at the
edges: how Phase 1 injects the lead for directional topics, and how Phase 4/5 handles
the "demand validated as absent" outcome, which the current "no artifact" path doesn't
support (it's designed for confirmed-simple work, not deliberate abandonment, and
explicitly avoids producing a durable artifact). The biggest open question is what
distinguishes "demand not validated" (thin evidence; needs another round) from "demand
validated as absent" (positive evidence of rejection), since the crystallize path
branches on that distinction.
