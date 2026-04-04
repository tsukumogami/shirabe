# Pragmatic Review: Strategic Pipeline Roadmap + PRDs

## Question 1: Is 7 features too many? Could any be merged or dropped?

**Yes -- drop to 5.** Two features don't carry their weight:

- **Feature 5 (Standardized Transition Scripts)** is scope creep. The roadmap says "retrofit existing PRD and Plan skills with transition scripts." That's not pipeline completion, that's standardization work orthogonal to the stated theme. The roadmap skill (Feature 2) already includes its own transition script. The VISION skill already shipped with one. Let each skill own its script; standardize later when there are 4+ scripts and actual divergence causes pain. **Drop Feature 5.** If you need a shared interface, write it as a 3-line convention in CLAUDE.md, not a feature with a PRD.

- **Feature 7 (Pipeline Documentation)** depends on Features 1-6 and produces a docs artifact. That's not a feature, it's a chore ticket after the real work ships. Don't plan it as a roadmap feature with its own downstream artifact pipeline. **Drop Feature 7** from the roadmap; file a single issue when the time comes.

- **Features 3 (Traceability) and 4 (Routing)** could merge. Both are small schema/config changes with shared dependency on Feature 1. But they're different enough in kind (frontmatter vs. routing table) that keeping them separate is fine. **Advisory -- no merge needed.**

**Verdict: 5 features (drop 5 and 7).** Blocking on Feature 5 (adds retrofit scope). Advisory on Feature 7.

## Question 2: Are the PRDs over-specifying?

**PRD-roadmap-skill.md:**

- **R7 (planned roadmap absorbs plan role)** and **R8 (always multi-pr)** describe /plan behavior, not /roadmap behavior. The PRD's own "Out of Scope" section says "Changes to /plan skill's roadmap consumption behavior (separate PRD)." Then R7 and R8 specify exactly that. These requirements belong in PRD-plan-skill-rework.md, not here. The Known Limitations section even acknowledges the contradiction. **Blocking.** Remove R7 and R8; reference the plan rework PRD instead.

- **R10 (minimum 2 features)** is reasonable but the enforcement mechanism is unspecified. Is this a validation check in the skill? A jury assertion? A transition precondition? Doesn't matter at PRD level -- this is fine as stated. **No finding.**

- **R6 (progress consistency invariant)** describes an invariant with no enforcement mechanism and no owner. The Known Limitations says "how completion events propagate is a /plan and /work-on concern." If it's not this skill's concern, why is it this skill's requirement? **Blocking.** Move R6 to PRD-plan-skill-rework.md where enforcement lives.

**PRD-plan-skill-rework.md:**

- **R4 (progress consistency)** and **R5 (completion cascade)** describe desired end-states but the Known Limitations section admits there's no mechanism and detection "requires polling or event-driven automation, which is outside current skill capabilities." Requirements that can't be implemented with current capabilities aren't requirements -- they're aspirations. **Blocking.** Either scope these down to what the skill can actually do (manual update instructions, or a script the user runs) or move them to a future feature.

- **R3 (consistent upstream status transitions)** codifies the current behavior for design docs and PRDs while adding roadmap behavior. The design doc and PRD rows add no new value -- they just document what already happens. **Advisory.** Trim to roadmap-only; the other rows are just restating existing code.

## Question 3: Does "planned roadmap absorbs the plan role" actually simplify things?

**No. It creates a hybrid artifact.** Today the model is clean: upstream artifacts define *what*, PLAN docs define *how and when*. Merging the plan into the roadmap means:

1. The roadmap format now has two modes: pre-planning (features only) and post-planning (features + issues table + Mermaid graph + milestone). Every consumer must handle both.
2. The transition script must know that Draft -> Active is triggered by /plan, not by the roadmap skill itself. Lifecycle ownership splits across two skills.
3. The "delete PLAN doc on completion" cascade becomes "update roadmap to Done on completion" -- different mechanism, same concept, now with two code paths.

The motivation ("PLAN doc is a thin duplicate of the roadmap") is real. But the fix is simpler than what's proposed: **don't produce a PLAN doc for roadmaps, and don't enrich the roadmap either.** Just create the GitHub milestone + issues directly from the roadmap's feature list. The roadmap already has sequencing and dependencies. /plan's value-add for roadmaps is the GitHub artifact creation, not the document production.

**Blocking.** The hybrid artifact is more complex than the problem it solves. Consider: /plan reads roadmap, creates milestone + issues, done. No document mutation.

## Question 4: Is PRD-plan-skill-rework.md premature?

**Yes.** The roadmap skill (Feature 2) doesn't exist yet. The /plan rework (Feature 6) depends on it. Writing a PRD for Feature 6 now means:

- Specifying how /plan consumes a format that hasn't been finalized
- Making design commitments (hybrid artifact, enrichment pattern) before seeing how the roadmap skill works in practice
- Two PRDs in Draft that can't both ship -- the plan rework PRD's requirements depend on outcomes from the roadmap skill PRD

**Blocking.** Defer PRD-plan-skill-rework.md until the roadmap skill ships and you've used /plan with a real roadmap at least once. The current PRD is speculating about integration problems that may not materialize.

## Question 5: Are 4 cross-cutting decisions too many?

**Yes -- 2 of 4 are either obvious or premature.**

1. **"Each document type gets its own skill"** -- Load-bearing decision that shapes all features. Keep.
2. **"Every skill uses a deterministic transition script"** -- This is Feature 5 restated as a principle. If you drop Feature 5 (per Q1), this becomes aspirational. The pattern already exists in design-doc and vision skills. Don't state the obvious. **Drop.**
3. **"Draft artifacts must not merge to main"** -- Reasonable gate. But it's a CI rule, not a cross-cutting architectural decision. File it as a single issue or put it in CLAUDE.md conventions. **Demote to convention.**
4. **"Each skill owns its completion lifecycle cascades"** -- Premature. No skill currently implements completion cascades. This is aspirational architecture for a problem you haven't hit yet. **Drop.**

**Verdict: Keep decision 1. Demote decision 3 to a convention. Drop decisions 2 and 4.**

## Summary

| # | Finding | Severity | Location |
|---|---------|----------|----------|
| 1 | Feature 5 (Transition Scripts) is standardization scope creep, not pipeline completion | Blocking | ROADMAP L185-200 |
| 2 | Feature 7 (Docs) is a chore ticket, not a roadmap feature | Advisory | ROADMAP L217-230 |
| 3 | PRD-roadmap-skill R7+R8 specify /plan behavior in a /roadmap PRD; contradicts own Out of Scope | Blocking | PRD-roadmap-skill L100-109 |
| 4 | PRD-roadmap-skill R6 defines an invariant this skill can't enforce; belongs in plan rework PRD | Blocking | PRD-roadmap-skill L95-99 |
| 5 | PRD-plan-rework R4+R5 require capabilities outside current skill infra (Known Limitations admits this) | Blocking | PRD-plan-rework L77-86 |
| 6 | Hybrid roadmap-as-plan artifact is more complex than the problem; consider milestone+issues only, no doc mutation | Blocking | PRD-plan-rework L60-68, DESIGN L252-258 |
| 7 | PRD-plan-skill-rework is premature; depends on unbuilt roadmap skill | Blocking | PRD-plan-rework (entire doc) |
| 8 | Cross-cutting decisions 2 and 4 are aspirational; decision 3 is a CI rule not an architecture decision | Advisory | ROADMAP L69-90 |
| 9 | PRD-plan-rework R3 restates existing behavior for design docs and PRDs | Advisory | PRD-plan-rework L72-75 |

**blocking_count: 6**
**advisory_count: 3**
