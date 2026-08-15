# Lead: What guarantees does koto provide, and is "a koto session exists for this plan" observable from outside the agent?

Investigated directly by the orchestrator after two delegated attempts died on
usage limits. Everything below is confirmed by running commands and reading real
files on this machine, not inferred.

## Findings

### 1. Session state is an append-only JSONL event log on local disk

Layout, confirmed by `find`:

```
~/.koto/sessions/<workflow-name>/
├── koto-<workflow-name>.state.jsonl     # append-only event log
└── ctx/
    ├── manifest.json                     # content-context key index
    ├── manifest.lock
    ├── settled_branch                    # a context value
    └── workflows/publish-location
```

The first line of the state log is a header record. Real example from
`~/.koto/sessions/demo-before/koto-demo-before.state.jsonl`:

```json
{"schema_version":1,"workflow":"demo-before",
 "template_hash":"63d02c5c8bb...","created_at":"2026-08-15T18:59:11.959Z",
 "template_source_dir":".../shirabe/0.16.1-dev/skills/execute/koto-templates",
 "session_id":"6ca7fa36-2e97-4ffa-81b5-0813dfb1efbb",
 "template_name":"execute","dispatch_epoch":0}
```

Every subsequent line is a sequenced event:

```json
{"seq":1,"type":"workflow_initialized","payload":{"variables":{
   "PAUSE_BEFORE_FINALIZE":"false","PLAN_DOC":"docs/plans/PLAN-x.md","PLAN_SLUG":"x"}}}
{"seq":2,"type":"transitioned","payload":{"from":null,"to":"orchestrator_setup",...}}
{"seq":3,"type":"intent_updated","payload":{"intent":"Plan orchestrator template. Creates a
   shared branch and draft PR, spawns per-issue work-on.md children, awaits batch
   completion, finalizes the PR description, marks it ready, and monitors CI to green."}}
{"seq":4,"type":"context_added","payload":{"key":"settled_branch","hash":"68d108a5...","size":26}}
```

Two properties matter for this exploration. **The header names the template**
(`"template_name":"execute"`), so an execute-driven run is distinguishable from
any other koto workflow. And **the initialization event carries `PLAN_DOC`**, so
a session is bound to a specific plan document by path.

### 2. The gate condition is computable, cheaply, with zero agent cooperation

This was the make-or-break question. It is answered yes.

**Does a koto session exist for this plan?**

```bash
grep -l "\"PLAN_DOC\":\"docs/plans/PLAN-<slug>.md\"" \
     ~/.koto/sessions/*/koto-*.state.jsonl 2>/dev/null
```

Run live against real state: 32 sessions on this machine carry a `PLAN_DOC`
variable. Sample hits include `execute-vale-adoption`,
`execute-calendar-cli-only`, and
`execute-chain-cardinality.o-sequence-entries-survive-frontmatter-parsing`.

**What state is a given workflow in?**

```bash
koto status <name> 2>/dev/null
```

Returns clean JSON on **stdout**:

```json
{"current_state":"orchestrator_setup","is_terminal":false,"name":"demo-before",
 "template_hash":"63d02c5c8bb...","template_path":"/home/dgazineu/.cache/koto/63d02c5c8bb....json"}
```

`koto status --help` confirms it is documented "read-only, no state changes",
which makes it safe to call from a hook.

**Operational caveat, important for hook authors.** Both `koto workflows` and
`koto status` emit a large volume of `koto: migration skipped <name>: session
already exists` lines to **stderr** before the payload — dozens of lines on this
machine, one per legacy session. Any hook parsing koto output must redirect
stderr (`2>/dev/null`) or it will choke on noise. The direct `grep` over
`state.jsonl` avoids the CLI entirely and is faster; prefer it for a hot path
like PreToolUse.

### 3. Incident 2 is confirmed by the artifact record

The incident report said `~/.koto/sessions/` held only unrelated pre-existing
sessions. The directory listing corroborates the shape of that claim: 1,210
session directories exist, the overwhelming majority dated March through early
April, and only `demo-before` is dated 2026-08-15. No session exists for the plan
that incident 2 implemented.

This is the proof that the durable artifact discriminates where invocation does
not. The incident agent **ran `plan-to-tasks.sh` and produced a valid payload
with all six `waits_on` edges** — so any check asking "did the skill fire" or
"did the scripts run" would have passed it. The `PLAN_DOC` grep returns nothing.
That is the whole finding.

### 4. What koto supplies that a hand-rolled loop does not

Read off the `intent_updated` payload of the execute template, which states the
contract in one sentence: "Creates a shared branch and draft PR, spawns per-issue
work-on.md children, awaits batch completion, finalizes the PR description, marks
it ready, and monitors CI to green."

Decomposed, the guarantees are: a **task state machine** with recorded
transitions (`transitioned` events with `from`/`to` and a condition type); **one
fresh `/work-on` child per issue** rather than one context implementing
everything; a **batch await** that is the natural place review gates hang;
**content context** with hashed, manifest-indexed keys (`context_added` events)
so downstream steps read what upstream steps actually produced; and **CI monitoring
through to green** rather than stopping at "pushed."

The CLI surface confirms the scope: `init`, `next`, `cancel`, `rewind`,
`workflows`, `status`, `context`, `decisions`, `overrides`, `request`,
`dashboard`, `session`, `workspace`.

Two of those are directly relevant to the user's stated loss. **`koto decisions`**
records decisions, and **`koto overrides`** records *gate overrides* — meaning
koto already has a first-class notion of a gate being deliberately bypassed and
that bypass being written down. An agent that hand-rolls the loop produces no
override record; an agent inside the loop that skips a gate produces one. That
distinction is the difference between an unlogged deviation and an audited one,
and it bears directly on the precedence-conflict problem incident 2 raised.

And **`koto dashboard`** is a live terminal view of session hierarchy and state —
which is precisely the visibility the user said they lost. The visibility was
never missing from the system; it was missing because nothing registered a
session for it to display.

### 5. Where koto is structurally blind

Koto observes what is submitted to it. It has no view of edits made outside a
task, no hook into the agent's tool calls, and no way to notice that a plan it
was never told about is being implemented in the same repo. It cannot detect its
own absence.

This is the asymmetry the design has to absorb: **koto is an excellent detector
of what happened inside it and a null detector of what happened instead of it.**
The observation therefore has to come from a surface that sees tool calls — a
hook — and consult koto state as the *reference*, not the *sensor*.

### 6. The payload/submission seam

Incident 2 turned on a specific structural fact: `plan-to-tasks.sh` produces a
payload, and submitting that payload to a session is a separate, independently
skippable step. The script is plain bash and never touches koto (the incident
report says the same of `preflight.sh` and `run-cascade.sh`).

So the execute skill has a step that looks like progress, produces a real
artifact, and leaves no koto trace. An agent can complete it and stop, having
done real work, with nothing registered. Whether the seam should be closed —
by having the script refuse to emit a payload it cannot also register, or by
making production-and-submission atomic — is a design question this lead surfaces
rather than answers. It is the cheapest single intervention identified in this
round, because it needs no hook, no policy, and no niwa change.

## Implications

**The gate condition is computable, so the one path-agnostic mechanism with teeth
is viable.** A PreToolUse hook can, on an Edit/Write in a repo where a PLAN doc
is in play, run a sub-millisecond grep over `~/.koto/sessions/*/…state.jsonl` and
know whether a session exists for that plan. This was the open question blocking
the whole enforcement end of the spectrum. It is closed.

**The durable artifact is the right unit, and it is a single grep.** "Was the skill
invoked" passes incident 2; "does a koto session exist for this plan" fails it.
Any check the design adopts should key on the latter.

**The same condition serves all three strengths.** Detect-and-report (a Stop hook
that notices a plan was implemented with no session), remind (a UserPromptSubmit
hook that says so at the next turn), and gate (a PreToolUse deny) are the same
predicate evaluated at three different lifecycle events. That is a strong argument
for the graded-policy shape: one condition, one implementation, a level that
chooses when it fires and how hard.

**koto already models "a gate was overridden."** `koto overrides` means the
design does not have to invent an audit trail for deliberate deviation — it has
to route deviation through a surface that records it. That reframes the
precedence-conflict problem from "stop the agent deviating" to "make deviation
leave a record," which is much closer to the user's stated preference for
guidance over enforcement.

**The visibility loss was a registration failure, not a tooling gap.**
`koto dashboard` exists. Nothing appeared in it because nothing was registered.

## Surprises

**`koto status` is clean JSON on stdout but preceded by dozens of stderr warnings.**
The `migration skipped` noise is one line per legacy session and would break a
naively written hook. Worth fixing in koto independently; worth knowing about
before anyone writes the hook.

**1,210 session directories, essentially all from March and April.** The store
has never been reaped. `koto workspace` advertises "reclaim and maintenance
verbs," so the capability exists and has not been run. Not this exploration's
problem, but a grep-based hook's cost scales with this directory, so it is
adjacent.

**The state log records `intent`, in prose, as an event.** `intent_updated`
carries a human-readable description of what the workflow is for. That is a
richer audit surface than expected and would let a report say what the run was
supposed to be doing, not just which state it reached.

**`koto overrides` already exists.** I expected to have to argue for building an
audit trail for deliberate gate bypass. It is a shipped verb.

## Open Questions

1. **How does a hook know a PLAN doc is "in play"?** The `PLAN_DOC` grep answers
   "is there a session for plan X" but something must supply X. Candidates: the
   branch name, a `wip/` state file, the PR body, or the prompt text. This is the
   remaining gap in the gate condition and it belongs to the hook-surfaces lead.
2. **Should `plan-to-tasks.sh` refuse to emit an unregistered payload?** The
   cheapest intervention found this round, and it needs no policy machinery.
3. **Is the session store's growth a practical problem for a hot-path grep?**
   1,210 directories today, unreaped since April.
4. **Does `koto overrides` fit the precedence-conflict case?** If an agent
   concludes a session constraint forbids `spawn_and_await`, is recording an
   override the sanctioned response — and can that be made the only path forward
   that does not stall?

## Summary

Koto session state is an append-only JSONL log at
`~/.koto/sessions/<name>/koto-<name>.state.jsonl` whose header names the template
(`"template_name":"execute"`) and whose init event carries `PLAN_DOC`, so "does a
koto session exist for this plan" is a single grep answerable from outside with
zero agent cooperation — confirmed live against 32 real plan-bound sessions, and
confirmed to return nothing for incident 2's plan even though that agent ran the
skill's scripts and produced a valid payload. This closes the make-or-break
question: the durable artifact discriminates where invocation does not, and the
same predicate can be evaluated at Stop (report), UserPromptSubmit (remind), or
PreToolUse (gate), which argues for one condition behind a graded level rather
than three mechanisms. The biggest open question is how a hook learns which PLAN
doc is in play, since the grep answers "is there a session for plan X" but
something upstream must supply X.
