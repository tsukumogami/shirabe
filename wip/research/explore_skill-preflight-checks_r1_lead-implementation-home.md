# Lead: Where should the prerequisite check live -- shell, the shirabe Rust binary, or split?

> Recorded by the orchestrator: the research agent ran read-only and returned
> its findings inline rather than writing this file. Content is verbatim.

## Findings

### 1. The binary as a hook host

Two existing hook entry points establish the pattern, both registered as clap
subcommands in `crates/shirabe/src/main.rs`.

Registration is three lines: a variant in `enum Commands` (main.rs:64-102), a
`mod` declaration (main.rs:25-27), and an arm in the `match` in `fn main()`
(main.rs:364-389). `WorkSummary(work_summary::WorkSummaryArgs)` at main.rs:92
and the unit variant `PrBodyHook` at main.rs:101 dispatch to
`work_summary::run(&args.command)` and `pr_body_hook::run()`.

`crates/shirabe/src/pr_body_hook.rs` (581 lines) is the cleanest precedent for a
preflight-shaped adapter:

- Input: `std::io::stdin().read_to_string()` into a `String`, ignoring the error
  (`let _ =`), then `serde_json::from_str(input).ok()?` -- a malformed stdin
  degrades to allow.
- Output: hook JSON on stdout via `println!` (pr_body_hook.rs:373); emits
  *nothing* when clean.
- Exit code: `pub fn run() -> ExitCode` always returns `ExitCode::SUCCESS`. Its
  doc comment is explicit: "must never abort the tool call with a non-zero code
  -- a block is expressed as a `deny` decision in the emitted hook JSON, not as
  a process exit code."
- Kill switch: `PR_BODY_HOOK_DISABLE=1` (pr_body_hook.rs:58-65), described as
  mirroring the `WS_*` env seams.
- Layering: it adds no rule; it reuses `shirabe_validate::check_pr_body` /
  `check_pr_title`, the same engine `validate --pr-body` calls, so the rule is
  stated once in `references/pr-body-conformance.md`.

`crates/shirabe/src/work_summary.rs` (1462 lines) is the larger hook host. Its
module doc states "Every subcommand ALWAYS exits 0 (fail-safe): an error
degrades to 'no output', never a non-zero abort of a hook or turn," and `pub fn
run` (work_summary.rs:157-167) matches each subcommand and unconditionally
returns `ExitCode::SUCCESS`. Six subcommands: three ambient hook adapters
(`capture`/`absence`/`compact`, reading hook JSON on stdin, emitting hook JSON),
one on-demand skill-facing command (`render`, emitting a *plain* block for
`/inflight` to relay verbatim), `track`, and `spec` -- the last prints the
block-format contract as the single source of truth (work_summary.rs:169-178).
Its doc comment names the CLI as "a cross-layer contract: the dot-niwa hooks and
the `/inflight` skill build against these subcommand names, their stdin/stdout
shapes, and the `WS_*` env seams. Keep them stable."

Crucially, the hooks that *invoke* `work-summary` and `pr-body-hook` are
registered by dot-niwa, not by this plugin: `.claude-plugin/` contains only
`plugin.json` and `marketplace.json` -- no `hooks.json`. The one in-repo hook
wiring is `.claude/settings.json`, which only lists `enabledPlugins` and
marketplaces.

Contrast with the rest of the CLI: `validate`/`transition`/`finalize-chain` use
a four-level exit-code vocabulary (`0` clean, `1` tool-error, `2` violations,
`3` I/O) documented on `ValidateOutcome` (main.rs:391-458). So the binary
already has two distinct exit disciplines, and a preflight would clearly belong
to the fail-safe hook family (exit 0, output-or-silence), matching the "nothing
hard-blocks" requirement in the exploration context.

`skills/inflight/SKILL.md` shows the skill-side half of that contract:
frontmatter `allowed-tools: Bash(shirabe:*)`, `disable-model-invocation: true`,
and dynamic command injection `` !`shirabe work-summary render` `` with
instructions to relay output verbatim. If that binary is absent, the skill's
entire body is dead -- this is exactly the failure the preflight is supposed to
name.

### 2. The existing shell-script surface

Repo-root `scripts/`: `check-evals-exist.sh`,
`check-no-duplicate-rule-list.sh`, `check-no-fixture-design-leak.sh`,
`check-sentinel.sh`, `check-template-interpolation.sh` + `_test.sh`,
`ci-gate-expression_test.sh`, `run-evals.sh`, `validate-template-mermaid.sh` +
`_test.sh`, and `scripts/lib/koto-gates.sh` (a sourced library).

Skill-local scripts:
`skills/execute/scripts/{preflight.sh,preflight_test.sh,run-cascade.sh,run-cascade_test.sh}`,
`skills/plan/scripts/{plan-to-tasks,validate-plan,create-issues-batch}.sh` each
with a `_test.sh`, plus `skills/{brief,comp,strategy}/evals/test-cli.sh` and
`skills/work-on/references/scripts/extract-context.sh`.

House style, uniformly:

- `#!/usr/bin/env bash` everywhere -- **not** POSIX `sh`. The only `#!/bin/sh`
  in the repo is `install.sh`, which must run under `curl | sh`.
- `set -euo pipefail` at the top (exceptions are deliberate and commented:
  `scripts/run-evals.sh` uses `set -uo pipefail` with "Note: no set -e; we
  handle errors explicitly for --all resilience"; `test-cli.sh` uses bare `set
  -u` so it can count failures).
- Self-location idiom: `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`
  then a relative climb to the root.
- Long explanatory header comments stating *why* the script exists and what it
  deliberately does not check.
- Documented exit codes in the header (`scripts/run-evals.sh`: 0 pass / 1 fail /
  2 infrastructure / 3 missing prerequisites).
- Tool resolution by precedence with an env override.
  `skills/execute/scripts/run-cascade.sh:633-648`: `$SHIRABE_BIN` -> `command -v
  shirabe` -> `$REPO_ROOT/target/release/shirabe` -> `target/debug/shirabe` ->
  else emit `{"cascade_status":"skipped",...,"error":"shirabe binary not found
  (set SHIRABE_BIN, install shirabe, or build with cargo)"}` and exit 1.
  `skills/brief/evals/test-cli.sh:17-30` uses the same shape with a `cargo
  build` fallback. **The "is the binary present" probe already exists in this
  repo, twice, in bash.**
- Bash 3.2 portability is an enforced constraint (see section 5).

Test convention: a sibling `<name>_test.sh` with the same shebang/`set -euo
pipefail`, `PASS_COUNT`/`FAIL_COUNT` counters, ANSI `RED`/`GREEN` helpers
`pass()`/`fail()`, temp dirs collected in a `TMPS` array with a `trap cleanup
EXIT`, a final `echo "$PASS_COUNT passed, $FAIL_COUNT failed"` and
`[[ "$FAIL_COUNT" -eq 0 ]]` as the exit status.
`skills/execute/scripts/preflight_test.sh` is the canonical short example (77
lines, 4 cases).

Invocation from skills is `${CLAUDE_PLUGIN_ROOT}`, never `${CLAUDE_SKILL_DIR}`
(which appears nowhere in the repo) and never a bare relative path.
`skills/execute/SKILL.md:129` and `:276`: `bash
${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh`, described as "Step 1
-- Preflight (cross-skill coupling)... A non-zero exit halts the run with a
clear message."

The single most relevant precedent is `skills/execute/scripts/preflight.sh`
itself -- 29 lines, and it already solves the plugin-root bootstrapping problem
the same way a prerequisite check would need to:

```bash
ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
```

with the comment: "Prefer `$CLAUDE_PLUGIN_ROOT` when the loader exported it, but
fall back to the script's own location so the preflight works from a plain shell
(e.g. an agent running it directly) where the env var may be unset." It fails
*closed* (exit 1) and prints a two-line remediation message to stderr. Note that
this existing preflight is a hard-block, which differs from the "nothing
hard-blocks" posture of the proposed check.

### 3. Distribution reality -- confirmed, nothing bundles the binary with the plugin

- `.claude-plugin/plugin.json`: `"skills": "./skills/"`, version `0.16.1-dev`.
  No `hooks`, no `bin`, no binary reference of any kind.
- `.claude-plugin/marketplace.json`: one plugin, `"source": "./"` -- the plugin
  *is* the repo checkout. So everything under `skills/` and `scripts/` is
  present the moment a skill loads, guaranteed and version-matched to the
  SKILL.md that references it.
- `install.sh` (`#!/bin/sh`) downloads a single prebuilt asset
  `shirabe-${OS}-${ARCH}` from the GitHub release to `~/.shirabe/bin`, verifies
  with `sha256sum` or `shasum` (warns if neither), and writes `~/.shirabe/env`
  exporting PATH, appending a source line to `.bashrc`/`.bash_profile`/`.zshenv`.
  It supports only `linux|darwin` and `amd64|arm64`. Note the PATH-modification
  path: a freshly installed binary is not on PATH for an already-running shell
  until `~/.shirabe/env` is sourced -- a real "installed but not visible" case.
- `.tsuku-recipes/shirabe.toml`: downloads the same release asset, `chmod`,
  `install_binaries` to `bin/shirabe`, verify `shirabe --version`.
- `.github/workflows/release-binaries.yml` fires on `push: tags: v*`, builds a
  4-way matrix (linux/darwin x amd64/arm64), and uploads exactly
  `dist/shirabe-{linux,darwin}-{amd64,arm64}` plus `checksums.txt` to the
  release. **No archive, no plugin bundle, no skills/ payload in the release.**
- `README.md` "Requirements": "The `shirabe` binary -- skills call `shirabe
  validate` during ordinary runs, so install it before you use them" and koto
  ">= 0.3.3 (for `/work-on` and `/execute`; the skills check `koto version`
  first and give you an install command when it's missing)."

Conclusion: plugin files are always present at skill load; the binary is a
separate, optional, out-of-band install that may be absent, stale, or
installed-but-not-on-PATH. **No release bundles the binary with the plugin.**
This is the bootstrapping asymmetry, confirmed from the manifests and the
release workflow, not inferred.

### 4. Weighing the three options

**(a) Pure shell in the plugin.** Nothing breaks without the binary -- the
script ships with the skill and reports the binary's absence as data, which is
the whole point. Startup is one `bash` spawn plus N `command -v` forks; `command
-v` is a bash *builtin*, so N probes cost no extra processes -- a five-tool
check is one process, a few milliseconds. Runs on macOS and Linux with zero
deps, provided it stays bash-3.2-clean and avoids `jq` (the repo already treats
jq as an installable CI dep, see section 5). Maintenance cost is the real
objection: per-skill composability ("each skill declares which apply") means the
check needs a registry, a per-skill selector, and per-tool remediation text, in
bash -- and the repo's own history is that it moved exactly this class of logic
*out* of bash (work_summary.rs:1-16: "The security-critical,
determinism-focused logic that used to live in bash... is re-expressed here in
typed Rust"). But note the countervailing evidence: the two things the check
must do -- probe `command -v` and print a remediation line -- are trivial, and
the repo already implements the shirabe probe in bash twice
(run-cascade.sh:633-648, test-cli.sh:17-30).

**(b) Pure binary subcommand (`shirabe preflight`).** Structurally the nicest:
reuses the fail-safe hook idiom (exit 0 always, silence when satisfied), typed
per-skill manifests, `serde_json` output, unit tests colocated, one process
exec. But it cannot report its own absence. On a machine without the binary the
invocation is `command not found` / exit 127 with a shell-generated stderr line
that is *not* the host-appropriate instruction the design calls for -- and
whatever invokes it (a `!` injection, a hook, or a SKILL.md bash step) sees a
bare 127. The most important prerequisite becomes the one the check is silent
about. Fatal on its own.

**(c) Split: thin shell shim in the plugin, binary does the rest.** The shim
handles precisely the case the binary cannot: resolve the binary (the
run-cascade.sh precedence chain: `$SHIRABE_BIN` -> `command -v shirabe` ->
local `target/{release,debug}`), and if unresolved, print the shirabe-install
instruction itself and exit 0. If resolved, `exec` into `shirabe preflight
--skill <name>` so there is one process, not two. Costs: two artifacts to keep
in sync, and the shim's fallback message duplicates one string the binary also
owns -- mitigable the way `work-summary spec` mitigates it, by having the binary
own the canonical text and the shim carry only the "binary missing" case. Works
identically on macOS and Linux. This is also the option whose *hard* part (the
resolution chain) is already written and shipped in this repo.

A fourth consideration cuts across all three: the shim/script must be invoked as
`bash ${CLAUDE_PLUGIN_ROOT}/skills/<skill>/scripts/<name>.sh` (section 2), and
`${CLAUDE_PLUGIN_ROOT}` may be unset -- `preflight.sh:19` already shows the
self-resolution fallback, and `preflight_test.sh` case 1 tests exactly that with
`env -u CLAUDE_PLUGIN_ROOT`.

### 5. Testability

The repo has two mature CI conventions and one that is a poor fit.

**Shell tests -- strong, cross-platform, and already includes a "dependency
missing" idiom.** `.github/workflows/check-execute-scripts.yml` runs on a
`[ubuntu-latest, macos-latest]` matrix, installs jq per-OS, and runs `bash
skills/execute/scripts/run-cascade_test.sh` and `bash
skills/execute/scripts/preflight_test.sh`, triggered by `paths:
skills/execute/scripts/**`. `.github/workflows/check-plan-scripts.yml` goes
further, with a long comment worth quoting in full for the design: "macOS ships
bash 3.2 as /bin/bash and always will, so the macOS leg invokes `/bin/bash`
explicitly rather than `bash`: a newer bash on the runner's PATH would otherwise
hide a portability regression... This matrix IS the guard against reintroducing
a post-3.2 construct." A prerequisite-check shim inherits this floor: bash 3.2,
no `declare -A`, no namerefs. `check-template-consistency.yml` and
`check-templates.yml` run the root `scripts/*_test.sh` files on ubuntu only.

The missing-dependency case is directly testable in shell, and the repo already
does it: `preflight_test.sh` cases 3 and 4 build fake plugin roots with `mktemp
-d` and assert the failure path fires; `run-cascade_test.sh` injects
`SHIRABE_BIN` stubs and manipulates `PATH` (`PATH="$effective_path"
SHIRABE_BIN="$bin" bash "$CASCADE_SCRIPT"`, run-cascade_test.sh:216-221). A
"shirabe not on PATH" test is a `PATH=` scrub plus an `env -u SHIRABE_BIN` --
three lines in the established harness.

**Rust tests -- good depth, but Linux-only and can't test its own absence.**
`.github/workflows/build-and-test.yml` runs `cargo build --release` and `cargo
test --workspace` on `ubuntu-latest` only, no matrix. `crates/shirabe/tests/`
has 13 integration test files including `work_summary.rs` and `cli.rs`, so a
`preflight` subcommand's *satisfied/unsatisfied per-tool* logic is easy to cover
with env/PATH manipulation. What Rust cannot cover is the case that matters most
-- the binary itself not existing -- because the test harness has to run the
binary to test it.

**Skill evals -- the "dependency missing" case is already modeled here.**
`skills/work-on/evals/evals.json` eval id 10, `"name": "koto-not-installed"`,
`"scenario": "koto-missing"`, asserts the agent "detects that koto is not
installed or not on PATH" and installs it. The mechanism is
`skills/work-on/evals/fixtures/bin/koto`, a bash shim that returns `bash: koto:
command not found` / exit 127 when `EVAL_SCENARIO=koto-missing`.
`skills/execute/evals/fixtures/bin/koto` is the same file. So the repo already
has a pattern for simulating a missing prerequisite *end to end at the agent
level*. Caveat: evals run weekly on cron / workflow_dispatch (`run-evals.yml`),
need `ANTHROPIC_API_KEY`, and are transcript-graded -- they are not a PR gate.
`check-evals.yml` + `scripts/check-evals-exist.sh` enforce only that every
non-`disable-model-invocation` skill has at least one eval.

Net: a shell shim gets the strongest test coverage available in this repo (2-OS
matrix, PR-triggered, bash-3.2 floor, missing-dep cases already idiomatic). A
pure binary subcommand gets Linux-only unit coverage and structurally cannot
test the case that motivates the whole lead.

## Implications

- The bootstrapping problem is decisive against option (b) and neutral between
  (a) and (c). Whatever ships must have at least one always-present artifact
  that can speak when the binary cannot, and `.claude-plugin/marketplace.json`'s
  `"source": "./"` makes plugin files exactly that.
- The split is cheaper here than it looks because the shim's hard part is
  already written and reviewed: `run-cascade.sh:633-648`'s four-step resolution
  chain and `preflight.sh:19`'s `${CLAUDE_PLUGIN_ROOT:-self}` fallback can be
  lifted almost verbatim.
- The posture must differ from `skills/execute/scripts/preflight.sh`. That one
  exits 1 to halt the run; the proposed check is "prints and the agent decides,
  nothing hard-blocks," which is the `work_summary`/`pr_body_hook` exit-0
  fail-safe discipline. Reusing the name "preflight" for a script with the
  opposite exit contract inside the same plugin
  (`skills/execute/scripts/preflight.sh`) will confuse readers -- pick a
  distinct name or reconcile the two.
- Per-skill composability wants a declarative registry. In the split, the
  natural home is the binary (typed, unit-testable, `spec`-style
  self-documentation as in work_summary.rs:169-178) with the shim carrying only
  the skill name and the one bootstrap case.
- Version checks are a hidden second requirement. The README already promises
  koto ">= 0.3.3" and `work-on/SKILL.md:181` carries an install curl line; a
  check that only asks "is it on PATH" will not catch a stale `shirabe` whose
  subcommand the skill needs. `--version` parsing is meaningfully nicer in Rust
  than in bash 3.2.
- New CI is cheap and follows an existing template: a `check-<skill>-scripts.yml`
  clone with `paths:` on the new script directory, 2-OS matrix, and the macOS
  `/bin/bash` leg if the script is nontrivial.

## Surprises

- A file literally named `preflight.sh` already exists at
  `skills/execute/scripts/preflight.sh`, with its own test and its own CI job --
  and it is a *plugin-side shell* check that hard-fails, i.e. the shape this
  lead is asking about, already chosen once and shipped.
- The binary-presence probe is already implemented twice in bash, with a
  documented precedence chain including a `cargo build` fallback
  (`run-cascade.sh`, `test-cli.sh`) -- the "hard part" of the shim is not new
  code.
- The Rust test suite runs on Linux only (`build-and-test.yml` has no matrix)
  while the *shell* tests run on both Linux and macOS, including an explicit
  bash-3.2 leg. Cross-platform confidence in this repo currently comes from the
  shell tests, not the Rust ones.
- The plugin ships no `hooks.json` at all; `pr_body_hook`'s own doc comment says
  it is "Registered via dot-niwa" -- hook registration for this binary's
  existing hook subcommands lives entirely outside this repo.
- `install.sh` writes `~/.shirabe/env` and appends a source line to shell rc
  files, so "installed but not yet on PATH in this shell" is a real, common
  state that a naive `command -v shirabe` will report as "missing" -- the
  remediation text should distinguish "not installed" from "not sourced."
- The check-plan-scripts.yml comment explicitly rejects grep-based portability
  guards in favor of actually running the suite on the bash 3.2 floor, after a
  real regression (`declare -A` found, a bash 4.3 nameref missed).

## Open Questions

- What invokes the check, and does that invoker see stdout, stderr, or a
  hook-JSON channel? The three in-repo shapes differ: `` !`shirabe work-summary
  render` `` (SKILL.md dynamic injection, stdout relayed verbatim), `bash
  ${CLAUDE_PLUGIN_ROOT}/.../preflight.sh` (a SKILL.md instruction the agent
  runs), and a dot-niwa-registered hook (stdin JSON in, hook JSON out). The
  output contract can't be fixed until that lead lands.
- Is `${CLAUDE_PLUGIN_ROOT}` reliably exported in the invocation context the
  other lead settles on? `preflight.sh:19` and `preflight_test.sh` case 1 assume
  it may not be.
- Should the check enforce minimum versions (`shirabe --version`, `koto version`
  >= 0.3.3) or only presence? Nothing in the repo currently version-gates the
  shirabe binary from a skill.
- Where does the per-skill declaration live -- SKILL.md frontmatter (new key,
  needs a validator), a manifest file per skill directory, or a table compiled
  into the binary?
- Does the check need to run when the *plugin* is installed but the repo is not
  a git repo, or `gh` is unauthenticated? `skills/execute/SKILL.md:276` already
  treats "confirm `gh` auth is live" as a preflight concern, and auth is a live
  probe, not a `command -v`.
- Is `jq` allowed in the shim? Every shell CI job installs it explicitly (`brew
  install jq` / `apt-get install -y jq`), which implies it is not assumed
  present on user machines.

## Summary

The bootstrapping asymmetry is real and confirmed from the manifests:
`.claude-plugin/marketplace.json` ships the plugin as the repo itself
(`"source": "./"`) so `skills/*/scripts/*.sh` are always present at skill load,
while `release-binaries.yml` publishes only bare `shirabe-{os}-{arch}` assets
that `install.sh` or the tsuku recipe fetch separately -- no release bundles the
binary with the plugin, so a check living only in the binary cannot report its
own absence. The evidence points to a split: a thin bash shim in the plugin that
reuses the already-shipped resolution chain (`run-cascade.sh:633-648`) and
`${CLAUDE_PLUGIN_ROOT:-self-resolve}` fallback (`preflight.sh:19`) to handle the
binary-missing case itself, then `exec`s a fail-safe `shirabe preflight`
subcommand built on the exit-0, silent-when-clean discipline of
`pr_body_hook.rs` and `work_summary.rs` for everything else. Testability
reinforces this: shell tests run PR-triggered on a Linux+macOS matrix with an
explicit bash 3.2 leg and already simulate missing dependencies
(`preflight_test.sh` fake roots, `run-cascade_test.sh` PATH/`SHIRABE_BIN`
injection, the `koto-missing` eval shim), whereas `cargo test` runs on ubuntu
only and structurally cannot test the binary's own absence.
