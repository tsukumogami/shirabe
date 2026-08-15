# Lead: What prior art exists for making a workflow mandatory in an agent harness, and has shirabe already attempted this?

## Findings

### 1. The two terms in `/execute`'s description are false friends

The lead flagged that `/execute`'s description mentions "parent-skill conformance" and
"an explicit autonomy mandate". Both exist, both are real and load-bearing, and
**neither one is about invoking a skill**. This matters because it means the answer to
"has shirabe already attempted this?" is *no* — but shirabe has attempted something
methodologically adjacent that is worth mining.

**"Parent-skill conformance" is an authoring checklist, not runtime adherence.**
It resolves to `references/parent-skill-pattern.md:548`, `## Required SKILL.md
Structural Elements`:

> Every parent skill's `skills/<name>/SKILL.md` SHALL contain seven structural
> elements. The list is pattern-level; the content slotted into each element is
> parent-specific.

The seven are Input Modes, execution-mode flag parsing, a topic-slug constraint
statement, a Workflow Phases diagram, a Resume Logic ladder, a Phase Execution list,
and a Reference Files table. This is a spec that a *skill author* conforms to when
writing a SKILL.md. It has zero bearing on whether a running agent invokes the skill.
`skills/execute/SKILL.md:713` confirms the binding is "the seven required SKILL.md
structural elements, the three exit names, substitution surfaces."

**"The autonomy mandate" governs not-stopping, and presupposes the skill already
fired.** `skills/execute/SKILL.md:574` (`## Autonomy`):

> When authorized to run autonomously, the orchestrator loop (Step 3) runs to the
> done-signal or a genuine blocker and **does not** pause for checkpoints,
> confirmation, reassurance, or unsolicited advisory stops. It **does not** stop
> because the work is large, because issues remain, or out of concern for its own
> context budget.

The corresponding requirement is `docs/prds/PRD-execute-skill.md:194` (R18). Every
word of it is about an agent that is *already inside* `/execute`'s orchestrator loop.

**Net: shirabe has solved "the agent drifts out of the sanctioned loop mid-run" and
has never addressed "the agent never enters the loop."** The trigger incident is the
second failure, and it is unowned.

### 2. The autonomy mandate is nonetheless the best methodological prior art shirabe has

`docs/designs/current/DESIGN-execute-skill.md:207` (`### Autonomous execution
contract`) is the closest thing in the repo to a theory of why prose fails and what
fixes it. Four things in it transfer directly.

**It states the failure model the exploration is chasing.** Lines 209-211:

> A coordinator-driven design is what makes hours-long autonomous runs feasible, and
> the skill must be explicit about the behavior **or the model driving it reverts to a
> default caution** that stops mid-run.

And the sharper version, "Why the architecture is not sufficient":

> Bounded context removes the cause, but a model driving the loop still tends to stop
> and seek reassurance on long work.

That is the same shape as the observed failure: architecture and knowledge are in
place, and the model reverts to a default disposition anyway.

**It names the specific rationalization and kills it by name.** Line 230:

> the cautious-stop instinct surfaces precisely as "I've done several of these, maybe
> I should check in." The mandate must kill that specific non-blocker and replace the
> vibe-of-enough with the concrete done-signal.

The implementing device is a two-column taxonomy in `SKILL.md:583-593` —
**Genuine blockers that stop the run** vs **Not blockers** — which is structurally the
same device as superpowers' Red Flags table (thought in the left column, the reality
that defeats it in the right). Two independent authors converged on "enumerate the
rationalization, then refute it inline." That is the strongest evidence in the
catalogue that the anti-rationalization table is a real technique and not folklore.

**It re-injects rather than relying on entry-time instruction.** Line 227:

> The mandate lives in the SKILL prose and in the koto orchestrator-loop directives so
> it binds at every tick, not only at entry.

The koto-side copy is `skills/execute/koto-templates/execute.md:369`, in the
`spawn_and_await` state: "**Autonomy at every tick.**" This is the single most
transferable insight for this exploration — shirabe already concluded that a
once-at-entry instruction decays and that the fix is repetition against a checkpoint
the agent must pass through anyway.

**It contains an explicit argument against generalizing a mandate.** Same line 230:

> The strategic and tactical chains already run autonomously well, because each of
> their steps produces a *different* artifact ... That heterogeneity gives them
> momentum for free ... This is why the explicit mandate is load-bearing for /execute
> specifically **and not bolted onto every skill.**

The exploration's stated ambition is "a general mechanism." Shirabe's own design doc
argues, with a reason, against exactly that generalization. Flagging as the doctrinal
tension the lead asked about (expanded in §8).

### 3. Shirabe has explicitly named the dispatch gap — and deferred it

`docs/briefs/BRIEF-pr-template-gate.md`, `### OUT of scope`:

> Closing the dispatch gap — routing dispatched PR-opening work through a
> template-applying skill — remains out of scope: it is an orthogonal
> workflow-authoring change, not part of this enforcement work.

The same brief's user journeys describe the failure in the same terms this exploration
uses. A contributor "runs `gh pr create` directly **without invoking any skill**"
(line 100). A dispatched worker "is handed a task brief and opens a PR when its work
is done" and "produces the same generic no-separator body that #220 shipped with."

So the problem is not merely undesigned — it was seen, scoped out in writing, and
labelled an orthogonal workflow-authoring change. Nothing since has picked it up.

### 4. Shirabe's actual shipped doctrine is outcome-gating, not path-mandating

This is the most important finding for the exploration's decision, because it is a
worked, twice-applied alternative to a mandate. `BRIEF-pr-template-gate.md`,
`### IN scope`:

> - Framing PR-template conformance as a property enforced **independent of which code
>   path opened the PR**, mirroring how the DRAFT-vs-READY discipline was moved behind
>   a path-independent gate in #220.
> - **Path-independence as the acceptance property**: the gate must catch a manual or
>   dispatched PR, not only a skill-authored one, and must not fail a legitimate
>   minimal PR.

Its References section calls this a repeated correction: "the same 'move the rule off
the happy path' correction applies." `references/pr-body-conformance.md:18` states the
result — "pointing every consumer here makes conformance a property of the repo."

Read against this exploration: shirabe's established answer to "an agent skipped the
skill" has been *don't try to make the skill unskippable; make the outcome checkable
without it*. Two instances shipped (#220 DRAFT-vs-READY, the PR-body gate). That is a
genuine counter-proposal that the exploration should weigh rather than assume away.

The limit is equally clear, though: it works where the sanctioned path's value is a
*checkable artifact property* (a title format, a `---` separator). The trigger
incident's loss was a *process* — no koto session, no task state machine, no per-issue
spawn, no adversarial review gates. Those leave weaker artifact traces, so a
path-independent gate has less to bite on. Partially checkable: koto session existence
and per-issue PR shape are observable after the fact.

### 5. A PreToolUse deny-gate is already designed and specified in shirabe

`docs/designs/current/DESIGN-pr-template-gate.md:183` evaluates three client-side
surfaces and picks one. Directly reusable, and it front-runs several questions this
exploration will hit.

The chosen surface (line 198): "a **Claude Code PreToolUse hook matching the Bash
tool**, the same mechanism shirabe's `work-summary` (PostToolUse) and the existing
`gate-online` (PreToolUse) hooks already use. It receives the exact command string in
the hook JSON before execution, **fires for every Bash invocation regardless of how it
was issued**, and has a defined allow/ask/deny response contract."

The chosen response (line 214, `### Hook response: block vs warn-only`) is
**deny, fail-open**. Two rejections matter here:

> **Warn-only** (allow + `additionalContext` naming the findings) was considered and
> rejected as the primary behavior: it does not stop the malformed PR from being
> created, so the client surface would be redundant with the CI gate rather than
> additive.

> **Ask** was rejected because the session runs under `bypassPermissions` and
> **dispatched/headless agents have no human to prompt; an `ask` there stalls the
> turn.**

That second one is a hard constraint on anything this exploration designs: the
`niwa dispatch` half of the requirement rules out `ask` entirely. A gate must be
deny-or-allow, and the deny reason must be precise enough that the agent re-issues a
corrected call unaided.

Distribution is already solved for this one hook: logic lives in the on-PATH `shirabe`
binary (`shirabe pr-body-hook`), and niwa's per-repo `SettingsMaterializer` injects a
thin inline pass-through during `niwa apply`, gated per repo (design lines 471-489).
That is precisely the "declarable as workspace policy by an org owner" shape the
exploration wants. (`lead-niwa-distribution-surface` owns the detail.)

Note `shirabe install-hooks` is **not** this — it scaffolds a git `pre-commit` hook
(`crates/shirabe/src/main.rs:1264`, `docs/guides/multi-consumer-cli-contract.md:112`).
Different surface, no bearing on skill invocation.

### 6. The routing map exists; the router does not

`references/pipeline-model.md:229` has a `## Skill routing table`. One of its rows:

| Situation | Skill sequence |
|-----------|---------------|
| Full plan ready to ship | /execute PLAN-*.md (plan orchestrator) -> /release |

The trigger incident is a row in a table. The same file's complexity table (line 33)
maps entry points per level; `/explore SKILL.md:19` describes itself as "the entry
point for 'I don't know what I need'" serving "as a passive routing advisor (when
Claude is auto-loaded and users need help picking a command)."

But **nothing loads any of this unless a skill has already fired**. `pipeline-model.md`
is a `references/` file read by skills mid-run. `/explore`'s routing tables are inside
`/explore`, reachable only by invoking `/explore`. The "passive routing advisor" role
is passive in the strict sense: it advises only if something already put it in context.
There is no gateway skill, no entry-point skill, and no mechanism that consults the
routing table before the agent picks its first action. Shirabe has a complete map with
no compass.

### 7. Shirabe uses the harness's *suppress* lever and has no *force* lever

Three skills carry `disable-model-invocation: true` — `skills/inflight/SKILL.md:13`,
`skills/private-content/SKILL.md:4`, `skills/public-content/SKILL.md:4`. The intent is
stated at `skills/inflight/SKILL.md:107`: "This skill is user-invoked only
(`disable-model-invocation: true`); the model does not trigger it on its own."

The frontmatter has an off switch and no on switch. This is a harness limitation, not
a shirabe oversight — corroborated by an open Claude Code issue,
[anthropics/claude-code#65371](https://github.com/anthropics/claude-code/issues/65371),
"Support auto-invoke of skills via settings.json (SessionStart hook)". The community
workaround is the same SessionStart-injection trick superpowers uses
([gist](https://gist.github.com/mrvnklm/024a04e05e960f85815fdfc698761f1a)).

### 8. Local hooks in this repo: intent right, distribution absent, one is dead

`.claude/hooks/` contains two hooks:

- `pre_tool_use/gate-online.local.sh`
- `stop/workflow-continue.local.sh`

Both match `*.local*` in `.gitignore:30` — **untracked local state, not distributed to
anyone**. Whatever they do, they are not workspace policy.

`workflow-continue.local.sh` is the interesting one because its posture is exactly what
the user says they prefer. Its header:

> Checks if there's an active workflow state file with incomplete work. If so, nudges
> the agent with a non-blocking reminder about the controller. **The agent decides
> whether to continue or stop -- this avoids infinite loops.**

It looks for `wip/*-state.json`, checks for issues not `completed`/`ci_blocked`, and
emits `{"decision": "block", "reason": ...}` pointing at `workflow-tool controller
next`.

Two defects worth recording. First, **it is effectively dead code**: line 24 exits 0
unless `stop_hook_active == "true"`, but that field is set only when Claude is *already*
continuing from a previous stop-hook block. The first stop always exits 0, so the
second never occurs, so the nudge never fires. (Inference from reading the script
against the documented hook payload semantics; not runtime-tested.) Second, it targets
`workflow-tool controller next`, a legacy tsukumogami tool, not koto — so even if the
guard were fixed it would nudge toward the wrong runtime.

Still, its *shape* is the best local template for a nudge-class mechanism: read durable
state, decide, emit a reason the agent can act on, leave agency intact.

### 9. `P5: Strictness tracks blast radius` already licenses a staged posture

`references/workflow-principles.md:87`:

> How hard a rule is enforced scales with the consequence of getting it wrong. A check
> whose retrofit cost is contained can land strict; a check whose retrofit cost is
> corpus-wide lands as a notice first, then is promoted to error once the corpus
> conforms.

The user prefers strong guidance over hard enforcement but wants the spectrum mapped.
P5 is the existing doctrine that says *both, in sequence*: ship the adherence
mechanism as a notice/nudge, promote to a hard gate once behavior settles. Any design
that picks a single point on the spectrum is arguing against a stated shirabe
principle; a design that stages is arguing with it.

### 10. The superpowers `using-superpowers` pattern, in full

`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.2.0/`.

**Mechanism.** `hooks/hooks.json` registers one hook:

```json
"SessionStart": [{ "matcher": "startup|clear|compact", "hooks": [...] }]
```

`hooks/session-start` reads `skills/using-superpowers/SKILL.md` *whole*, JSON-escapes
it, and injects it as `hookSpecificOutput.additionalContext` wrapped in
`<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n...`. The matcher including `compact`
is deliberate and is a genuine strength — the mandate is re-injected after compaction,
which is exactly the failure window for a 22-issue run.

**Content.** The framing block (SKILL.md:10-16):

> If you think there is even a 1% chance a skill might apply to what you are doing, you
> ABSOLUTELY MUST invoke the skill.
>
> IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.
>
> This is not negotiable. You cannot rationalize your way out of this.

The rule (line 20): "**Invoke relevant or requested skills BEFORE any response or
action** — including clarifying questions, exploring the codebase, or checking files."
Then a 12-row Red Flags table (lines 37-50) pairing a rationalizing thought with its
refutation — "Let me explore the codebase first" / "Skills tell you HOW to explore.
Check first."; "This doesn't need a formal skill" / "If a skill exists, use it."

**Two holes, both material to this exploration.**

The first is at the very top, SKILL.md:6-8:

```
<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>
```

The pattern **explicitly exempts dispatched agents**. This is on top of the structural
fact that SessionStart does not fire for subagents at all. The exploration requires the
mechanism work "for agents launched by another agent via `niwa dispatch`" — superpowers'
answer to that case is to opt out of it.

The second is the last line, SKILL.md:62:

> User instructions (CLAUDE.md, AGENTS.md, GEMINI.md, etc, direct requests) take
> precedence over skills, which in turn override default behavior. Only skip skill
> workflows or instructions when your human partner has explicitly told you to.

The second sentence narrows the first, but the first sentence is a general license and
is the one that will be recalled under load. Expanded in §11.

### 11. Honest assessment of each pattern against the observed failure

The diagnostic fact governs everything below: **the agent already knew.** When asked,
it named koto, the task state machine, the per-issue spawn, and the review gates. So
the failure is not missing knowledge, not description-matching, not skill discovery. It
is that at the moment of choosing the first action, "start implementing" was more
available than "call the Skill tool." **Any mechanism whose only effect is to supply
knowledge cannot fix a failure whose cause is not missing knowledge.** That test
disqualifies more of the catalogue than it looks like it should.

**SessionStart injection with `<EXTREMELY_IMPORTANT>` framing — would raise the odds,
would not have caught it, and is holed for half the requirement.** It attacks the right
moment (action-selection, turn 1) and the `compact` matcher is a real strength for long
runs. But it adds salience, not knowledge, and salience is probabilistic — the agent had
the skill listed in its toolset, with a description naming exactly its task, and chose
otherwise. Restating "use skills" louder does not add the missing ingredient. And it
self-exempts dispatched subagents, so it fails the `niwa dispatch` path outright.
Verdict: worth having, insufficient alone, and needs a different answer for dispatch.

**The anti-rationalization table specifically — the strongest prose component, but its
power comes from where it fires, not from its wording.** Two independent authors
(superpowers' Red Flags, shirabe's blocker/not-a-blocker taxonomy) converged on the
device, and shirabe's design doc claims it works for the analogous mid-run failure.
Note the asymmetry, though: shirabe's taxonomy fires **at every koto tick against a live
state machine**; superpowers' table fires once, at session start, unwitnessed. The
mid-run mandate has a checkpoint; the entry-time table does not. If this exploration
adopts the table, it should adopt the checkpoint with it.

**Restricted-tool subagent (agent definition omitting Edit/Write) — this one would
actually have caught it.** It is the only mechanism in the catalogue that converts a
*should* into a *cannot*. An orchestrator without Edit/Write cannot implement 22 plan
outlines by hand; its only route to code is spawning children, which is the sanctioned
loop. It also enforces a boundary shirabe's architecture already draws —
`DESIGN-execute-skill.md` describes `/execute` as holding "only the metadata surface"
and offloading "every issue's real work to a fresh /work-on child," so the restriction
formalizes an existing design invariant rather than inventing one. Three real costs: it
only covers the dispatch path (you must control the agent definition, so a human typing
`/execute` in a normal session is untouched); it is coarse (the orchestrator also
authors a wip state projection and a PR body, so carve-outs are needed, and a Bash-
capable agent can write files anyway unless Bash is also constrained); and it changes
*what the agent is*, not *what it chooses*, which is a heavier commitment than a nudge.

**Output styles — weakest in the catalogue, with no compensating advantage.** Same class
as SessionStart injection (more authoritative words at the top of the context) but
strictly worse for this purpose: one active at a time, not composable with per-repo
policy, a user-level setting rather than something an org owner declares as workspace
policy, and blind to the task. Would not have caught it. I would not spend design
budget here.

**CLAUDE.md precedence — would not have caught it, and the precedence rule is arguably
part of the cause.** CLAUDE.md is advisory by construction and is the least-attended
text in a long session. The sharper problem is the rule itself: "user instructions take
precedence over skills" gives the agent a principled reason to proceed directly, and it
has **no way to distinguish "the user overrode the skill" from "the user described the
task the skill exists for."** The trigger session was *told to execute a plan* — a
direct request. That is simultaneously the strongest possible signal to invoke
`/execute` and, under the precedence rule, a user instruction that outranks it. The
rule is load-bearing for good reasons (a user must be able to say "just do it"), but
the ambiguity is real and this exploration should design against it explicitly rather
than inherit it. This is the sharpest tension the lead asked about.

**Hook-based gates — the only mechanisms with teeth; three variants, different
timings.**

- *UserPromptSubmit* — fires before the agent reasons, sees the prompt text, can inject
  or block. Would plausibly have caught "execute this plan" at the door for the human
  path. Whether it fires for a `niwa dispatch` agent's initial task brief is the open
  question; if it does not, this variant covers only half the requirement.
  (`lead-hook-surfaces` owns this.)
- *PreToolUse deny* — fires at the moment the failure manifests: the first Edit/Write in
  a session where a plan is in play and no koto session exists. This is the closest
  thing to the restricted-tool subagent, but conditional, per-repo distributable, and
  **path-agnostic** — it keys on the tool call, not on who typed the prompt, so it
  covers both the human and the dispatch entry paths with one mechanism. It also has a
  fully worked precedent in `shirabe pr-body-hook`. The hard part is the condition: "a
  plan doc is the subject and no koto session exists" is not trivially computable from
  the hook payload, and a false positive blocks legitimate work.
- *Stop hook* — catches it 22 issues too late, but is exactly the shape of the local
  `workflow-continue.local.sh` and matches the user's stated preference. Its honest role
  is **detector, not preventer**: it can notice "a plan was implemented with no koto
  session" and say so, which is worth something as a feedback loop even if it saves
  nothing on the run in question.

Constraint binding all three, from shirabe's own design: `ask` is unusable. Dispatched
sessions run under `bypassPermissions` with no human, and an `ask` stalls the turn. The
gate must be deny-or-allow, with a deny reason precise enough to self-correct.

### 12. Does shirabe's autonomy language undercut adherence?

Less than it looks in general, more than expected in two specific places.

**Not in tension in general.** The autonomy mandate is about *not stopping*; an
adherence mandate is about *starting*. They compose cleanly — "invoke `/execute`, then
don't stop" is coherent, and adherence arguably *strengthens* autonomy, since
`/execute`'s whole value proposition is the unattended run that autonomy protects.

**First real tension: shirabe argues against generalizing a mandate.**
`DESIGN-execute-skill.md:230` says the mandate is load-bearing "for /execute
specifically and not bolted onto every skill," reasoning that heterogeneous chains
(`/charter`, `/scope`) have completion momentum for free and need no mandate. The
exploration's stated ambition — a general mechanism — is exactly the bolting-onto-every-
skill that this passage rejects. The rejection has a reason attached, so it deserves an
answer rather than a wave-through. The available answer is that the two mandates differ
in kind: shirabe's argument is about *mid-run stopping*, whose likelihood genuinely does
vary with chain heterogeneity, whereas *invocation failure* has no such variance — an
agent can skip `/scope` as easily as `/execute`. But this is my reasoning, not the
document's, and should be stated as a decision rather than assumed.

**Second real tension, and this one is inference.** An agent primed with "run
autonomously, don't pause, don't seek confirmation, take the reasonable default and
continue" has been given a disposition that at action-selection time reads as *bias
toward proceeding directly*. The trigger session's behavior — build a task list, start
implementing, don't check in — is what an autonomy-primed agent does. If a session
absorbs "be autonomous" before it absorbs "use the sanctioned loop," the autonomy
language may make the invocation failure *more* likely, not less. I found no document
that considers this interaction. Flagging as a hypothesis worth testing, not a finding.

## Implications

**The problem is genuinely unowned in shirabe, so this is design work, not repair.**
No prior attempt failed; no prior attempt was made. The one place the gap was written
down (`BRIEF-pr-template-gate.md`) scoped it out as "an orthogonal workflow-authoring
change." That framing is now the thing to overturn.

**The exploration must choose between two doctrines shirabe already holds, or
reconcile them.** Outcome-gating (§4, two shipped instances, path-independence as the
acceptance property) says: don't make the skill unskippable, make the outcome
checkable. A mandate says the opposite. They are not incompatible — the honest read is
that outcome-gating works where the loss is a checkable artifact property and degrades
where the loss is process, which is the trigger incident's case. A design that adopts a
mandate should say why outcome-gating is insufficient here, in those terms.

**Only two mechanisms in the catalogue would actually have caught the failure**, and
they sit at opposite ends: restricted-tool agent definitions (dispatch path only,
converts should to cannot) and PreToolUse deny (both paths, needs a computable
condition). Everything else raises probability. If the user genuinely prefers guidance
over enforcement, the honest framing is that guidance is a probability play and should
be sold as one — with `P5` (§9) as the sanctioned route to promote it later.

**Two structural insights transfer directly into whatever gets designed.** Bind at
every tick, not only at entry (`DESIGN-execute-skill.md:227` — shirabe's own conclusion
that entry-time instruction decays). And enumerate the specific rationalization rather
than issuing a general exhortation (the blocker taxonomy and the Red Flags table
converged on this independently).

**The dispatch path needs its own answer.** Both the superpowers pattern
(`<SUBAGENT-STOP>`, plus SessionStart not firing for subagents) and the ergonomics work
(`BRIEF-shirabe-pattern-v1-ergonomics.md`) show that dispatched agents are where prose
guarantees go to die. A design that solves the human `/execute` case and assumes
dispatch follows will not hold.

**`ask` is off the table** for any gate, per `DESIGN-pr-template-gate.md`'s explicit
rejection on `bypassPermissions` grounds. Deny-or-allow only, with self-correcting
reasons.

## Surprises

**The routing table contains a row for the exact failure.** `pipeline-model.md:229`:
"Full plan ready to ship | /execute PLAN-*.md (plan orchestrator) -> /release". The
knowledge was not just available to the agent, it was written down in a table
specifically built to answer the question the agent got wrong. Nothing loads that table
unless a skill already fired. Shirabe has a complete map and no compass.

**The gap was named in writing and deferred.** I expected to find the problem
undiscussed. `BRIEF-pr-template-gate.md` names "the dispatch gap" and defers it as
orthogonal. That is a stronger starting position than a blank slate and a more awkward
one — the deferral has a stated rationale to answer.

**Shirabe uses the harness's off switch three times and has no on switch.**
`disable-model-invocation: true` on `/inflight`, `/private-content`, `/public-content`.
The asymmetry is a harness limitation with an open upstream issue (#65371), not a
shirabe choice — but it means every "force" mechanism in the catalogue is a workaround
for a missing primitive.

**Both of shirabe's shipped enforcement mechanisms gate the artifact, not the path.**
I expected at least one path-level control. There is none. The consistency is
deliberate ("the same 'move the rule off the happy path' correction").

**The one hook in this repo whose posture matches the user's preference is dead code.**
`workflow-continue.local.sh` guards on `stop_hook_active == "true"`, which is only set
on a continuation *from* a stop hook — so the first stop exits 0 and the nudge never
fires. It also targets `workflow-tool controller next`, a legacy tool, not koto. And
it is gitignored, so it was never anyone's policy.

**Shirabe's design doc contains an argument against the exploration's stated ambition.**
`DESIGN-execute-skill.md:230`, "not bolted onto every skill." Worth surfacing early
rather than discovering it in review.

## Open Questions

1. **Does `UserPromptSubmit` fire for a `niwa dispatch` agent's initial task brief?**
   If yes, it is the cheapest mechanism covering both entry paths. If no, dispatch needs
   a separate surface. (`lead-hook-surfaces`.)
2. **Can a PreToolUse hook cheaply compute "a plan is in play and no koto session
   exists"?** This is the make-or-break for the only path-agnostic mechanism with teeth.
   koto has session storage and a `status` surface. (`lead-koto-observability`.)
3. **Can an org owner declare hooks as per-repo workspace policy via niwa's
   `SettingsMaterializer`?** `DESIGN-pr-template-gate.md` says yes for the pr-body hook
   specifically; whether that generalizes is unconfirmed.
   (`lead-niwa-distribution-surface`.)
4. **Is a restricted-tool orchestrator agent definition distributable as workspace
   policy, and does a human typing `/execute` have any route into one?** The restriction
   is the only hard mechanism for dispatch; if it cannot reach the human path, the
   design needs two mechanisms rather than one.
5. **Should the mechanism be shirabe-owned or niwa-owned?** The pr-template-gate
   precedent splits it — logic in the `shirabe` binary, injection by niwa. Worth
   following unless there is a reason not to.
6. **Does an autonomy-primed agent skip skills more often?** (§12, inference only.) If
   true, the mandate and the autonomy language need to be authored together rather than
   layered.
7. **How much of the trigger incident's loss is actually artifact-checkable?** koto
   session existence and per-issue PR shape leave traces; the adversarial review gates
   leave less. This determines whether outcome-gating is a partial substitute or no
   substitute.

## Summary

Shirabe has never attempted to make skill invocation mandatory — `/execute`'s
"parent-skill conformance" is a seven-element SKILL.md authoring checklist and its
"autonomy mandate" governs not-stopping once the skill is already running, so both are
false friends; the dispatch gap was named in `BRIEF-pr-template-gate.md` and explicitly
scoped out as orthogonal. Shirabe's real shipped doctrine is the opposite of a mandate —
path-independent outcome gating, twice applied — and its own `DESIGN-execute-skill.md`
argues that an explicit mandate is load-bearing "for /execute specifically and not
bolted onto every skill," so this exploration's general mechanism has to answer both
positions; meanwhile only two catalogued patterns would actually have caught an agent
that knew the right path and chose otherwise, namely a restricted-tool agent definition
(dispatch path only) and a PreToolUse deny gate (both paths, if the condition is
computable), while SessionStart injection, output styles, and CLAUDE.md precedence only
raise probability — and the precedence rule arguably licenses the skip. The biggest open
question is whether a hook can cheaply detect "a plan is in play with no koto session,"
since that condition is what separates the one path-agnostic mechanism with teeth from
another round of louder prose.
