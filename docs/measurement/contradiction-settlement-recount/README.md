# Contradiction-settlement re-count

The contradiction-settlement work deleted dead prose from the instructions
`/work-on`, `/execute`, `/deliver` and `/scope` load, and settled 48
contradictions between their files. Its design estimated, per profile, how
much of each profile's load that dead prose was. This directory re-runs the
[offload baseline](../offload-baseline/README.md)'s count after every
settlement pull request merged and sets what came out beside that estimate.

The design and its inventory are on the coordination branch of pull request
#507, not on `main`. The parts the re-count needs (the dead-prose entries
with each span's excerpt, the withholding candidates, the spans held for
policy items, the parent-skill reference list and the estimate itself) are
copied into `spans.json`, which names the commit they came from.

Nothing here is loaded by a run. The directory sits outside `skills/` and
`references/`, it adds no load-manifest row, and it changes no figure the
baseline records.

| File | Holds |
|------|-------|
| `recount.py` | The re-count: every check and every figure below |
| `spans.json` | The commits measured, the settlement pull requests, and the copied inventory data |
| `dropped-rows.tsv` | The load-manifest rows for files a profile no longer loads, each with its reason |

## Re-running it

```bash
python3 docs/measurement/contradiction-settlement-recount/recount.py --check
```

It prints nothing but a verdict, and fails if any check below fails or if the
figures between the markers in this file differ from what it computes. Without
`--check` it prints the figures; `--write` rewrites them here. Every file it
measures is read with `git show <commit>:<path>`, so it gives the same answer
from any checkout. It needs git and Python 3, plus what
`scripts/offload-baseline.sh` needs (jq).

`spans.json`'s inventory part was produced by
`recount.py extract 137ccd4b92d68e994d24a11f6a5d908a29414f14`, which reads the
inventory and the design at that commit. It only works while the commit is
reachable; the committed copy is what the re-count reads.

## What it checks before it counts

- **Every span by its excerpt.** Each dead-prose span is found by the excerpt
  the design prints for it, exactly once in its file at the inventory commit
  (`662f6ec`), inside the span's line range (or above it, for an excerpt the
  design marks `above:`). A missing or repeated excerpt fails the run and names
  the entry. An excerpt that `scripts/ablation/check-public-content.sh` refuses
  can't be added as text: two do, one in `dp-design-duplicates` and one in
  `dp-prd-internal-restatements`, because each quotes a skill's
  work-in-progress path template. `spans.json` stores those two as a sha256
  and a length, and the script finds them by hashing each substring of that
  length.
- **The estimate.** The per-profile estimate is recomputed from the spans the
  way the design computed it (overlapping spans counted once per profile, a
  pointer-loaded file counted in full) and must equal the design's figure.
- **Withholding candidates.** No estimate line may fall inside a withholding
  candidate. The design's estimate already leaves them out, and no policy item
  is undecided (all ten decisions are recorded and applied), so the target is
  the design's estimate as it stands, with nothing taken off it.
- **Dropped rows.** Each row in `dropped-rows.tsv` must exist in the load
  manifest. A `pointer-removed` file must be named, as a whole file name, by no
  span the profile still loads at the measured commit. The spans are the ones
  the manifest counts, so a YAML comment in a template's frontmatter, which
  koto never shows the agent, isn't searched; `work-on.md`'s frontmatter
  still names two of the dropped files that way. A literal mention that isn't
  a pointer (one example value in a code block) is listed in the row's fourth
  column, and the run fails if that text disappears. A `reference-table` file
  relies on `/scope`'s SKILL.md saying that nothing in its reference table is
  read up front; that one is a judgement, set out under "Reading the figures".

## How it counts

- **Before and after.** `scripts/offload-baseline.sh count` at the pinned
  commit (`2a3719e`) and at the measured commit (`0398358`, `main` once every
  settlement pull request had merged), with the load manifest read from the
  measured commit. The pinned figures are the restated ones in
  `token-baseline.tsv`, so `execute-single-pr` and `deliver` start lower than
  the raw figures the design copied (41,083 and 6,181), which predate the two
  restatements recorded in the baseline README.
- **Two manifests.** Once with the manifest as it is, and once with the rows
  in `dropped-rows.tsv` removed. The manifest as it is keeps counting a file
  whose pointer is gone; the second view drops it.
- **The settlement pull requests' share.** `count` at each settlement pull
  request's parent and at its merge commit, so the change those nine pull
  requests made is separated from everything else that landed on `main`
  between the pin and the measured commit.
- **Against the estimate.** `git blame --reverse` from the inventory commit to
  the measured commit says, for each line the estimate counts, which
  first-parent commit removed it, or that it's still there. A line a pull
  request rewrote counts as removed; the rewritten text shows in the net change
  columns instead. A pointer entry's file counts as removed only in the
  rows-removed view, and only when the file's row is dropped for every profile
  the entry names. Tokens are bytes divided by 4, rounded down, as the design
  rounds; the count's own columns round as the baseline does.

The inventory holds 48 contradictions: 38 mechanical and 10 policy. Two of
them, `prd-complexity-routing` and `prd-upstream-roadmap`, were added while
the work was being carried out, and reviewers called them items 47 and 48 by
the order they were added. The inventory identifies its items by name, not by
number, and in its file order they sit 40th and 41st, as the first lines of
the figures say.

## The figures

<!-- recount:begin -->
Commits: pin `2a3719e`, inventory `662f6ec`, measured `0398358`; inventory data copied from `137ccd4`.

Contradictions in the inventory: 48 (38 mechanical, 10 policy). `prd-complexity-routing` is item 40 and `prd-upstream-roadmap` item 41 in file order.

#### Raw tokens, before and after

| Profile | Pin | Main, manifest as is | Main, dropped rows removed | Change, as is | Change, rows removed |
|---|---:|---:|---:|---:|---:|
| `work-on` | 46,671 | 50,154 | 42,363 | 3,483 | -4,308 |
| `execute-single-pr` | 40,903 | 24,643 | 21,641 | -16,260 | -19,262 |
| `execute-coordinated` | 24,844 | 11,271 | 11,271 | -13,573 | -13,573 |
| `deliver` | 5,970 | 4,502 | 4,502 | -1,468 | -1,468 |
| `scope` | 226,407 | 208,595 | 183,643 | -17,812 | -42,764 |

#### Change the settlement pull requests made (raw tokens, manifest as is)

| PR | Group | Commit | `work-on` | `execute-single-pr` | `execute-coordinated` | `deliver` | `scope` |
|---|---|---|---:|---:|---:|---:|---:|
| #531 | decisions | `d34134d` | 0 | 0 | 0 | 0 | 0 |
| #534 | review-plan | `44bd606` | 0 | 0 | 0 | 0 | -1,703 |
| #541 | brief-prd-deliver | `dcf925f` | -133 | 0 | 0 | -1,732 | -6,691 |
| #557 | work-on | `3cc4c54` | -3,237 | -465 | 0 | 0 | 95 |
| #545 | execute | `273f7ae` | 0 | -17,075 | -15,476 | 0 | 0 |
| #586 | scope | `c4226c3` | 754 | 0 | 0 | 0 | -9,006 |
| #637 | design | `92fd1c5` | 0 | 0 | 0 | 0 | 108 |
| #658 | plan | `354ff38` | 0 | 0 | 0 | 0 | -3,807 |
| #660 | brief-prd-policy | `0398358` | 79 | 0 | 0 | 0 | 2,122 |
| | **Sum** | | **-2,537** | **-17,540** | **-15,476** | **-1,732** | **-18,882** |
| | Every other commit, pin to main | | 6,020 | 1,280 | 1,903 | 264 | 1,070 |

#### Against the DESIGN's dead-prose estimate (tokens are bytes divided by 4, rounded down)

| Profile | Estimate | Removed by the settlement PRs | Files no longer loaded | Removed by other commits | Still present | Realized, as is | Realized, rows removed | Settlement PRs' net change, as is | Net change, rows removed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `work-on` | 13,170 | 4,562 | 7,765 | 0 | 842 | 34.6% | 93.6% | -2,537 | -10,328 |
| `execute-single-pr` | 20,944 | 17,995 | 2,804 | 91 | 53 | 85.9% | 99.3% | -17,540 | -20,542 |
| `execute-coordinated` | 15,498 | 15,362 | 0 | 91 | 44 | 99.1% | 99.1% | -15,476 | -15,476 |
| `deliver` | 1,725 | 1,514 | 0 | 211 | 0 | 87.8% | 87.8% | -1,732 | -1,732 |
| `scope` | 27,558 | 27,474 | 0 | 0 | 84 | 99.7% | 99.7% | -18,882 | -43,834 |

#### Per entry (bytes)

| Entry | Profiles | Estimate | Removed by the settlement PRs | Files no longer loaded | Removed by other commits | Still present | Realized | Over 10% short |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `dp-work-on-retry-rationale-copies` | `work-on` | 8,378 | 8,243 | 0 | 0 | 135 | 98.4% | no |
| `dp-work-on-pointer-loaded-docs` | `work-on` | 24,710 | 0 | 24,710 | 0 | 0 | 100.0% | no |
| `dp-work-on-finishing-obligations-pointer` | `work-on` | 6,352 | 0 | 6,352 | 0 | 0 | 100.0% | no |
| `dp-work-on-rationale` | `work-on` | 6,412 | 3,178 | 0 | 0 | 3,234 | 49.6% | yes |
| `dp-work-on-duplicates` | `work-on` | 4,472 | 4,472 | 0 | 0 | 0 | 100.0% | no |
| `dp-work-on-missing-files` | `work-on` | 722 | 722 | 0 | 0 | 0 | 100.0% | no |
| `dp-work-on-koto-restated` | `work-on` | 1,636 | 1,636 | 0 | 0 | 0 | 100.0% | no |
| `dp-execute-skill-duplicates-template` | `execute-single-pr`, `execute-coordinated` | 31,033 | 30,666 | 0 | 367 | 0 | 98.8% | no |
| `dp-execute-skill-rationale` | `execute-single-pr`, `execute-coordinated` | 17,414 | 17,239 | 0 | 0 | 175 | 99.0% | no |
| `dp-execute-skill-dead-mechanisms` | `execute-single-pr`, `execute-coordinated` | 12,723 | 12,722 | 0 | 0 | 1 | 100.0% | no |
| `dp-execute-skill-koto-restated` | `execute-single-pr`, `execute-coordinated` | 824 | 824 | 0 | 0 | 0 | 100.0% | no |
| `dp-execute-template` | `execute-single-pr` | 7,992 | 7,955 | 0 | 0 | 37 | 99.5% | no |
| `dp-execute-pointer-loaded-refs` | `execute-single-pr` | 11,058 | 2,575 | 8,482 | 0 | 1 | 100.0% | no |
| `dp-execute-phase-6-pointer` | `execute-single-pr` | 2,735 | 0 | 2,735 | 0 | 0 | 100.0% | no |
| `dp-deliver-skill` | `deliver` | 6,901 | 6,057 | 0 | 844 | 0 | 87.8% | yes |
| `dp-scope-history` | `scope` | 7,140 | 7,134 | 0 | 0 | 6 | 99.9% | no |
| `dp-brief-history` | `scope` | 2,632 | 2,632 | 0 | 0 | 0 | 100.0% | no |
| `dp-plan-history` | `scope` | 422 | 422 | 0 | 0 | 0 | 100.0% | no |
| `dp-scope-rationale` | `scope` | 14,507 | 14,446 | 0 | 0 | 61 | 99.6% | no |
| `dp-plan-rationale` | `scope` | 4,141 | 4,141 | 0 | 0 | 0 | 100.0% | no |
| `dp-design-rationale` | `scope` | 597 | 597 | 0 | 0 | 0 | 100.0% | no |
| `dp-scope-duplicates` | `scope` | 14,772 | 14,772 | 0 | 0 | 0 | 100.0% | no |
| `dp-plan-duplicates` | `scope` | 2,793 | 2,793 | 0 | 0 | 0 | 100.0% | no |
| `dp-design-duplicates` | `scope` | 507 | 507 | 0 | 0 | 0 | 100.0% | no |
| `dp-scope-no-reader` | `scope` | 5,791 | 5,791 | 0 | 0 | 0 | 100.0% | no |
| `dp-scope-koto-restated` | `scope` | 7,255 | 7,255 | 0 | 0 | 0 | 100.0% | no |
| `dp-plan-koto-restated` | `scope` | 806 | 806 | 0 | 0 | 0 | 100.0% | no |
| `dp-brief-internal-restatements` | `scope` | 20,878 | 20,704 | 0 | 0 | 174 | 99.2% | no |
| `dp-prd-internal-restatements` | `scope` | 3,413 | 3,413 | 0 | 0 | 0 | 100.0% | no |
| `dp-design-internal-restatements` | `scope` | 3,947 | 3,880 | 0 | 0 | 67 | 98.3% | no |
| `dp-plan-internal-restatements` | `scope` | 13,469 | 13,441 | 0 | 0 | 28 | 99.8% | no |
| `dp-review-plan-internal-restatements` | `scope` | 7,460 | 7,460 | 0 | 0 | 0 | 100.0% | no |

#### Spans outside the estimate (bytes)

| Set | Size | Removed by the settlement PRs | Removed by other commits | Still present |
|---|---:|---:|---:|---:|
| Withholding candidates | 10,443 | 244 | 614 | 9,585 |
| Held for policy items | 4,466 | 1,247 | 0 | 3,219 |

#### Manifest rows removed, and the DESIGN's parent-reference files (bytes)

| Profile | File | Reason | At the pin | At main |
|---|---|---|---:|---:|
| `work-on` | `references/default-action-conversion.md` | pointer-removed | 15,746 | 15,746 |
| `work-on` | `references/koto-session-retention.md` | pointer-removed | 8,964 | 8,920 |
| `work-on` | `skills/work-on/references/finishing-obligations.md` | pointer-removed | 6,352 | 6,496 |
| `execute-single-pr` | `references/worktree-discipline.md` | pointer-removed | 8,482 | 8,949 |
| `execute-single-pr` | `skills/work-on/references/phases/phase-6-pr.md` | pointer-removed | 2,735 | 3,059 |
| `scope` | `references/parent-skill-pattern.md` | reference-table | 52,599 | 52,599 |
| `scope` | `references/parent-skill-state-schema.md` | reference-table | 19,791 | 19,950 |
| `scope` | `references/parent-skill-resume-ladder-template.md` | reference-table | 11,002 | 11,002 |
| `scope` | `references/parent-skill-child-inspection.md` | reference-table | 8,821 | 8,821 |
| `scope` | `references/parent-skill-security.md` | reference-table | 7,433 | 7,433 |
| `scope` | `references/worktree-discipline.md` | kept: a directive still names it | 8,482 | 8,949 |

Rows removed from `work-on` at main: 7,791 tokens, 16.7% of its raw load at the pin.
Rows removed from `execute-single-pr` at main: 3,002 tokens, 7.3% of its raw load at the pin.
Rows removed from `scope` at main: 24,952 tokens, 11.0% of its raw load at the pin.
<!-- recount:end -->

## Reading the figures

**Against the estimate, the deletions landed.** In the rows-removed view
every profile but `deliver` realized more than 90% of its estimate, and in
`deliver` the rest of the text is gone too, removed by a commit outside the
settlement set (below). "Realized" counts a rewritten line as removed, so it
is the upper bound of what was deleted; the net change columns show what the
same pull requests added back. The settlement pull requests also removed part
of the spans held for policy items, which the estimate leaves out. The
withholding candidates are still in place, apart from the part of the
introspection evidence the PLAN let the `/work-on` pull request delete (the
outcome values koto's evidence schema already delivers) and the key-list line
of each retry-clearing block, which #609 rewrote to add `light_results.json`
to the keys a retry clears.

**The net change is smaller than what was removed.** The settlement pull
requests also added text: the ten policy rulings, rewritten winners, and a
new dispatch shape in `references/fixes/sub-agent-dispatch.md`, which
`/work-on` loads too. That's why each pull request's own count change can be
smaller than the dead prose it deleted, and why a few are positive.

**`work-on` grew between the pin and `main`.** The settlement pull requests
took text out of it, but other changes that landed in the same period added
more (the panel retry and review-seat work among them), which the "every
other commit" row shows. Compare the settlement rows, not the before and
after columns, to see what settlement did.

**Which `/scope` rows the rows-removed view drops is a judgement.** The test
applied: a file stays loaded when a step the modelled run takes tells the
agent to carry out a procedure that lives in that file, and leaves the load
when the run's files only cite it for where a term or a rule is defined.
Phase 2's first step says to run the three-phase staleness flow "from"
`references/worktree-discipline.md`, so that row stays. The five parent-skill
references are cited ("per", "see", "is in", "extensions from"), and the
baseline's model already had the run not reading them: they carry weight 0,
so they were never in the weighted figure, only in raw. Two citations come
close to the line: SKILL.md's exit-finalization step names the R9 extensions
"from" `parent-skill-state-schema.md`, and Phase 2 points to
`parent-skill-pattern.md`'s Dispatch Contract. Read `scope`'s rows-removed
figure as the upper bound of what settlement took out of its raw load and the
as-is figure as the lower bound. The design reported the six files as 11.9%
of `scope`'s raw load; the five dropped here are the share printed under the
last table.

**The manifest keeps the dropped rows.** The baseline's "Maintaining the
baseline" rules require a restatement when a file or state the manifest lists
is removed; these files all still exist, so `count` still succeeds and no
restatement is owed. Whether the baseline itself should stop counting them is
a change to its load model, not something a re-count decides, and it is
proposed for the contradiction-settlement follow-up issue (#659). Until then,
a measurement that wants the post-settlement load should apply
`dropped-rows.tsv`, as `recount.py` does.

Only raw figures are compared: the design's estimate is a raw figure, and the
weights are fixed inputs the settlement didn't change. `count` prints the
weighted figures at any commit for a reader who wants them.

## Shortfalls over 10% of the estimate

Two entries fall short in the rows-removed view. In the as-is view three
profiles fall short: `deliver` for the reason its entry gives, and `work-on`
and `execute-single-pr` for the reason in the last bullet.

- **`dp-work-on-rationale`.** Two spans in `references/pr-body-conformance.md`
  are still there: the "Why a single source" section, and the span that runs
  from the paragraph explaining which slice of the body check PB4 gates
  through the "Accepted residuals" and "Consumers" sections. The `/work-on`
  pull request (#557) edited that file only to correct the check count
  (PB1-PB3 to PB1-PB4) and recorded no reason for keeping either span. The
  design classed both as rationale; `work-on` and `execute-single-pr` still
  load them. Deleting them, or recording why they stay, is proposed for the
  follow-up issue (#659). The other kept bytes are the title line of
  `skills/work-on/references/koto-context-conventions.md`, which the deletion
  of the paragraph under it left as the file's heading.
- **`dp-deliver-skill`.** All of it is gone, but part was removed before the
  settlement pull request reached it: #542, which made `/deliver` and
  `/execute` run in private repositories, rewrote some of the same SKILL.md
  lines. Its share shows as removed by other commits.
- **`work-on` and `execute-single-pr`, manifest as is.** The pointer entries
  (`dp-work-on-pointer-loaded-docs`, `dp-work-on-finishing-obligations-pointer`,
  `dp-execute-pointer-loaded-refs`, `dp-execute-phase-6-pointer`) take a file
  out of the load by deleting its pointer. The manifest as it is still counts
  those files, so in that view the entries realize only their in-line spans.
  This is the case the rows-removed view is for; there, both profiles clear
  90%.

Every other entry realized at least 90% of its estimate. What remains of each
is a heading, a table header or a sentence the deleting pull request kept so
the text around the deletion still reads whole.
