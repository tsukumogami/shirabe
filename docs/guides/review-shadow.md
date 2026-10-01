# Review shadow trial

The shadow trial grades a pull request with a batch of closed criteria, some
checked by script and some asked of Jev, and records the result beside the
pull request's review panel. Its report says how often a unanimous pass
agreed with a clean panel. That's the evidence for deciding, one criterion
at a time, whether a check can move into a koto decider check. The PRD's R20
says when the trial ends and what result flips a criterion.

Nothing in the trial approves, skips or shortens a panel. A unanimous pass is
a line in a local file.

The requirements are in `docs/prds/PRD-jev-review-shadow.md` and the approach
in `docs/designs/current/DESIGN-jev-review-shadow.md`. The tool is
`scripts/review-shadow/review-shadow.py`; it needs Python 3.8 or later and
`gh`, logged in to an account that can read the repository.

## The five commands

| Command | What it does | Writes |
|---|---|---|
| `grade` | grades one pull request at one head | one record |
| `outcome` | records a panel's result for one pull request and head | one outcome, and a placeholder record if the head was never graded |
| `report` | prints agreement between grades and panel outcomes | nothing |
| `scan` | runs the script criteria over your local branch | nothing |
| `check` | loads the criteria and category files and reports problems | nothing |

## Before a panel: grade the head

```
scripts/review-shadow/review-shadow.py grade --repo <owner/repo> --pr <n> --head <sha> \
    --panel-kind pre-merge --panel-run claude:<session-id> \
    --private-terms <file>
```

Run it before the panel records its outcome. A head graded after its outcome
exists, or graded again later, gets an in-sample record: it's kept apart and
never counts as the test. The command prints the record's path, its run
status, `in_sample=`, the Jev tokens used and any reasons.

The arguments:

- `--head` is the full 40-character sha the panel reviews. Any head the pull
  request ever had can be graded.
- `--panel-kind` is what kind of panel sits beside this grade: `pre-merge`
  for the panel before merge, or `scrutiny`, `review` or `qa` for a worker's
  own panels during a run. It's optional here and required on `outcome`.
- `--panel-run` identifies the panel run, so the grade and the outcome join.
  It's `claude:<session-id>` for the Claude Code session that runs the panel
  (in that session, `echo $CLAUDE_CODE_SESSION_ID`), or
  `koto:<workflow>:<koto-session-id>` for a koto workflow. It's optional
  here: `outcome` fills it into any grade record of the same head that lacks
  one.
- `--private-terms <file>` (or `REVIEW_SHADOW_PRIVATE_TERMS`) names a local
  file of private terms: one term per line, blank lines ignored, lines
  starting with `#` treated as comments. The file must live outside every git
  work tree, and it's never sent or recorded. For a public repository,
  running without it leaves the private-name check unanswered, so the run
  can't be a unanimous pass. A repository counts as private only when GitHub
  says so explicitly.
- `--body-at <YYYY-MM-DDTHH:MM:SSZ>` grades the body as it read at that UTC
  time, from the pull request's edit history. Leave it out to grade the body
  as it reads now.
- `--body-file <file>` grades the body in that file instead, for a body the
  edit history can't reach.
- `--enable <rule-id>` also runs a criterion that ships off. `rs-009` and
  `rs-010` ship off because they cost the most: `rs-010` took most of the
  Jev tokens in the demonstration.
- `--unbatched` sends each Jev criterion in its own request instead of one
  request per slice, to compare accuracy between the two modes.

The Jev key is read from `JEV_API_KEY`, or `KOTO_DECIDER_API_KEY` when that is
unset.

### When grade fails or records not-graded

`grade` exits 2 without writing a record when an argument is wrong or `gh`
can't read the pull request; the message names the cause and the fix (not
logged in, wrong `--repo` or `--pr`, a `--head` the pull request never had,
the rate limit). Fix it and run it again.

A record with status `not-graded` was written but graded nothing Jev could
answer. Its reason says why:

| Reason | Meaning | What to do |
|---|---|---|
| `no-key` | no Jev key in the environment | set the key and grade again |
| `transport`, `provider` | Jev couldn't be reached, or answered with an error, twice | grade again later |
| `over-bound` | every slice Jev would grade was still over 2,560 bytes after the body was cut (the file list leaves under 512 bytes for the body) | nothing; it's left out of the agreement rates |
| `no-changed-paths` | the head changes nothing | nothing; this head can't be graded |
| `outcome-without-grade` | an outcome was recorded for a head nobody graded | nothing; it's counted as not graded |

Grading again is safe: each run writes a new record, and the report reads
the latest one for each head. A record that says `inconclusive` isn't a
failure of the tool: some criterion escaped or went unanswered (for example
`no-denylist` when no term list was given, or `over-bound` for a slice over
2,560 bytes that other graded slices sit beside).

A pull request body over the 2,560-byte bound is cut, not skipped: Part 1 is
trimmed at a paragraph or sentence end and ends with a "cut here" line, and
the slice's record carries `body_cut`.

## After the panel: record its outcome

```
scripts/review-shadow/review-shadow.py outcome --repo <owner/repo> --pr <n> --head <sha> \
    --panel-kind pre-merge --panel-run claude:<session-id> \
    --finding <category>:<disposition>[:inferred][:<code>] ...
```

Give one `--finding` per blocking finding, and none for a clean panel.

- The category is a key of `scripts/review-shadow/categories.json`.
- The disposition is `upheld`, `narrowed`, `dismissed` or `unknown`. Only
  `upheld` and `narrowed` findings make the panel blocked.
- `inferred` marks a disposition that wasn't recorded at the time.
- The optional code is up to 32 characters from `[a-z0-9-]`, for your own
  cross-reference. There is no free-text field, because the store is
  archived.

When a fix round changes a disposition, record the same panel run again and
the outcome is replaced.

## Reading the report

```
scripts/review-shadow/review-shadow.py report [--mode batched|unbatched] [--json]
```

The report keeps out-of-sample records, graded before their panel's outcome
was known, apart from in-sample ones. Only the out-of-sample table is the
test. Every table is split by panel kind and by diff kind: `docs` when a
change touches only Markdown under `docs/` or the top-level `README.md`,
`code` when it touches none of those, and `mixed` otherwise.

The columns:

- **agreement**: heads where a unanimous pass met a clean panel, or a
  non-pass met a blocked one, over all scored heads.
- **false passes**: unanimous passes on blocked panels. The false-pass rate
  is over unanimous passes, with its 95% upper bound beside it.
- **miss rate**: false passes over blocked panels.
- **fail on clean**: runs where a criterion failed although the panel was
  clean.
- **no verdict on clean** and **no verdict (all heads)**: runs where a
  criterion escaped or went unanswered. No verdict counts as a fail for
  agreement, since it would send the change to the panel, but it has its own
  columns so a question the grader couldn't answer is never read as a real
  dissent.
- **passes on zero slices**: unanimous passes where a Jev criterion had
  nothing to read, such as a comment check on a docs-only change.
- **not graded** and **undetermined**: heads left out of every rate, because
  the grade never ran or the panel's only findings have an unknown
  disposition.

The coverage table shows what share of upheld blocking findings a criterion
that ran could have caught. A flip can only ever be safe for that share.

The model string Jev reports is in every record. The tool asks for
`jev-latest`, so a new Jev build mid-trial can move the numbers.

## Checking your own branch

```
scripts/review-shadow/review-shadow.py scan --base origin/main --private-terms <file>
```

`scan` runs the six script criteria over your branch and prints each failure
as rule id, path and line, never the matched term. It writes nothing. The
repository counts as public unless its `CLAUDE.md` declares
`Repo Visibility: Private`.

## Changing the criteria

Criteria live in `scripts/review-shadow/criteria.json`, and finding
categories in `scripts/review-shadow/categories.json`. After any edit, run
`scripts/review-shadow/review-shadow.py check`; CI runs it too.

To add a criterion:

- Give it the next `rs-NNN` id. Ids are never reused.
- Give it a `group` that is a category in `categories.json`, and list its id
  under that category's `rule_ids`.
- Point `rule_ref` at the repository file whose rule it checks.
- A script criterion also needs a check function in `review-shadow.py`,
  named by `check` and listed in its `CHECKS` table.
- A Jev criterion's question can name the slice's input labels (such as
  `pr_body_part1` or `location_a`); those are the keys the slicer emits.
- Bump the file's `version` whenever a question or description changes.
  Every record carries the version and a hash of the file, so runs before
  and after the change can be told apart.

To retire a criterion, set `"enabled": false` rather than deleting it, so
old records still resolve. Retiring a category is different: the report
reads the category map as it is now, and an outcome whose category is gone
is counted as open judgment. Old outcomes are reclassified, so keep a
category that stored outcomes use.

## Where records live

Records and outcomes are written under
`${XDG_STATE_HOME:-~/.local/state}/shirabe/review-shadow/`, with directories
0700 and files 0600, and never inside a git work tree. Every record carries
`trial: jev-review-shadow`, the tool version and the criteria version, so the
trial's spend can be reported apart from normal work. The report's last line
totals it.

## Cost

This was measured once, on the twelve heads of the in-sample demonstration
made when the tool was built. With every criterion on, a grade cost between
about 14,000 and 240,000 Jev input tokens per pull request, median about
32,000. The stale-comment criterion took 89% of it, which is why it ships
off. With the default criteria, on the same twelve heads, a grade cost
about 950 to 1,260 Jev input tokens and 83 output tokens.
