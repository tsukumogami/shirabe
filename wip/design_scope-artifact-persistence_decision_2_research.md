# Research: Contribution-Section Authorship (child-drafting-time vs parent-fold-time)

## Research conducted

Read the following files in the worktree at
`public/shirabe/.claude/worktrees/scope-artifact-persistence`:

- `skills/prd/references/phases/phase-3-draft.md` (full)
- `skills/strategy/references/strategy-format.md` (Strategic Context quality-guidance block)
- `skills/strategy/references/phases/phase-1-discover.md`, `phase-2-draft.md`, `phase-4-validate.md`
- `skills/prd/references/phases/phase-4-validate.md`
- `skills/design/references/phases/phase-6-final-review.md`
- `skills/brief/references/phases/phase-4-validate.md`
- `skills/plan/references/phases/phase-1-analysis.md`, `phase-6-review.md`
- `skills/review-plan/references/phases/phase-0-setup.md`, `phase-1-scope-gate.md`,
  `phase-2-design-fidelity.md`, `phase-3-ac-discriminability.md`, `phase-5-verdict.md`
- `skills/scope/references/phases/*` (all 6 files, directory listing + content of
  `phase-2-chain-orchestration.md` in full)
- `skills/design/references/phases/phase-0-setup-prd.md`
- `docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md` (dispatch/team-shape table)
- `crates/shirabe-validate/src/formats.rs` (full `FormatSpec` struct, Strategy/Brief entries)
- Grep sweeps for `Agent tool`, `subagent`, `Task tool`, `spawn`, `/decision`, `dispatch binding`
  across `skills/scope/references/phases/` and `docs/`

## Findings

### 1. `/prd` Phase 3.2 reads its upstream BRIEF

`skills/prd/references/phases/phase-3-draft.md`, section "3.2 Draft the PRD", lines 63-85:

> **When an upstream BRIEF exists (Input Mode 2), read it first.** The brief already
> settled this feature's framing, and four of its five required sections map onto
> sections this PRD must carry:
>
> | BRIEF section | PRD section |
> |---|---|
> | Problem Statement | Problem Statement |
> | User Outcome | Goals |
> | User Journeys | User Stories |
> | Scope Boundary (in-list / out-list) | Requirements / Out of Scope |
>
> Draw those four sections from the brief's body, not from this PRD's own Phase 1
> conversation. ... (line 74-76)
>
> Carrying the framing forward properly is also what makes the downstream
> consolidation judgment usable. `/scope` checks section by section whether this PRD
> carries the brief's four concerns before it removes a redundant brief; a PRD
> written without reading its brief fails that check, and both documents stay.
> (lines 82-85)

So yes: the PRD is instructed to draw four named sections (Problem Statement, Goals,
User Stories, Requirements/Out of Scope) from the BRIEF's body at drafting time
(line 63-80), and the instruction explicitly names the downstream consolidation/carry
check as a reason (lines 82-85, plus a second explicit callback at line 74-76: "what
makes a BRIEF and its PRD read as two documents saying one thing"). Per-section
drafting guidance reiterates the same sourcing at lines 88-101 (Problem Statement,
Goals, User Stories, Out of Scope each say "Draw from the upstream BRIEF when one
exists").

This means today's `/prd` already carries the child-authored-at-drafting-time model
for *fold-worthy content* — but it is not labeled/isolated as a distinct "contribution
section"; it is folded directly into the PRD's own normal sections (Problem Statement,
Goals, etc.), which is exactly what makes the downstream Stage-2 carry check (finding
5) possible without a dedicated section.

### 2. `strategy-format.md` Strategic Context contract + which phase authors it

**Contract wording** — `skills/strategy/references/strategy-format.md`, lines 346-356,
under "## Quality Guidance" / "### Strategic Context":

> - Carries forward the essential framing from upstream context without
>   re-justifying the long-term thesis. If the section reads like a
>   re-write of the upstream VISION, fold it back; if a reader can't
>   follow the bet without first reading the upstream, expand.
> - Stands alone. A reviewer landing on the STRATEGY cold should be able
>   to grasp what's at stake from this section alone.
> - Sub-structure is the author's call. Free-flowing prose is fine;
>   numbered antecedents are fine; situation/complication/question is
>   fine. Pick what serves the framing.

This is the two-sided adequacy test the question asked about: too-thin ("can't
follow ... expand") vs. too-thick ("reads like a re-write ... fold it back").
The "Required" status of Strategic Context appears in the section-by-status table
at line 192: `| Strategic Context | Required | Required | Required | Required |`.

**Which phase drafts it:** `skills/strategy/references/phases/phase-2-draft.md`,
section "## 2.4 Draft Strategic Context", lines 118-148. This is the CHILD skill's
own drafting phase (Phase 2 of `/strategy`, not `/charter` and not `/scope`). Key
lines:

> Strategic Context grounds the bet for a reader who lands on the document
> cold. The format reference allows free sub-structure; what matters is the
> content properties. (120-122)
>
> **Required content properties:**
> - If an upstream VISION exists, carry forward its essential framing (the
>   audience, the value proposition, the org fit). Paraphrase rather than
>   quote when the upstream is in a private repo and the strategy is public.
>   (126-128)
> ...
> - The section MUST stand alone: a reader who has never seen the upstream
>   should still understand what this strategy is about after reading
>   Strategic Context. (137-139)

So: **yes, child-authored at drafting time.** `/strategy`'s own Phase 2 (not
`/charter`, the parent) writes Strategic Context, using Phase 1's anchor sketch
(`phase-1-discover.md` lines 53-56, 96, 147-160) as raw material. Phase 4
(`phase-4-validate.md`, see finding 3 below) is a later validation/jury pass over
the already-drafted section, not the authoring step.

### 3. Do child juries receive the upstream document?

**`/prd` Phase 4** (`skills/prd/references/phases/phase-4-validate.md`) — 3-agent
jury (Completeness, Clarity, Testability). Each reviewer prompt's context block is
identical and minimal:

- Completeness Reviewer: lines 50-54 — `## PRD to Review` / `[Contents of
  docs/prds/PRD-<topic>.md]` and `## Original Scope` / `[Contents of
  wip/prd_<topic>_scope.md]`.
- Clarity Reviewer: lines 92-93 — only `## PRD to Review` / `[Contents of
  docs/prds/PRD-<topic>.md]`.
- Testability Reviewer: lines 131-132 — same, PRD only.

**None of the three reviewer prompts includes the upstream BRIEF.** The upstream
document is NOT passed into any `/prd` jury reviewer.

**`/design` Phase 6** (`skills/design/references/phases/phase-6-final-review.md`) —
three reviewers (architecture, security, structural-format), lines 21-99. Each
prompt's context is an excerpt of the DESIGN doc itself:

- Architecture reviewer: line 35 — `[Include Solution Architecture and
  Implementation Approach sections]`.
- Security reviewer: line 51 — `[Include Security Considerations section]`.
- Structural-format reviewer: line 89 — `[Include all nine required sections
  plus the frontmatter]`.

**None references the upstream PRD.** The upstream document is NOT passed into any
`/design` Phase 6 reviewer.

**`/brief` jury** (`skills/brief/references/phases/phase-4-validate.md`, two
reviewers) — Content Quality Reviewer (lines 100-178) receives only `## BRIEF to
Review` / `[Contents of docs/briefs/BRIEF-<topic>.md]` (lines 112-113). Structural
Format Reviewer (lines 180-234+) receives `## BRIEF to Review` (line 193), `##
Repo Visibility` (line 196, from `wip/brief_<topic>_context.md`), and `## Format
Reference` (line 199, `brief-format.md`). **Neither reviewer prompt includes the
upstream ROADMAP.** Not passed.

**`/plan`** — Yes, `/plan` has a review phase: Phase 6 (`skills/plan/references/phases/phase-6-review.md`)
invokes `/review-plan` as a sub-operation (line 3: "Invoke `/review-plan` as a
sub-operation against the current plan artifacts"). Unlike the three juries above,
`/review-plan`'s Category B ("Design Fidelity") check *does* read the upstream
document: `skills/review-plan/references/phases/phase-2-design-fidelity.md`,
line 11 ("Upstream design doc path (from `wip/plan_<topic>_analysis.md`)") and
line 28 ("Read the upstream design doc. Run the following checks:"), gated by
input type (lines 17-22: full check for `design`/`prd` input, empty findings for
`roadmap`/`topic`). However, this is not a parallel-spawned "reviewer agent" the
way brief/prd/design juries are — grepping `skills/review-plan/references/phases/*.md`
for `Agent tool`, `subagent`, `Task tool`, `spawn` returns no hits; `/review-plan`
runs its category checks in the calling agent's own context, not via spawned
sub-agents, and it is itself invoked as a child (`/plan` → `/review-plan`) rather
than materializing peers.

**`/strategy` Phase 4** (`skills/strategy/references/phases/phase-4-validate.md`),
altitude reviewer prompt, lines 193-197:

> ## STRATEGY to Review
> [Contents of docs/strategies/STRATEGY-<topic>.md]
>
> ## Upstream Context (if applicable)
> [Contents of the grounding document — the upstream VISION declared in
> frontmatter, or the PRD recorded at Phase 0 in grounding-PRD mode; otherwise
> "no upstream declared"]

**`/strategy`'s altitude reviewer DOES receive the upstream document** — the only
one of the four/five juries examined that does. Evaluation criteria at lines
219-230 directly test the fold-back/stand-alone properties against that upstream
content (quoted in finding 2).

Summary table:

| Skill | Jury exists | Upstream passed to reviewer? |
|---|---|---|
| `/brief` | Yes (2 reviewers) | No |
| `/prd` | Yes (3 reviewers) | No |
| `/design` | Yes (3 reviewers, Phase 6) | No |
| `/plan` | Yes, via `/review-plan` sub-invocation (not a parallel jury) | Yes, for Category B when input is `design`/`prd` |
| `/strategy` | Yes (3 reviewers, Phase 4) | Yes, altitude reviewer only |

### 4. `/scope` structure

Directory listing of `skills/scope/references/phases/`:

```
phase-0-setup.md
phase-1-discovery.md
phase-2-chain-orchestration.md
phase-3-exit-finalization.md
phase-4-cleanup.md
phase-resume.md
```

**(a) No sub-agent spawn site.** `grep -n "Agent tool\|subagent\|Task tool\|spawn"`
across all six files returns zero matches. `/scope` never spawns a sub-agent or
team in any phase file.

**(b) No row in a per-child "dispatch/team-shape" table, and `/decision` is not
invoked as a sub-operation.**

- `grep -n "/decision\b" -r skills/scope/` returns zero matches — `/scope`'s
  phase files never invoke `/decision`.
- The closest thing to a "dispatch binding table" is the per-child peer-roster
  table in `docs/designs/current/DESIGN-shirabe-child-dispatch-contract.md`,
  lines 329-335, which enumerates `child_layer.peers` for `/brief`, `/prd`,
  `/design`, `/plan`, `/vision`, `/strategy`, `/roadmap` — the seven **child**
  skills. `/scope` and `/charter` do not appear as rows in this table because
  they are the two **parent** skills the table is describing dispatch *from*,
  not children being dispatched *to*. The same design doc states explicitly
  (line 75): `/scope`'s own `## Team Shape` section "declares the parent is
  single-agent with 'no team spawned at the `/scope`-itself layer.'" This is
  consistent with (a): `/scope` has no spawn site and, structurally, cannot
  have a row in a table that only lists dispatch targets' own peer rosters.

Combined, (a) and (b) confirm `/scope` has no mechanism today to spawn any agent
(sub-agent, jury, or `/decision` invocation) that could author a contribution
section at fold time other than by direct prose-writing inside its own
single-agent context.

### 5. The absorb procedure — Stage 3 carry check (`phase-2-chain-orchestration.md`)

The three stages, all under "## Consolidation Judgment" (line 401 onward),
run as step 8 of Phase 2's eight-step per-child loop (lines 38-66), and only
when the chain produced a durable artifact above the one that just landed
(line 404-405):

- **Stage 1 — Absorbability** (lines 417-437): look up the hop in a fixed
  mapping table (lines 424-428, BRIEF→PRD / PRD→DESIGN / DESIGN→PLAN) derived
  from `crates/shirabe-validate/src/formats.rs`'s required-section contracts
  (lines 430-433). Only BRIEF→PRD is "Yes" (absorbable); PRD→DESIGN and
  DESIGN→PLAN are "No" because required upstream sections have no home
  downstream. When not total, verdict is `keep` (lines 435-437).
- **Stage 2 — Judgment** (lines 439-456): read both bodies and ask whether the
  upstream does work the downstream doesn't. `No` → `absorb`, continue to
  Stage 3; `Yes` → `keep` with a finding.
- **Stage 3 — Carry check and absorb** (lines 458-501): "walk the upstream's
  required sections one at a time and record where each landed. This is the
  receiving mechanism: an absorb that is not itemized is a recommendation, and
  a recommendation with nothing confirming the transfer is how content goes
  missing" (lines 460-464). The YAML shape (lines 466-478):

```yaml
consolidation_judgments:
  - hop: brief->prd
    absorbable: true
    carry_check:
      Problem Statement: {target: Problem Statement, carried: true}
      User Outcome:      {target: Goals, carried: true}
      User Journeys:     {target: User Stories, carried: true}
      Scope Boundary:    {target: Requirements + Out of Scope, carried: true}
    verdict: absorb
    absorbed: docs/briefs/BRIEF-<topic>.md
    into: docs/prds/PRD-<topic>.md
```

Any `carried: false` **aborts the absorb** (lines 480-483: downgrades to `keep`,
names the missing section, deletes nothing). When every section is carried, the
completion mechanics (lines 485-496) are: (1) read the absorbed artifact's own
`upstream:` value; (2) re-point the survivor's `upstream:` to that value or
remove it; (3) `git rm` the absorbed artifact; (4) re-run `shirabe validate` on
the survivor, reverting the absorb on non-zero exit.

**Which actor performs the absorb, and what writes the actual carried
content today:** `/scope` (the parent) performs the mechanical absorb steps —
the `carried: true/false` recording, the `upstream:` re-point, the `git rm`,
and the re-validate — all under Phase 2, "step 8," which lives inside `/scope`'s
own single-agent execution (confirmed by "Manual-fallback boundary", lines
511-519: "a child cannot see the chain, and a parent's invocation shape decides
whether the child's branch is reachable at all"; "there is no consolidation
code path inside a child"). But Stage 3 is explicitly a **check**, not a
drafting step: it records where content "landed" — it presumes the downstream
document's own sections (Problem Statement, Goals, User Stories,
Requirements/Out of Scope) already carry the content, because `/prd` Phase 3.2
(finding 1) drafted them that way when it read the BRIEF. Nothing in Stage 3's
text instructs `/scope` to *write* prose into the survivor; it only instructs
`/scope` to verify content is present and abort if not. There is no dedicated
"contribution section" in the survivor today — the carried content is folded
into the survivor's own ordinary required sections, and Stage 3 is the parent's
verification pass over content the child already wrote at drafting time.

### 6. Where do child skills read their upstream (file:line)

| Skill | Phase file | Line(s) | What it reads |
|---|---|---|---|
| `/brief` | `skills/brief/references/phases/phase-1-discover.md` | 46 ("Load the upstream ROADMAP and find the feature this brief frames") | Upstream ROADMAP |
| `/prd` | `skills/prd/references/phases/phase-3-draft.md` | 63 ("When an upstream BRIEF exists (Input Mode 2), read it first") | Upstream BRIEF body |
| `/design` | `skills/design/references/phases/phase-0-setup-prd.md` | 25-27 ("### 0.2 Read PRD" / "Read the PRD file from the path provided in `$ARGUMENTS`.") | Upstream PRD body |
| `/plan` | `skills/plan/references/phases/phase-1-analysis.md` | 33 ("Read the source document at the path provided in $ARGUMENTS and check the Status field.") | Upstream DESIGN (or PRD/ROADMAP) body |

All four reads happen in exactly one phase file each — a "consumption
instruction" touches four files total (one per child's entry/drafting phase),
matching the four rows above. `/design` does read the PRD body (confirmed,
`phase-0-setup-prd.md` line 25-27, "Read PRD"). `/plan` does read the DESIGN
body (confirmed, `phase-1-analysis.md` line 33, generic "Read the source
document").

### 7. File-count inventory by authorship model

**Format references** (the target schema each drafting/carry instruction would
cite):
- `skills/brief/references/brief-format.md`
- `skills/prd/references/prd-format.md`
- `skills/design/references/design-format.md`
- `skills/plan/references/plan-format.md`
(and, for the pattern already partially in place, `skills/strategy/references/strategy-format.md`)

**Child drafting phase files** (where a "contribution section" would be authored
under the child-authorship model):
- `skills/brief/references/phases/phase-2-draft.md` (or `phase-1-discover.md`,
  where the upstream ROADMAP is first loaded — brief's structural fill is
  Phase 3)
- `skills/prd/references/phases/phase-3-draft.md`
- `skills/design/references/phases/phase-0-setup-prd.md` (upstream read/carry
  point) plus whichever DESIGN drafting phase composes body sections
- `skills/plan/references/phases/phase-1-analysis.md` (upstream read) plus
  whichever PLAN drafting phase composes body sections

**Child jury/review phase files** (where a "contribution section" would need a
new evaluation criterion under the child-authorship model, or where the parent
would need to inject upstream content under the parent-fold-time model):
- `skills/brief/references/phases/phase-4-validate.md`
- `skills/prd/references/phases/phase-4-validate.md`
- `skills/design/references/phases/phase-6-final-review.md`
- `skills/plan/references/phases/phase-6-review.md` (+ `skills/review-plan/references/phases/phase-2-design-fidelity.md` for the one place upstream already flows into a plan-side check)

**`/scope` phase files holding the absorb procedure** (where a "contribution
section" would be authored/verified under the parent-fold-time model):
- `skills/scope/references/phases/phase-2-chain-orchestration.md` (the entire
  Stage 1/2/3 procedure, lines 401-519)

Rough count: the child-authorship model touches roughly 4 format references +
4-8 child phase files (drafting instructions) + 4-5 jury phase files (if the
jury needs to check the new section) = ~12-17 files, spread across five skill
directories. The parent-fold-time model concentrates changes in one file,
`skills/scope/references/phases/phase-2-chain-orchestration.md` (plus possibly
the four format references, if the contribution section needs a name in the
schema) — roughly 1-5 files, all under `/scope`.

### 8. Conditional-section precedent and validator support

**`strategy-format.md` treats Strategic Context as required, not conditional.**
The section-by-status table (`skills/strategy/references/strategy-format.md`,
line 192): `| Strategic Context | Required | Required | Required | Required |`
— required in every status column (Draft/Accepted/Active/Sunset). This is
corroborated by `crates/shirabe-validate/src/formats.rs`, Strategy's
`FormatSpec` entry (lines 205-223): `"Strategic Context"` sits inside the flat
`required_sections` list (line 212) and `execution_mode_required_sections: None`
(line 222) — no conditional override exists for Strategy. Brief's entry (lines
224-239) is likewise fully flat: `required_sections` includes all five
sections (lines 230-236), `execution_mode_required_sections: None` (line 239).

**Does `formats.rs` support conditional/optional sections at all?** Only in one
narrow, format-specific way. The `FormatSpec` struct (lines 5-38):

```rust
pub struct FormatSpec {
    pub name: String,
    pub prefix: String,
    pub schema_version: String,
    pub required_fields: Vec<String>,
    pub valid_statuses: Vec<String>,
    pub required_sections: Vec<String>,
    pub issues_table_columns: Vec<String>,
    pub private: bool,
    pub execution_mode_required_sections: Option<HashMap<String, Vec<String>>>,
}
```

`required_sections: Vec<String>` is unconditional and all-or-nothing per
format — there is no per-section "optional" or "conditional" flag in the
struct. The one escape hatch is `execution_mode_required_sections:
Option<HashMap<String, Vec<String>>>` (lines 29-37 doc comment): "When
`Some(map)` ... FC04 consults `map[execution_mode]` instead of
`required_sections`. When `None` (the default for every format except Plan)
... Plan profile populates this with `single-pr`, `multi-pr`, and
`coordinated` lists." This mechanism is Plan-specific today (only Plan's
`FormatSpec` sets it to `Some(...)`, built by `plan_execution_mode_sections()`
at lines 44-81); every other format, including Strategy and Brief, leaves it
`None`. So: the validator has exactly one conditional-requirement mechanism
(branching on a frontmatter `execution_mode` field), it is wired for exactly
one format (Plan), and it is not a general "optional section" primitive — a
brand-new "contribution section, present only when an absorb happened"
concept has no existing FormatSpec field to hang off of and would need either
a new field (e.g., an `optional_sections: Vec<String>` not checked by FC04's
presence gate) or reuse of the execution-mode mechanism under a different key.

## Assumptions made (with consequences)

- **Assumed "PRD Phase 3.2" in the prompt maps to the file's own numbering
  "3.2 Draft the PRD"** inside `phase-3-draft.md` (the file is itself "Phase
  3" of `/prd`, and its internal step numbering restarts at 3.1). If the
  decision document intends a different Phase-3/3.2 addressing scheme, the
  citation still resolves to the same file and line range; only the label
  might need adjusting. Consequence if wrong: negligible — the quoted text is
  unambiguous regardless of numbering interpretation.
- **Assumed "the two-sided adequacy wording" in strategy-format.md is the
  Quality Guidance bullet at lines 348-351**, not the near-identical
  restatement in `phase-4-validate.md` lines 219-230 or the Phase-2 drafting
  guidance. I treated the format reference's Quality Guidance section as the
  canonical contract location (it is cross-referenced by both drafting and
  jury phases) and the phase files as consumers/enforcers of that same
  contract. Consequence if wrong: the decision author may want the jury-phase
  wording (lines 219-230) cited as the "contract" instead — both locations are
  reported above so this is low-risk.
- **Assumed `/review-plan`'s Category B "Design Fidelity" check counts as part
  of `/plan`'s "jury/review phase" for Q3's purposes**, even though it is not a
  parallel-spawned multi-reviewer jury like brief/prd/design/strategy. I
  reported this distinction explicitly (single inline check vs. spawned
  reviewer agents) rather than silently equating the two, since the decision
  question's framing ("do child juries actually receive the upstream
  document") could be read either way for `/plan`. Consequence if wrong: the
  decision document should treat `/plan` as a partial/different case rather
  than a clean "yes" or "no" — the report above already frames it this way.
- **Assumed the "dispatch binding table" referred to in the prompt is the
  `child_layer.peers` table in `DESIGN-shirabe-child-dispatch-contract.md`**
  (lines 329-335), since no file/table is literally titled "dispatch binding
  table" anywhere in the repo (grep for that exact phrase and for "Dispatch
  Binding" as a heading both returned nothing). This is the only per-skill
  table found that enumerates dispatch-relevant peer/team-shape rows across
  the same seven child skills, and its absence-of-`/scope`-and-`/charter`-rows
  is corroborated independently by prose in the same document (line 75).
  Consequence if wrong: if a differently-named table exists elsewhere that I
  did not find, the "no row for /scope" conclusion should be re-verified
  against it — but the independent grep-based confirmation of (a) (no spawn
  site anywhere in scope's phase files) stands regardless.
- **Did not exhaustively read every line of `skills/design/` and `skills/plan/`
  phase files** beyond the sections needed to answer each numbered question
  (e.g., did not read all of `phase-2-execution.md` for `/design` or all of
  `phase-2-milestone.md`/`phase-3-decomposition.md` for `/plan`). If the
  decision document needs a full drafting-phase walkthrough for DESIGN or PLAN
  bodies (not just the upstream-read step), that would require a follow-up
  pass. Consequence if wrong/incomplete: finding 6's "which phase reads the
  upstream" citations are solid (confirmed by direct quotes), but "which phase
  composes the body sections that would carry a contribution" for DESIGN and
  PLAN specifically (as opposed to BRIEF/PRD, which were pinned exactly) is
  inferred rather than exactly cited in finding 7.

## Critical unknowns

- **No existing "contribution section" concept exists anywhere in the corpus.**
  All content-carrying today happens by folding upstream content into the
  downstream document's own ordinary required sections (BRIEF's four sections
  into PRD's four sections; STRATEGY's Strategic Context summarizing VISION).
  There is no doc type with a section literally labeled "Contribution from
  <upstream>" or similar, so there is no precedent to confirm whether such a
  section, if introduced, would need to be conditionally required (present
  only after an absorb) or always-present. This directly bears on finding 8's
  validator question: today's `formats.rs` has no general per-section
  optionality primitive, and Strategy's only "conditional" precedent
  (Strategic Context) is unconditionally required, not conditionally required
  based on whether an absorb happened.
- **Whether `/scope`'s Stage 3 carry check, as written, could be satisfied by
  content the parent itself writes (rather than the child) is not settled by
  the current text.** Lines 460-464 describe Stage 3 as "the receiving
  mechanism" and a check against `carried: true/false`, but do not specify who
  authored the content being checked — in practice today it works because
  `/prd` Phase 3.2 already drafted BRIEF-derived content into ordinary PRD
  sections. If a future contribution-section were added at fold time by
  `/scope` itself, Stage 3's "walk the upstream's required sections... and
  record where each landed" framing would need to be read as `/scope` writing
  new content into the survivor rather than verifying pre-existing content —
  a structurally different operation not currently described anywhere in
  `phase-2-chain-orchestration.md`.
- **Whether PRD→DESIGN and DESIGN→PLAN's "No" absorbability verdicts (Stage 1,
  lines 427-428) are permanent or could change if a contribution section were
  added as a new mapping target.** The mapping table's "No" verdicts stem from
  required upstream sections (Goals, User Stories, Requirements, Acceptance
  Criteria, Out of Scope, Decision Drivers, etc.) having "no home" in the
  downstream format's *current* required-sections list. A contribution section
  would, by construction, create exactly the missing home the table currently
  finds absent — but whether that's the intended purpose of "contribution
  section" in the decision question, or whether it's scoped only to hops that
  are already absorbable (BRIEF→PRD), is not stated in any file read during
  this research and would need to be confirmed with the decision's author or
  the DESIGN-scope-artifact-persistence context files.
