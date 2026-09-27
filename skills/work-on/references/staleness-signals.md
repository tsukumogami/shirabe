# Staleness signals

What `/work-on`'s `staleness_check` gate means by "stale", stated in one place.
The check is `skills/work-on/scripts/check-staleness.sh`; the gate runs it
against the issue a run is about to implement.

## The four checks

An issue is **stale** when any one of these fires, and **fresh** when none do.

These are the previous check's rules, kept unchanged, and they fire on almost
everything. On 2026-09-27 they marked all 65 open milestone issues in shirabe
and tsuku stale, mostly on age. Retuning them is shirabe#440.

| Check | Fires when | Threshold |
|-------|------------|-----------|
| Issue age | the issue was created more than the threshold ago, in whole days | 14 days (`AGE_THRESHOLD_DAYS`) |
| Closed milestone siblings | at least one issue in the same milestone was closed after this issue was created | 1 |
| Milestone position | the issue is `last` (some milestone issues closed, exactly one open) or `middle` (some closed, any other number open, zero included) | position `middle` or `last` |
| Referenced files | a file the issue body names has a commit touching it since the issue was created | 1 file |

Details that decide edge cases:

- Age is `floor((now - createdAt) / 86400)`, so an issue exactly 14 days old
  is fresh.
- Position is `first` when no issue in the milestone is closed, and `unknown`
  when the issue has no milestone or the milestone lists are empty. Neither
  fires. A milestone sibling closed after creation always moves the position
  off `first`, so the sibling check never fires without the position check;
  it still counts, because its number says how much moved.
- Milestone lists are read with a limit of 100 closed and 100 open issues. A
  larger milestone undercounts.
- A referenced file is a path in the body that ends in `.go`, `.ts`, `.tsx`,
  `.js`, `.jsx`, `.md`, `.sh`, `.py`, `.toml`, `.yaml`, `.yml` or `.json`:
  either anything inside backticks, or a bare run of letters, digits, `_`, `-`
  and `/` followed by a one-to-four-letter extension. The bare form matches
  slashless names like `README.md`, and it can take a prefix of a longer name
  (`foo.json` out of `foo.jsonl`). At most 20 are checked, in sorted order. A
  path that is absolute or has a `..` segment is skipped, as is one that isn't
  a file in the working tree. "Modified" means
  `git log --since=<createdAt> -- <path>` finds a commit.

## Exit statuses

| Status | Verdict | The directive's evidence |
|--------|---------|--------------------------|
| 0 | fresh | `fresh` |
| 1 | stale | `stale_requires_introspection` |
| 3 | unavailable: `gh`, `jq` or `git` missing, a `gh` call failed, a `git log` failed, a response couldn't be read, or the temporary directory or the report couldn't be made | `unavailable`, with the reason in `detail` |
| 2 | usage error: anything but `--issue <positive integer>` | `blocked`; the template passed a bad argument |

The gate also exits 3 itself when the script isn't executable at
`{{PLUGIN_ROOT}}`, and koto reports -1 when it couldn't run the gate to
completion (the gate timed out or failed to start), which the state treats as
unavailable too.

On 0, 1 and 3 the script prints a JSON report: `verdict`,
`introspection_recommended`, the `issue` (number, title, created_at, age_days,
milestone), the `signals` (each measured value plus `age_threshold_days`), and
a `reason`. On 3 the report carries `verdict`, `reason` and the issue number.

## Differences from the check used before

Before shirabe shipped this check, the gate called a script of the same name
that shirabe didn't provide. The four checks and their thresholds above are
unchanged from it. What changed:

| Area | Before | Now |
|------|--------|-----|
| Argument | the issue number as a positional argument | `--issue <N>` only; a bare number is a usage error |
| How the verdict reaches the gate | a JSON field, read by `jq -e` in a pipe | the exit status; the JSON report is still printed |
| Age arithmetic | GNU `date -d`, which fails on BSD `date` and then reads as age 0 | `jq`'s `fromdateiso8601` and `now`, the same on Linux and macOS |
| A failed milestone query | counted as no siblings, which reads as fresh | unavailable; no verdict from partial data |
| `gh` calls | four (the closed list fetched twice) plus `gh auth status` | at most three: the issue, the closed list, the open list |
| `gh`, `jq` or `git` missing | its own error exit, which the gate read as stale | unavailable |
| A `git log` failure on a referenced file | not counted as modified | unavailable |
| Paths with `..` or a leading `/` | checked if they existed | skipped |

Nothing else differs: the same extensions, the same limit of 20 files, the
same limit of 100 per milestone list, and the same rule for positions.
