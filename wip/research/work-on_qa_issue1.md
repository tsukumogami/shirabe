# QA: Issue 1, reconcile-report.sh

Script under test: `skills/coordinate/scripts/reconcile-report.sh`, checked against
the Issue 1 acceptance criteria in `docs/plans/PLAN-coordinate-reconcile.md`
and PRD R16 to R19 and R21. Fixtures are hand-built facts documents in a
scratch directory outside the repo (`$QA`). No repository file was edited.
All scenarios can be automated: the script is a pure stdin/stdout function.

Result: 13 scenarios run, 13 passed, 0 failed. There are three observations
below, none of which breaks an acceptance criterion as written.

## Test suite

`bash skills/coordinate/scripts/reconcile-report_test.sh` prints `passed=64 failed=0` and exits 0.

## Fixtures

| File | What it models |
|------|----------------|
| f1-restart-merged.json | Roadmap restart. The recorded pull request #101 now reads MERGED, the branch is gone, and a merge side effect is confirmed |
| f2-worker-no-pr-missed.json | Two no-PR holdings: one whose worker was missed on both listing reads and has an inventory with unpushed work, and one whose worker was found |
| f3-scoping-src.json | Four holdings. A scoping entry point with `src/x/main.go` changed. A `--intent=stop` mode with only `docs/x/y.md` and `docs/PRD.md`. A scoping entry point with `phase=executing`. `phase=Scoping` with `docsx/a` changed. Also a merge that is not confirmed |
| f4-discipline-handoff.json | Discipline start from a handoff: a row with `source: handoff`, a leg, a draft regression, a side effect of unknown kind, one undisposed and one disposed deferral, `reasoning: present` |
| f5-timeouts.json | The pr and board reads time out on a PR holding. The host and inventory reads time out on a no-PR holding. A close re-check and a deferral check time out, and one record row is unparseable |
| f6/f7/f8 (generated from gen10.jq) | 10 holdings: a stress case, a realistic case and a total-outage case |
| f9-leaky-reasons.json | Probes: reasons carrying an absolute path, a session id, a multi-line JSON payload, and an inventory path starting with `~/` |

## Scenarios

**S1. Documented schemas: PASS.** The script header documents
`coordinate-reconcile-facts/v1` (scope, record, reconciled_at, holdings with
row, refused and facts for each fact kind, side_effects, deferrals, reasoning,
unparseable) and `coordinate-reconcile-report/v1` (header, changes, holdings
with next_code and grades, waiting, nowhere_else, side_effects with code,
deferrals, reasoning, not_verified). Every field the jq reads or emits is
listed there, including `read_at`, `reads`, `how` and `merge_state`.

**S2. Sections in R16 order, with "None." for an empty section: PASS.** In
every md run (f1 to f5) the sections come in this order: header, Changed
since then, Holding, Waiting on a person, Exists nowhere else, Side effects,
Undisposed deferrals, Predecessor's reasoning (f4 only, discipline scope), and
Not verified. For example, f1 shows "Waiting on a person / None.", "Exists
nowhere else / None.", "Undisposed deferrals / None." and "Not verified /
None.". f4 has "## Predecessor's reasoning" and the roadmap fixtures don't.

**S3. Change entries carry all four values: PASS.** f1 md:
`- record-feature: pull request: record said open, now merged (written 2026-09-20T10:00:00Z; measured).`
and `- record-feature: branch: record said feat/record, now branch gone (written ...)`.
f3: `scope-docs: head moved: record said cccc333, now dddd444 (written ...)`.
f4: `docs-sweep: draft: record said ready (parked), now draft (...)`. In the
JSON, each change has topic, recorded, live and written. The "a fixture
missing any of the four fails" half is enforced in the test at
reconcile-report_test.sh lines 87-91.

**S4. R18 next lines, all seven cases: PASS.**
- merged gives "drop from holdings" (f1, record-feature)
- closed gives "decide: re-dispatch or drop" (f3, phase-overrides)
- open with a failing board gives "worker fixes CI" (f3, scope-docs, "board fails: job lint has no runner")
- open with a holding board and live head equal to verified head gives "ready to land" (f3, scope-src)
- open otherwise gives "wait on worker" (f3 docsx-scope, which has no board; f4 docs-sweep)
- no PR with the worker found gives "wait on worker" (f2, host-found)
- no PR with the worker not found gives "read again, then decide" (f2, host-checks)

**S5. Waiting on a person lists exactly what R18 names: PASS.** f3 JSON
`.waiting` is
`[{"topic":"scope-src","why":"ready to land"},{"topic":"phase-overrides","why":"decide: re-dispatch or drop"},{"topic":"#199","why":"merge not confirmed"}]`.
Neither the fix_ci holding nor the wait holding appears. f1, f2, f4 and f5
have empty waiting lists, which is correct: no land, decide or unconfirmed merge.

**S6. Grades by kind: PASS.** PR state is "measured" (f1, f3). A branch
change is "measured" (f1). A board is "verified by reading" (f3, both holds
and fails). A confirmed merge is "verified by reading" (f1 side effect). An
unconfirmed merge is "verified by reading" (f3). Phase and next are
"inferred" on every holding. A leg is "measured" (f4). A not-re-checked side
effect is "inferred" (f4). A failed read is graded "not verified" and never
"measured" (f5 holdings, side effect and nowhere-else).

**S7. Phase marks under R17: PASS.** Taken from f3 JSON:
- scope-src: entry point `shirabe:scope`, empty phase, so "scoping ahead", with `phase_flag: true` (src/x changed)
- scope-docs: mode `--intent=stop`, empty phase, so "scoping ahead", with `phase_flag: false` (only `docs/x/y.md` and `docs/PRD.md`)
- phase-overrides: entry point `shirabe:scope` but `phase: executing`, so "executing" (the phase column wins)
- docsx-scope: `phase: Scoping` (mixed case), so "scoping ahead", with `phase_flag: true` for `docsx/a`

The AC wording "nor is a path like `docsx/a`" reads as "`docsx/a` is not
treated as inside docs/". The script does that, and the header states it.

**S8. 10-holding line bound: PASS.** With the realistic f7 (10 holdings, one
side effect), `md | wc -l` gives 72. The bound is 40 + 6*11 = 106. The test
suite's own 10-holding fixture passes at 100 or fewer.

**S9. No raw read output: PASS for realistic facts.** An extra `stdout`
field on a fact is dropped (test suite, RAW-GH-OUTPUT). Fixtures f1 to f5
contain no command output, JSON or log lines. The only quoted text is the
unparseable record row in f5, which R21 allows. See observation 2 for
reasons.

**S10. Clone-relative paths and no identifiers: PASS for realistic facts.**
f2's inventory has an absolute clone and an absolute path. Both render as
"(absolute path withheld)", while `public/shirabe: commit skills/...` renders
as is. None of f1 to f5 contain a session id, instance path or job id. See
observation 2.

**S11. Purity: PASS.** Running
`env -i PATH=$QA/onlyjq /bin/bash reconcile-report.sh md < f5-timeouts.json`,
where `$QA/onlyjq` holds only a jq symlink, renders the full report. The
suite's purity check covers only `json`, so this run adds `md`.

**S12. Timed-out reads land under Not verified: PASS.** f5 md lists
`slow-one: pr: gh pr view timed out after 20s`, `slow-one: board: timed out after 20s`,
`no-pr-host-timeout: host: niwa list timed out after 10s`,
`no-pr-host-timeout: inventory: git timed out`,
`deferral retry flake: gh issue list timed out` and `close #77: timed out`,
along with the unparseable row and its raw text in a fence. The holding
states read "pull request not verified (not verified)" and "not verified
(not verified)", and both next lines read "read again, then decide". The
timed-out deferral appears in neither disposed nor undisposed.

**S13. The md renderer and the exit codes behave: PASS.** Rendering f4's
report JSON with `md` produces bytes identical to `md` run directly on the
facts (`cmp` reports IDENTICAL). No argument exits 64 with a usage line.
Non-JSON input exits 65 with "input is not a coordinate-reconcile-facts/v1
document".

## Observations (not AC failures)

1. **R21 is not enforced by construction.** Nothing caps the rendered length.
   The contrived stress fixture f6 renders 121 lines against a bound of 106.
   Each of its holdings has an "appeared" read with two PRs next to a
   recorded PR, plus two board reads, one of which failed. The total-outage
   fixture f8 renders 112 against 106: every read times out, there are two
   board reads per holding, and the host is read for PR holdings. Realistic
   facts stay well under the bound, as S8 shows. The margin depends on the
   Issue 2 and 3 producers not emitting that many facts per holding. A cap,
   or a test that uses the densest legal fact set, would make the bound
   hold for any input.
2. **Reasons pass through verbatim.** In f9, a reason carrying
   `/home/someone/.niwa/instances/tsuku-7` and a session UUID shows up in the
   Not verified section. A multi-line JSON payload used as a side-effect
   reason is rendered raw across two lines. An inventory path starting with
   `~/.claude/jobs/<id>/...` is not withheld, because `safe_path` only
   catches a leading `/`. This meets the AC as long as the producers emit
   short reasons with no paths. It is a hardening gap if they ever pass
   stderr through.
3. **Cosmetic issues.** The verdict renders as "not rechecked", while R16
   says "not re-checked". A no-PR holding with no inventory fact at all (f2,
   host-found) reads "inventory could not be taken (not verified)" in
   "Exists nowhere else" but gets no entry under Not verified. That's fine if
   the pass always supplies an inventory fact.
