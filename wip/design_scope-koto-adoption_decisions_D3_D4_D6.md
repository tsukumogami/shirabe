# Decisions D3, D4, D6 — inline resolutions

**Resolved inline.** The delegated evaluations for these three died on a session
limit mid-run. Per `references/fixes/sub-agent-dispatch.md`, the
decision-bypass-with-inline-resolution shape applies. Verification that could be
run directly was run; where a claim rests on reasoning rather than a command,
this file says so.

---

# Decision D3: Exit region shape

## Blocked state or self-loop, per exit path

**Chosen: a blocked state for full-run, evidence-guarded self-loops for the
other two.** D1's asymmetry is upheld, for a reason D1 stated and this decision
confirms: a blocked state that re-declares the gate reports the failing check in
its own `blocking_conditions`, while a self-loop reports nothing beyond the
directive. That difference is worth a state only where the refusal is the
feature. The full-run refusal is the feature — it is PRD AC8, the criterion the
reported incident fails. The re-evaluation and abandonment paths refuse for
ordinary reasons (a Decision Record or a force-materialized partial is not yet on
disk) and an author fixes those by writing the file.

**Rejected: blocked states for all three.** Symmetry for its own sake, three more
states, and two of them carry no assertion any test needs.

**Rejected: self-loops for all three,** which is what D1 flagged as reporting the
failure less loudly. It would make AC8 harder to assert against, and AC8 is the
one criterion the whole exit binding exists to satisfy.

## The clean-cancel path

A clean cancel deletes `wip/scope_<topic>_state.md` and must NOT delete
`wip/scope_<topic>_handoff.md` — `/scope`'s security contract enumerates the
handoff as a known target carved out of the cancel, so a later invocation can
resume against it.

A terminal state's directive never crosses the wire, so `done_cancelled` cannot
instruct the deletion. **`bail` performs it** before routing, which is where the
run already knows it is cancelling: `bail`'s gate distinguishes a cancel (no
child intermediate on disk) from an abandonment (an intermediate exists), and the
cancel branch is the one that deletes. `done_cancelled` therefore needs no
cleanup state, and Phase 4 correctly does not run on a cancel.

## R6's two clauses

Clause 2 is free under D1's shape and this is mechanical rather than argued:
each exit path's required fields are declared on that path's own state, so a
field belonging to another path is an unknown field there, and koto refuses
unknown fields at submission before any write. Clause 1 — a missing required
field — is koto's `required: true` handling on the same accepts block.

Not re-verified by command here; koto's refusal of unknown and missing required
fields was exercised by D1's full run to `done_full_run`, which reported both
submission refusals.

## Evidence sets per exit

Conditional-field discipline holds: a field is absent from the state file when
its condition does not hold, never null and never empty.

| Exit state | Required evidence | Written to state file |
|---|---|---|
| `exit_full_run` | `exit_artifacts`, `plan_execution_mode` | `exit: full-run`, both fields |
| `exit_re_evaluation` | `boundary`, `decision_record_sub_shape`, `exit_artifacts` | `exit: re-evaluation`, both discriminators |
| `exit_abandonment` | `triggering_child`, `exit_artifacts` | `exit: abandonment-forced`, `triggering_child`, `partial_phase_reached` |

`plan_execution_mode` is required on the full-run state because a full-run exit
means `/plan` ran or its hop was folded, and either way the mode is known. On the
other two paths it is absent.

## The abandonment marker

Written by `exit_abandonment`, before its gate evaluates, because the gate checks
for the force-materialized artifact and the marker is part of what makes that
artifact well-formed. Its four substitutions come from `triggering_child` (the
state's own required evidence), `partial_phase_reached` (the phase map D4 fixes,
read at the moment of the write), and `chain_started` (the state file). The graph
guarantees `triggering_child` is resolved first because it is required evidence
on the state that writes the marker — the state cannot advance without it.

## Skip interaction

A run that skipped every hop reaches `finalize`, may declare any exit, and if it
declares full-run the `chain_complete` gate fails for all four hops — so it lands
in `full_run_blocked` and its only forward route is `abandon`, reaching
`exit_abandonment`. A partially-skipped run behaves the same way with fewer named
hops. This is PRD AC13, and it is why R9's "a skipped hop satisfies neither limb"
matters: without it, `chain_skipped:` would launder the claim.

---

# Decision D4: Session lifecycle and phase recovery

## Naming scheme

`scope-<topic>`. Fixed literal prefix, reconstructible from the slug alone,
and it begins with a letter for every slug shirabe's `^[a-z0-9-]+$` admits —
which is what let PRD R16's predecessor (a digit-first slug rejection) be
removed. Verified previously: `koto init 2fa-rollout` is refused for a
first-character violation while `koto init scope-2fa-rollout` succeeds.

## Probe and reattach

Verified directly against koto 0.11.6 with an isolated session store:

```
$ koto status scope-nonexistent-topic          # no session
exit=2
{"command":"status","error":"workflow 'scope-nonexistent-topic' not found"}

$ koto init scope-probetest --template scope.md --var TOPIC=probetest
exit=0
{"name":"scope-probetest","state":"setup"}

$ koto status scope-probetest                  # live session
exit=0
{"current_state":"setup","directive":"...","expects":{...}}
```

So the probe branches on the exit code of `koto status scope-<topic>`:

- **exit 0** — a session exists. Reattach: continue from `current_state`. Do not
  init.
- **exit 2** — no session. `koto init` when the ladder decides to run.

`koto init` is therefore never reached for a live session, which means the
collision error below appears only in a genuine cross-worktree race.

## The prohibition, made decidable

The collision error, verbatim:

```
$ koto init scope-probetest ...   # second time
exit=1
{"command":"init","error":"workflow 'scope-probetest' already exists; run `koto session cleanup scope-probetest` to reuse the name, or `koto cancel --cleanup scope-probetest` to stop a running workflow first"}
```

koto's own text recommends the two commands PRD R16 forbids. `/scope` **reports
this error to the author and stops**. It does not remediate.

R14 makes the distinction decidable rather than assumed: the state file records
the session this invocation opened, under a `koto_session:` field carrying the
name and the ISO timestamp of the `init` that created it. A session named in the
current topic's state file with a matching name is this run's; anything else is
not, and R16's prohibition attaches to "not recorded here" rather than to a
judgment about who is running what.

## Phase recovery

D1's declared state-to-phase map, confirmed. The map lives **in the template**,
as a `phase:` key per state, because that keeps it adjacent to the states it
describes and lets R26's static check assert every state has a row without
reading a second file. `/scope` reads it by taking `current_state` from `koto
status` and looking up its row.

The alternative — a naming convention such as a `p2_` prefix — was rejected: it
encodes the map in identifiers, so renaming a state silently changes which phase
it reports, and there is nothing for a check to assert.

## The `--no-cleanup` decision

**Do not pass `--no-cleanup`.** PRD R23 is written against the surface that
survives the trade, and the author's ruling during exploration accepted a
machine-local record rather than a durable copied one. Passing `--no-cleanup`
preserves the richer event log and forfeits koto's terminal index entry, and the
index entry is what a later `koto workflows` listing reads. Since the record this
design promises is per-hop gate outcomes rather than evidence values, and those
reach the surviving surface, the trade buys nothing R23 needs and costs the
listing.

## Commit ordering

R17's commit happens **inside the hop state, after the child returns and after
the hop's gate evaluates**. The gate reads the working tree and does not care
whether the artifact is committed, so gating first keeps the gate's result
independent of git state; committing second means a failed gate does not produce
a commit claiming a hop landed. New commit on the run's own branch naming the
hop, no push.

## Fresh-clone path

Session absent, artifacts committed. `koto status scope-<topic>` exits 2, so no
reattach. The resume ladder then runs exactly as today against artifact status at
canonical paths — sixteen of its twenty rows never consulted a session in the
first place. `phase_pointer:` is written from `/scope`'s own phase per R11's
no-session clause. This is why R17 matters: an uncommitted artifact is invisible
to a fresh clone, and the ladder's durable anchor would be empty.

---

# Decision D6: Test and check construction

## The harness changes (R24)

Four changes to `scripts/run-evals.sh`, each independently testable and each an
acceptance criterion already: read `expectations` with an `assertions` fallback
so the five suites using the old name keep working; materialize `files:`
preconditions into the scenario's working tree; copy post-run filesystem state
into the scenario's output directory so assertions grade against the tree rather
than against narration; and exit non-zero when a scenario grades zero
assertions. The fourth is what let the first defect survive unnoticed.

Rate reporting across N runs is the fifth clause R24 gained during the PRD jury,
and it is what makes AC34 implementable — the runner currently writes
auto-incrementing iteration directories and aggregates nothing across them.

## The deterministic PR-path test (R25)

Modelled on `skills/execute/scripts/settled-branch-record_test.sh`, which already
drives real koto sessions on every pull request. Three assertions:

1. A full-run claim submitted as evidence with three hops lacking both artifact
   and recorded fold does not reach a terminal, and the blocked state names the
   failing check. D1 established that re-declaring the gate on the blocked state
   populates its own `blocking_conditions`, so the test may key on that as well
   as on the directive.
2. After the run has ended, a walked hop and a bypassed hop are distinguishable
   in the per-hop record — gate evaluations present for the first, absent for the
   second, with a typed directed-transition entry beside it.
3. The general-form reduction argument is absent from what the session delivers
   before the first hop and present at the fold state.

Mechanics: session storage confined to the test's own temporary store via
`KOTO_SESSIONS_BASE`; skip with a message naming the missing binary when koto is
absent, with the CI job installing koto explicitly so a skip cannot mask a
missing dependency; read stdout only, since session discovery emits parse
warnings for unrelated sessions on stderr.

## The static check (R26)

Two predicates over `skills/*/koto-templates/*.md`, skipping files without YAML
frontmatter so the two `.mermaid.md` diagrams are excluded:

- **Universal:** fail any non-terminal state carrying an `accepts` block with no
  `when`-guarded transition. Terminals are exempt because a terminal cannot have
  a transition, which is why `done_blocked` in both shipped templates is a false
  positive rather than a defect.
- **`/scope` only:** fail any hop-completion gate command referencing `wip/scope_`
  or an agent-submitted evidence field. This is PRD R8's prohibition in
  mechanical form and it is what gives AC12 a vehicle.

Four states in the shipped templates violate the universal predicate today —
`research` in `/work-on`, and `escalate`, `escalate_dirty_merge_state`,
`escalate_upstream_drift` in `/execute`. They are filed as
tsukumogami/shirabe#333 and tsukumogami/koto#202. AC33 requires each to be fixed
or listed in an allowlist the check reads with an issue reference beside it, so
the check can land without failing on its own introduction.

## The model-graded scenarios (R27)

Two, both asserting on files after a run, one of them negatively: no document
under `docs/` claims an artifact was folded away for a hop with neither that
artifact nor a recorded fold behind it. That negative is the assertion that
separates absorbing from asserting, and it is the one closest to the reported
incident. Run at n≥5, reported as a rate against a threshold stated in the suite,
never gating a pull request — they grade a stochastic process and one red run is
a reason to look.
