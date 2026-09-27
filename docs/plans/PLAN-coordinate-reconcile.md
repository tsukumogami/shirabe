---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-coordinate-reconcile.md
milestone: "Coordinate reconcile"
issue_count: 6
---

# PLAN: coordinate-reconcile

## Status

Active

## Scope Summary

Mechanise the `coordinate` skill's reconcile state: scripts that read the
record, re-check every claim against GitHub and the host, and write a sealed
report into the workflow's context, plus the filled `reconcile` state whose
non-overridable gate holds the workflow until that report exists.

## Decomposition Strategy

Horizontal. The design's components have stable interfaces between them (a
facts document in, a report out; one subcommand per re-check; a seam file to
the record feature), and the pure report function is the prerequisite every
other piece feeds. Building it first means each later issue is tested
against a fixed schema. The work lands as one pull request: nothing forces a
split, and the dependency on the record feature's template is waited out
before execution starts rather than split around.

## Issue Outlines

### Issue 1: feat(coordinate): reconcile report function and schema

**Goal**: Ship `reconcile-report.sh`, the pure function that turns a facts
document into the report JSON (`coordinate-reconcile-report/v1`) and its
rendered text, carrying the PRD's structure, phase, next-line, waiting and
grading rules (R16 to R19, R21).

**Acceptance Criteria**:
- [ ] The facts schema and the report schema are documented in the script
  header, with every field the other scripts produce or read.
- [ ] Fixtures produce the sections of R16 in order, each empty section
  reading "None.".
- [ ] Every entry under "Changed since then" names the holding, the recorded
  value, the live value and the record's `Written:` time; a fixture missing
  any of the four fails.
- [ ] One fixture per R18 case yields the stated next line, and "Waiting on a
  person" lists exactly the holdings and merges R18 names.
- [ ] Every claim carries one grade, and the test asserts the grade per kind:
  a pull request state or branch tip is "measured", a confirmed merge or a
  judged board is "verified by reading", a phase mark or next line is
  "inferred".
- [ ] Phase marks follow R17: a row with `phase` set uses it even when its
  entry point says otherwise; a row without it falls back to entry point and
  mode; a scoping-ahead holding whose facts show `src/x` changed is flagged
  and one showing only `docs/` paths (including `docs/x/y.md`) is not, nor is
  a path like `docsx/a`.
- [ ] A 10-holding fixture renders within R21's line bound, and no fixture's
  rendering contains raw read output.
- [ ] File paths in the report are clone-relative; no fixture's output
  contains a session id, instance path or job id.
- [ ] The script does no I/O besides stdin and stdout (the test runs it with
  an empty `PATH` apart from `jq`).

**Dependencies**: None

**Type**: code
**Files**: `skills/coordinate/scripts/reconcile-report.sh`, `skills/coordinate/scripts/reconcile-report_test.sh`

### Issue 2: feat(coordinate): GitHub re-checks for reconcile

**Goal**: Ship the GitHub-facing subcommands of `reconcile-check.sh` (pull
request, board through the seam, branch, appeared, files, merge, close,
deferral through the seam), each printing one fact in Issue 1's schema, with
every call under a deadline and every row value validated through
`coord-common.sh`'s patterns.

**Acceptance Criteria**:
- [ ] A holding recorded open whose stubbed pull request reads merged yields
  a merged fact with both values; a parked holding back in draft yields a
  draft change.
- [ ] The board subcommand calls the record feature's board check through
  `reconcile-deps.sh` at the verified head, and at the live head too when
  they differ, reporting "head moved" with both shas; a job with no runner
  name reads "fails" naming it, and a board where every job is real reads
  "holds".
- [ ] The files subcommand reads a pull request's file list with pagination,
  stops at its cap with a truncation note, and returns renamed and removed
  files by both paths.
- [ ] A row whose repository, branch, sha, number or topic fails
  `coord-common.sh`'s pattern (for example a branch of `-x` or `a;b`)
  becomes a not-verified fact and reaches no command.
- [ ] `ls-remote` returning nothing reads "branch gone"; a tip that differs
  reads "branch tip differs" with both shas; the URL comes from the
  validated row, not a clone's remote.
- [ ] One pull request appearing on a no-PR holding's branch reads
  "appeared"; two read ambiguous with both listed.
- [ ] A merge in flight whose changed files match at the verified head reads
  "confirmed"; one where the branch moved past the verified head reads "not
  confirmed" although the pull request is merged; a file deleted at the
  verified head is confirmed only by a not-found on the default branch.
- [ ] A close reads confirmed or not confirmed from the target's state; a
  side effect of unknown kind reads "not re-checked" and its "How to confirm"
  text appears in no stub log.
- [ ] A deferral naming an existing issue, closed with a reason, or carried
  forward with a reason reads disposed; one with none reads undisposed.
- [ ] Paths from a pull request's file list with `..`, a leading `/` or a
  control character are refused into "not verified"; others are
  percent-encoded per segment.
- [ ] Each stubbed read made to time out yields a not-verified fact with its
  reason.
- [ ] Every stub log contains only `gh` read subcommands and `gh api` GETs.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code
**Files**: `skills/coordinate/scripts/reconcile-check.sh`, `skills/coordinate/scripts/reconcile-check_test.sh`, `skills/coordinate/scripts/reconcile-deps.sh`

### Issue 3: feat(coordinate): host re-checks for reconcile

**Goal**: Add the host-facing subcommands of `reconcile-check.sh` (listing
with the 30-second re-read, inventory, teardown, request leg), read-only and
contained to the worker's instance.

**Acceptance Criteria**:
- [ ] The listing subcommand does one read and never sleeps; the re-read is
  the pass's (Issue 5). A miss yields a "missed" fact carrying the read time.
- [ ] A match yields "found"; two matching instances yield ambiguous; a
  topic that is a prefix of another topic's slug (`recon` beside
  `reconcile`) doesn't match it.
- [ ] A failing, absent or timed-out workspace-manager command, a timed-out
  in-clone git call, and a timed-out or unreadable request-store read each
  yield a not-verified fact with its reason while GitHub facts are
  unaffected.
- [ ] The inventory lists a commit on a branch deleted on the remote, an
  uncommitted change and a file whose content isn't on the default branch;
  a squash-merged branch whose content landed yields "nothing unique found".
- [ ] Every in-clone git call carries `--no-optional-locks`, `-c
  core.fsmonitor=`, `-c core.hooksPath=/dev/null` and `-c
  protocol.allow=never`; `hash-object` runs with `--no-filters` and never
  `-w`; no stub log shows `fetch`, `pull`, `push` or `checkout`.
- [ ] A symlink out of the instance, a clone outside it and a worktree
  outside it are not read; caps of 20 clones and 200 files produce a
  truncation note.
- [ ] A teardown whose target is absent from both listing reads and from
  disk reads confirmed; one whose directory remains reads not confirmed.
- [ ] A holding whose `return_path` is `leg <request-id>:<leg>` shows its
  leg's result beside the pull request state (a deliver leg's outcome; a work-on leg's terminal status and
  final state; a refusal with its reason); a holding whose `return_path` is
  `message` makes no request-store call.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>

**Type**: code
**Files**: `skills/coordinate/scripts/reconcile-check.sh`, `skills/coordinate/scripts/reconcile-check_test.sh`, `skills/coordinate/scripts/testdata/reconcile/`

### Issue 4: feat(coordinate): record read and rotation handoff for reconcile

**Goal**: Ship `reconcile-read.sh`, which reads the record through the record
feature's reader and, at discipline scope, the predecessor's handoff, and
emits the record as facts input with the refusal cases of R3.

**Acceptance Criteria**:
- [ ] At roadmap scope the exact-title issue is read and a longer title
  containing it is ignored; at discipline scope the record branch's pull
  request body is read; a record whose author or last editor lacks write
  access to the host repository is a refusal (the reader's rule, inherited).
- [ ] A holding the reader's facts refuse (pull request outside the scope's
  repositories, or head branch differing from the row's branch) reaches the
  report as a refused row and triggers no re-check call.
- [ ] No record, two candidates, a candidate without the declaration line,
  an unreadable body and a timed-out read each exit with a distinct code
  naming the case.
- [ ] A row the reader returns as unparseable reaches the facts with its raw
  text for a fence and the reader's reason.
- [ ] The handoff is read through the record feature's `predecessor_handoff`
  read, never by fetching the file directly; its tables are labelled with its
  heading date; its reasoning
  section is emitted verbatim for `reconcile/reasoning.md`; a missing, empty
  or "not recorded" section yields "no reasoning received" and no reasoning
  output; a missing handoff file yields a first rotation.
- [ ] Holdings are read by the record's row keys (`unit`, `entry_point`,
  `mode`, `phase`, `dispatch_status`, `return_path`, `worker`, `repo`,
  `branch`, `verified_head`, `dispatched`, `pull_request`), taken from the
  record feature's reader through `reconcile-deps.sh`, so a key rename there
  is one change here.
- [ ] The reader, board check, deferral check and seal helper are named only
  in `reconcile-deps.sh`.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>

**Requires on the default branch**: the record feature's reader. Issue 2 creates `reconcile-deps.sh`, which this issue extends.

**Type**: code
**Files**: `skills/coordinate/scripts/reconcile-read.sh`, `skills/coordinate/scripts/reconcile-read_test.sh`, `skills/coordinate/scripts/reconcile-deps.sh`

### Issue 5: feat(coordinate): sealed reconcile pass and the reconcile state

**Goal**: Ship `reconcile-pass.sh` and `reconcile-report-get.sh`, and fill
the template's `reconcile` state with the pass as its action, the shared
verdict gate as its non-overridable gate, and `pick_facts` as its target.

**Acceptance Criteria**:
- [ ] The pass runs at most four reads at once, stops launching reads at 20
  seconds, clips each deadline to the time left, and never plans past its
  budget (injected clock).
- [ ] A listing miss is re-read by the pass no sooner than 30 seconds after
  the first read: within the same pass when the wait ends before the
  20-second cutoff, otherwise on a later pass with `pending:`; two misses
  yield "not found on this read", an entry under "Exists nowhere else" and
  an inventory that couldn't be taken, with none of "gone", "dead" or
  "lost"; a miss then a match yields "found".
- [ ] With no record, two candidates or an undeclared candidate, the pass
  prints `blocked:<case>`, writes `reconcile/refusal` naming the case,
  writes no `reconcile/report.json`, and the engine test shows the workflow
  still in `reconcile`; a timed-out record read does the same.
- [ ] It prints exactly one line, `pending:<seq>:<n>:<64 hex>`,
  `blocked:<case>` or `reconciled sealed:<seq>:<64 hex>`, each accepted by
  koto's capture allowlist; every child's stdout goes to stderr.
- [ ] A work file edited between passes, or left by a killed pass, is
  discarded and the visit's reads restart; a new visit discards the old work
  file and `reconcile/*` keys; `reconcile/refusal` and `reconcile/progress`
  are cleared at the start of every pass.
- [ ] The pass refuses to run with `BASH_ENV`, `ENV`, `LD_PRELOAD`,
  `GIT_CONFIG_*`, `GIT_DIR` or a `GH_HOST`, `GH_REPO` or `GH_TOKEN` override
  set; with a `PATH` whose first entry shadows `gh` and a `HOME` pointing
  elsewhere, it still runs the tools from its fixed path; no environment
  variable changes its clock or sleep.
- [ ] Across every test's stub logs, commands match an explicit allowlist:
  `gh pr view`, `gh pr list`, `gh issue view`, `gh issue list`,
  `gh run list`, `gh api` with no `-f`, `-F`, `--input` or non-GET
  `--method`; `git ls-remote`, `status`, `log`, `worktree list`,
  `merge-base --is-ancestor`, `hash-object --no-filters`; `niwa list`;
  `koto context get`, `koto request get`, and `koto context add`/`remove`
  only on `reconcile/` keys.
- [ ] No context key or value the pass writes, from fixtures carrying a
  session id, instance path and job id, contains any of them.
- [ ] The report written by the pass contains no raw stub output and stays
  within R21's line bound for a 10-holding fixture.
- [ ] In the template, `reconcile` has no `accepts`, no `polling`, and one
  transition to `pick_facts` conditioned on a gate declared
  `overridable: false`; no override transition exists; both commands start
  with `env -u BASH_ENV -u ENV`.
- [ ] An engine test drives the state from `pending:` to the sealed line
  and into `pick_facts`; it stays in `reconcile` when the report key is
  absent, stale from an earlier visit, or set by the agent, and when every
  evidence field is submitted.
- [ ] No gate in the template names `reconcile/reasoning.md`.
- [ ] The template declares `PLUGIN_ROOT` without `rebind`, and the
  directive doesn't reference `RECONCILE_SEAL`.
- [ ] The pass reports whether the plugin root lies inside the repository
  being worked on.
- [ ] `reconcile-report-get.sh` takes no sealed token as an argument and
  reads the capture from the session log through `coord-log.sh`; it refuses
  a report whose hash doesn't match; with a log holding a
  `directed_transition` anywhere in the run it names it, and with only
  ordinary transitions it names none.
- [ ] The template passes every template check CI runs, and the mermaid
  companion is regenerated.

**Dependencies**: Blocked by <<ISSUE:2>>, <<ISSUE:3>>, <<ISSUE:4>>

**Requires on the default branch**: the record feature's template, check channel (`coord-verdict.sh`, `coord-log.sh`), board check and deferral check.

**Type**: code
**Files**: `skills/coordinate/scripts/reconcile-pass.sh`, `skills/coordinate/scripts/reconcile-pass_test.sh`, `skills/coordinate/scripts/reconcile-report-get.sh`, `skills/coordinate/scripts/reconcile-report-get_test.sh`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/koto-templates/coordinate.mermaid.md`

### Issue 6: docs(coordinate): reconcile docs, evals and limitations

**Goal**: Point `references/loop.md`'s reconcile section at the state, add
the Known Limitations and the two evals, and declare the scripts' tools.

**Acceptance Criteria**:
- [ ] `loop.md`'s reconcile section names the state, the report keys and
  what the agent does at `pending:` and `blocked:`, and no longer instructs
  the reads by hand.
- [ ] SKILL.md's Known Limitations names shirabe#395, #396, #398, #401,
  koto#250 and koto#251, each with what it costs today, and says where
  liveness, the double-held check and externalised load would attach; no
  rule in the reconcile state or scripts cites one of them as its reason.
- [ ] An eval restarts a coordinator whose record holds a holding that has
  since merged; it passes when the first report up has "Changed since then"
  before "Holding" and names that holding with both states.
- [ ] An eval starts a rotation from a handoff with a reasoning section; it
  passes when the first report attributes the reasoning to the previous
  rotation and doesn't list it among re-checked claims.
- [ ] `requires.tsv` declares every tool the scripts call, and preflight
  passes.
- [ ] A grep of the reconcile scripts and the template's `reconcile` state
  for `settings.json`, `permissions` and `.claude/hooks` finds nothing.
- [ ] The restart eval checks that the scripts ran from the installed plugin
  root.
- [ ] A grep of every added file for the workflow scratch directory's path
  prefix, `private/`, the organization's private repository names,
  UUID-shaped session ids and `<config>+<topic>-<8 hex>` instance names
  finds nothing.

**Dependencies**: Blocked by <<ISSUE:5>>

**Type**: docs
**Files**: `skills/coordinate/references/loop.md`, `skills/coordinate/SKILL.md`, `skills/coordinate/evals/evals.json`, `skills/coordinate/requires.tsv`

## Implementation Sequence

Issue 1 first; it needs neither stubs nor the record feature. Issue 2
follows and creates `reconcile-deps.sh`; Issues 3 and 4 then run in
parallel, 3 because it extends `reconcile-check.sh` and 4 because it adds to
the seam file. Issue 5 needs all three and the record feature's
template, reader, board check, deferral check and check channel on the
default branch. Issue 6 closes. The critical path is 1, 2, 3, 5, 6.
