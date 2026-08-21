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
