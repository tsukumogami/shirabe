---
schema: design/v1
status: Current
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
  per tool/subcommand/mode triple, read by a plugin-shipped bash script at
  `scripts/skill-preflight.sh` invoked as `bash <path>`. Each SKILL.md gains one
  injected command that runs the script at load and one matching `allowed-tools`
  entry. The script resolves each declared tool with `command -v`, falls back to
  an overridable root list to tell "absent" from "off PATH", probes surface by
  enumerating one `--help` per subcommand level with memoization and a
  position-anchored extractor, prints plain prose for each unsatisfied entry,
  prints nothing at all when everything is satisfied, and always exits 0.
  Install routes and the `gh`-on-Linux exclusion move into a line-oriented data
  file the script reads only after a tool is found absent.
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

Current

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

**A. A shell script shipped in the plugin.** Chosen. One entry point at
`scripts/skill-preflight.sh`, alongside the existing `scripts/check-*.sh` family,
with helpers under `scripts/lib/` following `scripts/lib/koto-gates.sh`. Which
shell it runs under is its own question, settled below.
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

### Which shell the entry point runs under

An earlier draft of this design specified `sh` and called the script POSIX. That
was wrong, and it was wrong in the way that costs the most: it made the shell the
script runs under in production different from the shell every test and every
precedent in this repo uses, without anyone choosing that.

**A. `sh`, as a strict POSIX script.** Rejected. On ubuntu-latest `/bin/sh` is
dash. Every precedent this design inherits from is bash --
`scripts/lib/koto-gates.sh` is `#!/usr/bin/env bash`, the existing
`skills/execute/scripts/preflight.sh` is `#!/usr/bin/env bash` with
`set -euo pipefail` and `${BASH_SOURCE[0]}`, and `check-plan-scripts.yml` runs
`bash` on ubuntu and `/bin/bash` explicitly on macOS. Choosing `sh` would mean
the CI matrix validates the script under bash 5 and bash 3.2 and never under the
shell that actually runs it on Linux. This design's own bash-3.2 rationale, taken
from `check-plan-scripts.yml`, is that a pattern list only catches what its author
remembered and only running the suite on the floor catches the rest; that argument
applies with equal force to dash, and the honest options were to add a dash leg or
to stop pretending. Three constructs decide it in practice, and all three are
bash-only: `${BASH_SOURCE[0]}` for self-resolution, `IFS=$'\t'` for the
tab-delimited read, and `local` in the helpers.

**B. `bash`, with bash 3.2 as the floor.** Chosen. The injected line is
`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh`, which is the house idiom
verbatim: `skills/execute/SKILL.md:129` already reads
`bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh`. This adds no new
host dependency. bash 3.2 ships with macOS and bash is universal on the Linux
distributions `install.sh` supports, the plugin already asks an agent to run a
bash script by absolute path, and the two CI legs the design was already going to
clone from `check-plan-scripts.yml` -- bash 5 on ubuntu, `/bin/bash` 3.2 on macOS
-- now test the same interpreter production uses. The floor is bash 3.2, stated
as such: no `declare -A`, no namerefs, no `mapfile`, no `${var^^}` or `${var,,}`,
no `+=` on arrays. `shirabe#270` is on file as bash 4 syntax meeting exactly that
shell, which is why the floor is tested rather than asserted.

The one thing `sh` would have bought is a script that runs where bash does not,
and the design does not need that: the Windows exposure is already documented as
out of scope because `install.sh` accepts only `linux` and `darwin`.

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
never evaluated is a sidecar in a format a shell can read, which dissolves the
constraint rather than accepting it. And the binary-as-reader conclusion
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

**E. A restricted YAML subset the shell can read.** Rejected, and it is the
option this design owes the most careful answer to, because it is exactly the
option the design accuses B of never evaluating. A flat block form -- `tool: koto`
/ `subcommand: context add` / `flags: -` / `when: always`, one key per line, no
nesting, no anchors, no flow collections, no multi-line scalars -- is readable by
a shell with `sed` or a `case` on the key prefix, and it recovers two of the three
costs booked against D: comments with structure, and an encoding a maintainer
recognizes on sight. It would also let a future binary-side reader parse the same
file with `saphyr` rather than a second hand-written splitter.

It loses on the property that decides the format, which is what a malformed file
does. The restriction is the whole value and nothing enforces it: the file is
valid YAML either way, so an author who writes a nested key, a quoted scalar with
an escape, or a flow list gets a file that a real YAML parser accepts and the
shell reader silently misreads. That is a divergence between two readers of the
same bytes, and it is precisely the class of failure D's four-field, exactly-three-tabs
rule makes impossible -- a record either has three tabs or it is rejected, with no
third state where two readers disagree. The block form also costs four lines per
record where D costs one, which makes a fifteen-record declaration like
`/work-on`'s sixty lines and makes the diff of adding one requirement four
hunks rather than one. And it would give the repo two line-oriented data
conventions instead of one, since the discard enumeration reached tab separation
independently on its own evidence.

The cost of D over B and E is real and should be stated: no schema validation from
a parser, no comments-with-structure, and a format a maintainer has to learn from
its header rather than recognize. A CI conformance scan replaces the parser, the
script enforces the same rules again at read time, and the schema is four fields.

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
policy.

It is *not* the home for R11. An earlier draft called it "the natural home for the
mode-scoped enforcement in R11" and then implemented R11 in Phase 6 through the
agent-instructed shape rejected here for load-time use, without saying why. The
reason is that mode selection is not a `Skill` tool call. It happens inside an
already-loaded skill, at a phase the skill's own body defines, long after the
`PreToolUse` hook on `Skill` has fired and with no tool event to hang a hook on.
The hook's unresolved skill-identity question therefore does not need answering
for R11's sake; Phase 6 supersedes the hook as R11's home, and the question only
matters if the injection path is closed and option B has to be revisited for
load-time use.

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
plugin-shipped bash script against that sidecar at load. The script
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
| Entry point | `scripts/skill-preflight.sh` | Reads one skill's sidecar, resolves, probes, reports. Always exits 0. `#!/usr/bin/env bash`, invoked as `bash <path>`. |
| Reader helper | `scripts/lib/preflight-read.sh` | Parses and validates `requires.tsv` records. |
| Resolver helper | `scripts/lib/preflight-resolve.sh` | `command -v`, the R28 root list, R18's ordering. |
| Probe helper | `scripts/lib/preflight-probe.sh` | Level enumeration, memoization, the position-anchored extractor. |
| Reporter helper | `scripts/lib/preflight-report.sh` | Block rendering, route resolution, the emitted-token filter. |
| Route table | `scripts/lib/tool-routes.tsv` | Install routes per tool and the R20 exclusions. Read only after a tool is found absent. Six tab-separated fields; schema below. |
| Declaration policy | `references/tool-declaration-policy.md` | R4's committed policy: the first-party/independent-cadence split, its rationale, and the rule for moving a tool between the two lists. Cited by name from `requires.tsv` headers and from the conformance scan's failure text. |
| Discard enumeration | `references/tool-diagnostic-discards.md` | Policy prose plus a fenced tab-separated record block. Read by CI only. |
| Discard scan | `scripts/check-tool-diagnostic-discards.sh` | Joins live sites against the enumeration in both directions. |
| Injection scan | `scripts/check-skill-injection.sh` | Asserts every injected command is covered by an `allowed-tools` entry in the same file and carries an outer exit-0 guard. |
| Conformance scan | `scripts/check-skill-requires.sh` | Twenty sidecars exist; every record has exactly four fields; every field matches its character allowlist; every tool name appears in `tool-routes.tsv`; declared flags match flags extracted from the skill's own command lines; declared mode names match the mode strings in the skill's own phases. |

Two data conventions, split by who reads them. Anything on the load path is a
bare `.tsv` under `scripts/lib/` or `skills/<name>/`, because parsing a fenced
block out of markdown at every skill load is work for nothing. Anything on the
review path is markdown policy prose with a fenced record block, because a human
has to read the rule before they read the records.

### The declaration policy (R4)

R4 asks that the first-party/independent-cadence split be recorded as a stated
policy with its rationale rather than left to emerge from how an author reads
"the subcommands the skill calls", and the PRD pins the deliverable: the policy
"appears in a committed reference under `references/`, cited by name from the
requirement it governs." That artifact is `references/tool-declaration-policy.md`,
following `references/wip-hygiene.md` and `references/worktree-discipline.md` --
normative prose no skill loads, reviewed as part of a PR.

It states four things. The rule: a tool whose release cadence is coupled to
shirabe's own gets subcommand-and-flag records; a tool with an independent cadence
gets a tool-only record with `-` in fields two and three. The current membership:
`shirabe` and `koto` are first-party, `gh`, `jq`, `git`, and `python3` are
independent-cadence. The rationale: `gh` has roughly ninety call sites across the
corpus, and declaring its subcommands would verify a surface shirabe neither
controls nor tracks, so a stale entry would be indistinguishable from a real
finding; the cost side is measured, `gh --help` at 20 ms against `koto --help` at
2.5 to 3 ms, so a subcommand declaration for `gh` is also the most expensive one
available. And the change rule: moving a tool between the lists is an edit to this
file, in the same PR as the declaration changes it forces, and the conformance
scan names this file in its failure text so an author who trips it is sent to the
rule rather than left to infer it.

The file is the reason `/work-on`'s declaration can name `gh` with `-` in field
two while naming ten `koto` subcommands, and a reader who wonders why has one
place to look.

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

Because a mode-scoped record is distinguished from an always-required one by
field four alone, a reader can tell them apart by looking at the file, which is
what the PRD's criterion "a declaration distinguishes an always-required entry
from a mode-scoped one by inspection, without running the check" asks for. That
matters for how R10 is discharged, and the point is taken up in *Mode-scoped
verification* below.

#### The rest of the schema

The four fields above are the interesting part; the following rules are the ones
an implementer would otherwise have to invent, and each has a reason.

*Line kinds.* Exactly three. A line whose first character is `#` is a comment and
is skipped, which is what makes the `#schema` line legal under the same rule that
rejects a four-field-less record -- an earlier draft's "reject any line without
exactly four fields" would have made every comment a hard error. A line that is
empty or contains only whitespace is skipped. Every other line is a record and
must carry exactly three tabs.

*The schema line.* Required, and it must be the first line. The reader compares
the version token literally against `skill-requires/v1`. Any other value, or a
missing schema line, is a hard error reported with the skill name -- not a
best-effort parse. A version bump is therefore a deliberate, visible act, and a
file written for a future schema fails loudly on an old reader instead of being
half-understood.

*Whitespace.* Leading and trailing whitespace on a record line is stripped before
the tab count is taken, so an editor that adds a trailing newline-adjacent space
does not break the file. Whitespace *inside* a field is significant only in field
two, where it separates subcommand path elements; runs of spaces there collapse to
one. No other field may contain a space, and the allowlist below enforces it.

*Commas in flags.* Field three uses comma as its intra-field separator, and this
design rejected comma as the *record* delimiter partly because "comma appears
inside flag lists". Those two facts do not conflict, but only because of a rule
that has to be stated: there is no escaping mechanism, and a flag whose own name
contains a comma cannot be declared. The character allowlist below makes that a
rejected record rather than a silent mis-split. Nothing in either binary's help
output today has a comma in a flag name; if one ever appears, the schema goes to
v2 rather than growing an escape.

*Field order.* Not significant. The reader evaluates records in file order only
so that its output is stable, and the report re-sorts blocks by posture anyway.

*Character allowlists, enforced at read time.* Each field is validated by the
script before any part of it is used, and the conformance scan enforces the same
rules in CI. The script is the load-bearing copy -- CI runs after the fact, and a
reviewer with the plugin root pointed at a PR checkout loads skills before CI has
run at all.

| Field | Allowed | Notes |
|---|---|---|
| 1, tool | `[A-Za-z0-9._-]+`, first character not `-` | Must also appear as a tool in `tool-routes.tsv`. |
| 2, subcommand | `-`, or space-separated tokens each `[A-Za-z0-9._-]+` with a first character that is not `-` | Each token becomes one argv element. |
| 3, flags | `-`, or comma-separated tokens each matching `--?[A-Za-z0-9][A-Za-z0-9-]*` | Never passed to a tool; compared against extracted text only. |
| 4, when | `always` or `mode:[a-z0-9-]+` | Mode names are an interface; the scan cross-checks them against the skill's phases. |

A record that fails any of these is skipped and reported: the skill name, the
line number, the field, and what was expected. It is deliberately not dropped
silently, because a silent drop would put a record into the same zero-byte
outcome as a satisfied one -- the blind spot the Security Considerations section
takes up at length.

The leading-`-` rejection in fields one and two is the one rule that is there for
a security reason rather than a parsing reason. Field two is split into argv
elements and appended before `--help`, so a subcommand field of `--version` or
`-x` would otherwise reach the probed tool as a flag. This is the same discipline
`skills/scope/SKILL.md` states for its own command construction and the same
reason `work_summary.rs` anchors its owner/repo pattern on an alphanumeric.

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

Step 1 has a precondition the design has to state, because the same threat model
that forbids a `$PWD`-relative plugin root applies to the binaries this script
executes. `command -v` honours whatever PATH the session carries, including a `.`
entry or a relative one, and the working directory at skill load may be a
repository whose contents arrived from a pull request. So: the path `command -v`
returns must be absolute and must not lie under the current working directory. If
either test fails, the tool is treated as **resolution refused** -- the script
never executes it, and the report says the tool resolved to a path inside the
working directory and was not probed. That is a finding a reader can act on, and
it is strictly better than the alternative, which is running a binary out of the
branch under review at skill load.

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
description on the next line, as `shirabe roadmap populate` renders). The
`Commands:` block is read by the same rule at the same depths -- a subcommand
name is the first whitespace-delimited token on a line carrying 2 to 6 leading
spaces inside the `Commands:` section, and a line carrying 8 or more is a wrapped
description and contributes nothing. R7 depends on that extractor as much as R8
depends on the `Options:` one, so it gets the same stated rule rather than a
grep.

#### How a probe is executed

Every `--help` invocation is bounded, because R17's never-block promise is an
availability claim and an exit-code argument does not establish one. A binary
that hangs, that reads stdin, or that writes without stopping blocks skill load
just as completely as one that refuses, and the injected line's `|| true` cannot
rescue a process that has not exited.

Each probe runs with stdin closed (`</dev/null`), with stdout and stderr captured
separately, with a 2-second wall-clock budget, and with output truncated at 64 KiB.
The timeout is implemented without `timeout(1)`, which macOS does not ship: the
probe is started in the background, a watchdog subshell sleeps the budget and
sends `TERM` then `KILL`, and the parent waits. A probe that hits the timeout or
the byte cap is **inconclusive**, not a finding: the report names the tool, says
the probe did not complete, and makes no claim about the surface. Treating it as
a finding would let a slow binary fabricate a missing subcommand.

#### How the TSV is read

`IFS=$'\t' read -r tool sub flags when` per record, with the `IFS` assignment
scoped to the `read` builtin so it never leaks. Setting `IFS` to a literal tab is
what keeps field two intact: with the default `IFS`, `roadmap populate` splits
into two fields and every multi-word subcommand record fails the four-field check.
`$'\t'` is an ANSI-C quote, available in bash 3.2 and one of the three constructs
that settled the interpreter question above.

`SHIRABE_PREFLIGHT_ROOTS` is colon-separated and is split once, before any record
is read, with `IFS=: read -r -a PREFLIGHT_ROOTS <<<"$SHIRABE_PREFLIGHT_ROOTS"`.
Again the `IFS` is scoped to the `read`, so the two splits cannot interfere -- the
alternative, assigning `IFS` globally and restoring it, is the version that breaks
the day someone adds an early return.

#### How levels are memoized

The cost argument depends on memoization, so the mechanism is specified rather
than left to instinct -- and the instinct here is `declare -A`, which bash 3.2
does not have. No associative array, and no temp files either, because the check
writes nothing to disk.

Two ordinary string variables, each holding newline-delimited records:

- `PROBE_KEYS` -- one visited level key per line, where the key is the tool name
  and the subcommand path joined by spaces (`koto`, `koto context`).
- `PROBE_DATA` -- one `key<TAB>tokens` line per visited level, where `tokens` is
  the space-joined extracted subcommand and flag list for that level.

Membership is a `case` glob against the key bracketed by newlines, which is an
exact-line test rather than a substring one. Retrieval is a
`while IFS=$'\t' read -r k v` loop over `PROBE_DATA`. Both are bash 3.2
constructs, both are `set -u`-safe, and neither allocates.

The `case` pattern is built from a key, and a key built from untrusted text would
be a glob-injection hazard. It is not: keys are composed only of field one and
field two, both of which passed the `[A-Za-z0-9._-]` allowlist at read time, so no
glob metacharacter can enter the pattern. That is the second place the allowlist
earns its keep.

Ten distinct levels for `/work-on` become nine `--help` calls, and the difference
is the point of memoizing: `koto context add`, `koto context get`, and
`koto context exists` all resolve against one `koto context --help`.

#### Measured cost

Mean of 10 to 20 runs on this host: shirabe and koto `--help` at 2.5 to 3 ms each,
`gh --help` at 20 ms, `git --help` at 9.9 ms.

`/work-on` costs 5 `command -v` calls -- one per declared tool, for `koto`,
`shirabe`, `gh`, `git`, and `jq` -- and 9 `--help` calls, over these levels:
`koto`, `koto init`, `koto next`, `koto context`, `koto decisions`,
`koto decisions record`, `koto overrides`, `shirabe`, and `shirabe validate`.
`koto context add` is not among them: the rule is one `--help` per subcommand
level visited plus one per leaf carrying a declared flag, and `context add`
declares no flags, so `koto context --help` is the last call on that path.

The 18.7 ms figure quoted throughout was measured against a prototype that
visited ten levels, including the `koto context add` leaf the stated rule does not
need. It is therefore a conservative upper bound on the rule as specified, and it
is the number the Negative consequences section budgets against. `/scope` costs
3 calls and 5.9 ms. The satisfied path was measured end to end at 0 bytes
combined, asserted with `wc -c` per R12's acceptance criterion rather than by
inspection.

`gh` at 20 ms per call is the strongest cost argument for declaring it tool-only,
which R3 and R4 already reach on independent grounds.

### The report

Plain prose on stdout, one block per unsatisfied record, off-PATH blocks first.
No color, no box drawing, no glyphs, no re-run affordance.

#### What R14's "what the skill will be unable to do" resolves to

R14 asks that an unsatisfied outcome name which R13 posture holds, what the skill
will be unable to do, and exactly one command that works on this host. An earlier
draft rendered the middle clause as a per-record sentence in the skill's own
vocabulary -- "phases 0 through 5 will run; phase 6 cannot complete" -- which the
four-field schema cannot produce. There is no capability field, no call-site
field, and no affected-phase field, so those sentences were prose no data source
could generate.

Two ways out, and the design takes the second.

**Add a fifth free-text field.** Rejected. A per-record sentence describing what
the skill loses is unverifiable prose sitting inside a file whose entire value is
that everything in it is mechanically checkable. Nothing can test that "phase 6
cannot complete" is still true after a phase renumber, a phase split, or a
refactor that moves the `gh` call. It would rot in exactly the way the prose this
feature retires has rotted --
`references/fixes/cli-version-preflight.md` is prose no skill cites and
`skills/work-on/SKILL.md`'s `koto >= 0.3.3` floor is a stale number nobody
updated -- and it would rot while colocated with data that stays true, which is
worse than rotting alone, because a reader would have no way to tell which half of
a record to trust. It also costs the schema its best property: "exactly three
tabs" is a rule a scan, a diff reader, and a human can each apply in one pass.

**Narrow the report to what the declaration knows.** Chosen. The report names the
skill, the posture, the tool, the subcommand path and flag where the record
carries them, and the remedy. It does not name phases, call sites, or
capabilities, because the declaration does not carry them.

R14 is still met, and it is worth being precise about how. "Which outcome from
R13 holds" is the posture sentence, unchanged. "Exactly one command that will
work on the host it is running on" is the route line, unchanged. "What the skill
will be unable to do" is discharged at *declaration granularity*: the report
states that this skill declares this exact call and that the call will fail as
written. That is a true statement about what the skill cannot do, derived
entirely from committed data, and it is actionable -- a reader who wants the
call sites has the tool and the subcommand to grep for.

What is lost is real and should be recorded rather than glossed: the reader no
longer learns which phases survive. Someone who wants that back should ask for a
mechanically derived call-site index rather than a hand-written field, and this
design does not build one.

#### The four unsatisfied cases

R13 requires four distinguishable unsatisfied outcomes and forbids collapsing
either split. All four are rendered here, verbatim as a reader sees them, because
a shape stated in prose and never shown is a shape an implementer invents.

*Resolves-but-incomplete, missing subcommand:*

```
shirabe /work-on: prerequisite not met.

koto resolves at /Users/you/.tsuku/tools/current/koto and runs, but it
does not have the subcommand `koto context remove`. `koto context`
advertises: add, get, exists, list. The tool is installed and working;
only this part of its surface is absent.

/work-on declares `koto context remove`. That call will fail as written,
exiting 2 with an unrecognized-subcommand error.

Update to the newest koto:

  tsuku install koto@latest && . ~/.tsuku/env

This check reads the installed binary's advertised surface and nothing
else. It cannot tell you whether any released koto has `context
remove`. If the newest build still does not, the call site is wrong and
needs changing -- the binary is not the problem.
```

*Resolves-but-incomplete, missing flag on a present subcommand:*

```
shirabe /roadmap: prerequisite not met.

shirabe resolves at /Users/you/.tsuku/tools/current/shirabe and has the
subcommand `shirabe roadmap populate`, but that subcommand does not
advertise the flag --no-issues. `shirabe roadmap populate` advertises:
--issues, --milestone, --milestone-description, --help. The tool is
installed and the subcommand exists; only this flag is absent.

/roadmap declares `shirabe roadmap populate --no-issues`. That call
will fail as written.

Update to the newest shirabe:

  tsuku install shirabe@latest && . ~/.tsuku/env

This check reads the installed binary's advertised surface and nothing
else. It cannot tell you whether any released shirabe has --no-issues.
If the newest build still does not, the call site is wrong and needs
changing -- the binary is not the problem.
```

*Unresolvable, installed but off PATH:*

```
shirabe /work-on: prerequisite not met, and nothing needs installing.

koto is installed at /Users/you/.tsuku/tools/current/koto but is not on
this shell's PATH. Checked PATH first, then ~/.tsuku/tools/current,
~/.shirabe/bin, and ~/.local/bin.

/work-on declares koto. Every call to it will fail as written until
PATH includes the directory above.

Put it on PATH:

  . ~/.tsuku/env

Do not reinstall koto. It is already here.
```

*Unresolvable, absent from the host:*

```
shirabe /work-on: prerequisite not met.

gh is not installed on this host. Checked PATH, then
~/.tsuku/tools/current, ~/.shirabe/bin, and ~/.local/bin.

/work-on declares gh. Every call to it will fail as written.

No install route is available on this host, so this report gives no
command. Every route was checked:

  tsuku     excluded for gh on Linux -- segfaults, tsukumogami/tsuku#2245
  homebrew  brew does not resolve
  apt-get   does not resolve
  cargo     resolves, but publishes no gh package

Install gh by whatever means this host supports.
```

The fifth R13 case, satisfied, emits nothing. So does a `mode:` record at load,
for the reason given under *Mode-scoped verification*.

Two outcomes outside R13's three postures also emit a block, and both say
explicitly that no claim about the surface is being made: **resolution refused**,
where `command -v` returned a relative path or one under the working directory,
and **probe inconclusive**, where a `--help` call hit the 2-second budget or the
64 KiB cap. Neither is reported as a missing subcommand or a missing flag,
because neither establishes one.

#### Shape rules

Seven rules the cases encode.

1. The first line names the skill and states the posture in words.
2. The posture paragraph distinguishes all four unsatisfied cases explicitly. An
   off-PATH block says "installed at ... but is not on this shell's PATH"; an
   absent block says "is not installed on this host"; a subcommand gap says the
   tool "does not have the subcommand"; a flag gap says the subcommand "does not
   advertise the flag". R13 exists because collapsing any of these sends the
   reader after the wrong thing.
3. The impact paragraph names the skill, the declared call, and that the call
   will fail as written. It is composed from the record's own fields and says
   nothing about phases -- see the R14 discussion above.
4. Exactly one command on its own indented line, or an explicit no-route
   statement. Never two commands, never a choice for the reader.
5. Off-PATH blocks say "nothing needs installing" in the first line and sort
   first, so an agent reading top-down cannot reinstall a tool it already has.
   The block ends by saying so again, because the failure this prevents is an
   agent that read only the remedy.
6. Surface-gap blocks list what the level does advertise. It costs nothing --
   the probe already parsed the list -- and it is what turns "wrong subcommand"
   into a fixable observation.
7. Nothing points at a second run (R16).

#### The filter on tool-derived text

Three things in the blocks above come from a binary on the user's PATH rather
than from a committed file: the advertised subcommand list, the advertised flag
list, and the `command -v` resolved path. Everything else -- the posture
sentences, the impact sentence, the route lines, the closing bound -- is fixed
text or comes from `requires.tsv` and `tool-routes.tsv`, both committed and both
allowlisted at read time.

Those three are filtered, normatively, before they reach the report. The rules
below are requirements on the implementation, not descriptions of it.

*Extracted tokens* -- one subcommand name or one flag -- are processed in this
order. ANSI CSI sequences and all C0, C1, and DEL code points are stripped from
the source line first, so an escape sequence cannot survive by hiding inside an
otherwise-conforming token. The remaining token must match `[A-Za-z0-9._-]+` for
a subcommand or `--?[A-Za-z0-9][A-Za-z0-9-]*` for a flag, and must be 64 bytes or
shorter. A token that does not match is **dropped, not sanitized**, following the
reject-don't-sanitize rule `extract_pr_url` already applies in this repo: a
sanitized token would be a claim about a surface that does not exist. Each list
is capped at 24 items, with the overflow rendered as a literal `and N more`.

*The resolved path* must be absolute (already required by the resolution rule
above) and must match `[A-Za-z0-9._/-]+` within 4096 bytes. A path that does not
is not rendered; the block says the tool resolved to a path this report will not
render, and continues.

*The interpolated region is labelled.* Advertised lists appear only after the
fixed phrase "advertises:" and only on their own line, so a reader and a model
both see where committed text stops and binary output starts.

The design deliberately does not wrap that region in the 128-bit-nonce fence
`work_summary.rs:1073` uses for PR titles, and owes a reason, because the
placement here is worse than the one that fence protects: this text lands in the
SKILL.md body ahead of the instructions it qualifies, which is the highest-trust
position in the context, while a hook echo lands as a tool result the model reads
as data. The reason is that the fence exists to stop free-form text from forging
its own terminator, and the alphabet here is closed. After the filter, a token
cannot contain a space, a newline, a quote, a backtick, a colon, or any character
outside `[A-Za-z0-9._-]` plus a leading dash. It cannot form a sentence, an
imperative, a code fence, or a line break. There is nothing for a nonce to
protect against that the alphabet has not already excluded, and a nonce fence in
text a human reads on their terminal is a real cost. If the filter ever loosens --
if a future report wants to echo a description, a stderr line, or an error message
-- the fence becomes mandatory, and that is the tripwire: **any tool-derived text
the allowlist does not fully constrain must be nonce-fenced before it is
rendered.**

The check also does not echo raw stderr into the report on the probe path. That
is an invariant, not a preference.

None of these filters costs the satisfied path a byte. They run only where the
report is already emitting output.

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
succeeds for `koto`, `shirabe`, and `gh`.

### The route table

`scripts/lib/tool-routes.tsv` is the smallest component and the one with the
largest blast radius: it produces the single command every unsatisfied block
prints, it carries the R20 exclusion moved out of the `.tsuku.toml` comment, and
it is the closed set of tool names the reader validates field one against. It gets
a real schema rather than a sentence.

```
#schema	tool-routes/v1
<tool>	<route>	<os>	<probe>	<command>	<citation>
```

Six tab-separated fields, one route per record, several records per tool, in
preference order -- the reader takes the first record for a tool whose OS matches
and whose probe succeeds, which is what makes "exactly one command" (R14) fall out
of the data rather than out of reporter logic. The same line kinds as
`requires.tsv`: `#` opens a comment, blank lines are skipped, the schema line is
required and its version is compared literally.

| Field | Meaning |
|---|---|
| 1, tool | Tool name. `[A-Za-z0-9._-]+`. The union of this column is the closed tool set field one of every `requires.tsv` is checked against. |
| 2, route | Route identifier, printed in the no-route enumeration: `tsuku`, `homebrew`, `apt-get`, `cargo`. `[a-z0-9-]+`. |
| 3, os | `any`, `darwin`, or `linux`, matched against `uname -s`. This is how an exclusion binds to an OS. |
| 4, probe | The availability test, as a `<driver>` or `<driver> <verb>` pair. `-` means the route is unconditional. A record whose route is excluded carries `never`. |
| 5, command | The command emitted verbatim if this record wins. `-` when the route is excluded. |
| 6, citation | An issue reference (`tsukumogami/tsuku#2245`) or `-`. Mandatory and non-`-` on any record whose probe is `never`. |

The probe field is what the earlier one-sentence description left unspecified, and
it is the field the four routes differ in. It names a driver to resolve with
`command -v` and, optionally, a package-knowledge verb the reader runs against the
tool name. `tsuku tsuku-info` means "`tsuku` resolves *and* `tsuku info <tool>`
succeeds"; `brew -` means "`brew` resolves", which is all the design can establish
for homebrew without a network call it will not make. The verb vocabulary is
closed and lives in the reader, so the table cannot introduce a new command shape:
adding a driver is a code change, not a data change. That is the property that
lets the Security section call this file an emitted-command source with a bounded
grammar.

The seed, with `gh` showing all four route kinds:

```
#schema	tool-routes/v1
koto	tsuku	any	tsuku tsuku-info	tsuku install koto@latest && . ~/.tsuku/env	-
shirabe	tsuku	any	tsuku tsuku-info	tsuku install shirabe@latest && . ~/.tsuku/env	-
gh	tsuku	linux	never	-	tsukumogami/tsuku#2245
gh	tsuku	darwin	tsuku tsuku-info	tsuku install gh@latest && . ~/.tsuku/env	-
gh	homebrew	darwin	brew -	brew install gh	-
gh	apt-get	linux	apt-get -	sudo apt-get install -y gh	-
```

The `never` probe is the R20 exclusion, and it is a record rather than an absence
on purpose: a route that is deliberately excluded has to be visible in the
no-route enumeration the report prints, with its reason, or the reader concludes
the maintainers forgot about it. The header states the ownership rule -- a route
is added or excluded together with the incident that justifies it, cited by issue
number in field six, and field six is mandatory on an exclusion so the rule is
enforced by the schema rather than by memory. Without a stated owner this becomes
the next thing that drifts, which is the same failure the decision record
catalogues for version floors.

### The SKILL.md contract

Frontmatter, added to the existing `allowed-tools` where a skill has one:

```
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh *), Bash(true)
```

Body, at column 0, once per skill, near the top:

```
!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> 2>&1 || true`
```

Every element is load-bearing. `bash <path>` rather than the path directly,
because invoking through an interpreter ignores the executable bit and the design
must not depend on `chmod +x` surviving packaging, cloning, or a marketplace
fetch. It is also the house idiom verbatim: `skills/execute/SKILL.md:129` reads
`bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh`, and an earlier
draft cited that line while writing `sh`, which was the visible symptom of the
unmade interpreter decision settled above. The
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
`bash` exit 127, and without the guard that kills every skill at once. Dropping the
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
criteria name that success line directly.

The rename inventory, stated exactly, because an over-count is still a wrong
count:

- `skills/execute/SKILL.md` at lines 129, 276, 681, and 706.
- Four references in `skills/execute/evals/evals.json`.
- The sibling `skills/execute/scripts/preflight_test.sh`, which is renamed to
  `assert-child-template_test.sh` and carries three internal references of its
  own at lines 18, 67, and 68, including a `cp` into a fake plugin root.
- `.github/workflows/check-execute-scripts.yml` at line 29, which reads
  `bash skills/execute/scripts/preflight_test.sh`. Note what this is: the
  workflow references the *test* file, not `preflight.sh`, so it is touched only
  because the test is being renamed alongside. The workflow's `paths:` filter is
  `skills/execute/scripts/**` and survives the rename untouched.

R25 forces that SKILL.md open anyway, so the reconciliation is cheap now and
expensive later.

R25 itself resolves by removal rather than by implementation. The claim that the
preflight will "confirm `gh` auth is live" comes out of `skills/execute/SKILL.md`,
and no auth check is added. Auth liveness is a credential state, not a CLI
surface, and it can expire between load and the phase that needs it. `gh auth
status` is also a network round trip on a path whose measured budget is 18.7 ms
of local process spawns. `/execute`'s declaration covers `gh` presence; auth is
outside the check's remit and the claim was never true.

### Mode-scoped verification

R10 and R11 split load-time from mode-selection-time. The injected line evaluates
only `always` records, because the mode has not been chosen when the skill loads.

#### Where the deferral is visible

R10 and R12 appear to collide, and the collision has to be resolved in writing
rather than left for an implementer to trip over. R12 requires zero bytes on a
fully satisfied declaration. The PRD's acceptance criteria also carry "a
mode-scoped entry is visibly marked as deferred at load, so a reader can tell 'not
required here' from 'not checked yet'". A satisfied `/roadmap` load, whose
declaration carries two `mode:issues` records, cannot both emit a deferral marker
and emit nothing.

**The deferral is visible in the declaration, not in the load-time report.** The
load-time report says nothing about `mode:` records at all -- not that they are
deferred, not that they are satisfied, not that they are unsatisfied -- because
the check has not evaluated them and any byte it emits about them implies it has.
R10's own requirement text says exactly this: mode-scoped requirements "SHALL NOT
be reported as satisfied or unsatisfied at load". Silence is the only output that
is honest about a check that did not run.

The visibility obligation is discharged by the file. Field four is `always` or
`mode:<name>`, so a reader looking at `skills/roadmap/requires.tsv` can tell which
records hold on every run and which hold only on a named mode, and can tell that
the mode-scoped ones are checked somewhere else. That is precisely the PRD
criterion "a declaration distinguishes an always-required entry from a mode-scoped
one by inspection, without running the check" -- and "without running the check"
is the clause that settles which artifact carries the marker. The two criteria are
one obligation seen from two sides, not two obligations.

R10's own wording -- "visibly marked deferred" -- invites the other reading, and
this design does not pretend otherwise. **The PRD should be read with this design's
gloss: the marker lives in the declaration.** If a future revision wants a
load-time deferral line, it has to reopen R12 first, and it should know what that
costs: the argument for zero bytes is dedup, and while a constant deferral marker
would survive dedup (it is byte-identical across reloads), a marker that varied
with the record set would not, and the rule that says "emit nothing" is the only
one that cannot be got wrong by accident.

#### The mode entry point

At the step that selects a mode, the phase runs the same entry point with a mode
argument, under the same guard as the load-time line:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh <skill-name> --mode <name> 2>&1 || true
```

The guard is not optional here and an earlier draft omitting it was an oversight.
Every argument for it at load time applies with more force at mode-selection
time: a missing script or an unexpanded `${CLAUDE_PLUGIN_ROOT}` still gives 127,
and an unguarded non-zero exit still aborts the invocation -- except that aborting
mid-workflow, after phases have already run and written state, is worse than
aborting at load.

Its output contract, which the design owes and had not stated:

- It evaluates the `mode:<name>` records matching the named mode, and only those.
  The `always` records were evaluated at load and are not re-reported; repeating
  them would put a second copy of an already-seen block in front of the model.
- Zero bytes when every matching record is satisfied, for the same dedup reason
  and the same `wc -c` test.
- The same block shapes, the same filter, and the same four unsatisfied cases as
  the load-time report.
- Always exit 0.

This is the agent-instructed shape rejected for load-time use, and it is
acceptable here for the reason it was rejected there: mode selection is itself an
agent decision at a known step, so there is no earlier deterministic hook to
prefer -- the `PreToolUse` hook on `Skill` has long since fired, and there is no
tool event at a phase boundary to attach to. Mode names are an interface. The
strings in `requires.tsv` must match the strings the SKILL.md phases use, and the
conformance scan checks that.

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

Records are tab-separated inside the fenced block, six fields:

```
<path>	<trimmed command>	<count>	<exit-status>	<justification>	<citation>
```

The join key is `path` plus the trimmed source line, never `path:lineno`. Line
numbers drift whenever anything above a site is edited, which would make every
unrelated change break the build. Keying on the trimmed line tolerates
reindentation but breaks on an edit to the command itself, which is correct:
changing what the command does should force the exemption back through review.
The count field catches a third byte-identical copy. The exit-status field names
the status the fallback is entered on, which is the fact a reader needs to judge
whether the discard is safe.

Fields five and six are the adjudication half, and they exist because the design
demanded an ownership rule of `tool-routes.tsv` and demanded nothing of the file
that actually gates CI. Field five is one sentence saying why this site may
discard its diagnostic. Field six is an issue or incident reference, mandatory
and never `-`; a discard with no incident behind it is an unexamined discard, and
the point of R21b is that adding one is a decision somebody made on purpose.

Free text in field five is not a contradiction of the argument that killed the
fifth `requires.tsv` field. The difference is who reads it and when. This file is
on the review path -- CI joins on fields one through three and a human reads five
and six -- and it is never read at load, never rendered into model context, and
never a source of truth for behaviour. Its whole job is to make a human judgement
reviewable, which is what free text is for. A `requires.tsv` field would have been
free text sitting inside data a script executes against, which is what free text
is not for.

Adjudication is named rather than assumed. `references/tool-diagnostic-discards.md`
gets a `CODEOWNERS` entry, so an addition requires the owning reviewer's approval
rather than whoever happened to be on the PR. And a new entry may land in the same
PR as the code it exempts -- splitting them would mean landing code that fails CI
and fixing it afterward -- but the entry must be its own commit in that PR, so it
is reviewable as a decision rather than buried in a diff about something else.

The scan reports both directions, so an unenumerated site fails and a stale entry
matching nothing also fails, and the list cannot rot into a permanent allowlist.
Tool names come from the declarations rather than a hardcoded list, so the scan's
scope grows with them.

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

- Rename `skills/execute/scripts/preflight.sh` to `assert-child-template.sh` and
  `preflight_test.sh` to `assert-child-template_test.sh`, silence the success
  line, update the call sites listed under *The naming collision, reconciled*,
  and remove the `gh` auth claim from `skills/execute/SKILL.md` (R25).
- Write `scripts/skill-preflight.sh` and the four `scripts/lib/preflight-*.sh`
  helpers, plus `scripts/lib/tool-routes.tsv` seeded with the R20 exclusion moved
  out of the `.tsuku.toml` comment.
- Write `references/tool-declaration-policy.md` (R4), before the declarations,
  because it is the rule the twenty authors follow.
- Write twenty `skills/<name>/requires.tsv` files.
- Write `scripts/check-skill-requires.sh` and a
  `check-preflight-scripts.yml` workflow cloning `check-plan-scripts.yml`
  verbatim, including the explicit `/bin/bash` macOS leg. The bash 3.2 floor is
  the whole reason that leg exists, and a grep-based portability check has
  already missed a nameref that only running the suite on the floor caught. Both
  legs run bash, which is now the interpreter the injected line uses, so the
  matrix tests what production runs.
- Test coverage lands with the script: `wc -c` over a combined capture for R12,
  `PATH=` scrubs for the absent case, `SHIRABE_PREFLIGHT_ROOTS` pointed at an
  `mktemp -d` tree for the off-PATH case, a probe regression test asserting a
  known-present and a known-absent flag against the real binary, since the
  extractor inherits clap's help layout as a contract, a malformed-record test
  asserting the record is skipped *and* reported with its line number, and a
  timeout test using a fixture binary that sleeps past the 2-second budget,
  asserting the report says inconclusive rather than missing.

### Phase 4: rollout and retirement

Add the injected line and the `allowed-tools` entry to all twenty skills.
Nineteen have no `allowed-tools` today: `grep -rn "allowed-tools" skills/`
returns exactly one hit, `skills/inflight/SKILL.md:14`, `Bash(shirabe:*)`. That
matters twice over. Nineteen files gain a frontmatter key rather than fifteen
gaining a list item, so the rollout is larger than the design first claimed. And
the one existing entry uses the `Bash(<tool>:*)` colon form, not the
`Bash(bash <path> *)` prefix form proposed here, so there is no in-repo precedent
for the pattern shape at all -- which is a stronger reason for Phase 2's gate
than "no local evidence either way".

In the same change, remove the prose the declaration supersedes (R24):
`skills/work-on/SKILL.md`'s Prerequisites section including its `koto >= 0.3.3`
floor, and `references/fixes/cli-version-preflight.md`, whose `--help` grep
technique retires into the check rather than being repudiated.

The liveness eval lands here too, because it can only exist once the injection
path does. A fixture skill carrying a deliberately unsatisfiable declaration --
one record naming a tool that does not exist -- is loaded through the real
injected line, and the eval asserts the report is non-empty. It is the only test
in the plan that exercises the injection path rather than the script, and it is
the answer to the failure-open blind spot the Security Considerations section
names. It costs the satisfied path nothing.

### Phase 5: signal integrity

- `references/tool-diagnostic-discards.md` seeded with 23 entries in 22 records,
  each carrying its justification and issue citation, plus the `CODEOWNERS` entry
  naming its adjudicator. Then `scripts/check-tool-diagnostic-discards.sh` with a
  `_test.sh` sibling, and
  `.github/workflows/check-tool-diagnostic-discards.yml` on the
  `check-no-duplicate-rule-list.yml` pattern: ubuntu-latest, one `run:` step,
  path-filtered, no matrix, since the scan is pure text.
- The R22 producer change and both consumer precedence rules, with a sentence in
  `docs/guides/multi-consumer-cli-contract.md` stating envelope-presence
  precedence.
- R22a: pass mode-selecting flags explicitly at the `roadmap populate` call sites
  and any peer with the same shape.

### Phase 6: mode-scoped verification

The `--mode` path at each mode-selecting step (R11), with the guard and the
output contract stated under *Mode-scoped verification*. Last, because it is the
only part with no load-time consumer and because the mode-name interface is
easier to get right once twenty declarations exist to check it against.

This phase is R11's home, not the `PreToolUse` hook. Nothing here is blocked on
the hook's unresolved skill-identity question, and that question does not need
answering to ship.

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
command becomes `bash /scripts/skill-preflight.sh <name>`, an absolute path at the
filesystem root. On macOS and Linux an unprivileged attacker cannot create
`/scripts`, so the degenerate case is a 127 caught by the outer guard rather than
an execution of attacker-controlled code. This is why the path must stay
absolute: a relative fallback would resolve against the current working
directory, and the working directory during a skill load is a repository whose
contents may have arrived from a pull request.

The script's own `${CLAUDE_PLUGIN_ROOT:-self-resolve}` fallback follows the same
rule, and an earlier draft got its mechanism wrong in a way worth recording,
because the wrong version fails silently in exactly the forbidden direction. That
draft said the fallback was "lifted from the existing `preflight.sh`", which
resolves via `${BASH_SOURCE[0]}`, while specifying `sh` as the interpreter.
`BASH_SOURCE` is a bash array and does not exist under `sh`: a literal lift would
have yielded `dirname ""` → `.` → a `$PWD`-relative root, which is precisely what
the paragraph above forbids, and the 127 that followed would have been swallowed
by the outer guard with nobody learning anything. Settling the interpreter as
bash makes the lift accurate rather than aspirational, and the fallback is
`ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"`
-- one level up, since the entry point lives at `scripts/`.

Whatever root is resolved is the directory the four `scripts/lib/preflight-*.sh`
helpers are *sourced* from, and sourcing is code execution. So the root is
validated before anything is sourced: it must be absolute, and it must contain a
readable `plugin.json`. If either test fails the script exits 0 having sourced
nothing and having printed a single line saying it could not locate the plugin
root. That line is one of the few things it prints on a path that is not a
finding, and it is worth the bytes: a check that cannot find itself should say so
rather than join the silent-failure set.

**Declaration files are read from the repository and their contents reach a
shell.** A `requires.tsv` record supplies a tool name and a subcommand path that
the probe passes to `--help`.

The first thing to state plainly is what an earlier draft got backwards. That
draft claimed fields are "never word-split into a command line by expansion"
while the format definition made field two "the full subcommand path including
spaces". Both cannot be true, and the format is right: **field two is split on
spaces into argv elements, deliberately, because that is what it is for.** The
invariant is not that no splitting happens. It is that splitting is the only
transformation applied, that it happens under a controlled `IFS`, and that every
resulting element has passed a character allowlist before it becomes an argv
element.

Four controls apply.

Fields are never `eval`'d and never re-expanded. The probe builds its argv
explicitly with `set --` and quotes every expansion, so no field is ever
re-parsed as shell text.

Every field is validated against the character allowlist given under *The
declaration format*, **by the script at read time**, not only by CI. The
leading-`-` rejection in fields one and two is the security-relevant half: field
two's tokens are appended before `--help`, so an unvalidated subcommand field of
`--version` or `-x` would reach the probed tool as a flag. This is the discipline
`skills/scope/SKILL.md` states for its own command construction and the reason
`work_summary.rs` anchors its owner/repo pattern on an alphanumeric. A record
failing validation is skipped, and the skill name, the line number, the field, and
the expectation are reported -- not silently dropped, because a silent drop puts a
malformed record into the same zero-byte outcome as a satisfied one.

Field one must appear in `scripts/lib/tool-routes.tsv`, so a record cannot
introduce a new executable name without a reviewed edit to that file. The script
enforces this too, for the same reason.

And the probe only ever appends `--help` and reads stdout: it never runs a
declared subcommand, which is a requirement of the probe strategy for correctness
reasons and happens to close the injection path as well.

**The controls are in the script because review runs too late.** An earlier draft
answered the hostile-`requires.tsv` case by saying "the threat model here is a
malicious pull request against shirabe itself, which the review of a four-field
tab-separated line is well suited to catch", backed by `check-skill-requires.sh`
in CI. Both of those act on the PR. A reviewer who checks the branch out locally
-- with the plugin root pointing at that checkout, which `marketplace.json`'s
`"source": "./"` makes the normal developer configuration -- loads a skill and
runs that branch's declaration before either control has run. Review is not a
control against a payload that fires when the reviewer opens the branch. The same
ordering applies to `scripts/lib/preflight-*.sh` and to `skill-preflight.sh`
itself on that branch.

Two things follow, and the design states both rather than choosing one. The
allowlist and the tool-set check live in the script, so on a branch that changed
only `requires.tsv` -- much the likelier shape, since a declaration edit reads as
routine and a script edit does not -- the committed-and-reviewed script is the
control rather than the reviewer's attention. And for a branch that changed the
script itself, there is no mechanism and the design will not pretend otherwise:
**reviewing a shirabe pull request with the plugin root pointed at the checkout
means running that branch's preflight code at every skill load.** That is the
exposure a reviewer accepts, it is the same exposure every plugin-shipped script
already carries, and the way to avoid it is to review with the plugin root pointed
at a trusted checkout.

**The probe executes binaries PATH resolves, and neither the resolution nor the
execution was previously bounded.** This surface was missing entirely, and it is
the one where the design invoked a threat model for its own script and then
declined to apply it to the six binaries that script runs.

*Provenance.* `command -v` honours a PATH containing `.` or a relative entry, and
the working directory at skill load may be a PR checkout -- the same fact that
forces the plugin-root path to stay absolute. So the resolved path must be
absolute and must not lie under the current working directory, or the tool is
treated as resolution-refused and never executed. The report says so.

*Execution.* Every probe carries a 2-second wall-clock timeout, `</dev/null`, and
a 64 KiB output cap, with the timeout and cap paths reported as inconclusive
rather than as findings. Specified under *How a probe is executed*.

*The denial-of-service claim, qualified.* The always-exit-0 discipline establishes
that no exit code from this subsystem can refuse a skill. It does not establish
availability. A binary that hangs on `--help`, that reads stdin, or that writes
without stopping blocks skill load or floods the context, and under R12's silence
rule the user sees nothing while it happens -- the denial of service is not the
check refusing, it is the check waiting. The timeout, the stdin close, and the
byte cap are what make the availability claim true, and they are requirements
rather than optimizations. The 20 ms `gh --help` measurement quoted throughout is
an honest-host number and says nothing about a hostile one.

**`SHIRABE_PREFLIGHT_ROOTS` is input, not just a test affordance.** It appears in
this design as R28's override and in the test plan as an `mktemp -d` target, but
anything that sets session environment can set it -- including a project-level
`.claude/settings.json` `env` block, which is a file that ships in the repo under
review.

What setting it buys today is the absent-versus-off-PATH distinction: a crafted
root list can suppress an install route by making an absent tool look off-PATH, or
fabricate one by making an off-PATH tool look absent, in a report an agent is
likely to act on. That is bounded, and the bound is now an invariant rather than
an accident of the current sketch: **roots are only ever tested with `-x`, and a
root-resolved path is never executed.** A later revision that wants to probe a
root-resolved binary has to change that sentence first.

Root entries are also echoed verbatim into report text -- the "Checked PATH, then
..." line -- so they pass the same path allowlist as the `command -v` result
before rendering: absolute, `[A-Za-z0-9._/-]+`, 4096 bytes. A non-conforming entry
is not rendered.

**The report is generated from declaration content and tool output, and is
inserted into the model's context.** This is the sharpest surface in the design
and it deserves to be named as such. The report becomes body text the model reads
as instructions, and part of it is `--help` output from a binary on the user's
PATH. A hostile or shadowed `koto` could emit help text shaped like an instruction
and have it land in context.

The mitigation is the filter specified under *The filter on tool-derived text*,
and it is a mechanism rather than an argument: strip ANSI CSI and C0/C1/DEL code
points, apply a character allowlist per token, drop rather than sanitize a
non-conforming token, cap token length at 64 bytes and list length at 24 items,
and render only inside a fixed label. The section also states why no nonce fence
is used -- the allowlist leaves no character with which to forge a terminator --
and states the tripwire that would make one mandatory. Three interpolation points
are covered: the advertised subcommand list, the advertised flag list, and the
`command -v` resolved path. Nothing else in a report comes from a tool.

Two arguments accompany the filter and neither substitutes for it. The position
anchoring -- 2 to 6 leading spaces marks an option line -- was chosen to defeat a
false positive in honest help text, not as a security control, and a hostile
binary controls the bytes at that position completely; it bounds where text is
drawn from, not what it says. And the trust-boundary argument, that a hostile
binary on PATH already has a more direct path to the same outcome, is partly right
and insufficient in three specific ways: the check runs at load, unconditionally,
before the model or the user has decided to do anything, while the tool's own
execution is conditional on reaching a phase; it runs for records whose phase the
run may never reach; and the report lands in the SKILL.md body ahead of the
instructions it qualifies, which is a strictly higher-trust position than a tool
result. The filter is what closes that gap.

The check does not echo raw stderr into the report on the probe path, and the
report offers the reader exactly one command with no choice, so there is no path
by which report text becomes an arbitrary command line. Both are invariants the
implementation must hold, not descriptions of it.

**The enumeration file governs a CI gate.** `references/tool-diagnostic-discards.md`
is an allowlist, and adding a line to it makes a scan stop complaining. That is
the intended mechanism and R21b's whole point is that it costs a reviewed edit.
The design hardens it in two directions. The scan reports stale entries as well
as unenumerated sites, so the list cannot silently accumulate exemptions for code
that no longer exists. And the join key includes the trimmed command text, so
editing what an exempt command does breaks the join and forces the exemption back
through review rather than letting an exemption granted for one command silently
cover a different one.

The design also demanded a stated ownership rule of `tool-routes.tsv` and, in an
earlier draft, demanded nothing of the file that actually gates CI. That is closed
the same way the sibling file closes it. Every record carries a justification
field and a mandatory issue or incident citation, so an exemption with nothing
behind it fails the scan rather than a reviewer's memory.
The design called for `references/tool-diagnostic-discards.md` to get a
`CODEOWNERS` entry naming its adjudicator, because "it costs a reviewed edit" is
a claim about a process, and a process with no owner is not a control. A new
entry may land in the same PR as the code it exempts -- splitting them would
mean landing code that fails CI -- but it must be its own commit, so it is
reviewable as a decision rather than buried.

**Shipped without the CODEOWNERS entry.** This repository has no `CODEOWNERS`
file, and introducing the first one changes review mechanics repository-wide,
which is a maintainer's decision rather than a side effect of shipping this
check. The entry also only binds when branch protection sets
`require_code_owner_reviews`; without that it is inert, which is the same
silent no-op the enumeration exists to prevent. The mechanical half of the
control shipped and holds on its own -- an unenumerated discard fails CI. The
adjudication half is currently reviewer discipline, and
`references/tool-diagnostic-discards.md` says so in its own words rather than
claiming an owner it does not have.

The failure mode this leaves open is a reviewer approving an entry they did think
about and got wrong, which is the same failure mode every allowlist has and which
the one-record-per-line format is chosen to make as visible as possible in a diff.

**The route table emits commands an agent will run.** `scripts/lib/tool-routes.tsv`
produces the single command each unsatisfied block prints, and an agent reading
the report is likely to execute it. The table is a committed file with a stated
ownership rule, routes are probed for availability rather than assumed, and the
report prints exactly one command with no choice for the reader, so there is no
path by which report text becomes an arbitrary command line. The `gh`-on-Linux
exclusion is the first entry and the reason the table exists: emitting a command
known to produce a segfaulting binary is a real harm, and leaving that knowledge
in a TOML comment is what R20 exists to end.

**The check never refuses a skill.** R17 is a security property as much as a
usability one. A check that could refuse would give anyone who can influence the
declaration, the route table, or a tool's help output a way to disable twenty
workflows. The always-exit-0 discipline, in the script and again in the injected
line's outer guard, means no exit code from this subsystem can abort a skill. The
availability half of that claim is carried by the timeout, the stdin close, and
the byte cap, not by the exit discipline -- see the probe paragraph above.

**Failure-open is also a detection blind spot, and that has to be said out loud.**
Every paragraph above treats always-exit-0 as a benefit. It is also the reason
this subsystem cannot report its own subversion, which is an uncomfortable
property for a feature whose subject is detecting drift.

R17 plus R12 mean the observable output of a fully satisfied host is
byte-identical to the output of every one of these:

- the script is missing from the package
- the script is present but unreadable or truncated
- `${CLAUDE_PLUGIN_ROOT}` did not expand, giving a 127 the `|| true` swallows
- the plugin root resolved but `plugin.json` was absent, so nothing was sourced
- `requires.tsv` is absent, or empty, or its tabs were converted to spaces by an
  editor
- somebody inserted an early `exit 0`
- `scripts/` was dropped by packaging or a marketplace fetch

Zero bytes for all of them, and no host-side signal distinguishes any of them from
success. The design was aware of several individually -- the tab-conversion
hazard, the 127, the clap-layout break -- and never assembled them.

Two things partly cover it and it is worth being exact about what they do not.
The Phase 3 CI tests assert a non-empty report for the absent-tool case, which is
a real answer for the script's own logic, but they run the script directly in CI
rather than the injection path on a user's host. Phase 2 validates the injection
path end to end, but it is a one-time manual gate on one machine, not a recurring
signal.

The design's position is that this is worth one cheap mechanism rather than a
subsystem. The liveness eval in Phase 4 -- a fixture skill with a deliberately
unsatisfiable declaration, loaded through the real injected line, asserting a
non-empty report -- exercises the injection path continuously in CI and costs the
satisfied path nothing. It does not cover a user's host, and nothing short of
emitting bytes on the satisfied path would, which R12 forbids for reasons the
Decision Drivers section argues at length. That residual is accepted, named here
so a future reader does not have to rediscover it.

**Not applicable.** The check writes no files, holds no state across runs, opens
no network connection, and reads no credentials. It never parses or compares a
version, so there is no version-negotiation surface. Nothing it does is
privileged, and nothing it emits is persisted. The memoization store is two shell
variables for exactly this reason: a temp-file cache would have made the first two
sentences false.

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

Three rules that were previously somebody's judgement become committed artifacts
with named owners: the first-party/independent-cadence split in
`references/tool-declaration-policy.md`, the install routes and the `gh`-on-Linux
exclusion in `scripts/lib/tool-routes.tsv` with a mandatory issue citation on
every exclusion, and the diagnostic discards in
`references/tool-diagnostic-discards.md` with a `CODEOWNERS` adjudicator. Each
replaces a rule that lived in a comment, in prose, or in nobody's head.

Everything ships in one commit with no seam. The script, the declarations, and
the SKILL.md lines that invoke them are the same artifact, which is what makes
this feature's own drift story different from the one it is fixing.

Both `shirabe validate` consumers become correct against every shirabe version
ever shipped, including the ones already installed, which is what R22's
motivating case requires and what a producer-side fix alone cannot deliver.

The entry point stays a script, so a future `shirabe preflight` can be delegated
to behind the same contract without touching any SKILL.md or any test.

### Negative

`/work-on` pays up to 18.7 ms and 14 subprocesses at every load -- 5 `command -v`
builtins that spawn nothing plus 9 `--help` calls. That is the real recurring
cost, it scales with declaration size, and `/work-on`'s declaration is the one
most likely to grow. Nothing caches across skill loads.

Twenty SKILL.md files each gain a frontmatter entry and a body line, and each
pair is a way to kill a skill if the two disagree. Nineteen of the twenty have no
`allowed-tools` today, and the one that does uses a different pattern shape, so
there is no in-repo precedent for the form being rolled out.

Skills that need no shell today will need one, and specifically they will need
bash. The plugin already ships scripts several skills invoke, so bash is a de
facto requirement for those, but not for the prose-only skills, and this change
makes it one. Choosing bash over `sh` narrows nothing in practice -- bash ships
with macOS and is universal on the Linux distributions `install.sh` supports --
but it is a stated dependency rather than an implied one. On Windows without Git
Bash the harness routes injected commands to the PowerShell tool, where a
`bash <path>` command line does not run, and a failed injected command aborts the
invocation.
The exposure is narrow: `install.sh` accepts only `linux` and `darwin`, so the
binary most of these skills call cannot be installed on Windows at all. The honest
posture is to document bash as a requirement rather than to claim platform
neutrality, and to keep the injected line trivial so a platform-conditional
variant would be one line per skill to change.

A bash 3.2 artifact that will grow. The floor forecloses the constructs a
maintainer will reach for first -- associative arrays for memoization above all --
so the memoization store is two newline-delimited strings and the reader is a
`while read` loop, which is more code than the obvious version and will read as
gratuitous to anyone who forgets why. Structural introspection of shirabe's own
clap tree is foreclosed too: the check greps rendered help for shirabe exactly as
it does for koto, so a help-rendering change in clap is a silent break in the
probe.

A tab-separated format has no parser to reject a malformed file, and an editor
that converts tabs to spaces produces a file that looks right and parses wrong.
The read-time allowlist catches most of what a parser would, but it catches it at
load rather than at write time.

The `--help` layout becomes a contract. If a future clap changes the `Commands:`
or `Options:` block shape, the extractor under-reports, which fails open into
false findings rather than false silence.

Reports no longer say which phases of a skill survive an unsatisfied requirement.
An earlier draft's "phases 0 through 5 will run; phase 6 cannot complete" was
better writing than what replaced it, and it was writing no data source could
produce. The narrowed report names the skill, the declared call, and that the call
will fail as written, which meets R14 at declaration granularity and is the most
the four-field schema knows. A reader who wants the phases greps for the tool and
the subcommand the report names. If phase-level impact is wanted back, the way in
is a mechanically derived call-site index, not a free-text field colocated with
data that stays true.

The load-time report says nothing at all about mode-scoped records. That is the
resolution of R10 against R12 -- the deferral is visible in the declaration's
fourth field, not in the report -- and it means a reader who looks only at a
`/roadmap` load sees no trace that anything was deferred. They have to open
`requires.tsv`. This is the correct trade, because a report that mentions records
the check did not evaluate implies an evaluation that did not happen, but it is a
trade, and R10's "visibly marked deferred" wording invites the other reading.
**The PRD should be read with this design's gloss on that point.**

Some reports end by telling the reader the tool might be fine and the skill might
be wrong. That reads as weaker than a confident upgrade instruction, and it is
correct: `koto context remove` has never existed at any version, so the confident
version would send a reader to reinstall a binary that was never going to help.
A reviewer will push back on this wording. It should be held.

The check is silent about its own failure. Every way it can break -- missing
script, unexpanded plugin root, absent sidecar, tabs converted to spaces, an
inserted `exit 0` -- produces the same zero bytes as success. The Phase 4 liveness
eval covers the injection path in CI; nothing covers it on a user's host, and R12
is the reason. Named in Security Considerations and accepted.

### Mitigations and named risks

**The permission pattern is the risk that can delete twenty skills.** It is
masked locally by `"defaultMode": "auto"`, so it must be validated on a non-auto
host before rollout, which is why Phase 2 is a gate rather than a task.
`scripts/check-skill-injection.sh` holds the invariant afterward.

**Tab preservation** is enforced twice, by the conformance scan in CI and by the
reader at load, both rejecting any record line without exactly three tabs. The
reader is the load-bearing copy for the reason the Security section gives: CI runs
after the fact, and a reviewer with the plugin root pointed at a branch runs that
branch's declarations before CI has seen them.

**Install-route sprawl** has a stated threshold. R14, R15, R19, and R20 all push
the check toward accumulating per-host route knowledge. That data now lives in
`scripts/lib/tool-routes.tsv` with a six-field schema and a closed probe
vocabulary, rather than in `case` arms, which is what keeps adding a route a data
edit. If route *resolution logic* -- not the data -- outgrows what bash 3.2 should
carry, move route resolution alone into the binary as an optional enhancement the
script uses when present and falls back from when absent. The check itself never
sits behind the binary.

**The clap layout contract** is guarded by a probe regression test asserting a
known-present and a known-absent flag against fixtures captured from real help
output, in both of clap's layouts.

**A declaration is unverifiable for completeness.** Nothing mechanically proves
one complete, and a call the declaration omits is unchecked. The flag-extraction
scan is the closest available guard, and it reaches only the two first-party
tools whose declarations name flags at all. A default-flip behind a stable flag
name remains undetectable at any probe depth; R22a avoids it at compliant call
sites and nothing will say so at a non-compliant one.
