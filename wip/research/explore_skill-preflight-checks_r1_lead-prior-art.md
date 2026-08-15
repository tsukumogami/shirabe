# Lead: How do comparable tools declare prerequisites and check them?

Research pass 1. Each system is examined against four questions: (1) where the
declaration lives, (2) whether checks compose per-unit or run all-or-nothing,
(3) what failure and success look like on the terminal, (4) whether install
advice is resolved per platform and how the system knows what the host can do.

A fifth question runs underneath all of them and is the one shirabe actually
cares about: **does a correctly configured machine pay anything?**

---

## Findings

### 1. Claude Code skills and plugins — the host itself

**Declaration.** There is no prerequisite field. `SKILL.md` frontmatter allows
`name`, `description`, `license`, `compatibility`, `metadata`, `allowed-tools`,
`disallowed-tools`, `hooks`, `shell`, `context`, `agent`, `model`, `effort`,
`disable-model-invocation`, `user-invocable`. Only six of those (`name`,
`description`, `license`, `compatibility`, `metadata`, `allowed-tools`) are
portable to claude.ai/API packaging; the rest are Claude Code extensions.
`metadata` is explicitly a "free-form YAML map for your own key-value data …
Claude Code doesn't act on its contents" — which is the only spec-legal place a
declarative `requires:` list could live without tripping the
`Unexpected key(s) in SKILL.md frontmatter` validator on the claude.ai path.

**The execution mechanism exists and is exactly what this exploration needs.**
Dynamic context injection: `` !`<command>` `` at the start of a line or after
whitespace runs *before* the skill content is sent to the model, and the command
output replaces the placeholder in-place. A fenced ` ```! ` block does the same
for multi-line commands. Combined with `${CLAUDE_PLUGIN_ROOT}` substitution —
which is applied both in the body *and* in `allowed-tools` Bash rules, so
`allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh *)` matches the
exact command the body invokes and runs without a permission prompt — this gives
a deterministic, prompt-free, load-time hook per skill.

Four caveats found in the docs, all load-bearing here:

- Substitution runs **once** over the original file; output is not re-scanned,
  so a check cannot emit a placeholder for another pass.
- `disableSkillShellExecution: true` in settings replaces every command with
  `[shell command execution disabled by policy]`. Managed settings can force it.
  A preflight design must degrade to "no output" rather than "broken skill" when
  that placeholder appears.
- On Windows without Git Bash, `shell: bash` **fails the whole invocation**:
  ``Skill <name> requires bash (`shell: bash` in frontmatter) but Git Bash was
  not found``. A bash preflight script is therefore itself a portability
  liability on that host.
- Skill content lifecycle: re-invoking a skill whose *rendered* content is
  identical to the copy already in context adds a short "already loaded" note
  instead of a second copy. **If the check output differs between invocations,
  the entire skill body is appended again.** So variable output (timestamps,
  version strings, elapsed time) is not merely noise — it can cost a full
  re-injection of the skill. Zero output on success is the only shape that
  guarantees identical renders.

Skill-level `hooks` frontmatter registers hooks at invocation that keep running
for the rest of the session, with a `once` option. That is a second, heavier
mechanism — better suited to enforcement than to a one-shot check.

**Prior art in the wild: nobody ships a real check.** Surveying the installed
`anthropic-agent-skills` marketplace, prerequisite handling is entirely prose,
and interestingly it is prose written for a *known* environment:

- `xlsx/SKILL.md`: "`openpyxl`, `pandas`, and `markitdown` are preinstalled — do
  not run `pip install` first; write the script and import directly. Only if an
  import fails (or the `markitdown` command is missing): `pip install` the
  missing package."
- `pptx/SKILL.md`: same pattern for `react-icons`, `react`, `react-dom`, `sharp`
  — "preinstalled — `npm install …` only if a require fails".
- `pdf/SKILL.md`: a bare `# Requires: pip install pytesseract pdf2image` comment
  inside a code sample.

The design is "assume present, remediate lazily on failure, and spend prompt
tokens telling the model not to pre-emptively install". Cost is paid in context
on every load, and correctness depends on the model obeying prose. shirabe's own
`skills/work-on/SKILL.md:178` is the same shape: "Run `koto version` to verify
koto >= 0.3.3 is installed. If missing: `curl -fsSL …/install.sh | bash`" — a
version floor, a check command, and an install command, all as instructions to
the model rather than as an executed check.

**Success output.** N/A — nothing runs. **Per-platform advice.** None; the
skills assume a single known container image, which is exactly the assumption
shirabe cannot make.

### 2. direnv — `has`, and silence as the default

**Declaration.** Imperative, in `.envrc`, using the stdlib. `has` is documented
as: "Returns 0 if the *command* is available. Returns 1 otherwise. It can be a
binary in the PATH or a shell function." Canonical usage from the man page:

```bash
if has curl; then
  echo "Yes we do"
fi
```

**Composition.** Fully per-unit: `has` is a one-command predicate, and callers
compose. direnv uses it internally — the `layout` dispatcher calls `has
layout_$1` before dispatching. There is also `env_vars_required`, which logs an
error for each missing/empty variable, the closest thing in the stdlib to a
declarative "these must exist" list.

**Failure vs success.** `has` itself prints nothing either way; it is a pure
exit code. Output is the caller's choice via `log_status` / `log_error`. direnv
proper prints its `direnv: loading .envrc` / `export …` lines, but the primitive
is silent. **This is the cleanest prior art for the zero-cost-on-success
requirement, and it achieves it by separating the predicate from the reporting.**

**Per-platform advice.** None. `has` answers "is it here", never "how do I get
it". direnv deliberately delegates provisioning to `use nix` / `use flake` /
`layout python`, i.e. to a real package manager, and keeps the check dumb.

### 3. devcontainer features — the maintenance-cost case study

**Declaration.** `devcontainer-feature.json` per feature, with `dependsOn` (hard
dependencies, recursively resolved and *installed* by the tool) and
`installsAfter` (ordering hint only — a plain string array; if the named feature
is not already in the install queue from `devcontainer.json` or a `dependsOn`
chain, the relationship is **silently ignored**). Consumers declare features in
`devcontainer.json`.

**Composition.** Per-feature and graph-resolved. This is the best dependency
model in the survey: two distinct edge types, one that pulls in and one that
merely orders.

**Failure vs success.** Not a check at all — it's a build-time installer. There
is no "is it already here" question because the container starts empty. Output
is full build logs.

**Per-platform advice.** Each feature ships an `install.sh` that runs as root at
image build time, and the per-platform matrix is **hand-written inside every
feature**. The official `devcontainers/features` `github-cli` install script is
~280 lines, hardcodes `apt-get` and `dpkg` throughout, derives architecture from
`dpkg --print-architecture`, and — despite sourcing `/etc/os-release` — does not
branch on distro at all: it is Debian/Ubuntu only. Signing-key import, repo
setup, and fallback-to-GitHub-release logic are all bespoke. That is the honest
price of a hardcoded install matrix, per tool, forever, maintained by the feature
author. Multiply by shirabe's tool list and it is unsustainable.

### 4. mise and asdf — declaration plus a *tri-state* noise setting

**Declaration.** `mise.toml` (`[tools] node = "22"`) or the asdf-compatible
`.tool-versions`. Purely declarative, version-pinned, hierarchical (nearest
config wins; `mise use -g` writes the global one).

**Composition.** Per-tool entries; commands operate on the resolved set. Not
skill-like subsetting, but `mise x`, `mise run`, and tasks each resolve only
what they need.

**Failure vs success — the most directly transferable finding in this report.**
mise has an explicit setting for exactly the tension shirabe is navigating:

- `status.missing_tools` — default `if_other_versions_installed`; values
  `always`, `never`, `if_other_versions_installed` ("show the warning only when
  the tool has at least 1 other version installed").
- `status.show_tools` — default **`false`**.
- `status.show_env` — default **`false`**.

So on a correctly configured machine, `cd` into a mise project prints **nothing**.
The defaults were chosen so that the healthy case is silent and the warning
fires only on the heuristic most likely to indicate a real mistake. The failure
mode of the middle setting is visible in the wild: asdf→mise migrants get
persistent WARN spam precisely because old versions are on disk and new pins are
not — i.e. the heuristic is right, and it is still annoying when the diagnosis
is "you haven't run install yet".

mise also documents an explicit rationale for *not* auto-installing on directory
entry: auto-installing during shim execution or the `hook-env` prompt hook "would
add unpredictable latency to shell prompts and command invocations — a `cd` into
a project directory shouldn't silently block while downloading and installing
tools." That is a direct argument against a preflight that self-heals at skill
load: latency at an interaction boundary is worse than a message.

asdf is the counter-example on message quality. A missing pinned version yields
"No version is set for command X" plus advice to create a `.tool-versions` file —
which is wrong in the common case: the file exists, the version simply isn't
installed. Multiple open issues (asdf #1285, #2142, #2232, #2033) are about this
one misleading string. The lesson: **a check that misdiagnoses is worse than no
check**, because the reader (human or agent) acts on the diagnosis.

**Per-platform advice — the delegation answer.** mise carries a **registry**: a
compile-time-generated mapping from shorthand (`node`, `terraform`, `aws-cli`) to
a backend spec (`core:node`, `aqua:hashicorp/terraform`, `aqua:aws/aws-cli`).
The registry is compiled into the binary from TOML files in `registry/`. Backend
policy is explicit: aqua preferred, github next, new asdf/vfox plugins refused
for supply-chain reasons, ubi deprecated. The upshot is that
`mise use -g <tool>` is a **single, platform-independent install instruction**
that resolves to the right artifact for the host — the maintenance of the
matrix is aqua's and mise's problem, not the caller's. Also relevant:
`not_found_auto_install` (default true) wires `command_not_found_handler` →
`mise hook-not-found` → install → re-run.

### 5. pre-commit — good declaration, deliberately noisy output

**Declaration.** `.pre-commit-config.yaml`: `repo` + `rev` + per-hook `id`, with
optional `language`, `entry`, and `additional_dependencies`. The version floor is
the pinned `rev`, i.e. an exact revision rather than a range.

**Composition.** Per-hook, and pre-commit builds an isolated environment per
hook per language (python venv, node prefix, etc.) in the user cache, installing
`additional_dependencies` into it. This is the "bootstrap rather than check"
philosophy: it doesn't ask whether black is installed, it owns a black. The
escape hatch is `language: system`, which *does* depend on the host and fails
with ``Executable `X` not found`` — and that error is a known source of
confusion when a GUI git client has a different PATH than the terminal.

**Failure vs success.** Prints one aligned `hookname..........Passed` line per
hook, always. First run additionally prints environment-creation progress, which
can take minutes. There is no quiet mode; requests for one are long-standing
open issues (pre-commit #823, #957, #1805 — "silence passed and/or skipped
hooks … to keep scrollback clean"). The maintainer's implicit position is that
the checklist *is* the product. **This is the anti-pattern for shirabe:** a green
checklist per unit, unsuppressible, on every run.

**Per-platform advice.** None needed — it provisions its own environments and
therefore never has to tell you how to install anything.

### 6. The doctor family — all of them print on success

**flutter doctor.** The abstraction (`packages/flutter_tools/lib/src/doctor_validator.dart`)
is genuinely good and worth stealing structurally:

- `enum ValidationType { crash, missing, partial, notAvailable, success }` —
  note `partial`, which is the "present but wrong version / misconfigured" state
  that a boolean `has`-style check cannot express.
- `ValidationMessage` has three constructors — default (information),
  `.hint(...)`, `.error(...)` — with `isError` / `isHint` / `isInformation`
  accessors and per-message glyphs (`✗`, `!`, `•`).
- `ValidationResult(this.type, this.messages, {this.statusInfo})` with a
  `leadingBox` rendering `[☠]`, `[✗]`, `[✓]`, `[!]`, plus an `executionTime`.
- `GroupedValidator` merges child results with precedence rules: a crash or a
  missing demotes an otherwise-successful group to `partial`.

Per-validator composition is exactly the shape shirabe wants (one validator per
prerequisite; a skill selects a subset). But: **"No explicit suppression
mechanism exists in this abstraction. All validation results, including
successful ones, retain their message lists for potential display."** flutter
doctor is architecturally incapable of being silent when healthy. Its install
advice is prose embedded in the individual validators, hand-maintained by the
Flutter team in Dart source, per platform (Xcode paths, Android SDK locations,
`flutter doctor --android-licenses`, "run `sudo xcode-select --install`" and
friends). Nobody delegates it to a package manager. That is the maintenance
answer for the doctor pattern: **a paid team maintains it as product surface.**

**brew doctor.** Prints "Your system is ready to brew." on success, to stdout;
problems go to stderr (Homebrew discussion #5503). So: not silent, but at least
one line rather than a matrix.

**nix doctor.** "checks your system for potential problems and prints a PASS or
FAIL for each check" — a full checklist every time, healthy or not.

**brew bundle check.** The closest thing to shirabe's desired shape in the
Homebrew world: a `Brewfile` is the declaration, `brew bundle check` is the
predicate, it exits successfully when everything is satisfied and prints "The
Brewfile's dependencies are satisfied." When unsatisfied, the bare command tells
you to re-run with `--verbose` to get the list — a two-step failure UX that is
actively hostile to a non-interactive reader (issues #320, #1242 chase both the
exit code and the "more meaningful output" problem). Design note: it is still
one line on success, not zero.

**rustup check.** Prints a table of channel/version/status unconditionally.

### 7. Declarative version floors with automatic enforcement

| System | Declaration | Enforcement on violation | Output when satisfied |
|---|---|---|---|
| npm `engines` | `package.json` `engines: {node: ">=18"}` | `EBADENGINE` **warning** by default; `engine-strict=true` in `.npmrc` promotes it to an error that aborts install | silent |
| Cargo `rust-version` | `Cargo.toml`, bare version, no semver operators | hard **error**; `--ignore-rust-version` opts out; also feeds the MSRV-aware resolver, and `cargo add` auto-selects the newest dependency version compatible with your MSRV and tells you when that isn't the latest | silent |
| Go `go` / `toolchain` in `go.mod` | `go 1.21` + optional `toolchain go1.22.3` | **no message — it fixes it**: `GOTOOLCHAIN=auto` (the default) downloads and switches to the required toolchain; `GOTOOLCHAIN=local` restores fail-if-old | silent |
| .NET `global.json` | `sdk.version` + `rollForward` policy | `NETSDK1141` error naming the missing version | silent |
| Terraform `required_version` | `terraform` block | error, no install advice | silent |

Four of five are **silent on success and speak only on violation**, and all four
are declarative data, not scripts. Go is the outlier in the useful direction: it
converts the check into remediation and says nothing at all. npm is the outlier
in the interesting direction: it ships the check as a *warning* by default and
lets a per-consumer setting escalate it — which is structurally identical to
shirabe's "print and the agent decides, never hard-block" constraint.

Notably, **none of these five resolve per-platform install advice.** They say
"you need 1.56"; they never say "brew install rust". The version-floor family and
the install-advice family are disjoint in the prior art.

### 8. Delegating install advice to a package manager (the maintenance answer)

The only systems that produce host-appropriate install instructions *without*
hand-maintaining a matrix all do the same thing: query a package database that
someone else maintains.

- **Debian/Ubuntu `command-not-found`.** Hooks the shell's
  `command_not_found_handle`; on a miss it searches a package database for
  packages providing a binary of that name and prints the `apt install` line. The
  database ships with the distro and is regenerated by the distro. Zero
  per-command maintenance for anyone downstream.
- **`homebrew-command-not-found`** — the same idea on macOS, backed by a
  pre-generated index of which formula provides which executable.
- **`nix-index` + `comma`.** `nix-index` builds a file→package index over
  nixpkgs; `comma` prefixes any command with `,` to fetch and run it from
  whatever package provides it. `nix-index-database` publishes pre-generated
  indexes on a schedule so consumers never build one.
- **mise's registry** (above): shorthand → backend, so one instruction
  (`mise use -g X`) covers every platform mise supports.

The generalization: **an install-advice system either owns a package index or
borrows one.** Hand-writing `brew install X` / `apt install X` / `dnf install X`
per tool is the devcontainer-feature and flutter-doctor path, and both are
maintained by full-time teams. For a ~20-skill plugin, the sustainable options
are (a) print the tool name and a canonical upstream URL and let the agent
figure out the host, or (b) delegate to one cross-platform installer that
already owns the matrix — and this workspace happens to ship one (`tsuku`), plus
mise is a credible external fallback.

---

## Implications

1. **The mechanism is already in the host and needs no invention.**
   `` !`${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh <tools>` `` plus a matching
   `allowed-tools: Bash(${CLAUDE_PLUGIN_ROOT}/scripts/preflight.sh *)` rule
   gives a deterministic, permission-free, per-skill check at load. The design
   work is in the output contract and the declaration format, not the plumbing.

2. **Zero-output-on-success is not just a taste preference here — it is load
   bearing for context.** Because identical rendered content is deduplicated on
   re-invocation and *differing* content causes the whole skill body to be
   appended again, any check that prints something variable (versions, timings,
   even a `✓` list that changes as tools come and go) turns a re-invocation into
   a second full copy of the skill. Silence on success is the only output shape
   that keeps the dedup working.

3. **Split the predicate from the reporter, direnv-style.** `has`-shaped
   primitives that return exit codes, with a thin reporter that only speaks on
   failure, is the only architecture in this survey that achieves silence.
   flutter's `DoctorValidator` gives the right *composition* model but its
   result objects always carry messages; adopt the enum, not the renderer.

4. **Steal `ValidationType.partial`.** A boolean "is it on PATH" cannot express
   "gh is installed but 2.20 and we need 2.40", which is precisely shirabe's
   existing `koto >= 0.3.3` case. Three states minimum: satisfied, missing,
   present-but-below-floor. The remediation differs (install vs upgrade), and
   asdf's bug tracker is the cautionary tale for collapsing them.

5. **Declaration should be data in frontmatter, and `metadata:` is the only
   spec-legal home.** `metadata` is documented as free-form and ignored by
   Claude Code, and using a novel top-level key trips the
   `Unexpected key(s) in SKILL.md frontmatter` validator on the claude.ai and
   Skills-API packaging paths. A `metadata.requires` list keyed by tool name and
   floor keeps skills portable and lets a single shared script read it.
   devcontainer's two-edge model (`dependsOn` pulls in, `installsAfter` only
   orders) is more machinery than ~20 skills need; a flat list per skill is the
   right altitude.

6. **Do not hand-maintain a per-platform install matrix.** The prior art that
   does (devcontainer features, flutter doctor) is maintained by funded teams,
   and the github-cli feature — 280 lines, Debian-only, sourcing `/etc/os-release`
   without branching on it — shows how it rots. Prefer delegating to one
   installer that owns an index (tsuku here, mise as the external precedent), or
   emit tool name + canonical URL and let the agent resolve the host. If a
   matrix is unavoidable, keep it in *one* table keyed by tool, not per skill.

7. **The reader is an agent, and that changes the target.** Every "success"
   output in this survey — flutter's `[✓]` boxes, nix's PASS lines, brew's "Your
   system is ready to brew", pre-commit's Passed column, rustup's table — exists
   to reassure a human that the tool did something. An agent needs none of that
   reassurance; for it, a green checklist is pure token cost plus a distraction
   risk (an agent that reads `[✓] gh 2.40.0` may start narrating environment
   status to the user). Conversely, `brew bundle check`'s "re-run with
   `--verbose` to see what's missing" is a human-interactive affordance that is
   simply broken for a one-shot non-interactive reader: **failure output must be
   complete on the first emission**, because there is no second run.

8. **Failure output should be an instruction, not a diagnosis.** npm's model —
   warn by default, let a setting escalate — matches the "print and the agent
   decides, never hard-block" constraint exactly. The text should be shaped as
   something the agent can act on directly ("`gh` not found — install it, then
   re-run") rather than as a status report, and it should say what the *skill*
   will fail to do without it, because the agent's decision is whether to
   proceed degraded.

9. **Consider whether some checks should self-heal instead.** Go's
   `GOTOOLCHAIN=auto` is the endgame: no message, because the problem is fixed.
   mise's counter-argument is equally instructive — it deliberately refuses to
   auto-install at directory entry because unpredictable latency at an
   interaction boundary is worse than a warning. Skill load is exactly such a
   boundary, so auto-install is the wrong default; but for a tool this project
   controls (koto), "check and offer the one-line install" is already what
   `work-on` does in prose.

---

## Surprises

- **Almost nothing in the doctor family can be quiet.** flutter's validator
  layer has no suppression mechanism at all, by construction; nix doctor prints
  PASS per check; rustup prints a table; brew prints a sentence. The entire
  category treats the green checklist as the deliverable. The systems that *are*
  silent when healthy are the ones that aren't "doctors" at all — direnv's `has`,
  npm engines, cargo `rust-version`, `go.mod`, mise's `status.*` defaults.

- **mise has already litigated this exact trade-off in public.** A three-valued
  `status.missing_tools` setting (`never` / `if_other_versions_installed` /
  `always`) with `show_tools` and `show_env` both defaulting to `false` is a
  designed answer to "when is a warning worth the noise", and the migration-spam
  complaints show the middle heuristic still misfires. Worth reading as a
  settled precedent rather than re-deriving.

- **pre-commit's noise is a decade-old unresolved feature request.** Issues
  #823, #957, and #1805 all ask for quiet mode; none landed. A per-unit green
  checklist is easy to ship and apparently very hard to walk back.

- **The `!` command output affects context accounting, not just readability.**
  The "identical rendered content is deduplicated, differing content is
  re-appended in full" rule means a chatty preflight has a *multiplicative*
  context cost on re-invocation, not an additive one. This did not appear in any
  of the external prior art because none of it has a context window.

- **Anthropic's own skills assume a fixed environment.** The xlsx/pptx pattern
  ("preinstalled — do not run `pip install` first; only if an import fails") is
  well-tuned for a known container and provides no template for a plugin that
  runs on arbitrary developer laptops. There is no prior art to copy inside the
  ecosystem; shirabe would be defining it.

- **Version floors and install advice never co-occur in prior art.** npm, Cargo,
  Terraform, and .NET all tell you the version you need and nothing about how to
  get it. The systems that tell you how to install (command-not-found,
  nix-index/comma) are version-blind. Combining the two is a genuinely
  unoccupied spot, which is either an opportunity or a warning.

- **A single skill body can be killed by its own preflight on Windows.**
  `shell: bash` with no Git Bash fails the invocation before any command runs —
  so adding a bash preflight to a skill that would otherwise have worked is a
  net regression on that host. Any design needs a "check is best-effort" posture,
  including graceful behavior under `disableSkillShellExecution`.

---

## Open Questions

1. **Where does the declaration live given the frontmatter validator?**
   `metadata.requires` is spec-legal and ignored by the host, but it is inert —
   something must read it. Options: the `!` command receives the tool list as
   literal arguments in the body (simple, duplicated), or the script parses its
   own skill's `SKILL.md` (single source of truth, needs the skill path — is
   `${CLAUDE_SKILL_DIR}` available in plugin skills alongside
   `${CLAUDE_PLUGIN_ROOT}`?). Needs verification against the docs.

2. **What is the actual latency budget?** mise's argument against auto-install at
   a boundary is latency. A `command -v` sweep over 3-5 tools is sub-10ms, but a
   version check that *executes* each tool (`gh --version`, `koto version`) costs
   process spawns — measure before assuming free. Caching (a stamp file keyed on
   PATH + tool mtimes) is available if it isn't.

3. **What does a failed check say, exactly, for an agent reader?** Nothing in the
   prior art is written for this audience. Needs a decision on: one line per
   missing tool or one block; whether to name the affected capability ("`gh` is
   needed for the PR step"); whether to emit a machine-readable marker the skill
   body can reference; and whether install advice is a command, a URL, or a
   delegation (`tsuku install gh`).

4. **Delegate to tsuku, or stay generic?** tsuku is in-workspace and owns exactly
   the "resolve install per platform" problem, but shirabe is a public plugin and
   a hard tsuku dependency is a chicken-and-egg (tsuku itself would need
   installing). Precedent from mise says delegation is the only sustainable
   option; precedent from direnv says the check should stay dumb and delegate
   nothing. Possibly: name the tool, and offer tsuku *if tsuku is present*.

5. **Does anything need the `partial`/version-floor path today besides koto?**
   The grep across `skills/*/SKILL.md` found exactly one version floor
   (`koto >= 0.3.3` in `work-on`). If that is the whole population, a three-state
   validator may be over-built and a `has`-shaped binary check plus one special
   case for koto is the honest scope. Worth counting the real prerequisite
   surface across all ~20 skills before designing for generality.

6. **How does the check behave under `context: fork` / `agent:` subagent
   execution?** Several shirabe skills run work in subagents. If a forked context
   re-renders the skill, does the `!` command run again per fork, and does the
   dedup rule apply across the boundary?

7. **Should failure be sticky?** Skill content persists in context for the rest
   of the session and is not re-read. A tool installed mid-session after a failed
   check leaves a stale "gh not found" line in context forever. The `hooks`
   frontmatter with `once` is an alternative surface — worth checking whether a
   hook can emit a correction later, or whether the design should just tell the
   agent the check was point-in-time.

---

## Summary

The prior art splits cleanly: systems that stay silent when healthy (direnv's
`has`, npm `engines`, Cargo `rust-version`, `go.mod` toolchains, mise's
`status.*` defaults — all of which separate a bare predicate from any reporting,
or fix the problem instead of announcing it) versus the entire doctor family
(flutter, nix, brew, rustup, pre-commit), which is architecturally incapable of
quiet because the green checklist is treated as the product. Claude Code already
supplies the exact mechanism shirabe needs — `` !`command` `` dynamic context
injection with `${CLAUDE_PLUGIN_ROOT}` substituted into both the body and
`allowed-tools`, so a bundled preflight script runs deterministically at skill
load without a permission prompt — and silence on success is doubly required
here, because differing rendered content causes the whole skill body to be
re-appended to context on re-invocation rather than deduplicated. On the
maintenance question, nobody sustains a hand-written per-platform install matrix
without a funded team (devcontainer's github-cli feature is 280 apt-only lines;
flutter doctor's advice is hardcoded in Dart per platform); every system that
gets this right borrows someone else's package index — Debian's
command-not-found database, nix-index, or mise's compiled shorthand→backend
registry — which argues for delegating shirabe's install advice to one
cross-platform installer rather than enumerating brew/apt/dnf per tool.
