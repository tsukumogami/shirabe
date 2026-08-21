# Lead: Can the three-path model (koto runs it, agent takes over only on failure) be expressed with today's koto primitives?

## Findings

**The three-path model is fully reachable today, in a single state, with zero koto changes.** The mechanism is not `skip_if` (which is for deterministic, evidence-free routing) but an ordinary conditional `transition.when` that references `gates.<gate>.exit_code`, combined with `default_action` and a command-type `gate` on the same state.

The load-bearing fact is the advance loop's step order (`src/engine/advance.rs:150-162`, confirmed by reading the loop body at `advance.rs:286-475`):

1. `default_action` runs (step 5, `advance.rs:286`) — before any gate is evaluated.
2. Gates evaluate (step 6, `advance.rs:317`). Command-gate output is always `{"exit_code": N, "error": "<stderr or spawn error>"}` (`src/gate.rs:206-231`).
3. `skip_if` evaluates (step 7) — irrelevant to this pattern, see below.
4. **Plain `transitions[].when` resolution runs regardless of `skip_if`** (step 8, `advance.rs:475-560`, `resolve_transition` at `advance.rs:693`). Critically, **conditional transition matching does not depend on `fresh_evidence` or on the agent having submitted anything** — only the *unconditional fallback* is gated by `fresh_evidence`/`gate_failed` (`advance.rs:770-790`, doc comment at `advance.rs:684-691`). A `when: {gates.mygate.exit_code: 0}` transition fires the instant the gate passes, on the very first pass through the state, with no agent evidence at all.

So: put `default_action` (the real command) and a `gates.*` command gate (a *check*, e.g. "is HEAD now on the branch I wanted") on the same state, and give the state one conditional transition keyed on `gates.<gate>.exit_code: 0`. If the action succeeds, the gate passes, the transition fires inside the same `advance_until_stop` call, and the state's `directive` is **never sent to the agent** — `koto next` returns whatever the *next* state's directive is. This doesn't even need self-loop suppression (`DESIGN-self-loop-suppresses-details.md`): the directive isn't suppressed on a second lap, it's never delivered on the first one, because the loop never stops there.

On failure, the picture depends on whether the state has an `accepts` block (verified by reading `advance.rs:405-435` and `src/cli/mod.rs:4139-4152`):

- **No `accepts` block, no `gates.*`-referencing transition on any path** → `advance_until_stop` returns `StopReason::GateBlocked` immediately at step 6, before transition resolution even runs. The agent gets `action: "gate_blocked"`, `directive`, `blocking_conditions: [{name, type, status, output: {exit_code, error}}]`. No way for the agent to submit an override.
- **Has an `accepts` block** (our canonical case: agent needs an override path) → the failing gate does *not* immediately block. `gates_failed=true` is threaded into `resolve_transition`, the conditional `exit_code: 0` transition doesn't match, there's no unconditional fallback to suppress, so it resolves to `NeedsEvidence`. Because `accepts` is `Some`, the caller returns `StopReason::EvidenceRequired { failed_gates }`, and — this is the important, easy-to-miss part — **`EvidenceRequired` carries `blocking_conditions` too**, not just `GateBlocked` (`src/cli/mod.rs:4141-4152`, `blocking_conditions_from_gates` shared by both branches at `src/cli/next_types.rs:824-856`). So the agent sees `action: "evidence_required"`, the state's `directive` (written as the manual-fallback prose), the gate's `{exit_code, error}` in `blocking_conditions`, and an `expects` schema telling it exactly which fields to submit to move on.

I verified all of this against the compiled form of a real template. Compiling `shirabe/skills/work-on/koto-templates/work-on.md` with the local `koto` binary and inspecting the cached JSON output confirms the shape of `setup_issue_backed`'s compiled transitions exactly matches this reading — `status`/`gates.*` combined in one `when`, `override` bypassing the gate, `blocked` routing to `done_blocked`, and a bare unconditional fallback.

**Override safety is automatic, not something a template author has to engineer.** The action-execution closure (`src/cli/mod.rs:3966-3973`) skips running `default_action` entirely whenever the agent has submitted any evidence in that `koto next` call (`has_evidence` → `ActionResult::Skipped`). So when the agent hand-fixes the branch and submits `status: override`, koto does not re-run `git checkout -b` on top of the agent's work — the command only ever runs on evidence-free calls. A template author does not need to write an idempotent action command to make the override path safe (though it doesn't hurt).

## Implications

Concrete YAML for the canonical case — "create or reuse `impl/{{ARTIFACT_PREFIX}}`, koto attempts it, agent only sees prose if it fails":

```yaml
states:
  create_branch:
    default_action:
      command: >-
        git checkout -b impl/{{ARTIFACT_PREFIX}} 2>/dev/null ||
        git checkout impl/{{ARTIFACT_PREFIX}}
    gates:
      on_impl_branch:
        type: command
        command: 'test "$(git rev-parse --abbrev-ref HEAD)" = "impl/{{ARTIFACT_PREFIX}}"'
    accepts:
      status:
        type: enum
        values: [override, blocked]
        required: true
      detail:
        type: string
        description: What you did instead, or why you're blocked
    transitions:
      - target: analysis
        when:
          gates.on_impl_branch.exit_code: 0
      - target: analysis
        when:
          status: override
      - target: done_blocked
        when:
          status: blocked
```

Markdown body:

```markdown
## create_branch

koto could not create or check out `impl/{{ARTIFACT_PREFIX}}` automatically.
Create or check out that branch yourself (`git checkout -b impl/{{ARTIFACT_PREFIX}}`,
or `git checkout impl/{{ARTIFACT_PREFIX}}` if it already exists), then submit
`status: override`. If you cannot get onto that branch, submit `status: blocked`
with `detail` explaining why.
```

What the agent sees on each path, concretely:

1. **Success** (`git checkout -b` exits 0, or the branch already existed and the fallback checkout worked): the agent sees *nothing* about `create_branch` at all. `koto next` returns the next state (`analysis`)'s directive. No round trip is spent here, no tokens describe the branch step. This is strictly better than the "self-loop suppresses details" case — it's not that the instructions are suppressed on a repeat visit, the agent never learns this state exists.
2. **Failure, agent takes over**: `koto next` returns `action: "evidence_required"`, `state: "create_branch"`, `directive` = the prose above, `blocking_conditions: [{"name": "on_impl_branch", "type": "command", "status": "failed", "category": "corrective", "output": {"exit_code": 1, "error": ""}}]`, and `expects` listing `status`/`detail`. The agent does the checkout by hand and calls `koto next --with-data '{"status":"override"}'`.
3. **Failure, agent gives up**: same response shape, agent submits `{"status":"blocked","detail":"..."}"` and the workflow routes to `done_blocked`.

What's ugly or lossy, concretely:

- **The directive is written as if the automated attempt already failed** — it can't be phrased as neutral generic instructions the way today's prose is, because the agent never sees it on the happy path. This is a real authoring shift: every prose block in the template currently doubles as "how anyone would do this"; under this pattern it has to be phrased as "the automatic attempt failed, here's the manual recovery," which reads oddly if you skim the markdown body without knowing which states have `default_action`.
- **The agent cannot see the action's own stdout/stderr.** Command output from `default_action` is captured in a `DefaultActionExecuted` event (`src/cli/mod.rs:4028-4036`) for the audit log, but it's never placed into the `NextResponse` for a plain `Executed` result — only `ActionRequiresConfirmation` and `GateBlocked`'s own gate command carry any output back to the agent, and the gate here is a separate command from the action. If `git checkout -b` fails for a reason the "is HEAD on the branch" gate can't distinguish (e.g. dirty working tree vs. branch already exists vs. detached HEAD), the agent gets `{"exit_code": 1, "error": ""}` from the *gate*, not the actual git error from the *action* — it has to re-run the command itself to find out why. This is exactly the gap the other round-2 leads on output routing/failure propagation are chasing; it is not solvable inside the template.
- **`context_assignments` under a transition does nothing today** — see Surprises. I did not use it in the example above; a `failure_reason` write on the `blocked` path currently has no compiled effect in any template, including `work-on.md`'s existing use of it.
- **The gate is doing double duty as a correctness check, not just a git-state probe.** Authors must write a gate command that verifies the *outcome* the action was trying to produce, independently of the action — for branch creation that's easy (check current branch), but for actions with side effects that are harder to probe cheaply (e.g. "did the PR actually get created," "did the file actually get written correctly") the gate command itself becomes nontrivial engineering, doubling the shell surface per step instead of the "one command" the canonical case implies.

## Two-state vs. one-state pattern (step 4 of the ask)

**Two-state ("attempt" + "manual_fallback"):**

```yaml
  create_branch_attempt:
    default_action: {command: "git checkout -b impl/{{ARTIFACT_PREFIX}} ..."}
    gates:
      on_impl_branch: {type: command, command: '...'}
    transitions:
      - target: analysis
        when: {gates.on_impl_branch.exit_code: 0}
      - target: create_branch_manual   # unconditional fallback fires when gate fails
                                        # AND fresh_evidence is irrelevant here since
                                        # gate_failed forces NeedsEvidence... this does NOT work as an
                                        # unconditional auto-route: gate_failed=true suppresses the
                                        # unconditional fallback (advance.rs:770-781). It stays parked
                                        # on create_branch_attempt with GateBlocked, same as one-state.
```

This is the first concrete problem with the two-state split: **you cannot get from "attempt" to "manual_fallback" automatically on gate failure**, because `resolve_transition`'s unconditional-fallback suppression (`gate_failed || (!fresh_evidence && has_conditional)`) exists specifically to stop a gate failure from silently auto-routing anywhere. The only way to reach a distinct `create_branch_manual` state is a *conditional* transition keyed on the gate's failure output (`gates.on_impl_branch.exit_code: 1`, or `error: "!="`-style — koto only does equality, so you'd need the gate to emit a stable failure value), which then requires `create_branch_manual` to have its own `accepts` block and its own transitions back to `analysis`. That's workable but doubles the state count and the `accepts`/`transitions` boilerplate for a distinction ("stuck in the attempt state" vs. "moved to a dedicated fallback state") that changes nothing the agent can act on differently — the JSON shape reaching the agent is `EvidenceRequired`/`GateBlocked` either way, just with a different `state` name and a directive that lives in a different markdown section.

**One-state (recommended):** the pattern shown above in Implications. Same behavior, no extra `accepts`/no extra transitions, one markdown `##` section instead of two.

**Cost comparison**, concretely, against `work-on.md` (currently 25 states) and its mermaid companion:

- **Template size**: two-state costs one more YAML block (~10-15 lines: a `gates`-or-conditional-only-transition state, its own `accepts`, its own transitions) and one more `## state_name` markdown section. One-state costs zero beyond what any gated state already has.
- **Mermaid diagram** (`scripts/validate-template-mermaid.sh` check 1, `scripts/lib/koto-gates.sh`): the drift checker requires every YAML state name to appear as a node in the companion `.mermaid.md` and vice versa (`validate-template-mermaid.sh:27-49`). Two-state adds one node and at least two edges (attempt→fallback, fallback→analysis, fallback→done_blocked) to a diagram that, for a ~20-state template, is already dense enough to be hard to read; shirabe's own diagramming guidance treats every added node as a real readability cost. One-state adds nothing to the diagram — `create_branch` looks exactly like any other single-purpose state, and its self-contained "gate + override + blocked" transitions read the same as `setup_issue_backed`'s existing pattern in `work-on.md` today, so it doesn't introduce a new shape reviewers have to learn.
- **Gate-command drift check** (`koto_gate_rows` in `koto-gates.sh`): scoped to `gates:` blocks only, keyed by gate name; it does not look at `default_action.command` at all. Neither pattern affects it differently — but it's worth noting the drift checker would not catch two different templates giving the same gate name (`on_impl_branch`) two different check commands *if* one template's version diverges, same exposure either way.

Two-state only earns its cost when the fallback path is substantial enough to deserve its own name in history and its own resumability marker (e.g., if a human might abandon the workflow mid-manual-recovery and a resuming agent needs `koto history` to show "we're specifically in manual branch recovery," not just "we're in create_branch"). For a one-line git command, that's not the case — the `state` name plus `blocking_conditions` already tells a resuming agent everything the fallback state would have.

## Surprises

`context_assignments` — used in `work-on.md`'s existing YAML (e.g. under `context_injection`'s and `setup_issue_backed`'s `blocked` transitions, to write `failure_reason`) — **compiles to nothing**. `SourceState` has `#[serde(deny_unknown_fields)]` (`src/template/compile.rs:47-48`) but the per-transition type, `SourceTransition::Structured { target, when }` (`compile.rs:109-115`), has no such attribute and no `context_assignments` field, so serde silently drops the key during YAML deserialization. I compiled `work-on.md` with the local `koto` binary and inspected the cached compiled JSON directly: the compiled `Transition` for `setup_issue_backed`'s `blocked` arm has only `{"target": "done_blocked", "when": {"status": "blocked"}}` — no trace of `context_assignments` or `failure_reason`. `src/template/types.rs:1219-1242` (the W5 compiler-validation doc comment) already knows this surface is unfinished ("templates relying on `default_action` or `context_assignments` may see false positives"), but that comment reads as "the *validator* doesn't check it yet," not "the *field itself does nothing at all*." I did not use `context_assignments` anywhere in my example for this reason. This is likely relevant to whichever lead is covering failure-reason propagation into terminal/blocked states — it's a pre-existing gap, not something this three-path pattern introduces.

Second surprise: I expected `skip_if` to be the mechanism for the happy-path auto-advance in this design, since it's the feature explicitly built for "auto-transition without agent evidence." It isn't needed at all — plain conditional `transitions[].when` referencing `gates.*` already auto-fires without evidence, on the very first pass, because conditional-transition matching was never gated on `fresh_evidence` to begin with (only the *unconditional* fallback is). `skip_if` adds a synthetic `Transitioned` event with `condition_type: "skip_if"` and chains across multiple states in one `advance_until_stop` call — genuinely different, useful for orchestrator boilerplate — but it's solving a different problem (skip an entire state deterministically before any command runs) than "run a command and route on its result" (which plain gated transitions already do).

## Open Questions

- Should the gate in the one-state pattern be allowed to reuse the *action's own exit code* directly, instead of requiring a second, independent shell command to re-derive success? Today `default_action`'s `ActionResult::Executed{exit_code,...}` is captured in a `DefaultActionExecuted` event but never injected into the evidence map the way gate output is — a template author must always write a second command to check what the first one did. Whether that's worth closing is squarely a koto-primitives question for the other round-2 leads (output routing), not something a template pattern can route around.
- For actions with side effects that are expensive or unsafe to probe with a cheap synthetic command (unlike `git rev-parse --abbrev-ref HEAD`), does the one-state pattern still hold up, or does the "gate must independently verify the outcome" requirement become the dominant authoring cost? Worth a follow-up pass against `/execute`'s ~53 instruction sites and `/work-on`'s ~37, categorizing which are cheaply gate-checkable (branch/file/git state) vs. not (arbitrary tool output, PR state, CI state already covered by existing command gates).

## Summary
The three-path model is fully reachable today with zero koto changes: put `default_action` and a command `gate` on one state, add a conditional `transitions[].when: {gates.<gate>.exit_code: 0}` — it fires silently on success (directive never sent) because conditional matching ignores `fresh_evidence`, while an `accepts` block on the same state routes failure into `EvidenceRequired`, which already carries both the directive and the gate's `{exit_code, error}`. The one-state pattern beats a two-state "attempt/fallback" split on every axis (size, mermaid nodes, drift-check surface) since the unconditional fallback can't auto-route on gate failure anyway, so the split state buys no automatic behavior, only a name; what it cannot do — surface the action's own stdout/stderr, or write `failure_reason` via the currently-inert `context_assignments` field — is squarely output-routing and failure-propagation territory for other leads.
