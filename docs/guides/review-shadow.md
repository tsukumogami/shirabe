# Review shadow trial

The shadow trial grades a pull request with a batch of closed criteria, some
checked by script and some asked of Jev, and records the result beside the
pull request's review panel. After fifteen to twenty pull requests per panel
kind, its report says how often a unanimous pass agreed with a clean panel.
That's the evidence for deciding whether a unanimous pass may ever stand in
for a panel.

Nothing in the trial approves, skips or shortens a panel. A unanimous pass is
a line in a local file.

The requirements are in `docs/prds/PRD-jev-review-shadow.md` and the approach
in `docs/designs/DESIGN-jev-review-shadow.md`. The tool is
`scripts/review-shadow/review-shadow.py`; it needs Python 3.8 or later and
`gh`.

## Before a panel: grade the head

```
scripts/review-shadow/review-shadow.py grade --repo <owner/repo> --pr <n> --head <sha> \
    --panel-kind pre-merge --panel-run claude:<session-id> \
    --private-terms <file>
```

The command runs the six script criteria first and then sends the four Jev
criteria, one request per slice. It writes one record and prints its path,
the run status (`unanimous-pass`, `dissent`, `inconclusive` or `not-graded`)
and the Jev tokens used.

- `--head` is the full sha the panel reviews. Any head the pull request ever
  had can be graded, so a merged pull request can be graded at the head its
  panel read.
- `--body-at <YYYY-MM-DDTHH:MM:SSZ>` grades the body as it read at that time,
  from the pull request's edit history. Leave it out to grade the body as it
  reads now.
- `--private-terms` names a local file of private terms, one per line, which
  must live outside every git work tree. Without it the private-name check is
  not run, and the run can't be a unanimous pass.
- `--unbatched` sends each criterion in its own request, for comparing
  accuracy against the default batched mode on the same slices.
- The Jev key is read from `JEV_API_KEY`, or `KOTO_DECIDER_API_KEY` when that
  is unset. Without a key the scripts still run and the record says
  `not-graded` with reason `no-key`.

## After the panel: record its outcome

```
scripts/review-shadow/review-shadow.py outcome --repo <owner/repo> --pr <n> --head <sha> \
    --panel-kind pre-merge --panel-run claude:<session-id> \
    --finding <category>:<disposition>[:inferred][:<code>] ...
```

Give one `--finding` per blocking finding, and none for a clean panel. The
category is one of those in `scripts/review-shadow/categories.json`. The
disposition is `upheld`, `narrowed`, `dismissed` or `unknown`. Mark it
`inferred` when it wasn't recorded at the time. The optional code is up to 32
characters from `[a-z0-9-]`, for your own cross-reference; there is no
free-text field. When a fix round changes a disposition, record the same
panel run again and the outcome is replaced.

Panel kinds are `scrutiny`, `review` and `qa` for a worker's in-run panels,
and `pre-merge` for the panel before merge. A panel run id is
`claude:<session-id>` or `koto:<workflow>:<koto-session-id>`.

## Reading the report

```
scripts/review-shadow/review-shadow.py report [--mode batched|unbatched] [--json]
```

The report keeps out-of-sample records, graded before their panel's outcome
was known, apart from in-sample ones. Only the out-of-sample table is the
test. Every table is split by panel kind and by diff kind: `docs` when a
change touches only Markdown under `docs/` or the top-level `README.md`,
`code` when it touches none of those, and `mixed` otherwise. The coverage
table shows what share of upheld blocking findings any criterion could have
caught; a flip can only ever be safe for that share.

## Checking your own branch

```
scripts/review-shadow/review-shadow.py scan --base origin/main --private-terms <file>
```

`scan` runs the six script criteria over your branch and prints each failure
as rule id, path and line, never the matched term. It writes nothing.

## Where records live

Records and outcomes are written under
`${XDG_STATE_HOME:-~/.local/state}/shirabe/review-shadow/`, with directories
0700 and files 0600, and never inside a git work tree. Every record carries
`trial: jev-review-shadow`, so the trial's spend can be reported apart from
normal work. The report's last line totals it.

## Cost

Across the twelve heads of the in-sample demonstration, a grade cost between
about 14,000 and 240,000 Jev input tokens, with a median near 32,000, and
output tokens around a twentieth of that. The stale-comment criterion
accounted for 89% of the input tokens: it asks one question per packed group
of changed code, so cost grows with the size of the code change.
