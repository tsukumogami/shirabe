# Lead: input-modes-resume-ladder

## Findings

### Grounding: `/charter`'s shape

Source files inspected (extracted from `public/shirabe` at `origin/main`, commit `05f0eda` — the SE4 merge):

- `skills/charter/SKILL.md` — Input Modes section (lines 45-77) and Resume Logic citation (lines 147-177).
- `skills/charter/references/phases/phase-resume.md` — the concrete 10-row ladder body (lines 27-40).
- `references/parent-skill-resume-ladder-template.md` — the universal 9-row template with 6 meta-rows (1-4, 8-9) and 3 body slots (5-7).
- `references/parent-skill-pattern.md` — seven invariants, three exit paths, the seven required SKILL.md structural elements (lines 241-273).
- Child SKILL.md files at `skills/{brief,prd,design,plan}/SKILL.md` for the tactical chain's per-child lifecycles.

**Counting `/charter`'s input modes.** SKILL.md `## Input Modes` (lines 45-77) lists exactly **two** in `$ARGUMENTS` shapes: (1) Empty → cold-start prompt; (2) Non-empty → slug regex check. The lead's "3 input modes" framing in the scope file is functional rather than syntactic — `/charter` derives the `brief-just-landed` and `existing strategy revision` modes from Phase 1 discovery (scanning child docs at known paths) and from the resume ladder's status-aware re-entry rows (rows 5-6), not from $ARGUMENTS. Path-as-upstream is explicitly rejected at Phase 0 (lines 65-72): `/charter docs/visions/VISION-foo.md` fails the slug regex and stops. **The input-mode surface is narrow on purpose.**

**`/charter`'s 10-row ladder fills 3 body slots into 4 body rows.** Phase-resume.md lines 15-21 explain: rows 1-4 + 9-10 are the pattern meta-ladder; rows 5-6 expand template-slot-5 (status-aware re-entry: Accepted vs Draft STRATEGY); rows 7-8 expand template-slot-6 (partial-child-run: `/strategy` vs `/vision`); template-slot-7 (feeder-doc-detected) is unfilled because `/charter` has no feeder. So `/charter`'s 10 = 6 meta + 4 body.

### Tactical-chain artifact lifecycles (per-child SKILL.md citations)

| Child | Statuses authored | Path | Source citation |
|---|---|---|---|
| `/brief` | Draft → Accepted → Done | `docs/briefs/BRIEF-<topic>.md` (no directory move) | `skills/brief/SKILL.md` lines 51-56, 152-153, 173-180 |
| `/prd` | Draft → Accepted | `docs/prds/PRD-<topic>.md` | `skills/prd/SKILL.md` lines 99-106, 138-139 |
| `/design` | Proposed → Accepted (then `current/`) → Archived | `docs/designs/DESIGN-<topic>.md`, `docs/designs/current/`, `docs/designs/archive/` | `skills/design/SKILL.md` lines 109-114, 167-179, 192 |
| `/plan` | Draft → Active → Done (multi-pr mode emits GitHub issues; single-pr mode emits PLAN doc) | `docs/plans/PLAN-<topic>.md` | `skills/plan/SKILL.md` lines 32, 117-128, 219-229 |

**Asymmetries vs `/charter`'s children:**
- `/design` uses Proposed, not Draft. Its resume ladder uses "Accepted" / "Proposed" not "Accepted/Active" / "Draft" (skills/design/SKILL.md line 170-171).
- `/design` has a directory-move lifecycle: `docs/designs/` → `docs/designs/current/` → `docs/designs/archive/`. The status surface includes both the frontmatter `status:` field AND the file path; a `/scope` resume ladder reading "where is the DESIGN" has to look in two locations.
- `/plan` accepts THREE upstream types (design / PRD / roadmap) — skills/plan/SKILL.md lines 122-128. This is a fork in `/scope`'s Phase 2 logic that `/charter` never has (each `/charter` child accepts one upstream type or none).
- `/plan` has a multi-pr vs single-pr execution split. The terminal artifact is sometimes `docs/plans/PLAN-<topic>.md`, sometimes GitHub issues. A `/scope` resume ladder needs to handle both.

### Enumerated `/scope` input modes

Following `/charter`'s pattern (`$ARGUMENTS` is narrow; semantic modes resolve at Phase 1 / via the resume ladder), the `/scope` `$ARGUMENTS` surface is the same two slots: empty (cold-start) or non-empty (slug regex). But the **semantic input modes** the SKILL.md prose names (informing Phase 1 discovery and the chain-proposal logic) are richer:

| # | Mode name | Detection signal | `/scope` treatment | Maps to `/charter` analogue? |
|---|---|---|---|---|
| 1 | Empty / cold-start | `$ARGUMENTS` empty | Surface cold-start prompt with trigger phrases | Yes — same as `/charter` |
| 2 | Plain topic | `$ARGUMENTS` matches slug regex, no child docs exist | Standard Phase 0 → Phase 1 → chain | Yes — same |
| 3 | BRIEF-just-landed | `docs/briefs/BRIEF-<topic>.md` exists at status Accepted, no PRD downstream | Phase 1 discovery proposes chain starting at `/prd`; BRIEF treated as upstream | Yes — analogous to `/charter`'s "brief-just-landed" treatment of a VISION |
| 4 | PRD-just-landed | `docs/prds/PRD-<topic>.md` at status Accepted, no DESIGN | Phase 1 proposes chain starting at `/design`; PRD treated as upstream input to `/design` | **NEW** — no `/charter` analogue |
| 5 | DESIGN-just-landed | DESIGN at `docs/designs/current/DESIGN-<topic>.md` (Accepted), no PLAN | Phase 1 proposes chain starting at `/plan`; DESIGN's status + path both checked | **NEW** |
| 6 | Existing-PLAN revision | `docs/plans/PLAN-<topic>.md` Active/Done OR GH issues exist | Status-aware re-entry: "Re-evaluate / Revise / Bail" against the PLAN terminal | Yes — same shape as `/charter`'s row 5 |
| 7 | Draft-at-some-link | Any of BRIEF-Draft / PRD-Draft / DESIGN-Proposed / PLAN-Draft exists | Per-child draft continue-or-restart prompt | Yes — analogous to `/charter`'s row 6 (Draft STRATEGY) but the link can be at four positions |
| 8 | Partial child run | Any of `wip/{brief,prd,design,plan}_<topic>_*.md` exists | Resume into the partial child via the child's own resume logic | Yes — analogous to `/charter`'s rows 7-8 (slot 6) |
| 9 | Roadmap-issue feeder | A GitHub issue labelled `needs-prd` or `needs-design` exists tied to the topic | **Feeder-doc-detected** slot fires; chain proposal pre-populated from issue body | **NEW** — `/charter` left this slot empty (template slot 7); `/scope` fills it |
| 10 | Exploration-just-crystallized | A `docs/spikes/SPIKE-<topic>.md` or freshly closed `/explore` artifact exists | Feeder-doc-detected slot fires; chain proposal grounds in the spike's "decision crystallized" output | **NEW** — also fills template slot 7 |
| 11 | Topic-branch resume | No state file, no docs, but current branch contains topic slug | Resume at Phase 1 (matches `/charter` row 9) | Yes |
| 12 | Main / unrelated branch | No state file, no docs, branch unrelated | Start at Phase 0 (matches `/charter` row 10) | Yes |
| 13 | Existing-state-file (fresh / stale / malformed / exited) | `wip/scope_<topic>_state.md` exists | Universal meta-ladder rows 1-4 | Yes — same as `/charter` |

**SKILL.md `## Input Modes` text body.** Following `/charter`'s precedent of narrow `$ARGUMENTS` slots and rich semantic-mode prose, the section names two `$ARGUMENTS` shapes (empty, non-empty slug) and forward-references Phase 1 discovery for the eight semantic upstream-detection modes (rows 3-10 above) and the resume ladder for the four state-file modes (row 13). The same path-as-input rejection applies — `/scope docs/prds/PRD-foo.md` fails the slug regex.

### Candidate resume ladder for `/scope`

The universal template's 9-row shape (1-4 + 8-9 meta; 5-7 body slots) holds. `/scope`'s body slots expand:

**Slot 5 (status-aware re-entry)** — `/charter` had 2 rows here (Accepted/Active vs Draft against ONE upstream STRATEGY). `/scope` has **four** doc-emitting children, three of which can be in a "settled" state and four of which can be in a "draft" state, but the ladder is **first-match-wins** and looks for the most-downstream durable artifact (PLAN > DESIGN > PRD > BRIEF). So slot 5 expands into two rows per child (settled, draft), but the order is anchored on "the rightmost child in the chain that has produced an artifact":

| Row | Match condition | Action |
|---|---|---|
| 5a | PLAN-Active or PLAN-Done OR GH issues exist for topic | Re-evaluate / Revise / Bail against PLAN |
| 5b | PLAN-Draft exists | Continue-PLAN-draft / Start-fresh |
| 5c | DESIGN-Accepted exists (at `current/`), no PLAN | Re-evaluate / Revise / Bail against DESIGN; if Revise, chain continues into `/plan` |
| 5d | DESIGN-Proposed exists, no PLAN | Continue-DESIGN-draft / Start-fresh |
| 5e | PRD-Accepted exists, no DESIGN | Re-evaluate / Revise / Bail against PRD; if Revise, chain continues into `/design` |
| 5f | PRD-Draft exists, no DESIGN | Continue-PRD-draft / Start-fresh |
| 5g | BRIEF-Accepted or Done exists, no PRD | Re-evaluate / Revise / Bail against BRIEF; if Revise, chain continues into `/prd` |
| 5h | BRIEF-Draft exists, no PRD | Continue-BRIEF-draft / Start-fresh |

**Slot 6 (partial-child-run)** — one row per child where the child can have a wip/ partial-state artifact:

| Row | Match condition | Action |
|---|---|---|
| 6a | `wip/plan_<topic>_manifest.json` (or similar `/plan` wip artifact) exists, no PLAN.md and no GH issues | Resume into `/plan` |
| 6b | `wip/design_<topic>_coordination.json` exists, no DESIGN doc | Resume into `/design` |
| 6c | `wip/prd_<topic>_scope.md` exists, no PRD | Resume into `/prd` |
| 6d | `wip/brief_<topic>_discover.md` exists, no BRIEF | Resume into `/brief` |

Each partial-child-run row would inherit `/charter`'s "filename-asymmetry accommodation" pattern (charter row 7 reads `_discover.md` not `_scope.md` because that's what `/strategy` actually writes). The exact filenames must be verified against each child's phase prose, not just the SKILL.md.

**Slot 7 (feeder-doc-detected)** — `/charter` left this empty; `/scope` fills it. Two candidate rows (could potentially compress to one):

| Row | Match condition | Action |
|---|---|---|
| 7a | A GH issue with `needs-prd` or `needs-design` label exists tied to the topic | Phase 1 entry with chain-proposal seeded from issue body |
| 7b | A `docs/spikes/SPIKE-<topic>.md` with "decision crystallized" closure exists | Phase 1 entry with chain-proposal seeded from spike |

**Total row count:** 6 meta-rows (template-slot 1-4 + 8-9) + 8 status-aware re-entry rows (5a-5h) + 4 partial-child-run rows (6a-6d) + 2 feeder rows (7a-7b) = **20 rows**.

If 5a-5h compress to 4 by collapsing settled/draft into single rows per child (with branching action prose), that's 6 + 4 + 4 + 2 = **16 rows**. If the feeder slot stays one row, **15 rows**.

Either way: roughly **1.5× to 2× larger than `/charter`'s 10-row ladder.**

### Universal-template fit assessment

The template at `references/parent-skill-resume-ladder-template.md` was authored as a **9-row shape** with 3 body slots. It treats each slot as one "row" semantically but allows each parent to expand the slot into multiple rows (lines 33-34 — "rows 5-7 are parent-specific body slots each parent fills" — but the implementation in `/charter`'s phase-resume.md expands slot 5 into 2 rows and slot 6 into 2 rows for a 10-row literal ladder).

`/scope`'s expansion to 15-20 literal rows fits the template **without modification**: the slots are expansion points, and the meta-ladder remains the 6-row pattern-level invariant. The template does NOT need an extension.

The template's slot-7 (feeder-doc-detected) was authored speculatively (`/charter` doesn't fill it). `/scope` is the first concrete consumer of slot 7. The template's wording at lines 141-154 holds — `/scope` fills the slot per the rules already documented (parent's SKILL.md names which feeder docs are recognized; the slot's behavior is parent-specific Phase 1 entry behavior).

### Notable cross-cutting observations

**The "chain-position" insight.** `/charter`'s three children form a linear chain where each step's artifact is the prior step's input. `/scope`'s chain is the same shape but TWICE as long (4 children vs 3). Each additional chain step doubles the surface area of status-aware re-entry rows because every child can be at any of its 2-3 lifecycle states.

**The `/plan` divergence.** `/plan` is structurally different from `/vision`, `/strategy`, `/roadmap`, `/brief`, `/prd`, `/design` in that its terminal artifact is sometimes a doc and sometimes a set of GitHub issues. The pattern-level R14 widening (Decision 4, lines 599-610 of `DESIGN-shirabe-progression-authoring.md`) anticipates this: "for non-doc children (`/work-on`'s children — issues and PRs): the issue/PR state plus labels plus CI check rollup." `/plan`'s multi-pr mode emits issues, which means `/scope`'s row 5a (PLAN-terminal) must check BOTH `docs/plans/PLAN-<topic>.md` AND the GH issue surface tied to the topic. The R14 widening rule covers this, but `/scope` is the first parent to need it for one of its own children.

**The `/design` directory-move complication.** When `/design` transitions Proposed → Accepted, the file moves from `docs/designs/DESIGN-<topic>.md` to `docs/designs/current/DESIGN-<topic>.md`. The dual-check drift detection (status + git blob hash) computed at the snapshot path becomes a moving target. `/scope`'s `child_snapshots` block needs a `path:` field that gets updated when the directory move fires. `/charter` never has this — all three of its children stay at one path through their lifecycle.

## Implications

**For SKILL.md `## Input Modes` section.** Follow `/charter`'s precedent of declaring TWO `$ARGUMENTS` slots (empty, non-empty slug); enumerate the semantic upstream-detection modes in the Phase 1 discovery prose (where the chain proposal gets built), not in the Input Modes section. Keep the Input Modes section narrow — three lines like `/charter`'s — and put the eight semantic modes (rows 3-10 above) in `phase-1-discovery.md` along with the rules for detecting each. This matches `/charter`'s shape and keeps the SKILL.md authoring effort similar.

**For `phase-resume.md` body.** The ladder is 15-20 rows depending on collapsing decisions. The body slots' expansion fits the universal template without modification; what `/scope` needs is roughly twice as much prose per slot as `/charter` because there are roughly twice as many durable child docs. The R14 widening for `/plan`'s issue-emitting mode and the `/design` directory-move case both need explicit prose in `/scope`'s `phase-resume.md` — they don't appear in `/charter`'s.

**For the universal template at `references/parent-skill-resume-ladder-template.md`.** No changes needed. The template's 9-row meta-shape holds; `/scope` fills the body slots more densely than `/charter` did, but that's expected ("parent-specific body slots each parent fills" — lines 33-34 of the template).

**For ACs / evals.** `/charter`'s eval suite has 11 scenarios (per the design doc). `/scope` will need MORE scenarios because the row count is larger. Rough multiplier: if scenarios scale with ladder-row count, `/scope` evals could be 16-22 scenarios. The "shared eval baseline via copy-paste" pattern (Decision 4) bounds the multiplier — the baseline scenarios (slug rejection, malformed state file, child-internals isolation, visibility default) stay constant; the parent-specific scenarios scale.

**For the SE7 PRD's "scope ratification" sections.** The PRD authors should ratify `/scope` filling template slot 7 (feeder-doc-detected) since `/charter` left it empty. The PRD also needs to ratify the R14 widening's binding to `/plan`'s issue-emitting mode (the design doc anticipates this for `/work-on` but `/scope` consumes it first).

## Surprises

**`/charter` has only 2 `$ARGUMENTS` input modes, not 3.** The exploration scope file says "/charter had 3 input modes (plain topic, brief-just-landed, existing strategy revision)" — but the actual SKILL.md declares two: empty and non-empty-slug. The "brief-just-landed" and "existing strategy revision" modes are functional behaviors that emerge from Phase 1 discovery and the resume ladder, NOT from $ARGUMENTS dispatch. This is a non-trivial framing distinction: `/scope`'s SKILL.md Input Modes section can stay just as narrow as `/charter`'s; the semantic-mode richness goes elsewhere.

**`/charter` only fills 2 of 3 body slots.** Template slot 7 (feeder-doc-detected) is unfilled because `/charter` has no feeder doc. The scope file's mental model that "each child has 3 states and `/scope` resumes per-child × per-state, the resume ladder is naively 4 × 3 = 12 rows just for child positions" misses the chain-position-collapse mechanic — first-match-wins ordering walks the chain from terminal-most to earliest, so a PLAN match short-circuits checking earlier children. The ladder is large but not naively 4×3.

**`/plan`'s three-upstream-type acceptance is a Phase-1 fork, not a resume-ladder concern.** `/plan` accepts design / PRD / roadmap as upstream (skills/plan/SKILL.md lines 122-128). For `/scope`, this means Phase 1's chain proposal can stop at `/design` OR `/prd` OR even `/brief`-only-then-jump-to-`/plan`-with-skeleton-decomposition, depending on what the author wants. The resume ladder doesn't surface this — it surfaces "which child is the most-downstream durable artifact" — but the chain-proposal authoring (in Phase 1 prose) needs to handle the fork.

**`/design`'s directory-move lifecycle breaks `/charter`'s "stable path" assumption.** `/charter`'s `child_snapshots` block records a `path:` field per child. The assumption was the path is stable (`/charter`'s children all stay at one path through their lifecycle — see brief's "no directory movement" rule at line 53-56). `/design`'s Accepted-moves-to-`current/` transition violates this assumption. `/scope`'s state schema either tracks both `path:` and `current_path:`, or reads the path dynamically each resume by checking BOTH `docs/designs/` and `docs/designs/current/`. This wasn't documented anywhere — it's an implementation detail surface tactical specifically.

**`/design`'s status vocabulary is `Proposed`, not `Draft`.** `/charter`'s row 6 wording is "Draft STRATEGY exists." `/scope`'s analogous row for DESIGN says "Proposed DESIGN exists." The pattern-level prompt-vocabulary requirements (literal substrings like "Re-evaluate / Revise / Bail") hold; the upstream-status word differs. The "default-option wording" eval pattern (charter's PRD US-2) will need adapting for the Proposed→Accepted vs Draft→Accepted vocab differences.

**The "exploration-just-crystallized" handoff is new pattern territory.** `/explore` produces a SPIKE doc when an exploration crystallizes a decision. `/scope` invoked against a topic where a SPIKE already exists is a real handoff case (it's a forward-route from the discover/converge engine). `/charter` never has this because strategic exploration doesn't crystallize into SPIKEs in the same way. The feeder-doc-detected slot (template slot 7) is the natural home for it, but the prose authoring is novel.

## Open Questions

1. **Should the Input Modes section be richer than `/charter`'s?** `/charter`'s narrow 2-slot $ARGUMENTS section was a deliberate "path-as-upstream is rejected" stance. Does `/scope` keep the same stance? Or does the tactical chain's multi-position entry justify accepting paths-as-upstream in `$ARGUMENTS` (e.g., `/scope docs/prds/PRD-foo.md`) as a UX affordance? Recommendation lean: keep the narrow stance (consistency wins, Phase 1 discovery handles upstream detection), but the user should pick.

2. **Slot 5 row collapse: 8 rows or 4?** Should each "settled vs draft" pair be one row (with branching action prose) or two rows (one per status)? Two rows is more grep-checkable for evals and matches `/charter`'s precedent (charter has separate rows 5 and 6 for Accepted/Active vs Draft STRATEGY); one row is more readable. Recommend two rows (consistency with `/charter`'s expansion granularity).

3. **Should the feeder-doc-detected slot have ONE row or TWO (issue-label vs SPIKE)?** Both are genuine feeder shapes. Two rows preserves distinguishability; one row with branching action prose is more compact. Recommend two (clarity for evals + each has different downstream behavior — issue label seeds the chain proposal from issue body; SPIKE seeds from a decision-crystallized output).

4. **How does the ladder handle the multi-pr vs single-pr PLAN terminal?** `/plan` emits either a PLAN.md or GH issues. Row 5a (PLAN-terminal) must check BOTH surfaces; if EITHER is present and at a terminal status, the row fires. This needs explicit prose in phase-resume.md and an R14-widening citation pointing at the design doc's per-parent surface table.

5. **Does `/scope` need a `/comp` feeder analogous to `/charter`'s competitive-analysis case?** `/charter`'s feeder model includes `/comp` (gated by visibility=Private and Phase 1 detection of competitive framing). Does `/scope` have an analogous feeder — e.g., `/decision` invoked when the tactical chain surfaces a contested architectural choice that `/design`'s Phase 1 decomposition would otherwise consume? Recommend deferring to the tactical-chain-gates lead's findings; if `/decision` is in scope as a feeder, that's a SECOND feeder-doc-detected slot row (rows 7a, 7b, 7c).

6. **What stale-session threshold value does `/scope` pick?** `/charter` picked 7 days (skills/charter/SKILL.md line 170-172). The tactical chain may complete faster (one-sitting feature work) or take longer (a feature exploration that spans weeks). The threshold trades off "broke for lunch" vs "abandoned for a week" (template lines 184-187). Recommendation lean: keep 7 days for consistency unless the tactical chain's typical session shape is materially shorter.

## Summary

`/scope`'s input-mode surface stays narrow at the `$ARGUMENTS` layer (matching `/charter`'s 2-slot empty/non-empty-slug shape), with eight semantic upstream-detection modes living in Phase 1 discovery prose, but its resume ladder expands to roughly 15-20 literal rows (up from `/charter`'s 10) because the tactical chain has four doc-emitting children versus three, each with 2-3 lifecycle states, plus the previously-empty feeder-doc-detected template slot gets filled by `/scope` for the first time. The universal 9-row template at `references/parent-skill-resume-ladder-template.md` holds without modification — `/scope` just fills the body slots more densely — and the SKILL.md Input Modes section can stay structurally identical to `/charter`'s. The biggest open question is whether `/scope`'s `$ARGUMENTS` accepts upstream paths as a UX affordance (breaking from `/charter`'s explicit rejection stance) or stays narrow and pushes path-as-upstream detection entirely into Phase 1 discovery.
