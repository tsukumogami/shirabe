# Lead: What is the complete surface that has to change when multi-pr plan execution moves from `/work-on` into `/execute`, and what must each place say afterwards?

## Findings

### 1. The 16 known places, verified against current `main`

All sixteen previously-identified locations exist, say what was claimed, and
their line numbers have not drifted from the rebase (the repo apparently
hasn't touched these files since the sweep). Verified verbatim:

- `skills/execute/SKILL.md:12` (frontmatter) — "A `multi-pr` plan is the
  exception: those run through `/work-on` instead."
- `skills/execute/SKILL.md:48-49` — "`multi-pr` — out of scope for `/execute`;
  multi-pr plans run one issue at a time through `/work-on` against the
  repo-persisted PLAN. Direct the user to `/work-on`."
- `skills/work-on/SKILL.md:10` (frontmatter) — "It also runs a `multi-pr` PLAN,
  one issue at a time, each landing its own pull request; every other plan
  mode belongs to `/execute`."
- `skills/work-on/SKILL.md:137-140` — "**`multi-pr`** — run in place, one issue
  at a time. Select the next unblocked issue from the PLAN ... run it as a
  single issue-backed unit ... each landing its own PR. There is no shared
  branch and no cross-issue carry-forward."
- `skills/explore/SKILL.md:55` and `:70` — both routing tables, e.g. "a
  `multi-pr` PLAN is the exception and runs through `/work-on`."
- `skills/explore/references/quality/crystallize-framework.md:36,38` —
  "`multi-pr` PLAN does not qualify: `/execute` refuses that mode and directs
  the author to `/work-on` one issue at a time."
- `skills/explore/references/phases/phase-4-crystallize.md:75` — the same
  precondition, "`multi-pr` PLAN does not qualify; `/execute` refuses that
  mode," restated independently for the phase file (`crystallize-framework.md`
  is quality-check prose; `phase-4-crystallize.md` is the phase script — two
  copies of one rule, confirmed distinct as claimed).
- `skills/roadmap/SKILL.md:349-350` — "ROADMAP-rooted multi-pr chains follow
  the same shape — the final per-feature PR in the chain runs the work-on
  cascade, which performs the atomic PLAN-delete..." — a capability claim,
  confirmed nothing implements it (see below).
- `skills/plan/references/quality/plan-doc-structure.md:95` — table row: "Done
  ... multi-pr: all issues closed and the work-completing PR runs the cascade;
  single-pr: /work-on cascade ran before the PR flipped to ready."
- `skills/execute/evals/evals.json:22-33` — scenario id 2,
  `dispatcher-multi-pr-one-issue-at-a-time`, quoted verbatim in section 4.
- `skills/work-on/evals/evals.json:294-309` (the known line range 299-304
  falls inside this) — scenario id 20, `plan-mode-detection-from-path`, quoted
  in section 4.
- `skills/execute/evals/fixtures/plans/PLAN-multi-pr-test.md` — confirmed: a
  3-issue fixture, `execution_mode: multi-pr`, whose own prose says "run one at
  a time through `/work-on`, no shared branch."
- `docs/prds/PRD-execute-skill.md:307` — requirement D5, quoted verbatim in
  section 3.
- `docs/designs/current/DESIGN-execute-skill.md:138` and `:260`, and Decision
  2 / R1 (actually at lines 96-109, the rejected option at 105-106 and the
  chosen option R1 at 107-109) — all confirmed, quoted verbatim in section 3.
- `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md:276` and `:653` —
  confirmed: both are "What is lost" / consequence text stating "`/execute`
  declines `multi-pr` outright (`skills/execute/SKILL.md`, Input Modes)."

One correction to the prior sweep's framing: it attributed the "breaks
existing invocations and `/work-on`'s own evals" reasoning to "the earlier
split," described elsewhere as if it might live in a separate document. It
does not — it is `docs/designs/current/DESIGN-execute-skill.md:105-106`
itself, the rejected alternative right next to the chosen R1 option two lines
below it. Same document carries both the thing being inverted (R1) and the
reason a cruder version of this same inversion was rejected before.

### 2. Extended sweep: full count and classification

`grep -rniE 'multi-pr|multi_pr'` across the whole repo (excluding `.git/` and
`wip/`, which is this and prior phases' own scratch research and is not part
of the durable surface) returns **890 matching lines across roughly 95
files**. Including `wip/` adds 176 more lines across 11 files (this PRD
chain's own prior-phase research and handoff documents — not committed
surface, will be deleted by cleanup, out of scope for this count per the
wip-hygiene rule).

Classifying all 890 by file:

**Routing claims (say who executes a `multi-pr` PLAN) — load-bearing, ~30
lines across 12 files:**

- The 16 known places above (skills/execute, skills/work-on, skills/explore
  x2 files, skills/roadmap, skills/plan/plan-doc-structure.md, both eval
  suites, the fixture, the PRD, the two designs).
- **`README.md:43-44`** — NOT in the prior sweep. The top-level skill table:
  "`/execute` | ... owns single-pr and coordinated multi-repo plans (a
  multi-pr plan runs under `/work-on` instead)" and "`/work-on` | ... Also
  runs a `multi-pr` plan, one issue at a time, each landing its own PR." This
  is the front door to the whole skill list and must invert with everything
  else.
- **`references/pipeline-model.md:224-227`** — NOT in the prior sweep, and
  the most significant miss. This is a repo-root shared reference (not
  skill-scoped), read by multiple skills for chain/cascade architecture: "Plan-
  level execution (both single-pr and coordinated modes) and the completion
  cascade are owned by `/execute`. `/work-on` is the single-issue engine plus
  an execution_mode dispatcher: it runs multi-pr in place and hands single-pr
  and coordinated plans to `/execute`." This is a third, independent
  restatement of the exact routing rule outside any skill directory.
- **`docs/prds/PRD-execute-skill.md:113` (R4)** — "R4. /execute owns
  plan-level execution for exactly two plan shapes ... It does not own
  multi-pr (single-repo, independent pull requests) execution." A second
  accepted requirement beyond D5 that states the same exclusion and must be
  superseded alongside it.
- **`docs/prds/PRD-execute-skill.md:117-119` (R5)** — "R5 ... multi-pr is
  excluded because it has no such [ephemeral] home — its PLAN doc is
  persisted in the repository for the plan's duration and its per-issue
  artifacts live only for one issue." This is the *reasoning* for the
  exclusion, not just the exclusion — it has to be addressed, not just
  reworded, because a third `/execute` path for multi-pr does not get an
  ephemeral home either (see section 5).
- **`docs/prds/PRD-execute-skill.md:128-131` (R7)** — "The plan-orchestration
  responsibility is removed from /work-on ... Multi-pr plans execute as
  independent per-issue /work-on runs against the repository-persisted PLAN
  doc." A third PRD requirement asserting the routing, alongside D5 and R4.
- **`docs/designs/current/DESIGN-execute-skill.md:21`** (decision-frontmatter
  summary) and **`:249`** (solution-architecture step list) — two more
  restatements inside the same design beyond the two already known (`:138`,
  `:260`), all needing the same correction once Decision 2/R1 flips.
- **`docs/designs/current/DESIGN-capstone-orchestration.md:59-60`** — a
  different, still-`Current` design (about coordinated/multi-repo execution),
  citing the boundary as settled background: "`/work-on` collapses issues to
  PRs only via the `single-pr`/`multi-pr` binary." Minor drift once `/work-on`
  no longer owns that binary, but it's stating precedent, not making the
  decision — lower priority than the PRD/DESIGN-execute-skill.md pair.
- **`docs/briefs/BRIEF-cascade-outline-ac-completeness.md:12-13`** — "An
  author finishing a multi-pr plan knows the cascade refuses to delete the
  PLAN until every outline AC box is ticked off." This describes cascade
  behavior that is mode-agnostic (the AC-completeness check doesn't care which
  skill invoked the cascade); I judge this incidental rather than load-bearing
  — it doesn't assert who runs multi-pr, only what the cascade checks once
  it runs.

**Enum value / schema (the `execution_mode` field itself, PLAN authoring,
lifecycle posture, table structure) — NOT load-bearing for this migration,
~830 lines across ~80 files.** The `multi-pr` string keeps meaning exactly
what it means today (a PLAN whose issues each land independent PRs with no
shared branch); only *who runs it* changes. This bucket is untouched by the
migration and includes:

- `crates/shirabe-validate/src/lifecycle.rs` (118), `checks.rs` (87),
  `formats.rs` (15), `table.rs` (8), `mermaid.rs` (6), `transition.rs` (3) —
  all lifecycle-posture and structural validation keyed on the
  `execution_mode` enum value, none of it about which skill executes it.
- `skills/plan/**` (~135 lines: `SKILL.md`, `evals/evals.json`,
  `references/phases/phase-{2,3,4,7}-*.md`, `plan-format.md`,
  `plan-to-tasks-contract.md`, `plan-doc-examples.md`,
  `scripts/plan-to-tasks.sh` + its test, `requires.tsv`,
  `templates/agent-prompt*.md`) — `/plan`'s decision logic for *when to set*
  `execution_mode: multi-pr` on a new PLAN. This logic is unaffected: `/plan`
  still needs to choose the mode; only the downstream execution owner changes.
  (`plan-to-tasks.sh` itself now runs under `/execute` post-PR#199 for
  single-pr/coordinated, but its multi-pr branch is dead code from the
  routing's perspective — it isn't invoked for multi-pr today and won't be
  called by `/execute`'s new third path either, since that path drives issues
  through `/work-on` per-child rather than pre-materializing tasks.)
- `skills/scope/**` (10 lines) — same "author decides the mode" logic,
  scope-chain version.
- `docs/prds/PRD-{roadmap-plan-standardization,lifecycle-passing-state-
  validation,single-pr-plan-validation,lifecycle-draft-ready-discipline,
  shirabe-scope-skill,issue-outlines-one-parser,plan-skill-rework,skill-
  cascade-lifecycle-check,shirabe-artifact-decision-contract,execute-friction,
  cascade-outline-ac-completeness,work-on-definition-of-done,skill-preflight-
  checks,shirabe-pattern-v1-workflow-friction,shirabe-pattern-v1-ergonomics,
  release-same-day-merges,fold-record-removal,doc-vs-github-state-
  reconciliation}.md` and the parallel `docs/designs/current/DESIGN-*.md` /
  `docs/briefs/BRIEF-*.md` for the same features (~250 lines total) — all
  about tracking-level defaults, lifecycle strictness, table shape, or
  decision-record content keyed on the enum, not about routing ownership.
  One exception worth flagging: `docs/prds/PRD-work-on-definition-of-done.md:
  144` uses "coordinated multi-PR execution" as a generic phrase (plural,
  informal) meaning "coordinated mode," not the `multi-pr` enum value —
  classified incidental.
- `docs/decisions/DECISION-{multi-pr-posture-detection,cascade-trigger-
  mechanism,lifecycle-strict-mode-interface,orphan-doc-passing-state-rule}-
  2026-06-06.md` (~31 lines) — posture-detection and cascade-trigger decision
  records. See Surprises: `DECISION-cascade-trigger-mechanism-2026-06-06.md:
  210` already names `skills/work-on/SKILL.md` as where the finalization logic
  lives, which stopped being true when PR #199 moved it into `/execute` — a
  pre-existing, un-amended staleness this migration will compound rather than
  cause.
- `references/{workflow-principles,parent-skill-state-schema,coordination-
  strategy,split-triggers,issues-table,fixes/claude-md-conventions}.md`,
  `skills/design/references/design-format.md`,
  `skills/roadmap/references/roadmap-format.md` (~10 lines total) — schema
  and format documentation for the enum value, not routing.
- `docs/specs/decisions-file-format.md` (3), `docs/plans/PLAN-work-on-
  friction-fixes.md` (2 — itself a live `execution_mode: multi-pr` PLAN
  currently running through today's `/work-on` dispatcher, useful as a
  concrete backward-compatibility example, see section 6),
  `crates/shirabe/src/{main.rs,plan_outlines.rs}` and its `tests/fixtures/**`
  golden-corpus PLAN fixtures (~16 lines) — test data and doc-comments using
  the enum value, not routing.

**Fixture:** one physical fixture file (`PLAN-multi-pr-test.md`), shared by
both eval suites (see section 4).

**Test assertions:** the two known eval scenarios, plus one more found in the
sweep — `skills/work-on/evals/evals.json` scenario id 25
(`e2e-cross-mode-no-contamination`) also drives the same fixture through
`/work-on` and asserts the current routing as part of a broader
three-invocation scenario (see section 4).

### 3. Classification by change type

**Reword (prose that simply states the wrong owner today):** all of the
routing-claim skill prose in section 2's first bucket except the two accepted
documents below — `README.md`, `references/pipeline-model.md`,
`skills/explore/SKILL.md` (both rows), `crystallize-framework.md`,
`phase-4-crystallize.md`, `skills/work-on/SKILL.md` (frontmatter + the
Plan Input section), `skills/execute/SKILL.md` (frontmatter + Input Modes),
`skills/roadmap/SKILL.md:349-350`, `skills/plan/references/quality/plan-doc-
structure.md:95`, `docs/designs/current/DESIGN-capstone-orchestration.md:
59-60`.

**Invert (the routing table entry flips to the opposite answer, not just
different words):** `skills/execute/SKILL.md`'s Input Modes list item for
`multi-pr` (from "out of scope, direct to `/work-on`" to "a third execution
path, run it"), and `skills/work-on/SKILL.md`'s Plan Input dispatcher (the
`multi-pr` branch either disappears or becomes a refusal/redirect — settled by
the backward-compatibility decision in section 6, not by this lead).

**Delete or fix (documents a capability that nothing implements, independent
of the routing question):** `skills/roadmap/SKILL.md:349-350` and
`skills/plan/references/quality/plan-doc-structure.md:95` both claim "the
work-completing PR runs the [work-on] cascade" for multi-pr. I confirmed by
searching for cascade invocation inside `/work-on`: `run-cascade.sh` lives
exclusively at `skills/execute/scripts/run-cascade.sh` (moved there in PR
#199) and is invoked from exactly one place, `skills/execute/koto-templates/
execute.md:709`. Nothing under `skills/work-on/` calls it. So today, a
multi-pr PLAN's issues can all close and no cascade ever runs — the claim in
both files is aspirational prose describing a capability that has never
existed, or that was lost in the #199 split with no amendment recorded (the
handoff's exploration could not tell which, and neither can I from static
inspection alone). Once `/execute` grows a multi-pr path that reuses
`run-cascade.sh` (section 5), this claim becomes true for the first time —
but it should still be corrected now to say `/execute`, not "work-on cascade."

**Supersede via decision record, not silent contradiction (accepted
documents whose text is a decided position, not just descriptive prose):**
exactly two, as the lead specifies:

1. `docs/prds/PRD-execute-skill.md:307`, requirement **D5**: "**D5 — Multi-pr
   execution is independent per-issue /work-on runs.** A multi-pr plan
   executes one issue at a time through /work-on against the
   repository-persisted PLAN doc, with no plan-level coordinator and no
   cross-issue state. ... (Resolves the BRIEF/PRD multi-pr open question.)"
   This is a numbered, accepted requirement — the PRD's resolution of what it
   calls an explicitly open question. Reversing it needs a decision record
   citing D5 by name, not a docs edit that quietly disagrees with an accepted
   requirement. (R4 at `:113` and R7 at `:128-131` restate the same
   requirement and should be amended in the same pass, though the lead singles
   out D5 specifically as the numbered decision point.)

2. `docs/designs/current/DESIGN-execute-skill.md`, **Decision 2's chosen
   routing option, R1** (lines 107-109): "**Routing — thin dispatcher (chosen,
   R1).** `/work-on <PLAN>` keeps working as a thin dispatcher that reads
   `execution_mode`: it runs multi-pr in place per issue (PRD D5) and hands
   single-pr/coordinated PLANs to /execute." This is a Considered-Options
   decision record inside a `status: Current` design — R1 was chosen over the
   rejected hard-removal option two lines above it (105-106). The new
   direction is functionally a third option nobody scored in that decision:
   "multi-pr becomes a third `/execute` path." That has to be added to
   Decision 2 as an amendment (or a new decision record cross-referencing it),
   not merged into the prose as if R1 had always said this.

`docs/designs/current/DESIGN-multi-pr-plan-decoupling.md:276,653` are
different in kind from the two above: they're not decided routing options,
they're "Known Limitations" / "What is lost" text describing today's gap as a
cost of a different, already-shipped decision (issueless multi-pr milestone
tracking). Once `/execute` accepts multi-pr, this specific limitation
disappears — the text should be corrected to reflect that the gap is closed,
which is a simple reword/delete, not a supersession of a chosen option.

### 4. The eval problem

**Scenario A — `skills/execute/evals/evals.json:20-35`, id 2, name
`dispatcher-multi-pr-one-issue-at-a-time`:**

```
"prompt": "/work-on skills/execute/evals/fixtures/plans/PLAN-multi-pr-test.md",
"expected_output": "The /work-on dispatcher reads execution_mode: multi-pr,
re-validates the enum, and routes in place: it selects the next unblocked
issue from the PLAN (an issue is blocked while its Dependencies reference
open issues), runs it as a single issue-backed unit against the
repo-persisted PLAN, and lands its own PR. There is no shared branch and no
cross-issue carry-forward. The dispatcher does NOT hand off to /execute and
does NOT run the whole plan at once."
"expectations": [
  "Agent reads execution_mode: multi-pr from the PLAN frontmatter and
   re-validates the enum",
  "Agent selects the next unblocked issue (first issue with no open blocking
   dependency)",
  "Agent runs that single issue in place as an issue-backed unit, landing its
   own PR",
  "Agent does NOT hand off a multi-pr PLAN to /execute",
  "Agent does NOT create a shared branch or assemble cross-issue carry-forward
   for multi-pr"
]
```

The fourth expectation, "does NOT hand off ... to /execute," is exactly the
assertion the new decision inverts. This scenario is testing the skill it's
filed under (`execute`) by asserting that `/execute` is never invoked — an
odd shape already, and one the migration makes actively wrong: the new
behavior for this exact prompt should hand off (or, if `/execute` becomes the
correct invocation for multi-pr, the prompt itself should change to
`/execute <PLAN-multi-pr-test.md>`).

**Scenario B — `skills/work-on/evals/evals.json:294-309`, id 20, name
`plan-mode-detection-from-path`:**

```
"prompt": "/work-on skills/execute/evals/fixtures/plans/PLAN-multi-pr-test.md",
"expected_output": "Agent detects the PLAN.md path and acts as the thin
dispatcher: it reads execution_mode from the PLAN frontmatter, re-validates it
against the closed set {single-pr, multi-pr, coordinated}, and routes. For
this multi-pr PLAN it runs in place -- selects the next unblocked issue and
runs it as a single issue-backed unit landing its own PR. A single-pr or
coordinated PLAN would instead be handed off to /execute. The dispatcher does
NOT initialize a plan-orchestrator template and does NOT run
plan-to-tasks.sh; that orchestration now lives in /execute. It does NOT call
gh issue view to detect the PLAN path."
"expectations": [
  "Agent detects the PLAN.md path and routes via the dispatcher (reads
   execution_mode, not issue-backed or free-form)",
  "Agent re-validates execution_mode against {single-pr, multi-pr,
   coordinated} before any path or branch interpolation",
  "Agent routes multi-pr in place (selects the next unblocked issue, runs it
   as a single issue-backed unit landing its own PR)",
  "Agent hands single-pr and coordinated PLANs off to /execute rather than
   running them in /work-on",
  "Agent does NOT initialize a plan-orchestrator template or run
   plan-to-tasks.sh (orchestration lives in /execute)"
]
```

Third expectation asserts the exact behavior being inverted.

**A third scenario the prior sweep missed — `skills/work-on/evals/evals.json:
310-325`, id 25, name `e2e-cross-mode-no-contamination`:** this scenario
drives three sequential `/work-on` invocations in one session (`#42`, a
free-form task, then the same `PLAN-multi-pr-test.md`) to test that state
doesn't leak between modes. Its third expectation: "For invocation (3) plan
path, agent routes via the dispatcher (reads execution_mode; multi-pr in
place, single-pr/coordinated handed to /execute) and does NOT initialize a
plan-orchestrator template." This also asserts current-behavior routing for
the multi-pr leg and will need the same correction as scenario B, even though
it isn't purely about multi-pr — only its third leg is affected, so this
scenario needs a targeted edit, not a rewrite or removal.

**What each must become:** scenario A (currently filed under `/execute`,
asserting `/execute` refuses) most naturally becomes an assertion that
`/execute <PLAN-multi-pr-test.md>` *is* the correct invocation and drives a
third execution path — its prompt changes from `/work-on ...` to
`/execute ...`, and its expectations invert from "does NOT hand off" to
"does hand off" or "does run directly," depending on the design's final
shape. Scenario B, filed under `/work-on`, is really testing the dispatcher's
enum-detection and routing behavior generically (single-pr/coordinated
already hand off correctly) — its multi-pr leg needs to change from "runs in
place" to whatever `/work-on`'s new backward-compatibility behavior is
(redirect-with-a-pointer is the most likely shape given section 6, but that
choice belongs to the design hop). Scenario id 25's third leg needs the same
narrow correction.

**Whether the fixture stays, changes, or moves:** the fixture file itself
(`PLAN-multi-pr-test.md`) doesn't need content changes — it's a valid,
mode-agnostic 3-issue multi-pr PLAN and remains a correct example of that
shape regardless of who executes it. Its physical location, though, is a
quiet oddity worth surfacing: it lives under `skills/execute/evals/fixtures/
plans/` even though today it's `/work-on`'s scenario that is canonical (the
`/execute` scenario is testing a refusal). After the inversion, `/execute`
becomes the skill that actually runs it, so keeping the fixture under
`skills/execute/evals/fixtures/` becomes *more* correct, not less — I'd
recommend it stays put rather than moves, with `/work-on`'s evals continuing
to reference it by its existing cross-skill path (evals in this repo already
reference fixtures across skill directories, e.g. both suites already point
at this same file today).

### 5. What `/execute` must grow

Read `skills/execute/koto-templates/execute.md` and `skills/work-on/
koto-templates/work-on.md` directly. `/execute`'s single-pr path is a koto
plan-level session: `orchestrator_setup` -> `spawn_and_await` (iterates
issues in dependency order, spawning one `work-on.md` child koto session per
issue, injecting `SHARED_BRANCH`) -> `pr_finalization` -> `plan_completion`
(runs `${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/run-cascade.sh --push
{{PLAN_DOC}}` exactly once, at `execute.md:709`). The coordinated path is a
plain durable-state loop over a merge-order DAG with no koto session at all.

**The `SHARED_BRANCH` / `pr_status: shared` mechanism, and why it doesn't
cover multi-pr:** in `work-on.md`, the `pr_creation` state's transition table
(around line 754) sends `pr_status: shared` straight to `done`, skipping
`ci_monitor` entirely — this is the single-pr child's fast path: it commits
to the orchestrator's shared branch, never opens its own PR, and the
orchestrator's own PR carries CI. `work-on.md:1176-1177` states the rule
directly: "If `SHARED_BRANCH` is set, this child is running on the
orchestrator's shared branch and the orchestrator owns the PR. Submit
`pr_status: shared` — no PR creation step is needed here." A multi-pr child
does the opposite by design: each issue lands its **own** PR
(`pr_status: created`), which routes to `ci_monitor` and its own `done` like
a standalone issue-backed run. So the existing single signal
(`SHARED_BRANCH` present/absent) cannot distinguish "I am a plan child that
should not self-finalize" from "I am a plan child on a shared branch" —
those are two different axes, and today only one of the two combinations
(shared-branch child) exists. The second (own-branch, own-PR, but still a
plan child) has no representation in `work-on.md`'s variable schema at all
(`ISSUE_NUMBER`, `ISSUE_TYPE`, `ARTIFACT_PREFIX`, `ISSUE_SOURCE`, `PLAN_DOC`,
`SHARED_BRANCH` — declared at `work-on.md:14-38` — none of them mean "child,
but on my own branch").

**What a third path needs, concretely:**

- **A new per-child signal**, independent of `SHARED_BRANCH`, that a
  multi-pr child injects to mean "I am a plan child; do not run my own
  finalization/cascade even though I reach `done` through my own PR and my
  own `ci_monitor`." (The prior-phase research already anticipates this as
  the "no last-issue discriminator needed" simplification — with `/execute`
  driving the loop, the orchestrator's own loop-exhaustion is the
  completion signal, not a query the child has to make.) This is new
  variable-schema work in `work-on.md`, additive to what `SHARED_BRANCH`
  already does, not a replacement for it.
- **Reuses**: the `spawn_and_await` iteration shape (dependency-ordered
  dispatch, one `work-on.md` child koto session per issue) and the
  `plan_completion` cascade call (`run-cascade.sh --push`), fired once after
  the last child returns, exactly as single-pr already does it. It does
  **not** reuse `SHARED_BRANCH` injection, and it does not reuse the
  ephemeral-home machinery (PRD-execute-skill.md R5 built single-pr/
  coordinated's ownership specifically around having a session-scoped home
  PR to hold `wip/` artifacts for the run's duration — multi-pr has no such
  home today, by design, since each issue's PR merges independently and the
  PLAN doc is the only durable artifact). A multi-pr path inside `/execute`
  would need to either accept "no ephemeral home" as a legitimate third
  shape (reading/writing the PLAN doc directly, the way `/work-on`'s
  dispatcher does today) or invent one — the design hop's call, but PRD R5's
  stated reason for excluding multi-pr becomes the reason a third path can't
  simply copy single-pr's storage model.
- **Does not reuse** `plan-to-tasks.sh` (single-pr/coordinated's task-graph
  materializer) in the way single-pr does — multi-pr's per-issue dispatch
  already exists today, verbatim, inside `/work-on`'s dispatcher prose
  (select next unblocked issue by reading Dependencies directly from the
  PLAN's Implementation Issues table); the natural design is to lift that
  exact selection logic into `/execute`'s new path rather than route it
  through `plan-to-tasks.sh`'s pre-materialization model, which single-pr
  uses because it needs the whole task graph up front for a single
  koto session's iteration order.

### 6. Backward compatibility

**What happens today, end to end, for `/work-on <multi-pr PLAN>`:**
confirmed at `skills/work-on/SKILL.md:118-141`. The dispatcher reads
`execution_mode` from frontmatter, re-validates it against the closed set
`{single-pr, multi-pr, coordinated}`, and for `multi-pr` runs **in place**:
selects the next unblocked issue (one whose `Dependencies` don't reference
still-open issues), runs it as a single issue-backed unit against the
repo-persisted PLAN doc, and lands its own PR. There is no shared branch, no
cross-issue carry-forward, and — critically — **no looping**: this handles
exactly one issue per invocation. To finish a 3-issue multi-pr PLAN, a person
invokes `/work-on <PLAN>` three separate times. `docs/plans/PLAN-work-on-
friction-fixes.md` is a live, real example of this today: `execution_mode:
multi-pr`, `status: Active`, currently being worked one issue at a time
through exactly this path.

**The rejected-removal precedent, located precisely:** `docs/designs/
current/DESIGN-execute-skill.md:105-106`, inside Decision 2: "**Routing —
hard-remove /work-on PLAN input.** Rejected: breaks existing invocations and
/work-on's own evals." This is the design that created the `/execute`/
`/work-on` split in the first place; it already considered and rejected
stripping PLAN-path input from `/work-on` entirely, on the grounds that doing
so breaks invocations people already make and breaks `/work-on`'s own eval
suite (the same evals.json scenarios quoted in section 4 exist because of
this earlier rejection). The current migration reopens the identical
question from the opposite direction — not "should `/work-on` lose PLAN input
altogether" but "should `/work-on` lose *multi-pr* PLAN input specifically" —
and the same objection applies with the same force: a person invoking
`/work-on <multi-pr-PLAN>` today is doing the fully documented, currently
correct thing, and three eval scenarios encode that as passing behavior.
Whatever the design hop picks — refuse-and-redirect, thin pass-through to
`/execute`, or drop — it has to reckon with this precedent rather than
silently break the same invocations DESIGN-execute-skill.md already declined
to break once.

## Implications

- The routing surface is materially larger than "16 or more": with `README.md`
  and `references/pipeline-model.md` added, the true count of places that
  *assert who executes multi-pr* is closer to 20-25 lines across 14 files
  (12 routing-claim files plus the fixture plus the two eval suites), not
  counting the ~830 enum-value lines that are unaffected. `references/
  pipeline-model.md` is the more consequential of the two misses because it's
  a shared, skill-independent reference — any future skill that reads it for
  chain architecture inherits the stale claim if it isn't fixed here.
- Two threads of "nothing implements this" converge on `/work-on` needing to
  gain, not lose, cascade behavior at exactly the same time its multi-pr
  ownership is removed: `skills/roadmap/SKILL.md:349-350` and `plan-doc-
  structure.md:95` both claim a multi-pr cascade that doesn't exist anywhere
  in `skills/work-on/`, and the fix — moving multi-pr into `/execute`, which
  already has a working cascade call — makes those claims true for the first
  time rather than just less wrong. That's a reason to sequence this
  migration to land the cascade-reuse work concretely, not just correct the
  prose to a vaguer truth.
- The backward-compatibility decision (retain/refuse/drop) has real, live
  stakes beyond the eval suites: `docs/plans/PLAN-work-on-friction-fixes.md`
  is an actual in-flight multi-pr PLAN in this repo today. Whatever ships
  needs to keep working for a PLAN mid-execution under the old contract, or
  explicitly document the one-time migration step for it.

## Surprises

- `docs/decisions/DECISION-cascade-trigger-mechanism-2026-06-06.md:210`
  states the finalization logic lives in "`skills/work-on/SKILL.md` and
  `skills/work-on/koto-templates/`" — that stopped being true when PR #199
  moved the cascade orchestration into `/execute`, and the decision record
  was never amended. This predates and is independent of the multi-pr
  migration, but it's the same class of defect this migration is about to add
  two more instances of if the correction isn't made carefully (a decision
  record whose "Consequences" section names a file path that no longer holds
  the described logic).
- The `PLAN-multi-pr-test.md` fixture already sits in `skills/execute/evals/
  fixtures/`, not `skills/work-on/evals/fixtures/`, even though today it's
  `/work-on` that's canonical for it and `/execute`'s own scenario tests a
  refusal. The migration doesn't need to move this file — it needs to move
  the *scenario that's currently correct* from one skill's evals.json to
  match, which is a smaller and easier change than the file layout suggests.
- `skills/plan/scripts/plan-to-tasks.sh` already has a fully-built multi-pr
  parsing branch (issue-table parsing, issueless-plan handling) that is dead
  code from a routing standpoint — nothing calls it for multi-pr today, and
  the natural design for `/execute`'s new path (reusing `/work-on`'s existing
  per-issue selection logic instead) would keep it dead. Worth flagging so
  the design hop doesn't assume this script needs multi-pr work; it doesn't.

## Open Questions

- Whether `docs/designs/current/DESIGN-capstone-orchestration.md:59-60` and
  `docs/briefs/BRIEF-cascade-outline-ac-completeness.md:12-13` need edits at
  all, or are close enough to mode-agnostic/precedent framing to survive
  untouched — I judged both lower priority but didn't find a bright line
  rule for excluding them.
- Whether the eval fix for `dispatcher-multi-pr-one-issue-at-a-time`
  (scenario A) should change its prompt to `/execute <PLAN>` and become a
  positive assertion of the new third path, or whether it should be retired
  in favor of a new `/execute`-side scenario, leaving this id to be deleted —
  that's a design/plan-hop call, not something the current text settles.
- Exactly how `/execute`'s new path should represent "no ephemeral home" is
  unresolved by anything currently on disk — PRD-execute-skill.md R5 explains
  *why* multi-pr was excluded from the two owned shapes, but nothing describes
  what owning it without a home would look like structurally.

## Summary

The routing surface is bigger than the prior sweep's 16: the extended search over 890 non-`wip/` hits of `multi-pr`/`multi_pr` turns up roughly 20-25 load-bearing routing-claim lines across 14 files (all 16 known ones confirmed accurate at their cited locations, plus `README.md:43-44` and the shared `references/pipeline-model.md:224-227`, both missed before), against a much larger background of ~830 lines that are pure `execution_mode` enum/schema content and don't need to change. Two accepted documents genuinely need superseding rather than editing — `PRD-execute-skill.md`'s requirement D5 and `DESIGN-execute-skill.md`'s Decision 2/R1 — and three eval scenarios (not two: `work-on/evals/evals.json` also has a third, `e2e-cross-mode-no-contamination`, id 25) assert the exact behavior being inverted and will fail the moment the change lands, making them the acceptance criteria. `/execute`'s third path can reuse its existing per-issue dispatch loop and one-shot cascade call, but needs a new per-child "don't self-finalize" signal distinct from `SHARED_BRANCH` (since multi-pr children, unlike single-pr children, do reach their own PR and their own `ci_monitor`), and has to reckon with the same "breaks existing invocations and /work-on's own evals" objection that `DESIGN-execute-skill.md:105-106` already raised once against a cruder version of this exact change.
