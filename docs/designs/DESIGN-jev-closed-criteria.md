---
schema: design/v1
status: Planned
problem: |
  The scope chain and /work-on run a dozen or more review seats per feature
  as full agents, and some of what they check is closed and answerable from
  artifacts already on disk. Nothing says which seats a one-shot decider could
  serve with input a script gathers, and no seat has a decider verdict
  recorded beside its own. The decider sees 2,560 bytes while the seats read
  28 KB to 150 KB packets, verdicts land in five different shapes, and koto's
  decider check only exists on template states that most of these skills lack.
decision: |
  Classify every site in one table: seven decider-fit parts across the brief
  jury, the PRD jury, /review-plan's category C and three /work-on seats, and
  agent-only rows for the rest. Add a `site` subcommand to
  scripts/review-shadow/review-shadow.py with a registry of those sites. Each
  entry cuts one-unit slices by document structure, reads the seat's verdict
  from where the seat writes it, and sends seven new closed criteria (rs-011
  to rs-017) through review-shadow's existing client, bound and store. One
  line in each document site's phase file runs it between the seats' verdicts
  and cleanup. /work-on runs it from panel-scope.sh --record in the
  background. A measure mode prints slice and seat-packet sizes without
  calling anything. No framing seat is added; the design records why.
rationale: |
  The review-shadow tool already has the bound, redaction, batching, Jev
  client, record store and report the PRD asks to reuse, and it runs from any
  shell, which koto's decider-check gate doesn't. Narrow one-unit questions are
  the input shape the accuracy spike measured; two of the seven are the
  spike's own criteria that cleared its bar. Reading verdicts where seats
  already write them keeps the agent out of the decider's input, and hooking
  the existing recording points changes no route, gate or seat.
upstream: docs/prds/PRD-jev-closed-criteria.md
---

# DESIGN: Closed-criteria review checks in decider shadow

## Status

Planned

## Context and Problem Statement

The PRD asks for three things: a classification of every jury and review
site in the scope chain and `/work-on` as decider-fit or agent-only; for
each decider-fit site, a script that assembles the decider's input from
artifacts on disk and records the decider's verdict next to the seat's in
shadow; and a recorded answer to whether a framing seat belongs between the
brief and the PRD. It fixes the rules those rest on. A site is decider-fit
only when a script can gather its input from artifacts that exist when the
seat finishes (on disk or in the run's koto context), never from text the
main agent writes. Only closed criteria go to the decider, never one that
repeats a `shirabe validate` check. The decider calls, slices and records
reuse the review-shadow tool; nothing reads a decider verdict to route, gate,
retry or resize a seat. One shadow run writes one record holding every
shadowed seat's verdict, read from where the seat already writes it, with
`seat-verdict-missing`, `seat-verdict-unparsed` or `seat-verdict-stale` when
it can't be read.

Four facts shape the technical problem.

**The decider sees 2,560 bytes.** The review-shadow tool bounds every slice
at 2,560 bytes and never truncates, and koto's decider check uses the same
bound by default. The seats read far more: a brief jury packet is about
28 KB, a PRD packet about 35 KB, a design packet about 53 KB and a
`/work-on` code packet up to about 150 KB. The format references alone are
12.7 KB to 19.5 KB. So a decider input can't be a subset of a seat packet; it
has to be a targeted extract (one journey, one acceptance criterion, one
issue's criteria, a frontmatter field beside the body section it summarizes).

**The validator already covers the cheapest closed checks.** For briefs, PRDs
and designs, `shirabe validate` checks required frontmatter fields (FC01),
status values (FC02), the Status line (FC03), required sections and their
order (FC04, FC15), writing-style word rules (FC10) and upstream resolution
and legality (R6, R10, R11). Those are out. What remains closed and unchecked
is a small set per site, and some of it (a private name, a placeholder, a
keyword list) is a script's job rather than the decider's.

**Seats write their verdicts in five shapes, and some write none.** The brief
jury writes `**Verdict:** PASS|FAIL` into pinned scratch files its phase 4 reference names;
the PRD jury writes `## Verdict: PASS|FAIL`; `/review-plan` writes one
`review_result` YAML block with `verdict` and findings by category;
`/work-on` keeps each seat's `passed` or `blocking` verdict in the koto
context key `verdict_ledger.json`, stamped with the commit it judged
(`judged_at`) and the hash of the criteria it judged against (`ac_sha`).
Design phase 5 writes an option number, not a verdict, and none of the three
design phase 6 seats writes a verdict marker. Every scratch verdict file is
deleted at its skill's cleanup step.

**koto's decider check only exists on a template state.** A
`decider-check` gate holds at most four criteria per state, sends one request
per criterion and runs only for users opted into decider mode. `/brief`,
`/prd`, `/design` and `/review-plan` have no koto template, and `koto
decider` has no command that runs a check outside one. The review-shadow
tool calls the same decider directly, batches criteria per slice, and keeps
records outside every work tree; today it only knows pull requests: its
artifact kinds, slicers and record path are all keyed by repository, pull
request number and head.

## Decision Drivers

- **Shadow only.** No route, gate, accepts field, retry count, seat count,
  model or budget changes, and the shadow step's exit status and output are
  ignored by its caller (PRD R7).
- **Script-assembled input.** The shadow command takes identifiers only (a
  topic slug, a koto session name, a git ref, an issue number, a repository
  path) and never text the agent writes (R2, R4).
- **One shadow path.** Reuse review-shadow's slicer bound, redaction,
  batching, Jev client, store and report; no second client, store or schema
  family (R5).
- **Closed criteria the validator doesn't cover.** A criterion that repeats a
  validator check, or that a word list or path pattern answers, is not a
  decider question (R3).
- **Run inside the verdict window.** The shadow step runs after the seats'
  verdicts are written and before cleanup deletes them, and before any fix
  the orchestrator applies after the jury, so the decider grades what the
  seats saw (R8).
- **Floors.** Bash 3.2, Python 3.8 standard library, no installs; tests
  offline with the real transport refused (R12, R13).
- **No artifact text in records.** Hashes, counts, verdicts and closed-list
  values only, stored outside every work tree (R14).
- **Lean.** Each criterion is a question paid for on every run; few, sharp
  criteria over coverage of every checklist line.

## Considered Options

### Decision 1: Where the shadow check runs and what it records into

The check has to run in four skills with no koto template and in one koto
workflow, read local files rather than a pull request, and land in a store
the review-shadow report can read beside the pull-request trial. The PRD
forbids a second client, store or schema family, and the coordinator asked
for review-shadow's slice and record mechanics to be reused.

#### Chosen: a `site` subcommand of `review-shadow.py` with an in-file site registry

`scripts/review-shadow/review-shadow.py site <site-id> [identifiers]
[--measure]` is the one entry point. Each registry entry names the site's
artifact kind, its assembler (which reads files and koto context and returns
the `pr`-shaped dict the slicers already consume, or a kind-specific one),
its slicer, its seat-verdict reader and its criteria. The loader's
`ARTIFACT_KINDS` and `SLICE_KINDS` grow, and `run_scripts`, `run_jev` and
`active()` gain the `artifact_kind` filter they lack today, so pull-request
criteria never run on a brief and the reverse. Slices still go through
`make_slice`, so redaction, the bound, hashing and never-truncate are
unchanged, and Jev requests still go one per slice with every criterion of
that slice kind batched.

Records keep schema family `review-shadow/record` at version 2. A site record
adds `subject` (`kind: site`, `site`, `subject_id`, `artifact_sha`) and
`seats` (per shadowed seat: `seat`, `verdict` of `pass`, `fail` or
`unreadable`, `reason` from the seat-verdict list, and `attributed` per
slice where the site can attribute a finding). It is written to
`records/<owner>/<repo>/site/<site-id>/<subject-id>/<artifact-sha12>/<time>-<run>.json`
under the existing home. `subject_id` is the topic slug or `issue-<n>`;
`artifact_sha` is the SHA-256 of the graded inputs, playing the part a head
SHA plays for a pull request. Version 1 records read unchanged.

#### Alternatives Considered

**koto `decider-check` gates.** Declare the criteria on template states in
shadow mode. Rejected because only `/work-on` has a template, `koto decider`
has no command to run a check outside one, a state holds at most four
criteria and sends one request per criterion, adding a gate changes a
template's gates (forbidden here), and koto's ledger holds neither the seat's
verdict nor anything the review-shadow report reads. It stays the in-run home
for a criterion once a flip is ruled.

**A separate script per site that imports review-shadow.** Rejected because
`review-shadow.py` is a hyphenated script, not an importable module, and
seven parsers would each have to repeat the identifier checks, the
artifact-kind filter and the store's work-tree refusal. The assemblers can
move into a `sites` module behind the same command later if the file grows
too large.

### Decision 2: Which criteria each site sends, and how input is cut

The decider answers one closed question about one small unit well; the
accuracy spike measured inputs of 39 to 2,507 bytes, and its choice-form
criteria `ac_binary` and `comment_reason` cleared the bar for trusting a
pass. Sizes measured across this repository's own documents settle which
units fit: single acceptance criteria run 28 to 823 bytes (median 169),
single brief journeys 300 to 1,453 bytes (median 531), while whole
acceptance-criteria sections run a median 3,483 bytes and only 5 of 70 PRDs
cite requirement ids in their criteria.

#### Chosen: narrow one-unit criteria, compared with the seat directionally

Each decider-fit site sends one to three closed criteria in review-shadow's
choice form (question, one-sentence `pass` and `fail`, an `unclear` escape,
threshold 0.9), each asked of one unit a script cuts by structure alone: a
heading, a checkbox item, a frontmatter key, a diff hunk. A unit over the
bound is split only at whole sub-units with its header repeated; a sub-unit
still over the bound is not sent and is recorded `unanswered` with reason
`over-bound`. A criterion's verdict for the run is the worst of its unit
verdicts, as for pull requests. The site table under Decision Outcome lists
every site with its criteria and slices; the seven new criteria are rs-011
to rs-017, two of them the spike's cleared criteria carried over unchanged.

Seat verdicts cover a whole checklist and decider verdicts one closed
criterion, so the comparison is directional. Decider pass on every unit with
a seat pass is agreement. A decider fail with a seat pass is a
"decider-only fail", resolved only by a later outcome. A seat block with a
decider all-pass counts as a false pass only when the block is attributable
to the criterion's scope: at `/review-plan` a category C finding whose
`affected_issue_ids` names a graded issue, at `/work-on` a ledger finding
whose path and lines fall inside a graded hunk (the record keeps a boolean
per slice, never the path). Other seat blocks are "unattributed" and widen
the upper bound without counting as false passes. `unclear` and `unanswered`
are no-verdicts, never agreement.

#### Alternatives Considered

**Only the two spike-cleared criteria.** Rejected because it leaves the
brief jury, `/review-plan` and scrutiny's completeness check with no
evidence at all, and a shadow criterion costs a few hundred input tokens and
no risk: new-ground criteria are measured, not trusted.

**Batch each seat's whole closed checklist over one slice per section.**
Rejected because most sections exceed the bound (acceptance-criteria
sections at a median 3,483 bytes), and list-shaped questions are the shape
that let bad text through or escaped in the spike and the pull-request
trial. It also gives no finer granularity than the seat already has.

**Every closed checklist line, including coverage questions.** Rejected
because requirement-to-criterion and component-to-issue coverage have no
unit under the bound, Open Questions and placeholders are script checks, and
each extra criterion is paid for on every run.

### Decision 3: How a site reads its seat verdict and when the shadow step runs

The seat verdict has to reach the record without the agent typing it, and
the step has to run inside the window between the seats writing their
verdicts and cleanup deleting them, without any route reading its result.

#### Chosen: the command reads verdicts itself; document sites run it from a phase-file line, `/work-on` from `panel-scope.sh --record`

Each registry entry has a verdict reader for its seats' existing format: the
`**Verdict:**` line in the brief's pinned files, the `## Verdict:` heading in
the PRD's, the `review_result` block in `/review-plan`'s output, and the
seat's entry in `verdict_ledger.json` for `/work-on`. A file that is absent
is `seat-verdict-missing`; one whose marker doesn't parse is
`seat-verdict-unparsed`; a verdict given on a different artifact is
`seat-verdict-stale`. Staleness is the verdict file being older than the
artifact's last write at document sites, and at `/work-on` a `judged_at`
that isn't HEAD or an `ac_sha` that differs from the criteria hash now.

Document sites get one line in their phase file, after the seats' verdict
files are written and before the orchestrator applies fixes or cleans up:

```
"${CLAUDE_PLUGIN_ROOT}/scripts/review-shadow/review-shadow.py" site brief --topic <topic> >/dev/null 2>&1 || true
```

The line says its result is not read. It runs synchronously: with no key it
returns at once, and with one it sends a handful of small requests under the
tool's 20-second timeout and single retry. `/work-on` needs no new agent
step: `panel-scope.sh --record`, which the agent already runs once per
round after the ledger merge, starts the shadow for that panel in the
background with its output discarded and its status ignored, so `--record`'s
own exit status and timing are unchanged.

The hook starts the shadow whether or not the user has opted in with
`REVIEW_SHADOW_SITES=1`, as the document sites' lines do. The opt-in gates
the send, inside the site command, not the run: a run without it still
writes a record of the seats' verdicts with the decider's criteria
`unanswered` and reason `not-opted-in`. That was a requirement settled while
this design was under review, so that a shadow ledger with no decider
verdicts in it reads as "the decider wasn't asked" rather than as "no
disagreements". The cost is a short local process per panel round and a
local record holding no artifact text. The template's gates, routes,
accepts fields and default actions are untouched.

#### Alternatives Considered

**The agent passes the seat verdict on the command line.** Rejected because
it puts agent-typed input into the record, which the PRD forbids, and it
would let a careless or steered agent fake agreement.

**A phase-file step in each `/work-on` panel file.** Rejected because it
adds a skippable agent step to every panel when `--record` already runs once
per round, at the moment the ledger holds the verdict.

**A command in the panel state's `default_action`.** Rejected because it
edits the koto template, which the shadow-only rule keeps as is, and the
default action runs on entry, before any seat has a verdict.

**Detach the decider calls into a background process at document sites.**
Rejected for this unit: the decider calls are few and bounded, and a
detached process at a document site would race the cleanup that deletes the
files it reads unless it snapshotted them first, which is more machinery than
the latency saves.

### Decision 4: A framing seat between brief and PRD

Issue #592 proposes spending part of the decider savings on one judgment
seat at the step from brief to PRD, asking whether the artifact needs to
exist and whether its framing holds. Nothing asks that today: `/brief` has
no branch that declines to write a brief, and `/scope`'s consolidation
judgment runs only after both documents exist, has no seat, and doesn't run
at the brief hop.

#### Chosen: no seat in this unit; record why and what would justify one

The question is open judgment, so it can't be a decider criterion, and an
agent seat is a seat-count and budget change this unit rules out. There is
also nothing yet to pay for it: the savings the issue counts on exist only
once a seat is flipped from shadow to trust, which is a later ruling. The
seat is worth adding when three things hold: the shadow data has reached the
out-of-sample count the flip ruling needs for a brief or PRD seat kind, at
least one closed-criteria seat at those juries has been flipped, and the new
seat's cost (one agent on a declared model with a `review-packet.sh doc`
packet of the brief and its upstream) fits inside what that flip freed.
Adding it then also means giving `/brief` a branch that can decline to write
a brief, since a seat whose "this shouldn't exist" has nowhere to go would
be ceremony.

#### Alternatives Considered

**Add the agent seat now.** Rejected because it changes the seat count and
adds cost before any saving exists, both outside this unit.

**Ask the decider whether the brief should exist.** Rejected because the
question is open, not closed, so it breaks the closed-criteria rule, and a
shadow verdict on it would have no seat verdict to compare against.

**Fold the question into the brief's content-quality seat.** Rejected
because it changes what an existing seat judges, which is a seat change by
another route, and it mixes judgment into a rubric this design is splitting
into closed and judgment parts.

## Decision Outcome

A maintainer reads one table to know where the decider can be tried, and
every run of a decider-fit site leaves a record pairing the seats' verdicts
with the decider's, in the store the pull-request trial already uses.

### Site classification

| Site | Part | Class | Decider input (artifacts) or reason | Criteria | Slice unit | Seat verdict read from |
|---|---|---|---|---|---|---|
| Brief jury | content quality, journey check | decider-fit | `docs/briefs/BRIEF-<topic>.md`, User Journeys section | rs-011 | `brief-journey`: one `###` journey | `**Verdict:**` in the content-quality seat's pinned file (brief phase 4) |
| Brief jury | content quality, other checks | agent-only | Whether the problem is real, the outcome outcome-shaped, the journeys distinct, the exclusions real and the open questions blocker-free is judgment | none | none | none |
| Brief jury | structural format, summary agreement | decider-fit | `docs/briefs/BRIEF-<topic>.md`, frontmatter `problem` and `outcome` with the Problem Statement and User Outcome | rs-012 | `summary-pair`: one frontmatter field with its section, packed by whole paragraph | `**Verdict:**` in the structural-format seat's pinned file (brief phase 4) |
| Brief jury | structural format, other checks | agent-only | Sections, order, Status line and banned words are FC01-FC04, FC10, FC15; private names, placeholders and Open Questions in Draft are script checks; the judgment-only style rules are judgment | none | none | none |
| PRD jury | clarity and testability, binary criteria | decider-fit | `docs/prds/PRD-<topic>.md`, Acceptance Criteria section | rs-013 | `prd-ac`: one `- [ ]` item with its group label | `## Verdict:` in the clarity and testability seats' pinned files (PRD phase 4) |
| PRD jury | completeness | agent-only | Sufficiency and gaps are judgment; its one closed question (every requirement has a criterion) has no unit under the bound | none | none | none |
| Design security review | phase 5 | agent-only | Whether a risk applies and how severe it is is judgment, and the seat writes an option, not a verdict | none | none | none |
| Design final review | architecture | agent-only | Judgment over the whole architecture | none | none | none |
| Design final review | security | agent-only | Judgment over the mitigations | none | none | none |
| Design final review | structural format | agent-only | Presence and order are validator checks, field order and section length are script checks, and the frontmatter is written after the seats run (step 6.5), so there is nothing closed left to compare | none | none | none |
| `/review-plan` | category C, transition coverage | decider-fit | the plan's issue manifest and the issue outline files it lists (`/plan` phase 0 names them) | rs-014 | `plan-ac-block`: one issue's title and Acceptance Criteria, split at whole items | `review_result` in the verdict file `/review-plan` phase 5 writes |
| `/review-plan` | categories A, B, D and C patterns 1, 3, 7 | agent-only | Whole-plan and whole-graph judgment, or keyword checks a script answers | none | none | none |
| Scrutiny | completeness | decider-fit | The acceptance criteria and diff the seat's `review-packet.sh code` packet holds (issue body or criteria file; `git diff <impl_base>..HEAD`) | rs-015 | `ac-hunks`: one criterion plus the hunks that mention its anchor terms | `verdict_ledger.json` `seats["scrutiny/completeness"]` |
| Scrutiny | justification | agent-only | Whether a deviation's reason is a real trade-off is judgment on text the coder wrote | none | none | none |
| Scrutiny | intent reviewer | agent-only | It judges the change against the design and downstream issues, which reads beyond the diff and far over the bound | none | none | none |
| Review panel | maintainer, comment criteria | decider-fit | `git diff <impl_base>..HEAD` | rs-016, rs-017 | `code-hunks` (existing slicer) | `verdict_ledger.json` `seats["review/maintainer"]` |
| Review panel | pragmatic, architect | agent-only | Over-engineering, scope creep and structural fit are judgment | none | none | none |
| QA | tester | agent-only | The verdict comes from running the code | none | none | none |
| light_review | reviewer, criteria and comments | decider-fit | As scrutiny completeness and the maintainer row | rs-015, rs-016, rs-017 | `ac-hunks`, `code-hunks` | `verdict_ledger.json` `seats["light/reviewer"]` |
| light_review | reviewer, unmentioned breakage | agent-only | Open-ended correctness judgment | none | none | none |

Four site ids come out of the table: `brief`, `prd`, `review-plan` and
`work-on`, the last taking `--panel scrutiny|review|light` to pick the seat
and criteria. A site whose decider-fit parts span two seats (the brief's
content-quality and structural seats, the PRD's clarity and testability
seats) runs once and writes one record holding both seats' verdicts.

### The `site` command

| Argument | Sites | Meaning |
|---|---|---|
| `<site-id>` | all | `brief`, `prd`, `review-plan` or `work-on` |
| `--topic <slug>` | `brief`, `prd`, `review-plan` | the topic slug the artifact and verdict paths are built from |
| `--session <name>` | `work-on` | the koto session whose ledger, `impl_base` and criteria are read |
| `--panel <panel>` | `work-on` | `scrutiny`, `review` or `light` |
| `--head <sha>` | `work-on` | the commit the diff range ends at and the ledger verdicts must be judged at |
| `--issue <n>` | `work-on` | read the acceptance criteria from this issue instead of the session's `context.md` |
| `--measure` | all | print slice and seat-packet sizes; send nothing, write nothing |
| `--in-sample` | all | mark the record in-sample (a manual re-grade) |
| `--repo-path <dir>` | all | the repository root; default the current directory |

### Units and slices

A **unit** is what one criterion judges: one journey (`brief-journey`), one
frontmatter field with its section (`summary-pair`), one acceptance
criterion (`prd-ac`), one issue's criteria list (`plan-ac-block`), one
acceptance criterion with its matching hunks (`ac-hunks`). For these five
kinds a slice holds exactly one unit, so a run sends one request per unit,
carrying every criterion of that slice kind. A unit over the bound is cut at
whole sub-units (paragraphs of a section, items of a list, hunks) with its
header kept, and the record counts what was dropped; a single sub-unit still
over the bound is not sent and is `unanswered` with `over-bound`. Only
`code-hunks` packs several hunks into one slice, as it does for pull
requests.

`ac-hunks` finds a criterion's hunks by its **anchor terms**: every
backticked token, every token containing `/` or a file extension, and every
`--flag` in the criterion's text. A hunk matches when its file path or one of
its changed lines contains an anchor term as a literal substring. That is a
lexical rule, not a reading of meaning; a criterion with no anchor term or no
matching hunk sends nothing and is `unanswered` with `no-anchor`.

At `/work-on`, only seats whose decision this round was `full` or `rerun`
are shadowed: a `keep` seat's verdict was given on an earlier commit and was
already paired then, and a `recheck` seat judged only its own findings, not
the whole change. A seat whose ledger `judged_at` isn't the `--head` passed
in is `seat-verdict-stale`. When no seat qualifies the command writes
nothing.

When a jury loops (fix, re-run), each round's artifact has its own
`artifact_sha`, so each is its own paired observation. The report counts the
latest record per site, subject and `artifact_sha`.

### The new criteria

| Rule id | Slice kind | Question (pass means the rule holds) | Spike resemblance |
|---|---|---|---|
| rs-011 | `brief-journey` | Does this user journey name a specific user, the situation that brings them to the feature, and what they get from it? | close to `ac_binary` |
| rs-012 | `summary-pair` | Does the frontmatter summary agree with the section it summarizes? | new ground, near `rs-009`; asks contradiction only |
| rs-013 | `prd-ac` | Can this acceptance criterion be answered yes or no by someone who didn't write it? | `ac_binary`, cleared the bar |
| rs-014 | `plan-ac-block` | Does every criterion in this issue that checks an end state or a created artifact also check the operation that produces it? | new ground (taxonomy pattern 4) |
| rs-015 | `ac-hunks` | Do these diff hunks contain a change that would make this acceptance criterion true? | new ground |
| rs-016 | `code-hunks` | In these diff hunks, does every added comment give a reason rather than restate the code? | `comment_reason`, cleared the bar |
| rs-017 | `code-hunks` | In these diff hunks, does every code comment still describe the code as it reads after the change? | the question of `rs-010`, for local diffs |

Each carries one-sentence `pass`, `fail` and `unclear` descriptions in the
criteria file, threshold 0.9, and a `rule_ref` to the seat prompt it
shadows. They ship enabled, because nothing reads them; `rs-012` and
`rs-014` are the least proven and the first to turn off if they mostly
escape.

### What a run does

1. The site's caller runs `review-shadow.py site <site> <identifiers>`.
2. The assembler reads the artifact (and, for `/work-on`, the session's
   ledger and the same criteria and diff `review-packet.sh code` uses), and
   the reader reads every shadowed seat's verdict.
3. The slicer cuts units and packs them into slices of at most 2,560 bytes.
4. With a key, `REVIEW_SHADOW_SITES=1` and a repository that declares itself
   public, one Jev request per slice carries every criterion of that slice
   kind, up to 32 slices and 60 seconds. Otherwise every criterion is
   `unanswered`, with `no-key`, `not-opted-in` or `private-repo`.
5. One record is written with the seats' verdicts, the decider's verdicts
   per unit and criterion, slice hashes and sizes, and tokens.
6. The command exits 0 on every shadow-time failure; only a malformed
   argument exits 2. Callers ignore both.

`review-shadow.py site <site> <identifiers> --measure` stops after step 3
and prints, for each slice, its id and byte size, then one line with the
byte size of the seat packet that site's seats read (built with the same
`review-packet.sh` call the phase file names, then deleted). It sends
nothing and writes no record. Those two numbers are the input-size
comparison the implementation pull request reports.

`review-shadow.py report` gains a per-site table beside the per-panel ones:
per site and per criterion, agreement, decider-only fails, attributed false
passes, the Clopper-Pearson 95% upper bound on the false-pass rate computed
with attributed plus unattributed seat blocks counted against it, and
no-verdicts, out-of-sample and in-sample in separate tables. A record is
in-sample when it was written by a manual re-grade of an artifact
(`--in-sample`), as for the demonstration on this repository's existing
documents; every record a workflow writes is out-of-sample.

## Solution Architecture

```
caller (phase-file line | panel-scope.sh --record &)
  review-shadow.py site <site> <identifiers> [--measure]
    check identifiers (slug, session name, ref, issue number, path)
    SITES[<site>]:
      assemble()  -> inputs from files / koto context / git diff
      read_seats() -> [{seat, verdict|unreadable, reason}]
      slicer()    -> units -> make_slice() (redact, bound, sha)
    --measure: print slice sizes + seat packet size; exit 0
    run_jev(slices, criteria where artifact_kind == site kind)   (batched)
    roll up per criterion; attribute seat findings to slices (where possible)
    write_private(record v2)  under <home>/records/<o>/<r>/site/<site>/...
  exit 0 (shadow failures) | 2 (bad argument)

review-shadow.py report
  load v1 (pull request) and v2 (site) records + outcomes
  pull-request tables (unchanged) + per-site tables
```

Components, all under `scripts/review-shadow/`:

- `review-shadow.py`: the `site` subcommand and `SITES` registry; four
  slicers (`brief-journey`, `summary-pair`, `prd-ac`, `plan-ac-block`) and
  `ac-hunks`, reusing `code-hunks`; one assembler per artifact kind (`brief`,
  `prd`, `plan`, `local-change`), the last built on the existing
  `local_pr()` diff reader; one verdict reader per verdict shape; the
  artifact-kind filter in the loader and runners; the v2 record writer; the
  per-site report tables.
- `criteria.json`: rs-011 to rs-017, version bumped.
- `categories.json`: one category per new criterion group, class `covered`.
- `test_review_shadow.py`: fixture artifacts per site kind under
  `fixtures/sites/`, stub ledger and verdict files, stub transport.

Callers:

- `skills/brief/references/phases/phase-4-validate.md`: the shadow line after
  verdicts are collected, before 4.4's fixes.
- `skills/prd/references/phases/phase-4-validate.md`: after collection,
  before 4.3's fixes.
- `skills/review-plan/references/phases/phase-5-verdict.md`: after the
  verdict file is written.
- `skills/work-on/scripts/panel-scope.sh`: once the ledger write succeeds,
  `--record` starts `site work-on --session <WF> --panel <panel> --head
  <sha> --repo-path <root>` in the background for the `scrutiny`, `review`
  and `light` panels, when `python3` and the script are present. It runs
  whatever `REVIEW_SHADOW_SITES` says, because the site command records an
  unset opt-in as `not-opted-in` rather than writing nothing, so an empty
  shadow record is never mistaken for agreement. Its own exit status and
  output are unchanged either way.

The work-on assembler reads the session's `impl_base` and criteria the way
`review-packet.sh code` does, so the decider and the seat read the same
criteria and diff range: the session's `context.md`, or the issue's body
when `--issue` names one.

## Implementation Approach

1. **Loader, artifact-kind filter and record v2.** New artifact and slice
   kinds, the filter in `active()`, `run_scripts` and `run_jev`, the v2
   record with `subject` and `seats`, the site path layout, and tests that a
   pull-request criterion never runs on a site and the reverse, and that the
   pull-request report's output is unchanged with site records in the store.
2. **Assemblers, slicers and measure mode.** The `site` subcommand and its
   argument checks, the `brief`, `prd`, `plan` and `local-change`
   assemblers (with path containment, `--no-ext-diff --no-textconv` and the
   secret-path skip), the five slicers, and `--measure`. Measuring this
   repository's own documents comes first: a slicer whose units mostly come
   out over the bound or with no anchor is a reason to drop its criterion
   before going further.
3. **Grading and records.** rs-011 to rs-017, the verdict readers with the
   missing, unparsed and stale reasons, the send gates (key,
   `REVIEW_SHADOW_SITES`, public visibility, private terms, the 32-slice and
   60-second caps), finding attribution, the record writer, and boundary
   tests at 2,560 and 2,561 bytes.
4. **Report.** Per-site tables with hand-computed fixture figures, built
   before any caller exists so the record's attribution fields are settled
   first.
5. **Callers and guide.** The phase-file lines for `/brief`, `/prd` and
   `/review-plan`; the `panel-scope.sh --record` hook, as above, with
   tests that `--record` returns at once and with the same status when the
   shadow fails or `python3`, the script or koto is missing; the guide
   `docs/guides/review-shadow.md` gains the site commands; the measured
   sizes go in the pull request body.

## Security Considerations

**What leaves the machine.** Slices of briefs, PRDs, plan issue outlines,
acceptance criteria and diff hunks go to the decider, the same public
endpoint the pull-request trial already calls. Unlike the trial, these are
drafts and local commits rather than pushed text, and a site run starts from
a workflow rather than a command the user typed. So site mode sends only when
three things hold: a decider key is set, `REVIEW_SHADOW_SITES=1` is set, and
the repository's `CLAUDE.md` declares `## Repo Visibility: Public`. With the
key alone every criterion is recorded `unanswered` with reason
`not-opted-in`; in a repository that doesn't declare itself public, with
`private-repo`. Nothing is sent in either case. A private repository's drafts
never reach the endpoint through this path, whatever the environment says.
Each slice goes through three steps in a fixed order: credential redaction,
then the private-term check (a slice holding a term from the caller's
private-term list, the list `rs-002` reads, is not sent and is recorded
`unanswered` with reason `private-term`), then the size bound. `/work-on`
diff slices skip paths that look like secrets (`.env*`, `*.pem`, `*.key`,
`*.p12`, `*.pfx`, `id_rsa*`, `id_ed25519*`, `.npmrc`, `.netrc`, `*.tfvars`,
`*credentials*`, `*secret*`). A run sends at most 32 slices (enough for one
slice per acceptance criterion of a large PRD) and stops sending
after 60 seconds; slices past either limit are recorded `unanswered` with
reason `run-cap`. Records keep slice hashes and sizes, never text.

**Where configuration comes from.** The criteria file, the category map, the
endpoint and the model come from the plugin's own copy of
`scripts/review-shadow/`, never from the repository being graded, so a branch
under review can't change what is asked or where it goes. The private-term
list comes from the caller's environment or a file outside every work tree,
as it does for pull requests.

**Input handling.** Every identifier is checked before it becomes a path or
an argument: topic slugs against `^[a-z0-9-]+$`, session names against
koto's name grammar, issue numbers as digits, refs through `git
check-ref-format` or as 40-hex SHAs. Every file read, including a
verdict file and each issue file a plan manifest lists, is resolved with
symlinks followed and must lie inside the repository root; a symlinked
scratch file is refused, manifest entries must match the plan's issue-outline
file pattern, and the count of files and bytes read is capped.
A seat verdict is the first anchored marker line in the seat's own pinned
file, so text inside the graded artifact is never read as a verdict.
`owner/repo` taken from a git remote passes the same pattern as `--repo`.
Artifact text is data in the request's `state` object and is never
interpolated into a shell command; `git` and `koto` are called with argument
lists and no shell, every value passed to them is refused if it starts with
`-`, and every `git diff` carries `--no-ext-diff --no-textconv` so a
repository's own diff drivers can't run a command during assembly.

**Steering text.** An artifact can carry text written to steer the decider,
or a seat. In shadow no route reads either answer, but steered answers land
in the very records a later flip ruling reads, so they are a data-integrity
risk rather than only a wrong line in a file. A flip ruling therefore needs
this analysis redone first, and the per-criterion table shows any criterion
whose agreement jumps on one artifact.

**Records.** Records live under the existing review-shadow home, refused
inside a work tree, written 0600 in 0700 directories through a rename. They
hold hashes, counts, verdicts and closed-list reasons, and no free text from
an artifact or a seat.

**The `/work-on` hook.** The background call is a child with stdin closed
and output discarded; it inherits `--record`'s environment (the decider key
included) and working directory, and can't change `--record`'s exit status
or the ledger it already wrote, so a failing or slow decider can't hold the
panel. It is passed the HEAD `--record` validated and grades the diff range
ending there, not the live tree, so a commit made while it runs can't change
what a stamped verdict is paired with; a ledger entry whose `judged_at` no
longer matches that HEAD by the time the child reads it (a later round
landed first) is recorded `seat-verdict-stale`. It is bounded by the same
32-slice and 60-second caps.

**Residual risk.** Credential redaction is pattern-based and can miss an
unprefixed secret in a diff's context lines. If a later ruling lets a
decider verdict route anything, this analysis has to be redone.

## Consequences

**Positive.**

- The classification is written down per site part, with the artifacts or
  the reason, so a reviewer can judge any change to a review site against it.
- Seven criteria start collecting paired verdicts on every run, two of them
  criteria the spike already trusts, in the store and report the flip ruling
  will read.
- No skill gains a route, gate or seat, and no agent writes decider input.
- The measure mode gives the input-size comparison as a command anyone can
  re-run.

**Negative.**

- Seat verdicts are per seat and decider verdicts per criterion, so many
  seat blocks will be unattributed and the false-pass upper bound at the
  brief and PRD sites will stay wide until outcomes are recorded.
- rs-013 will escape often (the spike's `ac_binary` passed only 4 of 12 good
  criteria), and rs-012 and rs-014 are new ground.
- The design final review and the PRD completeness seat get no shadow, so
  the costliest document juries keep their full cost whatever the data says.
- Document sites run the shadow synchronously; with a key, a run waits for a
  few decider requests.

**Mitigations.**

- The report prints attributed and unattributed seat blocks apart, so a wide
  bound is visible as a wide bound rather than as a false pass.
- Each criterion can be turned off in the criteria file without touching a
  skill, and the per-criterion table shows which ones mostly escape.
- The framing-seat decision names when a seat could be added, so the design
  final review's cost is revisited once flips free budget.
