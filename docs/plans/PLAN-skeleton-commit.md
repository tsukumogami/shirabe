---
schema: plan/v2
status: Active
execution_mode: multi-pr
split_mode_source: default
split_rationale: |
  Hard Constraint. The plugin changes depend on a released shirabe binary
  that accepts Draft for designs: a plugin that writes a Draft design over an
  older binary is refused with FC02 at its first commit. Step 1 lands the
  validator change and a shirabe release carries it before step 2's plugin
  change merges, and the design ships every plugin change in one plugin
  release so none carries half the rule.
tracking_level: none
upstream: docs/designs/DESIGN-skeleton-commit.md
milestone: "Skeleton commit under a validating pre-commit hook"
step_count: 2
---

# PLAN: Skeleton commit under a validating pre-commit hook

## Status

Active

## Scope Summary

Designs gain a `Draft` status so every commit `/design` makes before step 6.5
is a valid document the pre-commit hook accepts, and only step 6.5 writes
`Proposed`. The resume checks then read the committed status first, guard an
attached session with its jury keys, and reset to `Draft` on every loop-back;
`/scope` and `/plan` learn `Draft`.

## Decomposition Strategy

Walking skeleton, as a step plan. Step 1 is the thinnest path a person can
run: a hand-written design at `status: Draft`, with `status` and `problem` set
and the unreached sections stubbed, is committed in a repository whose
pre-commit hook runs `shirabe validate`, moved to `Proposed` with
`shirabe transition`, and checked at ready posture, where L11 refuses it while
it is still `Draft`. That crosses every integration the binary adds (the status
list, conditional FC01, the transition rule, L11) on one real input. It lands
in its own pull request and a `shirabe` release carries it.

Step 2 puts `/design` on that path: the skill writes the Draft skeleton itself
and commits every stage through the hook, writes `Proposed` only at 6.5, reads
progress from the committed status on resume, and its other readers of design
status (`/scope`, `/plan`) learn `Draft`. It merges only once the release from
step 1 is out, as one pull request so one plugin release carries the whole
rule.

## Steps

### Step 1: a Draft design commits through the validating hook and is refused at ready posture

**Goal**: The pre-commit hook that `shirabe install-hooks` writes hands a hand-written Draft design (frontmatter `status: Draft` and `problem` only, all nine sections, the unreached ones stubbed) to the validator, and the commit passes. `shirabe transition` moves that design between `Draft` and `Proposed`, and the ready-posture lifecycle check refuses it while it is `Draft`. This step lands in its own pull request, and a `shirabe` release carries it before step 2 merges.

**Acceptance Criteria**:

- [ ] With the locally built `shirabe` first on `PATH` and its hook installed by `shirabe install-hooks`, `git commit` of a design at `docs/designs/DESIGN-<name>.md` whose frontmatter holds only `schema: design/v1`, `status: Draft` and `problem`, whose body `## Status` reads `Draft`, and whose nine required sections are all present (the six unreached ones holding one stub line each) succeeds. `shirabe validate` on that file exits 0 and reports no FC01, FC02, FC03 or FC04.
- [ ] A Draft design with no `problem` field gets one FC01, naming `problem`, and exits 2. No FC01 names `decision` or `rationale` for any design at `Draft`.
- [ ] A design at `Proposed`, `Accepted`, `Planned`, `Current` or `Superseded` with no `decision` and no `rationale` still gets FC01 for both and exits 2. The statusless skeleton (frontmatter `schema: design/v1` only, three sections, body Status `Proposed`) is still refused with its four FC01, one FC03 and six FC04 findings and exit 2.
- [ ] Only the exact spelling selects the Draft rules: `status: draft` gets FC02 (status outside the enum) plus FC01 for `decision` and `rationale`. `status: "Draft"` and `status: Draft` followed by trailing spaces give the same findings and exit code as an unquoted `status: Draft`.
- [ ] `shirabe transition <doc> Proposed` on a Draft design exits 0 and rewrites the frontmatter `status:` line and the body `## Status` line to `Proposed`. Afterwards `shirabe validate <doc>` reports FC01 for `decision` and `rationale` and exits 2, and a `git commit` of that file is refused by the hook with the same findings.
- [ ] `shirabe transition <doc> Draft` on a `Proposed` design exits 0 and rewrites both status lines to `Draft`.
- [ ] `shirabe transition <doc> Draft` on an `Accepted`, `Planned`, `Current` or `Superseded` design exits non-zero with a message saying a design moves into `Draft` only from `Proposed`, and the file is unchanged.
- [ ] Every status `shirabe validate` accepts for a design without FC02 is a target `shirabe transition` accepts for a design, and the reverse: `Draft`, `Proposed`, `Accepted`, `Planned`, `Current` and `Superseded`. `cargo test` fails if either list gains a status the other lacks.
- [ ] `shirabe validate --lifecycle-chain <doc> --mode=draft` on a Draft design reports L11, a new code ("design is still a draft"; the lifecycle codes in use today end at L10), as a notice and exits 0. At `--mode=ready` it reports L11 as an error and exits 2. Both hold for a design that no plan or roadmap names.
- [ ] `shirabe validate --lifecycle <root>`, the whole-tree mode the lifecycle CI job runs, reports the same L11 on a Draft design under `docs/designs/`: a notice at `--mode=draft`, an error with exit 2 at `--mode=ready`.
- [ ] A design at `Proposed` or any later status gets no L11 at either posture. Briefs, PRDs, plans and roadmaps at `Draft` give the same per-file and lifecycle findings and exit codes as before, and L10 on a plan outline step is still a notice at draft posture and an error at ready posture.

**Check**: In the shirabe checkout, run `cargo build -p shirabe`, then `export PATH="$PWD/target/debug:$PATH"` and confirm `command -v shirabe` names that build (the hook silently skips validation when `shirabe` isn't on `PATH`, so this matters). In a scratch repository under `mktemp -d`, run `git init` and `shirabe install-hooks`, then write `docs/designs/DESIGN-skeleton-check.md` by hand: frontmatter `schema: design/v1`, `status: Draft` and a one-line `problem`; body `## Status` reading `Draft`; a sentence each under Context and Problem Statement and Decision Drivers; and the other six required sections each holding one stub line. `git add` it and `git commit -m "docs: draft design"`, and see the commit succeed. Run `shirabe validate --lifecycle-chain docs/designs/DESIGN-skeleton-check.md --mode=draft` and see L11 as a notice with exit 0, then the same with `--mode=ready` and see L11 as an error with exit 2. Run `shirabe transition docs/designs/DESIGN-skeleton-check.md Proposed` and see both status lines read `Proposed`; `shirabe validate docs/designs/DESIGN-skeleton-check.md` now reports FC01 for `decision` and `rationale` with exit 2, `git commit -m "docs: propose"` is refused by the hook with those findings, and `--lifecycle-chain --mode=ready` no longer reports L11. Run `shirabe transition docs/designs/DESIGN-skeleton-check.md Draft` and see it succeed, then fill in `decision` and `rationale`, move it to `Proposed` and `Accepted`, and see a further `shirabe transition docs/designs/DESIGN-skeleton-check.md Draft` refused with a non-zero exit and the file still at `Accepted`.

**Dependencies**: None

**Files**: `crates/shirabe-validate/src/formats.rs`, `crates/shirabe-validate/src/transition.rs`, `crates/shirabe-validate/src/checks.rs`, `crates/shirabe-validate/src/lifecycle.rs`, `crates/shirabe-validate/src/validate.rs`, `crates/shirabe/src/main.rs`

**Type**: code

**Complexity**: testable

### Step 2: /design commits every stage under the hook and resumes from the committed status

**Goal**: A `/design` run in a clone with the validating pre-commit hook commits its Phase 0 skeleton at `Draft` and every later stage on the first try, and only step 6.5 writes `Proposed`. On resume the run reads the committed status first, and in a session that `skill-session.sh open` reports as `opened=attached` with no Phase 6 jury keys it sends an early `Proposed` back to `Draft` so the jury runs. `/scope` and `/plan` treat a `Draft` design as not finished.

**Acceptance Criteria**:

- [ ] A fresh `/design` run, freeform or from a PRD, makes a Phase 0 commit that the hook accepts. The committed document has `status: Draft` and `problem` in its frontmatter, a body Status of `Draft`, and all nine required sections, with each section the run hasn't reached holding only the one stub marker line that `skills/design/references/design-format.md` defines.
- [ ] With a `shirabe` on PATH that refuses a `Draft` design, the run stops at Phase 0 before it writes or commits anything and names the `shirabe` release it needs. The probe leaves no file in the work tree.
- [ ] Every commit the run makes between Phase 0 and step 6.5, including the Phase 5 draft, fix and section commits and the Phase 6 fix commits, passes the hook on its first attempt. A step with nothing new to stage makes no commit, so a Phase 5 with no changes adds no empty commit.
- [ ] The document reads `Draft` in its frontmatter and body Status after every phase up to and including 6.4. After 6.5 it holds `decision` and `rationale` and reads `Proposed` in the frontmatter and the body Status at once, and `shirabe validate` reports no FC03 mismatch on it.
- [ ] Resuming on a document with no frontmatter `status` (the old skeleton) rewrites it to the Draft shape, commits it, and continues at the phase the session keys and sections point to.
- [ ] Resuming a `Proposed` design in a session reported as `opened=attached` with no Phase 6 jury key sets the document back to `Draft`, removes any placeholder `decision` or `rationale`, commits, and runs the 6.1 jury. Under `--auto`, or under `/scope` with the status prompt suppressed, this happens with no question asked and the run's output says so.
- [ ] Resuming a `Proposed` design in a session reported as `opened=new` or `opened=replaced`, or one that holds jury keys, does not revert it. The run goes to Phase 6's own check: a `Proposed` document whose change isn't committed resumes at 6.6 and makes the commit (and, on a direct run, the push and pull request), and a committed `Proposed` document goes to 6.7 with no second jury and no second pull request.
- [ ] Resuming a `Draft` design that reaches Phase 6 runs from 6.1, the document check and then the jury. A section whose only body is the stub marker counts as absent for every section-based resume row, so a run stopped with Solution Architecture still stubbed resumes at Phase 4, not Phase 5.
- [ ] The automatic commits the resume rows make (the skeleton rewrite and the status revert) contain only the design file: with another file staged beforehand, `git show --stat HEAD` lists just `docs/designs/DESIGN-<topic>.md` and the other file stays staged.
- [ ] Choosing to loop back at 6.2, or "Continue revising" at 6.7, leaves the document at `Draft` in frontmatter and body with no Phase 6 jury keys in the session, and the next pass through Phase 6 runs the jury again. After 6.6 has opened the pull request, the revision commits and the second 6.6 push land on that same branch and pull request, and no second pull request is opened.
- [ ] A round run through the serial self-review fallback writes the same three review files the parallel jury writes, and 6.2 records its jury keys the same way, so a resume inside that round's Phase 6 doesn't run the jury a second time.
- [ ] `skills/scope/scripts/hop-complete.sh --hop design` exits 1 (not complete) for a design at `Draft` with stub sections, and still exits 0 for the same design at `Proposed` or `Accepted`. `skills/scope/scripts/resume-probe.sh` routes a `Draft` design back to the design step's resume (the route a `Proposed` design takes today), not on to the PRD or BRIEF rows. Both test scripts carry a `Draft` case that passes.
- [ ] `/plan` run on a `Draft` design stops in Phase 1 with a message saying the design is still a draft and must be finished and reviewed first. The design format and lifecycle references list `Draft` ahead of `Proposed` and say what it means.
- [ ] A release note under `docs/guides/` gives the one-line migration step for a run that wrote `Proposed` early and whose session is gone: set the status back to `Draft` and resume.

**Check**: With the `shirabe` release from Step 1 on PATH and the pre-commit hook installed in a scratch clone, run `/design` on a throwaway topic and watch `git log --oneline` grow by one commit per stage with no hook refusal; at the Phase 0 commit, `git show HEAD:docs/designs/DESIGN-<topic>.md` shows `status: Draft`, nine section headings and the stub marker under the unreached ones. Stop the run after Phase 5 and confirm the document still reads `Draft`, then resume and see the jury run at 6.1 and the status move to `Proposed` only at 6.5. In a second scratch run, hand-edit the frontmatter and body Status to `Proposed` after Phase 5 and resume in the same session: the run reverts it to `Draft`, commits only the design file, and runs the jury. Put an older `shirabe` that refuses `Draft` first on PATH and start a new run: it stops at Phase 0 naming the release it needs, with `git status` clean. Finally run `bash skills/scope/scripts/hop-complete_test.sh` and `bash skills/scope/scripts/resume-probe_test.sh` and see both exit 0 with their `Draft` design cases listed as passing.

**Dependencies**: Step 1

**Files**: `references/doc-check-steps.md`, `skills/design/SKILL.md`, `skills/design/references/design-format.md`, `skills/design/references/lifecycle.md`, `skills/design/references/phases/phase-0-setup-freeform.md`, `skills/design/references/phases/phase-0-setup-prd.md`, `skills/design/references/phases/phase-5-security.md`, `skills/design/references/phases/phase-6-final-review.md`, `skills/scope/scripts/hop-complete.sh`, `skills/scope/scripts/hop-complete_test.sh`, `skills/scope/scripts/resume-probe.sh`, `skills/scope/scripts/resume-probe_test.sh`, `skills/plan/references/phases/phase-1-analysis.md`, `docs/guides/`

**Type**: code

**Complexity**: testable

## Implementation Sequence

The steps run in order, each in its own pull request. Step 2 merges only after
a `shirabe` release carries step 1, so a plugin that writes `Draft` never
reaches a binary that refuses it. Nothing runs in parallel.
