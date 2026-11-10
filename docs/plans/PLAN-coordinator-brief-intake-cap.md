---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-coordinator-brief-intake-cap.md
milestone: "Coordinator brief intake under the inferred-row cap"
step_count: 3
---

# PLAN: Coordinator brief intake under the inferred-row cap

## Status

Active

## Scope Summary

A successor brief written by hand can mark its rules with an opt-in
`## Standing rules` heading, so the intake reads only the rule sections and a
long handover brief clears `brief-unread` in one run. A capped intake records
how far it read the digest in a per-label Run `briefs-read` row, so re-running
the same digest goes on after the lines it already took and ending rows
converges. The caps, `--end`, the golden briefs' 7, 11 and 11 candidates, and
every row already standing stay as they are.

The work lives in the coordinate skill's scripts (`state-schema.jq`,
`state-stored-set.sh --intake`, `state-handover.sh`), their two test suites,
and the skill's guidance and evals. `render-brief.sh` doesn't change: the
design leaves its refusal of heading lines in free-text fields to a follow-up.
Nothing is filed; the plan lands as one pull request.

## Decomposition Strategy

Walking skeleton. Step 1 runs a 90-line hand-written successor brief, mostly
holdings and one-time takeover steps, end to end: it's recorded under a label,
`--intake` reads it through the opt-in mode of `brief_candidates`, writes only
the rules under the four rule sections that no row already holds plus the
`briefs` row, and the handover check stops listing `brief-unread`. That is the
issue's own test of a fix, and it crosses every part of the intake path the
change touches except the marker. The design's Decision 1 makes this the
first step: the opt-in heading alone meets the acceptance test, and it's
independent of the marker.

Step 2 covers the briefs that still cap, either because they have no heading
or because they really carry more rules than the caps allow. Decision 2 gives
a capped digest a memory: a `briefs-read` row that the next intake of the same
digest starts from, so a row a person ended doesn't come back. Decision 4
makes the start a fourth parameter of `brief_intake_plan` rather than a second
function, so every caller states where its plan begins, and Decision 5 drops
the marker in the completing write with no entry of its own. Step 2 also
changes the gap's capped fix text to name the `## Standing rules` rewrite
first. That text names step 1's heading, so step 2 lands after step 1 even
though its code doesn't depend on it.

Step 3 is the guidance a coordinator follows when it writes a successor brief
by hand and when an intake caps. It quotes step 2's fix text, so it comes
last.

## Steps

### Step 1: a successor brief with its rules under `## Standing rules` clears brief-unread in one intake

**Goal**: A 90-line hand-written successor brief, mostly holdings and one-time takeover steps, with its rules under an exact `## Standing rules` heading, recorded with `--host briefs:LABEL` and taken with `state-stored-set.sh --intake LABEL`, crosses `brief_candidates`' opt-in mode, the intake's write of rule rows and the `briefs` row, and the handover check, which stops listing `brief-unread LABEL`. A brief without that heading is read exactly as today.

**Acceptance Criteria**:

- [ ] The 90-line successor fixture, on a record already holding some of its rules as Standing rows of another Source: `--intake LABEL` exits 0 and writes one `inferred brief LABEL <digest>` row per rule under the four rule sections that no row holds; a rule restated word for word gets no row, and no holdings or takeover-step sentence gets one.
- [ ] After that intake the Run `briefs` row reads `LABEL sha256:<digest>`, `state-handover.sh --check` no longer lists `brief-unread LABEL`, and the brief file's digest is unchanged.
- [ ] The same 90 lines without the heading, on the same record: `--intake` exits 1 with `took T of the brief's lines; N of its lines can't be taken under the caps` on stderr, writes no `briefs` row, and the handover check still lists `brief-unread LABEL` naming the same N.
- [ ] A brief with 61 rules under `## Standing rules` on an empty record writes 60 rows, the first 60 in order, exits 1 with `took 60 of the brief's lines; 1 of its lines can't be taken under the caps`, and the handover check lists `brief-unread LABEL` naming 1 line.
- [ ] `brief_candidates` over a brief whose rule-like heading is `## Standing Rules`, `## Standing rules (kept)`, `### Standing rules`, or `## Standing` + non-breaking space + `rules` returns today's list: its preamble and the sentences under that heading and every non-excluded section are all present.
- [ ] A brief whose only `## Standing rules` line sits inside a fenced block gets today's list, with the fenced line not among the candidates; the same brief with the heading outside the fence and every line ending in CRLF gets the opt-in list.
- [ ] In opt-in mode, sentences above the first `#` or `##` heading, under a `#` heading, under any other `##` section (such as `## Holdings`), and under each of the renderer's six excluded sections are not candidates, and no heading line is.
- [ ] In opt-in mode, a sentence under a `###` subsection inside `## Standing rules` is a candidate, and sentences under `## Decisions already made`, `## Out of scope` and `## Workspace rules` are candidates alongside it, in brief order, each once under `norm_text`.
- [ ] The golden briefs still give 7, 11 and 11 candidates, the lists `brief-kept.json` pins, and their first intakes still write exactly those rows and clear the gap.
- [ ] A hand-written brief with `## Out of scope` and no opt-in heading still yields its preamble sentences and the sentences under its other sections alongside the out-of-scope lines, as today's filter does.
- [ ] A brief whose `## Standing rules` section is empty gives `[]` from `brief_candidates`; its intake exits 0, writes no rule row, writes the `briefs` row, and stderr names a count equal to every non-heading sentence of the brief.
- [ ] Every opt-in intake prints on stderr how many of the brief's sentences sat outside the rule sections (the 90-line fixture's known count); an intake of a brief without the heading prints no such line.
- [ ] The brief's path appears nowhere in the intake's stdout or stderr, in the handover check's output, or in the rows and entries the intake writes, in either mode.

**Check**: Run `bash skills/coordinate/scripts/state-schema_test.sh` and `bash skills/coordinate/scripts/brief-intake_engine_test.sh` and see every criterion's case pass, with the existing golden and 61-sentence cases still green. The end-to-end path is the engine suite's 90-line successor case: `--intake LABEL` exits 0, the `briefs` row `LABEL sha256:<digest>` is in the record, and the handover check's gaps no longer include `brief-unread LABEL`.

**Dependencies**: None

**Files**: `skills/coordinate/scripts/state-schema.jq`, `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/state-schema_test.sh`, `skills/coordinate/scripts/brief-intake_engine_test.sh`, `skills/coordinate/scripts/testdata/standing-rules/`

### Step 2: a capped intake of the same digest goes on after the lines it already took

**Goal**: A brief that still caps leaves a per-label Run `briefs-read` row `<label> sha256:<64 hex> <c>/<n>`, and the next `--intake` of that digest with the same n starts its writes at candidate c, so a row a person ended doesn't come back and clearing a cap converges; the intake that completes writes `briefs` and drops `briefs-read` in the same write. The handover check counts from the same start, and its capped fix text names the `## Standing rules` rewrite first.

**Acceptance Criteria**:

- [ ] The 61-sentence brief under label `lane` exits 1 with 60 rows written and leaves Run `briefs-read` `lane <D> 60/61`. After one of its rows is ended, `--intake lane` exits 0, writes only `- Decision 61 holds for every lane.` (not the ended sentence), and the same write holds `briefs` `lane <D>` and no `briefs-read` row for `lane`.
- [ ] A headingless brief of well over 60 lines caps, and most of its rows are ended. One re-run writes only candidates from the marker's c onward, no ended sentence reappears in Standing, and further rounds of ending and re-running end with the `briefs` row written and exit 0.
- [ ] A seeded `briefs-read` row for `lane` naming another digest, or the current digest with an n other than the candidate count, is ignored: the intake writes from candidate 0, the same first 60 rows a fresh record gets, and leaves its own `<c>/<n>` in place of the seeded row.
- [ ] A new digest under the same label reads whole, ignoring the old marker, and ends only the earlier digest's rows it states nowhere. A row of the earlier digest whose sentence the new brief states before the new digest's own marker stays in Standing across that digest's re-run from c.
- [ ] A capped re-run that writes and ends nothing exits 1 and leaves the record unchanged, `briefs-read` row included, byte for byte. A capped run whose ends leave no room, so it takes no candidate (c = 0), writes its ends and no `briefs-read` row, and the next run starts at candidate 0.
- [ ] A state write holding `briefs-read` with c = 0, c = n, c > n, a digest that isn't `sha256:<64 hex>`, or two rows for one label is refused and the record is unchanged. `state-stored-set.sh --run briefs-read ...` exits 64 and writes nothing.
- [ ] On a record holding a marker, the count of untaken lines that `state-handover.sh --check` names for `brief-unread lane` equals the N in the intake's own `N of its lines can't be taken under the caps` for the same record and brief.
- [ ] The capped `brief-unread` fix text for label L and count N reads exactly `state-stored-set.sh --intake L --by <you>; N of its lines can't be taken under the caps (60 inferred rule rows, 120 rule rows): when they aren't standing rules, have the brief rewritten with its rules under ## Standing rules and record it under the same label (state-stored-set.sh --host briefs:L <absolute path>); otherwise ask a person which rule rows to confirm or end; then run it again, and it goes on after the lines it already took`, and the 61-sentence gate check and the 120-rule-cap gap match it. The uncapped form stays `state-stored-set.sh --intake L --by <you>`.
- [ ] After a rotation carry (`state-open.sh --carry`) and after a restart carry of a record capped at `lane <D> 60/61`, the successor's record holds that `briefs-read` row and the 60 Standing rows it went past; ending one there and re-running writes the 61st sentence, writes `briefs` and drops `briefs-read`.
- [ ] A capped write that leaves a marker adds, after its rule and end entries, the run entry `Run briefs-read L D c/n set by WHO.` A completing intake adds only `Run briefs L D set by WHO.`, with no entry for the marker's removal. The brief's path appears in none of the capped stderr, the gap's fix text or either run entry.
- [ ] `--intake` still exits 0 when the brief is taken or was already taken and 1 when a cap stops it, with `took T of the brief's lines; N of its lines can't be taken under the caps` on stderr, and that stderr still ends with `confirm or end one first` when the inferred cap stops it and `end one first` when the 120-rule cap does.
- [ ] `brief_intake_plan` called with a start of 0 gives the same ends, room and untaken as today on the existing plan cases, with each write naming its index in the candidate list; called with a start of 2, its writes begin at index 2 while its ends are still tested against every candidate. A three-argument call is a jq error.
- [ ] A record capped by a headingless brief under `lane`, marker present, clears when a rewrite with its rules under `## Standing rules` is recorded with `--host briefs:lane <absolute path>` and taken: exit 0, the earlier digest's rows it doesn't state ended, `briefs` `lane <new digest>` written, no `briefs-read` row, and `brief-unread lane` no longer listed.
- [ ] An intake of each golden brief on an empty record still writes its 7, 11 or 11 rows, exits 0, and leaves no `briefs-read` row and no `Run briefs-read` entry.

**Check**: run `bash skills/coordinate/scripts/brief-intake_engine_test.sh` and `bash skills/coordinate/scripts/state-schema_test.sh` and see every case above pass, in particular the case `a capped 61-sentence brief converges`: the brief caps at 60 with `briefs-read` `lane <D> 60/61`, one row is ended, and the re-run writes the 61st sentence, lands the `briefs` row and leaves no `briefs-read` row, exit 0.

**Dependencies**: Step 1

**Files**: `skills/coordinate/scripts/state-schema.jq`, `skills/coordinate/scripts/state-stored-set.sh`, `skills/coordinate/scripts/state-handover.sh`, `skills/coordinate/scripts/state-schema_test.sh`, `skills/coordinate/scripts/brief-intake_engine_test.sh`

### Step 3: a coordinator writing a successor brief by hand files its rules under `## Standing rules`

A coordinator handing a run over writes the successor brief with its rules under `## Standing rules`, and follows the new fix text when an intake caps.

## Implementation Sequence

The steps run in order, 1 to 3, in one pull request. Step 2 waits on step 1
because its fix text and its rewrite criterion name step 1's heading, and step
3 waits on step 2 because its guidance and evals quote that fix text. None of
them runs beside another. The plan's owner details step 3 after step 2's work
reaches its terminal, in a commit that touches only this plan.
