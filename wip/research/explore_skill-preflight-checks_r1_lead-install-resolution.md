# Lead: How can install instructions be resolved to commands known to work on the host?

## Findings

### 1. The real dependency set, and every install route that exists today

Grepping the skills for external commands gives a short list, not a long one. Counting
mentions across `skills/*/SKILL.md` and the scripts they call:

| Tool | Who needs it | Evidence |
|---|---|---|
| `shirabe` | nearly every skill (`shirabe validate`, `roadmap populate`, `transition`, `finalize-chain`, `slug-prefix-detect`, `install-hooks`) | 95 mentions across SKILL.md files |
| `gh` | `/plan`, `/work-on`, `/execute`, `/roadmap` (issues, PRs, milestones, CI) | 83 mentions |
| `koto` | `/work-on` and `/execute` only, floor `>= 0.3.3` | 52 mentions |
| `jq` | script layer of `/plan`, `/execute`, `/work-on` | 140 call sites under `skills/*/scripts/` and `scripts/` |
| `git` | universal | assume present; a repo without git is not a shirabe host |

`node` appears in SKILL.md prose 14 times but every one is a DAG node, not Node.js. There
is no Python, no `rg`, no `yq` dependency. One script (`skills/plan/scripts/validate-plan.sh`)
uses `mapfile`/`declare -A`, so it needs bash >= 4 — that is a real macOS trap
(`/bin/bash` is 3.2) but out of scope for a tool-presence check.

So the matrix has **four uncertain tools**, not a dozen.

**Route inventory, per tool, verified from files in this repo and the sibling public repos:**

`shirabe` — three routes.
1. `curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/main/install.sh | bash`
   — installs to `~/.shirabe/bin/shirabe`, writes `~/.shirabe/env` with a PATH export, and
   appends `. "$HOME/.shirabe/env"` to `~/.zshenv` or `~/.bashrc`/`~/.bash_profile`.
   `install.sh` already does the OS/arch detection the lead asked about (lines 30-50):
   `uname -s | tr` lowercased to `linux|darwin`, `uname -m` normalized `x86_64|amd64 → amd64`,
   `aarch64|arm64 → arm64`, anything else is a hard exit. The release asset name it builds,
   `shirabe-${OS}-${ARCH}`, is exactly the four-way matrix shirabe ships.
2. `tsuku install -y tsukumogami/shirabe` — `.tsuku-recipes/shirabe.toml` at this repo root
   is a complete distributed recipe: GitHub version provider on `tsukumogami/shirabe` with
   `tag_prefix = "v"`, a `download` step with `checksum_url` pointing at `checksums.txt`,
   `chmod`, `install_binaries` to `bin/shirabe`, and `verify` running `shirabe --version`
   against the resolved version. It resolves `{os}`/`{arch}` itself. This is the same
   binaries as route 1 with checksum verification and version bookkeeping added.
3. Download the asset from the releases page by hand. Not worth printing to an agent.

`koto` — the same three shapes.
1. `curl -fsSL https://raw.githubusercontent.com/tsukumogami/koto/main/install.sh | bash`
   — this is the command `skills/work-on/SKILL.md:178` already prints. Installs to
   `~/.koto/bin/koto` (override with `KOTO_INSTALL_DIR`), writes `~/.koto/env`, same
   `uname` detection, and accepts `--version=X.Y.Z` for pinning — which matters because
   koto has a version floor, not just a presence requirement.
2. `tsuku install -y tsukumogami/koto` — `public/koto/.tsuku-recipes/koto.toml` exists,
   so the distributed-source route is live. This repo's own `.tsuku.toml` already declares
   `"tsukumogami/koto" = "latest"`.
3. `cargo install` from source (koto is Rust). Slow; never the right advice for an agent.

`gh` — `tsuku install -y gh` (`recipes/g/gh.toml` in the tsuku monorepo, curated, darwin+linux,
amd64+arm64, pulling GitHub's own release archives), `brew install gh`,
`sudo apt install gh` (after adding the cli.github.com apt repo — plain `apt install gh`
is not reliable on older Debian/Ubuntu), `sudo dnf install gh`, `sudo pacman -S github-cli`.
**Important caveat found in this repo:** `.tsuku.toml` has gh commented out with
`# disabled: segfaults on Linux (tsukumogami/tsuku#2245)`. So shirabe's own project config
already declares the tsuku route for gh unusable on Linux. Any generated advice that prints
`tsuku install gh` on a Linux host would be printing a command this repo knows is broken.

`jq` — `tsuku install -y jq` (`recipes/j/jq.toml`), `brew install jq`, `sudo apt install jq`,
`sudo dnf install jq`, `sudo pacman -S jq`. jq is the least interesting: it is present on
almost every developer host and in every CI image.

The README's Requirements section (lines 202-208) currently states this in prose: Claude Code,
the `shirabe` binary "install it before you use them", and koto >= 0.3.3 with the note that
"the skills check `koto version` first and give you an install command when it's missing".
That last clause is the existing precedent — `/work-on` already does exactly the thing this
exploration is about, for exactly one tool, in prose.

### 2. What `tsuku install` actually does here

tsuku is a no-sudo package manager that installs into `$TSUKU_HOME` (default `~/.tsuku`):
binaries land in `~/.tsuku/tools/<name>-<version>/` with the active version symlinked through
`~/.tsuku/tools/current/`, and `~/.tsuku/bin/` holds shims plus tsuku itself. It has a
`doctor` subcommand whose second check is literally "tools/current is in PATH", plus
`which`, `list`, `shellenv`, and `activate`.

Two things make it the strongest single answer for this lead:

**(a) It can install all four tools.** `tsukumogami/shirabe` and `tsukumogami/koto` resolve
through the distributed-recipe path (a `.tsuku-recipes/<name>.toml` in the target GitHub repo;
when the repo has exactly one recipe the recipe name can be omitted, which is why the bare
`tsukumogami/koto` form works). `gh` and `jq` are curated central-registry recipes. First
install from a new source prompts for trust — `-y` skips it, so the agent-safe forms are:

```bash
tsuku install -y tsukumogami/shirabe
tsuku install -y tsukumogami/koto
tsuku install -y jq
tsuku install -y gh          # avoid on Linux, see tsukumogami/tsuku#2245
```

**(b) The project manifest is real and `tsuku install` with no args honors it.**
`cmd/tsuku/install_project.go` implements `runProjectInstall`: it discovers the nearest
`.tsuku.toml`, parses `[tools]` (quoted keys carry the org scope — the design doc
`DESIGN-org-scoped-project-config.md` in the tsuku repo is entirely about making
`"tsukumogami/koto" = "latest"` work), pre-scans for `/` to batch-bootstrap distributed
sources once each via `ensureDistributedSource`, warns about unpinned versions, prompts
`Proceed? [Y/n]` only when interactive, and installs each tool leniently — a failure on one
tool does not abort the rest. So in this repo:

```bash
tsuku install -y     # reads .tsuku.toml, installs everything declared
```

is a genuine one-command answer. The catch: **shirabe's skills do not run in shirabe's repo.**
They run in whatever downstream repo the plugin is installed into, and that repo has no
`.tsuku.toml` unless someone wrote one. `runProjectInstall` errors with
`no .tsuku.toml found (run 'tsuku init' to create one)` and exits with a usage code. And
shirabe's own `.tsuku.toml` doesn't even declare `shirabe` — only `tsukumogami/koto`, since
shirabe builds itself from source here. So the no-args form is a great answer for contributors
to this repo and a non-answer for the actual audience, unless shirabe starts shipping a
`.tsuku.toml` fragment for downstream repos to copy. That's a design option, not a fact.

The per-tool `tsuku install -y <name>` form has no such constraint and works from any cwd.

**PATH mechanics that the check has to know about.** tsuku writes `~/.tsuku/env`:

```sh
export PATH="${TSUKU_HOME:-$HOME/.tsuku}/bin:${TSUKU_HOME:-$HOME/.tsuku}/tools/current:$PATH"
```

so a tool installed by tsuku appears at `~/.tsuku/tools/current/<name>`. On this very host,
`command -v koto` and `command -v shirabe` return `/Users/danielgazineu/.tsuku/tools/current/koto`
and `.../shirabe` — the tsuku route is not hypothetical, it is what the workspace already uses.
The three installers each own a different directory, and a check that wants to distinguish
"not installed" from "installed but not on PATH" must know all four:

- `~/.tsuku/tools/current/` and `~/.tsuku/bin/` (tsuku), sourced by `~/.tsuku/env`
- `~/.shirabe/bin/` (shirabe install.sh), sourced by `~/.shirabe/env`
- `~/.koto/bin/` (koto install.sh, or `$KOTO_INSTALL_DIR/bin`), sourced by `~/.koto/env`

### 3. Cheap host signals and a precedence order

Every signal below is a single builtin or one `uname`; the whole probe is well under 50ms
and needs no network.

| Signal | Probe | Cost |
|---|---|---|
| tool on PATH | `command -v <tool>` | builtin |
| version floor met | `koto version`, `shirabe --version` | one exec, only for koto/shirabe |
| installed-but-unlinked | `[ -x "$HOME/.tsuku/tools/current/<t>" ]`, `[ -x "$HOME/.shirabe/bin/shirabe" ]`, `[ -x "${KOTO_INSTALL_DIR:-$HOME/.koto}/bin/koto" ]` | stat |
| tsuku available | `command -v tsuku` \|\| `[ -x "$HOME/.tsuku/bin/tsuku" ]` | builtin + stat |
| OS | `uname -s` → `Darwin`/`Linux` | one exec |
| arch | `uname -m` → `arm64`/`aarch64`/`x86_64` | one exec |
| package managers | `command -v brew apt-get dnf pacman cargo mise` | builtins |
| network | do **not** probe | see below |

**Proposed precedence, and why:**

1. **`command -v <tool>` succeeds and any version floor passes → print nothing.** The silent
   path must be the cheapest and must never touch the network. For koto this is
   `koto version` parsed against 0.3.3; for shirabe there is no declared floor today, so
   presence is enough.

2. **Binary exists in a known install dir but `command -v` fails → this is a PATH problem, and
   it gets its own message.** This is the case the lead calls out and it deserves to be second,
   above every install route, because printing an install command here is actively wrong: the
   agent re-downloads a binary it already has, the install succeeds, `command -v` still fails,
   and the loop repeats. The right output names the env file:

   ```
   koto is installed at ~/.tsuku/tools/current/koto but not on PATH.
   Run: . "$HOME/.tsuku/env"
   ```
   (or `. "$HOME/.koto/env"` / `. "$HOME/.shirabe/env"` depending on which directory matched).
   `tsuku doctor --fix` is the heavier repair when the env file itself is stale.

3. **Tool absent, `tsuku` reachable → `tsuku install -y <spec>`.** One route, four tools, no
   sudo, no OS branch, checksum-verified, and it is what this workspace already runs. Reachable
   means on PATH *or* present at `~/.tsuku/bin/tsuku` — in the latter case print the
   `. "$HOME/.tsuku/env"` line first. The single exception is `gh` on Linux, where
   `tsukumogami/tsuku#2245` sends you to step 4.

4. **Tool absent, no tsuku → the tool's own canonical installer, then the OS package manager.**
   For `shirabe` and `koto` the vendor `install.sh` is unambiguously correct and identical on
   macOS and Linux, because the script does the OS/arch branch internally — that is the single
   most useful thing found in this lead. There is no macOS-vs-Linux fork to encode for the two
   first-party tools at all:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/tsukumogami/shirabe/main/install.sh | bash
   curl -fsSL https://raw.githubusercontent.com/tsukumogami/koto/main/install.sh | bash
   ```

   Only `gh` and `jq` need the `uname -s` + package-manager branch, and only because they are
   third-party. Order within the branch: `brew` if present (works on Darwin and Linux), else
   `apt-get`/`dnf`/`pacman` by presence, else point at the vendor's install page. Never guess
   at a package manager by OS alone — Linux distro detection by `uname` is impossible, and
   `brew` on Linux is common enough that presence-testing beats OS-testing every time.

5. **Nothing matched → print the tool's docs URL and stop.** Do not invent a command.

6. **Never probe the network as a signal.** A reachability check costs seconds, is unreliable
   behind proxies, and changes nothing: if there is no network, every install route fails
   identically and the failure message from `curl` or `tsuku` is more accurate than anything a
   preflight check could have predicted. Offline is a failure mode to report, not a branch to
   take.

Note that `cargo` and `mise` are worth *detecting* only to decide they are not the right
answer. `cargo install koto` builds from source (minutes, needs a toolchain) and mise has no
registry entry for either first-party tool. Detecting them and then not using them is fine;
detecting them and preferring them would be a regression.

### 4. What the matrix costs

Enumerating honestly for shirabe's four uncertain tools:

Host situations that produce distinct advice: (1) present and satisfied, (2) present but
below version floor, (3) unlinked in a known dir, (4) absent with tsuku, (5) absent, no tsuku,
brew present, (6) absent, no tsuku, apt, (7) absent, no tsuku, dnf, (8) absent, no tsuku,
pacman, (9) absent, nothing detected. That is 9 situations x 4 tools = **36 cells**, and the
real number is worse: cases 2 and 3 are per-tool-specific (three different env files, two
different version commands), gh-on-Linux needs a hardcoded exception carrying a tsuku issue
number, and the apt route for gh needs an extra repo-add step the other cells do not have.
Call it 40 distinct strings, each of which drifts independently when GitHub CLI changes its
apt instructions, when koto's installer gains a flag, or when tsuku fixes #2245.

Delegating to tsuku collapses situations 4 through 9 into one command per tool. The maintained
surface becomes: 4 tool specs (`tsukumogami/shirabe`, `tsukumogami/koto`, `gh`, `jq`), 3 env-file
paths for the PATH case, 2 version-floor checks, 1 tsuku-bootstrap command
(`curl -fsSL https://get.tsuku.dev/now | bash`), and 1 documented exception (gh on Linux).
Roughly **11 strings instead of 40**, and the ones that drift most — third-party packaging —
drift inside tsuku's recipe registry rather than inside shirabe.

**I would pick delegation, with a two-line fallback rather than a full matrix.** Concretely:
prefer `tsuku install -y <spec>` when tsuku is reachable; otherwise print the tool's own
`install.sh` one-liner for shirabe and koto (which are OS-agnostic by construction) and a
brew/apt/dnf/pacman line chosen by `command -v` for gh and jq. That is one branch on tsuku
presence, one branch on package-manager presence, and zero branches on `uname -s` except
inside the gh exception. The full 36-cell matrix buys nothing that these two branches don't
already cover, and every cell it adds is a cell that can go stale into a wrong command — and
for a consumer that will run whatever is printed, a stale command is worse than a docs link.

## Implications

- The install knowledge is small enough to live in one place. Four tools, four tsuku specs,
  three env-file paths, one exception. That is a table in a single reference file, not
  knowledge scattered across nine SKILL.md files.
- `/work-on` already implements the pattern for koto in prose. Whatever this exploration
  produces should subsume that block rather than sit beside it, or the two will disagree.
- The PATH case is not an edge case here. On this host, both koto and shirabe resolve through
  `~/.tsuku/tools/current/` — a directory that is only on PATH because `~/.tsuku/env` was
  sourced. An agent shell that misses that sourcing sees "not installed" for tools that are
  installed, and a naive check would tell it to reinstall them.
- If shirabe wants the strongest possible answer — one command, no per-tool logic — the move
  is to publish a `.tsuku.toml` fragment (declaring shirabe, koto, jq, and conditionally gh)
  for downstream repos to adopt, at which point the advice degenerates to `tsuku install -y`.
  That is a product decision with adoption cost, not something a check can assume.
- Any generated command must be checked against known-broken combinations. `tsuku install gh`
  on Linux is the live example, and it is documented only as a comment in `.tsuku.toml` — a
  place no check would think to look.

## Surprises

- shirabe already has a tsuku recipe for itself (`.tsuku-recipes/shirabe.toml`), complete with
  checksum verification and a `verify` step. Half the answer was sitting in the repo root.
- Both first-party installers do full OS/arch detection internally, so the "macOS and Linux
  need different commands" premise is false for shirabe and koto — the identical curl line is
  correct on both. The OS branch only exists for the third-party tools.
- `tsuku install` with no args is a real project-manifest install, backed by a whole design doc
  about org-scoped keys — but it is useless to shirabe's actual audience, because skills run in
  downstream repos that have no `.tsuku.toml`.
- shirabe's own `.tsuku.toml` documents that the tsuku route for gh is broken on Linux. The
  best available package manager has a known-bad cell for one of the four tools.
- jq turned out to be the heaviest script-level dependency by call count (140 sites) and is
  mentioned nowhere in the README's Requirements section.

## Open Questions

- Does shirabe want a declared version floor for its own binary? Skills call `shirabe validate`
  and subcommands like `finalize-chain` that were added over time; presence alone will not
  catch an old binary missing a subcommand.
- Should the check bootstrap tsuku itself (`curl -fsSL https://get.tsuku.dev/now | bash`) when
  it is absent, or treat tsuku as one more thing to report? Bootstrapping a package manager to
  install jq is disproportionate.
- Is `gh`'s tsuku Linux segfault (tsukumogami/tsuku#2245) still open? The whole gh exception
  disappears if it has been fixed.
- Does the check run per-skill with a per-skill tool list, or once with the union? `/vision`
  needs only `shirabe`; telling its user to install koto and gh would be noise.

## Summary

shirabe's skills depend on exactly four uncertain tools — `shirabe`, `koto`, `gh`, `jq` — and every one of them is installable through tsuku, including the two first-party ones, via distributed recipes that already exist in `.tsuku-recipes/shirabe.toml` here and in the koto repo. A hardcoded per-OS matrix would run to about 36-40 cells that drift independently, whereas delegating to `tsuku install -y <spec>` with a fallback to each tool's own OS-agnostic `install.sh` (and a `command -v`-chosen brew/apt/dnf/pacman line for gh and jq) needs roughly eleven maintained strings and only two branches, neither of which is `uname -s`. The precedence that matters most is putting "installed but not on PATH" ahead of every install route — on this host both koto and shirabe live in `~/.tsuku/tools/current/`, reachable only after sourcing `~/.tsuku/env`, so an install command printed in that situation would be a wrong command an agent would dutifully run.
