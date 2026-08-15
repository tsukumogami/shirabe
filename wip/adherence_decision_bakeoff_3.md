# Validation: Alternative 3 — Graded workspace policy

*Revised in Phase 4 against the hook-surfaces research. The revision moved me
further than the first pass did, and it moved me against my own alternative in
the place that matters most. Summary of the change is at the end of this
preamble; the body is rewritten, not patched.*

I was assigned to argue for the decider's frontrunner and told not to
rubber-stamp it. On the first pass I concluded that Alternative 3 survives only
in a narrower form — the predicate is worth having, the policy surface and the
`gate` rung are not. The new evidence sharpens that verdict and adds a harder
one. The hook research strengthens the *enforcement* argument decisively and, in
the same stroke, hands that enforcement to somebody else: **Alternative 6 (skill
frontmatter hooks) delivers Alternative 3's enforcement leg with none of
Alternative 3's machinery and, critically, with no trigger ambiguity at all.**

What changed from my first pass:

- The `remind` rung is now *confirmed* incapable of fixing incident 2, not merely
  a probability play. `additionalContext` is delivered as "a system reminder that
  Claude reads as plain text" — below the session instruction that beat the skill.
- The `gate` rung is stronger than I credited: `PreToolUse` deny fires before any
  permission-mode check and holds under `bypassPermissions`, which is this
  workspace's default mode. A hook block is outside the precedence order the
  model arbitrates.
- But `Stop`, not `PreToolUse`, is now the surface I would build on, for reasons
  the first pass had no evidence for.
- And Alternative 6 dissolves the objection I called Alternative 3's most serious
  weakness. I have to concede that, and I do, below.

## Strengths

**The enforcement argument is now settled, and it lands in Alternative 3's
favour over every injection-based alternative.** The hook research is
unambiguous: `PreToolUse` hooks fire before any permission-mode check, in every
mode including `dontAsk`, and a `permissionDecision: "deny"` blocks the tool even
under `bypassPermissions` or `--dangerously-skip-permissions`. The live workspace
runs `defaultMode: bypassPermissions`. So a hook block is the only enforcement
surface that still holds here at all. More important than the strength is the
*category*: a hook block is outside the precedence order the model arbitrates,
while injected `additionalContext` is inside it and below a session instruction.
That is the exact order that produced incident 2. Any design whose enforcement
leg is stronger words will reproduce the failure by construction — this is no
longer an inference, it is documented behavior.

**The join has no inference left in it.** The `PreToolUse` input carries
`session_id` (confirmed against `pr_body_hook.rs` and its test fixture), and
koto's workflow record is keyed by that same id. Predicate, input, and record now
line up end to end with nothing assumed.

**`Stop` and `SubagentStop` turn the detector into a corrective surface.** This
is the most useful new fact for my position and it was not available on the first
pass. The binary's own schema strings describe `additionalContext` on these
events as "non-error feedback delivered to the model; the conversation continues
so the model can act on it," and both events can also *block* — exit 2,
`decision: "block"`, or a prompt hook's `ok: false`, with `impossible: true` as
the designed anti-loop escape. So "you produced a koto payload and never
submitted it — do that before you finish" is deliverable at the moment the agent
tries to stop, as feedback it must act on, with a built-in valve for the case
where the gate is wrong. My first pass argued for the detector as an observation
leg. It is better than that: it is enforcement with a graceful failure mode.

**`Stop` is bypass-proof in a way `PreToolUse` is not.** A `PreToolUse` matcher
on `Edit|Write` does not see `python -c "open(...).write(...)"`, and the docs say
plainly that path rules and hooks do not reach subprocesses that write files
indirectly. A `Stop` check does not care how the files were written; it reads the
durable koto record at turn end. The porosity I flagged as a weakness of the
`gate` rung simply does not exist at `Stop`.

**Tool events fire uniformly inside subagents and background sessions**, with
`agent_id` and `agent_type` supplied. That closes the coverage question for the
dispatch path on the enforcement surfaces, though not on the injection ones.

**Distribution remains a solved problem** — `pr-body-hook` is the shipped
template, the plugin-adoption gate and off-switch idioms are established, and
every hard-won operational rule has a comment in `materialize.go` explaining the
failure it prevents.

## Weaknesses

**1. Alternative 6 dissolves the objection I called fatal, and it does so
structurally.** My first pass named this as Alternative 3's deepest problem, and
it stands: the predicate is a conjunction — *plan-scale work is in play* **and**
*no koto record exists for this session*. The koto lead confirmed the right
conjunct session-exactly. The left conjunct is undefined, and every false
positive lives there, because applied blind the check answers NO-KOTO for every
session on the machine that is not running koto.

Alternative 6 does not solve the left conjunct. It **removes** it. A hook armed
by `shirabe:execute`'s own frontmatter exists only in sessions where `/execute`
actually fired, so "is plan-scale work in play" is answered by construction
rather than by heuristic. The trigger is the invocation. There is no false
positive to have, no marker to stash, no transcript to grep, no repo that merely
contains plan docs to worry about.

That is not a small edge. It is the difference between a mechanism that needs a
design and a mechanism that needs a frontmatter block.

**2. Alternative 3's marginal value over 6 is concentrated in its weakest
component.** 6 covers incident 2 completely and incident 1 not at all, because
nothing arms if the skill never fires. So everything Alternative 3 uniquely buys
reduces to incident-1 coverage — and incident 1 is precisely the case where no
invocation signal exists, which is precisely the undefined left conjunct. Stated
plainly: **the only thing Alternative 3 does that Alternative 6 does not, it does
using the part of itself that is speculative and carries all the risk.** A
validator arguing for 3 has to sit with that rather than route around it.

**3. The org-owner configuration surface delivers a suggestion, not a mandate.**
`disableAllHooks: true` in a project settings file beats user settings and kills
every non-managed hook. Only managed policy settings are immune. So a
`[claude.skills]` policy distributed by niwa into instance and project settings
is defeatable by any repo that carries its own settings file — and the same is
true of the shirabe plugin's own hooks, so this is a wash between 3 and 6 rather
than a point against 6. But it is a direct deflation of Alternative 3's headline
claim. The comparison table's "Org-configurable: **Yes**" is the alternative's
unique selling point against the whole field, and what it actually delivers is a
default that a repo can switch off. The only layer that cannot be defeated is
managed policy settings, which are not distributed in this workspace at all, and
which remove the escape hatch entirely — the escape hatch my own conditions, and
the `env_example_policy` precedent the sketch is modeled on, both insist on. So
the org-owner leg is either defeatable or unescapable, with nothing in between,
and the drafted alternative quietly assumes a middle that does not exist.

**4. The `remind` rung is now confirmed insufficient, not merely probabilistic.**
My first pass called it a probability play. The evidence is harder than that:
`additionalContext` is injected as "a system reminder that Claude reads as plain
text," which sits below an actual session instruction — the very thing that
outranked the skill in incident 2. An agent that resolved "do not call the
AgentTool unless the user requested it" against `spawn_and_await` resolves it the
same way against a reminder, in the same order, for the same reason. Add the
mechanical limits: `UserPromptSubmit` does not fire for subagents, does not exist
for a dispatched worker's programmatically composed task, has no matcher, and
runs on the critical path of every turn under a 30-second timeout. The rung is
weak on the interactive path and close to absent on the dispatch path. I would
now drop it below `Stop` in priority rather than ship it as the headline.

This does not rescue Alternative 1 — injection is confirmed structurally
incapable there too. It means the graded ladder's middle rung is the wrong rung,
not that the ladder is wrong.

**5. The predicate is still satisfiable by ritual, and this is unchanged by the
new evidence.** koto's guarantees are bookkeeping: the substrate-spawn primitive
is a logging stub, review gates and CI monitoring are directive text koto never
verifies. A gate that forces `koto init` buys a record. An agent can `koto init`,
satisfy the predicate permanently, and implement six issues inline exactly as
incident 2 did. The one repair the new evidence offers is real and worth taking:
`Stop` can assert something stronger than record-existence — §H's formulation,
"a session in which `/execute` fired must have spawned at least one `work-on`
child before it may stop," is a conformance claim rather than a token check, and
`type: "prompt"` and `type: "agent"` hooks make judgment-shaped assertions
expressible without writing a classifier. But note whose alternative that
strengthens: it is Alternative 6's shape, armed at invocation, not Alternative
3's.

**6. Two silent-no-op paths remain.** Unknown TOML fields warn and continue, so
an older niwa ignores a declared mandate; and the injected command must swallow
non-zero, so an older `shirabe` lacking the subcommand fails open. A declared
policy can do nothing, twice over, unnoticed. Alternative 6 has one fewer of
these, since the hook ships in the same artifact as the code it calls.

**7. n = 2.** Both incidents are one user, one machine, one month. A configurable
org-wide policy surface is a large commitment on that base, and the detector is
what converts n=2 into a rate you could set a level from.

## Risks

**The fail-open posture must be an explicit allow, not silence.** In
non-interactive background subagents, a tool call with no hook decision is
*denied* — the default flips. So the `pr-body-hook` idiom of exiting 0 quietly on
every ambiguity does not transfer unexamined: an adherence gate must emit
`permissionDecision: "allow"` explicitly on every error path, and must never
emit `ask`, which is an effective deny in a background worker. This also means
niwa's existing `gate-online.sh` `ask` branch is probably already hardening into
a deny inside dispatched instances, which is worth someone checking independently
of this decision.

**A `type: "prompt"` `PreToolUse` gate kills the turn by default.** Since
v2.1.210 the deny reason no longer returns to the model as a tool error unless
`continueOnBlock: true` is set — so a corrective prompt-hook gate written today
without that flag ends the turn and the agent never learns why. Any prompt-shaped
gate must set it. Agent hooks behave as though it were always on.

**Cost.** An `agent`-type hook on `Stop` is the most expensive instrument in the
inventory (a full subagent, up to 50 tool turns, 60s default) and must be gated
behind a cheap precondition — read the workflows record first, spawn nothing if
it exists. A `find` over `~/.claude/projects` on every Edit needs memoization on
a per-session sentinel.

**Duplicate project dirs**, reproduced not theorized: one session id can appear
under two encoded project dirs when cwd changes mid-session, and the copies
disagree. Worktree entry is exactly such a change, and this workspace mandates
worktrees for background jobs. Scan all, take the freshest by mtime.

**A third tool's default can invert the predicate.** `workflows.native = true` is
koto configuration. Set it false, the record stops being written, and a gate
denies everything. This must be detected as "cannot evaluate," never as a
negative.

**Per-child observability may still fragment.** Tool hooks fire inside subagents
with `agent_id` supplied — that half is now confirmed. Whether koto's *write*
side lands a child's record under the parent's session id is still open, so a
per-`work-on`-child adherence check is not yet known to work even though the hook
that would run it does.

## Conditions under which this is the right choice

Alternative 3 is the right choice only for the part of the problem Alternative 6
structurally cannot reach: **a session that never invoked the skill at all.**
That is incident 1, it is half the evidence base, and nothing else in the field
addresses it — 6 needs an invocation to arm, 4 needs an agent definition, 5 needs
a recognized conflict, and 2's CI leg is impossible today because the PR carries
no koto marker and the `wip/` projection is `git rm`ed before ready.

For that part, and only that part, an always-on check is required, and it must be
distributed by niwa because it must exist in sessions where no shirabe skill ran.
That is the honest residue of Alternative 3.

But the instrument for it is a **`Stop` detector, not a `PreToolUse` gate**, and
the reason is a proportionality argument the new evidence makes cleanly. The left
conjunct is imprecise and will stay imprecise. At `PreToolUse`, imprecision costs
a blocked turn with no appeal under `bypassPermissions`. At `Stop`, imprecision
costs a sentence of steerable feedback the agent can act on or override, with
`impossible: true` as a designed valve. Same predicate, same evidence, two orders
of magnitude apart in blast radius. `P5: Strictness tracks blast radius` is cited
in the alternatives file as licensing promotion toward `gate`; read straight
against a loss whose actual character was missing bookkeeping while the work got
done correctly, it licenses `Stop` and forbids `PreToolUse`.

On the `[workspace]` tombstone I have not changed my view, and the new evidence
reinforces it. An overlay can already install an executable `PreToolUse` gate via
`[claude.hooks]`, whose scripts land in `.claude/hooks/` unimpeded, while
`isProtectedDestination` blocks only the `[files]` route. Treating the tombstone
as a veto on `[claude.skills]` would block the declarative, inspectable,
off-switchable path and leave the imperative, opaque one open — strictly worse
for the value the tombstone protects. The principled resolution is to make
**readability the requirement rather than placement**: every rung above `off`
emits its declaration into generated context the contributor reads in the
instance they work in, and every reminder or block names the config that declared
it. That satisfies what `config.go:312-320` protects, which is un-auditable
behavior change, not private authorship. This resolution is now less load-bearing
than it was, since Weakness 3 shows the configuration surface should probably not
ship in the first release at all — but if it ever ships, this is the shape.

## Recommendation

**Adopt with conditions — where the conditions concede the enforcement leg to
Alternative 6 and reduce Alternative 3 to a detector.** What survives is worth
shipping. What survives is also no longer a graded workspace policy, and the
decider should retitle it rather than ship a policy system under a name that no
longer describes it.

1. **Concede incident 2 to Alternative 6.** Arm the conformance gate from
   `shirabe:execute`'s own frontmatter, at `Stop`, asserting the strong form —
   a session in which `/execute` fired must have a koto record and at least one
   spawned `work-on` child before it may stop. It ships inside the plugin, needs
   no niwa release, no `[claude.skills]`, and no org-owner action, and it has no
   trigger ambiguity because invocation is the trigger. I cannot construct an
   argument that Alternative 3's machinery beats this for the case where the
   skill fired, and I tried.

2. **Keep Alternative 3 for incident 1 only, as a niwa-injected `Stop`
   detector.** This is the residue that genuinely has no other owner. Same
   predicate, always on, distributed on the existing default-on-with-off-switch
   pattern. Its imprecision is affordable at `Stop` and nowhere else.

3. **Do not build `[claude.skills]` in the first release.** Ship on the existing
   `work_summary_hooks` / `pr_body_hook` idiom, which needs no new TOML, no
   `ClaudeOverride` field, no `OverlayClaudeConfig` merge, and no answer to the
   placement question. Weakness 3 shows the surface would deliver a defeatable
   default anyway. Add configuration when a second policy exists to configure.

4. **Drop `PreToolUse` from the plan, and do not hold it as the promotion
   target.** It is porous to indirect writes, its false positives are terminal
   under `bypassPermissions`, and its unique strength — surviving
   `bypassPermissions` — is shared by `Stop` blocks, which also carry steerable
   feedback and an escape valve. Revisit only if the detector produces a rate
   that justifies it and the koto record becomes load-bearing for something that
   actually enforces.

5. **Demote `remind`.** It is confirmed to sit below the session instruction that
   won in incident 2, it does not reach dispatched workers, and it taxes every
   turn. Ship it, if at all, as the cheap rung it is, and do not let it carry the
   argument.

6. **Engineering conditions, non-negotiable:** explicit `permissionDecision:
   "allow"` on every error path rather than silence; never `ask`;
   `continueOnBlock: true` on any prompt-shaped gate; `impossible: true` honored
   as the deviation valve; memoize per session; redirect stderr; scan all project
   dirs and take the freshest by mtime; treat `workflows.native = false` as
   "cannot evaluate."

The short version: the predicate is the good idea, `Stop` is the right surface
for it, Alternative 6 owns the half of the problem where a trigger exists, and
Alternative 3 is worth keeping only for the half where one does not. What I still
cannot defend is the drafted alternative — a new configuration system and a
`PreToolUse` deny, justified by a predicate whose trigger half is undefined,
protecting a record the agent can produce in one line without changing anything
it does.
