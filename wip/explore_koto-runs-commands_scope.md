# Explore Scope: koto-runs-commands

## Visibility

Public

## Core Question

The koto-backed workflows shipped by shirabe (`/execute` and the `/work-on`
template it drives) hand the agent mechanical shell commands to run inside
prose instructions — for example "then run `git rev-parse --abbrev-ref HEAD`
to get the current branch". If koto can execute deterministic commands itself
when `koto next` is called, the agent should receive judgment work, not
mechanical steps. The question is whether the gap is a missing koto capability,
an unused koto capability, or a mix — and what a happy-path-automated,
guarded-fallback design would need.

## Context

- Orientation finding (pre-research): koto ships `default_action` end to end —
  `src/action.rs` (shell execution with process-group isolation, timeout,
  output capture), `ActionDecl` in `src/template/compile.rs`, and execution
  step 5 inside `advance_until_stop` (`src/engine/advance.rs:286`). A design
  doc, `docs/designs/current/DESIGN-default-action-execution.md`, spawned from
  koto issue #71 and parented by `DESIGN-shirabe-work-on-template.md`, states
  the automation-first principle explicitly and claims ~42% of skill
  instructions could be eliminated.
- Counter-finding: **zero** occurrences of `default_action` in the entire
  shirabe repo. Neither `skills/execute/koto-templates/execute.md` (40 KB) nor
  `skills/work-on/koto-templates/work-on.md` (43 KB) declares one.
- The user's stated target state: koto runs the commands on all happy paths and
  falls back to instructing the agent only when a command fails; execution must
  be guarded hard against side effects in the wrong place (wrong directory
  being the named example).

## In Scope

- Every hardcoded shell command in the koto templates for `/execute` and
  `/work-on`, plus their `SKILL.md` files and `references/`.
- koto's `default_action` capability as implemented today: schema, execution
  point, guards, output capture, fallback, polling, confirmation.
- The mechanism by which command output becomes available to later states and
  to the agent (context variables, substitution, evidence).
- Mapping each hardcoded command to: automatable now, automatable after a koto
  change, or must stay with the agent.

## Out of Scope

- Rewriting the templates in this exploration (the exploration produces the map
  and the routing decision, not the implementation).
- koto features unrelated to command execution (dashboard, cloud sync, batch
  spawning) except where they bear on action execution.
- Other shirabe skills that do not ship koto templates.

## Research Leads

1. **Where exactly does the `/execute` koto template and skill surface tell the
   agent to run a shell command, and what is each command for?**
   Full inventory with line references, classified as mechanical (deterministic,
   no judgment) versus judgment-bearing. This is the concrete evidence base for
   how large the problem is.

2. **Same inventory for `/work-on`** — the template `/execute` delegates to,
   plus its SKILL.md and references.
   `/execute` drives `/work-on` per issue, so most per-issue mechanical commands
   likely live there. Without this the map is half-built.

3. **What does koto's `default_action` actually support today, and what did the
   design promise that the code does not deliver?**
   Schema fields, execution trigger, override semantics, `requires_confirmation`,
   polling, timeouts, `working_dir`, variable substitution. Separates "missing
   koto feature" from "unused koto feature".

4. **How does a command's output reach later states and the agent?**
   Can stdout of a `default_action` become a context value that later
   `{{VAR}}` substitution and rendered instructions can consume? The
   `git rev-parse --abbrev-ref HEAD` case needs the branch name *available*,
   not just executed. If it can't, that is the missing feature.

5. **What guards exist against unintended side effects, and are they enough?**
   Working-directory resolution and validation, reversibility policy,
   confirmation for irreversible actions, timeout and process-group behavior,
   what happens when the repo root is wrong or the state is dirty.

6. **What happens when an action fails — is there a real fallback-to-agent path?**
   The design references a three-path model and gate-with-evidence-fallback.
   Whether that is implemented, what the agent sees, and whether the template
   would need to carry both an action and prose instructions for the same step.

7. **Why does shirabe not use `default_action` — was this considered, deferred,
   or overlooked?**
   Search design docs, issues, and PR history in both repos for a decision or a
   deferral. A documented rejection changes the recommendation entirely.

8. **What authoring guidance and validation exists for actions?**
   koto's `koto-author`/`koto-user` skills, template compiler validation, other
   templates in the wild that use `default_action`, and any examples. Tells us
   whether the shirabe rewrite is a documentation-following exercise or a
   trailblazing one.
