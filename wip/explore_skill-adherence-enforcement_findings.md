# Exploration Findings: skill-adherence-enforcement

Round 1. Seven leads dispatched; five landed before a usage-limit interruption
and two were relaunched. Findings below are cited to the per-lead research files
in `wip/research/`.

---

## The premise changed twice

The exploration opened on the theory that shirabe's skills are hard to reach:
the plugin ships `skills/` and no `commands/`, so a bare `/execute` was assumed
to match nothing. **That theory is dead.** A live probe on Claude Code v2.1.233
confirmed bare `/execute` resolves to `shirabe:execute` today, at the workspace
root, on this machine -- 41,901 tokens of cache creation is the execute SKILL.md
body entering context. Plugin skills get a bare alias unless another command
claims the name, and nothing else on disk claims `execute`
(`lead-slash-command-resolution`).

Then the second incident arrived and moved the problem again. In it the skill
**did** fire. The agent ran the preflight, confirmed the referenced defect, and
ran `plan-to-tasks.sh` to produce a valid koto payload with all six `waits_on`
edges -- then used the payload only to check the graph and never submitted it,
implementing all six issues inline. Its reason: the session instruction "Do not
call the AgentTool unless the user requested it" collided with `spawn_and_await`,
which spawns one `/work-on` child per issue, and it resolved the conflict against
the skill (`wip/explore_skill-adherence-enforcement_evidence.md`).

So the target is not discoverability. It is two distinct failures that produce
one identical loss:

| | Incident 1 | Incident 2 |
|---|---|---|
| Skill fired? | No | Yes |
| Cause | Never consulted the skill list | Precedence conflict resolved silently against the skill |
| Would better descriptions help? | Marginally | No |
| Would checking "was the skill invoked?" catch it? | Yes | **No** |
| User-visible loss | No visibility, no review gates | Identical |

---

## Finding 1: The competence filter, not the description, is why the skill did not fire

`skill-creator/SKILL.md:396-400` states the mechanism first-party: skills appear
in `available_skills` with name and description, and **"Claude only consults
skills for tasks it can't easily handle on its own."** That filter runs upstream
of description matching. Executing a plan reads as a task a model can handle
directly -- it has Read, Edit, Bash, and a task list, and a PLAN doc is a legible
list of work items (`lead-skill-firing-mechanics`).

The decisive evidence is not `execute`'s description but `work-on`'s. `execute`'s
description is genuinely defective -- roughly 40 words of internal vocabulary
("wip-yaml-md state projection over the durable home PR", "the three exit-path
bindings", "the six security surfaces") with no "Triggers on" phrases and no
named moment. But `work-on`'s description is close to ideal: it claims PLAN
documents explicitly, lists eight trigger verbs, and says "at any size, from a
single issue to a whole plan." **It also did not fire on "execute this plan."**
Overlap can explain a wrong choice; it cannot explain a total miss.

Consequence: description repair is necessary hygiene with a measurable ceiling,
not the mechanism.

## Finding 2: Shirabe's eval suite cannot see this failure at all

All 18 shirabe eval suites use the `skill-creator` `evals.json` schema, and
**every prompt begins with an explicit slash command** -- `"/execute
skills/execute/evals/fixtures/plans/PLAN-diamond-test.md"`. Every expectation is
about post-invocation behavior. The suite is strong evidence the skills behave
correctly once invoked and zero evidence about whether they get invoked
(`lead-skill-firing-mechanics`).

`skill-creator` ships a real triggering-measurement loop (`scripts.run_loop`:
60/40 train/test split, three runs per query for a stable rate, extended-thinking
rewrites from failures, up to five iterations, `best_description` selected on the
held-out split to avoid overfitting). Closing the gap costs ~20 queries per skill.
Its stated limit matters though: it measures cold single queries and cannot
measure past the competence filter, and both incidents arrived mid-session with
conversational momentum.

## Finding 3: Shirabe has never attempted this, and its shipped doctrine argues the other way

The two terms in `execute`'s description that sounded like prior art are false
friends. "Parent-skill conformance" is a seven-element **SKILL.md authoring
checklist** (`references/parent-skill-pattern.md:548`). The "autonomy mandate"
governs **not stopping once the skill is already running**
(`skills/execute/SKILL.md:574`). Shirabe has solved "the agent drifts out of the
loop mid-run" and never addressed "the agent never enters the loop"
(`lead-mandatory-workflow-prior-art`).

The gap was seen and deferred in writing. `BRIEF-pr-template-gate.md` names
"closing the dispatch gap" and scopes it out as "an orthogonal workflow-authoring
change."

Two positions in shirabe's own docs have to be answered rather than waved past:

- **Outcome-gating is the shipped doctrine, twice.** The same brief frames
  conformance as "a property enforced independent of which code path opened the
  PR," and calls path-independence the acceptance property. Shirabe's established
  answer to "an agent skipped the skill" has been *don't make the skill
  unskippable, make the outcome checkable without it*.
- **`DESIGN-execute-skill.md:230` argues against generalizing a mandate** -- it is
  load-bearing "for /execute specifically and not bolted onto every skill,"
  reasoning that heterogeneous chains have completion momentum for free. This
  exploration's stated ambition is exactly that generalization. The available
  answer is that the two mandates differ in kind (mid-run stopping varies with
  chain heterogeneity; invocation failure does not), but that is a decision to
  record, not an assumption.

Three transferable insights from the same body of work: **bind at every tick, not
only at entry** (`DESIGN-execute-skill.md:227` -- shirabe's own conclusion that
entry-time instruction decays, implemented as "Autonomy at every tick" in the
koto template); **enumerate the specific rationalization rather than exhorting
generally** (shirabe's blocker/not-a-blocker taxonomy and superpowers' Red Flags
table converged on this independently); and **`P5: Strictness tracks blast
radius`** (`references/workflow-principles.md:87`), which already licenses
shipping as a notice and promoting to a gate once the corpus conforms.

## Finding 4: `ask` is off the table, and the superpowers pattern self-exempts the case we need

`DESIGN-pr-template-gate.md:214` rejected `ask` explicitly: dispatched and
headless agents run under `bypassPermissions` with no human, so an `ask` stalls
the turn. Any gate must be deny-or-allow with a reason precise enough to
self-correct.

The superpowers `using-superpowers` pattern -- SessionStart injection of the whole
SKILL.md wrapped in `<EXTREMELY_IMPORTANT>`, matched on `startup|clear|compact`,
carrying a twelve-row anti-rationalization table -- is the strongest prose
precedent, and re-firing on `compact` is a real strength for long runs. It has
two holes for our purposes. Its first line is `<SUBAGENT-STOP>: If you were
dispatched as a subagent to execute a specific task, ignore this skill.` And its
last line concedes that user instructions and CLAUDE.md **take precedence over
skills** -- which is precisely the rule incident 2 invoked.

That concession cuts both ways. It is good news for the org-owner requirement (a
CLAUDE.md declaration sits at the top of an already-established precedence order)
and it is the license incident 2 used. The precedence rule has no way to
distinguish "the user overrode the skill" from "the user described the task the
skill exists for" -- and being *told to execute a plan* is simultaneously the
strongest possible signal to invoke `/execute` and, under the rule, a user
instruction that outranks it.

## Finding 5: The distribution question is already solved; niwa ships a working gate today

niwa **already injects a shirabe-specific PreToolUse allow/deny gate** (`shirabe
pr-body-hook`) plus three work-summary hooks into any instance that installs the
shirabe plugin, by default, with no configuration -- gated on a
`shirabePluginName = "shirabe"` const in niwa's own source and controlled by a
`[claude] pr_body_hook = false` off switch (`lead-niwa-distribution-surface`).

So the coupling this exploration was going to have to justify already exists and
already ships. The whole spectrum maps onto parts already in the binary:

| Rung | Existing mechanism |
|---|---|
| `off` | nothing |
| `advertise` | generated CLAUDE.md fragment via `appendToWorkspaceRulesFile` |
| `remind` | `user_prompt_submit` hook, on the `shirabe work-summary absence` template |
| `gate` | `pre_tool_use` hook, on the `shirabe pr-body-hook` template |

The established division of labor is **niwa declares and distributes, shirabe
decides** -- niwa injects `shirabe pr-body-hook` and knows nothing about PR
bodies. A skill policy should follow that line.

Two operational cautions recorded in niwa's own source: a PreToolUse hook
matching every Bash command must not `exec` and must swallow non-zero, because a
non-zero exit blocks the call and a stale binary would brick every session
(`materialize.go:592-603`); and unknown TOML fields warn and continue, so an
older niwa would **silently ignore** a declared mandate -- the wrong failure mode
for a policy.

**The one genuinely contested question is placement, and it is a values question.**
`[workspace]` is deliberately overlay-proof: `OverlayWorkspaceTombstone` exists
solely to warn that overlay `[workspace]` does nothing, and the stated reason
(`config.go:312-320`) is that it "keeps a contributor's first run un-alterable by
a configuration layer they cannot read." A skill mandate changes what an agent
does for a contributor who cannot read the layer imposing it -- the exact class
the tombstone excludes. The user asked for an org-owner configuration option;
niwa has already answered this question once, in the opposite direction.

## Finding 6: The dispatch mandate is a one-line change, and the brief template is a root cause

`niwa dispatch` composes the worker prompt as `prefix + body`, where `prefix` is
niwa-authored and already carries the keep-alive arming instruction. The
injection point is `dispatch.go:421`, prefix-first ordering is pinned by
`TestComposedArgvIsPrefixThenBody`, and there is no size budget -- oversized
prompts spill to a file rather than being refused
(`lead-dispatch-prompt-construction`).

niwa has already recorded its own channel analysis on exactly this question
(`dispatch_keepalive.go:14-22`): the prompt prepend "is the one channel niwa
controls end to end for a dispatched worker."

The `/dispatch` skill's brief template -- embedded in the niwa binary at
`internal/workspace/rootskills/dispatch/SKILL.md` -- lists Goal, Context,
Pointers, Acceptance criteria, Out of scope, and the work-in-flight block. **There
is no slot for which skills or workflows the worker must use.** The omission is
sharp because step 1a spends 23 lines making the `=== WORK IN FLIGHT ===`
reporting block non-negotiable. The template mandates a reporting convention and
treats the working convention as the worker's business.

And plugin delivery is not the problem: `prewarmDeclaredPlugins` synchronously
clones and installs shirabe before launch, precisely to stop the worker
enumerating skills before shirabe lands. The worker has the skills and no
instruction to use them.

**An unused channel was found.** `DiscoverHooks` plus a `snakeToPascal` fallback
means a workspace-authored `hooks/session_start/*.sh` dropped into the config repo
would materialize a SessionStart hook into **every instance**, including every
dispatch-provisioned one, with zero niwa code changes. niwa's keep-alive design
declared this channel "not viable," but that conclusion is correct only for
niwa's own root-level hook, which self-no-ops inside an instance. Flagged as
read-from-source and **not empirically verified** -- the lead asked for a second
pair of eyes before it is treated as load-bearing.

## Finding 7: A silent-success failure mode worth fixing regardless

When a slash command does not resolve, the harness returns `is_error: false`,
`subtype: "success"`, exit code 0, `num_turns: 0`, and zero tokens -- the failure
exists only as the literal string `Unknown command: /X` in the result field. No
fuzzy match, no passthrough to the model, arguments discarded
(`lead-slash-command-resolution`).

For a human that is a visible annoyance. For any programmatic caller -- `niwa
dispatch`, CI, a parent agent shelling out to `claude -p` -- it is **a silent
failure indistinguishable from success**. This is orthogonal to the adherence
mechanism and cheap to fix (assert the expected skill is installed before launch,
or grep the result for `Unknown command:`).

Related: shirabe is installed at **`local` scope keyed by `projectPath`** -- 25
separate `shirabe@shirabe` entries, one per instance directory. Every fresh niwa
instance re-installs, which makes the workspace structurally exposed to
enumeration timing. niwa fixed the race in `2d72419` (2026-06-28); incident 2
postdates the fix and shows the skill loading correctly, which retires the race
as an explanation for the current problem.

## Finding 8: The gate condition is computable -- this closes the make-or-break question

Koto session state is an append-only JSONL log at
`~/.koto/sessions/<name>/koto-<name>.state.jsonl`. Its header names the template
(`"template_name":"execute"`) and its initialization event carries the bound plan
(`"variables":{"PLAN_DOC":"docs/plans/PLAN-x.md","PLAN_SLUG":"x"}`). So the
question "does a koto session exist for this plan?" is one grep, answerable from
outside with zero agent cooperation (`lead-koto-observability`):

```bash
grep -l "\"PLAN_DOC\":\"docs/plans/PLAN-<slug>.md\"" \
     ~/.koto/sessions/*/koto-*.state.jsonl 2>/dev/null
```

Verified live: 32 plan-bound sessions exist on this machine. And it returns
nothing for incident 2's plan -- **even though that agent ran the skill's scripts
and produced a valid payload with all six `waits_on` edges.** That is the whole
argument for the durable artifact as the unit of measurement.

Three consequences:

- **The same predicate serves all three strengths.** Detect-and-report (Stop
  hook), remind (UserPromptSubmit), and gate (PreToolUse deny) are one condition
  evaluated at three lifecycle events. That is a strong argument for a graded
  level over three separate mechanisms.
- **koto already models deliberate deviation.** `koto overrides` is a shipped verb
  for recording a gate override. The precedence-conflict problem can therefore be
  reframed from "stop the agent deviating" to "make deviation leave a record" --
  much closer to the stated preference for guidance over enforcement.
- **The visibility loss was a registration failure, not a tooling gap.**
  `koto dashboard` exists and shows live session hierarchy and state. Nothing
  appeared in it because nothing was registered.

Koto is structurally blind in one direction that matters: it observes what is
submitted to it and cannot detect its own absence. So the sensor must be a hook;
koto state is the reference it consults.

The cheapest single intervention found in the whole round also lives here.
`plan-to-tasks.sh` produces a payload, and submitting it is a separate, skippable
step -- a step that looks like progress, produces a real artifact, and leaves no
koto trace. Making payload-production and session-registration atomic needs no
hook, no policy, and no niwa change.

Two operational cautions: `koto status` and `koto workflows` emit dozens of
`migration skipped` lines to stderr before their JSON payload, so any hook must
redirect stderr or parse only stdout; and the session store has never been reaped
(1,210 directories, essentially all from March and April), which is adjacent cost
for a hot-path grep.

## Finding 9: The session-id join is confirmed wired end to end

The koto lead flagged one unverified link: it asserted `session_id` is present in
the PreToolUse hook input from the documented contract, but had not read the gate
shirabe already ships. Verified directly against
`crates/shirabe/src/pr_body_hook.rs`.

The hook input carries `session_id` alongside `tool_name` and `tool_input` --
confirmed by the module's own test fixture:

```rust
serde_json::json!({
    "session_id": "s1",
    "tool_name": "Bash",
    "tool_input": { "command": command },
})
```

And the deny response shape is already implemented, with a documented injection
defense (the reason is a `serde_json` string value "so an attacker-influenceable
title/body can never break out of the JSON string or inject a terminal control
sequence"):

```json
{"hookSpecificOutput": {"hookEventName": "PreToolUse",
                        "permissionDecision": "deny",
                        "permissionDecisionReason": "<reason>"}}
```

So the join is complete: **PreToolUse receives the Claude Code session id, and
koto's workflow record is keyed by that same id.** No inference remains in the
chain from "an edit is about to happen" to "this session has no koto workflow
record over the execute/work-on template." A gate is fully specified, and the
place to put it is the binary that already implements this exact shape.

---

## What only two mechanisms would actually have caught

Applying the diagnostic test -- *the agent already knew* -- disqualifies most of
the catalogue. Any mechanism whose only effect is to supply knowledge cannot fix a
failure whose cause is not missing knowledge.

| Mechanism | Catches #1? | Catches #2? | Notes |
|---|---|---|---|
| Better descriptions | Raises odds | No | Necessary hygiene; `work-on` disproves sufficiency |
| SessionStart injection + rationalization table | Raises odds | No | Salience, not knowledge; self-exempts subagents |
| CLAUDE.md declaration | No | **No -- it is the license** | Precedence rule is arguably part of the cause |
| Output styles | No | No | One at a time, not org-declarable, task-blind |
| `niwa dispatch` prefix mandate | Yes, for dispatch | Partially | One line; cannot know which workflow |
| Restricted-tool orchestrator | Yes | **Yes** | Converts should into cannot; dispatch path only |
| PreToolUse deny gate | Yes | **Yes** | Both paths; needs a computable condition |
| Stop-hook detector | Too late | Too late | But it is the honest visibility fix |

The condition a gate needs -- "a plan is in play and no koto session exists" -- is
the make-or-break, and it is exactly what the koto-observability lead owns.

Note the workspace already runs a nudge hook whose posture matches the stated
preference (`stop/workflow-continue.sh`: "nudges the agent with a non-blocking
reminder... The agent decides whether to continue or stop"). It is gitignored
`*.local*`, so it was never anyone's policy; it fires at `Stop`, after the damage;
it keys on `wip/*-state.json`, which neither incident created; and it appears to
be dead code, guarding on `stop_hook_active == "true"` which is only set on a
continuation *from* a stop hook.

---

## Open questions carried into crystallize

1. ~~What is the observable definition of "executed under the workflow"?~~
   **Answered (Finding 8):** a koto session bound to the plan via `PLAN_DOC`.
2. ~~Can a hook cheaply compute "a plan is in play and no koto session exists"?~~
   **Answered (Finding 8):** yes, one grep. The residual gap is how a hook learns
   *which* plan is in play -- branch name, `wip/` state, PR body, or prompt text.
3. **Do hooks fire for subagents, and does SessionStart reach a `--bg` dispatch
   worker?** Decides whether one mechanism or two. (Pending: `lead-hook-surfaces`.)
4. **How is a precedence conflict surfaced rather than resolved silently?**
   Raised by incident 2; upstream of every strength option. Unowned by round 1.
5. **Should the policy be overlay-settable?** The user asked for an org-owner
   option; niwa's `strict_secrets` reasoning says a setting that changes a
   contributor's run must live where the contributor can read it.
6. **Does `work-on` keep its PLAN mode?** Two skills claim PLAN documents. A
   product question, not a research one.
7. **Does an autonomy-primed agent skip skills more often?** Hypothesis only. If
   true, the mandate and the autonomy language must be authored together.
