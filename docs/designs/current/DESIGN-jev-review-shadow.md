---
schema: design/v1
status: Current
problem: |
  shirabe wants to know whether a unanimous pass from Jev, the typed decision
  model koto calls as its decider, agrees often enough with a clean review
  panel that a pass could someday stand in for one. Nothing records the two
  verdicts side by side. The trial needs criteria drawn from what panels
  actually block on, a way to cut a real pull request into slices inside the
  2,560-byte bound the accuracy spike measured, a record a cost model and a
  measurement effort can both read, and a report that makes the uncovered
  share of panel findings impossible to miss.
decision: |
  A standard-library Python tool at `scripts/review-shadow/` with five
  subcommands (`grade`, `outcome`, `report`, `scan`, `check`). `grade` fetches a pull request at a stated head through `gh`,
  cuts it into slices per criterion, runs six script criteria locally and
  then sends each Jev slice as one request carrying every Jev criterion that
  reads it, and writes one JSON record per run under a local state
  directory. `outcome` records a panel's kind, run id and each blocking
  finding's category and final disposition against the same head. `report`
  joins the two and prints agreement, false passes, fails and no-verdicts
  on clean panels, coverage and a
  Clopper-Pearson bound per panel kind and per criterion, in-sample and
  out-of-sample apart. Criteria live in a JSON file with opaque ids, an
  artifact kind and a slice kind, so pull requests are only the first kind.
rationale: |
  A local script run by a reviewer is the only place that sees both panel
  kinds today, needs no koto change, and can grade merged pull requests for
  the in-sample demonstration. Python keeps the statistics, JSON handling and
  the spike's request shape in one small file with offline tests, as the
  spike harness already does. Choice questions with an escape follow the
  spike's finding that the boolean form compresses probabilities. Script
  checks run first because they're free, and they count toward unanimity
  because a flip would replace the whole panel, not the Jev part of it.
upstream: docs/prds/PRD-jev-review-shadow.md
decision_provenance: inline-resolved
user_visible_surface: false
---

# DESIGN: Jev review shadow trial

## Status

Current

## Context and Problem Statement

The PRD (`docs/prds/PRD-jev-review-shadow.md`) asks for a shadow trial: grade
a pull request with a batch of closed criteria, record the panel's verdict
on the same head, and report how often a unanimous pass agreed with a clean
panel. It fixes the vocabulary (verdicts, run status, upheld findings,
scored heads, in-sample) and the numbers the report prints. This design
settles how.

Four facts from outside the PRD shape the answer.

**What the spike measured.** `docs/spikes/SPIKE-jev-accuracy.md` sent one
question per request, over inputs of 39 to 2,507 bytes, in two forms. The
boolean form kept every probability between 0.06 and 0.96 and escaped 428
of 480 answers; the choice form (`pass`, `fail`, an escape, one-line
description each, winner only at 0.9 or above) spread probabilities across
the range. Two criteria cleared the bar for trusting a pass. The PR-body
criterion, the closest relative of one criterion here, did not: it passed
five of 22 bad bodies.

**How Jev batches.** A request carries one `state` object of labelled
inputs and any number of named questions over it. Each question is answered
on its own, with its own probabilities; the request reports one `usage`
block (input and output tokens) for all of them. A probe with two questions
over one comment and its code came back in 367 ms with both answers and one
usage block.

**What koto records.** koto's decider check bounds a slice at 2,560 bytes,
never truncates, and records per criterion the rule id, probabilities,
outcome, model, slice hash and length, tokens from every billed answer, and
a count of billed answers whose usage couldn't be read. A missing verdict is
`unanswered` with a reason and never blocks. The records here mirror those
fields so that moving the in-run version into a koto decider check later is
a rename, not a redesign.

**What panels block on.** A read-only pass over about 250 review-panel
reports from recent pull requests (roughly 955 findings; 187 reports carry a
vote, 157 merge and 30 do-not-merge) grouped the findings as follows. Counts
come from keyword classification plus a full read of every blocking
section, and are good to about 30%.

| Finding group | Findings | Blocking | Class | Criterion |
|---|---|---|---|---|
| Pull request body claims more or less than the diff | ~130 | ~12 | covered | `rs-007`, `rs-008` |
| Document contradicts itself, or a doc statement went stale after the change | ~90 | ~8 | covered | `rs-009` |
| Code comment contradicts the code after the change | ~40 | ~2 | covered | `rs-010` |
| Path or anchor reference that doesn't resolve | ~55 | 0 | covered | `rs-006` |
| Wording that presents unfinished work as done, or done work as planned | ~11 | 0 | covered | `rs-004` |
| Private name or local path in public content | ~5 | 2 | covered | `rs-002` |
| Paragraph pasted twice in one document | ~3 | 1 | covered | `rs-005` |
| Attribution or session trailer | 0 | 0 | covered | `rs-001` |
| Committed reference into the scratch directory | 0 | 0 | covered | `rs-003` |
| Decision text differs from the recorded human answer | ~3 | 2 | closed, uncovered | none: needs the recorded answer, which no pull request carries |
| Correctness or security defect in code | ~150 | ~10 | open judgment | none: needs cross-file reasoning a 2.5 KB slice can't hold |
| Missing test for new behaviour | ~45 | ~3 | open judgment | none: "is this tested enough" has no closed form |
| Layering and architecture | ~75 | ~2 | open judgment | none |
| Proportionality, scope creep, dead code | ~85 | 0 | open judgment | none |
| Naming and terminology | ~140 | 0 | open judgment | none |
| Changelog or docs not updated with the change | ~30 | 0 | open judgment | none: whether a doc needed updating is a judgment |

Three things follow. The covered groups hold most of what panels *block* on
(the contradiction groups are about 60% of blocked reports), but only about
a third of all findings. The script groups rarely fire: the attribution and
scratch-directory groups produced no real finding, because reviewers already
check them. And the bulk of findings, correctness, layering,
proportionality, naming and test gaps, is open judgment that no criterion
here covers. The report's coverage share exists so that a flip is only ever
considered for the covered part.

## Decision Drivers

- Measure only. Nothing may skip, shorten or gate a panel (PRD R15).
- Choice questions with an escape, never booleans (spike finding, PRD R2).
- Every Jev slice at most 2,560 UTF-8 bytes, never truncated (PRD R4).
- Runs from a reviewer's shell with no koto state, on any head a pull
  request ever had (PRD R6), so merged pull requests can be graded.
- Records local and uncommitted; no private term committed in any form
  (PRD R16, R17).
- Everything but the live Jev call testable offline in CI (PRD R18).
- Keep criteria independent of the artifact so briefs, PRDs, designs and
  plans can use the same runner later.
- Fields line up with koto's decider-check record, so the in-run version
  can move into koto without a data migration.
- Lean: one small tool, no new dependencies.

## Considered Options

### Decision 1: Where the grader runs and what it's written in

The grader has to run beside a pre-merge panel that isn't a koto workflow,
beside a worker's in-run panels that are, and against pull requests that
merged days ago. It needs HTTP, JSON, a binomial bound and a diff parser.

#### Chosen: a standard-library Python tool under `scripts/review-shadow/`

One executable, `scripts/review-shadow/review-shadow.py`, with `check`, `scan`, `grade`,
`outcome` and `report` subcommands, plus a criteria file, a category map, a
test module and fixtures in the same directory. It uses only the Python
standard library (3.8 or later), calls `gh` for pull request data and
`urllib` for Jev, exactly as the spike harness does. shirabe already runs
Python in CI for `scripts/ablation/`, so no new toolchain enters the repo.

#### Alternatives Considered

**A koto decider check in work-on's scrutiny state.** Declare the criteria
as a `decider-check` gate in shadow mode. Rejected for this change because
it only sees in-run panels of koto workflows, can't grade a merged pull
request, and the pre-merge panel isn't a koto workflow. It is the follow-on
home for the in-run version (see Implementation Approach).

**A `shirabe` subcommand in Rust.** Ship it in the validator binary.
Rejected because the trial is expected to end in a decision after fifteen
to twenty pull requests per kind; binary releases, cross-compiled builds
and a Rust HTTP client are a lot of weight for a measurement that may be
deleted.

**Bash with `jq` and `curl`.** Rejected because the Clopper-Pearson bound,
slice packing and the report's joins are awkward in shell, and scripts may
reach the network only to call Jev.

### Decision 2: The criterion format

The PRD requires a two-value choice with an escape, an opaque rule id, a
rule ref, an artifact kind and a slice kind (R2), and the coordinator asked
that a criterion name the artifact kind it applies to so pull requests are
just the first.

#### Chosen: a JSON criteria file with one object per criterion

`scripts/review-shadow/criteria.json` holds a version and a list. Each
criterion:

| Field | Meaning |
|---|---|
| `rule_id` | `rs-NNN`, assigned in order, never reused; carries no word of the rule |
| `rule_ref` | repository path of the rule text the criterion checks |
| `group` | the finding group it covers (a key of `categories.json`) |
| `artifact_kind` | `pull-request` today |
| `slice_kind` | which slicer feeds it (see Decision 3) |
| `observer` | `script` or `jev` |
| `question` | Jev criteria: the question, as the `instructions` string |
| `values` | `{"pass": "...", "fail": "..."}`: the two values and their descriptions |
| `escape` | `{"unclear": "..."}`: the escape value and its description |
| `threshold` | 0.9, koto's default; a value wins only if highest and at least this |
| `check` | script criteria: the check function's name |
| `applies_to` | optional: `public` for criteria that run only on public repositories; `run_scripts` gives such a criterion `pass` with reason `not-applicable` on a private one |
| `enabled` | optional, default true: `false` ships the criterion off, and `grade --enable <rule-id>` turns it on for a run |

The loader refuses a file where any criterion lacks a field, declares a
boolean, repeats a rule id, names a `rule_ref` that doesn't exist, or names
an unknown slice kind or check. A script criterion carries the same
`values` and `escape` as a Jev one, so the record is uniform and a script
verdict could become a Jev one without a format change.

`scripts/review-shadow/categories.json` maps every finding category the
outcome command accepts to a class (`covered`, `closed-uncovered`,
`open-judgment`) and, for covered ones, the rule ids that cover it. The
report reads coverage from it, and the loader refuses a covered category
whose rule ids don't exist.

#### Alternatives Considered

**TOML, like shirabe's other data files.** Rejected because `tomllib`
arrived in Python 3.11 and the tool targets 3.8, the spike harness's floor.

**The rule registry.** Rejected because it doesn't exist yet. The criteria
move there when it does, and opaque ids make that a copy.

**koto decider-check declarations in a template.** Rejected for now for the
same reasons as Decision 1's koto alternative; the field names are chosen
so a declaration can be generated from this file later.

### Decision 3: Cutting a pull request into slices

A slice is the labelled text one Jev request carries. The PRD bounds it at
2,560 UTF-8 bytes summed over its labelled inputs (R4) and fixes two input
shapes (R5). A real pull request can be far larger, and three criteria need
three different views of it.

#### Chosen: one slicer per slice kind, packing whole units up to the bound

Every slicer works from the same fetched data: the pull request body at the
graded time, the file list with per-file added and removed counts, each
changed file's unified-diff hunks with three lines of context, for
changed Markdown files the file's full text at the head, and the list of
every path in the repository at the head (for `rs-006`).

- **`pr-summary`** (`rs-007`, `rs-008`). Inputs: `pr_body_part1` (the body
  up to the first `---` line, which becomes the squash message) and
  `diff_summary` (one line per file: status, path, `+added -removed`). One
  slice per pull request. If the two together exceed the bound, the file
  list is never cut, because an "omits a change" judgment over part of the
  list would be wrong. Instead it is summarized: files are grouped by
  directory into one line each (`dir/ N files +added -removed`), a level at
  a time, until the slice fits; the record keeps the level used. If even
  the top-level summary doesn't fit, or Part 1 alone is over the bound, the
  slice is over-bound and both criteria are `unanswered`.
- **`code-hunks`** (`rs-010`). Inputs: `path` and `hunks`. For each changed
  file that isn't Markdown, JSON, YAML or a lock file, whole hunks are
  packed in file order into slices up to the bound. Only hunks that add,
  remove or border a comment line (`#`, `//`, `/*`, `*`, `--`) are packed;
  a file with none produces no slice. A hunk over the bound, which is what a
  whole new file arrives as, is first split at blank lines into blocks, each
  headed by the hunk's `@@` line; a block still over the bound is cut into
  windows that each start at a comment line and run on through the code
  after it, up to the bound. Only a single line over the bound stays an
  over-bound unit. (The in-sample demonstration showed why: without the
  windows, nearly every pull request had one long block, so this criterion
  was unanswered everywhere and no run could be a unanimous pass.)
- **`doc-pairs`** (`rs-009`). Inputs: `path`, `location_a` and
  `location_b`. A passage is a blank-line-separated prose block, or a single
  table row or list item, since that's where a count or a status usually
  sits; fenced code is skipped. For each changed Markdown file, every added
  passage that contains a multi-digit number or a backticked term is paired
  with each other passage in the file at the head that shares one of those
  terms. Pairs are ranked by the number of shared terms and at most eight are
  kept per pull request; the record counts the pairs dropped by the cap. A
  kept pair whose two passages together exceed the bound becomes an
  over-bound slice: it is never cut or sent, and its verdict is `unanswered`,
  so the criterion can't pass without having looked at it.
- **`pr-text`** (script criteria). The body plus every added line, with its
  path. Scripts have no bound.

The criterion verdict is the worst of its slice verdicts (PRD Terms), so a
criterion with no slice at all, such as a comment criterion on a docs-only
change, is `pass` with `slices: 0` recorded: nothing it checks was touched.
The report counts how many unanimous passes rested on at least one
zero-slice criterion, so a pass that looked at little is visible.

#### Alternatives Considered

**Fixed-size byte windows over the whole diff.** Rejected because a window
boundary splits a comment from the code it describes, and a question about
contradiction can't be answered from half of either.

**One slice per file.** Rejected because a large file overflows the bound
and a small one wastes a request; packing hunks gets the same answers in
fewer requests.

**Whole-document slices for self-contradiction.** Rejected because nearly
every design document in this repository is several times the bound. The
paired-paragraph approach is new ground: nothing in the spike measured it,
and the term-overlap pairing will miss contradictions phrased without a
shared term. The trial measures that as misses rather than guessing.

### Decision 4: Batching criteria per request

Each request costs its input tokens once, whatever the number of questions,
and the probe showed Jev answers each question separately.

#### Chosen: one request per slice, carrying every Jev criterion of that slice kind

The runner groups Jev criteria by slice kind and, for each slice, sends one
request whose `questions` object holds one choice question per criterion,
keyed by rule id. Today that puts `rs-007` and `rs-008` (claims more,
claims less) in one request over the `pr-summary` slice, and one criterion
each in the `code-hunks` and `doc-pairs` requests. A timeout, connection
failure, 5xx or unreadable answer is retried once, as koto's decider check
does; after that every criterion in the request is `unanswered` with the
reason. A request whose answer lacks one of its questions leaves just that
criterion `unanswered`.

Batching is new ground. The spike measured one question per request, and
Jev's documentation says batching doesn't change accuracy, which the spike
didn't check. So `grade` also takes `--unbatched`, which sends each
criterion on each slice as its own request, and every round records its
`rule_ids` list and a `batched` flag. Grading the same slices both ways
costs one extra run and lets the report compare per-criterion verdicts
between modes; the report prints the mode of every run it counts.

Splitting the body criterion in two is itself a batching choice. The
spike's single body criterion passed five of 22 bad bodies; two narrower
questions (does the body claim a change the file list doesn't show; does
the file list show a significant change the body omits) cost no extra
tokens in one request and let the report say which direction fails.

#### Alternatives Considered

**One request per criterion per slice, as the spike did.** Rejected because
it multiplies input tokens by the number of criteria sharing a slice, for
the same answers.

**One request carrying several slices under different labels.** Rejected
because the state is shared by every question, so it would break the bound
the spike measured.

### Decision 5: The record and where it lives

The PRD fixes the record's content (R7 to R9) and the coordinator's
measurement effort reads it. It needs a stable shape, a place outside any
repository, and a way to hold several runs per head.

#### Chosen: one JSON file per run under a local state directory

The directory is `$REVIEW_SHADOW_HOME`, defaulting to
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/review-shadow`. Every
subcommand refuses a directory inside a git work tree (`git -C <dir>
rev-parse --is-inside-work-tree`). Layout:

```
<home>/records/<owner>/<repo>/<pr>/<head-sha>/<recorded_at>-<run_id>.json
<home>/outcomes/<owner>/<repo>/<pr>/<head-sha>/<panel_run_id>.json
```

A grade record (`schema: review-shadow/record/v1`):

| Field | Meaning |
|---|---|
| `schema`, `trial` | schema id; `trial: jev-review-shadow`, the spend marker |
| `run_id`, `recorded_at` | random id; UTC time, which orders runs on one head |
| `repo`, `pr`, `head_sha`, `panel_run_id` | join keys; the panel run id may be null until the outcome fills it |
| `session_id` | the Claude Code session that ran the command (`CLAUDE_CODE_SESSION_ID`), or null when none did |
| `panel_kind` | the kind the caller said it grades beside, or null |
| `graded_body_at` | the time the body was read as of (see Decision 6) |
| `diff_kind` | `docs` when every changed path is Markdown under `docs/` or the top-level `README.md`; `code` when none is; `mixed` otherwise; `none` when the head changes nothing. Both paths of a rename count, so moving a file out of `docs/` is never `docs`, and every other Markdown file (`CLAUDE.md`, `AGENTS.md`, a changelog, a nested README) is code |
| `in_sample` | true when an outcome for this head already existed at grading time |
| `host` | the machine's hostname |
| `criteria_version` | the criteria file's version and SHA-256 |
| `mode` | `batched` (default) or `unbatched` |
| `slices` | per slice: id, slice kind, byte length, SHA-256, over-bound flag |
| `verdicts` | per criterion per slice: rule id, slice id, verdict, probabilities (Jev only), observer, reason (unanswered only) |
| `criteria` | per criterion that ran: rule id, criterion verdict, slice count, and for `rs-009` the pairs dropped and over bound |
| `criteria_enabled` | the rule ids this run graded |
| `tool` | the tool version, SHA-256 of the script, `categories.json` and `unfinished-wording.txt`, and the git sha (with a dirty flag) when git can say |
| `rounds` | per Jev request: slice id, rule ids, `batched` flag, model string, input tokens, output tokens, attempts, latency. Tokens are per request, not per criterion: in batched mode `rs-007` and `rs-008` share one usage block |
| `unread_usage_attempts` | billed answers whose usage couldn't be read, counted as koto counts them |
| `tokens` | totals of input and output tokens over `rounds` |
| `status` | `unanimous-pass`, `dissent`, `inconclusive` or `not-graded`; a run where no Jev request got an answer (no key, transport or provider failure on every request) is `not-graded`, so an outage never counts as agreement |
| `not_graded_reason` | for `not-graded` runs: `no-key`, `transport`, `provider`, `outcome-without-grade`, or `no-changed-paths` for a head that changes nothing (a merge-only head or an empty diff), which is never counted as docs |

Every `reason` in a record comes from one closed list: `over-bound`,
`no-key`, `transport`, `provider`, `unreadable-answer`, `missing-answer`,
`outcome-without-grade`, `body-history-unreadable`, `no-denylist`, `no-changed-paths`,
`file-unreadable`, `not-applicable`,
`tree-unreadable`. No record field holds
free text taken from the pull request or typed by a person.

An outcome (`schema: review-shadow/outcome/v1`): `repo`, `pr`, `head_sha`,
`panel_kind` (`scrutiny`, `review`, `qa`, `pre-merge`), `panel_run_id`,
`recorded_at`, `driver_session_id` (the Claude Code session that recorded
it, or null), `result` (`clean` or `blocked` as recorded), and `findings`,
each with `category`, `disposition` (`upheld`, `narrowed`, `dismissed`,
`unknown`), `disposition_source` (`recorded`, `inferred`) and an optional
`code` of at most 32 characters from `[a-z0-9-]`, for the recorder's own
cross-reference. There is no free-text note: the store is archived, and a
note about a private pull request would leave the host with it. Re-recording the same pull
request, head and panel run id overwrites the file. Recording an outcome
for a head with no grade record writes a `not-graded` record with reason
`outcome-without-grade`.

**The panel run id** is the identity of the session that ran the panel,
written `claude:<session-uuid>` for a Claude Code session (the pre-merge
panel's orchestrating session, or a worker's own session for its in-run
panels) or `koto:<workflow>:<koto-session-id>` for a koto workflow. koto's
session header carries koto's own session id and no Claude Code session id,
so a koto id alone can't reach the session that drove it and the panel's
cost. That's why the outcome records `driver_session_id` beside it: the
join from a panel to the Claude Code session that paid for it is that
field, whichever form the panel run id takes.

**Files and permissions.** The home is a fixed directory,
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/review-shadow`, overridable
only by `REVIEW_SHADOW_HOME` for tests. Directories are created 0700 and
files written 0600, each through a temporary file and a rename so an
archiver never reads half a record.

#### Alternatives Considered

**One append-only JSON Lines file.** Rejected because an outcome has to be
replaced in place when a fix round changes a disposition, and rewriting a
shared log is where concurrent runs corrupt each other.

**Records beside the repository in a gitignored directory.** Rejected
because an ignore rule is one `git add -f` from committing private text,
and the PRD requires a location outside any work tree.

**koto's session store.** Rejected because the pre-merge panel has no koto
session, and records must outlive sessions.

### Decision 6: Grading a head the pull request has moved past

The demonstration grades merged pull requests at the head their panel
reviewed, often a head a fix round later replaced. The diff at that head is
recoverable; the body isn't, because a body edit leaves no commit.

#### Chosen: compare API for the diff, edit history for the body

`gh api repos/<o>/<r>/pulls/<n>` gives the base branch; the diff is
`gh api repos/<o>/<r>/compare/<base-sha>...<head-sha>` (three-dot, so it's
the pull request's own change against their merge base), with file stats
and patches; full file text comes from the contents API at the head. The
body comes from the pull request's GraphQL `userContentEdits`, taking the
last version edited at or before `--body-at` (default: now). The record
stores that time as `graded_body_at`. When the history can't be read, the
current body is used and the record says so.

#### Alternatives Considered

**Always grade the current body.** Rejected because a body the panel
blocked on and a fix round rewrote would then pass, and the demonstration
would show a false pass that never happened.

**Require the caller to supply the body.** Kept as a flag (`--body-file`)
for bodies the edit history can't reach, not as the default.

## Decision Outcome

A reviewer runs:

```
scripts/review-shadow/review-shadow.py grade --repo <owner/repo> --pr <n> --head <sha> \
    [--panel-kind pre-merge] [--panel-run <id>] [--body-at <iso-time>] \
    [--private-terms <file>] [--unbatched]
```

The command loads and checks `criteria.json`, fetches the pull request at
the head through `gh`, and builds the slices. It runs the six script
criteria over the `pr-text` slice first, then sends the Jev requests (one
per slice, questions grouped by slice kind), with the key read from
`JEV_API_KEY` or `KOTO_DECIDER_API_KEY` and sent only in the
`Authorization` header. It writes one record and prints one line: the
record path, the run status and the tokens used. Without a key it still
runs the scripts and writes a record whose Jev verdicts are `unanswered`
with reason `no-key`.

When the panel ends, whoever closes it runs:

```
scripts/review-shadow/review-shadow.py outcome --repo <owner/repo> --pr <n> --head <sha> \
    --panel-kind <kind> --panel-run <id> \
    [--finding <category>:<disposition>[:inferred]]...
```

With no `--finding`, the panel is recorded clean. Before pushing a change of
their own, an author can run the script criteria over a local branch:

```
scripts/review-shadow/review-shadow.py scan --base origin/main [--body-file <file>] \
    [--private-terms <file>]
```

`scan` builds the `pr-text` slice from the local diff of the branch against
`--base` (three-dot) and the optional body, runs `rs-001` to `rs-006`,
prints each failure as rule id, path and line (never the matched term), and
exits non-zero on any. It writes no record. This is the local private-term
scan the PRD's R17 asks for, and the same matcher `rs-002` uses.

At any time:

```
scripts/review-shadow/review-shadow.py report [--json]
```

prints, per panel kind and per diff kind and then overall, one table of
scored heads for out-of-sample records and a separate one for in-sample
records: agreement,
false passes with the false-pass rate and its Clopper-Pearson 95% upper
bound, the miss rate, fails on clean panels and no-verdicts on clean panels
in separate columns, no-verdicts over all heads, unanimous passes that rest
on a zero-slice Jev criterion, and the counts of not-graded and
undetermined heads. No verdict counts as a fail for agreement but is never
added into the fail column. Then a per-criterion table with the same
figures, the coverage table (covered, closed-uncovered, open-judgment
counts and shares of upheld blocking findings), each false pass listed with
its pull request, head and upheld categories, and the trial's total Jev
tokens. The report counts one mode at a time (`--mode batched`, the
default, or `--mode unbatched`) and says which. It picks the latest record
for each head separately within each population (out-of-sample and
in-sample) and mode, so a later in-sample re-grade never replaces the
out-of-sample record of the same head. On heads graded both ways it adds a table of
per-criterion verdicts that differ between the modes.

**How the report counts.** A head enters the rates for a panel kind only when it
has a graded record and a blocked or clean panel of that kind. A not-graded
record and an undetermined panel (only `unknown` findings left) are counted in
their own columns and change no rate. Several panels of one kind on one head
count as blocked if any of them was. Per criterion, the panel counts as blocked
only when it upheld a finding in that criterion's group, so a criterion is
charged with a false pass only for a miss it could have caught. Every table is
printed per panel kind and diff kind, for all panel kinds per diff kind, and
overall.

**Why split by diff kind.** The uncovered blocking findings sit mostly in
code: correctness and security defects, missing tests and layering. A
unanimous pass on a code change therefore can't stand in for a panel, while
on a change that touches only documentation or planning the uncovered
blocks are rare. The flip is decided per panel kind and per diff kind, and
the likeliest first flip is documentation-only changes. The `docs` class is
deliberately narrow: shirabe's skills, references and templates are
Markdown that drives workflows, so they count as code, and only Markdown
under `docs/` and a top-level `README.md` count as documentation. A script
kept under `docs/` is code.

Nothing else in shirabe calls these commands. No skill, template or
workflow changes.

### The criteria

| Rule id | Observer | Slice kind | Question (pass means the rule holds) | Rule ref | Spike resemblance |
|---|---|---|---|---|---|
| `rs-001` | script | `pr-text` | No attribution or session trailer in the body or added lines | `CLAUDE.md` | none needed (script) |
| `rs-002` | script | `pr-text` | No private term from the local list, in plain, case-folded, base64, hex, SHA-1, SHA-256 or MD5 form, and no home-directory path, in a public repository's body or added lines | `skills/public-content/SKILL.md` | none needed (script) |
| `rs-003` | script | `pr-text` | No added line outside the scratch directory names a path inside it | `CLAUDE.md` | none needed (script) |
| `rs-004` | script | `pr-text` | The body's first part has no wording from a fixed list that marks work as unfinished (for example "not yet implemented", "will be added", "TODO", "for now") | `references/pr-body-conformance.md` | none needed (script) |
| `rs-005` | script | `pr-text` | No paragraph longer than 60 characters appears twice in a changed Markdown file | `skills/writing-style/SKILL.md` | none needed (script) |
| `rs-006` | script | `pr-text` | Every backticked repository path in an added Markdown line resolves at the head, from the root, from any directory above the file, or as the tail of a tracked path; a path whose first segment isn't a top-level entry of the repository (a workspace, runtime or other-repository path) isn't checked | `references/cross-repo-references.md` | none needed (script) |
| `rs-007` | jev | `pr-summary` | Does the body's first part claim no change that the file list doesn't show? | `references/pr-body-conformance.md` | close to `pr_body_summary`, which failed the bar |
| `rs-008` | jev | `pr-summary` | Does the body's first part mention every significant change the file list shows? | `references/pr-body-conformance.md` | close to `pr_body_summary`, which failed the bar |
| `rs-009` | jev | `doc-pairs` | Are these two passages from one document consistent with each other? | `skills/design/references/phases/phase-6-final-review.md` | new ground |
| `rs-010` | jev | `code-hunks` | Does every comment in these hunks still describe the code as changed? | `skills/work-on/references/phases/phase-4-implementation.md` | related to `comment_reason` (cleared the bar) but a different question |

`rs-009` and `rs-010` ship off (`enabled: false`). In the in-sample
demonstration `rs-010` took 89% of the Jev tokens and escaped on most heads,
so they run only when `grade --enable` names them. The PRD's R20 states when
the trial ends and what per-criterion result flips a criterion to a koto
decider check.

Each Jev criterion's `values` and `escape` descriptions are written in the
criteria file in the spike's style: one sentence each for `pass`, `fail`
and `unclear`. `rs-007` and `rs-008` resemble the one spike criterion that
let bad bodies through, so the trial should expect false passes there and
the per-criterion table exists to show them. `rs-009` and `rs-010`, and
every slice cut from a real diff, are outside what the spike measured.

## Solution Architecture

```
review-shadow.py grade
  load criteria.json + categories.json      (refuse malformed)
  fetch(gh): pull, compare base...head, contents at head, body as of --body-at
  slicers[slice_kind] -> slices             (bound 2,560 B, over-bound units flagged)
  scripts[check](pr-text, private terms)    -> verdicts (observer=script)
  for slice in jev slices:
      request = {model, state: slice.inputs, questions: {rule_id: choice}}
      call Jev (retry once) -> answers, usage
      map each answer at threshold          -> verdicts (observer=jev)
  roll up: criterion verdict = worst slice verdict; run status
  write record                              (refuse a home inside a work tree)

review-shadow.py outcome
  write/replace outcome file; write not-graded record if the head has none

review-shadow.py report
  load latest record per (repo, pr, head); load outcomes
  classify heads: scored | not-graded | undetermined; panel blocked/clean per kind
  tables per panel kind x {out-of-sample, in-sample}; per criterion; coverage; tokens
```

Components in `scripts/review-shadow/`:

- `review-shadow.py`: the command, with the loader, fetcher, slicers,
  script checks, Jev client, record writer and report in one module. The
  spike's request shape and threshold mapping are reused, not imported,
  because the spike directory is a finished record.
- `criteria.json`, `categories.json`: data.
- `unfinished-wording.txt`: the fixed phrase list `rs-004` reads.
- the `scan` subcommand, which runs the script criteria on a local branch.
- `test_review_shadow.py`: `unittest` suite, offline, with a stub fetcher
  and a stub Jev transport.
- `scripts/review-shadow/fixtures/pr-basic.json`: one small fake pull request (body, file
  list, patches, a Markdown file's text, a two-version body history) that the
  fetch and slice tests read. The seeded, clean and near-miss cases for each
  script criterion, and the record-and-outcome set with hand-computed report
  figures (`TestReport`), are built inline in the tests.

CI: `.github/workflows/check-review-shadow.yml` runs on changes under
`scripts/review-shadow/`. One job per script criterion (a matrix over
`rs-001` to `rs-006`) runs that criterion's test class, and one job runs the
rest of the suite (loader, slicers, bound, batching, record, outcome,
report). No job sets a Jev key or names the endpoint. The test module
replaces urllib's opener factory with one that fails the test, so a test
that reached a real transport would fail, and `cmd_grade` is tested end to
end with a key set, through the stub transport and the stub fetcher.

## Implementation Approach

1. **Criteria, loader and categories.** `criteria.json` with the ten
   criteria, `categories.json`, the loader and its refusal tests.
2. **Fetcher and slicers.** The `gh` fetcher behind an interface the tests
   stub; the three Jev slicers and the `pr-text` slice, with bound and
   packing tests at 2,560 and 2,561 bytes and with multibyte text.
3. **Script checks.** `rs-001` to `rs-006`, each with seeded, clean and
   near-miss fixtures, and the CI matrix.
4. **Jev client and grade.** Request building, retry, threshold mapping,
   roll-up, record writing, the no-key path, and the call-order test that
   no Jev request precedes the last script verdict.
5. **Outcome and report.** The outcome writer, the not-graded record, the
   report's classification and tables, the Clopper-Pearson bound, and the
   fixture set with hand-computed output.
6. **Guide and demonstration.** A short usage guide in
   `docs/guides/review-shadow.md`, and the in-sample demonstration on
   merged pull requests, whose table goes in the pull request body, not in
   the repository.

**Follow-on, not built here.** The in-run version belongs in a koto
`decider-check` gate in shadow mode inside work-on's scrutiny state: the
Jev criteria of this file become check declarations with the same rule ids,
the `code-hunks` and `pr-summary` slicers become the gate's extraction
command, and koto's own ledger replaces the grade record for in-run panels.
The outcome command stays as it is, since koto doesn't know a panel's
disposition.

**Marking trial spend inside an agent session.** The command makes no model
call except to Jev, and every Jev token lands in a record carrying
`trial: jev-review-shadow`, so the report's token total is the trial's Jev
spend. The agent session that runs the command spends only the tool call
and its one-line output, and the record's `session_id` names that session.
A session started only to run the trial is
identified by the `session_id` on its grade records, and its whole spend
is trial spend. A reviewer's session that runs the command in passing
contributes the one tool call, attributable through the same field. The
tool sets no telemetry variable: overriding the host's own telemetry
attributes could silently drop what the host already sets there.

### Beyond pull requests

The runner reads a criterion's `artifact_kind` and `slice_kind` and nothing
else about the artifact, so the same command can grade other shirabe
artifacts once each has a fetcher and slicers. None is built here.

| Artifact | Example criteria | Skill prose it could let go |
|---|---|---|
| BRIEF | The problem statement names a gap a reader feels, not the feature being built; each OUT item is something a reader might expect inside the boundary | The content-quality reviewer's first and fifth checks in `/brief` Phase 4 |
| PRD | Each acceptance criterion is binary pass/fail (the spike's `ac_binary`, which cleared the bar); no requirement names an implementation technology | Parts of the testability and clarity reviewer prompts in `/prd` Phase 4 |
| DESIGN | Every rejected alternative carries a specific rejection reason; the frontmatter `decision` agrees with the Decision Outcome section | The strawman check in `/design` Phase 6 and part of the structural review |
| PLAN | Every issue's acceptance criteria are binary; no issue depends on one that comes after it | Parts of `/review-plan`'s criteria-strength reading |
| Review panels | A finding names a file and line; a blocking finding says what would change the vote | Parts of the panel instructions that ask reviewers to self-check their findings |

## Security Considerations

**Credentials.** The Jev key is read from the environment and placed only
in the `Authorization` header. It is never printed, logged or written to a
record. An HTTP error keeps only the status, since some servers echo request
headers in error bodies. `gh` uses the caller's own login.

**What leaves the machine.** Slices of the graded pull request go to Jev.
For a public repository that's public text. For a private one, it's the
same text a koto decider check in that repository would send, and the
caller chooses to run the command. Before any slice is sent, strings shaped
like common credentials (GitHub, cloud and API token prefixes, private-key
headers) are replaced with a fixed marker, and the record keeps the slice
hash, not the text.

**Private terms.** The private-term list is read from a file the caller
names with `--private-terms` or `REVIEW_SHADOW_PRIVATE_TERMS`, one term
per line, outside any work tree. The repository carries no copy of any
term in any form: not plain, not hashed, not encoded, not split, because a
hash of a guessable term is the term. When no list is given, `rs-002` is
not checked: its verdict is `unanswered` with reason `no-denylist`, which
makes the run inconclusive rather than a pass. It is never
sent to Jev, never written to a record, and never committed. Records hold
the rule id and a match count, not the matched term.

**Records.** Records live outside every work tree, and the commands refuse
a home directory inside one. They hold hashes, probabilities, counts and
values from closed lists, and no free text, because an archive collects
them.

**Input handling.** Every argument that becomes a path or a `gh` endpoint is
checked before use: `--repo` against `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`
(and neither part may be `.` or `..`), `--pr` as digits, `--head` as 40
lowercase hex characters, `--panel-run` against its two forms with
`[A-Za-z0-9._-]` parts, and finding categories and codes against their
closed lists. Pull request text is data. It goes into Jev's `state` object
and is never interpolated into a shell command. `gh` is called with an
argument list and no shell, only with `api` and fixed endpoint templates;
field values go through `-f` (raw strings), never `-F`, which would read a
local file for a value starting with `@`; file paths from the pull request
are percent-encoded before they enter an endpoint.

**Endpoint.** The Jev endpoint is Jev's public API host, the same one the
accuracy spike already commits in `docs/spikes/jev-accuracy/grade.py`; it is
a public service, not a private vendor, so the PRD's rule against naming
private vendors doesn't reach it.

**Key transport.** The Jev endpoint is a constant `https://` URL; an
override (for tests) must also be `https://` or the command refuses. The
key is attached with `add_unredirected_header`, and the opener refuses to
follow any redirect, so the key never reaches a second host.

**The work-tree refusal fails closed.** The home directory is resolved with
`realpath`; the check asks git whether the nearest existing ancestor is
inside a work tree, and any answer other than a clean "no" refuses. The
`--private-terms` file gets the same check, so a term list inside a
repository is refused rather than read.

**Visibility fails closed.** The private-name check is skipped only for a
repository that is explicitly private: `grade` reads GitHub's `private` flag
and treats a missing value as public, and `scan` treats the repository as
public unless `CLAUDE.md` declares `Repo Visibility: Private`. A
home-directory path counts as a leak only when it names this machine's user
or a term on the list, so example paths in docs and tests don't fail it.

**Failure messages.** A failed `gh` call raises a fixed hint per cause (not
logged in, no such repository or pull request, a head the pull request never
had, the rate limit) chosen by classifying `gh`'s error text, which is never
echoed.

**Test fixtures.** The private-term tests use an invented term and compute
its plain, case-folded, base64 (all three byte alignments), hex, SHA-1,
SHA-256 and MD5 forms at test time, so no encoded term is committed. Jev's documented weakness to steering
text in its input can lift a probability by up to about 0.2 (spike); in a
shadow trial that shows up as a false pass in the report rather than as an
approval, and it's one reason a flip needs the out-of-sample data.

**No approval path.** No code path writes to GitHub, marks a check, or
changes a panel. A pass is a line in a local file.

## Consequences

**Positive.**

- The flip decision gets out-of-sample numbers per panel kind, with the
  uncertainty and the uncovered share printed beside them.
- The records carry everything a cost model needs, including heads the
  grader never saw.
- Criteria, ids and record fields line up with koto's decider check, so
  the in-run version can move there without re-deciding anything.
- The criterion format already carries an artifact kind, so other shirabe
  artifacts can use the runner later.

**Negative.**

- Two of the four Jev criteria resemble a spike criterion that let bad
  text through; expect false passes from them.
- Pairing paragraphs by shared terms misses contradictions that share no
  term, and the eight-pair cap can drop the pair that mattered.
- A reviewer has to remember to run two commands; a head with an outcome
  and no grade shows up as not-graded, which measures the gap but doesn't
  close it.
- Past panel votes are not dispositions. The in-sample demonstration
  labels inferred dispositions, but its agreement numbers carry that doubt.

**Mitigations.**

- The per-criterion table shows which criterion produced each false pass,
  so a weak criterion can be dropped from the batch before a flip.
- `pairs_dropped` and over-bound counts are recorded per run, so the size
  of what the slicers couldn't see is measured.
- The process owner records dispositions for live panels, and only those
  count as the test.
