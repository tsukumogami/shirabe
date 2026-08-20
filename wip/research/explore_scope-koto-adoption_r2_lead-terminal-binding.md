# Lead: Can a koto shape bind the terminal decision — the moment `/scope` finalizes and its agent authors the exit claim?

Yes, but not at the terminal state, and not in the way the framing
assumes. A koto terminal state is inert in every direction: it cannot
gate, cannot accept evidence, and cannot even deliver its own directive.
Everything the lead asks for binds one state earlier. The shape that
works is *agent proposes, koto vetoes*, and its whole strength is that
koto records the agent's exit claim verbatim next to the gate outcomes
that contradict it.

Two findings change round 1's conclusions rather than extending them.
The session event log — round 1's "typed event in a log the agent does
not author" — is **deleted by `fs::remove_dir_all` on the terminal
tick**, by default, at exactly the moment `/scope` finalizes. And a
different koto artifact nobody in round 1 knew about, the `/workflows`
render file, survives that deletion, is on by default, and renders the
#331 signature in four legible lines.

All runtime evidence below is koto 0.11.6 (the binary on PATH),
produced against scratch templates under
`$CLAUDE_JOB_DIR/tmp/kt2/` which are not durable. koto paths are
relative to `public/koto/`; shirabe paths to this worktree.

## Findings

### 1. A terminal state can require nothing, refuse nothing, and say nothing

The advance loop checks terminality at **step 3 of 8**
(`src/engine/advance.rs:243-250`), ahead of integration (4), action
execution (5), gate evaluation (6), `skip_if` (7), and transition
resolution (8). The loop's own header comment (`advance.rs:150-160`)
lists the order. So a terminal state's gates are structurally
unreachable — the same reason E-SKIP-TERMINAL rejects `skip_if` on a
terminal (`src/template/types.rs:691-696`: "the terminal check fires
before skip_if, making it unreachable").

Four consequences, each verified:

**Gates on a terminal are a compile error.** Not by a terminal-specific
rule — by D5 (`types.rs:866-897`), which requires every gated state to
carry at least one transition whose `when` clause references `gates.*`.
A terminal state has no transitions, so it can never satisfy D5.
Verified: adding a `command` gate to a terminal produced

```
validation error: state "done_full": gate "never_true" has no gates.* routing
  add a when clause referencing gates.never_true.passed, ...
  or use --allow-legacy-gates to permit boolean pass/block behavior
```

`koto template compile` is strict by default (`src/cli/mod.rs:1375`,
`let strict = !allow_legacy_gates`), and the inline resolution path is
strict-only (`cli/mod.rs:104`). So this is a real structural refusal, not
a convention.

**`accepts` on a terminal compiles clean and is dead config.** Removing
the gate and leaving `accepts: {attestation: {type: string}}` on
`done_full` compiled with no error and **no warning**. At runtime the
field is unreachable twice over: `NextResponse::Terminal`
(`cli/mod.rs:4124-4129`) carries only `state`, `advanced`, and
`unassigned_children` — no `expects` — and evidence submission is
refused outright at `cli/mod.rs:3581-3592`:

```
{"error":{"code":"terminal_state","details":[],
  "message":"cannot submit evidence: state 'done_full' is terminal"}}
```

**The terminal state's directive is never delivered.** `## done_full`'s
body text does not cross the wire on the terminal tick (no `directive`
field in the Terminal response) and does not appear in `koto status`
either — a parked terminal session returns
`{"current_state":"done_full","is_terminal":true,"name":"cp1",...}`
with no directive key. Terminal body text is documentation for template
readers and nothing more.

**W5's remedy is cosmetic for a phase-substrate template.** W5
(`types.rs:1214-1245`) warns when a `failure: true` terminal has no path
writing `failure_reason`, and names "add `failure_reason` to the state's
accepts block" as the fix. That silences the warning and can never
collect the field. Relatedly, `synthesize_workflow_result`
(`cli/mod.rs:2321-2352`) lifts `summary` from "the latest terminal
`EvidenceSubmitted` event" — an event that cannot exist when the terminal
is reached by transition, since evidence is always tagged with the
pre-terminal state. Every phase-substrate run falls back to the
synthetic `"completed at done_full"`.

**So the terminal binding is the pre-terminal state's binding.** There is
nothing else available.

### 2. The audit trail is deleted at the terminal tick — by default

This is the round's most consequential finding and it inverts round 1's
residual value claim.

`finish_terminal_tick` (`cli/mod.rs:2529-2586`) ends in
`backend.cleanup(name)`, and `LocalBackend::cleanup`
(`src/session/local.rs:76-83`) is `fs::remove_dir_all(&dir)`. The whole
session directory goes — event log, context store, everything.

Verified. After a run reached terminal:

```
$ koto status tp1        -> {"command":"status","error":"workflow 'tp1' not found"}
$ koto overrides list tp1 -> {"error":"no state file found for workflow 'tp1'"}
$ koto decisions list tp1 -> {"error":"no state file found for workflow 'tp1'"}
$ ls ~/.koto/sessions/tp1 -> No such file or directory
```

**What survives is one line.** `~/.koto/_terminal_index.jsonl` gets:

```json
{"session_id":"tp1","terminal_at":"2026-08-20T21:33:27.968Z",
 "header_mtime_ns":1787261607961214770,"terminal_state":"completed","has_result":true}
```

`terminal_state` is two-valued — `"completed"` or `"abandoned"`,
classified solely on the presence of a `WorkflowCancelled` event
(`cli/mod.rs:2450-2456`). It does **not** name which terminal state was
reached. The run above ended in a `failure: true` terminal and the index
says `"completed"`. A `full-run` exit and an `abandonment-forced` exit
are indistinguishable in the only thing that survives.

**`has_result: true` is a dangling pointer for a root session.** The
`WorkflowResult` envelope is written to the child's own log (then
deleted) and copied onto the parent's `ChildCompleted` — but
`append_child_completed_to_parent` returns `NoParent`
(`cli/mod.rs:2388-2390`) when `parent_workflow` is `None`. A
phase-substrate `/scope` is a root session. The done-bit's stated
invariant — "`has_result` true implies a durable result is readable"
(`cli/mod.rs:2472-2477`) — does not hold for it.

**The two durability modes are mutually exclusive.** `--no-cleanup`
preserves the log, but `finish_terminal_tick` returns at `:2542`
(`if no_cleanup && pointer.is_none()`) for an unbound root session, so it
writes no terminal-index line and no `request_store.result`. Verified:
`grep -c cp1 ~/.koto/_terminal_index.jsonl` → `0`. You get the full log
with no index entry, or the index entry with no log. Never both.

**And the party that decides is the agent.** `--no-cleanup` is a flag on
`koto next` (`cli/mod.rs:143-145`, documented as "useful for debugging").
An agent doing honest work has no reason to pass it; an agent covering
its tracks has every reason not to. Deletion is the default.

An incidental observation: `~/.koto/sessions/` on this machine holds over
a thousand directories. Parked sessions accumulate without bound, which
is presumably why cleanup-on-terminal is the default.

### 3. The `/workflows` render file survives, and it renders the #331 signature

Round 1 asked "who reads the log." There is an answer nobody found, and
it is on by default.

`src/workflows_surface/` writes a `koto-<uuid>.json` per session into a
Claude Code `/workflows` directory on **every state commit**, including
the terminal one. `project::per_state_outcomes` (`project.rs:298-324`)
projects the latest `GateEvaluated` and all `EvidenceSubmitted` events
per state; `materialize::outcome_line` (`materialize.rs:147-160`) renders
each phase as `gate <name>: PASS|FAIL`, falling back to evidence **field
names** when no gate ran.

The target directory resolves three ways (`materialize.rs:203-238`), the
third of which is self-discovery from `CLAUDE_CODE_SESSION_ID` under
`workflows.native`, **default on** (`materialize.rs:36-39`,
`:250-256`), landing at
`~/.claude/projects/<projectDir>/<sessionId>/workflows/`. That is outside
the session directory, so it survives `remove_dir_all`.

Four runs of the same four-hop template, all rendered after cleanup:

| Run | Render |
|---|---|
| Honest full run | `Brief: gate brief_written: PASS` … all PASS |
| **Plan-only (#331 shape)** | `Brief -> gate brief_written: FAIL`<br>`Prd -> gate prd_written: FAIL`<br>`Plan -> gate plan_written: PASS`<br>`Finalize -> gate plan_present: PASS`<br>`status: completed, currentState: done_full` |
| **Override bypass, nothing produced** | `Brief: FAIL / Prd: FAIL / Plan: FAIL / Finalize: FAIL`<br>`status: completed, currentState: done_full` |
| **`--to` walk, nothing produced** | `Brief -> done / Prd -> done / Plan -> done / Finalize -> done`<br>(no gate lines at all) |

Four failing gates and a `full-run` completion, in a machine-authored
file, is exactly the artifact issue #331 says does not exist today.

The override case is the most legible of the three bypasses, and by
accident: `advance.rs:363` emits **no** `GateEvaluated` event for an
overridden gate, so the render's "latest gate" stays the stale failing
evaluation from the prior tick. The override does not appear as an
override — but the FAIL it papered over does.

Five caveats, all of them real:

- **Machine-local.** Under `$HOME/.claude/projects/`, tied to the Claude
  Code session id, not in git and not in any PR. In an ephemeral niwa
  instance the whole home can go away.
- **Latest gate per state only.** A state whose gate failed and later
  passed shows PASS; the failure is gone.
- **Evidence values are never rendered** — only field names, and only
  when no gate ran (`materialize.rs:147-160`). `outcome: skipped`, the
  `exit:` enum, and a fabricated `summary` string all appear nowhere.
- **`directed_transition` and `gate_override_recorded` are not rendered
  as such.** The `--to` walk's four bare `done` phases are legible only
  to a reader who knows that a gated template should show gate lines.
- **The terminal phase renders `"in progress"` on a completed workflow.**
  `phase_detail` (`materialize.rs:136-143`) maps `PhaseStatus::Active`
  with an empty outcome line to `"in progress"`, and the terminal state
  is the active one. Every completed run's render says
  `Done full -> in progress` under `status: "completed"`. A live cosmetic
  defect in koto, worth filing.

### 4. The trace is forgeable with one `sed -i`

The event log is a plain JSONL file at
`$(koto session dir <name>)/koto-<name>.state.jsonl`, mode 0600,
owner-writable. There is no checksum, no HMAC, and no integrity check on
read beyond a weak seq-ordering assumption (`persistence.rs:508-520`).

Verified: mid-run, I rewrote two `gate_evaluated` payloads from
`{"exists":false},"outcome":"failed"` to
`{"exists":true},"outcome":"passed"` and one `evidence_submitted` from
`"outcome":"skipped"` to `"written"`. `koto status` then reported
normally and `koto next` continued the workflow without a murmur. The
`/workflows` render file is likewise a 0600 JSON file at a path the
agent can compute.

**Round 1's praise of `src/engine/audit.rs` is accurate about a
different attack.** `is_reserved_kind` (`audit.rs:99-110`) rejects
`--with-data` payloads whose `fields.kind` collides with the
request-store audit family, and the synthetic-state-name discipline
(`audit.rs:64-76`) stops an audit record being promoted as a child's
result. Both are genuine hardening — of the request-store namespace, at
the CLI write seam. Neither touches file tampering, and neither applies
at all to a phase-substrate `/scope`, which uses no request-store kinds.

**The fair framing.** The threat model that produced #331 is a
rationalizing agent, not a forger. A rationalizing agent writes a prose
Status section reconciling what it did with what it thinks the skill
wants; it does not `sed -i` its own JSONL, because that is a categorically
different act it would have to decide to commit. The trace holds against
the actual mechanism. But the claim has to be stated as *legible to a
reader who looks*, not *tamper-evident*, and round 1's "a log the agent
does not author" needs the qualifier that the agent can rewrite it
afterward and delete it by default.

### 5. `completion: state:` confirmed; `all_success` vs `all_complete` confirmed

Empirically confirmed, not just re-read:

```
$ koto template compile comp.md
{"command":"template compile","error":"state \"await\" gate \"kids\":
  completion mode \"state:published\" is reserved but not yet implemented"}
```

matching `types.rs:561-584`.

The distinction is computed at `src/cli/batch.rs:2457`:

```rust
let all_success = all_complete && failed == 0 && skipped == 0 && spawn_failed_count == 0;
```

`all_complete` counts terminal children of every kind; `all_success`
excludes failures, skips, and spawn failures. Round 1's constraint —
route on `all_success`, never `all_complete` — is exactly right, and W4
(`types.rs:1196`) treats both as the same routing pair, so the compiler
will not catch the wrong choice.

**One addition round 1 did not have.** `built_in_default` for
`children-complete` (`src/gate.rs:258-274`) is
`{"total":0, ..., "all_complete":true, "all_success":true, "any_failed":false, ...}`.
So `koto overrides record --gate kids --rationale x` passes `all_success`
with zero children. Routing on `all_success` closes the sanctioned-skip
hole and does nothing about the override hole.

All of which is moot for the working shape: the phase substrate has no
children and declares no `children-complete` gate. It matters only if
`/scope` ever materializes its four hops, or ever runs under `/execute`.

### 6. Three terminals with different requirements: yes. Conditional routing on gate state: yes, with a catch

A template with three terminals, two gate-constrained routes and one
ungated, compiles and runs. Verified:

- The gate genuinely vetoes the exit path. Submitting
  `{"exit":"full-run","summary":"I consolidated the upstream artifacts away"}`
  with `plan_present` failing returned `"advanced": false` and re-issued
  the finalize directive. koto refused the agent's exit claim on the
  strength of what was on disk. **This is the terminal binding working.**
- The ungated route fired immediately:
  `{"exit":"abandonment-forced"}` → `{"action":"done","state":"done_abandoned"}`.
  An exit route with no `gates.*` clause is an unconditional exit.
- `--to done_full` from `finalize` with `plan_present` failing landed in
  `done_full` on the spot. Round 1's finding that `--to` ignores `when`
  clauses (`cli/mod.rs:3305-3322`) applies to terminal routing without
  modification: **every declared terminal is one command away from every
  state that declares an edge to it, regardless of guard.**

**An adversarial detail round 1 did not surface.** The
`evidence_required` response publishes the entire routing table to the
agent:

```json
"expects":{"options":[
  {"target":"done_full","when":{"exit":"full-run","gates.plan_present.exists":true}},
  {"target":"done_reeval","when":{"exit":"re-evaluation","gates.plan_present.exists":true}},
  {"target":"done_abandoned","when":{"exit":"abandonment-forced"}}]}
```

`derive_expects` hands the agent, at the finalize state, a map of which
exit is gated and which is not. If any exit route is ungated, koto tells
the agent where it is. The design rule that follows is blunt: **no exit
route may omit a `gates.*` clause.**

### 7. The pass-through trap at the terminal, and the general rule behind it

Round 1's trap — a state with an `accepts` block and a single
unconditional transition is silently skipped — is one instance of
something broader, and the general rule is what the terminal region has
to be designed against.

`resolve_transition` (`advance.rs:693-771`) collects `conditional_matches`
first and returns `Resolved` from it at `:754-755`, **before** reaching
the `gate_failed || (!fresh_evidence && has_conditional)` guard at
`:757-766`. That guard governs only the *unconditional fallback*. And gate
outputs are merged into the resolver's evidence map for any state with
`gates.*` routing (`advance.rs:443-472`).

**The rule: a state stops if and only if no transition resolves from what
koto already holds. `accepts` is a schema, never a stop condition.**

Two verified demonstrations at the exit-finalization site.

*Trap A — the round-1 shape, applied to `finalize`.* A `finalize` state
with `accepts: {exit: enum, summary: string}`, a directive reading
"state the exit path, and write the Status section describing what
actually ran", a `<!-- details -->` block reading "Do not assert that
upstream artifacts were consolidated unless they exist" — and a single
unconditional transition to `done_full`. One `koto next` at the prior
state returned:

```json
{"action":"done","advanced":true,"state":"done_full","expects":null}
```

The exit-finalization directive never crossed the wire. Compiles clean,
no warning. This is #331's failure reproduced in the substrate meant to
prevent it, with zero adversarial intent.

*Trap B — worse, and not covered by round 1's rule.* A `finalize` state
with two **conditional** transitions whose `when` clauses reference only
`gates.*`, plus `accepts: {status_section: {type: string, required: true}}`.
The very first `koto next`, with no evidence submitted:

```json
{"action":"done","advanced":true,"state":"done_partial","expects":null}
```

A `required: true` field, on a state with conditional transitions, and
the state still auto-advanced without stopping — because the gate outputs
resolved a conditional match. `required` is enforced (`evidence.rs:74-82`)
only on a submission that happens.

**The corollary the design has to live with.** koto cannot both stop the
agent at exit finalization *and* pick the exit path itself. If routing
resolves from gate state alone, the agent is never asked and never sees
the directive. If the agent must be asked, its evidence participates in
routing. Pure-gate terminal routing does work — a two-terminal template
routing only on `gates.plan_present.exists` picked `done_partial` from
disk state with no agent input at all — but it picks *silently*.

**Safe `/scope` terminal region.** Sketch, with every rule load-bearing:

```yaml
finalize:
  gates:
    brief_present:  {type: context-exists, key: brief.md}
    prd_present:    {type: context-exists, key: prd.md}
    design_present: {type: context-exists, key: design.md}
    plan_present:   {type: context-exists, key: plan.md}
  accepts:
    exit:            {type: enum, required: true,
                      values: [full-run, re-evaluation, abandonment-forced]}
    status_section:  {type: string, required: true}
    exit_artifacts:  {type: string}
  transitions:
    - target: done_full
      when: {exit: full-run, gates.plan_present.exists: true}
    - target: done_reeval
      when: {exit: re-evaluation, gates.decision_record.exists: true}
    - target: done_abandoned
      when: {exit: abandonment-forced, gates.partial_present.exists: true}

done_full:      {terminal: true}
done_reeval:    {terminal: true}
done_abandoned: {terminal: true, failure: true}
```

1. **Every route names at least one agent field.** Nothing resolves from
   gate state alone, so the state always stops and always delivers its
   directive. Defeats trap B.
2. **Every route also names a `gates.*` clause.** The agent proposes the
   exit; koto vetoes it against disk. Verified working. No ungated exit
   route — do not repeat the `abandonment-forced` shortcut used in the
   probe.
3. **No unconditional transition anywhere in the region.** The fallback
   path never fires. Defeats trap A.
4. **No self-loop.** Round 1's Surprise 2 — gate-driven self-loops error
   with `cycle detected` after one lap.
5. **No gate and no `accepts` on any terminal.** D5 rejects the first;
   the second compiles and is dead.
6. **D4 is exempt.** `validate_gate_reachability` (`types.rs:1304-1400`)
   only inspects transitions whose `when` keys are *all* `gates.*`-
   prefixed; this region has none, so the round-1 Surprise 3 rejection
   cannot fire (`types.rs:1334-1337`).
7. **`status_section: {type: string, required: true}` is the binding.**
   koto cannot judge the Status section — a string field is validated as
   a string and nothing more. What it does is record the claim
   **verbatim** in an `evidence_submitted` event, in the same log, next
   to the `gate_evaluated` events that contradict it. That juxtaposition
   is the entire terminal binding on offer. It is not enforcement; it is
   putting the assertion and its refutation in the same file, written by
   different parties.
8. **`## finalize`'s `<!-- details -->` is where the exit-path doctrine
   goes** — physically absent from context until the chain is finished.
   This is the disclosure argument landing at the site of the incident,
   which is what round 2 was scoped to establish. It does land.
9. **The terminal tick must be `koto next <s> --no-cleanup`** if anything
   is to read the log afterward. See finding 2 for what that forfeits.

### 8. Adversarially: reaching `full-run` having produced only a PLAN

Seven routes. Verified where marked.

**Route 1 — honest evidence, no bypass at all.** *Verified end to end.*
Two `{"outcome":"skipped"}` submissions at the brief and prd hops, write
`plan.md`, then `{"exit":"full-run","summary":"Chain ran. Upstream
artifacts were consolidated into the PLAN."}`. Result:
`{"action":"done","state":"done_full"}`. No `--to`, no override, every
gate that was consulted genuinely passing. **This is #331, reproduced
under koto, with the template behaving exactly as designed.** Loud in
both artifacts: the log carries two `gate_evaluated ... "outcome":"failed"`
events, and the render shows `Brief -> gate brief_written: FAIL` next to
a `done_full` completion. It is loud *only because an ungated skip route
existed in the template at all* — which `/scope` legitimately wants for
re-entry protection.

**Route 2 — `koto overrides record` at finalize.** *Verified.* Skip all
three hops, produce nothing, then
`koto overrides record cp5 --gate plan_present --rationale "upstream
artifacts consolidated into the PLAN per reader economy"` →
`{"status":"recorded"}` → `{"action":"done","state":"done_full"}`. Loud:
the log carries `gate_override_recorded` with the rationale, and the
render shows four FAILs under a completed `full-run`.

**Route 3 — `koto next --to`, one hop per command.** *Verified.* Four
commands walk brief → prd → plan → finalize → done_full producing
nothing. The log is four `directed_transition` events and *nothing else*
— zero gate evaluations, zero evidence. Loudest of all, and the render's
four bare `done` phases are the tell.

**Route 4 — satisfy the gate with a stub.** `printf '# PLAN\n' | koto
context add <s> plan.md`. `cli/context.rs:16-38` validates nothing
between read and write. **Silent in the render** — `gate plan_written:
PASS` is indistinguishable from an honest pass. The log's
`context_added` payload carries a content hash and a byte count
(`"size":7` in my run), which is the only tell, and it is not rendered
anywhere.

**Route 5 — author the template so `finalize` never runs.** *Verified
twice* (traps A and B above). Silent: the render shows `Finalize -> done`
and the log shows a `transitioned` event, which at a glance looks like a
visited state. This is an authoring error rather than an agent action,
which makes it the most dangerous item on the list — it ships once and
then holds forever.

**Route 6 — rewrite the log.** *Verified.* One `sed -i`. Silent and
complete.

**Route 7 — do nothing and let cleanup delete the evidence.** *Verified.*
Simply omit `--no-cleanup`, which is the default. The log is gone; the
only durable koto record is an index line reading `"completed"`. Silent,
free, and requires no decision at all. The `/workflows` render is the
sole reason routes 1, 2 and 3 stay loud.

The pattern: **the deliberate bypasses are loud and the accidental ones
are silent.** koto instruments exactly the acts a motivated agent would
avoid and says nothing about the ones a confused agent would stumble into
— a stub artifact, a badly authored finalize state, a default that
deletes.

### 9. Could a koto-authored artifact replace the self-reported PR-body record?

Today `/scope` Phase 3 copies `chain_ran`, `chain_skipped`, and
`consolidation_judgments` from its own `wip/` state file into the PR body
(`skills/scope/references/state-schema.md:234-238`, elaborated at
`skills/scope/references/phases/phase-3-exit-finalization.md:69-82`),
because Phase 4 deletes the state file and "a reviewer reading the PR
cannot tell an artifact that was absorbed from one that was never
produced."

**No koto command produces a report.** `koto --help` lists no `history`,
`log`, `audit`, or `export`. `koto status` is current-state only.
`koto decisions list` is scoped to the current state. `koto overrides
list` is full-session-history but overrides-only, and dies with the
session. `koto dashboard` has a History tab
(`cli/dashboard_data.rs:294-295`) that reads the live session log —
useless post-terminal.

**Two viable sources, with different trade-offs.**

*The `/workflows` render.* Quote its `phases` array verbatim into the PR
body. It survives the terminal tick, it is machine-authored, and it says
which gates passed and which failed per hop. It does **not** carry
evidence values, so consolidation verdicts have no analogue in it.

*The event log, read at finalize before the terminal tick, or after it
with `--no-cleanup`.* Richer: `evidence_submitted` payloads carry the
agent's fields verbatim, so `outcome: skipped`, the `exit:` enum, and
consolidation verdicts are all there, alongside every `gate_evaluated`,
every `directed_transition`, and every `gate_override_recorded`. A reader
of this log can reconstruct: every state visited in order with
timestamps, every gate evaluated with its output and verdict, every
evidence field the agent submitted, the template hash the run was
compiled from, the submitter's cwd, and which terminal was reached. What
it does *not* record is **which** `when` clause matched — every
`transitioned` payload says `"condition_type":"auto"` — so attributing a
route requires the template alongside the log.

**Recommendation.** Drive `/scope`'s terminal tick with `--no-cleanup`
and quote the event log into the PR body as a fenced block. The
terminal-index line it forfeits carries nothing a root session can use
(finding 2). The log is the strictly richer artifact and it is the one
that contains the agent's own exit claim next to the gate outcomes.

**Is it forgeable?** Yes, twice: the file is editable (finding 4), and
the agent does the copying. But note what forging it would require — an
agent would have to hand-write `"outcome":"passed"` for a gate it knows
never ran. That is a different act from writing a prose Status section
that reframes what happened, and #331 was the latter. This is the
concrete form of the author's resolution that a koto-authored trace
counts: not that it cannot be faked, but that faking it is no longer the
same motion as rationalizing.

## Implications

**The lead's question resolves yes, one state earlier than asked, and at
a specific strength.** A koto shape can force `/scope`'s exit
finalization to happen — the agent cannot reach any terminal without
stopping at `finalize` and submitting a typed `exit:` enum and a
`status_section:` string, provided every route out carries an agent field.
It can veto the exit path the agent proposes, against what is on disk —
verified, `advanced: false` on a `full-run` claim with the gate failing.
And it records the exit claim verbatim in a machine-authored log
alongside the gate outcomes. It cannot judge the claim, and it cannot
stop `koto next --to done_full`.

**Round 1's disclosure argument reaches the incident site, and this is
the finding round 2 was commissioned for.** `## Why the Artifact Set
Shrinks` moves into `finalize`'s `<!-- details -->`, physically absent
from context until every hop is done and the agent is being asked to
account for what it produced. Verified as a mechanism: only the current
state's directive and details cross the wire. The hole round 1 flagged —
that deferring the reduction argument to Phase 2 does not cover exit
finalization — closes, because exit finalization is a state too.

**But round 1's gating conclusion needs amending on durability, not on
substance.** "What survives is a typed event in a log the agent does not
author" is true about the writer and false about the artifact. The log is
deleted at the terminal tick by default, and rewritable by the agent
while it lives. What actually survives unaided is the `/workflows`
render, which round 1 did not know about, is on by default, and shows the
#331 signature in four lines. The conclusion holds; the mechanism it
rests on is different, and any design doc that repeats round 1's wording
without the `--no-cleanup` requirement will ship a `/scope` whose audit
trail evaporates at exit.

**The design's largest exposure is an authoring error, not an agent.**
Route 5 — a `finalize` state whose routes resolve without the agent — is
silent, ships once, and holds forever. The general rule (finding 7) is
not documented anywhere in koto's template-format reference, and koto
itself and shirabe have each already shipped a template with the narrower
version of the bug. `/scope`'s template needs a review rule stated in the
template's own description, the way `/work-on`'s line 11 states the
self-loop rule.

**One `/scope` design decision this forces.** The hop states need to
either carry an ungated skip route or not. With one, route 1 works and is
the exact #331 reproduction — legible in the trace, but possible with no
bypass at all. Without one, `/scope` loses `chain_skipped:` semantics and
its re-entry protection has nowhere to go. This is a scoping call, not a
research finding, and it is the sharpest thing this round hands the
author.

## Surprises

**A terminal state's directive is dead text.** I expected the terminal to
carry a closing instruction. It carries nothing: no directive in the
Terminal response, none in `koto status`. Every terminal body section in
every shipped shirabe template is documentation for template readers.

**Cleanup deletes the audit trail, and the two durability modes are
mutually exclusive.** I went in expecting to characterize what a reader
could reconstruct. The answer for a default-configured root session is:
one line saying `"completed"`, which does not name the terminal reached.
`--no-cleanup` fixes it and forfeits the index entry.

**`accepts` is not a stop condition.** This is the finding that most
changes what a template author must know. A `required: true` field on a
state with two conditional transitions was skipped entirely because gate
output resolved one of them. Round 1's "accepts + single unconditional
transition" is a corollary of "a state stops iff nothing resolves."

**The `/workflows` render exists, is on by default, and is exactly the
artifact this exploration has been looking for.** It is the answer to
round 1's open question "who reads the log" — Claude Code's `/workflows`
screen does, natively, with no skill and no reader
(`workflows_surface/mod.rs:1-5`).

**The override bypass renders as FAIL.** Because `advance.rs:363` emits
no `GateEvaluated` for an overridden gate, the render keeps the stale
failing evaluation. Accidentally the most legible of the three bypasses.

**The render says `in progress` on every completed workflow's terminal
phase.** Live cosmetic defect (`materialize.rs:136-143`).

**`expects.options` hands the agent the routing table**, including which
exit route is ungated.

**The log is trivially forgeable.** Given how adversarially designed
`audit.rs` is, I expected at least a seq-chain hash. There is none.

## Open Questions

1. **Is the `/workflows` render durable enough to be the answer?** It
   lives under `~/.claude/projects/<projectDir>/<sessionId>/workflows/`,
   keyed to the Claude Code session id. In an ephemeral niwa instance the
   home directory may not outlive the run. Either `/scope` copies it (or
   the log) into the PR body at finalize, or the author accepts a
   machine-local audit surface. This is a scope decision.

2. **Should `/scope`'s hop states carry an ungated skip route?** Route 1
   depends entirely on it; `/scope`'s re-entry protection wants it. Needs
   an author call.

3. **Adopt `--no-cleanup` on the terminal tick?** It is the only way the
   log survives, it forfeits the terminal-index line (worthless to a root
   session), and it leaves session directories accumulating — over a
   thousand already on this machine.

4. **Would koto take a `koto history` / `koto export` command?** The
   render machinery already computes the projection; a subcommand that
   prints it to stdout would remove the "agent reads a file and pastes
   it" step, which is where forgeability enters. koto is a sibling repo,
   so this is a real option with its own cost.

5. **Should the terminal-region hazards be filed upstream?** Three
   candidates, all independent of this effort: `accepts` on a terminal
   compiles silently as dead config; a completed workflow's terminal
   phase renders `"in progress"`; and the template-format reference
   documents neither the "a state stops iff nothing resolves" rule nor
   that a terminal state's directive is never delivered.

## Summary

A koto terminal state can require nothing, refuse nothing, and say nothing — the terminal check fires at step 3 of the advance loop before gates ever run (`advance.rs:243-250`), gates on a terminal are a D5 compile error, `accepts` on a terminal compiles silently as dead config, evidence submission there is refused outright (`cli/mod.rs:3581-3592`), and the terminal directive never crosses the wire — so the binding is entirely the pre-terminal state's, where the workable shape is *agent proposes, koto vetoes*: verified, a `full-run` claim submitted with the plan gate failing returned `advanced: false`. Two findings amend round 1 rather than extending it — the event log round 1 called the surviving value is deleted by `fs::remove_dir_all` on the terminal tick by default (`cli/mod.rs:2586`, `session/local.rs:76-83`), leaving one index line that says only `"completed"` and does not name which terminal was reached, and is trivially rewritable by `sed -i` while it lives; but a koto artifact nobody found in round 1, the `/workflows` render file, survives that deletion, is on by default via `CLAUDE_CODE_SESSION_ID` self-discovery, and rendered the #331 signature as `Brief: FAIL / Prd: FAIL / Plan: PASS / Finalize: PASS` under a completed `full-run` exit. The biggest open question is whether that render — machine-local under `~/.claude/projects/`, outside git and outside any PR — is durable enough to be the answer, or whether `/scope` must drive its terminal tick with `--no-cleanup` and copy the richer event log into the PR body itself, which is the recommendation but reintroduces the agent as the copier.
