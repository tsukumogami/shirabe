# Lead: How does /charter run today, and what did PR #252 already convert?

Repo: `public/shirabe` (worktree `.claude/worktrees/charter-scope-parity`, branch
`docs/charter-scope-parity`). Charter's whole surface is 10 files:
`skills/charter/SKILL.md`, six phase files under
`skills/charter/references/phases/`, three templates under
`skills/charter/references/templates/`, plus `skills/charter/evals/evals.json`.
Sources read in full: all ten, the three child SKILL.md entry points
(`skills/vision/`, `skills/strategy/`, `skills/roadmap/`), the complete
`70cd921` diff (PR #252), `docs/prds/PRD-shirabe-charter-skill.md`,
`references/parent-skill-pattern.md`, `references/parent-skill-state-schema.md`,
`skills/scope/SKILL.md`, and
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`. Issues #254,
#255, #257 read via `gh`.

## Findings

### 1. Charter's current pipeline, phase by phase

Four phases. Declared twice in `skills/charter/SKILL.md` — as a diagram at
:128-132 and a table at :134-139:

```
Phase 0: SETUP --> Phase 1: DISCOVER --> Phase 2: CHAIN --> Phase N: FINALIZE
(slug validation +  (visibility detect +   (orchestrate     (record exit +
 state-file create)  chain proposal)        child skills)    write artifacts)
```

**Phase 0 — Setup** (`skills/charter/references/phases/phase-0-setup.md`, 174
lines)

Slug validation and state-file creation only; visibility detection is explicitly
deferred to Phase 1 (:21-23, "Phase 0 only records the slug and creates state").
Three steps:

- 0.1 (:31-45) — empty/whitespace `$ARGUMENTS` surfaces a cold-start prompt
  naming the three CLAUDE.md trigger phrases, then **stops**: "the cold-start
  path does not auto-retry, does not loop, and does not derive a slug from the
  author's response" (:43-45).
- 0.2 (:47-136) — byte-for-byte match against `^[a-z0-9-]+$`. "There is NO
  normalization step before validation... Phase 0 does not lowercase, does not
  replace whitespace, does not strip punctuation, does not collapse repeated
  hyphens, does not trim" (:56-59). A five-row canonical rejection table at
  :89-97 (`MyTopic`, `my_topic`, `my.topic`, `Hello World`,
  `docs/visions/VISION-foo.md`) — these are what the eval baseline asserts
  against (:99-102). Path-as-topic is rejected by construction (:122-136).
- 0.3 (:138-174) — writes `wip/charter_<topic>_state.md` with `topic`,
  `last_updated`, `phase_pointer: 0`, `exit: UNSET`, `exit_artifacts: []`
  (:150-156). Conditional fields are absent per invariant I-5 (:167-170).

**Phase 1 — Discover** (`phase-1-discovery.md`, 322 lines)

Five sub-steps. The file has a visible seam at :205-214 (an HTML comment marking
where the "discovery prelude" ends and the chain-proposal output begins) — the
two halves were authored by different issues.

- 1.1 (:29-71) — reads `## Repo Visibility: (Public|Private)` from
  CLAUDE.md/CLAUDE.local.md; absent ⇒ default Private plus a warning whose
  "literal phrasing is the pattern-level wording shared with `/strategy` and
  `/explore` — eval scenarios assert against it byte-for-byte" (:52-54).
- 1.2 (:73-112) — manual-fallback non-interference. Direct child invocation is
  "first-class steady-state capability, not a degraded path and not an error
  case" (:79-80).
- 1.3 (:114-136) — the discover/converge loop is **borrowed cross-skill**, not
  owned: `skills/explore/references/phases/phase-2-discover.md` and
  `phase-3-converge.md`. ":126-128" — "Per Design Decision 1, the engine stays at
  its current location; parent skills that need a discovery phase point
  cross-skill rather than copying the engine into their own directory."
- 1.4 (:139-203) — the thesis-shift signal prompt (see section 2).
- 1.5 (:216-321) — chain-proposal confirmation prompt with the literal options
  **Proceed / Adjust / Bail** (:286-311).

Phase 1 writes nothing durable; its outputs are conversational plus state.

**Phase 2 — Chain orchestration** (`phase-2-chain-orchestration.md`, 445 lines)

Invokes up to four children in fixed order — `/vision` (R4), `/comp` (R5+R12),
`/strategy` (R6), `/roadmap` (R7). Each invocation runs as a dispatch under the
Team-Lead Operating Discipline, implementation-pass task class, 120s window /
10-cycle patience budget (SKILL.md:145-152). Durable outputs land at
`docs/visions/VISION-<topic>.md`, `docs/strategies/STRATEGY-<topic>.md`,
`docs/roadmaps/ROADMAP-<topic>.md`.

Charter itself writes exactly one artifact in this phase: the handoff
`wip/roadmap_<topic>_scope.md`, seven named fields (Theme Statement, Initial
Scope, Candidate Features, Dependency Sketch, Sequencing Constraints, Downstream
Artifact State, Coverage Notes) at :374-395, which "causes `/roadmap` to skip its
Phase 1, analogous to the existing `/explore` Phase 5 handoff pattern"
(:371-372). It also passes `--upstream <strategy-path>`.

**Phase N — Finalization** (`phase-finalization.md`, 798 lines)

Three exits plus a fallthrough (:44-60):

- **Exit 1 full-run** — STRATEGY + ROADMAP (AC11b, :110-122, two
  `exit_artifacts` entries), or STRATEGY alone (AC11a, :91-108) **only** when a
  matching `chain_skipped:` declination exists. ":106-108" — "A STRATEGY-only
  full-run with no recorded declination means `/roadmap` was dropped without the
  author asking, which is a contract violation rather than a permitted shape."
- **Exit 2 re-evaluation**, two sub-shapes: *re-evaluation* (:230-268, triggered
  from resume row 5 when the existing STRATEGY's falsifiability claims all still
  hold) and *rejection* (:270-334, `/strategy` Phase 5 Reject fired inside the
  chain; charter captures the discard SHA via read-only `git log` and issues no
  git writes, :300-302). Both write a Decision Record under `docs/decisions/`.
- **Exit 3 abandonment-forced** (:383-466) — four triggers; force-materializes
  the most-recently-running child's intermediate as a schema-compliant Draft
  carrying `<!-- charter-status-block: abandonment-forced; ... -->`.
- **Clean-cancel** (:501-525) — R8 tie-break step 3. No state file, no artifact,
  no `exit:` value; explicitly "NOT a contract violation" of invariant I-2.

Full-run additionally runs a **validator pass-through** (AC24, :136-228):
`shirabe validate --format json --visibility=<lowercased>` against the Draft
STRATEGY, parsing the `shirabe-validate/v1` envelope and branching 0/1/2. The
case-translation seam (`Public → public`) lives here deliberately (:153-164).
Note this fires **only for Exit 1 and only against the STRATEGY** (:224-228) —
the ROADMAP and VISION get no chain-level validation.

Then the R9 hard-finalization check runs (spec in
`phase-state-management.md:290-379`, four failure modes, fails closed, "NOT
skipped under `--auto` mode", :344-345).

**There is no cleanup phase.** `grep -rn "cleanup" skills/charter/` returns
exactly one incidental prose mention (`phase-state-management.md:431`). Charter
never removes its own state file, its own `wip/roadmap_<topic>_scope.md` handoff,
or any child wip artifact.

### 2. Skipping behavior — the exact decision text

Charter has **three different skip mechanisms**, and only one of them asks the
author.

#### `/vision` — auto-skip on a settled artifact, with a signal override

`phase-2-chain-orchestration.md:32-38`:

> `/charter` invokes `/vision` unless an Accepted or Active VISION already exists
> at the published path. Phase 1 inspects `docs/visions/VISION-<topic>.md` for
> the topic slug; if nothing Accepted or Active is there, `/vision` runs. **A
> cold start is therefore always a `/vision` run — there is no upstream thesis to
> build on, and nothing the author says about the thesis changes that.**

:40-47:

> When an Accepted or Active VISION *does* exist at that path, the thesis-shift
> question decides whether `/vision` runs anyway. A positive signal overrides the
> auto-skip and fires the invocation; no signal leaves the existing VISION in
> place and the chain skips the child, recording it in `chain_skipped`. **The
> question is an override on an existing VISION, not a second route into the
> child, and this is the only case where the answer changes what the chain
> does.**

So: **skipping `/vision` is conditional on an existing upstream doc at a settled
status. That is the only trigger.** The author *is* asked something —
`phase-1-discovery.md:144` requires verbatim:

> *"Is the long-term thesis shifting, or is this an operational layer below
> it?"*

— but the answer is inert on a cold start. `phase-1-discovery.md:150-155`: "The
classification decides the `/vision` invocation only when an Accepted or Active
VISION already exists at `docs/visions/VISION-<topic>.md` — a positive signal
overrides it. On a cold start `/vision` runs regardless, and the question is
asked for the framing it gives the conversation." Classification is agent
judgment over three anchor categories (thesis-change, new-frame,
VISION-rejection; :157-178), tie-breaking to no-signal when unsure (:192-197).

#### `/comp` — a two-condition environmental gate, author not consulted

:82-86 — Private visibility AND `skills/comp/SKILL.md` on disk. The third pattern
condition (a discovery signal) is "satisfied implicitly for `/comp` v1 by the
visibility gate" (:88-93). On failure, the **Stated-Skip Rule** (:95-111)
requires one of two fixed conversational sentences:

> *"Skipping competitive analysis — `/comp` writes a private-only artifact and
> this repo is public. The chain continues without it."*
>
> *"Skipping competitive analysis — the `/comp` skill isn't installed in this
> workspace. The chain continues without it."*

The skip is conversational only. ":115-130" — `comp` never enters
`planned_chain`, never gets a `chain_skipped:` entry, never reaches anything
under `docs/`. The stated reason: "A child whose gate never opened was never
planned, so there is nothing to record; `chain_skipped:` is for children that
were planned and then dropped, like a declined `/roadmap`."

#### `/strategy` — ALWAYS, no gate

:188-197: "`/charter` ALWAYS invokes `/strategy`. It is the load-bearing child of
the chain... **There is no condition under which `/charter` skips `/strategy`**;
if `/strategy` cannot run to completion the chain enters the abandonment-forced
exit path."

#### `/roadmap` — ALWAYS, with an explicit author declination

:232-236:

> `/charter` ALWAYS invokes `/roadmap` on a full-run chain. **No property of the
> just-produced STRATEGY feeds the decision**: `/charter` does NOT count Building
> Blocks, does NOT test the Coordination Dependencies section for qualifying
> entries, and does NOT parse the document for feature-sequencing surface. The
> chain that produced a STRATEGY produces a ROADMAP.

:238-244 draws the read-vs-decide line: "`/charter` still READS those sections...
The distinction is what the reading is for: filling in the handoff and informing
the author, never deciding whether the invocation happens."

The one skip path is the **roadmap confirmation prompt** (:249-328). Charter
reads the Draft STRATEGY and walks three observations (:260-284): **O1** Building
Blocks describe deliverables vs open questions; **O2** invalidation conditions
name signals someone would act on; **O3** the STRATEGY does not explicitly defer
its own work ("Its absence is neutral, not positive"). Roll-up rule at :286-287:
"headed-for-execution unless O3 fires, or O1 and O2 both read
not-headed-for-execution."

Crucially, the walk **cannot change the pre-selected answer** (:318-322):

> The default is **Proceed** in both readings. A negative reading changes what
> `/charter` says, never which answer is pre-selected — the observations inform
> the author, they do not vote. And the observation walk is not a gate: whatever
> it reads, `/charter` still invokes `/roadmap` unless the author says otherwise.

:324-327 — "In `--auto` mode the prompt does not fire at all and `/roadmap`
always runs — there is no roadmap-specific `--auto` special case... The
declination is an interactive choice, never an inference."

A declination writes `chain_skipped: [{child: roadmap, reason: author declined
the roadmap at the confirmation prompt}]` while `roadmap` **stays in
`planned_chain`** (:330-339). :345-348 frames it as marking the STRATEGY
**non-actionable**, "not a judgment about the STRATEGY being too small or too
simple to sequence." And :350-359 closes the other door: "The confirmation prompt
is the ONLY path that skips `/roadmap`. Phase 1's 'Adjust' option re-shapes the
chain before any child fires, but it cannot drop `/roadmap`."

#### Is there an "entry altitude" concept?

**No.** Nothing in charter lets the author or the parent choose where the chain
starts. The chain always begins at `/vision`'s gate and runs down. The closest
thing is Phase 1's **Adjust** option (`phase-1-discovery.md:296-304`):

> **Adjust** — the author wants a different chain shape. The prompt routes the
> author back to Phase 1 discovery for chain-shape redirection BEFORE any child
> fires. The redirected discovery may force a previously-skipped child on (e.g.,
> "force `/vision` on, even though an Accepted VISION exists"), opt out of a
> child that would otherwise fire, or reframe the topic entirely.

But Adjust has almost nothing to act on: `/strategy` has no gate, `/roadmap`
cannot be dropped there, and `/comp`'s gate is environmental. In practice Adjust
toggles `/vision` and re-frames the topic. Contrast `/scope`, which states its
position outright (`skills/scope/SKILL.md:348-350`): "The proposal never offers a
shorter chain, because `/scope` has no way to produce one. An author who wants to
start above `/brief` invokes `/design` or `/plan` directly."

The chain-proposal prompt's canonical shape (`phase-1-discovery.md:259-263`):

> *"Based on our conversation, here's the chain I propose: skip `/vision` because
> an Accepted VISION already exists and the thesis isn't shifting, skip `/comp`
> because this repo is public and a COMP is private-only, run `/strategy`, run
> `/roadmap`. Proceed / Adjust chain / Bail?"*

":246-251" — "`/strategy` and `/roadmap` always appear as 'run' — both gates are
unconditional."

### 3. What #252 changed, and what it explicitly did not

`70cd921`, "feat(charter): always produce a ROADMAP, and let one feature be
enough (#252)", merged 2026-08-09, 88 files, +2618/−817. PR is
`https://github.com/tsukumogami/shirabe/pull/252`, state MERGED.

**What it changed on charter's skipping surface:**

1. **Deleted `/roadmap`'s computed threshold.** The removed text required "The
   STRATEGY's Building Blocks section contains 3 or more blocks" plus "at least
   one non-empty [Coordination Dependencies] entry that references another
   Building Block by name", and asserted "Skipping `/roadmap` when the shape
   gates fail is correct behavior, not a degraded path — `/roadmap`'s value
   depends on the upstream STRATEGY exhibiting feature-sequencing surface." The
   old rationale header `### Why /roadmap Is Conditional` became `### Why
   /roadmap Is Unconditional`. The retirement reasoning survives in the shipped
   file at :431-438: "Every author and every agent reasoning about the chain had
   to hold two counting rules in their head to predict what `/charter` would do,
   and the payoff was skipping a small, disposable document. 'The chain that
   produces a STRATEGY produces a ROADMAP' is one sentence and needs no
   arithmetic."

2. **Reclassified `/vision`'s gate** from EITHER-signal to
   Mandatory-with-auto-skip-plus-override, and retired EITHER-signal from the
   shared vocabulary (`references/parent-skill-pattern.md:181-195`). The old text
   read "`/charter` invokes `/vision` when EITHER of two signals is present. Both
   signals are independent." The PR body is explicit this is nomenclature: "No
   gate's behavior changed — the same children fire on the same runs." What *did*
   materially change in prose was the cold-start clarification: the no-signal
   default used to read "the chain proposal proceeds without inviting `/vision`
   as a candidate" and now reads "changes nothing on a cold start, where
   `/vision` runs either way."

3. **Replaced `/comp`'s degenerate-silence rule with the stated-skip rule.** The
   deleted rule demanded "byte-identical chain-proposal output" between public
   and private runs and forbade any explanation. PR body: "That misread the
   visibility rule, which governs document references rather than what the agent
   may say." `/comp` also became a fourth named child in the chain proposal
   (three → four, `phase-1-discovery.md:235-236`).

4. **Removed ROADMAP's two-feature minimum**, which is what made the
   always-ROADMAP rule viable. PR body: "The floor stranded any strategy whose
   work was a single feature: no legal path into `/scope`, no progress tracking.
   Zero features is still rejected."

5. Adjacent chain-integrity fixes: `/brief` no longer accepts a PRD as upstream;
   `/strategy` no longer records a grounding PRD in `upstream:` (leaving #257
   open); `upstream:` now documented as pointing at "the nearest artifact
   actually produced above it," omitted when nothing was; a validator chain-walk
   bug fixed; decision-point wording audited across eleven skills.

**How far did "always produce a ROADMAP" go toward "always run every step"?** One
child out of four. `/roadmap` moved from a parent-computed threshold to
ALWAYS-with-declination. `/strategy` was already ALWAYS. `/vision` and `/comp`
were untouched as *whether-to-run* gates — `/vision` still auto-skips against a
settled VISION, `/comp` still skips on visibility or skill absence.

**What it explicitly did not do:**

- Did not touch `/vision`'s or `/comp`'s gates (only `/vision`'s label and
  `/comp`'s messaging).
- Did not introduce cleanup, consolidation, or per-child validation.
- Did not resolve the PRD-as-strategy-grounding question — it shipped as an
  inline caveat in the skill itself (`phase-2-chain-orchestration.md:215-218`):
  "*Open: whether a STRATEGY may be grounded in a tactical-chain PRD at all is
  unresolved — see [#257]. The PRD is never recorded as the STRATEGY's
  `upstream:`; only the grounding input remains open.*"
- Did not generalize the scope model.
  `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:353-372`,
  Decision 9 — chosen option A was "state in prose that the consolidation model
  is a no-op on the strategic chain, and change nothing"; option B, "implement
  the same model in `/charter` now", was rejected as "Out of scope per the PRD":

  > `/charter` has already taken the run-every-child half of this: PR #252 made
  > `/roadmap` an ALWAYS child with an author declination rather than a threshold
  > the parent computed, which is the same move Decision 1 makes for `/design`.
  > The consolidation half does not generalize, and the mapping test from
  > Decision 4 says why. STRATEGY's required sections have no home for a VISION's
  > Audience, Value Proposition, Org Fit, or Success Criteria; ROADMAP's have no
  > home for a STRATEGY's Defensibility Thesis, Building Blocks, or
  > Bet-Specific Falsifiability. Zero strategic hops are absorbable, so porting
  > the judgment would install a rule that can only ever return `keep`. **The
  > model is intended to generalize; generalizing it today changes nothing, which
  > is the reason not to.**

  Note that this decision addresses only the *consolidation* half. It does not
  say the *run-every-child* half is finished for charter — it says #252 "has
  already taken" it, which is true only for `/roadmap`.

### 4. Artifact durability, and whether charter consolidates

**Durable, committed under `docs/`:**

| Artifact | Path | Producer |
|---|---|---|
| VISION | `docs/visions/VISION-<topic>.md` | `/vision` |
| STRATEGY | `docs/strategies/STRATEGY-<topic>.md` | `/strategy` — the declared durable terminal artifact |
| ROADMAP | `docs/roadmaps/ROADMAP-<topic>.md` | `/roadmap` |
| Decision Record | `docs/decisions/DECISION-strategy-<topic>-{re-evaluation\|rejection}-<YYYY-MM-DD>.md` | `/charter` directly |
| Force-materialized partial | the triggering child's canonical `docs/` path | `/charter` |

SKILL.md:26-32 draws the durable/working line:

> STRATEGY is still the *durable* terminal artifact even though `/roadmap` runs
> after `/strategy`: the ROADMAP is a working artifact that drives work rather
> than recording it, while the STRATEGY stays in `docs/strategies/` as the audit
> trail. Both appear in `exit_artifacts:`.

SKILL.md:34-38 then qualifies "working" — added by #252:

> A working artifact is not a self-disposing one. `/roadmap`'s own `## Artifact
> Lifecycle` section owns the completion condition, and the cascade only retires
> a ROADMAP through a finished downstream PLAN — a ROADMAP nobody plans against
> persists until someone removes it.

Confirmed against `skills/roadmap/SKILL.md:60-68`: "**Lifecycle:** Working.
Completion condition: all features on the ROADMAP are at status Done AND all
referenced GitHub issues are closed... Deleted by: the work-on cascade's
handle_roadmap_deletion step." `/vision` and `/strategy` both declare
"**Lifecycle:** Durable" (`skills/vision/SKILL.md:36-38`,
`skills/strategy/SKILL.md:53-57`).

**Non-durable in principle, never cleaned in practice:**
`wip/charter_<topic>_state.md`, the `wip/roadmap_<topic>_scope.md` handoff
charter writes itself, and every child wip artifact
(`wip/strategy_<topic>_discover.md`, `wip/vision_<topic>_scope.md`,
`wip/research/*`). `phase-state-management.md:387-413` treats the state file as
durably public: "the `wip/` artifact is committed to the feature branch during
the run; on push, the branch is publicly visible... Squash-merge to main removes
the `wip/` files from main's history, but it does NOT remove them from the
feature branch's pre-merge commits." Free-text exposure surfaces named:
`rejection_rationale`, `referenced_strategy`, `chain_skipped[].reason`
(:404-409).

**Does charter ever consolidate or merge artifacts? No.** Each child always emits
its own doc, and nothing in the skill tree removes one. The only thing that
reduces the artifact count is a skipped child — i.e. a doc that was never
written. There is no analogue of `/scope`'s Consolidation Judgment
(`skills/scope/SKILL.md:424-453`), no absorb/keep verdict, no carry check, no
re-point rule. Decision 9 above is the recorded reason.

### 5. Structural comparison to `skills/scope`

They share the pattern-level floor and diverge everywhere below it.

#### Shared, exactly

Both SKILL.md Reference Files tables cite the same six shared references (charter
:223-228, scope :321-326):

- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md`
- `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`
- `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md`

Also shared: single-agent prose team shape;
`--auto`/`--interactive`/`--max-rounds=N`; the `^[a-z0-9-]+$` slug regex with
AS-PROVIDED validation and path-rejection; the `wip-yaml-md` storage substrate;
the same three exit paths plus clean-cancel; the same `## Repo Visibility:`
detection with default-Private and the literal "Default to Private if unknown"
warning; the 7-day stale threshold (scope inherits charter's —
`skills/scope/SKILL.md:260-264`, "The threshold inherits the default `/charter`
chose for R16"); and the R9 hard-finalization check.

**Is there a shared conformance doc?** Not as a separate file. The conformance
contract is `references/parent-skill-pattern.md:540-565`, `## Required SKILL.md
Structural Elements` — seven elements (Input Modes, execution-mode flag parsing,
topic-slug constraint, Workflow Phases diagram, Resume Logic ladder, Phase
Execution list, Reference Files table). Both parents state alignment to it:
charter SKILL.md:42-44 ("the seven SKILL.md structural elements below align
section-by-section"), scope SKILL.md:34-37 (same phrasing, plus "`/scope` is the
second concrete consumer after `/charter`"). The pattern doc's other sections
both bind: Semantic Invariants (:40), Three Exit Paths (:78), Gate Vocabulary
(:113), Conditional Feeder Invocation Shape (:197), Named Substitution Surfaces
(:274), Team-Shape Declarator (:316), Dispatch Contract (:366), Team-Lead
Operating Discipline (:601).

#### Divergences

**a. State-schema file location.** Scope has a dedicated non-phase reference,
`skills/scope/references/state-schema.md`. Charter folds the identical role into
a *phase* file, `skills/charter/references/phases/phase-state-management.md` — a
phase file for something that is not a phase, and it is not in charter's Workflow
Phases table (it appears only in the Reference Files table, SKILL.md:232, as "All
phases").

**b. Phase count and cleanup.** Scope has five phases including
`skills/scope/references/phases/phase-4-cleanup.md`, which removes
`wip/scope_<topic>_*` plus `wip/{brief,prd,design,plan}_<topic>_*` and
`wip/research/{prd,design}_<topic>_*` while preserving durable artifacts (scope
SKILL.md:310-315). Charter has four phases and no cleanup file.

**c. Phase naming.** Scope: `phase-3-exit-finalization.md`, numbered "Phase 3".
Charter: `phase-finalization.md`, called "Phase N" throughout.

**d. Resume-ladder shape.** Charter's is 10 flat rows (`phase-resume.md:47-60`):
meta rows 1-4 and 9-10, parent slots 5-8 (rows 5-6 status-aware STRATEGY, rows
7-8 partial-child-run for `/strategy` and `/vision`; slot 7 feeder-doc "is
unfilled because `/charter` has no feeder-doc case", SKILL.md:173-175). Scope's
is 9 rows: meta 1-4 and 8-9, slots 5-7 — with Slot 5 itself expanding to 9
sub-rows evaluated most-downstream-first, including refuse-and-redirect rows for
PLAN-Active/PLAN-Done (scope SKILL.md:266-275).

**e. Drift-prompt vocabulary differs.** Charter: **Re-run / Accept / Proceed
without** (`phase-resume.md:364-379`). Scope: **Re-run / Accept /
Proceed-without** (hyphenated, scope SKILL.md:270-271). Same three concepts,
different literals for eval grepping.

**f. `chain_skipped` entry shape.** `{child, reason}` in charter
(`phase-state-management.md:141-144`) vs `{name, reason}` in scope. Filed as
issue #254 item 2.

**g. Parent-orchestration signalling — a live mismatch.**
`references/parent-skill-state-schema.md:176-193` defines the
`parent_orchestration:` block as "the pattern-level convention **every parent
writes and every child reads identically**", with fields fixed at the pattern
layer (`invoking_child:`, `suppress_status_aware_prompt:`, `rationale:`) — "no
parent extends or omits any field". Scope implements it: it appears in
`skills/scope/SKILL.md`, `phase-0-setup.md`, `phase-2-chain-orchestration.md`,
`references/state-schema.md`, and `evals/evals.json`, and scope's Phase 0 has a
stale-sentinel self-heal.

Charter does not. `grep -rn "parent_orchestration" skills/charter/` returns
nothing, and the 17-field schema at `phase-state-management.md:100-211` omits it.
Charter instead describes a `--parent-orchestrated` **flag** at
`phase-resume.md:415-431`, framed as awaiting child adoption:

> Future child-side adoption — when `/strategy`, `/vision`, and `/roadmap`
> SKILL.md updates land — binds to the same flag name; this file is the canonical
> contract surface for the flag's meaning.

But the children already read the **block from charter's state file**.
`skills/vision/SKILL.md:145-146` and `skills/strategy/SKILL.md:189-190` both open
their resume ladder with: `parent_orchestration sentinel in
wip/scope_<topic>_state.md or wip/charter_<topic>_state.md -> see
references/fixes/sub-agent-dispatch.md`. So the children look in charter's state
file for something charter's own schema never writes.

**h. Sections scope has that charter has none of:** Coordination Intent
(multi-repo coordination PRs, `--coordinated`, `## PR Grouping Policy:` / `##
Reviewability Ceiling:` headers, `shirabe validate --coordination-body`,
`--merge-gate`, R20 coordinated abandonment — scope SKILL.md:117-179 and
:640-664); Consolidation Judgment (:424-453); "Why the Artifact Set Shrinks"
(:372-422); per-child Validator Pass-Through (:563-588 — scope validates *each*
intermediate before invoking the next child; charter validates once, at full-run,
STRATEGY only); R20 structural file-existence checks; `--max-rounds` default of 5
vs charter's unbounded (scope :104-110 — "overriding `/charter`'s default of 3
per R16.5 / AC16b", though charter's SKILL.md:104 actually says "Default is
unbounded", an internal inconsistency between the two docs).

**i. The philosophical divergence.** `skills/scope/SKILL.md:400-407` records that
scope shipped and then withdrew exactly the thing charter still has:

> A briefly-shipped revision of this skill also let Phase 1 choose an entry
> altitude for the chain. It was withdrawn. The question it asked the author was
> more answerable than the per-hop gates it replaced — which conversation are you
> having, rather than what would an unwritten document have said — but it was
> still a decision that shrank the artifact set before any artifact existed, and
> having two reduction mechanisms fire at different times meant neither read as
> the rule.

And :382-394 of the design: "The per-hop produce-or-skip gates are removed.
`/brief`'s R4 gate, `/prd`'s R5 gate, and `/design`'s R6/R7 shape-dependent gate
stop deciding whether their child runs." Scope preserved the settled-artifact
skip under a **separate name** — re-entry protection, recorded in
`chain_skipped:` with reason
`settled-artifact-at-canonical-path-reentry-protection`, "and the prose around it
states that this protects a settled document from being overwritten and is not a
judgment about whether the artifact was worth writing" (design :388-394); scope
SKILL.md:419-422 restates it: "Anything held back for any other reason is
re-entry protection — a settled artifact is already on disk and re-running would
clobber it — and it is recorded under its own name so the two never blur again."

Charter has no such vocabulary split. Its `/vision` auto-skip and a
re-entry-protection skip are the same undifferentiated thing, recorded in
`chain_skipped` with free-text reasons.

### 6. Known pain

**Issue #254 — "chore(parents): three unresolved items in the parent-skill
chains"** (OPEN, filed 2026-08-08 out of #252). Framing: "Grouped because they
share a shape: machinery guarding decisions that cost less than the guard." Two
of three items are charter's:

- *Item 2*: "`chain_skipped` entries are `{child, reason}` in `/charter` and
  `{name, reason}` in `/scope`. The pattern-level schema defines the field but
  pins neither the entry shape nor the key. Both parents are internally
  consistent; a reader moving between them is not, and any tooling that reads the
  triad has to handle both."
- *Item 3*: "`/charter`'s ladder is ten rows. During PR #252 one row gained a
  disambiguation for a case that turned out to be handled two rows earlier, which
  suggests the match conditions have not been traced end to end. Rows 7-8 in
  particular both require no artifact at the published path, which narrows them
  further than their descriptions imply. This is an audit rather than a known
  defect."

That self-acknowledgment is visible in the shipped file —
`phase-resume.md:242-249`: "A `/charter` chain interrupted mid-`/roadmap`
normally still has its state file, so rows 3-4 match first... Row 6 is the case
where no state file survives."

**Issue #255 — "test: judgment gates in /scope, /explore and /design are
unasserted"** (OPEN, "Found while auditing decision points during PR #252").
Names charter as the site of a specific failure mode: "The one hazard worth
designing against: a verdict assertion can encode the *author's* wrong answer.
**PR #252 hit this — an assertion claimed a cold start does not invoke `/vision`
when the rule says it does, and the fix was to the assertion.**" Charter's suite
is 16 scenarios (`skills/charter/evals/evals.json`): six `baseline-*`, four
`us-*`, four `r7-*` covering the roadmap prompt (declined, informed-prompt,
negative-reading-still-invokes, auto-mode-no-prompt), and
`ac10d-chain-proposal-triad`. No scenario isolates a `/vision`
cold-start-versus-skip verdict beyond the chain-proposal entries.

**Issue #257** (OPEN) is embedded as an inline caveat in the shipped skill
(`phase-2-chain-orchestration.md:215-218`) and again in the PRD
(`docs/prds/PRD-shirabe-charter-skill.md:361-364`).

**In-file placeholders and stale prose:**

- Unresolved `<<ISSUE:5>>` markers still ship in two phase files:
  `phase-finalization.md:18, :127, :430, :604, :629, :678` and
  `phase-state-management.md` (referenced from finalization).
- SKILL.md:141-143 still reads as an unfinished scaffold: "The per-phase bodies
  are authored by downstream issues in the PLAN-shirabe-charter-skill plan. This
  section is the diagram and phase-list shape; downstream phase files plug in
  here."
- `phase-resume.md:281-290` documents a known `/strategy` documentation-vs-
  behavior asymmetry that charter accommodates rather than fixes: "`/strategy`'s
  SKILL.md documents `_scope.md` as the Phase 1 scoping artifact name, but the
  phase files write `_discover.md`. The ladder accommodates the asymmetry by
  reading the artifact that exists on disk, not the artifact the documentation
  claims exists. Fixing `/strategy`'s documentation versus its phase-file
  behavior is out of scope; the PRD explicitly accommodates the asymmetry here."
- Charter's `--max-rounds` default disagrees between charter SKILL.md:104
  ("unbounded") and scope SKILL.md:106-107 ("overriding `/charter`'s default of
  3").

**No document in the repo argues that charter's `/vision` or `/comp` skipping is
itself a defect.** The strongest available signal is Decision 9's framing of #252
as having taken "the run-every-child half" of the scope model — which is accurate
only for `/roadmap`, and which leaves the strategic chain half-converted relative
to the tactical one.

## Implications

**Charter is one-quarter converted, not converted.** The headline of #252 —
"always produce a ROADMAP" — is true and it is also the smallest of the four
possible conversions. `/strategy` needed no conversion (it was ALWAYS from the
start), and `/vision` and `/comp` were left with per-hop gates of exactly the
shape `/scope` removed for `/brief`, `/prd`, and `/design`. Any parity work
therefore has one live target on charter's chain (`/vision`) and one contested
one (`/comp`, whose gate is environmental rather than a judgment about whether
the artifact is worth writing, and which may not be the same category of thing at
all).

**The vocabulary split is the load-bearing part, not the gate removal.** Scope's
move was not simply "run every child" — it was to separate *the parent judging
whether a document is worth writing* (removed) from *protecting a settled
document from being clobbered* (kept, renamed re-entry protection, recorded with
a fixed machine-readable reason string). Charter's `/vision` gate is already
mostly the second thing wearing the clothes of the first: it fires on artifact
state, not on a judgment about value. Converting it may be closer to a renaming
plus a fixed reason string than to a behavioral change — and the thesis-shift
override has no counterpart in scope's re-entry protection, so that is where the
real design question sits.

**Charter has no cleanup, which compounds with always-run.** Scope's Phase 4
deletes `wip/scope_<topic>_*` plus every child's wip artifact on full-run or
re-evaluation. Charter deletes nothing — including the `wip/roadmap_<topic>_scope.md`
handoff it writes itself. Every additional child charter runs adds wip residue
that no phase reclaims, on a branch the state-management doc already describes as
"durably public from feature-branch push time."

**Two docs disagree about charter's own `--max-rounds` default** (unbounded vs
3), which means at least one of the two parents' SKILL.md is stating a fact about
the other that is not true. That is a small thing, but it is the same class of
problem as the `{child,reason}`/`{name,reason}` mismatch: the two parents were
written against each other's prose rather than against a shared source.

**Charter's validation coverage is asymmetric to scope's.** Scope validates every
child's intermediate before invoking the next; charter validates once, at
full-run, against the STRATEGY only. A ROADMAP charter produced has never been
run through `shirabe validate` by charter — which matters more now that #252 made
ROADMAP production unconditional.

## Surprises

**(a) Charter's three skip mechanisms are three different kinds of thing, and
only one asks the author.** `/vision` skips on artifact state with a
conversational override the author does not know is an override; `/comp` skips on
environment (repo visibility plus a file existing on disk) with the author told
after the fact and never consulted; `/roadmap` skips only when the author
explicitly declines, and the parent's own three-observation reading of the
STRATEGY is forbidden from changing the pre-selected answer. Three mechanisms,
three different loci of control, one shared word ("skip") and one shared state
field (`chain_skipped`) — except `/comp` does not even use that field. Reading
the SKILL.md alone, none of this is visible; it takes all of
`phase-1-discovery.md` and `phase-2-chain-orchestration.md` to see that "skip"
means three unrelated things.

**(b) Charter never writes `parent_orchestration:`, yet `/vision` and
`/strategy` both read that sentinel out of charter's own state file.**
`references/parent-skill-state-schema.md:176-193` calls the block "the
pattern-level convention every parent writes and every child reads identically"
with fields fixed at the pattern layer. `/scope` implements it across six files.
Charter's 17-field schema (`phase-state-management.md:100-211`) omits it entirely
and `grep -rn "parent_orchestration" skills/charter/` returns nothing — charter
instead documents a `--parent-orchestrated` **flag** (`phase-resume.md:415-431`)
described as awaiting "future child-side adoption... when `/strategy`,
`/vision`, and `/roadmap` SKILL.md updates land." Those updates already landed,
on the other side: `skills/vision/SKILL.md:145-146` and
`skills/strategy/SKILL.md:189-190` open their resume ladders by checking for the
sentinel in `wip/charter_<topic>_state.md`. The children are reading a key
charter's contract does not define, out of a file charter owns.

**(c) Decision 9 scoped its "change nothing" ruling to the consolidation half
only — its claim that #252 "has already taken" the run-every-child half is true
for `/roadmap` alone.**
`docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:362-372` reads
"`/charter` has already taken the run-every-child half of this: PR #252 made
`/roadmap` an ALWAYS child with an author declination rather than a threshold the
parent computed, which is the same move Decision 1 makes for `/design`." The
sentence is accurate about `/roadmap` and silent about `/vision` and `/comp`,
which still carry per-hop gates. Every argument the decision then makes for
"changing nothing" is about consolidation specifically — the mapping test, the
"rule that can only ever return `keep`" — and none of it bears on whether
charter's remaining gates should go. The doc reads as a blanket "charter is
fine"; it is not one.

## Open Questions

1. **Is `/comp`'s gate the same category as `/vision`'s?** `/comp` skips on repo
   visibility and skill-file existence — neither is a judgment about whether the
   artifact would have said anything. Scope's model removed *judgment* gates and
   kept *protection* gates under a new name. `/comp` is arguably a third
   category (capability/eligibility) that the two-name vocabulary does not cover.

2. **What happens to the thesis-shift question if `/vision` becomes always-run
   with re-entry protection?** Today the question exists to override the
   auto-skip, and `phase-1-discovery.md:150-155` already concedes it is asked "for
   the framing it gives the conversation" on a cold start. If the skip becomes
   pure re-entry protection, the question either becomes the trigger for
   *revising* a settled VISION (a different act than running the child fresh) or
   it becomes decorative.

3. **Does charter need a cleanup phase before or as part of any parity work?**
   Charter has no Phase 4 and no `chain_skipped` cleanup story; scope's Phase 4
   is what makes always-running safe on the wip surface. Unclear whether this is
   in scope for a parity effort or a separate gap.

4. **Which parent wins on `{child,reason}` vs `{name,reason}`, and who pays?**
   Issue #254 notes that "picking one means changing the other parent's schema
   doc, its phase files, and its eval assertions." No decision recorded.

5. **Should charter's `parent_orchestration:` gap be fixed as part of parity or
   independently?** It is a pattern-conformance defect that exists today
   regardless of the skipping question, and the children are already coded
   against the correct contract.

6. **What is charter's actual `--max-rounds` default** — unbounded (charter
   SKILL.md:104) or 3 (scope SKILL.md:106-107, citing "R16.5 / AC16b")? The PRD
   would settle it; I did not chase it down.

7. **Is the resume ladder's row 7-8 reachability problem (issue #254 item 3) made
   better or worse by always-running `/vision`?** Row 8 requires
   `wip/vision_<topic>_scope.md` to exist with no STRATEGY at the published path;
   changing when `/vision` fires changes which states are reachable.

## Summary

`/charter` runs four phases (setup, discovery, chain orchestration, finalization)
over up to four children — `/vision`, `/comp`, `/strategy`, `/roadmap` — with no
entry-altitude concept, no consolidation, and no cleanup, landing at one of three
exits with a durable STRATEGY plus a working ROADMAP. PR #252 converted exactly
one of its four children: `/roadmap` moved from a parent-computed
Building-Blocks threshold to an unconditional invocation with an author
declination, while `/vision` kept its auto-skip-against-a-settled-VISION gate
(relabeled but behaviorally untouched) and `/comp` kept its
visibility-plus-skill-existence gate (its silence replaced by a stated skip).
Charter and `/scope` share six pattern reference files, the seven-element
conformance list, the slug regex, the substrate and the three exit paths, but
diverge on cleanup, state-schema placement, ladder shape, `chain_skipped` key
names, per-child validation, and — most concretely — the `parent_orchestration:`
sentinel that `/vision` and `/strategy` already read out of charter's state file
and that charter's schema never writes.
