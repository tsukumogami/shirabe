---
schema: prd/v1
status: Accepted
problem: |
  /work-on's review panels keep their verdicts per reviewer seat. A retry
  spawns every seat that blocked again and re-runs in full any passed seat
  whose citations the fix touched, up to seven reviewer runs per retry, and
  no finding has an identity that lasts from the round that raised it to the
  record that closed it, so the panel gate passes on seats rather than on
  findings closed by a reviewer.
goals: |
  A retry costs what the fix touched: re-verification of the findings whose
  code changed, plus one review of the fix's own diff. Every finding is
  traceable across rounds, a panel passes only when every blocking finding
  is closed by a verdict record a reviewer or check wrote, and the ledger
  already accepts findings from a decider for the next offload step.
upstream: docs/briefs/BRIEF-findings-ledger.md
---

# PRD: findings-ledger

## Status

Accepted

## Problem Statement

/work-on sends a code change through review panels: scrutiny (three seats),
review (three seats) and QA (one tester) at the `full` review level, or one
light seat at `light`. When a panel blocks, the coder fixes the work and the
run walks forward into the panels again. `panel-scope.sh` keeps a ledger of
each seat's last verdict in the session's `verdict_ledger.json`, and on each
panel entry decides per seat whether to keep its verdict, re-check it, or
re-run it.

That ledger works at seat granularity, and the cost and the guarantees both
follow from it:

- Every seat that blocked is spawned again to re-check its own findings,
  whether or not the fix touched them.
- A seat that passed is re-run as a full review when the fix touched any path
  it cited or any location of a finding it raised.
- A fix over 200 changed lines re-runs every seat.
- Summed over scrutiny, review and QA, one retry can cost seven reviewer runs,
  and a run may retry three times.

A finding lives inside one seat's entry for one round. A re-check returns only
the findings that still hold, so a finding that disappears from the answer
can't be told apart from one that was checked and found fixed. The
`<panel>_verdict` gate passes when no seat is blocking, which is a statement
about seats, not about each blocking finding having been closed by someone
other than the agent. And a finding raised by anything other than a reviewer
seat, such as a decider answering a closed criterion, has no place in the
ledger for the gate to read.

## Goals

- A retry's reviewer runs are bounded by what the fix touched: outside a
  full round, at most one run per panel, three per retry at the `full` level where today's worst case
  is seven, and the saving is measured on a fixture against today's rule.
- Each finding keeps one identity from the round that raised it, with a
  record of who raised it and which run closed it.
- The panel's pass stays koto's, computed from records a reviewer or check
  wrote; the agent can't close a finding by saying it fixed it.
- The ledger accepts decider findings without the gate changing again.

## User Stories

1. As the /work-on agent whose scrutiny round blocked on three findings in
   three files, I want a fix to one file to re-verify only that finding plus
   one look at the fix's diff, so that I don't pay for three re-checks when
   two findings are still waiting for their fix.
2. As the /work-on agent, I want to mark a finding I addressed outside its
   recorded location as fixed, so that it is re-verified even though the
   diff didn't touch its file, without that mark closing it.
3. As the maintainer paying for reviewer runs, I want a fix that breaks code
   no finding pointed at to be caught by the review of the fix's own diff,
   so that cheaper retries don't open a blind spot.
4. As a maintainer reading a finished run, I want each finding's raiser,
   round, location, rule, status history and closing run, so that I can tell
   a finding closed by a reviewer from one that was dropped.
5. As the maintainer building the batched decider check, I want a decider's
   failed criterion to enter the same ledger the gate reads, and a decider
   that gives no verdict to send the criterion back to a reviewer, so that
   the next step needs no gate change and can't pass by silence.

## Requirements

### Terms

- **Round**: one `--record` of a panel's spawned reviewer runs, numbered per
  panel from 1.
- **Retry**: the stretch of a run from a panel's `blocking_retry` to the next
  round any panel records. A retry's fix is what was committed in it.
- **Run**: one spawned reviewer or one check execution. Each run in a round
  carries a run id: the spawned agent's id or the check's own id, a string
  matching `^[A-Za-z0-9][A-Za-z0-9._:/#-]{3,}$`, unique within the round.
- **Fix diff**: `git diff --no-renames <base> HEAD`, where `<base>` is the
  commit the location or record in question was written at. With renames off, moving a file is a
  deletion plus an addition, so it touches the old path.
- **Touched**: a `file` location is touched when the fix diff changes its
  path at all (content, mode, deletion); a `lines` location is touched when a
  fix hunk's old-side range overlaps its range (an insertion between lines
  `a` and `a+1` touches a range containing either).
- **Changed lines**: added plus deleted lines in `git diff --numstat` over the
  fix diff, a binary file counting 1 per side.

### The ledger

**R1. One ledger.** Findings are recorded in the existing
`verdict_ledger.json` context key, maintained only by `panel-scope.sh`. No
other context key or script holds finding state. The ledger keeps its
per-seat entries (`verdict`, `judged_at`, `findings` with top-level `path`
and `lines`) and its `history`, so `review-shadow.py`, `review-level.sh
report` and `review-packet.sh` keep reading it, and each history entry's
`spawned` is the number of reviewer runs that round made.

**R2. Finding identity.** A finding's id is a hash of its panel, its
raiser's kind and name, its location's path (empty for `none`), and its
summary with whitespace collapsed. Line ranges are left out, so a finding
whose lines shift keeps its id. Two findings equal on all four are one
finding. Re-verification answers by id; an answer naming an id the ledger
doesn't hold for that panel is refused, and a due finding the answer omits
keeps its status.

**R3. Finding fields.** Each finding records its id, panel, severity
(`blocking` or `advisory`), the round it was raised in, its raiser (kind and
name), the raising run, its location, its `rule_id` when R13 allows one, its
summary, and its records in the order written. A record holds its kind, its
writer (kind, name, run), the round, the commit it was written at, and a
reason where its kind needs one.

**R4. Location kinds.** A location is `lines` (path and range, in the
numbering of the commit it was recorded at), `file` (path), or `none`. A
finding given a path and a range is `lines`, a path alone is `file`, no path
is `none`. A location keeps the commit it was recorded at, and whether it is
touched is judged on the fix diff from that commit, whose old side is in the
location's own numbering. A re-verification may give the finding a new
location, recorded at the commit it was judged at.

**R5. Records and statuses.** A finding's status is the status its latest
record yields:

| Record | Writer | Status | Closed |
|---|---|---|---|
| `raised` | reviewer, check or decider | `open` | no |
| `holds` (re-verified, still a defect) | reviewer or check | `open` | no |
| `reverified` (no longer a defect) | reviewer or check; a decider only on a finding it raised for the same criterion | `reverified` | yes |
| `dismissed` (not a defect), with a reason | reviewer or check | `dismissed` | yes |
| `fixed` (re-verification is due) | the agent | `fixed` | no |
| `unverified` (no verdict) | decider | `unverified` | no |

A re-verifier can't change a finding's severity; a different defect is a new
finding.

**R6. Writes are checked and whole.** `panel-scope.sh` refuses, with a
non-zero exit and the ledger unchanged, a round with a closing record that
lacks a run id or a reason it needs, names a writer kind the table doesn't
allow, or names a run that isn't one of the round's runs. The agent's
mark-fixed mode writes only `fixed` records. A refused write leaves the
ledger byte-identical. Advisory findings are recorded with `raised` and
nothing else, are never due, and never block.

### Retries

**R7. Full rounds.** A panel's round is full, spawning every seat with its
full review, when any of these holds: it is the panel's first round; the
ledger has no finding records (one written before this change); the
acceptance criteria or plan changed (the hash of the `context.md` and
`plan.md` context keys differs from the one recorded); a recorded commit is
no longer an ancestor of HEAD; `git status --porcelain` is non-empty; there
are no commits since `impl_base`; or the fix diff exceeds 200 changed lines.
In a full round each seat is also given the panel's unclosed blocking
findings it raised, and answers each by id, so a full round never drops one.

**R8. What is due.** On any other round, a blocking finding is due when its
row says so:

| Status | Location touched | Location untouched | Location `none` or unresolvable |
|---|---|---|---|
| `open` | due | not due | due |
| `fixed` | due | due | due |
| `unverified` | due | due | due |
| `reverified`, `dismissed` | due (regression check) | not due | not due |

A location is unresolvable when the commit it was recorded at is gone or the
diff for its path fails. A not-due finding keeps its status and costs no run;
an `open` one still blocks the gate. A regression check that answers `holds`
re-opens the finding.

**R9. The passed-seat re-run is replaced.** Today a passed seat whose cited
paths the fix touched is re-run in full. That rule goes: a passed seat with
no unclosed findings is never re-run outside a full round. The fix-diff
review (R10) is what sees new defects instead.

**R10. The fix-diff review.** Each retry runs one review of the fix diff from
the newest recorded commit that is an ancestor of HEAD (the one with the most
ancestors among all panels' records), and every finding it raises is
recorded `blocking`. A full round needs none, since its seats review the whole change.
Otherwise it runs at the first panel the retry enters whose fix diff from
that commit is non-empty, and its findings are raised by reviewer
`fix-review` in that panel, where they block that panel's gate. Once it is
recorded, later panels in the same retry see an empty fix diff and don't run
it.

**R11. One run per panel.** A non-full round makes at most one reviewer run
per panel: the panel's re-verifier (seat `recheck` for scrutiny and review,
`tester` for QA, `reviewer` for light), given every due finding by id and,
when R10 places it there, the fix diff to review. A round with no due
finding and no fix-diff review spawns nothing and carries the panel's
verdict. So a retry makes at most three reviewer runs where today it can
make seven.

### The gate

**R12. The pass.** `panel-scope.sh --verdict <panel>` exits:

- 2 when it can't decide: a seat of the panel's latest full round, or a run
  the latest round planned, has no record since the round was planned; the
  ledger can't be read; or a rule can't be resolved. 2 wins over 1.
- 1 when some blocking finding of the panel isn't closed, printing one
  `::koto-finding::` line per such finding (`open`, `fixed` or
  `unverified`), in the rule registry's message form.
- 0 otherwise.

koto routes on these exits; no status field the agent writes is read as a
pass.

**R13. Rule ids.** A finding carries a `rule_id` only when the check that
raised it is that rule's registered check (the entry's `check.path`), or a
reviewer cites the id. A rule id is never inferred from wording. `--record`
refuses a finding naming an id that isn't an `active` registry entry.

**R14. The generic entry.** A blocking finding with no rule prints under a
new registry entry, `panel/open-finding`, with the panel, raiser and summary
in its message; it has `level: gate`, guards, and `withhold: never`. A
finding with a rule prints under that rule. `panel/blocking-finding` is set
to the registry's `retired` status, which keeps its id joinable and forbids
printing it. The gate never prints an id that isn't `active`.

### Decider findings

**R15. The decider raiser.** A raiser of kind `decider` is named by its gate
and the criterion's rule id (`<gate>/<rule_id>`); its finding's summary is
the criterion's rule id and its location is `none` unless the criterion
names a path, so the same criterion failing again maps to the same id. A
decider finding is `blocking`. The raiser carries a reference to the `decider_checked` event
that produced it: its state, `visit_seq`, gate, rule id, declaration hash,
and input hash when present. A decider reference missing state, gate, rule
id or `visit_seq` is refused. Outcomes map as: `fail` writes `raised` (or
re-opens the finding); `pass` writes `reverified`, under R5's limit, and
writes nothing when the criterion has no finding; `escape`,
`unanswered`, `not_graded` and any other value write `unverified`. Nothing
in this feature produces decider findings; the shape is tested on fixtures.

### Retry counting

**R16. The cap is unchanged.** `panel-retry-budget.sh` keeps its rule: the
first two retries in a run are granted, a third only when this panel's count
is lower than on its own previous blocking round, never more than three. The
count is now the number of findings `--verdict` printed for the round, one
per unclosed blocking finding; advisory findings are never counted. The
count stays in the `panel_retries` context key, because koto 0.15.0 stamps a
new attempt on every tick that evaluates a gate, including ticks held at a
blocked verdict and carried rounds, exposes those counts to no command, and
keeps no per-round finding count, so its attempt counts can't express this
rule without changing it.

### Evidence and hygiene

**R17. The saving is shown.** A test drives `panel-scope.sh` on a fixture
where three scrutiny seats each raise one blocking finding in a different
file and a fix commit touches one of the files. It asserts the second
round's history entry records `spawned: 1`, where today's seat-level rule
records 3 on the same fixture.

**R18. Checks ship with CI.** Every acceptance criterion below is checked by
a test in `panel-scope_test.sh`, `panel-retry-budget_test.sh`,
`review-packet_test.sh`, `test_review_shadow.py`, `rule-registry_test.sh` or
`check-rule-registry.sh`, each run by its existing workflow on the pull
request (`panel-scope_test.sh` also on the macOS bash 3.2 leg); a workflow
whose path filter misses a file this feature changes gains that path.

**R19. Nothing withheld, nothing shrunk.** No registry entry's `withhold`
changes, the new entry is `withhold: never`, and every first round is full.

**R20. Public content.** Nothing committed or in the pull request body names
a private repository or its documents, a local path, a session or instance
name, or a job id, in any form, and `scripts/ablation/check-public-content.sh`
passes on the branch's diff and on the body.

## Acceptance Criteria

The ledger:

- [ ] After a recorded round, each finding of the round is in
      `verdict_ledger.json` with id, panel, severity, round, raiser, raising
      run, location, summary and ordered records, and each seat entry keeps
      `verdict`, `judged_at` and `findings` with `path` and `lines` (R1, R3).
- [ ] `review-shadow.py`'s ledger reader, `review-level.sh report` and
      `review-packet.sh recheck` pass their suites against a ledger written by
      the new `panel-scope.sh`, and each history entry's `spawned` equals the
      runs in that round's file (R1).
- [ ] Two rounds raising the same panel, raiser, path and summary (differing
      in whitespace or lines) give one id; a different panel, raiser, path or
      summary gives a different id (R2).
- [ ] A re-verification naming an unknown id is refused; a due finding it
      omits keeps its status (R2).
- [ ] Path and range give `lines`, path alone `file`, no path `none`; a
      `lines` finding at lines 10-12 is touched by a fix changing line 11,
      not by one changing only line 40 of the same file, judged from the
      commit it was recorded at (R4).
- [ ] Each row of R5's table yields its status, and only `reverified` and
      `dismissed` close (R5).
- [ ] Each of these is refused with a non-zero exit and an unchanged ledger:
      a closing record with no run id, a run id not among the round's runs,
      a `dismissed` with no reason, a closing record by the agent's
      mark-fixed mode, a decider `reverified` on a reviewer's finding (R6).
- [ ] An advisory finding is recorded, is never due, and `--verdict` exits 0
      with only advisory findings open (R6).

Retries:

- [ ] Each R7 trigger makes the next round full, one case per trigger: first
      round, old ledger, changed criteria, changed plan, a recorded commit off
      HEAD's history, a dirty tree, no commits, a fix of 201 changed lines;
      a fix of exactly 200 doesn't (R7).
- [ ] In a full round after a block, each seat's packet lists its unclosed
      blocking findings by id (R7).
- [ ] Each cell of R8's table is driven by one case and gives the stated
      due or not-due decision; a regression check answering `holds` re-opens
      the finding and `--verdict` exits 1 (R8).
- [ ] A passed seat with no unclosed findings whose cited file the fix
      touched is not spawned in a non-full round (R9).
- [ ] A full round plans no fix-diff review. With an empty fix diff none is
      planned; with a non-empty
      one it is planned at the first panel entered, with base the newest
      recorded ancestor commit, and not at the next panel after it is
      recorded; a finding it raises is `open` under seat `fix-review` and
      makes that panel's `--verdict` exit 1 (R10).
- [ ] A non-full round with two due findings plans exactly one run, given
      both ids; a round with none due and no fix-diff review plans no run and
      the panel's carried gate exits 0 (R11).
- [ ] On the R17 fixture, the second round's history records `spawned: 1`,
      and the same fixture under the current `main` rule records 3 (R17).

The gate:

- [ ] `--verdict` exits 0 when every blocking finding is `reverified` or
      `dismissed`; 1 with one printed line per `open`, `fixed` or
      `unverified` blocking finding; 2 for an unrecorded seat, an unreadable
      ledger, or an unresolvable rule, including when a blocking finding is
      also open (R12).
- [ ] An unruled finding prints under `panel/open-finding` with panel,
      raiser and summary in the message; a finding citing an active id prints
      under it; `--record` refuses an unknown or retired id;
      `panel/blocking-finding` is `retired`; `check-rule-registry.sh` passes
      (R13, R14).

Decider findings:

- [ ] A decider round with a full `decider_checked` reference is accepted;
      one missing `visit_seq` is refused; `fail` raises, `pass` closes only
      its own finding, and `escape`, `unanswered`, `not_graded` and an unknown
      outcome each set `unverified`, which is due next round and keeps
      `--verdict` at 1 (R15).

Retry counting:

- [ ] `panel-retry-budget.sh` on one panel's counts: 5, 5, 5 grants two
      retries and refuses the third; 5, 5, 3 grants all three; a fourth call
      after three grants is refused; and the scrutiny
      directive tells the agent to pass the number of findings `--verdict`
      printed (R16).

Hygiene:

- [ ] The suites named in R18 run in CI on the pull request, and
      `panel-scope_test.sh` runs on the macOS bash 3.2 leg (R18).
- [ ] No existing registry entry's `withhold` differs from `main`, and every
      first-round case plans every seat `full` (R19).
- [ ] `scripts/ablation/check-public-content.sh` passes on the branch diff
      and the pull request body (R20).

## Out of Scope

- The batched decider check itself. This feature defines the decider raiser
  and the `unverified` status; producing decider findings is the next feature.
- Any change to koto. Everything here runs on koto 0.15.0.
- Any change to the retry cap's numbers.
- Withholding rules from default context, or shrinking a first round.
- Re-designing the seats' roles or full-review prompts beyond the answer
  shape the ledger needs.
- Migrating ledgers from sessions started before this change. A ledger with
  no finding records reads as if no round were recorded, so the next round
  is full.

## Decisions and Trade-offs

**Keep the 200-line rule.** The alternative was to drop it and let the
fix-diff review absorb large fixes. Kept, because a fix that size is new work
the panel's several angles should see, and it is the only rule that sees
files a fix adds in bulk; the fix-diff review is one reviewer.

**Retire `panel/blocking-finding` and add `panel/open-finding`.** Keeping the
old id as the generic entry would be cheaper, but rule ids never change
meaning, and the gate now reports unclosed findings rather than blocking
seats.

**Keep `panel_retries`.** Moving the count onto koto's attempt counts would
change what is counted (every gate tick, carried rounds), and koto 0.15.0
offers no per-round finding count for the progress rule.

**One fix-diff review per retry, not per panel.** Per panel would re-review
the same diff up to three times; per retry reviews it once and records its
findings under the panel that ran it.

**Count findings, not seats, for the retry cap.** The progress rule already
counted printed blocking findings; it now counts unclosed blocking findings,
which also includes `fixed` and `unverified` ones and any the fix-diff review
adds. A retry that leaves the count unchanged earns no third retry, as
before.

**Old ledgers start over.** A session begun before the change has seat
entries but no finding records. Reading it as unrecorded costs one full round
and can't carry a pass the new gate didn't check.

## Known Limitations

- `panel-scope.sh` checks that a closing record names a run of its round, not
  that the run really happened: the agent builds the round file from the
  reviewers' answers, as it does today. Provenance stronger than that needs a
  record koto writes itself, which the decider raiser is the first step to.
- A reviewer that rewords a finding it already raised creates a new id; the
  old one stays due until answered by id. Full rounds and re-verification
  packets list unclosed findings by id to keep that rare.
- QA findings are failed scenarios and usually have no location, so they are
  due on every retry; the QA panel's saving comes from batching, not from
  targeting.
