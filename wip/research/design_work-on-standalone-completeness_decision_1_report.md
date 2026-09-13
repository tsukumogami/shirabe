# Decision 1: Where the shared cascade machinery lives

## Context

`skills/execute/scripts/run-cascade.sh` (1,157 lines) walks a PLAN's upstream
frontmatter chain, runs `shirabe finalize-chain`, performs the `git rm`/`add`/
`commit`/`push` sequence, runs the `handle_roadmap`/`handle_roadmap_deletion`
bash handlers, and emits the `{cascade_status, steps[]}` JSON contract that
`execute.md`'s `plan_completion` state parses
(`skills/execute/koto-templates/execute.md:706-729`). It is invoked exactly
once today, from directive prose (agent-run bash, not a koto `command:`
field), as:

```
RESULT=$(${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/run-cascade.sh --push {{PLAN_DOC}})
```

(`skills/execute/koto-templates/execute.md:709`). Because this is directive
prose rather than a koto-evaluated gate command, `${CLAUDE_PLUGIN_ROOT}`
resolves at the agent's own shell, the same way for any path under the plugin
root — this is confirmed by `references/`-lead research and by
`scripts/check-template-interpolation.sh:14-23`, which explicitly exempts
directive-prose shell interpolation from the `{{KEY}}`-only rule that governs
koto-executed gate commands. **This means no relocation option is blocked on
interpolation mechanics** — `${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/...`,
`${CLAUDE_PLUGIN_ROOT}/scripts/...`, and the status quo path all resolve
identically well from either template's directive prose.

The location was a recorded decision, not an accident. `docs/designs/current/
DESIGN-execute-skill.md` (status: `Current`) Decision 2 chose:

> "**Extraction — move into /execute (chosen, E3).** Move `work-on-plan.md`,
> the orchestrator prose, and `run-cascade.sh` (with the
> `WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch) into /execute; keep `work-on.md`
> in /work-on as the canonical single-issue engine /execute spawns by
> cross-skill path."
> (`docs/designs/current/DESIGN-execute-skill.md:101-104`)

— explicitly rejecting the alternative next to it:

> "**Extraction — shared library both skills reference.** Rejected: a neutral
> or plan-hosted template muddies the single-issue legibility the narrowing is
> meant to buy."
> (`docs/designs/current/DESIGN-execute-skill.md:98-100`)

R5a (PRD:183-193) now forbids the status-quo reading of E3 continuing to hold
once `/work-on` also needs the cascade: "the chosen location SHALL NOT leave
the single-issue skill depending on the plan entry point." Any answer here
**amends E3** — it does not reopen Decision 2's "shared library" rejection,
because (a) that rejection was about a shared, neutral *koto template*
muddying legibility, not about a script, and the PRD's own "Decisions and
Trade-offs" section already draws this line: "a script is executed rather
than read into a run's context and is not the thing that was rejected"
(PRD:536-537); and (b) it is not proposing a neutral third location either —
every option below keeps the script inside one skill's ownership or moves it
out of the skill layer entirely, matching E3's actual principle (full
ownership, not joint reference) even where it changes which party owns it.

`assert-child-template.sh` (`skills/execute/scripts/assert-child-template.sh`)
is the existing guard for the one cross-skill path E3 already created:
`/execute` resolves `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/
work-on.md` before spawning any child, and fails loud and early if it's
missing (`skills/execute/scripts/assert-child-template.sh:1-29`). This is the
"dedicated assertion" the PRD's motivating text refers to
(PRD:191-193, PRD:527-528) as the kind of guard a second load-bearing
cross-skill path deserves. Notably, `/execute` already has a **second**,
*unguarded* cross-skill path today — `${CLAUDE_PLUGIN_ROOT}/skills/plan/
scripts/plan-to-tasks.sh` (`skills/execute/koto-templates/execute.md:598,618`)
— which has no analogous assertion. Both existing cross-skill paths point the
same direction: `/execute` → `/work-on` and `/execute` → `/plan`. Neither
`/work-on` nor `/plan` references anything under `skills/execute/`. That
asymmetry is the load-bearing fact for this decision: it is not merely that
R5a *forbids* inverting it, it is that nothing in the repository today
inverts it, and the naive fix would be the first thing to.

## Options considered

### Option 1 — Leave it in `skills/execute/scripts/`, `/work-on` calls across

**What it is.** Do nothing to the script's location. `/work-on`'s koto
template gains a `plan_completion`-equivalent step whose directive prose reads
`${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/run-cascade.sh --push
{{PLAN_DOC}}`.

**What it costs.** The smallest possible diff: zero files move, no test
harness relocates, no CI workflow trigger path changes. `run-cascade.sh`,
`run-cascade_test.sh`, `assert-child-template.sh`, the `requires.tsv` comment
block, and every doc reference to the script's path stay exactly where they
are.

**What it breaks.** This is precisely the reading R5a exists to forbid. The
PRD states it in the requirement text itself: "The script lives under the
plan entry point's own directory today, so the naive reading of 'both call
one script' would invert the dependency direction that this feature's whole
shape rests on" (PRD:189-193), and restates it as a named acceptance
criterion: "the single-issue skill does not reference any path under the
plan entry point's directory. Verified by searching the single-issue skill's
tree for such references and finding none" (PRD:367-370). This option fails
that criterion by construction — it is not a close call or an edge case, it
is the literal shape the criterion was written to catch. It also creates
the second load-bearing cross-skill path the motivating text warns about
(PRD:191-193), except in the wrong direction: where `assert-child-template.sh`
guards `/execute`'s dependency on its own consumer's canonical engine (a
downward reach that was always the design), this would be `/work-on`
depending on the thing that depends on it — a cycle in spirit even though
koto sessions never literally call each other in a loop. Rejected outright;
included here because it is the "obvious" reading a first-time implementer
reaches for, and the report needs to show why it was ruled out rather than
merely asserting that it was.

### Option 2 — Move to a repo-root location neither skill owns

**What it is.** Relocate `run-cascade.sh` (and its test) to somewhere under
the repository's existing root-level `scripts/` directory — e.g.
`scripts/run-cascade.sh` or `scripts/cascade/run-cascade.sh`. Both `/execute`
and `/work-on` invoke it as `${CLAUDE_PLUGIN_ROOT}/scripts/run-cascade.sh`,
a peer reference to shared infrastructure rather than a reach into either
skill's own directory.

**The case for it.** The PRD names this option itself as "the obvious
candidate" and leaves it to the design hop deliberately: "The repository
already has a root-level `scripts/` directory holding cross-skill machinery,
including the test for the one expression both templates duplicate on
purpose. That is the obvious candidate, and naming it here would be deciding
a layout question without having looked at what else moves with it."
(PRD:539-543). There is real, *runtime* precedent for a root-`scripts/`
script both skills invoke identically without either owning it:
`${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh` is injected at column 0 in
both `skills/execute/SKILL.md:19` and `skills/work-on/SKILL.md:19`
(`!\`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill> 2>&1 ||
true\``), and `scripts/validate-template-mermaid.sh` lints both templates the
same way. A root location trivially satisfies R5a's letter — `/work-on`
never references a path under `skills/execute/` — without creating a
cross-skill dependency in *either* direction, since neither skill's directory
is the owner.

**What it costs.** `run-cascade.sh` and `run-cascade_test.sh` move out of
`skills/execute/scripts/`; every reference to the old path updates: the two
call sites in `execute.md` (lines 706-709), `SKILL.md`'s description
(`skills/execute/SKILL.md:257`, `:786`), the informational comment block in
`skills/execute/requires.tsv` describing what the script does, the hardcoded
path in `scripts/check-bash-floor.sh:111` (moves from the `execute` case arm
to a new or existing arm), and the `check-execute-scripts.yml` workflow step
`run: bash skills/execute/scripts/run-cascade_test.sh`
(`.github/workflows/check-execute-scripts.yml:27-29`), whose `paths:` trigger
(`skills/execute/scripts/**`) would also need to include the new location or
be replaced by a new workflow file.

**What it breaks — or rather, what it blurs.** The precedent the PRD leans
on (`skill-preflight.sh`) is not structurally the same kind of script.
`skill-preflight.sh`'s own header states its genericity plainly: "the
prerequisite check for **one shirabe skill**... Usage: bash
scripts/skill-preflight.sh **<skill-name>**" (`scripts/skill-preflight.sh:1-4`)
— it is parameterized by caller and behaves identically for any of a dozen
skills that pass their own name in. `validate-template-mermaid.sh` is the
same shape: a generic linter over *any* koto template file. Every other
inhabitant of root `scripts/` that a template or `SKILL.md` actually invokes
at runtime is this kind of skill-agnostic, parameterized infrastructure; the
rest of the directory (`check-template-directives.sh`,
`check-skill-requires.sh`, `ci-gate-expression_test.sh`, `check-sentinel.sh`,
etc.) runs only in CI, never at agent runtime, over the whole repository tree
rather than as a step one specific workflow calls. `run-cascade.sh` is
neither: it is single-purpose domain logic for exactly one business
process (PLAN-anchored artifact lifecycle finalization), non-generic (it does
not take a skill name and behave differently per caller — it always walks
the same PLAN-shaped chain), and it mutates git state and repository content
as its main effect rather than checking or linting. Moving it to `scripts/`
would be the first instance of skill-specific, mutating business logic living
in a directory that has so far held only checks and skill-agnostic utilities;
there is no `scripts/README.md` or other scoping document establishing this
as the directory's intended second category, so this option would be
extending root `scripts/`'s remit by example rather than by a stated rule.
This is a real cost, not a fatal one — it is a legibility argument, structurally
the same *kind* of argument (where does an artifact live so a reader can find
it) that sank the "shared library" template option in Decision 2, but applied
to a different location than that decision considered.

**What breaks if someone moves it again.** A root-level location has no
natural "owner" to push back if unrelated repository-wide tooling accretes
around it — the failure mode is drift toward `scripts/` becoming a junk
drawer for anything more than one skill happens to touch, which is exactly
the shape `references/tool-declaration-policy.md`'s split-rule reasoning
(coupled vs. independent cadence, PR-scoped review) exists to head off for
tool declarations; there is no equivalent stated rule for script placement.

### Option 3 — Move under `skills/work-on/scripts/`, `/execute` calls across

**What it is.** Relocate `run-cascade.sh` (and its test) to
`skills/work-on/scripts/run-cascade.sh`. `/work-on`'s own koto template
invokes it directly (no cross-skill path at all, for the skill that needs it
for its own R1/R2 obligations). `/execute`'s `plan_completion` state keeps
calling it, but now over a cross-skill path:
`${CLAUDE_PLUGIN_ROOT}/skills/work-on/scripts/run-cascade.sh --push
{{PLAN_DOC}}`.

**Why this is the direction the repository's dependency graph already runs.**
`/execute` already has two cross-skill dependencies, and both point the same
way: `${CLAUDE_PLUGIN_ROOT}/skills/work-on/koto-templates/work-on.md` (the
child-materialization target, guarded by `assert-child-template.sh`) and
`${CLAUDE_PLUGIN_ROOT}/skills/plan/scripts/plan-to-tasks.sh`
(`skills/execute/koto-templates/execute.md:598,618`, unguarded today). Neither
`/work-on` nor `/plan` references anything under `skills/execute/`. Adding a
third `/execute` → `/work-on` reference (this time to a script rather than a
template) does not introduce a new *kind* of coupling — it extends an
existing, already-guarded pattern one path further, using the same
`${CLAUDE_PLUGIN_ROOT}/skills/<owner>/...` shape `assert-child-template.sh`
already established as legible and testable.

**What it costs.** The move touches the same file set Option 2 does — the
script, its test, two call sites in `execute.md`, `SKILL.md` prose and its
component-inventory table in both skills, the `requires.tsv` comment block
(which moves from `skills/execute/requires.tsv` to `skills/work-on/
requires.tsv`, since that file's comment documents what the *owning* skill's
script does — `requires.tsv` itself is unaffected structurally, since script
paths are outside its schema per `references/tool-declaration-policy.md`,
which governs only `shirabe`/`koto`/`gh`/`jq`/`git`/`python3` calls), the
`scripts/check-bash-floor.sh:111` suite-script list (moves from the
`execute` case arm to the `work-on` arm, which already lists
`skills/work-on/scripts/retry-clearing_test.sh` — precedent for a script test
living there), and the CI workflow step (moves from
`check-execute-scripts.yml` to `check-work-on-scripts.yml`, whose `paths:`
trigger already covers `skills/work-on/scripts/**`
(`.github/workflows/check-work-on-scripts.yml:5`) with no new trigger line
needed). This is a materially larger diff than Option 1's zero, comparable to
Option 2's, and additionally amends `DESIGN-execute-skill.md`'s "moved from
/work-on" component-inventory line (`docs/designs/current/
DESIGN-execute-skill.md:156-157`) — the same document R18 already requires a
decision record against for the unrelated multi-pr routing question, so this
is not new machinery, but it is a second reason that document needs the
pointer.

**What it breaks.** Nothing mechanically — the interpolation mechanics are
identical regardless of which skill's directory a `${CLAUDE_PLUGIN_ROOT}`
path descends into (see Context). The only thing this option arguably
"breaks" is the letter of E3's specific placement choice (it moves the
script back into `/work-on`, the direction E3 moved it *away from*), which is
exactly why this option, like every other option here, amends E3 rather than
merely implementing it — the decision record this design produces has to say
so explicitly regardless of which option is chosen, because R5a itself
already states the constraint is "settled... rather than fixed incidentally,"
meaning even the status quo direction can't survive un-recorded.

**What breaks if someone moves it again.** Low risk: the pattern this
establishes (`/execute` reaches into `/work-on`'s directory for both the
child template and the cascade script) is now used twice, which is the
opposite of a fragile precedent — a third similar need has an obvious existing
convention to follow rather than a fresh judgment call. Introducing a
guard analogous to `assert-child-template.sh` for this second path (currently
absent for `plan-to-tasks.sh` and would be newly relevant here) is worth
flagging as a follow-on, not a blocker — see Open Questions.

### Option 4 — Duplicate the script in both skills, guarded by a CI drift check

**What it is.** Keep a full copy of the cascade logic under both
`skills/execute/scripts/` and `skills/work-on/scripts/`, with a CI script
that diffs the two files (or the behavior they produce against shared
fixtures) and fails the build on divergence.

**The precedent it leans on.** The repository already accepts exactly this
shape for one piece of duplicated logic: `work-on.md` and `execute.md` both
carry an inline `ci_passing` gate expression — the same `gh pr checks
--json ... --jq '...'` pipeline — copy-pasted rather than shared, because
koto templates have no include/inherit mechanism at all
(confirmed against koto's own template-format reference and its archived
design doc; neither documents composition). `scripts/ci-gate-expression_test.sh`
is the drift check: it extracts the live gate command out of each template
with `scripts/lib/koto-gates.sh`, and runs the same fixture matrix (all-pass,
fail, cancel, pending, unknown-bucket, no-checks) against both extracted
expressions, so a future edit to one template that silently changes its
semantics fails CI rather than shipping a second, disagreeing copy
(`scripts/ci-gate-expression_test.sh:1-27`, `:136-216`). `work-on.md`'s own
gate carries the inline comment "kept identical to execute.md"
(`skills/work-on/koto-templates/work-on.md:790`) naming its counterpart.

**Why the precedent does not transfer.** The PRD's own "Decisions and
Trade-offs" section already runs this comparison and rejects it: "the
repository does accept deliberate duplication guarded by a drift check, and
uses it for one CI-gate expression, but a 200-line script is not a one-line
expression and the drift would not stay caught" (PRD:530-533; the script is
actually 1,157 lines, an even larger gap than the PRD's own estimate). The
distinction is not that a byte-diff over a longer file is mechanically
harder to write — it is not — it is that `run-cascade.sh` has git-mutating
side effects, a JSON step-accumulation contract seven other pieces of the
system parse, ROADMAP-specific bash handlers with their own idempotency
invariants (`handle_roadmap`, `handle_roadmap_deletion`,
`skills/execute/scripts/run-cascade.sh:479-690`), and an extensive internal
comment record of prior incidents (`resolve_anchor`'s comment names two
specific scenarios by name, `run-cascade.sh:317-339`). Two copies of this
under active development is a standing invitation for exactly the failure
this repository has already lived through once with the one-line gate
expression (`scripts/ci-gate-expression_test.sh:12-13`: "That is how issue
#244 got two templates gating CI on the same wrong expression" — quoted from
the sibling `validate-template-mermaid.sh` comment the test file cites). A
drift check *catches* divergence after the fact; it does not lower the odds
that a bug fix applied under time pressure to one copy is forgotten in the
other, and every future PR touching cascade behavior now has two files to
edit and one more CI gate to satisfy, forever, for a component with git-level
blast radius (a bad cascade commits and pushes to a shared branch). This
option is priced fully here because the report should not merely defer to
the PRD's own rejection without showing why it holds under a size/risk
analysis, not because there is a live case for choosing it.

### Option 5 — Fold the cascade into the `shirabe` binary as a new subcommand

**What it is.** Move the orchestration itself out of bash entirely: a new
`shirabe cascade run --push <plan-doc>` subcommand absorbs `run-cascade.sh`'s
logic (the pre/post lifecycle probes are already `shirabe validate` calls;
`finalize-chain` is already Rust; only the git mutation sequence and the
`handle_roadmap`/`handle_roadmap_deletion` bash handlers would need porting).
Both `/execute` and `/work-on` would then declare and call an ordinary
`shirabe` subcommand via `requires.tsv`, the same way they already declare
`shirabe finalize-chain` and `shirabe transition` — eliminating the
cross-skill *script* question entirely, since there would be no script.

**Why the repository suggests this direction.** Two pieces of evidence point
here. First, `CLAUDE.md`'s CLI-surface rule explicitly encourages exactly this
move for correctness/orchestration logic while foreclosing only the
*artifact-authoring* half: a shared deterministic check or mechanical
git/gh-driving action absorbed into `shirabe` is the rule's stated
"anti-pattern... do not repeat" only in reverse — the removed
`shirabe coordination create/status/sync` subcommand was rejected because it
*rendered a PR body* (authored content), not because it moved mechanics into
the binary. Second, `run-cascade.sh`'s own comments already draw this exact
boundary inside the script: the tactical chain walk and per-node transition
decision are "owned by the `shirabe finalize-chain` subcommand"
(`skills/execute/scripts/run-cascade.sh:6-10`), and the ROADMAP handler stays
in bash specifically because it is "external-state-dependent (`gh`) and out
of finalize-chain's scope" (`skills/execute/scripts/run-cascade.sh:479-483`)
— i.e., the boundary between "in Rust" and "in bash" has already been moving
toward Rust for everything that isn't inherently a shell-level git/gh
mutation, and this option is that trend's logical next step, not a novel
idea.

**What it costs.** This is categorically larger than the other four options.
`shirabe` is a coupled-cadence tool per `references/tool-declaration-policy.md`
("shirabe declares what it can track" — Coupled cadence tools get
subcommand-and-flag `requires.tsv` records that both skills would gain), but
more importantly it requires a Rust implementation, its own test suite inside
`crates/shirabe/tests/`, a `cargo build`/release cycle before either skill
could adopt it, and a design and review of its own — this PRD's Requirements
and Out of Scope sections say nothing about a CLI surface change, and R20
explicitly forbids touching the execution-mode enum/schema (a narrower but
related kind of CLI-surface stability constraint), suggesting this feature's
intended blast radius is the skill layer, not the binary. It would also
need its own decision about whether git mutation belongs in a compiled binary
at all, a question this PRD never raises and the design hop for this feature
should not decide as a side effect of the cascade-location question.

**Why it is not recommended here.** Right-shaped for a future where the
binary keeps absorbing mechanical logic, but wrong-sized for this decision:
it would make this design responsible for a `shirabe` release before either
half of this PRD's two-PR sequence (R22) could land, and the PRD's explicit
scope is silent on CLI changes. Noted as the direction of travel, not
adopted.

## Recommendation

**Option 3 — move `run-cascade.sh` (and `run-cascade_test.sh`) under
`skills/work-on/scripts/`, with `/execute` reaching it over a cross-skill
path exactly as it already reaches `work-on.md` and `plan-to-tasks.sh`.**

The decisive reason is not cost — Options 2 and 3 touch almost the same file
set — it is that Option 3 is the only relocation that follows the
dependency direction the repository has *already chosen twice* rather than
inventing a third shape for this one script. `/execute` already depends on
`skills/work-on/koto-templates/work-on.md` (guarded by
`assert-child-template.sh`) and on `skills/plan/scripts/plan-to-tasks.sh`
(unguarded); neither dependency runs the other way. Placing the cascade
script under `/work-on` makes `/execute`'s reach into it the *third* instance
of a pattern this repository has already built tooling for, rather than a
new category of "peer utility" (Option 2) that would be the first
non-generic, git-mutating business script to live in root `scripts/` — a
directory whose only current runtime inhabitants are explicitly
skill-agnostic and parameterized (`skill-preflight.sh`,
`validate-template-mermaid.sh`), and whose only other contents are CI-only
checks that never execute at agent runtime at all. Option 3 satisfies R5a's
literal acceptance criterion just as cleanly as Option 2 does — `/work-on`
ends up with zero references under `skills/execute/` either way — but it
does so by extending a legible, already-precedented shape instead of
creating a new one whose scope and future membership nothing in the
repository currently defines.

This amends `DESIGN-execute-skill.md` Decision 2 (E3) on two specific points,
both of which the decision record accompanying this design must state
explicitly per R5a's own text ("settled by the design... and recorded there
as an explicit decision"): (1) `run-cascade.sh` no longer lives under
`/execute`'s own directory — E3's "move `run-cascade.sh`... into /execute"
clause is reversed for the script (not for the orchestrator template or
prose, which stay in `/execute` per E3 unchanged); and (2) the
"Extraction — shared library both skills reference" alternative E3 rejected
(`DESIGN-execute-skill.md:98-100`) remains rejected and is not what this
recommendation does — no neutral, jointly-owned location is created; the
script is fully owned by `/work-on`, exactly as `work-on.md` is fully owned
by `/work-on` today, and `/execute` reaches it the same way it already
reaches that template: by cross-skill path, not by shared ownership.

## Open Questions

- **Should the new `/execute` → `/work-on` script path get a guard analogous
  to `assert-child-template.sh`?** The repository's own stated rationale for
  that guard — a missing/misresolved cross-skill path is "otherwise a silent
  failure at child-spawn time" — applies just as much to a missing
  `run-cascade.sh` at cascade time. The existing `plan-to-tasks.sh` path has
  no such guard, so the repository does not treat every cross-skill script
  reference as requiring one; whether the cascade path's higher blast radius
  (it commits and pushes) justifies the extra assertion is a design/plan-hop
  judgment call, not a call this decision needs to make.
- **Does the `WORK_ON_ALLOW_UNTRACKED_ACS` escape hatch travel with the
  script or stay conceptually tied to `/execute`?** E3 explicitly moved this
  allowance into `/execute` alongside the script (`DESIGN-execute-skill.md:
  101-104`); since the mechanism lives entirely inside `run-cascade.sh` itself
  (`skills/execute/scripts/run-cascade.sh:61-71`), it moves with the file
  under Option 3 with no special handling, but the decision record should
  say so rather than leave it implied.
- **Is `plan-to-tasks.sh` in scope for an assertion too, now that the
  cascade path is being added as a second guarded (or unguarded) reference
  into the same skill's directory?** Out of this PRD's stated scope (it is
  not one of the requirements), but worth flagging to whoever writes the
  decision record, since leaving one of three now-parallel cross-skill paths
  unguarded while a sibling gets a new guard is the kind of inconsistency a
  future reader will ask about.
