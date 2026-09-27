# Round 4 review: Issue 1 (reconcile-report.sh)

Reviewed at 1752fa5 ("decide whether a holding has a pull request in one
place") against PLAN Issue 1, DESIGN-coordinate-reconcile.md and PRD
R16-R21, R29, with the round-3 findings in `work-on_round3_issue1.md`.
`bash skills/coordinate/scripts/reconcile-report_test.sh`: 60 passed, 0
failed. Probes below were run by hand against the current script.

## Round-3 blocking finding (B1): closed

`has_pr` is now the one test behind `state_of`, `next_code_of`,
`grade.state` and `nowhere_else`. All three round-3 probes now come out
consistent:

- Recorded `#1`, `pr` read failed, `host` found: state "pull request not
  verified", graded not verified, `read_again`, nothing under Exists nowhere
  else. Covered by a new test.
- `none yet`, `appeared` failed, `host` missed: state "pull request not
  verified", nothing under Exists nowhere else. Covered by a new test.
- `none yet`, `appeared` lists one PR, no `pr` fact: state "pull request not
  verified", `read_again`, changes says "pull request appeared". The two
  sections agree there's a pull request. No fixture covers this one (see C1).

The next line is now chosen as a token and its sentence looked up from it
(round-3 P1 closed), md checks a report document's shape before rendering
(A3 partly closed), md's error message names both schemas (M1 half closed)
and the header now says the agent reads the sealed bytes (J3 closed).

## Blocking

### B1 (intent, completeness): "inventory could not be taken" loses its reason and grade

R11 says that when the inventory can't be taken "the report says the
inventory couldn't be taken and why, and lists the read under 'not
verified'". The facts schema documents `inventory.taken` (bool) and a
`reason` on every fact, so an ok fact with `taken: false` is a valid shape
for exactly this case. The script renders it without the reason, grades it
"measured", and puts nothing under Not verified.

Failing input:

```json
{"schema":"coordinate-reconcile-facts/v1","scope":{"kind":"roadmap","name":"d"},
 "record":{"written":"W"},"reconciled_at":"N",
 "holdings":[{"row":{"worker":"t","unit":"u","pull_request":"none yet"},"refused":null,
   "facts":[{"kind":"appeared","status":"ok","prs":[]},
            {"kind":"host","status":"ok","state":"missed"},
            {"kind":"inventory","status":"ok","taken":false,"reason":"instance not on this host"}]}]}
```

`md` prints:

```
## Exists nowhere else
- t: no pull request; worker not found on this read; inventory could not be taken (measured).

## Not verified
None.
```

The same happens when there's no inventory fact at all (a found worker on
a `none yet` row with no `inventory` fact reads "inventory could not be
taken" graded not verified, with no reason anywhere). This was advisory I3
in round 3; it's raised here because read against R11 the reason is
dropped, not just mis-graded. Fix: pick one shape. Either drop `taken`
from the schema and say an inventory that can't be taken arrives as
`status: not_verified` with a reason, or treat `taken: false` as not
verified: grade "not verified", append `(.reason)` to the line, and add it
to `not_verified`. Add a fixture for it.

## Advisory

### Completeness

- C1. The third round-3 case (`none yet`, `appeared` lists a PR, no `pr`
  fact) has no fixture, though round 3 asked for all three.
- C2 (carried). `nowhere_else[].grade` is still not asserted anywhere.
- C3 (carried). Nothing tests that `merge_state` is left out when the `pr`
  read failed.
- C4 (carried). No fixture puts a job or run id in `board.detail`.

### Justification

- J1 (carried). A failed side-effect re-check appears twice (Side effects
  "not verified" and Not verified); a failed deferral check appears once.
  R16 names three side-effect values. The header documents the fourth but
  not why the two are handled differently.
- J2 (carried). DESIGN Decision 2's Implementation Approach still assigns
  the docs/ comparison to `reconcile-check.sh`.

### Intent

- I1 (carried). A side effect with no `fact` gets `code: not_rechecked` but
  grade "verified by reading" (probe: `side_effects:[{row:{action:"merge",
  target:"x"}}]`). The grade defaults `.fact.verdict` to `""`, the code to
  `not_rechecked`.
- I2 (carried). `holdings[].read_at` takes the max over all facts, failed
  reads included.
- I4 (carried). `grade.board` is `null` both with no board fact and with a
  failed board read.
- I5. The `has_pr` comment says "'no pull request' is only ever said when
  it was checked". With no `appeared` fact at all, a `none yet` row plus
  `host found` reads "no pull request; worker found" graded measured. The
  comment overstates what the code guarantees; either treat a missing
  `appeared` fact like a failed one or soften the comment. This depends on
  A4.
- I6. A holding graded "not verified" because a fact is missing, rather
  than failed (recorded `#1` with no facts at all, or an appeared PR with no
  `pr` fact), has no entry under Not verified, so a reader sees "not
  verified" with no reason.
- I7. `state_of` lowercases `pr.state` but `next_code_of` compares it
  case-sensitively: `state: "merged"` renders "merged" with next `wait`
  rather than `drop`. The schema says upper case, so this only bites if a
  reader sends lower case; comparing `ascii_upcase` would close it.

### Pragmatic

- P3 (carried). `grade_of` has one caller.

### Architect

- A1 (carried). `holdings[].state` and `side_effects[].verdict` are prose
  in v1 JSON; `next_code` and `code` cover routing.
- A2 (carried). Per-row `source` exists only on holdings.
- A3 (partly closed). md checks that the report's sections are arrays but
  not their entries: a report with `holdings:[{}]` renders
  "- null (null): null; null (null)" and exits 0.
- A4 (carried). The facts contract still doesn't say when the pass sends
  `appeared`, `host`, `inventory` or `pr` for a holding, which is what I5,
  I6 and B1 hinge on. Issues 2 and 3 need it written down.
- A5 (carried). The workflow comment about macOS bash 3.2 sits over a bare
  `bash` call that resolves to a newer bash on the runner.
- A6. A facts document with `holdings` as an object (not an array) passes
  and yields an empty report with exit 0. `.holdings[]?` swallows the
  shape error.

### Maintainer

- M1 (half closed). The message is fixed; the exit-code line in the header
  still reads "65 the input is not a facts document" though md also takes a
  report and refuses a malformed one with 65.
- M3 (carried). "branch tip differs" puts a live value (`$pr.head`) in
  `recorded`, rendered "record said ...".
- M4 (carried). `phase_known` and `phase_of` each list the recognised phase
  values.
- M5 (carried). The test header claims broader redaction than the script
  does.
- M6 (carried). The `gone|dead|lost` regex has no comment and the failure
  branch's grep omits `lost`.
