# Explore Scope: scope-tactical-progression

## Visibility

Private

## Core Question

How does shirabe ship SE7 (`/scope` tactical-chain parent skill) by inheriting
SE4's parent-skill pattern where it transfers cleanly, and extending the pattern
where the tactical chain legitimately needs something different? The output
should walk SE7 on all advanceable fronts the same way the SE4 brief did for
its sibling.

## Context

- SE4 (`/charter` strategic-chain parent skill) shipped at shirabe#96 (merged
  2026-05-25). It delivered four top-level pattern references
  (`parent-skill-pattern`, `parent-skill-state-schema`,
  `parent-skill-resume-ladder-template`, `parent-skill-child-inspection`),
  the `/charter` skill body with 7 phase reference files + 3 exit-artifact
  templates, an 11-scenario eval suite, and a Strategic Chain Entry section
  in shirabe's CLAUDE.md.
- The pattern codifies seven semantic invariants (I-1 through I-7, with I-7
  being the team-lead operating discipline and I-6 acknowledged-unsatisfied
  in v1), three exit categories (full-run / re-evaluation / abandonment-forced)
  with Decision-Record having two sub-shapes, and two named substitution
  surfaces (`storage_substrate` v1=`wip-yaml-md`, `team_primitive`
  v1=`single-team-per-leader-no-nested`).
- SE6 (`/brief` skill) shipped at shirabe#95. SE3 (`/strategy`) shipped at
  shirabe#94. So the chain `/brief → /prd → /design → /plan` exists as
  separate skills today; SE7 wraps them into a parent progression.
- SE4's PR was authored by dog-fooding the same `/brief → /prd → /design →
  /plan` chain that SE7 will codify. The friction the SE4 session surfaced
  IS the validation evidence for what SE7 needs.
- SE7's roadmap entry names TWO design docs: `DESIGN-shirabe-explore-split.md`
  + `DESIGN-shirabe-progression-authoring.md`. The latter exists in shirabe
  (Component 6 added Team-Lead Operating Discipline). The "explore-split" doc
  is a mystery worth investigating.
- The SE4 roadmap entry promised "discover/converge engine extraction (the
  patterns `/explore` uses today) lands as a shared reference file SE4 and
  SE7 both pull from." Whether SE4 shipped this is unclear — possibly a hidden
  SE7 prerequisite that didn't actually close in SE4.
- Twelve observations and fourteen untapped learnings came out of the SE4
  session. A subset folded into SE4's v1 (I-7, L3, L7, L8, L13); the rest
  were deferred to SE12. Some of the deferred items may be cheap to fold
  into SE7's v1 rather than continuing to defer.
- Source-of-truth locations:
  - shirabe parent-skill references: `public/shirabe/` at `origin/main` —
    NOT the plugin cache at `/home/dgazineu/.claude/plugins/cache/shirabe/
    shirabe/0.6.2-dev/` (stale, predates #96 merge)
  - vision strategy + roadmap: this worktree at `origin/main`

## In Scope

- Pattern-reference inheritance: what `/scope` cites verbatim vs extends vs substitutes
- Tactical chain gate semantics for `/brief`, `/prd`, `/design`, `/plan`
- The hidden `DESIGN-shirabe-explore-split.md` referenced by SE7's roadmap entry
- Discover/converge engine extraction (whether shipped in SE4 or owed to SE7)
- Three-exit contract for tactical chains (where Decision Record re-evaluation
  applies in a PLAN-terminal chain)
- Input modes and resume ladder shape for `/scope` (vs `/charter`'s 10 rows)
- Learning-fold opportunities from the SE4 retrospective (which of the 14
  untapped + 7 deferred Track A items are cheap to fold into SE7 v1)

## Out of Scope

- Re-litigating pattern invariants I-1..I-7 at the abstract level (SE12)
- Authoring SE7's BRIEF/PRD/DESIGN/PLAN inside this exploration (those land
  in shirabe via the standard tactical chain once exploration crystallizes)
- Strategic re-evaluation of whether SE7 stays on the roadmap (Tactical scope
  was chosen → SE7 stays)

## Research Leads

1. **pattern-inheritance-audit — Which of SE4's four parent-skill references does `/scope` cite verbatim, which need extension, which need substitution?**
   The pattern was authored to be inherited. This lead validates that promise
   by walking each reference file against the tactical chain's needs. Output
   should be a per-reference disposition table (verbatim / extend-section /
   substitute) with concrete justification grounded in differences between
   strategic and tactical chains.

2. **tactical-chain-gates — What are the analogous child-invocation gates for `/brief`, `/prd`, `/design`, `/plan` (vs `/charter`'s /vision EITHER-signal, /comp three-condition skip, /strategy ALWAYS, /roadmap shape gates)?**
   Each child of `/charter` has a specific invocation rule. Each child of
   `/scope` likely has one too — but they're not the same rules. `/brief`
   may have a "brief-just-landed" auto-skip (we observed this during SE4).
   `/prd` is likely mandatory. `/design` may have shape-dependent invocation
   (e.g., always for complex changes, optional for thin features). `/plan`
   is terminal. Name each gate; explain why. This is the foundational
   architectural work for `/scope`'s Phase 2 logic.

3. **three-exit-tactical — How does the three-exit contract change for a tactical chain where PLAN is action-binding rather than directional?**
   `/charter`'s Decision-Record exit covered (a) existing STRATEGY holds (no
   revision needed) and (b) explicit rejection. In a tactical chain, where
   does Decision Record re-evaluation make sense? At /prd boundary if PRD
   exists and holds? At /design boundary if DESIGN exists and holds? Or is
   the tactical chain genuinely "always full-run" because PLAN is binding
   and the only meaningful exit is producing actionable issues? Where the
   strategic/tactical asymmetry concentrates lives here.

4. **input-modes-resume-ladder — What input modes does `/scope` need, and how does its resume ladder differ from `/charter`'s 10-row ladder?**
   `/charter` had 3 input modes (plain topic, brief-just-landed, existing
   strategy revision) and a 10-row resume ladder. `/scope` likely has more
   input modes (plain topic, PRD-just-landed, design-just-landed, issue from
   roadmap with needs-design/needs-prd label, exploration-just-crystallized
   handoff). Each child has multiple intermediate states (Draft, Active,
   Done), and recovery needs to resume at the right step. Quantify the
   resume-row count and enumerate input modes — these shape SKILL.md's
   structural surface.

5. **explore-split-mystery — What does `DESIGN-shirabe-explore-split.md` propose, and did SE4 ship the promised discover/converge engine extraction?**
   SE7's roadmap entry names `DESIGN-shirabe-explore-split.md` as a needed
   design. SE4's roadmap entry promised a shared discover/converge reference
   file. Investigate: does the explore-split doc exist anywhere (vision wip,
   shirabe docs, drafts, issues)? Did SE4 ship the discover/converge
   extraction (search shirabe references/, skills/, CLAUDE.md)? If neither
   shipped, is this a hidden SE7 prerequisite that needs to land first, or
   can `/scope` legitimately not consume the shared engine and still ship?
   Concrete file/PR/issue citations required.

6. **learning-fold-opportunities — Of the 14 untapped learnings and 7 deferred Track A items from the SE4 retrospective, which are cheap to fold into SE7 v1 rather than continuing to defer to SE12?**
   SE4 surfaced 12 observations (5 Track A inside-pattern, 7 Track B
   amplifier-layer) and 14 untapped learnings. Four learnings folded into
   SE4 v1 (L3 reviewer-vs-worker, L7 decoupling thesis named, L8 default-
   option wording, L13 parents don't extend children's input surfaces).
   Three observations folded (I-7 from #12, parts of #1 and #7 subsumed).
   Candidates worth folding into SE7 v1: L4 (brief Mermaid diagrams from
   the start), L9 (pattern-level requirement tagging in PRDs), L11 (outline-
   number reference brittleness in /plan), observation #11 (worktree rebase
   discipline as a runbook entry). Audit each candidate against SE7's surface
   area; recommend fold vs defer for each.

7. **adversarial-demand — Is there evidence of real demand for this, and what do users do today instead?** (lead-adversarial-demand)

   You are a demand-validation researcher. Investigate whether evidence supports
   pursuing this topic. Report what you found. Cite only what you found in durable
   artifacts. The verdict belongs to convergence and the user.

   ## Visibility

   Private

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
      references — not paraphrases.
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
