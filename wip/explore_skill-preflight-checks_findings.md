# Exploration Findings: skill-preflight-checks

Round 1. Seven leads, all returned.

## 1. The mechanism exists, is already in production here, and needs no invention

Claude Code substitutes `` !`command` `` in a SKILL.md body: the command runs at
skill invocation, its stdout replaces the placeholder, and the substitution
happens **before the model sees the body**. The agent cannot skip it. It is
scoped per-skill by construction (the line lives in that skill's SKILL.md),
`${CLAUDE_PLUGIN_ROOT}` resolves inside the command and inside the matching
`allowed-tools` rule, and a pre-approved `allowed-tools: Bash(...)` entry means
no permission prompt on load.

`skills/inflight/SKILL.md` already does it: `allowed-tools: Bash(shirabe:*)` at
line 14, `` !`shirabe work-summary render` `` at line 39, with a comment noting
`CLAUDE_CODE_SESSION_ID` is "confirmed exposed to a skill's `!` injection on
Claude Code 2.1.201".

Two hard constraints come with it:

- **A non-zero exit aborts the entire skill invocation.** Claude never sees the
  body. This is not compatible with "print and let the agent decide" unless the
  script *always* exits 0 and expresses failure as printed text. The repo
  already has that idiom -- `command -v shirabe || exit 0` appears throughout
  `docs/designs/current/DESIGN-session-work-summary.md` (lines 313, 342, 391,
  459, 523, 752), and `pr_body_hook.rs` documents it explicitly: "must never
  abort the tool call with a non-zero code."
- **Silence on success is load-bearing for context, not taste.** Identical
  rendered content is deduplicated on re-invocation; *differing* content causes
  the whole skill body to be appended again. A check that prints anything
  variable (versions, timings, a checkmark list) turns a re-invocation into a
  second full copy of the skill. That is a multiplicative context cost, and it
  is the one argument in this exploration where the token framing actually
  holds.

Consequence flagged by the author mid-round: **every existing `!` line that
embeds a tool's output needs an inline fallback**, e.g.
`` !`shirabe work-summary render || echo "..."` ``. `/inflight`'s bare
injection is a live defect -- on a host without the binary the shell returns
127 and the skill dies rather than degrading to its documented empty-state line.

Alternatives are worse. PreToolUse on the `Skill` tool fires before the body but
its `tool_name` is the generic `"Skill"`; whether the individual skill name
reaches the hook is unconfirmed. SessionStart is session-level, once, too early.
No `requires`/`preflight`/`dependencies` field exists in SKILL.md frontmatter.

## 2. The stated premise does not survive measurement

Prerequisite prose is 7 passages across 5 of 20 skills. Eagerly-loaded cost is
~327 tokens total -- 0.43% of the 75,500-token SKILL.md corpus. The
always-loaded `description:` fields mention no tool, version, or install step at
all, so the always-on cost is **zero**. Fifteen skills carry none of this prose.

The one complete passage is `skills/work-on/SKILL.md:176-183`, 47 tokens, which
states the koto >= 0.3.3 floor, the check, and the curl-pipe-bash install.

There is no token-budget argument for this work. Anyone who writes one is
writing fiction.

## 3. The real defect is the inverse of the premise

What the inventory and dependency map actually found:

- Four of the five tools shirabe depends on -- the `shirabe` binary, `gh`, `jq`,
  `git` -- are invoked **unguarded** across the corpus. Only `koto` has a stated
  guard, in one skill.
- `skills/execute/SKILL.md:271-273` promises the preflight will "confirm `gh`
  auth is live -- it is a precondition." `skills/execute/scripts/preflight.sh`
  checks a file path and nothing else. Prose and implementation have already
  drifted.
- `references/fixes/cli-version-preflight.md` is a purpose-built 108-line
  preflight reference whose own header claims chain skills dereference it. No
  skill cites it. It costs nothing at runtime because nothing loads it.
- `run-cascade.sh` guards `shirabe` and `git` beautifully (`:628-646`) and
  leaves 19 `jq` uses and one `python3` use unguarded on a path that mutates
  docs *before* committing them.
- koto command gates swallow a missing `gh` as an unexplained red-CI stall:
  "koto reports a failed command gate as an exit code with no message and
  discards the command's own output" (`koto-templates/execute.md:353`).
- `gh auth status` is checked at exactly one of roughly thirty call sites.

## 4. The demand is real but for a different failure than the topic names

Five durable incidents, all filed by the maintainer (so breadth is Low, but
maintainer acknowledgment is the strongest available form):

- **shirabe#80** (open) -- `check-staleness.sh` never shipped with shirabe; the
  `command not found` exit code "misroutes through introspection accidentally
  rather than meaningfully."
- **shirabe#215** (closed, PR #216) -- `preflight.sh` hard-required
  `CLAUDE_PLUGIN_ROOT`, which the harness does not export into Bash tool
  subprocesses. Blocked the entire single-pr `/execute` run.
- **shirabe#217** (open) -- friction log; four of nine items are
  environment/version mismatches, including three shirabe copies on disk with
  no way to tell which a run binds to.
- **shirabe#270** (closed, PR #278) -- `plan-to-tasks.sh` used bash 4.0/4.3
  constructs; stock macOS ships 3.2.57. The reporter's own listed fix option was
  "add a version guard that fails with an actionable message naming the
  requirement."
- **shirabe#279** (open) -- `/execute` calls `koto context set`, a subcommand
  koto does not have; stderr was filtered with `2>/dev/null`, so the step
  *appeared to succeed* and twelve children would have dispatched against a
  branch that was never created.

**Every one is version or subcommand skew, or a file that never shipped. None is
plain tool absence.** A presence-and-version check as scoped catches #270 and
possibly #217 item 4. It does not catch #279, #215, or #217 items 6-7.

Two prior decisions cut against the obvious shapes and must be argued past, not
around:

- `DESIGN-shirabe-pattern-v1-ergonomics` Decision 6 evaluated and **rejected**
  per-SKILL inline snippets ("inlining duplicates the pattern across seven
  SKILLs") and once-per-chain-entry probes ("version-skew fires
  per-subcommand-invocation, not per-chain-entry"), choosing lazy-loaded prose
  for R30 instead.
- PR #278 chose portability plus a CI matrix over the runtime version guard
  #270 offered, with the workflow comment arguing the matrix is *better*: "a
  pattern list only catches what its author remembered." That reasoning
  generalizes uncomfortably to a declared prerequisite list.

Adjacent precedent that helps: `PRD-shirabe-pattern-v1-ergonomics.md` R30
explicitly names "**capability detection at skill load**" as an open mechanism
and leaves it to DESIGN. `skills/work-on/evals/evals.json` id 10
(`koto-not-installed`) already asserts the desired behavior with a fixture that
exits 127. And the check-absorption chain (BRIEF/PRD/DESIGN, status Done)
already established the "prose restating a rule a check could execute" argument
-- for document checks. Host checks appear nowhere in its disposition table:
not absorbed, not deferred, not rejected. It simply never reached this.

## 5. Composability must be per-mode, not per-skill

Six skills split hard on a mode chosen at runtime:

- `/roadmap` issueless mode is documented as "no `gh` call of any kind"
  (`SKILL.md:369`); `--issues` mode needs it.
- `/execute` coordinated mode has **no koto session** (`SKILL.md:245`); single-pr
  mode is koto end-to-end.
- `/plan` needs `gh` only in multi-pr mode, and the mode is chosen between
  Phases 3 and 4 -- after load.

Meanwhile nine skills need nothing but `git`: `decision`, `review-plan`,
`private-content`, `public-content`, `writing-style`, plus `vision`, `prd`,
`brief`, `strategy` which add only `shirabe transition` at one finalize step.
Five would declare an empty set outright.

A flat `requires: [gh]` per skill would false-alarm on the majority path. The
declaration needs at least `{unconditional: [...], on_mode: {...}}` -- and the
mode-conditional half cannot be evaluated at load time, which is an unresolved
tension.

`shirabe` is genuinely unconditional in exactly one skill: `/inflight` -- the
one place a `!` command runs at load, before any model reasoning.

## 6. Implementation home: split, because the binary cannot report its own absence

`.claude-plugin/marketplace.json` declares `"source": "./"` -- the plugin *is*
the repo checkout, so `skills/*/scripts/*.sh` are always present at skill load,
version-matched to the SKILL.md that references them.
`.github/workflows/release-binaries.yml` publishes only bare
`shirabe-{os}-{arch}` assets. **No release bundles the binary with the plugin.**

So a pure `shirabe preflight` subcommand is fatal on its own: on a host without
the binary the invocation is a bare 127 and the most important prerequisite
becomes the one the check is silent about.

The split -- a thin bash shim in the plugin that owns the binary-missing case,
then `exec`s into a fail-safe binary subcommand -- is cheaper than it looks
because the hard part already ships:
`skills/execute/scripts/run-cascade.sh:633-648` implements the four-step
resolution chain (`$SHIRABE_BIN` -> `command -v shirabe` -> `target/release` ->
`target/debug`), and `skills/execute/scripts/preflight.sh:19` implements the
`${CLAUDE_PLUGIN_ROOT:-self-resolve}` fallback.

Testability reinforces it. Shell tests run PR-triggered on a Linux+macOS matrix
with an explicit `/bin/bash` (3.2) leg and already simulate missing dependencies
(`preflight_test.sh` fake roots, `run-cascade_test.sh` PATH/`SHIRABE_BIN`
injection, the `koto-missing` eval fixture). `cargo test` runs ubuntu-only and
structurally cannot test the binary's own absence.

Naming hazard: `skills/execute/scripts/preflight.sh` already exists and
hard-fails with exit 1. A second thing called "preflight" with the opposite exit
contract, in the same plugin, will confuse readers.

## 7. Install advice: delegate, and put PATH ahead of everything

All four uncertain tools -- `shirabe`, `koto`, `gh`, `jq` -- are installable
through tsuku, including the two first-party ones, via recipes that already
exist (`.tsuku-recipes/shirabe.toml` here, and koto's own). A hardcoded per-OS
matrix runs to roughly 36-40 independently-drifting cells. Delegating to `tsuku
install -y <spec>`, with each tool's own OS-agnostic `install.sh` as fallback
and a `command -v`-chosen brew/apt/dnf/pacman line for `gh` and `jq`, needs
about eleven maintained strings and two branches -- neither of which is `uname
-s`.

**"Installed but not on PATH" must precede every install route.** On this very
host, koto and shirabe both live in `~/.tsuku/tools/current/`, reachable only
after sourcing `~/.tsuku/env`. A naive `command -v` reports "missing" and an
agent would dutifully run a reinstall it does not need. `install.sh` writes
`~/.shirabe/env` and appends a source line to shell rc files, so this state is
common, not exotic.

Known-broken combinations must be checked too: `gh = "latest"` is commented out
of `.tsuku.toml` with "segfaults on Linux (tsukumogami/tsuku#2245)" -- a
host-specific exception recorded only in a TOML comment, where no check would
think to look.

## 8. Prior art: the doctor family is the wrong model

Systems that stay silent when healthy -- direnv's `has`, npm `engines`, Cargo
`rust-version`, `go.mod` toolchains, mise's `status.*` defaults -- all separate
a bare predicate from any reporting, or fix the problem instead of announcing
it. The entire doctor family (flutter, nix, brew, rustup, pre-commit) is
architecturally incapable of quiet: the green checklist is treated as the
product. pre-commit's quiet-mode request is a decade old across three issues and
has never landed.

Worth stealing: flutter's `ValidationType.partial` -- a boolean cannot express
"gh is installed but 2.20 and we need 2.40", which is exactly shirabe's koto
case. Three states minimum: satisfied, missing, present-but-below-floor, because
the remediation differs.

Worth avoiding: hand-maintained per-platform install matrices. Every system that
gets this right borrows someone else's package index. devcontainer's github-cli
feature is 280 Debian-only lines.

Also relevant: `tsukumogami/tsuku` already ships a `doctor` command, and its open
bug tail (tsuku#2507 "prints 'Everything looks good!' underneath its own WARN
lines", #2517, #2522, #2475, #2524) is the cost signal -- an environment checker
is a maintained surface with its own failure modes, not a one-time write.

The reader here is an agent, which changes the target: a green checklist is pure
token cost plus a distraction risk, and failure output must be complete on first
emission because there is no interactive second run. Failure text should be an
instruction the agent can act on, and should say what the *skill* will fail to
do without the tool, since the agent's decision is whether to proceed degraded.

## Contradictions and open questions

1. **Presence versus skew.** The demand evidence says the real failures are
   version and subcommand skew; the scoped check catches absence.
   `cli-version-preflight.md:52-66` explicitly rejects semver gating in favor of
   per-subcommand `--help` probing because "shirabe releases sometimes ship
   partial surface changes" -- while `.tsuku-recipes/shirabe.toml` does the
   opposite. The two existing artifacts disagree.
2. **Mode-conditional dependencies cannot be resolved at load.** `/plan` picks
   multi-pr between Phases 3 and 4; a load-time check cannot see it.
3. **Windows and `disableSkillShellExecution`.** `shell: bash` with no Git Bash
   fails the invocation before any command runs, so adding a bash preflight to a
   skill that would otherwise have worked is a net regression on that host. Any
   design needs a best-effort posture.
4. **Declaration home.** `metadata:` is the only spec-legal free-form frontmatter
   key; a novel top-level key trips `Unexpected key(s) in SKILL.md frontmatter`
   on the claude.ai and Skills-API packaging paths.
5. **`/execute`'s koto floor is unrecorded.** It uses `koto context`, `koto
   workflows`, `failure_policy: skip_dependents`, `--with-data @file` -- likely
   higher than `/work-on`'s stated 0.3.3, and nothing states it.
6. **Is `python3` a real dependency or an accident?** `run-cascade.sh:43`
   justifies it for `realpath`, but macOS 12.3+ removed system python3. A
   pure-bash normalizer deletes the dependency.
7. **Degrade as a check outcome.** `extract-context.sh:407-409` is the only
   graceful degradation in the repo -- warns and falls back to `wip/` when koto
   is absent. Worth preserving as an outcome type, not just pass/fail.
