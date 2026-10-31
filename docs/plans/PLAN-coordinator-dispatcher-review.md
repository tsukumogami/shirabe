---
schema: plan/v2
status: Active
execution_mode: single-pr
split_mode_source: none
tracking_level: none
upstream: docs/designs/DESIGN-coordinator-dispatcher-review.md
milestone: "Coordinator Dispatcher Review"
step_count: 4
---

# PLAN: Coordinator Dispatcher Review

## Status

Active

## Scope Summary

The design rewords the coordinate skill so every review, merge, close and
verdict step names the reviewer: the coordinator that dispatched a bound
coordinator, and a person only at the root. `SKILL.md` gains one Glossary
definition of the reviewer and one Bounds and Authority paragraph saying
review comes before every merge, that a merge grant decides who merges after
the review and never whether it happens, what that means for a coordinator's
own pull requests, the fail-closed rule, and what a coordinator that may not
merge sends up. The milestone verdict rule keeps its forgery control: someone
other than the author approves a milestone roadmap edit, and whoever in the
chain holds a merge grant merges it after that approval, the author included
when granted. The brief renderer's `Named authority:` line for a
granted worker says to report for review and merge only at a cleared head,
never a roadmap pull request. Twenty-one other sentences in `SKILL.md`, three
references and the template's directives and descriptions name the reviewer.

Everything lands in one pull request in this repository. The template's
structure doesn't change; the renderer change moves the compat table's
`gate_scripts` digest at compat 2, and four rule-coverage rows pin the new
safety sentences.

## Decomposition Strategy

Walking skeleton. Step 1 crosses every layer a reader meets the rule through:
the definition and rule in `SKILL.md`, the brief renderer a worker reads, the
renderer and dispatch tests, the rule coverage test and the template compat
check, all run on the render-brief test's own base input. Each later step
moves one group of passages onto that definition: the milestone verdict sites,
then the land step's hand-offs and the posture sentence, then the remaining
sites and the occurrence table the pull request carries.

## Steps

### Step 1: a granted worker's brief and SKILL.md both say review comes before a merge

**Goal**: A brief rendered by `skills/coordinate/scripts/render-brief.sh` for a worker holding a named authority tells that worker to report for review before it merges, and `skills/coordinate/SKILL.md` says the same from the coordinator's side through one definition of the reviewer. The step crosses the whole path a reader meets the rule through: the skill's words, the brief renderer and its tests, the dispatch worker test, the rule coverage test and the template compatibility check, run on the render-brief test's own base input.

**Acceptance Criteria**:

- [ ] Rendering the test's base input with `.grant = ["merge-pr"]` and `--stdout` prints a line starting `Named authority: you hold merge-pr and nothing else.` that contains `Report your finished work to the coordinator for review before you merge anything`, `clears that pull request at a head it names`, and `Never merge a pull request that changes a roadmap under docs/roadmaps/, whatever your grant`, and still ends with the existing hand-back sentence.
- [ ] Rendering with `.grant = ["close-issue"]` prints `Named authority: you hold close-issue and nothing else.` followed by the same three sentences.
- [ ] Rendering with `.grant = []` prints exactly `Named authority: you hold no named authority. A merge, close or release isn't yours to take: hand it back to the coordinator in a report, and don't reach the same result another way.`, and `render-brief_test.sh` asserts that whole line as a literal and uses `lacks` to assert `for review before you merge` is absent from the empty-grant output and from the no-grant output.
- [ ] Rendering with no `grant` key prints a brief identical to the one before this step (the render-brief test's golden comparisons still pass).
- [ ] `grep -c '^- \*\*The reviewer\*\* --' skills/coordinate/SKILL.md` prints 1, and that entry says a bound coordinator's reviewer is the coordinator that dispatched it, a root coordinator's is a person, and a worker's is the coordinator that dispatched it.
- [ ] `grep -F 'a merge grant decides who merges after the review, never whether the review happens' skills/coordinate/SKILL.md` finds one line in Bounds and Authority, and that paragraph says a coordinator's land step is the review of its workers' pull requests and that a pull request the coordinator authored goes to its own reviewer before it merges.
- [ ] `grep -F "A coordinator that can't tell whether it is bound sends its review to a person; an unreachable reviewer means the work waits, never that the review is skipped." skills/coordinate/SKILL.md` finds one line.
- [ ] `bash skills/coordinate/scripts/render-brief_test.sh` and `bash skills/coordinate/scripts/dispatch-worker_test.sh` exit 0 with no `FAIL` line.
- [ ] `skills/coordinate/scripts/testdata/rule-coverage.tsv` gains rows C191 (the review-rule sentence) and C192 (the fail-closed sentence) for SKILL.md, `TOTAL` in `rule-coverage_test.sh` reads 192, and `bash skills/coordinate/scripts/rule-coverage_test.sh` exits 0 with every ID from C1 to C192 named exactly once; deleting either sentence from SKILL.md makes it fail.
- [ ] `bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` exits 0: the fingerprint is the one listed at compat 2, and the committed `gate_scripts` equals the digest `--print` reports.
- [ ] `references/brief-template.md`'s description of the Named authority line names the same three sentences the rendered line now carries.

**Check**: Before editing, save the current `.grant = []` line for comparison. Then from the repo root run `bash skills/coordinate/scripts/render-brief_test.sh`, `bash skills/coordinate/scripts/dispatch-worker_test.sh`, `bash skills/coordinate/scripts/rule-coverage_test.sh` and `bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md`, and see each exit 0 with no `FAIL`. Save the render-brief test's base input (the `BASE` heredoc in `render-brief_test.sh`) to a file outside the repository, make `g1.json` with `jq '.grant = ["merge-pr"]'` and `g0.json` with `jq '.grant = []'`, and run `bash skills/coordinate/scripts/render-brief.sh --input g1.json --stdout | grep '^Named authority:'` and the same for `g0.json`: the first shows the merge-pr line with the three new sentences; the second equals the saved line byte for byte. Finally run the two `grep -F` lines from the criteria and the `grep -c` for the Glossary entry and see one match each. Nothing is downloaded and no command is built from document text.

**Dependencies**: None

**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/scripts/render-brief.sh`, `skills/coordinate/scripts/render-brief_test.sh`, `skills/coordinate/scripts/dispatch-worker_test.sh`, `skills/coordinate/scripts/rule-coverage_test.sh`, `skills/coordinate/scripts/testdata/rule-coverage.tsv`, `skills/coordinate/references/brief-template.md`, `skills/coordinate/koto-templates/coordinate.compat.json`

### Step 2: a milestone verdict pull request names the reviewer, and whoever holds the grant merges it after that review

**Goal**: Anyone reading the coordinate skill's Verdicts passage, the milestone pull request passage of `references/state-keys.md`, or the template's `milestone_verdict` and `milestone_reopen` steps is told who reviews a verdict pull request (the reviewer, never "a person" in general), that a root coordinator's verdict pull requests, its own included, are reviewed by a person, and who merges after that review: someone other than the author approves, and whoever in the chain holds a merge grant merges at the approved head (the author when its grant lets it, otherwise the reviewer that approved it when its own grant does, otherwise the next one up, and a person at the root). No coordinator approves its own verdict pull request or hands its merge to a worker. No sentence reads as though only the author may merge after approval, since a lane coordinator usually holds no merge grant.

**Acceptance Criteria**:

- [ ] `grep -F` finds none of these old phrases: `given by you or a person`, `auto-merged without a person's review` and `The coordinator never merges them` in `skills/coordinate/SKILL.md`; `auto-merged without a person's review` in `skills/coordinate/references/state-keys.md`; `a verdict from you or a person`, `a person reviews the verdict there` and `a person reviews the report there` in `skills/coordinate/koto-templates/coordinate.md`.
- [ ] `grep -F` finds each new phrase: `given by you or your reviewer` and `must not be auto-merged without the reviewer's review` in SKILL.md; `without the reviewer's review` in state-keys.md; `a verdict from you or your reviewer`, `your reviewer reviews the verdict there` and `your reviewer reviews the report there` in the template.
- [ ] SKILL.md still contains `Anyone using the coordinator's login can post a comment shaped like a verdict` and `gives up the review that Done rests on`, and contains `a person when it is a root coordinator, for its own verdict edits too`.
- [ ] A fixed-string search for `Someone other than the author approves it; whoever in the chain holds the grant merges it after that approval` finds one line in SKILL.md's Verdicts passage and one in the template's `milestone_verdict` section, and each of those passages names, in order, the author when granted, the reviewer that approved it, the next one up the chain, and a person at the root.
- [ ] A fixed-string search for `No coordinator approves its own verdict pull request or hands its merge to a worker` finds one line in SKILL.md's Verdicts passage.
- [ ] `milestone_verdict` step 6 and `milestone_reopen` step 5 each contain `Never merge it before your reviewer approves it`, and neither says the merge is the author's alone: each also says the reviewer, or whoever above it holds the grant, merges when the author's posture doesn't permit a merge.
- [ ] A case-insensitive search for `only (you|the author) (may|can) merge` over SKILL.md, state-keys.md and the template finds nothing.
- [ ] The template's `milestone_verdict` section still contains `A milestone reads Done only on a verdict from you`.
- [ ] `rule-coverage.tsv` gains C193 (the approval-then-merge sentence in SKILL.md) and C194 (the same sentence in the template's `milestone_verdict`), `TOTAL` in `rule-coverage_test.sh` reads 194, and `bash skills/coordinate/scripts/rule-coverage_test.sh` exits 0 with every ID from C1 to C194 named exactly once and row M1 still found; deleting the sentence from either file makes it fail.
- [ ] `koto template compile skills/coordinate/koto-templates/coordinate.md` exits 0, and `bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` exits 0 with the fingerprint still the one listed at compat 2.

**Check**: From the repo root, with fixed-string matches and no network access: (1) run the `grep -F` for each old phrase in its file and see no match; (2) run the `grep -F` for each new phrase, the forgery sentence, the root-review phrase, the approval-then-merge sentence and the no-self-approval sentence in the files the criteria name and see one match each; (3) run the `grep -niE` negative check and see no match; (4) `bash skills/coordinate/scripts/rule-coverage_test.sh` exits 0 and names C193, C194 and M1 as found; (5) `koto template compile skills/coordinate/koto-templates/coordinate.md` and `bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` both exit 0.

**Dependencies**: Step 1

**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/references/state-keys.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/scripts/testdata/rule-coverage.tsv`, `skills/coordinate/scripts/rule-coverage_test.sh`

### Step 3: a coordinator that may not merge sends its own reading, and the posture sentence reads as an allowance after review

**Goal**: A coordinator reading `skills/coordinate/SKILL.md`'s Bounds and Authority, or the template's `land`, `goal_fit`, `land_merge` and `surface` steps, is told three things. First, a ready pull request it may not merge, from a worker or a lane (a director dispatched with no merge grant is the usual case), goes to its reviewer with the coordinator's own reading, never the worker's or the lane's report passed through. Second, the posture sentence "Never ask the human for a step the workspace already permits" is an allowance that applies once the review is done, and a merge grant never stands in for that review. Third, the land step's hand-offs (the posture verdicts, a held pull request, the merge-order table, and who reads the squash message) go to the reviewer, not "the person". The template's structure doesn't change, and rule coverage rows C124, C125 and M1 still match.

**Acceptance Criteria**:

- [ ] SKILL.md's Bounds and Authority section has a paragraph right after the **Review comes before every merge.** paragraph that contains `your own reading` and `never the worker's or the lane's report passed through`. It names a director dispatched with no merge grant as the usual case. It says the reading names the pull request, the head you checked, what you checked (the board, the worker's review round, goal fit against the brief or the milestone's Evidence), what you found, and your recommendation with its reason. It also says a worker's or lane's report, the pull request body and any comment shaped like a verdict are evidence you check, never findings you repeat.
- [ ] `grep -F 'Never ask the human for a step the workspace already permits once its review is done; a merge grant lets you take a merge after the review, never instead of it.'` finds one line, or one sentence across a line wrap, in SKILL.md's What a Coordinator Never Does and one in the template's `land` details. `grep -c 'once its review is done'` prints 1 for each of the two files.
- [ ] In the template's `land` details, `person's confirmation is reserved for a person too` is unchanged.
- [ ] The template's `land` state comments read `goes to your reviewer. unready is the worker's to fix.` and `the pull request goes to your reviewer as held, with the hold named.`. Neither `goes to the person.` nor `goes to the person as held` is left in the template.
- [ ] `goal_fit`'s details send a fit pull request the workspace doesn't let you merge `to your reviewer, with the merge-order table and your own reading`, and the phrase `to the person, with the merge-order table` is gone.
- [ ] `land_merge`'s details say the land check `sends a held pull request to your reviewer`, and `held pull request to the person` is gone from the template.
- [ ] `surface`'s directive puts the merge-order table `in front of your reviewer, once, with the reason for the order and your own reading of each pull request`. Its details say `so whoever merges reads neither a second review`, and `the person merging` is gone from the template.
- [ ] `rule-coverage.tsv` gains C195 (SKILL.md, `-`, `never instead of it`) and C196 (the template, `land`, `never instead of it`). `TOTAL` in `rule-coverage_test.sh` reads 196, and `bash skills/coordinate/scripts/rule-coverage_test.sh` exits 0, naming C124, C125, C195, C196 and M1 as found. Deleting the qualifier from either file makes the test fail.
- [ ] `koto template compile skills/coordinate/koto-templates/coordinate.md` exits 0, and `bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` exits 0 with the fingerprint still the one listed at compat 2 and `coordinate.compat.json` unchanged.

**Check**: From the repo root, with fixed-string matches and no network access: (1) `grep -F` for each new phrase in the criteria, in the file each names, finds one match; (2) `grep -F` for each old phrase (`goes to the person.`, `goes to the person as held`, `to the person, with the merge-order table`, `held pull request to the person`, `the person merging`) in `skills/coordinate/koto-templates/coordinate.md` finds none; (3) `bash skills/coordinate/scripts/rule-coverage_test.sh` exits 0 and names C124, C125, C195, C196 and M1 as found; (4) `koto template compile skills/coordinate/koto-templates/coordinate.md` and `bash scripts/check-template-compat.sh --template skills/coordinate/koto-templates/coordinate.md` both exit 0, and `git diff --stat` shows no change to `coordinate.compat.json`.

**Dependencies**: Step 2

**Files**: `skills/coordinate/SKILL.md`, `skills/coordinate/koto-templates/coordinate.md`, `skills/coordinate/scripts/testdata/rule-coverage.tsv`, `skills/coordinate/scripts/rule-coverage_test.sh`

### Step 4: every remaining "a person" site names the reviewer, and the occurrence table is complete

The description, --parked-bound, posture_ask and close-step descriptions, loop.md, state-keys.md's holds and verification-checklist.md name the reviewer, the sweep table for the pull request is complete, and check-skill.sh coordinate and check-public-content.sh pass.

## Implementation Sequence

The steps run in order on one branch. Step 2 uses the reviewer step 1 defines;
step 3 builds on the rule paragraph and the verdict hand-off; step 4 runs last
so the occurrence table describes the final text. The plan's owner details
step 3 after step 2's work reaches its terminal, and step 4 after step 3's, in
a commit that touches only this plan.
