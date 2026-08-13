# Lead: adopter distribution surface

All paths below are relative to a repo root unless given absolutely. The
shirabe worktree inspected is
`/home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/public/shirabe/.claude/worktrees/vale-adoption`;
sibling consumers are under
`/home/dgazineu/dev/niwaw/tsuku/tsuku+vale_or_not-33480214/public/{koto,niwa,tsuku}`.

## Findings

### 1. The distribution channel: `.github/workflows/validate-docs.yml`

The reusable workflow is 101 lines
(`.github/workflows/validate-docs.yml`). Step by step:

1. **Check PR context** (lines 31-37) — bails with a `::notice` when
   `github.base_ref` is empty, so non-PR triggers are a clean no-op.
2. **Checkout caller repo** (lines 39-43) — `actions/checkout` pinned by
   SHA, `fetch-depth: 0` "so `git diff <base>...<head>` resolves both
   endpoints."
3. **Checkout shirabe** (lines 45-57) — a *second, full* checkout of the
   shirabe repo into `.shirabe-src`:

   ```yaml
         - name: Checkout shirabe
           uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd  # v6.0.2
           with:
             repository: ${{ job.workflow_repository }}
             ref: ${{ job.workflow_sha }}
             path: .shirabe-src
   ```

   The comment (lines 46-52) states the intent: "`job.workflow_repository`
   and `job.workflow_sha` resolve to the called workflow's repository and
   commit SHA … this picks up tsukumogami/shirabe at the called ref so the
   binary matches the workflow contract." No `sparse-checkout` and no
   `filter` — **the entire shirabe repo tree, including `references/`,
   `skills/`, and `docs/`, is already on the runner at exactly the ref that
   produces the binary.** This is the single most important fact for
   sub-question 4.
4. **Install Rust toolchain** (lines 59-61) — `dtolnay/rust-toolchain`
   pinned by SHA; the comment says it "Reads
   `.shirabe-src/rust-toolchain.toml` and installs the pinned channel."
   (Note: `release-binaries.yml:42-47` records that this action does *not*
   read `rust-toolchain.toml`, so the comment here is optimistic; the pin
   applies once cargo runs inside the repo.)
5. **Cache Cargo** (lines 63-72) — caches `~/.cargo/registry`,
   `~/.cargo/git`, `.shirabe-src/target`, keyed on
   `hashFiles('.shirabe-src/Cargo.lock')` with a `${{ runner.os }}-cargo-`
   restore prefix.
6. **Build shirabe** (lines 74-77) — **build from source, every run**:

   ```yaml
             cargo build --release --bin shirabe --manifest-path .shirabe-src/Cargo.toml
             install -m 0755 .shirabe-src/target/release/shirabe /usr/local/bin/shirabe
   ```

   No release-binary download, no action, no container. Note also that
   `SHIRABE_VERSION` is *not* set here, so per `crates/shirabe/build.rs:33-34`
   the CI-built binary reports the crate version — and both crate manifests
   pin `version = "0.0.0"` (`crates/shirabe/Cargo.toml:3`,
   `crates/shirabe-validate/Cargo.toml:3`). The CI binary is
   version-anonymous by construction.
7. **Validate changed docs** (lines 79-100) — computes the file set itself
   and passes it positionally:

   ```bash
             FILES=$(git diff --name-only --diff-filter=ACMR \
               ${{ github.event.pull_request.base.sha }}...${{ github.event.pull_request.head.sha }} \
               | grep -vE '(^|/)(evals|tests)/fixtures/' || true)
   ...
             shirabe validate \
               --visibility=${{ github.repository_visibility }} \
               ${CUSTOM_STATUSES:+--custom-statuses="$CUSTOM_STATUSES"} \
               $FILES
   ```

   The step comment names the contract: "CI uses the default annotation
   output mode (no `--format`), reads the exit code as a zero/non-zero
   pass-fail gate, and owns path selection … The CLI never discovers files
   itself."

**Inputs.** Exactly one, and it is optional (lines 16-23):
`custom-statuses`, "YAML map of schema version to custom status values",
`type: string`, `default: ''`. There is no `paths` input, no `args`
passthrough, no config-file input. **Path filters live in the caller**, not
here — the reusable workflow has no `paths:` of its own (it is
`on: workflow_call:` only).

**Permissions.** `contents: read` (line 29).

**Build time.** I measured a cold release build of `--bin shirabe` in a
clean `CARGO_TARGET_DIR` on this machine: `Finished release profile
[optimized] target(s) in 10.93s` / `real 0m10.953s`, but with `user
1m39.103s` — i.e. ~100 CPU-seconds spread over a many-core local box. A
2-core GitHub-hosted `ubuntu-latest` runner has no such parallelism, so
expect roughly 50-90s of compile on a cold cache, plus checkout ×2 and
toolchain install. **I cannot determine the actual observed CI wall time
from the repo** — no timing is recorded anywhere in the workflows or docs.
The `actions/cache` step exists precisely to avoid paying full price on
every run, but the cache key is `hashFiles('.shirabe-src/Cargo.lock')`,
which does not change when shirabe's own source changes, so the
`shirabe-validate` and `shirabe` crates recompile on every shirabe commit
while dependencies stay cached.

**Sibling reusable workflows using the identical build pattern.** Two
others exist and are also adopted downstream:
`.github/workflows/lifecycle.yml` (lines 70-103) and
`.github/workflows/pr-body.yml` (lines 95-130). Both do the same
`.shirabe-src` checkout → toolchain → cache → `cargo build --release --bin
shirabe` → `install -m 0755 … /usr/local/bin/shirabe`. Whatever a Vale step
costs, it would be paid per-workflow unless factored.

shirabe self-calls its own validator via
`.github/workflows/validate-shirabe-docs.yml`, which uses the local
relative path `uses: ./.github/workflows/validate-docs.yml` and adds its own
`paths:` filter covering `docs/**`, `crates/**`, `Cargo.toml`,
`Cargo.lock`, `rust-toolchain.toml`, and the two workflow files.

### 2. The consumers

**All three doc-validation callers are byte-identical in substance.**

`public/koto/.github/workflows/validate-docs.yml` and
`public/niwa/.github/workflows/validate-docs.yml` are literally the same
file (same 19 lines, same comment); `public/tsuku/.github/workflows/validate-docs.yml`
differs only in its comment prose. All three:

```yaml
on:
  pull_request:
    paths:
      - 'docs/**'

jobs:
  validate:
    uses: tsukumogami/shirabe/.github/workflows/validate-docs.yml@main
```

None passes `custom-statuses`. The path filter is `docs/**` in all three —
**no consumer currently triggers doc validation on README, CLAUDE.md, or
any prose outside `docs/`.** The koto/niwa comment states the pin rationale
explicitly: "Pinned to `@main` so this repo always runs the current engine
without per-release pin bumps. The validator is per-file and
changed-files-only, so a new engine check only ever affects PRs that touch
docs."

The full set of shirabe reusable-workflow references across the three
consumers (`grep -rn "tsukumogami/shirabe" */.github/`):

| Caller file | Called workflow | Ref |
|---|---|---|
| koto `validate-docs.yml:19` | `validate-docs.yml` | `@main` |
| niwa `validate-docs.yml:19` | `validate-docs.yml` | `@main` |
| tsuku `validate-docs.yml:20` | `validate-docs.yml` | `@main` |
| koto `lifecycle.yml:32` | `lifecycle.yml` | `@main` |
| niwa `lifecycle.yml:32` | `lifecycle.yml` | `@main` |
| koto `validate-pr-body.yml:37` | `pr-body.yml` | `@main` |
| niwa `validate-pr-body.yml:37` | `pr-body.yml` | `@main` |
| tsuku `validate-pr-body.yml:37` | `pr-body.yml` | `@main` |
| koto `finalize.yml:20` | `finalize-release.yml` | `@v0.2.0` |
| niwa `finalize.yml:20` | `finalize-release.yml` | `@v0.2.0` |
| koto `prepare-release.yml:27` | `release.yml` | `@v0.2.0` |
| niwa `prepare-release.yml:22` | `release.yml` | `@v0.2.0` |
| tsuku `release-prepare.yml:41` | `release.yml` | `@v0.5.1` |
| tsuku `release-finalize.yml:33` | `finalize-release.yml` | `@v0.5.1` |

Two clear conventions: **engine/validation gates ride `@main`; release
plumbing rides a version tag** (and those tags are stale — v0.2.0 and
v0.5.1 against a latest tag of v0.16.0). tsuku is the one repo that does
*not* adopt `lifecycle.yml`.

**Other ways shirabe reaches an adopter:**

- **Claude Code plugin marketplace.** `.claude-plugin/marketplace.json`
  declares the marketplace `shirabe` with one plugin, `source: "./"`,
  `version: "0.16.1-dev"`; `.claude-plugin/plugin.json` declares `"skills":
  "./skills/"`. `public/tsuku/.claude/settings.json` consumes it *from
  GitHub, with auto-update*:

  ```json
    "enabledPlugins": { "tsuku-recipes@tsuku": true, "tsuku-user@tsuku": true, "shirabe@shirabe": true },
    "extraKnownMarketplaces": {
      "shirabe": { "source": { "source": "github", "repo": "tsukumogami/shirabe" }, "autoUpdate": true }
    }
  ```

  `public/koto/.claude/settings.json` enables only `koto-skills@koto` —
  **koto does not enable the shirabe plugin in committed settings**. niwa
  has no `.claude/settings.json` at all (only a gitignored
  `settings.local.json`). So plugin reach is: tsuku committed + auto-updating;
  koto and niwa via local/uncommitted settings I cannot inspect
  authoritatively (koto's `.gitignore:10,14-15` ignores `*.local*` and
  `.claude/*` except `settings.json`).
- **tsuku recipe.** `.tsuku-recipes/shirabe.toml` installs the release
  binary: `url = "https://github.com/tsukumogami/shirabe/releases/download/v{version}/shirabe-{os}-{arch}"`
  with `checksum_url = ".../checksums.txt"` and `verify.command = "shirabe --version"`.
  None of koto/niwa/tsuku has a `.tsuku.toml` declaring shirabe (none of
  the three has a `.tsuku.toml` at all; shirabe's own `.tsuku.toml` pins
  `"tsukumogami/koto" = "latest"`).
- **`install.sh`** — curl-pipe installer at repo root; resolves
  `api.github.com/repos/tsukumogami/shirabe/releases/latest`, downloads
  `shirabe-${OS}-${ARCH}`, verifies against `checksums.txt`, installs to
  `~/.shirabe/bin`.
- **Local git hook.** `shirabe install-hooks` writes a static pre-commit
  hook (`crates/shirabe/src/main.rs:1209-1237`) that runs
  `shirabe validate --format human -- "${docs[@]}"` over staged `*.md`,
  fail-closed, and no-ops when `shirabe` is absent from `PATH`.
- **No vendored binary anywhere.** No consumer checks in a shirabe binary.

### 3. What shirabe already reads FROM an adopter repo

This is the crux, so it is enumerated exhaustively. There are **three**
adopter-supplied surfaces, and they are read by different halves of shirabe.

**(a) CLAUDE.md / CLAUDE.local.md headers — read by the binary: exactly one
header, `## Repo Visibility:`.**

`crates/shirabe-validate/src/visibility.rs` is the only module that reads an
adopter's CLAUDE.md as *configuration*. Its resolution order
(`resolve_doc_visibility`, lines 70-101):

```rust
    let mut dir = canonical.parent();
    while let Some(d) = dir {
        for name in ["CLAUDE.local.md", "CLAUDE.md"] {
            if let Ok(contents) = std::fs::read_to_string(d.join(name)) {
                if let Some(v) = parse_visibility_header(&contents) {
                    return v;
                }
            }
        }
        dir = d.parent();
    }
    // 2. Infer from the path components.
    if let Some(v) = infer_visibility_from_path(&canonical) { return v; }
    // 3. Default: restricting is easier to undo than oversharing.
    PRIVATE.to_string()
```

Precedence, top down: `--visibility` flag (the reusable workflow always
passes `--visibility=${{ github.repository_visibility }}`, which overrides
detection for every file — `crates/shirabe/src/main.rs:221-228`) → nearest
ancestor `CLAUDE.local.md` then `CLAUDE.md` carrying
`## Repo Visibility:` → `public`/`private` path component (leaf-upward) →
default `private`. Parsing is case-insensitive and prefix-matched
(`visibility.rs:31-46`); a header-less CLAUDE.md does **not** stop the
ancestor walk (comment at lines 78-81).

**(b) CLAUDE.md headers — read by no code at all, only by skills.** The
other headers named in the lead are prose contracts, not parsed
configuration. `check_claude_md_conventions`
(`crates/shirabe-validate/src/checks.rs:3167-3208`) is the *only* other
CLAUDE.md-touching check, it fires only when `basename == "CLAUDE.md"`
(line 3170), and it checks exactly one header —
`## Release Notes Convention: <path>` — at notice level. Its own doc
comment is explicit (lines 3163-3166):

> The check is intentionally narrow: it only validates the Release Notes
> Convention header. Other CLAUDE.md headers (`## Repo Visibility:`,
> `## Planning Context:`, `## Default Scope:`, `## Execution Mode:`) have
> their own defaults and are not checked here.

Grepping the Rust sources for `PR Grouping Policy|Reviewability Ceiling|Planning Context|Artifact Lifecycle`
returns **no parsing code** — only that comment. Those headers are read by
the *agent* per skill prose, e.g. `skills/scope/SKILL.md:127-136`:

> Coordination intent resolves on the existing `flag >
> CLAUDE.md-header > default` stack: … `## PR Grouping Policy:` and
> `## Reviewability Ceiling:` headers in CLAUDE.md — the durable workspace
> preferences … default — single-repo (intent absent).

So the header stack is real, but it is **agent-interpreted, not
binary-parsed**, for everything except Repo Visibility.

**(c) `.claude/shirabe-extensions/<skill>.md` — the per-adopter skill
extension surface.** This is a genuine, already-shipping "adopter supplies
config back to shirabe" mechanism and it is the one closest in spirit to a
style-config file. Ten skills `@`-import a pair of adopter files in their
SKILL.md, e.g. `skills/work-on/SKILL.md:6-7`:

```
@.claude/shirabe-extensions/work-on.md
@.claude/shirabe-extensions/work-on.local.md
```

The same pair appears in `skills/{decision,roadmap,strategy,vision,plan,explore,brief,design,prd}/SKILL.md`.
The contract is documented in-skill (`skills/work-on/SKILL.md:35`): the
extension file "defines additional label names and routing messages … It
also declares the project's **verification map** that the
definition-of-done gate reads — see `references/verification-map.md`", and
`SKILL.md:289` states the fallback: "If no extension file exists at
`.claude/shirabe-extensions/work-on.md`, the skill …" (defaults apply).

All three consumers populate it — but **only the `.local.md` half**:
`{koto,niwa,tsuku}/.claude/shirabe-extensions/{design,explore,prd,work-on,plan}.local.md`
exist; no committed `<skill>.md` does. koto's `.gitignore:10,14-15` ignores
`*.local*` and `.claude/*` except `settings.json`, so these arrive from
outside the public repos (the private overlay) and are invisible to CI.

**(d) There is no shirabe dotfile or config file.** Grepping the crates for
`env::var`, `.toml"`, `.shirabe.`, `dotfile`, `.config` finds only
`PR_BODY_HOOK_DISABLE` (`crates/shirabe/src/pr_body_hook.rs:61`), `HOME`
for a state dir (`work_summary.rs:411`), and gh-related env in
`shirabe-validate/src/gh.rs`. **`shirabe validate` reads no config file.**
Everything configurable arrives as a CLI flag.

**(e) The one injectable rule-data channel: `--custom-statuses`.** Parsed
in `crates/shirabe/src/main.rs:1375` (`parse_custom_statuses`, YAML,
size-capped, invalid YAML rejected) into
`Config.custom_statuses: HashMap<String, Vec<String>>`
(`crates/shirabe-validate/src/doc.rs:15`). Per
`docs/guides/doc-validation.md:62-63`: "Custom values **replace** (not
extend) the built-in enum for the specified schema version. Omit a key to
keep the built-in values." Everything else structural — required fields,
required sections and their order, issues-table columns, private-only
formats — is a hardcoded `FormatSpec` in
`crates/shirabe-validate/src/formats.rs` and cannot be supplied by an
adopter.

### 4. "Read the rule source without installing shirabe": the concrete options

First, an important negative: **the checks are compiled Rust logic, not
embedded data.** The only `include_str!` calls in the whole codebase are
`crates/shirabe-validate/src/checks.rs:5195-5196`, which include
`checks.rs` and `validate.rs` *into a test*. There is no embedded rule file
to extract today; the human-readable rule *prose* lives in
`references/**.md` and `docs/guides/**.md` in the shirabe repo, and the
binary only emits pointers to those paths in messages (e.g. `"… -- see
references/fixes/claude-md-conventions.md"`, `checks.rs:3206`) — pointers
that resolve for a plugin user (`${CLAUDE_PLUGIN_ROOT}/references/…`, used
83 times across `skills/*/SKILL.md`) and are dangling for a CI-only
adopter's own working tree.

The options, and what breaks in each:

| Option | Mechanism | What breaks |
|---|---|---|
| **A. Ships inside the binary** (`include_str!` a rules file into the crate) | Adopter obtains it only by running the binary (would need a new `shirabe rules --emit` style surface, which the "CLI Surface" rule in CLAUDE.md would have to be checked against — it forbids *authoring* subcommands, not emitting ones) | Zero version skew (binary and rules compile together). But **no adopter can read the rules without a binary**, so a third-party tool (Vale) that needs a config file on disk cannot consume them; and the CLI-surface convention pushes back on new subcommands. |
| **B. A file in the shirabe repo that the workflow already has** (`.shirabe-src/<rules>`) | **No fetch needed** — `validate-docs.yml:53-57` already checks out the whole shirabe repo at `job.workflow_sha` into `.shirabe-src`, and lifecycle.yml/pr-body.yml do the same | Nothing breaks that isn't already broken. Rules and binary are the *same* commit by construction, so version skew is impossible in CI. Costs nothing extra: no network call, no cache, no release asset. Does **not** help a local (non-CI) adopter who only has the binary. |
| **C. Published as a release asset** (alongside `shirabe-{os}-{arch}` and `checksums.txt` in `release-binaries.yml:107-113`) | Adopter downloads it per release | Requires network at consume time; **breaks offline CI**; adds a fetch step to a workflow that currently makes zero unpinned network calls beyond the two checkouts; and creates skew for any adopter on `@main`, since `@main` has no release asset corresponding to it. |
| **D. Vendored into the adopter repo** (a committed `.vale.ini` / styles dir) | Adopter copies the file in | Works offline, no fetch. But it **drifts silently**: nothing in shirabe can detect that koto's copy is 6 versions old, and there is no sync check today (compare `check-template-freshness.yml`, which koto runs against koto's own templates — a precedent for a freshness gate, but one that would have to be built). A fork drifting is the same failure with no upstream signal at all. |
| **E. The workflow fetches it at run time** (curl from raw.githubusercontent) | Explicit download step | Adds an unpinned network dependency; a raw.githubusercontent fetch of `main` would be *newer* than `job.workflow_sha` for a tag-pinned adopter — i.e. it manufactures the exact skew option B avoids. Strictly worse than B. |

**The asymmetry that matters for a requirement:** CI adopters and local
adopters have different reach. In CI, option B is free and skew-proof. For
a local adopter, the plugin install (`claude plugin install shirabe@shirabe`)
already places `references/` on disk at `${CLAUDE_PLUGIN_ROOT}` — so a
rules file committed under `references/` reaches *both* audiences through
paths that already exist, with no new distribution channel. An adopter who
installs only the binary (`install.sh` or the tsuku recipe) gets **neither**
`references/` nor `skills/` — the binary is the only artifact.

### 5. Version skew

**How shirabe versions.** The crate manifests are frozen at `0.0.0`
(`crates/shirabe/Cargo.toml:3`). The user-visible version is stamped two
ways, neither of which is Cargo:

- `.release/set-version.sh` stamps *only* `.claude-plugin/plugin.json` and
  `.claude-plugin/marketplace.json` (lines 11-27, via `jq`). It does not
  touch `Cargo.toml`.
- The binary's `--version` string comes from `SHIRABE_VERSION` at build
  time (`crates/shirabe/build.rs:29-37`), which is set **only** in
  `release-binaries.yml:57-60` (`SHIRABE_VERSION: ${{ github.ref_name }}`).

Consequence: **a release binary knows its version; a CI-built binary does
not.** `validate-docs.yml:76` builds without `SHIRABE_VERSION`, so the
binary that gates every adopter PR reports the crate version `0.0.0`.
`references/fixes/cli-version-preflight.md:50-54` already anticipates the
unversioned case ("`shirabe-unknown` for locally-built binaries").

**Release machinery.** `release-binaries.yml` fires on `push: tags: v*`,
cross-builds four targets, and uploads `shirabe-{linux,darwin}-{amd64,arm64}`
plus `checksums.txt` to a draft release. The reusable `release.yml` /
`finalize-release.yml` pair (documented in
`docs/guides/release-adoption.md`) does the version stamping and promotion;
its hook contract is `.release/set-version.sh <version>` called twice per
release (release version, then `<next>-dev`). Release notes convention:
shirabe's own CLAUDE.md declares `## Release Notes Convention: docs/guides/`,
and `docs/guides/` holds `RELEASE-NOTES-artifact-decision-contract.md` and
`RELEASE-NOTES-populate-issueless-default.md`.

**Current version state.** Latest tag is `v0.16.0` (`git tag --sort=-v:refname`);
in-flight version is `0.16.1-dev` (both plugin JSONs).

**Documented, already-observed skew.**
`references/fixes/cli-version-preflight.md` exists *because* skew already
bit: "The workspace `shirabe` binary may not match the skill version shipped
in the active marketplace bundle. The mismatch surfaces during chain
transitions: a skill written against v0.9 calls `shirabe transition <doc>
Accepted` and the v0.6.1 binary rejects the second positional arg" (lines
16-20). Its remedy is a runtime `--help` probe, not a version assertion,
"because shirabe releases sometimes ship partial surface changes" (lines
63-66). This is direct evidence that **skill-prose and binary-behavior drift
in practice**, and that the project's accepted mitigation is defensive
probing rather than lockstep versioning.

**Additional live skew in the docs themselves.** The adoption docs pin
examples to versions long superseded: `README.md:236,251` and
`docs/guides/doc-validation.md:43,55` say `@v0.6.0`;
`docs/guides/release-adoption.md` says `@v0.2.1` in seven places; consumers'
release callers sit at `@v0.2.0`/`@v0.5.1` against a latest of `v0.16.0`. Pin
rot is the empirical norm here, not a hypothetical.

**What `@main` implies.** All doc-validation, lifecycle, and pr-body callers
ride `@main`, and the workflow resolves `job.workflow_sha` to that same
`main` commit. So:

- Rules and binary in CI are **always the same commit** — a rules file
  living in the shirabe repo has *zero* skew surface for these adopters,
  today.
- A shirabe merge to `main` reaches every adopter's next PR immediately,
  with no adopter action. A new error-level check is therefore an
  **instant, unannounced breaking change** for koto, niwa, and tsuku
  simultaneously. The callers' own comment accepts this consciously,
  bounded by scope: "a new engine check only ever affects PRs that touch
  docs" — a bound that holds only while the caller's `paths:` filter stays
  `docs/**`.
- An adopter who *does* pin a tag (as the release callers do) gets the
  rules from that tag too, still consistent, just older. The failure mode
  for a pinned adopter is staleness, never mismatch.
- tsuku's plugin marketplace entry has `"autoUpdate": true`, so its
  *skills* also track upstream continuously — but from the GitHub repo's
  default branch state at update time, which is a different clock from the
  CI `job.workflow_sha`. Skill prose and CI engine can therefore be a few
  commits apart on the same machine. I could not determine from the repo how
  frequently that auto-update fires.

## Implications for requirements

**A PRD requirement can demand:**

- That any rule/style source ship as a **file inside the shirabe repo**
  (`references/…`) and be consumed in CI from `.shirabe-src/…`. This is
  free — the checkout already exists at `validate-docs.yml:53-57` — and it
  is the only option with a structurally impossible skew, since the rules
  and the binary come from one `job.workflow_sha`.
- That the same file reach local users via the plugin
  (`${CLAUDE_PLUGIN_ROOT}/references/…`), a path 83 SKILL.md references
  already use. No new distribution channel is needed for either audience.
- That adopters need **zero changes to their caller workflows** for a
  `docs/**`-scoped capability: all three callers are 19-20 lines, pass no
  inputs, and ride `@main`, so a new step inside the reusable workflow
  reaches them on their next docs PR automatically.
- Per-adopter *tuning* through one of the two surfaces that already exist:
  a new **optional `workflow_call` input** (the `custom-statuses` precedent,
  `validate-docs.yml:16-23` — string, defaulted, `${VAR:+--flag}`-guarded),
  or an **adopter file under `.claude/shirabe-extensions/`** for the
  agent-side half.
- Fail-open defaults for unconfigured adopters, matching the existing
  posture: the schema gate emits `::notice` rather than failing
  (`doc-validation.md:17-20`), and FC-CONVENTIONS is notice-level
  (`checks.rs:3159-3161`).

**A PRD requirement cannot demand (without new machinery it must fund):**

- **Any new CLAUDE.md header being read by the binary.** Only
  `## Repo Visibility:` is parsed today (`visibility.rs`). Grouping Policy,
  Reviewability Ceiling, Planning Context, and Artifact Lifecycle are
  agent-read prose with no parser. Adding a parsed header is new code, not
  a config change.
- **A shirabe config dotfile.** None exists; `validate` reads no config
  file at all. Introducing one is a new concept for the project.
- **Coverage of prose outside `docs/`.** Every consumer caller filters
  `paths: ['docs/**']`. README, CLAUDE.md, skill prose, and PR bodies are
  outside the doc-validation trigger. Broadening coverage requires each
  adopter to edit their caller — three separate PRs, and the `@main` pin
  means the change lands the moment it merges.
- **Structural rule extension by adopters.** `FormatSpec` is hardcoded
  (`formats.rs`); `--custom-statuses` is the *only* adopter-injectable rule
  data, and it replaces rather than extends.
- **Offline CI.** The workflow already makes two network checkouts and a
  cargo fetch; "offline" is not a property this pipeline has. But a
  requirement *can* demand no **additional** network dependency, and option
  B satisfies that where options C and E do not.
- **A version-assertion contract between rules and binary.** The CI binary
  is version-anonymous (`0.0.0`, no `SHIRABE_VERSION` at
  `validate-docs.yml:76`), so a requirement phrased as "the rules file must
  declare a compatible shirabe version" has nothing to compare against in
  CI without first fixing the version stamping.
- **Vendoring into adopter repos** without also funding a freshness check.
  There is no drift detector for adopter-side copies today; koto's
  `check-template-freshness.yml` is a precedent for building one, not an
  existing mechanism shirabe can rely on.

**The cost lever a requirement should be aware of:** every added second in
`validate-docs.yml` is also potentially paid by `lifecycle.yml` and
`pr-body.yml` (identical build blocks), and `pr-body.yml` has **no
`paths:` filter at all** in its callers ("path-independent by design"), so
it runs on every PR in koto, niwa, and tsuku. A tool that must be installed
per-run belongs in the narrowly-triggered workflow, not the universal one.

## Open questions

1. **Actual CI wall time.** Not determinable from the repo. My local cold
   build was 10.9s wall / 100s CPU on a many-core machine; a 2-core runner
   figure needs a real workflow run to establish. Someone should read a
   recent `validate-docs` run's timing before a requirement asserts a
   budget.
2. **Does the Cargo cache actually hit?** The key is
   `hashFiles('.shirabe-src/Cargo.lock')`, which is stable across shirabe
   source changes — so deps cache well, but the two shirabe crates
   recompile on every shirabe commit. Whether the restore-key path makes
   the common case fast needs a run log.
3. **Do koto and niwa have the shirabe plugin enabled locally?** Their
   committed settings say no (koto enables only `koto-skills@koto`; niwa has
   no committed settings.json), yet both carry
   `.claude/shirabe-extensions/*.local.md`. The plugin may be enabled via
   gitignored `settings.local.json` or the private overlay. A requirement
   that assumes plugin reach in all three repos needs this confirmed by a
   human.
4. **Who owns the `.local.md`-only extension files?** All extension files in
   all three consumers are `.local.md` and gitignored — they come from
   outside the public repos. If a requirement wants adopters to supply
   config through `.claude/shirabe-extensions/`, it needs to know whether
   the non-`.local` (committed) half is intended to be used at all, or
   whether that surface is de facto private-overlay-only.
5. **Is a new `shirabe`-emitting subcommand acceptable?** CLAUDE.md's "CLI
   Surface" rule forbids subcommands that *render or create an artifact
   body*. An "emit the rules file" subcommand is arguably not authoring, but
   this reading should be confirmed rather than assumed.
6. **Auto-update cadence for the plugin.** tsuku sets `"autoUpdate": true`;
   how often that pulls, and how far skill prose can lag the CI engine on
   one machine, is not recorded in the repo.

## Summary

shirabe reaches adopters through one channel that matters here: a reusable
GitHub Actions workflow that checks out the *entire shirabe repo* at the
called ref into `.shirabe-src`, builds the binary from source with cargo,
and runs `shirabe validate` over the PR's changed files — so any rule file
committed to the shirabe repo is already sitting on the runner at exactly
the commit that produced the binary, making version skew structurally
impossible for the CI path and requiring no new fetch, asset, or vendoring.
Adopters supply almost nothing back: koto, niwa, and tsuku each call the
workflow in 19 identical lines pinned `@main` with `paths: ['docs/**']` and
pass no inputs; the only adopter-injectable rule data is the optional
`custom-statuses` YAML input, the only CLAUDE.md header the binary actually
parses is `## Repo Visibility:` (every other header is agent-read prose),
and there is no shirabe config file of any kind. The `@main` pin means a
new check reaches all three repos on their next docs-touching PR with no
adopter action — powerful for rollout, and the reason a new error-level
rule is an unannounced breaking change unless it ships notice-level first.
