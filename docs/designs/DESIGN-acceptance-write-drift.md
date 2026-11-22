---
schema: design/v1
status: Draft
problem: |
  /work-on's three counting gates read test-change.sh status, which counts an
  edited test or observation only once a seat, a person or a coordinator has
  written an acceptance line into the run's own koto session. The panels
  already judge edited tests but store no freshness, the re-verifier judges
  none, observations reach no packet, and two late-commit paths never pass a
  panel, so retiring the seat needs the panels to own that judgment end to end.
upstream: docs/prds/PRD-acceptance-write-drift.md
---

# DESIGN: acceptance-write-drift

## Status

Draft

## Context and Problem Statement

`/work-on` counts a unit's passing checks three times: at `pass_counting`
after local verification, at `pr_precheck` just before the pull request, and at
`ci_pass_counting` after CI passes on the open PR. At each of those, a gate
named `tests_counted` (`tests_still_counted` at `pr_precheck`) runs
`test-change.sh status`. That command classifies the unit's test files over
`impl_base..HEAD` with `scripts/lib/test-classify.sh`, and holds the unit while
any `edited` test or any recorded observation lacks a live acceptance in the
context key `test_change_ledger.jsonl`. An acceptance is a line written by a
minted seat (`test-change.sh seat`, then `accept` or `decline`), by a person
from an interactive terminal, or by a coordinator, and it is judged by the rule
library `scripts/lib/acceptance-rule.sh`. A coordinator can also `overrule` an
acceptance, after the run has finished. The PRD requires all of that to go
(R1 to R3): no outside party writes into the run's session for test-change
acceptance (R26), and no ledger line other than the header can change whether a
unit counts (R18).

The judgment itself already happens elsewhere. `panel-scope.sh --record`
requires every panel seat that ran to judge each edited test `corrects` or
`weakens`, refuses a round that doesn't, and records a `weakens` as a blocking
finding under rule `review/test-edit-weakens`. Each seat entry in the panels'
verdict record (the `verdict_ledger.json` context key) stores `judged_at`
(HEAD when it judged) and `test_edits: [{path, judgment}]`. Three things are
missing for the panels to replace the seat:

1. **Freshness.** Nothing compares what a seat judged with what is at HEAD. The
   blob a seat judged is recoverable as `git rev-parse <judged_at>:<path>`, and
   a rewritten history already forces a full round, so `judged_at` stays
   resolvable for as long as the record holds a verdict. But no code computes
   whether an edited test is **due**: the PRD's term (R9) for an item no seat or
   re-verifier of a panel judged at its current content.
2. **The re-verifier.** A retry that touches fewer than 200 lines plans only the
   panel's re-verifier, and the re-verifier judges no test edit: its packet has
   no test-changes section and `--record` drops its `test_edits`. So a test
   edited in a small retry is never judged again by anyone but the seat today.
3. **Observations.** A fix whose failure no check can reproduce records an
   observation pair in `red_first.json` (`before` and `after`). No panel packet
   carries it, and `red-first.sh check-green` (the `fix_green` gate) counts the
   pair only through `test-change.sh covered`, which reads seat acceptances.

Two routes also skip the panels entirely. At `ci_pass_counting`, a held run's
only rework edges lead to `ci_monitor`, which never plans a re-verifier
(shirabe#1931). And `/execute`'s `ci_monitor` pushes CI fixes to the plan's
shared branch itself, after its children reached `done`, so nothing classifies
or judges a test those fixes edit (shirabe#1730).

The PRD also asks for two smaller outside writers to be closed: a person's
override of a panel verdict gate must be recorded by the run naming the person
(R22), and `/review-plan` run directly must not write into a live `/plan`
session (R23).

## Decision Drivers

- **One writer.** Every line in a `/work-on` session about test changes comes
  from that run's own scripts, driven by that run's own directives (R18, R26).
- **Same gates, same edges.** The gate names stay, the command behind
  `tests_counted` stays byte-identical wherever it appears (the mermaid
  validator's check 4), no state is added or removed, and the only new edges
  leave `ci_pass_counting` on `counting_status: test_gap` (R12, R25).
- **The panels' record is the source.** A judgment counts because the run
  recorded it from a panel seat or re-verifier in the verdict record, not
  because a line in the test-change ledger says so (R9, R18).
- **Exit codes keep their meanings.** 0 counted, 1 held, 2 can't decide, and
  3 held with no way left to clear it (R14).
- **One retry budget.** A late `weakens` is a blocking finding under
  `panel-retry-budget.sh`'s existing two-plus-one budget, not a second
  per-path limit (R21).
- **Fail closed.** A record that can't be read, a commit that can't be
  resolved, or a re-verifier that returns nothing holds the unit; it never
  counts it (R11, R14).
- **Bash 3.2 and the existing toolchain.** The work-on scripts run on bash 3.2
  hosts with `jq` and `git`; no new dependency.
- **Smallest blast radius.** Keep `test-change.sh` as the gate's entry point so
  the registry entry, the route tests that stub it and the template's gate
  commands change as little as possible.

## Considered Options

### Decision 1: Where the counting check lives and what it reads

The three gates need a check that holds the unit while an edited test or an
observation pair is due for a panel, or carries an open adverse judgment
(R12), keeps the header and clean-tree holds (R13), keeps the exit codes'
meanings (R14), and ignores every ledger line except the header (R5, R18). The
check has to answer from the panels' verdict record, because that's where the
run records the judgments.

#### Chosen: keep `test-change.sh status` as the gate, rewritten to read the verdict record

`test-change.sh status <session>` stays the command every counting gate runs,
byte for byte. Its body changes: it keeps the header check, the clean-tree
check and the item list (edited tests from `test_classify_unit`, plus the
observation pair when `red_first.json` has one), and asks
`panel-scope.sh --due-items <session>` (Decision 2) which items are due or
carry an open adverse judgment for any panel the unit ran. It never reads seat,
accept, decline, refuse or overrule lines; a ledger from an older run still
parses, and those lines are simply not consulted. `test-change.sh covered`,
the one call `red-first.sh check-green` makes for an observation pair, keeps
its name and arguments and answers the same question for the pair (R17), so
`fix_green` needs no change beyond its hold message.

Exit codes: 0 counted; 1 held, one `held:` line per item and reason (`due`,
`weakens`, `not shown`, `no header`, `uncommitted`, `untracked`); 2 can't
decide (work tree gone, session or verdict record unreadable, stored classifier
rules missing); 3 held while `panel-retry-budget.sh --remaining` reports no
retry left, so another panel round can't run. Its `test-change/held` finding
and the rule-registry entry keep their id, with fixtures and text updated.

The counting evidence keeps its names and edges (R15). `declined` now means
"held by a due item or an adverse judgment", and routes as it does today: to
implementation from `pass_counting` (whose next panel round plans the
re-verifier) and to `ci_monitor` from `ci_pass_counting`; exit 3 and `blocked`
go to `done_blocked`. Only the descriptions and `failure_reason` texts change.

#### Alternatives

- **A new `panel-scope.sh --tests-counted` mode as the gate command.** It puts
  the check beside the record it reads, but changes three gate commands, the
  registry entry's check path, and every route test that stubs
  `test-change.sh status` (`output-gates-routing_test.sh`, `leg-result_test.sh`
  and others) for no behavioral gain. Rejected on blast radius.
- **A new script for the check.** The same churn as above plus a new file in
  the bash-floor list and CI workflow, while `test-change.sh` would keep only
  its producer-side subcommands. Rejected for the same reason.
- **Keep the seat's ledger as the gate's input, written by the run from panel
  verdicts.** That copies judgments from one record into another and gives the
  ledger a second meaning to keep in step. Rejected: the PRD wants the panels'
  record to be the only source (R18).

### Decision 2: How the panels and the re-verifier judge due items

The re-verifier has to judge each edited test or observation pair that changed
since its panel last judged it (R9, R10), with the run's note for each edited
test (R7), and observation pairs have to reach the seats in the first place
(R8). A re-verifier that returns nothing must leave the item due (R11).

#### Chosen: per-panel judgments keyed by content, a due-item trigger on the re-verifier, and observations in both packets

- **Recording content.** When `--record` stores a seat's `test_edits`, it adds
  each test's blob at `judged_at` (`git rev-parse <judged_at>:<path>`, or
  `deleted`). A new per-panel list, `.judgments[<panel>]`, gets one entry per
  judged item: `{item, content, judgment, by, run, judged_at}`, where `item` is
  a test path or `observation`, `content` is the blob or the pair's two
  digests, and `by` is a seat name or `reverifier`. Seat entries keep their
  `test_edits` for the panels' existing checks.
- **Due.** An item is due for a panel when `.judgments[<panel>]` has no entry
  whose `content` equals the item's content at HEAD (R9). Judgments at other
  content don't count, whichever seat made them; one seat's judgment at
  current content is enough, because a full round has already required every
  seat to judge and any `weakens` stays open as its own blocking finding.
  `panel-scope.sh --due-items <session>` prints, for every panel with recorded
  seats, each due item and each item with an open `weakens` or `not shown`
  finding, and exits 0 when there are none, 1 when there are, 2 when the record
  can't be read.
- **Planning.** `--plan` computes the panel's due items. In a round that would
  otherwise keep every seat, a non-empty due list plans the re-verifier (new
  decision reason `items-due`) and puts the list in its decision. A full round
  needs no special case: every seat judges every edited test and the pair.
- **Packets.** `review-packet.sh code` gains an `## Observations` section with
  both observation texts and the report passage, and the `## Test changes`
  section gains each edited test's note from the test-change ledger. The
  `recheck` packet gains the same two sections, restricted to the due items
  its decision lists.
- **Round file.** A seat or re-verifier entry may carry
  `observations: {judgment: "shown"|"not_shown", reason}`. Every seat in a
  round must judge the pair when the unit has a complete pair, as seats must
  judge edited tests today. A re-verifier entry must judge every due item its
  decision lists and nothing else; a round whose re-verifier entry misses one
  is refused whole (65), so nothing is recorded and the item stays due (R11).
  `not_shown` raises a blocking finding under a new rule,
  `review/observation-not-shown`, like `weakens` does under
  `review/test-edit-weakens`. A re-verifier's `weakens` or `not_shown` is raised
  by `fix-review` in its panel, so it closes and counts like any other blocking
  finding.

#### Alternatives

- **Compute content at query time from `judged_at` alone.** Works today, since
  a rewritten history forces a full round, but couples the counting check to
  `git rev-parse` over every seat entry on every tick and gives the
  re-verifier, whose marker has no per-item record, nowhere to keep its
  judgments. Rejected in favor of one explicit list.
- **Make every due item force a full round.** Simplest to plan, but a one-line
  CI fix to a test would respawn every seat of every panel. Rejected on cost:
  the re-verifier exists for exactly this size of change.
- **Have a dedicated seat judge observations.** Gives observations their own
  judge, but that is the acceptance seat again under another name. Rejected.

### Decision 3: Routing late commits through a re-verifier

#### Chosen: a `test_gap` edge out of `ci_pass_counting`, and fix rounds for `/execute`'s test-touching CI fixes

- **`ci_pass_counting` (shirabe#1931).** It gains `counting_status: test_gap`,
  the value `pass_counting` already has, with edges to `implementation` on
  `tests_counted` exits 0 and 1, matching `pass_counting`'s pair. From there the
  run passes the panels, whose next round plans the re-verifier for the due
  test, then verification and counting again. The open PR is reused the same
  way a fix round reaches `pr_creation` with an open PR today. These are the
  only new edges (R25).
- **`/execute`'s CI fixes (shirabe#1730).** A CI fix that edits a test is not
  pushed by `/execute` itself. Its `ci_monitor` directive starts a fix round of
  the step's `/work-on` run (`fix-round.sh start --from <child>`; the child
  whose recorded changed paths include the test, else the last child to reach
  `done`) and drives it to `done`, so that run's panels judge the test and the
  run records the judgment in its own session. The `failing_fixed` edge gains a
  gate, `ci_fix_tests_judged`, run by a new
  `skills/execute/scripts/ci-fix-tests.sh`: it exits 1 when the diff from the
  newest child or fix-round session's counted head to HEAD touches a file the
  test classifier counts as a test, 0 otherwise, and 2 when it can't read the
  heads. `/work-on` records `counted_head` in its own session when a counting
  gate passes; `/execute` only reads it. A CI fix that edits no test passes the
  gate as today (R20).

#### Alternatives

- **`ci_pass_counting` to `ci_monitor` with a re-verifier planned from there.**
  `ci_monitor` has no panel to plan from, so it would need a re-verifier of its
  own outside the panels' record. Rejected.
- **`/execute` classifies its own push and holds it, as a child's run would.**
  The judgment would then land in `/execute`'s session, or `/execute` would
  have to write into the child's. Rejected on the one-writer rule (R26).
- **A new `/execute` state for test-touching CI fixes.** Clearer on the
  diagram, but a new state for what a gate and an existing helper already do.
  Rejected on scope.

### Decision 4: The panel-gate override, `/review-plan`, and the koto floor

#### Chosen: the run records overrides with the person named; `/review-plan` refuses on a live plan; the koto floor rises to 0.37.0

- **Overrides.** The directives of `scrutiny_verdict`, `review_verdict`,
  `qa_verdict` and `light_verdict` each spell out
  `koto overrides record <session> --gate <gate> --rationale "<the person's reason>" --by person:<handle> --surface <terminal|forge|relay>`,
  with `--link <url>` for `relay`, run by the agent after the person says so,
  never by the person in their own shell. `skills/work-on/requires.tsv` declares
  `--by`, `--surface` and `--link`. koto 0.37.0 is the first release whose
  `overrides record` takes `--by` and `--surface`, so `assert-koto-floor.sh`'s
  floor rises from 0.33.0 to 0.37.0, which supersedes the floor in
  `DECISION-preflight-koto-minimum-2026-09-27.md`.
- **`/review-plan`.** In its standalone case, when
  `skill-session.sh status plan-<topic>` prints `live`, it stops before any
  write: no `work/review.md`, no `work/review_loopback.md`, no key removed. It
  says the `/plan` run owns the session and runs its own review at Phase 6, and
  offers a read-only review printed to the conversation. Absent or finished
  sessions behave as today.

#### Alternatives

- **Leave overrides to the person's own shell, adding `--by`.** The person
  would still be the writer into the run's session. Rejected (R22).
- **`/review-plan` writes to a session of its own (`review-plan-<topic>`).**
  Nothing reads such a session, and it needs a convention change. Rejected.
- **Keep the koto floor and detect `--by` support at runtime.** Two code paths
  for one command. Rejected: the floor exists to avoid that.

## Decision Outcome

The seat machine goes, and the panels carry its one unique job. Each panel
keeps a list of what it judged, keyed by the item's content, so "changed since a
panel last looked" is a lookup rather than a guess. A panel round that would
otherwise run nothing plans its re-verifier whenever that lookup finds a due
item, and the re-verifier judges exactly those items with the run's notes in
front of it. Observation pairs reach the packets and get a `shown` or
`not shown` from every seat, the same way edited tests get `corrects` or
`weakens`. The counting gates keep their names and commands: `test-change.sh
status` answers from the verdict record and stops reading acceptance lines, so
nothing a party other than the run writes can count a unit. The two late paths
get routes that pass a re-verifier: `ci_pass_counting` gains `test_gap`, and
`/execute` turns a test-touching CI fix into a fix round of the step's own run.
The remaining outside input, a person's override of a panel gate, is recorded
by the run with the person named, and `/review-plan` stops writing into a live
`/plan`.

These fit together because they share one record. The re-verifier writes its
judgments into the same per-panel list the seats do; the counting check and
`fix_green` read that list; the retry budget that governs panel retries also
bounds a late `weakens`; and a fix round is an ordinary `/work-on` session, so
its judgments land in a ledger that run owns.

## Solution Architecture

### Components

| Component | Change |
|-----------|--------|
| `skills/work-on/scripts/panel-scope.sh` | `--record` stores test blobs and appends to `.judgments[<panel>]`; accepts `observations` judgments from seats and the re-verifier and `test_edits` from the re-verifier for its listed due items; raises `review/observation-not-shown`. `--plan` plans the re-verifier for due items. New `--due-items` mode. |
| `scripts/review-packet.sh` | `## Observations` section and per-test notes in the `code` packet; the same, restricted to due items, in `recheck`. |
| `skills/work-on/scripts/test-change.sh` | `status` and `covered` answer from `panel-scope.sh --due-items`; `seat`, `accept`, `decline`, `overrule`, the person path, the key and tag, and the brief are deleted. `init`, `classify`, `note` and `record` stay; `record` lists old acceptance lines as legacy history. |
| `scripts/lib/acceptance-rule.sh` | Deleted, with its tests. |
| `skills/work-on/scripts/panel-retry-budget.sh` | A read-only `--remaining` mode for the counting check's exit 3. |
| `skills/work-on/scripts/red-first.sh` | `check-green`'s hold message for an unjudged pair. |
| `skills/work-on/koto-templates/work-on.md` | `ci_pass_counting` gains `test_gap` and its two edges; directives and descriptions drop the seat, person and overrule text and spell out the panel-gate override; counting states record `counted_head`. |
| `skills/execute/koto-templates/execute.md`, new `skills/execute/scripts/ci-fix-tests.sh` | The `ci_fix_tests_judged` gate on `failing_fixed`, and the fix-round instruction in `ci_monitor`'s directive. |
| `skills/review-plan/` | The live-session refusal in Phase 0 and SKILL.md, with an eval. |
| `scripts/assert-koto-floor.sh`, `skills/work-on/requires.tsv` | Floor 0.37.0; override flags declared. |
| `skills/work-on/references/red-first.md`, `SKILL.md`, phase references, `references/fixes/claude-md-conventions.md`, `scripts/lib/claude-md-header.sh` | The seat, person and overrule text removed; the due rule and re-verifier described; the `## Test Change Acceptance:` convention removed. |
| `references/rule-registry.json`, `review-level-rules.tsv`, bash-floor list, CI workflow, evals | Entries for deleted files removed; `test-change/held` fixtures updated; new rule `review/observation-not-shown`; evals 56, 57 and 62 removed or rewritten. |
| `docs/prds/PRD-red-first-fixes.md`, `docs/designs/current/DESIGN-red-first-fixes.md` | A supersession note (R24). |

### Data flow

1. Implementation edits a test (and notes why) or records an observation pair.
2. A panel round's packet carries the test hunks with notes and the pair; every
   seat judges both; `--record` appends `{item, content, judgment}` per seat.
3. A later commit changes the test. The next round that would keep every seat
   finds the test due and plans the re-verifier with it; the re-verifier judges
   the new content; `--record` appends its judgment.
4. At a counting gate, `test-change.sh status` lists the items and asks
   `--due-items`; nothing due and nothing adverse counts the unit.
5. A test edited at `ci_pass_counting` goes back through `test_gap`; one edited
   by `/execute`'s CI fix goes through a fix round of the step's run.

## Implementation Approach

1. **Panel judgments of due items.** `panel-scope.sh` content-keyed judgments,
   `--due-items`, the re-verifier's due-item planning and judging, observation
   judgments and the new rule; `review-packet.sh` sections. Tests in
   `panel-scope_test.sh` and `review-packet` tests. Nothing reads the new data
   yet, so this lands alone.
2. **Counting from the panels.** Rewrite `test-change.sh status` and `covered`;
   add `panel-retry-budget.sh --remaining`; delete the seat, person and
   overrule code and `acceptance-rule.sh`; update the template's directives and
   descriptions, `red-first.sh`'s message, the registry, the tests, the evals
   and the references. Depends on step 1.
3. **`ci_pass_counting` `test_gap`.** The evidence value, the two edges, the
   directive and a route test. Depends on step 2.
4. **`/execute` CI fixes.** `counted_head` recording in `/work-on`,
   `ci-fix-tests.sh`, the gate and the directive, with tests. Depends on step 2.
5. **Outside writers.** The override directives, `requires.tsv`, the koto
   floor, and `/review-plan`'s refusal. Independent of the others.
6. **Supersession notes** on the red-first PRD and design. Lands with step 2.

## Security Considerations

The change narrows who can write into a `/work-on` session, so its security
effect is mostly a removal. Today a minted seat identity, a person claim
guarded only by a terminal check and a keyed tag, and a coordinator overrule can
each write a line that counts or uncounts a unit; after it, nothing in the
test-change ledger beyond the header affects counting, and the judgments that
do are recorded by the run's own `panel-scope.sh --record` from reviewer
output. That removes an injection surface: a party that could append to the
ledger can no longer flip a unit to counted.

What it doesn't add: no new credentials, network calls or external inputs.
The re-verifier's packet carries the run's notes and observation texts, which
are agent-written prose, into a reviewer's context; they are framed as data in
the packet the way test hunks already are, and the reviewer's output is parsed
by `--record`'s existing schema checks, which refuse unknown items and values.
A run could game its own review by writing misleading notes; that is the same
producer-side trust the panels already rest on, and the PRD states it as a
known limitation rather than something this work claims to solve.

The koto floor rise means hosts on koto older than 0.37.0 are refused at
preflight rather than running with a flag koto would reject. A person override
names its decider as the run is told it; koto records the handle without
verifying it, which the PRD lists as a known limitation.

`ci-fix-tests.sh` reads commit ranges and session context and writes nothing;
it uses the existing test classifier and quotes every path it passes to `git`.

## Consequences

### Positive

- Every line in a run's session about test changes is the run's own, and the
  ledger can no longer count a unit by itself.
- A test edited late, by the run or by `/execute`, is judged by a re-verifier
  that sees the production diff, the hunks and the note, instead of by a seat
  that saw the hunks alone.
- Observations get judged by the panels for the first time.
- About a thousand lines of seat, person and rule code and their tests go.

### Negative

- A late weakening after the panels spent their retries ends the run blocked
  sooner than the old per-path decline limit would have.
- `panel-scope.sh`, already large, takes on the due computation.
- Raising the koto floor refuses hosts still on koto 0.33 to 0.36.
- A test-touching CI fix in a plan costs a fix round, which is slower than
  `/execute` pushing it directly.

### Mitigations

- The exit-3 path names the item and the spent budget, so a person can resume
  with a fix round or override.
- `--due-items` is one mode with its own tests, and the counting check calls it
  rather than re-deriving anything.
- The preflight already prints the floor and the installed version, and koto
  0.37 is current on every host the workspace manages.
- A CI fix that edits no test, the common case, keeps today's path.
