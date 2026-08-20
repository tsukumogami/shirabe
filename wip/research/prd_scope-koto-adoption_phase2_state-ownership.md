# Lead: State ownership

Scope: does `/scope` keep `wip/scope_<topic>_state.md` alongside a koto session,
or does one absorb the other? Answered field by field, with the koto mechanisms
named and verified empirically on koto 0.11.6 where verification was possible.

## koto's five candidate stores, and what each actually is

Named up front because the classification column below is meaningless without
them. Four of the five were probed on a live koto session; the findings that
came out of that probing are not all what the prior rounds recorded.

**K-pos — session current state.** `koto status <name>` returns
`{current_state, directive, expects, is_terminal}`. Reachable from any cwd and
any branch by session name: `~/.koto/sessions/` is a flat, home-global
directory (`koto:src/session/local.rs:34-45`), not a per-repo or per-branch
one. Verified: `koto status statprobe` returned the same payload from
`/home/dgazineu` as from the session's own working directory. Deleted with the
session at the terminal tick.

**K-ev — evidence submitted at a state.** An `accepts` block declares typed
fields (`enum` with `values`, `string`, `number`, `boolean`, each with
`required`), submitted via `koto next --with-data '<json>'`. Three enforcement
behaviors verified live:

- unknown field → `invalid_submission`, `unknown field "bogus_field"`
- out-of-enum value → `value "maybe" is not in allowed values ["absorb", "keep"]`
- missing `required` field → `required field missing`

**Evidence carries arbitrary prose.** The `--var` allowlist constraint the
prior rounds recorded (`template-format.md:747-751`, rejects newlines, quotes,
shell metacharacters) applies to `{{VAR}}` template variables only. `--with-data`
is JSON, and a submitted string round-tripped `"quotes"`, `;`, `\n`, `$(x)`, `&`
and backticks intact into the event log. Any PRD requirement that says koto
cannot carry prose is over-broad: `--var` cannot, evidence can.

The catch is on the read side. `derive_evidence`
(`koto:src/engine/persistence.rs:745-752`) filters to
`state == current_state`, and so does `derive_decisions` (`:759-788`). **There
is no CLI that returns evidence submitted at an earlier state.** `koto status`
gives position only; `koto decisions list` gives the current state's epoch only;
`koto session list` gives `created_at` and template hash and nothing else. Past
evidence exists only in the raw JSONL, which has no query surface.

**K-ctx — the context store.** `koto context add|get|exists|remove|list`, a
byte-content store under hierarchical keys (`koto:src/session/context.rs:19-41`).
Readable at any state. Round-tripped a multi-line YAML fragment with quotes,
`$(x)`, `&` and backticks byte-for-byte. This is koto's only cross-state
readable store.

**Its only writer is the agent, and that is a correction to the prior rounds.**
The findings file records `context_assignments` as "used by the shipped
`execute.md` template and validated by the engine
(`koto:src/template/types.rs:1219-1242`)". Those lines are a comment inside the
W5 warning explaining that `context_assignments` is *not* checked. The field
does not exist on `Transition` (`koto:src/template/types.rs:136-140`: `target`
and `when`, nothing else) and does not exist on `SourceTransition`
(`koto:src/template/compile.rs:105-115`), which is an `#[serde(untagged)]` enum
and therefore carries no `deny_unknown_fields`. Verified end to end: a template
with `context_assignments: {judgment_finding: "hop brief->prd: ${evidence.finding}"}`
on both transitions compiled, initialized, and ran to terminal, after which
`koto context list` returned `[]` and `koto context get` failed with "failed to
read context key 'judgment_finding'". `context_assignments` is silently ignored.
`grep -rn context_assignments src/` in koto returns five hits, all of them
comments.

Consequence for this lead: koto has no mechanism that writes agent-supplied
content into a cross-state readable store on koto's own authority. Anything in
K-ctx was put there by a shell command the agent chose to run, which makes it
exactly as forgeable as a line in `wip/`. It also means the eleven
`context_assignments:` blocks in `skills/execute/koto-templates/execute.md` are
dead config and `/execute`'s `failure_reason` context key is never written by
them — a live defect, not this effort's to fix, but it removes the only shipped
precedent a PRD might have cited for koto-writes-prose.

**K-gate — gate evaluation.** `context-exists`, `context-matches`, `command`,
`children-complete`. Produces a `GateEvaluated` event koto authors, not the
agent. This is the only koto record that is both machine-authored **and**
survives the terminal tick, because it is projected into the `/workflows` render
before cleanup runs.

**K-render — the `/workflows` projection.** Per-phase `{title, detail}` plus a
progress tree. `detail` comes from `outcome_line`
(`koto:src/workflows_surface/materialize.rs:148-161`): the gate result if a gate
was evaluated (`gate <name>: PASS` / `FAIL`), else `evidence_summary`. And
`evidence_summary` (`:165-180`) emits **field names only** — `evidence: verdict,
finding` — never values, with gate outcome taking precedence over evidence when
both exist.

That is the single most consequential mechanical fact in this lead. The one koto
surface that outlives the run can show *that* a state was entered and whether
its gate passed. It cannot show what the run decided there. `verdict: absorb`
and `verdict: keep` render identically. So `exit:`, `plan_execution_mode:`,
every consolidation verdict, and every discriminator are invisible in the
durable audit surface, and only a `command` gate testing the filesystem puts a
run's actual outcome into it.

## Field Inventory

Conditional column: **N** unconditional, **C** conditional per I-5.
Classification: **HOLD** koto can hold it, **NO** koto cannot hold it,
**COPY** koto holds it but shirabe still needs its own.

| Field | Writer | Readers | Cond | koto equivalent | Class |
|---|---|---|---|---|---|
| `topic` | Phase 0 | every path composition; slug re-validation on resume | N | session name at `koto init`; a `{{TOPIC}}` var | COPY |
| `last_updated` | every state-file write | ladder Entry 3/4, 7-day stale check | N | every event's `timestamp`; state-file mtime — no CLI returns it | COPY |
| `phase_pointer` | Phase 0, advanced at each boundary | ladder Entry 3/4 re-entry | N | **K-pos**, `koto status` → `current_state` | HOLD |
| `exit` | Phase 3 | R9 cond. 1; ladder Entry 2; gates every conditional field | C at finalization | **K-ev** enum on the finalize state + which terminal was reached | COPY |
| `exit_artifacts` | Phase 3 | R9 cond. 2; PR-body record | N | no list type in `accepts`; **K-gate** `command` gates per path verify instead | NO |
| `chain_started` | Phase 0 | abandonment marker field 4 | N | session header `created_at`; `workflow_initialized` seq 1 | COPY |
| `chain_completed` | Phase 3, all exits | DR filename date; abandonment marker | N | `_terminal_index.jsonl` `terminal_at` — written *after* Phase 3 needs it | COPY |
| `visibility` | Phase 0; **re-checked and removable at resume** | Phase 2 `--visibility=` interpolation | N | `{{VISIBILITY}}` var (allowlist accepts it) is immutable → wrong; **K-ctx** is mutable but agent-written | COPY |
| `consumed_upstream` | Phase 0 | Phase 2 `--upstream` arg; re-validated every re-entry; **droppable at resume** | C | **K-ctx** key (path with `/` and `:` also passes the `--var` allowlist, but `--var` is immutable) | COPY |
| `consumed_handoff` | resume Slot 7 | resume ladder on later re-entry | C | **K-ctx** key | COPY |
| `planned_chain` | Phase 1 | Phase 2 loop driver; R8 tie-break ordering | N | **the template's state graph** — compile-time constant, cannot drift | HOLD |
| `chain_ran` | Phase 2 step 6 (sole write site) | consolidation firing condition; R8 tie-break; PR-body record; `plan_execution_mode` presence | N | **K-gate** per-hop artifact gate (durable, machine-authored) + the `transitioned` sequence (not queryable) | COPY |
| `chain_skipped` | Phase 1 re-entry protection; Phase 2 boundary rejection | Phase 2 loop; PR-body record | N | skip-route **K-ev** enum whose `values` are the closed reason vocabulary — compiler enforces the closed set | COPY |
| `consolidation_judgments` | Phase 2 step 8 | PR-body record; `verdict:`/`stage:` read back to drive the absorb and gate a `git rm` | C | per-hop **K-ev** enums for `hop`/`stage`/`verdict` + a prose `finding`; **no object type for `carry_check`**, no list accumulation | NO |
| `boundary` | Phase 3 | R9 cond. 4; DR path; template selection | C on `re-evaluation` | **K-ev** `required: true` enum on the re-evaluation finalize state | HOLD |
| `decision_record_sub_shape` | Phase 3 | R9 cond. 4; DR path; template selection | C on `re-evaluation` | same state, second `required: true` enum | HOLD |
| `plan_execution_mode` | Phase 3 | R9 cond. 5; `exit_artifacts` status; commit body | C on `/plan` ∈ `chain_ran` | **K-ev** enum on the full-run finalize state; presence condition becomes reachability + a PLAN-file gate | HOLD |
| `referenced_artifact` | Phase 3 | DR body | C on `re-evaluation` | **K-ev** string / **K-ctx** key | HOLD |
| `discard_commit_sha` | Phase 2 | DR body substitution | C on rejection | **K-ev** string; no gate can verify it (gate `command` takes only init-time `{{VAR}}`) | HOLD |
| `rejection_rationale` | Phase 2 | DR body via template substitution; `git commit -F` | C on rejection | **K-ev** `type: string` — verified safe for quotes/newlines/`$()`/backticks | HOLD |
| `triggering_child` | Phase 3 via R8 tie-break | marker field 2; force-materialization path | C on `abandonment-forced` | **K-ev** enum closes the path-interpolation surface; but the *derivation* needs `chain_ran` timestamps koto cannot query | COPY |
| `partial_phase_reached` | Phase 3 | marker field 3 | C on `abandonment-forced` | **K-pos** — this field *is* the parent's own loop position, koto's core datum | HOLD |
| `child_snapshots` | Phase 1 initial, Phase 2 step 6 | drift detection on every ladder match | N | expressible as a `command` gate shelling `git hash-object` against a **K-ctx** key, but baroque; no map type in evidence | NO |
| `worktree_rebases` | after each rebase | worktree-discipline audit | C | per-event **K-ev** enum (`/execute`'s `worktree_discipline_check` is the shipped shape); no list append | NO |
| `worktree_divergences` | escalation "proceed against intent" | audit | C | per-event **K-ev** enum + prose string; no list append | NO |
| `drift_acknowledged` | Proceed-without at drift prompt | future-reviewer audit | C | 6-key entries, no map type, no list append | NO |
| `parent_orchestration` | Phase 2 step 2, cleared step 5 | **the child**, at its own Phase 0 | ephemeral | none — see below | NO |

Twenty-seven fields. Eight HOLD, eight NO, eleven COPY.

## Findings

### `parent_orchestration:` decides the question on its own

`skills/brief/SKILL.md:246` and `skills/prd/SKILL.md:117` both instruct the
child to read the `parent_orchestration` sentinel in a hardcoded literal path:
`wip/scope_<topic>_state.md or wip/charter_<topic>_state.md`. The pattern fixes
the block's three fields at Layer 1 and says explicitly that no parent extends
or omits any field, precisely so children read it identically regardless of
parent (`parent-skill-state-schema.md:248-265`).

So the state file is not `/scope`'s private bookkeeping. It is a
**parent→child interface at a literal path**, consumed by four children that
have no koto session name, no koto in their `requires.tsv`, and no reason to
acquire either — the adoption shape is settled as a phase substrate over
`/scope`'s own steps, with the children on unchanged inline Skill-tool dispatch.
Absorbing the state file into koto means editing all four children plus
`/charter`'s three, and changing a Layer-1 field of the shared contract, to
serve one parent's substrate. That is not a trade-off; it is a non-starter, and
it forecloses "one store, koto's" without any further argument.

### The state file must outlive the koto session, and by design does not

`fs::remove_dir_all` runs on the whole session directory at the terminal tick
unless `--no-cleanup` is passed. Verified: after a terminal tick, both
`~/.koto/sessions/ctxprobe/` and its `ctx/` subdirectory were gone, and the
surviving `~/.koto/_terminal_index.jsonl` line read
`{"session_id":"ctxprobe","terminal_at":"…","terminal_state":"completed","has_result":true}`
— `"completed"` for every non-failure terminal, never naming which one.

`/scope`'s Phase 3 record — `chain_ran`, `chain_skipped`,
`consolidation_judgments`, and `consumed_upstream` copied into the PR body
(`phase-3-exit-finalization.md:69-93`) — is written at Phase 3, which is
pre-terminal, so ordering saves it. But the round-2 gap about whether a
`single-pr` `/scope` run has a PR at all is still open, and if the answer is
"often not", then a design that put the record in koto's context store has
moved it from a scratch file that at least sits in the working tree onto a
machine-local directory that self-deletes. Strictly worse.

### koto position is genuinely better than `wip/` position

The one field where koto wins outright is `phase_pointer`. The pattern's own
`storage_substrate` entry concedes the weakness: "This substrate does NOT
satisfy invariant I-6; resume on a different branch starts fresh"
(`parent-skill-pattern.md:374-384`), and it requires an amplifier-layer
substrate to satisfy I-6. koto sessions are home-global and keyed by name only,
so `koto status <topic>` resolves from any branch and any directory — verified.
That is I-6 satisfied on one machine, which is more than `wip-yaml-md` offers
and is achieved without the `gh` round-trip `/execute` needs.

The contract move is available without a schema amendment. The state schema
already says field names are fixed, semantics are pattern-level, and
**serialization is substrate-bound** (`parent-skill-state-schema.md:9-14`), and
`phase_pointer`'s allowed values are "the parent's named phase identifiers"
(`:55-58`). A koto-substrate parent's phase identifiers can be its state names.
`phase_pointer` is satisfiable by K-pos with no Layer-1 change.

Two caveats. koto's states will be finer-grained than `/scope`'s five phases, so
either the state names become the enum or a documented map is needed. And K-pos
dies at the terminal tick — which is fine, because position is what a *resume*
needs and a terminated run has none.

### `planned_chain` should stop being data

`planned_chain` is `[brief, prd, design, plan]` on every run, fixed before the
first child and never amended (`phase-1-discovery.md:461-473`). Under a koto
template that is the declared edge set. Making it structural rather than a
recorded list is the cleanest single win in the inventory: a constant that lives
in a mutable file can drift from what the run does, and a compiled state graph
cannot. It also makes the `chain_skipped` reason vocabulary compiler-checked
rather than prose-asserted — the schema says the closed enum "is the only form
of that rule a grep can assert" (`parent-skill-state-schema.md:199-203`), and an
`accepts` enum with those four `values` upgrades the grep to a rejection at
submission.

### What koto genuinely cannot represent

Three shapes, and they account for every NO in the table.

**No object type.** `accepts` field types are `enum | string | number | boolean`
(`template-format.md:191-200`). `consolidation_judgments[].carry_check` is a map
of section→`{target, carried}`, `child_snapshots` is a map of child→three keys,
`drift_acknowledged[]` entries carry six. None is expressible as evidence.

**No list append.** Every `/scope` audit field that accumulates —
`consolidation_judgments`, `worktree_rebases`, `worktree_divergences`,
`drift_acknowledged`, `chain_ran`, `chain_skipped`, `exit_artifacts` — needs
"append one entry per occurrence." koto records each occurrence as a separate
`evidence_submitted` event, which is an append log, but with no read API for
prior states the accumulation is unrecoverable from within the run.

**No cross-state read.** The one that bites hardest. Everything `/scope` writes
early and reads late — `chain_started` at Phase 0 read by the Phase 3 marker,
`chain_ran` written per hop and read four ways at Phase 3, `child_snapshots`
written at Phase 1/2 and compared at every later resume — crosses states. Only
K-ctx crosses states, and K-ctx is agent-written and self-deleting.

## The /execute Precedent

`/execute` describes its state as "a **reconstructable per-session projection**,
not the source of truth", with the durable source being the home pull request
(`skills/execute/SKILL.md:387-396`, Decision 3 of `DESIGN-execute-skill.md`).
Read closely, three things about it do not transfer the way a PRD would want.

**The projection is not a projection of koto.** It is a projection of the home
PR. koto is not one of the two stores in `/execute`'s reconciliation at all —
the koto session is a third thing that holds the loop position and the
`materialize_children` batch, and the SKILL's State section never mentions it.
So `/execute` is not the shipped precedent for "koto plus wip/"; it is the
precedent for "GitHub plus wip/". A PRD that reaches for it as the dual-state
precedent is reaching for a different pair.

**There is no reconciliation procedure, because the projection has no
authority.** The rule is rebuild-or-fresh: the topic-keyed `gh pr list` lookup
runs at ladder Entries 8-9, "before either row declares 'no state → fresh
chain'" (`skills/execute/SKILL.md:479-488`). Entries 1-4 of the meta-ladder all
trigger on the state file existing
(`parent-skill-resume-ladder-template.md:68-110`), and Entry 3 resumes at the
recorded `phase_pointer` with no prompt. So when both stores exist and disagree,
**the projection wins and the durable source is never consulted** — the home-PR
lookup only fires when the projection is absent. What ships is a fallback, not a
reconciliation. Nothing in `/execute` answers "what happens when they disagree",
because nothing in `/execute` ever notices.

**One sentence of the precedent is factually wrong and would propagate.**
`skills/execute/SKILL.md:389` names "the committed koto context and in-flight
PLAN on the `impl/<slug>` branch" as part of the durable source of truth. koto's
context store is at `~/.koto/sessions/<id>/ctx/`, a home-global directory
(`koto:src/session/local.rs:34-45`), never committed to any branch and deleted
with the session at terminal. A PRD that transfers the precedent verbatim
inherits a durability claim the storage layer does not support.

What does transfer is the shape of the answer: **name one authoritative store,
make the other reconstructable from it, and never merge them.** That discipline
is right and `/scope` should keep it. The direction is what changes — see the
recommendation.

## R9 Viability

R9 fires at Phase 3 against a finalized run (`phase-3-exit-finalization.md:264-298`).
Its five conditions read seven fields: `exit`, `exit_artifacts`, every
`exit:`-gated conditional field, `boundary`, `decision_record_sub_shape`,
`plan_execution_mode`, and `chain_ran`.

**R9 is not merely still runnable under koto — three of its three spec Parts get
stronger, and the strengthening is mechanical rather than argued.** This is the
most useful result in the lead.

- **Part 1, `exit:` valid.** An `accepts` field with `type: enum`,
  `values: [full-run, re-evaluation, abandonment-forced]`, `required: true`.
  Verified: an out-of-enum value is refused with `invalid_submission` before any
  disk write, and a missing required field is refused the same way. Today Part 1
  is a check a prose-following agent performs on itself; under koto it is a
  precondition of the submission existing.

- **Part 2, multi-discriminator completeness.** `boundary:` and
  `decision_record_sub_shape:` both `required: true` on the *same* state means
  neither can be omitted while the other is present. The four-combination matrix
  becomes two required enums on one submission.

- **Part 3, conditional fields absent when ungated.** This is the one that looks
  impossible and is not. koto has no "field must be absent" constraint, but it
  rejects unknown fields per state — verified:
  `{"field":"bogus_field","reason":"unknown field \"bogus_field\""}`. **Split
  finalization into three states — `finalize_full_run`, `finalize_reevaluation`,
  `finalize_abandonment` — each declaring exactly its own path's fields, and I-5
  becomes an engine rejection.** Submitting `boundary:` on a full-run
  finalization is an unknown field at that state. The invariant the pattern
  today expresses as a rule an agent is trusted to follow becomes a schema the
  engine enforces at submission time.

Two conditions do not translate, and both have better replacements.

- **Condition 2, `exit_artifacts:` non-empty.** No list type, so no way to
  assert non-emptiness in `accepts`. But the substantive question is not whether
  the agent typed a path — it is whether the artifact is on disk. A
  `command` gate (`test -f docs/plans/PLAN-{{TOPIC}}.md`) answers the real
  question, emits a koto-authored `GateEvaluated`, and lands in the `/workflows`
  render as `gate plan_exists: PASS|FAIL`, durably. Prior research already
  verified the veto works: a `full-run` claim submitted with the plan gate
  failing returned `advanced: false`.

- **Condition 5, `plan_execution_mode:` present iff `/plan` ∈ `chain_ran`.**
  Cross-field, and `when` clauses are AND-over-values, not presence logic. The
  structural replacement: `plan_execution_mode` is declared only on
  `finalize_full_run`, and `finalize_full_run` is reachable only through the
  edge that ran `/plan`, gated on the PLAN existing. The biconditional becomes a
  reachability property of the graph.

**But all of that reads evidence at the state it is submitted at, which is the
only place koto lets you read it.** R9 as specified runs *over the state file*
at Phase 3, reading fields written across four phases. A koto binding does not
let R9 read what an earlier state accepted. So the honest statement for the PRD
is: koto can enforce R9's Parts 1-3 **at the moment of finalization**, over the
finalization submission, and cannot enforce anything about fields written
earlier. `chain_started`, `chain_ran`, `child_snapshots` and the audit lists all
have to be read from somewhere else, and the only somewhere-else that works is
the state file.

**A design that puts R9's inputs in koto does not make R9 unrunnable; it makes
R9 run over a smaller domain and forces the rest of the domain into a store
koto is not.** That is viable. Absorbing the state file into koto is not.

## `chain_ran: []` and What Moving It Would Change

**Verified, all four readers, against the current text.**

1. **Consolidation firing condition** — `phase-2-chain-orchestration.md:503-508`:
   "the judgment fires only if that artifact appears in `chain_ran:`". Empty
   list, no hop ever fires, no `consolidation_judgments:` entry is ever written.
2. **R8 tie-break** — `phase-3-exit-finalization.md:183-186`: "reads from the
   state file's per-child Phase 2 start timestamps (recorded as the child's
   entry in `chain_ran:`)". No entries, no candidates; the documented fallback
   (`planned_chain:` order) is a tie-*break*, not a source, so with zero
   candidates the rule is undefined rather than merely wrong.
3. **PR-body record** — `:73-77`: "every artifact in `chain_ran:`". Empty list,
   the record says nothing was produced, and the section's own stated purpose —
   letting a reviewer "tell an artifact that was absorbed from one that was
   never produced" — is defeated.
4. **`plan_execution_mode:` presence** — R9 condition 5, `:289-293`: present
   **iff** `/plan` ∈ `chain_ran`. Empty list, so the field must be **absent**,
   and omitting it *passes*.

And the composite: `exit: full-run` + `chain_ran: []` + `plan_execution_mode:`
omitted + `exit_artifacts:` naming the PLAN clears all five R9 conditions.
Condition 1 passes (valid enum), 2 passes (list non-empty), 3 passes (nothing
gated by `full-run` is present to be invalid), 4 is inapplicable, 5 passes by
absence. Confirmed: the audit surface disarms rather than trips. The failure is
**fail-open** and it is fail-open in all four readers at once, from one empty
list the agent writes itself.

**Does moving `chain_ran` into koto change that? Yes, and this is the strongest
mechanical argument in the whole adoption — stronger than the disclosure
argument, which is about what an agent is holding, where this is about what an
agent can assert.**

The reason is that emptiness stops being expressible. `chain_ran: []` is
available today because the field is a list the agent writes and can decline to
write. Under koto, "which hops this run took" is not a value at all: it is the
path the session walked to arrive at the finalize state, recorded as
`transitioned` events koto authors. A session sitting at `finalize_full_run`
walked edges to get there. There is no submission that produces an empty
history, because the history is the arrival.

Three qualifications, and they are load-bearing.

**Walking a hop is not running its child, given the ungated skip route.** The
settled constraint is that hop states carry an ungated skip route with the
binding on the exit state. So arrival at the finalize state proves the hop state
was *entered*, not that the child ran. The distinguishing datum is which exit
edge was taken — ran-edge or skip-edge — and that is in the `transitioned`
payload's `from`/`to`. koto records it faithfully; it just cannot be queried.

**Which means the durable record has to be a gate, not evidence.** From the
render's `outcome_line`, the only per-state fact that both survives cleanup and
is machine-authored is a `GateEvaluated` result. An evidence submission renders
as its field *names* only, so `verdict: absorb` and `verdict: keep` are
indistinguishable in the surviving surface. **A per-hop `command` gate testing
the child's durable artifact on disk is therefore the load-bearing mechanism,
and a per-hop evidence field is not.** `gate brief_exists: PASS` in the render
is a claim about the filesystem that koto made; `evidence: verdict, finding` is
a claim about nothing.

This is also what makes the round-2 `/workflows` finding work. The signature it
reported — `Brief: FAIL / Prd: FAIL / Plan: PASS / Finalize: PASS` — is four
gate outcomes, not four evidence summaries. A template that expresses hop
completion as evidence rather than as a gate produces a render that shows the
#331 run and a compliant run identically.

**Two bypasses stay open and both leave marks.** `koto next --to <state>` emits
`DirectedTransition` rather than `Transitioned`, and `koto overrides record`
emits `GateOverrideRecorded` — and the override case renders as `FAIL`, because
`advance.rs:363` emits no fresh `GateEvaluated` and the render keeps the stale
failing evaluation. So the override bypass is *more* legible than compliance,
not less. Neither bypass can produce an empty history.

**Net answer:** koto converts `chain_ran`'s fail-open into fail-closed, but only
if hop completion is expressed as a filesystem gate. It does not remove
shirabe's need for `chain_ran` in the state file: the PR-body record needs the
list in prose, and R8's tie-break needs the per-entry `started_at` timestamps,
which live in event timestamps koto will not return. What changes is that the
list acquires an independent machine-authored witness that a run cannot empty,
and a `chain_ran: []` next to `gate brief_exists: PASS` is now a visible
contradiction rather than a quiet vacuum.

## Recommendation

**Two stores, with disjoint content and one deliberate overlap. Not one store,
and not a projection.**

`wip/scope_<topic>_state.md` stays authoritative for all twenty-seven fields.
koto holds position and per-hop gate outcomes, and holds nothing that shirabe
also stores except `phase_pointer`.

What each option costs:

**One store, koto's** — foreclosed, not merely expensive. `parent_orchestration:`
is a parent→child interface at a literal path in four children's SKILL.md files
and a Layer-1 fixed block in the shared contract. The store self-deletes at the
terminal tick, before Phase 4 and before any PR-body record that a run without a
PR would need. Eight fields have no koto representation at all. Cost: rewriting
every child in both chains, amending the shared contract to serve one parent's
substrate, and losing the audit trail at exit.

**One store, shirabe's, with koto holding nothing** — this is today plus a
template. Cheap, and it forfeits the `chain_ran` fail-closed result, which is
the mechanically strongest thing the adoption buys.

**A projection, either direction** — costs a reconciliation procedure that
`/execute` demonstrates nobody writes. `/execute`'s ladder consults its durable
source only when the projection is missing, so in three shipped releases the
disagreement case has never been reached and no rule for it exists. Building one
for `/scope` means specifying what happens when koto says `state:
finalize_full_run` and the state file says `phase_pointer: phase-2`, on every
resume, forever. `/scope` also has no equivalent of the home PR: koto's session
is machine-local and self-deleting, so it cannot be the durable side, and the
state file is deleted by Phase 4, so it cannot be either. A projection needs a
durable anchor and `/scope` has none.

**Two stores** costs one thing and buys three.

The cost is the `phase_pointer` overlap, and it should be resolved by making
koto authoritative for it rather than by keeping two copies in agreement. The
state file continues to carry a `phase_pointer:` line because the 5-field
minimum requires the name, and its value is written from `koto status`'s
`current_state` at each state-file write rather than tracked independently. The
schema permits this without amendment: serialization is substrate-bound and the
allowed values are the parent's own phase identifiers. When they disagree, koto
wins, and the state file's copy is refreshed — which is a one-line rule, not a
reconciliation procedure, because the state file's copy is never the input to
anything.

What it buys: `chain_ran`'s fail-open closes; R9 Parts 1-3 become engine
rejections at the finalize submission instead of self-checks; and `planned_chain`
becomes the state graph, where it cannot drift.

**The fields that force this answer** are exactly two.
`parent_orchestration:` forecloses koto absorbing the state file, because it is
an interface rather than bookkeeping. And `chain_ran` forecloses koto holding
nothing, because its fail-open is the shipped defect and koto's transition
history is the only witness to it that the agent does not author.

Four requirements follow, stated so a PRD can lift them:

1. The state file remains authoritative and keeps every field it has today,
   including `chain_ran` with per-entry `started_at`. No field moves out.
2. `phase_pointer:` is derived from the koto session's current state at every
   write. On disagreement, koto is authoritative and the state file's line is
   refreshed.
3. Each hop's exit carries a `command` gate testing the child's canonical
   durable artifact on disk. Hop completion is expressed as a gate, never as an
   evidence field, because only a gate outcome reaches the surviving audit
   surface.
4. Finalization is three states, one per exit path, each declaring exactly its
   own path's fields as `required: true` typed evidence. R9 Parts 1-3 bind
   there.

## Open Risks

**The audit surface carries outcomes only where a gate produced them.**
`evidence_summary` emits field names, not values, and gate outcome takes
precedence over evidence. So `exit:`, `plan_execution_mode:`, and every
consolidation verdict are absent from the one surface that survives the run. Any
requirement written as "the trace shows what the run decided" is false unless
the decision is also a filesystem gate. This constrains template authoring more
than it constrains the state-ownership split, but it will be written wrong if
nobody says it.

**Two contradictory PRD-adjacent claims in the corpus should be corrected before
they propagate.** `context_assignments` does not work — it compiles, runs, and
writes nothing, verified — so `/execute`'s eleven blocks are dead and koto has
no koto-authored path into the context store. And `skills/execute/SKILL.md:389`'s
"committed koto context" is not committed anywhere. Both are pre-existing
defects; both would be inherited by a PRD that cites the precedent.

**`--no-cleanup` and the terminal index line are still mutually exclusive**, and
this recommendation leans on the `/workflows` render rather than the event log
precisely to avoid choosing. That is sound as long as gates carry the outcomes.
If a later requirement needs evidence *values* durably, the render cannot supply
them and the choice comes back.

**A topic slug starting with a digit is legal for shirabe and illegal for koto.**
`^[a-z0-9-]+$` admits `2fa-rollout`; `validate_session_id`
(`koto:src/session/validate.rs:14-35`) requires the first character to be
`is_ascii_alphabetic`. A `/scope` run on such a topic cannot open a koto session
under its own slug. Small, real, and cheaper to name in the PRD than to discover
in a template.

**`visibility:` and `consumed_upstream:` are mutable on resume** — the resume
ladder can drop either when a visibility check that passed at Phase 0 fails
later. `--var` is immutable for a session's lifetime, so neither can live as a
template variable, which is the shape a template author would reach for first.

**R8's tie-break has no koto input.** It resolves `triggering_child` from
per-entry `started_at` timestamps in `chain_ran`. koto stamps every event, but
returns no past-state timestamps, so the tie-break stays entirely on the state
file. Anyone who assumes koto's log can back it will find the log deleted and
unqueryable.

## Summary

`/scope` should keep its state file authoritative for all twenty-seven fields
and let koto hold only position and per-hop gate outcomes — two stores with
disjoint content, not one store and not a projection, because
`parent_orchestration:` is a parent→child interface at a literal path in four
children's SKILL.md files and cannot move, while `chain_ran`'s verified
four-way fail-open is exactly what koto's transition history closes. The
`/execute` precedent transfers only in shape: its projection is over the home
PR rather than over koto, its ladder consults the durable source only when the
projection is absent so no disagreement rule exists, and its "committed koto
context" is a home-global self-deleting directory. R9 survives and improves —
splitting finalization into one state per exit path makes Parts 1-3 engine
rejections at submission, since koto refuses unknown fields, out-of-enum values,
and missing required fields — but only over the finalization submission, because
koto has no cross-state read API for evidence. Two corrections the PRD needs:
evidence carries prose safely (the `--var` allowlist constraint does not reach
it), and `context_assignments` is silently ignored by the engine, so hop
completion must be expressed as a `command` gate rather than an evidence field
if it is to reach the surviving `/workflows` render at all.
