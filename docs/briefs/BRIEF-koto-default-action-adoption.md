---
schema: brief/v1
status: Done
problem: |
  shirabe's koto-backed workflows ask the agent, in prose, to run commands
  that have exactly one correct answer. koto can run a command itself when a
  state is entered, and shirabe has never used the capability, so every
  mechanical step costs an agent turn and arrives as a request rather than a
  guarantee.
outcome: |
  The mechanical steps of a koto-backed workflow happen without being asked
  for, and the directive an agent reads carries judgment work only. A step
  that fails hands back the command's own output and prose for doing it by
  hand, in the same response.
motivating_context: |
  koto v0.12.1 shipped the pieces that were missing: output capture into a
  named value, a real failure path that reaches the agent, and execution
  anchoring. The capability stopped being half-built, which is what made this
  worth doing now rather than earlier.
---

# BRIEF: Adopting `default_action` in shirabe's koto templates

## Status

Done

The framing stops at what moves and why. Which specific steps convert, and
where the state boundaries end up, belong to the downstream PRD and DESIGN.

Two questions this brief deferred are closed in the downstream PRD's Decisions
and Trade-offs section: where the state boundaries land once mechanical steps
are pulled out, and whether a template variable carrying the per-repo
verification command belongs in this feature.

## Problem Statement

shirabe's koto-backed workflows tell the agent to run shell commands in prose.
A directive reads "then run `git rev-parse --abbrev-ref HEAD` to get the
current branch" and the agent spends a turn doing it. `/execute` carries 53
such agent-instructed commands and `/work-on` around 37 instruction sites.

koto has been able to run a command itself when a state is entered since March
2026. shirabe is koto's main consumer and has never used it: `default_action`
appears zero times in the repository. Nobody decided against it. No design,
issue, or pull request in either repo records a rejection. The capability was
half-built when the templates were first authored, days after it shipped, and
the templates were never revisited.

Two things go wrong because of that, and they are not the same thing.

The first is cost. Every mechanical step is a round trip: the agent reads a
directive, runs a command whose output is fully determined, and reports back.
That is a turn spent on work with no judgment in it, in a workflow whose whole
premise is that the agent's turns are the scarce resource.

The second is weaker and matters more. A prose instruction is a request, not a
guarantee. The workflow cannot tell a step that ran from a step that was
skipped, mis-transcribed, or run against the wrong tree, except through
whatever gate happens to sit downstream — and the workflow has no way to hand
the agent a value a command produced, so a step whose entire purpose is to
compute something has to be re-run by hand wherever the value is needed. The
same slug gets derived five separate times in one template for exactly this
reason.

Underneath both is a boundary nobody has drawn. Some of these commands are
plainly safe for an engine to run and some plainly are not, and the difference
is not "does it write". It is whether a *successful* run creates something
that cannot be taken back. Without that line written down, adoption is a
judgment call made afresh, badly, at every site.

## User Outcome

A workflow author running `/work-on` or `/execute` finds the mechanical steps
already done. The directive they read asks them to decide which branch to
reuse or whether the approach still holds — not to read a ref, create a
directory, or re-derive a slug the template already knows. Values a command
produced are already interpolated into the instructions that need them, so
nothing gets computed twice.

When a converted step fails, the same author gets the command's exit status,
its stdout and stderr, and prose telling them how to do the step by hand, all
in the response that stopped, without a second call to find out why. Nothing
advanced past the failure, because a failing action never reaches the state's
gates.

And an author adding a mechanical step to a template later has a rule to apply
and a worked example to copy, rather than a decision to improvise. For every
step that stayed with the agent, they can read why.

## User Journeys

### An agent needs a value the workflow already computed

An agent driving `/work-on` reaches a state whose instructions have to name the
branch it is working on. The engine has already read the branch name on state
entry and delivered it under a declared name; the directive arrives with the
name in it. The agent never runs `git rev-parse`, and no later state re-derives
it. The trigger is entering the state; the outcome is instructions that are
already specific.

### A converted step fails and the agent has to recover

The same agent enters a converted state in a checkout where the command cannot
succeed — `gh` is not installed, or the repository is not the one the session
was anchored to. koto stops the tick at that state, and the response carries
the command line, the exit status, the command's own stderr, a typed failure
kind, and the author's fallback prose spliced onto the directive. The agent
reads what actually went wrong, does the step by hand, and submits an override.
Nothing advanced, and no gate passed on work that never happened.

### An author extends a template months later

A template author adds a step to `/execute` and has to decide whether koto runs
it or the agent does. They apply the recorded rule — does the risk live in a
bad success, or only in a bad failure? — and read a converted state next to it
as the shape to copy: the action, the fallback prose, the gate that checks the
outcome without consulting the action's own exit code. The trigger is writing a
new state; the outcome is a decision they can defend in review.

### A reviewer reads the change

A reviewer opens the pull request and wants to know why the workflow still asks
the agent to open the pull request itself. The design names it: a successful
`gh pr create` is the externally visible event, and no signal arriving
afterwards can un-fire it. The reviewer finds the steps that stayed with the
agent listed with their reasons, not silently absent. The trigger is review;
the outcome is a boundary they can check rather than infer.

## Scope Boundary

### In

- shirabe's koto-backed workflow templates, the ones under
  `skills/*/koto-templates/`.
- Converting the mechanical steps that pass the recorded rule into
  `default_action` declarations, each with fallback prose for the failure path.
- Splitting states where a mechanical step is currently bundled with judgment,
  so the mechanical part is isolated and independently checkable.
- Gates that verify a converted step's outcome without consulting the action's
  own exit code.
- Delivering a command's output to later states under a declared name, where
  that removes a re-derivation.
- Writing the conversion rule down where a future template author will find it,
  including the reason each step that stayed with the agent stayed.
- Keeping the mermaid companions in sync with the templates they document.

### Out

- **Any change to koto.** The engine is the version that ships. A defect found
  here is filed and worked around, not fixed here.
- **Commands whose success is the externally visible event** — opening,
  publishing, or closing a pull request, posting a comment, marking a draft
  ready for review. These stay with the agent permanently, not pending a
  future capability, and the reason is recorded rather than left implicit.
- **The retry-clearing blocks in `/work-on`.** They are governed by
  `docs/designs/current/DESIGN-work-on-retry-clearing.md`, which is status
  Current and deliberately chose manual clear-and-verify. Reversing a Current
  design is its own piece of work.
- **The shirabe skills that are not koto-backed.** They carry real hardcoded
  commands, and `default_action` cannot reach any of them, because it only exists
  inside a template state.
- **koto's own protocol calls** — initializing a session, the tick loop,
  listing workflows, rewinding. These drive the state machine and cannot live
  inside it.
- **A general mechanism for conditional instruction text.** A state's directive
  is one string rendered the same way on every stop reason. Fallback prose
  covers the failure path; anything more is a koto concern.

## References

- `skills/execute/koto-templates/execute.md`: the `/execute` workflow template.
- `skills/work-on/koto-templates/work-on.md`: the `/work-on` workflow template.
- `skills/scope/koto-templates/scope.md`: the `/scope` workflow template.
- `scripts/check-template-interpolation.sh`: already checks shell
  interpolation defects in a `default_action` command, and has never had one to
  check.
- `scripts/validate-template-mermaid.sh`: the drift check between a template
  and its mermaid companion.
