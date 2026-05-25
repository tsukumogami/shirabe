# Lead: explore-split-mystery

## Findings

**Q1: Does `DESIGN-shirabe-explore-split.md` exist anywhere?**

No. Verified by exhaustive search:

- **Vision worktree** (`/home/dgazineu/dev/niwaw/tsuku/tsuku-3/.niwa/worktrees/vision-ce182769`): no file matching `*explore-split*` in `docs/designs/{current,proposed,superseded}/`, no occurrence in any committed file.
- **Shirabe origin/main** (`git ls-tree -r origin/main --name-only`): no file matching `*explore-split*` anywhere; the design docs present are `DESIGN-shirabe-brief-skill.md`, `DESIGN-shirabe-progression-authoring.md`, and `DESIGN-shirabe-strategy-skill.md` (no charter design, no scope design, no explore-split design).
- **GitHub** (`gh search issues "explore-split" --owner tsukumogami`): one match — `tsukumogami/vision#495 "docs(design): /scope tactical progression"`, the SE7 design tracking issue, which references the *future* `DESIGN-shirabe-explore-split.md` as its deliverable. The doc itself does not exist.
- **WIP**: no draft in `vision/wip` or `shirabe/wip` (no `wip/` directory in shirabe origin/main).

The roadmap reference in `docs/roadmaps/ROADMAP-shirabe-evolution.md:212` (`DESIGN-shirabe-explore-split.md`) is a forward-looking placeholder; the document is unwritten.

**Q2: Did SE4 ship the discover/converge engine extraction?**

No — and this was a deliberate design choice, not an oversight. The reversal is documented inside SE4's own design doc.

- `shirabe/references/` on origin/main contains the original 5 cross-skill references (`cross-repo-references.md`, `decision-*.md`, `pipeline-model.md`, `wip-hygiene.md`) PLUS the 4 new parent-skill-pattern files SE4 added (`parent-skill-pattern.md`, `parent-skill-state-schema.md`, `parent-skill-resume-ladder-template.md`, `parent-skill-child-inspection.md`). There is **no** `references/discover-converge.md` or similar engine reference.
- `DESIGN-shirabe-progression-authoring.md` Decision 1 (`docs/designs/current/DESIGN-shirabe-progression-authoring.md:284-345`) explicitly chooses "Hybrid extraction": ship the 4 new pattern-level references at top-level `references/`, **leave the existing `/explore` discover/converge engine in its current location** (`skills/explore/references/phases/{phase-2-discover,phase-3-converge}.md`). The doc says: *"Moving the engine is deferred — the PRD explicitly frames extraction as a follow-on PR, and no current cross-skill consumer demands the refactor."* The "Full top-level extraction" alternative was named and rejected.
- `/charter` Phase 1 (`skills/charter/references/phases/phase-1-discovery.md` §1.3) ratifies the choice in skill prose: *"Per Design Decision 1, the engine stays at its current location; parent skills that need a discovery phase point cross-skill rather than copying the engine into their own directory. `/charter`'s Phase 1 loads both files when running the discovery conversation and adapts the engine's prose to the charter-specific context."*

In short: SE4 chose to *point cross-skill at* `/explore`'s engine rather than *extract* it. The roadmap text in vision (`ROADMAP-shirabe-evolution.md:163-165, 396-398`) still describes the original extraction promise; the shipped reality is cross-skill pointing.

**Q3: Did /charter need the engine extraction? Or did it sidestep?**

/charter explicitly needed and used the engine — it just consumed it by pointing rather than by extracted reference. Phase 1's "Discover / Converge Loop" section (§1.3) loads `skills/explore/references/phases/phase-{2-discover,3-converge}.md` directly. So the engine *was* shared cross-skill; the only thing that didn't ship was a third copy at `references/discover-converge.md`.

The asymmetry with the roadmap: SE4's roadmap entry promised an *extracted shared reference file*; what actually shipped is *cross-skill pointing*. Functionally equivalent for the consumer (`/charter` reads the same files); semantically different (no engine file at the `references/` root).

**Q4: What's the candidate split boundary for /explore?**

Reading `/explore`'s SKILL.md and phase files:

- `/explore` runs Phase 0 (setup) → Phase 1 (scope) → Phase 2 (discover) → Phase 3 (converge) → Phase 4 (crystallize) → Phase 5 (produce-X).
- The "discover/converge engine" = Phases 2 + 3 (research-agent fan-out, evidence gathering, candidate framing, convergence on intent).
- The "crystallize menu" = Phase 4 + the 10 Phase-5-produce-* variants (PRD, design, plan, vision, roadmap, decision, rejection-record, deferred, no-artifact). Today `/explore` is the artifact-type routing advisor — it owns the full menu.

SE7's planned "soft split" (per vision issue #495 body): `/scope` shares the discover/converge engine but narrows the crystallize menu to tactical artifacts (brief, PRD, design, plan). The hard split (disjoint menus where `/explore` loses cross-altitude routing) is rejected per Non-Goals — `/explore`'s cross-altitude routing (VISION↔PRD, VISION↔Rejection) is actively used and must remain.

So the candidate split boundary is at **entry-point + Phase 4 crystallize menu**, not at the discover/converge engine. `/scope` would invoke its own entry mode, share Phases 2-3 by pointing at `/explore`'s files (same idiom `/charter` uses), and own a tactical-only Phase 4 menu.

## Implications

**For SE7's design surface:**

1. **The engine "extraction" hard prerequisite is dissolved.** SE7 doesn't need a new `references/discover-converge.md` to ship — `/charter` proved that cross-skill pointing into `skills/explore/references/phases/` is the working idiom. `/scope` can follow the same pattern verbatim. The roadmap text describing "extraction" is stale; the actual contract is "cross-skill point with parent-specific adaptation prose."

2. **`DESIGN-shirabe-explore-split.md` is genuinely needed but its surface is narrower than the name suggests.** What actually needs designing for SE7:
   - `/scope`'s entry-mode (topic-slug, argument forms, child-doc inspection)
   - `/scope`'s Phase 1 discovery prose (adapted for tactical context)
   - `/scope`'s Phase 4 crystallize menu (tactical-only artifact set: brief, PRD, design, plan)
   - The interaction with `/explore`'s cross-altitude routing (when does `/explore` redirect to `/scope`, when does `/scope` redirect back?)
   - The integration of `/brief` (shipped SE6) as a Phase-2-equivalent input to `/scope`'s tactical chain
   
   What does NOT need designing: a new discover/converge engine file, a re-extraction, or a refactor of `/explore`'s Phase 2/3.

3. **The design name is misleading.** "explore-split" implies splitting `/explore`'s engine; the actual work is "author `/scope` as the second parent skill consuming `/charter`'s pattern + cross-pointing at `/explore`'s engine." Consider renaming to `DESIGN-shirabe-scope-skill.md` for parallelism with `DESIGN-shirabe-strategy-skill.md`, `DESIGN-shirabe-brief-skill.md`, `DESIGN-shirabe-charter-skill.md` (which doesn't exist yet — see Surprises).

4. **SE7 can ship without authoring a separate "engine extraction" doc.** It can author `DESIGN-shirabe-explore-split.md` (or renamed equivalent) and treat the engine question as resolved by reference to Decision 1 of `DESIGN-shirabe-progression-authoring.md`. No prerequisite design needs to land first.

## Surprises

1. **`DESIGN-shirabe-charter-skill.md` does not exist either.** SE4 shipped (`shirabe#96`, merged 2026-05-25) without an under-`docs/designs/current/` design doc dedicated to `/charter` — the design content lives in `DESIGN-shirabe-progression-authoring.md` (the shared pattern doc) plus `BRIEF-shirabe-charter-skill.md` and `PRD-shirabe-charter-skill.md`. The roadmap names `DESIGN-shirabe-progression-authoring.md` as SE4's needed design, and it shipped. This is an undocumented pattern: parent-skill features can ship with the *shared pattern design* serving as their primary design doc plus a BRIEF/PRD pair for skill-specific content.

2. **Roadmap text is stale relative to shipped reality.** The SE4 entry still describes the engine extraction as a deliverable ("Discover/converge engine extraction…lands as a shared reference file SE4 and SE7 both pull from"). The shipped Decision 1 explicitly rejected that approach. The SE7 entry inherits the staleness ("Shares the discover/converge reference file with SE4 from the core-layer extraction"). Both entries describe a refactor that did not happen.

3. **The vision tracking issue (#492) for SE4's design also describes the unfulfilled promise.** Issue body: *"Must deliver: the parent-skill pattern that `/scope` reuses…the discover/converge reference file extracted from `/explore` lands here and gets reused by `/scope`."* The merged design doc explicitly rejected the extraction. The acceptance criteria on #492 don't enforce extraction (they only require the design doc to exist and follow schema), so #492 could still close cleanly — but the issue body misrepresents what shipped.

4. **`/charter` Phase 1's "Discovery" overloads the term.** It runs both (a) repository visibility detection and child-doc inspection (which is /charter-specific) AND (b) the discover/converge loop (which points at /explore's files). Anyone scanning for "did the engine get extracted?" by skimming charter Phase 1 might miss the cross-skill pointing because the file name and prose both say "Discovery."

5. **`DESIGN-shirabe-explore-split.md` and `DESIGN-shirabe-progression-authoring.md` are jointly named as SE7's prerequisites in the roadmap** — but `DESIGN-shirabe-progression-authoring.md` already shipped with SE4 and includes the substrate `/scope` needs. So *one of SE7's two named design prerequisites is already in `current/`*. SE7 only needs to author the second.

## Open Questions

1. **Should `DESIGN-shirabe-explore-split.md` be renamed?** Given the engine extraction was rejected and the design's actual content is "`/scope`'s skill body + entry/menu split from `/explore`," a name like `DESIGN-shirabe-scope-skill.md` would parallel the existing `DESIGN-shirabe-strategy-skill.md` / `DESIGN-shirabe-brief-skill.md` / (missing) charter design. Counterargument: the explore-split framing captures the cross-skill routing question (when does `/explore` send to `/scope`?), which `DESIGN-shirabe-scope-skill.md` would have to cover anyway.

2. **Should /charter ship a `DESIGN-shirabe-charter-skill.md` retroactively, or is the pattern "shared design + BRIEF + PRD" intentional precedent?** SE7 can either follow SE4's apparent precedent (no skill-specific design; BRIEF + PRD do the work, with the shared pattern design as substrate) or pioneer the parallel structure (DESIGN-shirabe-scope-skill.md alongside the shared progression-authoring design). The roadmap text suggests the latter; SE4's shipped reality is the former.

3. **Should the roadmap be updated to reflect that engine extraction was rejected?** SE4 is marked Done but the description still promises an extraction that didn't ship. SE7's entry still inherits the language. A documentation-only update could clarify that "shared discover/converge reference" means cross-skill pointing, not file extraction. Alternatively, the roadmap could be left alone (since SE4 is closed and SE7 will produce its own design).

4. **Is "soft split" (vision issue #495 body language) the right framing in the design doc, given that no engine moved?** The "split" is purely at entry-mode and Phase 4 crystallize menu; Phase 2 and Phase 3 are unchanged for `/explore` and consumed-by-pointing for `/scope`. The shipping reality is closer to "extend the parent-skill pattern with a tactical-menu variant" than to "split `/explore` in two."

## Summary

`DESIGN-shirabe-explore-split.md` does not exist anywhere on disk or in any draft — it is a roadmap placeholder; vision issue #495 is its tracking issue. SE4 deliberately rejected the discover/converge engine extraction (`DESIGN-shirabe-progression-authoring.md` Decision 1, "Hybrid extraction"), choosing cross-skill pointing instead — and `/charter` consumes `/explore`'s engine by pointing, so the substrate `/scope` needs already exists, meaning SE7 has **no hard prerequisite** blocking it and the explore-split design's actual scope is narrower than its name suggests (`/scope`'s entry + Phase 4 menu, not an engine refactor). The biggest open question is whether to rename the design doc and/or update the roadmap to match shipped reality before /scope authoring begins.
