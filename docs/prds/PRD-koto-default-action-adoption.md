---
schema: prd/v1
status: In Progress
problem: |
  shirabe's koto-backed workflow templates hand the agent mechanical shell
  commands inside prose instructions. koto has been able to run a command
  itself when a state is entered since March 2026, and shirabe has never used
  it, so every mechanical step costs a turn, arrives as a request rather than a
  guarantee, and produces a value the workflow has no way to keep.
goals: |
  The mechanical steps that qualify run inside the templates, each isolated in
  its own state, verified by a gate that does not consult the action's exit
  code, and carrying prose for the failure path. The rule that decides what
  qualifies is written down, and every step that stays with the agent stays for
  a recorded reason.
upstream: docs/briefs/BRIEF-koto-default-action-adoption.md
---

# PRD: Adopting `default_action` in shirabe's koto templates

## Status

In Progress

## Problem Statement

shirabe ships three koto-backed workflow templates: `/work-on`, `/execute`,
and `/scope`. Every mechanical command in all three lives in prose the agent is
asked to carry out. A directive reads "run `git rev-parse --abbrev-ref HEAD` to
get the current branch", and the agent spends a turn on a step with exactly one
correct answer.

koto has shipped the capability to run such a command itself, on state entry,
since March 2026. `default_action` appears zero times in shirabe. No design,
issue, or pull request in either repository records a decision against it; the
capability was half-built when the templates were authored days after it
shipped, and nobody came back.

Three costs follow, and they are separate.

**Turns.** Each mechanical step is a full round trip in a workflow whose
premise is that the agent's turns are the scarce resource.

**Assurance.** A prose instruction is a request. The workflow cannot tell a
step that ran from one that was skipped or mis-transcribed, except through
whatever gate happens to sit downstream, and `/execute`'s own template says so
in a comment: a gate not referenced in a `when` clause is "evaluated, reported,
and ignored."

**Lost values.** A command that computes something has nowhere to put the
answer, so the answer gets recomputed. `/execute` re-derives `PLAN_SLUG` at
five separate sites from `{{PLAN_DOC}}`, with a `sed` expression, while
`PLAN_SLUG` is a declared, compile-time-validated template variable the
frontmatter already carries.

Underneath all three is a line nobody has drawn. Some of these commands are
obviously safe for an engine to run and some obviously are not, and the
difference is not whether they write. Without the line recorded, every site is
an improvised judgment.

## Goals

- A template author can read one rule and decide, for any command, whether koto
  runs it or the agent does.
- The mechanical steps that pass that rule run without an agent turn, and their
  outcome is established by something other than the action's own exit code.
- A converted step that fails is diagnosable from the response that stopped:
  the command, its output, and prose for doing the step by hand.
- Values a converted command produces reach the states that need them, so
  nothing is derived twice.
- The steps that stay with the agent are visibly a decision, with the reason
  attached.

## User Stories

**As an agent driving `/work-on`,** I want the branch I am working on already
named in the instructions I read, so that I do not spend a turn reading a ref
whose value the workflow could have kept.

**As an agent whose converted step just failed,** I want the command's exit
status, its stderr, and instructions for doing the step by hand in the response
that stopped, so that I can recover without a second call to find out what
happened.

**As a template author adding a mechanical step months from now,** I want a
recorded rule and a converted state next to mine to copy, so that I make a
decision I can defend in review instead of guessing.

**As a reviewer of a shirabe change,** I want each step that stayed with the
agent to name why it stayed, so that I can check the boundary rather than infer
it from what is missing.

**As a maintainer of the repository's checks,** I want the templates to still
compile and the mermaid companions to still match after the change, so that the
existing drift checks keep meaning what they meant.

## Requirements

### Functional

**R1. The conversion rule is recorded, and cited rather than restated.**
shirabe records where a template author will find it: keep `default_action` off
any command whose *successful* exit is itself the irreversible, externally
visible event; allow it where the only irreversibility is bounded and
repairable after a successful run. The record names koto's
`docs/guides/default-action-authoring.md` as the authority for the reasoning
rather than reproducing it, so the two cannot drift apart.

**R2. A converted step is isolated in its own state.** Every state carrying a
`default_action` has that step as its whole mechanical content. Where a
mechanical step is currently bundled with judgment in one state, the state is
split so the mechanical part stands alone and the judgment keeps its own state.

**R3. A converted step is verified independently of its own exit code.** Every
state carrying a `default_action` declares a gate establishing that the step's
outcome actually holds, and at least one transition out of that state
references the gate in a `when` clause. An unreferenced gate does not count:
the template already records that such a gate is evaluated, reported, and
ignored.

**R4. Every `default_action` declares `fallback` prose, and that prose names
the evidence.** The fallback tells the agent what to run by hand. It also names
the evidence field and value to submit, because an action-failure response
carries no `expects` block. The agent is told what went wrong and is not told
what to submit.

**R5. Every converted command is safe to run twice.** A state's action
executes on every entry without evidence, including each gate-blocked retry and
each lap of a self-loop. Commands are written so a second run is harmless.

**R6. A value a converted command produces is delivered under a declared
name.** Where a converted command computes something later states need, it
declares `capture_stdout_as`, and the value is read only from states that every
path into them reached through the producing state. Reading a capture on a path
that skipped its producer is a hard stop, not an empty render.

**R7. Derivations the templates already carry as variables are not repeated.**
Where a template declares a variable and the prose re-derives the same value
with shell, the prose references the variable.

**R8. Steps that stay with the agent are recorded with their reason.** For
every candidate examined and not converted, the design names the step and why
it stayed. An absent step is indistinguishable from an overlooked one; a named
one is a decision.

**R9. A command interpolates template values as `{{KEY}}`, never as a shell
variable.** A `$NAME` inside an action command reaches `sh -c` untouched and
expands to nothing. `scripts/check-template-interpolation.sh` already checks
this for `default_action` commands and has never had one to check.

**R13. A skill whose content changes has its evals run.** shirabe's `CLAUDE.md`
requires evals to be created or updated whenever a skill is, and run rather
than assumed. Where they cannot be run in the environment doing the work, that
is stated plainly rather than reported as a result.

### Non-functional

**R10. Every converted command completes inside koto's per-run budget.** Each
individual run gets 30 seconds and the limit is not configurable. A command
that cannot finish in that time is not a candidate.

**R11. The change requires no koto change.** The engine is the version that
ships. A koto defect found while doing this work is filed and worked around.

**R12. The repository's existing checks keep passing.** All three templates
compile, the mermaid companions match their templates' state names, and the
interpolation and template-directive checks pass.

## Acceptance Criteria

- [ ] AC1. `default_action` appears at least once in a shipped shirabe koto
      template, and no state declaring one also asks the agent, in that state's
      prose, to run a second command or make a judgment call (R2).
- [ ] AC2. Every state declaring a `default_action` also declares at least one
      gate, and at least one of that state's transitions names that gate in its
      `when` clause (R3).
- [ ] AC3. No gate verifying a converted step is a re-run of that step's own
      command; each checks the state the step was supposed to leave behind (R3).
- [ ] AC4. Every `default_action` declares a non-empty `fallback`, and every
      fallback names both a manual command and the evidence field and value to
      submit (R4).
- [ ] AC5. Every converted command is run twice in sequence against the state
      the first run left, and the second run exits 0 and leaves that state
      unchanged (R5).
- [ ] AC6. For every `capture_stdout_as` declared, every state whose rendered
      text or command reads that name is reachable only through the declaring
      state (R6).
- [ ] AC7. No `default_action` command contains a bare `$NAME` shell reference
      to a template value; `scripts/check-template-interpolation.sh` exits 0
      (R9).
- [ ] AC8. `koto template compile` exits 0 for each of
      `skills/work-on/koto-templates/work-on.md`,
      `skills/execute/koto-templates/execute.md`, and
      `skills/scope/koto-templates/scope.md` (R12).
- [ ] AC9. `scripts/validate-template-mermaid.sh` exits 0, so every state a
      split introduced appears in its template's mermaid companion (R12).
- [ ] AC10. The conversion rule is recorded in the repository, cites koto's
      authoring guide as the authority, and does not restate its reasoning
      (R1).
- [ ] AC11. The design names every candidate step that was examined and not
      converted, each with its reason (R8).
- [ ] AC12. No file under the koto repository is modified by this work (R11).
- [ ] AC13. `PLAN_SLUG` is not re-derived with shell anywhere in
      `execute.md`'s body; every site references `{{PLAN_SLUG}}` (R7).
- [ ] AC14. Skill evals are run for every skill whose content changed and the
      results reported in the pull request body in the format `CLAUDE.md`
      prescribes, or their absence is stated plainly with the reason (R13).

## Out of Scope

- **Any change to koto.** Including fixes for defects this work uncovers. Those
  are filed against koto and worked around here.
- **Commands whose success is the externally visible event.** Opening,
  publishing, or closing a pull request, posting a comment, marking a draft
  ready for review, pushing a branch. These stay with the agent, and R8 makes
  that a recorded decision rather than an omission.
- **The retry-clearing blocks in `/work-on`.** Eight near-identical
  context-clearing blocks whose behavior is settled by
  `docs/designs/current/DESIGN-work-on-retry-clearing.md`, status Current,
  which chose manual clear-and-verify deliberately. Reversing a Current design
  is its own piece of work with its own argument to make.
- **The shirabe skills that are not koto-backed.** They carry real hardcoded
  commands and `default_action` cannot reach any of them: it exists only inside
  a template state.
- **koto's own protocol calls.** Initializing a session, the tick loop, listing
  workflows, rewinding. These drive the state machine and cannot live inside
  it. koto refuses a nested `koto next` outright.
- **A `TEST_COMMAND` template variable.** See Decisions and Trade-offs below.
- **Conditional instruction text.** A state's directive is one string rendered
  identically on every stop reason. `fallback` covers the failure path;
  anything beyond that is a koto concern.

## Decisions and Trade-offs

### D1. Conversion happens by splitting states, not by annotating them

**Decided:** a mechanical step gets its own state.

**Alternatives:** annotate the existing state with a `default_action` covering
the mechanical part of what it does.

**Why:** the states koto's own design named as targets bundle both kinds of
work. `/work-on`'s setup states pick a branch by decision tree (reuse
`SHARED_BRANCH`, reuse the branch the user said to continue on, reuse the
feature branch already checked out, otherwise create) and then run a test
suite whose command is explicitly project-specific. Annotating such a state
either drags the decision tree into a shell script or leaves the mechanical
half in prose beside an action that does something else. Splitting is what
makes R3 satisfiable at all: a gate can only establish an outcome it can name,
and a state doing two things has two.

This closes the first Open Question the upstream BRIEF deferred. Where the
splits land is the DESIGN's to settle; that they are required is settled here.

### D2. A capture's producing state must dominate every state that reads it

**Decided:** a `capture_stdout_as` value is read only from states every path
reaches through the producer.

**Alternatives:** produce the value wherever it is first computed and read it
wherever it is convenient.

**Why:** reading a capture the run never produced is a hard stop with exit 3,
not an empty string. `/work-on` has three entry modes converging at `analysis`,
so a value produced inside one mode's setup state and read after the
convergence would break every run that took another mode. This is a placement
constraint on the design, not a preference.

### D3. A `TEST_COMMAND` template variable is not part of this feature

**Decided:** out of scope, and worth doing separately.

**Alternatives:** resolve the project's test command once at `koto init` and
substitute it into the states that currently say "use project-specific
commands from the language skill or CLAUDE.md."

**Why:** three reasons, and the third is the one that decides it. Resolving the
value is itself judgment, since it means reading CLAUDE.md or a language skill
and choosing, so the variable relocates the judgment to session start rather than removing
it. It changes the init contract of both templates and of every caller that
spawns children with variables, which is a wider blast radius than anything
else here. And the shipped `tests_passing` gate hardcodes
`[ ! -f go.mod ] || go test ./...` with no variable at all, so a variable would
fix the prose site and leave the gate reporting a pass for every repository
without a root `go.mod`. Fixing the prose while leaving the gate lying makes
the template more confusing, not less.

This closes the second Open Question the upstream BRIEF deferred.

### D4. `requires_confirmation` is not used

**Decided:** no converted state declares it.

**Alternatives:** use it as a safety valve on the more consequential
conversions.

**Why:** it fires after a successful run, so it cannot gate the event it would
be protecting. For a command whose success is the event, it arrives too late;
for everything this feature converts, success is reversible and there is
nothing to confirm. A flag that reads as a guard and delivers a receipt is
worse than no flag.

### D5. Permission visibility is not a reason to keep a command in prose

**Decided:** it does not constrain what converts.

**Why:** an engine-run command is a direct child of the koto binary and never
passes the agent's tool layer, so allow/deny rules do not see it. That is the
intended design. Loading a koto-backed workflow is the grant, and moving
consent from per-command prompting to the decision to run the workflow is what
lets koto carry mechanical work at all. Recorded here because it looks like a
strong objection and will be raised again by anyone who notices the mechanism.

## Known Limitations

- **An action-failure response carries no evidence schema.** `expects` is
  `null`, so an agent that has not read the state's `details` has to call `koto
  status` to learn what to submit unless the fallback says. R4 makes the
  fallback say it, which is a convention rather than something the engine
  enforces.
- **A capture is a single line of restricted characters.** The trimmed value
  must be non-empty, at most 4096 bytes, and free of newlines and characters
  outside koto's allowlist. Multi-line output cannot be captured, so a command
  producing prose is not a capture candidate however useful its output is.
- **Anchoring binds where commands start, not what they can touch.** A session
  refuses to tick from a different tree, which is the wrong-directory guard.
  Once a command is running it can name absolute paths and reach anything the
  user can. The rule in R1 is the only thing deciding which commands get that
  reach.
- **A converted step's output lands in the session event log.** A command whose
  output contains a secret writes it there. No converted command should print
  one.
