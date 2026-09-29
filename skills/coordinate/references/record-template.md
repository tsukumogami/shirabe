# The Record: Template and Procedures

What the record holds, and where it lives for each scope, are in
`skills/coordinate/SKILL.md`. This file holds the literal shapes and the
steps that open, update and close it. Load it when you open or update the
record.

## Container and Host

| Scope | Host repository | Container |
|---|---|---|
| Roadmap `docs/roadmaps/ROADMAP-<name>.md` | the roadmap's repository | an issue titled `Coordinator record: ROADMAP-<name>` |
| Discipline `<name>` | the host repository the human named | a draft pull request from `coordinate/discipline-<name>` |

A roadmap's record is an issue because an issue fits a record that commits
nothing: there is no branch to maintain, no merges from the default branch
to absorb, and it closes cleanly when the roadmap finishes. A rotation's
record is a pull request because its diff is the handoff file it commits
at the end.

Name every worker, in the record and in every pull request, by its dispatch
topic, never by session id, instance path or job id: those are host facts
that don't survive a restart or a move, and reconcile finds sessions by
topic. When the record's host repository is public, it never names a
private repository, path or issue; a holding that would need one is a
scope question for the human.

## Finding or Opening the Record

The workflow finds the record itself, on every start, before the first
dispatch: `scripts/record-find.sh` runs as the `record_find` state's check,
and you open a record only when it reports none, with `scripts/record-open.sh`.

**Roadmap scope.** The find lists every open issue and matches the record's
title exactly. It never uses GitHub's search: the search index can lag a newly
created issue, so a coordinator restarted just after opening its record would
find none and open a second, and a phrase search also matches longer titles
such as a `-v2` roadmap. One open issue with the title, the declaration line,
an author and last editor with write access, and a canonical body is adopted;
never open a second one. A title match without the declaration line, more than
one match, a body that isn't canonical, or an author without write access is a
stop for the human: don't pick, report what you found and ask.

**Discipline scope.** The find reads the branch `coordinate/discipline-<name>`
and its pull requests, and reports one of these:

1. **An open pull request carrying the declaration line, whose title's end date
   hasn't passed:** a restart of that rotation; it is adopted, never replaced.
2. **The same, past its end date:** the previous rotation's record; close it out
   as "Closing a Predecessor's Rotation" says, and once it has merged, the find
   runs again.
3. **An open pull request without the declaration line:** not adopted; a scope
   question for the human.
4. **A branch whose last pull request merged or closed, or that never had one:**
   `record-open.sh --recut` deletes it and cuts it again from the default
   branch, so a squash-merged history never comes back.
5. **No branch:** `record-open.sh` cuts it from the default branch, makes an
   empty commit, and opens the draft pull request.

Report the record's issue number or pull request URL up with every report,
so a successor is handed it as a decision and reads it directly.

## The Rotation's Pull Request Title

`docs(coordinate): <name> rotation <start> to <end>`, with both dates in
`YYYY-MM-DD` form from the day it opens. The end date is the start plus
the rotation's length. If the human ends the rotation early, or sets a new
length, edit the end date to match in the same update that records the
decision; the title is where a successor reads it.

## The Body

The body is rendered by `scripts/record-render.sh` from its JSON form and read
back by `scripts/record-parse.sh`; never write it by hand. A body is valid only
when rendering what was parsed reproduces it byte for byte, so the tables below
are the whole record and nothing else may sit between them. A rotation's pull
request body starts with the fixed Part 1 line and a single `---`, which the
renderer writes (`--container pr`); an issue body starts at the declaration
line.

```markdown
> This is a **coordinator record** for <ROADMAP-<name> | the <name> discipline>.

Written: <YYYY-MM-DDTHH:MM:SSZ>

## Holdings

| Unit | Entry point | Mode | Phase | Dispatch status | Return path | Worker | Repo | Branch | Verified head | Dispatched | Pull request |
|---|---|---|---|---|---|---|---|---|---|---|---|
| <feature, issue, question or choice> | <skill> | <--auto and flags> | <scoping-ahead, executing or held> | <dispatching, dispatched or dispatch-failed> | <message, or leg <request-id>:<leg>> | <dispatch topic> | <owner/repo> | <branch, blank until known> | <full sha once verified, else blank> | <YYYY-MM-DD> | <[#n](URL), blank for none yet> |

## Deferrals

| Deferral | Reason | Raised | Disposition |
|---|---|---|---|
| <what> | <why not now> | <YYYY-MM-DDTHH:MMZ> | <blank, filed #n, closed: <reason>, or carried <YYYY-MM-DDTHH:MMZ> [until <YYYY-MM-DDTHH:MMZ>]: <reason>> |

## Side effects in flight

| Action | Target | Verified head | Attempted | How to confirm |
|---|---|---|---|---|
| <merge, close, teardown> | <pull request, issue, worker> | <full sha verified before acting or asking> | <YYYY-MM-DDTHH:MMZ> | <the read that settles it> |

## Reversals

| Date | Reversed | Now | Reason | From |
|---|---|---|---|---|
| <YYYY-MM-DDTHH:MMZ> | <earlier decision> | <new decision> | <why> | <who decided> |
```

An empty section reads `None.` in place of its table. No table carries a
status, CI or merge-state column: those are read from GitHub every time, and
the renderer refuses one. Phase says whether a worker is scoping a unit whose
execution waits on another feature landing (`scoping-ahead`), executing it, or
holding a verified pull request whose merge the human directed held although the
workspace permits it (`held`).
A row leaves Side effects in flight once confirmed. Reversals only grow.

A deferral is disposed of when its Disposition reads `filed #<n>`,
`closed: <reason>`, or `carried <time>: <reason>` with a time at or after the
run's start. Filed and closed rows drop out at the first rewrite after the
run's first dispatch; a carried row stays with its new reason.

A carry can name a decide-by, `carried <time> until <time>: <reason>`; once
the until time passes, the deferral is open again. On a restart (a run opened
over a live run of the same scope, which it cancels), a carry made since the
first of those cancelled runs started still counts; a run that ended at a
handover or a finish breaks the chain.

The verified head is the sha the workflow verified before you acted or asked.
After a crash, confirming a merge compares the default branch against that sha,
not against whatever the branch holds now.

The renderer refuses a Worker cell holding anything but a dispatch topic (a
`/`, a UUID, a `session_` prefix, a `+`, or only digits), a malformed
structured cell, and a control character. Quoted text such as a CI log line
is safe in any cell: pipes, newlines and backticks are encoded so they can't
break a table.

### The Decisions section

After Reversals, once the record holds a decision, comes a fifth section. It
opens with the identifier the next decision takes, and has one row per decision
the scope opened:

```markdown
## Decisions

Next decision: <n>

| Decision | Round | Question | Options | State | Source | Verdict | Recommendation | Reason | Context | Problem | Grounds | Target | Owed | Asked | Evidence | Outcome | Decided by | Updated |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| <n> | <times escalated> | <one line> | <one per line> | <proposed, coordinator-verdict, escalated or settled> | <worker <topic>, coordinator <topic> #<n> round <r>, dispatcher or self, then a stamp> | <blank, settle, escalate or hold> | <one of the options> | <its reason, or what a hold waits on> | <what is being decided and why now> | <what is unresolved and why the coordinator can't settle it> | <scope, supplied-decision, reserved-step, outside-scope> | <a person or coordinator <topic>> | <blank, escalation, withdrawal or reply> | <YYYY-MM-DDTHH:MMZ> | <one line per item: <time> <source> <stamp>: <text>> | <outcome and reason> | <who decided> | <YYYY-MM-DDTHH:MMZ> |
```

Every entry has Decision, Round, Question, State, Source and Updated. What
each state means, and what else it requires:

| State | Means | Also requires | Reached by |
|---|---|---|---|
| `proposed` | Opened, not yet taken up | Options | `--open`, `--open-from-report` |
| `coordinator-verdict` | With the coordinator for a verdict; a Verdict of `hold` waits on the fact in Reason, and `escalate` is queued behind the escalated entry | Reason, when the Verdict is `hold` | `--take`; any evidence, from any state |
| `escalated` | Asked of the run's target, one entry at a time | Options (each `<option> -- <explanation>`), Recommendation, Reason, Context, Problem, Grounds, Target | `--escalate`, or the release of a queued verdict |
| `settled` | Decided | Outcome (`<outcome>; reason: <reason>`), Decided by | `--settle`, `--answer` |

Owed says which message the entry still owes (an escalation, a withdrawal
after new evidence on a sent escalation, or a reply to the source that asked),
and clears when `--sent` marks it. Asked is when the escalation went out.

A record written before the section existed has none and stays canonical. The
section appears at the first decision and stays: `Next decision` only goes up,
so an identifier is never reused, and a section holding `Next decision: 1` and
no entry is not canonical. A stamp, `[<run> <kind> <seq>]`, names the run (the
UTC stamp in its session's name) and the visit that caused a write. `@` is
encoded in the text columns so a record never mentions anyone, and those columns
refuse a private repository, a home-directory path and a token-shaped string.

Only `record-decision.sh` changes the section: `record-write.sh` refuses a body
whose section differs from the live record's, and `record-open.sh` refuses a new
record that carries one. A rotation's handoff carries the unsettled entries and
the same `Next decision`; a predecessor copy carries the section as it stands. A
roadmap record can't close while an entry is unsettled.

The write core refuses a body over 60,000 bytes (`record-full`, exit 13), under
GitHub's 65,536-byte limit.

The declaration line is for readers. It is deliberately different from the
`This is a **coordination PR**` marker that `/execute` uses, so no gate
written for coordination pull requests ever parses a record.

**Updating.** Parse the live body, change the JSON, and render the whole body
again keeping the live body's `Written:` time (`record-render.sh --written
<that time>`); apply it with the record's write script, never by editing the
body on GitHub. The write script compares that time with the live record's,
refuses with `record-changed` (exit 12) when someone wrote since, and stamps
its own time on what it writes. Every pull request in the record is a
link. Follow the host repository's conventions (its CLAUDE.md) for commit
messages and bodies.

## Closing a Roadmap Record

When every feature reads Done or Dropped on the roadmap, Holdings and Side
effects in flight are empty, every deferral is filed or closed, and every
decision is settled: write
the final body, then close the issue if the workspace permits, or hand the
close to the human.

## The Discipline Handoff

At rotation end, write `docs/disciplines/<name>.md`, one file per
discipline, overwritten each rotation. It is plain markdown with no
shirabe artifact prefix, so `shirabe validate` applies no structural
checks to it, though the host's docs validation still runs its prose
checks on it:

```markdown
# <name> handoff, <YYYY-MM-DD>

Rotation from <start> to <end>. Host repository: <owner/repo>. Record: <pull request URL>, kept on coordinate/discipline-<name>.

<the four sections, and the Decisions section with its unsettled entries when the record has one>

## Reasoning for the next rotation

<Prose: what this rotation learned that the tables can't say.>
```

The same renderer writes it (`--format handoff`). It carries no declaration
line and no `Written:` line, so a search for records never matches a committed
handoff.

Write the reasoning section fresh each rotation. Replace the previous
rotation's text; never append to it, or the handoff grows into a standing
protocol.

## Closing a Rotation

1. Commit the handoff to the record branch and push.
2. If the rotation ended on a different day than the title says, edit the
   title's end date to the actual one.
3. Mark the pull request ready and merge it if the workspace permits;
   otherwise hand it to the human as the last row of the merge-order
   table in `references/verification-checklist.md`.
4. Delete the branch once it has merged.

## Closing a Predecessor's Rotation

When the discipline check finds a previous rotation's record still open
past its end date, the successor closes it, and writes only what it can
stand behind:

- The tables are copied from the predecessor's record body as it stands,
  under a line reading "As written by the previous rotation at <its
  Written time>; not re-checked." Your own reconcile re-checks those rows
  when you carry them into your record.
- The reasoning section says the outgoing rotation's reasoning was not
  recorded. Never write it on the predecessor's behalf.
- Open deferrals carry into your own record, to be disposed of before your
  first dispatch.

Then follow Closing a Rotation for that record.
