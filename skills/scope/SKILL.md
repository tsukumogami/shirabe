---
name: scope
description: >-
  Work out what a feature is and how it gets built, ending in an
  implementable PLAN: the problem it solves, the requirements, the technical
  approach, and dependency-ordered issues. Reach for this INSTEAD of writing
  a specification yourself — if you are about to draft a PRD, a design doc, a
  spec, or a list of issues for a feature, run this instead of authoring it
  by hand. Use it whenever you are asked to build, add, redesign, or work out
  a feature whose requirements are not already written down, even when nobody
  says "spec", "scope", or "design": deciding a feature by starting to code
  it is the failure this exists to prevent. It also covers requests for a
  single document, because the chain decides per hop which documents survive
  — "just write me a design for X" is usually this. Do NOT use to implement a
  PLAN that already exists (`/execute`), to fix one known issue
  (`/work-on`), or to justify a project or sequence a multi-feature
  initiative (`/charter`).
argument-hint: '<topic-slug or freeform topic> [--upstream <path>] [--intent=continue|stop] [--coordinated|--no-coordinated] [--auto|--interactive] [--max-rounds=N] [--koto-leg=<request-id>:<leg>]'
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
---

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh scope 2>&1 || true`

# Scope

`/scope` is the second parent skill in the shirabe parent-skill
pattern, sitting on the tactical chain (BRIEF → PRD → DESIGN → PLAN)
the way `/charter` sits on the strategic chain (VISION → STRATEGY →
ROADMAP). It walks an author through the four tactical-chain
children as a single conversation, holds state across child
boundaries, enforces the pattern-level invariants (state schema,
resume ladder, three exit paths, child inspection, worktree
discipline), and lands at one of three terminal exits: a `full-run`,
whose terminal hop deposits a PLAN at `docs/plans/PLAN-<topic>.md`,
a `re-evaluation` exit that writes a Decision Record at a settled-
upstream boundary (PRD or DESIGN), or an `abandonment-forced` exit
that force-materializes the most-recently-running child's
intermediate as a Draft artifact.

The pattern-level contract surface is documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` and its
four companion references. `/scope` is the second concrete consumer
after `/charter`; the seven SKILL.md structural elements below align
section-by-section with the pattern's required structural elements,
and the prose contracts after them bind the `/scope`-specific
asymmetries the tactical chain introduces (two settled-upstream
boundaries, Mandatory-with-auto-skip re-entry protection on every
child, a consolidation judgment that is the only thing permitted to
remove a document from a run and that cannot run before the
documents exist, a refuse-and-redirect Slot 5 shape for PLAN's
downstream-owned lifecycle states, and a terminal child with two
output modes).

## Why This Skill, and Why You Must Not Route Around It

When `/scope` is invoked, run the workflow. Do not read ahead, decide what the
answer probably is, and write the terminal document. That is not a caution
about a hypothetical: it is what happened, and it is why this skill is built
the way it is.

Two properties are what the workflow buys, and neither survives working
outside it. **The deterministic work is offloaded to scripts the engine runs
itself.** Whether a hop is complete is decided by `hop-complete.sh` reading the
artifact tree, not by your judgment and not by your report of what you did. You
do not invoke that script; the gate on each state runs it and routes on its
exit status. The same holds for the chain-wide check at the exit. So the parts
of this job that can be settled mechanically are settled mechanically, and your
judgment is spent on the parts that actually need it.

**And the process is what makes the solutioning thorough and unbiased.** Each
hop asks its question at the point where the answer is available, in an order
where the earlier answers are already on the page. The one judgment that
removes a document is made against two documents that exist, rather than by a
party deciding in advance that a document would not have been worth writing --
which is the same party that benefits from not writing it. An agent that skips
ahead reproduces neither property: nothing checks its claims, and the decision
to skip is made by whoever gains from the skip.

The workflow does not stop you from skipping. It makes a skip leave a mark in a
record you did not author.

## Why Each Hop Is Taken

Each hop is taken because it settles something no earlier document
settles and nothing available before it runs can settle on its
behalf. Framing is settled by writing the framing; requirements by
writing the requirements; an approach by choosing between
alternatives on the page; an order by committing to one. A hop that
does not run leaves its question open. It does not answer the
question more cheaply.

This is why the chain has four hops and why `/scope` walks all
four. The decision a run makes per hop is what the hop produces,
not whether the question gets asked.

Invoking `/design` or `/plan` directly costs the hops it skips:
their questions go unasked rather than answered, and no later hop
recovers them. What it buys is a shorter conversation, not a
smaller artifact set — inside `/scope`, the set is settled per hop
after the artifacts land.

**A hop's contribution** is what its document holds that no other
document in the chain holds — what a reader would have to
reconstruct from scratch if it were gone. It is a property of the
document in hand rather than of its type: read off the body in
front of you, never inferred from what documents of that type
usually carry. Each type's own format reference states the
contribution that type declares, and this file does not restate
them. Four sentences summarizing what each document contains,
read by someone holding none of them, is a summary standing in for
the documents rather than a way into them — which is the substitution
this skill exists to prevent.

Anything held back is re-entry protection — a settled artifact is
already on disk and re-running would clobber it — and it is
recorded under its own name so that a hop not re-run is never
confused with a hop not needed.

## Team Shape

**`/scope` spawns nothing.** It is a single-agent skill: you run every
phase yourself, and each child — `/brief`, `/prd`, `/design`, `/plan` —
is invoked **inline through the Skill tool, in your own context**. No
subagent, no roster to materialize, nothing to poll or wait on. Each
hop's directive says so again at the point of invocation.

The declarator is prose per the pattern's v1 form; see the Team-Shape
Declarator and Dispatch Contract sections of
[`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md).
R19's Team-Lead Operating Discipline binds at the child-dispatch layer
and is vacuous here for the same reason: there are no peers whose
terminal exits a team lead drives.

## Input Modes

From `$ARGUMENTS`. Flags are set aside first (see Execution-Mode
Flags, Intent Flag, and Upstream Flag below); the input modes
classify what remains. koto, not this file, checks every argument:
the tokens reach `koto init` through `scripts/scope-open.sh`, and a
value the template's variables do not admit is refused there, with
exit 2 and no session or state file.

1. **Empty** — surface a cold-start prompt asking the author what
   feature scope they want to settle. The cold-start prompt says
   what reaches this entry point, in the terms CLAUDE.md uses — a
   feature to be built, added, or redesigned whose requirements are
   not already written down — and asks the author
   to re-invoke `/scope <topic-slug>` with a slug that matches the
   topic-slug regex. Phase 0 then stops, before `koto init`; there
   is no auto-retry loop.
2. **Non-empty `$ARGUMENTS`** — a freeform topic string that must
   already conform to the topic-slug regex (see Topic-Slug
   Constraint below for the regex source-of-truth and validation
   discipline). On match, the value becomes the topic slug verbatim;
   on mismatch, koto refuses it at `koto init` and `scope-open.sh`
   prints the slug-refusal text; the run stops.

Paths to durable artifacts (e.g., `/scope docs/prds/PRD-foo.md`)
fail the regex on slashes / dots / uppercase and are rejected at
Phase 0; they are not treated as upstream pointers. An upstream the
chain should consume is named with `--upstream <path>` (below); an
upstream the chain can find for itself is detected during Phase 1
discovery by inspecting topic-related child docs in the repo.
Neither route parses a path out of the positional slot.

## Execution-Mode Flags

`/scope` parses three execution-mode flags from `$ARGUMENTS`:

- `--auto` — non-interactive mode. Decisions follow the recommended
  default based on context; the run does not block on user input.
- `--interactive` (default) — the run blocks on user-input prompts
  at decision points.
- `--max-rounds=N` (default 5) — caps the number of re-evaluation
  re-entries allowed against the same topic. The `/scope` default
  is `--max-rounds=5`, overriding `/charter`'s default of 3 per
  R16.5 / AC16b. Setting `N` causes the (N+1)th re-evaluation to
  be rejected with a clear error naming the cap. Values outside
  1 to 50 are refused by koto at `koto init` and stop the run.

`--auto` and `--interactive` together, or either twice, are refused
at `koto init` too. The execution mode applies to all phases, and it
is a per-invocation setting: a run another invocation picks up takes
that invocation's mode. `--auto` mode does NOT suppress R9's
hard-finalization check; an `--auto` run that cannot record a valid
exit still fails finalization rather than silently absorbing the
violation.

## Intent Flag

`--intent=continue|stop` declares what the caller wants done once
the chain ends: with either value, `/scope` pushes its branch and
opens one pull request at exit, once the PLAN's mode is known -- a
draft for a `single-pr` or `coordinated` PLAN and for the
re-evaluation and abandonment exits, a ready PR for a `multi-pr`
PLAN. Omitting it means today's behavior, exactly: the same
artifacts, the same execution-mode selection, no push, no PR, and no
`gh` call from `/scope`. Only
the two values are accepted. The token reaches koto unmodified as the
`INTENT_FLAG` variable, whose pattern refuses anything else —
`--intent=none`, `--intent=unset`, a bare `--intent` — at `koto init`
with an error naming `--intent`, and a repeated `--intent` is refused
the same way. A lone, empty `--intent=` is treated as a missing flag.

The run's effective intent is resolved by the template's `intake`
state and recorded in the state file as `intent: continue|stop|none`:
the flag when given, else the intent the state file already records,
else `none`. Against an unfinished run, a different explicit intent is
refused — by koto as `var_mismatch` while the session lives, by
`intake` as `intent-mismatch` once it is gone — and a bare
re-invocation resumes under the recorded intent.

With intent set, the `/plan` hop receives `--intent=<value>`, the
caller's coordination flag if one was passed, and `/scope`'s own mode
flag; a no-intent hop receives exactly today's arguments. The rule
and the gate that checks the hop's result are in the `/plan` row of
`skills/scope/references/phases/phase-2-chain-orchestration.md`.
`/scope` never invokes `/execute`, with any intent: what happens after
the PLAN is the caller's decision.

When the effective intent is `continue` or `stop`, verify the
intent-scoped prerequisites at `setup`, before any hop, because a
missing `gh` found at exit would strand a finished chain unpublished:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh scope --mode intent 2>&1 || true
```

Two re-invocations with intent take shortcuts rather than re-scoping.
A topic whose PLAN already exists goes to `republish`, which re-runs
the publish step for the PLAN's mode, reuses or opens the owned PR,
and rewrites the PR body's `intent=` field to this run's intent, so a
finished `--intent=stop` run re-invoked with `--intent=continue` is
not a mismatch. A topic whose PLAN was executed and removed goes to
`executed_report`, which names the owned PR and whether it is merged
or open. Without intent, an Active PLAN is refused with a redirect to
`/execute docs/plans/PLAN-<topic>.md` (`single-pr`, `coordinated`) or
`/work-on` (`multi-pr`).

**Owned-PR lookup.** Every PR lookup `/scope` makes goes through
`${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/owned-pr.sh`, the one
shared ownership filter, called unchanged; `/scope` has no lookup of
its own. Its results map to `/scope`'s steps in one place:

| `owned-pr.sh` | Publish (`publish-scoping-pr.sh`) | `executed_report` |
|---------------|-----------------------------------|-------------------|
| one URL (exit 0) | reuse it | report it |
| none (empty, exit 0), a foreign-only branch included | create the PR | `scope:pr-create` |
| several (exit 3) | `scope:pr-create` | `scope:pr-create` |
| read failure (exit 2) | `scope:pr-create` | `scope:pr-create` |

## Request Leg Flag

`--koto-leg=<request-id>:<leg>` attaches this run's session to a koto
request leg, so its terminal result reaches the coordinator that
opened the leg. `scope-open.sh` checks the value against koto's
request-id grammar and the closed leg-name set (`scope`) before
`koto init`. It changes nothing but where the terminal result goes:
the run, its prompts and its printed output are those of a direct
run. A refusal at `koto init` is recorded on the leg by koto, so a
coordinator reads the refusal instead of waiting on the leg.

## Upstream Flag

`--upstream <path>` names an existing ROADMAP this chain consumes rather than
produces. It is set aside before the positional slug and is never tested against
the topic-slug regex, so a path in the positional slot is still rejected.

The value is validated inbound -- its shape by koto at `koto init` (a
repository-relative `docs/roadmaps/.../ROADMAP-*.md` path or its `owner/repo:`
form, no `..` segment), then in the `intake` state confined to
`<repo-root>/docs/roadmaps/` with symlinks followed, basename starting with
`ROADMAP-`, tracked by git, and not under `wip/`, and finally in Phase 0 not a
private artifact named from a public repo -- then recorded in
`consumed_upstream:` and handed to `/brief` and to `/plan`.
Neither records the roadmap the same way, and which one records it is a
lifetime rule rather than a convenience: a ROADMAP is deleted when its features
land, so no durable document may name one, and the PLAN goes first.

The full procedure, the rejection wording, and the pre-authoring notice an
author is owed when no upstream is supplied are in
`skills/scope/references/phases/phase-0-setup.md` and
`skills/scope/references/phases/phase-1-discovery.md`.

## Coordination Intent

Additive, and absent unless coordination intent resolves. When it is absent
`/scope` behaves exactly as documented everywhere else in this file --
single-repo, no coordination PR, no new prompts. Read this section only when
coordination intent is present.

Coordination intent is whether this effort is coordinated across PRs; it is
not the `--intent` flag, which declares what the caller wants done once the
chain ends (see Intent Flag).

Coordination intent resolves on `flag > CLAUDE.md-header > default`:
`--coordinated` / `--no-coordinated` (the session's `COORDINATION` variable),
then the `## PR Grouping Policy:` and `## Reviewability Ceiling:` headers, then
single-repo.

The moment it resolves to coordinated, verify the mode-scoped prerequisites
before authoring anything, because a missing `gh` here means an authored body
with nowhere to go:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh scope --mode coordinated 2>&1 || true
```

**With `--intent` set, `/scope` never creates a coordination PR up front.** On
an intent run the PLAN's mode is not known until the `/plan` hop resolves it,
so the publish step opens the coordination PR at exit, once the mode is known;
no `gh pr create` runs before the first child, and an abandoned intent run has
no coordination PR to close. **Without `--intent` the up-front behavior is
unchanged:** the coordination PR is created up front, before any child runs,
and its body is authored by this skill rather than rendered by a subcommand. The lifecycle, the
coarsest-legal-grouping rule, the merge-order model, the done-signal, and the
F1/F2/F4 rules are canonical in
[`${CLAUDE_PLUGIN_ROOT}/references/coordination-strategy.md`](${CLAUDE_PLUGIN_ROOT}/references/coordination-strategy.md).
This skill binds to that contract and does not restate it.

## Topic-Slug Constraint

The topic slug appears in the state-file path
(`wip/scope_<topic>_state.md`), the Decision Record paths
(`docs/decisions/DECISION-{prd|design}-<topic>-{re-evaluation|rejection}-<YYYY-MM-DD>.md`),
and downstream child wip/ paths under `wip/{brief,prd,design,plan}_<topic>_*`.
The slug MUST match the regex `^[a-z0-9-]+$` — the pattern-level
constraint canonical in
[`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`](${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md)
(Topic-Slug Regex section), including the validation discipline
(AS PROVIDED, no normalization) and the resume-time re-validation
rule. Phase 0's rejection-example table and the slug-handling
procedure live at `skills/scope/references/phases/phase-0-setup.md`.

Slugs recovered from on-disk artifact paths during Slot 5 or Slot 6
ladder matches are re-validated against the same regex before
interpolation into any emitted shell command; the resume-time slug
rule lives in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` (Slug
Re-Validation on Resume section).

## Workflow Phases

```
Phase 0: SETUP  -> Phase 1: DISCOVER  -> Phase 2: CHAIN  -> Phase 3: FINALIZE  -> Phase 4: CLEANUP
(koto entry +     (visibility detect +    (orchestrate     (record exit +        (wip cleanup;
 intake +         child-doc discovery +    child skills     write exit_artifacts;  remove non-
 state-file +     chain proposal)          one-by-one)      R9 hard-finalization)  durable scratch)
 parent_orch
 self-heal)
```

| Phase | Purpose | Reference |
|-------|---------|-----------|
| 0. Setup | Tokenizing and the residue rule; entry through `scope-open.sh`, where koto checks the arguments and opens or attaches the session; `intake` (effective intent, upstream battery, recorded-intent check); visibility detection; state-file creation with `intent:`; stale `parent_orchestration:` self-heal | `skills/scope/references/phases/phase-0-setup.md` |
| 1. Discover + Chain Proposal | Topic-related child-doc discovery; R6 shape-predicate evaluation for `/design`'s roster size; chain-proposal output | `skills/scope/references/phases/phase-1-discovery.md` |
| 2. Child Invocation Loop | Per-child: worktree-staleness check (Rebase / Impact-analysis / Escalation per `worktree-discipline.md`); write `parent_orchestration:` sentinel; invoke child with its upstream artifact's path; structural file-existence check per R20; clear sentinel; capture child snapshot; validator pass-through; consolidation judgment | `skills/scope/references/phases/phase-2-chain-orchestration.md` |
| 3. Exit Finalization | Set `exit:` field; write `exit_artifacts:`; run R9 hard-finalization check | `skills/scope/references/phases/phase-3-exit-finalization.md` |
| 4. wip Cleanup | Remove the topic's wip/ scratch artifacts; preserve durable Decision Records and force-materialized partials in `docs/` | `skills/scope/references/phases/phase-4-cleanup.md` |

Before each child invocation the loop runs a worktree-staleness check —
the Rebase / Impact-analysis / Escalation flow in
`${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md`. None and
Informational classifications proceed silently; an Intent-changing one
halts and puts the judgment to the author. The hop's own directive says
so when it applies.

## Running the Workflow

**Start here.** Read
`skills/scope/references/phases/phase-0-setup.md` and follow its Tokenizing
and Workflow Session sections: write the invocation's raw tokens to an args
file outside the work tree and run
`bash ${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/scope-open.sh --plugin-root ${CLAUDE_PLUGIN_ROOT} <args-file>`.
koto checks every argument there, and in the same call opens a new session,
attaches to this worktree's live one, or -- when an earlier run of the topic
already reached a terminal -- replaces that finished session with a fresh one
(`--replace-terminal`), which starts again at `intake` and `resume_route`. A
live session is never replaced. A refusal prints its text followed by
`outcome=error` and `step=scope:refused`; print them and stop. There is no
session to tick until that has run, so this is the one procedure you need
before the workflow can tell you anything. The session is named
`scope-<topic>`, derived from the slug alone.

After that, every step comes from the workflow rather than from this file: call
`koto next`, do what the directive says, submit the evidence it asks for,
repeat.

**Every `koto next` carries `--no-cleanup`, on every tick, unconditionally**,
whether or not `--koto-leg` was given. The session is always a root, so the flag
keeps the run's per-hop record after its terminal tick, and under `--koto-leg`
koto still promotes the terminal result to the leg. Deciding per tick is wrong
in both directions; see
`${CLAUDE_PLUGIN_ROOT}/references/koto-session-retention.md`. The retained
session is read where it lives and is never resumed: the next `/scope <topic>`
gets a fresh session from the entry itself, so there is no read-then-clean-up
step, and a finished session is never ticked.

**The run ends at a terminal whose result koto recorded, and the printed exit
block comes from that result.** Every outcome, refusals and errors included,
is a terminal with a `result:` map. When a `koto next` answers
`"action": "done"`, print what this prints, verbatim, and compose no exit line
of your own:

```bash
bash ${CLAUDE_PLUGIN_ROOT}/skills/scope/scripts/print-scope-exit.sh --topic <topic> --session scope-<topic>
```

It prints `/scope finished: exit=<exit>; artifact=<path>`, then `intent=`,
and, as the run calls for them, `outcome=`, `step=`, `next=`, `pr=`,
`pr_state=`, `wip_paths=`, and a multi-pr run's startable items; the Success
Summary in `skills/scope/references/phases/phase-4-cleanup.md` lists which line
appears when.

Two things about what you receive. Each state's `directive` arrives on every
tick and is short. Longer procedure arrives once, as `details`, when you first
reach a state -- a self-loop or a blocked retry is not a new arrival, so do not
expect it again. If you lose it, `koto status scope-<topic>` returns the
current state's directive, details and evidence schema without ticking the
workflow.

Directives name the reference file for the phase they belong to. Read it when
the directive tells you to, or when you hit a corner case it does not cover.
They are not required reading up front, and reading all of them before starting
is the failure this arrangement exists to avoid.

The state file at `wip/scope_<topic>_state.md` stays authoritative for
`/scope`'s own position; the session carries the workflow's.

Never run a workflow cleanup or cancel verb against a session this run did not
open. koto reports `state file corrupted` for unrelated sessions on every tick,
and acting on that text destroys another run.

## Resume Logic

`/scope` maintains state at `wip/scope_<topic>_state.md` (one file
per topic, keyed by the topic slug). The full state-file schema,
conditional-field gating discipline, and R9 hard-finalization check
spec are documented in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`;
the `/scope`-specific field enumeration lives in
`skills/scope/references/state-schema.md`. On re-entry, the resume
ladder consults the state file, the per-child snapshots recorded
in state, and the current branch context to decide where to
re-enter.

The ladder shape follows the universal meta-ladder template at
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md`:
universal rows 1-4 (malformed → exit set → fresh resume → stale-
session) and rows 8-9 (on-topic branch → main fallback) are the
pattern-level meta-ladder; rows 5-7 are parent-specific body slots
`/scope` fills against its child set (`/brief`, `/prd`, `/design`,
`/plan`).

`/scope`'s stale-session threshold is **7 days**: state with
`last_updated` ≥ 7 days old surfaces the Resume / Force-materialize
/ Discard prompt; fresher state silently resumes. The threshold
inherits the default `/charter` chose for R16; the tactical chain
spans the same conversational profile as the strategic chain.

The ladder runs in the workflow, not in prose. The `resume_route`
state, right after the branch check, runs
`skills/scope/scripts/resume-probe.sh` as its one gate: a read-only
probe over the artifact tree, the state file, the child partials and
the handoff, which exits with the code of the first row that matches,
and `resume_route` sends each code to a state. The ladder's prompts
are states too (`resume_stale`, `resume_malformed`, `resume_exit_set`,
`resume_draft`, `resume_boundary`), with the ladder's wording and
choices. A state file that records an exit together with a
`publish_error:` routes an intent run straight back to its publish
state, which is how a failed publish is retried.

The full Slot 5 / Slot 6 / Slot 7 row body, each row's probe exit
code, and the drift-detection contract (Re-run / Accept /
Proceed-without — the three literal substrings the eval surface
grades against) live in
`skills/scope/references/phases/phase-resume.md`. The high-order
shape: Slot 5 has 11 rows evaluated most-downstream-first (with
PLAN-Active and PLAN-Done as refuse-and-redirect rows owned by
downstream skills, the Active redirect naming `/execute` or
`/work-on` by the PLAN's mode; two `--intent` shortcuts, `republish`
for an existing PLAN and `executed_report` for an executed topic;
and DESIGN-Accepted / PRD-Accepted as the two settled-upstream
boundary rows offering the **Re-evaluate / Revise / Bail** triad);
Slot 6 has 4 partial-child-run rows; Slot 7 is the feeder-doc
clause, matching the `/explore` handoff at
`wip/scope_<topic>_handoff.md` and entering Phase 1 with it
pre-loaded.

## Phase Execution

The phases and the file each one's procedure lives in. The workflow names the
right file at the right state, so this is a map rather than a reading list —
do not read them all before starting:

0. **Setup** — tokenizing, the entry through `scope-open.sh` (koto
   checks the arguments and opens or attaches the session), the
   `intake` state's working-tree checks and effective intent,
   visibility detection, state-file creation with `intent:`, stale
   `parent_orchestration:` self-heal.
   - Instructions: `skills/scope/references/phases/phase-0-setup.md`

1. **Discover + Chain Proposal** — topic-related child-doc
   discovery, R6 shape-predicate evaluation to size `/design`'s
   decision roster, chain-proposal output (Proceed / Adjust /
   Bail triad).
   - Instructions: `skills/scope/references/phases/phase-1-discovery.md`

2. **Child Invocation Loop** — invoke the planned chain (the
   whole tactical chain on every run; a child held back by re-entry
   protection stays in the list and is also recorded in
   `chain_skipped:`), running the worktree-staleness
   check before each invocation, writing the
   `parent_orchestration:` sentinel immediately before invoking,
   clearing the sentinel immediately after, capturing the child
   snapshot, running the validator pass-through against each
   intermediate, and running the consolidation judgment against
   the nearest surviving artifact above it.
   - Instructions: `skills/scope/references/phases/phase-2-chain-orchestration.md`

3. **Exit Finalization** — set the `exit:` field to one of
   `full-run`, `re-evaluation`, or `abandonment-forced`; write the
   `exit_artifacts:` list; run the R9 hard-finalization check
   (including R9 Part 2 multi-discriminator and R9 Part 3
   chain-membership-gated extensions from
   `parent-skill-state-schema.md`).
   - Instructions: `skills/scope/references/phases/phase-3-exit-finalization.md`

4. **wip Cleanup** — remove the topic's wip/ scratch artifacts
   (`wip/scope_<topic>_*` plus, on full-run or re-evaluation,
   `wip/{brief,prd,design,plan}_<topic>_*` and
   `wip/research/{prd,design}_<topic>_*`); preserve durable
   artifacts under `docs/`.
   - Instructions: `skills/scope/references/phases/phase-4-cleanup.md`

## Consolidation Judgment

The consolidation judgment is the only thing in a `/scope` run that removes a
document, and it runs in Phase 2, after each artifact lands -- never at Phase 1,
against artifacts nobody has written. The ordering is a bound, not a
preference: whether a document holds anything a later one does not is only
answerable against a document that exists, and the party deciding before it
exists is the one that benefits from not writing it.

A run therefore ends with all four artifacts, or fewer, or -- once the PLAN is
implemented and deleted -- none. Which of those is decided per hop against two
documents in hand, not chosen in advance and not fixed by the types involved.
There is no durable-artifact floor, and the prohibition on reintroducing one
lives beside the judgment in Phase 2.

Two verdicts: `keep` leaves both artifacts, `absorb` carries the upstream's
contribution into the survivor and removes the upstream. The judgment fires
only when both endpoints of the edge appear in `chain_ran:`. Its first stage, a
citation preflight, can reach no outcome stronger than `keep`. No check in it
may read either type's required-section list. And a carry check itemizes where
every concern landed before any deletion -- anything that did not arrive aborts
the absorb.

The eight-step procedure, the rollback table, and the firing condition are in
the Consolidation Judgment section of
`skills/scope/references/phases/phase-2-chain-orchestration.md`.

## Three Exit Paths

Every run ends at exactly one, recorded in `exit:`:

- **`full-run`** — the chain walked. Requires every hop to have either its own
  artifact at a canonical path or a recorded fold in a surviving document. A
  skipped hop satisfies neither, and the completion predicate has no skip limb.
- **`re-evaluation`** — a settled upstream was rejected at a boundary (PRD or
  DESIGN). Writes a Decision Record under `docs/decisions/`.
- **`abandonment-forced`** — the run stopped with a child mid-flight. Force-
  materializes that child's intermediate as a Draft artifact.

The R9 hard-finalization check refuses a run that cannot record a valid exit,
in `--auto` as much as interactively. The per-path required fields, the
Decision Record templates, and the abandonment marker are in
`skills/scope/references/phases/phase-3-exit-finalization.md`.

## State File Schema

`/scope` writes `wip/scope_<topic>_state.md`. The pattern-level schema and the
conditional-field gating discipline are in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md`; the
`/scope`-specific field enumeration, including which fields the workflow
session feeds and which it does not, is in
`skills/scope/references/state-schema.md`.

The substrate declaration stays `storage_substrate: wip-yaml-md`. A workflow
session does not change it: the session carries the workflow's position, the
state file carries `/scope`'s, and `exit:` lives in the file so a run whose
session is gone still reports how it ended.

## Security Considerations

`/scope` binds the six pattern-level contract surfaces in
`${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` — slug
re-validation on resume, closed write-target set, state-file enum
re-validation, stale `parent_orchestration:` self-heal, visibility boundary,
and no untrusted-input interpolation. `/scope` v1 binds to public-repo tactical
chains exclusively.

This is the authoritative declaration of the closed write-target set. The Phase
3 reference restates it and the Phase 4 reference reads it back; neither may
diverge from it. Every path below is composed from the validated topic slug or
is a fixed constant, never from author-supplied text. The `--upstream` value
does not widen the set: it is a read target only.

**Deletions**, by Phase 2's absorb:

- `docs/briefs/BRIEF-<topic>.md`
- `docs/prds/PRD-<topic>.md`
- `docs/designs/DESIGN-<topic>.md`

The PLAN is never a deletion target of a fold. At the terminal hop it is the
survivor; the implementation cascade deletes it later, outside `/scope`.

**Mutations**, by Phase 2's absorb — the survivor, at whichever hop:

- `docs/{prds,designs,plans}/{PRD,DESIGN,PLAN}-<topic>.md`
- `docs/designs/current/DESIGN-<topic>.md`

Both DESIGN locations appear because the canonical design path is a pair and a
survivor at either takes the same writes. `docs/plans/` appears because the
PLAN is the survivor at the terminal hop.

**Phase 3 and Phase 4**: Decision Records under `docs/decisions/`,
force-materialized partials under `docs/{briefs,prds,designs,plans}/` and
`docs/designs/current/` on `abandonment-forced`, and state-file plus child-wip
cleanup under `wip/`.

**R8's clean cancel** deletes one further path, and carves one out:

- deletes `wip/scope_<topic>_state.md` — that single path, not the prefix
- never deletes `wip/scope_<topic>_handoff.md`, which sits under the same
  prefix but belongs to the router rather than to this run, so a bail leaves
  it for a later invocation to resume against

The carve-out is enumerated here because an omission from a set that governs
deletion is a live delete at an undeclared target — the same reason every
other path in this section is named.

**Commits**, by Phase 2's per-hop commit and by the absorb's own:

- `docs/briefs/BRIEF-<topic>.md`
- `docs/prds/PRD-<topic>.md`
- `docs/designs/DESIGN-<topic>.md`
- `docs/designs/current/DESIGN-<topic>.md`
- `docs/plans/PLAN-<topic>.md`

`.git/` writes are confined to `git add` and `git commit` restricted to those
pathspecs — no `-A`, no `commit -a`, nothing staged the pathspec does not name.
The preconditions and branch checks are in the Per-Hop Commit section of
`skills/scope/references/phases/phase-2-chain-orchestration.md`.

**Publish**, on intent runs only (a run with no intent makes no push and no
`gh` call), by `skills/scope/scripts/publish-scoping-pr.sh`, which the agent
runs in the publish states and in `republish` and never as a default action:

- **untrack** — `git rm --cached` of the topic's own
  `wip/{scope,brief,prd,design,plan}_<topic>_*` and
  `wip/research/{prd,design}_<topic>_*`, committed as exactly that removal and
  nothing else staged; the files stay on disk for Phase 4
- **push** — `git push origin HEAD:refs/heads/<branch>`, with no force option
  and no `+` refspec, refused for a detached HEAD, for a branch failing
  `git check-ref-format --branch`, and for the remote's default branch
- **create** — one `gh pr create --head <branch> --base <default> --title
  <title> --body-file <file>`, only when the ownership filter finds no owned PR
  on the branch
- **edit** — `gh pr edit --body-file` on the one owned PR, only to rewrite its
  `intent=` field

`gh pr create` and that `gh pr edit` are the only `gh` writes. Every PR lookup
goes through the ownership filter in `skills/execute/scripts/owned-pr.sh`
(same repository, the authenticated author, the default base, the topic
branch), so a fork's or another author's PR on the same branch name is never
edited or reported. The body is a fixed template over the slug, exit, outcome,
`intent=`, mode, `docs/` artifact paths and work-item IDs, with no free-text
field. Every `wip/` path in unpushed history is reported as `wip_paths=`, and
the public-content visibility check runs over those files: a line naming a
`private/` path component, or declaring `Repo Visibility: Private`, in a
repository whose CLAUDE.md declares `## Repo Visibility: Public` stops the push
with `scope:push`. A failed publish writes `publish_error:` into the state file
under the parent's own prefix, which is already in this set.

**Out-of-repo ephemera**, by the workflow session: the koto session store
(`~/.koto/sessions/` under the default local backend) and koto's template
compile cache (`$XDG_CACHE_HOME/koto`, or `~/.cache/koto` when unset). Neither
is in the repository and neither is cleaned by this skill. The entry adds one
more: the args file of raw tokens and the vars file `scope-open.sh` derives
from it, both in a private `mktemp -d` directory (or the koto session
directory) outside the work tree, and both removed on every exit path. The
publish step adds another: the private index its untrack commit is built in and
the rendered PR body, in a `mktemp -d` directory removed on every exit path.

**No argument reaches a shell.** The invocation's tokens travel as JSON data
from the args file to koto's `--vars-file`, mapped by `jq`; nothing evaluates
or expands them, and a token holding shell metacharacters reaches koto as a
literal value that its variable's constraint then refuses.

## Reference Files

| File | When to load |
|------|-------------|
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-pattern.md` | All phases — contract surface, invariants, exit paths, Gate Vocabulary (Mandatory-with-auto-skip), L13 `parent_orchestration:` convention, substitution surfaces |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-state-schema.md` | Phase 0 (slug regex), Phase 2 (state writes including `boundary:` and `plan_execution_mode:`), Phase 3 (R9 check, multi-discriminator Part 2, chain-membership-gated Part 3) |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-resume-ladder-template.md` | Resume Logic — meta-ladder rows 1-4 and 8-9, refuse-and-redirect Slot 5 paragraph |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-child-inspection.md` | Phase 2 — child-doc inspection (R14 widened rule, dual-check drift detection) |
| `${CLAUDE_PLUGIN_ROOT}/references/worktree-discipline.md` | Phase 2 — per-child worktree-staleness check (Rebase / Impact-analysis / Escalation phases with `worktree_rebases:` and `worktree_divergences:` recording) |
| `${CLAUDE_PLUGIN_ROOT}/references/parent-skill-security.md` | All phases — six pattern-level security contract surfaces (slug re-validation, closed write-target set, enum re-validation, self-heal, visibility, no-untrusted-input-interpolation) |
| `skills/scope/references/phases/phase-0-setup.md` | Phase 0 — tokenizing, the entry through `scope-open.sh`, and what `intake` checks |
| `skills/scope/references/phases/phase-1-discovery.md` | Phase 1 |
| `skills/scope/references/phases/phase-2-chain-orchestration.md` | Phase 2 — includes Phase-N Reject in-chain mechanism |
| `skills/scope/references/phases/phase-3-exit-finalization.md` | Phase 3 |
| `skills/scope/references/phases/phase-4-cleanup.md` | Phase 4 |
| `skills/scope/references/phases/phase-resume.md` | Resume Logic — each row's probe exit code, Slot 5 (11 rows), Slot 6 (4 rows), Slot 7 (`/explore` handoff), session-recovered value re-validation, Drift Detection (Re-run / Accept / Proceed-without) |
| `skills/scope/references/state-schema.md` | All phases — `/scope`-specific state-file field enumeration (`intent:`, `visibility:`, `consolidation_judgments:`, exit discriminators, worktree audit fields, `drift_acknowledged:`, `parent_orchestration:` sentinel) |
