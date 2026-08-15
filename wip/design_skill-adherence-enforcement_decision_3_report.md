# Decision 3: Registration surface, lifetime, and the operator switch

**Question.** Where does the enforcement register, what is its lifetime, and how
does an operator disable the refusal while leaving the read-only determination
available?

**Requirements in scope.** R12 (agent-launched coverage), R15 (operator switch
with the determination surviving), R16 (100ms p95), R17 (absent/failed/stale
degrades to permit).

**Classification.** Critical (Tier 4).

All binary claims below were re-verified independently against
`/home/dgazineu/.local/share/claude/versions/2.1.233` for this decision rather
than carried over from `wip/adherence_decision_bakeoff_6.md`. Where my reading
differs from a prior artifact, I say so. Where a claim is inference rather than
extraction, it is labeled.

---

## What the binary actually says

Six facts carry this decision. Each is an extraction, quoted.

**F1 — Skill-frontmatter hooks register as a side effect of invocation, and
persist for the session.** The registrar:

```js
function cAf(e,t,r,n,o){ ... for(let l of a) for(let c of l.hooks){
  let u=c.once?()=>{ w(`Removing one-shot hook for event ${s} in skill '${n}'`),
                     gka(e,t,s,c) }:void 0;
  Y1n(e,t,s,l.matcher||"",c,u,o), i++ }
  if(i>0) w(`Registered ${i} hooks from skill '${n}'`) }
```

It is reached from the skill-expansion path, guarded on the skill declaring
`hooks`. The one-shot removal branch is the proof that the default is
persistent. Confirmed, and it agrees with the prior verification note.

**F2 — Skill-registered hooks do NOT fire inside spawned subagents.** This is
the item the coordination file lists as "known_unverified" and the lead flagged
as unresolved. It is now resolved. The session-key resolver:

```js
function Aat(e,t,r){ let n=e?.agentId??r, o=e?.agentContext;
  return o!==void 0 && WCr(o) && NU_.has(t) ? [n, o.parentAgentId??r] : [n] }
function WCr(e){ return e.agentType==="subagent" && e.isBuiltIn===!0
                        && e.subagentName===kM }
```

Inside any agent context the key is `agentId`, so the parent session's
registry is never consulted. The parent-key fallback exists for exactly one
built-in subagent type (`WCr`), irrelevant here. The consumer confirms the
scoping — in `cMS`, only `ZLt(e,d,r)` (the session-hook registry) is keyed by
the `Aat` array.

**F3 — Settings-file and plugin hooks are session-key-independent, so they DO
fire inside subagents.** Same function, opposite half. `cMS` pushes
`Khe()?.[r]` (settings) and `Sle()?.[r]` (plugin) into the result without
reference to the key array. This corroborates the documented statement quoted in
`wip/research/..._lead-hook-surfaces.md` §1 ("Hooks from settings files, managed
policy settings, and plugins also run inside subagents ... the input carries the
`agent_id` and `agent_type` common input fields").

**F4 — `disableAllHooks` kills all three candidate placements identically.**
Confirmed on two independent paths.

```js
function J8e(){ let e=dn("policySettings");
  if(e?.allowManagedHooksOnly===!0) return!0;
  if(Ta().disableAllHooks===!0 && e?.disableAllHooks!==!0) return!0; return!1 }
function RL(){ return dd()||J8e() }              // dd() === --safe-mode
```

- Settings hooks: `Kzs()` returns only `policySettings.hooks` once
  `Ta().disableAllHooks===true`.
- Skill/session hooks: `cMS` collects them only under `if(!J8e() && e!==void 0)`.
- Plugin hooks: collected, then dropped —
  `if(s && "pluginRoot" in d && !a?.has(d.pluginId)) continue`, where `s=RL()`
  and `a=IIe()` is the managed `enabledPlugins` allowlist, `null` when unset.
  The loader carries the matching guard:
  `if(RL() && (dd() || IIe()===null)) { "Skipping plugin hooks ..." }`.

Only managed-policy hooks survive. I initially read the plugin path as surviving
`disableAllHooks` and it does not; the `IIe()===null` filter is what closes it.

**F5 — `strictPluginOnlyCustomization` favors plugin sources.**
`IL(e)` reads the managed-policy array or boolean; `aFe(source)` exempts
`{plugin, policySettings, built-in, builtin, bundled}`. Under
`strictPluginOnlyCustomization: ["hooks"]`, a shirabe plugin hook survives and a
niwa-written project `.claude/settings.json` hook does not.

**F6 — Workspace trust gates every hook, not any one placement.** `JF` opens
with `if(Cmt()) return w("Skipping ${a} hook execution - workspace trust not
accepted"),[]`. Trust is a session-level precondition on all hook execution and
is therefore not a discriminator between the three placements. (I very nearly
argued the opposite from `$bi`/`Obi`, which is the *frontmatter*-specific trust
check for agent and skill definition folders — a narrower thing.)

**Measured, for R16.** The shipped adapter `shirabe pr-body-hook`, cold process,
40 samples on this machine: min 4ms, **p95 6ms**, max 6ms. That is the whole
process-spawn-plus-parse cost of the reference shape, against a 100ms budget.

---

## The structural conflict, worked out rather than papered over

**Placement 1 cannot satisfy R4, and therefore cannot host the refusal.**

The chain is short and it does not have a repair inside the alternative:

1. By F1, registration happens as a side effect of skill expansion. No
   invocation, no registration.
2. R4 requires R3 to arm "on a signal ... that SHALL NOT be the invocation of the
   plan-execution skill", and AC11 makes the never-invoked, never-named-a-workflow
   session a **required refusal** — the PRD calls it "the arming case".
3. A hook that does not exist cannot refuse. Placement 1 fails AC11 by
   construction, for the exact journey the requirement was written to cover.

This is a disqualification, not a weakness to be traded off.

The prior bakeoff (`wip/adherence_decision_bakeoff_6.md`, "Recommendation")
argued placement 1 is nonetheless the only viable home because the write-target
predicate "is inherently skill-scoped — the closed set is `/execute`'s own
declaration, meaningless in a session that never invoked it." **That argument
does not survive R3's wording.** R3 refuses writes outside "the closed
write-target set *the plan-execution skill declares for itself*" — a static
property of the shipped skill, sitting on disk at
`skills/execute/SKILL.md:661-667`, readable with no invocation whatsoever. The
only session-dependent part is the `<topic>` slug that parameterizes
`wip/execute_<topic>_*`, and the slug comes from the PLAN under execution, which
is decision 2's arming input, not from the act of invoking. The bakeoff reached
its conclusion before the PRD split arming from invocation; the split invalidates
its premise.

So the surviving question is not "frontmatter or settings" but "which
non-frontmatter surface", and the framing's three candidates under-weight a
fourth that is neither: **shirabe's own plugin `hooks/hooks.json`**.

---

## Options

### Option A — Skill frontmatter (`skills/execute/SKILL.md` `hooks:`)

Registers at invocation into a session-keyed in-memory registry, persists for the
session, `once: true` opts out (F1). Children are exempt structurally (F2).
Ships to every adopter on `git pull`, no workspace configuration, and cannot
drift from the contract it enforces because both are in the same file.

Fails R4/AC11 outright. Two further costs, both relevant even as a supplement:

- **Lifetime is wrong for the workload.** `sessionHooks` is a `Map` in app state
  (`a.sessionHooks.set(t,{hooks:p})`), with no serialization anywhere in the
  binary. `/goal`, which registers a `Stop` hook through the same registry,
  ships a dedicated `restoreGoalFromTranscript` to re-register after a restart —
  code that would be unnecessary if the registry persisted. [Inference, strongly
  supported.] `/execute` runs are long, resumable, and cross-branch
  (`skills/execute/SKILL.md` **Resume**), so a `claude --resume` returns
  ungated.
- **A skill invoked from inside a subagent registers on the wrong key.** `cAf`'s
  session id is taken from the ambient current-session accessor with no
  agent-context branch. [Inference — I did not pin the accessor's behavior inside
  an agent turn.] The failure mode is a gate arming in the wrong place, which is
  worse than not arming.

### Option B — niwa-distributed settings hooks

Precedented and shipped. `shirabe pr-body-hook` is a niwa-injected PreToolUse
allow/deny gate, default-on for any instance whose config installs the shirabe
plugin, gated on `shirabePluginName` (`materialize.go:487`,
`installsShirabePlugin` at `:525`), with a `[claude] pr_body_hook = false` off
switch (`prBodyHookEnabled`, `:611`) and marker-grep dedup (`:644`). The command
shape encodes the fail-open discipline this design needs verbatim:

```go
// materialize.go:604
return "command -v shirabe >/dev/null 2>&1 || exit 0; shirabe pr-body-hook 2>/dev/null || exit 0"
```

Costs: reaches only niwa-managed instances; is the source `strictPluginOnlyCustomization`
strips first (F5); and puts the gate on niwa's release cadence while the contract
it enforces lives in shirabe's. The richer form the niwa research sketched — a
`[claude.skills]` policy table with graded levels — is **explicitly out of scope
per the PRD** ("A workspace-level policy surface for declaring required skills")
and re-opens the `[workspace]` overlay-tombstone values question that research
flagged as genuinely contested.

### Option C — shirabe plugin `hooks/hooks.json` *(chosen)*

Neither of the framing's first two. The plugin manifest at
`.claude-plugin/plugin.json` declares `skills` today and no hooks; shirabe ships
no `hooks/` directory yet. The pattern is standard and locally precedented —
superpowers 6.2.0 declares
`"command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start"`.

Registration is part of plugin load (`await zct(...)` on the plugin-load path),
so it happens once per session before the agent loop, for every session shape:
interactive, `-p`, `--bg`, dispatched, and resumed.

### Option D — Both A and C

Rejected below.

---

## Chosen option

**Option C: register the refusal as a `PreToolUse` hook declared in shirabe's own
plugin `hooks/hooks.json`, matching `Edit|Write|MultiEdit|NotebookEdit`, running
a fail-open `shirabe` subcommand that reads the plugin-shipped write-target
declaration via `${CLAUDE_PLUGIN_ROOT}`.**

Sketch, deliberately the `pr-body-hook` shape:

```json
{ "hooks": { "PreToolUse": [ { "matcher": "Edit|Write|MultiEdit|NotebookEdit",
  "hooks": [ { "type": "command", "shell": "bash",
    "command": "command -v shirabe >/dev/null 2>&1 || exit 0; shirabe adherence-hook --contract \"${CLAUDE_PLUGIN_ROOT}\" 2>/dev/null || exit 0" } ] } ] } }
```

`type: "command"` is load-bearing, not incidental: a `prompt`- or `agent`-type
hook's deny **ends the turn** with a chat warning unless `continueOnBlock: true`
is set (behavior changed at v2.1.210), whereas a command hook's deny is fed back
as the tool error and the turn continues — which is what AC13 ("proceeds
correctly on its next attempt with no human input") requires.

### Lifetime

**Registration is unconditional and session-long; arming is decided per tool
call.** The hook is always registered, observes every `Edit`/`Write`, and answers
"not armed, allow" for the overwhelming majority of calls. It carries no state
between calls.

Separating these two lifetimes is what makes R4 and R8 compatible. If
registration were the arming act (Option A), arming would inherit invocation as
its trigger, which R4 forbids. With registration unconditional, the arming
predicate (decision 2) is free to be anything readable from the hook input plus
disk — and R8's "cannot establish → do not arm → the write proceeds" becomes the
default branch rather than an exception.

It also sets the R16 design rule: **the not-armed answer must be reachable
without expensive I/O**, because that path runs on every file write in every
session on the machine. Cheap discriminators first, disk work only after arming
looks plausible. Measured headroom is 100ms − 6ms ≈ 94ms for predicate I/O,
which is generous but is the thing AC28 must regression-test.

### The operator switch (R15), and `disableAllHooks`

**They are different levers, and the DESIGN must say so in the operator-facing
documentation.**

`disableAllHooks` is not R15's switch, for three reasons:

1. **Over-broad.** By F4 it kills settings hooks, plugin hooks, main-thread agent
   hooks, and skill session hooks alike, leaving only managed-policy hooks. An
   operator reaching for it to silence one refusal silently loses the four hooks
   niwa already ships (`work-summary` capture / absence / compact, and
   `pr-body-hook`).
2. **Not expressible per-mechanism.** R15 asks for disabling *the refusal*. There
   is no surgical disable at any settings level; hooks merge and nothing removes
   a specific one.
3. **Not operator-specific.** It is read from the effective settings after
   precedence, so a project `.claude/settings.json` any contributor can edit
   reaches it.

It does happen to satisfy R15's second clause — the read-only determination
survives, because the determination is a `shirabe` CLI subcommand a human or CI
runs, not a hook — but only incidentally.

**R15's switch is the `PR_BODY_HOOK_DISABLE` seam, reused in shape:** an env
check first in `run()`, short-circuiting to allow before any I/O
(`crates/shirabe/src/pr_body_hook.rs:47-65`), plus a durable repo-readable form.
For the durable form, use a CLAUDE.md convention header — the mechanism shirabe
already uses for `PR Grouping Policy`, `Reviewability Ceiling`, and `Release
Notes Convention` — resolved `env > CLAUDE.md header > default(on)`, matching the
existing headers' documented resolution order. This keeps the setting where the
contributor it applies to can read it, which is the property niwa's `[workspace]`
tombstone reasoning protects, and it stays inside the PRD's scope by not creating
a workspace policy surface.

**Can an agent reach it?** Yes, and the PRD already concedes this (Known
Limitations). Two things worth recording:

- Self-disarming by editing `.claude/settings.json` or the CLAUDE.md header is
  itself a write, outside `/execute`'s declared set, so an armed orchestrator's
  attempt to disarm is itself refused. That raises the cost without eliminating
  it.
- The env route is *harder* for an in-session agent than `disableAllHooks`. The
  hook runs as a child of the Claude Code process and inherits its environment,
  not the environment of a `Bash` subshell; `export` in a tool call reaches
  nothing. Durably setting it requires editing settings `env:` or a shell
  profile — both writes, both refusable.

---

## Rationale against the requirements

**R12 (agent-launched coverage).** Three launch shapes, all covered by C:

- *Separate session* (niwa dispatch, `claude --bg`, `claude -p`): plugins load per
  session, so the hook registers with the child's own `session_id`. This is
  AC11's journey and it is the one Option A cannot reach.
- *Subagent* (Task / `spawn_and_await`): plugin hooks fire inside subagents (F3),
  carrying `agent_id` and `agent_type` on the input.
- *Resumed session*: plugin load runs again at startup; unlike the in-memory
  session registry, nothing needs re-registering by hand.

The consequence of F2/F3 together is the **opposite** of what the task framing
anticipated. The risk is not that `/work-on` children escape the gate; it is that
they are **caught** by it. Option A would have exempted them structurally;
Option C must exempt them explicitly, by reading `agent_id`/`agent_type` off the
hook input. R8 makes that fail-safe: role not establishable → not armed → allow.

**R15.** Satisfied by the env seam plus the convention header, with the
determination untouched because it is a separate read-only CLI verb (AC18 is
directly testable: set the switch, run a plan-scale session, assert no refusal
and assert `shirabe <determination>` still returns a verdict).

**R16.** Measured p95 of 6ms for the reference adapter shape, 40 samples, against
a 100ms budget. Command hooks for an event run in parallel and the tool call
waits on the slowest, not the sum, so co-existing with niwa's `Bash`-matched
hooks costs nothing — the matchers do not overlap.

**R17.** Three degradations, all already expressed in the reference adapter:
absent binary (`command -v shirabe || exit 0`), failing binary (`|| exit 0`, plus
`run()` always returning `ExitCode::SUCCESS` and expressing a block as JSON
rather than an exit code — `pr_body_hook.rs:43-56`), and version staleness (the
contract version is read from the plugin-shipped declaration; a binary that does
not understand the declared version allows — AC17). Passing
`${CLAUDE_PLUGIN_ROOT}` rather than compiling the write-target set into the
binary is what makes the staleness check meaningful, because the plugin and the
tsuku-installed binary version independently.

**R18** (no mechanism asserting skills outrank user instructions). The hook
refuses a *write target*, names a sanctioned alternative, and — per decision 4 —
names the recorded-conflict route as an accepted resolution. It never asserts
precedence. Satisfied by construction.

---

## The adversarial case against the chosen option

The strongest concrete failure is not a bypass. It is a **false refusal that
deadlocks a headless run**, and it comes from the interaction between my
placement and the delegation primitive this workspace actually uses.

**The case.** `/execute` reaches the delegation step for issue 3 of 6. It hands
the issue to a child. If that child is a **separate Claude session** rather than a
Task subagent — which is exactly what `niwa dispatch` is (the workspace root
CLAUDE.md documents it as the way to "hand the work off to run on its own", and
`/execute`'s coordinated path is described as "a plain durable-state loop") —
then the child has **no `agent_id`**. It is a session, in a repo, with a PLAN
document present, writing source files: the precise shape decision 2's arming
signal keys on. The `agent_id` exemption does not fire. The child is refused on
its first `Edit`. It is running under `bypassPermissions` with no human present,
where R6 requires the refusal to hold. It cannot delegate further and cannot
write. The run stalls, or the agent resolves the bind privately — which is a new
silent failure mode, arguably worse than the one being fixed.

This is the failure case, and it is not hypothetical: it is the delegation path
this workspace ships.

Three mitigations, in order of how much they buy:

1. **The orchestrator/child distinction must survive a session boundary.** A
   parent handing work to a separate session must pass a scope marker the child's
   arming predicate can read — an env var on the dispatched process, or a field in
   the child's brief. This is decision 2's mechanism, but my placement is what
   makes it load-bearing, so it is stated here as a cross-decision constraint and
   sent to decision 2.
2. **R8 is the backstop and it points the safe way.** "Where the system cannot
   establish that a session is performing plan-scale execution in the orchestrator
   role, it SHALL NOT arm." An ambiguous separate-session child is therefore
   permitted. The cost is that a genuinely non-conforming orchestrator that looks
   like a child escapes the refusal — but it is still caught by the read-only
   determination, which does not fail open (R9). The asymmetry the PRD's
   "Decisions and Trade-offs" section deliberately built is exactly what absorbs
   this.
3. **A denial counter that degrades to warn.** After N consecutive refusals in one
   session, emit the reason as `additionalContext` and allow. A gate that can
   brick a headless run is worse than a gate that gives up. This bounds the damage
   even when the classification is wrong, and it costs one counter in the state
   the hook already has access to.

Three lesser attacks, for completeness:

- **Plugin not enabled.** No plugin, no hook. Covered by R17 and by the scope
  assumption below, but the DESIGN must say the enforcement's population is
  "sessions with the shirabe plugin enabled" rather than claim universal coverage.
- **`allowManagedHooksOnly` with no managed `enabledPlugins`.** By F4 the plugin
  hooks are not even loaded. Enterprise adopters get nothing, fail-open. The
  remedy is documentable: list shirabe in managed `enabledPlugins`.
- **Subprocess writes.** A `Bash` heredoc bypasses an `Edit|Write` matcher. Already
  a stated Known Limitation. Extending the matcher to `Bash` is the footgun niwa's
  own source warns about at `materialize.go:592-603`, and shell-text write
  detection is unreliable. Keep the matcher narrow; accept the limitation as the
  PRD does.

---

## Rejected options and why

**Option A as the primary surface.** Disqualified by R4/AC11 — registration is a
side effect of invocation (F1), and AC11 requires refusal in a session that never
invoked the skill. Not a trade-off.

**Option D, A and C together.** Rejected. It buys no coverage: any session that
can register a skill hook has already loaded the plugin, so C already covers it.
It costs a second copy of the predicate, a second process spawn per write, and a
second lifetime that behaves differently across `--resume`. It would also
double-register, which the deny-wins merge makes *correct* but not free.

**Option B with the `[claude.skills]` policy table.** Out of scope per the PRD's
own Out of Scope list, and re-opens a values question niwa has already answered in
the opposite direction (`[workspace]` is deliberately overlay-proof so a private
layer cannot change what a contributor's run does).

**Option B in its minimal form** (niwa injects a fixed hook, `pr_body_hook`-shaped,
`[claude] adherence_hook = false` off switch). Viable and well precedented, and I
would not call it wrong. Rejected because it reaches only niwa instances while the
plugin reaches every adopter, it is the first source
`strictPluginOnlyCustomization` strips (F5), and it separates the gate's release
cadence from the contract's. **Keep it as the named fallback** if open question 2
below resolves badly.

**`disableAllHooks` as R15's switch.** Rejected on all three grounds in the
operator-switch section above.

**`UserPromptSubmit` or `Stop` as the refusal's surface.** `UserPromptSubmit`'s
block reason goes to the user and not to the model, which is a silent dead end in
an unattended run; `Stop` fires after the writes have landed. Both remain useful
as non-blocking secondary surfaces — decision 4's territory, not this one's.

---

## Assumptions

1. A session without the shirabe plugin is out of scope. R17 makes that a
   permitted degradation rather than a coverage gap, and the DESIGN should state
   the population explicitly rather than imply universality.
2. The `shirabe` binary is on PATH (tsuku-installed) and is not shipped inside the
   plugin, so the hook shells out behind the `command -v` guard and the plugin and
   binary version independently. This is why the contract-version staleness check
   (R17/AC17) is a real requirement and not a formality.
3. `/execute`'s closed write-target set becomes machine-readable inside the plugin
   and versioned. Today it exists only as prose at
   `skills/execute/SKILL.md:661-667`, parameterized by `<topic>`. The prose must be
   generated from, or validated against, the machine-readable form — otherwise the
   refusal enforces a different set than the skill documents, which is the drift
   this placement was chosen to avoid.
4. Decision 2 supplies an arming predicate evaluable from the PreToolUse input
   (`session_id`, `cwd`, `tool_input`, `transcript_path`, `agent_id`, `agent_type`)
   plus on-disk state, with a cheap not-armed early-out.
5. A `PreToolUse` deny is not defeated by `bypassPermissions`. First-party
   documented, and stated in the binary: "permissionMode 'bypassPermissions'
   auto-approves every tool call ... To gate every tool call, use a PreToolUse hook
   instead."

---

## Open questions the DESIGN must carry

1. **Does an `/execute`-delegated child arrive as a Task subagent or as a separate
   session?** This decides whether the `agent_id` exemption is sufficient or
   whether a cross-session scope marker is required. It is the pivot of the
   adversarial case above and it **blocks implementation**. Sent to decision 2 as a
   cross-decision constraint.
2. **Startup-ordering probe.** `await zct(...)` appears on the plugin-load path, so
   registration is awaited — but I did not prove that path completes before the
   first tool call in a `-p` session whose opening move is an `Edit`. One-command
   probe: a plugin `PreToolUse` hook that appends to a log, then
   `claude -p 'write /tmp/probe'`, and check whether the log line precedes the
   write. If it does not, Option B becomes the fallback.
3. **Durable form of the R15 switch: CLAUDE.md convention header or a niwa
   `[claude]` boolean?** I recommend the header (contributor-readable, inside PRD
   scope) and flag its cost: an owner setting policy across twenty repos writes it
   twenty times.
4. **Session-hook non-persistence across `--resume` is inference, not extraction.**
   It does not affect the chosen placement, but it is one of the two reasons Option
   A is not kept as a supplement, so it should be labeled as inference wherever the
   DESIGN repeats it.
5. **Double-registration guard.** niwa's `prBodyHookInstalled` dedup greps installed
   hook *scripts* under `.claude/hooks/` and does not inspect a plugin's
   `hooks.json`. If niwa later injects the same subcommand, both fire. The DESIGN
   should record that shirabe's `hooks/hooks.json` is the single registration point
   for this hook and that niwa must not inject it.

---

## Summary

The refusal registers in shirabe's own plugin `hooks/hooks.json` as an
always-registered `PreToolUse` command hook on `Edit|Write|MultiEdit|NotebookEdit`,
with arming decided per tool call rather than at registration time; it is disabled
by a dedicated env-plus-convention-header seam modeled on `PR_BODY_HOOK_DISABLE`,
which is a different and narrower lever than `disableAllHooks`. Skill frontmatter
is disqualified rather than merely disfavored: registration is a side effect of
invocation, and AC11 requires a refusal in a session that never invoked the skill.
The subagent question the coordination file flagged as unverified is now confirmed
in the binary, with the consequence inverted — `/work-on` children must be exempted
explicitly, not structurally. The strongest failure case against the choice is a
false refusal deadlocking a separate-session delegated child under
`bypassPermissions`, which R8's fail-open-on-arming absorbs and which a
degrade-to-warn counter bounds.
