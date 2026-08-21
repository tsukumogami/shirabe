---
schema: plan/v1
status: Draft
execution_mode: single-pr
upstream: docs/designs/DESIGN-scope-koto-adoption.md
milestone: "koto as /scope's instruction substrate"
issue_count: 12
---

# PLAN: koto as /scope's instruction substrate

## Status

Draft

Single-pr: twelve issues on one shared branch, no GitHub issues filed. The
outlines below are what `/work-on` decomposes against.

## Scope Summary

Express `/scope` as a koto workflow so each hop's instructions arrive at that
hop, gate the full-run exit on every hop having either its artifact or a declared
fold, and rewrite the prose that told an agent a smaller artifact set was the
point.

## Decomposition Strategy

**Horizontal by layer, ordered by dependency.** Not a walking skeleton, and the
reason is specific rather than a preference: a partially-wired substrate is worse
than none. A template that delivers directives without its gates would move the
reduction argument to the fold state and remove the exit refusal at the same
time, which is the incident with better plumbing — exactly the outcome the design
warns against. The layers have to land in an order where nothing is half-armed.

Three ordering constraints fall out of the design and drive the sequence.

The eval harness is fixed before any scenario is written, because a scenario run
against the current runner reports green having graded nothing — the defect that
let three others survive unnoticed.

The predicate lands before the template, because every hop gate and the exit gate
invoke it, and a template whose gates call a missing script fails closed on every
hop.

The template lands before the prose, because the fold state's details block is
where the reduction argument goes, and the prose work has nowhere to move it
until that state exists.

Two issues are deliberately sequenced late for a reason worth stating: the
deterministic test and the model-graded scenarios both assert against the shipped
template, so writing them earlier means writing them against a moving target.

## Issue Outlines

### Issue 1: Fix the eval harness

**Goal**: `scripts/run-evals.sh` grades what a scenario asserts against what a run produced, and fails loudly when it grades nothing.

**Acceptance Criteria**:
- [ ] The runner reads `expectations`, falling back to `assertions` so the suites on the old name keep working.
- [ ] `files:` preconditions are materialized into the scenario's working tree.
- [ ] Post-run filesystem state is copied into the scenario's output directory, so assertions grade against the tree rather than against narration.
- [ ] A scenario that grades zero assertions exits non-zero.
- [ ] One scenario can be run N times and its pass rate reported.

**Dependencies**: None

**Type**: code
**Files**: `scripts/run-evals.sh`

### Issue 2: Build the hop-completion predicate

**Goal**: One script decides whether a hop is complete under both limbs of the design's exit rule, reading only the artifact tree.

**Acceptance Criteria**:
- [ ] Limb (a) credits a hop only for a regular, non-symlink, non-empty file at a canonical path that `shirabe validate` returns clean on; the design hop reads both DESIGN locations.
- [ ] Limb (b) parses the `absorbed:` frontmatter key specifically, matches whole entries, and scans frontmatter only.
- [ ] On a limb (b) match the predicate checks the FC18 pairing and requires a clean validation as a second condition.
- [ ] No path under `wip/` is read.
- [ ] With `shirabe` absent the predicate exits 2 naming the missing binary, and does not fall back to a weaker check.
- [ ] The refusal names each hop that satisfied neither limb; a survivor that declares a fold and fails validation is reported as such rather than as no declaration.
- [ ] A fixture suite covers: artifact present, legitimate fold, cascading fold, the reported incident, a body-prose claim, a frontmatter name-drop, a body code-block declaration, a three-line stub, an artifact copied onto another type's path, a symlink, a zero-byte file, an `absorbed:` entry that is a substring of a longer path, an `absorbed_by:` lookalike key, an inline backticked `---` inside a block scalar, and a missing validator.

**Dependencies**: None

**Type**: code
**Files**: `skills/scope/scripts/hop-complete.sh`

### Issue 3: Build the template lint

**Goal**: A static check fails the two authoring shapes the koto engine punishes silently.

**Acceptance Criteria**:
- [ ] The check runs on every pull request over all `skills/*/koto-templates/*.md` that carry YAML frontmatter, skipping files without it.
- [ ] Any non-terminal state carrying an evidence block with no guarded transition fails.
- [ ] Over `/scope`'s template, any hop-completion check reading `wip/scope_` or an agent-submitted evidence field fails, and the predicate covers scripts the gates invoke rather than only gate command strings.
- [ ] A deliberately malformed fixture fails and the shipped templates pass.
- [ ] The four states violating the universal rule today are fixed, or listed in an allowlist the check reads with an issue reference beside each.

**Dependencies**: None

**Type**: code
**Files**: `scripts/check-template-directives.sh`, `.github/workflows/check-templates.yml`

### Issue 4: Author the koto template

**Goal**: The 21-state workflow the design specifies exists and compiles clean.

**Acceptance Criteria**:
- [ ] `koto template compile` exits 0 and emits no warning lines.
- [ ] Every non-terminal state carries at least one guarded transition keyed on an agent evidence field.
- [ ] Every gate is co-routed with an evidence field, so no branch resolves without the agent.
- [ ] Every hop gate decides completion through the predicate from Issue 2.
- [ ] Each exit path's required fields are declared on that path's own state.
- [ ] The `rejected` outcome appears only on the two hops that can produce it and routes to the re-evaluation exit.
- [ ] Every state declares its `phase:`.
- [ ] The template's description states the two authoring rules a reviewer checks before reading the states.
- [ ] A hop can still be marked skipped, and a skipped hop satisfies neither limb of the exit rule.
- [ ] A diff against the merge base shows no change under `skills/brief/`, `skills/prd/`, `skills/design/` or `skills/plan/`.

**Dependencies**: Blocked by <<ISSUE:2>>

**Type**: code
**Files**: `skills/scope/koto-templates/scope.md`

### Issue 5: Declare the koto tool surface

**Goal**: `skills/scope/requires.tsv` matches the koto commands the skill now invokes.

**Acceptance Criteria**:
- [ ] A record exists per koto verb `/scope` calls, with its flags.
- [ ] The header comment explains what each record is for, in the shape `/execute`'s file uses.
- [ ] `scripts/check-skill-requires.sh` passes.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `skills/scope/requires.tsv`

### Issue 6: Wire the session lifecycle

**Goal**: `/scope` opens, reattaches to, and finishes a workflow session safely, with the state file staying authoritative.

**Acceptance Criteria**:
- [ ] The session name is the topic slug carrying a fixed literal prefix, reconstructible from the slug alone.
- [ ] On invocation `/scope` probes for an existing session before opening one.
- [ ] Reattach happens only when the session's recorded origin worktree matches this invocation's; on a mismatch the collision is reported and the run stops.
- [ ] The origin record lives in the session's context store and carries the store location alongside the name.
- [ ] No cleanup or cancel verb is run against a session `/scope` did not open.
- [ ] Every terminal transition passes the retention flag, so the per-hop record survives the run.
- [ ] `phase_pointer:` names the `/scope` phase the run is in, is written after the tick that advances the session, and is written from `/scope`'s own phase when no session exists.
- [ ] A run whose session no longer exists still reports its exit from the state file.
- [ ] Every field in the state schema is still written.
- [ ] Every resume-ladder row label and every row's author-facing prompt text is unchanged against the merge base.
- [ ] A resume from a fresh clone, with artifacts on disk and no session, reaches the same handler it reaches today.
- [ ] `skills/scope/SKILL.md` still declares its existing storage substrate.
- [ ] The state file records the session `/scope` opened.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `skills/scope/SKILL.md`, `skills/scope/references/phases/phase-0-setup.md`, `skills/scope/references/phases/phase-resume.md`, `skills/scope/references/state-schema.md`

### Issue 7: Commit each hop's artifact

**Goal**: The resume anchor is durable, because each hop's artifact is committed as it lands.

**Acceptance Criteria**:
- [ ] After a hop's gate evaluates, that hop's artifact is committed to the run's own branch as a new commit naming the hop.
- [ ] HEAD must be a named branch and must not be the repository's default branch, or the run aborts with a diagnostic.
- [ ] The recovered branch name is validated before reaching any emitted shell command.
- [ ] Staging uses an explicit pathspec for the one canonical path; no `-A` and no `commit -a`.
- [ ] The commit message is composed only from the hop name and the validated slug.
- [ ] Nothing pushes.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: code
**Files**: `skills/scope/references/phases/phase-2-chain-orchestration.md`

### Issue 8: Rewrite the purpose-bearing prose

**Goal**: `SKILL.md` states why the hops are taken and carries no sentence that reads as licence to skip one.

**Acceptance Criteria**:
- [ ] Every entry in the design's disposition table has its disposition applied.
- [ ] The general-form reduction argument appears nowhere in the pre-hop set and is delivered at the fold state.
- [ ] The four per-type contribution summaries appear nowhere in the pre-hop set and are delivered at the fold state.
- [ ] `SKILL.md` carries a named section stating why the hops are taken.
- [ ] `SKILL.md` carries exactly one operational definition of the hop-output term, saying what kind of thing such an output is rather than what each type produces.
- [ ] Neither denylisted sentence survives; the protected path statement inside the first one does.
- [ ] No withdrawn design is narrated in the past tense.
- [ ] `shirabe validate` passes on every changed document.

**Dependencies**: Blocked by <<ISSUE:4>>

**Type**: docs
**Files**: `skills/scope/SKILL.md`

### Issue 9: Move the phase-2 twin's desirability clause

**Goal**: The reduction argument is absent from the whole pre-hop set, not only from `SKILL.md`.

**Acceptance Criteria**:
- [ ] The reader-economy clause in `phase-2-chain-orchestration.md` moves to the fold state's details.
- [ ] A fixed-string search for the design's pinned fragment returns zero across every file in the pre-hop set.
- [ ] The pre-hop set used by the check is the enumerated one, not re-derived.

**Dependencies**: Blocked by <<ISSUE:8>>

**Type**: docs
**Files**: `skills/scope/references/phases/phase-2-chain-orchestration.md`

### Issue 10: Amend the upstream design and fix its citations

**Goal**: No committed document points at a section that no longer exists.

**Acceptance Criteria**:
- [ ] `DESIGN-scope-consolidation-over-skipping.md` carries an appended amendment dated on or after this work and citing this chain.
- [ ] The amendment records that the two named `SKILL.md` sections no longer stand as deliverables.
- [ ] The three by-title citations of those sections are updated.
- [ ] No by-title citation of either removed section remains anywhere in the repository.

**Dependencies**: Blocked by <<ISSUE:8>>

**Type**: docs
**Files**: `docs/designs/current/DESIGN-scope-consolidation-over-skipping.md`, `skills/brief/references/phases/phase-0-setup.md`

### Issue 11: Widen the shared parent-skill contract

**Goal**: The contract admits a workflow-driven parent without requiring the other parent to become one.

**Acceptance Criteria**:
- [ ] The contract states that a parent may drive its phases from a workflow session while declaring the existing storage substrate.
- [ ] The Observability Surface names the session-status surface and the per-hop record, scoped to the parent's own session rather than to a child's.
- [ ] The child-isolation limb is restated as unchanged.
- [ ] A diff against the merge base shows no change under `skills/charter/`.

**Dependencies**: None

**Type**: docs
**Files**: `references/parent-skill-pattern.md`

### Issue 12: Build the tests

**Goal**: The feature's central claims are asserted by something that runs on every pull request.

**Acceptance Criteria**:
- [ ] A deterministic test drives a real session against the shipped template on every pull request.
- [ ] It asserts that a full-run claim submitted as evidence is refused when hops have neither artifact nor recorded fold, and that the refusal names them.
- [ ] It asserts that after the run has ended a walked hop and a bypassed hop are distinguishable in the per-hop record.
- [ ] It asserts that the reduction argument is absent from what the session delivers before the first hop and present at the fold state.
- [ ] It confines its session storage to its own temporary store, names its session outside the production prefix, and calls no cleanup verb against a name it did not create there.
- [ ] It skips with a message naming the missing binary when koto is absent, and the CI job installs koto explicitly so a skip cannot mask a missing dependency.
- [ ] Two model-graded scenarios assert on files present after a run, one of them negatively: no document claims an artifact was folded away for a hop with neither that artifact nor a recorded fold behind it.
- [ ] The model-graded scenarios run at least five times and report a rate against a threshold stated in the suite, and do not gate a pull request.

**Dependencies**: Blocked by <<ISSUE:1>>, <<ISSUE:2>>, <<ISSUE:4>>, <<ISSUE:6>>

**Type**: code
**Files**: `skills/scope/scripts/scope-substrate_test.sh`, `skills/scope/evals/evals.json`, `.github/workflows/check-scope-scripts.yml`

## Dependency Graph

## Implementation Sequence

**Critical path: 2 → 4 → 6 → 12.** The predicate gates the template, the template
gates the session wiring, and the tests assert against all three. Five issues
long counting issue 1, which the tests also need but which can land any time
before them.

**Parallel from the start.** Issues 1, 2, 3 and 11 have no dependencies. The
harness fix, the predicate, the lint and the contract widening can proceed at
once, and three of the four are self-contained enough to review independently.

**Parallel after the template.** Issues 5, 6, 7 and 8 all depend only on issue 4
and touch different files — the tool declarations, the session wiring, the commit
behaviour and the prose. They can run together.

**The tail.** Issues 9 and 10 follow the prose rewrite and are small. Issue 12 is
last by construction, because it asserts against the shipped template.

**Where to be careful about ordering within an issue.** Issue 1's zero-assertion
exit comes before its other three changes, or the changes cannot be seen to work.
Issue 2's attack corpus is written with the predicate rather than after it — five
of its cases are defeats that review found in earlier versions, and a predicate
written without them in front of you is likely to reproduce one.
