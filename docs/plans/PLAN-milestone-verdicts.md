---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-milestone-verdicts.md
milestone: "Milestone verdicts"
issue_count: 6
---

# PLAN: Milestone verdicts

## Status

Active

## Scope Summary

Make the coordinator close every milestone on a `roadmap/v2` roadmap on a
recorded, checked verdict instead of a merge, carry goal fit against the
milestone's Evidence, reopen a Done milestone when its Evidence later fails,
and stop the completion cascade from touching milestone roadmaps, as
`docs/designs/DESIGN-milestone-verdicts.md` designs it.

## Decomposition Strategy

**Walking skeleton, one PR.** The design couples a new script, the record
codec, the status writer, the picker and the koto template at runtime, and
the riskiest seam is the first one: the `landed` tick on a milestone roadmap
reaching a verdict step instead of the Done write, with the verdict entry
checked and the roadmap edit opened. Step 1 builds that path end to end for
the two verdicts that need no follow-ups, with the guards that keep a merged
milestone off the picker, so after step 1 a coordinator on a milestone
roadmap already can't set Done by merge and can close a milestone on a
verdict. Each later step adds one observable behaviour on top and extends
the same acceptance suite, `skills/coordinate/scripts/milestone-verdicts_test.sh`.

The work stays one pull request: the repository's Delivery Preference is
the default (`consolidated`), and no split branch fires; each step is a
building block of one outcome, not an increment a reader would use alone.
Steps run one at a time in the order below. Steps after the first are
outlined here and detailed just before they start, from what the earlier
steps taught.

Every step: new and changed scripts run on bash 3.2 and are listed in
`scripts/check-bash-floor.sh`; every new `*_test.sh` is picked up by
`skills/coordinate/scripts/run-tests.sh` (or listed in the workflow that runs
its skill's tests); suites are run locally by executing them directly
(`./x_test.sh`), and any suite that stalls on the host is named in the pull
request body with CI as its build of record.

## Issue Outlines

### Issue 1: feat(coordinate): close milestones on a recorded verdict

**Type**: skeleton
**Complexity**: critical

**Goal**: On a `roadmap/v2` roadmap, ticking `landed` writes a verdict-owed
mark and reaches a verdict step instead of opening a Done pull request; a
verdict entry checked against the milestone's Evidence is posted to the
record and followed by the one roadmap pull request it calls for; the picker
and `dispatch_check` never offer a milestone with a verdict owed; a finished
milestone with nothing to merge reaches `landed`; and feature roadmaps behave
exactly as before.

**Acceptance Criteria**:
- [ ] `skills/coordinate/scripts/milestone.sh` exists with `schema`,
  `evidence`, `check-verdict` and `progress-has`, reads files only, and its
  suite `milestone_test.sh` shows: `schema` prints `roadmap/v2` for a v2
  fixture and the v1 value for a v1 fixture; `evidence` prints a milestone's
  numbered clauses as JSON with wrapped lines joined and exits 2 for a tag
  that isn't a milestone with Evidence; `check-verdict` accepts one
  well-formed entry of each verdict and refuses, naming the line, a missing
  or reordered line, a clause count different from the milestone's Evidence,
  a verified verdict with a clause not held or `does not fit` or a follow-up
  or changes named, verified with follow-ups with no follow-up, changes
  needed with every clause held and `fits` or with `Changes needed: none`, a
  `Checked on` later than `--today`, and a `Checked by` containing the
  `--worker` topic in any letter case.
- [ ] The record codec accepts and renders the Work kind `verdict-owed` and
  the Side effects Actions `milestone-done` and `milestone-verdict`
  (`record-codec.jq`, `record-parse.sh`, `record-render.sh`,
  `record-state.sh`): a body holding each round-trips through parse and
  render unchanged, and an unknown kind or Action is still refused;
  `record-append.sh` accepts the entry kind `milestone-verdict` and still
  refuses an unknown kind.
- [ ] `roadmap-status.sh --unit TAG` on a v2 roadmap reads the schema before
  any other refusal, opens no pull request (the GitHub stand-in's log has no
  branch, commit or `pr create` call), writes a `verdict-owed` Work row whose
  Who is the holding's topic, or `none` when no holding names TAG (a
  milestone with no worker, whose `--worker` check is then skipped), prints
  `verdict-owed <TAG>` and exits 0; run
  again with the row present it prints the same and writes nothing; on a v1
  roadmap every existing `roadmap-status_test.sh` case still passes.
- [ ] `roadmap-status.sh --verdict TAG --entry-file F --entry-url URL`
  requires TAG's `verdict-owed` row, checks the entry with `milestone.sh
  check-verdict --worker <the row's Who>` against the roadmap at the entry's
  Source commit, and for a verified verdict opens one pull request whose
  roadmap diff sets TAG's Status to Done, removes its Needs line, appends the
  work checked to Delivered and appends the Progress line
  `- <date>: <TAG> -- verified, checked by <checker> (<URL>, <hash8>)`, with
  the entry in the pull request body; for changes needed the diff leaves
  Status and Delivered unchanged and adds the Progress line; it writes a
  Side effects row with Action `milestone-done` or `milestone-verdict`; the
  stand-in's log shows no merge call. It refuses (exit 65, nothing opened) a
  TAG with no `verdict-owed` row, an entry `check-verdict` refuses, a
  verified-with-follow-ups verdict (until step 2 adds follow-ups, so Done is
  never written without them), an entry file over 16 KiB, a TAG outside the
  heading-tag grammar, and checker or Work checked values outside their
  closed shapes.
- [ ] `roadmap-status.sh --confirm TAG` checks per Action (Done for
  `roadmap-status` and `milestone-done`, the entry URL in Progress for
  `milestone-verdict`), clears TAG's `verdict-owed` row when it passes, and
  exits 1 writing nothing while the default branch doesn't show it;
  `--list` includes the new Actions with an `action` field.
- [ ] `pick-facts.sh` reports `verdict_owed: true` for a unit with a
  `verdict-owed` row, with and without a holding, and `dispatch_check`
  (`deferral-check.sh`) refuses a topic whose unit has one, with a new
  verdict word and code in `coord-verdict.sh` and its table test.
- [ ] The template: `roadmap_status` accepts `status: verdict_owed`, which
  routes to a new agent state `milestone_verdict` accepting `verdict:
  recorded|deferred` and `unit`; `recorded` goes to `record`, whose
  `record-confirm.sh` rule requires a pending `milestone-done` or
  `milestone-verdict` row naming the unit; `deferred` goes to `wait`. The
  directives for `milestone_verdict`, `classify_report` (a milestone
  finished with nothing to merge is classified done and `landed` ticked, not
  sent back to name a pull request), `merge_confirm` and `merged_facts` (no
  status-line pull request on a milestone roadmap) say so;
  `coordinate.mermaid.md`, the structure test's WANT list,
  `testdata/rule-coverage.tsv` and the template checks are updated, and
  `scripts/check-template-directives.sh`,
  `scripts/validate-template-mermaid.sh` and
  `coordinate-template-structure_engine_test.sh` pass.
- [ ] An engine test with real koto (modelled on `writeback_engine_test.sh`)
  shows the template's behaviour, not just its text: ticking `landed` for a
  unit on a v2 roadmap reaches `milestone_verdict` with no merge-driven
  status call in the GitHub stand-in's log, and on a v1 roadmap still opens
  the Done pull request; a `done` report with no pull request for a v2
  milestone, fed through `classify_report`, doesn't return to `wait` with the
  name-your-pull-request directive; and the rendered `merge_confirm` and
  `merged_facts` directives for a unit on the v2 roadmap contain no
  status-line pull request instruction while the v1 rendering still does
  (`rule-coverage.tsv` pins the new phrases).
- [ ] `milestone-verdicts_test.sh` starts from an empty record and a test
  milestone roadmap with a PR-bearing milestone (two Evidence clauses) and a
  host-state milestone, ticks `landed` for each through
  `roadmap-status.sh --unit`, records a verified verdict for each through
  `milestone.sh check-verdict`, `record-append.sh` and
  `roadmap-status.sh --verdict`, and finds two `milestone-verdict` entries
  each passing the check with a `Checked by:` naming the coordinator's
  session; before `--confirm` the picker reports both `verdict_owed`, and
  after the stand-in's default branch takes each edit and `--confirm` runs
  both read Done with no `verdict-owed` row.
- [ ] Every script changed or added is in `scripts/check-bash-floor.sh`'s
  coordinate list (with the existing tests of the scripts it changes) and
  passes there; `run-tests.sh` passes.

**Dependencies**: None

### Issue 2: feat(coordinate): hold and carry a verdict that waits

**Type**: refinement
**Complexity**: testable

**Goal**: Close-out refuses while a verdict is owed, a deferred verdict
comes back at each pick, a confirmed changes-needed verdict leaves a rework
row that the milestone's next brief quotes, a verified-with-follow-ups
verdict adds its follow-up milestones in the same edit, and the verdict
writer refuses a Source commit the default branch doesn't contain and an
entry file that differs from the posted comment.

Step 1 landed (build on it, don't redo it): `milestone.sh` with `schema`,
`evidence`, `check-verdict` and `progress-has`; the `verdict-owed` Work kind
and `milestone-done` and `milestone-verdict` Actions (the codec closes only
the `milestone-` prefix of the Action column); the `VERDICT_WRITER` flag
that lets only `roadmap-status.sh` change a verdict-owed row; schema-gated
`--unit` (Who `none` when no holding names the milestone);
`--verdict` for verified and changes-needed, refusing verified with
follow-ups, a milestone already Done, Evidence changed since Source, and a
second pending edit; per-Action `--confirm` and `--list`; `verdict_owed` in
`pick-facts.sh` and the `dispatch_check` refusal (code 49); the
`milestone_verdict` state with `verdict: recorded|deferred`; the
`ROADMAP_FORM` koto variable and the
`references/landing-{feature,milestone}-roadmap.md` guidance; and the suites
`milestone_test.sh`, `milestone-verdicts_test.sh` and
`milestone-verdict_engine_test.sh`.

**Acceptance Criteria**:
- [ ] `closeout-read.sh` refuses with a `verdict-owed <tag>` reason while any
  `verdict-owed` Work row stands, routes through `roadmap_blocked` as its
  other blockers do (with `coord-verdict.sh`'s table and test updated if a
  new word is needed), and still closes the test roadmap once every
  milestone reads Done with no such row; `closeout-read_test.sh` covers both.
- [ ] The pick directive lists each unit whose `verdict_owed` is true as a
  verdict to give, and `milestone-verdict_engine_test.sh` shows a deferred
  verdict: `verdict: deferred` returns to `wait` with the row standing, the
  picker passes over the milestone with and without its holding, and a later
  `landed` tick reaches `milestone_verdict` again without writing a second
  row.
- [ ] `roadmap-status.sh --confirm` on a `milestone-verdict` (changes needed)
  row writes a `rework` Work row for the tag whose Next carries the verdict's
  Changes needed line and its not-held clause numbers. The codec accepts the
  `rework` kind and refuses rework text outside its closed shape (one
  paragraph, at most 600 bytes, no URLs or markdown links, no control
  characters). `pick-facts.sh` reports `rework` for the unit, and
  `render-brief.sh` quotes it into the brief's acceptance under a fixed
  heading that labels it a report to check against the Evidence, not
  instructions. A successful `dispatch-worker.sh` clears the row, and the
  picker offers the milestone (In progress, no holding) again.
- [ ] `roadmap-status.sh --verdict --follow-ups FILE` accepts verified with
  follow-ups. In the same pull request it adds each `new:` follow-up as its
  FILE section (a `### <tag>: <title>` heading with non-empty Outcome,
  Evidence, Left open and Dependencies) after the last milestone, applies
  each `amend <tag>:` section from FILE to that milestone with a Progress
  line naming the amendment, and sets Done. The suite checks the added
  sections' text and the amended milestone's changed lines in the diff. It
  refuses a `new:` tag already used, a `new:` with no FILE section, an
  `amend` of a tag the roadmap lacks, a section missing a required field,
  follow-up text failing the redaction or control-character check, and a
  FILE over 32 KiB.
- [ ] `--verdict` refuses a Source commit the default branch doesn't contain
  (the GitHub stand-in in `testdata/gh` gains the compare read it needs). It
  also refuses an entry file whose text differs from the comment at
  `--entry-url` (re-read through the record's comment API and required to
  sit on this run's record issue with the `milestone-verdict` kind marker).
  After `--drop` of a pending edit whose pull request closed unmerged, the
  same entry's `--verdict` opens a new edit.
- [ ] `milestone-verdicts_test.sh` gains a changes-needed verdict confirmed
  into a rework row and re-offered, a verified-with-follow-ups verdict, and
  close-out refused then passing. Every new or changed script and test is in
  `scripts/check-bash-floor.sh`'s coordinate list. `run-tests.sh` and the
  coordinate engine suites that run on this host pass, and the PR body names
  those that stall.

**Dependencies**: Issue 1

### Issue 3: fix(work-on): cascade leaves milestone roadmaps alone

**Type**: refinement
**Complexity**: testable

**Goal**: When a PLAN completes under a `roadmap/v2` roadmap, the completion
cascade (`skills/work-on/scripts/run-cascade.sh`) writes nothing to the
roadmap, never transitions or deletes it, records its roadmap step `skipped`
with a detail naming the milestone Done rule, and reports `completed` when
no other step failed; feature roadmaps keep today's behaviour, including the
`**Downstream:**` Done write and the not-found `partial`.

This step is independent of the coordinate scripts steps 1 and 2 changed.
The coordinator side already never writes Done on landing for a milestone
roadmap (step 1), so this closes the remaining merge-driven path.

**Acceptance Criteria**:
- [ ] `handle_roadmap` reads the roadmap's frontmatter `schema:` before its
  `**Downstream:**` lookup. For `roadmap/v2` it records the step through
  `add_step` with action `update_roadmap_feature`, the roadmap path as
  target, `found_in` null, status `skipped` and the detail `milestone
  roadmap: status follows a recorded verdict (roadmap format, When a
  milestone is Done)`. It writes nothing to the file and returns without
  calling `handle_roadmap_deletion`, even when the roadmap carries a
  `**Downstream:**` line naming the plan.
- [ ] A new `run-cascade_test.sh` scenario, copied from the
  roadmap-feature-not-found and design-roadmap scenarios, runs a PLAN whose
  chain reaches a v2 roadmap (with no `**Downstream:**` line) in a scratch
  git repository. It asserts `cascade_status` is `completed`, the step
  record above appears verbatim, the roadmap's `git hash-object` is
  unchanged, and the file is still tracked after the finalization commit.
- [ ] A second v2 scenario has every milestone reading Done and a
  `**Downstream:**` line naming the plan. It asserts the roadmap is neither
  transitioned nor deleted and no milestone's Status line changed.
- [ ] The existing feature-roadmap scenarios still pass unchanged, among
  them the `**Downstream:**` Done write, the not-found `partial` and the
  deletion scenarios.
- [ ] A frontmatter that can't be read (no closing `---`, or no `schema:`
  line) is treated as a feature roadmap, exactly as today. A scenario pins
  that.
- [ ] `run-cascade_test.sh` passes locally (it rebuilds shirabe with cargo;
  set TMPDIR to a mktemp directory outside /var/folders if the host's
  symlinked temp path breaks it) and stays in `check-execute-scripts.yml`
  and in `scripts/check-bash-floor.sh`'s list. The step changes no
  coordinate script.

**Dependencies**: Issue 1

### Issue 4: feat(coordinate): judge goal fit against Evidence

**Type**: refinement
**Complexity**: testable

**Goal**: Landing a pull request for a milestone shows goal fit the
milestone's numbered Evidence and posts a checked goal-fit entry naming the
pull request and the clauses it advances or `advances none`; and the branch's
CI failures in the template-freshness and public-content checks are fixed.

Steps 1 to 3 landed (build on them): `milestone.sh` (`schema`, `evidence`,
`check-verdict`, `progress-has`), the `ROADMAP_FORM` koto variable, the
`milestone-` Action prefix and the `verdict-owed` and `rework` Work kinds in
the codec, `record-append.sh`'s `milestone-verdict` kind, and the cascade's
v2 skip. CI at the step 3 head fails on these checks, which this step fixes:
- Template Freshness: `coordinate.mermaid.md` is stale. Regenerate it with
  `koto template export skills/coordinate/koto-templates/coordinate.md
  --format mermaid --output skills/coordinate/koto-templates/coordinate.mermaid.md`.
- public-content and shipped-paths: test fixtures carry literal
  forbidden-shaped strings. They are `roadmap-status_test.sh` near line 560
  (a home-directory path), `milestone_test.sh` near line 150 (a `wip/`
  value) and `dispatch-worker_test.sh` near lines 265 and 275 (a
  session-shaped name). Build each at run time the way
  `record-append_test.sh` does (`"/ho""me/..."`, with its comment), or use
  a neutral value where the test doesn't need the shape; never allowlist
  them.

**Acceptance Criteria**:
- [ ] `land-check.sh` adds `milestone: {tag, evidence: [...]}` (numbered
  clauses from `milestone.sh evidence` at the default branch) to
  `coord/land.json` when the pull request's holding names a unit on a v2
  roadmap. It adds nothing on a v1 roadmap or when no holding names the
  pull request, and a failed roadmap read doesn't change the land verdict.
  `land-check_test.sh` covers all three.
- [ ] `milestone.sh check-goal-fit ROADMAP TAG ENTRY` accepts an entry
  (`Goal fit: <owner/repo#n> -- <tag>`, `Fit: <fits|fits with
  follow-ups|gap>`, `Clauses: <n, n|advances none>`, `Rationale: <text>`)
  naming existing clause numbers or `advances none`. It refuses, naming the
  line: clause 3 on a two-clause milestone, a tag other than TAG, a pull
  request not shaped `owner/repo#n`, a malformed or reordered entry, and a
  file over 16 KiB. `record-append.sh` accepts the kind `goal-fit` and still
  refuses an unknown kind.
- [ ] `goal_fit` accepts an optional `clauses` field. On a milestone roadmap
  (`ROADMAP_FORM` milestone) its directive reads `milestone.evidence` from
  `coord/land.json` and posts the checked entry with `record-append.sh
  --kind goal-fit` before submitting. `advances none` with a `fits` outcome
  still reaches `land_merge`. The v1 rendering is unchanged, and
  `rule-coverage.tsv` pins the new phrase.
- [ ] `milestone-verdicts_test.sh` posts a goal-fit entry for the PR-bearing
  milestone's pull request, naming that pull request and a clause that
  exists. The engine suite shows a second pull request judged `advances
  none` reaching `land_merge`.
- [ ] Template Freshness passes locally for `coordinate.md` (the export
  matches the committed diagram), and `scripts/ablation/check-public-content.sh
  --diff origin/main --head HEAD -- docs skills references .claude
  .claude-plugin ':(glob)*.md'` reports nothing.
- [ ] Every new or changed script and test is in
  `scripts/check-bash-floor.sh`'s coordinate list, and `run-tests.sh` passes.

**Dependencies**: Issue 1

### Issue 5: feat(coordinate): reopen a Done milestone on failure

**Type**: refinement
**Complexity**: testable

**Goal**: A failure recorded against a Done milestone is checked, posted,
and followed by a pull request setting it In progress; once confirmed the
picker offers it again with the failure in its brief, and close-out waits
while the reopen edit is pending. Step 2's rework row (Who `verdict <id>`)
and the confirm path's entry-reading helpers are specific to verdict
entries; this step widens both for failure entries.

**Acceptance Criteria**:
- [ ] `milestone.sh check-failure` accepts a well-formed failure against a
  Done milestone and refuses one against a milestone not Done, a clause out
  of range, a malformed entry and What-was-seen text outside its closed
  shape; `record-append.sh` accepts `milestone-failure`.
- [ ] `roadmap-status.sh --reopen` opens a pull request setting In progress
  with the reopen Progress line and the entry in its body, writes a
  `milestone-reopen` row, lists dependents that hold a worker, and refuses a
  second edit while one is pending; `--confirm` checks In progress and
  writes a `rework` row with the clause and what was seen.
- [ ] The record codec accepts and renders the Side effects Action
  `milestone-reopen`, and the reporter is refused outside its closed shape.
- [ ] `wait` accepts `event: failure` with `unit`, routing to a new
  `milestone_reopen` state (`status: opened|failed`, `unit`) with its
  record-confirm rule, mermaid edges and structure-test entry.
- [ ] While the reopen edit is pending the picker doesn't offer the
  milestone; once the reopen is confirmed it lists it not done and offers
  it, its next brief quotes the failure, a dependent reads
  blocked, and close-out refuses while the reopen edit is pending.
- [ ] A test in `crates/shirabe-validate` shows a milestone roadmap with a
  reopened milestone and a reopen Progress line validates.
- [ ] A failure or verdict entry posted with no matching record-body change
  sets nothing, clears nothing, re-offers nothing and doesn't let close-out
  pass.

**Dependencies**: Issue 2

### Issue 6: docs(roadmap): say the tools enforce the Done rule

**Type**: docs
**Complexity**: simple

**Goal**: The roadmap format reference and the coordinate skill's
documentation describe what the tools now do, and the acceptance suite
covers every criterion of the feature's requirements.

**Acceptance Criteria**:
- [ ] `skills/roadmap/references/roadmap-format.md` no longer says the Done
  rule is unenforced or that the cascade updates status as plans land on a
  milestone roadmap, and says a post-Done failure returns a milestone to In
  progress through the coordinator; a grep for "unenforced" and "updates it
  as downstream plans land" finds nothing, and the Done rule's section names
  the coordinator's verdict step and `roadmap-status.sh --verdict` as what
  sets Done.
- [ ] `skills/coordinate/SKILL.md` and
  `skills/coordinate/references/record-template.md` have a section on
  verdicts covering the verdict step, the three entries, reopening, and
  that milestone roadmap edits need a person's review before merge.
- [ ] `shirabe validate` passes on every changed document, and every suite
  this feature added runs in a CI workflow.
- [ ] `milestone-verdicts_test.sh` names, in a comment beside each case, the
  feature acceptance criterion it covers, and every criterion has one.
- [ ] The documentation states the two points where the shipped behaviour
  follows the PRD over the design: a changes-needed edit leaves Delivered
  unchanged, and a verdict-owed row's Who is `none` when no holding names the
  milestone, in which case the checker check is skipped.
- [ ] The coordinate documentation also covers what step 2 landed:
  `--follow-ups` and its file format, the rework row and the brief heading
  that quotes it, the entry-to-comment binding, and that close-out reuses
  the `verdict-owed` word and code 49.
- [ ] The completion cascade's design and the roadmap format say the cascade
  skips a `roadmap/v2` roadmap (one `update_roadmap_feature` step at
  `skipped`, the run still `completed`), and that when a PLAN's chain points
  straight at a v2 roadmap the `--push` after-commit check reads `skipped`.

**Dependencies**: Issue 3, Issue 4, Issue 5

## Dependency Graph

## Implementation Sequence

Each outline's Dependencies line carries the edges: steps 2, 3 and 4
depend on step 1, step 5 on step 2, and step 6 on steps 3, 4 and 5. The
steps run one at a time, in outline order: 1, 2, 3, 4, 5, 6. The
critical path is 1, 2, 5, 6. Steps 3 and 4 depend only on step 1 and could
run beside step 2, but this plan runs them in order, so each step is
detailed from what the earlier ones landed, and because steps 1, 2, 4 and 5
all edit the coordinate template and its structure tests, running them
together would conflict.
