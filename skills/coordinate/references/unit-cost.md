# Unit cost entries

Every unit the coordinator tears down gets one `cost` entry on its record.
The teardown pass writes it between the archive and `niwa destroy`, through
`scripts/unit-cost.sh capture`; nobody runs anything for it, and nothing
about the teardown depends on it. This page says what the entry holds, how
each figure is defined, and how to read entries back.

## Where it comes from

The capture reads four things and writes two:

- the teardown archive the pass just made: the unit's koto sessions
  (`koto/<session>/`), their verdict ledgers, the worker's transcripts
  (`transcript/`) and the job's `state.json`;
- the unit's koto request, which stays on the host after teardown (koto's
  request directory, `KOTO_REQUESTS`; found through a session's
  `request-leg.toml`), for dispatch;
- GitHub, read only: each pull request's merge time and head branch, its
  commits, the workflow runs on that branch and every earlier attempt of
  each run, and repository visibility;
- the record's run facts and the Holdings row for the unit's topic, for the
  milestone.

It writes `unit-cost.json` into the archive (to a temporary name, then
renamed; it is not in the MANIFEST, and the archive's README says so) and
posts one `cost` entry through `record-append.sh`. A record that already
holds a `cost` entry with the same capture key gets nothing new.

The capture has 90 seconds for its reads, each GitHub read bounded on its
own, and the pass stops it at 120. Whatever it hasn't taken when time runs
out is posted as `not recoverable` with reason `time limit`; a missing
source, a failed read or input outside its expected shape does the same with
its own reason. Either way the teardown goes on exactly as it would have.

## Definitions

Every figure is in one of four states. **measured**: read from its source
by the definition below. **bound**: a lower bound, never the figure itself.
**not recoverable**: the source is gone, unreadable or out of time; the
entry's `missing` list says which and why. **not applicable**: the figure
means nothing for this unit. Nothing is estimated.

- **Dispatch**: the `created_at` of the unit's koto request. Requests a
  session inside the unit made (a `/deliver` asking its `/scope`, say) are
  not the dispatch; the earliest of the rest is. With no request, the job's
  `createdAt`; with neither, not recoverable. A request id outside koto's
  grammar makes it not recoverable, since the request it names can't be
  read.
- **Green**: among a pull request's heads, in commit order, the first where
  every workflow run on that head (each run's final attempt) concluded
  `success` or `skipped`; green is the latest finish time among those runs.
  A unit with several pull requests is green when the last of them is. If
  the first such head still has runs that haven't concluded (none failing),
  green is `bound` at the latest finish so far.
- **Merge**: the pull request's merge time; for several, the last.
- **State time**: within one koto session, a state lasts from the
  `transitioned` or `rewound` event that entered it to the next such event.
  A state's total is the sum of its visits. Nothing after the session's
  first entry into `done` counts; a session with no `done` ends at its last
  event.
- **Unit sessions**: the archived sessions run from the `work-on` template
  (a plan's children, or a single issue's session). The others feed only
  plan shape and the per-session state totals.
- **Writing code**: the unit sessions' total time in `implementation`. It
  includes the worker's test runs; no source separates them.
- **Review**: the unit sessions' total time in `scrutiny`, `review` and
  `qa_validation`.
- **Outside share**: one minus writing code divided by dispatch to green.
  **Review share**: review divided by dispatch to green.
- **Session span**: from a session's first state change to its first entry
  into `done` (or its last event). Its implementation and review shares
  divide its own time in those states by its span.
- **Summed session spans**: every unit session's span added up. Where
  sessions overlapped it exceeds the wall-clock it covers; it is never
  wall-clock.
- **Minutes per unit**: for a unit that ran a plan, the mean of its unit
  sessions' spans.
- **Panel rounds**: per session and per panel in its verdict ledger
  (`ctx/verdict_ledger.json`, `.history[]`), the distinct rounds beyond the
  first, summed over the unit sessions. Not recoverable when no unit session
  has a ledger.
- **Failing heads**: the pull request heads, up to and including the green
  head, on which any attempt of any workflow run concluded `failure` or
  `timed_out`. A head that failed once and passed on a rerun counts;
  `cancelled` doesn't.
- **Tokens**: assistant messages counted once by message id, each of the
  four classes (input, output, cache creation, cache read) at the largest
  value written for that id, since a streamed message is written several
  times with growing usage. `worker` is the job's own transcript and its
  `subagents/`; `nested` is every other transcript in the archive.
- **Precision**: minutes to 0.1 and shares to 0.1 percentage point, rounded
  half up once from the unrounded value; counts and tokens exact. A figure
  can differ by 0.1 from one computed out of the rounded figures beside it.
- **Weakest state**: a figure computed from others (the two dispatch spans,
  both shares) takes the weakest state among its inputs: not recoverable if
  any is, else bound if any is, else measured. Failing heads is bound with
  green, since a run still going may yet fail.

With no unit session at all, the session-based figures are not applicable.

## Plan shape and milestone

**Plan shape**, one per unit, from the archived sessions in byte order of
their names, first match wins:

1. a `/deliver` session's context key `plan_execution_mode`: `single-pr`,
   `multi-pr` or `coordinated`;
2. an `/execute` session's template: `execute-coordinated.md` is
   `coordinated`, `execute.md` is `single-pr`;
3. a `/work-on` session's entry `mode`: `plan_backed` is `multi-pr`,
   `issue_backed` and `free_form` are `issue`;
4. otherwise `none`.

A session that matches but whose value can't be read, or a session whose
header can't be read at all, makes the shape not recoverable.

**Milestone**, one per unit, from the Holdings row's Unit for the topic, cut
at its first `: ` (so `Feature 4: Title` gives `Feature 4`). On a roadmap
record it is `{roadmap: ROADMAP-<name>, tag}`; on a discipline record, or
when the Unit is an issue reference (`#12`, `owner/repo#12`), it is `none`.
A Unit outside `^[A-Za-z0-9][A-Za-z0-9 _.#/-]{0,63}$` is dropped and the
milestone is not recoverable, as it is when the run facts or the Holdings
row can't be read.

## The entry

The comment, after `record-append.sh`'s marker and stamp, is one summary
line, a blank line and one fenced `json` block holding a compact object:

````
Cost of <topic> (<capture key>): <n> sessions, <worker output> output tokens, dispatch to merge <m> min.

```json
{"schema":"unit-cost/1", ...}
```
````

| Field | Shape |
|---|---|
| `schema` | `"unit-cost/1"`; a reader treats any other value as unreadable |
| `key` | the archive directory's name, `<UTC date>-<topic>-<job id>` |
| `captured_at` | UTC, to the second |
| `topic` | the dispatch topic |
| `record` | `{scope, name, repo, ref}` from the run facts, or `null` |
| `unit` | the Unit's tag, `"not public"`, or `null` |
| `milestone` | `{value, state, source: "record"}` |
| `plan_shape` | `{value, state, source: "koto-state"}` |
| `pulls` | `[{repo, number, merge_commit, merged_at}]`, or `{repo: "not public"}` for one the host may not name |
| `dispatch` | `{value, state, source}`, source `koto-request` or `job-state` |
| `figures` | `dispatch_to_green_min`, `dispatch_to_merge_min`, `writing_code_min`, `review_min`, `outside_share_pct`, `review_share_pct`, `panel_rounds`, `failing_heads`, `sessions_without_done`, `summed_session_span_min`, `minutes_per_unit`, each `{value, raw, state, source}` |
| `sessions` | per archived session, in byte order of the names: `{index, template, unit_session, done, span_s, states, figures}`; `figures` holds `span_min`, `impl_share_pct` and `review_share_pct`, the shares not applicable outside unit sessions |
| `tokens` | `{worker, nested}`, each `{messages, input, output, cache_creation, cache_read, state, source: "transcripts"}` |
| `complete` | `true` when `missing` is empty |
| `missing` | `[{figure, reason}]`, reason one of `no source`, `read failed`, `time limit`, `entry size`, `invalid input` |

`value` is a number (or `null` unless the state is measured or bound),
rounded as above; `raw` keeps what it was rounded from: seconds for the time
figures, the percentage for shares, the count for counts. `source` is one of
`koto-request`, `job-state`, `koto-state`, `verdict-ledger`, `transcripts`,
`github-pr`, `github-runs`, `derived`. A session's `states` maps each state
to its seconds and `span_s` is its span, both to the millisecond, so the
states sum to the span exactly. `template` is one of `deliver`, `scope`,
`execute`, `work-on`, `other`; sessions carry no names, since a plan's child
names carry its issue titles.

An entry over 50,000 bytes is posted without the `states` maps (each set to
`null`, `missing` naming `sessions.states` with reason `entry size`); the
archive's `unit-cost.json` keeps them.

On a public host (the record's repository is public, or its visibility
can't be read), a pull request whose repository isn't read as public is
written as `{repo: "not public"}`, and an `owner/repo#n` Unit naming one as
`"not public"`. A failed lookup counts as not public. The figures are kept.

## Evidence, not proof

Every figure comes from files the worker itself could write: its koto state,
its ledgers, its transcripts. The capture reads them as untrusted input (it
keeps only numbers, ids, timestamps and closed-set words, each matched to
its shape) but it can't tell an honest record from a shaped one. A second
derivation from the same archive agreeing with the entry shows the capture
computed what the archive holds, not that the archive holds what happened.

## Reading entries

The entries are ordinary record comments. With `gh` and `jq`, for a record
`owner/repo#n`:

```bash
gh api "repos/<owner>/<repo>/issues/<n>/comments" --paginate \
  --jq '.[] | select(.body | startswith("<!-- coordinator-record-entry v1 kind=cost -->")) | .body' \
  | sed -n '/^```json$/,/^```$/p' | grep -v '^```' \
  | jq -c 'select(.schema == "unit-cost/1")
           | {key, unit, plan_shape: .plan_shape.value,
              minutes: .figures.summed_session_span_min.value,
              output_tokens: .tokens.worker.output, complete}'
```

A record can hold the same key twice (a capture that couldn't list the
record posts anyway); keep the latest and report the repeat. Read a figure's
`state` before its `value`: a `bound` or `not recoverable` figure is not a
measurement and doesn't belong in a sum.
