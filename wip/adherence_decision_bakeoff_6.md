# Validation: Alternative 6 — Skill-registered conformance hooks

> Note: an earlier copy of this file was written at 15:18 and removed by a
> cleanup pass around 15:22 along with the context and alternatives docs. This
> is a rewrite incorporating the peer arguments from Validators 2 and 5.

## Mechanism verification

I verified the load-bearing claim independently against the installed binary at
`/home/dgazineu/.local/share/claude/versions/2.1.233` before the lead's
confirmation arrived. The two findings agree. All of this is **[confirmed
against the binary]**, and I have dropped the doc-only hedging accordingly.

**1. `hooks` is a recognized skill frontmatter key**, in the key list alongside
`name`, `description`, `model`, `allowed-tools`, `shell`, and read by the skill
parser as `hooks: sgv(e, r)`, validated against the standard hook schema
`record(enum(ALL_HOOK_EVENTS), array({matcher?, hooks:[HookDef]}))`. Plugin
skills take a separate path with its own error string, `Invalid hooks in plugin
skill '<name>'`. shirabe ships as a plugin, so that is the path that matters.

**2. Registration happens at invocation, into a session-keyed registry:**

```js
let l = await e.getPromptForCommand(t, ...);            // expand the skill body
let c = !IL("hooks") || aFe(e.source);
if (e.hooks && c) {
  let A = qt();                                          // CURRENT SESSION ID
  cAf(r.setAppState, A, e.hooks, e.name,
      e.type === "prompt" ? e.skillRoot : undefined);
}

function cAf(setState, sessionId, hooks, skillName, skillRoot) {
  for (let ev of ALL_HOOK_EVENTS)
    for (let group of hooks[ev] ?? [])
      for (let h of group.hooks) {
        let onSuccess = h.once
          ? () => { log(`Removing one-shot hook for event ${ev} in skill '${skillName}'`),
                    removeSessionHook(setState, sessionId, ev, h) }
          : undefined;
        addSessionHook(setState, sessionId, ev, group.matcher || "", h, onSuccess, skillRoot);
      }
  log(`Registered ${i} hooks from skill '${skillName}'`);
}
```

**3. Persistence is persistence-by-absence-of-cleanup.** The hook lands in
`appState.sessionHooks.get(sessionId)`, and the dispatcher `cMS` re-reads that
map on every subsequent hook event for the session. Nothing removes a
skill-registered hook. The subagent path has an explicit teardown
(`{name:"sessionHooks", run:()=>{ if(e.hooks) registry.clear(agentKey) }}`); the
skill path has no equivalent. `once: true` is the opt-out, implemented as the
removal callback above.

**4. The hook input carries the join key.** The common input builder returns
`{session_id, transcript_path, cwd, prompt_id, permission_mode, agent_id,
agent_type, effort}`. `session_id` is exactly what koto's workflow record is
keyed by. No inferential gap.

**5. `PreToolUse` is first-party documented as the surface that survives
`bypassPermissions`,** verbatim from the binary:

> canUseTool will not be invoked: permissionMode 'bypassPermissions'
> auto-approves every tool call (except explicit deny rules) before the callback
> is consulted. **To gate every tool call, use a PreToolUse hook instead.**

**6. `strictPluginOnlyCustomization` strips niwa's hooks and exempts shirabe's.**
The registration guard `!IL("hooks") || aFe(e.source)` reads that managed policy,
and `aFe` is true for `{plugin, policySettings, built-in, builtin, bundled}`.
shirabe's skills are `source: "plugin"`. niwa writes into an instance
`.claude/settings.json`, which is not in that set. Under that policy Alternative
6's channel survives and Alternative 3's does not.

**7. Skill-registered hooks do NOT fire inside spawned subagents.** The lookup
key resolution:

```js
function Aat(ctx, event, sessionId) {
  let n = ctx?.agentId ?? sessionId;
  let o = ctx?.agentContext;
  return (o !== undefined && WCr(o) && TOOL_EVENTS.has(event))
    ? [n, o.parentAgentId ?? sessionId]
    : [n];
}
// WCr(e) === e.agentType==="subagent" && e.isBuiltIn && e.subagentName===<built-in web-fetch>
```

**This closes the item the synthesis draft lists as open and load-bearing.** The
draft notes correctly that `/work-on` children legitimately write source files,
so a parent-registered write-target gate must exempt them, and flags the
behavior as unverified. It does not need to exempt them — the exemption is
structural. Inside any subagent, `agentId` is set, so the lookup key is the
agent id; the parent session's registry is never consulted; the parent's hook
does not fire. No `agent_id` matcher is needed and none should be written. The
sole carve-out in the code is for one built-in agent type (web-fetch),
irrelevant here. Treat this as resolved, with a live probe as confirmation
rather than as investigation.

**What I could not verify:** whether `${CLAUDE_PLUGIN_ROOT}` interpolates inside
a hook `command` string. The binary carries the variable and threads `skillRoot`
through to execution (`hookSource: "skill:<name>"`), so a relative-resolution
mechanism exists, but I did not pin the substitution rule. A hook can always
shell out to `shirabe`, which is on PATH for any adopter, so this is an
implementation detail rather than a viability question.

---

## Strengths

**It arms before the model can decide not to comply.** Registration happens
immediately after `getPromptForCommand` returns and before the expanded skill
body reaches the model. In incident 2 the agent ran the preflight, ran
`plan-to-tasks.sh`, then decided the session's no-subagents instruction
outranked `spawn_and_await`. The gate was already armed thousands of tokens
before that reasoning happened. No other alternative gets its enforcement in
place earlier than the decision it is meant to catch.

**It is outside the precedence order the model arbitrates.** This is the
decisive property, and the synthesis draft states the same conclusion
independently: injected context sits below a session instruction in the ordering
that already beat the skill, so no amount of louder prose wins that conflict,
while a hook block is not in the ordering at all. Incident 2 was not a failure of
knowledge or salience — the agent applied the documented precedence rule
correctly and lost.

**It gates the orchestrator and frees the children, structurally.** This falls
out of finding 7. A `PreToolUse` deny on `Edit`/`Write` registered by `/execute`
blocks the orchestrator's own inline edits and cannot reach a spawned `/work-on`
child. That is exactly the invariant `DESIGN-execute-skill.md` already asserts.
Alternative 4 buys the same invariant with an agent definition and pays twice
for it: hand-maintained carve-outs, and coverage only of `--agent`-launched
dispatch workers, missing the human who types `/execute`. Alternative 6 gets the
invariant on both entry paths, with the child exemption free rather than
configured.

**Zero distribution cost, no new policy surface.** It ships in
`skills/execute/SKILL.md` frontmatter. Every adopter gets it on `git pull` —
niwa or not, no niwa release, no `[claude.skills]` table, no org-owner action.
Alternative 3's own honest cost is that it introduces a policy surface niwa does
not have; Alternative 6 delivers Alternative 3's `gate` level without it.

**It sidesteps the `[workspace]` tombstone collision.** The org-owner knob does
not go into niwa. If a graded level is wanted, the hook script reads it from a
CLAUDE.md convention header — the mechanism shirabe already uses for `PR
Grouping Policy` and `Reviewability Ceiling`, and one a contributor *can* read,
because it is in the repo they cloned. That is the established
niwa-declares/shirabe-decides split with less machinery, not more.

**The gate is co-versioned with the workflow it enforces.** A gate distributed by
niwa encodes the predicate in a binary released on a different cadence than the
`execute` template it checks. When template states or record schemas change, the
two drift, and a drifted gate is a false-positive generator that blocks real
work in `bypassPermissions` sessions with no human to unblock it. A gate in the
same SKILL.md as the workflow cannot drift from it.

**Precedent exists for the executable half.** `shirabe pr-body-hook` is already a
`PreToolUse` deny that returns findings as the decision reason so the agent can
correct and retry (`crates/shirabe/src/pr_body_hook.rs:20-22`): always exits 0,
expresses the block as JSON, fails open on ambiguity, has an env kill switch.
That is the reference adapter; this adds a subcommand of a shape the repo
already ships, and a conformance check is deterministic validation and feedback,
which is what shirabe's CLAUDE.md says the CLI is for.

---

## Weaknesses

**It does nothing for incident 1, and this cannot be fixed inside the
alternative.** If `/execute` never fires, `cAf` never runs, and there is no gate.
As a standalone answer it fails hard constraint 1 and should be rejected. It
must be paired. The pairing is the description repair plus trigger evals, which
are the only work in the field that raises the odds on invocation and which the
repo owes itself regardless.

The fair form of the deeper objection is that the mechanism is self-defeating —
it protects only sessions that were already going to be fine. The evidence does
not support that. Half the observed corpus had the skill fire and then lose the
loop, *after* producing a valid payload with all six `waits_on` edges.
Invocation was not the hard part there; the thirty minutes after invocation
were, and shirabe reached this conclusion itself
(`DESIGN-execute-skill.md:227`, bind at every tick rather than only at entry).
A session-persistent hook is the only mechanism here that binds at every tick
without spending a token per tick.

**It gives org owners nothing to configure out of the box.** The user asked
explicitly, and this is soft constraint 8. My answer — a CLAUDE.md convention
header read by the hook script — is real but weaker than Alternative 3's: it is
per-repo, so an owner setting policy across twenty repos writes the header
twenty times. If cross-repo org policy is weighted heavily, Alternative 3 wins
that criterion outright and I will not pretend otherwise. I do not think it is
fatal, because the thing the user actually lost was visibility, not
configurability, and the header satisfies the stated request at the altitude
where a contributor can see what is being imposed on them.

**`disableAllHooks` kills it.** Confirmed: session hooks are collected only under
`if (!J8e() && ...)`, and `J8e()` is true when managed policy sets
`allowManagedHooksOnly` or the effective settings file sets `disableAllHooks`.
A project `.claude/settings.json` can silently disarm the gate. This is not a
discriminator — the same setting kills Alternative 1's SessionStart injection
and Alternative 3's niwa-injected hook. Under the other restriction policy
(`strictPluginOnlyCustomization`) Alternative 6 survives and Alternative 3 does
not. Net, the robustness comparison slightly favors 6, and neither is proof
against a determined local settings file.

**Session hooks probably do not survive a process-level resume.** `sessionHooks`
is in-memory app state. The evidence is indirect but hard to explain otherwise:
`/goal`, which registers a `Stop` hook through the same registry, ships a
dedicated `restoreGoalFromTranscript` that re-registers by scanning the
transcript on resume. If session hooks were persisted generically that code
would not exist. `/execute` runs are long, resumable, and cross-branch, so a
`claude --resume` after a crash comes back ungated. The mitigation is cheap — a
`SessionStart` matcher on `resume` in the same plugin — but it is work the
"zero configuration" pitch does not advertise.

**The gate buys visibility, not verified process.** koto's substrate-spawn is a
logging stub and review gates are directive text koto never verifies. A gate
keyed on koto state guarantees the run was registered and is visible in `koto
dashboard`; it does not guarantee the adversarial reviews ran. True of every
alternative here, and it should be stated plainly rather than sold as process
enforcement.

---

## Risks

### The predicate-gaming attack (Validator 2), and the predicate I would use

Validator 2 is right, and the objection is fatal to the *naive* form of my
predicate. "A koto session exists" is satisfiable by one command. An agent
meeting that gate can run `koto init`, buy write permission, and implement
inline anyway — leaving a record that attests registration and reads, to anyone
scanning the dashboard, as though the loop ran. Because koto's guarantees are
bookkeeping, that record proves nothing about delegation. Converting a visible
failure into an invisible one is a strictly worse outcome than incident 2, where
at least the absence was detectable. I concede this without reservation.

I would not repair it by strengthening the koto predicate. I would replace it.
**The synthesis draft's R9 write-target predicate is better than anything I
proposed and better than any of Validator 2's three candidates**, for a reason
that generalizes: it is checked on the write itself, so there is no separate
token to acquire and therefore nothing to game. `koto init` buys nothing,
because the gate never asks whether a session exists — it asks whether *this
write* is inside the closed set `/execute` already declares. It also needs no
coordinated-plan carve-out, and it enforces a contract the skill already
publishes rather than inventing one. Both incidents fail it directly:
hand-editing 22 or six issues' source files is precisely a write outside the
declared set.

What Alternative 6 contributes is that R9 write-target enforcement has nowhere
else to live. It is inherently skill-scoped — the closed set is `/execute`'s own
declaration, meaningless in a session that never invoked it — and it must fire
at write time in `bypassPermissions`, which only `PreToolUse` does. A
niwa-distributed hook would have to carry a copy of another repo's write-target
contract and keep it in sync across two release cadences. Skill frontmatter is
the only surface where the gate and the contract it enforces are the same file.

If a koto-state check is still wanted as the secondary detector, the strongest
non-gameable form is not `currentState` past `orchestrator_setup` (an agent can
advance the state machine as easily as it can create it) and not `scheduler_ran`
with `spawned_count >= 1` alone (koto's spawn is a logging stub, so that proves
scheduling, not execution). It is **the existence of a separate workflow record
over the `work-on` template whose koto workflow name matches `<parent>.o-*`** —
a child loop that actually ran and committed its own state. That requires a
second agent to have executed, which is the thing being attested. Glob all
workflow records for `koto.workflow` with the parent's prefix; that works
whether children share the parent's Claude session id or get their own.

### The deadlock (Validator 5), and the tension nobody has named

Validator 5's argument is correct and load-bearing: under `bypassPermissions`
with no human, an agent that can neither delegate nor edit does not stop — it
resolves the bind privately and undocumented, which is a new class of silent
failure and arguably worse than the one being fixed.

The important thing I want on the record for synthesis is that **the
gaming fix and the deadlock fix pull in opposite directions.** Every
strengthening that makes the predicate harder to game makes it harder to satisfy
without subagents; a predicate requiring delegation evidence is by construction
unsatisfiable by an agent forbidden from delegating. Any design that answers
Validator 2 by strengthening a *blocking* predicate walks straight into
Validator 5's deadlock. The resolution is not a better predicate. It is to put
the two checks on different events:

- **Blocking check (`PreToolUse`) must be satisfiable by the orchestrator
  alone.** R9 write-target conformance has this property natively: the escape is
  to write inside the declared set, which requires no subagent and no koto
  state. There is no bind, because the gate never demands delegation — it
  demands that the orchestrator not hand-edit issue source files, and the
  sanctioned alternative to that is delegation *or* recorded deviation.
- **Delegation check (`Stop`) must never block.** `Stop`'s `additionalContext`
  is non-error feedback with the conversation continuing, so the strong,
  ungameable, subagent-requiring predicate lives here where it costs nothing if
  unsatisfiable.

On top of that split, three explicit hatches, in priority order:

1. **A recorded deviation satisfies the blocking gate.** `koto overrides` is a
   shipped verb for exactly this. Deviation is sometimes correct; unrecorded
   deviation never is. This is Alternative 5's thesis, and the hook is what
   gives it teeth — incident 2's agent conceded it should have flagged the
   conflict and did not.
2. **Every denial emits a user-visible `systemMessage` alongside the
   agent-visible reason.** Confirmed in the binary: `systemMessage` — "Display a
   message to the user (all hooks)". `shirabe work-summary` already uses this
   channel and is already on niwa's default hook path for every adopter, so this
   is reuse, not invention. This is the direct answer to Validator 5: a
   privately-resolved bind stops being silent, because the bind itself is
   surfaced to the human at the moment it occurs, independent of whether the
   agent chooses to report it. That property is worth more than the block.
3. **A denial counter that degrades to warn.** After N consecutive denials in a
   session the check emits its reason as context and allows. A gate that can
   brick a headless run is worse than a gate that gives up. Plus the env kill
   switch `pr_body_hook` already models.

### Operational risks

**Fail-open is mandatory.** Hard constraint 5 exists because niwa documents that
a non-zero exit blocks the call, so a stale binary bricks every session
(`materialize.go:592-603`). The check must exit 0 with `permissionDecision:
"allow"` on every internal error — missing `jq`, unreadable paths, malformed
JSON, its own crash — and must not match `Bash`. Scope the matcher to
`Edit|Write|MultiEdit` so a bug costs file writes in one skill's sessions rather
than every command in every session.

**A skill invoked from inside a subagent registers on the parent's turns.**
`cAf` is called with `qt()` and has no agent-context branch, so a subagent
invoking `/execute` appears to land its gate on the main session. I did not
confirm what `qt()` returns inside an agent turn — [inferred] — but it deserves
a probe before a deny ships, because the failure mode is a gate firing in the
wrong place.

**Stop-hook nagging.** `once: true` is the wrong fix: it burns the single nudge
on the first turn boundary, which in an `/execute` run is right after the
preflight, long before the failure is diagnosable. Use no `once`, with a
per-session latch in the script capping the nudges at two or three.

**Thin field history.** Everything verified above is in 2.1.233 today, but I
found no adopter using skill frontmatter hooks for enforcement. Alternative 2's
advantage is that its pattern shipped twice in this repo. That is schedule risk,
and it argues for the `Stop` variant shipping first.

---

## Conditions under which this is the right choice

Alternative 6 is right when all of the following hold:

1. The decision accepts that incident 2 requires a mechanism outside the model's
   precedence arbitration. If better prose would have been enough, this is
   over-built and Alternative 1 is the answer.
2. Something else covers incident 1, explicitly rather than aspirationally.
3. The blocking predicate is satisfiable by the orchestrator alone — which R9
   write-target conformance is and a koto-session predicate is not.
4. Per-repo configuration is acceptable in place of per-workspace org policy.
5. The team holds the fail-open discipline and the `Bash`-exclusion in review.

It is the **wrong** choice if the goal is to catch hand-rolled work regardless of
path. That is Alternative 2's territory, and a session that never invokes the
skill is invisible to this mechanism.

---

## Recommendation

**adopt-with-conditions** — as the delivery substrate for the chosen policy, not
as the policy, and not as the whole answer.

Alternative 6 is a mechanism, not a strategy. It covers one of the two incidents
and is structurally incapable of covering the other. Presented as the answer it
fails hard constraint 1 and should be rejected. Presented as *how* the chosen
check reaches an adopter's session, it dominates the field, and the synthesis
draft's R9 write-target predicate is the check it should carry. That predicate
needs a surface that is skill-scoped (the closed write-target set is `/execute`'s
own declaration), fires at write time under `bypassPermissions` (only
`PreToolUse` does), and stays in the same file as the contract it enforces (only
frontmatter does). Skill-registered hooks are the only surface with all three.
My original koto-session predicate should be dropped; Validator 2 is right about
it, and R9 is strictly better.

What I would ship, in order:

- **Now:** the `execute` description repair and trigger evals, which are the only
  work that touches incident 1. Alongside them, a `Stop` hook in
  `skills/execute/SKILL.md` frontmatter running a fail-open `shirabe`
  subcommand, emitting both `additionalContext` and a user-visible
  `systemMessage` when no child `work-on` record exists for this run. No block,
  no deadlock surface, no configuration, no niwa release.
- **Next:** promote to a `PreToolUse` deny on `Edit|Write|MultiEdit` enforcing
  R9 write-target conformance, with the three hatches above. `P5: Strictness
  tracks blast radius` licenses exactly this staging, and here the promotion is
  a frontmatter change in one file rather than a config system.
- **Fold in Alternative 5 as the sanctioned resolution**, not standalone. Its
  honest cost is that surfacing a conflict has no teeth; a gate whose reason
  string names `koto overrides` as an accepted resolution supplies them.
- **Ship Alternative 2's payload-seam closure independently.** Cheapest
  intervention in the round and orthogonal to all of this.
- **Do not ship Alternative 3's niwa policy surface** unless the org-owner
  requirement is genuinely cross-repo. If it is, keep Alternative 3's level
  semantics and replace its transport with this one.

One thing the decision should not let itself forget: every alternative here,
mine included, buys visibility rather than verified process. koto records that
evidence was submitted in the right order; it does not verify the evidence is
true. If the outcome is written up as "the adversarial reviews will now
definitely run," the writeup is wrong.
