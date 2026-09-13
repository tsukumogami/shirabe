# Decision 4: One discriminator or two

## Context

PRD-work-on-standalone-completeness (`docs/prds/PRD-work-on-standalone-completeness.md`)
introduces two behaviours that both need to know whether the current run is a
root invocation or a child dispatched by a plan entry point:

- **R11/R12/R13** (`docs/prds/PRD-work-on-standalone-completeness.md:235-243`):
  a child materialized by the plan entry point must not pull the document
  chain to its terminal state — that is the plan's job, once. The existing
  `SHARED_BRANCH`/`pr_status: shared` fork (`skills/work-on/koto-templates/work-on.md:764-767`)
  does not cover this, because it only routes single-pr children (which skip
  `ci_monitor` entirely) — multi-pr children still land their own PRs, reach
  `ci_monitor`, and transition to `done` exactly like a root run
  (`skills/work-on/koto-templates/work-on.md:777-819`).
- **R19/R19a/R19b** (`docs/prds/PRD-work-on-standalone-completeness.md:312-341`):
  a root session's terminal tick must retain its workflow context record
  (pass `--no-cleanup` on the `koto next` that reaches the terminal); a child
  must never request that retention, because the retention flag suppresses
  both sources the parent's child-completion gate reads
  (`ChildCompleted`/`append_child_completed_to_parent`, per
  `wip/research/prd_work-on-standalone-completeness_phase4r3_testability.md:9`),
  wedging the parent indefinitely.

R19b explicitly leaves open "[w]hether that same mechanism also serves the
child-suppression signal of R12... that is not a requirements-level call"
(`docs/prds/PRD-work-on-standalone-completeness.md:338-341`). This report
answers that question for the design hop.

## What exists on this branch today

**`session-role.sh` is not present.** `find . -path "*/skills/work-on*"` and a
repo-wide search turn up no `session-role.sh` anywhere on
`docs/work-on-standalone-completeness` (current HEAD `4894c53`). The only
references to it are in this chain's own working notes:
`wip/scope_work-on-standalone-completeness_state.md:207-233`. So everything
below about the script's shape is carried forward from that note, not verified
against a real file, and is flagged as an assumption per the task brief.

**What the note says, and what independently checks out against the engine.**
Per `wip/scope_work-on-standalone-completeness_state.md:207-233`:

- The script prints `root` or `child`, reading koto's own `parent_workflow`
  field rather than a naming convention. A dot-based heuristic was vetoed as
  unsound both ways (legacy non-composed children carry no dot and would
  read as root; a user-chosen root name may contain one and silently drop
  retention).
- `parent_workflow` is readable via `koto session list` (per-session, keyed by
  id); `koto workflows` also emits it but is scoped to the current directory,
  so a session anchored elsewhere falls through; `koto status` emits nothing.
- The fix leaves `work-on.md` and `execute.md` untouched — its rule is
  consumed from `skills/work-on/SKILL.md`.

Independent verification against the koto engine
(`wip/research/explore_work-on-standalone-completeness_r2_lead-koto-materialization.md:177-183`)
confirms the load-bearing fact this rests on: `parent_workflow` is written into
the child's own event header by `init_child_core`
(`src/cli/init_child.rs:560`) on *every* `materialize_children` call,
unconditionally — it is not something a template author opts into by passing
a variable. That is structurally different from `SHARED_BRANCH`, which is a
plain template variable a caller must remember to set
(`skills/execute/koto-templates/execute.md:606,626` —
`.vars.SHARED_BRANCH = $b` on each task before dispatch). A fact the platform
records automatically can't be forgotten by a future dispatch call site the
way a hand-threaded variable can.

**The retention mechanism itself is concrete and already verified.** Per
`wip/research/prd_work-on-standalone-completeness_phase4r3_testability.md:9`:
`finish_terminal_tick` in `koto/src/cli/mod.rs` takes a `no_cleanup: bool`
and, when true, returns before the three durable completion records
(`append_request_store_result_to_child`, `append_terminal_index_for_session`,
`append_child_completed_to_parent`) are written. Mechanically, retention is
not a template construct at all — it is a CLI flag (`--no-cleanup`) on the
`koto next` invocation that reaches a terminal state, chosen by whoever issues
that command. `/scope`'s working version of the same pattern
(`skills/scope/references/phases/phase-4-cleanup.md:119-124`,
`skills/scope/requires.tsv:31`) confirms the shape: `requires.tsv` names the
flag per call site, and a phase reference file (reached from `SKILL.md`, never
from the koto template body) carries the instruction and rationale.

**Cascade suppression has no code yet** — R1/R11 are unimplemented — but the
insertion point is visible from the existing terminal wiring. `done` is a bare
`terminal: true` sink with no `accepts` of its own
(`skills/work-on/koto-templates/work-on.md:820-821`); every path into it is a
`transitions: when:` clause on the *preceding* state
(`pr_creation` when `pr_status: shared` at :764-765; `ci_monitor` when
`ci_outcome: passing` or `failing_fixed` at :795-802). A new cascade state has
to be spliced into exactly this handoff — most naturally as an added
`session_role` field alongside `ci_outcome` on `ci_monitor`'s `accepts`, with
`transitions: when: ci_outcome: passing, session_role: root` routing into the
new cascade state and `session_role: child` routing straight to `done`,
mirroring the `pr_status`/`ci_outcome` pattern already in the file.

## Options considered

### Option A — one script, consulted independently from two places

`session-role.sh` (or whatever R19b's mechanism ends up naming) stays a single
source of truth. It is invoked twice, from two structurally different
consumption sites:

- **Cascade suppression**, from inside `work-on.md`'s own template body — as
  the directive text for `ci_monitor` (and any new pr_creation-adjacent path
  that reaches CI), instructing the agent to run the script and submit its
  result as an accepted field (`session_role: root|child`) that a
  `transitions: when:` clause branches on, exactly like the existing
  `ci_outcome`/`pr_status` fields.
- **Terminal-record retention**, from `SKILL.md` or a phase reference file it
  cites (following the `/scope` precedent), instructing the *root-driving*
  agent to run the script before the final `koto next` and append
  `--no-cleanup` only when it prints `root`.

**Why this fits the mechanics, not just the requirements text.** `skip_if`
(the only demonstrated "skip a whole state" primitive) only reads
`vars.*` and same-state accepted fields
(`skills/work-on/koto-templates/work-on.md:45-47,286-289`) — values fixed at
session-init time or submitted at that state, never a value computed
mid-run and threaded through invisibly. There is no gate type in the file
that branches a *transition* off an arbitrary shell computation directly;
branching happens via a state's `accepts`+`transitions when:`, which means
whatever decides cascade routing must be *computed and submitted as evidence
at the deciding state*. That is naturally template-body prose (satisfying
R10), not `SKILL.md` prose. Retention's consumption point, by contrast, is
necessarily outside the template's declarative graph — `done` accepts
nothing, so the choice of `--no-cleanup` has to be made by whoever issues the
CLI call, which is exactly why `/scope`'s and the assumed `#360` fix's
mechanism live in reference prose, not in template YAML.

**Correctness.** Single source of truth: if the underlying fact
(`parent_workflow` via the script) is ever wrong, both behaviours are wrong in
a way that is traceable to one place, not two independently-drifting
implementations. Satisfies R19b's literal test ("the cascade states call the
same named helper or discriminator... a search for a second implementation
... returns nothing") without contortion.

**Failure mode.** If `session-role.sh` itself has a bug (say, it defaults to
`root` when `koto` is unreachable), both behaviours fail together, in the
same direction, on the same runs. That is easier to reason about and to test
once than two independently-wrong mechanisms failing in uncorrelated ways.

**Cost of a later tidy-up.** Someone "simplifying" this later might try to
collapse the two call sites into one shared value (Option C) — see that
option's discussion for why that specific collapse is the trap, not this
option itself. Option A does not invite that mistake as directly, because the
two call sites are already visibly different in kind (a template `accepts`
field vs. a `koto next` CLI flag chosen by prose), so there's less temptation
to merge them.

### Option B — two independent mechanisms

Build a second discriminator purpose-built for cascade suppression — e.g. an
explicit `IS_CHILD` (or `SESSION_ROLE`) template variable, set the way
`SHARED_BRANCH` is set today: `execute.md`'s dispatch loop adds
`.vars.SESSION_ROLE = "child"` to each task before calling
`materialize_children` (mirroring `skills/execute/koto-templates/execute.md:606,626`),
defaulting to `root` (or unset) for any session created directly. This would
plug straight into `skip_if: vars.SESSION_ROLE: child`, the same pattern
`setup_plan_backed` already uses for `SHARED_BRANCH`
(`skills/work-on/koto-templates/work-on.md:286-289`) — arguably a cleaner fit
for `skip_if` than Option A's accepted-field-plus-transition approach.

**Correctness.** Works for the one dispatch path that exists today
(`execute.md`'s `materialize_children` call sites). But it is opt-in and
textual in exactly the sense R19's own rationale rejects for retention: "the
discipline is root-only at runtime, not textual"
(`docs/prds/PRD-work-on-standalone-completeness.md:317-319`). Any future
dispatch path that materializes a `work-on.md` child — and the codebase
already has at least one precedent for adding new ones (multi-pr's own
still-unowned entry-point gap, `wip/research/explore_work-on-standalone-completeness_r2_lead-multipr-cadence.md:78`)
— would have to remember to set the variable, or a child silently reads as
root. `parent_workflow` cannot be forgotten this way because koto sets it
unconditionally on every `materialize_children` call
(`src/cli/init_child.rs:560`), regardless of which template author wrote the
dispatch code.

**Failure mode, and which direction it's biased toward.** A forgotten
`SESSION_ROLE` var on a new dispatch path defaults every future child to
"root" (since `skip_if` only fires when the var is explicitly matched) —
exactly the false-root failure the task asks about: a false `root` for a
child wedges its parent (retention side, if this same variable were reused
there) and — for the cascade side specifically — a false `root` on a child
means the child *does* run the cascade, which is the R11 violation this whole
requirement exists to prevent. This is worse than Option A's shared-script
risk because it is a *per-call-site* risk that compounds with every new
caller, not a single script to get right once.

**Why it's still "two mechanisms" even if it reused the same variable name for
retention.** R19b requires reusing the mechanism the separately-landing fix
introduces, and that fix (per the working note) is `parent_workflow`-based,
not variable-based. Building a second, variable-based signal for cascade
specifically — even one that happens to agree with `parent_workflow` in the
common case — is a second implementation of "is this a child," which is
exactly what R19b's own testable definition rules out.

### Option C — one script, result captured once into koto context, read twice

Run `session-role.sh` once, early (e.g., at `entry` or the first setup state),
submit its result as an accepted field, and let koto persist it in context.
Later consumption sites — the `ci_monitor`-adjacent cascade branch, and the
`SKILL.md`-level retention prose — read the stored value (`koto context get`)
instead of re-invoking the script.

**Where this breaks: retention's blast radius is wider than cascade's.**
R19 covers "every terminal tick this feature introduces," but the underlying
`#360`/koto#240 fix this feature must reuse is not scoped to this feature's
new states — it is described as fixing *all* of `/work-on`'s terminal ticks
(`wip/research/explore_work-on-standalone-completeness_r1_lead-standalone-trace.md:93`
lists `done`, `done_already_complete`, `done_blocked`, `validation_exit`, and
`skipped_due_to_dep_failure` — none exempted). Several of those terminals
(`validation_exit`, `done_already_complete`, `skipped_due_to_dep_failure`) are
reached on paths that never pass through the new cascade-decision state this
PRD adds. A context value captured only at that new state would simply not
exist on those paths, forcing a fallback re-invocation of the script anyway —
which means Option C doesn't actually eliminate the second call, it just adds
a cache that's empty exactly where the retention behaviour also needs to work.
The only way to make the capture-once value generally available would be to
compute it at `entry`, before any mode-specific branching — which is possible,
but then buys nothing mechanically over Option A (the script is cheap: one
`koto session list` call) while adding a second thing that has to be kept in
sync (the captured context key, plus whatever documents that consumers must
read it from context rather than compute it fresh).

**Correctness and failure mode.** Marginally more fragile than Option A
without a matching benefit: an extra piece of state (the captured context
key) that could itself go stale or missing on a code path nobody thought to
route through the capturing state, versus Option A's each-site-computes-fresh
guarantee that the value is never staler than the moment it's needed.

**Verdict on collapsing.** This is the "later tidy-up that could collapse
things wrongly" the task warns about. It looks like a natural simplification
of Option A ("why call the script twice when you could call it once") but it
quietly assumes the two consumption sites share a code path, which R19's own
scoping note ("R19 covers only the states this feature adds,"
`docs/prds/PRD-work-on-standalone-completeness.md:472-474`) shows they do not.

### Option D — a single koto-level discriminator, if koto exposes one natively

Check whether koto itself exposes root/child as a first-class template
primitive — e.g., an auto-populated `vars.PARENT_WORKFLOW`, or a gate type
like `is-root`/`is-child` — which would let both consumption sites use the
engine's own vocabulary instead of a repo-owned wrapper script.

**Not available today.** Per the working note and independent verification:
`parent_workflow` is exposed only through `koto session list` (per-id) and
`koto workflows` (scoped to cwd, so a session anchored elsewhere falls
through) — both external CLI calls, not template-interpolable variables —
and `koto status` emits nothing at all
(`wip/scope_work-on-standalone-completeness_state.md:212-214`). There is no
`include`/`extends` template-composition mechanism either
(`wip/research/explore_work-on-standalone-completeness_r2_lead-koto-materialization.md:163-172`),
so there is no way to write this once at the koto-template level and have it
apply to both `work-on.md` and whatever consumes it from `SKILL.md`-side
prose. This option collapses to "write `session-role.sh` as the wrapper that
makes the engine's fact usable from a template state's directive text" —
which is Option A. It's not a fifth path; it's the reason Option A's wrapper
script exists instead of a bare `koto session list | jq` inline in two
places.

## The asymmetry, stated plainly

Retention and suppression are needed at different points in the run and are
reachable from different places, for reasons that don't disappear under any
of these options:

- **Suppression** must be decided *before* the cascade-entering state, and
  the only state that can decide it (`ci_monitor`, per the existing
  `pr_status`/`ci_outcome`-based transition pattern) is inside `work-on.md`'s
  own compiled body — which a materialized child *does* receive
  (`wip/research/explore_work-on-standalone-completeness_r2_lead-koto-materialization.md:194-198`).
  This is required by R10: an obligation that lived only in `SKILL.md` would
  be structurally unreachable by a child, and for this obligation, omission
  is the failure (a child that never learns to suppress just cascades).
- **Retention** must be decided at each terminal tick, by whoever issues the
  `koto next` that reaches it — a CLI-flag choice, not a template-graph
  branch, because `done` (and the other terminals) accept nothing to branch
  on. The `#360`/`koto#240` fix's own placement in `SKILL.md`
  (`wip/scope_work-on-standalone-completeness_state.md:221-223`) is *correct
  for that rule specifically* because a child never reaching `SKILL.md` means
  a child never learns to retain — omission is the correct child behaviour
  here, the mirror image of the cascade case.

So the two behaviours don't just fire at different times — they are
consumed from places that differ for a load-bearing reason tied to each
rule's own failure mode, not an incidental one. That is exactly the condition
under which "one mechanism consulted twice" is coherent and "one mechanism
consulted once, then reused" (Option C) is not: the shared part is the fact
(root or child), not the code path that consumes it.

## Cost of getting it wrong, per option

- **Option A** (one script, two call sites): if the script itself is wrong,
  both behaviours fail together and in the same direction — traceable to one
  place. If only one call site is wired up wrong (e.g., someone hand-edits
  the `ci_monitor` transition and typos the field name), that one behaviour
  fails independently; a false `child` there silently drops the cascade
  (R11's failure mode), while a false `child` at the retention call site
  silently drops the record — both quiet, neither wedges anything, matching
  the "false child" bias the task names. A false `root` misapplied at the
  retention site is the dangerous direction: it wedges the parent. Option A
  does not make a false `root` more or less likely than any other option
  that ultimately reads `parent_workflow` — the risk lives in the underlying
  fact, not in how many places read it.
- **Option B** (separate variable-based mechanism): biased toward false
  `root`, structurally. Because `skip_if`/transition matching only fires on
  an explicitly-set value, any dispatch path that forgets to set the variable
  reads as root by default — which is the wedge-the-parent direction for
  retention and the always-cascade direction for suppression (itself also a
  correctness bug, just not the one R19 is protecting against). This is the
  worst-biased option of the four for the specific failure the task flags as
  most dangerous.
- **Option C** (captured-once context): biased toward false `child` on the
  paths that never touch the capturing state — those terminals would find no
  context value and (depending on how the fallback is written) most likely
  degrade to "don't retain," which is the omission-is-safe direction for
  retention but is a coverage gap against R19's own requirement to cover
  every new terminal tick, and provides no benefit over Option A on the
  paths it does cover.
- **Option D**: not a real fourth option today — see above.

## Recommendation

One discriminator — the script (or whatever the `#360`/koto#240 fix
ultimately names) that reads `parent_workflow` — consulted independently from
two places: as directive prose inside `work-on.md`'s own template body (most
naturally an added `session_role` evidence field on `ci_monitor`, branching
the transition into a new cascade state versus straight to `done`) for
cascade suppression, and as `SKILL.md`/phase-reference prose for terminal
retention, matching wherever the `#360` fix actually lands it. This is Option
A.

The reasoning that settles it, in order of weight: (1) the two consumption
sites are dictated by mechanics that don't change under any option — `done`
accepts nothing, so retention can only be a CLI-flag choice made by prose,
while cascade suppression can only be a template-graph branch reachable by a
child, so template prose is the only option; (2) R19b's testable definition
("the same named helper or discriminator... a search for a second
implementation returns nothing") is satisfied exactly by Option A and
violated by Option B; (3) Option B's per-call-site opt-in reproduces the
"textual, not root-only-at-runtime" defect R19's own rationale was written to
rule out, applied now to the requirement that didn't originally name it; (4)
Option C's apparent simplification silently assumes retention's and
suppression's code paths coincide, which R19's own "states this feature adds"
scoping shows is false, and would leave the pre-existing terminal ticks
`#360` is supposed to also cover without a computed value to read.

This recommendation assumes the working note's description of the
`session-role.sh` fix is accurate, since the script itself is not present on
this branch. If the landed fix differs — reads a different field, exposes
its result differently, or (per R19b's own escalation clause) has not landed
at all by the time this feature is implemented — the mechanical argument
above still holds (compute the fact once per consumption site, from whatever
the actual mechanism is), but the concrete wiring (an accepted `session_role`
field on `ci_monitor`, the exact script name) would need to be re-verified
against whatever actually merged.

## Open questions

- What does `session-role.sh` (or the merged fix's actual mechanism) do when
  `koto` is unavailable or `parent_workflow` is missing from its output —
  exit non-zero, print an empty string, or default to a value? This decides
  the fail-open/fail-closed posture of both consumption sites and cannot be
  answered until the fix lands or its PR is read directly.
- Does the merged `#360` fix express its root/child check as a shell script
  at all, or does it turn out to be a small inline command repeated at each
  `requires.tsv` line (the way `/scope`'s `--no-cleanup` itself is a bare
  `requires.tsv` annotation, not a wrapped script)? If so, "the same named
  helper" in R19b's test may resolve to a `requires.tsv` pattern rather than
  a callable script, which would change how the cascade side's `ci_monitor`
  directive should phrase "call the same check."
- Is `parent_workflow` guaranteed durably written before a child ever reaches
  `ci_monitor`, or is there a case (e.g. a child that queries its own role
  very early, before the parent's dispatch loop has finished writing the
  header) where the fact is queried before it's durably recorded? This wasn't
  checked against `init_child_core`'s event ordering and is worth a direct
  look before implementation.
