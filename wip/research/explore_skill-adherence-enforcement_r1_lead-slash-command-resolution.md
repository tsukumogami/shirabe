# Lead: Why did a bare `/execute` fail to resolve to `shirabe:execute`, and what invocation surfaces does Claude Code actually offer a plugin?

Investigated 2026-08-15 against Claude Code **v2.1.233** and shirabe **0.16.1-dev**.
All harness-behavior claims below are either quoted from official docs at
`code.claude.com/docs` or established by a live probe run on this machine. Where I
am inferring, I say so.

## Findings

### 1. Bare aliases for plugin skills DO exist — the scope assumption is wrong

The official skills doc states it explicitly (fetched from
`https://code.claude.com/docs/en/skills`, section "How a skill gets its command name"):

> In a plugin skill, the frontmatter `name` replaces the directory name in the last
> segment of the command, so `my-plugin/skills/review/SKILL.md` with `name: fancy`
> becomes `/my-plugin:fancy`. **The bare `/fancy` also invokes the skill unless another
> command already uses that name.** Before v2.1.216, the frontmatter name replaced the
> whole command name, so the menu showed `/fancy` without the plugin prefix and
> `/my-plugin:fancy` didn't autocomplete.

I verified this empirically rather than trusting the prose. I built a throwaway plugin
at `/home/dgazineu/.claude/jobs/4d06ff3a/tmp/bareplug/` with
`.claude-plugin/plugin.json` declaring `"name": "zzzplug"`, `"skills": "./skills/"`,
and one skill `skills/zzzbaretest/SKILL.md` whose entire body is
`Reply with exactly the string PROBE_SKILL_LOADED`. Then:

```
claude -p "/zzzbaretest" --plugin-dir .../bareplug --output-format json
→ "result":"PROBE_SKILL_LOADED", num_turns 1
```

The bare, unqualified name resolved to a plugin skill. **A plugin does not need a
`commands/` directory to own a bare slash command.**

And the decisive one — the same probe against the real skill, run from the workspace
root where shirabe is installed:

```
cd /home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf
claude -p "/execute docs/plans/PLAN-nonexistent-probe.md" --output-format json --max-turns 1
→ num_turns 2, cache_creation_input_tokens 41901, stop_reason "tool_use"
```

41,901 tokens of cache creation is the `execute` SKILL.md body entering context. **Bare
`/execute` resolves to `shirabe:execute` today, at the workspace root, on this
machine.** The lead's premise — that shirabe having `skills/` and no `commands/` is why
`/execute` didn't resolve — is not the explanation.

Confirming there is no collision that would suppress the alias: I searched every
installed plugin cache and every project/personal command directory
(`/home/dgazineu/.claude/commands/` and `~/.claude/skills/` are both **empty**). The
only `execute` skill directories on disk are shirabe's own, across versions
0.13.1-dev through 0.16.1-dev. Nothing else claims the name.

### 2. What actually happens on an unknown slash command: a silent, exit-0 no-op

This is the most operationally important finding and it is not documented anywhere I
could find. Probe:

```
cd /home/dgazineu/.claude/jobs/4d06ff3a/tmp
claude -p "/zzznonexistentprobecmd hello world" --output-format json --max-turns 2
```

Full result payload:

```json
{"is_error":false, "num_turns":0, "stop_reason":null, "total_cost_usd":0,
 "usage":{"input_tokens":0,"output_tokens":0,...},
 "subtype":"success", "result":"Unknown command: /zzznonexistentprobecmd",
 "duration_ms":32}
```

And the exit code:

```
claude -p "/zzznonexistentprobecmd hello" ... ; echo $?
→ EXIT CODE: 0
```

Read that carefully. When a slash command doesn't resolve:

- **No fuzzy matching.** No nearest-name suggestion, no "did you mean".
- **No passthrough to the model.** `num_turns: 0`, zero input and output tokens, 32ms.
  The model is never invoked. The user's arguments (`hello world`, or a plan path) are
  discarded entirely.
- **It is reported as success.** `is_error: false`, `subtype: "success"`, exit code 0.
  The failure exists only as the literal string in the `result` field.

For a human at an interactive prompt this is a visible, recoverable annoyance. For any
programmatic caller — `niwa dispatch`, CI, a parent agent shelling out to `claude -p` —
this is a **silent failure that is indistinguishable from success**. A wrapper checking
exit status or `is_error` sees a clean run that did nothing.

### 3. The dispatch surface never presents a slash command at all

`niwa dispatch` is Go, at
`/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/public/niwa/internal/cli/dispatch.go`.
Two things matter.

**(a) The sanctioned dispatch prompt is prose, not a command.** The `/dispatch` skill at
`/home/dgazineu/dev/niwaw/tsuku/.claude/skills/dispatch/SKILL.md:86` templates the
invocation as:

```
niwa dispatch "Read <abs-path-to-brief> for your complete task brief, then implement it. <one-line summary>" \
```

A dispatched worker receives a prose instruction to read a brief. There is no slash
command anywhere in that path, so **there is nothing for the harness to resolve** —
skill selection on the dispatch surface is 100% model discretion from descriptions in
context. Whatever mechanism this exploration designs, on the dispatch surface it cannot
rely on slash resolution at all.

**(b) Even if a caller passed one, a prefix can displace it.** `dispatch.go:425` sets
`promptPrefix = keepAliveArmingInstruction`, and the final argv is prefix-then-body
(asserted by `dispatch_promptsplit_test.go:45-49`,
`TestComposedArgvIsPrefixThenBody`). `keepAliveArmingInstruction`
(`dispatch_keepalive.go:33`) is a ~600-character paragraph. So
`niwa dispatch "/execute plan.md"` with keep-alive armed produces a prompt whose first
character is `K`, not `/`.

I confirmed a non-position-0 slash is not intercepted: `claude -p "Before you begin:
/zzzbaretest"` produced `num_turns: 2` with an API call, versus `num_turns: 0` and zero
tokens for the harness's slash-interception path. The harness only inspects the slash
command at the start of the prompt.

The prefix is conditional (applied only when keep-alive resolves on *and* remote control
is on), so this is a latent hazard rather than an always-on break — but it means "put a
slash command in the dispatch prompt" is not a reliable mechanism.

### 4. The most likely explanation for the trigger incident: a plugin-enumeration race

`shirabe` is installed at **`local` scope, keyed by `projectPath`** — not user scope.
From `/home/dgazineu/.claude/plugins/installed_plugins.json`, there are **25 separate
`shirabe@shirabe` entries**, one per instance directory:

```json
{ "scope": "local",
  "projectPath": "/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf",
  "installPath": "/home/dgazineu/.claude/plugins/cache/shirabe/shirabe/0.16.1-dev", ... }
```

Every fresh niwa instance is a new directory that must have shirabe installed into it
before its skills exist. And niwa's own source documents exactly this failure, in the
header comment of
`.../public/niwa/internal/cli/dispatch_plugins.go` (function `prewarmDeclaredPlugins`):

> It closes the race where a github-sourced marketplace (e.g. shirabe) is cloned
> asynchronously during a session's own Claude startup and finishes AFTER skill
> enumeration, **leaving that marketplace's skills uninvocable for the whole session.**

That is the mechanism, named in the code, with shirabe as the named example. Combine it
with finding #2 and the incident reconstructs cleanly: session boots in a fresh
instance, shirabe's clone lands after skill enumeration, `/execute` is not a known
command, the harness returns `Unknown command: /execute` at exit 0 having burned zero
tokens — and whatever came next (the prose task description, a follow-up turn) drove a
model with no execute skill in context, which improvised its own loop.

The race was fixed in niwa `2d72419` (2026-06-28, "fix(provisioning): pre-warm declared
Claude plugins on instance provision (#178)"). **I am inferring the incident predates or
otherwise escaped that fix — I did not see the incident's transcript and cannot confirm
this.** The alternative explanation is finding #6 below: the skill resolved fine and the
model simply didn't follow it. Both are live; they are not mutually exclusive.

### 5. `commands/` vs `skills/`: the distinction has largely collapsed

Straight from the skills doc:

> **Custom commands have been merged into skills.** A file at `.claude/commands/deploy.md`
> and a skill at `.claude/skills/deploy/SKILL.md` both create `/deploy` and work the same
> way. Your existing `.claude/commands/` files keep working. Skills add optional features:
> a directory for supporting files, frontmatter to control whether you or Claude invokes
> them, and the ability for Claude to load them automatically when relevant.

Skills are the superset. A `commands/` entry is a single markdown file with a
`description`; a skill is a directory that can carry scripts, references, and the
invocation-control frontmatter. **Shirabe loses nothing by having no `commands/`.**

The vercel plugin at
`/home/dgazineu/.claude/plugins/cache/claude-plugins-official/vercel/0.45.1/` is
instructive: it ships **both**, and the `commands/*.md` files are *generated from the
skills* — each has a sibling `.md.tmpl` with byte-identical frontmatter, and
`commands/deploy.md` carries the comment `<!-- Sourced from bootstrap skill: Preflight -->`.
Both `skills/bootstrap/SKILL.md` and `commands/bootstrap.md` exist. This looks like
backward-compatibility scaffolding for older clients, not a capability shirabe lacks.
(Inference from file layout; I did not find vercel's build script.)

### 6. What the model receives — and the honest reading of "the model ignored it"

The docs table on invocation control:

| Frontmatter | You can invoke | Claude can invoke | When loaded into context |
| :--- | :--- | :--- | :--- |
| (default) | Yes | Yes | **Description always in context**, full skill loads when invoked |
| `disable-model-invocation: true` | Yes | No | Description not in context, full skill loads when you invoke |
| `user-invocable: false` | No | Yes | Description always in context, full skill loads when invoked |

So by default the model sees **the full `description` field of every skill**, namespaced,
plus the Skill tool's own framing. I can see this directly in my own session: shirabe's
skills arrive as `shirabe:execute` with the complete multi-sentence description, verbatim
from the SKILL.md frontmatter. Names alone would not be enough for routing; full
descriptions are what the model routes on.

Shirabe's `execute` skill (`skills/execute/SKILL.md`) sets **neither**
`disable-model-invocation` nor `user-invocable`. It is fully model-invocable and its
description is always in context.

The Skill tool description itself constrains model-side invocation: *"Plugin skills use
`plugin:skill`"* and *"Only names from the listing (or that the user typed explicitly) are
valid."* So the bare alias is a **user-typing affordance**; the model is steered toward
the namespaced form. An agent asked in prose to "execute the plan" must pick
`shirabe:execute` out of a listing of ~100 skills, on description quality alone.

And the docs name the exact failure this exploration is about:

> If a skill seems to stop influencing behavior after the first response, the content is
> usually still present and the model is choosing other tools or approaches. **Strengthen
> the skill's `description` and instructions so the model keeps preferring it, or use
> [hooks](/docs/en/hooks) to enforce behavior deterministically.**

That is the official answer to "agents improvise instead of using the skill," and it maps
onto the user's stated spectrum: description/prose strengthening at the soft end, hooks at
the hard end.

### 7. Aliases, collision rules, and the plugin.json schema

**No alias key exists.** The plugin.json schema (from
`code.claude.com/docs/en/plugins-reference`) supports `name`, `displayName`, `version`,
`description`, `author`, `homepage`, `repository`, `license`, `keywords`, `metadata`,
`defaultEnabled`, `skills`, `commands`, `agents`, `workflows`, `hooks`, `mcpServers`,
`outputStyles`, `lspServers`, `userConfig`, `channels`, `dependencies`, and
`experimental`. There is **no `aliases` key and no way to declare an extra invocation
name.** A plugin gets exactly one bare candidate per skill, derived from the frontmatter
`name` or the directory name.

**Collision resolution.** Documented for the non-plugin levels:

> Across levels, enterprise overrides personal, and personal overrides project. [...] A
> skill at any of these levels also overrides a bundled skill with the same name, but not
> the bundled skill's aliases. [...] **Plugin skills use a `plugin-name:skill-name`
> namespace, so they can't conflict with other levels.** [...] if a skill and a command
> share the same name, the skill takes precedence.

Plugin-vs-plugin bare collision is *not* documented. I tested it: a second probe plugin
`zzzplugtwo` with an identically-named `zzzbaretest` skill, both loaded:

```
claude -p "/zzzbaretest" --plugin-dir .../bareplug --plugin-dir .../bareplug2
→ "result":"PROBE_SKILL_LOADED"
```

**First-registered wins the bare alias**; the loser keeps only its namespaced form. This
matches the documented LSP precedent ("the first server registered handles files with that
extension"). I did not determine what fixes registration order — `--plugin-dir` argument
order is the obvious candidate but I only tested one ordering, so treat "first wins" as
confirmed and "order is caller-controlled" as unverified.

**Actual collisions in this workspace.** I diffed the skill directory listings:

- `shirabe` ∩ `tsukumogami` = **`release`, `roadmap`** — these two bare names are contested.
- `shirabe` ∩ `superpowers` = none.
- `shirabe` ∩ `koto-skills` = none.
- **`execute` collides with nothing.** Nor do `plan`, `design`, `prd`, `explore`, `work-on`.

The scope brief flagged `tsukumogami:implement` and `tsukumogami:legacy-work-on` as
overlapping. They overlap *semantically* — same job, different name — but they do not
contest a bare name. That distinction matters: `/implement` and `/execute` both resolve
cleanly and to different plugins, so a user or agent reaching for "run the plan" has two
valid, differently-named, non-conflicting entry points. **The routing hazard here is
semantic ambiguity, not name collision.**

## Implications

**The acute bug is almost certainly a provisioning race, not a plugin-shape defect.**
Shirabe needs no `commands/` directory. Adding one would fix nothing, because `/execute`
already resolves. Any redesign premised on "shirabe can't own a bare slash command" should
be dropped.

**The silent-success failure mode is the real infrastructural finding, and it is worth
fixing independently of this exploration.** `Unknown command: /X` at `is_error: false`,
exit 0, zero tokens means every programmatic caller of `claude -p` in this workspace can
be handed a no-op it will record as a success. niwa's pre-warm (#178) closes the race that
*causes* the unknown command; it does not make the unknown command *detectable*. A
dispatch-side guard that greps the result for `Unknown command:` — or, better, asserts the
expected skill is installed before launch — would convert a silent no-op into a loud
failure. That is cheap and orthogonal to whatever adherence mechanism gets designed.

**The two surfaces in scope need genuinely different mechanisms.** The human-typed
`/execute` surface is a *resolution* problem: when it resolves, the full skill body enters
context and stays there, which is strong. The `niwa dispatch` surface is a *selection*
problem: the worker gets prose, and nothing about the harness will route it to
`shirabe:execute`. A single mechanism spanning both must therefore act on context or via
hooks, not on slash syntax.

**For the dispatch surface specifically, three declarable levers exist and only one is
per-repo.** (a) The subagent `skills:` frontmatter key preloads *full skill content* at
startup, not just descriptions — but that binds to agent definitions, not dispatched
top-level sessions. (b) Hooks are the documented deterministic lever and are declarable in
workspace settings. (c) Injected system-prompt or CLAUDE.md text is the soft lever and is
what the user's stated "strong guidance over hard enforcement" preference points at. Since
niwa already materializes `.claude/settings.json` per instance and already pre-warms
plugins there, **niwa's instance provisioning is the natural place to declare workspace
policy once and have it apply to every dispatched worker** — which satisfies the brief's
"declarable as workspace policy by an org owner" constraint without per-repo re-derivation.

**Description quality is a real lever, not a cop-out.** The model routes on full
descriptions, and the official guidance for exactly this symptom is "strengthen the
description, or use hooks." Shirabe's `execute` description is long and heavy on internal
vocabulary — "wip-yaml-md state projection over the durable home PR", "the three exit-path
bindings", "the six security surfaces". Those phrases are meaningless as routing signal to
a model deciding whether "implement this plan" means `/execute`. Compare `work-on`, whose
description ends with a plain-language trigger list: *"Use when asked to work on,
implement, fix, build, tackle, pick up, close, or ship work."* That is what a routing
description should look like. Rewriting `execute`'s description to lead with triggers
rather than architecture is a low-cost, high-leverage change worth evaluating on its own.

## Surprises

**The premise didn't hold.** I expected to confirm that `/execute` fails and explain why.
It resolves. Everything downstream of "shirabe has no commands/ directory, therefore no
bare slash command" is a dead end.

**`is_error: false` on an unknown command genuinely surprised me.** A command that
consumed zero tokens, ran zero turns, and did nothing at all is reported as a successful
run with exit code 0. I would not have predicted the harness reports it that way, and I
suspect nobody wrapping `claude -p` in this workspace has accounted for it.

**niwa's source already documents this exact bug, naming shirabe.** The
`prewarmDeclaredPlugins` comment describes "leaving that marketplace's skills uninvocable
for the whole session" with shirabe as the worked example. Someone hit this before, fixed
the race in June, and the incident under investigation looks like the same failure. Worth
checking whether the trigger incident predates 2026-06-28 before designing around it.

**Plugin installs are `local`-scoped per directory.** 25 shirabe entries, one per instance
path. Every new niwa instance re-installs. This makes the workspace structurally more
exposed to enumeration timing than a user-scope install would be, and it is a design
choice worth revisiting on its own terms.

**Bare aliases are recent.** The behavior changed at v2.1.216 and again at v2.1.220. Any
mechanism resting on bare-alias resolution is resting on young, moving behavior.

## Open Questions

1. **What CLI and shirabe version ran the trigger incident, and what was its instance
   provisioned from?** This decides between the two explanations. If it predates niwa
   #178 (2026-06-28), the race explains it and the fix already shipped. If it postdates,
   the skill loaded and the model ignored it — a much harder and more interesting problem.
   The session transcript would settle this in minutes. **Needs human input; I could not
   locate the incident.**

2. **Was `/execute` actually typed, or was the instruction prose?** "A session was told to
   execute a plan" is ambiguous between the two surfaces, and they fail for different
   reasons.

3. **Can workspace-level policy reach a dispatched top-level session?** The `skills:`
   preload key is documented for subagent definitions. Whether an equivalent exists for a
   top-level session launched by `claude --bg` — via settings.json, `--append-system-prompt`,
   or otherwise — I did not determine. This is the crux of the "declarable as workspace
   policy" requirement and should be round 2's first question.

4. **Which hook events can gate skill adherence?** I confirmed hooks are the documented
   deterministic lever but did not read the hooks reference. Whether a hook can observe
   "session started with a plan-shaped task and has not invoked `shirabe:execute`" and
   intervene is unknown.

5. **What determines plugin registration order for bare-alias collisions?** First-wins is
   confirmed; the ordering rule is not. This matters concretely for the contested
   `release` and `roadmap` names between shirabe and tsukumogami — today it is unclear
   which plugin owns bare `/release`, and it may not be stable.

## Summary

Bare `/execute` resolves to `shirabe:execute` today on v2.1.233 — I confirmed it by probe
at the workspace root, so shirabe's lack of a `commands/` directory is not the cause; the
likely culprit is a plugin-enumeration race that niwa's own source documents by name and
fixed in June, made invisible because an unknown slash command returns `is_error: false`,
exit 0, and zero model turns. The two surfaces in scope fail differently and need
different mechanisms: `niwa dispatch` passes prose with no slash command at all, so on that
path skill selection is pure model discretion over descriptions, and the only levers are
hooks, preloaded skill content, or injected context declared once in niwa's per-instance
settings. The biggest open question is which explanation actually produced the trigger
incident — a race that is already fixed, or a model that had the skill in context and
improvised anyway — and only the incident's transcript and version can settle that.
