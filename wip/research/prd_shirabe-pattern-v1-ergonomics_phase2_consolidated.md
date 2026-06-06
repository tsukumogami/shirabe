# Phase 2 Research: shirabe-pattern-v1-ergonomics (consolidated)

## Operating context

This research file replaces the parallel-agent fan-out the phase
prescribes. `/prd` runs here as a sub-agent dispatched by `/scope`
(`parent_orchestration.invoking_child: prd`,
`rationale: fresh-chain`); the Agent tool with
`run_in_background: true` is not exposed to sub-agents in this
substrate, so the three roles (codebase analyst, current-state
analyst, maintainer perspective) collapse into one sequential
investigation. Independence-loss caveat: one author evaluated all
three lenses against the same evidence base; the cross-checking
that parallel agents provide was not available. The PRD draft
proceeds against the consolidated findings and the Phase 4 jury
will sanity-check the result against the same independence-loss
caveat.

## Evidence base

1. `tsukumogami/vision#514` — issue body (Track A scope narrowed
   from SE12 after PR-166 merged) + consolidated 17-theme comment
   (2026-06-05) + observation #12 comment (2026-05-25 team-lead
   discipline).
2. `friction-log-shirabe-0.9.0.md` (484 lines) — v0.9.0/v0.9.1-dev
   dogfooding round. Re-confirms v0.7.0-era observations on the
   Rust-cutover codebase; adds /design Phase 6 missing
   structural-format reviewer, /plan Phase 7 single-pr drift,
   /work-on koto deterministic-mode overhead, CLI version-skew
   workaround, /scope dispatch-contract chain-handoff positive
   datapoint.
3. `docs/briefs/BRIEF-shirabe-pattern-v1-ergonomics.md` — Accepted
   2026-06-06; supplies the six-cluster framing and named
   user journeys.

## Lead 1: Cluster 1 — Sub-agent dispatch fallbacks

### Findings

The friction log (lines 10-51, 90-132) and SE12 theme 1 confirm
the same surfaces, with one v0.9.1-dev re-confirmation each:

| Skill | Phase | Site | Top-level prescription | Sub-agent fallback (required) |
|-------|-------|------|------------------------|--------------------------------|
| /brief | Phase 4 | jury fan-out | Three Agent invocations (completeness, clarity, structural-format) parallel via `run_in_background: true` | Serial-self-jury against the same three rubrics |
| /brief | Phase 5 | approval gate | `AskUserQuestion` | Parent-delegated approval (commit deferred to parent) |
| /prd | Phase 2 | research fan-out | Parallel agents per role | Serial-self-investigation with consolidated findings |
| /prd | Phase 3 | user-review checkpoint | `AskUserQuestion` | Parent-delegated review |
| /prd | Phase 4 | 3-agent jury | Parallel agents (completeness, clarity, testability) | Serial-self-jury, independence-loss caveat surfaced |
| /design | Phases 1-3 | per-decision /decision dispatch | Agent spawning per decision | Inline-resolution variant when PRD enumerated alternatives |
| /design | Phase 6 | approval gate | `AskUserQuestion` | Parent-delegated approval |
| /plan | Phase 3 | execution-mode prompt | `AskUserQuestion` | Read execution-mode hint from parent dispatch contract |
| /plan | Phase 6 | /review-plan nested fan-out | Sub-skill dispatch | Inline-substitute single-pass review |
| /vision, /strategy, /roadmap | Phase-N jury | Parallel agents | Serial-self-jury |
| /work-on | plan-orchestrator | koto deterministic-mode | Full koto state machine | Deterministic-mode bypass when parent supplied decomposition (friction log lines 325-363) |

The required contract per fallback:
- Section lives in each child SKILL.md (or per-phase reference,
  by skill convention).
- Names the substitute primitive (serial-self-jury,
  parent-delegated approval, inline resolution, deterministic
  bypass).
- Names the audit-trail obligation: the artifact (verdict file,
  state file, decision record) records the operating context AND
  the independence-loss caveat.
- Explicitly states what is NOT covered: nested-team spawning
  remains Track B (vision#535) — sub-agents cannot recursively
  dispatch sub-sub-agents in pattern v1 substrate.

### Implications for Requirements

A single requirement per affected skill is too coarse — different
sites (jury, approval, /decision dispatch, execution-mode prompt)
have different fallback substitutes. Group by skill, enumerate
sites, and let DESIGN pick whether the fallback prose lives in
SKILL.md or each phase reference.

### Open Questions

- Whether /vision, /strategy, /roadmap need the same explicit
  fallback section as /brief/prd/design/plan. The friction log
  primarily exercised the tactical chain; the strategic chain
  has the same parallel-jury structure and the same sub-agent
  dispatch surface from /charter, so the contract should be
  uniform. → Resolution: include them in scope; the PRD treats
  the tactical and strategic chains symmetrically.

## Lead 2: Cluster 2 — Resume Logic sentinel-awareness

### Findings

SE12 theme 2: /brief, /prd, /design each have Resume Logic
tables. None of the tables consult the `parent_orchestration:`
sentinel set by /scope/charter. A cold-spawned sub-agent reads
its SKILL.md, walks the Resume Logic table top-to-bottom, and
hits a row whose precondition is satisfied (e.g., "on main") and
proceeds as if the run were top-level.

PR-166 merged the sentinel convention but only retrofit /prd
Phase 0 (the brief-handoff transition) to consult it. The other
children's Resume Logic tables were not updated.

Affected children: /brief, /prd, /design, /plan. Also /vision,
/strategy, /roadmap if they expose Resume Logic tables. (Verified
that /prd has one; /brief has one in the current cache. /design
and /plan have entry-mode dispatch logic that serves a similar
purpose.)

### Implications for Requirements

The contract:
- Each child's Resume Logic table adds a sentinel-check row at
  high priority (above the wip/-file-existence rows).
- Sentinel-present row reads `parent_orchestration.invoking_child`
  and either short-circuits the status-aware prompt
  (suppress_status_aware_prompt: true) or follows the rationale
  hint (fresh-chain | revise | continue-existing).
- Sentinel-absent rows are the existing behavior unchanged.
- The pattern-level template / parent-skill-pattern reference
  optionally describes the sentinel-row convention so children
  inherit consistently.

### Open Questions

- Row position relative to status-aware prompt rows is DESIGN
  territory — the PRD only commits "high priority" (consulted
  before status-aware prompts fire).

## Lead 3: Cluster 3 — Format-reference clarifications

### Findings

SE12 themes 6, 7, 8, 9, 16 + friction log /plan #158
re-confirmation. Specific surfaces:

1. **brief-format / prd-format**: public-with-private-upstream
   traceability. Public artifact cannot reference a private
   upstream issue in `upstream:` per the visibility-direction
   rule. Either an optional `motivating_context:` field, or
   document the "carry framing forward in prose" pattern as
   load-bearing. The PRD commits to one of these contracts being
   documented; DESIGN picks which.
2. **brief-format / phase-4-validate.md**: public-visibility
   cleanliness grammar disambiguation ("private paths, repos,
   filenames, codenames, OR issue numbers" — the "private"
   qualifier distribution). Author over-strips or under-strips.
   The PRD commits the format reference SHALL state explicitly
   whether public issue numbers in public-repo briefs are
   allowed.
3. **prd-format**: "Decisions and Trade-offs" optional section
   surfaced as the canonical home for closing upstream BRIEF
   Open Questions when promoting Draft → Accepted. Currently
   inferred from precedent. The PRD requires both brief-format
   and prd-format to surface the convention explicitly.
4. **design-format / SKILL.md**: Implementation Issues table
   ownership — SKILL.md says /plan owns it; some dispatch
   prompts ask /design to ship inline. PRD requires the
   convention be stated explicitly (which path is canonical and
   when the variant is acceptable).
5. **prd-format**: Content Boundaries ambiguity for
   skill-specifying artifacts (PRD authoring /comp is a PRD
   whose subject is a competitive-analysis artifact — needs
   distinguishing "competitive findings" from
   "competitive-analysis-as-an-artifact-type"). PRD requires the
   boundary statement be clarified.
6. **plan-format**: single-pr `## Implementation Issues`
   contract (friction log lines 227-257, shirabe#158-lineage).
   /plan emits inline-issues in single-pr mode but the format
   reference doesn't enumerate the section. PRD requires the
   format reference document the canonical structure.

### Implications for Requirements

Format-reference clarifications are prose-only; ACs are
grep-presence checks per format reference.

### Open Questions

- Whether the BRIEF's "carry framing in prose" workaround and
  the optional `motivating_context:` field are alternatives
  (DESIGN picks one) or compatible (DESIGN documents both). The
  PRD commits to "one of these patterns SHALL be documented";
  DESIGN picks.

## Lead 4: Cluster 4 — Validator extensions

### Findings

Friction log lines 154-177 (#157 re-confirmation), SE12 theme 12
(content budgets), SE12 theme 14 (eval-fixture line-1 marker),
plus the meta-meta writing-style banned-word observation the
BRIEF surfaced.

1. **Schema silent-skip (#157)**: missing `schema:` frontmatter
   causes validator to exit 0 (success) instead of warning or
   erroring. PRD requires the validator's exit code to reflect
   the silent skip (the FC code assignment is DESIGN territory).
2. **Content-budget enforcement**: ACs that name approximate
   lengths ("~110 lines", "one paragraph") ship 60%-over with
   validator exit 0. PRD requires the validator OR /design
   Phase 6 jury surface budget overshoots; the choice between
   the two surfaces is DESIGN territory.
3. **Mechanical writing-style banned-word grep**: BRIEF meta
   observation. Phrases like "robust", "leverage",
   "comprehensive", "holistic", "facilitate", "tier", "tiered"
   ship in documents despite the writing-style reference banning
   them. PRD requires a mechanical check; placement (validator
   notice, Phase 4 reviewer, pre-commit hook) is DESIGN
   territory.
4. **/design Phase 6 missing structural-format reviewer**:
   friction log lines 178-203. The DESIGN-format reviewer is
   missing from /design Phase 6's three-reviewer jury (jury runs
   completeness + clarity + decisions-traceability, but no
   structural-format check). PRD requires the structural-format
   reviewer be added to /design Phase 6's jury.
5. **/plan single-pr Implementation Issues drift (#158)**:
   friction log lines 227-257. /plan emits inline-issues in
   single-pr mode with prose drift from the format reference.
   PRD requires the validator OR /plan Phase 7 enforce the
   contract.

### Implications for Requirements

Validator-side requirements are mechanical; ACs are exit-code
tests at the FC level (FC code assignments to be made by
DESIGN). One FC code per check.

### Open Questions

- Whether the writing-style grep lives in the validator
  (mechanical) or in the format reference / Phase 4 reviewer
  (judgment). DESIGN to pick; the PRD commits the contract that
  some mechanical surface exists.

## Lead 5: Cluster 5 — Cross-skill consistency rules

### Findings

SE12 themes 11, 13, 14, 17 plus the friction log /work-on
deterministic-mode overhead.

1. **PLAN/DESIGN field consistency**: SE11 `scope` field
   collision is the canonical example. /plan emits sibling
   issues whose `scope` field is treated differently across
   issues (free-text prose vs enum). PRD requires /plan run a
   pre-flight consistency pass on cross-issue field contracts.
2. **PLAN AC anchor-existence pre-flight**: SE12 theme 17.
   ACs that say "annotation only; schema fields unchanged"
   presuppose an anchor in the target file. PRD requires /plan
   ACs that claim "annotation only" grep the target file at
   PLAN-authoring time.
3. **/design Phase 6 wip/-hygiene carve-out**: SE12 theme 13.
   Skill-implementation DESIGNs document a skill's runtime
   wip/ usage; the wip-hygiene rule's carve-out wording covers
   "quoted statements OF the rule itself" but not "documentation
   of a skill's runtime wip/ contract." PRD requires the
   carve-out be extended.
4. **Eval-fixture line-1 marker**: SE12 theme 14. Some
   eval-fixture ACs require an HTML-comment marker on line 1,
   but frontmatter parsers require `---` on line 1. PRD requires
   eval-authoring guidance and PLAN/issue-drafting guidance be
   reconciled.

### Implications for Requirements

Cross-skill consistency rules are integration-level grep
checks; ACs are presence/absence checks across multiple skill
files and format references.

### Open Questions

- Whether the pre-flight consistency pass is a separate /plan
  Phase or folded into Phase 7 — DESIGN territory.

## Lead 6: Cluster 6 — Convention updates

### Findings

SE12 themes 3, 4, 5, 15 plus friction log lines 178-203
(/design Phase 6).

1. **Slug-prefix detection at Phase 0**: SE12 theme 4. /scope
   Phase 0 validates the slug regex but doesn't detect
   repo-prefix conventions (shirabe's `shirabe-<feature>`
   precedent). PRD requires Phase 0 sample existing artifacts
   and prompt when the input slug lacks the detected prefix.
   The PRD does NOT require the same of /charter (strategic
   chain — separate cluster) unless evidence surfaces.
2. **Release-notes adopter-doc home**: SE12 theme 15. ACs
   that reference a "release-notes draft" target a file that
   shirabe doesn't have on disk. PRD requires ACs that
   reference release-notes target durable adopter docs under
   `docs/guides/` or the workspace's actual release mechanism.
3. **/scope Phase 1 forward-looking gate (R6 P1/P3) at cold
   start**: SE12 theme 3. R6 predicates inspect the PRD's body;
   at cold start no PRD exists yet, so all predicates trivially
   "do not fire" and R7 would skip /design. PRD requires R6 P1
   and P3 evaluate the projected PRD's expected content shape
   when the PRD doesn't yet exist; framing-shift opener
   short-circuits on cold-start condition.
4. **Skill body path resolution**: SE12 theme 5. SKILL.md
   bodies resolve pattern-level references as absolute plugin
   paths but leave skill-local references relative; phase
   references contain raw `${CLAUDE_PLUGIN_ROOT}` placeholders.
   PRD requires either path-resolution rendering at load time
   OR explicit documentation in the SKILL.md preamble of the
   resolution convention.
5. **Structural-format reviewer for /design Phase 6**: friction
   log lines 178-203. Already named in Cluster 4 (validator
   extensions) — the same fix surface is convention update +
   validator extension. PRD treats this as one requirement; the
   reviewer is added.

### Implications for Requirements

Convention updates affect Phase-N behavior in named skills. ACs
are grep markers (the convention prose exists in the named
phase) + prose-presence checks.

### Open Questions

- /scope Phase 1 cold-start: whether the "framing-shift
  opener" is short-circuited at Phase 1 or eliminated entirely
  for cold-start — DESIGN territory.

## Lead 7: CLI version-skew preflight

### Findings

Friction log lines 52-89, 409-430. Skill bodies prescribe
`shirabe transition <path> Accepted` but the installed CLI may
not expose `transition` (the workspace's installed shirabe is
0.6.1; the skill prose was authored against 0.9.x). Failure
mode is `unknown command` exit 1, leaving the skill body's
sed/awk fallback uncalled. The friction log records a
workaround (manual sed-edit) that ships consistently.

### Implications for Requirements

The PRD requires that any skill body prescribing a `shirabe`
subcommand surface a CLI-version preflight that detects whether
the subcommand exists in the installed binary, with a documented
fallback prose path when it doesn't. The mechanism (preflight
shell snippet, capability-detection at skill load, parent-skill
inheritance) is DESIGN territory.

### Open Questions

- Which subcommands besides `transition` need the preflight.
  PRD scope: any subcommand the skill prose prescribes; DESIGN
  enumerates.

## Lead 8: Sub-agent serial-self-jury independence-loss caveat

### Findings

This is the load-bearing requirement the dispatch note flagged.
When a child's Phase-N jury runs under sub-agent dispatch, the
parallel-agent fan-out is NOT REQUIRED; serial-self-jury with
discipline preserving the independence property (each role's
criteria evaluated against the role's specific lens without
cross-contamination) SATISFIES the jury requirement. The verdict
files MUST surface the independence-loss caveat in their
preamble so the audit trail records what happened.

This requirement is referenced by Cluster 1 (sub-agent dispatch
fallbacks) but stands alone as a load-bearing pattern-level
contract because it governs jury sites uniformly across the
strategic and tactical chains.

### Implications for Requirements

This is a single named requirement at the pattern level. ACs
verify the contract is stated explicitly in the parent-skill
pattern reference AND each affected child's jury phase
reference.

### Open Questions

None — the contract is settled.

## Synthesis

Themes across the leads:

1. **Silent degradation is the common failure shape**. Every
   observation describes a path the skill prose silently
   degrades along when the operating context doesn't match the
   assumed ideal. The PRD's requirements convert each
   degradation site into explicit signal.
2. **Mechanism is deferred to DESIGN per observation**. The
   PRD names what must hold (the contract); DESIGN picks how
   (skill-prose edit vs reference-content edit vs validator
   extension). The BRIEF's Out-of-Scope item ("mechanism per
   observation") is honored.
3. **Sub-agent dispatch is the dominant operating context**.
   Six of the eight leads touch sub-agent dispatch directly;
   the contract is uniform across affected sites.
4. **Symmetric strategic and tactical chain treatment**.
   /vision, /strategy, /roadmap inherit the sub-agent dispatch
   fallback contract on the same shape as /brief, /prd, /design,
   /plan — because /charter dispatches them the same way /scope
   dispatches the tactical children.

Scope adjustments: none — the BRIEF's six clusters cover the
research findings cleanly, and the additional "CLI version-skew
preflight" + "Sub-agent serial-self-jury caveat" leads are
already in BRIEF scope (named in the BRIEF's "plus the boundary
observation" paragraph and journey 1).

Decisions made during research (feed Decisions and Trade-offs):

- D1: /vision, /strategy, /roadmap included in Cluster 1
  (sub-agent dispatch fallback) scope despite the friction log
  primarily exercising the tactical chain. Alternative: tactical
  chain only. Chosen because /charter dispatches the strategic
  chain the same way /scope dispatches the tactical chain;
  asymmetric treatment would compound chain tax on the
  strategic side.
- D2: Mechanism per observation deferred to DESIGN per the
  BRIEF's Out-of-Scope item, with one exception: the
  serial-self-jury contract under sub-agent dispatch is
  load-bearing enough to name explicitly in the PRD. DESIGN
  picks placement (parent-skill-pattern reference vs per-skill
  jury phase reference) but the contract is fixed.
- D3: The CLI version-skew preflight is treated as a contract
  the skill prose must surface, NOT as a validator extension.
  Alternative: validator detects CLI version-skew. Chosen
  because the version-skew is a runtime condition the skill
  body addresses inline (the validator runs against committed
  artifacts, after the skill body has already prescribed the
  subcommand).

New questions for the user / Phase 4: none — the BRIEF Open
Questions were closed at BRIEF acceptance; this PRD doesn't
re-open them.

## Summary

Eight research leads consolidate into ~30 per-observation
requirements organized by the six BRIEF clusters plus two
adjacent observations (CLI preflight, serial-self-jury caveat).
Each requirement names the contract that must hold and defers
the implementation mechanism to DESIGN. The PRD treats the
strategic and tactical chains symmetrically and honors the
BRIEF's explicit Out-of-Scope items.
