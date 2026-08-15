# Decision 4: Probe strategy and report format

Scope: HOW the check probes and WHAT it prints. What gets verified is
settled by `docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md`
and is not reopened here.

## Measured probe costs

All figures measured on this host (Darwin arm64, M-series, warm page
cache), mean of 10-20 runs. Harnesses are under `wip/` alongside this
report; every number below is reproducible by running them.

### Does `--help` enumerate a whole level in one call?

Yes, for both first-party tools. Verified by running them.

`shirabe --help` (exit 0) prints a `Commands:` block listing all nine
top-level commands — `validate`, `roadmap`, `transition`,
`finalize-chain`, `slug-prefix-detect`, `install-hooks`,
`work-summary`, `pr-body-hook`, `help`. `koto --help` (exit 0) prints
all sixteen — `version`, `init`, `next`, `cancel`, `rewind`,
`workflows`, `template`, `session`, `context`, `status`, `decisions`,
`overrides`, `config`, `workspace`, `dashboard`, `help`.

The decision record's claim holds. One call resolves the tool *and*
enumerates every top-level subcommand, so presence and the entire
first subcommand layer cost one invocation, not one per subcommand.

### Per-call cost

```
    3.19 ms   shirabe --help
    2.70 ms   shirabe roadmap --help
    2.58 ms   shirabe roadmap populate --help
    2.57 ms   shirabe validate --help
    2.61 ms   shirabe transition --help
    2.54 ms   shirabe work-summary --help
    2.81 ms   koto --help
    2.76 ms   koto context --help
    2.75 ms   koto session --help
    2.73 ms   koto next --help
    2.18 ms   jq --help
    9.89 ms   git --help
   20.37 ms   gh --help
   20.08 ms   gh --version
    4.34 ms   python3 --version
    0.13 ms   command -v (shell builtin, no subprocess)
```

shirabe and koto are ~2.5-3 ms; the decision record's "roughly 2ms"
was close and slightly optimistic. `gh` is the expensive one at 20 ms,
which is the strongest cost argument for declaring `gh` tool-only
rather than by subcommand — a point R3/R4 already settle on
independent grounds.

### How a flag is checked

`<tool> <subcommand> --help` and parse the `Options:` block. One call
per flag-bearing subcommand, not one per flag: a single
`shirabe validate --help` yields all fifteen of its flags at once, so
a subcommand with four declared flags costs the same as one with one.

The parse must be position-anchored, not a loose grep, and this is not
a stylistic preference — it is a measured false-positive. Flags are
routinely named in *prose* inside clap descriptions. Running both
extractors over `shirabe roadmap --help`:

```
loose  (grep '--[a-z-]*' anywhere):   --help  --issues  --no-issues
strict (Options: block, definition column only):   --help
```

`--issues` and `--no-issues` appear only inside `populate`'s
description text at that level; neither is a flag of `shirabe
roadmap`. A loose grep reports a flag as present that the level does
not accept — the exact false-pass the check exists to prevent. The
strict extractor keys on clap's layout: option *definitions* carry 2-6
leading spaces, wrapped descriptions carry 8 or more. It was verified
against both of clap's layouts — inline (`  -h, --help  Print help`)
and wrapped-long-flag (`      --no-issues` with the description on the
following line, as `shirabe roadmap populate` renders) — and returns
the correct set for both.

### The nested-group case

A group costs exactly one extra call, and only the group, not its
members. `shirabe roadmap --help` (exit 0) lists `populate`; checking
`shirabe roadmap populate` therefore costs one call for the `shirabe`
top level, one for the `roadmap` group, and one more only if a flag on
`populate` is declared. `koto context --help` behaves identically.

Levels are memoized: `koto context get`, `koto context add`,
`koto context exists` together cost **one** `koto context --help`, not
three.

### Real call counts and wall time

Counted against the declarations actually present in the skill trees
(enumerated from `SKILL.md`, `references/phases/*`, `references/scripts/*.sh`,
and `koto-templates/*`), not against estimates.

**`/work-on`** — the heaviest skill in the corpus. Its real surface is
koto-dominated: `koto version|init|next|rewind|workflows`,
`koto context add|get|exists|remove`, `koto decisions record`,
`koto overrides list`, plus `shirabe validate --pr-body --pr-title`
and `shirabe pr-body-hook` via the shared `references/pr-body-conformance.md`;
`gh`, `git`, `jq` are presence-only.

```
  10 --help calls + 3 command -v   ->  18.7 ms
  levels probed:
    koto, koto init, koto next, koto decisions, koto decisions record,
    koto context, koto context add, koto overrides,
    shirabe, shirabe validate
```

Note what memoization buys: eleven declared koto subcommands across
three groups collapse to eight calls, and five of those eleven
(`version`, `rewind`, `workflows`, `context get`, `context exists`,
`overrides list`) cost nothing beyond the group enumeration they
already share.

**`/scope`** — far lighter than expected. Its real first-party surface
is two leaf subcommands, no nested groups, no koto at all:
`shirabe validate --format --visibility --coordination-body --merge-gate`
and `shirabe slug-prefix-detect --docs-root`.

```
   3 --help calls + 2 command -v   ->   5.9 ms
  levels probed: shirabe, shirabe validate, shirabe slug-prefix-detect
```

**Worst case in the corpus**: 12 calls at **48.7 ms**, and that figure
only arises if `gh` and `git` were ever declared by subcommand — which
R3 forbids. Under the actual policy the true worst case is `/work-on`
at **10 calls, 18.7 ms**.

The decision record stated 6-9 calls under 100 ms. The call count is
low by one to four (10, not 6-9), because the record's estimate
predated the enumeration of work-on's real koto surface. The timing
claim holds with large margin: 18.7 ms against a 100 ms budget.

### Resolution and R12 verified

Resolving all six tools including filesystem probes of three fallback
roots costs **3.29 ms**. The satisfied path was measured end to end:
running `/scope`'s real declaration through the prototype entry point
and capturing stdout and stderr together yields **0 bytes**, asserted
with `wc -c` per R12's acceptance criterion, not by inspection.

### A live defect the probe found while being measured

Running the real `/work-on` declaration reported:

```
!! MISSING SUBCOMMAND: 'koto context remove'
```

Confirmed directly: `koto context remove foo` exits 2 with
`error: unrecognized subcommand 'remove'`. `koto context` advertises
`add`, `get`, `exists`, `list` and nothing else. The call site is
`skills/work-on/references/phases/phase-4a-scrutiny.md:45`, instructing
the agent to run `koto context remove <WF> scrutiny_results.json` to
clear a stale artifact.

This is a second live instance of the shirabe#279 shape, in the tree
today, found by the probe in 18.7 ms. It is the single strongest piece
of evidence that the probe strategy works, and it should be cited in
the DESIGN rather than merely fixed quietly.

## Options considered

**Probe each declared subcommand directly (`<tool> <sub> --help`, one
call per subcommand).** The original framing in
`references/fixes/cli-version-preflight.md`. Rejected on measured
cost: `/work-on`'s eleven koto subcommands would cost eleven calls
plus the flag calls, roughly 21 calls against the 10 that enumeration
needs, for identical information. Enumeration strictly dominates.

**Run the real command with a harmless argument and read the exit
code.** Rejected outright. It has side effects, it cannot be made safe
across a corpus containing `koto init` and `roadmap populate`, and
clap returns exit 2 for both an unknown subcommand and a malformed
argument, so it cannot distinguish "surface absent" from "my probe was
wrong". It also inverts R8, which asks what the tool *advertises*, not
what it accepts.

**Parse `--help` with a loose grep.** Rejected on the measured
false-positive above: it reports `--issues` as present on `shirabe
roadmap`, which does not accept it.

**Ask the tool for a machine-readable surface dump (a hypothetical
`shirabe --dump-surface --json`).** Attractive and rejected for now.
It would be faster and unambiguous, but it requires shipping a new
subcommand in both binaries before the check can work anywhere, it
does not exist in any released build, and it fails on exactly the
stale binaries the check exists to detect — a koto old enough to lack
`context remove` is old enough to lack the dump verb. `--help` is the
one interface every version already has. Worth revisiting once the
floor is old enough that no supported build lacks it.

**Parallelise the probes.** Rejected as unnecessary. At 18.7 ms
sequential for the worst case, the complexity buys nothing a reader
can perceive, and it would interleave diagnostics from failing probes,
which R21 requires be preserved legibly.

**Report to stderr, or split across both streams.** Rejected in favour
of stdout only. R12's assertion is over the combined capture, so
either choice satisfies it, but keeping stderr empty in normal
operation means a non-empty stderr is unambiguously the check itself
malfunctioning, which is signal worth preserving. R27's entry point
captures both regardless.

## Recommendation

**Probe by level enumeration, memoized, parsed with a
position-anchored extractor over `--help`.** For each declared entry,
walk the subcommand path one level at a time: one `--help` per level
visited, cached so sibling subcommands and repeated paths cost
nothing, plus one `--help` per leaf subcommand carrying a declared
flag. Resolution comes first and free — `command -v` at 0.13 ms, then
`-x` tests against an overridable list of fallback roots (R28) only
when `command -v` fails. Never execute a declared subcommand to test
it; never parse a version.

**Report as one plain-prose block per unsatisfied entry, on stdout,
ordered PATH-invisibility first.** Each block names the posture in
words, states what the skill cannot do in terms of that skill's own
work, and ends with exactly one command or an explicit statement that
no route exists. Ordering is load-bearing for R18: a host that has
shirabe and koto under `~/.tsuku/tools/current` but has not sourced
`~/.tsuku/env` produces two off-PATH findings, and an agent that reads
an install instruction first will reinstall tools that are already
there.

**Emit an upgrade command for a surface gap, and say in the same
breath what it cannot promise.** This is the part the requirements
force and the obvious design gets wrong. R19 forbids emitting a
command whose availability is unestablished; the acceptance criterion
reads "runs successfully on that host". `tsuku install koto@latest`
does run successfully, and the resolver establishes that by checking
`tsuku` resolves and `tsuku info koto` succeeds. But the check cannot
establish that any *released* koto has `context remove`, because it
reads one installed binary's surface and there is no version-to-feature
map — the decision record says so explicitly. A report that prints
"upgrade koto" and stops is quietly lying about a subcommand that has
never existed at any version. Each surface-gap block therefore carries
one closing sentence naming the other possibility: the call site is
wrong. That is not hedging, it is the honest bound on what a surface
probe knows, and it keeps the report complete on first emission (R16)
rather than sending the reader to discover it the hard way.

### Resolver order

R18 and R19 together fix the order. Established empirically on this
host: with `PATH=/usr/bin:/bin:/usr/sbin:/sbin` (an unsourced shell),
`shirabe` and `koto` resolve OFF_PATH under
`~/.tsuku/tools/current`, `jq`/`git`/`python3` resolve ON_PATH, and
with the root list overridden to `/nonexistent` everything reports
ABSENT — confirming R28's override actually governs the distinction.

1. `command -v <tool>` — if it resolves, the tool is present; proceed
   to surface checks.
2. Otherwise `-x` test each root in `SHIRABE_PREFLIGHT_ROOTS`
   (default `~/.tsuku/tools/current:~/.shirabe/bin:~/.local/bin`,
   overridable per R28). A hit is **off-PATH**, and the remedy is
   `. ~/.tsuku/env` with no install offered.
3. Only on a miss everywhere is the tool **absent**, and only then is
   an install route resolved.

Route availability is probed, never assumed. Measured on this host:
`tsuku` AVAILABLE at `~/.tsuku/bin/tsuku`, `brew` AVAILABLE, `cargo`
AVAILABLE, `apt-get` UNAVAILABLE, and `tsuku info` succeeds for all of
`koto`, `shirabe`, and `gh`. A route counts as available only when its
driver resolves *and* it knows the package.

R20's exclusion — `gh` is commented out of `.tsuku.toml` as
segfaulting on Linux, citing `tsukumogami/tsuku#2245` — must move out
of that TOML comment into a machine-readable exclusion table the
resolver reads, which the PRD's acceptance criterion already demands.
The resolver consults it before offering tsuku for a tool, so on Linux
the `gh` route is skipped and the next available one is offered.

## The report format

Verbatim output as a reader sees it. No color, no box drawing, no
emoji, no glyph key, no re-run affordance.

### Case 1 — koto absent from the host entirely

```
shirabe /work-on: prerequisite not met.

koto is not installed on this host. Checked PATH, then
~/.tsuku/tools/current, ~/.shirabe/bin, and ~/.local/bin.

/work-on drives every phase through koto: without it no phase can be
entered, advanced, or rewound, no phase artifact can be stored or read
back, and no gate override can be recorded. The skill will load and
its first phase will run, but nothing will persist.

Install it:

  tsuku install koto && . ~/.tsuku/env
```

### Case 2 — shirabe present under `~/.tsuku/tools/current` but off PATH

```
shirabe /scope: prerequisite not met.

shirabe is installed but not on this shell's PATH. It is at
/Users/you/.tsuku/tools/current/shirabe, which is not in PATH. Nothing
needs installing and nothing is out of date.

Until it is on PATH, /scope cannot validate a document at any chain
step and cannot detect the workspace slug prefix, so Phase 0 setup and
every subsequent validation gate will fail as written.

Put it on PATH:

  . ~/.tsuku/env
```

### Case 3 — koto present but lacking a declared subcommand

```
shirabe /work-on: prerequisite not met.

koto resolves at /Users/you/.tsuku/tools/current/koto and runs, but it
does not have the subcommand `koto context remove`. `koto context`
advertises: add, get, exists, list. The tool is installed and working;
only this part of its surface is absent.

/work-on uses it to clear a stale scrutiny artifact before re-running
phase 4a (skills/work-on/references/phases/phase-4a-scrutiny.md:45).
That call will exit 2 with "unrecognized subcommand 'remove'". No other
phase is affected.

Update to the newest koto:

  tsuku install koto@latest && . ~/.tsuku/env

This check reads the installed binary's advertised surface and nothing
else. It cannot tell you whether any released koto has `context
remove`. If the newest build still does not, the call site is wrong and
needs changing -- the binary is not the problem.
```

### Case 4 — shirabe present, subcommand present, declared flag absent

```
shirabe /scope: prerequisite not met.

shirabe resolves at /Users/you/.tsuku/tools/current/shirabe and has the
subcommand `shirabe validate`, but `validate` does not advertise the
flag `--merge-gate`. It advertises: --allow-untracked-acs, --check,
--coordination-body, --custom-statuses, --format, --lifecycle,
--lifecycle-chain, --mode, --pr, --pr-body, --pr-title, --upstream,
--visibility.

The tool is present and the subcommand is present; one flag is
missing. /scope passes it to run the coordinated multi-repo merge
gate, so that gate cannot run. Single-repo scoping is unaffected and
the rest of the chain will complete.

Update to the newest shirabe:

  tsuku install shirabe@latest && . ~/.tsuku/env

This check reads the installed binary's advertised surface and nothing
else. It cannot tell you whether any released shirabe has
`--merge-gate`. If the newest build still does not, the call site is
wrong and needs changing -- the binary is not the problem.
```

### Case 5 — gh absent on a host with no install route available

```
shirabe /work-on: prerequisite not met.

gh is not installed on this host. Checked PATH, then
~/.tsuku/tools/current, ~/.shirabe/bin, and ~/.local/bin.

/work-on uses gh to read the issue it was asked to implement, to poll
CI checks, and to open the pull request. Phases 0 through 5 will run;
phase 6 cannot complete.

No install route is available on this host, so this report gives no
command. Every route was checked:

  tsuku     excluded for gh on Linux -- segfaults, tsukumogami/tsuku#2245
  homebrew  brew does not resolve
  apt-get   does not resolve
  cargo     resolves, but publishes no gh package

Install gh by whatever means this host supports, or run /work-on
through phase 5 and open the pull request by hand.
```

### Shape rules the five cases encode

- **Silence is the whole of the satisfied case.** Measured at 0 bytes
  combined (R12). There is no success line, no count, no timing.
- **The first line names the skill and states the posture in plain
  words.** No status codes, no severity glyphs.
- **The second paragraph says what the skill cannot do**, in terms of
  that skill's own phases, never in terms of the tool (R14).
- **Exactly one command, on its own indented line**, or an explicit
  no-route statement (R14, R15, R19). Never two commands, never a
  choice for the reader to make.
- **Off-PATH blocks say "nothing needs installing" outright** (R18),
  and sort before absent-tool blocks so an agent reading top-down
  cannot reinstall a tool it already has.
- **Surface-gap blocks list what the level does advertise.** Naming
  the alternatives is what turns "wrong subcommand" into a fixable
  observation, and it costs nothing since the probe already parsed
  the list.
- **Nothing points at a second run.** No `--verbose`, no environment
  variable, no "for details" (R16).

## Consequences

The check's implementation is a `--help` parser, so it inherits clap's
help layout as a contract. If a future clap changes the `Commands:` or
`Options:` block shape the extractor silently under-reports, which
fails open into false findings rather than false silence — noisy, but
not the silent-pass failure mode that matters. The extractor should
carry a test asserting both known layouts against fixtures captured
from real help output, which is the cheapest guard available.

`/work-on` pays 18.7 ms and 10 subprocesses at every load. That is the
real recurring cost of this feature and it is worth stating plainly in
the DESIGN rather than rounding to "negligible", because it scales
with declaration size and `/work-on`'s declaration is the one most
likely to grow.

The honest-bound sentence on surface-gap blocks means some reports end
by telling the reader the tool might be fine and the skill might be
wrong. That reads as weaker than a confident "upgrade koto", and it is
correct: `koto context remove` has never existed at any version, so
the confident version would send a reader to reinstall a binary that
was never going to help. The DESIGN should expect a reviewer to push
back on this wording and should hold it.

Moving the `gh`-on-Linux exclusion out of the `.tsuku.toml` comment
creates a small piece of machine-readable data with no current owner.
It needs a home and a rule for who updates it, or it becomes the next
thing that drifts — the same failure the decision record catalogues
for version floors.

The probe found `koto context remove` while this decision was being
measured. That defect should be fixed in this feature's work, and the
DESIGN should cite it as the second filed-and-reproduced instance of
the shirabe#279 class rather than treating shirabe#279 as a single
historical incident.
