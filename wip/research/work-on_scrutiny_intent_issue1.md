# Intent review: reconcile-report.sh (Issue 1) -- round 2

Re-reviewed `skills/coordinate/scripts/reconcile-report.sh` and its test at
`8aa14a6` against DESIGN-coordinate-reconcile.md, PRD-coordinate-reconcile.md
(R16-R21, R29), and PLAN Issue 1's ACs, focused on whether the four round-1
blocking findings actually got fixed and whether the fix itself introduced
anything new that would force Issues 2-5 to reopen this schema. All 48 of
the script's tests pass (up from 36 in round 1).

## Round-1 blocking findings: disposition

**B1 (grades hardcoded, not derived from the read) -- fixed.** `grade.state`
now follows `.refused`/`ok($pr)`/`ok($host)` the same way `state_of` does;
`grade.board` is `null` when `board_of` is `null` and "verified by reading"
otherwise; a new `grade_of($f)` helper grades the leg fact "measured" /
`null` / "not verified" by whether the read was attempted and whether it
succeeded. Verified with the round-1 repro fixture (`pr` status
`not_verified`): `grade.state` now reads "not verified" and `grade.board` is
`null`, matching `state`/`board`. New test "grades follow the read" covers
exactly this case.

**B2 (`merge_state` had no slot) -- fixed.** `holdings[].merge_state` is now
populated from the `pr` fact when it's ok, and the rendered Holding line
shows "merge state \(.merge_state)" when non-null. Covered by the new
"merge state and legs" test, which checks the rendered line for
`merge state BLOCKED`.

**B3 (`leg` fact had no display slot) -- fixed.** `leg_of` renders
`disposition[: result]` and both the JSON (`holdings[].leg`) and the
rendering (`"; leg \(.leg) (\(.grade.leg))"`) now carry it, positioned beside
the pull request state as R12 requires. The positive case (a resolved leg's
result appearing) and the negative case (an unreadable leg landing in
`not_verified` with its reason, `leg` staying `null`) are both tested.

**B4 (a failed deferral-disposal check had nowhere to go) -- fixed.** The
facts-schema comment now documents `status`/`reason` on a deferral entry;
`deferrals[]` construction now requires `(.status // "ok") == "ok"` before
sorting into disposed/undisposed, and a new clause adds a failed deferral
check to `not_verified` with its reason. Tested: a deferral with
`status: "not_verified"` is absent from `deferrals[]` (neither disposed nor
undisposed) and present in `not_verified`.

All four are genuine fixes at the `REPORT_JQ` level, not just new test
coverage papering over the same bug -- I re-ran the round-1 repro fixtures
by hand against the current script and got the corrected output in every
case.

## Round-1 advisory findings: disposition

**A1 (grade invisible in rendered Holding line) -- fixed.** The line now
shows `(\(.grade.state))`, `(\(.grade.leg))`, `(\(.grade.board))` and a fixed
`(inferred)` for phase/next.

**A2 (mode fallback only matched `--intent=stop`) -- fixed.** The regex is
now `--intent(=| +)stop( |$)`, and a new pair of tests confirms both
`--intent stop` (accepted) and `--intent=stopper` (rejected, so it doesn't
over-match).

**A3 (line bound untested for side effects/deferrals) -- fixed.** A new test
renders 10 holdings + 10 side effects + 10 deferrals and checks the output
is at or under `40 + 6*30 = 220` lines (actual: 79, so the bound itself
isn't exercised tightly, but the three-way combination R21 names is now in
the suite where before it was absent).

## New in this round

**Phase classification moved into this script.** The `files` fact now
carries raw `paths[]` instead of a pre-computed `outside_docs` bool, and
`reconcile-report.sh` does the `docs/`-prefix classification itself
(`outside_docs` def). This is a good change, not a regression: it keeps the
classification rule in one place instead of duplicating "what counts as
docs/" logic between whatever produces the `files` fact (Issue 2) and this
script, and R17's docs/-prefix rule is exactly what's implemented
(`startswith("docs/")`, so `docsx/a` is correctly outside). Confirmed by the
`docsx/a` test.

**Unrecognised phase values are now surfaced.** `phase_known` flags any
`phase` value other than `""`, `scoping`, `scoping-ahead`, `executing`
(case-insensitive); such a holding is marked executing and listed under
"not verified". This matches the commit message and is a sensible reading
of R17 ("not guessed at"). One completeness gap: the `not_verified` entry's
reason is the fixed string "unrecognised phase value; marked executing" and
does not include the actual invalid value (e.g. "scoped") the way R2's
unparseable-row handling includes the raw text in a fence. Not blocking --
R17 doesn't require this, and the holding's topic is still named -- but it
would help a person debugging a bad record faster to see what the bad value
actually was.

## Advisory (new)

### A4. Board's grade collapses "no board fact" and "board fact failed to read" into the same `null`

`leg`'s grade is now three-valued (`"measured"` / `null` / `"not verified"`)
so a JSON consumer can tell "no leg to report" apart from "we tried to read
the leg and failed." `board`'s grade stayed two-valued
(`if board_of == null then null else "verified by reading" end`): a holding
with no board fact at all and a holding whose board fact has
`status: "not_verified"` both get `grade.board == null`, even though the
latter is caught elsewhere (the generic `facts[]` loop adds it to
`not_verified`). This doesn't affect the rendered text (the Holding line
only shows the board clause when `.board != null` regardless of which `null`
grade it got), so it's invisible today, but it's an inconsistency in the
JSON contract between two claims the header groups the same way ("measured"
for a live read is listed as covering "a listing read, an inventory, a
leg" -- board's "verified by reading" grade doesn't get the same
not-attempted/failed distinction the leg grade now has). Worth a look before
Issue 5's template or any other JSON consumer starts branching on
`grade.board == null` to mean "nothing to show" -- it currently also means
"we tried and the read failed."

## What's solid

The two-call interface, purity, section order, the seven next-line cases and
the waiting list, the absolute-path/session-id/instance-name scrubbing, and
the refused/unparseable-row handling remain correct and untouched by this
round's diff. All four round-1 blockers are fixed at the source, not just
retested; the facts schema (with `paths[]`, `merge_state`, `leg`, and the
deferral `status`/`reason`) is now a sufficient foundation for Issues 2-5 --
nothing in Issue 2 or 3's stated ACs needs a field this script doesn't
already have a slot for.

## Verdict

No blocking findings. One new advisory (A4, board/leg grade asymmetry) plus
the phase-value-omitted-from-reason nit above; both are polish items for a
JSON consumer, not correctness bugs, and neither forces a rewrite for
Issues 2-5.
