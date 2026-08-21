# Exploration Findings: koto-runs-commands

## Core Question

The koto-backed workflows shipped by shirabe (`/execute` and the `/work-on`
template it drives) hand the agent mechanical shell commands inside prose
instructions. If koto can execute deterministic commands itself when `koto next`
is called, the agent should receive judgment work, not mechanical steps. Is the
gap a missing koto capability, an unused one, or a mix — and what would a
happy-path-automated, guarded-fallback design need?

## Round 1

### Key Insights

**The capability exists, ships, and is used by nobody.** (lead-action-capability,
lead-empirical-probe) `default_action` is implemented end to end in koto —
YAML schema, compile-time validation, a fourth engine closure at
`src/engine/advance.rs:286`, process-group-isolated execution in `src/action.rs`,
a `default_action_executed` event, polling, and confirmation. It works in the
installed binary (`koto 0.11.6`, built 2026-08-17), verified by running it.
`default_action` appears **zero** times in the entire shirabe repo. This is an
unused capability, not a missing one.

**Nobody decided to skip it — it was dropped.** (lead-history) koto shipped
`default_action` via issue #71 / PR koto#75, merged 2026-03-23, as the core
mechanism of a design whose stated goal was eliminating ~42% of skill-instruction
lines. shirabe's `work-on` template was authored days later, in the same PR
chain, by the same author, and never used it — not even in its first commit. No
design, issue, or PR in either repo records a decision against it. Later
koto-unification designs stop mentioning it. There is no rejection to respect.

**The motivating example is blocked by output routing, not by execution.**
(lead-output-plumbing, lead-empirical-probe) koto runs
`git rev-parse --abbrev-ref HEAD` happily and captures `feature/some-branch\n`
into its event log. Then it throws it away: `src/engine/advance.rs:291` discards
the fields on the normal path. The value never reaches `{{VAR}}` substitution
(which only reads the one-time `WorkflowInitialized` event), never reaches the
context store (gate-readable, agent-writable only), and never reaches the
`koto next` JSON. Running the command was never the hard part.

**There is exactly one way to see action output, and it halts the workflow.**
(lead-empirical-probe P4) `requires_confirmation: true` produces
`{"action":"confirm","action_output":{"command":…,"exit_code":0,"stdout":…}}`.
So `action_output` is already a real field in the response contract — it is
simply populated on one stop reason only. The plumbing is half-built.

**A failing action is a complete no-op.** (lead-empirical-probe P6,
lead-fallback) An action exiting 3 does not stop the loop, does not appear in
the response, and does not affect any transition. The exit code is recorded in
the event log and influences nothing. `ActionResult::Executed` fires for every
exit code. The fallback the user described — "koto falls back to instructing the
agent when commands fail" — does not exist in any form. Only a separately
declared gate can halt, and gate evaluation drops stdout/stderr entirely
(`src/gate.rs:206-230`), keeping only the exit code.

**"Run in the wrong folder" is the default, not the risk.** (lead-guards,
lead-empirical-probe P8) Sessions are looked up by flat name under
`~/.koto/sessions/`, with no binding to the tree they were created in. The
action inherits the raw cwd of whoever invoked `koto next`. Proven: a workflow
initialized in `tmp/kototest` and advanced from `tmp/elsewhere` wrote its output
file into `tmp/elsewhere`. `working_dir` does not help — it is relative to that
same caller cwd, and `working_dir: ".."` escapes upward with no containment
check. `template_source_dir` is recorded in the session and looks like exactly
the anchor this needs, but it is used only for batch child-template lookup and
is never consulted by the action path.

**The real inventory is bigger than the one command that prompted this.**
(lead-execute-inventory, lead-work-on-inventory) `/execute` carries 53 distinct
agent-instructed shell commands: 26 mechanical, 11 mixed, 2 judgment, 14
koto-protocol. `/work-on` carries ~37 instruction sites: 26 koto-protocol, ~14
mechanical, the rest judgment or mixed. The line the user quoted is real and
nearly verbatim at `skills/execute/koto-templates/execute.md:353`.

**koto already runs shell in these templates — as gates.** (both inventories)
`/work-on` declares 8 `type: command` gates (branch check, commit count, test
run, CI polling, staleness) and `/execute` declares 3. koto executes these
autonomously on every `koto next`. So "koto runs commands on the happy path" is
already half-true for *checks*; only *actions* are still 100% prose. This also
creates a duplication risk: `ci_passing`'s `gh pr checks` pipeline is nearly the
same query a `ci_monitor` action would run.

**The densest mechanical concentration is not git plumbing — it is koto's own
retry bookkeeping.** (lead-work-on-inventory) Eight near-identical blocks across
verification, analysis, implementation, all three review panels, and
finalization instruct the agent to run the same deterministic 4-key
`koto context remove` / `koto context exists` loop with a hard `exit 1`, then a
fixed `koto next --with-data`. This exists in prose only because koto has no way
to clear its own context on a retry transition.

**Adoption means authoring conventions from scratch.** (lead-authoring)
koto-author's SKILL.md and template-format.md give `default_action` one table
row: no schema, no example, no gate-vs-action guidance. The only working example
in the whole repo is a Rust integration test
(`tests/integration_test.rs:3846`). The SKILL.md action-dispatch table does not
even list the `confirm` value that `default_action` produces. Compile-time
validation is real (integration/action mutual exclusion, empty-command
rejection, `{{VAR}}` checking, polling-timeout floor) but the action sub-struct
silently accepts unknown fields.

**No version blocker.** (lead-authoring) shirabe pins no koto floor and installs
latest; the shipped binary already has the feature.

### Tensions

- **Execution is solved; everything around it is not.** The engine runs commands
  safely (process group, timeout, kill, 64KB truncation, and a genuinely
  enforced allowlist that blocks shell injection through `--var`). But it cannot
  tell anyone what happened, cannot react to failure, and cannot be pinned to a
  directory. Adopting the feature as-is buys automation and loses observability.

- **The inventories assume an ability the probe disproves.** Both inventory
  leads flag the MIXED bucket as convertible "if `default_action` can populate
  evidence fields from command output." It cannot: step 5 does not merge action
  output into `current_evidence` before gate evaluation. So the 11 MIXED
  commands in `/execute` are blocked on a koto change, not on template authoring.

- **`requires_confirmation` promises a guard and delivers a receipt.** The
  design's safety story is "only reversible actions auto-execute; irreversible
  ones require confirmation." As implemented the command executes first and the
  agent is consulted afterward — proven by the confirmation response carrying
  the command's stdout. For `gh pr create` that means the PR exists by the time
  anyone is asked. Whether this is deliberate (confirm the *result* before
  advancing) or a defect against stated intent is unresolved.

- **Two safety asymmetries inside one feature.** `command` gets shell-escaped
  variable substitution; `working_dir` gets unescaped substitution (koto issue
  #186). One-shot actions are hard-capped at 30s with no template override,
  while polling actions require an explicit timeout; the design's required
  maximum-timeout cap was dropped without being marked deferred.

- **Automating koto's own protocol calls is a different feature.** The 26
  koto-protocol sites in `/work-on` cannot become `default_action` — `koto init`
  and the `koto next` loop bootstrap and drive the machine itself. But the
  retry-clearing blocks are koto talking to koto through the agent, which argues
  for an engine-side transition hook rather than an action.

### Gaps

- No mechanism exists for conditional instruction text. `TemplateState.directive`
  is one static string per state, rendered identically on every stop reason, so
  "prose only when the automated attempt failed" has no primitive behind it. The
  three-path model in `DESIGN-shirabe-work-on-template.md` is a target for a
  template that was never written, not something koto implements.
- Nothing prevents an action from running twice — no idempotency check, and
  concurrent `koto next` calls on a non-batch session are deliberately unlocked
  (`src/cli/mod.rs:3836-3848`), a decision reasoned about purely as state-file
  write safety without noticing it also double-fires arbitrary shell.
- `DESIGN-template-evidence-routing.md` was not read in round 1 and may bear on
  whether action output can be routed into evidence.
- Whether `koto status` or any projection can retrieve the last
  `default_action_executed` event for the current state is unverified.
- No concrete per-state conversion map exists yet for either template — the
  inventories classify commands but do not say which koto state gets which
  action, nor in what order the work would land.

### Decisions

Recorded in `wip/explore_koto-runs-commands_decisions.md`.

### User Focus

Running in `--auto`: the user's brief is the standing focus — map every place
commands are hardcoded across the workflow, the main skill file, and references;
determine what is needed and what is possible; insist that happy paths run
automatically and that guards be strong enough that a command never runs against
the wrong tree.

## Accumulated Understanding

The problem the user noticed is real, and it is not primarily a shirabe
authoring failure. It splits cleanly in two.

**The adoption half is shirabe's.** koto can run commands today, shirabe's
templates run none, and no one ever decided against it. A meaningful slice of
the inventory — the mechanical git/gh plumbing in `/execute`, the
`extract-context.sh` invocation in `/work-on` phase 0, the branch and slug
derivation repeated five times in one template — could be converted with
today's primitives and would remove agent turns from the happy path immediately.

**The enabling half is koto's, and it is what the user's stated target design
actually requires.** Three specific things are missing, and each one blocks a
distinct part of the goal:

1. *Output routing.* koto captures the command's stdout and discards it. Until
   an action's result can reach the agent, a later state, or a gate, every
   command whose value is its output — which is most of the interesting ones —
   has to stay with the agent. `action_output` already exists in the response
   schema, populated on exactly one stop reason, which makes this the cheapest
   of the three to fix.
2. *Failure propagation.* An action's exit code influences nothing. The user's
   design ("fall back to the agent only when the command fails") cannot be
   expressed at all: today a template author must pair every action with a gate
   that independently re-checks the same condition, which doubles the command
   count and still hides the reason for failure, since gates keep only exit
   codes.
3. *Execution anchoring.* The action runs wherever `koto next` was called from.
   For read-only commands that is a correctness annoyance; for
   `git checkout -b`, `git push`, `gh pr create`, and the finalization cascade
   it is the exact hazard the user named. The session already records
   `template_source_dir` and simply does not use it for this.

The ordering follows from that: koto's three gaps are the enabling work, and
shirabe's template rewrite is the payoff. A narrow shirabe-only adoption of the
safe subset is possible first, but the bulk of the inventory stays with the
agent until koto can route output, react to failure, and pin a directory.

## Round 2

### Key Insights

**The target design is reachable today, and I verified it running.** (lead-template-patterns, r2 probe P15) A state carrying a `default_action`, a command gate that independently checks the outcome, and a transition keyed on `gates.<gate>.exit_code: 0` auto-advances silently on success — koto created the branch, the agent never saw the state or its directive. On failure the same state returns `action: "evidence_required"` with the directive written as manual-recovery prose, the gate's exit code in `blocking_conditions`, and an `expects` schema for the override. Three paths, one state, zero koto changes.

One correction to the pattern as first proposed: it does not compile if one transition is keyed on a gate and another on `status`. The compiler rejects `when` blocks that share no fields ("transitions share no fields, so both could match the same evidence"), which is why `work-on.md`'s real states repeat `status` in every branch. The working form repeats the gate field instead: `{gates.X.exit_code: 0}`, `{gates.X.exit_code: 1, status: override}`, `{gates.X.exit_code: 1, status: blocked}`.

**A related safety property already exists.** (lead-template-patterns) The action closure skips execution entirely when the agent submits evidence in the same call (`has_evidence` → `ActionResult::Skipped`). So koto will not re-run `git checkout -b` on top of an agent's manual fix. Override safety is automatic, not something the author engineers.

**There is a live deadlock in the layer both gates and actions share.** (r2 probe P11-P13) `run_shell_command` spawns with piped stdout/stderr, calls `wait_timeout`, and only then reads the pipes. Any command writing more than the 64KB pipe buffer blocks forever and dies at the timeout with its output discarded. Measured with plain `tr`: 60KB captured, 70KB stalled 30 seconds and returned exit -1 and empty output. Stderr triggers it as readily as stdout.

This is not a `default_action` problem. Gates have it too, verified: a gate command that exits 0 but emits 200KB was reported as `{"status":"timed_out","output":{"exit_code":-1}}` after a 30-second stall — a passing check turned into a false failure.

**Severity, corrected in round 3.** My first reading called this a live bug in shipped templates. The accurate statement is narrower. Only one of shirabe's eleven gates (`tests_passing`) writes captured stdout at all — the other ten use `test`, `[`, `grep -q`, or `$(...)` substitution, which produce no top-level output; an accidental property of idiomatic gate-writing rather than a defense. And measured on the tsuku monorepo, `go test ./...` across 63 packages emits 3,793 bytes, far under the trigger. The defect is confirmed and real but is not firing at today's scale: latent, not an active outage. What makes it matter is expansion — a failure dump, a verbose linter, or any nested koto command crosses the threshold at once.

**koto cannot call koto, for the same reason.** (r2 probe P13) Every session-touching koto command emits about 106KB of `migration skipped` warnings on stderr in this workspace — one line per session, roughly 1,250 of them — so it deadlocks itself inside an action. `koto version`, which emits nothing, runs in 0.06 seconds. This corrects an earlier reading of the same evidence as a lock: redirecting the nested command's output to files makes it work. Two defects stacked, both worth fixing: the un-drained pipe, and koto's warning volume. The noise half is already tracked as koto issue #193, filed from a different angle — log noise during direct CLI use — with no mention of the deadlock this exploration connects it to.

**`context_assignments` is silently discarded, and shirabe's templates use it 28 times.** (lead-transition-hooks, verified by probe) A transition declaring `context_assignments: {failure_reason: "..."}` writes nothing — the key is absent afterward. `work-on.md` uses it 19 times, `execute.md` 9. Every blocked and escalation path that was supposed to record why it stopped records nothing, `/execute`'s `done_blocked` state tells the agent to read a key that will never exist (`execute.md:649`), and the batch view's per-child reason falls back to the state name. koto's own W5 compiler warning fires on those states anyway and its remedy text recommends the mechanism that does not work. Filed as koto issue #204 on 2026-08-20.

**Output routing has a clear smallest answer.** (lead-output-routing) A `capture_stdout_as:` field on `ActionDecl`, emitting an additive `VariableCaptured` event folded into the existing `Variables::from_events` path, satisfies the motivating case — a later state's directive text interpolating the captured branch name — while touching no response field, no hand-rolled `Serialize` arm, and none of the exhaustive-match combinators that make contract changes expensive. It needs one care point: `Variables` must be rebuilt after the advance loop rather than before, or it silently misses exactly the auto-advance-in-one-call case it exists for. Populating `action_output` on every stop reason looks smaller and is not — once auto-advance chains through several states, the acting state and the stopping state diverge, forcing the field through five variants and three combinators.

**Failure semantics need plumbing, not schema.** (lead-failure-semantics) The design never intended non-zero exit to halt; gates are the arbiter, which the only real example (`touch` then `test -f`) demonstrates. So no `on_failure:` field is needed. The genuine gaps are that `GateBlocked` and `EvidenceRequired` never carry the action's output, and that a state with an action and no gates has no failure detection at all — which is what the round-1 `exit 3` probe actually exposed. Two additive changes cover it: thread `action_output` through those two variants, and synthesize a fail-on-nonzero result only for the gate-less case.

**Anchoring has a concrete design, and the worktree fear was unfounded.** (lead-anchoring) `koto next` recomputes `std::env::current_dir()` fresh every tick and feeds it unchecked to both closures at one choke point in `handle_next`; `template_source_dir` is the template file's directory, not the working tree. Despite its name, `worktree_discipline_check` does an in-place fetch and rebase — shirabe never relocates a running session between worktrees. So the design does not need to tolerate cwd drift as normal, only refuse it: record a canonicalized `execution_root` at `koto init`, refuse to run any gate or action when the live cwd does not canonicalize to it, resolve `working_dir` by joining and canonicalizing under that root (which closes the `..` escape and the unescaped-substitution asymmetry of koto issue #186 in one change), and add an explicit `koto session bind` verb for the legitimate re-anchor case.

**The retry bookkeeping needs epoch-scoped context.** (lead-transition-hooks) The eight blocks are one shell template copied seven times, and they exist because the context store is the only per-state artifact that is not epoch-scoped — evidence, gate overrides, and gate output all are, using an `epoch_slice` mechanism koto already has, and the event log already carries the `ContextAdded`/`ContextRemoved` events needed to apply it here.

**Yields are smaller than the inventories implied.** (lead-map-execute, lead-map-work-on) `/execute`: of 12 states, five have nothing to convert and one should have a duplicate read deleted rather than converted; roughly 19-20 commands convert today, another 8-10 after the koto changes. The design's ~42% claim holds for both waves combined, overstates the first wave alone, and has a practical ceiling nearer 79% because 11 of the 53 commands live in SKILL.md, outside any state's reach. `/work-on`: of 24 states, three sites convert today at low risk.

### Tensions

- **The central disagreement of the exploration.** The template-patterns lead says the target design works today and is cheap. The counter-case lead says it is right for exactly one state (`ci_monitor` polling) and wrong nearly everywhere else. Both are well-evidenced and they are arguing about different things: the pattern is available, and the *candidates* are worse than the inventories suggested. The two maps land between them and closer to the counter-case.

- **The permission-bypass argument is the strongest objection raised, and it goes straight at the user's own stated concern.** A `default_action` runs `sh -c` from the koto binary, not through the agent's Bash tool. So a user's allow/deny/ask rules for `git push` or `gh pr create` never see it — the command is an opaque side effect of one `koto next` call. The only valve is `requires_confirmation`, which the design itself says the template author is responsible for setting correctly, and which round 1 showed fires *after* execution. A user who asked for hard guards against unintended side effects would likely count "moves the decision from my permission config to a template author's judgment" as a step backwards.

- **The states the design targeted are the wrong ones.** `DESIGN-default-action-execution.md:41` names `setup_issue_backed` and `setup_free_form`. Their branch step is a decision tree (reuse `SHARED_BRANCH`, reuse the current feature branch, or create), and their baseline step says outright to use project-specific commands from CLAUDE.md or the language skill. Neither is a fixed string.

- **The one gate that already does what actions promise is already broken across environments.** `tests_passing`'s `[ ! -f go.mod ] ||` guard reports pass for every repo without a root `go.mod` — Rust, JS, a Go monorepo with nested modules, anything using `make test`. "Tests passing" can be true when no test ran. This is what a compiled command string does when the plugin ships to many repos, and actions inherit it exactly.

- **The strongest pro-conversion case argues against the mechanism.** `ci_monitor` polling is the cleanest candidate, and koto's own design says the right long-term home for CI monitoring is a typed integration rather than `default_action`, because an action's output is just a shell string to parse.

- **A prior incident cuts both ways.** `BRIEF-skill-preflight-checks.md` records twelve child workflows dispatched against a branch nobody created, because a koto subcommand that does not exist had its error filtered away. That happened with the *agent* running the command in prose — so agent visibility is no guarantee. But the recovery came from the prose paper trail, which is exactly what a conversion deletes.

### Gaps

- No one has swept the 64KB deadlock across all 11 existing gates to rank real exposure, or sized the fix.
- The counter-case's middle path — restrict actions to read-only, side-effect-free commands and leave side-effecting work to scripts and prose — is proposed but not evaluated against the two maps.
- Whether any mechanism could keep a user's permission layer in the loop for engine-run commands is unexamined.
- Rounds 1 and 2 inventoried `/execute` and `/work-on`. Nothing has checked for instruction surfaces elsewhere: the repo-root `koto-templates/` directory named in shirabe's CLAUDE.md, `plan-to-tasks.sh`, other skills' scripts.
- No dependency-ordered, sized work list exists across the two repos.

### Decisions

Appended to `wip/explore_koto-runs-commands_decisions.md`.

### User Focus

Unchanged and standing: map every hardcoded command, determine what is needed and what is possible, insist the happy paths run automatically and that the guards be strong enough that a command never runs against the wrong tree.

## Round 3

### Key Insights

**The disagreement dissolved, and the answer is granularity.** (lead-middle-path)
The two round-2 leads were never testing the same claim. Template-patterns
proved a mechanism works, using a synthetic `create_branch` state. The
counter-case argued about the states the design actually names, and its
citations check out: `phase-1-setup.md`'s "Create Feature Branch" is a decision
tree (reuse `SHARED_BRANCH`, reuse if the user said to continue, reuse if
already on a feature branch, create otherwise), and "Establish Baseline" says to
use project-specific commands from CLAUDE.md or the language skill. Both are
true. The primitive works; today's states are the wrong unit. Conversion has to
happen at isolated sub-step granularity, which means splitting states, not
annotating them.

**The permission-bypass objection holds, and there is no mitigation inside
koto.** (lead-middle-path) Verified: `default_action` runs `sh -c` as a direct
child of the koto binary, never through the agent's tool layer, so a user's
allow/deny rules never see it. `requires_confirmation` fires only after the
command has run and been logged. No preview-before-execution mechanism exists
anywhere in koto, and building one would reproduce shirabe's current
prose-plus-Bash-plus-gate pattern under a new name. This is a real constraint,
not a hypothetical.

**The read-only restriction is too blunt.** (lead-middle-path) Applied line by
line, it zeroes out `/execute`'s entire current Wave A — both candidates are
writes-remote — and cuts `/work-on`'s to between one and three sites depending
on whether koto-store writes count as side effects. It is also unenforceable at
compile time; only convention or a lint could carry it.

**A usable principle came out of it.** (lead-middle-path) Run a mechanical step
through koto when it is isolated to its own state, gate-verifiable independent
of the action's own exit code, and either read-only or a repo-local mutation
that is safe to reach twice. Anything that mutates a remote — push, PR create or
edit, the finalization cascade — or needs project-specific configuration to know
what to run stays agent-run, because that is the surface where both the user's
permission layer and a developer's judgment still get to see it first.

**The brittleness objection is half-solvable today, in shirabe alone.**
(lead-middle-path) `koto init --var` already exists and both templates already
use `{{VAR}}` substitution throughout. A `TEST_COMMAND` variable, resolved once
by the agent at session start from CLAUDE.md or the language skill, would replace
the per-state re-derivation that happens at least twice per `/work-on` run. What
it does not fix is the shipped `tests_passing` gate, which hardcodes
`[ ! -f go.mod ] || go test ./...` with no variable at all — a live false-pass
for every repo without a root `go.mod`.

**The inventory was complete for the koto question and incomplete for the user's
literal one.** (lead-completeness) `/execute` and `/work-on` are the only two
koto-backed skills in the workspace, so `default_action` is structurally inert
everywhere else — rounds 1 and 2 covered the whole surface that matters for it.
But eighteen other skills carry real hardcoded-command surface nobody opened:
`/inflight` (missed entirely, instructs `shirabe work-summary track <pr-url>`),
`/release`'s four non-koto shell blocks, `/roadmap`'s two `shirabe roadmap
populate` forms, `/plan`'s `gh issue list`, `/explore`'s own `gh issue view`, and
a `shirabe transition` / `shirabe validate` pattern copy-pasted independently
into eight artifact-lifecycle skills — 23 files carry `shirabe transition`, 48
carry `shirabe validate`. None of that is reachable by koto automation; the
duplication is worth flagging on its own terms.

**shirabe's own linter already knows about `default_action`.**
(lead-completeness) `scripts/check-template-interpolation.sh` explicitly checks
shell-interpolation defects "in a gate command or a default_action command", and
its test file carries a `default_action:` fixture. The validation infrastructure
for adoption exists and is dormant.

**There is one documented decision after all, and it is narrow.**
(lead-sequencing) `docs/designs/current/DESIGN-work-on-retry-clearing.md`, status
Current, is the design authority for the eight retry-clearing blocks. It chose
manual clear-and-verify deliberately, reasoning that a uniform superset-clearing
rule beats a per-edge mechanism, at a time when `context_assignments` was
unimplemented. No round-1 or round-2 lead cited it. This does not contradict
round 1's finding that nobody decided against `default_action` — it is about the
retry blocks specifically — but it turns "koto should just do this" into a
shirabe design reversal that has to be argued, not assumed.

**The migration spam has a five-line root cause.** (lead-sequencing)
`src/session/local.rs:657-719`: when a session's flat-layout copy already exists,
the old-layout entry is never moved out, so `old_dir` stays non-empty, so
`fs::remove_dir(&old_dir)` at line 717 fails silently behind `let _ =`, so the
same ~1,250 warnings print again on the next invocation, forever.

**Anchoring is the item that most directly answers the user and depends on
nothing.** (lead-sequencing) The guard belongs at one choke point in
`handle_next`, before `current_dir` feeds either the gate or the action closure —
structurally clean for a large-sounding feature. Its size is in the design
questions (default behavior, pre-existing sessions, equality versus containment),
not the blast radius. And it guards gates too, which run against the same
unguarded cwd today, so it pays off whether or not a single state is ever
converted.

### Tensions

- **The strongest work is not the work the exploration set out to find.** The
  two highest-priority items — the pipe-buffer deadlock and the migration spam —
  are live defects in mechanisms shirabe already ships, and the item that most
  directly answers the user's stated concern is execution anchoring, which is
  independent of `default_action` entirely. The conversion project the question
  implied is real but is neither the largest nor the most urgent thing found.

- **The conversion yield swings on one defect fix, not on new capability.**
  The `/execute` estimate moved three times as the nested-koto diagnosis was
  corrected, settling on a range: 15% (8 of 53 commands) convert today with no
  koto change; **62% (33 of 53) once the pipe-drain and migration-warning
  defects are fixed**, because that single fix reopens the 25 commands whose
  whole purpose is a koto context read or write; 70% with a further
  evidence-consumption capability `pr_finalization` needs; and a ceiling near
  79%, since 11 of the 53 live in SKILL.md where no per-state action reaches
  them. So the design's original ~42% claim fails today and is comfortably
  exceeded after a defect fix rather than after a feature. The counter-case's
  candidate-quality objections still apply on top of these numbers — reachable
  is not the same as advisable.

- **Converting before the plumbing lands makes things worse, not better.**
  Without `action_output` on the failure path, a converted state trades a
  debuggable agent-run command for an opaque gate exit code. That is the exact
  silent-failure shape that already cost twelve misdirected child workflows once.

### Gaps

- The `koto next` outer-invocation staleness defect found by the map lead is
  reproduced but not filed anywhere.
- Whether koto-store writes count as side effects under the recommended
  principle is unresolved, and it is the hinge for `/work-on`'s remaining yield.
- Who owns revisiting `DESIGN-work-on-retry-clearing.md` is an open question the
  exploration cannot answer for the author.

## Accumulated Understanding

The question was whether this is a missing koto feature or poor koto use in
shirabe. The answer is neither, exactly, and the exploration turned up something
more urgent than the thing it was sent to look at.

**On the original question.** koto's `default_action` has shipped since March
and shirabe has never used it, with no decision recorded anywhere. The shape the
problem statement describes — koto runs the command, the agent is handed prose
only when it fails — works today, verified running: an action, a gate that
independently checks the outcome, and a transition keyed on the gate's exit code
auto-advances silently on success and returns `evidence_required` with the
fallback directive on failure. So the mechanism is not missing.

What is missing is everything around the command. koto captures the output and
discards it, so the specific example that prompted this — running
`git rev-parse --abbrev-ref HEAD` to get the branch — is blocked not by
execution but by the fact that the value has nowhere to go. A failing action
changes nothing at all; only a separately declared gate can stop the loop, and
gates keep exit codes and drop the text. And the command runs in whatever
directory `koto next` was called from, which is the hazard the user named,
present as the default rather than as an edge case.

**On what should actually be converted.** Less than the inventory first
suggested. The states the original design named bundle mechanical work with
genuine judgment — which branch to reuse, which test command this repo uses — so
conversion means splitting states rather than annotating them. Outward-facing
commands carry a further cost the user would care about: an engine-run `git push`
or `gh pr create` never passes the agent's tool layer, so the user's own
permission rules never see it. The defensible line is that koto runs a step when
it is isolated, independently checkable, and either read-only or a repo-local
mutation safe to run twice; everything that touches a remote or needs per-repo
configuration stays with the agent.

**On what turned up along the way.** Two defects that have nothing to do with
this decision. `run_shell_command`, shared by gates and actions, waits on the
child before draining its pipes, so any command emitting more than 64KB
deadlocks and is killed at the timeout with its output discarded — a passing
check reported as a failure, evidence gone. Measured honestly it is latent
rather than firing: only `tests_passing` writes captured output at all, and
`go test ./...` on the tsuku monorepo emits under 4KB. It trips on a failure
dump, a verbose linter, or any nested koto command. Separately, koto emits
roughly 106KB of migration warnings per session-touching command because a
cleanup step fails silently on the skip branch — already filed as koto issue
#193 — and that is what would make the deadlock self-inflicted the moment koto
commands are nested inside koto-run gates or actions, which is exactly the
expansion this exploration is weighing. Both fixes are contained: the drain is
roughly 100-150 lines in one function plus tests, the migration cleanup a few
lines.

Alongside those: `context_assignments` is silently discarded while shirabe
declares it 28 times, so every blocked path that was supposed to record why it
stopped records nothing, and koto's own compiler warning recommends the broken
mechanism.

**Where that leaves the work.** Fix the defects first — the pipe drain, the migration spam, the inert
declarations, the duplicate CI read, the repeated slug derivation. The first two
come first not because they are burning today but because every expansion of
what koto runs makes them load-bearing, and because the drain fix alone
quadruples what is convertible. Then anchor execution, which is the direct answer to
the user's guarding requirement and is worth doing whether or not anything is
ever converted. Then the small plumbing that makes a converted step diagnosable:
action output on the failure path, and failure detection for a gate-less action.
Then, and only then, convert the set of steps that pass the principle, starting
with the ones that need no new capability. Note what the numbers say about
ordering: the drain fix is worth more to conversion reach than any feature on
the list, because most of what looked unreachable was only unreachable through
it. `capture_stdout_as` and the
retry-clearing question come after, the latter behind a shirabe design decision
that has to argue against a doc already marked Current.
