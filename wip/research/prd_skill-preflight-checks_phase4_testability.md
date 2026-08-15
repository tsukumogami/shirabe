# Verdict: FAIL

Reviewer: testability axis, /prd Phase 4 jury.
Document: `docs/prds/PRD-skill-preflight-checks.md` (Draft, 17 acceptance criteria, R1-R25).
Format reference: `skills/prd/references/prd-format.md` — Acceptance Criteria must be binary
pass/fail, verifiable by a developer who did not write the PRD, cover happy path and edge
cases, and verify requirements rather than duplicate them.

The requirements set is unusually strong: R1-R25 are specific, individually falsifiable, and
grounded in verifiable facts about this repo (I confirmed the `.tsuku.toml` `gh` comment, the
`koto >= 0.3.3` floor at `skills/work-on/SKILL.md:178`, the unsubstantiated `gh` auth claim at
`skills/execute/SKILL.md:272`, the exit-2 collision, and the Phase 3/Phase 4 mode-selection
boundary at `skills/plan/SKILL.md:442`). The acceptance criteria do not hold up to the same
standard. Five are not binary, one is arguably already satisfied by the unchanged system, one
demands a grep that fails on ~103 pre-existing sites, and four requirements have no criterion
at all.

## Per-criterion verifiability table

Criteria numbered in document order (AC1-AC17).

| # | Criterion (abbrev.) | How you would verify it | Binary? | Verdict |
|---|---|---|---|---|
| AC1 | Twenty skills have a declaration; five requiring nothing explicitly empty | `ls skills/` gives 20 dirs (confirmed). Parse each SKILL.md for the declaration block; count empties. | Count is binary; **the set is not** — the PRD never names which five. | WEAK |
| AC2 | Independent-cadence tools name no subcommands; `shirabe`/`koto` name subcommands, and flags "wherever the skill's logic branches on one" | First clause: greppable against the R3 tool list. Second clause: requires reading every phase of every skill and judging whether logic "branches on" a flag. | **No.** Two engineers will disagree on every borderline call site. | FAIL |
| AC3 | The split policy is written down with rationale in a durable document | Open a document and read it. Which document is unnamed; "with its rationale" is a quality judgment. | **No.** | FAIL |
| AC4 | Satisfied declaration → zero bytes of check output, verified by byte count | See hard case 1. | Conditionally — needs a stated invocation surface and a stated stream. | FAIL as written |
| AC5 | Tool removed from PATH → report names tool, capability, one command; skill still loads and remains usable | Sealed-PATH fixture, capture report, assert three substrings. "Remains usable" is not observable from a shell test. | Mostly. Drop "remains usable" or bind it to an exit code. | WEAK |
| AC6 | Subcommand absent → report names subcommand, says tool resolved, does not say tool missing | Stub whose `--help` omits the subcommand; assert substring present and a negative substring absent. | **Yes.** Best-formed criterion in the set. | PASS |
| AC7 | Flag absent from present subcommand → report names flag and subcommand | Stub whose `<sub> --help` omits the flag; two substring assertions. | **Yes.** | PASS |
| AC8 | Tool under `~/.tsuku/tools/current/` and off PATH → report says source the env file, offers no install command | See "new test machinery". Requires writing into the developer's real `$HOME`, or an injectable root the PRD does not require. | Assertions are binary; **the state is not creatable in CI**. | FAIL |
| AC9 | No requirement, check, or report references a version number; verified by grep over the shipped check surface | See hard case 3. | **No.** Neither the path set nor the pattern exists. | FAIL |
| AC10 | Mode-scoped requirement not reported at load; `/plan` without `gh` produces no `gh` finding; multi-pr branch reports it when selected | First half: sealed PATH + load, assert empty. Second half: drive `/plan` through Phases 1-3.5 to the mode decision — an agent eval, not a shell test. | Assertions binary; second half needs a harness that does not exist. | WEAK |
| AC11 | No network and no package manager → report states no install route and names the tool | Sealed PATH hides brew/apt/dnf. Network absence is a separate condition with no precedent. AC conflates the two without saying which drives the outcome. | Assertions binary; **state partly uncreatable**, and the trigger condition is ambiguous. | WEAK |
| AC12 | No probe and no skill call site redirects a tool's stderr to `/dev/null`; verified by grep across `skills/` | `grep -rn "2>/dev/null" skills/`. I ran it: **103 hits in 8 `.sh` files, 6 more in `.md`.** | Binary and **currently failing on pre-existing code**, most of it out of scope. | FAIL |
| AC13 | `shirabe validate` failing on an unrecognized flag is distinguishable by its consumer from one failing on document violations | See hard case 2. | **No.** Arguably already true today. | FAIL |
| AC14 | `skills/work-on/SKILL.md` has no Prerequisites section; no skill contains prose stating a tool version floor | First clause: `grep -n "### Prerequisites" skills/work-on/SKILL.md` → currently line 176. Second: pattern for "prose stating a version floor" undefined. | First yes; second no. | WEAK |
| AC15 | `references/fixes/cli-version-preflight.md` removed, or no remaining claim that a skill dereferences it | File exists; its own line 8 claims "dereferenced on-demand by chain skills (`/scope`, `/charter`)". Grep finds no skill actually pointing at it — only `DESIGN-shirabe-pattern-v1-ergonomics.md`. Ambiguous whether DESIGN references count. | Mostly, once scope is named. | WEAK |
| AC16 | `skills/execute/SKILL.md` does not claim a check its preflight does not perform | Requires reading the whole SKILL.md and cross-checking every claim against `preflight.sh`. The specific offending string is at line 272 but the AC does not name it. | **No.** Open-ended audit. | FAIL |
| AC17 | Empty declaration → no output and no probe | Output half is byte-countable given hard case 1. "Runs no probe" needs process tracing (`strace`/`dtrace`) or an instrumented harness. Also tests something no requirement states. | **No.** | FAIL |

Summary: 2 clean pass, 6 weak, 9 fail.

## Criteria requiring new test machinery

Precedent surveyed: `skills/execute/scripts/preflight_test.sh` (fake plugin roots via
`mktemp -d`, exit-code assertions), `skills/execute/scripts/run-cascade_test.sh` (PATH stub
injection at lines 1388/1416, `SHIRABE_BIN` override, `setup_shirabe_stub` wrapping the real
binary at line 284), and `skills/work-on/evals/fixtures/bin/koto` (shim exiting 127 under
`EVAL_SCENARIO=koto-missing`).

**State: tool removed from PATH (AC5, AC10 first half).** Precedent is *inverted*, not
absent. `run-cascade_test.sh` only ever *prepends* a stub dir (`PATH="$stub_dir:$PATH"`),
which adds a tool; nothing in the repo *removes* one. The `koto` eval shim looks like a
precedent but is a trap: under `koto-missing` it exits 127 while still being on PATH, so
R6's "resolves to an executable" probe (`command -v koto`) would report the tool **present**.
The shim simulates a failing call, not an absent tool. New machinery: a sealed-PATH fixture
(`PATH="$tmp/bin"` with only chosen tools symlinked in). Small, but genuinely new.

**State: tool present, subcommand missing (AC6).** Precedent exists and is close. The `koto`
shim already pattern-matches `ARGS` to emulate a subcommand surface, and `setup_shirabe_stub`
wraps the real binary while overriding one path. A stub emitting a `--help` body with one
subcommand elided is a direct extension. Low cost.

**State: tool present, flag missing (AC7).** Same precedent as above, and the probe shape is
already documented in the repo: `references/fixes/cli-version-preflight.md` shows
`shirabe transition --help 2>&1 | grep -qE -- '--superseded-by'`. Low cost.

**State: no network and no package manager (AC11).** No precedent anywhere in the repo.
Nothing simulates network absence. Cost depends on an undecided design point: if "no install
route" is determined purely by the absence of brew/apt/dnf on PATH, the sealed-PATH fixture
covers it; if the check probes reachability, you need a network namespace or an injected
override. The AC must say which condition drives the outcome before its cost can be
estimated.

**State: tool under `~/.tsuku/tools/current/` but off PATH (AC8).** No precedent, and the
hardest of the set. The path is absolute and user-scoped. A test either hardcodes
`$HOME/.tsuku/tools/current/` — mutating the developer's real installation, and unavailable
on a CI host with no tsuku — or the check must accept an overridable root. That override is a
*design affordance the requirements do not ask for*, so a design that satisfies R18 literally
can leave AC8 permanently unverifiable. This is the one place where an AC gap forces a
requirement change, not just an AC rewrite.

**State: mode-scoped deferral (AC10 second half).** Highest cost, and it spans two harnesses.
The load-time half is a shell test; the "multi-pr branch reports it when that mode is
selected" half requires driving `/plan` to the Value Confirmation and Execution Mode Selection
step, which `skills/plan/SKILL.md:442` places *between Phase 3 and Phase 4* — an agent eval.
`skills/plan/evals/` currently contains `evals.json` and no `fixtures/` directory, so the
fixture surface for this does not exist.

**Grep-only criteria (AC9, AC12, AC14, AC15).** No machinery needed, but each needs a stated
path set and pattern to be binary. See hard case 3 and the AC12 finding below.

## The three hard cases

### 1. AC4 — "produces zero bytes of check output. Verified by byte count, not by inspection."

Zero bytes is not observable as written, and the reason is structural rather than
nitpicking. The PRD deliberately declines to say how the check runs — correctly, since that
is a design question — but "byte count" presumes an artifact with a capturable output stream.
If the design lands the check as prose in each SKILL.md instructing the agent to verify its
declaration, there is no stream to count: "output" becomes the agent's choice about whether
to narrate, which is exactly the failure mode the Decisions section warns about ("a risk that
it starts narrating environment status to the user"). AC4 would then be unfalsifiable while
still appearing rigorous.

Two things must be true for this to be measurable, and the PRD should require both without
prescribing an implementation. First, the check must have a **single invocable entry point**
whose output can be captured in one shell expression — that is a requirement-level property
(the check is a runnable artifact), not a design choice. Second, the AC must name **which
stream** it counts. Combined capture is the only honest reading, because R21 forbids
discarding stderr, and a check that prints a warning to stderr while keeping stdout clean
would pass a stdout-only count and fail a combined one. Two competent engineers reading AC4
today will pick different streams and reach opposite verdicts.

There is also a live counterexample worth naming: today's `skills/execute/scripts/preflight.sh`
prints `execute preflight OK: cross-skill child template resolves at: ...` on success. The
repo's only existing preflight does the exact opposite of R12, so the change must strip that
line, and AC4 should be the criterion that catches it.

Required shape: "Running the check against a fully satisfied declaration produces zero bytes
on stdout and stderr combined, measured as `[[ $(bash <check> 2>&1 | wc -c) -eq 0 ]]`."

### 2. AC13 — "distinguishable by its consumer"

Not testable as written, and it fails in the most dangerous way: **the unchanged system
arguably already satisfies it.** I verified against the installed `shirabe v0.16.0`:

```
$ shirabe validate --not-a-real-flag --format json
error: unexpected argument '--not-a-real-flag' found
...
Usage: shirabe validate [OPTIONS] [FILES]...
$ echo $?
2
```

The clap usage error goes to stderr, exit 2, and **no `shirabe-validate/v1` JSON envelope is
emitted on stdout**. Document violations emit the envelope and exit 2.
`skills/scope/SKILL.md:627-636` documents the consumer as parsing that envelope *and*
branching on the exit code. So an engineer can argue today that the two failures are already
distinguishable — parse the envelope, treat "absent" as tool-error — and mark AC13 passed
without a single line changing. A criterion that a no-op satisfies cannot certify the feature.

"Distinguishable" also names neither the discriminator nor the consumer. At least three
incompatible designs satisfy the sentence: change `validate` to exit 1 (or a new code) on
usage errors; require the consumer to treat an absent envelope as R22's tool-error bucket; or
add an explicit discriminator field inside the envelope. A tester handed the finished work
cannot say pass or fail without knowing which was chosen, and the three have different
blast radii for `/scope`, `/charter`, and `/execute`.

Required shape: name the discriminator and the consumer, and assert both branches. For
example: "`shirabe validate --<unrecognized-flag>` and a document with a known violation
produce different values of `<named discriminator>`; `skills/scope/SKILL.md`'s documented
branch routes the first to the tool-error path (R22) and the second to the violation path,
and the routing is asserted for both inputs."

### 3. AC9 — "grep over the shipped check surface"

Not greppable, on two independent counts.

**The path set does not exist.** "The shipped check surface" names no files, and cannot
before the DESIGN decides where declarations live and where the check is implemented. Its
extent is genuinely contested: declarations only? declarations plus the check implementation?
plus the report/instruction templates? Each choice yields a different verdict, since install
instructions for `koto` plausibly carry a pinned URL or tag.

**The pattern does not exist, and it over-tests its requirement.** R9 forbids the check to
"parse, compare, or gate on a version number." AC9 forbids anything that "references a version
number" — strictly broader. Under AC9, a probe that runs `koto --version` purely to confirm
the binary executes fails, while satisfying R9 completely; so does an install command pinning
a release tag. A criterion must not be stricter than the requirement it verifies, or the
implementer satisfies the requirement and still fails the gate. Separately, `shirabe#270` and
`tsukumogami/tsuku#2245` are numbers a naive version regex will hit, and `0.16.1-dev` lives in
`plugin.json` regardless of this feature.

Required shape: state the path set (even as a glob the DESIGN must populate) and the pattern,
and align the verb with R9 — forbid version *comparison or gating*, not version *reference*.

## Uncovered requirements

**R2 (per-skill and composable; no skill inherits another's).** No criterion tests
non-inheritance. AC1 tests presence only. A design where a shared base declaration is merged
into every skill would pass every AC and violate R2. Needs a criterion asserting that a
declaration added to one skill does not appear in another's evaluated set.

**R16 (report complete on first emission; no second, more verbose run).** No criterion at all.
This is a load-bearing requirement — the rationale is that "the reader gets one pass and
cannot ask again" — and nothing verifies it. A design shipping `--verbose` would pass the
whole AC set. Needs a criterion asserting no affordance in the report directs the reader to
re-run.

**R19 (instructions resolved against what the host has; delegate to a package manager already
present).** Only the *negative* case is covered, by AC11 (no package manager → say so).
Nothing tests the positive: a host *with* a package manager gets a command that delegates to
it rather than an OS-enumerated list. This is R19's actual content, and it is the easiest of
the host states to fixture (a sealed PATH containing a stub `brew`).

**R20 (account for combinations known not to work — `gh` commented out of `.tsuku.toml` as
segfaulting on Linux).** No criterion whatsoever. I confirmed the exclusion is live at
`.tsuku.toml`: `# gh = "latest"  # disabled: segfaults on Linux (tsukumogami/tsuku#2245)`.
R20's whole point is that this knowledge lives only in a TOML comment; with no AC, nothing
forces it out of that comment. Needs: "On Linux, the instruction for `gh` does not route
through tsuku."

**Partial coverage worth noting.** R11's second clause ("the declaration SHALL make that
deferral visible rather than silent") is untested — AC10 tests the check's behavior, not the
declaration's visibility. R14's "naming which outcome from R13 holds" is untested; AC5 asserts
tool, capability, and command, but not the posture label. R17 is tested only by AC5's
non-binary "remains usable".

**Criterion testing something no requirement states.** AC17's "and runs no probe" has no
requirement behind it. R12 requires zero output on a satisfied declaration; no requirement
says an empty declaration must execute no subprocess. It is also the least observable
assertion in the document — proving a negative about process execution needs `strace`/`dtrace`
or an instrumented harness. Either add a requirement (reasonable: it is the cost argument in
Known Limitations, "one subprocess per declared subcommand") or drop the clause and keep the
byte count.

## Required changes

1. **AC13 — name the discriminator and the consumer.** As written, the shipped
   `shirabe v0.16.0` arguably already passes (clap usage errors emit no
   `shirabe-validate/v1` envelope while exiting 2). Restate as: `shirabe validate` with an
   unrecognized flag and `shirabe validate` on a violating document differ in `<named
   discriminator>`, and `skills/scope/SKILL.md`'s documented branch routes the first to
   R22's tool-error path and the second to the violation path — asserted for both inputs.

2. **AC9 — state the path set and the pattern, and align the verb with R9.** Replace "the
   shipped check surface" with an enumerated glob the DESIGN must populate, give the regex,
   and forbid version *comparison or gating* rather than version *reference*, so a
   `--version` liveness probe or a pinned install URL does not fail a criterion R9 permits.

3. **AC4 — make zero bytes measurable.** Specify stdout and stderr combined, give the
   measurement (`wc -c` on combined capture), and add a requirement that the check is a
   single invocable entry point whose output is capturable — without prescribing what it is.
   Otherwise a prose-in-SKILL.md design leaves the criterion unfalsifiable. Note that
   `skills/execute/scripts/preflight.sh` currently prints an OK line on success and must
   stop.

4. **AC12 — scope the grep or accept the real cost.** `grep -rn "2>/dev/null" skills/`
   returns **103 hits across 8 `.sh` files** plus 6 in `.md` today. Live tool call sites
   include `gh issue view ... 2>/dev/null`
   (`skills/work-on/references/scripts/extract-context.sh:320`),
   `gh repo view ... 2>/dev/null` (`skills/plan/scripts/create-issues-batch.sh:273`), and —
   most pointedly — `koto context get ... 2>/dev/null`
   (`skills/execute/koto-templates/execute.md:390,409`), the exact shape of `shirabe#279`
   that the Problem Statement cites, still live. `skills/plan/scripts/plan-to-tasks_test.sh`
   alone holds 58, nearly all `jq` on internal data. Either restrict the criterion to the
   check's own probes plus call sites for R3's declared tools in non-test files, or state
   that all 103 are in scope and move the remediation into Requirements. Also widen the
   pattern: `&>/dev/null` and `2>&1 >/dev/null` discard stderr and do not match `2>/dev/null`.

5. **AC8 — make the tsuku state creatable, or the criterion is dead on arrival.** Verifying
   it today requires writing into the developer's real `$HOME/.tsuku/tools/current/` and is
   impossible on a CI host without tsuku. Either add a requirement that the check's
   tool-location root is overridable for verification, or restate AC8 against an injected
   root. No existing fixture covers this state.

6. **AC2 — remove the judgment clause.** "names flags wherever the skill's logic branches on
   one" cannot be adjudicated without re-deriving every skill's call graph. Replace with a
   mechanical form: every flag appearing in a `shirabe`/`koto` invocation in a skill's phases
   also appears in that skill's declaration, verified by comparing declared flags against
   flags extracted from the skill's own command lines.

7. **AC16 — name the string.** Replace the open-ended "does not claim a check its preflight
   does not perform" with the concrete assertion: `skills/execute/SKILL.md` line 272's
   `confirm \`gh\` auth is live` is either removed, or `skills/execute/scripts/preflight.sh`
   performs a `gh` auth check. Otherwise the criterion is an unbounded audit.

8. **AC3 — name the document.** "written down with its rationale in a durable document" gives
   the tester no file to open. Name the artifact (or the class of artifact) and assert the
   policy statement's presence there.

9. **Add criteria for R16, R19, R20, and R2.** Respectively: the report contains no
   affordance directing the reader to re-run more verbosely; on a host with a package manager
   present, the instruction delegates to it; on Linux the `gh` instruction does not route
   through tsuku; and a declaration added to one skill does not appear in another's evaluated
   set.

10. **AC17 — drop "runs no probe" or add the requirement behind it.** No requirement states
    it, and proving it needs process tracing. If the subprocess cost in Known Limitations is
    the real concern, promote it to a requirement first.

11. **AC1 — pin the five, or drop the number.** The PRD asserts five skills require nothing
    but names only `/decision`. Either enumerate them (the count is checkable: `skills/` holds
    exactly 20 directories) or restate as "every skill requiring no host tool carries an
    explicitly empty declaration", which is verifiable without a magic number.

12. **AC5 — replace "remains usable".** Not observable from a test. Bind R17 to something
    mechanical: the check's exit status does not halt the skill, or the skill's first phase
    still executes after an unsatisfied report.

13. **AC11 — separate the two conditions.** "No network and no package manager" conflates an
    easily fixtured state (empty PATH of package managers) with one that has no precedent in
    this repo (network absence). Say which condition triggers the no-install-route report; if
    both are required, say how a tester creates the second.
