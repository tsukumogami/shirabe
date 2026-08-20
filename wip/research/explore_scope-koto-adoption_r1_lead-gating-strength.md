# Lead: What gates does koto actually offer, what would `/scope` gate on at each hop, and how cheaply can an agent satisfy a gate without doing the work?

Paths below are relative to the repo they name. koto source is at
`public/koto/`; shirabe source is this worktree. koto plugin skills are
the `0.11.5-dev` version dir.

## Findings

### 1. The gate inventory is four types, not two

`src/gate.rs:71-99` dispatches on exactly four gate-type constants, and
the fallthrough arm (`:99-111`) hardcodes the error string "only
command, context-exists, context-matches, and children-complete gates
are evaluated." The author-facing table at
`koto-author/references/template-format.md:274-280` matches the source
exactly. There is no fifth type and no extension point.

| Type | Checks | Evaluator | Runtime cost |
|---|---|---|---|
| `context-exists` | `store.ctx_exists(session, key)` — key present, content unread (`gate.rs:116-141`) | koto | one store stat |
| `context-matches` | key's bytes are valid UTF-8 **and** match `gate.pattern` as a regex (`gate.rs:143-196`) | koto | one store read + regex |
| `command` | shell command exits 0 (`gate.rs:198-224`) | koto spawns, shell decides | process spawn, default 30s timeout |
| `children-complete` | delegated to a caller-supplied closure; `None` yields an Error result with a 15-field zeroed payload (`gate.rs:77-98`) | koto, over child session headers | scans child state files |

Two properties of the evaluator matter downstream. First, it does not
short-circuit — `evaluate_gates` iterates every gate and collects all
results (`gate.rs:68-114`), so a caller sees every blocking condition at
once. Second, failure modes collapse toward `Failed`, not `Error`:
`context-matches` returns `Failed` when the key is missing entirely,
when the bytes are not UTF-8, and when the regex does not match
(`gate.rs:159-176`) — only an uncompilable pattern is an `Error`. A
missing key and a non-matching key are indistinguishable in the output.

`children-complete` has a `completion:` field, and this is the important
limitation. `src/template/types.rs:561-584` validates it and then
**rejects both non-trivial modes at compile time**: `completion:
state:...` and `completion: context:...` each produce "reserved but not
yet implemented." Only `terminal` works. A `children-complete` gate can
therefore assert that children *stopped*, never that a child reached a
*particular* state.

### 2. Both bypasses are documented, first-class, and unconfigurable

This is the section that changes the answer to the lead question.

**Bypass A — `koto next --to <state>` ignores gates and `when` clauses.**
`src/cli/mod.rs:3286` opens the branch with the comment "Handle --to
(directed transition) -- single-shot, no advancement loop." Gate
evaluation lives in the advance loop, at `src/engine/advance.rs:316-420`
("6. Evaluate gates"). The `--to` branch never enters that loop. Its
entire validation is at `src/cli/mod.rs:3305-3322`:

```rust
let valid_targets: Vec<&str> = current_template_state
    .transitions
    .iter()
    .map(|t| t.target.as_str())
    .collect();
if !valid_targets.contains(&target.as_str()) { /* PreconditionFailed */ }
```

It maps transitions to `t.target` and discards everything else. The
`when` clause is never read. So `--to` bypasses not only gates but
evidence-based routing: a transition guarded by `when: {gates.x: true}`
is as reachable as an unguarded one. `--rationale` is `Option<String>`
(`src/cli/mod.rs:151-153`) — optional, free text, never parsed.

koto's own user docs describe this plainly:
`koto-user/references/command-reference.md:88` says `--to` "**Forces** a
directed transition," and `:93` documents it as "Force a directed
transition to a named state. Must be a valid transition target from the
current state."

Declaring no long-jump edge does not save you. It only forces the agent
to spend one command per hop along the template's own declared chain.

**Bypass B — `koto overrides record` needs no evidence at all.**
`src/cli/overrides.rs:54-72` resolves the override value through a
three-level fallback: `--with-data` → the gate's `override_default` →
`built_in_default(gate_type)`. And `src/gate.rs:239-243` supplies
built-in defaults for every gate type, including:

```rust
GATE_TYPE_CONTEXT_EXISTS => Some(serde_json::json!({"exists": true, "error": ""})),
```

So `koto overrides record <wf> --gate <g> --rationale "<anything>"`
succeeds with no payload. On the next tick, `advance.rs:330-366` builds
the epoch override map and, for any overridden gate, injects a synthetic
`Passed` result **without calling `evaluate_gates` at all**. The source
comment at `:355-364` is explicit, and the unit test is named
`override_injects_passed_result_and_no_gate_evaluated_event`
(`advance.rs:3216`). The rationale is size-checked (`overrides.rs:122-135`)
and never content-checked.

**Neither bypass can be turned off.** `src/config/mod.rs:181-262`
enumerates the full settable config surface; every key is under
`request_store.` and concerns timeouts, caps, and batch sizes. There is
no `allow_directed_transition` or `allow_overrides` knob, and no
capability gate on either command.

### 3. Even unbypassed, the gates are content-blind and cheap

`koto context add` reads from stdin or `--from-file` and writes
whatever it gets: `src/cli/context.rs:16-38` performs no validation
between read and `store.add(session, key, &content)`. So
`echo x | koto context add <session> prd.md` satisfies any
`context-exists: prd.md` gate. `context-matches` raises the bar to
"produce bytes matching a regex," which a heading like `## Requirements`
satisfies in one more echo.

There is no ordering constraint either — the key can be written at any
time, including before the state that gates on it is ever reached.

### 4. The honest R20 baseline

`skills/scope/references/phases/phase-2-chain-orchestration.md:38-77`
defines the eight-step per-child loop. R20 is step 4, "Confirm the
child's canonical durable artifact exists after the child returns."

The detail at `:760-790` (the section runs from the "R20 Structural
File-Existence Check" heading) gives four canonical paths —
`docs/briefs/BRIEF-<topic>.md`, `docs/prds/PRD-<topic>.md`,
`docs/designs/DESIGN-<topic>.md` with a `docs/designs/current/` fallback,
`docs/plans/PLAN-<topic>.md`. On absence, the outcome
("PASS-with-no-artifact — the child reported success but the canonical
durable file does not exist on disk") is mapped to STALE and routed via
R8's bail-handling.

Three things about this baseline are worth stating precisely, because
the upgrade claim depends on them:

- **It is an existence check, not a content check.** `touch
  docs/prds/PRD-x.md` satisfies it. It is the same class of check as
  `context-exists`, not a weaker one.
- **The evaluator is the parent agent itself.** R20 is prose in a
  markdown reference that the parent reads and is trusted to execute.
  Nothing outside the agent observes whether step 4 ran.
- **The per-child gates are cached, not re-derived.** `:760` onward
  ("Per-Child Gates from `planned_chain:`, Not Re-Walked") says Phase 2
  reads `planned_chain:` and `chain_skipped:` from the state file and
  does not re-walk re-entry protection: "Phase 2's job is iterative
  invocation against the cached chain shape, not re-evaluation of Phase
  1's decisions." So the set of children that must run is itself read
  from the agent-authored state file.

### 5. Drafted per-hop gates, and what defeats each

A `/scope` koto template with one state per hop. Concrete enough to
argue with; each row's last column is the adversarial answer.

| Hop | State | Gate | Cheapest defeat |
|---|---|---|---|
| brief | `brief` | `context-matches`, key `brief.md`, pattern `^## Scope Boundary` | `printf '## Scope Boundary\n' \| koto context add <s> brief.md` |
| prd | `prd` | `context-exists`, key `prd.md` | `echo x \| koto context add <s> prd.md` |
| design | `design` | `context-matches`, key `design.md`, pattern `^## Decision \d+` | one echo with a matching heading |
| plan | `plan` | `context-exists`, key `plan.md` | one echo |
| any | any | any of the above | `koto next <wf> --to <next>` — zero setup |
| any | any | any of the above | `koto overrides record <wf> --gate <g> --rationale x` |

A `command`-gate variant (`test -f docs/prds/PRD-<topic>.md`) is
reachable but is what `template-format.md:758` explicitly advises
against: "Prefer `context-exists` gates over `command` gates when
checking paths or files that come from variable interpolation. The
`context-exists` and `context-matches` gate types don't invoke a shell
and aren't vulnerable to injection." It also merely relocates R20's
`touch` defeat into koto without strengthening it.

The precedent in-repo is real but small:
`skills/work-on/koto-templates/work-on.md:77-81` gates
`context_injection` on `context-exists: context.md`. Note that the same
state's `accepts` block (`:82-89`) declares `status:` with values
`[completed, override, blocked]` — a template-level `override` value
alongside the gate.

**On `skipped_marker` and F5.** The lead asks whether F5's required
skip terminal is also an escape hatch. It is, with two qualifications.
F5 is a **warning printed to stderr, not an error**
(`src/template/compile.rs:428-438`), and the doc comment at `:352-360`
says so explicitly: "F5 is a warning, not an error, because
batch-eligibility is not knowable when a child template is compiled in
isolation." So the skip terminal is strongly encouraged, not mandatory.
Where it exists, `TerminalOutcome::Skipped` (`src/engine/types.rs:843-848`)
counts toward `all_complete` and is excluded only from `all_success`
(the W4 validator at `src/template/types.rs:1196` treats
`"all_complete" | "all_success"` as the routing pair). A parent gating
on `children-complete` must therefore route on `all_success`, not
`all_complete`, or every child has a sanctioned way to finish having
done nothing. And because `completion: state:` is unimplemented
(finding 1), even `all_success` cannot assert *which* terminal a child
reached beyond the failure/skip flags.

### 6. The audit trail is real, koto-authored, and records the bypasses

This is where koto genuinely differs from the `wip/` state file, and
it is a stronger result than I expected going in.

**Gate evaluations are durable and koto-authored.**
`src/engine/advance.rs:370-390` appends an `EventPayload::GateEvaluated`
per evaluated gate, carrying `state`, `gate`, `output`, `outcome`
(one of `passed` / `failed` / `timed_out` / `error`), and
`now_iso8601()`. The agent supplies none of these fields. It is written
to the session's append-only JSONL log.

**Both bypasses leave typed, distinguishable events.** An override
writes `EventPayload::GateOverrideRecorded` with the gate name, the
mandatory rationale, and `override_applied`
(`src/cli/overrides.rs:78-84`, consumed at `advance.rs:330-343`).
A directed transition writes `EventPayload::DirectedTransition { from,
to, rationale }` (`src/cli/mod.rs:3334-3339`). Critically,
`advance.rs:363` notes "No GateEvaluated event is emitted for overridden
gates" — so the log distinguishes *koto observed this gate pass* from
*the agent asserted it should pass* by the presence or absence of a
different event type, not by a field an agent could set.

koto also reserves an audit-kind namespace against agent forgery:
`src/engine/audit.rs:103-110` (`is_reserved_kind`) rejects any
`koto next --with-data` payload whose `fields.kind` starts with
`request_store.` or matches the four reserved literals, and the
CLI parser consumes that predicate before any disk write
(`audit.rs:99-102`). The comment at `audit.rs:64-76` explains why
reserved records use synthetic state names: without that, an
agent-visible audit record would be promoted as a child's result.

Contrast with `/scope` today. `chain_ran:`, `chain_skipped:`, and
`consolidation_judgments:` are fields the parent agent writes into its
own `wip/` state file. Issue #331's phrase — "authored by the party
being audited" — is exactly right, and koto changes the author for the
gate-evaluation subset specifically.

### 7. FC18 composition

`crates/shirabe-validate/src/checks.rs:421-424`:

```rust
pub fn check_fc18(doc: &Doc) -> Vec<ValidationError> {
    let line = doc.fields.get("absorbed").map(|f| f.line).unwrap_or(1);
    let entries = match parse_absorbed(doc) {
        AbsorbedDecl::Absent => return Vec::new(),
```

The doc comment at `:400-402` states the design intent: "Gated entirely
on `absorbed:` being present, so it is silent on every document that
declares no absorption." The incident defeat is not a bug in the six
clauses — it is the guard condition working as documented. Deleting
`absorbed:` returns `AbsorbedDecl::Absent` on line 424 before any clause
runs.

**A koto gate would compose, not conflict, but it would not close this
hole.** The two operate on disjoint inputs: FC18 reads a finished
markdown document's frontmatter and section structure; a koto gate reads
the session context store. Nothing in FC18 inspects koto state and
nothing in koto inspects `absorbed:`. There is no duplicated check and
no contradictory verdict.

But the composition is weaker than it looks. FC18's hole is a *document
that declares nothing*; a koto gate's hole is a *state advanced by a
declared bypass*. Adding the gate does not make the empty-`absorbed:`
document detectable, and adding FC18 does not make `--to` detectable.
Each covers what the other misses only in the sense that neither covers
the other's gap — they are two separate uncovered gaps, not a covering
pair. An agent that deleted `absorbed:` and ran `koto next --to plan`
passes both.

## Implications

**The prior research's strength claim is too generous and needs
restating.** The wording under test was: a `context-exists` gate would
make the *parent* unable to skip a hop and still finish. As stated,
that is falsified by `src/cli/mod.rs:3286-3322`. The parent can skip
every hop and still finish, using one documented command per hop, along
the template's own declared edges, with no context keys written and no
artifacts produced. "Unable to skip a hop and still finish" is not a
property koto provides.

**But there is a real residual claim along a different axis, and it is
worth having.** What koto actually buys is a change of *authorship and
legibility*, not of possibility:

> Under a koto gate, a hop that was genuinely performed leaves a
> `GateEvaluated` event written by koto, and a hop that was skipped
> leaves either nothing or a `DirectedTransition` / `GateOverrideRecorded`
> event naming the bypass. The two cases become distinguishable in a log
> the agent does not author. Skipping remains possible; it stops being
> *indistinguishable from compliance*.

That is stronger than R20, whose execution is unobservable from outside
the agent, and stronger than `chain_ran:`, which the agent writes. It is
much weaker than "cannot skip." It should be stated at that strength and
no higher — the same discipline the lead applied to the previous claim.

**This creates a sharp tension the exploration has to resolve.** The
residual value is realized only by someone or something *reading the
event log after the run*. That is post-hoc inspection, which is the
shape the author explicitly ruled out. The substrate/checker distinction
the lead asked to keep sharp does hold formally — the gate genuinely is
a substrate property, and the bypasses are separate code paths rather
than gate weaknesses — but the *practical* benefit that survives the
adversarial pass lands on the ruled-out side of the line. Adopting koto
gating for enforcement value, without also deciding who reads the log,
buys close to nothing over R20.

**If the design proceeds anyway, three constraints are non-negotiable.**
Route `children-complete` on `all_success`, never `all_complete`, or the
skip terminal is a sanctioned no-op exit. Do not rely on
`completion: state:` — it does not compile. And do not treat a
template's `when` clauses as a second line of defense, because `--to`
ignores them.

## Surprises

**`--to` ignores `when` clauses, not just gates.** I expected a force
flag to skip gates. I did not expect it to also discard evidence-based
routing. `src/cli/mod.rs:3309-3311` maps transitions to `t.target` and
never reads `t.when`, so every declared edge is reachable regardless of
its guard. This makes the template's routing logic, not only its gates,
advisory under `--to`.

**`koto overrides record` works with zero evidence.** I assumed
`--with-data` would be required to override a gate. The three-level
fallback in `src/cli/overrides.rs:54-72` bottoming out in
`built_in_default` (`src/gate.rs:239-243`) means the built-in default for
`context-exists` is literally `{"exists": true}`. The mandatory
`--rationale` is the only friction, and it is an unvalidated string.

**`completion:` is a compile-time stub.** The template format documents
`children-complete` as a completion-condition gate, which reads as
though a parent can require a specific child end-state.
`src/template/types.rs:561-584` rejects both non-`terminal` modes as
"reserved but not yet implemented." The gate is meaningfully weaker than
its documentation implies.

**F5 is a warning, not an error.** I went in expecting the lead's
premise — that F5 *requires* every child to have a skip terminal — to
hold. `src/template/compile.rs:428` prints to stderr and continues, and
the doc comment at `:357-360` explains the deliberate choice. So the
escape hatch is conventional rather than structural, which slightly
weakens the lead's framing of that sub-question while leaving the
`all_complete` counting problem fully intact.

**koto has thought hard about audit forgery.** `src/engine/audit.rs` is
a genuine surprise in the other direction: reserved kind prefixes
rejected at the CLI parser before any disk write (`:99-110`), synthetic
state names specifically so audit records cannot be promoted as results
(`:64-76`), and a type-level mitigation using `ValidatedSessionId` to
keep unvalidated ids out of human-readable narrative (`:18-24`). The
audit substrate is considerably more adversarially designed than the
gate substrate.

## Open Questions

1. **Who reads the event log, and when?** This is the question the whole
   lead reduces to. The surviving value of koto gating is a
   distinguishable durable trace, which is inert unless something
   consumes it. Answering "nobody" means koto gating buys nothing over
   R20; answering "a post-hoc reader" collides with the author's stated
   exclusion. Needs human input — it is a scope decision, not a
   research finding.

2. **Is a bypass that is loud but unblocked acceptable?** An agent that
   runs `koto next --to plan --rationale "upstream absorbed"` has left a
   typed event naming exactly what it did. Whether that counts as an
   adequate control depends on the threat model — a confused agent
   versus a motivated one — which the exploration has not stated.

3. **Would koto accept a hardening change?** `--to` restricted to
   non-gated states, or gate evaluation on the directed path, or a config
   key disabling either bypass, would move this from a legibility upgrade
   toward the enforcement upgrade the prior research claimed. koto is a
   sibling repo in the same workspace, so this is a real option rather
   than a hypothetical, but it is upstream work with its own cost.

4. **Does the per-session context store survive `/scope`'s actual
   process shape?** I established what the gates check but not whether a
   single `/scope` run is one koto session throughout. If children run
   as separate sessions, `context-exists` on the parent's session gates
   on keys the parent wrote, which weakens the gate further — the parent
   would be attesting to its own children's work. Flagging for whichever
   lead covers substrate shape.

## Summary

koto offers four gate types, all evaluated by the koto binary and all
durably recorded as koto-authored `GateEvaluated` events — but two
documented, unconfigurable commands defeat every one of them:
`koto next --to <state>` (`src/cli/mod.rs:3286-3322`) validates only that
the target is a declared edge and never reads gates or `when` clauses,
and `koto overrides record --rationale <anything>`
(`src/cli/overrides.rs:54-72` with `src/gate.rs:239-243`) injects a
synthetic pass with no evidence. The prior research's claim that a
`context-exists` gate makes the parent "unable to skip a hop and still
finish" is therefore too generous and falsified as worded; what survives
is narrower and different in kind — a skipped hop stops being
*indistinguishable from compliance*, because it leaves either nothing or
a typed `DirectedTransition` / `GateOverrideRecorded` event in a log the
agent does not author. The biggest open question is that this residual
value is only realized by reading the event log after the run, which
lands on the post-hoc side of the boundary the author explicitly ruled
out — so the exploration must decide who reads the log before it can
claim koto gating buys anything over `/scope`'s existing R20 check.
