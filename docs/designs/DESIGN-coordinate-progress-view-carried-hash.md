---
schema: design/v1
status: Accepted
problem: |
  `skills/coordinate/scripts/progress-view.sh` refuses the whole progress table
  (exit 65, nothing on stdout) when any plain cell holds text that looks like a
  commit hash. Some of that text isn't written for the render: a follow-up Work
  row's `next`, written at merge time, often names a squash commit and a head, and
  pick copies it into the unit's Next cell as-is. The coordinator can't reword it
  at render time, so every table for that run is refused and the coordinator
  writes one by hand, skipping every check the script makes (shirabe#1575).
decision: |
  Split the hash check by where the text comes from. Text the coordinator passes
  for this render (`--next` and `--blocked`) is checked once, before any row is
  built, and a hash there is still refused with exit 65. Every plain cell `row()`
  prints (Kind, Unit, Status, Next) goes through a new jq `masked` filter that
  replaces each token `hashy` would flag with the literal word `(commit)`, using
  the same pattern, the same digit-and-letter test and the same dispatcher cut.
  The table then always renders for valid facts, and no row of it holds a
  flagged token. The record and `coord/pick.json` are unchanged.
rationale: |
  Masking only the carried text keeps the refusal where it does some good: the
  coordinator wrote `--next` and `--blocked` text for this report and can reword
  it, while carried text was written earlier, is legitimate in the record, and
  can't be changed from the render. Building `masked` from the same pieces as
  `hashy` means a masked cell can never trip the check, so the display rule holds
  by construction and a test can assert it on stdout. Masking everything would
  silently rewrite text the coordinator just typed; refusing at write time would
  keep heads out of the record that the coordinate guidance puts there and leaves
  existing records broken; dropping the text or the row loses information the
  reader needs.
---

# DESIGN: Progress table rendering when record-carried text holds a commit hash

## Status

Accepted

## Context and Problem Statement

`/coordinate` ends every report after the reconcile with one progress table, and
`skills/coordinate/scripts/progress-view.sh` renders it from the pick facts
(`coord/pick.json`). The SKILL.md section "What the human sees" sets the display
rule the script enforces: a pull request is a clickable link, a session is inline
code, and no commit hash appears on screen. The verified head stays in the record
and the evidence, never in the table.

The script enforces the hash half of that rule with one check in its jq `row()`
function. Every row's plain cells (Kind, Unit, Status, Next) go through `hashy`,
which scans for a standalone 7-40 character lowercase hex token holding at least
one digit and one letter. If any cell in any row matches, `row()` raises
`<session>: a cell holds a commit hash`, the script prints
`progress-view: refused: ...` and exits 65, and nothing reaches stdout.

That check treats two kinds of text the same way:

- Text the coordinator types for this render, through `--next KEY=TEXT` and
  `--blocked KEY=NEED`. When this holds a hash, refusing is the right answer: the
  coordinator wrote it moments ago and can reword it on the next call.
- Text the table carries from earlier writes: a unit's title, a decision's
  question, recommendation and reason, and a follow-up Work row's `who` and `next`,
  which pick copies into each unit's `follow_up` as-is. The follow-up row is
  written at merge time, when naming the squash commit and the merged head is
  normal (for example "squash cc60dd68 at head 2b2031b7"), and the coordinate
  guidance itself says heads stay in the record's rows.

When carried text holds a hash, the refusal can't be fixed at render time. The
coordinator has no flag to reword it, and the only way out is to rewrite the
record row. In the case shirabe#1575 reports, a roadmap run had two follow-up
rows whose `next` named a squash commit and a head. Every call to
`progress-view.sh` for that run exited 65, so the coordinator wrote the table by
hand, which skips every check the script exists to make: merge order, blockers,
link and session formatting, and the hash rule itself.

The design question is how `progress-view.sh` renders a table when a carried
cell holds hash-like text, while still showing no commit hash on screen.

## Decision Drivers

- **No hash on screen.** The SKILL.md display rule is not relaxed. Whatever the
  script prints on stdout holds no token `hashy` would flag, and a test can show it.
- **A table always comes out for valid facts.** Text written earlier in the run,
  which the coordinator can't change at render time, must not block the whole
  table. Otherwise the coordinator falls back to a hand-written table and loses
  every other check.
- **Keep the pressure on text written for this render.** `--next` and `--blocked`
  text is the coordinator's own wording for this report; refusing a hash there is
  still useful and is what the existing tests assert.
- **The record keeps its content.** Heads and squash commits are legitimate in the
  record's rows; the fix must not require the record or `coord/pick.json` to drop
  them.
- **Small and checkable.** The change stays inside `progress-view.sh` and its test
  file, reuses the existing `hashy` detection so "masked" and "refused" can't
  disagree, and lands as one testable rule.

## Considered Options

### Decision 1: How the script treats hash-like text, by where the text comes from

The table has two sources of plain-cell text. Text typed for this render arrives
through `--next KEY=TEXT` and through the need text a `--blocked KEY=NEED` is
worded into. Carried text arrives in the pick facts: unit names and titles, a
follow-up's `after` and `next`, a decision's question, recommendation and reason,
phases, pause ids and targets. Today `row()` refuses both kinds the same way. The
question is what the script does with each kind so a table still comes out and no
hash is printed.

Key assumptions:

- Session and PR cells stay out of this. They're checked separately (a session
  must be a session name, a PR a link to one pull request), and worker and unit
  names are the keys the flags match on, so they must reach the matching code
  unchanged.
- No script parses the rendered cells; a person reads the table.
- Fields such as `follow_up.after`, `.phase` and `.target` hold identifiers in
  practice. If one ever holds a hash-shaped token, it shows as `(commit)`, which
  is still safe.

#### Chosen: Mask carried text, refuse typed text

Before any row is built, the jq program checks every `--next` value and every
worded `--blocked` need with `hashy`. A match is refused as today: exit 65,
nothing on stdout, and a stderr line naming the key and saying the text holds a
commit hash. The coordinator wrote that text for this report and can reword it.

Every plain cell `row()` prints then goes through a new `masked` filter that
replaces each token `hashy` would flag with the literal word `(commit)`. Typed
text has already passed the check, so masking it changes nothing; carried text
loses its hashes and keeps every other word. The issue's follow-up row renders its
Next cell as `its execution: squash (commit) at head (commit)`.

`masked` is built from the same three pieces as `hashy`: the token pattern, the
test that a token holds both a digit and a letter, and the cut that leaves the
`--dispatcher` name alone (tightened for both to a whole-word match, as
Components describes). A cell after `masked` can't contain a token `hashy`
flags, so the display rule holds by construction rather than by a second check
that could drift from the first.

The replacement word is `(commit)`, plain text. `reconcile-report.sh` masks full
SHAs as `<commit>`, but in a markdown table a bare `<commit>` can be read as an
HTML tag and disappear, and the display rule reserves inline code for sessions.

#### Alternatives Considered

- **Mask every cell and drop the refusal.** One rule instead of two, but a hash
  the coordinator types into `--next` would be swapped silently instead of
  refused, and the existing `--next` refusal test would flip. The refusal keeps
  the coordinator's own wording free of hashes, where it can still act on it.
- **Refuse hashes when the follow-up row is written.** This moves the check into
  `state-stored-set.sh --kind follow-up`. The coordinate guidance keeps heads in
  the record's rows, so the record would start rejecting content it legitimately
  holds; records that already carry a hash, like the one in shirabe#1575, would
  stay unrenderable; and decision text and titles would still be uncovered. It
  also changes the record's write path, which is outside this fix.
- **Replace the whole carried cell with a fixed phrase.** When a carried cell
  holds a hash, print something like "see the record" instead. It's no safer than
  masking the one token, and it throws away the words that matter, such as the
  execution step a follow-up names or the question a decision asks.
- **Drop the offending row.** The table stops being complete, the "n of m in
  line" counts go wrong, and a decision meant for a person could vanish from the
  one table they read.

### Decision 2: Where the typed-text check runs

Decision 1 needs typed text refused and carried text masked, but by the time a
value reaches `row()` the two are mixed in the Next cell, as
`$next[$w] // <carried default>`.

#### Chosen: Check typed text once, up front, in the same jq program

The check runs over `$next` and `$blocked` at the start of the jq program, with
the same `hashy` the masking is built from, and `row()` masks all four plain
cells without asking where each came from. That gives two short rules, each in
one place.

#### Alternatives Considered

- **Tag each Next value at its call site and have `row()` refuse or mask by tag.**
  This keeps a single checkpoint in `row()`, but every row expression has to pass
  the right tag, and a new row type that forgets it would mask typed text
  silently.
- **Check typed text in bash, next to the existing phrasing check.** The flags are
  already checked there for decision phrasing, but the hash pattern lives in jq
  (with PCRE lookarounds), and a second copy in bash regex could drift from it.

## Decision Outcome

`progress-view.sh` treats hash-like text by its source. Text passed for this
render through `--next` or `--blocked` is refused before any row is built, as
before. Every plain cell the table prints is masked: each token the existing hash
test flags becomes `(commit)`. A table therefore always comes out for valid pick
facts, whatever the record carries, and no row of the table holds a flagged
token. (The `Paused:` line printed above the table is outside this change; see
Consequences.) The
record, `coord/pick.json`, pick and the record's write path are unchanged.

The rule a test checks: given pick facts whose unit carries a follow-up with
`next` set to `squash cc60dd68 at head 2b2031b7`, `progress-view.sh` exits 0, that
unit's Next cell reads `its execution: squash (commit) at head (commit)`, and no
table row on stdout (a line starting with `|`) holds a token the hash test flags.
Given
`--next <key>=rebase onto 0123abcd`, it still exits 65 with nothing on stdout.

## Solution Architecture

### Overview

All changes are in `skills/coordinate/scripts/progress-view.sh`, its test file
`skills/coordinate/scripts/progress-view_test.sh`, and the one sentence of
`skills/coordinate/SKILL.md` that says what the script refuses.

### Components

The jq program's hash helpers are split so detection and masking share their
parts:

- `hashre`: the token pattern, `(?<![0-9A-Za-z])[0-9a-f]{7,40}(?![0-9A-Za-z])`,
  unchanged.
- `flagged`: true for a token holding at least one digit and one letter, the
  existing `test("[0-9]") and test("[a-f]")`.
- The dispatcher cut: while `--dispatcher` exists, the text is split on the
  dispatcher name and each part is handled on its own, so the name's hex-looking
  suffix is never flagged or masked. `masked` joins the parts back with the name,
  so the name prints unchanged. The split matches the name only as a whole word
  (not followed by a letter or digit), with the name regex-escaped before it
  goes into jq's regex `split` (every regex metacharacter escaped, not only the
  `.` a session name may hold): today's plain
  `split` lets
  `lead-1a2bc3d4e5` through unflagged under `--dispatcher lead-1a2b`, and the
  build closes that gap.
- `hashy`: some `hashre` token in some part is `flagged`. Same result as today,
  except that the whole-word cut now flags hex that runs on from the dispatcher
  name, which the plain split let through.
- `masked`: in each part, replace every `hashre` token that is `flagged` with
  `(commit)` (a `gsub` with a named capture), then join the parts.

### Key Interfaces

- **Typed-text check.** At the top of the program, for each entry of `$next`, and
  each `$blocked` need as jq receives it (already worded by the bash loop; a
  dispatcher name the wording adds is skipped by the dispatcher cut), whose
  value is `hashy`, raise
  `<key>: the text given for this render holds a commit hash`. The existing error
  path prints it as `progress-view: refused: ...` and exits 65. Every entry is
  checked, including one whose key names no row. The message keeps the phrase
  "a commit hash" that the `--next` refusal test looks for. The two
  dispatcher-bound tests that look for the old `a cell holds a commit hash` pass
  their hash through `--next`, so they stay refusals and only their expected
  phrase changes (see the test cases below).
- **`row()`.** Its four plain cells go through `cell` and then `masked`. The
  `hashy` refusal inside `row()` goes away, since nothing can reach it any more.
  Session and PR cells keep their own checks and aren't masked.
- **Exit codes.** Unchanged: 0 printed, 65 refused, 64 usage. Carried text can no
  longer cause a 65.
- **Header comment.** Lines 32-34 say a hash-shaped cell is refused; they change
  to say text passed for this render is refused and carried text is masked as
  `(commit)`.
- **SKILL.md.** The sentence saying the script "refuses a table that breaks the
  display rule" is reworded to say it refuses a hash in the text you pass and
  masks one carried from the record. The display rule under "What the human sees"
  stays word for word.

### Data Flow

A follow-up row written at merge time keeps its hashes in the record. Pick copies
its `who` and `next` into the unit's `follow_up` unchanged. `progress-view.sh`
reads the pick facts, refuses if a flag's text holds a hash, builds each row, and
masks each plain cell on the way out. The person reading the table sees `(commit)`
where the record has a SHA; the SHA stays in the record and the evidence, where
the checks read it.

### Test cases the build adds

These go in `progress-view_test.sh`, each built from `testdata/progress/pick.json`
with jq patches, as the existing cases are. The follow-up fixture uses the shape
`pick-facts.sh` writes (`follow_up: {after, next}`, copied from the Work row
unchanged), so feeding it to `progress-view.sh` is the issue's repro from pick
onward.

1. **The issue's repro.** A queued unit whose `follow_up.next` is
   `squash cc60dd68 at head 2b2031b7`: exit 0, and its Next cell reads
   `its execution: squash (commit) at head (commit)`.
2. **A carried Status.** A `follow_up.after` holding a 7-character SHA: exit 0,
   and the Status cell reads `scoping landed in (commit)`.
3. **Decision text.** A decision escalated to a person whose question,
   recommendation and reason each hold a 40-character SHA: the row renders with
   `(commit)` in place of each and still shows its recommendation and reason.
4. **A unit title.** The existing case "a hash in a unit's title is refused"
   becomes "a hash in a unit's title is masked": exit 0 and `(commit)` in the
   Unit cell.
5. **Typed text is still refused.** The existing `--next ... rebase onto 0123abcd`
   case stays: exit 65, empty stdout, stderr names a commit hash. A new case
   passes the same `--next` for a unit that also carries a hashed follow-up, to
   show the typed check wins rather than the flag text being masked.
6. **A blocked need.** A `--blocked` need whose text holds a hash, such as
   `credential 0123abcd`, is refused the same way.
6a. **The dispatcher bounds, typed.** The two existing cases at lines 119 and
   121 ("only the dispatcher's name is left out of the hash scan" and "the
   dispatcher's suffix alone is still a hash elsewhere") pass the hash through
   `--next`, which is typed text. They stay refusals (exit 65, empty stdout);
   only their expected stderr phrase changes from `a cell holds a commit hash`
   to `a commit hash`.
6b. **The dispatcher bounds, carried.** New cases feed the same shapes through a
   carried follow-up under `--dispatcher lead-1a2b3c4d`: a cell holding the name
   prints it unchanged, and a cell holding `rebase onto 1a2b3c4d` (the suffix
   alone) prints `rebase onto (commit)`. A third case covers the whole-word cut:
   under `--dispatcher lead-1a2b`, a carried `lead-1a2bc3d4e5` prints as
   `lead-(commit)`, where today's plain split leaves the six-character remainder
   unflagged and prints the ten-character hex.
7. **Nothing else is masked.** A carried cell holding an all-digit run
   (`20261110`), an all-letter hex word (`deadbeef`) and the `--dispatcher` name
   prints unchanged.
8. **No hash in any row, on every success.** The existing check at line 51 (a
   grep for a 7-40 character hex token) becomes a helper that also requires a
   digit and a letter in the token, and runs on the table rows (stdout lines
   starting with `|`) of every case that exits 0, including cases 1-4 and 7. Like
   the script, the helper skips the `--dispatcher` name the case passes.

## Implementation Approach

One step and one pull request, so no PLAN is needed:

- Split the hash helpers, add `masked` and the typed-text check in
  `progress-view.sh`, mask in `row()`, and update the header comment.
- Add or change the test cases above in `progress-view_test.sh`.
- Reword the one SKILL.md sentence about what the script refuses.

The build closes shirabe#1575.

## Security Considerations

The change reads only the pick facts and the flags the script already reads,
writes only stdout and stderr, and adds no dependency, file or network access.
The new `gsub` uses the existing bounded hash pattern, which can't match empty
text and runs on short cells. A commit hash isn't a secret: the rule is about
display, and the record keeps every hash. The table now prints carried text it
used to refuse, with each hash in it replaced, so a run that was blocked gets
its table.

Carried text, some of it from workers' entries, prints as before except that
hash-shaped tokens become `(commit)`. Before, such a cell blocked the table, and
the coordinator wrote one by hand that skipped the script's link, session and
merge-order checks. The dispatcher cut applies only where the name stands as a
whole word, so hex glued onto the name can't slip past the scan. The `Paused:`
line stays unscanned, as it is today.

## Consequences

### Positive

- A run whose record carries a hash gets its progress table from the script
  again, with the merge-order, blocker, link and session checks still applied,
  instead of a hand-written table that skips them.
- The no-hash rule holds by construction for carried text: `masked` and `hashy`
  share their pattern and test, so a printed cell can't hold a flagged token.
- Text the coordinator types for a report is still refused, so its own wording
  stays hash-free.
- The record and pick are untouched, and heads stay where the coordinate guidance
  keeps them.

### Negative

- There are two behaviours where there was one: a reader of the script has to
  know which text is refused and which is masked.
- A carried token that's hex-shaped but isn't a commit (a short build id, say) is
  shown as `(commit)`. The current script refuses the same token, so nothing that
  rendered before renders worse.
- The `Paused:` line above the table isn't scanned or masked today, and this
  design doesn't change that.
- The whole-word dispatcher cut changes `hashy` for one shape: hex that runs on
  from the dispatcher name, such as `lead-1a2bc3d4e5` under `--dispatcher
  lead-1a2b`, is now flagged (masked in carried text, refused in typed text)
  where today it prints.
- A `--next` entry whose key names no row is now checked too, so a hash in it is
  refused where before it was silently unused.

### Mitigations

- The header comment and the SKILL.md sentence each state the split in one line,
  and the test names say "refused" or "masked" per source.
- The over-masking matches the existing over-refusal exactly, because the two
  share one test.
- The `Paused:` line is left to a separate follow-up: pause owners can be instance
  names whose suffix looks like hex, so it needs its own call on what to exempt.
