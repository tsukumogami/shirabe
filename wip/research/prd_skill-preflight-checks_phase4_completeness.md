# Verdict: FAIL

Reviewed against the 374-line revision (md5 932bc5b3...). The document
was being edited during the review; an earlier 364-line revision cited
the bakeoff's `wip/` working files in prose, which the current revision
has already replaced with a durable
`docs/decisions/DECISION-skill-preflight-verification-depth-2026-08-14.md`
(confirmed present, 14908 bytes). That wip-hygiene problem is resolved
and is not held against the document below.

## Section and frontmatter checks

All seven required sections present and in canonical relative order:
Status (28), Problem Statement (32), Goals (71), User Stories (84),
Requirements (106), Acceptance Criteria (227), Out of Scope (362). The
two optional sections -- Decisions and Trade-offs (273) and Known
Limitations (344) -- are interleaved before Out of Scope. This does not
break required ordering, and I confirmed it mechanically rather than by
eye: a copy with `schema: prd/v1` added validates at exit 0 with no
FC04 or FC15 finding.

That test exposes the frontmatter defect. The PRD carries no `schema`
field, and `shirabe validate` on it emits
`::notice::schema field missing, skipping` and exits 0 having checked
**nothing**. The document is currently unvalidated -- FC01, FC03, FC04
and FC15 never run. 32 of the 44 PRDs in `docs/prds/` carry
`schema: prd/v1`, and every recently authored one does; the twelve
without it are the older cohort. The format reference does not list
`schema` among required fields, so this is a convention gap rather than
a spec violation, but its effect is that the mechanized half of this
review's axis is switched off in the shipped file.

Required fields `status`, `problem`, `goals` are all present and are
paragraph-form literal block scalars. `status: Draft` matches the body
Status section. `upstream: docs/briefs/BRIEF-skill-preflight-checks.md`
resolves -- the file exists and its body Status and frontmatter both
read `Accepted`. `motivating_context` is used legitimately.

## BRIEF question closure

The BRIEF's Status section (lines 34-46) hands three questions
downstream. Decisions and Trade-offs opens by claiming "The BRIEF
deferred three questions. All three are answered here." Two of the
three land as recorded decisions. The third does not.

(a) **What the check targets -- absence, version skew, or subcommand
surface.** Closed, and closed well. "What the check verifies" (280-299)
states the chosen rule, names all three alternatives (presence-only,
presence plus floor, author-chosen depth), records that presence-only
was absorbed rather than rejected, and grounds the floor's elimination
on four separate pieces of evidence including the 0.3.3-versus-0.8.0
self-drift. "Why not pre-classify which flags are risky" (301-310) and
"The answer to PR #278" (312-320) extend it.

(b) **How a declaration expresses a mode-conditional dependency when
the mode is chosen after load.** Closed. "Mode-scoped dependencies"
(322-329) states the position (a load-time check does not report on a
branch not yet taken), binds it to R5/R10/R11, and states the rejected
alternative with its failure mode.

(c) **What an instruction must contain to be actionable, including the
no-install-route case.** **Not closed on the required surface.** The
substance exists -- R14 (contents of an instruction), R15 (no-install
route), R16 (complete on first emission), R18 (PATH before install),
R19 (delegate to a present package manager), R20 (known-bad
combinations) -- but it exists only as requirements. There is no entry
in Decisions and Trade-offs for it: no statement of what was decided,
no alternatives considered, no reasoning. The format reference is
explicit that this section "is also the conventional closure surface
for an upstream BRIEF's Open Questions section -- each deferred-to-PRD
question lands as a recorded decision (or as an acknowledged remaining
unknown)." A downstream design reading only the decisions surface will
find two of three questions settled and re-litigate the third. The
section's own opening sentence asserts otherwise, so the document is
also internally inconsistent on this point.

## Requirement/criterion coverage gaps

25 requirements, 17 acceptance criteria. Mapping is mostly sound: R1/R23
to AC1 and AC17; R3 to AC2; R4 to AC3; R12 to AC4; R6/R14/R17 to AC5;
R7/R13 to AC6; R8/R13 to AC7; R13/R18 to AC8; R9 to AC9 and AC14; R10/R11
to AC10; R15 to AC11; R21 to AC12; R22 to AC13; R24 to AC14 and AC15;
R25 to AC16.

Requirements with **no** corresponding criterion:

- **R16** (report complete on first emission; no affordance requiring a
  second, more verbose run). Nothing in the criteria mentions verbosity,
  a second run, or first-emission completeness. Untested outright.
- **R20** (instruction resolution accounts for combinations known not to
  work; `gh` commented out of `.tsuku.toml` as segfaulting on Linux).
  No criterion mentions `gh`, Linux, or a known-bad combination. This is
  the most concrete requirement in the Instruction resolution block and
  it has no test.

Requirements only partially covered:

- **R2** (per-skill and composable; no skill inherits another's). AC1
  tests that each skill has a declaration; nothing tests non-inheritance.
- **R5** (a declaration entry distinguishes always-required from
  mode-scoped). AC10 tests the *check's* behaviour at load; no criterion
  tests that the declaration format actually carries the distinction.
- **R11** has two halves. AC10 covers "verified where the mode is
  selected"; the second half -- "the declaration SHALL make that
  deferral visible rather than silent" -- is untested.
- **R19** (resolve against what the host has, delegating to a package
  manager already present). AC11 tests only the negative case (no
  package manager). The positive case -- a host with brew, or with
  tsuku, gets that manager's command -- has no criterion, though it is
  the case R19 is written for.
- **R21** (see next section) is narrower than the requirement it derives
  from, and AC12's grep is narrower still.

Criteria testing something no requirement states:

- AC17's second clause, "**runs no probe**". R12 requires zero *output*
  on a satisfied declaration; no requirement states that an empty
  declaration executes no subprocess. The criterion is reasonable but
  currently tests an unstated requirement.

## Factual spot-checks

Five checked, all confirmed.

1. `shirabe validate --not-a-real-flag` exits **2**. Confirmed against
   the installed binary. TRUE.
2. `skills/scope/SKILL.md` lines 628-634: "**2 (violations)** halts the
   chain and routes via ... **1 (tool-error)** is a validator failure
   DISTINCT from a content violation (the validator could not run)".
   TRUE, quoted accurately including the "DISTINCT" emphasis.
3. `.claude-plugin/plugin.json` reads `"version": "0.16.1-dev"`;
   `shirabe --version` at `~/.tsuku/tools/current/shirabe` reports
   `shirabe v0.16.0`. The drift the Problem Statement claims is live in
   this worktree. TRUE.
4. `--superseded-by` first appears in commit `ceb04fb`, "feat(transition):
   replace per-skill transition-status scripts with a shirabe subcommand
   (#146)" -- the commit whose message describes adding
   `shirabe transition` and whose diff creates the transition module.
   Same commit. TRUE.
5. Twenty skill directories under `skills/`. TRUE. Of those, five carry
   no host-tool invocation at all -- `decision`, `review-plan`,
   `private-content`, `public-content`, and `writing-style` (which
   mentions `shirabe validate` only in prose about who reads
   `rules.yaml`). The "five require nothing" claim holds, and matches
   the BRIEF's derivation (nine need nothing beyond a checkout, four of
   those call `shirabe transition`). See the count conflict in change 5
   below, which is internal to the PRD rather than a defect in this
   claim.

## Upstream coverage

All four items named in the review brief are present. Stderr discipline:
R21 plus AC12, with the shirabe#279 mechanism in the Problem Statement.
Exit-code collision: frontmatter, Problem Statement (60-69), R22, AC13.
Accretion evidence: "Why not pre-classify which flags are risky" carries
`--coordination-body`/`--merge-gate` (#196), `--pr-body` (#223),
`--lifecycle-chain` (#176-#271), `roadmap populate --no-issues` (#195).
Default-flip blind spot: "Known unknown, carried deliberately" plus the
first Known Limitation.

Three of the four are carried whole. The remaining material drops are
listed as required changes 4, 6 and 7 below. Lower-severity omissions I
am recording but not gating on: `DESIGN-shirabe-pattern-v1-ergonomics`
Decision 6, which both the findings and the crystallize handoff name
alongside PR #278 as a prior position any proposal must argue past --
the PRD argues past #278 only; the `!`-injection exit discipline (a
non-zero exit aborts the whole skill invocation, so the check must
always exit 0) and `/inflight`'s undeclared
`shirabe work-summary render`, which is the same class of defect R25
fixes for `/execute`; the Windows / `disableSkillShellExecution`
posture; the `metadata:` frontmatter constraint on where a declaration
can legally live; and the report's preservation of
`cli-version-preflight.md`'s per-subcommand sed-edit fallback as "the
answer to a detected gap", which R24 deletes without carrying forward.

## Required changes

1. Add `schema: prd/v1` to the frontmatter. Verified: without it
   `shirabe validate` skips the document entirely and no structural
   check runs; with it added, the document validates clean at exit 0.
   Until this lands, the section-presence and ordering guarantees this
   review asserts are unenforced in the shipped file.

2. Add a Decisions and Trade-offs entry closing the BRIEF's third
   deferred question -- what an instruction must contain to be
   actionable, including the no-install-route case. State the decision
   (PATH-before-install, host-resolved delegation, explicit "no route
   available"), the alternatives (a per-OS install matrix; a generic
   install line; deferring the no-route case), and why the chosen shape
   won. Requirements R14-R20 are the answer; the decision surface is
   where a downstream reader must be able to find it.

3. Add acceptance criteria for R16 and R20. For R16: an unsatisfied
   check's first and only emission contains everything the reader needs,
   with no flag, env var, or re-run producing more. For R20: on Linux,
   the report for a missing `gh` does not offer a tsuku install route,
   and the exclusion is read from a machine-readable source rather than
   a TOML comment.

4. Widen R21 and AC12. The upstream requirement is that neither the
   check's probes nor any skill call site may discard stderr **or ignore
   an exit code** -- shirabe#279 was silent because of `2>/dev/null`
   *plus* an unchecked exit status, and R21 currently carries only the
   stderr half. AC12's grep is scoped to `skills/` and to the literal
   `/dev/null`, which misses both other redirect spellings and
   `koto-templates/`, where koto is documented as discarding a gated
   command's own output.

5. Reconcile the skill count. AC1 and R23 say "the five whose
   declaration is empty"; the third Known Limitation says "Six of twenty
   skills spawn nothing." Both trace to upstream sources that disagree
   (the findings say five declare empty; the decision record says six
   declare nothing). My own count supports five. Pick one number and use
   it in both places, or state plainly why the two counts differ.

6. Carry the default-flip mitigation, not just the limitation. The
   decision record's closing section records a settled joint position --
   "the mitigation is to always pass the mode flag explicitly,
   `--issues` or `--no-issues`, and never rely on a default. Both
   validators named this independently." The PRD converts a settled
   authoring-discipline answer into an acknowledged unknown. Add a
   requirement that skills pass mode-selecting flags explicitly rather
   than relying on a default, with a criterion, and keep the limitation
   for what remains uncovered after it.

7. Name `/charter` alongside `/scope` in R22 and AC13. The decision
   record identifies two consumers that branch on the colliding
   0/1/2 contract -- `skills/scope/SKILL.md:615-637` and
   `references/phases/phase-finalization.md:165-198` for `/charter`.
   The PRD names only `/scope` throughout, so a downstream
   implementation satisfying R22 and AC13 literally can leave
   `/charter` misdiagnosing surface failures as content violations.

8. Close the smaller coverage gaps: a criterion for R2's
   non-inheritance, for R5's declaration-level always-versus-mode
   distinction, for R11's "deferral is visible" half, and for R19's
   positive case (a host with a package manager present gets that
   manager's command). Either add a requirement stating that an empty
   declaration runs no probe, or drop that clause from AC17.
