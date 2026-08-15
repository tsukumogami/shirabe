# Lead: How does `niwa dispatch` build the worker's prompt, and what could be injected into it?

All paths below are absolute. Go source read at `public/niwa/internal/cli/` and
`public/niwa/internal/workspace/` in the workspace instance
`/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/`.
Everything cited is public (niwa repo + the live instance's own materialized
`.claude/settings.json`).

## Findings

### 1. The prompt is assembled in exactly two pieces, and niwa already owns one of them

The whole prompt pipeline is short and deliberately factored into a
**niwa-authored prefix** plus the **caller's body**. That factoring is the
single most important fact for this exploration: the injection point already
exists and is already used in production.

`/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/public/niwa/internal/cli/dispatch.go`,
`runDispatch`, step (9d), lines 421-434:

```go
	promptPrefix := ""
	keepAliveArmed := false
	if resolveDispatchKeepAlive(dispatchKeepAlive, hostGlobal, inst) {
		if remoteControlEnabled(rcInjected, inst) {
			promptPrefix = keepAliveArmingInstruction
			keepAliveArmed = true
		} else {
			fmt.Fprintf(cmd.ErrOrStderr(), "niwa dispatch: %s\n", keepAliveNonRCWarning)
		}
	}

	if err := dispatchLaunch(cmd.Context(), instancePath, promptPrefix, prompt, passthrough, nil); err != nil {
		return fmt.Errorf("niwa: error: launching dispatch worker: %w", err)
	}
```

`prompt` here is purely the caller's string (positional arg, or the interactive
terminal capture at step 3b). `promptPrefix` is niwa's. They travel apart all
the way to the launcher and are only joined at exec.

`/home/.../public/niwa/internal/cli/dispatch_launcher.go`, `realDispatchLaunch`,
lines 42-69:

```go
func realDispatchLaunch(ctx context.Context, instanceDir, prefix, body string, passthrough, env []string) error {
	if body == "" {
		return fmt.Errorf("dispatch: empty prompt")
	}
	...
	prompt := prefix + body
	if len(prompt) > maxArgStringBytes || strings.ContainsRune(body, 0) {
		token, err := spillToken()
		...
		path, err := spillPrompt(instanceDir, token, body)
		...
		prompt = composeSpillPointer(prefix, path, body, token)
	}
```

and `buildClaudeBgArgs` (same file, lines 112-118):

```go
func buildClaudeBgArgs(prompt string, passthrough []string) []string {
	args := make([]string, 0, 2+len(passthrough))
	args = append(args, "--bg")
	args = append(args, passthrough...)
	args = append(args, prompt)
	return args
}
```

**What reaches the worker, in order:** `claude --bg [--model X] [--permission-mode Y]
[--agent Z] [--name slug] [--settings <RC json>] "<niwa prefix><caller body>"`. One
single argv element for the whole prompt, never shell-interpolated. The prefix is
always first; that order is pinned by a test,
`TestComposedArgvIsPrefixThenBody` in
`/home/.../public/niwa/internal/cli/dispatch_promptsplit_test.go`, whose comment
gives the design reason: the niwa text is written as a preamble ("before starting
the task below" ... "then proceed with the task"), and putting the body first
"would put untrusted text ahead of niwa's own framing on every path."

The existing prefix content, `keepAliveArmingInstruction` in
`/home/.../public/niwa/internal/cli/dispatch_keepalive.go` lines 33-35, is a
fixed constant with no untrusted input. Its doc comment (lines 14-22) is worth
reading in full for this exploration, because it is niwa's own recorded
reasoning about *which channel reaches a dispatched worker*:

> B1 is not viable for a dispatched worker: the `niwa instance from-hook`
> SessionStart entry is materialized only into the WORKSPACE-ROOT
> .claude/settings.json (root_materializer.go), which a `claude --bg` worker
> rooted in the instance directory does not load -- and that hook's guard
> deliberately no-ops for a cwd inside an instance (the re-entrancy check in
> instance_from_hook.go). The prompt prepend is the one channel niwa controls
> end to end for a dispatched worker, so B2 is the shipped channel.

That paragraph is effectively a prior art note for a workflow mandate: niwa has
already asked "how do I reliably put a sentence in front of a dispatched
worker?", and answered "prompt prefix."

### 2. The one line of code that would prepend a workflow mandate

`dispatch.go:421`. Today:

```go
	promptPrefix := ""
```

An unconditional mandate is `promptPrefix := workflowMandateInstruction`, with the
keep-alive block below becoming `promptPrefix += keepAliveArmingInstruction`
(order is a choice; keep-alive's text reads as an opening preamble so it probably
stays first). Nothing else in the pipeline needs to change:

- **Size:** nothing breaks. There is no longer any reserve to keep honest. The
  comment block at `dispatch.go:101-107` records that the old
  `dispatchPromptReserve` / `maxPromptBytes` pair was deliberately deleted: "There
  is deliberately no reserve here any more... Making the decision a route rather
  than a refusal dissolves that." A prompt that no longer fits after a prepend is
  *spilled*, not refused — see section 4.
- **Argv safety:** a fixed constant carries no untrusted input and rides the same
  single argv element, preserving the no-shell-interpolation guarantee (D8).
- **Emptiness guard:** already binds to `body`, not to `prefix+body`
  (`dispatch_launcher.go:43`). `TestEmptyPromptGuardBindsToBodyNotTheComposedString`
  exists precisely so a long prefix cannot mask an empty task.

**What would break / needs care:**

1. **`dispatch.go:401-404` is already stale.** The step-(9d) comment still says
   "its fixed size was already reserved by step (1): maxPromptBytes is the exec
   ceiling minus dispatchPromptReserve" — but both constants were removed (see
   `dispatch.go:101-107`, and `grep` finds them only inside that stale comment).
   Anyone editing this area should fix the comment or they will reason from a
   budget that does not exist.
2. **The spill path composes its own framing.** `composeSpillPointer` in
   `/home/.../public/niwa/internal/cli/dispatch_spill.go` lines 160-180 writes
   `prefix` first, then a hard instruction that "It is your complete task; nothing
   else in this message is." A mandate placed in `prefix` survives the spill (good,
   and it is why prefix/body are kept apart), but the mandate's wording must not
   claim to *be* the task, or it will collide with that sentence.
3. **Tests that pin exact argv.** `dispatch_promptsplit_test.go` and parts of
   `dispatch_test.go` assert the composed string starts with
   `keepAliveArmingInstruction`; an unconditional prepend in front of it flips
   `strings.HasPrefix` to false and those tests need updating.
4. **Every dispatch pays the tokens.** The keep-alive instruction is ~700 bytes and
   only rides armed dispatches. An unconditional mandate rides all of them,
   including trivial ones ("fix this typo"), which argues for a *short* mandate that
   points at a skill rather than restating a workflow.
5. **Self-dispatch recursion.** A dispatched worker can itself run `niwa dispatch`
   (`ClassifyCwd` resolves to the shared workspace root and creates a sibling, see
   `dispatch.go:206-221`). A mandate prepended by niwa therefore propagates
   automatically down the whole dispatch tree — which is a feature here, and is
   exactly what the skill-authored brief fails to do.

### 3. Is the prompt otherwise purely the caller's string? Yes.

There is no other place niwa augments the dispatched prompt. Grep for
`--append-system-prompt` / `systemPrompt` in the niwa repo returns only
`docs/designs/archive/DESIGN-niwa-mesh-reliability.md` — the pre-pivot mesh
design that was removed wholesale. The live flag surface (`dispatch.go:24-37`) is
`--label`, `--name`, `--model`, `--permission-mode`, `--agent`, `--detach`,
`--parallel`, `--keep-alive`; `buildDispatchPassthrough` (`dispatch.go:609-624`)
forwards only `--model`, `--permission-mode`, `--agent`, `--name`. The only other
argv niwa ever adds is `--settings <remote-control JSON>` at `dispatch.go:386`.
So: **prefix is the whole of niwa's authorship over the worker's first turn.**

### 4. Size limits and spill/split mechanics — a mandate always fits

- `maxArgStringBytes = 32*4096 - 1` = **131071 bytes**
  (`dispatch.go:78-99`). This is Linux `MAX_ARG_STRLEN` minus the NUL, probed
  directly ("131071 succeeds, 131072 returns E2BIG"), and applied on macOS too so
  the accepted size is identical on both platforms.
- `validateDispatchPrompt` (`dispatch.go:654-660`) has **no size check at all**,
  by design: "Nothing about a prompt's size is the developer's problem."
- When `len(prefix+body) > maxArgStringBytes` (or the body contains a NUL, which
  argv cannot carry at any size), the launcher **spills**: `writeSpillFile` writes
  the body verbatim to
  `<instance>/.niwa/dispatch-prompts/prompt-<8hex>.local.txt` at mode 0600 in a
  0700 directory, and `composeSpillPointer` replaces the argv with prefix + a
  read-this-file instruction + a fenced 4096-byte excerpt
  (`spillExcerptBytes = 4096`), with an unforgeable per-launch fence token minted
  *after* the body is fixed.
- Ordering is explicit in `composeSpillPointer`'s doc comment: "niwa's prepends
  first, then the framing, then the path, then the excerpt last. The untrusted span
  therefore sits between niwa's framing and the end of the message."

**Budget conclusion for a mandate:** there is no budget to fit inside. A mandate of
any reasonable length rides both the normal and the spilled path, and cannot cause
a refusal — the worst case is that a borderline-huge task tips into the spill it
would nearly have hit anyway.

### 5. Plugins: the worker does reliably get shirabe, and it gets them synchronously

`/home/.../public/niwa/internal/cli/dispatch_plugins.go`, `prewarmDeclaredPlugins`
(lines 48-97), runs during provisioning, before launch. It reads the instance's
just-materialized `.claude/settings.json`, then (1) `claude plugin marketplace add
<repo>` for every **github-sourced** marketplace and (2) `claude plugin install
<plugin> --scope local` for every enabled plugin, each bounded by
`prewarmCmdTimeout = 120s`. Its doc comment names the exact race it closes:

> It closes the race where a github-sourced marketplace (e.g. shirabe) is cloned
> asynchronously during a session's own Claude startup and finishes AFTER skill
> enumeration, leaving that marketplace's skills uninvocable for the whole session.

So the shirabe skills are on disk before the worker enumerates. Note it is
**best-effort**: `claude` absent, a CLI error, or unreadable settings degrade to a
warning and the worker falls back to startup install. `--scope local` (not
`project`) is used so niwa's managed `settings.json` stays byte-identical.

**Live confirmation** — the current instance's materialized
`/home/dgazineu/dev/niwaw/tsuku/tsuku+execute_and_work_on_trigger-d36b0bbf/.claude/settings.json`
carries `enabledPlugins: {"shirabe@shirabe": true, "tsukumogami@tsukumogami": true}`
with marketplaces `shirabe` (github `tsukumogami/shirabe` @ `v0.16.0`) and
`tsukumogami` (directory source inside the instance).

### 6. Hooks: the worker gets PreToolUse/Stop but **no SessionStart** — and that is fixable without touching Go

Two different settings files, two different hook sets. Both read live:

| File | hooks present |
|---|---|
| workspace root `/home/dgazineu/dev/niwaw/tsuku/.claude/settings.json` | `SessionStart` → `<abs>/niwa instance from-hook` (timeout 180) |
| instance root `/home/.../tsuku+execute_and_work_on_trigger-d36b0bbf/.claude/settings.json` | `PreToolUse` (matcher `Bash`) → `hooks/pre_tool_use/gate-online.sh`; `Stop` → `hooks/stop/workflow-continue.sh`. **No SessionStart.** |

A `niwa dispatch` worker launches with `cmd.Dir = instancePath`
(`dispatch_launcher.go:89`), so it resolves the **instance** settings: instance
`CLAUDE.md`, instance plugins/marketplaces, instance permissions/env, and the
instance's PreToolUse + Stop hooks. It does **not** see the root's SessionStart
entry, and the guard would no-op anyway
(`sessionStartGuardPasses` part 3, `instance_from_hook.go`: "the launch cwd does
not already resolve inside a niwa instance").

The instance hook set is not hard-coded. `InstallWorkspaceRootSettings` in
`/home/.../public/niwa/internal/workspace/workspace_context.go` (lines 242+ —
note the name is misleading, its doc says it "targets an INSTANCE root") merges
`DiscoverHooks(configDir)`, which walks `<configDir>/hooks/<event>/*.sh`
(`/home/.../public/niwa/internal/workspace/discover.go:21-58`), copies each script
into `<instance>/.claude/hooks/<event>/`, and registers it. Event names are
snake_case → PascalCase via `hookEventMapping`
(`/home/.../public/niwa/internal/workspace/materialize.go:302-310`) with a
`snakeToPascal` **fallback for unmapped events** (`materialize.go:737-740`). The
mapping table lists only `pre_tool_use`, `post_tool_use`, `stop`, `notification`
— but `session_start` falls through the fallback to `SessionStart` correctly.

**Consequence, and I flag this as the most actionable finding after the prefix:**
dropping a `hooks/session_start/mandate.sh` into the workspace config repo
(`dot-niwa`) would materialize a `SessionStart` hook into **every instance**,
including every dispatch-provisioned one, emitting
`hookSpecificOutput.additionalContext` into the worker's context at startup —
with **zero niwa code changes**. That is the B1 channel the keep-alive design
declared "not viable"; it was not viable *for niwa's own hook*, which lives at the
root and self-no-ops. A workspace-authored instance-level hook has no such
constraint. (Inference: I have not executed this; the mechanism is read from
source and corroborated by the live instance's `PreToolUse`/`Stop` entries taking
exactly this path.)

Note the ordering property the ephemeral guide records
(`/home/.../public/niwa/docs/guides/ephemeral-session-instances.md:344-351`):
Claude resolves plugins, marketplaces, hooks and env from the launch directory's
`settings.json` **at startup, before the SessionStart hook runs**. So a
SessionStart-injected mandate arrives after skills are already enumerated — fine
for a mandate, fatal for anything trying to *add* a skill.

### 7. The `/dispatch` skill's brief template has no workflow slot — this is a root cause

The skill is **niwa-owned and embedded in the binary**:
`/home/.../public/niwa/internal/workspace/rootskills/dispatch/SKILL.md`, embedded
via `//go:embed rootskills` in
`/home/.../public/niwa/internal/workspace/root_materializer.go:25` and
materialized to `<workspaceRoot>/.claude/skills/dispatch/SKILL.md`. Live copy
confirmed at `/home/dgazineu/dev/niwaw/tsuku/.claude/skills/dispatch/SKILL.md`.
It is a *project* skill at the root, deliberately independent of plugin
enablement.

Its brief template (SKILL.md step 1, lines 28-42) names exactly six things:

- **Goal** — one or two sentences: what done looks like.
- **Context / decisions** — conclusions from the chat the worker can't see.
- **Pointers to durable artifacts** — pushed files, issue numbers.
- **Acceptance criteria** — how you'll know it's done.
- **Out of scope** — what NOT to touch.
- **Final-message work-in-flight block** — the `=== WORK IN FLIGHT ===` marker.

**There is no slot for which skills or workflows the worker must use.** Not in the
list, not in the launch-command template at step 3, not in the Cautions. The
skill's own framing sentence is "turn the conversation into a brief a competent
stranger could execute cold" — a task description, method unspecified.

The omission is doubly notable because the skill *does* already carry one
mandatory process instruction, and carries it emphatically: step 1a, 23 lines,
"Every brief you write MUST therefore instruct the worker to end its final
message with the standardized work-in-flight block." So the template has room for
a mandate and a precedent for phrasing one — it simply mandates the *reporting*
convention and not the *working* convention. A parallel "step 1b: name the
workflow" is a small, in-idiom edit to a file that ships in the niwa binary and is
re-materialized on every `niwa apply`.

Two structural notes on that fix. It is a niwa release, not a workspace edit:
the root skill is embedded, so changing it means changing niwa and re-applying —
and note step 1a already reaches across into shirabe's `work-summary` component
by reference, so a shirabe reference in the template would not be a new kind of
coupling. And the guidance is advisory: it tells the *coordinator* what to write,
so it degrades whenever the coordinator improvises a `niwa dispatch` call without
invoking `/dispatch` at all — which is the same class of failure this whole
exploration is about, one level up.

### 8. Does the worker boot with the workspace CLAUDE.md and instance settings? Yes for the instance; no for the root

- **Instance `CLAUDE.md`**: yes, by cwd. The instance root carries a generated
  `CLAUDE.md` (workspace-context at instance altitude) plus the repo `CLAUDE.md`
  files under it. `MaterializeWorkspaceRoot` writes a separate, minimal root-altitude
  `CLAUDE.md` at the *workspace* root (`root_materializer.go:47-50`), which the
  dispatched worker does **not** load, because its cwd is the instance.
- **Instance `.claude/settings.json`**: yes, by cwd — plugins, marketplaces,
  permissions, env, PreToolUse/Stop hooks.
- **Root SessionStart hook**: no (section 6).
- The `additionalContext` path in `buildSessionStartInjection`
  (`/home/.../public/niwa/internal/cli/instance_from_hook.go`, ~line 340) — which
  injects the instance path, a `cd` instruction, the key report, and the instance's
  `CLAUDE.md` under the framing "treat it as the authoritative guidance for this
  session" — serves the **other** dispatch route: a background session started by
  the harness at the workspace root (`claude agents` / a bg job), where niwa
  provisions the instance *reactively* on SessionStart. `niwa dispatch` provisions
  *proactively* and roots the worker inside, so it never traverses that code.

That two-route split matters for this exploration: a mandate placed only in
`promptPrefix` covers `niwa dispatch` workers; a mandate placed only in
`buildSessionStartInjection` covers root-launched background sessions. **Covering
both means touching both, or using the instance-level `session_start` hook from
section 6, which is the one channel both routes share** (both end up with a cwd
inside an instance whose settings.json carries workspace-declared hooks).

## Implications

**The strong-guidance option the user prefers is a one-line change with an
existing precedent.** `dispatch.go:421` already prepends niwa-authored
instructions to dispatched workers, the prefix/body split exists specifically so
niwa's text survives the spill path, the ordering (niwa's framing first) is
already pinned by a test, and there is no size budget to negotiate. A workflow
mandate as `promptPrefix` is the same shape of change as keep-alive arming,
which shipped.

**There are three distinct places a mandate can live, and they fail differently.**
(a) The `/dispatch` SKILL.md brief template — advisory, degrades to nothing when
the coordinator skips the skill, but it is the only place that can say *which*
workflow this particular task needs. (b) `promptPrefix` in `dispatch.go` —
unconditional for every `niwa dispatch`, cannot be skipped, but must be generic
because niwa knows nothing about the task. (c) A workspace-authored
`hooks/session_start/*.sh` materialized into every instance — unconditional,
covers both dispatch routes, needs no niwa release, and is the only lever the
workspace owner can pull without shipping Go. These compose rather than compete;
(a) is the specific mandate, (b)/(c) are the backstop that fires when (a) was
never written.

**Option (c) deserves serious weight** because it is the only one available to a
workspace today without a niwa release, and it is the only channel that covers
background sessions provisioned reactively at the root as well as `niwa dispatch`
workers. Its cost is that it fires after skill enumeration and it is per-workspace
rather than per-product, so it does not help other niwa users.

**The template gap is real and cheaply closed.** Step 1a proves the template can
carry a MUST-shaped process instruction; a step 1b requiring the brief to name the
sanctioned workflow (and, per shirabe's own idiom, to reference the skill rather
than restate it) is the in-idiom fix.

**Anything on the hard-enforcement end of the spectrum has no seam here.** niwa
dispatches a worker and never inspects it again — no PreToolUse gate on the
worker's first tool call, no verification that a skill was invoked. Enforcement,
if wanted, has to come from the instance hook surface (PreToolUse/Stop, which the
worker *does* load and which this workspace already uses for
`gate-online.sh` and `workflow-continue.sh`), not from the dispatch command.

## Surprises

**niwa already documented this exact problem and picked the prompt prefix as the
answer.** The channel analysis in `dispatch_keepalive.go:14-22` is a written
finding that the prompt prepend "is the one channel niwa controls end to end for a
dispatched worker." The exploration does not need to rediscover the channel; it
needs to decide the content.

**The `/dispatch` skill mandates a reporting format but not a working method.**
Step 1a spends 23 lines making the `=== WORK IN FLIGHT ===` block non-negotiable,
including cross-referencing shirabe's `work-summary` component as the single
source of truth. Immediately adjacent, the brief contents list says nothing about
how the work should be done. The skill treats "how do I know what you shipped" as
a contract and "how should you work" as the worker's business.

**The instance-level SessionStart channel is open and unused.** The keep-alive
design's "B1 is not viable" conclusion is correct for *niwa's own* root hook but
does not generalize: `DiscoverHooks` + the `snakeToPascal` fallback means a
workspace-supplied `session_start` hook materializes into every instance,
including dispatch-provisioned ones. I found no code or doc that considers this,
which makes me want a second pair of eyes on it before it is treated as load-bearing.

**A stale comment sits directly on the line we would edit.** `dispatch.go:401-404`
describes a `maxPromptBytes`/`dispatchPromptReserve` reserve that was deliberately
deleted (`dispatch.go:101-107`). Anyone implementing a prepend will read that
comment first and may build a budget that no longer exists.

**Plugin delivery is not the problem.** `prewarmDeclaredPlugins` synchronously
clones and installs shirabe before launch, specifically to stop the worker from
enumerating skills before shirabe lands. The worker has the skills. It just has no
instruction to use them — which sharpens the exploration's core question: this is
a mandate problem, not an availability problem.

## Open Questions

1. **Generic or specific?** A `promptPrefix` mandate cannot know whether the task
   wants `/work-on`, `/execute`, or `/plan`. Is a generic "before starting, check
   whether a shirabe workflow skill covers this task and invoke it" strong enough,
   or does the mandate have to come from the brief (and therefore from the
   coordinator, and therefore be skippable)?
2. **Does an unconditional prefix belong in niwa at all?** niwa is a
   workspace manager and shirabe is one plugin among several. A hard-coded shirabe
   mandate in the niwa binary couples the two products. Options: a
   `[global] dispatch_prompt_prefix` config key; a `--mandate` flag; or keep niwa
   generic and put the shirabe-specific text in the workspace `session_start` hook.
   This is a product-boundary call for the user, not something the code decides.
3. **Does an instance-level `session_start` hook actually fire for a `claude --bg`
   worker?** The mechanism reads correctly from source and matches how the existing
   `PreToolUse`/`Stop` entries got there, but I have not run a dispatch to observe
   the hook firing in a `--bg` session. Worth an empirical check before anyone
   designs on it.
4. **Order relative to keep-alive.** Both are preambles that say "before starting
   the task below." Two stacked preambles may read badly; someone has to decide
   whether they merge into one niwa block or stay separate.
5. **Coverage of the other route.** Do we care about background sessions started at
   the workspace root (the `buildSessionStartInjection` path) as well as
   `niwa dispatch`? If yes, a `dispatch.go`-only change misses them.
6. **Cost tolerance.** Every dispatch, including trivial ones, pays for whatever
   the mandate says. Is there an appetite for a short pointer ("consult the shirabe
   skill index") over a self-contained instruction?

## Summary

`niwa dispatch` composes the worker's prompt as `prefix + body` where `body` is the
caller's string and `prefix` is niwa-authored text already used to inject the
keep-alive arming instruction, so an unconditional workflow mandate is a
one-line change at `dispatch.go:421` with no size budget to respect (oversized
prompts spill to a file, they are never refused) and the prefix-first ordering
already pinned by test. The `/dispatch` skill's brief template
(`internal/workspace/rootskills/dispatch/SKILL.md`, embedded in the niwa binary)
lists Goal, Context, Pointers, Acceptance criteria, Out of scope, and the
work-in-flight block — it mandates a reporting format but has no slot for which
workflow the worker must use, which is a genuine root cause; meanwhile
`prewarmDeclaredPlugins` synchronously installs shirabe before launch, so this is
a mandate problem, not an availability problem. The biggest open question is where
the mandate should live: a niwa-side prefix couples niwa to shirabe, while a
workspace-authored `hooks/session_start/*.sh` — which `DiscoverHooks` plus the
`snakeToPascal` fallback would materialize into every instance, covering both
dispatch routes with no niwa release — appears to be an open and entirely unused
channel that I could not verify empirically.
