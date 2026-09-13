# Decision 5: The multi-pr migration's shape

## Context

This question covers the second of the PRD's two pull requests: the one that
moves `multi-pr` plan execution from `/work-on` to `/execute` (R14), makes
`/work-on` refuse a `multi-pr` plan instead of running it (R15), inventories
and corrects every routing claim this reversal invalidates (R16, R16a, R16b),
retires the three stale eval scenarios (R17), and supersedes the two settled
documents this reversal contradicts (R18). The PRD has already decided the
policy on all four points (`docs/prds/PRD-work-on-standalone-completeness.md:247-309`,
`:476-568`); this report investigates mechanism.

## The third execution path

Today `/execute` owns exactly two plan shapes. `single-pr` lifts `/work-on`'s
former plan-orchestrator template wholesale (`skills/execute/koto-templates/execute.md`)
and drives a plan-scoped koto session: `spawn_and_await` runs a two-tick loop —
tick 1 builds `tasks` from `plan-to-tasks.sh`, injects `SHARED_BRANCH` into every
task's vars, and submits them to `koto next`, which materializes one
`work-on.md` child per task; tick 2 waits for `batch_done` and re-submits the
same tasks alongside a computed `batch_outcome`
(`skills/execute/koto-templates/execute.md:591-631`). Every child commits
directly to the shared branch and skips its own PR creation (`pr_status: shared`,
`skills/work-on/SKILL.md:179`); the plan-level session then assembles one PR
body and runs a single finalization cascade at the end
(`skills/execute/koto-templates/execute.md:639-666`, `:761-789`).

`coordinated` cannot reuse a koto session because koto has no cross-repo
session (`skills/execute/SKILL.md:297-299`). It is instead a **plain
durable-state loop** the SKILL drives directly over the coordination PR: each
pass refreshes live `gh` status, re-authors the PR-Index and merge-order block,
walks the DAG, and for each unblocked PR node "dispatch[es] its issue(s) to
`/work-on`'s `work-on.md` per repo, on that repo's own branch (the same
per-issue delegation contract the single-pr path uses, minus the shared
branch — each repo's work lands as its own PR)"
(`skills/execute/SKILL.md:346-364`). This is the closest existing analog to
`multi-pr`: independent children that each land their own PR, with no shared
branch and (per R9 of `PRD-execute-skill.md`) no cross-issue carry-forward for
that shape's per-node work.

**Where the mode is read and re-validated.** `/execute`'s Input Modes section
reads `execution_mode` from the PLAN and re-validates it against the closed
enum `{single-pr, coordinated, multi-pr}` before it is used in any path or
interpolated into a branch name or emitted shell
(`skills/execute/SKILL.md:45-53`). `/work-on`'s Plan Input dispatcher does the
same re-validation independently, against the identical set
(`skills/work-on/SKILL.md:127-130`) — the PRD's own framing of `/execute` as
"the first untrusted-enum consumer" and `/work-on`'s dispatcher as "the
second" (`skills/execute/SKILL.md:54-55`) already anticipates a third
consumer's worth of care; `multi-pr` becomes a third *path* inside the first
consumer rather than a third consumer.

**What a multi-pr path reuses.** The per-issue dispatch mechanic itself:
`spawn_and_await`'s tick-based `koto next` submission of a `tasks` array,
materializing one `work-on.md` child per task with `failure_policy:
skip_dependents` (`skills/execute/koto-templates/execute.md:612`), is
shape-identical to what `multi-pr` needs — read the PLAN's issue table,
respect dependencies, skip dependents of a failed issue. R14's own text says
as much: "reusing its existing per-issue dispatch loop and its single
end-of-run cascade call" (PRD:247-249). The base-branch drift gate, the
dependency-aware skip-dependents sequencing, and the finalization-cascade
call site are all generic over "how a child lands its work" and need no
change.

**What is new.** Three things, and they compound:

1. **No `SHARED_BRANCH`.** Every task submitted to `koto next` currently
   carries `.vars.SHARED_BRANCH` injected via `jq`
   (`skills/execute/koto-templates/execute.md:604-609`). A `multi-pr` child
   must NOT receive it — per `skills/work-on/SKILL.md:137-141`,
   "there is no shared branch and no cross-issue carry-forward." Downstream,
   `work-on.md`'s `setup_plan_backed` state branches on whether
   `SHARED_BRANCH` is set (create-branch vs. commit-to-existing) and its
   `pr_creation` state branches on the same variable for `pr_status: shared`
   vs. real PR creation (`skills/work-on/koto-templates/work-on.md`,
   `skills/work-on/SKILL.md:177-179`) — that branching already does the right
   thing when the variable is simply omitted, so this is a "don't set it"
   change to the tasks payload, not new template logic in `work-on.md` itself.
   This mirrors exactly how the coordinated path already dispatches to
   `work-on.md` "minus the shared branch" (`skills/execute/SKILL.md:360-361`).
2. **No cross-issue context assembly.** The single-pr tick explicitly runs
   `references/cross-issue-context.md` between children
   (`skills/execute/koto-templates/execute.md:612`); a `multi-pr` tick must
   skip that step, matching R9's "intentionally absent" framing in the
   now-superseded `PRD-execute-skill.md:284-287,307-312` (D4, D5) and the new
   PRD's unchanged stance on `multi-pr` independence.
3. **No ephemeral PR home to anchor state or the cascade.** This is the one
   genuinely open architectural question and not fully a "mechanism, not
   policy" matter — flagged under Open Questions below. Single-pr's home is
   the shared PR; coordinated's home is the coordination PR. `multi-pr` has
   neither: its PLAN is repo-persisted, not branch-scoped, and per the
   document R18 will supersede, this was the *stated reason* `/execute`
   excluded it in the first place ("multi-pr is excluded because it has no
   such home" — `docs/prds/PRD-execute-skill.md:117-119`). R14 requires
   `/execute` to accept it anyway and still run "its single end-of-run
   cascade call" — but today, `multi-pr` under `/work-on` runs **no cascade
   at all**: `skills/work-on/SKILL.md:183` says plainly that "the completion
   cascade — now lives in `/execute`," full stop, with no multi-pr carve-out,
   and nothing in `work-on.md`'s plan-backed states ever calls
   `run-cascade.sh`. So the end-of-run cascade for `multi-pr` is new
   behavior, not preserved behavior, and it needs something to gate on
   ("all issues in this PLAN have a merged PR") without a coordination PR to
   recompute merge state from. The natural answer, given the coordinated
   path's precedent, is to read live `gh` status per issue directly off the
   PLAN's own issue table (the same source `plan-to-tasks.sh` already
   parses) rather than off a PR-Index — but whether `/execute` needs a
   `wip/execute_<topic>_state.md` at all for a plan with no durable home, or
   whether it can stay fully stateless the way `multi-pr` is today (recompute
   "what's left" from the PLAN and live `gh` on every invocation), is a call
   the design hop has to make, not this decision.

Concretely, the shape closest to R14's requirement is: `/execute`'s `Drive`
phase gains a `multi-pr` branch that reuses `spawn_and_await`'s tick
mechanism with `SHARED_BRANCH` omitted and cross-issue-context skipped
(borrowing the "own branch, own PR" shape from the coordinated path's
per-repo dispatch, but within one repo), and its `Finalize` phase adds a new
cascade trigger — gated on every PLAN issue's own PR having merged, read live
— to close the gap that exists today.

## The refusal

The mechanism the PRD already settled on ("refuse with a pointer") already
has a live precedent in this exact codebase, running in the opposite
direction: `/execute`'s own Input Modes section today says, for the mode it
doesn't own, "`multi-pr` — out of scope for `/execute`; multi-pr plans run
one issue at a time through `/work-on` against the repo-persisted PLAN.
Direct the user to `/work-on`." (`skills/execute/SKILL.md:48-50`). That is a
prose-level branch inside a numbered mode list, not a koto gate and not a
template terminal state — because the mode-dispatch decision for a PLAN
argument happens entirely in `SKILL.md` prose, before any koto session is
initialized. Confirmed by reading `work-on.md`'s koto template directly: its
`entry` state accepts exactly `{issue_backed, free_form, plan_backed,
skipped}` (`skills/work-on/koto-templates/work-on.md:44-76`) — there is no
`multi-pr` value and no template state for the top-level "which mode does
this PLAN want" decision at all. `/work-on`'s Plan Input section is where
that decision is made today (`skills/work-on/SKILL.md:121-141`), and it is
pure prose gating `koto init` — no session exists yet when the mode is read.

That symmetry settles where R15's refusal belongs: the same three-bullet
route list in `/work-on`'s Plan Input (Dispatcher) section
(`skills/work-on/SKILL.md:132-141`), with the `multi-pr` bullet's disposition
inverted from "run in place" to "refuse and point at `/execute`" — the mirror
image of `skills/execute/SKILL.md:48-50`. No koto template change is needed
in `work-on.md` at all, because no session for a refused plan should ever be
created.

**What a user sees.** Mirroring the existing message shape gives something
like: *"`multi-pr` — this plan now runs through `/execute`, one pull request
at a time, against the repo-persisted PLAN. Invoke `/execute
<path-to-plan>`."* This satisfies R15's two constraints directly: it names
where a plan is run now (not a vague "unsupported"), and it is not a partial
result — nothing is attempted, no branch or session is created, so there is
nothing left in an ambiguous state.

**Options for the refusal's mechanism, considered with real depth:**

1. **A prose-level mode-detection branch in `SKILL.md` (recommended).** Same
   surface, same call site, as today's "run in place" branch — just a
   different disposition. Cost: near zero, one paragraph. Consistent with
   the architecture: the decision of *which entry point runs this plan* is
   made before any workflow state exists, exactly as it is today for
   `single-pr`/`coordinated` handoff to `/execute` (`skills/work-on/SKILL.md:132-136`).
   Testable directly by the eval suite via prompt/expected-output, with no
   new gate-failure exit code to define.
2. **A koto gate inside `work-on.md`.** Add a `plan_validation`-style gate
   (the template already has a `plan_validation` state for a different
   purpose — validating a `plan_outline` issue source,
   `skills/work-on/koto-templates/work-on.md:268` area) that fails closed
   when `execution_mode: multi-pr` reaches it. Rejected: it requires
   `koto init` to run first, which means creating a workflow record (and,
   per the pattern's five-field state schema, a `wip/` state file) for a
   plan this skill is never going to execute. That is itself a small
   "confusing partial result" — a session exists, with a name, discoverable
   by `koto workflows`, for work that never happened — which is close to
   the exact failure mode R15 rules out ("SHALL NOT be a confusing partial
   result"). It also duplicates the enum re-validation that already has to
   happen in prose before `koto init` is even called (per the security
   re-validation requirement at `skills/work-on/SKILL.md:129-130`), so the
   gate would be redundant with a check that already exists earlier in the
   same invocation.
3. **A dedicated template terminal state (e.g., a `refused_multi_pr`
   terminal reachable from `entry`).** Same objection as (2), amplified: it
   requires adding a fifth `mode` enum value to `entry`'s `accepts` block
   (`skills/work-on/koto-templates/work-on.md:45-49`) purely to reach a
   state whose only job is to print a redirect message — enum surface added
   to a template for a case that a one-line prose check already handles
   before the template is ever loaded. It would also, notably, touch the
   `execution-mode enum` surface in a way indistinguishable from what R20
   forbids in spirit even though `entry`'s `mode` field is a template-local
   enum, not the PLAN-frontmatter `execution_mode` enum R20 actually
   protects — a distinction a future reader could plausibly get wrong,
   which is itself a reason to avoid it.

Option 1 wins outright: it is the same mechanism already used for the
opposite direction of this exact handoff, it adds no new gate, no new
terminal, no new enum value, and no stray `wip/` artifact for work that will
never run.

## The routing-claim inventory — options considered

**What "the surface" actually contains.** A non-eval grep for the mode name
across the live operational corpus turns up roughly a dozen routing-claim
sites outside eval suites, concentrated in a few places:

- `skills/execute/SKILL.md:12` (frontmatter `description`: "A `multi-pr` plan
  is the exception: those run through `/work-on` instead") and `:48-50`
  (Input Modes bullet).
- `skills/work-on/SKILL.md:10` (frontmatter `description`: "It also runs a
  `multi-pr` PLAN, one issue at a time...") and `:137-141` (Plan Input
  bullet).
- `README.md:43-44` — the skill-summary table states both directions:
  "`/execute` ... owns single-pr and coordinated multi-repo plans (a multi-pr
  plan runs under `/work-on` instead)" and "`/work-on` ... Also runs a
  `multi-pr` plan, one issue at a time, each landing its own PR."
- `references/pipeline-model.md:227` — "execution_mode dispatcher: it runs
  multi-pr in place and hands single-pr and coordinated..." describing
  `/work-on`.

This is a small, enumerable set — not the "830 lines of enum and schema
content" R16 explicitly excludes (PRD:254-258). It is exactly the kind of
list a `grep -rn` for the mode name, filtered by hand against R16a's
"routing claim" definition (a statement directing a reader/agent to one
entry point vs. the other — not a bare enum/schema/fixture mention), would
produce. That filtering-by-hand step is precisely why R16b requires the
inventory to record the exact command that produced the *candidate* set: the
disposition column is where the human/agent judgment about which candidates
are routing claims gets recorded, and the recorded command lets a reviewer
re-run the grep and confirm nothing outside the inventory both matches and
qualifies.

I also found a **third document with a stale routing claim that the PRD's
own scoping already excludes on purpose**: `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md:276,653`
says "`/execute` declines `multi-pr` outright." This is a `Current` DESIGN,
but it is not one of the two documents R18 names, so by R16a's own
definition ("It excludes durable artifacts that have finished their own
lifecycle... a DESIGN at `Current` or `Superseded`... plus exactly the two
settled documents R18 names") it falls outside the surface entirely — not
`edited`, not `superseded`, not `delegated`, simply out of scope, the same
as any other `Current` design would be. This is worth flagging to whoever
authors the inventory (it is easy to instinctively want to "fix" it) but it
is not mine to reopen: the PRD's exclusion rule already resolves it, on
purpose, by leaving it as a `Current` design's residual staleness — exactly
the trade-off the PRD's Known Limitations section implicitly accepts for any
document this feature doesn't name.

**Where R18's two documents' own claims live, for calibration.** Both are
already located precisely: `docs/prds/PRD-execute-skill.md:110-113` (R4:
"/execute owns plan-level execution for exactly two plan shapes... It does
not own multi-pr... execution") plus its D2/D5 decisions
(`:282-287,307-312`), and `docs/designs/current/DESIGN-execute-skill.md:108-110,138`
(Decision 2's chosen routing option: "`/work-on <PLAN>` keeps working as a
thin dispatcher... it runs multi-pr in place per issue"). These get
`superseded` rows, satisfied by the decision record's existence rather than
by editing the file.

**The form-and-location question.** Three real options:

1. **A section inside the feature's own DESIGN document (recommended).**
   This repository already has a working precedent for exactly this
   artifact shape: `docs/designs/current/DESIGN-multi-pr-plan-decoupling.md:346-357`
   carries a `| Site | Occurrences | Kind | Action |` table enumerating every
   place a re-keyed convention appears, with an explicit "leave" / "re-key"
   disposition per row and prose explaining why a `Current` design is
   `re-key` and not `leave`. That table lives permanently in the merged
   design, not in a `wip/` scratch file, and it is what the reviewer checks
   the actual diff against. R16a's inventory is the same shape at finer
   grain (file **and line**, before/after text, plus a `delegated` category
   the precedent doesn't need because it has no eval-suite carve-out).
   Placing it as a section (or appendix) of the DESIGN this PRD produces
   costs nothing new: no new artifact type, no new `shirabe validate` mode,
   no new file-naming convention to invent, and it is written by the skill
   authoring the DESIGN, consistent with "artifacts are authored by skills"
   (`CLAUDE.md:198-201`). Because R16a explicitly frames this as a one-off
   migration artifact rather than a recurring type, there is no future
   consumer that would benefit from a dedicated FormatSpec or a `shirabe
   validate --routing-inventory` check — the acceptance criteria that check
   it (every `edited` row's after-text present and before-text absent, every
   `superseded` row naming one of the two documents, etc.) are satisfiable
   by a reviewer or a one-off script diffing the table against the working
   tree, not by a standing correctness engine.
2. **A standalone file, e.g. `docs/migrations/MIGRATION-multi-pr-routing.md`
   or similar, outside the DESIGN.** Keeps the DESIGN focused on
   architecture rather than a line-by-line ledger, and would be discoverable
   independent of the DESIGN's own lifecycle. Rejected as the primary choice:
   it invents a new, ungoverned document location and naming convention for
   a type the PRD itself says is not recurring — the opposite of this
   repository's usual instinct (a new corner of `docs/` with no format
   reference, no validator, and exactly one instance is more architecture
   than a one-off table warrants). It is a reasonable fallback if the
   DESIGN document's own reviewers object to a long per-line table bloating
   the design's readability, but that has not been true of the precedent
   (`DESIGN-multi-pr-plan-decoupling.md`'s table sits comfortably as one
   subsection).
3. **The PR body.** Rejected on a hard constraint, not a style preference:
   this repository's PR-body convention splits every PR into "Part 1 —
   factual change paragraph (becomes the squash commit body)" and "Part 2 —
   reviewer context," and "everything from `---` down is deleted at merge"
   (`skills/execute/koto-templates/execute.md:642`, restated for `/work-on`'s
   own PR-body conformance rule). R16a requires the inventory to be
   "committed with the change" and the acceptance criteria describe
   re-running its command and checking rows against the merged tree — both
   presume the inventory survives the squash-merge. A PR-body Part 2
   location does not survive it. This option fails on its own terms, not on
   taste.

Recommendation: put the inventory in the DESIGN document this PRD produces,
as a section modeled directly on `DESIGN-multi-pr-plan-decoupling.md`'s site
table, extended with the `line`, `before`, `after`, and `disposition`
(`edited`/`superseded`/`delegated`) columns R16a names, plus a fenced block
recording the exact grep command per R16b.

## The supersession record

`docs/decisions/` holds seven records today, all named
`DECISION-<topic-slug>-<YYYY-MM-DD>.md`, each with frontmatter `status:
Accepted`, a one-paragraph `decision:` and `rationale:`, and a body of
`# DECISION: <title>` / `## Status` / `## Context` / `## Decision` /
`## Options Considered` / `## Consequences`. Reading
`DECISION-multi-pr-posture-detection-2026-06-06.md` in full shows this
shape, plus a precedent for exactly the situation R18 describes: that record
carries a dated `## Amendment — 2026-08-15` section appended at the end,
opening with "The decision above stands... What changed is a fact this
record's Context relied on, not the mechanism it chose," closing "This is an
amendment rather than a supersession because the decision was never about
the gate." That is an existing decision record amending *itself* in place —
useful for format, but not the shape needed here, since R18's correction
originates in a *new* decision and has to reach *two other, older* documents
(a PRD and a DESIGN) without touching their text.

The precedent for that exact cross-document shape already exists, and twice:

- `docs/prds/PRD-fold-record-removal.md:326-328` states the rule directly as
  an acceptance criterion: "Each of the seven documents named in R10 contains
  a section heading matching `## Amendment — <date>` where `<date>` is on or
  after the date this change lands, and the text under that heading contains
  the string `folds.md`. Each document's `status:` is unchanged from the
  merge base." This is a repository-level, validated convention for
  "correct a settled document without touching its body and without moving
  its lifecycle state": append a dated `## Amendment` heading, state what no
  longer holds and why, leave the status field untouched.
- `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md:825-829`
  shows the prose shape in practice: "**Amendment — 2026-08-15** / Superseded
  in part by `DESIGN-scope-artifact-persistence.md`, which makes... The
  original text above is left unedited; this section records what no longer
  holds and why." — followed by, per numbered decision, which conclusion is
  falsified and which stands.

R18's "pointer" is this same mechanism, applied to the two documents named:
append `## Amendment — <date>` to the end of `docs/prds/PRD-execute-skill.md`
and to the end of `docs/designs/current/DESIGN-execute-skill.md`, each
naming the new decision record by path, stating which requirement/decision
no longer holds (R4/D2/D5 in the PRD; Decision 2's chosen routing option in
the DESIGN) and pointing to it for what replaces it, with each document's
`status:` (`Done`, `Current` respectively) left exactly as it is. This
satisfies every constraint the acceptance criteria list: the contradicted
text is preserved verbatim above the amendment, the only edit permitted is
the addition of the pointer, and neither document's lifecycle status moves
(matching the PRD's own reasoning for why neither type's standard
supersession route fits — PRD:545-568).

**The new decision record itself.** One file,
`docs/decisions/DECISION-multi-pr-routes-through-execute-<date>.md` (or
similarly named for the topic), `status: Accepted`, naming both superseded
items explicitly in its `## Context` (the PRD's R4/D2/D5 and the DESIGN's
Decision 2 routing choice), and stating in its `## Decision` what supersedes
each and why — mirroring the two-sentence pattern already used at
`docs/prds/PRD-lifecycle-draft-ready-discipline.md:334-336`'s reference list
style, but as the target of the pointers rather than their source.

## The eval scenarios

Three scenarios, exactly as R17 names them, all keyed off the shared fixture
`skills/execute/evals/fixtures/plans/PLAN-multi-pr-test.md`:

1. **`dispatcher-multi-pr-one-issue-at-a-time`** (`skills/execute/evals/evals.json`,
   id 2) — "the dispatcher scenario in the plan entry point's suite." Today
   its `prompt` invokes `/work-on <fixture>` and its `expected_output`
   asserts `/work-on` "routes in place... does NOT hand off to `/execute`."
   Under the new routing this scenario has to invert at the root: the prompt
   changes to `/execute <fixture>`, and the expected output changes to
   assert that `/execute` reads `execution_mode: multi-pr`, re-validates the
   enum, and runs it "one pull request at a time, reusing its existing
   per-issue dispatch loop and its single end-of-run cascade call" (R14's own
   language is a good template for the new `expected_output`), explicitly
   asserting no shared branch is created and no cross-issue carry-forward
   happens.
2. **`plan-mode-detection-from-path`** (`skills/work-on/evals/evals.json`, id
   20) — one of "two in the single-issue skill's suite." Prompt stays
   `/work-on <fixture>` (this is still testing `/work-on`'s own dispatcher),
   but the `expected_output` inverts from "it runs in place" to the refusal:
   `/work-on` reads and re-validates `execution_mode`, and for `multi-pr`
   specifically refuses and names `/execute` as where the plan runs now —
   while explicitly still asserting the unchanged half of the behavior
   (`single-pr`/`coordinated` still hand off to `/execute`, no
   plan-orchestrator template is initialized, no `gh issue view` call).
3. **`e2e-cross-mode-no-contamination`** (`skills/work-on/evals/evals.json`,
   id 25) — "including a cross-mode contamination scenario an earlier sweep
   missed." This is the one that chains three invocations
   (`#42`, a free-form task, then the multi-pr fixture) in one session and
   checks no state leaks between them. Its third leg's `expected_output`
   needs the same inversion as (2) — from "routes multi-pr in place" to "the
   dispatcher reads `execution_mode`, refuses `multi-pr`, and points to
   `/execute`, without initializing a workflow for it" — while its actual
   contamination assertion (no `ISSUE_NUMBER`/`ARTIFACT_PREFIX`/template
   state carried between invocations 1, 2, and 3) stays intact, since a
   refusal that never calls `koto init` at all is, if anything, a stronger
   non-contamination guarantee than "ran with distinct vars."

**The fixture.** `PLAN-multi-pr-test.md` should **stay in place, content
adjusted, not moved.** It is already referenced cross-skill (by both
`skills/execute/evals/evals.json` and `skills/work-on/evals/evals.json`) via
its path under `skills/execute/evals/fixtures/plans/`, which is the existing
and unremarkable pattern for a fixture two suites share — moving it only
adds diff noise to both eval files for no behavioral gain. Its content does
need one edit: the `## Scope Summary` line currently reads "run one at a
time through `/work-on`, no shared branch" — under the new routing this is
now describing the wrong entry point (multi-pr runs through `/execute` after
this migration). Per R16a's own boundary rule, this text lives inside an
eval fixture, so it is `delegated` to R17, not resolved under R16a — but it
still has to change, because it would otherwise directly contradict the
`expected_output` of the very evals that reference it in the same PR. The
inventory should list it with `disposition: delegated`, and R17's scenario
work is where the actual text edit happens.

## Recommendation

Land all four mechanisms as described above, as one PR (R22's second):

- **Third execution path**: extend `/execute`'s `Drive` phase with a
  `multi-pr` branch that reuses `spawn_and_await`'s tick/`koto next` dispatch
  shape with `SHARED_BRANCH` omitted and cross-issue-context skipped
  (mirroring the coordinated path's "own branch, own PR" per-child dispatch,
  scoped to one repo), and add a new end-of-run cascade trigger gated on
  live per-issue PR status read off the PLAN's own issue table — this is new
  behavior, since no cascade exists for `multi-pr` today.
- **Refusal**: a one-paragraph inversion of the existing `multi-pr` bullet in
  `/work-on`'s Plan Input (Dispatcher) route list
  (`skills/work-on/SKILL.md:137-141`), mirroring the message shape already
  used in the opposite direction at `skills/execute/SKILL.md:48-50`. No koto
  template change, no new gate, no new terminal state — the decision happens
  before any session exists, exactly as it does today.
- **Routing-claim inventory**: a section in the feature's DESIGN document,
  modeled on `DESIGN-multi-pr-plan-decoupling.md`'s existing site table,
  with `file | line | before | after | disposition` columns and the R16b
  grep command recorded alongside it. No new artifact type, no new
  `shirabe validate` mode — the one-off nature of this artifact is the
  argument against inventing either.
- **Supersession record**: one new `docs/decisions/DECISION-*.md` record
  (`status: Accepted`) naming both superseded items, plus a dated
  `## Amendment — <date>` section appended to the end of
  `docs/prds/PRD-execute-skill.md` and `docs/designs/current/DESIGN-execute-skill.md`,
  each pointing at the new record and leaving the original text and
  `status:` field untouched — the same mechanism already validated
  elsewhere in this repository (`PRD-fold-record-removal.md`'s AC15;
  `DESIGN-scope-consolidation-over-skipping.md`'s two `## Amendment`
  sections).
- **Eval scenarios**: invert the `multi-pr` leg of all three named scenarios
  (execute's dispatcher scenario flips to assert `/execute` now runs it;
  work-on's two scenarios flip to assert the refusal), and update the shared
  fixture's scope-summary prose to name `/execute` instead of `/work-on`,
  filed under `delegated` in the inventory rather than `edited`.

## Open questions

- **What anchors resumable state for a `multi-pr` run under `/execute`, given
  it has no home PR?** Single-pr and coordinated both use a durable home (the
  shared PR, the coordination PR) plus a `wip-yaml-md` projection. `multi-pr`
  has neither, by the old PRD's own explicit design (`PRD-execute-skill.md:117-119`).
  The cleanest answer this report found is to stay fully stateless — recompute
  "which issues remain" from the PLAN's own issue table and live `gh` on
  every invocation, the same as `multi-pr` behaves today under `/work-on` —
  but whether `/execute` should nonetheless write a `wip/execute_<topic>_state.md`
  for consistency with its other two paths (and if so, what it's keyed to
  without a branch or PR to resume from) is a design-hop call this report
  does not settle.
- **Does the new end-of-run cascade for `multi-pr` need a mode-scoped
  `requires.tsv` record?** Likely not — `shirabe validate --lifecycle-chain`,
  `finalize-chain`, and `transition` are already declared `always` in
  `skills/execute/requires.tsv:29-31` for the single-pr cascade, and nothing
  about calling them for a `multi-pr` PLAN needs a different flag. Worth a
  one-line confirmation at implementation time rather than a fresh
  investigation.
- **`DESIGN-multi-pr-plan-decoupling.md`'s stale claim** ("`/execute` declines
  `multi-pr` outright," lines 276 and 653) is correctly excluded from R16a's
  surface by the PRD's own definition, since it is a `Current` design R18
  does not name. Flagging this explicitly for whoever authors the inventory,
  so it's a documented, deliberate omission rather than something a reviewer
  discovers and questions mid-review.
