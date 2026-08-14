# Lead: Does the run's reasoning survive the PLAN's death?

## Findings

### 1. The PLAN's lifecycle, precisely

**Created by** `/plan` at `docs/plans/PLAN-<topic>.md`.

**Status by mode** (`skills/plan/SKILL.md:29-73`): the lifecycle is
`Draft -> Active -> Done -> DELETED`, identical for single-pr and multi-pr.
Only the Draft->Active gate differs — multi-pr requires human approval and
creates the GitHub milestone and issues on the transition; single-pr auto-fires
when `/plan` finishes authoring. A committed PLAN at `status: Draft` is a
violation in either mode. `/scope` Phase 3 records `status: Draft` for single-pr
and `Active` for multi-pr/coordinated in `exit_artifacts:`
(`skills/scope/references/phases/phase-3-exit-finalization.md:40-52`), which is
a snapshot at chain-exit, before the single-pr auto-flip settles.

**Deleted by** `/execute`'s `plan_completion` state, which runs
`skills/execute/scripts/run-cascade.sh --push`. The script does
`git rm -f "$PLAN_DOC"` at `run-cascade.sh:859`, immediately after applying the
ephemeral Active->Done frontmatter flip, and commits both together at
`run-cascade.sh:872`:

```
git commit -m "chore(cascade): post-implementation artifact transitions"
```

A fixed message. No chain record, no rationale, no artifact list.

`finalize-chain` (the Rust half) never deletes and never transitions the PLAN —
it reports it as a `DeletePlan` node and hands the `git rm` to the caller
(`crates/shirabe-validate/src/finalize.rs:58-69`, `:792-797`). The same walk
transitions DESIGN->`Current`, PRD->`Done`, BRIEF->`Done`
(`finalize.rs:688-707`), so **the PLAN is the only chain member that dies**.
BRIEF, PRD and DESIGN survive at terminal status. That is exactly issue #280's
complaint.

`/scope` Phase 4 does *not* delete the PLAN — it sweeps `wip/` only, and the
PLAN is named as the surviving terminal artifact
(`phase-4-cleanup.md:48-56`). The PLAN dies later, at `/execute` time. So the
`/scope` state file — with `chain_ran:`, `chain_skipped:` and
`consolidation_judgments:` — is deleted at Phase 4, well before the PLAN is.

**Coordinated mode** follows the same cascade; `/execute` "owns single-pr and
coordinated multi-repo plans" (`skills/execute/SKILL.md`, skill description).
Multi-pr routes through `/work-on` per issue, and `skills/plan/SKILL.md:33`
attributes the deletion to "the work-on cascade's PLAN deletion step" — same
script, same fixed commit message.

### 2. Phase 3's PR-body record: documented, not implemented, and lands in the wrong half

`phase-3-exit-finalization.md:64-76` states that Phase 3 writes the production
and absorption record — every entry in `chain_ran:`, every `chain_skipped:`
entry with its re-entry-protection reason, every `consolidation_judgments:`
entry with verdict, finding, and what-was-absorbed-into-what — into "the run's
pull-request body", precisely because Phase 4 removes the state file.

Three separate problems:

**(a) There is no such PR.** `/scope` touches `gh pr` in exactly one place: the
coordinated multi-repo **coordination PR** (`skills/scope/SKILL.md:187`, `:214`,
`:699`). No `gh pr create` or `gh pr edit` exists anywhere on the single-pr or
multi-pr path. SKILL.md's own authoritative full-run binding
(`skills/scope/SKILL.md:505-510`) says only: "The `exit_artifacts:` list records
the PLAN doc's path." The phase-reference statement has no implementation and no
target.

**(b) Even with a PR, `/execute` overwrites it.** `pr_finalization` runs a full
body replacement (`skills/execute/koto-templates/execute.md`, step 3):

```
gh pr edit "$PR_NUMBER" --title "feat: $PLAN_SLUG" --body-file "$BODY_FILE"
```

`--body-file` replaces; it does not append. And `/execute` is metadata-only
(R14/R15) and explicitly forbidden from reading child PR bodies or diffs, so it
cannot merge whatever was there before.

**(c) The PR body *does* reach main's git history — but only Part 1.** Repo
settings, confirmed via `gh api repos/tsukumogami/shirabe`:

```json
{"squash": true, "merge": false, "rebase": false,
 "squash_title": "PR_TITLE", "squash_message": "PR_BODY",
 "delete_branch": true}
```

Squash-only, the squash commit message *is* the PR body, and the branch is
deleted on merge. So the PR body is genuinely durable, not a platform-only
artifact — **but** the two-part convention
(`references/pr-body-conformance.md`, "What the two-part convention is") holds
that Part 1 (above the single `---`) becomes the squash commit body and Part 2
(from `---` down) is "deleted at merge".

Verified empirically against PR #271 -> squash commit `9f45603`: the PR body's
Part 1 is four paragraphs; `git log -1 --format=%B 9f45603` ends at exactly the
last of those four paragraphs. The PR's numbered 12-step list, its
`## Verification` section, and its `## Follow-ups this work surfaced` section
are **absent from main**. Part 2 deletion is real.

I found no workflow that performs the trim (`.github/workflows/` has 22 files,
none touch merge messages), so it is a human editing the pre-filled squash body
in GitHub's merge dialog — a discipline, not a mechanism.

And `/execute`'s own Part 2 is defined as "the per-child outcome table"
(`execute.md`, pr_finalization step 2). The one place a chain record could
plausibly go under current instructions is the half that gets deleted.

Also note: the branch's 12 individual commits collapse into one. The 44 commits
behind #271 are gone from main and their branch was deleted; their messages
survive only in GitHub's PR view, not in any clone.

### 3. What `/execute` actually leaves behind

The Part 1 instruction, verbatim from `skills/execute/koto-templates/execute.md`
(pr_finalization, step 2):

> **Part 1 — factual change paragraph** (becomes the squash commit body): a
> concise paragraph of what the PLAN's PR changed in the codebase, derived from
> the PLAN's own validated framing plus the child-outcome metadata. `/execute`
> is metadata-only (R14/R15) — do NOT read child PR bodies or diffs. No
> `Fixes #N` here.

What changed, not why. Built from PLAN framing plus outcome metadata, and
explicitly barred from looking at the diff.

Part 2: per-child `name` / `outcome` / `reason` / `reason_source` /
`skipped_because_chain`, plus `Fixes #N` only for real GitHub issues. Deleted at
merge.

**Nothing in `/execute` or `/work-on` instructs writing design rationale,
rejected alternatives, or decision provenance into code comments, commit
trailers, or docs.** I grepped `skills/execute/SKILL.md`,
`skills/work-on/koto-templates/work-on.md` and all of
`skills/work-on/references/phases/` for `code comment`, `document why`,
`rationale.*comment`, `comment.*why` — zero hits.

The one structured why-capture is `koto decisions record`
(`skills/work-on/SKILL.md:252`, `work-on/koto-templates/work-on.md:1071`):

```
koto decisions record <WF> --with-data '{"choice": "...", "rationale": "...", "alternatives_considered": ["..."]}'
```

That is exactly the right shape — and it writes to koto session state under
`~/.koto/sessions` (29 MB on this machine), outside the repo, never committed,
gone with the machine. It is surfaced in the PR body only for the narrow
AC-deferral case (`work-on.md:683`), and the PR body's Part 2 is deleted at
merge.

The only durable why-writing `/work-on` does is the design-doc dependency
diagram update (`phase-6-pr.md`, "Design Document Status"), which writes into
the DESIGN — the artifact a fold-to-PLAN removes.

### 4. The #270/#278 test case

**First correction: PR #278 is not merged.** `gh pr view 278` returns
`"state": "OPEN"`, `"mergeCommit": null` (checked 2026-08-14). So there is no
merged code and no squash commit to test against. The test is against the branch
`impl/execute-single-pr-blockers` at `6e1a22dc` and against what a squash-merge
of the current body would produce.

The branch's 12 commits: 5 chain-doc commits (`594cc359` brief, `fce1626b` +
`32667808` prd, `cb7bc763` design, `06553355` plan), `54f546c8` wip cleanup, 4
implementation commits, `d869c660` chain finalization, and `6e1a22dc`.

**Do the two facts survive?** Yes — both.

- *koto does not resolve shell interpolation* (`{{KEY}}` only, compile-time
  validated against the `variables:` block): in `skills/execute/SKILL.md` (+9
  lines added by `f131d8ce`), in a 16-line comment block in
  `skills/execute/koto-templates/execute.md` added by `6e1a22dc`, and in PR
  #278's Part 1, paragraph 2 — so it would reach main's commit history.
- *koto discards gate stdout/stderr*: at
  `skills/execute/koto-templates/execute.md:353` on the branch — "koto reports a
  failed command gate as an exit code with no message and discards the command's
  own output, so if this state will not advance, check that file first" — added
  by `f131d8ce`. Also in PR #278's Part 1.

**Second correction, and the point: none of that is `/execute`'s doing.** The
survival was manufactured by hand in `6e1a22dc`, a commit whose entire purpose
was to do what `/execute` does not:

```
docs(chain): drop the scoping artifacts and move their reasoning into the code

The PRD and DESIGN this chain produced held one thing the diff did not:
why the rejected alternatives were rejected. That reasoning now sits
next to the code it constrains...
```

Its diffstat is the measurement:

```
 .github/workflows/check-plan-scripts.yml           |  11 +
 docs/designs/current/DESIGN-execute-single-pr-blockers.md | 460 ---
 docs/prds/PRD-execute-single-pr-blockers.md        | 269 ---
 scripts/check-template-interpolation.sh            |   5 +
 skills/execute/koto-templates/execute.md           |  16 +
 skills/plan/scripts/plan-to-tasks.sh               |  25 +-
 6 files changed, 56 insertions(+), 730 deletions(-)
```

730 lines out, 56 in. The four comment blocks map 1:1 onto the DESIGN's four
decision questions — D1 (gate slug resolution) -> `execute.md`, D2 (bash 4 map
removal) -> `plan-to-tasks.sh`, D3 (where the diagnostic lives) ->
`check-template-interpolation.sh`, D4 (what guards reintroduction) ->
`check-plan-scripts.yml`. The author's explicit judgment was that the
rejected-alternative reasoning is the only load-bearing part.

**What did not survive.** Everything else in those 730 lines: the DESIGN's
Context and Problem Statement (~77 lines), Decision Drivers, Solution
Architecture, Security Considerations, and the whole Consequences section — both
the positives and the four negatives with their mitigations. And the PRD's
requirements, including R4 ("Identical output across bash versions"), which PR
#278's own Part 2 says is *not* verified locally and depends on the CI matrix.
After merge, R4 exists nowhere.

One line from the deleted DESIGN's Consequences is worth quoting, because it
bet on its own durability and lost:

> Recording 2d here is the mitigation: the argument does not have to be rebuilt.

(2d was "port this to Rust". The author did carry that one across, by hand, into
the `plan-to-tasks.sh` comment block.)

**A third loss, invisible in the diff.** `f131d8ce`'s commit message is the
single richest account of the gate defect anywhere — root cause, the
process-boundary explanation (the directive derives `PLAN_SLUG` in the agent's
shell, koto evaluates the gate in a different process), the property that
matters ("not that this works today but that the next mistake is loud"), and the
verification. Squash-only merge plus `squash_message: PR_BODY` plus
`delete_branch_on_merge: true` means that message will not exist on main and its
branch ref will be deleted. It survives only to the extent the author manually
re-wrote it into Part 1 — which he did, in condensed form.

### 5. Existing provenance conventions in this repo

- **`docs/decisions/`** holds 6 `DECISION-*.md` files. All are standalone docs,
  cited from skill prose (e.g. `skills/plan/SKILL.md:90-95`). Documents, not
  trailers.
- **No commit-trailer convention exists.** The only commit rule in `CLAUDE.md`
  is negative — "Never add AI attribution or co-author lines" — enforced as PB3.
  PB1 requires a Conventional Commits title with no issue-number scope and puts
  issue references in Part 2, i.e. in the half deleted at merge (`Fixes #N`
  closes the issue at merge time via GitHub, but the text does not land on main).
- **`AGENTS.md:86`** — "Decision blocks for all non-trivial choices (see
  `references/decision-protocol.md`)". `references/decision-protocol.md`, Step 3:
  "Write a decision block (see `decision-block-format.md`) **in the current
  artifact**." The repo's decision-provenance convention is explicitly
  artifact-resident. That is precisely the surface a fold-to-PLAN removes.
- **One informal but real convention does put reasoning in code**: this
  repository's comments are unusually rationale-heavy — `finalize.rs`'s module
  doc ("Why the PLAN is a delete, not a transition", "The guard fails open, and
  says so"), the `ci_monitor` gate comment in `execute.md` ("Don't rewrite this
  as 'nothing is in the fail bucket' -- that would let an all-queued PR report
  green"). It is a house style with no skill instructing it and no check
  enforcing it.

## Implications

The load-bearing assumption — that `/execute` is good at documenting code as it
executes the plan — is not supported by what `/execute` does. Its one prose
surface is a factual what-changed paragraph derived from PLAN framing and
child-outcome metadata, with an explicit prohibition on reading the diff. It
writes no code comments, no commit trailers, no docs. The rationale-rich comments
that make this repository readable are written by humans and by `/work-on`'s
implementation agents following house style, not by any instruction in the
skill chain.

`#278` is evidence that a human *will* carry rationale into code when he sets out
to. It is not evidence that `/execute` will, and the author's own commit message
frames the act as a stopgap for #280 rather than as the normal path.

There is a better durable surface than expected: Part 1 of the PR body lands
permanently on main as the squash commit message, in every clone, forever. That
is the cheapest place to put a chain-production record and it needs no new
mechanism. But it has to be Part 1 — Part 2 is deleted at merge, and `/execute`
currently defines Part 2 as the outcome table and Part 1 as what-changed-only.

If the fold-to-PLAN lands as designed today, a small run loses: the PRD's
requirements and acceptance criteria, the DESIGN's problem framing, drivers,
consequences and security notes, and every rejected alternative — unless someone
does by hand what `6e1a22dc` did. The 730-to-56 ratio is the author's own
estimate of how much of that he considered worth keeping, and he still had to
write those 56 lines himself.

## Surprises

- **PR #278 is still open.** The lead's framing ("was fixed via PR #278", "the
  merged code and commits") is ahead of reality; nothing from it is on main.
- **Phase 3's PR-body record has no implementation.** It is stated in
  `phase-3-exit-finalization.md` and contradicted by SKILL.md's own binding,
  which records only the PLAN path. `/scope` creates a PR only in coordinated
  mode.
- **`/execute` would clobber it anyway.** `pr_finalization` does a full
  `--body-file` replacement and is forbidden by R14/R15 from reading what was
  there.
- **Part 2 really is deleted at merge**, confirmed against `9f45603`. So the
  natural-looking place for a "what the chain produced" note is exactly the
  wrong half — and the deletion is a manual trim in the merge dialog, not
  automation.
- **`koto decisions record` already has the right schema** (`choice`,
  `rationale`, `alternatives_considered`) and writes it to `~/.koto/sessions`,
  off-repo, machine-local, uncommitted.
- **`finalize-chain` retires but never deletes BRIEF/PRD/DESIGN.** The PLAN is
  the only chain member that dies. Every other artifact survives at terminal
  status — which is what #280 wants changed.

## Open Questions

- Who trims Part 2 at merge? GitHub pre-fills the squash body with the whole
  `PR_BODY`; no workflow does it. If it is a human, "Part 2 is deleted at merge"
  is a discipline, not a guarantee, and a chain record placed in Part 2 might
  survive by accident on an unattended merge.
- Could `/execute`'s Part 1 carry the chain-production record without violating
  R14/R15? The record is metadata, so it looks compatible on its face — but
  `/scope` Phase 4 deletes the state file long before `pr_finalization` runs, so
  the data would have to be carried forward somewhere first (the PLAN's own
  frontmatter is the obvious candidate, and it is what `/execute` already reads).
- Is a code-comment convention checkable at all? PB4-style mechanical checks
  work on structure, not on whether a comment explains why. `#278` did both
  (comments *and* a rich Part 1); whether the fold should mandate one, the other,
  or both is a design question this lead does not settle.

## Summary

The PLAN dies by `git rm` in `run-cascade.sh:859` under a fixed
`chore(cascade): post-implementation artifact transitions` commit message, and
`/scope`'s state file with the chain and consolidation record is already gone by
then — Phase 3's documented PR-body record has no implementation, no PR on the
ordinary path, and would be overwritten wholesale by `/execute`'s
`--body-file` edit anyway. `/execute` writes only a what-changed Part 1 built
from metadata (explicitly barred from reading the diff) and an outcome table in
Part 2 that is deleted at merge; nothing in `/execute` or `/work-on` instructs
rationale into code comments, commit trailers, or docs, and the one structured
capture (`koto decisions record`, with `alternatives_considered`) writes to
`~/.koto` outside the repo. PR #278 — still open, not merged — does carry both
koto facts into durable code, but only because commit `6e1a22dc` hand-deleted
730 lines of PRD and DESIGN and hand-wrote 56 lines of comments to replace them,
which is the author doing by hand exactly what the fold assumes `/execute`
already does.
