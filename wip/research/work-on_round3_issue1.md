# Round 3 review: Issue 1 (reconcile-report.sh)

Reviewed at 7bdd30b ("keep failed reads out of reconcile report
conclusions") against PLAN Issue 1, DESIGN-coordinate-reconcile.md and PRD
R16-R21, R29, with the round-2 findings in the other `work-on_*_issue1.md`
files. `bash skills/coordinate/scripts/reconcile-report_test.sh`: 57 passed,
0 failed.

The round-2 blocking findings were both from the maintainer panel. The
side-effect one is closed: a failed re-check now gets code `not_verified`, is
graded "not verified" and stays off the waiting list, and there's a test for
it. The "no pull request" one is only half closed. `nowhere_else` now works
out "no pull request" from the row's `pull_request` column and the `appeared`
listing. `state_of`, `next_of` and `grade.state` still treat "there's no ok
`pr` fact" as "there's no pull request". The round-2 finding said `state_of`
already got this right, but that's only true when the holding has no `host`
fact.

Round-2 advisories that were fixed: the handoff source label (holdings only),
`next_code` tokens, md rendering the sealed report, `clone` going through
`safe_path`, the renderer reading `.reasoning.key`, and the testdata trigger
path.

Probes below were run by hand against the current script with small facts
documents.

## Blocking

### B1 (intent, maintainer): "no pull request" is concluded from a missing or failed read

`state_of` (lines 147-155), `next_of` (168-180) and `grade.state` (230-232)
fall through to the `host` fact whenever `ok($pr)` is false. They don't check
whether the row records a pull request or whether the `appeared` listing
succeeded. Three probes show what goes wrong:

- The row has `pull_request: "#1"`, the `pr` read failed and `host` reads
  `found`. You get state `"no pull request; worker found"`, graded
  **measured**, with next line `wait on worker`. That's R18's no-PR case
  applied to a holding that has a pull request, and the header's rule that a
  failed read never keeps a success grade is broken. The same holding gets
  nothing under `nowhere_else`, because `$nopr` reads the row, so two parts
  of the same report disagree.
- The row has `pull_request: "none yet"`, the `appeared` read failed and
  `host` reads `missed`. The state and `nowhere_else` both say "no pull
  request; worker not found on this read" (graded measured), but the listing
  that would have shown a pull request never succeeded.
- The row has `pull_request: "none yet"`, `appeared` finds one PR and there's
  no `pr` fact. `changes` reports "pull request appeared", while the holding's
  state reads "no pull request; worker not found on this read" and its next
  line is `read again, then decide`.

Both fact shapes are valid under the documented facts schema. The test
suite's own bound fixture already puts `pr` and `host` on the same holding.
Fix: work out "no pull request" once, as `$nopr` does now, and have
`state_of`, `next_of`, `grade.state` and `nowhere_else` all use that one
definition. When a PR is recorded or has appeared but the `pr` read failed,
report "not verified" and `read_again`. Also say in the facts schema whether
the pass sends a `pr` fact for a PR that appeared. Add fixtures for all
three cases.

## Advisory

### Completeness

- C1. No fixture covers a failed `pr` read next to an ok `host` fact, or a
  failed `appeared` read. That's why B1 passes the suite.
- C2 (carried). `nowhere_else[].grade` is still not asserted anywhere.
- C3 (carried). Nothing tests that `merge_state` is left out when the `pr`
  read failed.
- C4 (carried). No fixture puts a job or run id in `board.detail`, which is
  copied into the line as free text.

### Justification

- J1. In side effects, a failed re-check now shows up twice: as "not
  verified" under Side effects and again under Not verified. A failed
  deferral check is only listed under Not verified. R16 gives Side effects
  three values (confirmed, not confirmed, not re-checked), so this adds a
  fourth. The header documents it but doesn't say why side effects and
  deferrals are handled differently.
- J2 (carried). DESIGN's Decision 2 Implementation Approach still assigns
  the docs/ comparison to `reconcile-check.sh`.
- J3. The header (lines 7-8) says the pass calls the script twice "so the two
  forms always agree". Now that md renders the sealed report, the two forms
  agree because md renders the same bytes, and the header should say that.

### Intent

- I1. A side effect with no `fact` gets `code: not_rechecked` but is graded
  "verified by reading", because the grade defaults `.fact.verdict` to `""`
  while the code defaults it to `not_rechecked`. The documented schema always
  carries `fact`, but the two defaults should match.
- I2. `holdings[].read_at` takes the maximum over all facts, failed reads
  included, so a timed-out read can set the holding's "Read" time.
- I3. An inventory fact with `status: ok` and `taken: false` renders
  "inventory could not be taken" graded "measured".
- I4 (carried). `grade.board` is `null` both when there's no board fact and
  when the board read failed. The leg grade tells these two cases apart.

### Pragmatic

- P1. `next_code` looks the token up from the prose sentence. It would be
  simpler to compute the token and map it to prose. As written, rewording a
  next line silently turns its code into `null`.
- P2 (carried). `got=` on test line 66 is never read.
- P3 (carried). `grade_of` has one caller.

### Architect

- A1 (carried, partly fixed). `holdings[].state` and
  `side_effects[].verdict` are still prose in the v1 JSON. `next_code` and
  `code` cover routing, so this only matters if a reader branches on the
  state.
- A2. `source` exists per row only on holdings. Issue 4's handoff side
  effects and deferrals will need the same field (additive).
- A3. `md` accepts any document whose schema is report/v1 without checking
  its shape. A malformed one prints half a report and exits 5, which isn't
  one of the documented exit codes.
- A4. The facts contract doesn't say when `host` and `appeared` come with a
  `pr` fact. This is the contract half of B1, and Issues 2 and 3 need it
  stated.
- A5 (carried, reworded). The workflow comment "macOS's /bin/bash is 3.2, the
  floor the scripts target" sits above a bare `bash` call, which on the macOS
  runner resolves to the image's newer bash (see
  check-execute-scripts.yml:208-222). The floor still isn't exercised.
  Either use `scripts/check-bash-floor.sh` or drop the implication.

### Maintainer

- M1. On bad input, md mode prints "input is not a
  coordinate-reconcile-facts/v1 document" even though md also accepts a
  report. Exit code 65's doc line has the same gap.
- M2. The workflow comment is covered in A5. It reads as a guarantee the job
  doesn't give.
- M3 (carried). In the "branch tip differs" change, `recorded` holds a live
  value (`$pr.head`), and the line renders "record said ...".
- M4 (carried). `phase_known` and `phase_of` each list the recognised phase
  values, so the two lists can drift apart.
- M5 (carried). The test header and test line 196 claim broader redaction
  than the script does. Only inventory paths are withheld, and dropped fields
  do the rest.
- M6 (carried). The `\b(gone|dead|lost)\b[^:]` regex has no comment, and the
  failure branch's grep leaves out `lost`.
