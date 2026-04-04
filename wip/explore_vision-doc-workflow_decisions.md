# Exploration Decisions: vision-doc-workflow

## Round 1
- VISION is the only new pre-PRD artifact type (no intermediates): every candidate intermediate (opportunity assessment, strategy brief, hypothesis doc, project charter) is better served as a section within VISION at this org's scale
- Name is VISION, not Project Brief: captures project identity (long-lived, stays Active) not just a go/no-go decision (one-time snapshot)
- VISION is a supported crystallize type, not a standalone command: /explore's discover-converge loop is the right process for thesis validation; no need for /vision or /incept
- Gate VISION to strategic scope: tactical scope is a hard anti-signal; VISION degenerates into a redundant project brief in tactical mode
- Reference standards for existing deferred types ship independently: roadmap, spike report, and ADR reference skills improve existing workflows regardless of VISION; not a prerequisite
- Proceed despite supply-side demand: the maintainer is the user, and workarounds (vision repo, roadmap "Vision" section) confirm the gap exists
- PROJECTS.md lifecycle tracking deferred: too custom to this org; a generic project tracking integration (GH Projects, JIRA, etc.) would be more useful in the future

## Round 1 → Round 2 (Scope Expansion)
- Scope expanded from "add VISION type" to "define the complete strategic-to-tactical pipeline": user identified that Round 1 narrowed prematurely; VISION is one piece of a larger picture
- Crystallize decision (PRD for VISION) rescinded: the right artifact type depends on what the full pipeline looks like
- Round 1 findings on VISION remain valid as input to the broader pipeline design

## Design Phase (cross-cutting)
- Each doc type gets its own skill with creation workflow: replaces the reference-only + inline-production pattern; skills own format, lifecycle, creation, and validation in one place; /explore hands off via auto-continue; skills also work standalone
- Applies to: Feature 1 (VISION), Feature 2 (Roadmap), and any future artifact types

## Round 2
- Pipeline model: three diverge-converge diamonds (Explore/Crystallize, Specify/Scope, Implement/Ship) with 5 named transitions (Advance, Recycle, Skip, Hold, Kill)
- 5 complexity levels (Trivial, Simple, Medium, Complex, Strategic): extends existing 3-level routing at both extremes
- Traceability: add `upstream` frontmatter to Roadmap and Design Doc; cross-repo references use `owner/repo:path` with `private:` prefix
- Multiple independent features to sequence → artifact should be a Roadmap, not a PRD
- The pipeline isn't a tunnel: Kill/abandon is first-class at every stage; investment-based routing over abstract complexity labels
