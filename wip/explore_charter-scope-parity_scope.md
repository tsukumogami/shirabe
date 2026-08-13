# Explore Scope: charter-scope-parity

## Visibility

Public

## Core Question

`/scope` was overhauled in PR #260 to always walk its whole four-child chain and
reduce the artifact set afterwards, per hop, via a consolidation judgment that may
absorb an upstream artifact into the one below it. `/charter` is the sibling parent
skill over the strategic chain. The question is whether that overhaul should be
applied to `/charter` — and, underneath that, whether the two chains are actually
symmetrical enough for the question to be well-formed. The tactical chain looks
1:1:1:1 per feature. The strategic chain may not be.

## Context

- No concrete failure prompted this. The author's trigger is symmetry instinct, and
  they explicitly hold no prior view on whether cost-per-step at strategic altitude
  makes always-run wrong. This is a directional topic by the Phase 1.1a gate.
- The author's own reframe: if VISION -> STRATEGY -> COMP -> ROADMAP is not a
  1:1:1:1 relationship, then absorption — which deletes an upstream and re-points a
  single `upstream:` link — may be structurally undefined at charter altitude, and
  the question becomes whether the skill *and the CLI* are prepared for relationship
  structures other than a straight line.
- Already established by grounding (leads 1 and 2): `/scope`'s overhaul is three
  coupled moves — constant `planned_chain:`, upstream-path child invocation, and a
  three-stage per-hop consolidation judgment (absorbability mapping -> redundancy
  judgment -> carry check) whose `absorb` verdict `git rm`s the upstream and
  re-points the survivor's `upstream:`.
- Also already established: `DESIGN-scope-consolidation-over-skipping.md` Decision 9
  explicitly evaluated porting this to `/charter` and chose "change nothing," on the
  grounds that zero strategic hops are section-mappable, so the judgment could only
  ever return `keep`. It scoped that ruling to the *consolidation* half only.
- `/charter` has converted one child of four to ALWAYS (`/roadmap`, via PR #252).
  `/strategy` was already ALWAYS. `/vision` still auto-skips against a settled
  VISION; `/comp` is gated on repo visibility and skill presence.
- `/scope` introduced a vocabulary split `/charter` does not have: reduction for
  reader economy (post-hoc, content-based) versus re-entry protection (a settled
  artifact would be clobbered). Charter records both as undifferentiated
  `chain_skipped` free text.

## In Scope

- `/charter` and the strategic chain (VISION, STRATEGY, COMP, ROADMAP).
- The cardinality of every link in both chains, as observed and as permitted.
- The Rust CLI and validation rules, insofar as they encode chain shape.
- Whether Decision 9's recorded reasoning survives the cardinality reframe.

## Out of Scope

- `/execute` and any other parent skill. The author scoped this to charter only;
  findings that generalize get flagged, not pursued.
- Re-litigating the `/scope` overhaul itself.
- The adjacent defects surfaced during grounding (issues #254, #255, #257, the
  `parent_orchestration` block charter never writes, `<<ISSUE:5>>` placeholders).
  Noted for the record, not explored.

## Research Leads

1. **What exactly did PR #260 change about how `/scope` runs?** (lead-scope-overhaul)
   The mechanism has to be understood precisely before asking whether it transplants.
   Complete.

2. **How does `/charter` run today, and what did PR #252 already convert?** (lead-charter-current)
   Establishes how much of the always-run half charter has already taken, and where
   its skipping behavior still differs. Complete.

3. **What is the real cardinality between artifact types in both chains?** (lead-cardinality)
   The load-bearing lead. Census the actual artifacts and their lineage frontmatter,
   compute observed fan-out per link, and separate what the schema permits from what
   exists. If any strategic link is 1:N, symmetry with the tactical chain fails at the
   structural level rather than the cost level.

4. **Where is 1:1 baked into the CLI, the document types, and the validation rules?** (lead-cli-model)
   Skills are prose and cheap to change; the Rust data model is not. Determines whether
   a shape change is a wording problem or a schema problem, and separates hard errors
   from silently wrong results under 1:N.

5. **Does `/scope`'s skip vocabulary have a slot for reuse-under-fan-out?** (lead-skip-vocabulary)
   `/scope` names exactly two reasons an artifact may not be written: reader-economy
   reduction (post-hoc) and re-entry protection (clobber avoidance). A VISION reused by
   a second STRATEGY is arguably neither. If fan-out reuse is a third category, the
   shared parent-skill vocabulary is incomplete, and charter's `/vision` auto-skip may
   be correct behavior that is merely misfiled.

6. **How does the system already handle the fan-out it has?** (lead-existing-fanout)
   A ROADMAP sequences many features, each becoming its own `/scope` run. That boundary
   is already 1:N and already works. Whether it is modeled explicitly or handled by the
   chains simply not meeting tells us whether there is an existing pattern to extend or
   a gap that has never been tested.

7. **Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)
   See the embedded agent prompt below.

### lead-adversarial-demand agent prompt

```
You are a demand-validation researcher. Investigate whether evidence supports
pursuing this topic. Report what you found. Cite only what you found in durable
artifacts. The verdict belongs to convergence and the user.

## Visibility

Public

Respect this visibility level. Do not include private-repo content in output
that will appear in public-repo artifacts.

## Six Demand-Validation Questions

Investigate each question. For each, report what you found and assign a
confidence level.

Confidence vocabulary:
- **High**: multiple independent sources confirm (distinct issue reporters,
  maintainer-assigned labels, linked merged PRs, explicit acceptance criteria
  authored by maintainers)
- **Medium**: one source type confirms without corroboration
- **Low**: evidence exists but is weak (single comment, proposed solution
  cited as the problem)
- **Absent**: searched relevant sources; found nothing

Questions:
1. Is demand real? Look for distinct issue reporters, explicit requests,
   maintainer acknowledgment.
2. What do people do today instead? Look for workarounds in issues, docs,
   or code comments.
3. Who specifically asked? Cite issue numbers, comment authors, PR
   references -- not paraphrases.
4. What behavior change counts as success? Look for acceptance criteria,
   stated outcomes, measurable goals in issues or linked docs.
5. Is it already built? Search the codebase and existing docs for prior
   implementations or partial work.
6. Is it already planned? Check open issues, linked design docs, roadmap
   items, or project board entries.

## Calibration

Produce a Calibration section that explicitly distinguishes:

- **Demand not validated**: majority of questions returned absent or low
  confidence, with no positive rejection evidence. Flag the gap. Another
  round or user clarification may surface what the repo couldn't.
- **Demand validated as absent**: positive evidence that demand doesn't exist
  or was evaluated and rejected. Examples: closed PRs with explicit maintainer
  rejection reasoning, design docs that de-scoped the feature, maintainer
  comments declining the request. This finding warrants a "don't pursue"
  crystallize outcome.

Do not conflate these two states. "I found no evidence" is not the same as
"I found evidence it was rejected."
```
