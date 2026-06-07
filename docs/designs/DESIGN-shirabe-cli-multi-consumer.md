---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-shirabe-cli-multi-consumer.md
problem: |
  The `validate` command emits GitHub Actions annotations only, runs every
  applicable check as one monolithic pass, and returns a 0/1 exit code.
  Three consumers (CI, the workflow skills, local hooks) need a wider,
  stable surface, and the annotation output CI depends on must not change.
decision: |
  Add an output-mode selector (annotation default, plus json and human),
  a versioned JSON result schema, per-check selection over the existing
  check codes, a validate exit-code contract aligned with the
  transition/finalize-chain scheme, and an install-hooks subcommand --
  layered over the existing engine without touching the annotation bytes.
rationale: |
  Reusing the existing check registry and the established exit-code scheme
  keeps the change additive and coherent across commands; defaulting to
  annotation output and holding it to a byte-parity bar preserves the live
  CI consumer while the other two consumers gain the surface they need.
---

# DESIGN: Multi-consumer CLI contract and UX

## Status

Planned

## Context and Problem Statement

The `validate` command in `crates/shirabe` is a thin wrapper over the
`shirabe-validate` engine crate. Today it collects a `Vec<ValidationError>`
from `validate_file` (and the lifecycle modes), formats each into a GitHub
Actions annotation (`::error file=...,line=...::message` /
`::notice ...`), prints them to stdout, and returns `ExitCode::SUCCESS` or
`ExitCode::FAILURE` -- a 0/1 result driven by whether any error-level
annotation was emitted.

That single shape is the technical obstacle to the command serving more
than CI. Three callers want the same checks but cannot use this surface:

- The workflow skills shell out and read the exit code as a verdict, but
  have no structured result to parse (only annotation text) and cannot
  distinguish "found violations" from "the tool could not run" because the
  exit code is 0/1.
- Local pre-commit hooks have nothing to scaffold them.
- Ad-hoc local runs cannot select one check and get annotation syntax in
  the terminal instead of human-readable output.

The raw material is already present. The engine emits results carrying a
named check code, a severity, a message, and a file/line. The check codes
(the FC-, R-, L-families, SCHEMA, FC-CONVENTIONS) are addressable strings.
The sibling commands `transition` and `finalize-chain` already return a
multi-level exit code (0 success, 1 tool-error, 2 lifecycle-violation, 3
I/O). The CI workflow already computes the changed-file set and passes
paths in; the CLI does not own git-diff. The technical problem is to layer
output modes, per-check selection, a richer exit-code contract, and a hook
installer over this existing engine without disturbing the annotation
bytes CI consumes.

## Decision Drivers

- **Annotation parity is non-negotiable.** CI consumes the current
  annotation bytes; the annotation mode must stay byte-for-byte identical
  (PRD R3, R10), held to a parity corpus.
- **Coherence with existing commands.** The validate exit-code scheme
  should match `transition`/`finalize-chain` so a consumer learns one
  contract (PRD R6).
- **Additive over rewrite.** The engine's check dispatch and result types
  already exist; the change should layer on top rather than restructure
  the engine.
- **Parseable without scraping.** The machine-readable mode must be
  consumable by a skill without parsing annotation text, and versioned so
  consumers can pin it (PRD R1, R11).
- **Orchestrator owns paths.** The CLI keeps taking explicit paths; it
  never reads git history to discover files (PRD R9).
- **Safe-by-default hook install.** The install-hooks command must not
  clobber an existing hook without an explicit opt-in (PRD R7).
- **Public visibility.** No private references in the artifact.

## Considered Options

The design makes four decisions. Each is presented with the chosen option
and the genuine alternatives weighed against it.

### Decision 1 -- Output modes, selection, and the JSON schema

**Chosen: a single `--format` flag with values `annotation | json | human`,
defaulting to `annotation`, plus a versioned JSON envelope.**

Mature check CLIs converge on a `--format`/`--output-format`/`--reporter`
flag that selects among a human mode, a machine mode, and a CI-annotation
mode (ruff's `--output-format`, eslint's `--format`, golangci-lint's
output formats, biome's `--reporter`). shirabe adopts the same grammar but
inverts the default: those tools default to human output, whereas shirabe
was born annotation-only with a live, tag-pinned CI caller that passes no
format flag and depends on the annotation bytes. An explicit
`annotation` default is the only choice that keeps every current CI run
byte-identical (R3, R10) while making output a pure function of arguments.

The JSON mode is a top-level envelope carrying a `schema_version` of
`shirabe-validate/v1`, a summary block (counts of errors and notices, the
resolved outcome), and a flat `findings` array. Each finding maps directly
to the engine's `ValidationError`: `code`, `message`, `file`, and `line`
(emitted as `null` when the engine's no-line sentinel is present).
Severity is *derived* from the same `is_notice()` seam that drives the
annotation error/notice split, so the JSON severity cannot drift from
annotation semantics. The schema version follows the repo's existing
`<name>/v<major>` idiom (the same shape as the `design/v1` document schema
tag): additive changes stay `v1`, a breaking change bumps to `v2`, and
consumers pin on the major.

**Alternatives rejected:**

- **Auto-detect the CI environment (emit annotation when `GITHUB_ACTIONS`
  is set, else human).** Rejected: it makes backward compatibility
  conditional on an environment variable. Any CI path without that
  variable set (composite actions, env-scrubbed containers, local CI
  runners, pre-commit) would silently flip to human output and break
  annotation scraping, and a formatter parity corpus cannot guard an
  env-driven selection regression.
- **A hand-rolled JSON writer matching the existing `to_json` style in
  `transition.rs`/`finalize.rs`.** Considered for stylistic consistency,
  but the byte-parity constraint applies only to the annotation mode, so
  the JSON path is free to use the standard serializer. The envelope shape
  and versioning are unaffected by the choice.

### Decision 2 -- Validate exit-code contract

**Chosen: mirror the sibling commands exactly -- `0` clean, `1` tool-error,
`2` violations found, `3` I/O error.**

`transition` and `finalize-chain` already return this scheme (documented
canonically on `finalize.rs`'s `WalkError` and asserted by unit tests in
both files). The decisive fact is that `validate` today collapses *all*
non-clean outcomes into exit `1` -- a bad flag, a parse failure, and an
error-level violation all return `1` -- so no consumer can currently
depend on "`1` means violations". That dissolves the backward-compatibility
objection to remapping `1`: both candidate mappings keep `clean = 0` and
`non-clean = non-zero`, so every existing pass/fail gate is unaffected.

With backward compatibility neutral, cross-command coherence is the
tiebreaker, and it points at mirroring. `validate`'s "ran to completion but
the rules say no" is the exact analogue of `transition`'s lifecycle
violation (code `2`); its "could not run" (unreadable file, bad invocation,
parse failure) is `transition`'s tool error (code `1`), which matches the
PRD R6 wording. Notice-level results never raise the floor above `0`. A run
over multiple documents returns the most severe outcome (tool-error
outranks violations outranks clean).

**Alternatives rejected:**

- **Validate-native ordering (`1` = violations, `2` = tool-error),
  "preserving" today's meaning of `1`.** Rejected: the preservation is
  illusory because today's `1` is the union of violations and tool-error,
  so nothing concrete is preserved -- and it inverts the sibling
  vocabulary, guaranteeing a cross-command surprise for the very
  multi-consumer audience this design serves.
- **A disjoint code band (violations `1`, tool-error `10+`).** Rejected: an
  alien band breaks the one-vocabulary goal and muddies the reserved I/O
  slot for no benefit.

### Decision 3 -- Per-check selection

**Chosen: a repeatable, comma-splittable `--check` flag, backed by a flat
registry of known check codes, with a post-filter on emitted results and
unknown codes rejected as a tool error.**

A single `--check` flag (clap `value_delimiter = ','` over a `Vec<String>`,
also repeatable) is the minimal surface that satisfies "one check or a
named subset" and matches the ruff/golangci-lint convention. Checks become
addressable by validating each requested code against a flat known-codes
registry and then post-filtering the emitted `ValidationError` set by
`code` -- leaving the engine's positional check dispatch in `validate_file`
untouched (additive, no rewrite). A valid but format-inapplicable code
(for example `FC05` against a BRIEF) is a clean no-op, because that
check simply never runs for that format; applicability is a property of
the document, so a selection narrows to nothing rather than failing. An
unknown code (a typo like `FC1`) is rejected up front as a tool error
(exit `1`, per Decision 2) with a message naming the offending code.

**Alternatives rejected:**

- **A `--select`/`--ignore` pair (ruff-style).** Rejected: the PRD requires
  positive selection only; shipping an ignore-list adds a precedence
  surface for an unrequested capability. `--ignore` is noted as a clean
  future extension.
- **A `code -> check-function` dispatch registry.** Rejected: it would
  force a uniform check signature and rewrite `validate_file`'s positional
  dispatch (with its short-circuits and the FC09 gh-client setup) to
  produce output identical to a simple post-filter.
- **Erroring on a valid-but-inapplicable code.** Rejected: it breaks
  mixed-format and scripted runs and contradicts the "checks that apply to
  the detected format" rule.
- **Family-level selection (`--check FC`).** Rejected as v1 scope creep;
  the exact-code registry leaves room to add prefix matching later without
  changing the grammar.

Note the scope of selectable codes: the per-file check codes (the
FC-family, FC-CONVENTIONS, the R-family, SCHEMA) are reachable through the
per-file pass and are selectable. The L-family lifecycle codes are produced
by the distinct `--lifecycle`/`--lifecycle-chain` traversal modes, not the
per-file pass, so they are not addressable by `--check` in v1.

### Decision 4 -- Hook-install mechanism

**Chosen: a flat `install-hooks` subcommand that writes a self-contained
POSIX `sh` pre-commit script to `.git/hooks/pre-commit`, with a `--force`
opt-in for overwrite.**

A raw git hook is the only option that honors shirabe's self-contained,
no-system-dependency philosophy as the default, while giving full control
over the byte-unchanged collision handling R7 requires. The subcommand name
`install-hooks` coheres with the existing flat kebab-case command set
(`finalize-chain`, `slug-prefix-detect`) and a single `--force` bool
mirrors the `--dry-run` style already on `finalize-chain`.

The installed hook is an orchestrator (R9): it computes the staged set
itself with `git diff --cached -z --name-only --diff-filter=ACMR`
(NUL-delimited, read with a NUL-safe loop and quoted expansions) filtered
to `*.md`, exits `0` early when no documents are staged, resolves the
binary on PATH (`command -v shirabe`), invokes `shirabe validate --format
human -- <staged-paths>` (the `--` end-of-options separator so a file named
like a flag is treated as a path), and blocks the commit on any non-zero
exit (fail-closed). The NUL-delimited, `--`-separated, fully-quoted
pipeline closes the filename shell-injection surface (see Security
Considerations). When `.git/hooks/pre-commit` already exists, the command
leaves it byte-unchanged and reports the collision unless `--force` is
given; a hook managed by the pre-commit framework is detected by its
marker line and the user is steered to a framework config entry rather than
clobbered.

**Alternatives rejected:**

- **A pre-commit-framework entry (`.pre-commit-config.yaml`).** Rejected as
  the default: it requires installing the framework, a system dependency
  that violates shirabe's self-contained philosophy, and having the
  framework own the hook file weakens the byte-unchanged guarantee. It is
  kept as advisory output for repos already on the framework.
- **A nested `hooks install` command namespace.** Rejected: hooks have a
  single verb today; nesting for one verb breaks coherence with the flat
  command set. A future `uninstall`/`status` can be added without
  committing to nesting now.

## Decision Outcome

The four decisions compose into one additive widening of `validate` plus
one new subcommand, layered over the existing engine without touching the
annotation bytes:

- `validate` gains a `--format annotation|json|human` selector (default
  `annotation`) and a `--check <code>...` selector. Its exit code becomes
  the four-level `0/1/2/3` scheme the sibling commands already use.
- The engine's `ValidationError` results are rendered three ways from one
  collected result set: the existing annotation formatter (unchanged), a
  new `serde`-backed JSON envelope (`shirabe-validate/v1`), and a new
  human-readable terminal renderer.
- A new `install-hooks` subcommand scaffolds a self-contained pre-commit
  hook that calls back into `validate`.

The coherence across decisions is deliberate: the `is_notice()` seam that
splits annotation errors from notices is the same seam that derives JSON
severity (D1) and the same seam that decides what counts as a violation for
the exit code (D2); the tool-error exit code (D2) is what an unknown
`--check` code (D3) and the fail-closed hook (D4) bind to. A consumer
learns one severity model and one exit-code vocabulary across the whole
CLI.

## Solution Architecture

### Components

1. **`ValidateArgs` (crates/shirabe/src/main.rs).** Gains two fields:
   `--format` (an enum-valued flag, default `annotation`) and `--check`
   (a `Vec<String>`, repeatable and comma-splittable). The existing
   `files`, `--visibility`, `--custom-statuses`, `--lifecycle`,
   `--lifecycle-chain`, and `--strict` fields are unchanged.

2. **Check-code registry (crates/shirabe-validate).** A flat set of the
   known per-file check codes, used to (a) validate `--check` arguments up
   front and (b) post-filter the emitted result set. This is a data
   structure over existing code strings, not a dispatch rewrite.

3. **Result renderers (crates/shirabe-validate).** One collected
   `Vec<ValidationError>` feeds three renderers:
   - the existing annotation formatter in `annotation.rs` (untouched);
   - a JSON renderer producing the `shirabe-validate/v1` envelope
     (summary + flat findings, severity derived via `is_notice()`,
     `line == 0` rendered as `null`);
   - a human renderer producing a terminal-shaped summary.

4. **Exit-code mapping (crates/shirabe/src/main.rs `run_validate`).** A
   mapping from the run's outcome to the `0/1/2/3` scheme, sharing the
   vocabulary defined for `transition`/`finalize-chain`. Most-severe-wins
   across multiple documents.

5. **`install-hooks` subcommand (crates/shirabe/src/main.rs).** A new
   `Commands` variant writing the pre-commit script, with `--force` and
   collision detection.

### Data flow

```
caller --> validate <paths> --format=<mode> --check=<codes>
              |
              v
        engine: validate_file per doc (unchanged dispatch)
              |
              v
        Vec<ValidationError>  --(optional post-filter by --check)-->
              |
       +------+--------------------+------------------+
       v                           v                  v
  annotation fmt              json envelope       human render
  (byte-identical)        (shirabe-validate/v1)   (terminal)
       |                           |                  |
       +------------+--------------+------------------+
                    v
            outcome --> exit code (0 clean / 1 tool-error /
                                   2 violations / 3 I/O)
```

The CLI never computes which files to validate; callers (CI, the installed
hook) pass explicit paths.

### Per-consumer contract (R8)

The repository documents, per consumer, the surface it relies on:

- **CI** invokes `validate <changed-paths>` with no `--format` (annotation
  default), reading exit zero/non-zero as the gate; the reusable workflow
  computes the changed set.
- **The skills** invoke `validate --format json <paths>`, parse the
  `shirabe-validate/v1` envelope, and branch on the `0/1/2/3` exit code.
- **Local hooks** are scaffolded by `install-hooks`; the hook computes the
  staged set and invokes `validate --format human <staged-paths>`,
  blocking the commit on any non-zero exit.

## Implementation Approach

The work is additive and naturally ordered so each step lands behind a
green test suite:

1. **Exit-code contract first.** Introduce the `0/1/2/3` outcome mapping in
   `run_validate`, reusing the sibling vocabulary. At this point the
   default annotation behavior is unchanged except that a tool-error path
   (bad flag, unreadable file) returns `1` and a violations path returns
   `2`; clean stays `0`. Parity corpus and a new exit-code test assert the
   mapping.
2. **JSON and human renderers.** Add the `--format` flag and the two new
   renderers over the existing result set, with `annotation` as the
   default so CI is untouched. Lock the annotation mode with the
   byte-parity corpus; add JSON-shape and version-field tests.
3. **Per-check selection.** Add the `--check` flag, the known-codes
   registry, the up-front unknown-code rejection (exit `1`), and the
   result post-filter. Add tests for single, subset, no-selection,
   inapplicable-code no-op, and unknown-code error.
4. **`install-hooks` subcommand.** Add the subcommand, the script
   template, collision detection, and `--force`. Add tests for fresh
   install, collision-reports-and-preserves, and force-overwrite.
5. **Per-consumer documentation.** Write the R8 contract doc and update the
   reusable CI workflow comments to name the contract they depend on.

Steps 2-4 are independent of each other once step 1 lands; step 5 follows
the surface settling.

## Security Considerations

**No new network or privilege surface.** `validate` remains local/CI-only
with no network egress; the JSON envelope is printed to stdout for the local
caller and transmitted nowhere. `install-hooks` writes only to the repo's own
`.git/hooks/pre-commit` (a fixed path, no user-derived path component, no
traversal surface) and requires no privilege beyond what the user already has
over their working tree. The installed script is static and tool-authored; no
repo-derived or user-derived string is interpolated into it.

**JSON output escaping (parity with annotation injection-hardening).** The
annotation mode strips `\n`/`\r` from emitted fields to prevent
annotation-injection via crafted frontmatter. The JSON mode achieves the
equivalent by JSON-escaping every string field (`message`, `file`, `code`)
through a real serializer or the existing `json_string` helper -- never via
raw string interpolation. A document containing quotes, newlines, or control
characters in a field value serializes to an escaped string and cannot forge
sibling fields or extra findings. The `null`-for-sentinel `line` rule and
severity (derived solely from `is_notice()`) are emitted structurally, not
string-built. An adversarial-value test corpus (embedded quotes, newlines,
control chars) guards this path the way the byte-parity corpus guards
annotation mode. Note that, unlike annotation mode, JSON preserves newlines
(escaped as `\n`) rather than stripping them, so messages stay faithful.

**`--check` rejection messages.** A rejected unknown code echoes the
offending value into an error message; that message inherits the escaping of
whatever channel carries it (annotation sanitization for annotation mode,
JSON escaping for json mode, plain stderr for the tool-error path). `--check`
values are never passed to a shell or the hook template, so they carry no
command-injection surface.

**Pre-commit hook filename handling.** The generated hook collects staged
paths with `git diff --cached -z --name-only --diff-filter=ACMR` (NUL
delimited), reads them with a NUL-safe loop, quotes every expansion, and
passes them to `validate` after a `--` end-of-options separator. This
prevents argument-splitting and option-smuggling via filenames that contain
whitespace, newlines, glob metacharacters, or leading dashes. The hook is
fail-closed: any non-zero `validate` exit blocks the commit.

**Hook binary resolution.** The hook resolves `shirabe` via `command -v` on
PATH at commit time, trusting the developer's PATH -- the same trust model as
any PATH-resolved hook. Developers should keep relative (`.`) or
world-writable directories out of PATH. The hook never falls back to a
repo-local binary. `install-hooks` emits the resolved path at install time so
the user sees what will run, sets the hook mode to `0755`, and resolves the
real hooks directory (handling worktrees and submodules where `.git` is a
file, not a directory) so a fail-closed hook is never silently
not-installed.

**Collision safety (R7).** An existing `pre-commit` hook is left
byte-unchanged and reported unless `--force` is given; a pre-commit-framework
hook is detected by its marker line and the user is steered to a framework
config entry rather than clobbered.

## Consequences

**Positive:**

- The checks stop being CI-only. The same authority is usable from the
  skills (parsing the `shirabe-validate/v1` JSON and branching on the
  `0/1/2/3` exit code), from local pre-commit hooks, and from ad-hoc
  terminal runs -- without anyone reimplementing the checks.
- The CLI gains one coherent exit-code vocabulary and one severity model
  across `validate`, `transition`, and `finalize-chain`. A consumer learns
  it once.
- CI is untouched: the annotation default plus the byte-parity bar means
  every current invocation behaves exactly as before, with no workflow
  edit required.
- The change is additive over the existing engine -- the check dispatch and
  result types are reused, not rewritten -- so the blast radius is small
  and the parity corpus pins the one output a consumer already depends on.

**Negative / trade-offs:**

- The `shirabe-validate/v1` JSON, once the skills pin it, becomes a contract
  whose evolution is constrained by the version discipline. Early schema
  churn is cheaper than late churn; the schema should be exercised by the
  skills before it is treated as frozen.
- Per-check selection covers only the per-file check codes in v1; the
  lifecycle L-family (reached through the `--lifecycle` traversal modes, not
  the per-file pass) is not addressable by `--check` yet. This is a known
  boundary, not a defect, and can be extended later.
- Remapping `validate`'s exit `1` from "any failure" to specifically
  "tool-error" is invisible to a zero-vs-non-zero gate but would surprise a
  hypothetical consumer that today special-cases `1` as "violations". No
  such consumer can exist against today's binary (where `1` is the union),
  so the risk is theoretical, but it is noted.

**Mitigations:**

- The annotation byte-parity corpus and a new exit-code test lock the two
  behaviors CI depends on before any renderer or flag lands.
- The adversarial-value JSON test corpus and the pathological-filename hook
  test close the two injection surfaces the security review identified.
- The per-consumer contract documentation (R8) records exactly what each
  consumer relies on, so a future change that would break one consumer is
  visible at review time.
