# Phase 2 Research: User researcher

Translates the brief's four User Journeys into observable `/charter`
behaviors so the PRD's User Stories and Acceptance Criteria are
anchored in what an author actually experiences. Pattern-level
findings (resume-ladder shape, exit-tracking field, visibility
gating) are tagged so the designer can lift them into the shared
design doc.

## Lead 1: Journey-to-behavior mapping

### Findings

#### Journey 1 — Standalone cold invocation (full-run path)

**Trigger.** Author opens Claude Code in a repo and types
`/charter <topic-slug>` (e.g., `/charter shirabe-charter-skill`). Their
state of mind: "I have a strategic bet I want to pressure-test from
scratch; I don't want to remember the chain order or the
artifact-decision rules." Topic slug is constrained to `[a-z0-9-]+`
(inherited from `skills/strategy/SKILL.md` Phase 0 — pattern-level).
Empty `$ARGUMENTS` lands in Cold Start: `/charter` asks "What
strategic conversation do you want to have? Provide a short topic
slug." Anything else is treated as the topic slug after kebab-case
normalization.

**Discovery prompts (Phase 1).** `/charter`'s discovery is layered on
top of the discover/converge engine `/explore` already uses
(`skills/explore/references/phases/phase-2-discover.md`). The prompts
are:

1. "What's the bet you want to pressure-test? Frame it as a
   falsifiable hypothesis we could be wrong about." (Adapted from
   `skills/strategy/SKILL.md` Phase 1 Freeform Topic mode.)
2. "Is there an existing VISION this builds on? If yes, paste the
   path; if no, I'll search `docs/visions/`."
3. "Is the long-term thesis shifting, or is this an operational layer
   below it?" — single-question router for `/vision` invocation.
   Detection signal: author claim. If "the long-term thesis is
   shifting," `/charter` enters Phase 2 with `/vision` queued. If
   "operational layer below it," `/charter` skips `/vision`.
4. "Do the building blocks look like they'll have cross-block
   dependencies an author can't sequence by inspection?" — router for
   `/roadmap` invocation. Signal: author claim plus a heuristic
   check (more than 3 candidate building blocks surfaced during Phase
   1 → recommend `/roadmap`; ≤ 3 → recommend skipping).

In Journey 1 the author confirms thesis holds → `/vision` skipped.
Public repo → `/comp` silently skipped (no prompt). `/strategy`
always runs. Cross-block dependencies confirmed → `/roadmap` queued.

**Decision points the author hits.** Three confirmation prompts:

1. After Phase 1 discovery: "Based on our conversation, here's the
   chain I propose: skip `/vision` (thesis holds), run `/strategy`,
   run `/roadmap` (multi-block coordination). Proceed, redirect, or
   bail?" Three-option `AskUserQuestion`: Proceed / Adjust chain /
   Bail (note: Bail does NOT exit silently — it routes to the
   abandonment-forced exit per the brief's hard-enforcement rule).
2. After `/strategy` completes (Draft STRATEGY landed): "STRATEGY
   Draft written at `docs/strategies/STRATEGY-<topic>.md`. Continue
   to `/roadmap`, halt here (full-run with STRATEGY only), or bail?"
3. After `/roadmap` completes: "Chain complete. STRATEGY and ROADMAP
   are both Draft. Review, ratify, then run lifecycle transition."

**Visible artifacts after the run.** Author sees:
- `docs/strategies/STRATEGY-<topic>.md` (Draft status)
- `docs/roadmaps/ROADMAP-<topic>.md` (Draft status, if Journey 1
  path took the roadmap exit)
- `wip/charter_<topic>_state.md` recording `exit: full-run` and the
  chain that ran
- `wip/strategy_<topic>_scope.md`, `wip/roadmap_<topic>_*.md` (child
  intermediates; cleaned up at chain finalization)

**What "good" looks like.** The author never re-derived chain order
or sequencing rules. The skip-`/vision` and skip-`/comp` decisions
happened without the author thinking about them. Both terminal
artifacts are Draft, ready for human review. `wip/charter_<topic>_state.md`
clearly says `exit: full-run`.

#### Journey 2 — Re-evaluation (the load-bearing journey)

**Trigger.** Author returns six weeks after the original
`/charter` run landed an Accepted STRATEGY. They invoke
`/charter <same-topic-slug>`. State of mind: "New evidence has
accumulated; I want to know whether the bet still holds." This is the
brief's novel contribution — without it, every `/charter` run is
tempted into a redundant STRATEGY revision.

**Discovery prompts (the hard part).** `/charter`'s Phase 1 resume
ladder detects `docs/strategies/STRATEGY-<topic>.md` exists with
status Accepted (or Active). Discovery's first prompt is **NOT** "Do
you want to revise?" — that prompt biases toward STRATEGY revision.
Instead `/charter` asks:

1. "An Accepted STRATEGY exists for this topic
   (`docs/strategies/STRATEGY-<topic>.md`, last updated <date>). Are
   you returning to revise the bet, or to check whether the existing
   bet still holds?" Three-option `AskUserQuestion`:
   - "Re-evaluate (check whether the bet still holds; lightweight
     exit)" — routes to re-evaluation discovery
   - "Revise (the bet needs a new STRATEGY draft)" — routes to full
     `/strategy` invocation against the existing STRATEGY path
   - "Bail (I came in by mistake)" — routes to abandonment-forced
     exit if any wip state already exists, otherwise clean cancel

2. If "Re-evaluate" selected: `/charter` reads the existing STRATEGY's
   Bet-Specific Falsifiability section and walks the author through
   each falsifiability claim with a structured prompt:

   > "The existing STRATEGY names these falsifiability conditions:
   > 1. <condition A>
   > 2. <condition B>
   > 3. <condition C>
   >
   > For each, has new evidence accumulated that flips, weakens, or
   > reinforces the claim? Paste evidence URLs/paths or describe
   > briefly."

   This is **both author claim and evidence check**. The author
   asserts which conditions are at risk; `/charter` records the
   evidence cited. If any condition is "flipped" the author is
   prompted: "This claim flipped. That likely warrants a STRATEGY
   revision rather than a re-evaluation. Switch to revision now?"
   (route back to `/strategy`).

3. Final confirmation prompt: "All falsifiability claims hold with
   the new evidence. The bet still stands. I'll write a Decision
   Record at
   `docs/decisions/DECISION-strategy-<topic>-re-evaluation.md`
   referencing the existing STRATEGY. Confirm, redirect, or bail?"

**Decision points the author hits.** Three: the entry-mode question,
the per-condition evidence prompt, and the final confirmation before
the Decision Record write.

**Visible artifacts after the run.** Author sees:
- `docs/decisions/DECISION-strategy-<topic>-re-evaluation.md` (new
  artifact; references existing STRATEGY by path)
- Existing `docs/strategies/STRATEGY-<topic>.md` unchanged (still
  Accepted/Active)
- `wip/charter_<topic>_state.md` recording `exit: re-evaluation` and
  the Decision Record path

**What "good" looks like.** No STRATEGY revision happened. No
ROADMAP regeneration happened. The Decision Record cites the
specific evidence the author reviewed and concludes the bet still
holds. The existing Accepted STRATEGY remains the live artifact. The
discipline-vs-artifact decoupling is empirically demonstrated:
strategic discipline was applied without producing a redundant
STRATEGY revision.

#### Journey 3 — Mid-chain abandonment-forced materialization

**Trigger.** Two sub-cases:
- **Sub-case A (resume + bail):** Author re-opens Claude Code a week
  after starting a `/charter` run, invokes `/charter <topic-slug>`.
  Resume ladder detects partial state (e.g.,
  `wip/strategy_<topic>_scope.md` exists, no STRATEGY Draft yet).
  Author indicates "wrap up the strategic conversation as it stands"
  rather than continuing.
- **Sub-case B (stale-session detection):** Author returns and
  invokes `/charter`. Resume ladder detects partial state AND the
  state-file `last_updated` timestamp is > 7 days old (stale-session
  threshold). `/charter` proactively asks whether to resume or
  abandon-force.

**Detection signal.** Both author intent and timestamp. `wip/charter_<topic>_state.md`
records `last_updated` on every write; the 7-day threshold
distinguishes "broke for lunch" from "abandoned for a week." Author
intent always wins — if the author says "resume," `/charter` resumes
even on a 30-day-old state file; if the author says "wrap it up,"
`/charter` force-materializes even on a 2-hour-old state file.

**Confirm/cancel prompt before force-materialization.**

> "I detected a partial `/charter` run from <date>: `/strategy`'s
> Phase 1 discover completed; STRATEGY draft not started. Three
> options:
> 1. Resume — continue from where `/strategy` left off (Phase 2).
> 2. Force-materialize — write what we have as a Draft STRATEGY with
>    a Status block noting it was abandonment-forced. The chain
>    leaves a review surface.
> 3. Discard — delete the wip/ state and start clean. This loses the
>    discovery work."

Three-option `AskUserQuestion`. "Force-materialize" is the
abandonment-forced exit; "Discard" is NOT a fourth exit path —
discarding leaves no wip state, so the next `/charter` run starts
clean and the discarded state cannot violate the terminal-artifact
contract (it never entered the contract's domain).

**Visible artifacts after the run.** Author sees:
- `docs/strategies/STRATEGY-<topic>.md` in Draft status with a Status
  block reading something like: "Status: Draft — abandonment-forced
  from `/strategy`'s partial state on 2026-05-24 by `/charter`. The
  Bet-Specific Falsifiability section is intentionally sparse;
  resume the chain or run `/strategy` directly to complete."
- `wip/charter_<topic>_state.md` recording `exit: abandonment-forced`
  and which child's partial state was materialized

**What "good" looks like.** The terminal-artifact contract held even
in the worst case (interrupted, half-finished work). A reviewer can
look at the force-materialized STRATEGY and immediately see it was
abandonment-forced (Status block makes the source obvious). The
author can ratify, discard, or re-enter the chain — but the chain
left a durable review surface.

#### Journey 4 — Reviewer redirects via manual fallback

**Trigger.** Reviewer reads a Draft STRATEGY from an earlier
`/charter` run. They decide the Building Blocks need tightening but
don't want to re-run the full chain. They invoke `/strategy
<path-to-existing-STRATEGY>` directly (using `/strategy`'s Input
Mode 2 — lifecycle verb path, or Mode 3 — VISION path if reframing
from VISION). `/strategy` runs standalone; produces a revised Draft.
`/charter` is not invoked during this step.

**What `/charter` says when the author later resumes.** Author runs
`/charter <topic-slug>` weeks later. Resume ladder detects:
- `docs/strategies/STRATEGY-<topic>.md` exists with status Draft
- `wip/charter_<topic>_state.md` exists, recording last-known
  STRATEGY checksum/timestamp from the previous `/charter` run
- STRATEGY's `last_updated` is newer than `wip/charter_<topic>_state.md`'s
  recorded STRATEGY timestamp → out-of-chain edit detected

`/charter` surfaces the detection with a concrete prompt:

> "STRATEGY at `docs/strategies/STRATEGY-<topic>.md` was edited
> outside `/charter` on <date> (revision count: <N>; last-known by
> `/charter`: <prior-date>). Any downstream ROADMAP at
> `docs/roadmaps/ROADMAP-<topic>.md` may be stale relative to the
> revised STRATEGY. Three options:
> 1. Re-run `/roadmap` against the revised STRATEGY to refresh
>    sequencing.
> 2. Accept the existing ROADMAP as still-valid (record the
>    acknowledgment in `wip/charter_<topic>_state.md`).
> 3. Proceed without ROADMAP (existing ROADMAP remains as-is; the
>    state file records the staleness ack but no regeneration)."

`/charter` warns; it does not act unilaterally. The author retains
full control. After the author chooses, `/charter` writes the choice
to the state file and continues the chain (or halts if "Accept" was
chosen and there's no further chain work).

**Decision points the author hits.** One main prompt (the staleness
ack), then the normal chain prompts for any remaining work.

**Visible artifacts after the run.** Whatever the author chose:
re-run `/roadmap` produces a fresh ROADMAP Draft; accept produces no
new artifact but updates `wip/charter_<topic>_state.md`.

**What "good" looks like.** The reviewer's manual `/strategy`
invocation worked exactly like a standalone run — `/charter` did not
interfere. When `/charter` later resumed, it noticed the out-of-chain
edit, warned about staleness, and offered three concrete options
without acting on the staleness itself. Manual fallback feels like
a first-class steady-state path, not a workaround.

### Implications for Requirements

The PRD's User Stories must capture:

- **One user story per journey** (four stories total).
- Each story must name the trigger phrasing the author uses, the
  discovery prompt sequence (verbatim quote-level — the wording is
  load-bearing), the decision points where the author can redirect
  or bail, the visible artifacts at end-of-run, and a "what good
  looks like" Acceptance Criterion.
- **Journey 2 is the load-bearing user story.** Its prompt sequence
  must be quoted verbatim in the PRD with all three confirmation
  prompts. The "re-evaluate vs revise vs bail" entry prompt is
  particularly important because it determines whether the
  discipline-vs-artifact decoupling actually holds in practice.
- **Bail does not exit silently.** Bail in any journey routes to
  abandonment-forced if wip state exists; otherwise it routes to a
  clean cancel (no wip state, no terminal artifact, no contract
  violation because the contract never engaged).
- Each user story must reference the corresponding exit type
  (full-run, re-evaluation, abandonment-forced) explicitly so the AC
  can verify the exit-tracking field in
  `wip/charter_<topic>_state.md` got set.

### Open Questions

- **Stale-session threshold tuning.** The 7-day heuristic is a
  defensible default but the brief doesn't fix it. Should it be
  configurable via CLAUDE.md, or is a fixed 7-day threshold the right
  shipping decision? Recommend fixed 7-day at v1; revisit if authors
  complain.
- **Multi-topic state collision.** If two `/charter` runs are active
  for two different topics, they have separate
  `wip/charter_<topic>_state.md` files — clean. But if an author
  invokes `/charter <topic>` while a partial state for that exact
  topic exists, the resume ladder must distinguish "intended resume"
  from "second author invoking on the same topic" (unlikely in
  practice; flag as design-team consideration).
- **Force-materialize partial `/vision`?** If the abandonment happens
  inside `/vision` (Phase 2 of `/charter`'s chain) rather than
  `/strategy`, what gets force-materialized? Recommend: a Draft
  VISION with abandonment-forced Status block. The PRD should state
  this explicitly — force-materialization applies to the
  most-recently-running child, not exclusively `/strategy`.

## Lead 2: Three exit paths as authored experiences

### Findings

#### Full-run exit

**Final user-visible message from `/charter`:**

> "Chain complete (full-run exit). Artifacts written:
> - `docs/strategies/STRATEGY-<topic>.md` (Draft)
> - `docs/roadmaps/ROADMAP-<topic>.md` (Draft) [if applicable]
>
> Review the artifacts. When ready, transition Draft → Accepted via
> `scripts/transition-status.sh <path> accept` (per shipped
> `/strategy` and `/roadmap` lifecycle conventions). Suggested next
> step: `/prd` per Building Block, or share STRATEGY for stakeholder
> review."

**What the author should do next.** Read the durable artifacts,
ratify or send for review, then run the lifecycle transition. The
routing-suggestions table (Lead 4) covers the variants.

**State-file content at end:**

```yaml
# wip/charter_<topic>_state.md
topic: <topic-slug>
chain_started: <timestamp>
chain_completed: <timestamp>
last_updated: <timestamp>
chain_ran: [discover, strategy, roadmap]  # or [discover, strategy]
chain_skipped: [vision, comp]  # with reasons
exit: full-run
exit_artifacts:
  - path: docs/strategies/STRATEGY-<topic>.md
    status: Draft
  - path: docs/roadmaps/ROADMAP-<topic>.md
    status: Draft
```

#### Re-evaluation exit

**The confirmation prompt before the Decision Record write:**

> "All falsifiability claims hold with the new evidence reviewed.
> The bet still stands. I'll write a Decision Record at
> `docs/decisions/DECISION-strategy-<topic>-re-evaluation.md`
> referencing the existing STRATEGY by path, with the evidence
> reviewed and the conclusion that the bet still holds. The existing
> STRATEGY remains Accepted; no STRATEGY revision; no ROADMAP
> regeneration. Confirm, redirect to revision, or bail?"

Three-option `AskUserQuestion`: Confirm (write the Decision Record),
Redirect to revision (route to `/strategy` for STRATEGY revision),
Bail (abandonment-forced exit).

**Drafting responsibility.** `/charter` drafts the Decision Record
body. The author confirms or edits before Accept. Body content:

- **Context** — references the original `/charter` run that produced
  the existing STRATEGY (timestamp, scope) and the trigger for this
  re-evaluation (e.g., "Author returned six weeks after the original
  run; new evidence on <topic-area> accumulated").
- **Existing STRATEGY** — full path link with status.
- **Falsifiability claims reviewed** — bullet list of each
  Bet-Specific Falsifiability claim from the existing STRATEGY, with
  per-claim evidence cited (URLs/paths/quotes from the discovery
  conversation) and a status verdict (still holds / reinforced /
  watch).
- **Conclusion** — "The bet articulated in
  `docs/strategies/STRATEGY-<topic>.md` still holds. No revision
  warranted. Re-evaluate again when <specific signal>."

The Decision Record format follows the shape used in
`skills/decision/SKILL.md`'s Phase 6 synthesis output (Context,
Assumptions, Chosen, Rationale, Alternatives Considered,
Consequences) but adapted to the re-evaluation shape: "Chosen" is
"Bet still holds, no revision"; "Alternatives Considered" is "Revise
the STRATEGY," "Force-abandon and rewrite," each rejected with the
evidence cited.

**State-file content at end:**

```yaml
topic: <topic-slug>
chain_started: <timestamp>
chain_completed: <timestamp>
last_updated: <timestamp>
chain_ran: [discover, re-evaluation]
chain_skipped: [vision, comp, strategy-revision, roadmap]  # all skipped
exit: re-evaluation
exit_artifacts:
  - path: docs/decisions/DECISION-strategy-<topic>-re-evaluation.md
    status: Draft  # author transitions to Accepted
referenced_strategy: docs/strategies/STRATEGY-<topic>.md
evidence_reviewed:  # captured from discovery conversation
  - <evidence item 1>
  - <evidence item 2>
```

**Final user-visible message:**

> "Re-evaluation complete. Decision Record written at
> `docs/decisions/DECISION-strategy-<topic>-re-evaluation.md`. The
> existing STRATEGY at `docs/strategies/STRATEGY-<topic>.md` remains
> Accepted. Review the Decision Record, then transition to Accepted
> via `scripts/transition-status.sh`. Suggested next step: schedule
> the next re-evaluation when <specific signal>."

#### Abandonment-forced exit

**Detection trigger.** Both sub-cases of Journey 3 (resume + bail
confirmation, OR stale-session timestamp > 7 days plus author
selecting "Force-materialize" or "Wrap it up"). The detection itself
is automatic; the force-materialization always requires explicit
author confirmation. There is no silent force-materialize.

**Confirm/cancel prompt** (already quoted in Journey 3 above):
three-option `AskUserQuestion` — Resume / Force-materialize /
Discard.

**Status block content on the force-materialized artifact:**

```
Status: Draft

This artifact was abandonment-forced by `/charter` on 2026-05-24.

- Triggering child: `/strategy` (Phase 1 discover completed; Phase 2
  draft not started)
- Original `/charter` run started: 2026-05-15
- Force-materialization confirmed by: <author> on 2026-05-24
- Completeness: <which sections are intentionally sparse>

To finish properly: run `/strategy
docs/strategies/STRATEGY-<topic>.md` directly, OR re-invoke
`/charter` and resume.
```

The Status block makes the artifact's provenance unambiguous to any
reviewer.

**State-file content at end:**

```yaml
topic: <topic-slug>
chain_started: <timestamp>
chain_completed: <timestamp>
last_updated: <timestamp>
chain_ran: [discover, strategy-partial]  # partial run noted
chain_skipped: [vision, comp, roadmap]  # the rest
exit: abandonment-forced
exit_artifacts:
  - path: docs/strategies/STRATEGY-<topic>.md
    status: Draft
    note: abandonment-forced from /strategy partial state
triggering_child: /strategy
partial_phase_reached: discover  # the last completed sub-phase
```

**Final user-visible message:**

> "Chain ended at abandonment-forced exit. Draft STRATEGY written at
> `docs/strategies/STRATEGY-<topic>.md` with abandonment-forced
> Status block. Review the artifact; ratify, discard, or re-enter
> the chain via `/charter <topic>` or `/strategy
> docs/strategies/STRATEGY-<topic>.md` directly. The
> terminal-artifact contract has held; the chain left a review
> surface."

### Implications for Requirements

The PRD must include a **Three Exit Paths** section with one
sub-section per exit. Each sub-section must specify:

- The trigger (when this exit fires)
- The confirmation prompt (verbatim, as the contract surface)
- The drafting responsibility (`/charter` writes vs author writes)
- The artifact's Status block content (verbatim shape for
  abandonment-forced; section content for re-evaluation Decision
  Record)
- The state-file content at end (YAML schema for `exit:` and
  related fields)
- The final user-visible message (verbatim)

The state file's `exit:` field is **the contract enforcement
mechanism.** A finalization check at the end of `/charter` must
verify `exit` is one of `full-run | re-evaluation |
abandonment-forced`. If unset or any other value, finalization
fails and `/charter` must either fix or abort with a clear error.

Pattern-level note: the state-file YAML schema (with `exit:`,
`chain_ran:`, `chain_skipped:`, `exit_artifacts:`) is reusable
across all parent skills. The designer should lift this schema
shape into the shared design as the parent-skill state-file
contract.

### Open Questions

- **Decision Record schema validation.** Does `shirabe validate`
  have rules for `docs/decisions/DECISION-*.md` files today?
  Recommend: PRD lists "extend `shirabe validate` to recognize
  re-evaluation Decision Records" as either in-scope or as an Open
  Question for the design phase. If the Decision Record format
  needs a schema definition file (parallel to
  `references/strategy-format.md`), that work either lands in
  `/charter`'s ship or is deferred to a follow-on.
- **Status block format consistency.** The abandonment-forced Status
  block format is `/charter`-specific; the STRATEGY format spec in
  `references/strategy-format.md` may not accommodate this. Either
  the STRATEGY format gets extended (in-scope) or
  abandonment-forced STRATEGYs use a `<!-- charter-status-block
  -->` HTML comment marker (less invasive, in-scope). Recommend the
  latter.
- **Decision Record name collision.** Two re-evaluations of the
  same STRATEGY in different months would collide on the filename
  `DECISION-strategy-<topic>-re-evaluation.md`. Should the path
  include a date suffix? Recommend:
  `DECISION-strategy-<topic>-re-evaluation-<YYYY-MM-DD>.md` to
  avoid collision; PRD calls this out.

## Lead 3: Visibility-gated discovery prompts

### Findings

#### Public repo author experience

`/charter` Phase 0 reads CLAUDE.md's `## Repo Visibility:` header
(pattern inherited from `skills/strategy/SKILL.md` lines 116-121 and
`skills/explore/SKILL.md` lines 138-148). If `Public`, `/charter`
sets internal flag `comp_allowed = false`.

The author-facing prompts in Phase 1 never mention competitive
analysis at all. The chain-proposal prompt at end of discovery reads
(for a public repo):

> "Based on our conversation, here's the chain I propose: [skip
> `/vision` (thesis holds) | run `/vision`], run `/strategy`, [run
> `/roadmap` | skip `/roadmap`]. Proceed, redirect, or bail?"

Notice: no `/comp` option appears. No "competitive analysis"
language appears. The author sees a 3-child chain (vision, strategy,
roadmap) with no awareness that `/comp` exists as a chain member at
all. This satisfies the brief's contract: "the skill never asks
about competitive analysis in a repo where the content would be
inappropriate."

#### Private repo author experience

For a private repo (CLAUDE.md `## Repo Visibility: Private`), the
flag `comp_allowed = true` AND the `/comp` skill must exist on disk.
The discovery's chain-proposal prompt adds the `/comp` option:

> "Based on our conversation, here's the chain I propose: [skip
> `/vision` | run `/vision`], optionally run `/comp` for competitive
> framing, run `/strategy`, [run `/roadmap` | skip]. Proceed,
> redirect, or bail?"

If the author wants `/comp` in the chain they confirm; if they want
it skipped they redirect ("skip `/comp`"). The brief's "offered as
an optional discovery feeder" translates to: `/comp` is offered with
a recommended default of OFF unless Phase 1 discovery surfaced
competitive-framing signals (e.g., author mentioned competitors, the
bet is framed against an external alternative, etc.). When such
signals exist, `/charter` recommends ON.

Concrete recommended-ON prompt variant:

> "Your topic mentions <competitor name>. Run `/comp` for explicit
> competitive framing before `/strategy`? Recommended: yes — the
> competitive frame will sharpen the Defensibility Thesis."

Concrete recommended-OFF prompt variant (default):

> "Optional: run `/comp` for competitive framing before `/strategy`?
> Recommended: skip unless you want a Competitive Analysis section
> in the eventual STRATEGY."

#### Behavior when `/comp` is unshipped (current state)

The brief and scope both say: skill-existence check; private repos
silently degrade to "documented-but-disabled" when `/comp`
SKILL.md is not on disk. The author-facing behavior must remain
silent — no "skill not yet shipped" message surfaces.

Concretely: `/charter` Phase 0 checks `skills/comp/SKILL.md` exists.
If not, `comp_allowed = false` regardless of visibility. The chain
proposal in private repos looks identical to a public repo's chain
proposal (no `/comp` mentioned, no "skill not yet shipped" warning).
This matches the scope doc's commitment: "When `/comp` lands, the
contract becomes live with no additional `/charter` change needed."

Verification against scope-doc commitment: the scope doc's In Scope
section says the `/comp` contract becomes live with no additional
`/charter` change when the skill lands. The mechanism — Phase 0
skill-existence check + silent degradation in the absence of the
skill — satisfies this commitment.

### Implications for Requirements

The PRD must specify:

- **Visibility detection** inherits from `skills/strategy/SKILL.md`'s
  Phase 0 pattern (read CLAUDE.md `## Repo Visibility:` header;
  infer from path if missing; default to Private). Pattern-level
  (lift into shared design).
- **`comp_allowed` flag computation:** `(visibility == Private) AND
  (skills/comp/SKILL.md exists on disk)`. `/charter`-specific.
- **Public-repo prompt invariant:** Phase 1 discovery and chain
  proposal must never mention `/comp`, competitive analysis,
  competitive framing, or anything related, regardless of what the
  author types. This is a hard rule the PRD calls out as a test
  point ("AC: invoke `/charter` in a public repo with topic mentioning
  'competitor'; verify no `/comp` prompt appears").
- **Private-repo, `/comp`-unshipped invariant:** behavior degrades
  silently to the public-repo experience for the chain proposal. No
  "skill not yet shipped" surface. AC: with `skills/comp/SKILL.md`
  absent, verify private-repo `/charter` invocation produces the
  same chain-proposal prompt as a public-repo invocation. Identical
  output.
- **Private-repo, `/comp`-shipped invariant:** chain proposal
  surfaces the optional `/comp` step with a recommended default
  derived from Phase 1 signals (competitive-framing keywords in the
  conversation → recommend ON, else recommend OFF).

### Open Questions

- **Competitive-framing keyword detection.** The recommended-ON
  variant requires `/charter` to detect "competitive framing
  signals" during Phase 1. Is this a keyword match, an
  LLM-judgment call (the agent decides), or a structured prompt?
  Recommend: agent judgment, with the PRD specifying broad
  categories (competitor name mentioned, bet framed against
  external alternative, market-share language). Avoid hard keyword
  lists.
- **Visibility downgrade attack.** If a public repo's CLAUDE.md is
  missing the `## Repo Visibility:` header, the default is Private
  (per shipped `/strategy` skill, which says "Default to Private if
  unknown — restricting is easier to undo than oversharing"). For
  `/charter` this means a public repo without the header would
  surface `/comp`. Recommend: PRD calls this out as a known
  limitation and recommends an authoring guideline that every
  public repo's CLAUDE.md must have the header. AC: `/charter` warns
  loudly if the header is missing.

## Lead 4: Routing suggestions after `/charter` completes

### Findings

Modeled after the shipped `/strategy` SKILL.md routing table (lines
220-227). `/charter`'s routing suggestions differ from `/strategy`'s
because `/charter` has three exit paths instead of one.

**Routing table for the PRD's user-story section:**

| Exit type | Situation | Recommended next step | Why |
|-----------|-----------|----------------------|-----|
| Full-run | STRATEGY Draft + ROADMAP Draft both written | Author review of both artifacts; `scripts/transition-status.sh` for each when satisfied | Two-artifact human-review surface; both need ratification before downstream `/prd` work |
| Full-run | STRATEGY Draft only (no ROADMAP) | Author review of STRATEGY; `/prd` per Building Block once Accepted | Single building-block scope; no cross-block sequencing needed |
| Full-run | STRATEGY + ROADMAP both Accepted (lifecycle transitions done) | `/prd` per ROADMAP Building Block, in the order ROADMAP sequences | ROADMAP's sequencing is the input to per-feature PRD work |
| Re-evaluation | Decision Record written; existing STRATEGY unchanged | Author review of Decision Record; transition to Accepted; schedule next re-evaluation when triggering signal recurs | The bet still holds; no downstream work needed; future re-evaluation is the only follow-on |
| Abandonment-forced | Draft STRATEGY (or VISION) with abandonment-forced Status block | Author reviews force-materialized artifact; **decides** ratify / discard / re-enter chain | The author owns the decision; `/charter` does not automatically route because the artifact's completeness varies |

The routing table is presented to the author in the final-message
section of each exit. For full-run and re-evaluation exits the
recommendations are deterministic (the chain completed under
discipline). For abandonment-forced the routing is intentionally
underspecified — the author owns the call.

### Implications for Requirements

The PRD must include a **Post-`/charter` Routing** sub-section
specifying:

- The exact routing table above, as `/charter`'s final-message
  surface.
- AC: at end of each exit, `/charter` outputs the appropriate
  routing-table row(s) verbatim. This matches the precedent set by
  shipped `/strategy` (its routing table is part of its post-Accept
  user-facing output).
- For abandonment-forced exits, the routing table makes clear the
  author owns the decision. No auto-routing.

The user stories should reference this routing surface:

- "As a skill author whose `/charter` run completed full-run with a
  STRATEGY Draft, I see a routing suggestion to `/prd` per Building
  Block (or review/ratify first) and can follow without re-deriving
  the next step."
- "As a skill author whose `/charter` run completed re-evaluation, I
  see a routing suggestion to schedule the next re-evaluation when
  a triggering signal recurs and am NOT prompted toward STRATEGY
  revision."
- "As a skill author whose `/charter` run completed
  abandonment-forced, I see the artifact's Status block and three
  follow-on options (ratify, discard, re-enter) without being
  forced into one."

## Summary

The four User Journeys translate cleanly into four observable
`/charter` behaviors, each centered on a distinct discovery-prompt
sequence and exit path. Journey 2 (re-evaluation) is the
load-bearing user story: its entry prompt must offer "Re-evaluate vs
Revise vs Bail" as the first question, with the per-falsifiability
evidence walk-through as the discipline mechanism — both author
claim and evidence are required, and any "flipped" claim routes back
to STRATEGY revision rather than allowing a re-evaluation exit on
shaky ground. The three exit paths each have a contract surface
(final user message, state-file `exit:` field, artifact Status
block) that the PRD must specify verbatim, with the state file's
`exit:` field as the hard-enforcement mechanism (finalization
fails if unset or invalid). Visibility gating is fully silent in
public repos and in `/comp`-unshipped private repos — the chain
proposal never mentions competitive analysis under those conditions
— while shipped `/comp` private repos surface `/comp` with a
recommended default derived from Phase 1 signals. The routing
suggestions table (five rows covering all exit-type × artifact-state
combinations) gives the PRD a concrete final-message surface that
matches the shipped `/strategy` skill's precedent.
