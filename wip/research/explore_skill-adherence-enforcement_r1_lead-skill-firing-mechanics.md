# Lead: What actually causes a skill to fire, and how do shirabe's descriptions compare against skills that reliably trigger?

Round 1 of the `skill-adherence-enforcement` exploration. All findings below come from
reading installed skill files and shirabe's checkout. Confirmed facts cite a path and
line; inferences are labelled.

---

## Findings

### 1. What drives invocation: the description, filtered by a competence check

**Confirmed.** The first-party statement is in the installed `skill-creator` skill,
`/home/dgazineu/.claude/plugins/cache/claude-plugins-official/skill-creator/unknown/skills/skill-creator/SKILL.md:335`:

> The description field in SKILL.md frontmatter is the primary mechanism that determines
> whether Claude invokes a skill.

But the more important passage is the "How skill triggering works" section at
`SKILL.md:396-400`:

> Skills appear in Claude's `available_skills` list with their name + description, and
> Claude decides whether to consult a skill based on that description. The important
> thing to know is that **Claude only consults skills for tasks it can't easily handle
> on its own** — simple, one-step queries like "read this PDF" may not trigger a skill
> even if the description matches perfectly, because Claude can handle them directly
> with basic tools. Complex, multi-step, or specialized queries reliably trigger skills
> when the description matches.

That sentence is the mechanism behind the trigger incident. Executing a plan reads to a
model as a task it can handle directly: it has Read, Edit, Bash, and a task list, and a
PLAN doc is a legible list of work items. The self-sufficiency filter runs *upstream* of
description matching. A description can shift where the threshold sits — the same file
at `SKILL.md:67` says so explicitly, advising authors to make descriptions "a little bit
pushy" because "Claude has a tendency to 'undertrigger' skills" — but the filter is not
something description text removes.

The same file also gives the mechanical detail that a description-eval must respect
(`SKILL.md:398-400`): trivial prompts fail to trigger regardless of description quality,
so they are worthless as test cases.

**Also confirmed:** the description carries the whole load at selection time. The SKILL.md
body is level 2 of a three-level progressive-disclosure system (`skill-creator/SKILL.md:86-93`)
and is only "in context whenever skill triggers". Nothing in the body can influence
whether the body gets read. This matters a great deal for sub-question 5, below.

### 2. Description style in skills that reliably fire

**Confirmed.** All fourteen superpowers descriptions
(`/home/dgazineu/.claude/plugins/cache/claude-plugins-official/superpowers/6.2.0/skills/*/SKILL.md`)
are trigger conditions, not capability statements. Thirteen of fourteen open with the
literal words "Use when". Verbatim samples:

- `test-driven-development`: "Use when implementing any feature or bugfix, before writing implementation code"
- `systematic-debugging`: "Use when encountering any bug, test failure, or unexpected behavior, before proposing fixes"
- `executing-plans`: "Use when you have a written implementation plan to execute in a separate session with review checkpoints"
- `subagent-driven-development`: "Use when executing implementation plans with independent tasks in the current session"
- `verification-before-completion`: "Use when about to claim work is complete, fixed, or passing, before committing or creating PRs - requires running verification commands and confirming output before making any success claims; evidence before assertions always"

The one exception is `brainstorming`, which is pushy instead: "You MUST use this before
any creative work - creating features, building components, adding functionality, or
modifying behavior."

Two structural properties recur and are worth naming:

1. **They name the moment, not the artifact.** "before writing implementation code",
   "before proposing fixes", "about to claim work is complete", "before committing".
   Each description describes a point in the agent's own trajectory where it would
   otherwise improvise. That is precisely the "name the situations where an agent would
   otherwise improvise" property the lead asked about.
2. **They contain no workflow summary at all.** This is deliberate. superpowers'
   `writing-skills` skill codifies it as a rule with worked examples
   (`superpowers/6.2.0/skills/writing-skills/SKILL.md`, the "Description" section):

   ```
   # BAD: Too much process detail
   description: Use when executing plans - dispatches subagent per task with code review between tasks

   # GOOD: Triggering conditions only
   description: Use when executing implementation plans with independent tasks in the current session
   ```

   The bad example there is *less* architectural than shirabe's `execute` description.

`skill-creator` gives near-identical advice (`SKILL.md:67`): "include both what the skill
does AND specific contexts for when to use it. **All 'when to use' info goes here, not in
the body.**"

### 3. Shirabe's descriptions: mostly well-formed, with `execute` as the outlier

**Confirmed.** Most shirabe descriptions are trigger-shaped and follow the house pattern
of `<what> + Use when <situation> + Triggers on "<phrases>" + Do NOT use for <sibling>`.
`design` is representative
(`public/shirabe/skills/design/SKILL.md`):

> Create technical design documents. Use when deciding how to implement something -- the
> skill decomposes the problem into decision questions... Triggers on "help me design X",
> "how should we architect Y", "compare approaches for Z", "write a design doc", "what's
> the best approach for W", or "I need to decide between A and B". Do NOT use for quick
> opinions without a formal document, open-ended exploration (/explore), or requirements
> definition (/prd).

`plan`, `prd`, `vision`, `roadmap`, `brief`, `strategy`, `explore`, `scope`, `charter` and
`writing-style` all follow it. `writing-style` is the most aggressive of the set and the
closest in spirit to superpowers, naming a moment rather than a request
(`public/shirabe/skills/writing-style/SKILL.md`):

> ...(2) prose output is about to be produced — PR descriptions, issue bodies, README
> sections, documentation, explanations, or summaries... Apply proactively when writing
> prose; don't wait for an explicit invocation.

`execute` is the outlier. Verbatim, from
`public/shirabe/skills/execute/SKILL.md:3-10`:

> Implementation-altitude parent skill that owns plan-level execution. Takes a finished
> PLAN doc and drives it to merged code, delegating each single issue to /work-on. Use to
> run a plan end-to-end: `/execute docs/plans/PLAN-<topic>.md`. Owns single-pr and
> coordinated multi-repo plans, with a wip-yaml-md state projection over the durable home
> PR (cross-branch resume), the three exit-path bindings, parent-skill conformance, the
> six security surfaces, and an explicit autonomy mandate.

Breaking that down against what the field is for:

| Segment | Function at selection time |
|---|---|
| "Implementation-altitude parent skill that owns plan-level execution" | Vocabulary internal to shirabe. Matches nothing a user types. |
| "Takes a finished PLAN doc and drives it to merged code" | Real trigger content — the only unambiguous piece. |
| "Use to run a plan end-to-end: `/execute docs/plans/PLAN-<topic>.md`" | Trigger content, but conditioned on the user already holding a PLAN path and already thinking in shirabe terms. |
| "wip-yaml-md state projection over the durable home PR (cross-branch resume), the three exit-path bindings, parent-skill conformance, the six security surfaces, and an explicit autonomy mandate" | Roughly 40 words, zero trigger value. A maintainer's table of contents. |

There are no "Triggers on" phrases, no "Do NOT use for", and no named moment in the
agent's trajectory. It is a capability statement with a usage example appended. Compare
the sibling that covers the same territory in superpowers — "Use when you have a written
implementation plan to execute in a separate session with review checkpoints" — which
names the situation and stops.

**Inference:** this is not a house-style problem. Ten of shirabe's skills follow the
trigger-condition pattern; `execute` regressed away from it, most likely because the
description was used as a change-log for the architecture work that landed in the skill.

### 4. The `execute` / `work-on` collision

**Confirmed.** Two shirabe skills claim PLAN documents as input.

`work-on` (`public/shirabe/skills/work-on/SKILL.md:3`):

> Implement work end-to-end with branch creation, analysis, coding, tests, and a pull
> request with CI monitoring. Accepts a GitHub issue (number or URL), a milestone
> (selects the next unblocked issue), **a PLAN document path (drives multiple issues
> through one shared branch and PR)**, or a free-form task description. Use when asked to
> work on, implement, fix, build, tackle, pick up, close, or ship work — **at any size,
> from a single issue to a whole plan.**

`execute` claims the same input and says it delegates each issue to `/work-on`.

By description quality alone, "execute this plan" should have matched `work-on` — its
trigger vocabulary ("work on, implement, fix, build, tackle, pick up, close, or ship")
covers essentially every phrasing a human would use, and it explicitly claims "a whole
plan". It is arguably the best-written description in the plugin.

**This is the load-bearing observation of the round.** The incident agent did not pick the
wrong shirabe skill. It picked *none of them*, when one of the two candidates had close to
ideal trigger phrasing. Overlap between the two can explain a wrong choice; it cannot
explain a total miss. What explains a total miss is the competence filter from Finding 1.

**Inference:** the collision is still a real defect worth fixing (a model that does
consult the list has to disambiguate two skills claiming one input, and ambiguity
suppresses selection), but fixing it alone would not have prevented the incident.

### 5. Why `using-superpowers` exists, and what its shape admits

**Confirmed.** `superpowers:using-superpowers` is not delivered through the normal
retrieval path at all. `superpowers/6.2.0/hooks/hooks.json` registers a `SessionStart`
hook matching `startup|clear|compact`, and `hooks/session-start:27` builds the injection:

```
session_context="<EXTREMELY_IMPORTANT>\nYou have superpowers.\n\n**Below is the full
content of your 'superpowers:using-superpowers' skill...**\n\n${...}\n</EXTREMELY_IMPORTANT>"
```

The entire SKILL.md body is read off disk (`hooks/session-start:11`) and pasted into the
context window unconditionally, before the user's first message.

That design is a structural admission: **the authors of the most trigger-disciplined
skill descriptions in the ecosystem do not trust description-based retrieval to fire their
own meta-rule.** They bypass retrieval entirely for the one skill whose job is making
other skills fire.

The injected content escalates from there
(`superpowers/6.2.0/skills/using-superpowers/SKILL.md:10-16`):

> If you think there is even a 1% chance a skill might apply to what you are doing, you
> ABSOLUTELY MUST invoke the skill.
> IF A SKILL APPLIES TO YOUR TASK, YOU DO NOT HAVE A CHOICE. YOU MUST USE IT.
> This is not negotiable. You cannot rationalize your way out of this.

And then the Red Flags table (`SKILL.md:33-50`) enumerates twelve specific rationalizations
with rebuttals. The entries that map onto the incident:

| Thought | Reality |
|---------|---------|
| "Let me explore the codebase first" | Skills tell you HOW to explore. Check first. |
| "I'll just do this one thing first" | Check BEFORE doing anything. |
| "This feels productive" | Undisciplined action wastes time. Skills prevent this. |
| "The skill is overkill" | Simple things become complex. Use it. |
| "I know what that means" | Knowing the concept ≠ using the skill. Invoke it. |

**What this tells us about the failure mode.** The table is a recognition-time
intervention, not an awareness-time one. It is not defending against "the agent didn't
know a skill existed" — it is defending against "the agent knew, and talked itself out of
it in a way that felt like diligence." That is exactly the incident: building a task list
and hand-implementing 22 plan outlines is the highest-scoring possible instance of "this
feels productive." The agent was not ignorant of `/execute`; it was mid-flow and never ran
the check.

Two further details from the injected text matter for the mechanism design:

**(a) The precedence rule, at `SKILL.md:62`:**

> User instructions (CLAUDE.md, AGENTS.md, GEMINI.md, etc, direct requests) take
> precedence over skills, which in turn override default behavior. Only skip skill
> workflows or instructions when your human partner has explicitly told you to.

Even the maximal-pressure injection concedes that CLAUDE.md outranks skills. That is good
news for the "declarable as workspace policy by an org owner" requirement: a CLAUDE.md
declaration sits at the top of the stated precedence order by existing convention, not by
anything shirabe would have to invent.

**(b) The subagent exemption, at `SKILL.md:6-8`, the very first thing in the file:**

```
<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific task, ignore this skill.
</SUBAGENT-STOP>
```

superpowers deliberately **disables** the meta-rule for dispatched subagents, on the
reasoning that a subagent given a narrow task should just do it. The exploration's scope
requires the opposite for `niwa dispatch` — an agent dispatched with "run this plan" is
exactly the case that must still route through the sanctioned workflow. Any mechanism
shirabe builds has to distinguish "dispatched to do one narrow thing" from "dispatched to
run a whole plan," which superpowers does not attempt.

### 6. Does `skill-creator` really support triggering measurement? Yes — two separate systems

**Confirmed.** `skill-creator` contains two distinct evaluation systems that are easy to
conflate.

**Behavior evals** (`skill-creator/SKILL.md:141-289`): `evals/evals.json` holds prompts;
subagents run each prompt with-skill and baseline in the same turn; a grader subagent
(`agents/grader.md`) scores assertions into `grading.json`; `python -m
scripts.aggregate_benchmark` produces mean ± stddev with a delta; `eval-viewer/generate_review.py`
renders it for a human. These measure what the skill does **after** it fires.

**Description optimization** (`skill-creator/SKILL.md:333-404`) is the one that measures
triggering, and it is a real, runnable loop:

```bash
python -m scripts.run_loop \
  --eval-set <path-to-trigger-eval.json> \
  --skill-path <path-to-skill> \
  --model <model-id-powering-this-session> \
  --max-iterations 5 --verbose
```

Per `SKILL.md:394`, it splits the eval set 60/40 train/held-out-test, runs each query
**three times** to get a stable trigger rate, calls Claude with extended thinking to
propose description rewrites from the failures, re-scores on both splits for up to five
iterations, and returns `best_description` **selected by test score rather than train
score to avoid overfitting.** The input is 20 queries as
`[{"query": ..., "should_trigger": true|false}]`, 8-10 positive and 8-10 negative
(`SKILL.md:339-347`).

The guidance on writing those queries is unusually specific and directly usable
(`SKILL.md:348-358`): queries must be realistic and detailed — file paths, job context,
company names, casual speech, typos — not abstract. Negatives must be **near-misses**:
"don't make should-not-trigger queries obviously irrelevant... The negative cases should
be genuinely tricky."

**What it would take to use on shirabe.** Roughly: 20 queries per skill, human-reviewed
via the bundled `assets/eval_review.html`, then one background `run_loop` per skill. For
`execute`, the positive set writes itself from the incident — "here's the plan doc, go
implement it", "work through this plan for me", "implement everything in
docs/plans/PLAN-foo.md" — and the negative set is where the `execute`/`work-on` boundary
gets tested, since single-issue phrasings must go to `work-on`. Running the two skills'
eval sets against each other would surface the collision in Finding 4 quantitatively.

**Caveat, from `SKILL.md:398-400`:** the loop measures the ceiling of *description
quality*. It cannot measure past the competence filter, because prompts that the model
handles directly do not trigger skills regardless of description. A `run_loop` score of
100% on trigger evals would not by itself prove the incident cannot recur, because the
incident's prompt arrived mid-session with momentum behind it, not as a cold opening
query.

### 7. `claude plugin eval` is a different, first-party system — and shirabe cannot use it today

**Confirmed.** `claude plugin --help` lists:

> `eval [options] [target]` — Run eval cases (`evals/**/case.yaml` or `evals/**/prompt.md`
> + `graders/*.md`) against a plugin and report scored results. Target is a path, a plugin
> name, or a `plugin@marketplace` id — installed and skills-dir plugins both resolve (and
> add a no-plugin baseline arm)

The no-plugin baseline arm is the interesting part: it is the same with/without
comparison `skill-creator` builds by hand, done by the CLI.

Shirabe has 18 `evals/` directories (one per skill, under
`public/shirabe/skills/*/evals/`). A `find` across the whole repo for `case.yaml` and
`graders` returns **nothing**. Every suite is `evals.json` — the `skill-creator` schema,
not the `claude plugin eval` schema. So `claude plugin eval` cannot run shirabe's suites
without a format migration.

**The more consequential finding is what the suites test.** Every prompt in
`public/shirabe/skills/execute/evals/evals.json` begins with an explicit slash command:

```json
"prompt": "/execute skills/execute/evals/fixtures/plans/PLAN-diamond-test.md"
"prompt": "/work-on skills/execute/evals/fixtures/plans/PLAN-multi-pr-test.md"
```

The expectations that follow are all about post-invocation behavior — enum re-validation,
running `scripts/preflight.sh`, `koto init` with the right template, driving the
orchestrator loop through `orchestrator_setup -> spawn_and_await -> pr_finalization ->
plan_completion`.

**Shirabe's eval suite presupposes that the skill has already fired.** There is no
coverage of the decision the incident actually got wrong. That is the single most
actionable gap this round found, and it is cheap to close: trigger evals are 20 JSON lines
per skill, not fixtures and orchestrator harnesses.

### 8. Shirabe ships no hooks; the workspace already runs them

**Confirmed.** `public/shirabe/.claude-plugin/plugin.json` declares `name`, `description`,
`version`, `author`, `homepage`, `repository`, `license`, `skills`, `keywords` — and **no
`hooks` key**. `grep -n hooks public/shirabe/install.sh` returns nothing. `SessionStart`
appears nowhere in the repo except a design document
(`docs/designs/current/DESIGN-session-work-summary.md`) and this exploration's own scope
file. Shirabe currently has no way to put anything in a context window that retrieval did
not put there.

Superpowers proves the capability exists for plugins: `hooks.json` at the plugin root plus
a script, and the plugin injects at every startup, clear, and compact.

**The workspace is already doing this, at the wrong end of the session.**
`.claude/settings.json` at the instance root registers a `PreToolUse` hook on `Bash`
(`gate-online.sh`) and a `Stop` hook (`workflow-continue.sh`). That Stop hook is a close
cousin of what this exploration wants:

```
# Checks if there's an active workflow state file with incomplete work.
# If so, nudges the agent with a non-blocking reminder about the controller.
# The agent decides whether to continue or stop -- this avoids infinite loops.
```

It scans `$CWD/wip/*-state.json`, and if any issue is not `completed`/`ci_blocked` it
returns `{"decision": "block", "reason": "..."}` with a message that ends "If you're
intentionally stopping... go ahead."

This is a working, in-production instance of the "strong guidance, not hard enforcement"
posture the user asked for, written by this workspace, in this workspace. Two limits: it
fires at `Stop`, after the work has already been done the wrong way; and it keys on a
state file that only exists once a sanctioned workflow has already started — so in the
incident it would never have fired at all, because no `koto` session and no state file
were ever created.

### 9. The workspace's own authoring doctrine already reached this conclusion

**Confirmed.** `tsukumogami:skill-authoring`
(`/home/dgazineu/.claude/plugins/cache/tsukumogami/tsukumogami/0.1.0/skills/skill-authoring/SKILL.md:12-30`)
opens with:

> Skills are **passive reference material** that commands and phases selectively apply.
>
> Skills do NOT:
> - Trigger themselves
> - Execute workflows
> - Make decisions about when to apply rules

and then, under a heading literally titled "The Skill Triggering Problem":

> **Problem we solved:** ... nothing guarantees the LLM invokes a separate validator skill.
>
> **Solution:** Unified `design-doc` skill contains ALL rules. Command phases explicitly
> say "Invoke the `design-doc` skill and validate against phase-1 requirements."
>
> **Anti-pattern:** ... LLM skipping the "invoke validator" instruction

The workspace concluded years-of-practice ago that skill self-triggering is unreliable and
that the fix is an outer layer that names the skill explicitly. But the fix was only
applied *inside* a workflow — a phase file naming a skill it depends on. Nothing applies
it at the entry point, where a human types "execute the plan" and no outer layer exists
yet to do the naming.

### 10. Body size, as a secondary factor

**Confirmed** line counts: `superpowers/executing-plans` 64 lines; `shirabe/work-on` 291;
`shirabe/plan` 581; `shirabe/execute` 716. `skill-creator/SKILL.md:96` advises keeping
SKILL.md under 500 lines and adding a hierarchy layer beyond that.

**Inference, low confidence:** this does not affect triggering (the body is not read at
selection time), but it plausibly affects follow-through — an agent that fires `execute`
and meets 716 lines has a larger commitment in front of it than one that meets 64, and
the autonomy mandate it needs is at line 574.

---

## Implications

**The description fix and the enforcement mechanism are two different problems, and both
are real.** `execute`'s description is genuinely defective by every published standard —
superpowers', `skill-creator`'s, and shirabe's own house pattern that ten sibling skills
follow. Fixing it is cheap, uncontroversial, and should happen regardless of what
mechanism the exploration lands on. But Finding 4 shows the incident would not have been
prevented by a good description, because `work-on` already had one and also did not fire.
Treat the description work as necessary hygiene and a measurement baseline, not as the
mechanism.

**The mechanism has to intervene at recognition time, not awareness time.** The Red Flags
table is the design pattern to steal: enumerate the specific rationalizations that
precede the failure ("I'll just build a task list", "this plan is simple enough to do
directly", "spinning up koto is overkill for this") and put rebuttals next to them, in
the context window, before the user's first message. Awareness was never the problem —
the incident agent had `/execute` in its skill list the whole time and admitted the miss
when asked directly.

**Shirabe needs to start shipping hooks.** This is the largest capability gap. Superpowers
demonstrates the exact mechanism (`hooks.json` + a script emitting
`hookSpecificOutput.additionalContext`), it is ~50 lines of bash, and it is the only path
by which shirabe can influence a context window that retrieval did not shape. It also
answers the "works for both a human `/execute` and a `niwa dispatch` launch" requirement
for free, because `SessionStart` fires either way. Note the `matcher: startup|clear|compact`
detail — re-firing on compact is what keeps the policy alive through a long autonomous run,
which is precisely the shape of run the incident was.

**The precedence convention favors the workspace-policy requirement.** `using-superpowers`
concedes that CLAUDE.md outranks skills. An org owner declaring workflow policy in
CLAUDE.md therefore sits at the top of an already-established order. A hook-injected
shirabe policy block and a CLAUDE.md declaration are complementary: the hook guarantees
presence, the CLAUDE.md declaration provides the authority. The design should probably
have the hook *read* an org-owner declaration rather than hardcode a policy.

**Trigger evals should be built before any description is rewritten.** `run_loop` measures
what the exploration is trying to change, shirabe already has the eval directory layout to
hang them on, and without a baseline any description rewrite is unfalsifiable. The
`execute`/`work-on` boundary in particular needs a shared negative set, since each skill's
positives are the other's near-miss negatives.

**Do not assume the existing eval investment covers this.** Eighteen eval suites, hundreds
of fixtures, and every single prompt starts with an explicit slash command. The suite is
strong evidence the skills behave correctly once invoked and zero evidence about whether
they get invoked. Anyone arguing "we already have evals" should be pointed at
`skills/execute/evals/evals.json`.

**`claude plugin eval` is worth adopting but is a separate decision.** Its no-plugin
baseline arm is exactly the comparison shirabe wants, and it targets an installed plugin
by `plugin@marketplace` id, which fits shirabe's distribution. But adopting it means
migrating 18 suites from `evals.json` to `case.yaml` + `graders/`, which is its own body of
work and should not block the trigger question.

---

## Surprises

**Shirabe's own workspace already documented this failure mode and shipped a partial fix
for it.** `tsukumogami:skill-authoring` states flatly that skills do not trigger
themselves, names it "The Skill Triggering Problem", and prescribes an outer layer that
explicitly invokes the skill. That doctrine was applied to phase files and never to the
session entry point. The exploration is, in a real sense, finishing an argument the
workspace started and dropped.

**`work-on` has a near-ideal description and still did not fire.** This inverts the round's
starting assumption. The lead's framing was that `execute`'s description mentions autonomy
and was ignored anyway, therefore descriptions have a low ceiling. The evidence supports
the conclusion but not that reasoning — `execute`'s description was never a well-formed
trigger, so the incident says little about it. The stronger version of the argument is
`work-on`: a description that names eight trigger verbs and explicitly claims "a whole
plan" also failed to fire on "execute this plan". That is the real evidence for a ceiling.

**The "explicit autonomy mandate" in `execute`'s description is a pointer to text that
cannot exist yet at decision time.** The mandate is at `SKILL.md:574-605`, in the body.
The body is loaded only when the skill fires. So the mandate is entirely downstream of the
decision it was cited as evidence against. Naming a rule in a description does not make
the rule operative — it only makes the description longer and worse at the one job the
field has.

**The workspace already runs an agentic nudge hook, and its comments read like a design
note for this exploration:** "nudges the agent with a non-blocking reminder... The agent
decides whether to continue or stop -- this avoids infinite loops." That is the strong-
guidance posture, already implemented, already tuned for the loop hazard. It is at the
wrong lifecycle event and keys off state the incident never created — but it is a
precedent, not a greenfield.

**Superpowers explicitly exempts dispatched subagents from its meta-rule.** The
`<SUBAGENT-STOP>` block is the first thing in the file. The exploration's scope requires
the opposite behavior for `niwa dispatch`, so the reference implementation cannot be copied
wholesale on this point. Someone should think about why superpowers made that call before
overriding it — most likely it is because a subagent dispatched to run three greps should
not be forced through brainstorming, which is a real concern, and the distinction wanted is
task breadth rather than dispatch mechanism.

**Operational note, kept out of the artifact detail:** the instance-root
`.claude/settings.json` has a live GitHub personal access token in its `env` block. Worth
flagging to the user out of band; not a finding for this exploration and deliberately not
quoted here.

---

## Open Questions

1. **Can `SessionStart` `additionalContext` reach a `niwa dispatch` worker?** Superpowers'
   hook fires on `startup|clear|compact` for a normal session. A dispatched worker boots
   rooted in a fresh niwa instance; whether that path emits `SessionStart` with the same
   matcher, and whether plugin hooks are loaded before the dispatch prompt is processed,
   needs verification against niwa's dispatch implementation rather than assumption.

2. **What is the right trigger surface for a mid-session `/execute`?** The incident agent
   was told to execute a plan partway through a session. `SessionStart` covers cold starts
   and compaction; it does not cover a turn 40 instruction. Is there a `UserPromptSubmit`
   hook that could pattern-match plan-execution intent, and does the harness expose one
   with context injection? This decides whether the mechanism is one hook or two.

3. **How does a hook distinguish "dispatched to run a plan" from "dispatched to do one
   narrow thing"?** Required for the `niwa dispatch` half of the scope and the point where
   superpowers gave up. Does the dispatch brief carry enough structure to key on, or would
   `niwa dispatch` need to pass an explicit signal?

4. **Should `execute` and `work-on` keep overlapping PLAN claims?** `work-on`'s description
   claims plan-scale work; `execute` claims it is the plan-scale owner and delegates to
   `work-on`. Trigger evals will quantify the confusion but not decide the boundary. This
   is a product question for the user: does `work-on` keep its PLAN mode?

5. **What does an org owner actually write?** The scope says "declarable as workspace
   policy by an org owner." A CLAUDE.md section? A key in `.niwa/workspace.toml`? A shirabe
   config file the hook reads? The precedence argument in Finding 5 favors CLAUDE.md, but
   CLAUDE.md is prose an agent interprets, whereas a hook reading a structured declaration
   is deterministic. Likely both, with the hook rendering the declaration into the injected
   block.

6. **Does trigger-eval score actually predict incident-shaped behavior?** `run_loop`
   evaluates cold single queries. The incident was a mid-session instruction with
   conversational momentum behind it. It may be worth building a second, harder eval —
   a multi-turn scenario ending in "ok, go implement it" — to check whether description
   improvements survive context. No existing tooling does this.

7. **Do the 716 lines of `execute` hurt follow-through once it fires?** Untested. Separable
   from the trigger question and only worth pursuing if post-invocation abandonment turns
   out to be a real second failure mode.

---

## Summary

The description field is the sole input to skill selection, but it is filtered by a
documented rule that Claude only consults skills for tasks it cannot easily handle itself
(`skill-creator/SKILL.md:396-400`) — and executing a plan looks like a task an agent can
handle with Read, Edit, and a task list, which is why `execute`'s architecture-inventory
description and `work-on`'s near-ideal trigger phrasing both failed to fire on the same
prompt. This means description repair is necessary hygiene with a measurable ceiling, and
the actual mechanism has to intervene at recognition time the way superpowers does — by
bypassing retrieval entirely with a `SessionStart` hook that injects a rationalization
table, a capability shirabe does not currently have since its `plugin.json` declares no
hooks and all 18 of its eval suites test post-invocation behavior with prompts that start
with an explicit slash command. The biggest open question is whether a `SessionStart`
injection reaches a `niwa dispatch` worker and a mid-session instruction at all, since
superpowers explicitly exempts dispatched subagents from its own meta-rule — the exact case
this exploration must cover.
