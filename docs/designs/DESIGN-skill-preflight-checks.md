---
schema: design/v1
status: Proposed
upstream: docs/prds/PRD-skill-preflight-checks.md
problem: |
  shirabe's twenty skills call six host tools and none of them declares what it
  needs. The check that would verify such a declaration cannot live in the
  `shirabe` binary, because the binary is one of the tools it reports on and is
  silent in exactly the case that matters. It cannot read YAML either, because
  no host tool shirabe can assume parses YAML: jq is JSON-only and installed
  explicitly in CI, yq appears nowhere in the repo, python3 ships no YAML in its
  stdlib, and the bash floor is 3.2. Four live defects in the tree today show
  the cost of leaving this unbuilt, one of which has kept `/inflight` from
  loading on any host since 2026-07-07.
decision: |
  A per-skill sidecar at `skills/<name>/requires.tsv`, one tab-separated record
  per tool/subcommand/mode triple, read by a plugin-shipped POSIX shell script
  at `scripts/skill-preflight.sh`. Each SKILL.md gains one injected command that
  runs the script at load and one matching `allowed-tools` entry. The script
  resolves each declared tool with `command -v`, falls back to an overridable
  root list to tell "absent" from "off PATH", probes surface by enumerating one
  `--help` per subcommand level with memoization and a position-anchored
  extractor, prints plain prose for each unsatisfied entry, prints nothing at
  all when everything is satisfied, and always exits 0. Install routes and the
  `gh`-on-Linux exclusion move into a line-oriented data file the script reads
  only after a tool is found absent.
rationale: |
  Two decisions concluded independently that the entry point must be a shell
  script rather than the binary, and a third concluded the declaration should be
  a sidecar rather than SKILL.md frontmatter. Those hold together only if the
  sidecar is readable by a shell, which is why the format is line-oriented
  rather than the YAML a binary-side reader would have made free. Tab separation
  is the same choice the discard enumeration reached on its own evidence, so the
  repo gains one data convention rather than two. Silence on the satisfied path
  is load-bearing rather than tasteful: skill re-invocation dedup is a strict
  byte comparison, so any varying output costs a full second copy of the
  SKILL.md body on every reload.
---

# DESIGN: Skill preflight checks

## Status

Proposed

Specifies the implementation for `docs/prds/PRD-skill-preflight-checks.md`
(status In Progress, requirements R1 through R28). What the check verifies is
already settled by
`docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md`;
this document takes that as given and does not reopen it.

## Context and Problem Statement

A skill ships inside the plugin. The binary it calls installs separately. They
drift by construction, and they are drifting in this worktree right now:
`plugin.json` reads `0.16.1-dev` against an installed `shirabe v0.16.0`. No
skill body states which host tools it needs, so nothing detects the drift and
the failures land as misroutes rather than crashes.

The PRD makes the case from five filed incidents. This design adds four defects
found while the decisions behind it were being measured, all four verified in
this worktree. They matter here because each one is a live instance of a failure
mode the architecture has to survive, and because they set the order the work
has to ship in.

**`skills/inflight/SKILL.md:77` kills the skill on every host.** The line is

```
!`shirabe work-summary track <pr-url> [<pr-url> ...]`
```

It was written as documentation of a verb the agent should run later, but it
carries the injection syntax at column 0, so the harness executes it at load
with the literal placeholder text as arguments. To a shell `<pr-url>` is a
redirection, not a placeholder. The command fails, and a non-zero exit from an
injected command aborts the whole skill invocation. `git blame` puts the line in
`db91dc6` (#226, 2026-07-07); the skill's original form in #219 had no such
line. `/inflight` has not loaded on any host since.

**`skills/inflight/SKILL.md:40` is a bare injection with no fallback.**
`shirabe work-summary render` always exits 0 by construction, so the command is
safe when it runs at all. On a host without the binary the shell returns 127 and
the skill dies rather than degrading to the empty-state line its own body
documents.

**`skills/work-on/references/phases/phase-4a-scrutiny.md:45` calls a subcommand
that does not exist.** It instructs the agent to run
`koto context remove <WF> scrutiny_results.json`. `koto context` advertises
`add`, `get`, `exists`, and `list`. The call exits 2 with
`error: unrecognized subcommand 'remove'`. The surface probe prototyped for this
design found it in 18.7 ms while being timed, which is the strongest evidence
available that the probe strategy works: it caught a defect nobody was looking
for, in the tree, on the first real declaration it was run against.

**`skills/execute/koto-templates/execute.md:390` and `:409` mask a failure with
a fabricated value.** The line is

```bash
SETTLED_BRANCH=$(koto context get {{SESSION_NAME}} settled_branch 2>/dev/null || echo "impl/$PLAN_SLUG")
```

Probing the live binary turned up something worse than R26 describes.
`koto context get` writes its error JSON to stdout, not stderr, so the
`2>/dev/null` suppresses a stream koto does not use for errors and has never
done anything. Command substitution captures stdout, `||` still fires on the
non-zero exit, and the variable receives the error JSON *and* the fallback
string concatenated. Only the downstream character-class guard rescues it,
because the JSON happens to contain braces and quotes. A koto error whose text
was sanitizer-clean would flow onward as a real branch name. The fix is to
branch on exit status, not to delete a redirect that never did anything.

Two of these four are failures of the load-time injection mechanism this design
adopts, in the only two places the repo already uses it. That is the strongest
argument in the record for fixing them before shipping the same mechanism to
twenty more skills.

## Decision Drivers

**The check must speak when the binary is absent.** `shirabe` is one of the six
tools the check reports on. A check inside the binary is silent in exactly the
case it most needs to speak, and worse: a stale binary answers an unknown
subcommand with exit 2 and a clap error on stderr, which is the same overloaded
code R22 exists to disambiguate and a direct R12 violation on a host that may be
perfectly healthy.

**The declaration and the reader must ship together.** The PRD's fifth goal is
that they cannot drift, because the check reads the declaration. Only the plugin
ships both. Anything compiled into the binary describes a different set of
skills than the ones on disk the moment the plugin updates first, which under
`marketplace.json`'s `"source": "./"` is every time the checkout moves.

**No assumable host tool parses YAML.** jq is JSON-only and the repo installs it
explicitly in three workflows, which is the repo's own admission that it is not
assumable. yq appears nowhere in the repo, in any workflow, or in `.tsuku.toml`.
python3 ships no YAML parser in its stdlib. bash is 3.2.57 on macOS, with no
`declare -A` and no namerefs, and `shirabe#270` is on file as bash 4 syntax
meeting exactly that shell.

**Silence on the satisfied path is load-bearing.** Skill re-invocation dedup is
a strict byte comparison of rendered content. Byte-identical renders collapse to
a one-line "already loaded" note; anything different re-appends the entire
SKILL.md body plus a note explaining that the output is new. A checkmark list, a
timing, or a version string does not cost its own length. It costs a second full
copy of the skill on every reload. R12's zero bytes is the only output shape
that guarantees identical renders.

**An injected command can delete a skill.** The harness evaluates the permission
check and throws on anything other than an explicit `allow`; injected commands
never prompt. A non-zero exit throws as well. Both throws abort the invocation
before the model sees the body. The mechanism that gives determinism is the same
mechanism that can silently remove the skill.

**The check never blocks (R17) and must be capturable by a test (R27, R28).**
The acceptance criteria are written in a vocabulary this repo speaks in bash:
`wc -c` over a combined capture, `PATH=` scrubs, injected roots built with
`mktemp -d`. CI already runs the shell suite on a `[ubuntu-latest, macos-latest]`
matrix with the macOS leg invoking `/bin/bash` explicitly, which
`check-plan-scripts.yml` calls the guard against reintroducing a post-3.2
construct. The Rust suite runs ubuntu-only with no matrix and structurally
cannot test the missing-binary case, because the harness must run the binary to
run the test.

## Considered Options

### Where the check is implemented

**A. A POSIX shell script shipped in the plugin.** Chosen. One entry point at
`scripts/skill-preflight.sh`, alongside the existing `scripts/check-*.sh` family,
with helpers under `scripts/lib/` following `scripts/lib/koto-gates.sh`.
Everything it touches is present and version-matched whenever a skill loads,
because the plugin is the checkout. The script, the declaration, and the
SKILL.md that invokes them move as one commit. There is no seam across which
anything can skew, which is a strange property to be able to claim about a
feature whose whole subject is skew.

**B. A `shirabe preflight` subcommand.** Rejected, and it is the option with the
best engineering on its own terms: the fail-safe idiom is proven twice in this
repo by `pr_body_hook.rs` and `work_summary.rs`, exit-0 discipline maps exactly
onto R17 and R12, and clap can be asked structurally what it accepts rather than
grepped. It fails three ways that have nothing to do with quality. It cannot
report its own absence. It misreports its own staleness as exit 2 with bytes on
stderr, reproducing the defect the PRD was written against. And it defeats R27
and R28 as test surfaces, because the entry point does not exist on the host that
most needs it. There is a fourth problem it shares with C: `grep -rn
CLAUDE_PLUGIN_ROOT crates/` returns zero hits, so a plugin-side declaration would
introduce the binary's first dependency on plugin layout, a new coupling running
opposite to the one this feature reduces.

**C. A split, with a shim resolving the binary and the binary doing the rest.**
Rejected. `exec` is not available to the shim: an `exec` forfeits its only chance
to intercept a stale binary's exit 2 and clap error, so the shim must fork and
capture, which costs the second process the split was meant to avoid. Working out
what each side owns settles it. The shim owns plugin-root self-resolution, binary
resolution, the R28 root read, R18's ordering rule, the R15 no-route case, R19's
availability requirement, and a full report renderer for the two shirabe cases.
That is the reporting machinery minus one loop. The binary would own ten lines of
`--help` grepping. And on the day this ships every host is the stale case, so the
Rust half is dead code for exactly the population the feature exists to serve.

### How the declaration is written and where it lives

This is the question where the decisions had to be reconciled rather than
summed, so the reasoning is given at length.

**A. A `metadata:` block in SKILL.md frontmatter.** Rejected.
`quick_validate.py` in the cached skill-creator plugin defines
`ALLOWED_PROPERTIES` as `{name, description, license, allowed-tools, metadata,
compatibility}` and rejects any other top-level key, so `metadata:` is genuinely
the one free-form slot. But zero of the 116 cached SKILL.md files use it, which
means no worked example and no evidence of how packaging treats its contents.
More decisively, `quick_validate.py` reads only SKILL.md and never enumerates the
skill directory, so a sidecar is invisible to it and to every packaging path that
shares its rules. `DESIGN-shirabe-child-dispatch-contract.md` asked this exact
question for team-shape declarations and chose `skills/<name>/team.yaml`, with the
verdict that "SKILL.md frontmatter is for plugin metadata, not for content
schemas." Choosing frontmatter now would split shirabe's declaration surface for
no reason either decision records. Editing requirements would also touch the file
whose `description` string governs skill triggering.

**B. A YAML sidecar at `skills/<name>/requires.yaml`, parsed by the `shirabe`
binary.** Evaluated in full and rejected on cross-validation. This was the
recommendation the declaration-format decision reached in isolation, and its
reasoning about *location* is correct and is carried forward: a sidecar, not
frontmatter; one entry per tool/subcommand/mode triple; a mandatory `when:`
field; an explicit-empty file distinguishable from an absent one. Its reasoning
about *format* rested on a premise that is true and an option set that was
incomplete. The premise is that nothing on an assumable host parses YAML, so the
only possible reader is the binary, which already depends on `saphyr` and already
parses `skills/writing-style/rules.yaml` this way. That premise is right. What it
never evaluated is a sidecar in a format a POSIX shell can read, which dissolves
the constraint rather than accepting it. And the binary-as-reader conclusion
collides head-on with the implementation-home and load-mechanism decisions, which
independently concluded that the reader must not be the binary, because a check
inside the binary is silent exactly when the binary is missing. The decision's own
consequences section had already noticed the seam, calling out that a skill
declaring `shirabe` cannot have that declaration read when `shirabe` is the thing
missing, and asking for a non-YAML fallback for that one case. Once the fallback
has to exist anyway, a format the fallback can read for every case is strictly
simpler than two readers with a bootstrap hole between them.

**C. A table compiled into the binary.** Rejected. It puts the declaration in a
different repo region, in a different language, behind a release cycle, from the
skill prose it describes, which is precisely the drift the PRD's problem
statement is about. The PRD's answer to PR #278 turns on the declaration being
written by the same author, in the same change, as the call it describes; a
compiled table breaks that by construction and makes the check unable to serve a
repo that adds a skill without rebuilding shirabe.

**D. A line-oriented sidecar at `skills/<name>/requires.tsv`, read by the
shell.** Chosen. This is the resolution of the cross-validation. It keeps every
structural conclusion B reached and changes only the encoding, so the shell-side
reader that decisions A and the load mechanism both require becomes possible. Tab
separation rather than any other delimiter, for three reasons. Pipe collides with
real command text (`jq -r '.findings | length'` appears in the sites the
enumeration must record) and would need escaping in the exact field a scan parses.
Comma appears inside flag lists. Tab appears in neither, and it is the same
delimiter the discard-enumeration decision reached independently on its own
evidence, so the repo ends with one data convention across all three of its
line-oriented surfaces rather than two. It is also consistent with the
implementation-home decision's separate finding that R20's `gh`-on-Linux exclusion
has to be line-oriented rather than JSON, since jq is not assumable.

The cost of D over B is real and should be stated: no schema validation from a
parser, no comments-with-structure, and a format a maintainer has to learn from
its header rather than recognize. A CI conformance scan replaces the parser, and
the schema is four fields.

### How the check runs at skill load

**A. An injected command per SKILL.md, with a matching `allowed-tools` entry.**
Chosen. The harness substitutes the command's stdout into the body before the
model sees anything, so the check is unskippable and its output arrives ahead of
the instructions it qualifies. `${CLAUDE_PLUGIN_ROOT}` expands on both sides,
body and `allowed-tools` pattern, so a pattern can name the same absolute path the
body invokes. On the satisfied path it substitutes zero bytes, with no tool call
and no round trip. It is the only option that can produce literally nothing.

**B. A plugin-shipped `PreToolUse` hook on the `Skill` tool.** Not disqualified,
but unresolved on the point that decides it. A per-skill declaration needs the
skill's identity, and the hook's `tool_name` is the generic `"Skill"`; whether the
individual skill name reaches the hook is unconfirmed. It also fires for every
skill from every plugin, a global blast radius the feature does not need, and it
routes the report through `additionalContext` rather than into the body the model
is about to read. It stays the fallback if the injection path is ever closed by
policy, and it is the natural home for the mode-scoped enforcement in R11.

**C. A fenced bash block instructing the model to run the check.** Rejected on
the driver the feature exists to satisfy. Prose that tells the model to check
something is the state this work ends:
`references/fixes/cli-version-preflight.md` is prose no skill cites, so it never
loads, and `skills/work-on/SKILL.md`'s koto floor is an instruction the model may
or may not act on. It also inverts the ordering and cannot satisfy R12, because a
tool call with an empty result is not zero bytes.

### How the probe reads a tool's surface

**Level enumeration with memoization, parsed by a position-anchored extractor.**
Chosen. One `--help` per subcommand level visited, cached so siblings and repeated
paths cost nothing, plus one `--help` per leaf carrying a declared flag. Verified:
`shirabe --help` lists all nine top-level commands and `koto --help` all sixteen,
so presence and the entire first subcommand layer cost one call.

**One `--help` per declared subcommand.** Rejected on measured cost.
`/work-on`'s eleven declared koto subcommands would cost eleven calls plus flag
calls, roughly 21 against the 10 enumeration needs, for identical information.

**Run the real command with a harmless argument and read the exit code.**
Rejected outright. It has side effects, cannot be made safe across a corpus
containing `koto init` and `roadmap populate`, and clap returns 2 for both an
unknown subcommand and a malformed argument, so it cannot tell "surface absent"
from "my probe was wrong". It also inverts R8, which asks what a tool advertises.

**A loose grep over `--help`.** Rejected on a measured false positive. Running
both extractors over `shirabe roadmap --help`, the loose one reports `--help`,
`--issues`, and `--no-issues`; the strict one reports `--help`. The other two
appear only inside `populate`'s description prose at that level and are not flags
of `shirabe roadmap`. clap names flags in prose, so a loose grep reports a flag as
present that the level does not accept, which is the exact false pass the check
exists to prevent.

**A machine-readable surface dump.** Attractive and deferred. It would be faster
and unambiguous, but it requires shipping a new subcommand in both binaries before
the check works anywhere, and it fails on exactly the stale binaries the check
exists to detect: a koto old enough to lack `context remove` is old enough to lack
the dump verb. `--help` is the one interface every version already has.

### How the discards are enumerated and how a stale binary is told apart

**An inline marker comment at each exempt call site.** Rejected on requirement
grounds. R21b exists so that adding an exemption is a reviewed edit rather than a
judgment made silently at the call site. An inline-only marker is that silent
judgment.

**A markdown table in `references/`.** Rejected on mechanics. The join key must
include the command text, and several in-scope commands contain a pipe, which
would need escaping in the field the scan parses.

**A TOML, JSON, or YAML data file.** Rejected on convention. The repo has no
committed data files of those types under `references/` or `scripts/`, and it
would need a parser for a file a human must review.

**A markdown policy document whose canonical records live in a fenced
tab-separated block.** Chosen, following `references/wip-hygiene.md` and
`references/worktree-discipline.md`: normative prose no skill loads, reviewed as
part of a PR.

For R22, four options were weighed. **A new sentinel exit code** was rejected for
inventing a fifth value in a vocabulary deliberately shared with `transition` and
`finalize-chain`, leaving every existing consumer misrouting until updated. **A
marker string in the usage-error text** was rejected because it makes consumers
string-match framework-generated text, which is the brittleness R22 is trying to
end. **Changing clap's usage-error exit code to 1** is necessary but cannot work
alone: a stale binary is by definition one that predates the fix, so the producer
change helps nobody currently experiencing the problem. **Having consumers test
for the envelope before reading the exit code** is the load-bearing half, and it
works against every shirabe version ever shipped. Both ship together, with the
consumer-side rule as the normative discriminator.

## Decision Outcome

Twenty skills each gain a four-field tab-separated sidecar naming the host
surface they call, and one injected command in their SKILL.md that runs a
plugin-shipped POSIX shell script against that sidecar at load. The script
resolves, probes, and reports without ever blocking and without ever printing
anything on a satisfied host. The binary is a subject of the check, never its
reader.

The pieces hold together because each one removes a seam rather than adding a
contract. The declaration ships in the same commit as the script that reads it
and the SKILL.md that invokes it, so nothing can skew. The format is readable by
the shell that has to survive the binary being absent, so there is one reader
rather than a reader plus a bootstrap fallback. Silence on the satisfied path
falls out of the same choice that keeps dedup working, so the cheap case is
cheap for a reason the design can state rather than a preference. And the entry
point is a script, so a future `shirabe preflight` can be delegated to without
changing any SKILL.md, any test, or the entry-point contract. The reverse
migration, from a subcommand back to a script after twenty skills have been
written against it, is not free. This is the reversible direction, which is worth
something for the first version of a check nobody has operated yet.

## Solution Architecture

### Components

| Component | Path | Role |
|---|---|---|
| Declaration sidecar | `skills/<name>/requires.tsv` | One per skill, twenty total. Four tab-separated fields per record. |
| Entry point | `scripts/skill-preflight.sh` | Reads one skill's sidecar, resolves, probes, reports. Always exits 0. |
| Helpers | `scripts/lib/preflight-*.sh` | Resolver, probe, reporter, sourced by the entry point. |
| Route table | `scripts/lib/tool-routes.tsv` | Install routes per tool and the R20 exclusions. Read only after a tool is found absent. |
| Discard enumeration | `references/tool-diagnostic-discards.md` | Policy prose plus a fenced tab-separated record block. Read by CI only. |
| Discard scan | `scripts/check-tool-diagnostic-discards.sh` | Joins live sites against the enumeration in both directions. |
| Injection scan | `scripts/check-skill-injection.sh` | Asserts every injected command is covered by an `allowed-tools` entry in the same file and carries an outer exit-0 guard. |
| Conformance scan | `scripts/check-skill-requires.sh` | Twenty sidecars exist; every record has exactly four fields; declared flags match flags extracted from the skill's own command lines. |

Two data conventions, split by who reads them. Anything on the load path is a
bare `.tsv` under `scripts/lib/` or `skills/<name>/`, because parsing a fenced
block out of markdown at every skill load is work for nothing. Anything on the
review path is markdown policy prose with a fenced record block, because a human
has to read the rule before they read the records.

### The declaration format

```
#schema	skill-requires/v1
<tool>	<subcommand>	<flags>	<when>
```

Field one is the tool name. Field two is the full subcommand path including
spaces (`roadmap populate`, `context add`), because that is the string the probe
hands to `--help`, or a literal `-` for a tool with an independent release
cadence, which R3 says names no subcommands. Field three is a comma-separated
flag list with no spaces, or `-` for none. Field four is `always` or
`mode:<name>`.

Every field is mandatory and `-` is the explicit empty value rather than an empty
field. Two reasons. A trailing empty field is invisible in a diff and vulnerable
to an editor that trims trailing whitespace, and R22a's lesson is that an
unstated default is where the failure hides: an entry that forgets its mode
marker must fail the conformance scan, not silently become always-required.

A file containing only the schema line is an explicit empty declaration. An
absent file is undeclared, and the conformance scan fails on it. That is R1's
distinction, and it is decidable by `ls` rather than by grepping twenty markdown
files for a nested key.

### Three concrete declarations

`skills/decision/requires.tsv` in full:

```
#schema	skill-requires/v1
```

`/decision` is the PRD's named exemplar for a skill that needs nothing beyond a
checkout, verified: its SKILL.md contains no `shirabe`, `koto`, `gh`, `jq`,
`git`, or `python3` call line. The file exists and carries no records. Deleting
it would make `/decision` undeclared, which R1 requires be a different state.

`skills/roadmap/requires.tsv`:

```
#schema	skill-requires/v1
shirabe	transition	-	always
shirabe	roadmap populate	--no-issues	always
shirabe	roadmap populate	--issues,--milestone,--milestone-description,--output-map	mode:issues
gh	-	-	mode:issues
```

The issueless form of `roadmap populate` runs on every path, so `--no-issues` is
always-required while the issue-creating flags and `gh` are `mode:issues`. Two
records share a tool and a subcommand at different modes, which is deliberate:
the entry unit is the triple, so R2's composability holds per record and the
check evaluates the always subset by filtering one field.

`skills/work-on/requires.tsv`:

```
#schema	skill-requires/v1
koto	version	-	always
koto	init	--template,--var	always
koto	next	--with-data	always
koto	rewind	-	always
koto	workflows	-	always
koto	context add	-	always
koto	context get	-	always
koto	context exists	-	always
koto	decisions record	--with-data	always
koto	overrides list	-	always
shirabe	validate	--pr-body,--pr-title	always
shirabe	pr-body-hook	-	always
gh	-	-	always
git	-	-	always
jq	-	-	always
```

`/work-on` is the heaviest declaration in the corpus and it is all-always, which
is worth stating so an author does not go looking for a mode declaration that
correctly does not exist. It has three modes and they differ in `gh` usage, but
`gh` is independent-cadence so its record names the tool alone, and every mode
needs `gh` for PR creation regardless. R5's split only produces mode-scoped
records where a mode changes which tool is needed, or changes a first-party
subcommand or flag.

Note what is absent: `koto context remove`. That record is what a declaration
written against the tree today would carry, and it is what the probe reported as
a surface gap when it was measured. The call site is the defect, so the fix is at
`phase-4a-scrutiny.md:45` and the declaration follows the corrected call site.

### Probe and resolution

Resolution runs first and is nearly free: `command -v` is a shell builtin at
0.13 ms and spawns nothing.

1. `command -v <tool>`. If it resolves, the tool is present; go to surface
   checks.
2. Otherwise test each root in `SHIRABE_PREFLIGHT_ROOTS` with `-x`, defaulting
   to `~/.tsuku/tools/current:~/.shirabe/bin:~/.local/bin` and overridable per
   R28. A hit means off-PATH, and the remedy is `. ~/.tsuku/env` with no install
   offered.
3. Only on a miss everywhere is the tool absent, and only then is an install
   route resolved at all.

The ordering is R18, and it was established empirically: with
`PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `shirabe` and `koto` resolve off-PATH under
`~/.tsuku/tools/current` while `jq`, `git`, and `python3` resolve on-PATH, and
with the root list overridden to `/nonexistent` everything reports absent, which
confirms R28's override actually governs the distinction.

Surface probing then walks each declared subcommand path one level at a time,
memoizing levels. The extractor keys on clap's layout rather than searching the
text: option definitions carry 2 to 6 leading spaces, wrapped descriptions carry
8 or more. It was verified against both of clap's layouts, inline
(`  -h, --help  Print help`) and wrapped-long-flag (`      --no-issues` with the
description on the next line, as `shirabe roadmap populate` renders).

Measured cost on this host, mean of 10 to 20 runs: shirabe and koto `--help` at
2.5 to 3 ms each, `gh --help` at 20 ms, `git --help` at 9.9 ms. `/work-on` costs
10 `--help` calls and 3 `command -v` for 18.7 ms, over ten distinct levels:
`koto`, `koto init`, `koto next`, `koto decisions`, `koto decisions record`,
`koto context`, `koto context add`, `koto overrides`, `shirabe`, and
`shirabe validate`. `/scope` costs 3 calls and 5.9 ms. The satisfied path was
measured end to end at 0 bytes combined, asserted with `wc -c` per R12's
acceptance criterion rather than by inspection.

`gh` at 20 ms per call is the strongest cost argument for declaring it tool-only,
which R3 and R4 already reach on independent grounds.

### The report

Plain prose on stdout, one block per unsatisfied record, off-PATH blocks first.
No color, no box drawing, no glyphs, no re-run affordance. Two of the five cases,
verbatim as a reader sees them:

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

Six shape rules the cases encode. The first line names the skill and states the
posture in words. The second paragraph says what the skill cannot do in terms of
that skill's own phases, never in terms of the tool. Exactly one command on its
own indented line, or an explicit no-route statement, never two commands and
never a choice for the reader. Off-PATH blocks say "nothing needs installing"
outright and sort first, so an agent reading top-down cannot reinstall a tool it
already has. Surface-gap blocks list what the level does advertise, which costs
nothing because the probe already parsed the list and is what turns "wrong
subcommand" into a fixable observation. Nothing points at a second run.

The closing sentence on surface-gap blocks is the part the requirements force and
the obvious design gets wrong. R19 forbids emitting a command whose availability
is unestablished, and the resolver can establish that `tsuku install koto@latest`
runs. It cannot establish that any *released* koto has `context remove`, because
it reads one installed binary's surface and there is no version-to-feature map.
A report that says "upgrade koto" and stops is quietly lying about a subcommand
that has never existed at any version. Naming the other possibility is the honest
bound on what a surface probe knows, and it keeps the report complete on first
emission. It reads weaker than a confident instruction. It should be held anyway.

Route availability is probed, never assumed: a route counts as available only
when its driver resolves *and* it knows the package. Measured on this host,
`tsuku`, `brew`, and `cargo` resolve while `apt-get` does not, and `tsuku info`
succeeds for `koto`, `shirabe`, and `gh`. R20's exclusion moves out of the
`.tsuku.toml` comment into `scripts/lib/tool-routes.tsv`, and its header states
the rule for changing it: a route is added or excluded together with the incident
that justifies it, cited by issue number. Without a stated owner it becomes the
next thing that drifts, which is the same failure the decision record catalogues
for version floors.

### The SKILL.md contract

Frontmatter, added to the existing `allowed-tools` where a skill has one:

```
allowed-tools: Bash(sh ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
```

Body, at column 0, once per skill, near the top:

```
!`sh ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> 2>&1 || true`
```

Every element is load-bearing. `sh <path>` rather than the path directly, because
invoking through an interpreter ignores the executable bit and the design must
not depend on `chmod +x` surviving packaging, cloning, or a marketplace fetch;
this also matches the house idiom already at `skills/execute/SKILL.md:129`. The
path is unquoted on both sides, because `allowed-tools` matching is textual
against the expanded command and a quoted body against an unquoted pattern risks
a mismatch, which aborts the skill; the cost is that a plugin root containing a
space breaks, and the canonical install path has none. The literal skill name
rather than `${CLAUDE_SKILL_DIR}`, because a literal name is greppable and lets a
test invoke the entry point for a named skill directly, which is what R27 asks
for. `2>&1` merges the streams under the script's control, so the satisfied case
is unambiguously empty rather than empty plus a possible `[stderr]` decoration
the harness appends, and so the thing a test captures and the thing the model
sees are the same string.

`|| true` is the one element in tension with a constraint this design otherwise
respects. Permission patterns do not compose across shell operators, so the
injected line should avoid them and the script should own its own error
discipline. The script does own it: no `set -e`, `set -u` throughout, every probe
guarded, an explicit `exit 0` at the end, following `pr_body_hook.rs` and
`work_summary.rs` rather than the `validate`/`transition` family with its
four-level exit vocabulary. But the script's discipline covers only what the
script can reach, and the dangerous failures happen before its first line
executes. A missing script or an unexpanded `${CLAUDE_PLUGIN_ROOT}` both give
`sh` exit 127, and without the guard that kills every skill at once. Dropping the
guard was considered and rejected on exactly that trade: it converts a report
that fails to appear into twenty skills that fail to load. So the guard stays,
`Bash(true)` is declared alongside the script pattern, and the composition itself
becomes a named implementation risk validated before rollout rather than assumed.

The general rule the `/inflight:77` defect teaches goes into the same contract:
*injection syntax is for commands intended to execute at load; a command shown to
the reader as an example must never be written with a leading `!` at column 0.*
`scripts/check-skill-injection.sh` enforces both halves, following
`scripts/check-template-interpolation.sh` and `scripts/check-sentinel.sh`, each
wired as its own path-filtered workflow.

### The naming collision, reconciled

`skills/execute/scripts/preflight.sh` already exists. It asserts that the
cross-skill `/work-on` child template resolves, it uses `set -euo pipefail`, it
exits 1 on failure, and `skills/execute/SKILL.md` says a non-zero exit halts the
run. That exit contract is correct for an agent-run assertion in the middle of a
workflow and exactly wrong for anything injected at load, and two scripts named
"preflight" in one plugin with inverted blocking semantics will be confused by
readers and by agents.

Resolution: rename it to `skills/execute/scripts/assert-child-template.sh`, which
names what it does, keep its fail-closed exit 1, and make its success path
silent so it stops printing `execute preflight OK: ...`. The PRD's acceptance
criteria name that success line directly. The rename touches
`skills/execute/SKILL.md` at lines 129, 276, 681, and 706, the sibling
`preflight_test.sh`, five references in `skills/execute/evals/evals.json`, and
`.github/workflows/check-execute-scripts.yml`. R25 forces that SKILL.md open
anyway, so the reconciliation is cheap now and expensive later.

R25 itself resolves by removal rather than by implementation. The claim that the
preflight will "confirm `gh` auth is live" comes out of `skills/execute/SKILL.md`,
and no auth check is added. Auth liveness is a credential state, not a CLI
surface, and it can expire between load and the phase that needs it. `gh auth
status` is also a network round trip on a path whose measured budget is 18.7 ms
of local process spawns. `/execute`'s declaration covers `gh` presence; auth is
outside the check's remit and the claim was never true.

### Mode-scoped verification

R10 and R11 split load-time from mode-selection-time. The injected line evaluates
only `when: always` records and marks `mode:` records visibly deferred, because
the mode has not been chosen when the skill loads. At the step that selects a
mode, the phase runs the same entry point with a mode argument:

```
sh ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> --mode <name>
```

This is the agent-instructed shape rejected for load-time use, and it is
acceptable here for the reason it was rejected there: mode selection is itself an
agent decision at a known step, so there is no earlier deterministic hook to
prefer. Mode names are an interface. The strings in `requires.tsv` must match the
strings the SKILL.md phases use, and the conformance scan checks that.

### The R22 discriminator

The verified matrix against `shirabe v0.16.0`: an unrecognized flag exits 2 with
clap usage text on stderr and no envelope; a clean document exits 0 with an
envelope; a violating document exits 2 with an envelope; mutually exclusive flags
exit 1 with no envelope. The collision is real, and both consumers branch on exit
2 and then read `findings` from an envelope that was never emitted.

The bug is narrower than it looks. `ValidateOutcome::ToolError` already maps to
exit 1 and is already documented as covering bad invocation. clap intercepts an
unrecognized flag and exits 2 with its own default before `run_validate` is
entered, so this is one existing contract that a framework default bypasses.

Two changes, and the consumer-side one is normative. Producer: replace
`Cli::parse()` with `Cli::try_parse()`, mapping `DisplayHelp` and
`DisplayVersion` to exit 0 and every other kind to exit 1. This is safe on all
three axes: `main.rs:171` freezes annotation-format bytes and a usage error emits
none, the three tests exercising clap usage errors all assert `.failure()` rather
than `.code(2)`, and no CI branches on validate's exit 2 specifically. Consumer:
**on a `--format json` run, absence of a parseable `shirabe-validate/v1` envelope
on stdout means the validator never reached a verdict, regardless of exit code.**

The producer change alone helps nobody. A stale binary is by definition one that
predates it, so the user experiencing the problem still gets exit 2 from their
old binary. The consumer rule works against every shirabe version ever shipped,
because envelope-absence on a `--format json` run is not a new signal.
`skills/scope/SKILL.md`'s Validator Pass-Through section gains an explicit
precedence rule ahead of its branch list, and `/charter`'s finalization step 4
gets the same treatment: it already lists "an envelope that does not parse" as a
tool-error cause, but only inside the exit-1 bullet, where an exit-2 no-envelope
run can never reach it. Both consumers also capture stderr rather than discarding
it, because in the no-envelope case the stderr text is the entire diagnostic
payload.

### The discard scan

Four redirect shapes, not the three the acceptance criteria name. R21's own text
is the authority: it forbids redirection to `/dev/null` in any spelling, and the
criteria omit `>/dev/null 2>&1`, which discards stderr just as completely and
matches six more in-scope sites. The criteria are under-specified against their
own requirement rather than a ceiling.

`command -v <tool>` is carved out. Measured directly: it writes zero bytes across
both streams and exits 1, there is no diagnostic to discard, and the declared tool
is never executed. Every such site already tests the exit status. Folding the
eight of them in would add entries whose "exit status the fallback is entered on"
is a property of the shell rather than of the tool, diluting a list whose value is
that a reader can scan it for genuine risk.

Net: 27 in-scope under the criteria's literal shape list, 33 with the fourth
shape, 25 after the carve-out. Two are R26 remediations and 23 become enumeration
entries, which is 22 records because two are byte-identical lines in one file.

The join key is `path` plus the trimmed source line, never `path:lineno`. Line
numbers drift whenever anything above a site is edited, which would make every
unrelated change break the build. Keying on the trimmed line tolerates
reindentation but breaks on an edit to the command itself, which is correct:
changing what the command does should force the exemption back through review.
An occurrence count catches a third byte-identical copy. The scan reports both
directions, so an unenumerated site fails and a stale entry matching nothing also
fails, and the list cannot rot into a permanent allowlist. Tool names come from
the declarations rather than a hardcoded list, so the scan's scope grows with
them.

Two scan details are stated coverage limits rather than oversights. Hits must
have `path:lineno:` stripped before the declared-tool test, or
`skills/work-on/koto-templates/work-on.md:441`'s `go test ./... 2>/dev/null` is
charged to `koto` because `koto` appears in a directory name; since the
enumeration must cover `koto-templates/`, that false-positive class is guaranteed
to recur. And the unread-variable arm runs against `*.sh` only. In `.md`
templates it produces a false positive on the first file it touches:
`skills/execute/koto-templates/execute.md:498` assigns `CASCADE_STATUS` and never
references it in shell, but the surrounding prose instructs the agent to submit
it, so the consumer is an agent reading prose.

## Implementation Approach

### Phase 1: the four live defects

Ships first and ships alone, before any new surface. Two of the four are
failures of the load-time injection mechanism in the only two places the repo
already uses it, and multiplying an unproven pattern by twenty is the wrong order
of operations.

- `skills/inflight/SKILL.md:77`: drop the leading `!` and present the line as an
  ordinary code sample. This is what it was always meant to be, and it restores
  `/inflight` on every host for the first time since #226.
- `skills/inflight/SKILL.md:40`: add a fallback branch and the matching
  `allowed-tools` entry, so a missing binary degrades to the skill's own
  documented empty-state line rather than a 127 that aborts the invocation. The
  fallback echoes an explanation rather than nothing, because `/inflight` is a
  relay skill whose whole body assumes the block exists.
- `skills/work-on/references/phases/phase-4a-scrutiny.md:45`: correct the
  `koto context remove` call to something koto advertises. `koto context` offers
  `add`, `get`, `exists`, and `list`; which of them expresses "clear the stale
  scrutiny artifact" is an implementation question the plan settles, and the
  `/work-on` declaration follows whatever it lands on.
- `skills/execute/koto-templates/execute.md:390,409`: branch on exit status.
  `koto context get` distinguishes 3 (key or session absent), 2 (clap usage
  error), and 127 (binary absent). Exit 3 keeps the fallback and becomes an
  enumeration entry with its status named. Exits 2 and 127 surface the captured
  stderr and stop. The character-class sanitizer stays as defence in depth but is
  no longer load-bearing.

### Phase 2: the permission-pattern spike

A gate, not a deliverable. Validate the exact `allowed-tools` pattern against the
exact injected body line on a host whose `permissions.defaultMode` is not `auto`.
The machine this was researched on carries `"defaultMode": "auto"` in
`~/.claude/settings.json`, which masks a pattern mismatch entirely, and neither
`.claude/settings.json` in this repo nor any `settings.local.json` carries a Bash
allow-list, so there is no local evidence either way. A mismatch does not degrade
the check. It silently deletes the skill. Rollout does not proceed until this is
green on a non-auto host, and `scripts/check-skill-injection.sh` plus its workflow
land here so the invariant is held mechanically afterward.

### Phase 3: entry point, declarations, and the naming reconciliation

- Rename `skills/execute/scripts/preflight.sh` to `assert-child-template.sh`,
  silence its success line, update the eight call sites and the workflow, and
  remove the `gh` auth claim from `skills/execute/SKILL.md` (R25).
- Write `scripts/skill-preflight.sh` and the `scripts/lib/preflight-*.sh`
  helpers, plus `scripts/lib/tool-routes.tsv` seeded with the R20 exclusion moved
  out of the `.tsuku.toml` comment.
- Write twenty `skills/<name>/requires.tsv` files.
- Write `scripts/check-skill-requires.sh` and a
  `check-preflight-scripts.yml` workflow cloning `check-plan-scripts.yml`
  verbatim, including the explicit `/bin/bash` macOS leg. The bash 3.2 floor is
  the whole reason that leg exists, and a grep-based portability check has
  already missed a nameref that only running the suite on the floor caught.
- Test coverage lands with the script: `wc -c` over a combined capture for R12,
  `PATH=` scrubs for the absent case, `SHIRABE_PREFLIGHT_ROOTS` pointed at an
  `mktemp -d` tree for the off-PATH case, and a probe regression test asserting a
  known-present and a known-absent flag against the real binary, since the
  extractor inherits clap's help layout as a contract.

### Phase 4: rollout and retirement

Add the injected line and the `allowed-tools` entry to all twenty skills.
Fifteen have no `allowed-tools` today. In the same change, remove the prose the
declaration supersedes (R24): `skills/work-on/SKILL.md`'s Prerequisites section
including its `koto >= 0.3.3` floor, and `references/fixes/cli-version-preflight.md`,
whose `--help` grep technique retires into the check rather than being
repudiated.

### Phase 5: signal integrity

- `references/tool-diagnostic-discards.md` seeded with 23 entries in 22 records,
  `scripts/check-tool-diagnostic-discards.sh` with a `_test.sh` sibling, and
  `.github/workflows/check-tool-diagnostic-discards.yml` on the
  `check-no-duplicate-rule-list.yml` pattern: ubuntu-latest, one `run:` step,
  path-filtered, no matrix, since the scan is pure text.
- The R22 producer change and both consumer precedence rules, with a sentence in
  `docs/guides/multi-consumer-cli-contract.md` stating envelope-presence
  precedence.
- R22a: pass mode-selecting flags explicitly at the `roadmap populate` call sites
  and any peer with the same shape.

### Phase 6: mode-scoped verification

The `--mode` path at each mode-selecting step (R11). Last, because it is the only
part with no load-time consumer and because the mode-name interface is easier to
get right once twenty declarations exist to check it against.

## Security Considerations

**The injected command runs at every skill load with the user's full
permissions, before the model sees anything.** This is the largest surface the
design adds. The mitigations are that the command is a fixed string in a
committed SKILL.md rather than anything composed at runtime, that it takes one
argument which is a literal skill name rather than data, that
`allowed-tools` pre-approves exactly one pattern rather than a class, and that
`scripts/check-skill-injection.sh` fails CI on an injected command not covered by
an `allowed-tools` entry in the same file. The residual risk is that anyone who
can land a commit in the plugin can land a command that runs on every load, which
is already true of every script the plugin ships and is bounded by code review
rather than by this design.

**`${CLAUDE_PLUGIN_ROOT}` may be unset.** If it fails to expand, the injected
command becomes `sh /scripts/skill-preflight.sh <name>`, an absolute path at the
filesystem root. On macOS and Linux an unprivileged attacker cannot create
`/scripts`, so the degenerate case is a 127 caught by the outer guard rather than
an execution of attacker-controlled code. This is why the path must stay
absolute: a relative fallback would resolve against the current working
directory, and the working directory during a skill load is a repository whose
contents may have arrived from a pull request. The script's own
`${CLAUDE_PLUGIN_ROOT:-self-resolve}` fallback, lifted from the existing
`preflight.sh`, resolves from `$0` rather than from `$PWD` for the same reason.

**Declaration files are read from the repository and their contents reach a
shell.** A `requires.tsv` record supplies a tool name and a subcommand path that
the probe passes to `--help`. Three controls apply. Fields are never eval'd,
never word-split into a command line by expansion; the probe builds its argv
explicitly and quotes every expansion. The conformance scan rejects any record
without exactly four fields, and rejects a tool name outside the declared set,
so a record cannot introduce a new executable name without a reviewed edit to the
tool list. And the probe only ever appends `--help` and reads stdout: it never
runs a declared subcommand, which is a requirement of the probe strategy for
correctness reasons and happens to close the injection path as well. The threat
model here is a malicious pull request against shirabe itself, which the review
of a four-field tab-separated line is well suited to catch precisely because the
format has no expressive room to hide in.

**The report is generated from declaration content and tool output, and is
inserted into the model's context.** This is the sharpest surface in the design
and it deserves to be named as such. The report becomes body text the model reads
as instructions, and part of it is `--help` output from a binary on the user's
PATH. A hostile or shadowed `koto` on PATH could emit help text shaped like an
instruction and have it land in context. Three things bound this. The check reads
help text from a tool the skill was going to execute anyway, so a hostile binary
on PATH already has a far more direct path to the same outcome; the check does not
widen the trust boundary, it only makes the tool's own text visible earlier. The
report interpolates tool output in exactly two places, the advertised subcommand
list and the advertised flag list, and both are rendered as a comma-separated list
extracted by the position-anchored parser rather than passed through verbatim, so
prose in a description never reaches the report. And the surrounding text is
fixed: the posture sentence, the capability sentence, and the command line are
composed from the declaration and the route table, both of which are committed
files. The design deliberately does not echo raw stderr into the report on the
probe path.

**The enumeration file governs a CI gate.** `references/tool-diagnostic-discards.md`
is an allowlist, and adding a line to it makes a scan stop complaining. That is
the intended mechanism and R21b's whole point is that it costs a reviewed edit.
The design hardens it in two directions. The scan reports stale entries as well
as unenumerated sites, so the list cannot silently accumulate exemptions for code
that no longer exists. And the join key includes the trimmed command text, so
editing what an exempt command does breaks the join and forces the exemption back
through review rather than letting an exemption granted for one command silently
cover a different one. The failure mode this leaves open is a reviewer approving
an entry they did not think about, which is the same failure mode every allowlist
has and which the one-record-per-line format is chosen to make as visible as
possible in a diff.

**The route table emits commands an agent will run.** `scripts/lib/tool-routes.tsv`
produces the single command each unsatisfied block prints, and an agent reading
the report is likely to execute it. The table is a committed file with a stated
ownership rule, routes are probed for availability rather than assumed, and the
report prints exactly one command with no choice for the reader, so there is no
path by which report text becomes an arbitrary command line. The `gh`-on-Linux
exclusion is the first entry and the reason the table exists: emitting a command
known to produce a segfaulting binary is a real harm, and leaving that knowledge
in a TOML comment is what R20 exists to end.

**The check never blocks, so it cannot be used to deny service.** R17 is a
security property as much as a usability one. A check that could refuse a skill
would give anyone who can influence the declaration, the route table, or a tool's
help output a way to disable twenty workflows. The always-exit-0 discipline, in
the script and again in the injected line's outer guard, means the worst outcome
of any failure in this subsystem is a report that does not appear.

**Not applicable.** The check writes no files, holds no state across runs, opens
no network connection, and reads no credentials. It never parses or compares a
version, so there is no version-negotiation surface. Nothing it does is
privileged, and nothing it emits is persisted.

## Consequences

### Positive

`/inflight` loads again, on every host, for the first time since 2026-07-07. The
`koto context remove` call site and both `koto context get` masks are fixed
rather than documented, which closes the two live instances of the `shirabe#279`
shape that are in the tree today.

A reader of any skill can see its host surface in a four-field file rather than
by grepping its phases for command names, and the check reads that same file, so
the two cannot drift. Adding a tool to one skill leaves every other skill's
evaluated set unchanged.

Everything ships in one commit with no seam. The script, the declarations, and
the SKILL.md lines that invoke them are the same artifact, which is what makes
this feature's own drift story different from the one it is fixing.

Both `shirabe validate` consumers become correct against every shirabe version
ever shipped, including the ones already installed, which is what R22's
motivating case requires and what a producer-side fix alone cannot deliver.

The entry point stays a script, so a future `shirabe preflight` can be delegated
to behind the same contract without touching any SKILL.md or any test.

### Negative

`/work-on` pays 18.7 ms and 10 subprocesses at every load. That is the real
recurring cost, it scales with declaration size, and `/work-on`'s declaration is
the one most likely to grow. Nothing caches across skill loads.

Twenty SKILL.md files each gain a frontmatter entry and a body line, and each
pair is a way to kill a skill if the two disagree. Fifteen of the twenty have no
`allowed-tools` today.

Skills that need no shell today will need one. The plugin already ships scripts
several skills invoke, so a POSIX shell is a de facto requirement for those, but
not for the fifteen prose-only skills, and this change makes it one. On Windows
without Git Bash the harness routes injected commands to the PowerShell tool,
where a POSIX command line does not run, and a failed injected command aborts the
invocation. The exposure is narrow: `install.sh` accepts only `linux` and
`darwin`, so the binary most of these skills call cannot be installed on Windows
at all. The honest posture is to document a POSIX shell as a requirement rather
than to claim platform neutrality, and to keep the injected line trivial so a
platform-conditional variant would be one line per skill to change.

A bash 3.2 artifact that will grow, with per-tool remediation data in `case` arms
rather than a typed table and no compile-time check that a declared tool has an
install route. Structural introspection of shirabe's own clap tree is foreclosed:
the check greps rendered help for shirabe exactly as it does for koto, so a
help-rendering change in clap is a silent break in the probe.

A tab-separated format has no parser to reject a malformed file, and an editor
that converts tabs to spaces produces a file that looks right and parses wrong.

The `--help` layout becomes a contract. If a future clap changes the `Commands:`
or `Options:` block shape, the extractor under-reports, which fails open into
false findings rather than false silence.

Some reports end by telling the reader the tool might be fine and the skill might
be wrong. That reads as weaker than a confident upgrade instruction, and it is
correct: `koto context remove` has never existed at any version, so the confident
version would send a reader to reinstall a binary that was never going to help.
A reviewer will push back on this wording. It should be held.

### Mitigations and named risks

**The permission pattern is the risk that can delete twenty skills.** It is
masked locally by `"defaultMode": "auto"`, so it must be validated on a non-auto
host before rollout, which is why Phase 2 is a gate rather than a task.
`scripts/check-skill-injection.sh` holds the invariant afterward.

**Tab preservation** is enforced by the conformance scan, which rejects any
record line without exactly three tabs. That is the only mechanism available and
it is enough, because the failure is loud rather than silent.

**The clap layout contract** is guarded by a probe regression test asserting a
known-present and a known-absent flag against fixtures captured from real help
output, in both of clap's layouts.

**Install-route sprawl** has a stated threshold. R14, R15, R19, and R20 all push
the check toward accumulating per-host route knowledge, which is exactly the kind
of branching data that gets unpleasant in bash 3.2. If route resolution outgrows
the `case` block, move *route resolution alone* into the binary as an optional
enhancement the script uses when present and falls back from when absent. The
check itself never sits behind the binary.

**A declaration is unverifiable for completeness.** Nothing mechanically proves
one complete, and a call the declaration omits is unchecked. The flag-extraction
scan is the closest available guard, and it reaches only the two first-party
tools whose declarations name flags at all. A default-flip behind a stable flag
name remains undetectable at any probe depth; R22a avoids it at compliant call
sites and nothing will say so at a non-compliant one.
