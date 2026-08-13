# Decision 1: enforcement engine

What enforces the prose rules. Three options, evaluated against the twenty
requirements of `docs/prds/PRD-vale-adoption.md` (Accepted).

Everything measured below was run on this worktree with Vale 3.17.1 at
`/home/dgazineu/.claude/jobs/b0818094/tmp/bin/vale` and the pre-built
`./target/release/shirabe`. Scratch config, fixtures, scripts, and a working
Rust prototype are in `/home/dgazineu/.claude/jobs/b0818094/tmp/d1/`. Commands
and raw output are in the Empirical Results section; the options sections cite
those results rather than restating them.

## Options considered

### Option A: external linter (Vale) invoked by the validator

**How it works.** `shirabe validate` shells out to `vale --output=JSON
--config=<path> --no-global <file>`, parses the `Alert` array
(`Check`, `Severity`, `Message`, `Match`, `Line`, `Span`), and maps each alert
to a `ValidationError` under the FC10 code. The rule source becomes a
`.vale.ini` plus a `styles/Shirabe/*.yml` directory committed to the shirabe
repo, reached in CI through the `.shirabe-src` checkout that
`validate-docs.yml:53-57` already performs. Per-repo vocabulary becomes
`styles/config/vocabularies/<name>/accept.txt`. The frequency rule becomes a
Tengo script under `styles/config/scripts/`.

**R1 (single source, read at enforcement time).** Vale compiles `.vale.ini` and
the style directory on every invocation, so the sentinel acceptance criterion
passes trivially: append a token to a YAML rule file and the next run reports it
with no rebuild. The complication is that the source is now Vale YAML, and seven
of the rulebook's thirty-eight rules cannot be expressed in it at all (the four
cognitive tells and the three "what human writing has" items). `SKILL.md` has to
survive carrying that half. Whether one YAML tree plus one prose file is "exactly
one authoritative representation" is a judgment call; they are disjoint, so it is
defensible, but a rule added to one and not the other is still possible and
nothing detects it.

**R2 (both consumers, same file, same commit).** A drafting skill would read the
YAML tree, whose `message:` fields carry the author-facing prose ("'%s' is an
AI-tell descriptor. Cut it or name the concrete property."). Workable. The
guidance a model consumes becomes YAML fragments rather than the prose the
rulebook is written in.

**R3 (instruction-file coverage).** This is where Option A fails outright, and
it fails on shirabe's own tree. Two of 211 files under `skills/` carry
frontmatter that Vale's YAML parser rejects with `E201`
(`skills/review-plan/SKILL.md`, `skills/writing-style/SKILL.md`). A single
rejected file in the argument list drives the whole invocation to exit 2 with
**zero findings**, including for the files that parsed. R3 is the requirement
that exists specifically to cover this file class, and the file class contains
files that stop Vale. The frontmatter in question is a wrapped plain scalar with
a colon inside it, which strict YAML disallows and which Claude Code's plugin
loader accepts; these are real committed files, not fixtures.

**R4 (prose scoping).** Vale's strongest feature, and it mostly holds. Fenced
blocks, inline code spans, and Markdown link destinations are excluded with no
configuration. Headings are included, which R4 requires. Table rows are
excluded in the ordinary case. But on shirabe's own `docs/` it produces 13
findings out of 489 that R4 forbids: 11 inside YAML frontmatter block scalars
and 2 inside GFM table rows. Bare URLs and angle-bracket autolinks are not
excluded at all. That is a 2.7% R4 violation rate, measured, not inferred.

**R5 (accurate locations).** Vale reports absolute file line numbers. This is a
genuine improvement over today's FC10, which reports body-relative numbers
offset by the frontmatter length.

**R6 (frequency rules).** The decisive finding, and it has two halves.

The per-paragraph half works well. `extends: occurrence`, `scope: paragraph`,
`token: '—'`, `max: 1` produces one alert per over-threshold block carrying the
observed count, and it fires on paragraphs, list items, blockquotes, and
headings while skipping fences and tables.

The document-level rate half does not work in any R4-compliant form. `metric`
exposes exactly twelve variables, all readability inputs (`words`, `sentences`,
`paragraphs`, `characters`, `syllables`, `complex_words`, `polysyllabic_words`,
`long_words`, `blockquote`, `list`, `pre`, `heading.h1`). There is no
punctuation count and no markup count, verified by probing each name; a formula
naming `em_dashes` fails to compile. So the rate has to be a Tengo `script`, and
a script sees whole-document text only at `scope: raw`, which switches off every
piece of markup awareness Vale has. At any markup scope the script runs once per
block and receives that block alone, so it never sees the document denominator.

R4 and R6 are therefore mutually exclusive under Option A. The one rule that
carries the entire empirical case for mechanized prose checking is the one rule
for which Vale's single best feature is unavailable, and the scoping has to be
rewritten inside Tengo using Go standard-library regex, which has no lookaround.

**R7 (frequency rule shape stated).** A Tengo script can attach a per-match
`message` field that overrides the rule's message, so a computed rate can reach
the author. This is not in the documentation; it was verified directly. The
reporting line for a document-level finding is 1. One sharp edge: an
`occurrence` message written with `%s` renders as `%!s(int=2)` because the count
is an int; it must be `%d`.

**R8, R10, R16 (vocabulary).** Vale's `Vocab` mechanism is the best fit of any
requirement here. It is term-scoped, extends rather than replaces, resolves from
the file being checked with no CI wiring, and works offline. It gets the
morphology rule right: a declared `tier` does not suppress `tiered`. It gets the
case rule wrong. A declared `tier` suppresses lowercase `tier` and leaves `Tier`
firing, and R8 requires case-insensitive matching in as many words. The
workaround is to declare `[Tt]ier` or `(?i)tier`, which works, but it means every
adopter's first action under R17 is writing regexes rather than words.

**R11, R12 (severity, promotion).** Neutral. Severity is shirabe's to assign
once the alert is mapped to a `ValidationError`. Vale's own exit code is
unusable as a gate (only `error`-level alerts make it non-zero) but that does not
matter if the JSON is parsed.

**R13, R14, R15 (registration, one code).** Neutral. The PRD chose extend, so
FC10 stays and is already in all four registration lists.

**R18 (no new runtime dependency for adopters).** This is the requirement Option
A cannot satisfy under any arrangement. The Linux binary is 40 MB unpacked,
10.5 MB as the release tarball, and it is not present on a GitHub-hosted
`ubuntu-latest` runner. Every way of getting it onto the runner is a fetch: a
`curl` of the release asset, a package manager, `go install`, or committing the
binary into the shirabe repo so the `.shirabe-src` checkout carries it. The
acceptance criterion is unusually specific about this: "The reusable workflow's
diff against its pre-change version adds no install, fetch, download, or
package-manager step." There is no reading of that sentence under which adding
Vale passes.

**R19 (version skew structurally impossible).** Partially. The rules would ride
`job.workflow_sha` like everything else, but the engine would be pinned by a
version string in the workflow. The string travels with the ref, so the pin is
consistent; the fetch it triggers is a runtime dependency on a third party's
release asset staying available. This is the same failure mode the PRD's
Decisions section used to reject a release asset for the rule source.

**R20 (no adopter workflow edit).** Satisfied. Changes stay inside the reusable
workflow.

**Robustness.** A Tengo script that returns a span outside the scope text
crashes Vale with an unrecovered Go panic in `internal/check/script.go`, exit 2,
zero findings for the entire run. Reproduced minimally. This matters more than it
would elsewhere because R6's rule must be a script under Option A, and a
document-level finding has no natural span, so span arithmetic on a computed
quantity is exactly the code path that produces the slip.

**Cost.** Two to twenty YAML rule files plus Tengo. An install step in
`validate-docs.yml` (forbidden). Roughly 150 lines of Rust to spawn the process,
parse the JSON envelope, and map alerts. Exit-code handling for 0, 1, 2, and the
panic path. A graceful-degradation path for a missing binary, which shirabe has
precedent for on `gh` but not on `git`.

**What breaks.** Coverage of `skills/` (R3). R4 compliance on frontmatter,
tables, and URLs. R8 case-insensitivity without a documented regex workaround.
R18 outright.

### Option B: widened native check compiled into shirabe-validate

**How it works.** A prose scoper over `Doc.body` producing `(line, text)` spans
with R4 applied, and a frequency check over those spans computing both a
document rate and per-block counts. Rules and vocabulary read from files at
runtime, resolved the way `visibility.rs` already resolves `CLAUDE.md`.

**R1 (single source, read at enforcement time).** Rust has to read a file at
runtime, and `include_str!` is forbidden. This is idiomatic in this crate
already: `visibility.rs:85` walks ancestor directories calling
`std::fs::read_to_string`, `gh.rs:220` reads a file for PR body context, and
`lifecycle.rs:289` walks directories. The only `include_str!` calls in the
codebase pull source files into a test. What it costs is path resolution in CI,
where the binary sits at `/usr/local/bin/shirabe` and the source sits at
`.shirabe-src/`, so an ancestor walk from the document under test lands in the
caller's repo, not shirabe's. The fix is a flag on the reusable workflow's
`shirabe validate` invocation plus an environment variable plus an ancestor-walk
fallback for local runs. A flag is not an install step, so it clears R18's
acceptance criterion. Note that Option A needs the identical flag to point at
`.vale.ini`, so this cost is common to both and decides nothing.

**R2 (both consumers, same file, same commit).** One file under `references/`
reaches the validator through `.shirabe-src` in CI and the working tree locally,
and reaches a drafting skill through `${CLAUDE_PLUGIN_ROOT}/references/`, a path
already used 71 times in `skills/*/SKILL.md` and 190 times across `skills/`
(`grep -rn 'CLAUDE_PLUGIN_ROOT}/references/'`). The file can be the prose
rulebook itself, so the skill reads the rules in the form they are written.

**R3 (instruction-file coverage).** Trivially satisfied. The format gate is
shirabe's own code and no third party can refuse a file. The prototype processed
all 211 files under `skills/`, including both files Vale rejects.

**R4 (prose scoping).** This has to be written, and the honest cost is the one
question worth answering with code rather than an estimate, so I wrote it. The
scoper handles fenced blocks with both delimiters and indent tracking, indented
code blocks, multi-line HTML comments, GFM table rows, inline code spans, link
destinations, autolinks, and bare URLs, keeps headings, and is total over
arbitrary input the way `mermaid.rs` documents itself to be. It is **122 lines
including doc comments, 90 lines of code**. Not 500.

It is also more R4-correct than Vale. On the same fixtures it drops the URL
paragraphs Vale flags, and on the real corpus it never enters frontmatter or
table rows. Against Vale's 489 per-paragraph findings across `docs/` it produces
483, agreeing on 91 of 92 files, with the per-file count differing by one or two
on 12 files from block-segmentation edge cases in nested lists. The one file
Vale flags and the prototype does not is a table row, which R4 forbids.

The existing precedent is closer than `mermaid.rs` suggests. `mermaid.rs` is 823
lines because it parses a diagram grammar. The nearer neighbours are
`section_has_prose` and `first_fence_info` at `checks.rs:316-368`, which already
do fence detection and table-row exclusion line by line inside one section. The
scoper generalizes those from a section to a document.

**R5 (accurate locations).** Needs `body_start_line` on `Doc`, set in
`parse_doc_bytes`. One field, one construction site, mechanical updates to test
constructors. The prototype demonstrates the arithmetic.

**R6 (frequency rules).** `Doc` carries what a rate needs. The body lines are
the numerator source and the denominator source, so a single pass over the
scoped spans yields both. The check signature `fn(&Doc, &FormatSpec) ->
Vec<ValidationError>` accommodates it without change: the function computes the
sums itself and emits one error at the recorded line, or one per block, or both.
The prototype does both in one pass. Nothing about the existing check shape
obstructs this; the check-lifecycle research is right that it is a new check
*shape*, but the shape fits the signature.

**R7 (frequency rule shape stated).** Free. The message is a Rust format string,
so the denominator, the observed rate, and the threshold all reach the author in
the finding text.

**R8, R10, R16 (vocabulary).** A declaration file resolved by the
`visibility.rs` ancestor-walk pattern, which is exact precedent for
"repo-local, resolvable from the file being checked, no CI wiring." Case
insensitivity is `to_lowercase()` on both sides. Non-extension to morphological
variants is exact-token matching, which is what the code does anyway. Extends
rather than replaces is the default unless someone writes the replace.

**R11 through R15.** Neutral, same as Option A.

**R18, R19 (no new dependency, no skew).** Satisfied by construction. Same
binary, same commit, no fetch, nothing added to the workflow but a flag.

**R20.** Satisfied.

**Cost.** Roughly 90 lines of scoper, 60 lines of frequency check, one `Doc`
field, a rule-file loader with three-way path resolution, a vocabulary loader,
and tests. The `regex` crate is already a direct dependency of
`shirabe-validate`, so the existing hand-rolled byte-boundary matching in FC10
can be replaced with `\b(...)\b` as a net simplification.

**What breaks.** The golden baseline. `crates/shirabe/tests/fixtures/golden/
corpus/real/BRIEF-shirabe-strategy-skill.md` carries 8 em dashes against a
byte-empty expected stdout, so any em dash rule that fires on it forces a
recapture. That cost is identical under Option A.

### Option C: split

**How it works.** Native for the validator and CI path, Vale for a local
authoring loop, or some other division of the same shape.

**R2 and R16 reject the shape by name.** R2 requires that no consumer can be
enforcing a different rule set than another at the same commit. Two engines
means two rule representations, Rust reading one format and Vale reading YAML,
unless one is generated from the other. Generating the Vale YAML at build time
reintroduces exactly the build-time embedding R1 forbids; generating it at
runtime means writing and maintaining a Vale-YAML emitter, which is more work
than the check it feeds. R16 is more direct still: "A declaration honored only
in CI does not satisfy R8: it would leave the drafting agent firing on terms the
validator has been told to ignore, which is the same split R2 exists to close
for the rule source." Option C is that split, reintroduced at the engine layer.

**It inherits every Option A defect on the half where Vale runs.** The
authoring loop is the loop that touches `skills/` most, and that is the tree
where Vale exits 2 on shirabe's own files. The vocabulary the local half honors
is the case-sensitive one. The 40 MB binary becomes a prerequisite for local
development, which is a softer version of R18 but the same category of cost.

**The value of the local half is unevidenced.** The exploration found zero
published measurements, anywhere, of a prose linter improving prose in an agent
revision loop, and shirabe already runs `shirabe validate` locally through
`shirabe install-hooks`. Whatever the native check reports in CI, the same
binary reports at the same moment locally.

**The one honest argument for C.** Vale ships a first-party Claude Code plugin
with an edit-time hook that lints prose files as an assistant writes them, plus
an LSP. That is real, already built, and shirabe has no equivalent. But it is an
authoring aid layered on top of enforcement, not an enforcement engine, and
adopting it does not require Vale to be the thing that decides whether a PR
passes. Nothing in Option B forecloses someone installing that plugin for
themselves later.

**Cost.** Strictly Option A plus Option B, plus the synchronization machinery
between the two rule representations.

## Empirical results

### Setup

```
$ /home/dgazineu/.claude/jobs/b0818094/tmp/bin/vale --version
vale version 3.17.1
```

Config at `/home/dgazineu/.claude/jobs/b0818094/tmp/d1/.vale.ini`:

```ini
StylesPath = styles
MinAlertLevel = suggestion

[*.md]
BasedOnStyles = Shirabe
```

### The per-paragraph occurrence rule

`styles/Shirabe/EmDashPerParagraph.yml`:

```yaml
extends: occurrence
message: "More than one em dash in this paragraph (%s). Use a comma, parentheses, or a colon."
level: warning
scope: paragraph
token: '—'
max: 1
```

Run over `docs/` (147 files):

```
$ time vale --no-global --config=.vale.ini --output=line <repo>/docs
real 0m0.710s   user 0m3.110s   sys 0m0.171s
$ wc -l emdash_para.txt
489
$ cut -d: -f1 emdash_para.txt | sort -u | wc -l
92
```

**489 alerts across 92 files.** The PRD cites 679 of 5,776 paragraphs at more
than one per paragraph. The rule does not reproduce that figure, and the
difference is segmentation rather than error. Reproducing the cited method (strip
frontmatter, fences, and table rows; split on blank lines) gives 654, not 679, on
this tree:

```
$ python3 count_para.py docs
files=147 paragraphs=9466 em_dashes=3025 paragraphs_over_1=654 files_with_over_1=100
```

A blank-line split treats a whole list as one paragraph; Vale treats each list
item as its own block. Two em dashes spread across two list items count as one
over-threshold paragraph under the cited method and zero under Vale. The gap
between 654 and 489 is that difference. This matters for R7: the reporting unit
is not the only choice that moves the number, the segmentation does too, and the
PRD's cited figure is not reproducible without stating which segmentation
produced it.

Message formatting, first alert, verbatim:

```
docs/briefs/BRIEF-execute-skill.md:46:29:Shirabe.EmDashPerParagraph:More than one
em dash in this paragraph (%!s(int=2)). Use a comma, parentheses, or a colon.
```

`%s` against an int count renders as `%!s(int=2)`. Switching the message to `%d`
renders `2` correctly.

### Scoping behaviour, controlled fixture

`fix/unit.md` and `fix/unit2.md` place two em dashes in each construct R4 names.
Results:

| Construct | Vale fires? | R4 requires |
|---|---|---|
| Paragraph | yes | yes |
| Heading | yes | yes (headings are prose) |
| List item | yes (each item separately) | yes |
| Blockquote | yes | yes |
| Fenced code block | no | no |
| Inline code span | no | no |
| GFM table row | no (usually; see below) | no |
| Frontmatter single-line scalar | no | no |
| Frontmatter multi-line block scalar | **yes** | **no** |
| Markdown link destination `[t](url)` | no | no |
| Bare URL | **yes** | **no** |
| Angle-bracket autolink `<url>` | **yes** | **no** |

Reporting unit confirmed: one alert per over-threshold block, carrying the
count, not one alert per excess occurrence. A paragraph with four em dashes
produces one alert reading `4`.

Auditing all 489 real findings against R4:

```
$ python3 r4_audit.py < v.txt
PROSE          476
FRONTMATTER    11
               BRIEF-lifecycle-posture-mode.md:11
               BRIEF-shirabe-charter-skill.md:20
               BRIEF-shirabe-scope-skill.md:20
TABLE_ROW      2
               DESIGN-shirabe-check-absorption.md:395
               DESIGN-shirabe-child-dispatch-contract.md:331
```

Confirmed directly for the frontmatter case:

```
$ vale --output=JSON --filter='.Name == "Shirabe.EmDashPerParagraph"' \
    docs/briefs/BRIEF-lifecycle-posture-mode.md
      "Message": "More than one em dash in this paragraph (%!s(int=2))...",
      "Line": 11
```

Line 11 of that file is inside the `outcome: |` block scalar of its YAML
frontmatter.

### Document-level rate: can Vale express it?

**`metric` cannot.** A formula naming a punctuation count fails to compile:

```
$ vale --no-global --config=.vale.ini --output=line fix/unit3.md
styles/Shirabe/EmDashMetric.yml:4:E201:Shirabe.EmDashMetric: script run:
Compile Error: unresolved reference 'em_dashes'
	at (main):1:37
EXIT=2
```

Probing each candidate variable name one at a time (`probe_metric.sh`):

```
PRESENT  words              ABSENT   em_dashes
PRESENT  sentences          ABSENT   dashes
PRESENT  paragraphs         ABSENT   punctuation
PRESENT  characters         ABSENT   chars
PRESENT  syllables          ABSENT   bold
PRESENT  complex_words      ABSENT   strong
PRESENT  polysyllabic_words ABSENT   emphasis
PRESENT  long_words         ABSENT   code
PRESENT  blockquote         ABSENT   links
PRESENT  list
PRESENT  pre
PRESENT  heading.h1
```

The `metric` namespace is exactly the readability inputs. There is no path to a
punctuation rate through it.

**`script` can, at `scope: raw` only.** `styles/config/scripts/em-dash-density.tengo`:

```go
text := import("text")
matches := []
body := text.re_replace("(?s)```.*?```", scope, "")
words := len(text.fields(body))
found := text.re_find("—", body, -1)
dashes := 0
if !is_undefined(found) { dashes = len(found) }
if words > 100 {
    per_k := float(dashes) * 1000.0 / float(words)
    if per_k > 3.0 { matches = append(matches, {begin: 0, end: 1}) }
}
```

```
$ time vale --no-global --config=.vale.ini --output=line \
    --filter='.Name == "Shirabe.EmDashDensity"' <repo>/docs
real 0m0.424s   user 0m1.859s   sys 0m0.172s
$ wc -l density.txt
104
```

**104 of 147 files**, matching the research file's 104 of 145. Findings land at
line 1, column 1. `math` and `fmt` are both importable in the sandbox, which the
rule-translation research left unverified.

**At any markup scope a script is per-block and never sees the document.**
Instrumenting a script at `scope: text` to report what it receives:

```
"Message": "BLOCK words=1 dashes=0 text=\"prd/v1\""
"Message": "BLOCK words=3 dashes=1 text=\"col — a\""
"Message": "BLOCK words=5 dashes=1 text=\"Heading with — one dash\""
"Message": "BLOCK words=8 dashes=1 text=\"A paragraph with one — em dash only.\""
"Message": "BLOCK words=9 dashes=2 text=\"A blockquote with two — em dashes — inside.\""
"Message": "BLOCK words=10 dashes=2 text=\"A paragraph with two — em dashes — in it.\""
"Message": "BLOCK words=11 dashes=2 text=\"A list item with two — em dashes — in it.\""
"Message": "BLOCK words=12 dashes=4 text=\"A paragraph with four — em — dashes — in — it.\""
```

One invocation per block, with only that block's text. Note it also hands the
script frontmatter values and table cells. There is no scope at which a Vale
script receives markup-aware whole-document text.

**A script can carry a computed value.** Undocumented, verified: a `matches`
entry may set a `message` key that overrides the rule's `message`.

```json
{ "Span": [1, 5], "Check": "Shirabe.ProbeMsg", "Message": "rate=7.84",
  "Severity": "warning", "Match": "# Hea", "Line": 1 }
```

So R7's requirement that the finding name the rate is satisfiable. The `Match`
field is meaningless for a document-level finding.

**What `scope: raw` costs against R4.** The script's own fence stripping is all
the scoping it has. Comparing that rate against a fully prose-scoped one
(`rate_compare.py`):

```
corpus raw:   3127 dashes / 445716 words = 7.02 per 1000
corpus prose: 3023 dashes / 402880 words = 7.50 per 1000

threshold >3.0/1000   raw=104  prose=104   verdict disagreements: 0
threshold >5.0/1000   raw= 84  prose= 89   verdict disagreements: 7
threshold >8.0/1000   raw= 69  prose= 72   verdict disagreements: 7
threshold >10.0/1000  raw= 46  prose= 57   verdict disagreements: 11
threshold >12.0/1000  raw= 28  prose= 32   verdict disagreements: 8
threshold >15.0/1000  raw= 11  prose= 15   verdict disagreements: 6

largest per-file rate divergence (raw vs prose):
  DECISION-lifecycle-strict-mode-interface-2026-06-06.md raw=18.05 prose=21.41
  DESIGN-work-on-definition-of-done.md                   raw=19.54 prose=22.37
  DESIGN-populate-issueless-default.md                   raw=14.08 prose=16.76
```

Stated honestly: at the 3-per-thousand threshold the PRD uses for its impact
figures, the R4 gap flips no verdicts. At the 10-to-15 range the check-lifecycle
research recommends for a cleanable first release, it flips 6 to 11 files, which
is a fifth to a quarter of the failing set. The R4 argument against the raw
script is threshold-dependent and should not be overstated.

### Instruction-file coverage (R3)

```
$ vale --no-global --config=.vale.ini --output=line <repo>/skills
<repo>/skills/review-plan/SKILL.md:1:E201:yaml: line 3: mapping values are not
allowed in this context
EXIT=2
findings: 0
```

Zero findings across 211 files. Passing the file list explicitly, the way
`validate-docs.yml:88-100` does, gives the same result. Isolating which files
Vale refuses:

```
=== C: how many skill files does Vale refuse? ===
  <repo>/skills/review-plan/SKILL.md
  <repo>/skills/writing-style/SKILL.md
  total refused: 2 of 211
```

The offending frontmatter, `skills/review-plan/SKILL.md:1-6`:

```yaml
---
name: review-plan
description: Adversarial plan review skill. Challenges a complete plan artifact across
  four categories before issues are created: Scope Gate (A), Design Fidelity (B), AC
  Discriminability (C), and Sequencing/Priority Integrity (D). ...
```

Excluding both files, Vale runs clean on the remaining 188:

```
linting 188 of 211 skill files
EXIT=0  errors=0
per-paragraph=106  density=83
--- native, same file set ---
files=188 prose_words=144327 em_dashes=1014 rate=7.03 docs_over_3per1000=79 blocks_over_1=106
```

Per-paragraph findings agree exactly (106 and 106). The density counts differ by
four files, which is the raw-versus-prose scoping divergence above.

### Script robustness

A script returning a span outside the scope text:

```go
matches := []
matches = append(matches, {begin: 100000, end: 100001})
```

```
$ vale --no-global --config=.vale.ini --output=line fix/unit.md
EXIT=2
panic: runtime error: slice bounds out of range [:100001] with length 612
goroutine 67 [running]:
github.com/errata-ai/vale/v3/internal/check.Script.Run(...)
--- findings ---
0
```

Unrecovered Go panic, exit 2, no findings. Contrast the stated contract of
shirabe's own extractor at `crates/shirabe-validate/src/mermaid.rs:1-14`: "total
over arbitrary line input, malformed inputs surface as `Issue` values, never
panics."

### Vocabulary semantics (R8)

`styles/Shirabe/Words.yml` is the seven-word FC10 list as an `existence` rule.
Fixture: `A tier of work, and Tier 4 specifically, plus a tiered rollout.` /
`This is a robust and comprehensive approach we can leverage.`

```
=== accept.txt entry: tier ===
'Tier' 'tiered' 'robust' 'comprehensive' 'leverage'
=== accept.txt entry: [Tt]ier ===
'tiered' 'robust' 'comprehensive' 'leverage'
=== accept.txt entry: (?i)tier ===
'tiered' 'robust' 'comprehensive' 'leverage'
=== accept.txt entry: Tier ===
'tier' 'tiered' 'robust' 'comprehensive' 'leverage'
```

Declaring `tier` leaves `Tier` firing. R8 requires the opposite in as many
words: "Matching SHALL be case-insensitive, so a declared `tier` suppresses
`Tier`." The regex forms work. The morphology half is right in every case:
`tiered` keeps firing, which R8 also requires. Every other rule stays active,
so the term-scoped requirement is met.

### The native prototype

Written to size Option B's R4 cost honestly rather than estimate it. Source at
`/home/dgazineu/.claude/jobs/b0818094/tmp/d1/proto/src/main.rs`, line-oriented
over `Vec<String>` body lines, `regex` and `std` only, in the shape `checks.rs`
already uses. The scoper is delimited by markers:

```
$ awk '/PROSE-SCOPER-BEGIN/,/PROSE-SCOPER-END/' proto/src/main.rs > scoper.txt
total lines between markers: 122
non-comment non-blank: 90
```

**90 lines of code.** On the same fixtures Vale saw:

```
$ ./proto detail fix/unit.md fix/unit2.md fix/unit3.md
fix/unit.md:10: BLOCK 2 em dashes      <- Vale: 10
fix/unit.md:12: BLOCK 4 em dashes      <- Vale: 12
fix/unit.md:14: BLOCK 2 em dashes      <- Vale: 14
fix/unit.md:15: BLOCK 2 em dashes      <- Vale: 15
fix/unit.md:17: BLOCK 2 em dashes      <- Vale: 17
fix/unit.md:27: BLOCK 2 em dashes      <- Vale: 27
fix/unit2.md:8: BLOCK 2 em dashes      <- Vale: 8
                                       <- Vale: 10  (bare-URL paragraph, R4 violation)
fix/unit2.md:14: BLOCK 2 em dashes     <- Vale: 14
fix/unit3.md:1: BLOCK 2 em dashes      <- Vale: 1
                                       <- Vale: 5, 7  (URL paragraphs, R4 violations)
```

Identical except where Vale violates R4. Over the whole corpus:

```
$ time xargs -a abs.txt ./proto summary
files=147 prose_words=395208 em_dashes=2990 rate=7.57 docs_over_3per1000=104 blocks_over_1=483
real 0m0.071s
```

Against Vale's 489 and 104, per file:

```
native files with findings: 91
vale   files with findings: 92
--- per-file count disagreements (file native vale) ---
DESIGN-lifecycle-passing-state-validation.md  1  2
DESIGN-lifecycle-posture-mode.md              6  5
DESIGN-shirabe-check-absorption.md      MISSING  1
DESIGN-shirabe-scope-skill.md                11 13
DESIGN-transition-script-consolidation.md     4  5
DESIGN-work-on-definition-of-done.md          2  1
execute-friction.md                           5  4
PRD-populate-issueless-default.md             2  3
PRD-roadmap-issueless-table-rendering.md      4  5
PRD-scope-consolidation-over-skipping.md      3  4
PRD-shirabe-scope-skill.md                   10  9
PRD-skill-cascade-lifecycle-check.md          2  4
```

Twelve files differ by one or two, from block segmentation in nested lists. The
single file Vale flags and the prototype does not is
`DESIGN-shirabe-check-absorption.md:395`, which is a table row.

### Timing

| Invocation | Vale | Native |
|---|---|---|
| `docs/` as a directory argument, 147 files | 0.75-0.77 s | n/a |
| 147 explicit paths (how `validate-docs.yml` invokes) | 2.38-2.53 s | 0.06-0.07 s |
| Single file | 0.02-0.03 s | under 0.01 s |

Latency is not a constraint for either. Note Vale is roughly three times slower
when handed explicit paths than when handed a directory, and CI hands it explicit
paths.

### Adopter cost (R18)

```
$ curl -sIL .../vale_3.17.1_Linux_64-bit.tar.gz
http=200
content-length: 11004294
$ time curl -sL -o vale.tgz .../vale_3.17.1_Linux_64-bit.tar.gz
real 0m6.886s
$ ls -la vale
-rwxr-xr-x 1 dgazineu dgazineu 40422656 Aug  5 13:02 vale
```

10.5 MB tarball, 40 MB binary, 6.9 s to download here and probably 1-3 s on a
runner with better bandwidth. Small next to the 50-90 s cargo build the workflow
already pays. **Wall time is not the objection.** The objection is that
`validate-docs.yml` currently contains no install, fetch, download, or
package-manager step for anything but the Rust toolchain and cargo, and the
acceptance criterion forbids adding one.

On the `pr-body.yml` question: it carries an identical `.shirabe-src` checkout,
toolchain, cache, and `cargo build` block (lines 95-130), and its callers have
no `paths:` filter, so it runs on every PR in koto, niwa, and tsuku. It does not
lint prose files, so a Vale step would not belong in it. The exposure is
conditional: if the install were factored into a shared composite action rather
than added as a step inside `validate-docs.yml`, every PR in three repos would
pay it. That is an avoidable mistake, not an inherent cost.

### Repo precedent

`check_fc08_introduces_no_new_dependency` at `checks.rs:5636` is a structural
test whose body is a single call with a discarded result. Its comment states the
intent: FC08 "uses only `std::collections::HashSet`, `regex` (already in
workspace deps), and the existing mermaid extractor infrastructure. No new
external crate is imported in checks.rs for FC08." It is about Rust crates, not
external binaries, and it does not mechanically detect anything. It is evidence
of a value rather than an enforcement of one.

The CLAUDE.md "CLI Surface" section forbids CLI subcommands that render or
create an artifact body. A prose linter consumes a body and emits
`(code, severity, message, file, line)`. It lands on the `validate` side and the
rule does not bar it, which the exploration already concluded.

**The `gh` and `git` comparison, both sides.**

For Option A: shirabe already spawns external binaries from inside the
validator. `gh.rs:393` and `gh.rs:537` shell out to `gh`; `transition.rs`,
`finalize.rs`, and `checks.rs:804` shell out to `git`. FC09 has an
auth-probe-and-skip degradation path (`probe_auth` at `gh.rs:536`). A third
binary is not a category change, and the plumbing pattern exists.

Against: `gh` and `git` are I/O oracles. They report remote issue state and the
git index, which are facts the validator cannot compute from the file in front of
it at any price. Vale would be spawned to compute a function of a string the
validator already holds in memory. That is the distinction, and it is not a
stylistic one. Two consequences follow. First, both `git` and `gh` are
preinstalled on every GitHub-hosted runner and on any machine plausibly doing
this work, which is why neither ever needed an install step, and which is exactly
what R18 is about. Second, shirabe's own handling of them is not a precedent an
advocate should want: `checks.rs:804` calls
`git ls-files --error-unmatch` and does `.unwrap_or(false)`, so a missing `git`
turns into an R6 error-level finding that the upstream is untracked. The repo has
one graceful degradation and one fail-closed-into-a-false-error, and the second
is the more recent shape.

### The measured-value question

The exploration measured Vale's word and phrase engine at roughly two true
positives across 554,000 words, 1.7% raw precision on the word rules, and found
the one defect worth catching is frequency. So: what does Vale's rule engine buy
that a native implementation would not, given that the valuable rule is a
counter?

Answer, from the measurements above rather than from reputation: markup-aware
scoping, for the rules where it applies, and a vocabulary mechanism. Both are
real. Neither survives contact with this requirement set. The markup awareness
is unavailable for the document-level rate, which must run at `scope: raw`, and
it is 2.7% wrong on the per-paragraph rule where it is available. The vocabulary
is case-sensitive where R8 requires case-insensitive. And the per-paragraph rule
that markup awareness does serve is reproduced natively to within 6 findings in
489 and 1 file in 92, by 90 lines of code that gets the three R4 edge cases right
that Vale gets wrong.

The rule engine itself, the twelve check types and the package ecosystem, buys
nothing measurable here. The exploration already established that off-the-shelf
styles produce 169 alerts in 1,636 words on shirabe's `CLAUDE.md`, several of
which demand changes that would break the validator's own FC-CONVENTIONS parse.
The style would be hand-written from shirabe's rulebook either way, which means
the question was never "Vale's rules versus ours." It was "Vale's engine versus
90 lines," and the engine cannot express the one rule that matters without
turning itself off.

## Recommendation

**Option B: a widened native check compiled into `shirabe-validate`, reading
its rules and vocabulary from files at enforcement time.**

Three findings decide it, in descending order of how hard they are to argue
with.

R18 and its acceptance criterion forbid Option A outright. Every route to
putting a 40 MB binary on an adopter's runner is an install, fetch, download, or
package-manager step, and the criterion names all four. This is not a
cost-benefit judgment that a fast download can win.

R3 fails on shirabe's own tree. Vale exits 2 with zero findings across 211 skill
files because two of them carry frontmatter its YAML parser rejects, and R3
exists precisely to cover that file class. It is fixable by invoking Vale
per-file and tolerating errors, but the fix means shipping a checking surface
that reports success for files it could not read, which is the exact failure mode
R12a exists to end.

R4 and R6 are mutually exclusive under Vale. `metric` has no punctuation
variable and a `script` sees whole-document text only at `scope: raw`. The one
rule carrying the empirical case for this whole capability is the one rule for
which Vale's best feature is switched off, and the scoping has to be rewritten
in Tengo, without lookaround, on a runtime that panics on an out-of-range span.

**The strongest counter-argument, stated fairly.** You are reimplementing a
mature, well-tested, markup-aware linter with a real Markdown parser behind it,
and shirabe's own FC10 is the cautionary tale for exactly this: a hand-rolled
matcher that fires inside code fences and URLs and reports line numbers off by
the frontmatter length. Hand-writing Markdown scoping is how you get FC10 again,
and a 90-line prototype validated on one corpus is not evidence that the
production version stays 90 lines once nested fences, reference links, HTML
blocks, and setext headings arrive.

**The answer.** The counter is right about the risk and wrong about the size,
and it misidentifies FC10's failure. FC10 does not fire inside code fences
because its scoping was attempted and failed; it fires there because it iterates
`doc.body` raw and attempts no scoping at all. The measured cost of attempting it
is 90 lines, and the result agrees with Vale on 483 of 489 paragraph findings and
91 of 92 files while being more R4-correct than Vale in the three places Vale
violates R4 on this corpus. The precedent is not `mermaid.rs` and its 823-line
diagram grammar; it is `section_has_prose` and `first_fence_info`, which already
do fence detection and table-row exclusion line by line, and which the scoper
generalizes from a section to a document.

More decisively, Vale does not discharge the obligation. Adopting it means
writing the prose scoper anyway, in Tengo, with Go standard-library regex and no
lookaround, for the one rule that carries the case, on a runtime that crashes
rather than degrades. Option A buys the scoper you do not need and charges you a
forbidden dependency for it. The right reading of the FC10 lesson is not "do not
write scoping," it is "do not skip it," and the correct response to a risk of
under-testing is the test surface the PRD already specifies in its acceptance
criteria, which is engine-independent.

The one thing Option A does better and Option B should copy rather than lose:
Vale's `Vocab` design is genuinely the right shape for R8, R10, and R16, and the
native declaration should be modelled on it, term-scoped, additive, resolved from
the file under check, with the case-sensitivity fixed.

## Confidence

**High.**

The two blocking findings are not judgment calls. R18's acceptance criterion
names the exact four words that describe every way of obtaining Vale, and the
metric-versus-script incompatibility with R4 was established by probing Vale's
variable namespace and instrumenting a script to report its own scope rather than
by reading documentation. The R3 abort was reproduced on shirabe's committed
files, isolated to two of 211, and confirmed to persist when files are passed
explicitly the way CI passes them.

The cost estimate that decides the close half of the argument was measured by
building the thing and diffing its output against Vale's on the real corpus, not
estimated. 90 lines, 483 findings against 489, 91 files against 92.

What would move me. Two of the three findings are salvageable by an advocate.
R3's abort could be worked around with per-file invocation and error tolerance,
at the cost of a surface that silently skips files. R8's case-sensitivity is a
documented regex workaround. If R18 were relaxed, if an adopter-visible install
step were acceptable, Option A would become a real contest and the deciding
question would shift to whether Vale's per-paragraph markup awareness is worth
losing R4 compliance on the document rate. It is not, but that is a closer call
than the one in front of us. R18 is not relaxed, and it is the requirement that
cannot be argued around.

The residual uncertainty in the recommendation is scope creep in the native
scoper, not correctness. Setext headings, reference-style links, and raw HTML
blocks are all constructs this corpus barely uses and a future one might. That is
a maintenance risk, it is bounded by the same acceptance criteria either option
must pass, and it does not change which option is buildable under R18.
