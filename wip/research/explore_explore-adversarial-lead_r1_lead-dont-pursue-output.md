# Lead: What should a "don't pursue this" crystallize output look like as a first-class outcome?

## Findings

### The current no-artifact path conflates two distinct states

`phase-5-produce-no-artifact.md` describes a path that is appropriate when "exploration
produced no new decisions -- it confirmed what was already known, or validated that a
simple, clearly-understood task can proceed." The artifact state after this phase is
nothing new: just whatever wip/ files were already committed.

This definition is fundamentally about *low-signal exploration* -- the agent ran out of
things to investigate, or the topic was already understood. It is not about *high-signal
rejection* -- the agent investigated thoroughly and concluded the idea has fatal flaws.

These are different outcomes that currently share the same code path:

| Situation | Cause | Current handling |
|-----------|-------|-----------------|
| Explored a simple task, nothing to document | Low investigation surface | No artifact |
| Explored deeply, found idea is not viable | Active rejection decision | No artifact (wrong) |

The second case represents a decision. The crystallize-framework.md is explicit: "artifacts
capture decisions already made, not only decisions yet to be made." A "don't pursue this"
conclusion is a decision. It belongs in a permanent document.

### What the crystallize framework scores for "don't pursue"

The framework's "No artifact" signals include:
- Simple enough to act on directly
- One person can implement without coordination
- Exploration confirmed existing understanding without making new decisions
- Short exploration (1 round) with high user confidence

None of these apply when exploration concluded "don't pursue." That conclusion:
- Is not simple (it required investigation to reach)
- Is not a matter of one person acting -- it's a gate on future work
- Represents a new decision (to not build)
- May span multiple rounds

The framework's "Decision Record" deferred type is the closest match: "Which option?
(single choice)." The available alternative is a Design Doc, but that's a poor fit --
Design Docs assume something will be built.

There's no current signal/anti-signal row in the framework that captures "we decided
not to build this." This is a gap.

### The /decision skill produces a "don't pursue" analog today

The decision skill's Phase 6 output format (`phase-6-synthesis.md`) includes:

```
**Alternatives Considered**
- **<Alt 1>**: description. Rejected because reason.
```

The "chosen" alternative can be "no action" or "not feasible." The decision report
format supports a `status` field (`confirmed` vs `assumed`). A "don't pursue" finding
from /explore could map to a decision report where:
- `chosen`: "Do not proceed"
- `rationale`: why
- `rejected`: the feature/idea's alternatives
- `consequences`: what this forecloses

This already exists as a pattern in /decision -- it just isn't exposed through /explore's
crystallize path.

### What distinguishes "stopped exploring" from "decided not to pursue"

The key distinction is whether the conclusion was reached by investigation or by
exhaustion:

**Stopped exploring (current no-artifact):**
- Leads ran out before reaching a conclusion
- The idea is still theoretically viable
- The user could restart with new information
- No evidence against pursuing
- User action: close if desired, or file a new issue later

**Decided not to pursue (proposed first-class outcome):**
- Investigation surfaced specific blockers, cost-benefit failures, or demand gaps
- The idea is assessed as not worth building given what was learned
- Future reconsideration requires the blockers to be resolved, not just more exploration
- Evidence against pursuing was gathered and evaluated
- User action: close the issue; optionally write a decision record; notify stakeholders

The content difference is substantial. A "don't pursue" outcome should capture:
1. What was investigated (the scope)
2. What was found (the specific blockers or failure modes)
3. What conclusion was reached (not viable because X)
4. What would need to change to reconsider (preconditions for revisiting)
5. Confidence level (was this a close call or clearly no?)

None of these appear in the current no-artifact phase output, which only asks to
"summarize what was learned and suggest concrete next steps."

### How other projects handle "we decided not to build this"

The Architecture Decision Record (ADR) format (Nygard, 2011) was designed for
exactly this. ADRs record "status: rejected" or "status: superseded" decisions. The
Y-Statements format ("In the context of X, facing Y, we decided Z, to achieve Q,
accepting D") handles rejection naturally: "we decided not to build" is a valid
Y-statement outcome.

RFC processes (IETF, Python PEPs, Rust RFCs) have "withdrawn" and "rejected" statuses
that capture the reasoning. A rejected Python PEP includes the rejection rationale in
the document itself, so future contributors don't re-propose the same idea.

The "DACI" framework used in product management defines a "decision not to decide" as
a valid outcome that requires documentation to prevent future re-litigation.

GitHub's own RFC template includes a "Rejected approaches" section within accepted RFCs,
but some organizations also file standalone "Not doing X" decision records.

The common thread: rejection decisions are considered more important to document than
acceptance decisions, because they prevent repeated re-evaluation of settled questions.

### What user action follows a "don't pursue" decision

Three patterns exist in practice:

1. **Close the issue with a documented reason** -- the issue comment captures the
   investigation summary. This is lightweight but the reasoning is buried in comments
   and hard to find later.

2. **Write a decision record and close** -- a permanent artifact (not in wip/) captures
   the "not pursuing" decision with full reasoning. Future issues touching the same
   topic can reference it. This is the most useful pattern.

3. **Archive and leave open** -- inappropriate for a "don't pursue" conclusion. Open
   issues signal future work; leaving them open after rejecting them creates noise.

The most appropriate action depends on how likely re-litigation is. For decisions with
high re-proposal risk (common UX requests, frequently-requested features that were
rejected for non-obvious reasons), a permanent decision record is worth the overhead.
For low-stakes rejections, closing with a comment is sufficient.

### How "don't pursue" should score in crystallize

The current framework has no explicit "don't pursue" artifact type. If it were added,
its signals would be:

| Signal | Description |
|--------|-------------|
| Exploration concluded the idea is not viable | Active rejection, not lack of information |
| Specific blockers were identified and evaluated | Evidence-based, not speculative |
| Re-proposal risk is high | Others may revisit this without knowing the reasoning |
| The investigation was multi-round or adversarial | Depth of investigation warrants documentation |
| Stakeholders outside this exploration may be affected | Others need to know this was evaluated |

Anti-signals:
| Anti-Signal | Description |
|-------------|-------------|
| Exploration ran out of leads without a conclusion | This is the existing no-artifact case |
| The decision is low-stakes and unlikely to resurface | Closing with a comment is enough |
| The blocking reason is already publicly documented | A reference to existing docs suffices |

### Where it sits relative to PRD/Design/Plan

The "don't pursue" artifact is lighter than PRD or Design Doc. It doesn't spec
requirements or architecture -- it closes a question. In a scoring framework it would
rank above "No artifact" but below Plan, because:

- It requires permanent documentation (unlike No artifact)
- It doesn't require downstream sequencing (unlike Plan)
- It forecloses work rather than enabling it

It is closest in function to the Decision Record deferred type. Since Decision Record
is already identified as deferred (planned for "Feature 5"), "don't pursue" could be
added as a variant of Decision Record with a "reject" disposition rather than a "choose
between options" disposition.

## Implications

1. **A "don't pursue" crystallize type should be added** as a first-class outcome,
   distinct from "No artifact." The crystallize-framework.md needs a new entry in
   Supported Types or the deferred Decision Record type needs to be promoted sooner
   with a "reject" disposition.

2. **The no-artifact phase wording should be tightened** to explicitly exclude cases
   where exploration reached a rejection conclusion. The current text ("exploration
   produced no new decisions") is ambiguous -- a rejection is a decision.

3. **The produce phase for "don't pursue"** would write a lightweight rejection summary
   to a permanent location (not wip/) covering: what was investigated, what was found,
   why the conclusion was "not viable," and what would need to change to revisit.

4. **User action after "don't pursue"** should be explicit in the phase file:
   - Close the issue referencing the decision artifact
   - If re-proposal risk is high, offer to write a formal decision record via /decision

5. **The adversarial demand-validation lead** (the topic this was part of) fits
   naturally here: if the adversarial lead returns "no real demand" or "costs outweigh
   benefits," the explore skill should be able to crystallize to "don't pursue" rather
   than forcing the user to pick between PRD, Design, Plan, or the weak "No artifact"
   fallback.

## Surprises

- The /decision skill already handles "don't pursue" implicitly -- the decision report
  format supports a "Do not proceed" choice. The gap is in /explore's crystallize
  framework, which doesn't route to /decision for rejection decisions.

- The current no-artifact phase has a strong guard ("check wip/decisions.md -- if it
  has entries, return to Phase 4") but this guard fires on any decision, including a
  rejection decision. So a "don't pursue" finding would already redirect away from
  no-artifact today -- but there's nowhere to redirect it to. It would most likely end
  up in a Design Doc, which is wrong.

- Decision Records as an artifact type are already identified as deferred in the
  crystallize framework, with "Design Doc" as the closest alternative. But Design Docs
  are for things being built. Using Design Doc as a substitute for a rejection decision
  record creates misleading artifacts that look like planned work.

## Open Questions

1. Should "don't pursue" route to the existing /decision skill (which already handles
   rejection) or be a standalone produce path in /explore? The /decision skill adds
   significant overhead (research, alternatives, bakeoff) that may be redundant if
   /explore already did the investigation.

2. Should "don't pursue" artifacts live in wip/ (cleaned at PR merge) or in a permanent
   location like docs/decisions/? If they live only in wip/, they're lost at merge --
   which defeats the purpose of capturing the reasoning for future contributors.

3. Is the re-proposal risk heuristic (high-stakes vs. low-stakes rejection) worth
   encoding as a signal in the crystallize framework, or should it be left to the user's
   judgment?

4. Should the crystallize framework score "don't pursue" as a supported type or as a
   promoted-from-deferred variant of Decision Record? The architecture is different:
   Decision Record is "choose between options," while "don't pursue" is "reject the
   entire premise."

5. What should the adversarial demand-validation lead output look like when findings
   show *moderate* demand -- not clearly viable, not clearly rejectable? The "don't
   pursue" type only helps at the clear-rejection end of the spectrum.

## Summary

The current `phase-5-produce-no-artifact.md` conflates two distinct states -- exploration
that ran out of leads without a conclusion (genuinely no artifact needed) and exploration
that concluded the idea isn't worth pursuing (a decision that requires permanent
documentation). A "don't pursue" outcome is a first-class decision: it should produce a
lightweight rejection artifact capturing what was investigated, what blockers were found,
and what preconditions would need to change for the idea to be reconsidered -- written to
a permanent location rather than wip/, and followed by closing the issue. The crystallize
framework currently has no signal rows for this outcome, and the closest available type
(Design Doc) creates misleadingly affirmative artifacts for what is fundamentally a
rejection decision; adding "don't pursue" as a supported type (or promoting Decision
Record from deferred status with a "reject" disposition) would fill this gap.
