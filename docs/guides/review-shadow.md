# Review shadow

The review-shadow trial graded pull requests with closed criteria beside their
review panels, and later shadowed the seats of four review sites with the
decider, keeping every result in a local store. That's over. The trial's
local store, its grader (`grade`, `outcome` and `report`) and the decider
shadow at review sites (`site`, which the brief, PRD and `/review-plan` phase
files and `/work-on`'s `panel-scope.sh --record` used to start) are retired.
No skill or script writes to the store any more.

`scripts/review-shadow/review-shadow.py` now keeps only two commands, `check`
and `scan`, which run the six script criteria (`rs-001` to `rs-006`), and the
slicers that the Jev criteria contracts name as their slice script. Jev
criteria, their slice contracts and pass trust are described in
`references/jev-criteria.md`. The tool needs Python 3.8 or later and nothing
outside the standard library.

The trial's requirements and approach are in
`docs/prds/PRD-jev-review-shadow.md` and
`docs/designs/current/DESIGN-jev-review-shadow.md`, and the review sites' in
`docs/designs/current/DESIGN-jev-closed-criteria.md`. They record what the
trial did, not what runs now.

## The two commands

| Command | What it does | Writes |
|---|---|---|
| `scan` | runs the six script criteria over your local branch | nothing |
| `check` | loads the criteria and category files and reports problems | nothing |

## Checking your own branch

```
scripts/review-shadow/review-shadow.py scan --base origin/main --private-terms <file>
```

`scan` runs the six script criteria over your branch and prints each failure
as rule id, path and line, never the matched term. It exits 1 when any
criterion failed or couldn't be checked, and writes nothing. The repository
counts as public unless its `CLAUDE.md` declares `Repo Visibility: Private`.

`--private-terms <file>` (or `REVIEW_SHADOW_PRIVATE_TERMS`) names a local file
of private terms: one term per line, blank lines ignored, lines starting with
`#` treated as comments. The file must live outside every git work tree, and
it's never sent or recorded. Without it the private-name check reports itself
as not checked. `--body-file <file>` adds a pull request body, so the checks
that read the body see it too.

## Changing the criteria

Criteria live in `scripts/review-shadow/criteria.json`, and finding
categories in `scripts/review-shadow/categories.json`. After any edit, run
`scripts/review-shadow/review-shadow.py check`; CI runs it too.

To add a criterion:

- Give it the next `rs-NNN` id. Ids are never reused.
- Give it a `group` that is a category in `categories.json`, and list its id
  under that category's `rule_ids`.
- Point `rule_ref` at the repository file whose rule it checks.
- Add its entry to `references/rule-registry.json`; the registry checks hold
  the two files to the same `rs-` ids.
- A script criterion also needs a check function in `review-shadow.py`,
  named by `check` and listed in its `CHECKS` table.
- A Jev criterion's question can name the slice's input labels (such as
  `pr_body_part1` or `location_a`); those are the keys the slicer emits. Its
  registry entry holds its slice contract.
- Bump the file's `version` whenever a question or description changes.

To turn a criterion off, set `"enabled": false` rather than deleting it: its
registry entry still names it, and its id can't be reused.

## The slicers

The slicers cut the bounded slices a Jev criterion reads: a pull request's
summary (Part 1 beside its file list), its code hunks around comments and its
doc pairs, and for the review sites a brief's journeys and summaries, a PRD's
acceptance criteria, a plan's issue criteria and a local change's hunks per
criterion. They stay because the contracts in `references/rule-registry.json`
name `review-shadow.py` as their slice script, and
`scripts/jev-criteria/jev_criteria.py measure prs` sizes pull-request slices
with them.

A slice is held to 2,560 bytes. One that can't fit whole is marked over the
bound instead of being cut mid-unit, except a pull request body, which is cut
at a paragraph or sentence end and says so.

## Records already on disk

Records the trial wrote under
`${XDG_STATE_HOME:-$HOME/.local/state}/shirabe/review-shadow/` are no longer
added to. Some contracts' measured sizes were taken from them, and
`jev_criteria.py measure records --dir <dir>` still reads them, so keep the
directory if you want to reproduce those figures.
