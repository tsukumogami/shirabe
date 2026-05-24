# Phase 2 Research: Current-state analyst

Maps how the shipped child skills (`/strategy`, `/vision`, `/roadmap`,
`/decision`) actually behave on disk today, so `/charter`'s delegation
contracts and resume ladder can bind precisely against the existing
surfaces.

## Lead 1: /strategy contract

### Findings

`/strategy` lives at `skills/strategy/SKILL.md` (+ six phase files under
`skills/strategy/references/phases/` and one `strategy-format.md`).

**Four Input Modes** (from SKILL.md "Input Modes" + phase-0-setup.md "0.1
Detect Entry Mode"):

1. **Empty** (`$ARGUMENTS` is empty/whitespace) → cold start; Phase 1 asks
   the user what strategic conversation they want.
2. **Existing STRATEGY path with lifecycle verb** (`accept`, `activate`,
   `sunset`) → executes the lifecycle transition via
   `skills/strategy/scripts/transition-status.sh`. `sunset` requires a
   reason argument. This is the *only* mode that accepts a STRATEGY path.
3. **Path to a VISION** (`docs/visions/VISION-*.md`) → treats it as
   upstream; derives the bet candidate from VISION content during Phase
   1. Phase 0 *also* accepts `docs/prds/PRD-*.md` as upstream (the SKILL
   header lists VISION explicitly; phase-0-setup.md `0.1` table and `0.3`
   canonicalization both accept PRD or VISION basenames).
4. **Anything else** → freeform topic; Phase 1 runs a directed
   conversation to elicit the bet.

**Phase 0 slug + path canonicalization** (load-bearing for `/charter`):

- `<topic>` slug MUST match `^[a-z0-9-]+$`. Phase 0 rejects topics with
  `.`, `/`, `_`, whitespace, or that start/end with `-`. Derivation rules
  (phase-0-setup.md `0.2`):
  1. From an upstream path: take basename, strip `PRD-`/`VISION-` prefix
     and `.md` suffix, use the remainder.
  2. From freeform string: lowercase, replace whitespace + underscores
     with `-`, strip everything outside `[a-z0-9-]`.
  3. Empty: ask the user.
- Upstream path canonicalization (phase-0-setup.md `0.3`): resolve
  against repo root, resolve symlinks, reject if outside repo working
  tree, verify file exists + has `PRD-` or `VISION-` basename. Rejection
  aborts the invocation — does NOT silently fall through to freeform.

**Phase 1 entry-mode branches and on-disk artifacts** (phase-1-discover.md
`1.1`):

| Mode | What Phase 1 does | wip/ artifact written |
|------|-------------------|------------------------|
| Upstream VISION | Loads VISION; identifies the slice this STRATEGY operationalizes; drafts bet candidate; sketches Strategic Context carry-forward. | `wip/strategy_<topic>_discover.md` |
| Upstream PRD | Loads PRD; identifies the implicit bet; drafts bet candidate grounded in PRD goals; sketches what STRATEGY adds vs what PRD already covers. | `wip/strategy_<topic>_discover.md` |
| Freeform topic | Short directed conversation: bet articulation → upstream probe → org-scope-without-VISION check → 1-2 altitude questions. | `wip/strategy_<topic>_discover.md` |
| Cold start | Asks the user to redirect into one of the above (VISION path, PRD path, topic, or suggest `/explore`). | `wip/strategy_<topic>_discover.md` (after redirect) |

**Filename ambiguity resolution.** There are TWO separate Phase 1 wip files,
not one. SKILL.md's Resume Logic is missing `_discover.md` entirely and
references `_scope.md` — but `_scope.md` is NEVER WRITTEN. The on-disk
shape per the phase files is:

- `wip/strategy_<topic>_context.md` — written by phase-0-setup.md `0.5`.
  Holds entry mode, upstream path, topic slug, visibility, scope, and a
  `## Phase` line that subsequent phases update.
- `wip/strategy_<topic>_discover.md` — written by phase-1-discover.md
  `1.4`. Holds bet candidate, Strategic Context anchor, Building Blocks
  sketch, altitude notes, open questions.
- `wip/research/strategy_<topic>_phase4_{bet-quality,altitude,structural-format}.md`
  — written by phase-4-validate.md jury reviewers at pinned paths.

The string `wip/strategy_<topic>_scope.md` referenced in SKILL.md's
Resume Logic ladder is a documentation bug: the file is not produced by
any phase. SKILL.md ladder line `wip/strategy_<topic>_scope.md exists →
Resume at Phase 2` should read `wip/strategy_<topic>_discover.md exists`
to match what phase-1-discover.md actually writes.

**Phase 4 Jury (three reviewers, parallel)**:

Reviewers (each writes to a pinned path):

- Bet quality → `wip/research/strategy_<topic>_phase4_bet-quality.md`.
  Tests Defensibility Thesis falsifiability, claim concreteness,
  invalidation-condition observability, corrective-action concreteness,
  both-failure-axes coverage.
- Altitude → `wip/research/strategy_<topic>_phase4_altitude.md`. Tests
  carry-forward without re-justification, Strategic Context standalone-ness,
  no sequenced feature decomposition, Building Blocks granularity rubric,
  Coordination Dependencies altitude, org-scope-without-VISION handling.
- Structural format → `wip/research/strategy_<topic>_phase4_structural-format.md`.
  Tests frontmatter validity, eight required sections in order, R8
  visibility-gating (Competitive Considerations forbidden in Public),
  Open Questions only when Draft, Downstream Artifacts durability (no
  `wip/...` paths), private-content-leakage scan, no placeholders,
  frontmatter `bet:` ↔ Defensibility Thesis consistency, Sunset reason.

Each reviewer emits a literal `**Verdict:** PASS | FAIL` marker that the
orchestrator parses character-for-character.

Aggregation (phase-4-validate.md `4.3`):

- All 3 PASS → minor fixes if any, then Phase 5.
- 1-2 FAIL minor only → fix in place, surface summary, proceed.
- Any FAIL with significant issues → AskUserQuestion loop back to Phase
  2 or 3, OR apply targeted fixes and re-run jury.

Phase 5 finalize requires explicit human approval via AskUserQuestion —
*jury PASS alone is not enough* to transition Draft → Accepted
(phase-5-finalize.md `5.2`).

**Does `/charter` need to wait for jury PASS?** Two distinct questions:

- Does `/charter` need to wait for `/strategy` to **finish** (i.e., Phase
  5 transition)? **No**, only if `/charter`'s exit is the full-run path
  and it wants a transitioned Accepted STRATEGY. The brief explicitly
  says "a Draft STRATEGY (and optional ROADMAP) lands; chain halts at
  durable artifact for human review." That's Phase 5 completion in
  Draft-staying-Draft (if user picks "Approve" at 5.2 it goes Accepted;
  the brief lets either land).
- Does `/charter` need to wait for Phase 4 jury PASS specifically? **The
  brief's full-run exit lands a "Draft STRATEGY".** A Draft STRATEGY
  exists from Phase 3 onward. Phase 4 validates it; Phase 5 transitions
  it (with user approval). `/charter` SHOULD wait through Phase 4 so
  that the Draft delivered to the human reviewer is jury-cleared (else
  the "review surface" exit promise is hollow). The cleanest contract:
  `/charter` invokes `/strategy` and lets `/strategy` run to its own
  Phase 5 termination (Approve/Request-changes/Reject); `/charter` only
  decides next-child invocation once `/strategy` exits.

**Full Resume Logic ladder** (SKILL.md lines 158-169, verbatim):

```
STRATEGY exists with status "Accepted" or "Active"      -> Offer to revise or start fresh
STRATEGY exists with status "Draft"                      -> Offer to continue from Phase 2 or 3
wip/research/strategy_<topic>_phase4_*.md files exist    -> Resume at Phase 4 (aggregate)
STRATEGY has Building Blocks section                     -> Resume at Phase 4
STRATEGY has Defensibility Thesis section                -> Resume at Phase 3
wip/strategy_<topic>_scope.md exists                     -> Resume at Phase 2  [BUG: file never written; should be _discover.md]
On a branch related to the topic                         -> Resume at Phase 1
On main or unrelated branch                              -> Start at Phase 0
```

**Output artifact**: `docs/strategies/STRATEGY-<topic>.md`, lifecycle
`Draft → Accepted → Active → Sunset`. Sunset moves the file to
`docs/strategies/sunset/`; Draft → Accepted and Accepted → Active do
not move the file.

### Implications for Requirements

PRD MUST specify, at requirements altitude:

1. **`/charter` → `/strategy` invocation contract.** `/charter` passes
   whatever upstream its own discovery surfaced — a VISION path, a PRD
   path, OR a freeform topic string. **Never a STRATEGY path** — that's
   `/strategy`'s lifecycle-verb mode, not the create-new mode. The brief
   already names this; PRD re-states.
2. **Slug parity.** The `<topic>` slug `/charter` produces from its own
   Phase 0 must satisfy `/strategy`'s `^[a-z0-9-]+$` constraint, since
   the same slug flows through to `wip/strategy_<topic>_*.md`. If
   `/charter` derives its own topic slug, the derivation must reject any
   slug `/strategy` would also reject.
3. **Path canonicalization parity.** Any upstream path `/charter` hands
   off (VISION or PRD) must already be canonicalized against the repo
   working tree. `/strategy` re-canonicalizes (defensive depth) but
   `/charter`'s contract should be: hand off a canonical path or a
   freeform topic string, never an unchecked path.
4. **Resume-ladder composition with the documented bug.** The PRD's
   resume ladder for the `/strategy` segment of the chain should look
   for `wip/strategy_<topic>_discover.md` (not `_scope.md`) to detect a
   partial Phase 1 run. The SKILL.md ladder doc bug should be either
   (a) treated as a known issue and `/charter` reads `_discover.md`
   defensively, or (b) flagged for a separate fix in `/strategy`. Out of
   scope per the brief ("Revisions to the `/strategy` SKILL.md" is
   excluded), so option (a) is the path.
5. **Phase-4 wait semantics.** `/charter` waits for `/strategy` to run
   to its own Phase 5 termination (Approve / Request changes / Reject)
   before deciding the next child. `/charter` does NOT inspect the
   intermediate `wip/research/strategy_<topic>_phase4_*.md` verdict
   files directly — those are `/strategy`'s internals. `/charter`'s
   contract reads the STRATEGY file's frontmatter `status:` value to
   decide what comes next (Accepted → consider `/roadmap`; Draft persisted
   → halt at full-run exit; rejected/deleted → halt at abandonment-forced).
6. **Reject-path handling.** If `/strategy` Phase 5 takes the Reject
   branch, it `git rm`s the STRATEGY file and exits. `/charter`'s
   contract must handle the "no STRATEGY exists after `/strategy` exit"
   case — likely a third-exit-flavour: user rejected the bet entirely,
   abandonment-forced fires against the most-recent intermediate
   (probably `/vision`'s output or, if no `/vision` ran, the `/charter`
   discovery output itself).

### Open Questions

- The SKILL.md `_scope.md` typo in the Resume Logic ladder is real. PRD
  should mention this as a known asymmetry `/charter` accommodates. Is
  there an appetite to file a follow-up issue against `/strategy` to fix
  the ladder text? (Brief says out of scope for `/charter` ship.)
- `/strategy` Phase 5 "Reject" deletes the STRATEGY file. Is the
  abandonment-forced exit the right fallback, or should `/charter` treat
  Reject as a fourth class of exit (deliberate-rejection)? Brief names
  three exits; a Reject branch is genuinely a fourth shape.
- The `/strategy` Phase 5 "Approve" branch transitions Draft → Accepted.
  Brief says the full-run exit lands a "Draft STRATEGY". If user picks
  Approve, the STRATEGY is Accepted, not Draft, when `/charter` halts.
  PRD should clarify: full-run exit lands at `/strategy`'s exit state,
  whether that's Draft (if user chose Request-changes that didn't loop)
  or Accepted.

---

## Lead 2: /vision and /roadmap contracts

### Findings

**`/vision` (`skills/vision/SKILL.md`)**

Input Modes (3, not 4):

1. **Empty** — ask the user what project/org to define a vision for.
2. **Existing VISION path with lifecycle verb** (`accept`, `activate`,
   `sunset`) — transition via `skills/vision/scripts/transition-status.sh`.
3. **Anything else** — starting topic for Phase 1 scoping.

Notably, `/vision` does NOT accept an upstream path as input — VISION
sits at the top of the chain. There IS a handoff input: if
`wip/vision_<topic>_scope.md` exists (written by `/explore` Phase 5),
`/vision` skips Phase 1 and proceeds to Phase 2.

**Phase structure** (5 phases): Phase 0 SETUP → Phase 1 SCOPE
(conversational, skipped on handoff) → Phase 2 DISCOVER (parallel
research agents) → Phase 3 DRAFT → Phase 4 VALIDATE (jury).

**Output**: `docs/visions/VISION-<topic>.md`, lifecycle `Draft → Accepted
→ Active → Sunset`. Sunset moves files to `docs/visions/sunset/`.

**Resume Logic ladder**:

```
VISION exists with status "Accepted" or "Active"       -> Offer to revise or start fresh
VISION exists with status "Draft"                       -> Offer to continue from Phase 3
wip/research/vision_<topic>_phase2_*.md files exist     -> Resume at Phase 3
wip/vision_<topic>_scope.md exists                      -> Resume at Phase 2
On a branch related to the topic                        -> Resume at Phase 1
On main or unrelated branch                             -> Start at Phase 0
```

(Note: `wip/vision_<topic>_scope.md` IS real here — `/vision`'s scope
file is the handoff artifact from `/explore`, written explicitly.
Different from `/strategy`'s _scope ghost.)

**`/charter` → `/vision` invocation signal**: brief says "if the
long-term thesis is shifting". `/vision` itself has no "is this a
revision-of-existing" auto-detection beyond its Resume Logic ladder
("VISION exists with status Accepted/Active → Offer to revise or start
fresh"). The detectable signal `/charter` can use is:

- Read `docs/visions/` for an existing VISION matching the topic slug or
  scope. If one exists with status Accepted/Active, the long-term thesis
  is *codified*; the question is whether it's *shifting*.
- The signal that the thesis is shifting must come from `/charter`'s own
  Phase 1 discovery conversation — ask the author whether the bet they
  want to articulate operationalizes the existing VISION as-is, or
  whether the VISION's thesis needs revision. This is an author-stated
  signal, not a derivable one. `/charter` cannot infer "thesis is
  shifting" from upstream content alone.

**`/roadmap` (`skills/roadmap/SKILL.md`)**

Input Modes (3):

1. **Empty** — ask what initiative/theme.
2. **Existing ROADMAP path with lifecycle verb** (`activate`, `done`) —
   transition.
3. **Anything else** — starting topic.

PLUS a `--upstream <path>` flag (typically a VISION path) that gets
written to ROADMAP frontmatter during Phase 3. Passed by `/explore`
when it identifies a VISION, or by user explicitly. The brief notes
`/charter` should invoke `/roadmap` after a STRATEGY lands — so
`/charter` likely passes `--upstream <strategy-path>` (NOT a VISION
path) so the ROADMAP traces to the bet it sequences.

**Whether `--upstream` accepts a STRATEGY path**: SKILL.md says "Typically
points to a VISION document" but doesn't restrict by basename. The
`/roadmap` Phase 0 / Phase 1 references would need to be read to confirm
STRATEGY upstream is also acceptable. The SKILL header allows it
logically — a roadmap can derive from a STRATEGY's Building Blocks.

**Handoff input**: like `/vision`, `/roadmap` checks for
`wip/roadmap_<topic>_scope.md` from an `/explore` Phase 5 handoff. If
present, skip Phase 1.

**Phase structure** (5 phases): Phase 0 SETUP → Phase 1 SCOPE → Phase 2
DISCOVER → Phase 3 DRAFT → Phase 4 VALIDATE (jury).

**Output**: `docs/roadmaps/ROADMAP-<topic>.md`, lifecycle `Draft → Active
→ Done` (no Accepted state, no Sunset state — different from VISION and
STRATEGY). No directory movement at any lifecycle stage.

**Critical constraint**: minimum 2 features. Single-feature work is
rejected (use a PRD instead).

**Resume Logic ladder**:

```
ROADMAP exists with status "Active" or "Done"              -> Offer to revise or start fresh
ROADMAP exists with status "Draft"                         -> Offer to continue from Phase 3
wip/research/roadmap_<topic>_phase2_*.md files exist       -> Resume at Phase 3
wip/roadmap_<topic>_scope.md exists                        -> Resume at Phase 2
On a branch related to the topic                           -> Resume at Phase 1
On main or unrelated branch                                -> Start at Phase 0
```

**`/charter` → `/roadmap` invocation signal**: brief says "if the
strategy decomposes into coordinated multi-block work". `/roadmap` itself
enforces ≥ 2 features and checks dependency awareness. The STRATEGY
produced by `/charter`'s preceding `/strategy` invocation has a
**Building Blocks** section (5-8 blocks per the altitude rubric, per
phase-4-validate.md) AND a **Coordination Dependencies** section that
maps block-to-block ordering. The detectable signal `/charter` can use:

- Read the just-produced STRATEGY's Building Blocks section. Count
  blocks. If only 1-2, skip `/roadmap` (PRD altitude). If 3+ blocks
  with explicit Coordination Dependencies, invoke `/roadmap`.
- This is derivable from the STRATEGY content `/charter` already
  produced. Brief's signal IS detectable.

### Implications for Requirements

PRD MUST specify:

1. **`/charter` → `/vision` invocation rule.** `/charter` invokes
   `/vision` when (a) no Accepted/Active VISION exists matching the
   topic/scope, OR (b) the author's `/charter` Phase 1 discovery
   indicates the long-term thesis is shifting. Item (a) is detectable
   from `docs/visions/`; item (b) is a conversational signal that
   `/charter` Phase 1 surfaces. The PRD should name both signals
   explicitly.
2. **`/charter` → `/vision` input contract.** `/charter` passes the topic
   slug (and any discovery-surfaced scoping). `/vision` doesn't accept
   upstream paths, so there's no upstream to hand off. `/charter` can
   write a `wip/vision_<topic>_scope.md` handoff artifact pre-populated
   with `/charter`'s discovery to skip `/vision`'s Phase 1 — analogous
   to `/explore`'s Phase 5 handoff. This is the cleanest contract since
   it avoids `/vision` re-doing scoping `/charter` already did.
3. **`/charter` → `/roadmap` invocation rule.** `/charter` invokes
   `/roadmap` when the just-produced STRATEGY's Building Blocks section
   contains 3+ blocks with explicit Coordination Dependencies. PRD names
   the threshold and the signal source.
4. **`/charter` → `/roadmap` input contract.** `/charter` passes the
   topic slug and `--upstream <strategy-path>` pointing at the STRATEGY
   just produced. The PRD must specify that `/roadmap`'s `--upstream`
   accepts a STRATEGY path (currently documented as "typically VISION"
   — needs explicit allowance for STRATEGY, or `/charter` falls back to
   passing the upstream VISION instead of the STRATEGY).
5. **Handoff-artifact convention.** For both `/vision` and `/roadmap`,
   `/charter` can pre-populate `wip/{vision|roadmap}_<topic>_scope.md`
   to skip Phase 1 of the child. This mirrors `/explore` Phase 5
   convention. PRD should name this as the handoff mechanism.
6. **Lifecycle deltas matter.** `/vision` and `/strategy` have a Draft →
   Accepted → Active → Sunset lifecycle. `/roadmap` has Draft → Active →
   Done (no Accepted, no Sunset). `/charter`'s "is this child healthy"
   resume check uses different status words per child.

### Open Questions

- `/roadmap`'s `--upstream` documented use is VISION; does it also
  accept STRATEGY? Behavior under STRATEGY upstream needs verification
  by reading `skills/roadmap/references/phases/phase-3-draft.md`. If
  STRATEGY isn't supported, either (a) `/charter` passes the upstream
  VISION instead (losing the STRATEGY trace), or (b) `/roadmap` needs a
  minor accommodation (which would violate the brief's
  "Revisions-to-children-out-of-scope" boundary).
- `/vision`'s handoff convention writes `wip/vision_<topic>_scope.md`.
  If `/charter` writes this file from its own Phase 1, what schema must
  the file follow? `/explore` Phase 5 has a documented format; PRD
  should require `/charter` follow the same schema or, if not exactly
  the same, surface the schema delta explicitly.

---

## Lead 3: /decision for re-evaluation exit

### Findings

`/decision` (`skills/decision/SKILL.md`) is NOT the right skill for the
brief's `docs/decisions/DECISION-strategy-<scope>-re-evaluation.md`
artifact. Here's why:

**`/decision`'s output is NOT a Decision Record at
`docs/decisions/`.** Per skills/decision/references/phases/phase-6-synthesis.md
section `6.3`, `/decision` writes a single file at
`wip/<prefix>_report.md` using the canonical decision-block format
(`<!-- decision:start id="..." status="..." -->` block with Context,
Assumptions, Chosen, Rationale, Alternatives Considered, Consequences).
This block is designed to be embedded into a parent design doc's
Considered Options section, OR consumed as a standalone-ADR-style block.
But `/decision` itself does NOT promote the file to `docs/decisions/`,
does NOT name it `DECISION-*.md`, and does NOT manage an ADR lifecycle.

**`/decision`'s input contract** (phase-0-context.md `0.1`):

- Standalone: `/decision <question>` — parses `$ARGUMENTS` as the
  decision question.
- Sub-operation (invoked by parent skill, e.g., `/design`): reads
  `decision_context` from the agent prompt with fields `question`,
  `prefix`, `options`, `constraints`, `background`, `complexity`.

There is no input mode that accepts "upstream STRATEGY path; re-evaluate
the bet". `/decision` is decision-question-driven, not artifact-driven.
You can phrase the question as "Does STRATEGY-<scope>'s bet still hold
given the evidence accumulated since acceptance?" but the format
`/decision` produces is the embeddable decision-block, not an ADR.

**`/decision`'s lifecycle**: there isn't one. The output block has a
`status="confirmed|assumed"` attribute (phase-6-synthesis `6.4`) that
maps to evidence quality, not to a Draft → Accepted ADR lifecycle.

**What IS at `docs/decisions/` in this workspace**: ADR files (e.g.,
`docs/decisions/ADR-koto-license-permissive.md`). The schema is the
**`tsukumogami:decision-record`** skill (`private/tools/plugin/tsukumogami/skills/decision-record/SKILL.md`),
not anything in `skills/shirabe/`. The ADR format:
- Frontmatter: `status`, `decision`, `rationale`, optional
  `superseded_by`.
- Required sections: Status, Context, Decision, Options Considered,
  Consequences.
- Lifecycle: Proposed → Accepted → Deprecated / Superseded.
- Filename pattern: `docs/decisions/ADR-<name>.md`.

**Brief's specified path**:
`docs/decisions/DECISION-strategy-<scope>-re-evaluation.md`. Two
mismatches with extant conventions:

- Filename prefix `DECISION-` (brief) vs `ADR-` (workspace). The
  workspace convention is `ADR-`.
- No shirabe-side skill currently writes to `docs/decisions/`. The ADR
  format lives in `tsukumogami:decision-record` (private overlay).
  shirabe core has no ADR-writing skill.

### Implications for Requirements

PRD MUST commit to one of three options and name the chosen one:

**Option A**: `/charter` writes the re-evaluation Decision Record
**inline** (without invoking `/decision` or any other skill). The PRD
names the minimum format `/charter` produces. The minimum format
matching the workspace's existing ADR convention is the
`tsukumogami:decision-record` format: frontmatter with `status`,
`decision`, `rationale`, body sections Status / Context / Decision /
Options Considered / Consequences. Filename:
`docs/decisions/ADR-strategy-<scope>-re-evaluation.md` (NOT `DECISION-`
— the workspace uses `ADR-`).

**Option B**: `/charter` delegates to `/decision`, framed as
"Does the STRATEGY's bet still hold?", and then `/charter` itself
promotes `/decision`'s `wip/<prefix>_report.md` into a durable
`docs/decisions/ADR-*.md` file. `/decision`'s output is a building
block; `/charter` is the consumer that promotes it. This adds an
indirection but reuses `/decision`'s structured-evaluation rigor.

**Option C**: a new sibling skill — `/decision-record` for shirabe core
that wraps `/decision` + ADR promotion. Out of scope for `/charter` v1
(the brief doesn't authorize new sibling skills).

**Recommendation**: Option A is the cleanest for v1. `/decision`'s
process (research → alternatives → bakeoff → synthesis) is overkill for
the re-evaluation use case, which is essentially "review evidence
against existing bet; either confirm or recommend re-strategizing".
Option A also avoids creating a `/charter` → `/decision` delegation
contract whose output `/decision` itself doesn't durably produce.

The PRD must also fix the **filename prefix mismatch**: brief says
`DECISION-strategy-<scope>-re-evaluation.md`; workspace ADR convention
is `ADR-<name>.md`. Either the PRD updates the brief's wording (most
likely) or the PRD declares a new `DECISION-*` prefix that diverges
from the workspace convention (less likely; would surface as a jury
issue).

The re-evaluation ADR's content must:

- Reference the existing STRATEGY by path (e.g.,
  `docs/strategies/STRATEGY-<topic>.md`).
- Capture the evidence reviewed (likely as the Context section).
- State the conclusion — bet still holds OR bet needs revision — as the
  Decision section.
- Treat "bet still holds" as the no-op Decision; "bet needs revision"
  would be a separate `/charter` re-run that produces a new STRATEGY
  (not within the re-evaluation exit's scope).

### Open Questions

- Does the PRD's audience accept the rename from `DECISION-*` (brief)
  to `ADR-*` (workspace convention)? The brief explicitly names
  `DECISION-strategy-<scope>-re-evaluation.md`; the PRD has to either
  validate the rename with the team-lead during drafting or carry the
  conflict forward as an Open Question.
- Should the ADR format `/charter` writes have a `supersedes:` or
  `references:` field pointing at the STRATEGY it re-evaluated? The
  workspace ADR format has `superseded_by` only. A new field would
  diverge from the format.
- If the re-evaluation concludes "bet does NOT hold", does `/charter`
  write the ADR AND queue a STRATEGY revision, or does the re-evaluation
  exit only fire when the bet holds (and a not-holding conclusion forces
  the chain back into `/strategy`)? Brief suggests the latter (the
  exit fires when the bet still holds) but is implicit.

---

## Lead 4: /comp skill status

### Findings

Confirmed absent. `skills/comp/` does NOT exist in the worktree
(`/home/dgazineu/dev/niwaw/tsuku/tsuku-3/.niwa/worktrees/shirabe-db61668b/skills/`
contains: decision, design, explore, plan, prd, private-content,
public-content, release, review-plan, roadmap, strategy, vision,
work-on, writing-style — no `comp`).

Cross-checked against the public shirabe source at
`/home/dgazineu/dev/niwaw/tsuku/tsuku-3/public/shirabe/skills/` — same
14 skills, no `comp`.

No in-flight signals found: no `comp` SKILL.md draft, no
`docs/briefs/BRIEF-shirabe-comp-skill.md`, no `docs/competitive/`
directory in the shirabe worktree. The closest related artifacts are in
the private overlay (`tsukumogami:competitive-analysis` skill stub
exists in `private/tools/plugin/tsukumogami/skills/competitive-analysis/`),
but that's a format-spec skill, not a workflow skill.

The brief's directive — `/charter` documents the `/comp` contract
behind a skill-existence check and silently skips when absent — is the
only viable v1 path given current state.

---

## Summary

`/strategy` ships with four input modes (empty, lifecycle verb,
VISION/PRD path, freeform topic), a Phase 0 slug constraint
`^[a-z0-9-]+$`, and Phase 1 producing `wip/strategy_<topic>_discover.md`
(NOT the `_scope.md` referenced in SKILL.md's Resume Logic — that line
is a documentation bug; `_scope.md` is never written). The Phase 4
three-reviewer jury (bet-quality, altitude, structural-format) writes
verdicts to pinned `wip/research/strategy_<topic>_phase4_*.md` paths,
and `/charter` should let `/strategy` run to its own Phase 5 termination
before deciding the next child — the contract bind point is the
STRATEGY file's frontmatter `status:` value, not the intermediate
verdict files. `/vision` and `/roadmap` follow the same shape (Phase 0
→ Phase 1/SCOPE → Phase 2/DISCOVER → Phase 3/DRAFT → Phase 4/VALIDATE)
but with three input modes each; both accept handoff via
`wip/{child}_<topic>_scope.md` from `/explore`'s Phase 5, which
`/charter` can mirror to skip the child's Phase 1.
The detectable invocation signals are: for `/vision`, no existing
Accepted/Active VISION OR conversational thesis-shift signal from
`/charter` Phase 1; for `/roadmap`, the just-produced STRATEGY's
Building Blocks section containing 3+ blocks with explicit Coordination
Dependencies.
`/decision` is NOT a fit for the re-evaluation exit — it produces a
`wip/<prefix>_report.md` decision-block, not a durable
`docs/decisions/` artifact, and has no input mode for "re-evaluate a
STRATEGY"; the PRD should specify `/charter` writes the re-evaluation
record inline using the workspace's existing `ADR-*.md` format (the
brief's `DECISION-*` prefix doesn't match workspace convention and the
PRD likely needs to rename).
`skills/comp/` does not exist anywhere in the shirabe worktree or public
source; the brief's skill-existence-check approach is the only viable v1
path.
