# Decision 1: Implementation home

Where the preflight check lives: pure bash in the plugin (A), a `shirabe`
binary subcommand (B), or a split shim that resolves the binary and execs it
(C).

## New evidence gathered for this decision

Three facts were measured on this host rather than reasoned about, and two of
them move the answer. They are stated up front because the option analysis
below leans on them.

**1. A stale binary rejects an unknown subcommand with exit 2, not 127.**
Measured against the installed `shirabe v0.16.0` while this worktree's
`plugin.json` reads `0.16.1-dev`:

```
$ shirabe preflight >/dev/null 2>&1; echo $?
2
$ shirabe validate --not-a-real-flag >/dev/null 2>&1; echo $?
2
```

with `error: unrecognized subcommand 'preflight'` on stderr. The prior
exploration modelled option B's failure as "a bare exit 127". That is the
*absent* case only. The *stale* case — a binary present, on PATH, executable,
and predating the release that adds `preflight` — is exit 2 plus a clap error
on stderr. Exit 2 is the exact code R22 identifies as already overloaded, and
the stderr bytes are a direct R12 violation on a host where the declaration may
be perfectly satisfied. Option B does not merely fail to report its own
absence; it misreports its own staleness in the same overloaded vocabulary the
PRD exists to disambiguate.

**2. On the day this ships, every host is the stale case.** No release before
the one that adds `preflight` contains it. `release-binaries.yml` publishes bare
`shirabe-{os}-{arch}` assets on tag push and nothing auto-updates them; the
plugin, by `marketplace.json`'s `"source": "./"`, updates the instant the
checkout does. So under B or C the fallback path is not an edge case to be
handled gracefully — it is the universal initial state, and it stays the state
for every user who updates the plugin but not the binary, which is the precise
population the feature exists to serve. R9 forbids gating on a version number;
B and C nonetheless introduce a *structural* floor (the binary must be new
enough to have the check) whose only expression is the fallback path.

**3. The R7/R8 surface probe is a line-anchored grep, and it works under bash
3.2.** Verified on `/bin/bash` 3.2.57 (macOS system bash) against real clap
output:

```bash
probe() { "$1" "$2" --help 2>&1 | grep -qE "^[[:space:]]+(-[a-zA-Z], )?$3([ =,]|$)"; }
```

Results: `validate --merge-gate` PRESENT, `--pr-body` PRESENT,
`--allow-untracked-acs` PRESENT, `--dry-run` ABSENT, `--force` ABSENT
(`--force` and `--dry-run` are real flags on *other* subcommands, so they are
the false-positive probes, and the anchor rejects both). A subcommand probe
anchored the same way against `shirabe --help` correctly reports `validate`,
`transition`, `roadmap` PRESENT and `preflight`, `notacommand` ABSENT. Eight
`--help` spawns took 15.4 ms wall clock, which is under the 100 ms the decision
record budgeted for the 6-9-call worst case, with room to spare.

This matters because it collapses the strongest technical argument for the
binary. For `koto`, `gh`, `git`, `jq`, and `python3` a Rust implementation has
no parsing advantage whatsoever — it would shell out to the same `--help` and
regex the same rendered text. Rust's only genuine edge is introspecting
*shirabe's own* clap command tree structurally instead of parsing its rendered
help. That is one tool out of six, and it is the one tool whose absence or
staleness the binary structurally cannot report.

## Options considered

### A. Pure bash in the plugin

**Shape.** One always-present entry point — the natural home is
`scripts/preflight-check.sh` at the plugin root, alongside the existing
`scripts/check-*.sh` family, with shared helpers in `scripts/lib/` following
`scripts/lib/koto-gates.sh`. It takes a skill name, reads that skill's
declaration from a plugin-side file, and for each always-required entry runs
`command -v`, then the anchored subcommand and flag probes, then renders an
instruction for anything unsatisfied.

**What it gets for free.** Every artifact it touches is guaranteed present and
version-matched at the moment a skill loads, because `marketplace.json` ships
the plugin as the repo checkout. The script, the declaration, and the SKILL.md
that references them move as one commit. There is no seam across which anything
can skew, which is a strange and valuable property for a feature whose entire
subject matter is skew.

**Testability, which is where it wins outright.** The acceptance criteria are
written in a vocabulary this repo already speaks in bash and nowhere else.
"Zero bytes across stdout and stderr combined, measured with `wc -c` over a
combined capture" is one line in the `preflight_test.sh` harness. "A tool
present under an injected tool-location root and absent from PATH" is
`run-cascade_test.sh`'s existing `PATH="$effective_path" SHIRABE_BIN="$bin"`
idiom plus R28's override variable. "A declared tool removed from PATH" is a
`PATH=` scrub. And critically, the CI that runs these is PR-triggered on a
`[ubuntu-latest, macos-latest]` matrix with the macOS leg invoking `/bin/bash`
explicitly — `check-plan-scripts.yml`'s comment calls that matrix "the guard
against reintroducing a post-3.2 construct" and records that a grep-based
portability check previously missed a bash 4.3 nameref that only running the
suite on the floor caught. `build-and-test.yml` runs `cargo test --workspace` on
`ubuntu-latest` with no matrix at all. Cross-platform confidence in this repo
comes from the shell suite, and a preflight check is a cross-platform artifact
by definition.

**The mechanism is not novel here.** `references/fixes/cli-version-preflight.md`
— which R24 retires — already documents the per-subcommand `--help` grep as the
recommended technique, with a worked `shirabe transition --help | grep -qE --
'--superseded-by'` example. R24 removes that prose because a skill dereferencing
it by hand is the wrong shape; it does not repudiate the technique. Adopting A
promotes an in-repo documented idiom to a tested script, which is a smaller
change than it looks.

**Honest costs.** Three, and they are real.

*Per-tool data without associative arrays.* Bash 3.2 has no `declare -A` and no
namerefs. Remediation text and install routes for six tools have to live in a
`case "$tool" in` block or a delimited string table. This is idiomatic and
bounded — six arms, roughly eleven install strings per the PRD's own count of
host-resolved delegation — but it is genuinely uglier than a typed Rust table
and it will not get prettier as tools are added.

*No jq.* Every shell CI job in this repo installs jq explicitly (`apt-get
install -y jq` / `brew install jq`), which is the repo's own admission that it
is not assumable on a user machine. R20's requirement that the gh/Linux
exclusion be read "from a machine-readable source rather than a comment in
`.tsuku.toml`" therefore has to be satisfied by a line-oriented plugin-side data
file the script can read with `grep`/`read`, not a JSON blob. That is a
constraint on the data format, not a blocker, but it is a constraint the design
must state.

*Repo direction.* `work_summary.rs`'s module doc says outright that "the
security-critical, determinism-focused logic that used to live in bash ... is
re-expressed here in typed Rust." A new bash artifact of nontrivial size cuts
against that. The counter is that the stated rationale does not reach this case:
work-summary moved because it maintains a ledger, parses attacker-influenced
hook JSON, and gates emissions — mutation, state, and a security surface. The
preflight check mutates nothing, holds no state across runs, reads only
repo-committed declarations, and always exits 0. Its worst failure is a report
that does not appear. The migration argument is about consequences of being
wrong, and the consequences here are categorically smaller.

### B. A `shirabe preflight` subcommand

**Shape.** A clap subcommand in the fail-safe family established by
`pr_body_hook.rs` and `work_summary.rs`: `pub fn run() -> ExitCode` that always
returns `ExitCode::SUCCESS`, silence when clean, typed per-skill manifests,
`serde_json` where structure is needed, unit tests colocated in
`crates/shirabe/tests/`. Registration is three lines in `main.rs`.

Taken on its own terms this is the most attractive engineering. The idiom is
proven twice in this repo, the exit-0 discipline maps exactly onto R17 and R12,
and the surface probe for shirabe's own flags becomes exact rather than a grep,
because clap can be asked structurally what it accepts.

**Why it fails anyway, in three independent ways.**

*It cannot report its own absence.* This was already established and is not
weakened: on a host without the binary, the invocation is a shell 127 and the
most important prerequisite is the one the check is silent about.

*It misreports its own staleness in the overloaded code.* Finding 1 above.
Exit 2 and a clap error on stderr, which is the same signal a violating
document produces, on a machine that may be entirely healthy. A check whose own
failure mode reproduces the defect described in the PRD's problem statement is
not a candidate.

*It defeats R27 and R28 as test surfaces.* R27 requires an entry point "whose
combined stdout and stderr can be captured by a test", justified explicitly on
the grounds that R12 is otherwise unfalsifiable. Under B, the entry point does
not exist on the host that most needs it — and the case "invoke the entry point
on a host without the binary" cannot be constructed at all, because the harness
must run the binary to run the test. The Rust suite structurally cannot cover
the case the feature was written for.

**A fourth problem, which also binds option C.** Where does the declaration
live? If it is compiled into the binary, it drifts from the plugin by exactly
the mechanism this feature exists to detect — right now, in this worktree,
`plugin.json` reads `0.16.1-dev` and the installed binary reads `v0.16.0`, so a
compiled-in declaration would already be describing a different set of skills
than the ones on disk. The declaration must therefore ship plugin-side, which
means the binary has to be told where the plugin root is. `grep -rn
CLAUDE_PLUGIN_ROOT crates/` returns zero hits: no crate reads plugin layout
today. B and C would introduce the binary's first dependency on the plugin's
directory structure — a new coupling running in the opposite direction from the
one the feature is trying to reduce.

### C. Split — shim resolves, binary does the rest

**Shape as the prior analysis proposed it.** A thin shim lifts
`run-cascade.sh:633-648`'s four-step resolution chain (`$SHIRABE_BIN` →
`command -v shirabe` → `target/release` → `target/debug`) and `preflight.sh:19`'s
`${CLAUDE_PLUGIN_ROOT:-self-resolve}` fallback; on failure it prints the
shirabe-install instruction itself and exits 0; on success it `exec`s `shirabe
preflight --skill <name>` "so there is one process, not two."

**Where the prior analysis was wrong: `exec` is not available.** An `exec`
replaces the shim process. Whatever the binary then emits goes straight to the
caller and whatever it exits with is the shim's exit status. On a stale binary
that is `error: unrecognized subcommand 'preflight'` on stderr and exit 2 — the
shim has forfeited its only chance to intercept. Option C is only viable if the
shim forks the binary as a child, captures combined output, and inspects the
result before relaying. That costs the second process the prior analysis was
trying to avoid, and it makes the "one process, not two" argument backwards:
the second process is not overhead to be optimised away, it is the mechanism
that makes the split work at all.

There is a clean discriminator available once you fork. If `shirabe preflight`
adopts the exit-0-always contract of `pr_body_hook.rs` and `work_summary.rs`,
then *any* non-zero exit from it means "this binary does not understand this
command" — absence gives 127, staleness gives 2, and both are non-zero while a
healthy run is always 0. The shim relays captured output on exit 0 and renders
its own stale-binary instruction otherwise. Note that R21 forbids discarding the
tool's diagnostics, so the captured clap error must be carried into that report
rather than swallowed.

**Why the split still loses, on its own accounting.** Work out what each side
actually owns.

The shim must own: plugin-root self-resolution; the four-step binary resolution
chain; the R28 tool-location-root read, because distinguishing "shirabe absent"
from "shirabe present under `~/.tsuku/tools/current/` but off this shell's PATH"
is a shirabe-specific question and shirabe is the tool the binary cannot speak
about; the R18 ordering rule that PATH-invisibility is resolved before any
install route is offered; the R15 no-route-available case; R19's requirement that
the emitted command be established to work on this host; and a full report
renderer, because it has to emit an R14-shaped instruction for the two shirabe
cases. That is not a shim. That is the reporting machinery, minus one grep loop.

The binary would then own: iterating a declaration and running anchored greps
over `--help` output for the other five tools. Which finding 3 shows is roughly
ten lines of bash running in two milliseconds a probe.

So the split does not put the hard part in Rust and the easy part in bash. It
puts the two hardest instruction cases in bash, the easiest probe in Rust, and
duplicates the report renderer across the seam — where the two copies will
diverge in format, because nothing forces them not to. The `work-summary spec`
mitigation (binary owns the canonical text, shim carries only the
binary-missing string) does not apply, since a shim that cannot reach the binary
also cannot ask it for the canonical text.

Add the day-one problem from finding 2: for every user until they update the
binary, C runs entirely in its bash half and the Rust half is dead code. A
design whose primary path is its fallback path is telling you something.

## Evaluation against drivers

| Driver | A (bash) | B (binary) | C (split) |
|---|---|---|---|
| R6 tool resolves | `command -v`, builtin, free | yes, but not for itself | shim for shirabe, binary for the rest |
| R7/R8 subcommand + flag surface | anchored grep, verified on bash 3.2 at 2 ms/probe | exact for shirabe, identical grep for the other five | same, split across the seam |
| R12 zero bytes on success | trivially; nothing prints unless a check fails | violated on a stale binary — clap writes to stderr before any of the check's own logic runs | holds only if the shim forks and captures rather than execs |
| R17 never blocks | script exits 0 unconditionally, one line | the established fail-safe idiom, its best fit | holds on both halves |
| R27 single capturable entry point | the script, always present, `bash <script> 2>&1 \| wc -c` | the entry point is absent on the host that most needs it; the missing-binary case cannot be constructed by the harness at all | the shim, always present |
| R28 overridable tool root | one variable read in one place | the binary cannot apply it to the tool it cannot see | the variable becomes a contract across the seam, honoured twice |
| Declaration co-location | script and declaration ship in the same commit | compiled-in declarations skew (0.16.1-dev vs v0.16.0, today); plugin-side declarations force the binary's first CLAUDE_PLUGIN_ROOT dependency | same problem as B |
| CI coverage | PR-triggered, Linux + macOS, explicit bash 3.2 leg | ubuntu-only, no matrix, cannot test its own absence | best coverage on the half that matters, weakest on the half that does not |
| Artifacts to keep in sync | one | one, skewing against the plugin | two, skewing against each other and against the plugin |

The two drivers that decide it are R27 and declaration co-location. R27 exists
specifically so R12 is falsifiable; an entry point that vanishes on the host
where the report matters most is not an entry point. And a check that reads a
declaration must be shipped by whatever ships the declaration, or the check and
the declaration drift — which R1-R5 and the PRD's fifth goal ("the declaration
and the check cannot drift apart, because the check reads the declaration")
rule out directly. Only the plugin ships both.

## Recommendation

**Option A: pure bash in the plugin.**

One entry point at the plugin root — `scripts/preflight-check.sh`, taking a
skill name — with helpers under `scripts/lib/`, following `#!/usr/bin/env bash`,
a documented exit-code header, and the `${CLAUDE_PLUGIN_ROOT:-self-resolve}`
fallback lifted verbatim from `preflight.sh:19`. It exits 0 unconditionally
(R17), prints nothing when the evaluated declaration is satisfied (R12), and
renders R13/R14-shaped instructions otherwise. Per-tool install routes and the
R20 gh/Linux exclusion live in a line-oriented plugin-side data file readable
without jq. R28's tool-location root is a single environment variable defaulting
to `~/.tsuku/tools/current/`. A `check-preflight-script.yml` clones
`check-plan-scripts.yml` verbatim, including the explicit `/bin/bash` macOS leg,
because this script is nontrivial and the bash 3.2 floor is the whole point of
that leg existing.

Two naming and scope items the design must settle alongside it:

*Rename or reconcile.* `skills/execute/scripts/preflight.sh` exists, is called
"preflight" everywhere in `skills/execute/SKILL.md`, and hard-fails with exit 1
— the opposite exit contract from R17. Two scripts named "preflight" in one
plugin with inverted blocking semantics will be confused by readers and by
agents. Pick a distinct name for the new check, or fold the existing one in as a
declaration entry. R25 forces `skills/execute/SKILL.md` open in the same change
regardless, so the reconciliation is cheap now and expensive later.

*Keep B available as an accelerator, not a dependency.* Because the entry point
is a script, a future `shirabe preflight` can be added and delegated to without
changing any SKILL.md, any test, or the entry-point contract. The reverse
migration — from a binary subcommand back to a script, after skills have been
written against it — is not free. A is the reversible choice, which is worth
something given that this is the first version of a check nobody has operated
yet.

## Consequences and what this forecloses

**Accepted.** A bash 3.2 artifact that will grow. Per-tool remediation data
expressed as `case` arms rather than a typed table, with no compile-time check
that a declared tool has an install route. No jq, so any structured data the
check reads must be line-oriented. Roughly 2 ms per surface probe and one
process per probe — 15 ms measured for eight, well inside the decision record's
100 ms figure, but it is linear in declared subcommands and nothing caches
across skill loads.

**Foreclosed for now.** Structural introspection of shirabe's own clap tree;
the check greps rendered help for shirabe exactly as it does for koto, so a
help-rendering change in clap is a silent break in the probe. This argues for
the probe's own regression test asserting a known-present and a known-absent
flag against the real binary. Also foreclosed: typed unit tests colocated with
the logic, and any cross-run caching in a persistent process.

**Not foreclosed.** Moving probe execution into the binary later, behind the
same entry point. Reusing the check from CI, since a script is directly
invocable from a workflow step in a way a subcommand requiring an installed
binary is not. Adding a `--format json` mode later, though emitting JSON from
bash without jq is a reason to defer it until something asks.

**A risk to name.** The check will accumulate install-route knowledge — R14,
R15, R19, R20 all push in that direction — and install-route logic is exactly
the kind of branching per-host data that gets unpleasant in bash 3.2. The design
should set a threshold now: if route resolution outgrows the `case` block, move
*route resolution alone* into the binary as an optional enhancement the script
uses when present and falls back from when absent. The check itself never sits
behind the binary.
