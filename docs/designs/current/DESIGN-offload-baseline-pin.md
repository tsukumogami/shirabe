---
schema: design/v1
status: Current
problem: |
  shirabe needs a fixed starting point before anything changes what its four
  koto-templated skills load: an identity for each template that a run record
  and shirabe's history can both match, a per-skill instruction-token count
  anyone can re-run at any commit, and a written definition of a rule's
  preloaded rate. The declared template version can't serve, since it never
  moves, and editing it would itself change what runs load.
decision: |
  A new docs/measurement/offload-baseline/ directory holds a JSON template pin
  (per template: git blob hash, koto compile hash and the koto version behind
  it), a TSV load manifest naming every file or template state each skill
  profile loads with its expected loads per run, the recorded token figures at
  the pinned commit and at e592501, and a README carrying the provisional
  preloaded-rate definition keyed by rule source location. One bash script,
  scripts/offload-baseline.sh, verifies the pin and re-runs the count from git
  objects at any commit; its test runs in a new CI workflow.
rationale: |
  Content hashes identify templates without touching them, and the koto hash
  is the one a run record already carries. Reading from git objects makes the
  count reproducible at any commit without a checkout. Recording the census's
  load weights as data, instead of re-deriving the census's row-level
  judgments, keeps the recount mechanical. Keeping everything outside
  skills/ and references/ guarantees no run loads it.
decision_provenance: inline-resolved
upstream: docs/prds/PRD-offload-baseline-pin.md
---

# DESIGN: offload-baseline-pin

## Status

Current

The architecture, security and structural-format reviewers all passed it.
The definitions in Solution Architecture stay provisional after acceptance.

## Context and Problem Statement

The requirements are in
[PRD-offload-baseline-pin](../../prds/PRD-offload-baseline-pin.md). This design
settles four things the PRD leaves open: how a template's identity is
recorded, where the baseline lives and in what form, how the token count is
computed so it can be re-run, and the proposed preloaded-rate definition with
its counting rules.

Three facts about the code shape the answers.

- The five templates (`skills/work-on/koto-templates/work-on.md`,
  `skills/execute/koto-templates/execute.md` and `execute-coordinated.md`,
  `skills/scope/koto-templates/scope.md`,
  `skills/deliver/koto-templates/deliver.md`) all declare `version: "1.0"`.
- koto reports a `template_hash` on every session (`koto status`). It's the
  sha256 of the compiled template, `koto template compile <file>` prints the
  compile-cache path named by that hash, and the hash doesn't depend on the
  source file's path. Compiling `deliver.md` from 175fb30 and from e592501
  gives the same hash, `f305c947...21ad`, because that file didn't change
  between them.
- A template file is YAML frontmatter followed by one `## <state>` section
  per state. koto returns a state's section as its directive, and delivers
  the text below a `<!-- details -->` marker only on arrival.

## Decision Drivers

- Nothing a run loads may change (PRD R10), which rules out any edit to
  templates, skill files or references, version bumps included.
- A later measurement has to select runs by template, and the only template
  identity a run record carries is koto's `template_hash`.
- The count has to give identical numbers when re-run at the same commit
  (PRD R8), so it can't depend on judgment, a network service, or the working
  tree.
- The definitions are proposals for review and will change (PRD R6), so they
  belong in one place, with each choice's alternative beside it.
- The tooling stays small and runs under bash 3.2 (PRD R12).

## Considered Options

### Decision 1: How a template's identity is recorded

**Chosen: content hashes, two of them.** Each pin entry records the git blob
hash of the template at the pinned commit and koto's compile hash of the same
text, with the koto version that produced it. The blob hash is what shirabe's
history matches and doesn't depend on koto. The compile hash is what a session
record carries, so it's the key a later measurement filters on.

*Alternative: bump the declared `version:`.* Rejected. It edits the files
runs load, which is exactly what this work must not do, and it only works if
every later editor remembers to bump it.

*Alternative: record the commit only.* Rejected. A commit identifies the
repository state, but a run record names a template hash, not a commit, and
most commits leave most templates unchanged, so a commit-keyed baseline would
treat identical templates as different versions.

*Alternative: the koto hash only.* Rejected. A koto release that changes
compiled output changes the hash with no change in shirabe. Keeping the blob
hash beside it lets a reader tell those two cases apart.

### Decision 2: Where the baseline lives and in what form

**Chosen: `docs/measurement/offload-baseline/`**, holding `template-pin.json`,
`load-manifest.tsv`, `token-baseline.tsv` and a `README.md` with the method,
the figures and the definitions. The directory is outside `skills/` and
`references/`, so no run loads it, and it's where a reader looks for
documentation.

*Alternative: one markdown file under `docs/specs/`.* Rejected. The pin and
the manifest have to be machine-readable for the script, and markdown tables
parsed by a shell script are brittle. `docs/specs/` also holds format
contracts that skills consume, which this isn't.

*Alternative: data beside the script under `scripts/`.* Rejected. It hides
the definitions, the part a reviewer most needs to read, among CI tooling.

### Decision 3: How the token count is computed

**Chosen: a load manifest with fixed weights, counted from git objects.**
Each manifest row names a profile, a path, a selector (the whole file, the
file without its YAML frontmatter, or one template state's section) and a
weight: expected loads per run, taken from the September census's load model.
Tokens are bytes divided by 4, as in the census. Raw tokens count each
distinct span once; weighted tokens multiply each row by its weight. The
script reads every span from git objects (`git cat-file blob <commit>:<path>`), so it never touches
the working tree and gives the same figures at the same commit every time.

*Alternative: re-derive the census row by row.* Rejected. The census's rows
carry judgments (kind, verdict, what counts as one instruction) that two
people wouldn't reproduce identically, and the token baseline needs none of
them.

*Alternative: a real tokenizer.* Rejected. It ties the count to one model's
vocabulary and usually to a network call, and it wouldn't be comparable with
the census's bytes/4 figures.

*Alternative: measure load weights from recorded runs each time.* Rejected
for now. It needs a transcript-parsing pipeline, which the PRD puts out of
scope; the weights are data in the manifest, so a later refresh changes one
column.

### Decision 4: The preloaded-rate definition

**Chosen: per-opportunity, observed at first production.** The full proposal,
with every counting rule and its alternative, is in Solution Architecture
under "Preloaded rate". In short: an opportunity is one production of an
output the rule governs while the rule is in the agent's default context; a
violation is that output breaking the rule when it's first produced, before
any check or reviewer feeds back; the rate is violated opportunities over
checkable opportunities, in runs of a pinned template.

*Alternative: per run.* Rejected as the default. A run that writes four PR
bodies and breaks the rule once would count the same as one that breaks it
four times, and the offload comparison needs to see the difference.

*Alternative: observed at the final output.* Rejected. The final output has
been through checks and review, so it measures the whole loop rather than
how well a preloaded rule was followed, which is the number the offload
target halves.

## Decision Outcome

The baseline is a data directory plus one script. The pin identifies each
template twice, by git blob and by koto compile hash. The count is a
manifest-driven sum over git objects, reproducible at any commit that has the
listed files and states. The preloaded-rate definition lives in the
directory's README, keyed by rule source location, marked provisional
throughout, with each counting rule's alternative stated. Together they give
a later change a fixed starting point without editing anything a run loads.

## Solution Architecture

### Files

| Path | Holds |
|------|-------|
| `docs/measurement/offload-baseline/README.md` | What the baseline is, the pinned commit, the recount method, the figures, and the provisional preloaded-rate definition |
| `docs/measurement/offload-baseline/template-pin.json` | The template pin |
| `docs/measurement/offload-baseline/load-manifest.tsv` | What each profile loads, and how often |
| `docs/measurement/offload-baseline/token-baseline.tsv` | Recorded figures per profile and commit, plus the September census reference |
| `scripts/offload-baseline.sh` | `verify-pin` and `count <commit>` |
| `scripts/offload-baseline_test.sh` | Tests for both subcommands |
| `.github/workflows/check-offload-baseline.yml` | Runs the tests |
| `scripts/check-bash-floor.sh` (edited) | Registers the suite for the bash 3.2 floor job |

### Template pin

```json
{
  "pinned_commit": "<full sha on main>",
  "koto_version": "0.14.1",
  "templates": [
    {
      "skill": "deliver",
      "path": "skills/deliver/koto-templates/deliver.md",
      "declared_name": "deliver",
      "declared_version": "1.0",
      "git_blob": "<sha1>",
      "koto_template_hash": "<sha256>"
    }
  ]
}
```

`koto_version` sits at file level because one koto computes every hash in a
pin. One entry per template under `skills/{work-on,execute,scope,deliver}/koto-templates/*.md`
at the pinned commit, `*.mermaid.md` excluded (they're diagrams, not
templates): five entries.

`verify-pin` checks, reporting each failure by entry and exiting non-zero if
any fails:

1. The file parses and every entry has all six fields.
2. `pinned_commit` resolves to a commit.
3. The set of paths equals the set of templates at that commit, so both a
   stray entry and a missing one fail.
4. Each entry's `skill` equals the `skills/<skill>/` directory of its path.
5. `git_blob` equals `git rev-parse <commit>:<path>`.
6. `declared_name` and `declared_version` equal the template's frontmatter.
7. When `koto version` reports the pinned `koto_version`, the entry's
   `koto_template_hash` equals the basename of what `koto template compile`
   prints for the file extracted from the commit into a temporary directory.
   Otherwise, including when koto isn't installed, it prints that the
   comparison was skipped and why, and doesn't fail on it.

### Load manifest and the count

Tab-separated, one row per loaded span:

```
profile         path                                         selector          weight  note
work-on         skills/work-on/SKILL.md                      body              1       resident
work-on         skills/work-on/koto-templates/work-on.md     state:implementation  2.25  visits per run
```

Selectors:

- `file`: the whole file.
- `body`: the file after its leading YAML frontmatter block.
- `state:<name>`: in a template, from the `## <name>` heading after the
  frontmatter to the next `## ` heading or the end of the file.

Profiles, matching the census's run models:

| Profile | Run it models |
|---------|---------------|
| `work-on` | One complete issue-backed code run |
| `execute-single-pr` | /execute's own load in a single-pr run, excluding each child's /work-on load |
| `execute-coordinated` | /execute's own load in a coordinated run |
| `scope` | A typical public-repository run through all four hops with one review round; main-context loads only |
| `deliver` | /deliver's own files, excluding the /scope and /execute runs it starts |

`count <commit> [--manifest <file>]` resolves the commit, reads each row's
span from git objects, and prints per profile the raw and weighted tokens.
Raw sums the bytes of each distinct (path, selector) once; weighted sums
bytes times weight. Each total is divided by 4 and rounded to the nearest
integer once, at the end, so rounding doesn't accumulate per row. A missing
commit, a missing path, or a missing state is an error naming it, and nothing
is printed on stdout. The script never writes to the working tree; the only
temporary files are under `mktemp -d`, removed on exit.

The manifest is built by reading, at the pinned commit, what each skill's
SKILL.md and directives tell the agent to load, following the census's load
tables for which files load in which state. The same manifest is run at
e592501; every file and state it lists exists there, so one manifest serves
both recorded commits. A later commit that drops a listed file or state makes
`count` fail by name, and the manifest is updated with the change that caused
it.

The census's load model isn't in the repository, so the weights enter the
manifest as data with their provenance in the `note` column: `resident` (1,
loaded once), `visits` (mean visits per state the census measured in recorded
runs, such as 2.25 for `implementation`), `reread` (1 plus 0.5 per return to
the state), `conditional` (a probability the census assigned), and
`failure-only` (0.05, for text koto shows only when a default action fails).
Where the census gives a profile total but no per-state figure, the row
carries 1 and says so. The README lists every weight that isn't 1.

### Recorded figures

`token-baseline.tsv` has one row per (commit, profile) with `raw` and
`weighted`, for the pinned commit and for e592501, plus rows with commit
`census-2026-09` and source `census-quoted` carrying the September figures
as the census published them. Those are quoted reference values, not
measurements: the census counted hand-split instruction rows at e592501, bytes
divided by 4, weighted by expected loads per run. `scripts/offload-baseline.sh
check-figures` regenerates every recount row and checks the README's figures
table against them; the quoted rows are the one exception, and the e592501
recount beside them makes the gap checkable. The README states why the two
differ: the census counted instruction rows and left out rationale prose in
places, while the recount counts whole spans.

### Preloaded rate (provisional)

Everything in this section is provisional, as version `provisional-1`. A later
measurement-definitions effort, shared with other measurement work, settles
it, and the baseline may move when it does. Each rule below names the
alternative it was chosen over.

- **Rule.** A rule is keyed by its source location at the pinned commit:
  `<path>#L<start>-L<end>` for a line range, or `<path>#<heading text>` for a
  whole section. When a rule registry gives rules ids, each key maps to one id
  and stays on the record as provenance. No id format is defined here.
  *Alternative:* key by census row number; rejected because row numbers exist
  only in a document outside the repository.
- **Opportunity.** One production, in a run, of an output the rule governs
  (a PR body, a commit message, a document section, a submitted evidence
  value), in a state where the rule is in the agent's default context. An
  output is produced when a tool call first writes it somewhere outside the
  agent's reply: to disk, to git, to GitHub, or to koto. Drafts revised
  before that write aren't visible and aren't counted, and each distinct
  output (each PR, each commit, each document) is one opportunity however
  often it's rewritten later. For a rule that governs an action rather than
  an output (passing `--no-cleanup` on every root tick, naming a branch,
  running a check before committing, never skipping hooks with
  `--no-verify`), an opportunity is one occurrence of the governed action
  (one tick, one commit, one push), observed from the tool call itself.
  *Alternative:* one per run; rejected because it hides repeat violations.
  Leaving action rules out was also considered and rejected: they would all
  land in `not-checkable`, and they include some of the most frequent slips,
  branch naming among them.
- **Violation.** The output breaks the rule as decided by the rule's check: a
  script where one exists, otherwise a grader or a human reading against the
  rule's text. *Alternative:* count only script-detected violations; rejected
  because most rules have no script yet, and the baseline would cover only
  them.
- **Observation point.** The first time the output is written (the first
  `gh pr create`, the first commit, the first evidence submission), before
  any check, gate retry or reviewer has fed back on it. *Alternative:* the
  final output; rejected because it measures the review loop, not the
  preloaded rule. The preloaded rate is defined as one of a pair. Its
  offloaded counterpart, the rate for a rule withheld from default context,
  is observed at the first production after the rule's text has been
  delivered once. The counterpart isn't computed here; naming the pair now
  keeps a later feature from measuring the two rates at inconsistent
  points.
- **Numerator.** Opportunities with at least one violation of the rule.
  *Alternative:* the count of violations; rejected because one output can
  break a rule in many places, and a rate above 1 isn't a rate.
- **Denominator.** Checkable opportunities for the rule: those where the
  check could reach a verdict. Opportunities it couldn't judge are counted
  separately as `not-checkable` and reported beside the rate.
  *Alternative:* all opportunities, treating unjudged ones as complied;
  rejected because it understates the rate by however much went unchecked.
- **Population.** Runs whose session `template_hash` equals a
  `koto_template_hash` in the pin. A run of any other template text is a
  different version, even with the same declared version.
  *Alternative:* runs in a date window; rejected because a window mixes
  template versions whenever a change lands inside it.
- **Early-ending runs.** A run that ends before producing an output
  contributes no opportunity for it; one that produced the output counts,
  whatever happened afterwards. *Alternative:* drop incomplete runs entirely;
  rejected because a run abandoned after a bad PR body still broke the rule.
- **Attribute names.** A measurement record carries: `definition.version`,
  `rule.source`, `rule.source_commit`, `skill`, `template.path`,
  `template.git_blob`, `template.koto_hash`, `state`, `run.id`,
  `opportunity.index`, `opportunity.outcome` (`complied`, `violated`,
  `not-checkable`) and `observed_by` (`script`, `grader`, `human`).
  *Alternative:* flat snake_case names; rejected because dotted groups keep
  rule, template and opportunity fields apart when records are merged with
  other measurement data.

The preloaded rate for rule *r* is numerator over denominator, across the
population.

Three items are flagged for reconciliation with the later
measurement-definitions effort that other measurement work shares. They stay
as written until then:

- the attribute names, including the dotted namespace;
- `run.id`, and what identifies a run across the records that effort merges;
- `rule.source`, keyed by source location, against the opaque rule id that
  koto's gate events will carry.

### Public-content check

The test suite greps the files this change adds for the patterns the PRD's
boundary criterion names. Repository references are checked against an
allowlist rather than a list of private names, so no private name has to be
written down anywhere: every `tsukumogami/<repo>` reference must name one of
the organization's public repositories (`shirabe`, `koto`, `tsuku`, `niwa`,
`dot-niwa`, `.github`). Home-directory prefixes (`/home/` or `/Users/`
followed by a name, and `~/.`) and the session, instance and job identifier
shapes (`session_` followed by an id, an instance name ending in `-` and
eight hex digits, and `jobs/` followed by eight hex digits) are matched by
pattern.

## Implementation Approach

1. **Script and tests.** Write `scripts/offload-baseline.sh` with
   `verify-pin` and `count`, and `scripts/offload-baseline_test.sh` covering
   every failure the PRD's criteria list, against fixtures built in a
   temporary git repository so the tests don't depend on shirabe's history.
2. **Pin and manifest.** Generate `template-pin.json` at the pinned commit
   and build `load-manifest.tsv` from the skills' load instructions and the
   census's load model.
3. **Figures and README.** Run `count` at the pinned commit and at e592501,
   record both with the September reference in `token-baseline.tsv`, and write
   the README: method, figures, the difference between the recount and the
   census, and the provisional definition.
4. **CI.** Add `.github/workflows/check-offload-baseline.yml`, running the
   tests on Linux, and register the suite in `scripts/check-bash-floor.sh`
   so the bash 3.2 floor job runs it the way it runs the template suites,
   plus a job that runs `verify-pin` and
   `count` against shirabe's own history (`fetch-depth: 0`) and diffs the
   output with `token-baseline.tsv`.

One pull request carries all four; none is useful without the others.

## Security Considerations

The script reads git objects and writes only to a `mktemp -d` directory it
removes on exit, so it can't alter the working tree. Commit and path
arguments come from the manifest or the command line and are passed to git
as single quoted arguments after `--` where git accepts it, never through
`eval`. A commit argument that starts with `-` is refused, and the rest are
resolved with `git rev-parse --verify --end-of-options <arg>^{commit}`
before use, so no argument can be read as a git option. The CI workflow
runs on `pull_request` (not `pull_request_target`) with `contents: read`
permission only, so a pull request that edits the script runs it without
access to secrets or write tokens. The public-content check is part of the
standing test suite and re-scans the baseline directory on every run, not
only this change's diff. `koto template compile` runs on text extracted
from a commit in shirabe's own history, the same text koto already compiles
for every run. The committed documents are checked for private names and
local paths by the test suite. No credentials, network calls or elevated
permissions are involved.

## Consequences

**Positive.** A later change can state its effect on instruction tokens per
skill by running one command, and a later measurement can select runs by the
template hash its records already carry. The definitions are in one file,
provisional, with alternatives, so settling them is an edit rather than a
migration.

**Negative.** The manifest is hand-built, so a skill that starts loading a
new file isn't counted until someone adds a row. The weights are fixed
inputs, so a change that alters how often a state is visited doesn't show in
the weighted figure until they're refreshed. Line-range rule keys drift once
the file is edited.

**Mitigations.** The README says how to add a row and refresh weights. Rule
keys carry the pinned commit, so they stay resolvable with `git show` after
the file moves on, and the rule registry replaces them.
