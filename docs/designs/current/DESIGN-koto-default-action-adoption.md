---
schema: design/v1
status: Current
upstream: docs/prds/PRD-koto-default-action-adoption.md
problem: |
  shirabe's three koto-backed templates hand the agent every mechanical shell
  command in prose. koto has run commands on state entry since March 2026 and
  shirabe has never used it, so mechanical steps cost turns, arrive as requests
  rather than guarantees, and throw away the values they compute.
decision: |
  Four steps convert, each into its own state carrying a default_action whose
  outcome an independent gate checks: the branch read that opens a /scope run,
  the settled-branch record and the shared-branch rebase in /execute, and the
  branch read before /work-on opens a pull request. Command bodies longer than
  one clause live in a script the action invokes. A fifth change deletes five
  re-derivations of a variable /execute already declares.
rationale: |
  The convertible shape is narrow and mechanical: the command must exit
  non-zero when it fails, must leave a trace some other command can check, and
  must be safe to run again. Every candidate that failed one of those is
  recorded with the reason rather than left out, because an absent step and an
  overlooked one look identical.
---

# DESIGN: Adopting `default_action` in shirabe's koto templates

## Status

Current

## Context and Problem Statement

`PRD-koto-default-action-adoption.md` settles what has to be true of a
converted step. This design settles which steps convert, where the states
split, and where the command bodies live.

The technical problem is narrower than "adopt a capability". koto's engine will
run any string an author puts in `default_action`, so nothing stops adoption
mechanically. What is missing is a boundary. The prior exploration of this
question produced two per-state maps whose conversion counts were computed
against koto 0.11.6, where two defects in the runner shared by gates and
actions were live: a command emitting more than the pipe buffer deadlocked and
lost its output, and koto's own migration warnings pushed any nested `koto`
call past that threshold on the first try. Both are fixed in 0.12.1, along with
the two gaps that mattered more: a command's stdout can now reach later states
under a declared name, and a failing action stops the tick and hands the agent
the command's own output. Those maps' numbers are floors, and several rows they
marked unreachable are reachable now.

Reaching for all of them is the wrong response. Every conversion is a worked
example a future author copies, so the cost of a bad one compounds. This design
converts four steps and records eleven that stay, with the reason each stayed.

## Decision Drivers

- **A converted step must be diagnosable when it fails.** koto delivers the
  command, exit status, stdout, stderr, a typed `failure_kind`, and the state's
  `fallback` prose in the response that stopped. A command that cannot fail
  loudly gets none of that.
- **A gate must be able to disagree with the action.** If the only evidence a
  step ran is the step's own exit code, converting it buys automation and sells
  assurance.
- **The action re-runs on every entry without evidence.** Gate-blocked retries
  and self-loops both re-enter, so a command that is not safe twice is not a
  candidate.
- **The repository's own linter constrains the command text.**
  `scripts/check-template-interpolation.sh` fails any `command:` containing
  `$NAME` or `${NAME}`, because it cannot tell an author's mistaken
  template-variable reference from a legitimate shell variable.
- **A capture is one line of restricted characters, and reading one the run
  never produced is a hard stop.**
- **Each individual run gets 30 seconds and the limit is not configurable.**

## Considered Options

### Decision 1 — What shape must a step have before it may become a `default_action`?

**Option A (chosen): the koto rule, plus two shirabe-side filters.** koto's
`docs/guides/default-action-authoring.md` supplies the rule: keep
`default_action` off any command whose *successful* exit is itself the
irreversible, externally visible event; allow it where the only irreversibility
is bounded and repairable. shirabe adds two filters that the koto rule does not
speak to because they are consequences of koto's response shape rather than of
the command:

1. **The command must exit non-zero when it fails.** A command that always
   exits 0 can never reach the failure path, so its diagnosis has to come from
   stdout, which a *successful* action discards. Converting such a command
   makes its failures less visible than they are today.
2. **The command must leave a trace some other command can check.** Otherwise
   the state cannot satisfy the PRD's R3, and the only available gate is one
   that re-runs the action, which is the circularity R3 exists to forbid.

**Option B: the koto rule alone.** Rejected. It is a rule about authorization,
not about diagnosability, and it clears commands whose conversion would lose
information. `extract-context.sh` is the worked case: read-only against the
world, writes one koto context key, and passes koto's rule cleanly. It also
documents `Exit codes: 0 - Always`, so a failure reaches the agent today as
readable stdout and would reach it after conversion as a blocked gate with an
exit code and nothing else.

**Option C: restrict to read-only commands.** Rejected, and it was proposed in
the prior exploration. Applied line by line it zeroes out the strongest
candidate in this design — the settled-branch record, whose whole point is
writing a key an existing gate already checks — while admitting reads that
leave no trace to gate on. It sorts commands by a property that does not track
the risk.

### Decision 2 — How is a converted step isolated from the judgment beside it?

**Option A (chosen): split the state; the mechanical step gets its own.** The
states that hold shirabe's mechanical work hold judgment too.
`/scope`'s `setup` validates a slug, writes a state file, and confirms the
branch. `/execute`'s `orchestrator_setup` decides create-versus-adopt, runs a
creation script, and records the settled branch. Each split puts the mechanical
step in a state whose gate names exactly what that step was supposed to
achieve.

**Option B: annotate the existing state.** Rejected. A state doing two things
has two outcomes, and a gate can only establish one. Annotating
`orchestrator_setup` would leave its existing `settled_branch_recorded` gate
unable to say whether it is judging the creation script or the record.

**Option C: leave the state alone and add the action to the state after it.**
Rejected. It reads as isolation and is not: the following state's own gate then
judges two steps, and the failure prose for the borrowed step lands on a state
whose directive is about something else.

### Decision 3 — Where does a converted command's body live?

**Option A (chosen): one clause inline, anything longer in a script.** A
command that is a single invocation with no shell variables goes in the
template. A command that needs to read a value, validate it, and store it goes
in a script under the skill's `scripts/` directory, and the action invokes that
script with `{{KEY}}` arguments.

Two reasons, and the second is the one that decides it. The linter fails any
`command:` containing `$NAME`, so an inline body cannot hold a local shell
variable at all — `B=$(git rev-parse --abbrev-ref HEAD)` followed by `"$B"` is
rejected. And a script is testable: shirabe already carries
`skills/execute/scripts/settled-branch-record_test.sh`, which today pulls live
shell out of the template to test it, and which a real script lets test a real
file.

**Option B: everything inline.** Rejected on the linter alone. Working around
it would mean either weakening the linter — it is the check that would catch a
genuinely mistaken `$PLAN_SLUG` in an action — or writing the command as a
chain of substitutions with no intermediate values, which is unreadable inside
a YAML scalar.

**Option C: everything in scripts.** Rejected as ceremony. `git rev-parse
--abbrev-ref HEAD` does not need a file, and putting it in one hides what the
state does from anyone reading the template.

### Decision 4 — Where must a state that produces a captured value sit?

**Option A (chosen): above every state that reads the value, on every path.**
Reading a capture the run never produced stops the run with `capture_unset` and
exit 3. It is not an empty render and not a warning. So the producing state has
to be one every path into every reading state passes through.

This is a placement constraint with teeth in `/work-on`, which has three entry
modes converging at `analysis`: a branch captured inside one mode's setup state
would break every run that took another mode. The two placements this design
uses are both trivially safe — `/scope`'s producer is the initial state, and
`/work-on`'s sits on the single edge into `pr_creation`.

**Option B: produce the value where it is first computed and read it where
convenient.** Rejected. It is the shape that produces the `capture_unset` stop,
and the failure surfaces at the reading state on some runs and not others.

### Decision 5 — Which steps convert in this pass?

**Option A (chosen): four, each of the shape Decision 1 describes.** Listed in
Solution Architecture below.

**Option B: convert the whole reachable set.** Rejected. The corrected
per-state maps put roughly two dozen further sites within reach now that the
runner defects are fixed, most of them `koto context` reads and writes inside
`/execute`'s `spawn_and_await`. Reachable is not advisable: `spawn_and_await`
assembles the child task list, and its assembly is interleaved with the
`koto next --with-data` submission that koto now refuses to run from inside an
action. Converting the readable half would split one block across an action and
prose that has to agree with it.

**Option C: convert one, as a proof of concept.** Rejected. One conversion
demonstrates the mechanism and settles nothing about the boundary, which is the
part a future author needs. Four span the three shapes that recur: a read whose
value is captured, a write an existing gate already checks, and a local
mutation whose effect a gate can confirm independently.

### Decision 6 — How does a converted state keep an escape without costing a turn?

**Option A (chosen): three transitions, all keyed on the gate's exit code.** A
state that auto-advances on success and still lets the agent take over on
failure needs both a gate-only edge and evidence-keyed edges. koto's compiler
rejects a state whose `when` blocks share no fields, so an evidence-only edge
beside a gate-only edge does not compile. Repeating the gate field in every
branch is what makes them mutually exclusive:

```yaml
transitions:
  - target: <next>
    when:
      gates.<gate>.exit_code: 0
  - target: <next>
    when:
      gates.<gate>.exit_code: 1
      status: override
  - target: <blocked>
    when:
      gates.<gate>.exit_code: 1
      status: blocked
```

Verified against the shipped binary. On the passing path the state advances
with no evidence at all and the agent never sees it. On the failing path the
response carries the gate's exit code and the full `expects` schema, so the
agent is told what to submit even though an action *failure* response is not.
The `accepts` fields are optional, which is what keeps the happy path free of
them.

**Option B: no `accepts` block at all.** Rejected. It is the shape that gives
the cleanest auto-advance and it leaves a state with no exit when the gate will
not pass. `/execute`'s own template makes this point about the blocked edge on
`orchestrator_setup`: the failure exit has to stay reachable when the thing
that is broken is exactly what the gate reads.

**Option C: require evidence on every path.** Rejected. It works and it costs
the turn the conversion existed to save.

### Decision 7 — How does a koto-run command name a script that ships in the plugin?

**Option A (chosen): a `PLUGIN_ROOT` template variable on `/execute`.** The
skills' prose reaches their scripts through `${CLAUDE_PLUGIN_ROOT}`, which the
agent's own shell expands. A koto-run command cannot: koto does not resolve
shell variables, and `scripts/check-template-interpolation.sh` fails the field
for exactly that reason. So `/execute` declares `PLUGIN_ROOT` and its `koto
init` passes `--var PLUGIN_ROOT=${CLAUDE_PLUGIN_ROOT}`, where the agent's shell
expands it once, and the action reads `{{PLUGIN_ROOT}}`.

This is the same argument the template already makes for `PLAN_SLUG`, whose
frontmatter comment says it is declared "because the `worktree_discipline_check`
gate interpolates it into a command koto runs itself" and a shell-style
reference "is passed to sh -c untouched and expands to the empty string." A
plugin root is the same case.

Only `/execute` needs it, because C2 is the only conversion whose body is long
enough to warrant a script. `/work-on` and `/scope` keep their init contracts
unchanged.

**Option B: a repo-relative script path.** Rejected, though `/scope` already
does it — its hop gates run `skills/scope/scripts/hop-complete.sh`, which
resolves against the execution anchor and therefore only in a checkout of
shirabe itself. That works where shirabe is the repository being worked on and
silently fails with exit 127 anywhere else. Copying it would spread the defect
rather than the pattern.

**Option C: keep the command inline and drop the script.** Rejected on quality
rather than on mechanism. An inline form exists — pipe the branch through two
`grep` filters into `koto context add` and read it back for the capture — and
it works, because a pipeline reports its last command's status. What it cannot
do is say what went wrong: a run on `main` reaches the agent as a capture that
came back empty, not as a refusal to record the default branch. The script's
whole value is the diagnosis.

## Decision Outcome

Four steps convert, one duplication is deleted, and the rule that decided each
is written down where a template author will find it.

The four are chosen so that between them they cover every shape the repository
will meet again. `/scope`'s branch read is a pure read whose value is captured
and whose gate checks the world the read describes. `/execute`'s settled-branch
record is a write whose gate reads back what was written, through a mechanism
the action cannot influence. `/execute`'s rebase is a local mutation whose gate
asks whether the mutation's goal actually holds. `/work-on`'s pre-pull-request
branch read repeats the first shape at the point where it removes a command
substitution from agent-facing prose.

What holds them together is that in all four cases the gate can contradict the
action. That is what makes the conversion an assurance gain rather than an
assurance trade.

## Solution Architecture

### The conversion record

A new reference, `references/default-action-conversion.md`, states the rule in
one paragraph, names koto's `docs/guides/default-action-authoring.md` as the
authority for the reasoning, and adds shirabe's two filters and two authoring
constraints. `CLAUDE.md`'s existing "Authoring koto-using Skills" section gains
a pointer to it. The reference does not reproduce koto's reasoning; the two
would drift and the guide is the one that ships with the engine.

The two authoring constraints are shirabe's own and are recorded nowhere else:

- **A `fallback` names the evidence, not just the command.** An action-failure
  response carries `expects: null`. The agent is told what went wrong and is
  not told what to submit, so a fallback that stops at "run this yourself"
  leaves it to call `koto status`.
- **A command body longer than one clause goes in a script.** Per Decision 3,
  and a script that ships in the plugin is reached through a declared variable
  rather than `${CLAUDE_PLUGIN_ROOT}`, per Decision 7.
- **Every branch of a converted state's transitions names the gate.** Per
  Decision 6. It is what lets one state both auto-advance on success and hand
  the agent an escape on failure.

### C1 — `/scope`: a `branch_check` state ahead of `setup`

`setup` today asks the agent, in prose, to "confirm HEAD is on a named branch
that is not the repository's default". The state declares no gates at all, so
nothing enforces it, and the same check is restated as a shell block in the
per-hop commit procedure that every hop is told to run.

A new initial state:

```yaml
branch_check:
  # phase: 0
  default_action:
    command: git symbolic-ref --quiet --short HEAD
    capture_stdout_as: BRANCH
    fallback: >-
      koto could not read a branch name, which usually means HEAD is detached.
      Run `git symbolic-ref --quiet --short HEAD` yourself and read the error
      above. Check out a named branch that is not the repository's default,
      then tick again; submit `setup_result: blocked` with `detail` if you
      cannot.
  gates:
    on_named_non_default_branch:
      type: command
      command: "test -n \"$(git symbolic-ref --quiet --short HEAD)\" && test \"$(git symbolic-ref --quiet --short HEAD)\" != \"main\" && test \"$(git symbolic-ref --quiet --short HEAD)\" != \"master\""
  accepts:
    branch_status:
      type: enum
      values: [override, blocked]
    detail:
      type: string
  transitions:
    - target: setup
      when:
        gates.on_named_non_default_branch.exit_code: 0
    - target: setup
      when:
        gates.on_named_non_default_branch.exit_code: 1
        branch_status: override
    - target: bail
      when:
        gates.on_named_non_default_branch.exit_code: 1
        branch_status: blocked
```

`initial_state` moves to `branch_check`. `setup` keeps slug validation and the
state-file write and drops the branch sentence from its directive.

Because `branch_check` is the initial state it dominates every other state, so
`{{BRANCH}}` is readable throughout the template. The per-hop commit directives
name it instead of telling the agent to recover it.

The gate names `main` and `master` literally alongside the emptiness test. The
resolved default would be better and `git symbolic-ref refs/remotes/origin/HEAD`
is absent in a clone that never fetched it, which would leave the check
satisfied by every branch — the same fallback the repository's own commit
procedure already makes for the same reason.

The `accepts` fields are optional, so the passing path carries no evidence and
the agent never sees the state. The two escapes exist for the run that cannot
get onto a branch: `override` for an author who knows the branch is right
anyway, `blocked` for one who cannot proceed, routing to the template's
existing `bail`.

### C2 — `/execute`: a `settled_branch_record` state after `orchestrator_setup`

This is the largest prose reduction in the change. `orchestrator_setup` today
carries a twelve-line shell block that reads HEAD, validates it against
`^[A-Za-z0-9._/-]+$`, stores it under the `settled_branch` context key, reads it
back, and compares — followed by four paragraphs explaining why each line is
load-bearing, and a fifth explaining that the block must run *last* because
running it before the creation script checks out `impl/<slug>` would record
`main`.

The ordering hazard is what a state boundary is for. A new state:

```yaml
settled_branch_record:
  default_action:
    command: '{{PLUGIN_ROOT}}/skills/execute/scripts/record-settled-branch.sh "{{SESSION_NAME}}"'
    capture_stdout_as: SETTLED_BRANCH
    fallback: >-
      koto could not record the settled branch. Read the command's output
      above: the script refuses a detached HEAD, a branch name outside
      ^[A-Za-z0-9._/-]+$, and the repository's default branch, and it reports
      which one it hit. Fix the branch, then tick again. Submit
      `status: blocked` with `detail` only if it cannot be fixed -- the
      settled_branch_recorded gate holds every success path, so a run that
      cannot record its branch must not report completed.
  gates:
    settled_branch_recorded:
      type: context-matches
      key: settled_branch
      pattern: '^[A-Za-z0-9._/-]+$'
  accepts:
    status:
      type: enum
      values: [override, blocked]
    detail:
      type: string
  transitions:
    - target: worktree_sync
      when:
        gates.settled_branch_recorded.matches: true
    - target: done_blocked
      when:
        gates.settled_branch_recorded.matches: false
        status: blocked
      context_assignments:
        failure_reason: "settled_branch_record blocked: ${evidence.detail}"
```

There is deliberately no `override` edge here, unlike C1 and C4. The recorded
branch is the only thing that knows where children commit on the adopt path, so
a run that cannot record it must not be able to wave the gate through; the
template's existing comment on this gate makes the same point about the two
success transitions it guards today.

The `settled_branch_recorded` gate moves here from `orchestrator_setup`, whose
transitions stop referencing it and target `settled_branch_record` instead. The
guarantee is unchanged and better placed: today the gate sits on the state that
was told to do the recording, and it can only fire after the agent claims to
have done it.

`record-settled-branch.sh` reads HEAD, refuses a detached HEAD, refuses a name
the pattern rejects, refuses `main` and `master`, stores the value with
`printf '%s' | koto context add`, and prints the branch on stdout as its only
output. Two consequences follow.

The read-back the prose block performs disappears. The gate is a
`context-matches` read of the same key through koto's own evaluator, which the
action cannot influence, so a hand-rolled comparison inside the command adds
nothing the gate does not already establish.

And the script closes the hole the prose documents but cannot fix. The comment
says `main` is "the one wrong value neither the pattern nor the read-back can
catch, because nothing about it is malformed; the ordering is the only thing
that prevents it." A script can simply refuse it, and does.

`SETTLED_BRANCH` is captured. `settled_branch_record` sits on the only path to
`spawn_and_await`, so `spawn_and_await` reads `{{SETTLED_BRANCH}}` in place of
the twenty-five-line block that reads the context key, branches on koto's exit
status to tell an absent key from a real failure, and falls back to
`impl/<slug>`. That block exists because the key might not be there; the gate
now guarantees it is.

### C3 — `/execute`: a `worktree_sync` state before `worktree_discipline_check`

`worktree_discipline_check` today asks for four things in one state: fetch
origin, rebase the shared branch on main, classify the upstream impact against
the PLAN's intent, and write the classification to
`wip/work-on_{{PLAN_SLUG}}_impact.json`. The classification is judgment. The
fetch and rebase are not.

```yaml
worktree_sync:
  default_action:
    command: git fetch --quiet origin && git rebase origin/main
    fallback: >-
      koto could not rebase the shared branch onto origin/main. Read git's own
      output above. A conflict leaves the rebase in progress: resolve it and
      run `git rebase --continue`, or run `git rebase --abort` and rebase by
      hand, then tick again. Nothing has advanced.
  gates:
    rebased_on_main:
      type: command
      command: "git merge-base --is-ancestor origin/main HEAD"
  accepts:
    sync_status:
      type: enum
      values: [override, blocked]
    detail:
      type: string
  transitions:
    - target: worktree_discipline_check
      when:
        gates.rebased_on_main.exit_code: 0
    - target: worktree_discipline_check
      when:
        gates.rebased_on_main.exit_code: 1
        sync_status: override
    - target: done_blocked
      when:
        gates.rebased_on_main.exit_code: 1
        sync_status: blocked
      context_assignments:
        failure_reason: "worktree_sync blocked: ${evidence.detail}"
```

The gate asks the question the rebase was for — is `origin/main` an ancestor of
HEAD — rather than asking whether the rebase command succeeded. A rebase that
exits 0 without achieving it fails the gate, and a rebase that was already
unnecessary passes without one having run.

The prior exploration declined this step, reasoning that a second run mid-conflict
would compound a bad state and that a conflict should surface as an ordinary
tool-call failure the agent can see. The second half no longer holds: a
conflicted rebase exits non-zero and the agent receives git's own stderr with
the fallback. The first half is answered by git rather than by this design — a
`git rebase` started while a rebase is in progress refuses and says so, so the
re-run on a gate-blocked retry reports the conflict again instead of compounding
it.

`git fetch` against a large remote is the one candidate here that could
approach koto's 30-second per-run limit. `--quiet` keeps the output small; a
timeout reports `failure_kind: timed_out` and the fallback tells the agent to
rebase by hand, which is what it does today.

### C4 — `/work-on`: a `pr_precheck` state before `pr_creation`

`pr_creation` is reached from `finalization` and from `deferral_approval`, and
its prose tells the agent to run `gh pr list --head $(git rev-parse
--abbrev-ref HEAD)`. A new state on that shared edge:

```yaml
pr_precheck:
  default_action:
    command: git rev-parse --abbrev-ref HEAD
    capture_stdout_as: BRANCH
    fallback: >-
      koto could not read the branch name. Run `git rev-parse --abbrev-ref
      HEAD` yourself, read the error above, and carry on with what it prints.
  gates:
    on_feature_branch_pr:
      type: command
      command: "test \"$(git rev-parse --abbrev-ref HEAD)\" != \"main\""
  accepts:
    precheck_status:
      type: enum
      values: [override, blocked]
    detail:
      type: string
  transitions:
    - target: pr_creation
      when:
        gates.on_feature_branch_pr.exit_code: 0
    - target: pr_creation
      when:
        gates.on_feature_branch_pr.exit_code: 1
        precheck_status: override
    - target: done_blocked
      when:
        gates.on_feature_branch_pr.exit_code: 1
        precheck_status: blocked
      context_assignments:
        failure_reason: "pr_precheck blocked: ${evidence.detail}"
```

`pr_creation`'s prose then reads `gh pr list --head {{BRANCH}}`, and its push
instruction names the branch instead of asking for it. The gate is the one
structural guarantee in the template that a pull request is not opened from the
default branch at the point where opening one happens.

The gate carries a distinct name rather than reusing `on_feature_branch`.
`scripts/validate-template-mermaid.sh` check 4 requires a gate name shared
across templates to carry an identical command, and a name reused inside one
template for a check with a different job is the kind of thing that check exists
to notice.

### C5 — `/execute`: stop re-deriving `PLAN_SLUG`

Five sites in `execute.md`'s body run `basename {{PLAN_DOC}} .md | sed
's/^PLAN-//'` to recover a value the frontmatter already declares as a required,
compile-time-validated variable. Each becomes `{{PLAN_SLUG}}`. No action is
involved; it is the same principle as the rest of this design applied to a value
the template never lost.

### What the mermaid companions need

Every state this design adds must appear in its template's `.mermaid.md`
companion or `scripts/validate-template-mermaid.sh` check 1 fails: `branch_check`
in `scope.mermaid.md`, `settled_branch_record` and `worktree_sync` in
`execute.mermaid.md`, `pr_precheck` in `work-on.mermaid.md`, with the edges the
splits introduce.

## Implementation Approach

The work splits into units that land in dependency order and can be verified
independently.

1. **The conversion record.** `references/default-action-conversion.md` plus the
   `CLAUDE.md` pointer. Nothing else depends on it landing first, but every
   later unit's review reads against it.
2. **C5, the `PLAN_SLUG` cleanup.** Independent of everything else, and the
   smallest diff. Landing it first keeps it out of the way of the state-machine
   changes to the same file.
3. **C1, `/scope`'s `branch_check`.** Self-contained: one new state, one moved
   sentence, one mermaid edge, and the hop directives that can now name
   `{{BRANCH}}`.
4. **C2, `/execute`'s `settled_branch_record`.** The `PLUGIN_ROOT` variable and
   the `koto init` line that passes it, the new script and its test, the new
   state, the gate relocation, the prose deletion in `orchestrator_setup`, and
   the `spawn_and_await` simplification that the capture makes possible. The
   largest unit and the one whose review matters most.
5. **C3, `/execute`'s `worktree_sync`.** Depends on C2 only for file ordering,
   since both edit the same template's state list.
6. **C4, `/work-on`'s `pr_precheck`.**
7. **Evals.** Every skill whose content changed has its evals run, per
   `CLAUDE.md`. Where the environment cannot run them, that is stated rather
   than reported as a result.

Each unit ends with `koto template compile` on the template it touched,
`scripts/validate-template-mermaid.sh`, and
`scripts/check-template-interpolation.sh`.

## Security Considerations

**The grant, and where it moves.** An engine-run command is a direct child of
the koto binary and never passes the agent's tool layer, so a user's
allow/deny/ask rules do not see it. This is koto's intended design: invoking a
koto-backed workflow authorizes the commands that workflow bakes in, and that
relocation of consent from per-command prompting to the decision to run the
workflow is what lets koto carry mechanical work at all. It is recorded here
because the mechanism looks like a defect to anyone meeting it for the first
time, and because it is the reason the rule in Decision 1 carries the weight it
does: the rule is what decides which commands get that grant, and there is no
second line of defence behind it.

**Command injection.** Every `{{KEY}}` reference is substituted before the
shell sees the string, and koto's value allowlist excludes every character able
to start a command, expansion, or redirection. The allowlist blocks injection
but not word splitting, so a reference that must stay one argument is quoted.
The four commands here take `{{SESSION_NAME}}` and nothing else, and it is
quoted at the one site that uses it.

`scripts/check-template-interpolation.sh` covers the inverse mistake — a
`$PLAN_SLUG` that koto never substitutes, expanding to the empty string and
running the command against the wrong value. It already reads `default_action`
commands and has never had one to read.

**Untrusted input reaching a command.** The one value this design recovers from
the environment rather than from a declared variable is the branch name, in C1,
C2, and C4. In C2 the script validates it against `^[A-Za-z0-9._/-]+$` before it
is stored or printed, which is the same validation the prose block performs
today, and koto's capture allowlist rejects anything that got past it. In C1 and
C4 the captured value is rendered into directive text and into `gh pr list
--head {{BRANCH}}`, where the same allowlist applies.

**What anchoring does and does not buy.** A session refuses to tick from a
different tree than the one it was created in, which is the wrong-directory
guard the original concern named, and it covers gates as well as actions. It is
not containment: once a command runs it can name absolute paths and reach
anything the invoking user can. Nothing in this design should be described as
sandboxed.

**Secrets in the event log.** Every action run appends the command, its exit
code, stdout, and stderr to the session log, which is committed to feature
branches for koto-driven workflows. A converted command that printed a token
would write it there. None of the four prints anything but a branch name, and
the conversion record names this as a check an author runs before converting
anything.

**The rebase.** C3 is the only converted step that rewrites anything. It
rewrites local commits on the shared branch and pushes nothing; the push that
follows is agent-run and unchanged. A rebase against the wrong `origin/main` is
the failure mode, and execution anchoring is what makes the repository the
session was created in the one it runs against.

**No new privilege.** No converted command runs with elevated rights, reads a
credential, or writes outside the working tree and koto's session store.

## Consequences

### Positive

- Four mechanical steps stop costing an agent turn, and two of them stop being
  requests: the settled-branch record and the rebase are now checked by gates
  that can contradict the command.
- The ordering hazard `/execute` spends five paragraphs on becomes a state
  boundary, and the `main`-as-settled-branch hole those paragraphs describe as
  uncatchable is closed by a script that refuses it.
- `/scope` gains its first structural guarantee that a run is not committing
  hops to the default branch.
- Roughly sixty lines of shell leave agent-facing prose across the two largest
  templates, and five re-derivations of a declared variable go with them.
- The repository gets a written boundary and four worked examples of it, which
  is what the next author needs and what none of them had.

### Negative

- Four new states. Each is one more node in a state machine that is already
  large, one more entry in a mermaid companion, and one more thing to keep in
  sync.
- A converted step is less visible than a prose one. An agent reading a
  transcript sees the state advance and does not see the command, unless it
  fails. The prior exploration's warning about a lost paper trail is real; what
  answers it is the session event log, which records every run, and not
  anything the agent sees.
- `record-settled-branch.sh` is a new file to maintain, and the logic it holds
  was previously visible in the template where a reader met it in context.
- C3 makes a rebase happen without the agent asking for one. In a worktree with
  uncommitted changes it fails rather than proceeding, which is correct and is
  also a new way for the state to block.

### Mitigations

- The mermaid drift check is mechanical and already runs in CI, so a companion
  that falls behind is caught rather than discovered.
- `settled-branch-record_test.sh` exists today and pulls shell out of the
  template to test it. Pointing it at a real script makes the test stronger, not
  weaker, and keeps the logic covered after it leaves the template.
- Every converted state keeps an evidence path the agent can use: submitting
  evidence into a state skips its action, so a failing command can always be
  worked around by hand rather than trapping the run.

## Steps examined and not converted

The PRD's R8 requires this list. Each entry names the step and the reason,
because an absent step and an overlooked one look the same.

| Step | Where | Why it stays |
|---|---|---|
| `gh pr create` | `/work-on` `pr_creation`, `/execute` `orchestrator_setup` | A successful run is the externally visible event: reviewers are notified, a number is allocated, subscribed automation reacts. Closing the pull request afterwards undoes its state and not the notifications. Permanent. |
| `gh pr ready` | `/execute` `plan_completion` | Same shape. Marking a draft ready fires `ready_for_review`, and CI starts elsewhere on it. Permanent. |
| `gh pr edit --title/--body-file` | `/execute` `pr_finalization` | Its input is prose the agent authored in the same turn, which no action can consume and no gate can verify. Editing a pull request body is also outward-facing. |
| `git push` | `/execute` `orchestrator_setup`, `/work-on` phase-6 | The case for calling it engine-runnable rests on an unchecked claim that a push notifies subscribers more quietly than an open. koto's guide resolves an unverified claim about external visibility in one direction: the command stays with the agent until the claim is checked. |
| `run-cascade.sh --push` | `/execute` `plan_completion` | It pushes, which is the row above. Its local half is repairable and its verification is internal, so this becomes convertible the moment the push is separated from it — which is its own change, not this one. |
| `extract-context.sh` | `/work-on` `context_injection` | Documents `Exit codes: 0 - Always`. It can never reach the failure path, and its diagnosis is the JSON on its stdout, which a successful action discards. Converting it would make a failure less visible than it is today. Decision 1's first filter. |
| Branch creation | `/work-on`'s three setup states | Which branch to use is a decision tree — reuse `SHARED_BRANCH`, reuse the branch the author said to continue on, reuse a feature branch already checked out, otherwise create one with a prefix and description chosen from the issue. Not a fixed string. |
| Baseline and verification test runs | `/work-on` `setup_*`, `verification`, `finalization` | No fixed command exists across consuming repositories; the prose says to use project-specific commands from CLAUDE.md or a language skill. A `TEST_COMMAND` variable would shrink this and is out of scope per the PRD's D3. |
| The three review panels | `/work-on` `scrutiny`, `review`, `qa_validation` | Task-tool subagent dispatch is not a shell command. No action mechanism reaches it. |
| The eight retry-clearing blocks | `/work-on`, throughout | Governed by `docs/designs/current/DESIGN-work-on-retry-clearing.md`, status Current, which chose manual clear-and-verify deliberately. Out of scope per the PRD. |
| koto's own protocol calls | all three templates | `koto init` and the tick loop bootstrap and drive the machine. koto refuses a nested `koto next` outright, with `nested_invocation` and exit 2. |
| `plan_context_injection`'s GitHub fetch | `/work-on` | The right shape — `gh issue view` fails loudly and the `context_artifact` gate already checks the result — but the state routes on evidence the agent submits *and* on a template variable, so isolating the fetch means reworking plan-backed routing. Worth doing with that rework rather than inside this change. |
| `spawn_and_await`'s context assembly | `/execute` | Roughly two dozen reads and writes that the koto 0.12.1 runner fixes make reachable. The assembly is interleaved with the `koto next --with-data` submission that koto now refuses from inside an action, so converting the reachable half would split one block across an action and prose that has to agree with it. |
