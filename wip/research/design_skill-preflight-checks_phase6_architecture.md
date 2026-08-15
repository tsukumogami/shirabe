# Verdict: FAIL

The architecture is sound and the Considered Options survive the strawman test.
It fails on four blockers: the report cannot be generated from the schema the
design specifies, R10 and R12 contradict each other unreconciled, R4's required
committed artifact is silently dropped, and the shell the entry point actually
runs under on Linux is never identified — leaving the two places a builder
would reach for bash 4 unspecified.

## Requirement coverage (R1-R28)

Addressed and traceable: R1 (schema-only vs absent file, decidable by `ls`),
R2, R3 (`-` subcommand for independent-cadence tools), R5 (`when` field), R6-R8
(resolve / level enumeration / position-anchored flag extractor), R9 (no
version parse anywhere; Consequences restates it), R12, R13 (partially — see
below), R15, R16 ("complete on first emission", no re-run affordance), R17,
R18 (resolution ordering, empirically established), R19 (route probing plus the
honest-bound closing sentence), R20 (`tool-routes.tsv`, exclusion moved out of
the `.tsuku.toml` comment), R21/R21b (four redirect shapes, `command -v`
carve-out, bidirectional join), R22 (envelope-presence discriminator, both
consumers), R22a (Phase 5), R23, R24 (Phase 4), R25 (resolved by removal, with
the reason stated), R26 (Phase 1, and the design found the defect is worse than
R26 describes — `koto context get` writes errors to stdout, so the `2>/dev/null`
never did anything), R27, R28 (`SHIRABE_PREFLIGHT_ROOTS`).

**R4 is silently dropped.** R4 requires the first-party/independent-cadence
split be "recorded as an explicit, stated policy with its rationale", and the
PRD's acceptance criterion pins it: "appears in a committed reference under
`references/`, cited by name from the requirement it governs." The design
names no such artifact. The Components table has eight rows and none of them is
that reference. The rationale exists in the design's prose ("`gh` is
independent-cadence so its record names the tool alone", the 20 ms cost
argument), but R4 asks for a committed policy document, not a design paragraph
that ships nowhere. This is the one requirement the design addresses in
substance and drops in deliverable.

**R14 is specified but not buildable — this is the blocking gap.** R14 requires
the report name "what the skill will be unable to do." Both worked examples do
this well, and it is the best writing in the document:

> `/work-on` uses it to clear a stale scrutiny artifact before re-running
> phase 4a (skills/work-on/references/phases/phase-4a-scrutiny.md:45).

> `/work-on` uses gh to read the issue it was asked to implement, to poll CI
> checks, and to open the pull request. Phases 0 through 5 will run; phase 6
> cannot complete.

Neither sentence can be produced from `<tool> <subcommand> <flags> <when>`.
There is no capability field, no call-site field, no affected-phase field. The
Security section asserts the opposite — "the posture sentence, the capability
sentence, and the command line are composed from the declaration and the route
table, both of which are committed files" — which is true of the posture
sentence and the command, and false of the capability sentence. Either the
schema gains a fifth field (and the design's repeated "four fields", the
conformance scan's "exactly three tabs", and the three worked declarations all
change), or R14's capability sentence degrades to something generic and the
examples are aspirational. The design must pick one. As written an implementer
reaches this line and stops.

**R13 is under-specified.** Five postures are implied ("Two of the five cases,
verbatim") but only two are shown. The flag-gap block and the off-PATH block are
never rendered, and the off-PATH block carries a normative rule stated only in
prose ("say 'nothing needs installing' outright and sort first"). R13's whole
point is that collapsing a split reproduces the misdiagnosis; the two splits
that are not shown are the two the design is asking an implementer to invent.

**R10/R11 are internally contradictory with R12.** See the next section.

## Strawman check

**This axis passes, and it is the strongest part of the document.**

The rejected implementation homes are argued, not asserted. Option B
(`shirabe preflight`) is granted the strongest possible framing — "it is the
option with the best engineering on its own terms" — with three named
precedents (`pr_body_hook.rs`, `work_summary.rs`, clap's structural
introspection) before the rejection lands, and the rejection turns on three
mechanical failures plus a piece of evidence the reviewer can check: `grep -rn
CLAUDE_PLUGIN_ROOT crates/` returns zero, so a plugin-side declaration would be
the binary's first dependency on plugin layout. I verified that grep: zero hits.
Option C (the split shim) is rejected by working out the ownership boundary
line by line and showing the shim ends up owning everything but one loop, plus
the `exec` observation — an `exec` forfeits the interception the shim exists
for. That is real analysis of an option the author did not want.

The YAML sidecar (option B in the declaration section) is genuinely evaluated,
not strawmanned. The design concedes the option's *location* reasoning is
correct and carries it forward wholesale — sidecar over frontmatter, one entry
per triple, mandatory `when:`, explicit-empty distinguishable from absent — and
rejects only the encoding. It names the real reader (`saphyr`, with the
`skills/writing-style/rules.yaml` precedent), grants the premise ("That premise
is right"), and then quotes the decision's own consequences section admitting
the bootstrap hole. Rejecting an option by adopting four fifths of it is the
opposite of a strawman.

One gap on this axis, and it is the same gap the design accuses option B of:
**the option set is still incomplete.** The design says B "never evaluated a
sidecar in a format a POSIX shell can read." True — and the design never
evaluates a *restricted YAML subset* a POSIX shell can read, which is the
symmetric option. A flat `tool: koto` / `subcommand: context add` block form is
shell-readable with `sed`, keeps comments-with-structure and a familiar
encoding (two of the three costs the design books against TSV), and would let a
future binary-side reader parse the same file with a real parser. It may well
lose to TSV. It is not weighed.

The rejected load-time mechanisms hold up: option C (fenced bash block) is
rejected on the driver the feature exists to satisfy, with two live instances of
prose-that-never-runs cited by path. **Option B (the `PreToolUse` hook) is the
weak one — not because it is strawmanned, but because it is left unresolved on
an empirical question nobody answered:** whether the individual skill name
reaches a hook whose `tool_name` is the generic `"Skill"`. That question is
answerable in an afternoon and it decides the option. Worse, the design names
the hook "the natural home for the mode-scoped enforcement in R11" and then
implements R11 in Phase 6 via the agent-instructed shape it rejected for
load-time use, without ever returning to say why the natural home was not used.

## Seams and internal inconsistencies

**1. R10's deferral marker versus R12's zero bytes.** The design says the
injected line "evaluates only `when: always` records and marks `mode:` records
visibly deferred." Marking something visibly at load emits bytes. R12 requires
zero bytes on a fully satisfied declaration, and the PRD's acceptance criteria
carry both rules — "A mode-scoped entry is visibly marked as deferred at load"
and "invoking the check's entry point yields zero bytes across stdout and
stderr combined." For `/roadmap` (which the design prints with two `mode:issues`
records) and `/plan`, a satisfied host either gets zero bytes and no deferral
marker, or a deferral marker and non-zero bytes. It cannot get both. The design
never notices the collision, and the "0 bytes, measured with `wc -c`" figure was
taken against `/work-on`, whose declaration the design itself flags as
all-always — the one skill in the corpus where the contradiction cannot appear.
This also blows the dedup argument the whole silence rule rests on: a persistent
deferral marker is byte-identical across reloads, so dedup actually survives,
which suggests the resolution is "marker is fine, R12 means zero *findings*" —
but that reading has to be written down, because R12's text says zero bytes.

**2. The shell is never identified, and it is not bash.** The injected line is
`sh ${CLAUDE_PLUGIN_ROOT}/scripts/skill-preflight.sh`. On ubuntu-latest `/bin/sh`
is dash. The design calls the script "POSIX" but every precedent it inherits
from is bash: `scripts/lib/koto-gates.sh` (verified: `#!/usr/bin/env bash`), the
existing `preflight.sh` (`#!/usr/bin/env bash`, `set -euo pipefail`,
`${BASH_SOURCE[0]}`), and the CI template it clones runs `bash` and `/bin/bash`.
So Phase 3's test workflow validates the script under bash 3.2 and bash 5 and
never under the shell that runs it in production on Linux. The design's own
bash-3.2 rationale — quoted from `check-plan-scripts.yml`, that "a pattern list
only catches what its author remembered" and only running on the floor catches
it — argues directly for a dash leg the design does not add. Either the injected
line becomes `bash ...` (which is also the actual house idiom — see below) or
the CI matrix gains a dash leg.

**3. The house-idiom claim is wrong.** The design justifies `sh <path>` as
matching "the house idiom already at `skills/execute/SKILL.md:129`". Line 129
reads `bash ${CLAUDE_PLUGIN_ROOT}/skills/execute/scripts/preflight.sh`. The house
idiom is `bash`, not `sh`. The *other* half of the justification — that
invoking through an interpreter avoids depending on the executable bit — is
sound and survives either choice.

**4. `${CLAUDE_PLUGIN_ROOT:-self-resolve}` cannot be "lifted from the existing
`preflight.sh`."** That fallback is `$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)`.
`BASH_SOURCE` is a bash array and does not exist in dash. The design does say
the new one "resolves from `$0` rather than from `$PWD`", which is the right
answer, but describes it as lifted verbatim from a construct that cannot be
lifted. An implementer following the citation writes a line that fails silently
under `sh` on Linux, producing exactly the 127 the outer guard swallows — the
check disappears and nobody learns.

**5. The mode entry point's signature diverges from the load-time one.**
Load-time: `sh <path> <skill> 2>&1 || true`. Mode-time: `sh <path> <skill> --mode <name>`,
with no `2>&1` and no `|| true`. Every argument the design makes for the guard —
a missing script or unexpanded plugin root gives 127, and an unguarded non-zero
exit aborts the invocation — applies identically at mode-selection time, where
aborting mid-workflow is worse than aborting at load. The mode path also has no
stated output contract: does it stay silent when satisfied? Does it re-report
the `always` records? R11 says the mode requirements "SHALL be verified", and
the design gives one line of command text and no behaviour.

**6. `/work-on`'s measured figures do not match `/work-on`'s printed
declaration.** The design prints a fifteen-record declaration naming five
distinct tools (koto, shirabe, gh, git, jq) and then reports "10 `--help` calls
and 3 `command -v`". Resolution runs per tool, so it is five `command -v` calls,
not three. Separately, the ten enumerated levels include `koto context add`,
which carries `-` for flags — under the design's own stated rule ("one `--help`
per subcommand level visited, plus one `--help` per leaf carrying a declared
flag") that leaf needs no call, and the count is nine. The rule and the
enumeration disagree by one call, and the resolution count is off by two. These
are the numbers the Negative consequences section budgets against (18.7 ms, ten
subprocesses), so they should reconcile.

**7. The conformance scan checks a set the design never defines.** The scan
"rejects a tool name outside the declared set." No file holds that set.
`tool-routes.tsv` is the plausible home, but it is described as install routes
plus exclusions, and its format is not given. This is also a security control —
the Security section leans on it to argue a record "cannot introduce a new
executable name without a reviewed edit to the tool list."

## Buildability gaps

An engineer would have to invent all of the following.

**The TSV schema is incompletely specified.** Stated: four fields, tab-separated,
`#schema	skill-requires/v1` header, `-` as explicit empty, field two carries
spaces, field three is comma-separated with no spaces, field four is `always` or
`mode:<name>`, exactly three tabs per record. Unstated: whether `#` opens a
comment line generally or only the schema line (the scan rejects any line
without exactly four fields, so a comment is currently a hard error — probably
not intended); whether blank lines are legal; what a flag containing a comma
does to field three (the design rejects comma as the *record* delimiter
precisely because "comma appears inside flag lists", then uses comma as the
intra-field separator with no escaping rule — the one place the argument
undercuts itself); whether the schema line is required, and what happens on a
version other than `v1`; whether trailing whitespace is stripped; whether field
order within a file is significant.

**`scripts/lib/tool-routes.tsv` has no stated format at all.** It is one of
eight components, it drives the single command every unsatisfied report prints,
it holds the R20 exclusion that is one of the design's motivating examples, and
its schema is one sentence of prose: "Install routes per tool and the R20
exclusions." Unspecified: field count and meaning, how a route is expressed, how
the availability probe for a route is encoded (the report shows `tsuku`, `brew`,
`apt-get`, `cargo` each with a distinct probe — `tsuku info <pkg>` succeeding is
named for tsuku and nothing is named for the others), how an exclusion binds to
an OS, how the required issue-number citation is carried, and how the header
that "states the rule for changing it" coexists with a scan that presumably
rejects malformed lines. The Security section calls this table an emitted-command
source and leans on its committed-file status; that is not a substitute for a
schema.

**How the TSV is read.** No `IFS` handling is specified anywhere. Field two
contains spaces, so the read must set `IFS` to a literal tab and use `read -r`;
get this wrong and `roadmap populate` splits into two fields and every record
with a multi-word subcommand fails the four-field check. `IFS=$'\t'` is
ANSI-C quoting — fine in bash 3.2, unavailable in dash. This is precisely the
kind of construct the design's own bash-3.2 discussion says a grep will not
catch.

**How levels are memoized.** The probe's cost argument depends entirely on
memoization ("cached so siblings and repeated paths cost nothing"), and the
mechanism is never given. In a shell with no `declare -A` this is a temp file, a
string accumulator with a `case` membership test, or a directory of marker
files — three real options with different failure modes, and the design leaves
the choice to the implementer at exactly the spot where reaching for an
associative array is the natural instinct. This is the single most likely place
a bash 4 construct enters the tree.

**Smaller inventions:** the helper filenames (`scripts/lib/preflight-*.sh` is a
glob; "Resolver, probe, reporter" is a role list, not three paths); how the
colon-separated `SHIRABE_PREFLIGHT_ROOTS` is split without clobbering `IFS` for
the TSV read; how the `Commands:` block is parsed for subcommand extraction (the
design specifies the `Options:` extractor precisely — 2-to-6 leading spaces for
definitions, 8+ for wrapped descriptions — and specifies nothing for the
subcommand list, which R7 depends on); the exact wording of the three unshown
report cases; and which `koto context` verb replaces `remove` at
`phase-4a-scrutiny.md:45`, which the design explicitly defers to the plan while
also making `/work-on`'s declaration depend on the answer.

## The bash 3.2 claim

By inspection, nothing the design *prescribes* requires bash 4: no `declare -A`,
no namerefs, no `mapfile`, no `${var^^}`, no `${var,,}`, no `+=` on arrays. jq is
avoided deliberately and consistently — it is the stated reason the route table
and the discard enumeration are line-oriented rather than JSON, and the design
verifies its own premise (jq is installed explicitly in three workflows; I
confirmed `check-execute-scripts.yml` and `check-plan-scripts.yml` both carry
`Install jq` steps for both legs). No arrays are prescribed at all; the probe's
argv construction is described as "builds its argv explicitly and quotes every
expansion", which is satisfiable with positional parameters via `set --`.

The claim is therefore not violated — but it is not *established* either,
because the two constructs that decide it are the two the design does not
specify (the TSV read's `IFS`, and the memoization store). And the floor is
mislabelled: the entry point is invoked as `sh`, so the real floor is POSIX sh
including dash, which is stricter than bash 3.2 in ways that matter here
(`$'\t'`, `local`, `BASH_SOURCE`, `[[`). Every test the design plans runs bash.

## Spot-checks

Ten claims checked against the tree; eight verified, three factual errors found.

Verified:

- `skills/execute/scripts/preflight.sh` ends with `echo "execute preflight OK:
  cross-skill child template resolves at: $CHILD"`. The success line the PRD
  names is real and must go. Confirmed.
- All four live defects are at the stated lines. `skills/inflight/SKILL.md:40`
  is `` !`shirabe work-summary render` ``; `:77` is
  `` !`shirabe work-summary track <pr-url> [<pr-url> ...]` `` at column 0 with
  injection syntax, as described.
  `skills/work-on/references/phases/phase-4a-scrutiny.md:45` is the
  `koto context remove <WF> scrutiny_results.json` call.
  `skills/execute/koto-templates/execute.md:390` and `:409` are the two
  `SETTLED_BRANCH=$(koto context get ... 2>/dev/null || echo "impl/$PLAN_SLUG")`
  lines, each followed by the character-class `case` guard the design says is
  load-bearing.
- `koto context --help` advertises exactly `add`, `get`, `exists`, `list`
  (plus `help`). No `remove`. The surface gap is real.
- `koto --help` lists 16 top-level commands, `shirabe --help` lists 9. Both
  counts as claimed, so the "presence plus the entire first subcommand layer
  costs one call" argument holds.
- `plugin.json` reads `0.16.1-dev`; the installed binary reports
  `shirabe v0.16.0`. The drift the Context section opens with is live.
- `grep -rn CLAUDE_PLUGIN_ROOT crates/` returns zero hits, as claimed.
- `.tsuku.toml:5` is `# gh = "latest"  # disabled: segfaults on Linux
  (tsukumogami/tsuku#2245)` — the comment, the exclusion, and the issue number
  all match.
- Timing is plausible: `koto --help` measured at ~4 ms here against the design's
  2.5-3 ms, within noise for a single sample.
- Every cited precedent file exists: `scripts/lib/koto-gates.sh`,
  `scripts/check-sentinel.sh`, `scripts/check-template-interpolation.sh`,
  `references/wip-hygiene.md`, `references/worktree-discipline.md`,
  `references/fixes/cli-version-preflight.md`,
  `docs/guides/multi-consumer-cli-contract.md`,
  `.github/workflows/check-plan-scripts.yml`,
  `.github/workflows/check-no-duplicate-rule-list.yml`. Twenty skill
  directories, matching the corpus size used throughout.

Errors found:

- **"Fifteen of the twenty have no `allowed-tools` today" is wrong. Nineteen
  have none.** `grep -rn "allowed-tools" skills/` returns exactly one hit:
  `skills/inflight/SKILL.md:14`, `allowed-tools: Bash(shirabe:*)`. This appears
  twice in the design (Phase 4 and the Negative consequences) and it understates
  the rollout by four files and understates the risk the Phase 2 gate exists to
  cover. It also matters qualitatively: the one existing entry uses the
  `Bash(shirabe:*)` colon form, not the `Bash(sh <path> *)` prefix form the
  design proposes, so there is no in-repo precedent for the pattern shape Phase 2
  must validate — the design's claim that there is "no local evidence either way"
  is right, but the reason is stronger than stated.
- **The rename inventory is off.** `grep -o "preflight\.sh"
  skills/execute/evals/evals.json` returns 4, not the five the design claims.
  The `skills/execute/SKILL.md` line numbers (129, 276, 681, 706) are exactly
  right. And `.github/workflows/check-execute-scripts.yml` does **not** reference
  `preflight.sh` — its only hit is line 29, `bash
  skills/execute/scripts/preflight_test.sh`, the *test* file. So the workflow is
  touched only if `preflight_test.sh` is renamed too, which the design gestures
  at ("the sibling `preflight_test.sh`") without stating. Note also that
  `preflight_test.sh` itself contains three internal references (lines 18, 67,
  68) including a `cp` into a fake root, and the workflow's `paths:` filter is
  `skills/execute/scripts/**`, which survives the rename. **Net: the rename is
  accounted for, but only because the design's error is conservative — it
  over-counts evals.json and mis-attributes the workflow reference.**
- **The `sh <path>` house-idiom citation is wrong** — `skills/execute/SKILL.md:129`
  uses `bash`. Covered above.

## Required changes

Blocking:

1. **Resolve R14's data source.** Either add a fifth field carrying the
   capability sentence (or a call-site reference the reporter can render), and
   update the schema, the "exactly three tabs" scan rule, and all three worked
   declarations to match — or replace the two worked report examples with what
   the four-field schema can actually produce, and state that R14's capability
   clause is met generically. Do not ship examples the schema cannot generate.
2. **Reconcile R10's deferral marker with R12's zero bytes.** State explicitly
   whether a satisfied `/roadmap` load emits a deferral line or nothing, and if
   it emits one, restate R12 as zero *findings* and show that dedup still holds
   (it does — the marker is constant across reloads). Give the marker's exact
   text.
3. **Name the shell and test it.** If the injected line stays `sh`, add a dash
   leg to `check-preflight-scripts.yml` and state the floor as POSIX sh, not
   bash 3.2. If the floor is genuinely bash 3.2, change the injected line to
   `bash` — which also fixes the house-idiom claim. Then specify the `IFS`
   handling for the TSV read and the memoization mechanism, since those are the
   two constructs the choice actually governs.
4. **Specify `scripts/lib/tool-routes.tsv`.** Field count, field meanings, how a
   route's availability probe is encoded per route, how an exclusion binds to an
   OS, and how the issue-number citation is carried. A component that emits the
   commands an agent will run cannot ship with a one-sentence description.
5. **Add R4's committed policy reference** to the Components table and to a
   phase, at a path under `references/`, cited by name.

Non-blocking but should be fixed before the document is approved:

6. Complete the TSV schema: comment lines, blank lines, comma-in-flag escaping,
   schema-line requiredness and version handling, trailing whitespace.
7. Give the mode entry point the same `2>&1 || true` guard as the load-time line,
   and state its output contract.
8. Correct "fifteen" to "nineteen" for `allowed-tools`, correct the evals.json
   count to four, correct the workflow reference to `preflight_test.sh`, and
   correct the `sh`/`bash` idiom citation.
9. Reconcile `/work-on`'s figures: five `command -v` calls, and either nine
   `--help` calls or an explanation of why `koto context add` is visited despite
   declaring no flags.
10. Render the three unshown report cases (off-PATH, missing flag, and the
    satisfied-but-deferred case if it emits anything), since R13's splits are
    normative.
11. Either resolve the `PreToolUse` hook's skill-identity question or state that
    Phase 6 supersedes it as R11's home, since the design currently names the
    hook "the natural home for R11" and then does not use it.
12. Consider adding a restricted-YAML-read-by-shell option to the declaration
    format comparison. TSV may still win, but the design's own critique of
    option B — that it never evaluated a shell-readable sidecar — applies to its
    treatment of shell-readable YAML.
