# Lead: Is "koto sequences a parent's own phases, with children still dispatched inline via the Skill tool" a legal and supported koto shape?

Yes. It is legal, it is supported, it is the shape koto's own reference
implementation teaches, and it is what `/work-on` already ships. The
interesting findings are not about legality — they are three authoring
traps that silently defeat the exact property `/scope` wants (progressive
disclosure), two of which are live in shipped templates right now,
including one in shirabe's own `work-on.md`.

All runtime evidence below was produced against **koto 0.11.6 (3d9ef1c
2026-08-17)**, the binary on PATH. Scratch templates used for the
experiments live under `$CLAUDE_JOB_DIR/tmp/kt/` and are not durable.

## Findings

### 1. The template model permits a workflow with no children

**Compile rules.** `CompiledTemplate::validate()` at
`public/koto/src/template/types.rs:482` is the whole schema gate. Its
required fields are `format_version`, `name`, `version`, `initial_state`,
and a non-empty `states` map whose keys include `initial_state`
(`types.rs:483-501`). Per state it requires a non-empty directive
(`types.rs:508-513`), that every transition target names a declared state
(`types.rs:514-522`), well-formed gates, well-formed `accepts` field
types, and that every `{{VAR}}` reference in a directive, gate command, or
action command is declared (`types.rs:780-803`). **Nothing in that list
mentions a child, a parent, a `default_template`, a `materialize_children`
hook, or a batch.**

The E-series rules bind only when the hook exists. The loop that runs them
opens with:

```rust
let hook = match &state.materialize_children {
    Some(h) => h,
    None => continue,
};
```

`types.rs:942-953`. Every one of E1-E10 lives inside that loop, so all ten
are unreachable for a template with no `materialize_children`. E9's
resolution half and F5 live in `compile.rs` because they need the source
path (`compile.rs:364-440`) and iterate the same hook-bearing states only.
W1-W5 come from `collect_materialize_children_warnings()`, same guard.

E10 is worth reading in the opposite direction from how it is usually
quoted: it says a state *with* `materialize_children` must *also* declare
a `children-complete` gate (`types.rs:1048-1060`). It is a rule about
hook-bearing states, not a rule that any template must have one.

**Minimum viable child-free template.** Frontmatter `name`, `version`,
`initial_state`, `states`; one `## <state_name>` body section per declared
state; each non-terminal state carries at least one transition; terminal
states carry `terminal: true` and no transitions. `description` and
`variables` are optional. Notably absent from the compiler: any check that
a terminal state exists or is reachable — a template with no terminal
state compiles, it just never yields `action: "done"`.

**Empirical confirmation.** A 5-state, zero-child template
(`frame → require → design → plan → done`, gates and evidence routing,
one evidence-driven self-loop) compiled clean on 0.11.6 and ran end to
end to `{"action":"done","advanced":true,"state":"done"}`. The only
compiler output was a benign D4 field warning
(`gate "brief_written" field "error" is never referenced`).

**Child-free templates that already ship.** `hello-koto` — koto's stated
reference implementation, 2 states, one `context-exists` gate, no children
(`public/koto/docs/guides/custom-skill-authoring.md:26-52`). koto-author's
own template — 9 states, no children
(`skills/koto-author/koto-templates/koto-author.md` in the 0.11.5-dev
plugin cache). Both non-batch canonical examples,
`complex-workflow.md` and `evidence-routing-workflow.md` — grep for
`materialize_children|children-complete` across all three returns nothing.

### 2. Runtime shape of a single-session workflow, per tick

The loop is four commands.

```
koto init <name> --template <path> [--var K=V ...]   -> {"name":..., "state": <initial>}
koto next <name>                                     -> JSON with an `action` field
koto context add <name> <key> --from-file <path>     -> register an artifact for a gate
koto next <name> --with-data '{"field":"value"}'     -> submit evidence, advance
... until {"action":"done"}
```

Per tick the driving agent must do exactly three things: read `directive`
(and `details` when present), do the work, then decide what to put in
`--with-data` by reading `expects.fields` and `expects.options`. Nothing
else is required of it. `koto-user/SKILL.md:11` states the contract
plainly: "You use koto by calling `koto next` in a loop. Each call returns
a JSON object that tells you what to do next."

Observed responses from the child-free run, abbreviated:

- Blocked phase — `action: "evidence_required"`, `blocking_conditions:
  [{"name":"brief_written","type":"context-exists","status":"failed",
  "output":{"exists":false},"category":"corrective","agent_actionable":true}]`,
  plus `directive`, `details`, `expects`. Submitting
  `{"status":"complete"}` while the gate was still failing returned the
  same response with `advanced: false` — the gate held.
- After `koto context add solo-t4 brief.md --from-file brief.md`, the same
  submission returned `advanced: true`, `state: "require"`,
  `blocking_conditions: []`, and *only the `require` phase's directive and
  details*. The other three phases' text never crossed the wire.
- `details` appeared on first arrival at a state and was absent on the
  second response from the same state, matching the `<!-- details -->`
  contract. `--full` forces it back.
- Terminal returned `{"action":"done","advanced":true,"state":"done",
  "expects":null}` with no directive.

Two extra affordances matter for a long conversational skill:

- **`koto status <name>`** returns `current_state`, `directive`,
  `details`, and `expects` without advancing — a re-hydration path after
  compaction. Verified against a live session.
- **The recovery pointer.** koto splices
  `"[koto] Lost context? \`koto status <name>\` returns this phase's
  directive/details/expects.\n\n"` onto the front of `directive`
  (`public/koto/src/cli/next_types.rs:166`). It is gated on whether the
  *phase declares* details, not on whether *this response carries* them,
  so a details-bearing phase advertises its own recovery on every visit.
  Confirmed: it appeared on `frame` and `require` (both declare details)
  and not on `design` or `plan` (neither does).

Resume across sessions is `koto workflows` to find the name, then
`koto next`. `koto rewind <name>` steps back one state.

### 3. Does koto's documentation name this pattern?

It does — and it names it as the *baseline*, not a variant. The exact
phrase "single-agent phase sequencing" does not appear, but the concept is
named repeatedly and endorsed:

- **Progressive disclosure is a named decision driver of the engine
  itself.** `public/koto/docs/designs/archive/DESIGN-koto-engine.md:141`:
  "**Progressive disclosure**: The agent should receive only the current
  state's directive, not the full template. The engine/controller boundary
  enforces this." This is the author's framing, stated by koto, as a
  reason the engine exists.
- **Single-agent is the assumed model.**
  `DESIGN-koto-engine.md:197`: "koto's primary use case is single-agent
  workflows." Same file, line 289: "the primary use case is single-agent
  workflows." And in a *current* design,
  `docs/designs/current/DESIGN-koto-cli-output-contract.md:664`: "This is
  acceptable for the current single-agent model where one agent drives one
  workflow."
- **koto-author's fit list puts children last and optional.**
  `koto-author/SKILL.md:15-23` — koto is a good fit when "Your skill has
  multiple phases that must run in order", "Phases have conditional
  branching", "You want resumability if a session is interrupted", "You
  want to separate workflow mechanics (ordering, branching, gating) from
  domain logic", and — fifth, and the only one that mentions children —
  "Your skill fans out a dynamic list of subtasks to child workers". The
  first four describe the phase-substrate shape with no children in sight.
- **The authoring guide's entire worked example is child-free.**
  `docs/guides/custom-skill-authoring.md` builds `hello-koto` end to end;
  hierarchy is not mentioned in it at all.
- **No warning against the shape exists anywhere.** Searching koto's
  `docs/` and both plugin skills for any caution about child-free
  workflows returns nothing. The only "when not to use koto" line is
  `koto-author/SKILL.md:23`: "If your skill is a single linear task with
  no decision points, koto adds unnecessary overhead." `/scope` has
  decision points at every hop, so it is on the endorsed side of that line.

**The absence worth naming:** koto never gives this shape a *name*. There
is no "phase substrate" or "single-agent sequencer" section to point an
author at, which is presumably why it reads as unexplored territory. It
is the unnamed default.

### 4. `/work-on` is already exactly this shape

`skills/work-on/koto-templates/work-on.md` is 1156 lines, 25 states, 5
terminal states, and contains **zero** `materialize_children` hooks and
**zero** `children-complete` gates. One koto session, one agent, states
advancing. It is the in-repo precedent and it answers the question.

Two details sharpen it:

- **It dispatches children inline anyway.** The `scrutiny`, `review`, and
  `qa_validation` states each spawn three parallel reviewers via the Agent
  tool — `skills/work-on/references/review-panel-orchestration.md:6-8`
  ("three parallel reviewers"), flagged in `SKILL.md:233-235` as
  "require parallel spawns, not standard directive execution". Those
  spawns are invisible to koto. This is precisely the shape in the lead
  question: koto sequences the parent's own phases; children are dispatched
  by the agent, outside koto's model.
- **The SKILL/template split inverts.** `skills/work-on/SKILL.md` is 287
  lines against a 1156-line template. `skills/scope/SKILL.md` is 968 lines
  against no template. The phase text moved into the state bodies, where
  it is delivered one phase at a time.

For contrast, `skills/execute/koto-templates/execute.md` has 13 states, of
which exactly **one** (`spawn_and_await`, line 147) declares
`materialize_children` pointing at `../../work-on/koto-templates/work-on.md`.
That is the structural point: materialization is a single state inside a
phase substrate, not an alternative to one. The two shapes are not rivals
— full materialization is the phase substrate plus one extra state.

### 5. What `/scope` looks like under this shape

`/scope`'s phase text is *already* extracted into
`skills/scope/references/phases/` — 6 files, 2708 lines
(phase-0-setup 333, phase-1-discovery 563, phase-2-chain-orchestration 872,
phase-3-exit-finalization 430, phase-4-cleanup 150, phase-resume 360).
The 968-line SKILL.md is the resident router plus the pattern contract,
resume ladder, exits, security surfaces, and the "Why the Artifact Set
Shrinks" argument (SKILL.md:472-531). So the template's directives point
at phase files exactly as `/work-on`'s do ("do the work described in
`directive`, read any phase file it references", `work-on/SKILL.md:225`);
it does not have to inline 2708 lines.

**Sketch — roughly 15 states:**

| State | Gate | Evidence | Routes to |
|---|---|---|---|
| `setup` | `context-exists` on the state file | `slug_valid`, `visibility` enum | `discover`, `done_blocked` |
| `discover` | — | `proposal: [proceed, adjust, bail]` | `brief`, `discover` (evidence self-loop), `done_bailed` |
| `brief` | artifact exists (`context-exists` or `command`) | `outcome: [written, skipped_reentry, rejected, abandoned]` | `consolidate_brief`, `decision_record`, `finalize` |
| `consolidate_brief` | — | `verdict: [keep, fold]` | `prd` |
| `prd` / `consolidate_prd` | same shape | same | `design` |
| `design` / `consolidate_design` | same shape | same | `plan` |
| `plan` / `consolidate_plan` | same shape | same | `finalize` |
| `finalize` | `context-exists` on `exit_artifacts` | `exit: [full-run, re-evaluation, abandonment-forced]` | `cleanup` |
| `cleanup` | wip absence check | `cleanup: complete` | `done` |
| `done` / `done_bailed` / `done_blocked` | terminal | | |

Fifteen states sits between `/execute`'s 13 and `/work-on`'s 25, so the
size is unremarkable for this repo. The payoff lands in the
`consolidate_*` states: "Why the Artifact Set Shrinks" becomes their
`<!-- details -->` body, so the argument that a smaller artifact set is
worth wanting reaches the agent **only when an artifact exists to judge**
— which is what the passage itself insists on (SKILL.md:481-488: "a
judgment about whether a document would have carried anything a later one
does not is only answerable against a document that exists"). Today that
passage is resident from line 1 of a 968-line load. That is the defect,
and this shape is a direct fix for it.

Note the Phase-2 loop has to be **unrolled**. koto has no loop counter and
no iteration primitive outside `materialize_children`. `/scope`'s chain is
fixed at four children, so four explicit state pairs is legitimate — and
arguably clearer than a loop, since each hop's directive can differ. This
is the one place where the fixed-arity chain makes the child-free shape
easier than it would be for a dynamic list.

**What it does NOT get, concretely:**

- **No koto-side per-child accounting.** No `children[]` array with
  `outcome` / `failure_mode` / `failure_reason` / `skipped_because` /
  `skipped_because_chain`, no `batch_final_view`, no aggregate booleans.
  `/scope` keeps its own `chain_skipped:`, per-child snapshots,
  `consolidation_judgments:`, and `worktree_rebases:` in
  `wip/scope_<topic>_state.md`. It already does — nothing is lost relative
  to today, but nothing is gained either.
- **No `failure_policy: skip_dependents`.** `/scope`'s re-entry protection
  and hold-back logic stay hand-rolled prose rather than becoming
  scheduler behavior.
- **No per-child rewind.** `koto rewind` moves the single session back one
  state; you cannot rewind just the PRD hop.
- **No hierarchy in `koto workflows` or the dashboard.** A `/scope` run is
  one row, not five. Whoever is watching Agent View sees "scope-foo,
  state: design" rather than a parent with four children. This is the
  single most tangible loss.
- **No `--needs-agent` / `unassigned_children` dispatch handshake** and no
  per-child epoch fencing (moot with no child sessions).

**What it gains over today's `/scope`:** progressive disclosure (proven —
only the current state's text crosses the wire); gates the agent cannot
argue past, because `context-exists` / `command` gates are evaluated by
koto and reported in `blocking_conditions` with `agent_actionable` and
`category`; resumability that does not depend on the agent correctly
reading its own state file; and the recovery pointer on every
details-bearing phase.

### 6. Cost, honestly

**Full materialization:** 1 coordinator template + 4 child templates
(`/brief`, `/prd`, `/design`, `/plan`), each required by E9 to be a
separately compilable template, each required by F5 to declare a reachable
`skipped_marker: true` terminal, each wanting a `failure: true` terminal
with a `failure_reason` path to avoid W5 — plus 5 `.mermaid.md` previews
kept fresh. Each child template has to encode, in state form, the whole of
a 900-2700-line conversational skill.

**Phase substrate:** **one** template plus **one** mermaid. That is the
honest number.

What replaces the cost is smaller but real, and it is not zero:

1. **Evidence-enum design.** Every routing decision `/scope` currently
   makes in prose has to become a named enum field with mutually
   exclusive `when` clauses. This is the genuine intellectual work, and
   it is roughly the same work that would have gone into a coordinator
   template under full materialization.
2. **Unrolling Phase 2** into four state pairs (above).
3. **The three authoring traps in "Surprises" below.** They are cheap once
   known and expensive once shipped — `/work-on` shipped one.
4. **CI.** Already wired: `.github/workflows/validate-templates.yml`
   compiles every `*/koto-templates/*.md`,
   `check-template-consistency.yml` enforces mermaid freshness,
   `check-templates.yml` rejects shell-style interpolation. One more
   template costs one more mermaid to keep fresh; no new infrastructure.
5. **SKILL.md rewrite.** Not additive — the 968 lines shrink toward a
   router. `/work-on`'s ratio (287 SKILL / 1156 template) is the shape to
   expect.

So the prior research's "four new koto templates over 900-2700-line
conversational skills" — the dominant structural cost — is not reduced
under this shape. It is **removed**.

## Implications

The central question resolves cleanly in favor of the shape, and it
resolves *more* cleanly than the framing anticipated: this is not an
unexplored alternative to full materialization, it is the base case that
full materialization extends by one state. `/execute` demonstrates the
composition (12 phase states + 1 materialization state), so adopting the
phase substrate for `/scope` does not foreclose materializing children
later — it is the prerequisite for it.

It also means the decision in front of the exploration is narrower than
"should `/scope` adopt koto". The phase-substrate shape costs one
template, targets the one defect prose cannot repair, and gives up only
child-level legibility in `koto workflows` / the dashboard. If the author
values that legibility (five rows instead of one during a `/scope` run),
that is the argument for materialization — and it is an argument about
observability, not about instruction sequencing.

The author's framing quoted in the exploration context — "koto allows for
progressive disclosure, since instructions can be given as the agent
progresses through the workflow. That is how the agent is kept going
through the workflow, rather than being given all the tools to rationalize
away from it at the very beginning" — is almost a paraphrase of
`DESIGN-koto-engine.md:141`. The author and koto's engine design agree
about what koto is for, and neither of them is describing child
materialization.

## Surprises

**Three traps, all verified by running them. Two are live in shipped
templates.**

### Surprise 1: `accepts` + a single unconditional transition is a pass-through state

This is the important one, because it defeats progressive disclosure
specifically.

`resolve_transition` (`public/koto/src/engine/advance.rs:693-771`) fires
an unconditional fallback unless `gate_failed || (!fresh_evidence &&
has_conditional)` (`advance.rs:758`). A state with an `accepts` block but
**only** unconditional transitions has `has_conditional == false`, so the
guard is false and the engine advances straight through it. The doc
comment says so outright (`advance.rs:691-692`): "Pure-routing states
(only unconditional transitions, no conditional) are not affected because
`has_conditional` will be false." The presence of an `accepts` block does
not enter the decision.

Consequence: **the agent never sees that phase's directive.**

Verified twice against shipped templates:

- **koto's own `koto-author` template.** `koto init ka-test --template
  koto-author.md --var MODE=new` then a single `koto next` returns
  `advanced: true` at state `compile_validation` — the agent is told to
  "Run `koto template compile <path-to-drafted-template>`" having never
  received `entry`, `context_gathering`, `phase_identification`,
  `state_design`, or `template_drafting`. Five of nine states collapse in
  one tick.
- **shirabe's own `work-on` template.** The `research` state
  (`work-on.md:125-135`) has an `accepts` block and one unconditional
  transition. Submitting `{"verdict":"proceed"}` at `task_validation`
  lands the agent directly at `post_research_validation`, whose directive
  opens "Reassess the task against what research revealed about the
  current codebase" — after koto silently skipped the state that would
  have told it to research. This is live in `/work-on` free-form mode
  today.

**Rule for the `/scope` template:** every phase state needs at least one
*conditional* transition (routing on an evidence enum, a `gates.*` field,
or both). The sketch in section 5 satisfies this everywhere. This is worth
filing upstream against koto for the `koto-author` template, and worth
filing against shirabe for `work-on.md:125`.

### Surprise 2: the documented self-loop polling idiom errors at runtime

`template-format.md:548-570` presents an `await_file` state — gate,
`skip_if`, pass transition, self-loop on `exists: false` — and calls it
"the idiomatic workaround when a `context-exists` gate would otherwise
block indefinitely: the self-loop keeps the agent polling."

Copied verbatim into a template, compiled clean, and run with the key
absent, it returns:

```
{"error":{"code":"template_error","message":"cycle detected: advancement loop would revisit state 'await_file'"}}
```

exit code 3. The advance loop fires the self-loop once (inserting the
target into `visited`, `advance.rs:552-558`), re-evaluates, resolves to
the same target, and hits the cycle check at `advance.rs:537-542`, which
`cli/mod.rs:4224-4232` reports as a template error. A gate-driven self-loop
that stays blocked always errors after one lap.

`/work-on`'s template description already knows this — line 11: "Self-loops
use conditional when blocks (`scope_changed_retry`,
`partial_tests_failing_retry`, `creation_failed_retry`) to avoid triggering
cycle detection."

**Evidence-driven self-loops are fine.** Verified: `design → design` on
`{"verdict":"revise"}` returned normally with `advanced: true` and
redelivered the directive. The distinction is that the agent's submission
starts a fresh tick, so `visited` is empty when the loop fires.

**Rule:** to hold a phase on a failing gate, give the state an `accepts`
block and route the *pass* branch on a mixed `gates.*` + evidence `when`
clause, with **no** self-loop. The engine then returns
`evidence_required` with populated `blocking_conditions` and simply cannot
advance until the gate passes. Verified end to end — this is the shape in
section 5's sketch.

### Surprise 3: D4 rejects a gate whose only pure-gate route is the failure branch

Adding the "obvious" self-loop `when: {gates.brief_written.exists: false}`
to the shape above turned a compiling template into:

```
validation error: state "frame": no transition fires when all gates use override defaults
  gate "brief_written" override: {"error":"","exists":true}
  pure-gate transitions checked: 1
```

`validate_gate_reachability` (`types.rs:1304-1400`) collects transitions
whose `when` keys are *all* `gates.*` prefixed, then checks that at least
one fires under the gate's override default. A state with zero pure-gate
transitions is exempt (`types.rs:1334-1337`) — which is why the
mixed-clause shape compiles. A state whose only pure-gate transition is
the failure branch is rejected, because a recorded
`koto overrides record` could never unblock it. The rule is correct; it is
just non-obvious, and it fires exactly when an author reaches for the
idiom in Surprise 2.

### Minor

`work-on/SKILL.md:216-224` documents the execution loop in terms of
`action: "execute"`, which is not in koto 0.11.6's action vocabulary
(`evidence_required`, `gate_blocked`, `integration`,
`integration_unavailable`, `done`, `confirm` —
`koto-user/SKILL.md:65-72`). Stale, and worth fixing whenever `/work-on`'s
skill is next touched.

## Open Questions

1. **Two state stores or one?** `/scope` keeps
   `wip/scope_<topic>_state.md` with a rich schema (255 lines of field
   enumeration in `skills/scope/references/state-schema.md`). Under koto,
   the session carries current state, evidence, and the context store.
   Keeping both risks divergence; folding the state file into koto context
   is a larger change than the template itself. Needs a human call on
   which fields migrate.
2. **Does the author want child-level dashboard legibility?** That is the
   only material thing full materialization buys that this shape does not.
   It is an observability preference, not a mechanism question.
3. **The children stay in the parent's context.** Progressive disclosure
   fixes `/scope`'s own 968-line footprint. It does nothing about `/brief`,
   `/prd`, `/design`, and `/plan` loading whole when invoked inline via the
   Skill tool. If the real complaint is total resident context across the
   run, this shape addresses roughly a fifth of it. Worth confirming which
   problem is being solved.
4. **Abandonment-forced exit and the R20 marker** (`SKILL.md:758-820`)
   need a mapping onto terminal states — probably `done_bailed` with a
   `failure: true` marker, but `failure:`/`skipped_marker:` semantics only
   matter to a parent's `children-complete` gate, and this template has no
   parent. Are they worth setting at all? Note `/execute` would become that
   parent if `/scope` ever runs under it.
5. **Should the `koto-author` and `work-on` pass-through defects be filed
   now?** They are independent of this decision and both are cheap fixes
   (add a conditional transition), but `work-on.md:125` is a live
   correctness bug in shirabe.

## Summary

The shape is legal, supported, and already shipped: every E-series and F5
rule is guarded on `materialize_children` being present
(`types.rs:942-953`), a 5-state child-free template compiled and ran to
terminal on koto 0.11.6, and `/work-on` is 25 states with zero children
that dispatches its review panels inline — while `/execute` shows
materialization is one extra state inside a phase substrate, not a rival
to it. The cost collapses from four child templates to one template plus
one mermaid, koto's own engine design names progressive disclosure as a
decision driver (`DESIGN-koto-engine.md:141`), and the payoff is that
"Why the Artifact Set Shrinks" can live in a consolidation state's details
instead of resident context. The biggest open question is whether the
author wants child-level legibility in `koto workflows` and the dashboard,
since that is the only material thing this shape gives up — but the
sharpest finding is a trap: a state with an `accepts` block and a single
unconditional transition is silently skipped (`advance.rs:758`), which
already skips five of nine states in koto's own `koto-author` template and
the entire `research` state in shirabe's shipped `work-on.md`.
