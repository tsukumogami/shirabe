# Decision 3: Registration surface, lifetime, and the operator switch

**Question.** Where does the enforcement register, what is its lifetime, and how
does an operator disable the refusal while leaving the read-only determination
available?

**Requirements in scope.** R12 (agent-launched coverage), R15 (operator switch
with the determination surviving), R16 (100ms p95), R17 (absent/failed/stale
degrades to permit).

**Classification.** Critical (Tier 4).

Revised after two rounds of live probing. Binary claims were re-verified
independently against
`/home/dgazineu/.local/share/claude/versions/2.1.233` for this decision rather
than carried over from `wip/adherence_decision_bakeoff_6.md`; the mechanism
claims that decide the placement were then confirmed empirically rather than left
as extraction plus inference. Where my reading differs from another artifact, I
say so.

---

## What the binary says

Six facts from extraction. Items F2 and F3 were subsequently confirmed live and
are now redundant with the probe evidence; F4 and F5 remain extraction-only.

**F1 — Skill-frontmatter hooks register as a side effect of invocation, and
persist for the session.**

```js
function cAf(e,t,r,n,o){ ... for(let l of a) for(let c of l.hooks){
  let u=c.once?()=>{ w(`Removing one-shot hook for event ${s} in skill '${n}'`),
                     gka(e,t,s,c) }:void 0;
  Y1n(e,t,s,l.matcher||"",c,u,o), i++ }
  if(i>0) w(`Registered ${i} hooks from skill '${n}'`) }
```

Reached from the skill-expansion path, guarded on the skill declaring `hooks`.
The one-shot removal branch proves the default is persistent.

**F2 — Skill-registered hooks do NOT fire inside spawned subagents.** The
session-key resolver:

```js
function Aat(e,t,r){ let n=e?.agentId??r, o=e?.agentContext;
  return o!==void 0 && WCr(o) && NU_.has(t) ? [n, o.parentAgentId??r] : [n] }
function WCr(e){ return e.agentType==="subagent" && e.isBuiltIn===!0
                        && e.subagentName===kM }
```

Inside any agent context the key is `agentId`, so the parent session's registry
is never consulted; the parent-key fallback covers exactly one built-in subagent
type. In `cMS`, only `ZLt(e,d,r)` — the session-hook registry — is keyed by the
`Aat` array.

**F3 — Settings-file and plugin hooks are session-key-independent, so they fire
inside subagents.** Same function, opposite half: `cMS` pushes `Khe()?.[r]`
(settings) and `Sle()?.[r]` (plugin) into the result without reference to the key
array.

**F4 — `disableAllHooks` kills all three candidate placements identically.**

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

Only managed-policy hooks survive. I first read the plugin path as *surviving*
`disableAllHooks`; it does not — the `IIe()===null` filter closes it.

**F5 — `strictPluginOnlyCustomization` favors plugin sources.** `IL(e)` reads the
managed-policy array or boolean; `aFe(source)` exempts
`{plugin, policySettings, built-in, builtin, bundled}`. Under
`strictPluginOnlyCustomization: ["hooks"]` a shirabe plugin hook survives and a
niwa-written project `.claude/settings.json` hook does not.

**F6 — Workspace trust gates every hook, not any one placement.** `JF` opens with
`if(Cmt()) return w("Skipping ${a} hook execution - workspace trust not
accepted"),[]`. Trust is a session-level precondition on all hook execution and is
therefore not a discriminator between placements. (I nearly argued the opposite
from `$bi`/`Obi`, which is the narrower *frontmatter*-specific trust check on
agent and skill definition folders.)

---

## Probe evidence

Two probes by the design lead
(`wip/design_skill-adherence-enforcement_probe_subagent_hooks.md`) and two of my
own. Mine were run because the lead's plugin result was the single piece of
evidence adverse to this decision's chosen placement, and because my own open
question about startup ordering was load-bearing.

**Lead's probe.** A settings-registered `PreToolUse` hook fired for both a
general-purpose subagent's write and the parent's write, one `claude -p` run,
`permission_mode: bypassPermissions`. `agent_id` and `agent_type` present on the
subagent's invocation, **both absent entirely** on the parent's. Same `session_id`
for both.

**Lead's adverse plugin result, and its retraction.** The identical hook declared
as `hooks/hooks.json` in a plugin loaded with `--plugin-dir` did not fire at all.
The probe file itself already carries the correction (its "Correction: this does
NOT generalize to installed plugins" section): the result is a fact about the
`--plugin-dir` dev-loading path, not about plugin hooks, and superpowers'
installed `SessionStart` hook demonstrably fires. Note for the record that the
file's later "Bearing on the decisions" section still carries the pre-correction
reading ("cannot yet rely on a plugin-registered one"); it was not updated when
the correction was added, and it is the sentence the briefing to this decision was
based on.

**My probes.** A throwaway plugin scaffolded with `claude plugin init` — the
supported skills-dir load path, not `--plugin-dir` — declaring a `PreToolUse`
hook on `Write`. Created, probed, and removed; nothing persists in the user's
config.

- **P1 — a plugin-registered `PreToolUse` hook fires.** Both writes of a two-write
  `claude -p` session logged. This is `PreToolUse` specifically, which the
  superpowers `SessionStart` evidence could not establish.
- **P2 — it fires on the session's very first tool call.** The prompt forced a
  `Write` as the opening move and the hook logged it. **This closes the
  startup-ordering question that was this decision's open question 2** — plugin
  hook registration completes before the first tool call in a `-p` session.
- **P3 — it fires inside a subagent, and denies under `bypassPermissions`.** A
  subagent's write and the parent's write both logged, same `session_id`,
  `agent_id`/`agent_type` present on the child and `null` on the parent —
  independently reproducing the lead's field-presence finding through the plugin
  route. The hook returned `permissionDecision: "deny"` and **neither file was
  created**, under `--dangerously-skip-permissions` with no human present.
- **P4 — the deny reason reaches the model as tool-error text, in both roles.**
  The subagent reported the reason string verbatim to its parent and the parent
  received it verbatim for its own denied write. This is the mechanism R5 and
  AC13 depend on, observed rather than assumed. `${CLAUDE_PLUGIN_ROOT}` also
  interpolates correctly inside a plugin hook `command` — the hook script only ran
  because it resolved, closing an item the earlier bakeoff listed as unverified.

**Measured for R16.** The shipped adapter `shirabe pr-body-hook`, cold process, 40
samples: min 4ms, **p95 6ms**, max 6ms, against a 100ms budget.

Net: the plugin route is no longer the inferred option and the settings route the
evidenced one. Both are now evidenced, through the properties this decision turns
on.

---

## The structural conflict, worked out rather than papered over

**Placement 1 cannot satisfy R4, and therefore cannot host the refusal.** The
lead asked me to reconsider this against the new evidence. The conclusion is
unchanged and the new evidence strengthens it.

1. By F1, registration is a side effect of skill expansion. No invocation, no
   registration.
2. R4 requires R3 to arm "on a signal ... that SHALL NOT be the invocation of the
   plan-execution skill", and AC11 makes the never-invoked, never-named-a-workflow
   session a **required refusal** — the PRD calls it "the arming case".
3. A hook that does not exist cannot refuse. Placement 1 fails AC11 by
   construction, for the exact journey the requirement was written to cover.

Decision 2 has since converged on an arming signal that is *purely external* —
the agent's own inbound brief plus on-disk PLAN state, with nothing the skill
writes feeding it. That removes the last reason anyone had to want the
enforcement co-located with the skill: the predicate no longer needs anything
invocation produces.

The prior bakeoff (`wip/adherence_decision_bakeoff_6.md`, "Recommendation")
argued placement 1 is nonetheless the only viable home because the write-target
predicate "is inherently skill-scoped — the closed set is `/execute`'s own
declaration, meaningless in a session that never invoked it." **That does not
survive R3's wording.** R3 refuses writes outside "the closed write-target set
*the plan-execution skill declares for itself*" — a static property of the shipped
skill, sitting on disk at `skills/execute/SKILL.md:661-667`, readable with no
invocation. The only session-dependent part is the `<topic>` slug that
parameterizes `wip/execute_<topic>_*`, and the slug comes from the PLAN under
execution. The bakeoff reached its conclusion before the PRD split arming from
invocation, and the split invalidates its premise.

---

## Options

### Option A — Skill frontmatter (`skills/execute/SKILL.md` `hooks:`)

Registers at invocation into a session-keyed in-memory registry, persists for the
session, `once: true` opts out (F1). Children exempt structurally (F2). Ships to
every adopter on `git pull`, and cannot drift from the contract it enforces
because both are in one file.

Fails R4/AC11 outright. Two further costs, relevant even as a supplement:

- **Lifetime is wrong for the workload.** `sessionHooks` is a `Map` in app state
  (`a.sessionHooks.set(t,{hooks:p})`) with no serialization anywhere in the
  binary. `/goal`, which registers a `Stop` hook through the same registry, ships
  a dedicated `restoreGoalFromTranscript` to re-register after a restart — code
  that would be unnecessary if the registry persisted. [Inference, strongly
  supported.] `/execute` runs are long, resumable, and cross-branch
  (`skills/execute/SKILL.md` **Resume**), so `claude --resume` returns ungated.
- **A skill invoked from inside a subagent registers on the wrong key.** `cAf`'s
  session id comes from the ambient current-session accessor with no agent-context
  branch. [Inference — I did not pin the accessor's behavior inside an agent
  turn.] The failure mode is a gate arming in the wrong place.

### Option B — niwa-distributed settings hooks

Precedented, shipped, and now empirically confirmed to reach subagents (lead's
probe). `shirabe pr-body-hook` is a niwa-injected PreToolUse allow/deny gate,
default-on for any instance whose config installs the shirabe plugin, gated on
`shirabePluginName` (`materialize.go:487`, `installsShirabePlugin` at `:525`),
with a `[claude] pr_body_hook = false` off switch (`prBodyHookEnabled`, `:611`)
and marker-grep dedup (`:644`). The command shape encodes the fail-open
discipline verbatim:

```go
// materialize.go:604
return "command -v shirabe >/dev/null 2>&1 || exit 0; shirabe pr-body-hook 2>/dev/null || exit 0"
```

Costs: reaches only niwa-managed instances; is the first source
`strictPluginOnlyCustomization` strips (F5); and puts the gate on niwa's release
cadence while the contract it enforces lives in shirabe's. The richer form the
niwa research sketched — a `[claude.skills]` policy table with graded levels — is
**explicitly out of scope per the PRD** ("A workspace-level policy surface for
declaring required skills") and re-opens the `[workspace]` overlay-tombstone
values question.

### Option C — shirabe plugin `hooks/hooks.json` *(chosen)*

Neither of the framing's first two. `.claude-plugin/plugin.json` declares
`skills` today and no hooks; shirabe ships no `hooks/` directory yet. The pattern
is standard and locally precedented — superpowers 6.2.0 declares
`"command": "\"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd\" session-start"`.

Registration is part of plugin load (`await zct(...)` on the plugin-load path),
completed before the first tool call (P2), for every session shape: interactive,
`-p`, `--bg`, dispatched, and resumed.

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

`type: "command"` is load-bearing. A `prompt`- or `agent`-type hook's deny **ends
the turn** with a chat warning unless `continueOnBlock: true` is set (behavior
changed at v2.1.210), whereas a command hook's deny is fed back as the tool error
and the turn continues — the behavior P4 observed and the one AC13 ("proceeds
correctly on its next attempt with no human input") requires.

### Lifetime

**Registration is unconditional and session-long; arming is decided per tool
call.** The hook is always registered, observes every `Edit`/`Write`, and answers
"not armed, allow" for the overwhelming majority of calls. It carries no state
between calls.

Separating these two lifetimes is what makes R4 and R8 compatible. If registration
were the arming act (Option A), arming would inherit invocation as its trigger,
which R4 forbids. With registration unconditional, decision 2's predicate is free
to be anything readable from the hook input plus disk — and R8's "cannot establish
→ do not arm → the write proceeds" becomes the default branch rather than an
exception.

It also sets the R16 design rule: **the not-armed answer must be reachable without
expensive I/O**, because that path runs on every file write in every session on
the machine. Measured headroom is 100ms − 6ms ≈ 94ms for predicate I/O — generous,
but it is what AC28 must regression-test, and decision 2's predicate reads a
transcript, which is the part that can grow.

### The operator switch (R15), and `disableAllHooks`

**They are different levers, and the DESIGN must say so in operator-facing
documentation.** `disableAllHooks` is not R15's switch:

1. **Over-broad.** By F4 it kills settings, plugin, main-thread agent, and skill
   session hooks alike, leaving only managed-policy hooks. An operator reaching for
   it to silence one refusal silently loses the four hooks niwa already ships
   (`work-summary` capture / absence / compact, and `pr-body-hook`).
2. **Not expressible per-mechanism.** There is no surgical disable at any settings
   level; hooks merge and nothing removes a specific one.
3. **Not operator-specific.** It is read from the effective settings after
   precedence, so any project `.claude/settings.json` reaches it.

It does satisfy R15's second clause — the read-only determination survives, being a
`shirabe` CLI subcommand a human or CI runs, not a hook — but incidentally.

**R15's switch is the `PR_BODY_HOOK_DISABLE` seam, reused in shape:** an env check
first in `run()`, short-circuiting to allow before any I/O
(`crates/shirabe/src/pr_body_hook.rs:47-65`), plus a durable repo-readable form.
For the durable form, a CLAUDE.md convention header — the mechanism shirabe
already uses for `PR Grouping Policy`, `Reviewability Ceiling`, and `Release Notes
Convention` — resolved `env > CLAUDE.md header > default(on)`, matching those
headers' documented resolution order. This keeps the setting where the contributor
it applies to can read it, which is the property niwa's `[workspace]` tombstone
reasoning protects, and stays inside the PRD's scope by not creating a workspace
policy surface.

**Can an agent reach it?** Yes, and the PRD concedes this (Known Limitations). Two
things worth recording:

- Self-disarming by editing `.claude/settings.json` or the CLAUDE.md header is
  itself a write, outside `/execute`'s declared set, so an armed orchestrator's
  attempt to disarm is itself refused. That raises the cost without eliminating
  it.
- The env route is *harder* for an in-session agent than `disableAllHooks`. The
  hook runs as a child of the Claude Code process and inherits its environment,
  not a `Bash` subshell's; `export` in a tool call reaches nothing. Durably setting
  it requires editing settings `env:` or a shell profile — both writes, both
  refusable.

---

## Rationale against the requirements

**R12 (agent-launched coverage).** Three launch shapes, all covered:

- *Separate session* (niwa dispatch, `claude --bg`, `claude -p`): plugins load per
  session, so the hook registers with the child's own `session_id`, before its
  first tool call (P2). This is AC11's journey and the one Option A cannot reach.
- *Subagent* (Task / `spawn_and_await`): confirmed firing through the plugin route
  in P3, carrying `agent_id` and `agent_type`.
- *Resumed session*: plugin load runs again at startup; unlike the in-memory
  session registry, nothing needs re-registering by hand.

**R15.** Satisfied by the env seam plus the convention header, with the
determination untouched. AC18 is directly testable: set the switch, run a
plan-scale session, assert no refusal, assert the determination still returns a
verdict.

**R16.** p95 6ms for the reference adapter shape against a 100ms budget. Command
hooks for an event run in parallel and the tool call waits on the slowest, not the
sum, so co-existing with niwa's `Bash`-matched hooks costs nothing — the matchers
do not overlap.

**R17.** Three degradations, all already expressed in the reference adapter: absent
binary (`command -v shirabe || exit 0`), failing binary (`|| exit 0`, plus `run()`
always returning `ExitCode::SUCCESS` and expressing a block as JSON rather than an
exit code — `pr_body_hook.rs:43-56`), and version staleness (the contract version
read from the plugin-shipped declaration; a binary that does not understand the
declared version allows — AC17). Passing `${CLAUDE_PLUGIN_ROOT}` rather than
compiling the write-target set into the binary is what makes the staleness check
meaningful, because the plugin and the tsuku-installed binary version
independently. P4 confirms the variable resolves.

**R18** (no mechanism asserting skills outrank user instructions). The hook refuses
a *write target*, names a sanctioned alternative, and — per decision 4 — names the
recorded-conflict route as an accepted resolution. It never asserts precedence.

---

## The adversarial case against the chosen option

The strongest concrete failure is not a bypass. It is a **false refusal that
deadlocks a headless run**, and it comes from the interaction between this
placement and the delegation primitive this workspace actually uses.

**The case.** `/execute` reaches the delegation step for issue 3 of 6 and hands
the issue to a child. If that child is a **separate Claude session** rather than a
Task subagent — which is what `niwa dispatch` is (the workspace root CLAUDE.md
documents it as the way to "hand the work off to run on its own"), and what the
coordinated path implies since each repo is worked in its own worktree — then the
child has **no `agent_id` and no `agent_type`**. It is a session, in a repo, with a
PLAN present, writing source files. Under a role test keyed on those fields it
reads as an orchestrator. It is refused on its first `Edit`, running under
`bypassPermissions` with no human, where R6 requires the refusal to hold. It cannot
delegate further and cannot write. The run stalls, or the agent resolves the bind
privately — a new silent failure mode, arguably worse than the one being fixed.

**This is where I disagree with the lead's probe conclusion, and agree with
decision 2.** The probe's measurement is sound; the inference "absence of
`agent_type` is the orchestrator signal" is not. Absence of `agent_type` means
"not a Task subagent of *this process*", which is not the same claim. Decision 2
reached the same objection independently and its role test — what the agent's own
inbound brief names as its unit of work — holds under Task-subagent,
separate-process, and inline dispatch alike. That is the right test, and it makes
this failure case a design question decision 2 has answered rather than an
unmitigated risk. My placement is what makes it load-bearing, so it is recorded
here and was sent to decision 2.

Residual mitigations, in order:

1. **R8 points the safe way.** "Where the system cannot establish ... orchestrator
   role, it SHALL NOT arm." An ambiguous separate-session child is permitted. The
   cost is that a genuinely non-conforming orchestrator that looks like a child
   escapes the refusal — but it is still caught by the read-only determination,
   which does not fail open (R9). The asymmetry the PRD deliberately built absorbs
   this.
2. **A denial counter that degrades to warn.** After N consecutive refusals in one
   session, emit the reason as `additionalContext` and allow. A gate that can brick
   a headless run is worse than a gate that gives up.

Three lesser attacks:

- **Plugin not enabled.** No plugin, no hook. Covered by R17 and the scope
  assumption below, but the DESIGN must state the population as "sessions with the
  shirabe plugin enabled" rather than claim universal coverage.
- **`allowManagedHooksOnly` with no managed `enabledPlugins`.** By F4 the plugin
  hooks are not loaded at all. Enterprise adopters get nothing, fail-open. The
  remedy is documentable: list shirabe in managed `enabledPlugins`.
- **Subprocess writes.** A `Bash` heredoc bypasses an `Edit|Write` matcher. Already
  a stated Known Limitation. Extending the matcher to `Bash` is the footgun niwa's
  own source warns about at `materialize.go:592-603`, and shell-text write
  detection is unreliable. Keep the matcher narrow.

---

## Rejected options and why

**Option A as the primary surface.** Disqualified by R4/AC11 — registration is a
side effect of invocation (F1), and AC11 requires refusal in a session that never
invoked the skill. Not a trade-off. Reconsidered at the lead's request against the
new evidence; unchanged, and strengthened by decision 2's purely external arming
signal.

**Option D, A and C together.** Rejected. No coverage gain: any session that can
register a skill hook has already loaded the plugin, so C covers it. It costs a
second copy of the predicate, a second process spawn per write, and a second
lifetime that behaves differently across `--resume`.

**Option B with the `[claude.skills]` policy table.** Out of scope per the PRD's own
Out of Scope list, and re-opens a values question niwa has answered in the opposite
direction (`[workspace]` is deliberately overlay-proof so a private layer cannot
change what a contributor's run does).

**Option B in its minimal form** (niwa injects a fixed hook, `pr_body_hook`-shaped,
`[claude] adherence_hook = false` off switch). Viable, well precedented, and
empirically confirmed to reach subagents. It was briefly the evidence-favored
option on the strength of the `--plugin-dir` result; that result has been retracted
by its author and positively refuted by P1-P4, so the evidence no longer separates
the two on mechanism. Rejected on the remaining grounds: it reaches only niwa
instances while the plugin reaches every adopter, it is the first source
`strictPluginOnlyCustomization` strips (F5), and it separates the gate's release
cadence from the contract's. **Keep it as the named fallback** if shirabe's
distribution ever stops being a plugin.

**`disableAllHooks` as R15's switch.** Rejected on all three grounds above.

**`UserPromptSubmit` or `Stop` as the refusal's surface.** `UserPromptSubmit`'s block
reason goes to the user and not the model — a silent dead end in an unattended run;
`Stop` fires after the writes land. Both remain useful as non-blocking secondary
surfaces, which is decision 4's territory.

---

## Assumptions

1. A session without the shirabe plugin is out of scope. R17 makes that a permitted
   degradation rather than a coverage gap, and the DESIGN should state the
   population explicitly rather than imply universality.
2. The `shirabe` binary is on PATH (tsuku-installed) and is not shipped inside the
   plugin, so the hook shells out behind the `command -v` guard and the plugin and
   binary version independently. This is why the contract-version staleness check
   (R17/AC17) is a real requirement and not a formality.
3. `/execute`'s closed write-target set becomes machine-readable inside the plugin
   and versioned. Today it exists only as prose at `skills/execute/SKILL.md:661-667`,
   parameterized by `<topic>`. The prose must be generated from, or validated
   against, the machine-readable form — otherwise the refusal enforces a different
   set than the skill documents, which is the drift this placement was chosen to
   avoid.
4. Decision 2 supplies the arming predicate, including the orchestrator-role test
   that survives a session boundary, with a cheap not-armed early-out.
5. A `PreToolUse` deny is not defeated by `bypassPermissions`. Documented, stated in
   the binary, and observed in P3.

---

## Open questions the DESIGN must carry

1. **Durable form of the R15 switch: CLAUDE.md convention header or a niwa
   `[claude]` boolean?** I recommend the header (contributor-readable, inside PRD
   scope) and flag its cost: an owner setting policy across twenty repos writes it
   twenty times.
2. **Session-hook non-persistence across `--resume` is inference, not extraction.**
   It does not affect the chosen placement, but it is one of the two reasons Option
   A is not kept as a supplement, so it should be labeled as inference wherever the
   DESIGN repeats it.
3. **Double-registration guard.** niwa's `prBodyHookInstalled` dedup greps installed
   hook *scripts* under `.claude/hooks/` and does not inspect a plugin's
   `hooks.json`. If niwa later injects the same subcommand, both fire — correct
   under deny-wins merge, but two process spawns per write. The DESIGN should record
   that shirabe's `hooks/hooks.json` is the single registration point for this hook
   and that niwa must not inject it.
4. **Predicate cost under a large transcript.** Decision 2's role test reads the
   session's own transcript. R16's headroom is 94ms and a long `/execute` run's
   transcript is not small. The not-armed early-out must precede the transcript
   read, and AC28 should measure late in a long run rather than at session start.

*Closed by probing during this decision:* whether plugin-registered `PreToolUse`
hooks fire (P1), whether registration completes before the first tool call (P2),
whether they reach subagents and deny under `bypassPermissions` (P3), whether the
deny reason reaches the model (P4), and whether `${CLAUDE_PLUGIN_ROOT}` resolves in
a plugin hook command (P4).

---

## Summary

The refusal registers in shirabe's own plugin `hooks/hooks.json` as an
always-registered `PreToolUse` command hook on `Edit|Write|MultiEdit|NotebookEdit`,
with arming decided per tool call rather than at registration time; it is disabled
by a dedicated env-plus-convention-header seam modeled on `PR_BODY_HOOK_DISABLE`,
a different and narrower lever than `disableAllHooks`, which kills all three
candidate placements equally and is therefore not a discriminator. Skill frontmatter
is disqualified rather than disfavored: registration is a side effect of invocation
and AC11 requires a refusal in a session that never invoked the skill — a conclusion
decision 2's purely external arming signal only strengthens. The evidence that
briefly favored the niwa settings route was a `--plugin-dir` artifact, retracted by
its author and refuted by four live probes that confirm plugin-registered
`PreToolUse` hooks fire, fire on the first tool call, reach subagents, deny under
`bypassPermissions`, and return their reason to the model. The strongest failure
case is a false refusal deadlocking a separate-session delegated child, which is
why the orchestrator-role test must key on the agent's own inbound brief rather
than on the absence of `agent_type`.
