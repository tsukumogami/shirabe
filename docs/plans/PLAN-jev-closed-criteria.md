---
schema: plan/v1
status: Active
execution_mode: single-pr
split_mode_source: none
upstream: docs/designs/DESIGN-jev-closed-criteria.md
milestone: "Closed-criteria checks in decider shadow"
issue_count: 5
---

# PLAN: Closed-criteria checks in decider shadow

## Status

Active

## Scope Summary

Add a `site` subcommand to `scripts/review-shadow/review-shadow.py` that grades
four review sites (`brief`, `prd`, `review-plan`, `work-on`) in decider shadow
with seven new closed criteria, records each seat's verdict beside the
decider's in the existing store, reports agreement per site, and is called
from the brief, PRD and `/review-plan` phase files and from
`panel-scope.sh --record`, with no route, gate or seat changed.

## Decomposition Strategy

**Horizontal.** The design's five implementation steps are layers of one tool
with stable interfaces between them: the loader and record format, the
assemblers and slicers, grading, the report, and the callers. Each is a
prerequisite for the next, and the callers come last so no workflow calls a
half-built command. The work lands as one pull request under the repository's
default consolidated delivery preference; no unit is a standalone increment a
reader would use alone.

## Issue Outlines

### Issue 1: feat(review-shadow): add site artifact kinds and v2 site records

**Goal**: Teach `scripts/review-shadow/review-shadow.py`'s loader, runners and record writer about local site artifacts, so later issues can add sites without touching pull-request behaviour.

**Acceptance Criteria**:
- [ ] `ARTIFACT_KINDS` gains `brief`, `prd`, `plan` and `local-change`; `SLICE_KINDS` gains `brief-journey`, `summary-pair`, `prd-ac`, `plan-ac-block` and `ac-hunks`; the loader refuses a criterion whose slice kind doesn't belong to its artifact kind, with a test for each refusal.
- [ ] `active()`, `run_scripts` and `run_jev` select criteria by artifact kind: a test grades the pull-request fixture with a site criterion enabled and shows it never runs, and a site grade never runs `rs-001` to `rs-010`.
- [ ] A site record is written with `schema: review-shadow/record/v2`, a `subject` object (`kind: site`, `site`, `subject_id`, `artifact_sha`) and a `seats` list, under `records/<owner>/<repo>/site/<site>/<subject-id>/<artifact-sha12>/`, through the existing private atomic writer; a test asserts the path and modes (0700 directories, 0600 file).
- [ ] A store holding both v1 pull-request records and v2 site records produces byte-identical `report` and `report --json` output for the pull-request tables as a store holding only the v1 records.
- [ ] `python3 scripts/review-shadow/test_review_shadow.py` passes, and `review-shadow.py check` still loads the shipped files.

**Dependencies**: None

**Type**: code

### Issue 2: feat(review-shadow): assemble and slice site inputs with a measure mode

**Goal**: Add the `site` subcommand's argument checks, the `brief`, `prd`, `plan` and `local-change` assemblers, the five site slicers, and `--measure`, so each decider-fit site's input can be built and sized from identifiers alone.

**Acceptance Criteria**:
- [ ] `review-shadow.py site <brief|prd|review-plan|work-on>` accepts only the identifier arguments the design's `site` command table lists, and exits 2 on a topic outside `^[a-z0-9-]+$`, a non-numeric issue, a value starting with `-`, or a path that resolves (symlinks followed) outside the repository root; each refusal has a test.
- [ ] Each slicer cuts units by structure: one `###` journey (`brief-journey`), one frontmatter field with its section (`summary-pair`), one `- [ ]` item with its group label (`prd-ac`), one issue's title and criteria (`plan-ac-block`), one criterion with the hunks matching its anchor terms (`ac-hunks`); fixture tests under `scripts/review-shadow/fixtures/sites/` assert the unit count and the bytes of each slice.
- [ ] A unit of exactly 2,560 bytes is one slice; one of 2,561 bytes is cut at whole sub-units with the dropped count recorded, and a single sub-unit over the bound is marked over-bound and never truncated.
- [ ] `ac-hunks` matches a hunk only when its path or a changed line contains an anchor term (backticked token, token with `/` or a file extension, `--flag`) and gives `no-anchor` for a criterion with none; every `git diff` it runs carries `--no-ext-diff --no-textconv`, and diffs of paths matching the design's secret-path list are skipped.
- [ ] `site <id> ... --measure` prints one `slice <id> <bytes>` line per slice and one `seat-packet <bytes>` line built with the site's `review-packet.sh` call, makes no network call (the test transport refuses one), writes no record, and exits 0 against this repository's own documents.

**Dependencies**: Blocked by <<ISSUE:1>>

**Type**: code

### Issue 3: feat(review-shadow): grade sites in shadow with rs-011 to rs-017

**Goal**: Read every shadowed seat's verdict from where the seat writes it, apply the send gates, ask the decider the seven new criteria, and write one paired record per site run.

**Acceptance Criteria**:
- [ ] `criteria.json` carries rs-011 to rs-017 as the design's criteria table states (slice kind, question, one-sentence `pass`, `fail` and `unclear`, threshold 0.9, `rule_ref` to the shadowed seat's prompt), with the version bumped and `categories.json` extended; `review-shadow.py check` loads them.
- [ ] The verdict readers parse the brief's `**Verdict:**` line, the PRD's `## Verdict:` heading, `/review-plan`'s `review_result` block and the `/work-on` ledger entry; fixtures show `seat-verdict-missing` for an absent file, `seat-verdict-unparsed` for a malformed marker, and `seat-verdict-stale` for a verdict file older than the artifact, a ledger `judged_at` other than `--head`, or a ledger `ac_sha` that differs from the criteria hash now; the `/review-plan` reader accepts either verdict file (proceed or loop-back).
- [ ] A criterion's run verdict is the worst of its unit verdicts, and units recorded `over-bound` or `no-anchor` carry that reason in the record; a fixture with one passing and one failing unit rolls up to `fail`.
- [ ] A test plants a credential-shaped string and a listed private term in one slice and shows redaction runs first, the private-term check second and the size bound last.
- [ ] At `/work-on` only seats whose round decision is `full` or `rerun` are recorded, and a run with none writes nothing.
- [ ] With a stub decider, one run writes exactly one record holding every shadowed seat's verdict and the decider's verdict per unit and criterion; a sentinel string planted in each fixture artifact appears nowhere in the record.
- [ ] Nothing is sent, and every criterion is `unanswered` with the stated reason, when the key is absent (`no-key`), `REVIEW_SHADOW_SITES` isn't `1` (`not-opted-in`), the repository's `CLAUDE.md` doesn't declare `## Repo Visibility: Public` (`private-repo`), or a slice holds a listed private term (`private-term`); slices past 32 or past 60 seconds are `run-cap`.
- [ ] With a stub decider that errors and one that times out, the command exits 0 and records `provider` and `transport`; only a malformed argument exits 2.
- [ ] Finding attribution sets a per-slice boolean for a `/review-plan` category C finding naming a graded issue and for a ledger finding whose path and lines fall inside a graded hunk, and the record holds no path or finding text.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code

### Issue 4: feat(review-shadow): report agreement per site

**Goal**: Make `review-shadow.py report` print the per-site tables the flip ruling will read.

**Acceptance Criteria**:
- [ ] Over a fixture store of site records with known seat and decider verdicts, `report` prints, per site and per criterion, agreement, decider-only fails, attributed false passes, the Clopper-Pearson 95% upper bound computed with attributed plus unattributed seat blocks, and no-verdicts, matching figures the test computes by hand.
- [ ] Out-of-sample and `--in-sample` records are counted in separate tables, and only the latest record per site, subject and `artifact_sha` is counted.
- [ ] An empty store and a site with no seat blocks print zero counts and an upper bound computed from zero false passes, without error.
- [ ] `report --json` carries the same per-site figures under a `sites` key.
- [ ] The pull-request tables' output is unchanged for a store that also holds site records.

**Dependencies**: Blocked by <<ISSUE:3>>

**Type**: code

### Issue 5: feat(skills): run the site shadow from brief, prd, review-plan and work-on

**Goal**: Call the site shadow at each decider-fit site without changing any route, gate or seat, and document the commands.

**Acceptance Criteria**:
- [ ] `skills/brief/references/phases/phase-4-validate.md`, `skills/prd/references/phases/phase-4-validate.md` and `skills/review-plan/references/phases/phase-5-verdict.md` each gain one line running `review-shadow.py site <id> --topic <topic> ... || true`, placed after the seats' verdicts are written and before any fix or cleanup step, saying its result is not read; a grep of the changed skill files for `review-shadow.py site` finds only identifier arguments.
- [ ] `skills/work-on/scripts/panel-scope.sh --record` starts `site work-on --session <WF> --panel <panel> --head <sha>` in the background after the ledger write, for `scrutiny`, `review` and `light` only, and only when `REVIEW_SHADOW_SITES=1` and `python3` and the script are present; `panel-scope_test.sh` shows `--record`'s exit status and ledger are the same with the shadow failing, missing, or absent, and that `--record` returns without waiting on it.
- [ ] No koto template's routes, gates, accepts fields, evidence or default actions change, and no **Seat commissioning** line changes its seat count, model or call budget (`git diff` of `skills/*/koto-templates/` is empty and the commissioning lines are unchanged).
- [ ] `scripts/check-bash-floor.sh` passes on the changed shell.
- [ ] The implementation pull request body lists, for each of the four sites, the `slice` and `seat-packet` byte counts `--measure` printed against this repository's own documents, with the exact command.
- [ ] `docs/guides/review-shadow.md` documents the `site` subcommand, `--measure`, the `REVIEW_SHADOW_SITES` opt-in and the per-site report.

**Dependencies**: Blocked by <<ISSUE:3>>, <<ISSUE:4>>

**Type**: code

## Dependency Graph

## Implementation Sequence

The critical path is the whole chain, 1 then 2, 3, 4 and 5. Issue 2 starts
by measuring this repository's own documents with `--measure`; a slicer whose
units mostly come out over the bound or with no anchor is a reason to drop
its criterion in issue 3. Issue 5 waits on issue 4 so the report's
attribution fields are settled before any caller writes records. There is no
parallel work worth taking: issues 1 to 4 all edit `review-shadow.py`.
