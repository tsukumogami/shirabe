# Router Handoff Contract — Phase 2 Research

Topic: `scope-chain-mandatory-steps`. Repo root:
`/home/dgazineu/dev/niwaw/tsuku/tsuku+shirabe_inconsistencies-03b57366/public/shirabe/.claude/worktrees/scope-chain`.
All line numbers refer to files as they exist in that worktree at the
time of writing.

---

## 1. What a handoff artifact contains, and where it lives

### 1.1 Current shape — three handoff writers

`/explore` Phase 5 has three files that write a `wip/<child>_<topic>_scope.md`
handoff. All three follow one template.

| Writer | Artifact path | Sections |
|---|---|---|
| `phase-5-produce-prd.md:3` | `wip/prd_<topic>_scope.md` | Problem Statement, Initial Scope (In/Out), Research Leads, Coverage Notes, Decisions from Exploration (`:8-35`) |
| `phase-5-produce-vision.md:3` | `wip/vision_<topic>_scope.md` | Problem Statement, Initial Scope (IS / IS NOT), Research Leads, Coverage Notes, Decisions from Exploration (`:8-37`) |
| `phase-5-produce-roadmap.md:3` | `wip/roadmap_<topic>_scope.md` | Theme Statement, Initial Scope (Covers / Does NOT Cover), Candidate Features, Coverage Notes, Decisions from Exploration (`:8-38`) |

Each writer's closing steps are identical in shape
(`phase-5-produce-prd.md:37-43`):

> 1. Commit: `docs(explore): hand off <topic> to /prd`
> 2. Invoke the PRD skill: `/shirabe:prd <topic>`
> 3. The PRD skill detects the handoff artifact and resumes at Phase 2
>    (Discover). Phase 1 (Scope) is already done -- the handoff artifact
>    fills that role.

The VISION writer says the same about `/vision`
(`phase-5-produce-vision.md:43-45`); the ROADMAP writer the same about
`/roadmap` (`phase-5-produce-roadmap.md:61-63`), plus an upstream-STRATEGY
detection step that passes `--upstream <strategy-path>` and an explicit
prohibition on substituting a VISION (`:43-57`).

Two other Phase 5 files write **durable** artifacts directly rather than a
wip handoff: `phase-5-produce-design.md` writes
`docs/designs/DESIGN-<topic>.md` (a Proposed skeleton) plus
`wip/design_<topic>_summary.md`, then invokes `/shirabe:design`; and
`phase-5-produce-plan.md` writes nothing and tells the author to run
`/plan` themselves.

The dispatcher is `phase-5-produce.md:38-48` — a nine-row routing table
mapping the crystallize verdict to the sub-file, with an "Auto-continues
into X" / "Stops — terminal" column.

### 1.2 The detection clauses that DO exist — and they are all in leaf children

Confirmed detection clauses, quoted:

- `/prd` — `skills/prd/references/phases/phase-1-scope.md:14`:
  "If `wip/prd_<topic>_scope.md` exists and this is NOT a loop-back from
  Phase 2, skip to Phase 2."
- `/vision` — `skills/vision/SKILL.md:96-101`: "On startup, check for
  `wip/vision_<topic>_scope.md`. If it exists, an /explore session already
  ran Phase 5 and wrote the handoff artifact with synthesized [scope] …
  If no handoff artifact exists, start from Phase 1." Reinforced in the
  resume ladder at `:153` and in the phase table at `:184` ("Skipped when
  handoff artifact (`wip/vision_<topic>_scope.md`) exists"), and again in
  `skills/vision/references/phases/phase-1-scope.md:14-18`.
- `/roadmap` — `skills/roadmap/SKILL.md:138-145`, ladder row at `:234`,
  phase table at `:269`; plus
  `skills/roadmap/references/phases/phase-1-scope.md:26-30`.

So the handoff contract today is **child-level, not parent-level**. Every
consumer of an `/explore` handoff is a leaf artifact skill.

### 1.3 Does `/scope` have ANY clause that detects a handoff artifact?

**No. Nothing exists.** A recursive grep for `explore` (case-insensitive,
both cases) across the entire `skills/scope/` tree returns **zero matches**.
`/explore` is not named anywhere in `/scope`'s SKILL.md, its five phase
files, its state schema, or its evals.

The slot where such a clause would live is explicitly reserved and empty.
`skills/scope/references/phases/phase-resume.md:80-84`:

> ## Slot 7 — Feeder-Doc-Detected (vacuous in v1)
>
> No feeder defined in v1; reserved for future. The slot is named
> explicitly here so future authors recognize the position rather than
> re-invent it.

Echoed in `skills/scope/SKILL.md:358`: "Slot 7 is vacuous in v1." and in
the reference table at `:415`: "Slot 7 (vacuous)".

**There is, however, an accidental glob collision that must be designed
around.** `/scope`'s Slot 6 partial-child-run rows are globs, not exact
filenames (`phase-resume.md:68-72`):

> - **6.1 `wip/plan_<topic>_*` exists.** Re-invoke `/plan` against its own
>   resume logic; do not re-run from scratch.
> - **6.2 `wip/design_<topic>_*` exists.** Re-invoke `/design`.
> - **6.3 `wip/prd_<topic>_*` exists.** Re-invoke `/prd`.
> - **6.4 `wip/brief_<topic>_*` exists.** Re-invoke `/brief`.

`/explore`'s PRD handoff writes `wip/prd_<topic>_scope.md`, which **matches
6.3's glob**. So an `/explore`-to-`/scope` handoff dropped at that path
would fire row 6.3 and be interpreted as *"`/prd` was interrupted mid-run"* —
re-invoking `/prd` directly, silently skipping `/brief`, skipping `/scope`
Phase 1 discovery, skipping the chain proposal, and writing no state file
entry that records why. Similarly `wip/design_<topic>_summary.md` (written
by `phase-5-produce-design.md`) matches 6.2. This is a latent bug today,
not just a design consideration for the router.

### 1.4 Does `/charter` have one?

**No detection clause for an `/explore` handoff exists.** `/charter`
mentions `/explore` in exactly four places, none of them a detection clause:

- `phase-2-chain-orchestration.md:425` — an **analogy only**: the
  pre-populated `wip/roadmap_<topic>_scope.md` "causes `/roadmap` to skip
  its Phase 1, analogous to the existing `/explore` Phase 5 handoff
  pattern."
- `phase-1-discovery.md:53` — a note that the default-Private warning
  wording is "shared with `/strategy` and `/explore`".
- `phase-1-discovery.md:119,122` — `/charter` **loads `/explore`'s
  discover/converge engine files** as its own Phase 1 conversation
  backbone (see §6).

Like `/scope`, `/charter` names the slot and declares it empty.
`skills/charter/SKILL.md:222-224`:

> slot 7 (feeder-doc-detected) is unfilled because `/charter` has no
> feeder-doc case.

**But `/charter` has a worse collision than `/scope`'s.** Ladder row 8
(`phase-resume.md:58`, detailed at `:293-302`) reads:

> **Row 8 — `/vision` Partial Run.** Match condition. No state file exists
> at `wip/charter_<topic>_state.md`, no STRATEGY exists at the published
> path, no `/strategy` partial-run artifact exists, AND
> `wip/vision_<topic>_scope.md` exists on disk.
>
> **Action.** Resume into `/vision`, passing the topic slug and letting
> `/vision`'s own resume logic detect the partial-run artifact and continue.

`wip/vision_<topic>_scope.md` is **the exact filename `/explore`
Phase 5 writes** (`phase-5-produce-vision.md:3`). So today, an `/explore`
VISION handoff followed by `/charter <topic>` on a cold start matches row 8
and jumps straight into `/vision` — bypassing `/charter` Phase 0 (visibility
detection, upstream validation, state-file creation) and Phase 1 (the
thesis-shift prompt, the chain proposal). The chain then has no state file,
so `/strategy` and `/roadmap` are never scheduled. The row is written as a
`/vision`-interrupted-run case and cannot tell the two apart, because both
produce a byte-compatible artifact at the same path.

Row 6's mid-roadmap disambiguation (`phase-resume.md:251-261`) keys on
`wip/roadmap_<topic>_scope.md` — but that one is `/charter`'s **own**
pre-population (`phase-2-chain-orchestration.md:423-426`), not an
`/explore` handoff, and it is gated on a Draft STRATEGY already existing,
so `/explore` output cannot reach it.

### 1.5 Summary answer

Nothing in either parent detects an `/explore` handoff. Both parents have a
named, empty Slot 7 that is the correct home for one. Both parents have an
existing ladder row whose match condition **already collides** with an
`/explore` handoff filename and silently misroutes it into a child,
bypassing the parent's own discovery — `/scope` Slot 6.3 by glob,
`/charter` row 8 by exact filename.

---

## 2. Where the detection clause goes in each parent

### 2.1 `/scope`

**File:** `skills/scope/references/phases/phase-resume.md`
**Section:** `## Slot 7 — Feeder-Doc-Detected` (currently `:80-84`).

The clause replaces the "vacuous in v1" body. It must:

- **Match** a handoff artifact at a path that does NOT collide with Slot
  6's `wip/{brief,prd,design,plan}_<topic>_*` globs. `wip/prd_<topic>_scope.md`
  is unusable for this reason; a distinct name such as
  `wip/scope_<topic>_handoff.md` (parent-namespaced, matching the existing
  `wip/scope_<topic>_state.md` convention at `phase-0-setup.md:275`) keeps
  the two surfaces separable.
- **Fire after Slot 5 and Slot 6, before rows 8-9.** Slot ordering is
  most-downstream-first; a real on-disk BRIEF/PRD/DESIGN/PLAN must still
  win over a feeder doc, because re-entry protection against settled work
  is the stronger claim.
- **Feed, not skip.** Slot 7's action should be *"enter Phase 1 with the
  handoff's content pre-loaded as discovery input"*, not *"skip Phase 1"*.
  See §3 for why: `/scope` Phase 1 also computes filesystem facts an
  exploration cannot supply.
- **Re-validate the recovered slug.** `phase-0-setup.md:233-244` requires
  slugs recovered from on-disk artifact paths during Slot 5 or Slot 6
  matches to be re-validated against `^[a-z0-9-]+$` before interpolation.
  Slot 7 must be added to that enumeration — the sentence at `:236-238`
  currently names Slot 5 and Slot 6 only.

Companion edits, all mandatory for internal consistency:
- `skills/scope/SKILL.md:358` — "Slot 7 is vacuous in v1" must change.
- `skills/scope/SKILL.md:415` — the reference table's "Slot 7 (vacuous)".
- `skills/scope/SKILL.md:278-283` — the slug re-validation cross-reference
  that currently reads "Slot 5 or Slot 6".
- `phase-resume.md:74-78` — the same slug rule, Slot-6-scoped.
- `skills/scope/references/phases/phase-1-discovery.md` — a new subsection
  under "Discovery Prompt Structure" (`:45-68`) defining which prompt
  inputs the handoff pre-supplies and which are still computed.

### 2.2 `/charter`

**File:** `skills/charter/references/phases/phase-resume.md`
**Section:** the 10-row ladder block at `:50-61`, plus a new `## Row N`
body section.

The placement question is constrained by an explicit note in the file.
`phase-resume.md:264-269` explains why the mid-roadmap check was put inside
row 6 rather than given its own row:

> The check lives in this row rather than in a new ladder row because rows
> 7-8 both require *no* STRATEGY at the published path and so can never
> match, rows 3-4 already cover the state-file case through
> `phase_pointer`, and rows 9-10 are pattern-level meta-ladder rows that
> **renumbering would disturb for `/scope` as well as `/charter`**.

So a new numbered row inserted before row 9 is off the table — rows 9-10
are the shared meta-ladder tail. The two viable slots:

1. **Slot 7 (feeder-doc-detected)** — the pattern already reserves a
   position here (`skills/charter/SKILL.md:222-224`), and the meta-ladder
   template at `references/parent-skill-resume-ladder-template.md` defines
   rows 5-7 as parent-specific body slots. `/charter` currently maps slot 5
   → rows 5-6, slot 6 → rows 7-8, slot 7 → nothing. Filling slot 7 means a
   row **8.5**, or renumbering 9-10 to 10-11 with the template updated in
   lockstep for both parents.
2. **Inside row 8**, mirroring row 6's precedent — row 8 already matches
   `wip/vision_<topic>_scope.md`, so a disambiguation there resolves the
   collision from §1.4 at the same time.

Option 2 is the lower-risk edit and fixes an existing defect; option 1 is
the structurally correct home. If the handoff gets a distinct filename
(`wip/charter_<topic>_handoff.md`), option 1 becomes clean and row 8 needs
only a note that it does not match handoff artifacts.

What the clause must do: enter `/charter` **Phase 1** with the handoff
pre-loaded, so the chain proposal (`phase-1-discovery.md:217-255`) still
runs and `/strategy` and `/roadmap` still get scheduled. It must NOT route
into `/vision` directly — that is exactly the bug in §1.4.

Companion edits:
- `skills/charter/SKILL.md:220-224` — the slot-mapping paragraph.
- `phase-resume.md:264-269` — the "why no new row" rationale, if a row is
  added.
- `phase-resume.md:293-302` — row 8's match condition, to exclude handoffs.
- `phase-resume.md:503-515` — the security section's note about rows 7-8
  filenames (`:509` references `wip/vision_<topic>_scope.md`).

---

## 3. What the handoff must carry so the parent does not re-ask

### 3.1 `/scope` Phase 1's inputs

From `skills/scope/references/phases/phase-1-discovery.md`:

| Input | Where | Pre-suppliable by exploration? |
|---|---|---|
| Framing-shift question (R4), verbatim at `:47-53` | discovery prompt | **Yes — the answer.** The question asks whether problem shape / audience / scope boundary / success criterion changed. An exploration that ran discover-converge with the author has that answer in `wip/explore_<topic>_decisions.md` (phase-3-converge.md:91-116) and in Accumulated Understanding (`:162-170`). Carry it as a stated answer with its evidence, and let Phase 1 confirm rather than re-ask. |
| Topic-related child-doc globs at `:56-62` | filesystem | **No.** These are `docs/briefs/`, `docs/prds/`, `docs/designs/`, `docs/designs/current/`, `docs/plans/` globs read together with each artifact's frontmatter `status:`. Files change between the exploration and the `/scope` run. Must be read fresh. |
| Cold-start projected-PRD evaluation `:71-88` | slug keywords | Moot — the projection is derived from the slug alone and is cheap; a handoff makes the run non-cold-start anyway. |
| R6 predicate walk P1/P2/P3 `:148-248` | projected PRD shape | **Partially.** P1 (architectural alternatives left open) and P3 (complexity signal) are exactly what an exploration's tensions and open questions establish. P2 (new-component references) cross-references the repo's directory structure (`:200-202`) and is a filesystem fact. All three are re-evaluated against the real PRD by the post-`/prd` gate (`:90-106`), so a pre-supplied estimate is safe — it only sizes `/design`'s roster. |
| Re-entry protection verdicts `:107-131` | filesystem + frontmatter status | **No.** The settled-status table (`:119-122`) requires reading live `status:` values. |
| Initial `child_snapshots:` capture `:439-454` | git blob hashes | **No.** `content_hash` is `git hash-object` output against the live doc. |
| Visibility, slug validation, `--upstream` validation | `phase-0-setup.md:62-231` | **No.** All Phase 0, all filesystem/git/CLAUDE.md reads, all re-run on every resume (`phase-resume.md:86-98` requires re-running the whole `--upstream` battery "against the worktree as it is NOW, not as it was when the value was recorded"). |

The general rule the existing files already state: **anything read from
disk is re-read.** `phase-resume.md:93-98` is explicit — "A file tracked
last week can be deleted or moved this week, and a repo's
`## Repo Visibility:` header can change between sessions." The handoff
carries *conversation*, never *filesystem state*.

Concretely, a `/scope` handoff should carry: the problem statement, the
in/out scope boundary, the framing-shift answer with its evidence, the
accumulated decisions (so the chain treats them as settled), the R6
predicate estimate with its reasons, and coverage notes naming what the
exploration did not answer. That maps almost exactly onto the existing
`wip/prd_<topic>_scope.md` template (`phase-5-produce-prd.md:8-35`) plus
an R6 block — the shape is already close to right; only the destination
and the consumer change.

### 3.2 `/charter` Phase 1's inputs

From `skills/charter/references/phases/phase-1-discovery.md`:

| Input | Where | Pre-suppliable? |
|---|---|---|
| Thesis-shift question, verbatim: *"Is the long-term thesis shifting, or is this an operational layer below it?"* `:144` | author | **Yes — the answer and its classification.** The three positive-signal categories (`:157-178`) are thesis-change, new-frame, VISION-rejection. An exploration that converged on VISION as the artifact type has necessarily surfaced this. Note the question is "asked once per `/charter` run" (`:148-149`) and is asked "for the framing it gives the conversation" even on a cold start where `/vision` runs regardless (`:154-155`) — so pre-supplying the answer does not eliminate the question's conversational role, only the re-derivation. |
| Repo visibility `:29-46` | CLAUDE.md | **No.** Read fresh; the default-Private warning at `:56-59` is asserted byte-for-byte by evals. |
| Existing VISION status at `docs/visions/VISION-<topic>.md` `:151-153` | filesystem | **No.** The classification only *decides* the `/vision` invocation when an Accepted/Active VISION already exists; that fact must be read live. |
| Discover/converge loop `:114-137` | `/explore`'s own engine files | Already shared — see §6. |
| Chain-proposal confirmation prompt `:217-255` | derived | Must still run. It is the surface "where the chain shape becomes a committed plan; nothing downstream runs until the author selects one of the three options" (`:222-224`). |

`/charter`'s `--upstream` accepts a VISION path with a `VISION-` basename
enforced (`phase-0-setup.md:228`), so an exploration that identified an
existing VISION should pass it via the flag rather than embed it in the
handoff — matching what `phase-5-produce-roadmap.md:43-57` already does for
STRATEGY.

---

## 4. The four arms, concretely

### 4.1 File an issue

- **Router hands over:** a problem statement and scope boundary sized for
  one issue. There is no shirabe skill that owns issue creation — `ls skills/`
  shows no `issue/` directory. The workspace provides `tsukumogami:issue`
  ("Create a well-formed GitHub issue with agent-assisted validation") and
  `tsukumogami:issue-drafting` / `tsukumogami:issue-filing` as format
  skills, but those are workspace-level, not shirabe-level.
- **Author runs next:** `/work-on <issue-number>`.
  `skills/work-on/SKILL.md:19-21`: "The input `$ARGUMENTS` can be an issue
  reference or a milestone reference. **Issue inputs**: `71`, `#71`, or
  issue URL - resolve directly to the issue number."
- **Not `/execute`.** See §4.4.

### 4.2 `/charter`

- **Router hands over:** topic slug plus, optionally,
  `--upstream <docs/visions/VISION-*.md>`. Signature:
  `argument-hint: '<topic-slug or freeform topic> [--upstream <path>]'`
  (`skills/charter/SKILL.md:14`). Basename `VISION-` enforced at
  `phase-0-setup.md:228`; a path in the positional slot is rejected
  (`:154`).
- **Author runs next:** `/charter <topic-slug>`. The chain then runs
  VISION → STRATEGY → ROADMAP.

### 4.3 `/scope`

- **Router hands over:** topic slug plus, optionally,
  `--upstream <docs/roadmaps/ROADMAP-*.md>`. Signature:
  `argument-hint: '<topic-slug or freeform topic> [--upstream <path>]'`
  (`skills/scope/SKILL.md:13`). Basename `ROADMAP-` enforced
  (`phase-0-setup.md:155-168`), path confined under
  `<repo-root>/docs/roadmaps/` (`:170-176`), must be tracked by git and not
  under `wip/` (`:183-193`).
- **Author runs next:** `/scope <topic-slug>`. Chain runs
  BRIEF → PRD → DESIGN → PLAN; `planned_chain:` is
  `[brief, prd, design, plan]` on every run (`phase-1-discovery.md:14-16`,
  `:399-417`: "That list is a constant").

### 4.4 `/execute` — and the problem

`skills/execute/SKILL.md:35-45`, the complete Input Modes section:

> From `$ARGUMENTS`:
>
> 1. **Path to a PLAN doc** (`docs/plans/PLAN-*.md`, or any `.md` whose
>    frontmatter has `schema: plan/v1`) — read the PLAN's `execution_mode`:
>    - `single-pr` — run the single-pr execution path below.
>    - `coordinated` — run the coordinated execution path below.
>    - `multi-pr` — out of scope for `/execute`; multi-pr plans run one
>      issue at a time through `/work-on` against the repo-persisted PLAN.
>      Direct the user to `/work-on`.
> 2. **Empty** — ask which PLAN to execute.

**Confirmed: `/execute` accepts only a PLAN path (or empty, in which case
it asks for one). It does not accept an issue number, a milestone, or a
free-form task.** There are exactly two input modes.

Three consequences:

1. **The "file an issue" arm cannot hand to `/execute`.** Its next step is
   `/work-on <N>`, which is the only skill accepting an issue number
   (`skills/work-on/SKILL.md:4`: `<issue_number | #issue | issue-url |
   M<milestone> | milestone-url | "Milestone Name" | docs/plans/PLAN-*.md |
   "task description">`). If the router's four arms are stated as *entry
   points to chains*, the fourth arm's honest name is `/work-on`, not
   `/execute` — or the arm is "file an issue" and its runner is `/work-on`,
   with `/execute` reachable only after a PLAN exists.
2. **The `/execute` arm presupposes a PLAN already on disk.** Routing to
   `/execute` is only legal when the exploration found an existing
   `docs/plans/PLAN-<topic>.md`. Otherwise the arm is really "go get a
   PLAN first", which is the `/scope` arm.
3. **`/execute` has no handoff-detection surface at all and needs none** —
   its input is a durable committed document, not a wip artifact. Nothing
   in `/explore` needs to write anything for this arm; it hands over a
   path.

For completeness, the current `/plan` arm (`phase-5-produce-plan.md`)
already works this way: it writes nothing and tells the author to run
`/plan <topic>` or `/plan <artifact-path>`. That is the model the router's
non-writing arms should follow.

---

## 5. The terminal recording set

### 5.1 Rejection record

- **Current handler:** `phase-5-produce-rejection-record.md`.
- **Writes:** `docs/decisions/REJECTED-<topic>.md`, creating
  `docs/decisions/` if absent (`:13-14`). Body template at `:16-59`:
  What Was Investigated, Findings by Question (the six demand-validation
  questions with High/Medium/Low/Absent confidence), Conclusion,
  Preconditions for Revisiting. Commit `docs(explore): record rejection of
  <topic>` (`:63`). Declared terminal: "No handoff to another skill — this
  is the final produce step" (`:82`).
- **Destination skill exists?** **No.** `ls skills/` returns: brief,
  charter, comp, decision, design, execute, explore, inflight, plan, prd,
  private-content, public-content, release, review-plan, roadmap, scope,
  strategy, vision, work-on, writing-style. No rejection skill. A grep for
  `REJECTED-` across `skills/` and `references/` hits only this file.
- **Naming mismatch worth flagging.** The live `docs/decisions/` directory
  contains seven files, all named `DECISION-<topic>-<YYYY-MM-DD>.md` (e.g.
  `DECISION-skill-preflight-verification-depth-2026-08-14.md`). Nothing in
  the repo is named `REJECTED-*`. So `/explore` is the sole author of a
  filename convention that exists nowhere else in the corpus.
- **Compatible with "`/explore` stops authoring durable chain artifacts"?**
  A REJECTED record is not a chain artifact — no `upstream:` field, no
  lifecycle status, nothing downstream consumes it, and no chain owns it.
  It is genuinely terminal. Keeping it in `/explore` is compatible with the
  constraint as stated. The open question is whether it should instead be a
  shape of the DECISION record, given that `phase-5-produce-rejection-record.md:72-75`
  already offers to escalate: "If re-proposal risk is high … offer to route
  to `/decision` for a formal ADR that captures the rejection as an
  architectural decision record."

### 5.2 Decision record

- **Current handler:** `phase-5-produce-decision.md`.
- **Writes:** `wip/explore_<topic>_decision-brief.md` (`:8`) with Decision
  Question, Context, Known Options, Constraints, Relevant Research,
  Complexity Signal (`:10-32`). Then hands off (`:36-47`): read
  `skills/decision/SKILL.md`, invoke with prefix `explore_<topic>_decision`,
  and "The decision skill runs its phases and produces
  `wip/explore_<topic>_decision_report.md`. The report serves as the
  Decision Record (ADR)."
- **Destination skill exists?** **Yes — `/decision` is a real skill**
  (`skills/decision/SKILL.md`), described as handling Tier 3/4 decisions
  and "Also invocable as a sub-operation by /design".
- **But the output is not durable.** `skills/decision/SKILL.md:121` puts
  Phase 6's output at `wip/<prefix>_report.md`; `:129` resume-checks the
  same; `:159`: "Only the final `wip/<prefix>_report.md` persists."
  A grep for `docs/decisions` or `ADR-` across `skills/decision/` returns
  **zero matches** — `/decision` never writes to `docs/decisions/`.
  So `/explore` claims "the report serves as the Decision Record (ADR)"
  while the report lives in `wip/`, which the wip-hygiene rule
  (`references/wip-hygiene.md`, and the workspace CLAUDE.md) says is
  deleted before the PR can merge. **This arm currently produces no durable
  artifact at all.**
- **Compatible?** Yes, in the sense that `/explore` already writes only a
  wip brief and delegates. The gap is downstream of the router: something
  must promote the decision report into `docs/decisions/DECISION-<topic>-<date>.md`,
  and nothing does today.

### 5.3 Spike report

- **Current handler:** `phase-5-produce-deferred.md`, `## Spike Report`
  section (`:42-105`).
- **Writes:** `docs/spikes/SPIKE-<topic>.md` **directly and inline**
  (`:46`), with frontmatter `status: Draft`, `question:`, `timebox:`
  (`:49-55`) and body sections Status, Question, Context, Approach,
  Findings, Recommendation (`:57-88`). Commit `docs(explore): produce spike
  report for <topic>` (`:90`). Also runs
  `gh issue edit <N> --remove-label needs-spike` when the exploration came
  from an issue (`:92-97`).
- **Destination skill exists?** **No.** There is no `skills/spike/`.
  The only other reference to `docs/spikes` in the tree is
  `skills/plan/references/templates/agent-prompt-planning.md`.
  `tsukumogami:spike-report` exists at workspace level, but its description
  is "Spike report format, lifecycle, and validation rules. Use when
  writing or reviewing docs/spikes/SPIKE-*.md files" — a format reference,
  not a producer. Two real spike docs exist:
  `docs/spikes/SPIKE-claude-code-goal-integration.md`,
  `docs/spikes/SPIKE-mermaid-parser.md`.
- **Compatible?** A SPIKE is not a chain artifact (it has no `upstream:`,
  and `references/pipeline-model.md:84` gives it a two-state lifecycle
  Draft → Complete that no chain drives). So `/explore` authoring it does
  not violate "stops authoring durable **chain** artifacts" as literally
  stated. But it is the one arm where `/explore` writes a durable
  `docs/` file with frontmatter and a lifecycle, with no owning skill to
  hand it to. If the constraint is read strictly as "`/explore` writes
  nothing durable", this arm needs a `/spike` skill that does not exist —
  a build, not a route.

### 5.4 Competitive analysis

- **Current handler:** `phase-5-produce-deferred.md`,
  `## Competitive Analysis` section (`:109-186`).
- **Writes:** `docs/competitive/COMP-<topic>.md` **directly and inline**
  (`:130`), with frontmatter `status: Draft`, `market:`, `date:`
  (`:132-139`) and body Market Overview, Competitors, Comparative Matrix,
  Opportunities, Implications (`:141-177`). Gated on repo visibility: in a
  public repo it refuses and offers three alternatives (`:111-126`).
- **Destination skill exists?** **Yes — `/comp` is a real skill, and it
  owns the exact same path.** `skills/comp/SKILL.md:57`: "COMP documents
  live at `docs/competitive/COMP-<topic>.md` (kebab-case)." `:42`:
  "**Lifecycle:** Durable. Stays in `docs/competitive/` after completion."
  `/comp` drives a six-phase workflow (scope → research → draft → jury →
  finalize) with a `wip/comp_<topic>_scope.md` Phase 1 artifact
  (`skills/comp/references/phases/phase-1-scope.md:37`), a Draft at
  `docs/competitive/COMP-<topic>.md`
  (`skills/comp/references/phases/phase-3-draft.md:8,50`), and an explicit
  `shirabe transition … Accepted` finalization
  (`skills/comp/references/phases/phase-5-finalize.md:18`). `/comp` also
  carries `argument-hint: <topic-slug> [--upstream <path>]` and the same
  private-only visibility warning.
- **Compatible?** **This is a straight duplication and the clearest
  candidate for deletion.** `/explore` writes a Draft COMP with no jury, no
  transition, and no lifecycle, at the identical path `/comp` owns. The arm
  should route to `/comp <topic>` — and unlike the spike arm, the
  destination already exists and is more complete than what `/explore`
  writes.

### 5.5 What "`/decision` and `/comp` are real skills while `/spike` and
`/competitive-analysis` are not" means, arm by arm

- **`/comp` exists** → the competitive-analysis arm becomes a **route**.
  Delete `phase-5-produce-deferred.md`'s Competitive Analysis section
  entirely; the router hands `/comp <topic>` and the author runs it.
  Nothing is lost — `/comp` covers the visibility gate too. Note the skill
  is `/comp`, not `/competitive-analysis`; the latter name belongs to the
  workspace format skill `tsukumogami:competitive-analysis`, which is a
  validation reference, not a producer.
- **`/decision` exists** → the decision arm is already a route and stays
  one. The unresolved half is that `/decision`'s output never leaves
  `wip/`, so "route and stop" leaves nothing durable. Either `/decision`
  gains a durable finalize step, or the router's decision arm must say
  plainly that the ADR lands in `wip/` and needs manual promotion.
- **No `/spike` skill** → the spike arm is either (a) `/explore` keeps
  writing `docs/spikes/SPIKE-<topic>.md` inline, which is the only arm
  where the router still authors a durable doc, or (b) a `/spike` skill
  has to be built. There is no third option that preserves the capability.
- **No rejection skill** → same shape as spike, but with the extra wrinkle
  that the filename convention `REJECTED-*` matches nothing else in the
  corpus. Folding it into `/decision` as a rejection-shaped DECISION record
  would resolve both the missing-owner problem and the naming drift, and
  `phase-5-produce-rejection-record.md:72-75` already gestures at it.

---

## 6. What survives untouched — and what does not

### 6.1 `phase-2-discover.md` — orthogonal, but shared

Pure research fan-out: read leads from the scope file (`:35-42`), build
agent prompts (`:44-57`), one agent per lead, agents write to
`wip/research/explore_<topic>_r<N>_lead-*.md`. Nothing in it references
artifact types, chains, or downstream skills. **Orthogonal to routing.**

**Caveat, and it is load-bearing:** this file is not `/explore`-private.
`skills/charter/references/phases/phase-1-discovery.md:114-132` loads it as
`/charter`'s own Phase 1 conversation backbone:

> Phase 1's conversational discovery uses the discover/converge engine that
> lives at: `skills/explore/references/phases/phase-2-discover.md` … and
> `skills/explore/references/phases/phase-3-converge.md` …
> Per Design Decision 1, the engine stays at its current location; parent
> skills that need a discovery phase point cross-skill rather than copying
> the engine into their own directory.

So any edit to these two files changes `/charter`'s behavior. They survive
the routing change, but they are not `/explore`'s to move or rename.

### 6.2 `phase-3-converge.md` — orthogonal, same shared-engine caveat

Synthesis (`:44-89`), decision capture into
`wip/explore_<topic>_decisions.md` (`:91-127`), findings-file update
(`:129-172`). The only downstream reference is `:115-116` — decisions
"feed into Phase 4 (Crystallize) and Phase 5 (Produce)" — which is a
pointer, not a routing rule, and stays true if Phase 4/5 become a router.
Same `/charter`-shares-it caveat as above.

### 6.3 `phase-1-scope.md` — mostly orthogonal, two couplings

Conversational scoping producing 3-8 leads. The scope-file template
(`:162-196`), the coverage-tracking table (`:52-60`), and the adversarial
demand-validation lead (`:200-273`) are all routing-agnostic.

**Two things are NOT orthogonal:**

1. **The Label Pre-Gate (`:21-39`)** branches on issue labels — `needs-prd`
   pre-classifies as directional, `bug` skips the adversarial lead. That
   couples Phase 1 to the issue-entry path and, indirectly, to the
   `needs-*` label vocabulary that Phase 0's Stage 2 triage assigns. If the
   Stage 2 triage is removed, `needs-prd` can still arrive from a human or
   from `/roadmap`'s branching (`references/pipeline-model.md:253-263`),
   so the gate survives — but its provenance story changes and should be
   restated.
2. **The hard stop at `:147-150`** requires `## Visibility` to be present
   in the scope file, written by Phase 0 step 0.2a. Any Phase 0 surgery
   must preserve 0.2a or this stops the run.

### 6.4 `phase-0-setup.md` — three things beyond the Stage 2 triage

The brief says "minus its Stage 2 artifact-type triage". Confirmed: **Step
0.5 Triage Stage 2 (`:160-249`)** is exactly the artifact-type triage being
replaced — three agents arguing needs-prd / needs-design / needs-spike /
needs-decision, a synthesis with a primary-gap heuristic (`:214-222`), and
an AskUserQuestion routing to Explore / Different type / Implement directly
(`:223-249`). That is the router's job now.

**Three other pieces of Phase 0 are also not orthogonal:**

1. **Step 0.4 Triage Stage 1 (`:79-158`)** — three agents arguing needs
   investigation / needs breakdown / ready, with two of the three outcomes
   routing *out* of `/explore` entirely: "Break down: Create sub-issues …
   Stop and suggest the user run `/work-on` on individual sub-issues" and
   "Implement directly: Remove the `needs-triage` label. Stop and suggest
   the user run `/work-on <issue-number>`" (`:154-158`). This is *already*
   router behavior living in Phase 0. It overlaps the "file an issue" arm
   and needs a decision: does Stage 1 stay in Phase 0, or fold into the
   terminal router?
2. **Step 0.1 Branch Setup (`:21-29`)** — creates and switches to a
   `docs/<topic>` branch. This has cross-skill consequences for the router:
   `/scope`'s meta-ladder rows 8-9 and `/charter`'s rows 9-10 both key on
   *"On branch related to topic"* (`skills/charter/references/phases/phase-resume.md:304-314`,
   `skills/scope/SKILL.md:337-338`). An `/explore` run that creates
   `docs/<topic>` and then routes to `/scope <topic>` lands the parent in
   ladder row 9 — "Resume at Phase 1", skipping Phase 0 — on what the
   author experiences as a first invocation. Whether that is desirable is
   a real design question, not a detail.
3. **Step 0.3 Issue Entry Point (`:68-77`)** — the `needs-design` branch
   gathers upstream context before Phase 1. If artifact-type triage moves
   to the router, this pre-gathering has no consumer at Phase 0 time.

Everything else in Phase 0 — 0.2 context resolution, 0.2a visibility
persistence (`:40-66`), the resume check (`:13-17`) — is orthogonal and
should survive verbatim.

---

## 7. `references/pipeline-model.md`

### 7.1 Statements routing `/explore` to a chain-internal step

Every one, with line numbers:

| Line(s) | Statement | Why it conflicts with an entry-point router |
|---|---|---|
| `:10-11` | "Diamond 1: EXPLORE / CRYSTALLIZE — `/explore` (diverge) -> crystallize (converge) -> **artifact type**" | The diamond's declared output is an artifact *type*, i.e. a chain-internal altitude, not a chain entry point. |
| `:38` | "Complex \| /explore \| 1-2-3 \| Explore -> crystallize -> **specify** -> implement" | "specify" is Diamond 2, whose members are `/prd`, `/design`, `/plan` (`:14-15`) — chain-internal steps. |
| `:39` | "Strategic \| `/explore --strategic` \| 1-2-3 with branching \| **VISION -> STRATEGY -> Roadmap** -> per-feature pipeline" | Names the three strategic altitudes directly — the chain `/charter` owns. `/charter` is not mentioned in this row. |
| `:63` | "**Skip** \| Diamond 1 or 2 \| Later diamond \| Complexity routing bypasses diamonds. Simple work skips Diamonds 1-2. Medium skips Diamond 1." | The named "Skip" transition. Bypasses whole diamonds based on classification. |
| `:67-69` | "Advance is the default. … **Skip is driven by complexity classification at entry.** Hold and Kill are human decisions." | Establishes Skip as a routing primitive keyed on classification. |
| `:144` | "`/roadmap` states it in its own contract, and **`/explore` hands it a STRATEGY or nothing**" | `/explore` handing a specific upstream to a specific chain-internal child. |
| `:240` | "Shape unclear, multiple unknowns \| `/explore` -> (crystallize) -> **`/prd` or `/design`** -> `/plan` -> `/work-on`" | Routes into the middle of the tactical chain. `/scope` — which owns that chain — is absent. |
| `:241` | "New project, thesis needed \| `/explore --strategic` -> **`/vision` -> `/strategy` -> `/roadmap`** -> per-feature pipeline" | Routes into the middle of the strategic chain, in parallel to the `/charter` row directly below it. |
| `:244` | "Feasibility unknown \| `/explore` -> (crystallize) -> **spike report**" | Terminal recording arm, consistent with the router — but names an artifact with no owning skill. |
| `:245` | "Single contested choice \| `/explore` -> (crystallize) -> **`/decision`**" | Terminal recording arm; `/decision` exists, so this row is already router-shaped. |
| `:253-263` | Roadmap branching: "Each feature gets a planning issue with a `needs-*` label (needs-prd, needs-design, needs-spike, needs-decision). The feature then enters its own pipeline at the appropriate diamond" and the tree at `:258-264` routing Feature A → `/prd`, B → `/design`, C → spike, D → `/decision` | The same needs-* vocabulary Phase 0's Stage 2 triage assigns, routing to the same chain-internal children. |

### 7.2 `/explore` named as the authority for the algorithm

Three places say so explicitly:

- `:41-44`: "Detection runs top-down (Strategic first, Trivial last). **The
  full detection algorithm and tiebreaker rules live in `/explore SKILL.md`
  under "Detection Algorithm."** This reference describes the levels;
  **`/explore` owns the classification logic.**"
- `:247-249`: "**The crystallize step in `/explore` determines which
  artifact type to produce. The detection algorithm in `/explore`
  determines which complexity level applies. Both are documented in
  `/explore SKILL.md`.**"

`/explore SKILL.md:69` does carry a "### Detection Algorithm" heading with
the six-step top-down walk at `:87-95`, so the pointer resolves.

### 7.3 Two additional facts about this file

- **`/scope` appears exactly once, at `:147`** — "`/scope` walks all four
  tactical altitudes on every run" — inside a paragraph about link
  legality. It is **absent from the skill routing table entirely**
  (`:234-245`), while `/charter` gets its own row at `:242`. So the
  document already routes past the tactical parent while acknowledging the
  strategic one.
- **The three-diamond model itself predates both parents.** Diamond 2 is
  defined as "`/prd`, `/design` (diverge) -> `/plan` (converge) -> issues"
  (`:14-15`) with no `/brief` and no `/scope`. Diamond 3 is "`/work-on`
  (diverge) -> `/release` (converge)" (`:16-17`) with no `/execute`, though
  `:204-220` later describes `/execute` owning plan-level execution and the
  completion cascade. The model's vocabulary and the current skill set have
  drifted apart independently of the routing question.

---

## Cross-cutting findings worth carrying into the PRD

1. **Two live misrouting bugs, both from filename collisions.** `/scope`
   Slot 6.3's glob `wip/prd_<topic>_*` matches `/explore`'s
   `wip/prd_<topic>_scope.md`; `/charter` row 8 matches
   `wip/vision_<topic>_scope.md` exactly. Both cause a parent to jump into
   a leaf child, skipping its own Phase 0/1. Any handoff filename the
   router adopts must be namespaced to the parent to avoid re-creating this.
2. **Both parents reserve an empty Slot 7 for exactly this.** `/scope`
   `phase-resume.md:80-84`; `/charter` `SKILL.md:222-224`. The design
   anticipated a feeder doc and left the position named.
3. **`/execute` takes only a PLAN path.** The "file an issue" arm's runner
   is `/work-on`, and the `/execute` arm presupposes a PLAN already exists.
4. **`/comp` already owns `docs/competitive/COMP-*.md`** — the deferred
   handler duplicates it with a weaker output. Clean deletion.
5. **The decision arm produces nothing durable.** `/decision` writes only
   `wip/<prefix>_report.md` and never touches `docs/decisions/`, despite
   `phase-5-produce-decision.md:47` calling the report "the Decision Record
   (ADR)".
6. **Two arms have no owning skill:** spike report and rejection record.
   Routing them requires building a skill or keeping `/explore` as their
   author.
7. **`/explore`'s Phase 0 already routes out of itself** (Step 0.4's
   break-down and implement-directly branches → `/work-on`), and Step 0.1's
   `docs/<topic>` branch creation interacts with both parents' "on
   topic-related branch" ladder rows.
