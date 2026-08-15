# Explore Scope: multi-pr-plan-decoupling

## Visibility

Public

## Core Question

Multi-pr PLAN execution mode currently fuses three independent decisions into
one mode flag: whether a plan *can* land in a single PR, whether it *should*,
and how the resulting work is *tracked*. The question is whether these should
be separated -- with the "can" gate derived near-deterministically from the
design's decomposition, the "should" gate bound to a repo-level preference, and
the tracking mechanism (GitHub issues, milestones, or neither) bound to its own
preference rather than hardcoded to multi-pr.

## Context

Shirabe has matured its separation of intent from mechanics across most skills.
The multi-pr PLAN path has not kept up. Two specific complaints from the author:

**Conflated gates.** The reason a plan is multi-pr should be either "cannot fit
one PR" or "should not fit one PR." The *cannot* case is close to deterministic:
given a well-formed DESIGN with an understood decomposition, the agent can judge
whether the work fits a single PR. The *should* case is a judgment call about
review ergonomics that varies by org. In tsukumogami the author is the sole
contributor and prefers every plan that can be one PR to be one PR; an org with
many reviewers may prefer small atomic increments for reviewability. Both are
legitimate. The preference should be repo configuration that the skill honors
and the tooling enforces (or at least hints back for a double-check), so that a
multi-pr plan in a "prefer-single" repo is trustworthy evidence that no other
option existed.

**Conflated tracking.** Nothing about landing code across several PRs requires
GitHub issues and milestones. That coupling exists only because the skill is
wired that way. Tracking mechanism should be a preference too. Boundary the
author already accepts: issues and milestones only make sense for ROADMAP and
multi-pr PLAN docs -- never for coordinated or single-pr PLANs, because those
never reach the main branch and so leave nothing worth persisting a reference
to. Additionally, even in a repo that opts into issues, milestone-worthiness may
be a separate judgment: a plan forced into multiple PRs by mechanical necessity
may not represent a project milestone at all.

The author raised these as one theme while explicitly inviting a split into two
issues, and flagged that the relationship between them is the point.

## In Scope

- The single-pr / multi-pr / coordinated mode decision in `/plan` and `/execute`
- Where GitHub issue and milestone creation is wired, and what downstream
  consumers depend on those artifacts existing
- Repo-level configuration surfaces for a PR-decomposition preference and a
  work-tracking preference
- Whether "milestone-worthy" is a judgment separable from "multi-PR"
- Whether the "can fit one PR" gate can be made deterministic enough to trust
- Whether this is one design or two

## Out of Scope

- Changing the coordinated multi-repo execution model itself
- ROADMAP-level milestone semantics beyond what is needed to answer the
  milestone-worthiness question
- Redesigning issue body format or acceptance-criteria templates
- Any change to `/work-on`'s single-issue path

## Research Leads

1. **Where is the single-pr / multi-pr / coordinated decision actually made today, and what inputs feed it?**
   Need the real control flow before proposing to split it. Covers `/plan`
   phase files, `/execute`, and any mode markers in PLAN frontmatter.

2. **Where does issue and milestone creation get wired, and what downstream consumers depend on those artifacts existing?**
   Determines the blast radius of making tracking optional. `/execute`,
   `/work-on`, `/inflight`, completion cascade, and the plan scripts all
   potentially read GitHub state.

3. **What repo-level configuration surfaces already exist in shirabe, and which would a decomposition preference and a tracking preference naturally bind to?**
   The answer should reuse an existing mechanism rather than invent a third
   config channel. Covers CLAUDE.md headers, `team.yaml`, skill extensions,
   and any settings files.

4. **What has the existing design corpus already decided here?**
   Several designs look adjacent -- plan-skill-rework, populate-issueless-default,
   doc-vs-github-state-reconciliation, execute-skill, chain-cardinality. Prior
   decisions may already constrain or partly answer this.

5. **Can the "can this fit one PR" gate be made near-deterministic from a DESIGN's decomposition, and what would the rule be?**
   The author's trust in multi-pr plans depends on this. Need the concrete
   signals (issue count, file overlap, dependency depth, cross-repo spread)
   and whether they are actually available at plan time.

6. **Is "milestone-worthy" separable from "multi-PR", and how are milestones used today across ROADMAP versus PLAN?**
   The author suspects a plan can need several PRs without being a milestone.
   Need to know whether milestones currently carry meaning beyond grouping.

7. **What does the tooling enforce or validate today around plan mode and issue creation?**
   The proposal says tooling should enforce or hint. Need to know what
   validation already exists in `scripts/`, CI doc-validation, and skill-level
   gates, so the new preference has somewhere to land.
