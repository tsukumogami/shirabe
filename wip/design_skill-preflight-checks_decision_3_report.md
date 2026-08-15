<!-- decision:start id="skill-preflight-load-mechanism" status="assumed" -->
# Decision 3: Load-time execution mechanism

**Question.** How does the prerequisite check run when a skill loads, without
ever blocking the skill?

**Context.** The check must be reached deterministically at every skill load
(the agent must not be able to skip it), must print an actionable report when a
declaration is unsatisfied, must print nothing at all when it is satisfied
(R12), and must never block, gate, or refuse the skill (R17). Claude Code's
inline command injection is the only harness mechanism that runs before the
model sees the skill body, and it has a fatal edge: a non-zero exit from an
injected command aborts the whole skill invocation. So the mechanism that gives
determinism is also the mechanism that can delete the skill, and the entire
decision turns on containing that.

## Options considered

### A. Injected command per SKILL.md (`` !`...` `` plus `allowed-tools`)

A backtick-quoted command prefixed with `!`, at line start, in each SKILL.md
body, with a matching `allowed-tools:` frontmatter entry. Claude Code runs the
command at invocation and substitutes its stdout into the body in place of the
placeholder, before the model sees anything. `skills/inflight/SKILL.md:14,40`
already ships this shape.

Confirmed behaviour (Claude Code skills documentation, verified this round):

- Substitution runs **once** over the original file; output is not re-scanned.
- `${CLAUDE_PLUGIN_ROOT}` (and `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`,
  `${CLAUDE_PLUGIN_DATA}`) are substituted in **two** places: the skill's
  markdown body *and* Bash rules in `allowed-tools`. The documented example is
  `allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)`. Both sides
  expand before matching, so a pattern can name the same absolute path the body
  invokes.
- Injected commands **never prompt**. The permission check is evaluated and
  anything other than *allow* aborts the invocation — including a rule that
  would normally ask. A pre-approving `allowed-tools` entry is therefore not an
  optimisation, it is the thing that keeps the skill alive.
- A non-zero exit aborts the entire invocation; the model never sees the body.

The last two were confirmed against the installed Claude Code bundle
(`~/.local/share/claude/versions/2.1.233`), not just the documentation. The
injection routine performs the permission check and throws on anything but
`allow` — `if(u.behavior!=="allow") throw new BRe('Shell command permission
check failed for pattern "…": '+(u.message||"Permission denied"))` — and a
command failure throws `Shell command failed for pattern "…"` carrying the
command's stdout and stderr. Both throws propagate out of the render and abort
the invocation.

One detail worth recording because it changes a rationale: the substituted text
is built by a helper that appends stderr under a literal `[stderr]` header when
stderr is non-empty. Stderr is therefore **not** silently discarded by the
harness, so `2>&1` is not required to satisfy R21. It is still recommended, for
two other reasons given below.

### B. A plugin-shipped hook in `hooks.json` (PreToolUse on the `Skill` tool)

Register one hook at the plugin root; it fires before the Skill tool executes,
for every skill invocation, and reports through hook JSON.

### C. Agent-instructed invocation in the skill body

The `/execute` precedent: a fenced ```bash block in the body telling the model
to run the check as an ordinary Bash tool call
(`skills/execute/SKILL.md:129,276` → `skills/execute/scripts/preflight.sh`).

## Evaluation against drivers

| Driver | A. Injected command | B. Plugin hook | C. Agent-instructed |
|---|---|---|---|
| Runs deterministically at load | Yes — before the body reaches the model, unskippable | Yes — fires before the Skill tool | **No** — the model may skip it |
| Per-skill scoping | Natural: each SKILL.md names its own declaration | **Unresolved**: the hook's `tool_name` is the generic `"Skill"`; whether the individual skill name reaches the hook is unconfirmed, and without it the hook cannot know which declaration to evaluate | Natural |
| Cannot block the skill (R17) | Only if the command always exits 0 — the discipline this decision imposes | Structurally safe (a non-2 exit is a non-blocking error) | Safe |
| Zero cost when satisfied (R12) | Zero bytes substituted; no tool call, no round trip | Hook runs but emits nothing | **No**: a Bash tool call plus its result lands in context on every load even when satisfied |
| Output reaches the model | Directly, as body text, before the model reads the skill | Only via `additionalContext` in hook JSON — a narrower, less certain channel | As a tool result, *after* the body is already in context |
| Blast radius | Confined to shirabe skills | Global: fires for every skill from every plugin | Confined |
| Cost to ship | 20 SKILL.md files each gain a frontmatter entry and a body line | One registration, but `.claude-plugin/` ships no `hooks.json` today and the existing shirabe hooks are registered by dot-niwa, not by the plugin — this is new surface | 20 body edits, no frontmatter |

Option C is disqualified on the driver the feature exists to satisfy. Prose that
instructs the model to check something is precisely the state this work ends:
`references/fixes/cli-version-preflight.md` is prose no skill cites, so it never
loads, and `skills/work-on/SKILL.md`'s koto floor is an instruction the model may
or may not act on. Adding a nineteenth such instruction does not make the check
happen. It also inverts the ordering — the report arrives after the model has
already read and begun acting on the body — and it cannot satisfy R12, because a
tool call with an empty result is not zero bytes.

Option B is not disqualified but is unresolved on the point that matters. A
per-skill declaration needs the skill's identity, and the hook input is not
confirmed to carry it. It also carries a global blast radius the feature does not
need, and it routes the report through `additionalContext` rather than into the
body the model is about to read. It remains the fallback if the injection path
is closed off by policy, and it is the natural home for the *enforcement*-shaped
work (R11's mode-scoped verification), where firing on a later tool call rather
than at load is the correct trigger.

Option A wins on determinism, ordering, scoping, and cost, and it is the only
option that can produce literally zero bytes on the satisfied path. Its one
disqualifying risk — killing the skill — is fully containable, and the repo
already has the idiom for containing it.

## Recommendation

**Adopt the injected command per SKILL.md (Option A)**, under three binding
constraints:

1. **The entry point is a plugin-shipped POSIX shell script, not the `shirabe`
   binary.** `shirabe` is itself one of the tools the check reports on. A check
   that lives inside the binary is silent in exactly the case it most needs to
   speak — the binary is absent. A script under `${CLAUDE_PLUGIN_ROOT}/scripts/`
   ships with the SKILL.md that invokes it, so it is present whenever the skill
   is present. This is R27's "single invocable entry point"; the script may
   delegate to `shirabe` when `shirabe` resolves, but it must produce the
   missing-tool report itself.
2. **The script always exits 0, and the injected command carries an outer guard
   anyway.** Two independent layers, because they fail for different reasons —
   see the failure-modes section.
3. **The satisfied path prints zero bytes on both streams.** Not a style rule.
   Anything printed is body text, and body text that varies between invocations
   is a context cost (see the deduplication note below).

## The exact SKILL.md contract

Frontmatter line (add to the existing `allowed-tools:` if the skill has one;
`/inflight` is the only skill that does today):

```
allowed-tools: Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
```

Body line, at column 0, once per skill, near the top of the body:

```
!`sh ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> 2>&1 || true`
```

Every element is load-bearing:

- **`sh <path>`, not `<path>` directly.** Invoking through `sh` ignores the
  executable bit. Verified: a script at mode 644 runs correctly under `sh
  path.sh` and exits 0. The design must not depend on `chmod +x` surviving
  packaging, cloning, or a marketplace fetch.
- **The unquoted path.** `allowed-tools` matching is textual against the
  expanded command. Quoting the path in the body (`sh "${CLAUDE_PLUGIN_ROOT}/…"`)
  while the pattern is unquoted risks a prefix mismatch, and a mismatch aborts
  the skill. The cost is that a plugin root containing a space breaks; that is
  the lesser risk, and the canonical install path (`~/.claude/plugins/…`) has
  none.
- **`<skill-name>` as the argument.** The script resolves that skill's
  declaration. One script at the plugin root, twenty call sites, one declaration
  per skill — not twenty copies of the script under `${CLAUDE_SKILL_DIR}`. The
  literal name is preferred over passing `${CLAUDE_SKILL_DIR}` (which would make
  the line byte-identical in all twenty files) because a literal name is
  greppable and lets a test invoke the entry point for a named skill directly,
  which is what R27 asks for.
- **`sh ` in the `allowed-tools` pattern too.** The documented example form is
  `Bash(${CLAUDE_SKILL_DIR}/scripts/render.sh *)` — direct invocation, which
  depends on the executable bit. Prefixing the interpreter matches the house
  idiom already in `skills/execute/SKILL.md:129` (`bash
  ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh`) and drops the
  dependency; the pattern simply has to carry the same prefix.
- **`2>&1`.** Not needed to keep stderr visible — the harness already appends it
  under a `[stderr]` header — but recommended for two reasons. First, byte
  identity: merging puts the whole report on one stream under the script's
  control, so the satisfied case is unambiguously empty rather than empty-plus-a
  possible `[stderr]` decoration, and that is what the deduplication path below
  compares. Second, R27 asks for an entry point whose *combined* stdout and
  stderr a test can capture; merging at the call site makes the thing the test
  captures and the thing the model sees the same string.
- **`|| true`.** The outer guard. It converts any non-zero exit from anywhere in
  the invocation into 0. `Bash(true)` is declared alongside the script pattern
  because Claude Code's Bash permission matching may decompose a command on
  shell operators and require each sub-command to be separately allowed; the
  extra entry costs nothing and removes the failure mode.

### `/inflight` — two live defects, both fatal

`skills/inflight/SKILL.md` carries **two** injected commands, and the second one
is worse than the reported problem.

**Line 40** is the known defect: `` !`shirabe work-summary render` `` with no
fallback. `shirabe work-summary` always exits 0 by construction
(`crates/shirabe/src/work_summary.rs:157-166`, module doc: "Every subcommand
ALWAYS exits 0 (fail-safe)"), so the command itself is safe — but on a host
where the *binary is absent* the shell returns 127 and the skill dies rather
than degrading to its own documented empty-state line. It should become:

```
!`shirabe work-summary render 2>&1 || echo "shirabe is not available; this session's tracked PRs cannot be rendered"`
```

with `allowed-tools: Bash(shirabe:*), Bash(echo:*)`. The `|| echo` branch is
preferred over `|| true` here because `/inflight` is a relay skill whose entire
body assumes the block exists; a bare empty substitution would leave the model
relaying nothing with no explanation.

**Line 77 is a live, unconditional break that kills `/inflight` on every host,
including one where everything is installed.** The line is

```
!`shirabe work-summary track <pr-url> [<pr-url> ...]`
```

It was written as *documentation of a verb the agent should run later*, but it
uses the injection syntax at column 0, so it executes at load — with the literal
placeholder text as arguments. `<pr-url>` is not a placeholder to a shell; `<`
and `>` are redirection operators. Verified directly:

```
$ sh -c 'shirabe work-summary track <pr-url> [<pr-url> ...]'
sh: pr-url: No such file or directory
exit=1
```

Exit 1 aborts the entire skill invocation. `git blame` puts the line in `db91dc6`
(#226, 2026-07-07); the skill's original form in #219 had no such line, so
`/inflight` has been dead since #226. **The fix is to stop it being an injected
command** — drop the `!` and present it as an ordinary fenced or inline code
sample, which is what it was always meant to be. This decision's contract should
carry the general rule: *injection syntax is for commands intended to execute at
load; a command shown to the reader as an example must never be written with a
leading `!` at column 0.*

## Failure modes and the always-exit-0 discipline

The discipline has two layers because the failure modes have two sources. The
script's own `exit 0` covers everything the script can reach. The injected
command's `|| true` covers everything that goes wrong before the script's first
line executes — and that class is the dangerous one, because it is invisible to
the script author and it fires on every skill at once.

Verified behaviour of the recommended line (measured, not assumed):

| Failure | Without the guard | With `… 2>&1 \|\| true` |
|---|---|---|
| Script missing from the install | exit 127 → **every skill dies** | exit 0, `sh: …: No such file or directory` appears as body text |
| `${CLAUDE_PLUGIN_ROOT}` fails to expand (empty) | `sh /scripts/…` → exit 127 → **every skill dies** | exit 0, path visible in the message, skill loads |
| Script not executable (mode 644) | Fine — `sh <path>` ignores the exec bit | Fine |
| Script has a syntax error | non-zero → skill dies | exit 0, the interpreter's error is visible |
| Script exits non-zero on an unsatisfied declaration | skill dies — **direct R17 violation** | exit 0, report visible; the agent decides |
| `allowed-tools` fails to match | Invocation aborts, no prompt | Unchanged — the guard cannot help; only a correct pattern can |

**The one thing to validate before rollout.** The permission check runs against
the full command string, and Claude Code's Bash matcher is known to decompose
commands on shell operators and require each sub-command to be separately
allowed. Whether `|| true` therefore needs its own `Bash(true)` entry was not
confirmed from source this round, which is why the recommended frontmatter
declares it. The implementation must verify the exact pattern against the exact
body line on a host with `defaultMode` *not* set to `auto` before this ships to
twenty skills — because a mismatch does not degrade anything, it silently
deletes the skill, and the developer machine this was researched on has
`"permissions": {"defaultMode": "auto"}` in `~/.claude/settings.json`, which
would mask the failure entirely. Neither `.claude/settings.json` in this repo
nor any `settings.local.json` carries a Bash allow-list, so there is no local
evidence either way; `allowed-tools` in the SKILL.md is the only pre-approval
the design can rely on.

The last row of the table is the residual risk and the reason the frontmatter
pattern must be kept byte-compatible with the body line. A future edit that quotes the path, adds
a flag before the script path, or renames the script without updating both sides
does not degrade the check — it deletes the skill. This warrants a CI check: for
every SKILL.md, assert that each injected command's text is covered by an
`allowed-tools` entry in the same file, and that no injected command lacks an
outer exit-0 guard. The repo has precedent for exactly this kind of gate —
`scripts/check-template-interpolation.sh` and `scripts/check-sentinel.sh`, each
wired as its own path-filtered workflow (`.github/workflows/check-sentinel.yml`
runs on `pull_request` under `.claude-plugin/**`). A `check-skill-injection`
workflow filtered on `skills/**` follows the established shape, and it is the
gate that would have caught the `/inflight` break below at review time.

The script's internal shape follows the two in-repo precedents. It does **not**
use `set -e` (which would defeat the point); it uses `set -u`, guards every
probe, and ends with an explicit `exit 0`. This is the same posture as
`crates/shirabe/src/pr_body_hook.rs` — "must never abort the tool call with a
non-zero code" — and `work_summary.rs`'s "an error degrades to 'no output',
never a non-zero abort". The `command -v <tool> || exit 0` idiom threaded through
`docs/designs/current/DESIGN-session-work-summary.md` (lines 313, 342, 391, 459,
523, 752) is the same rule at the hook layer. This check joins that family, not
the `validate`/`transition` family with its four-level exit vocabulary
(`crates/shirabe/src/main.rs:391-458`).

Note that `skills/execute/scripts/preflight.sh` is deliberately **not** in this
family: it uses `set -euo pipefail` and `exit 1`, and its SKILL.md says "a
non-zero exit halts the run". That is correct for an agent-run assertion in the
middle of a workflow and wrong for anything injected at load. The two must not
be confused, and if `/execute`'s preflight is ever moved to the injected path it
must change its exit discipline in the same edit.

## Consequences

**Deduplication makes silence load-bearing — confirmed, and it is exactly a
byte comparison.** The re-invocation path in the installed bundle compares the
previously rendered content against the freshly rendered content and branches:

```js
if (o !== i) {                       // o = priorContent, i = renderedContent
  let c = `(Re-invocation of /${r} — the skill instructions were previously
            loaded; the arguments or dynamic output below are new.)`;
  return [Sn({content: c, isMeta: true}), ...e];   // full body re-appended
}
// byte-identical: the body message is replaced by a one-line note
… `Skill /${r} is already loaded above; instructions unchanged.` …
if (a) w(`SkillTool eliding byte-identical re-invocation of skill ${r}`);
```

So the earlier finding is right and the comparison is strict string inequality,
not a similarity heuristic. A check that prints a version string, a timestamp,
an elapsed time, or a checkmark list does not cost its own length — it costs a
full second copy of the SKILL.md, every re-invocation, plus a note explaining
that the output is new. R12's zero bytes is the only output shape that
guarantees identical renders, and the *unsatisfied* report must be stable
run-to-run for the same reason: it should name postures and commands, never
anything that varies. Elision also requires the prior copy still to be present
in context — after compaction the body is re-sent with a different note — so
this is an optimisation on the common case, not a guarantee.

**Twenty skills gain a frontmatter entry and a body line.** Fifteen of them have
no `allowed-tools` today. This is mechanical but it is the whole surface, and
each one is a way to kill a skill if the two lines disagree — hence the CI gate
above.

**Skills that today need no shell will need one.** The plugin already ships
`.sh` scripts that several skills invoke (`skills/execute/scripts/`,
`skills/plan/scripts/`, `run-cascade.sh`), so a POSIX shell is already a de facto
requirement for those. It is not one for the fifteen prose-only skills, and this
change makes it one. On Windows without Git Bash, Claude Code routes injected
commands to the PowerShell tool, where a POSIX command line does not run — and a
failed injected command aborts the invocation. The regression is therefore real,
but it arrives by a different route than earlier research assumed: it is *not*
the `shell: bash` frontmatter error, because no shirabe skill sets `shell:` and
adding it would be the one combination that fails outright. It is the silent
PowerShell fallback. The bundle's shell selector makes the branch explicit:

```js
if (n === "bash" && !vm()) throw Error(`Skill ${r} requires bash (…) but Git
                                        Bash was not found. …`);
let i = (n === "powershell" && kQ()) ? PowerShellTool
      : vm() ? BashTool
      : PowerShellTool;    // no `shell:` key, no bash  →  PowerShell
```

The exposure is narrower than it looks. `install.sh:31-40` accepts only `linux`
and `darwin` and exits on anything else, so the `shirabe` binary — which most of
these skills call — cannot be installed on Windows at all today. The skills that
would actually regress are the prose-only ones that need no binary. The honest
posture is to state a POSIX shell (Git Bash on Windows) as a documented
requirement rather than to pretend the change is platform-neutral; there is no
per-skill "skip on this platform" affordance to hide behind. The mitigation that
*is* available is to keep the injected line trivial, so that if a
platform-conditional variant is ever needed it is one line per skill to change.

**`disableSkillShellExecution: true` degrades gracefully.** Under that setting
each injected command is replaced with the literal text `[shell command
execution disabled by policy]` and the skill still loads. The check simply does
not run. That text is stable, so it does not defeat deduplication. No design
work is needed beyond not treating its presence as a check result.

**The mode-scoped half of the feature is not served by this mechanism.** R10 and
R11 split load-time verification from mode-selection-time verification. This
decision covers only the first. The second fires after the body is loaded, when
`/plan` picks between Phases 3 and 4, and belongs either to an agent-instructed
call at that step or to Option B's hook — it is out of scope here and should not
be forced into the injected line.

<!-- decision:end -->
