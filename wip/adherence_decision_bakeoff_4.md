# Validation: Alternative 4 — Structural constraint

Position argued: ship a plan-scale execution context whose tool set omits Edit and
Write, so the orchestrator's only route to code is spawning `/work-on` children.

Two things changed during validation and both are reported here rather than
buried. First, the objection I was briefed to defend against — "you bind to an
agent definition and cannot reach a human typing `/execute`" — is answered by a
different binding surface that shirabe already ships. Second, the honest coverage
claim that replaces it is *worse* than the decider's comparison table asserts on
incident 1, and that table needs correcting. Net, the alternative is stronger than
briefed on one axis and weaker on another, and the vehicle should change.

---

## Strengths

### 1. It is the only mechanism that acts at the moment of the failure

Every other alternative operates on the agent's beliefs (1, 5), on the artifact
after the fact (2), or on a predicate about session state that something upstream
must compute correctly (3). This one operates on the action itself. At the instant
the orchestrator reaches for Edit on a source file, the answer is no. That instant
is the loss in both incidents, and it is the only point where the two incidents
converge — incident 1 arrived there without ever invoking the skill, incident 2
arrived there having invoked it and run its scripts.

The disqualifying test the context doc sets out ("the agent already knew") kills
alternatives 1 and 5 outright and constrains 2 and 3. It does not touch this one,
because knowledge is not in the causal path.

### 2. The carve-out objection dissolves on inspection — this is the strongest new fact

I was asked how the orchestrator authors its `wip/` state projection and its PR
body without Edit or Write. The answer is that `/execute`'s write surface is
already almost entirely bash, and this was not known when the alternatives were
drafted.

Already bash, no change required:

- **PR body** — `skills/execute/koto-templates/execute.md:443-458` is
  `mktemp` + `cat > "$BODY_FILE" <<'BODY'` + `gh pr edit --body-file`. The single
  carve-out the brief was most worried about is a non-issue; the skill already
  forbids inline interpolation and mandates the file route.
- **Branch and draft PR creation** — `execute.md:337-343`, `git`/`gh`.
- **koto task payloads** — `execute.md:384-398, 404-419`: `mktemp`, `echo ... > "$TMP"`,
  `koto next --with-data @"$TMP"`, `rm -f`.
- **koto context** — `execute.md:325-331`, `references/cross-issue-context.md:5-13`.
- **The entire finalization cascade** — `scripts/run-cascade.sh`: `git rm` at :860 and
  :562, awk-to-tmp-and-mv at :436/:457, `shirabe finalize-chain` at :716, `git add`,
  `git commit`, `git push` at :872-873.
- **PR ready / close** — `execute.md:505-507`, `SKILL.md:336`.

Exactly four writes would use Edit or Write today:

1. `wip/execute_<topic>_state.md` — creation and per-tick mutation
   (`SKILL.md:100, 113, 344, 385, 441`). The only structurally load-bearing one.
2. `wip/work-on_<slug>_impact.json` — `execute.md:351`; the koto gate on it is only
   `test -f` (`execute.md:78`).
3. The coordination body file passed to `shirabe validate --coordination-body <file>`
   (`SKILL.md:296-302`).
4. The `re-evaluation` Decision Record under `docs/decisions/` (`SKILL.md:487-489`).

All four are plain-text files the orchestrator authors wholesale, and all four are
expressible as `cat > "$F" <<'EOF'` — the identical pattern `pr_finalization` already
uses eleven lines away in the same skill. No carve-out mechanism is needed. What is
needed is a mechanical conversion of four call sites to an idiom the skill already
contains.

The honest residual cost: state-file mutations that are surgical single-field
edits today (`last_updated`, `phase_pointer`, the `parent_orchestration:` sentinel
set and clear) become full rewrites. For a ~20-line YAML document that is
acceptable, but it makes the projection's schema discipline load-bearing in a new
way, and a partial rewrite on an interrupted turn is now a corrupt state file
rather than a stale field.

### 3. Shirabe has already done the enumeration work this depends on

`/execute` declares a **closed write-target set** (`SKILL.md:643-649`), enforced by
the R9 hard-finalization check, with the pattern-level rule at
`references/parent-skill-security.md:41-65`: "Future implementors adding a write
target outside the declared set hit a documented enforcement boundary rather than
silently expanding the write surface."

That is this alternative's thesis, written down and shipped, one enforcement layer
short. R9 checks the set at finalization; a tool restriction checks it at the write.

Supporting evidence that the finalization-time check is not sufficient: the declared
set covers `wip/execute_<topic>_*`, but `execute.md:351` writes
`wip/work-on_<slug>_impact.json`, which is outside it. The write surface has already
drifted past its own declaration and R9 did not stop it. A restriction that binds at
the tool call would have.

### 4. It formalizes an invariant the architecture already asserts

`DESIGN-execute-skill.md` describes `/execute` as holding "only the metadata surface"
and offloading "every issue's real work to a fresh `/work-on` child."
`SKILL.md:690` states "Single-agent parent — no team is spawned at the `/execute`
layer." The design already says the orchestrator does not implement. This makes the
statement true rather than aspirational, and it is the cheapest possible reading of
the change: not a new policy, an existing one given effect.

### 5. It needs no predicate, no policy surface, no niwa release, no org config

Alternative 3's confessed implementation gap — something upstream must supply which
plan is in play — does not exist here at any strength. The condition is "am I the
orchestrator," known by construction at bind time. The late correction says Alt 3's
gap is smaller than drafted because a session-exact koto workflow record dissolves
it; grant that fully and this alternative still requires strictly less machinery.
It touches shirabe only.

It also sidesteps the `[workspace]` tombstone collision entirely. There is no layer
imposing behavior on a contributor who cannot read it; the restriction lives in the
skill the contributor invoked, and it is visible in the skill's own frontmatter.

### 6. The "no positive delegate lever" finding does not bite

Phase-4 evidence: permission rules are `Agent(...)`-addressable only negatively;
there is no "must delegate" lever. Conceded, and it costs nothing. This mechanism
never needed a positive assertion. "Must delegate" is produced as the *residue* of
removing every other route — that is what a structural constraint is. What is
needed alongside it is not a rule saying "delegate" but a reason string naming
delegation as the sanctioned move, which the hook vehicle below supplies.

---

## Weaknesses

### 1. The vehicle in the brief is the wrong vehicle — and correcting it changes the coverage claim in both directions

I was briefed to defend an agent definition. That binds to `--agent` and misses an
interactive `/execute`. Two better surfaces exist, and shirabe already uses one.

**Surface A — skill frontmatter.** `skills/inflight/SKILL.md:14` carries
`allowed-tools: Bash(shirabe:*)`. Shirabe already ships a tool-restricted skill
through SKILL.md frontmatter and needs no new distribution surface for a second one.
Per the composition table in the hook-surfaces research (line 150), skill frontmatter
is a first-class scope whose declarations persist "the rest of the session once the
skill is invoked."

**Caveat, and it is the one load-bearing unverified fact in this report:** I could
not confirm whether `allowed-tools` in SKILL.md frontmatter *removes* tools from the
model's context or merely pre-authorizes them without prompting. The subagent
tasked with verifying this against the CLI docs hit a session limit before
answering. If it is only a permission grant, surface A is inert for this purpose
and everything rests on surface B. **Verify before designing on it.** My
recommendation is deliberately structured so it does not depend on this fact.

**Surface B — a skill-frontmatter PreToolUse hook, verified.** Same composition
table; hook-surfaces §5 quotes the docs: "Skill hooks: Claude Code registers them
when you or Claude invoke the skill and keeps running them for the rest of the
session." A `PreToolUse` deny on Edit/Write outside the R9 set achieves capability
removal, and hook-surfaces §1 and §2 establish that a deny beats `bypassPermissions`
by documented design, fires inside subagents carrying `agent_id`, and feeds
`permissionDecisionReason` back to the model as tool-error text it can act on.

Either surface binds at skill invocation, which means it binds identically for a
human typing `/execute` and for a dispatched worker. **The coverage gap I was asked
to concede is not where the brief placed it.** It is not dispatch-versus-interactive.

The real gap is by incident:

| | Dispatch path | Interactive path |
|---|---|---|
| Incident 2 (skill fired, loop skipped) | Covered | **Covered** |
| Incident 1 (skill never fired) | Covered, but only via the agent-definition vehicle on `niwa dispatch --agent` | **Not covered at all** |

Nothing bound to `/execute` can fire when `/execute` was never invoked. The
hook-surfaces research states it flatly (lines 188-190): "a skill-frontmatter hook
only exists after the skill is invoked. It cannot enforce that the skill gets
invoked."

**This corrects the decider's comparison table**, which scores this alternative
"Catches #1: Yes / Covers human `/execute`: No". Both cells are wrong. It should
read "Catches #1: dispatch only" and "Covers human `/execute`: Yes, for incident 2."
The uncovered cell is a single one — interactive session, skill never fires — and it
is the cell I hand to Alternative 3.

The full form is therefore two vehicles: an agent definition for
`niwa dispatch --agent` (catches both incidents on that path, because a worker told
"execute this plan" that never invokes the skill still cannot hand-implement), plus
skill-level binding for the interactive path (catches incident 2 only).

### 2. The Bash bypass is real and I cannot close it

Phase-4 evidence is decisive and I concede the core claim as stated is too strong:
"Read/Edit deny rules don't apply to arbitrary subprocesses that read or write files
indirectly, like a Python or Node script that opens files itself." OS-level
enforcement requires sandbox settings.

I worked through whether Bash can be constrained enough to matter. It cannot, and
the reason is specific rather than general. `/execute`'s legitimate bash surface
includes `run-cascade.sh` doing awk-into-tmp-and-`mv`, `git rm`, `git commit`,
`git push`; `mktemp` + `echo` + redirect for koto payloads; `gh pr edit --body-file`;
`koto context add`. A prefix allowlist tight enough to block file creation breaks
the cascade. One loose enough to run the cascade permits `cat > file.go <<'EOF'`
trivially. There is no cut between them. **Bash must stay unrestricted, and the
bypass is accepted rather than mitigated away.**

So the honest claim is not "converts should into cannot." It is **"converts should
into cannot-without-deliberately-routing-around-it."** That is a weaker claim and I
will not defend the stronger one.

What makes the weaker claim still worth a lot: the threat model here is drift, not
evasion. Neither incident agent was circumventing a control — both took the path of
least resistance while believing they were being productive. Against drift, a
control that makes the wrong path require an unusual, self-evidently circumventing
action does most of the work. Against an agent that has decided to route around it,
it does nothing.

Two things follow. **This must never be sold as a security control**; if anyone ever
wants the security-grade version, the answer is OS-level sandbox settings and that
is a different project. And the residual is partly observable — heredoc redirection
into a non-carve-out path has a distinctive signature the same PreToolUse hook can
inspect on Bash calls. That raises the bar again and is defeated by `python -c`. It
is worth doing and worth not overclaiming.

### 3. Incident 1's real cause is untouched

The competence filter (`skill-creator/SKILL.md:396-400`) means executing a plan reads
as directly handleable, which is why both `/execute` and the near-ideally-described
`/work-on` failed to fire. Nothing here changes that. On the dispatch path the agent
definition catches the *consequence* without addressing the *cause* — the worker
still never invokes the skill, it just cannot implement, and what it does next is
undefined. That undefined next step is the deadlock branch below.

### 4. A durable maintenance cost

Once `/execute` cannot write, every future write target must be added as a bash
carrier. A contributor adding a Write-based step hits a wall, and unless the deny
reason names the R9 closed set explicitly they will not understand why. This
compounds quietly over time and is a real cost that no other alternative here
carries.

---

## Risks

### R1. Deadlock — the serious one, and I concede substantial ground

The scenario, sharpened by Validator 5: a session instruction forbids spawning
subagents. The orchestrator cannot implement and cannot delegate. Under
`bypassPermissions` there is no human to ask. No legal move.

**Under a raw tool-list omission this objection is correct and worse than stated.**
The agent receives a tool-unavailable failure with no explanation. Its most likely
recovery is precisely the bypass conceded above: it reaches for Bash and heredocs
the file. So the deadlock does not manifest as a stall — it manifests as the
bypass, which is *worse than a stall* because the violation is now laundered
through a channel with no reason attached and no record. Validator 5's argument
lands cleanly against the vehicle as briefed, and this is the strongest single
reason to abandon that vehicle.

**Under the hook vehicle it converts into a defined terminal state.** The deny
carries `permissionDecisionReason`, verified as text the model reads and acts on.
The reason can say: you are the `/execute` orchestrator; implementation belongs in a
`/work-on` child; if a session instruction forbids spawning, do not implement
inline — record the conflict via `koto overrides`, stop, and report it in your final
message.

That is a recorded, visible refusal instead of a silent hand-implementation. It is
also exactly the thing the user said they lost. A job that stops with a legible
reason beats six issues implemented invisibly, and the comparison should be made
against that baseline rather than against a hypothetical successful run.

This is where **Alternative 5 is not a competitor but a required complement, and the
dependency runs both ways.** Alternative 5's confessed weakness is that it has no
teeth: incident 2's agent conceded it should have flagged the conflict and did not.
This mechanism supplies the teeth — the conflict must be surfaced because there is
no other move. This mechanism's confessed weakness is that it has no escape hatch.
Alternative 5 supplies it. Neither is complete alone, and shipping this one without
the recorded-override path is the failure mode that gets it ripped out the first
time it is wrong.

**Residual I cannot design away:** in a fully unattended dispatch against a
deadline, a recorded stop is still a failed job. Someone has to read the record.
The reporting obligation needs a carrier that actually surfaces — the
`=== WORK IN FLIGHT ===` block niwa's `/dispatch` template already mandates is the
obvious one. And the restriction must be defeasible by explicit human instruction
(an override recorded before the run that the hook reads), or the first legitimate
inline case turns into a support incident.

Scope concession: **this alternative is unsafe in any context where a stall is
costlier than an unrecorded execution.** That inverts the org's usual trade and it
is a real category — time-critical unattended work. In that category, do not ship
this at deny strength.

### R2. Steerability versus structural purity is a genuine trade

Phase-4 evidence: a bare tool-name deny removes the tool from context entirely and
the model never sees it; a scoped rule leaves it visible and blocks matching calls.
Bare deny is structurally purer and carries no reason. Hook deny is slightly weaker
— the model sees the tool and may retry — but carries the reason that makes R1
survivable.

Given the threat model is drift rather than evasion, **steerability is worth more
than purity** and the hook wins. Recording the alternative honestly: someone
optimizing against a determined agent would choose the opposite.

### R3. Implementation traps

- File-scoped permission rules are consulted for `Edit(path)` and `Read(path)` only.
  A `Write(path)` rule is accepted, never consulted, and warned about at startup. If
  any part of this is built on permission rules rather than a hook, it must be
  written as `Edit(<glob>)`.
- A `type: "prompt"` or `type: "agent"` PreToolUse hook denying without
  `continueOnBlock: true` ends the turn instead of correcting it (behavior changed at
  v2.1.210). Command hooks keep feed-back-and-continue. Build it as a command hook.
- Non-interactive background subagents whose tool call gets no hook decision are
  **denied by default**. A hook that returns nothing is not neutral in a dispatched
  session — the pass path must return an explicit allow.
- `managedHooksOnly` appears in binary hook-dispatch paths and is undocumented. If
  some path runs only managed hooks, a plugin-declared hook is invisible there.
  Resolve before committing to plugin-hook delivery.

### R4. False positives on legitimate orchestrator writes

The four conversions in Strength 2 must all land, and the R9 declared set must be
corrected to cover `wip/work-on_<slug>_impact.json`, before the deny goes on.
Shipping the restriction ahead of the conversions produces an orchestrator that
cannot maintain its own state file — which fails at Phase 0, on the first run,
loudly. Loud is survivable; it is still an ordering constraint, not an optional one.

### R5. Irreversibility, downgraded

Under the agent-definition vehicle this is the heaviest commitment on the table.
Under the skill-frontmatter vehicle it is a frontmatter line plus a hook script,
removable in one commit, scoped to plugin enablement — which hook-surfaces
identifies as the adopter's expected escape hatch, since hooks merge with no
surgical disable and the only alternative off switch is the blunt `disableAllHooks`.
The vehicle swap turns the heaviest alternative into roughly the second-lightest.
What does not revert is the write-surface conversion, and that is a strict
improvement worth keeping either way.

---

## Conditions under which this is the right choice

1. **The org's tolerance for a stalled job exceeds its tolerance for an unrecorded
   plan execution.** Both incidents cost invisibility; this mechanism occasionally
   costs a stall. That trade is correct for high-blast-radius work and wrong for
   small work — which is `P5: Strictness tracks blast radius`
   (`references/workflow-principles.md:87`) applied directly, and it supplies the
   natural scoping rule: bind at `/execute` (plan scale), never at `/work-on`
   (issue scale). `/work-on` children must keep Edit and Write; they are the ones
   doing the work.

2. **Alternative 5's recorded-override path ships in the same release.** Without an
   escape hatch that produces a visible record, R1 is unmitigated. This is a
   blocking condition, not a nice-to-have.

3. **The four write-site conversions land first**, and the R9 declared set is
   corrected. Ordering constraint (R4).

4. **`allowed-tools` semantics are verified**, or the hook vehicle is used. Do not
   design on the unverified reading.

5. **Nobody sells it as a security control.** Its threat model is a well-intentioned
   agent taking the easy path. Documented as such, in the skill, next to the
   restriction.

6. **Something else covers incident 1 on the interactive path.** This alternative
   does not, and cannot.

---

## Recommendation

**Adopt-with-conditions, with a vehicle substitution — and only as a component, not
as the answer.**

Adopt the principle: at plan scale, remove the capability to implement inline rather
than discouraging its use. It is the only mechanism in the field that survives the
disqualifying test, its carve-out objection turned out to be nearly empty on
inspection, and it gives effect to an invariant shirabe has already written down and
already failed to hold (the R9 drift at `execute.md:351` is the proof).

Reject the vehicle as briefed. An agent-definition tool list misses the interactive
path, carries no reason string, and under a spawn-forbidding session degrades into
the silent Bash bypass rather than an honest stall — which is Validator 5's
objection landing at full force. Substitute a skill-scoped `PreToolUse` command hook
denying Edit and Write outside the R9 closed set, with `permissionDecisionReason`
naming the sanctioned move and the recorded-override route. Keep the agent
definition as a second vehicle on `niwa dispatch --agent`, where it is the only
thing that reaches incident 1.

On the sixth alternative the lead raised — skill-frontmatter hooks — it does not
dominate this position, it **is** this position, correctly implemented. The
root-cause claim was always about capability, never about the vehicle. A
skill-registered hook removes the capability, adds a steerable reason, fires inside
subagents, denies under `bypassPermissions`, and reverts in one commit. It beats a
raw tool-list omission on every axis raised in Phase 4 and loses on none. Treat the
"sixth alternative" as the implementation of the fourth.

Where this sits against Alternative 3: they are complements with almost no overlap
in machinery. Alternative 3 keys on a session-scoped predicate and fires before any
skill is invoked, which is the one cell this alternative cannot reach. This one
keys on identity, needs no predicate, no policy surface, no niwa release, and no
org-config placement decision — so it does not touch the `[workspace]` tombstone
question at all. If the decider ships Alternative 3 at `remind`, this mechanism is
what supplies the enforcement that `remind` deliberately withholds, scoped to the
one place where the blast radius justifies it. If Alternative 3 is later promoted
to `gate`, this becomes partly redundant at the margin and still carries the
write-surface hygiene.

Honest final accounting: I catch incident 2 completely, on both paths, structurally.
I catch incident 1 on the dispatch path only, and by consequence rather than cause.
I do not catch incident 1 in an interactive session at all. I convert should into
cannot-without-deliberate-circumvention, not into cannot. And I generate a deadlock
branch that is only survivable because Alternative 5 exists to absorb it.
