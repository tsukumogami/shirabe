---
schema: design/v1
status: Proposed
problem: |
  `state-stored-set.sh --intake` writes every sentence of a hand-written
  successor brief outside the renderer's six excluded sections as an
  inferred rule row, and the record keeps at most 60 of those. Most of a
  handover brief is holdings and one-time takeover steps, so a brief of more
  than about 60 such lines caps, writes no `briefs` row, and leaves
  `brief-unread` open. The remedy the gap names doesn't converge either: an
  ended row stops holding its sentence, so re-running the same brief takes
  the ended sentences again and caps again.
decision: |
  Two changes. A brief that carries a line exactly `## Standing rules` is
  read in opt-in mode, where only sentences under that heading and the
  renderer's three rule sections are candidates; a brief without it is read
  exactly as today. And a capped intake records how far it read the digest
  in a new per-label Run row, `briefs-read` (`<label> sha256:<hex> <c>/<n>`),
  so a re-run of the same digest starts after the lines it already took and
  ending rows converges. The gap's fix text names a rewrite under
  `## Standing rules` first and ending or confirming rows second. The caps,
  `--end` and every row already standing stay as they are.
rationale: |
  No read that ignores meaning can tell a holdings line from a rule in an
  unstructured brief, so the author has to mark the rules, and an opt-in
  heading asks them to mark only the few lines that are rules, fails loudly
  when misspelt, and changes nothing for briefs written today. The progress
  marker fixes the loop where it lives, a capped digest re-read from its
  first line, without reading the record's entries, overriding a rewritten
  brief, or adding tombstones every Standing reader would have to skip.
---

# DESIGN: Coordinator brief intake under the inferred-row cap

## Status

Proposed

## Context and Problem Statement

A coordinator run that starts from a brief records the brief's standing rules
through `skills/coordinate/scripts/state-stored-set.sh --intake LABEL`. The
handover check in `state-handover.sh` keeps the gap `brief-unread LABEL` open
until the intake has written a Run `briefs` row carrying the brief's digest.

The intake's candidates come from `brief_candidates` in `state-schema.jq`:
every sentence of the brief less heading lines and less every sentence under
six of the renderer's sections (Goal, Checkpoints, Read first, Acceptance
criteria, Reporting, Keep-alive). Each candidate that no Standing row already
holds is written as a rule row with Source `inferred brief LABEL <digest>`.
The record keeps at most 120 rule rows, at most 60 of them inferred. When a
cap stops the intake, it writes the rows up to the cap, writes no `briefs`
row and exits 1, so the gap stays open "for a person to say which rows to
confirm or end" (`state-stored-set.sh`, the `--intake` comment and body).

The section filter was chosen for briefs the coordinate skill renders
(`docs/designs/DESIGN-coordinator-standing-rule-provenance.md`, Decision 10).
On those, it keeps 7, 11 and 11 sentences of the golden briefs. A brief
written by hand to hand a run over to a successor uses none of those
headings, so intake takes it whole less its headings. Most of what such a
brief says is not a standing rule: it names what the outgoing session holds,
the one-time steps of the takeover and where the work stands. Intake can't
tell those lines from rules, so a successor brief longer than about 60
intakeable lines can't clear `brief-unread` (tsukumogami/shirabe#1634).

Ending rows doesn't get the gate to converge either. `--end` deletes the row
outright, and `brief_intake_plan` treats a candidate as taken only while some
Standing row's What matches it. Once the ended rows are gone, the next
`--intake` of the same brief finds their sentences untaken and writes them
again. Measured on a live run (the issue's comment): with 51 of 60 inferred
rows ended, one re-run of `--intake` wrote 50 new rows from the same brief,
including sentences already taken and ended once, stopped at the cap again,
and the handover check still listed `brief-unread` naming 35 lines it
couldn't take. The remedy the gap names, "ask a person which rule rows to
confirm or end, then run it again", can't converge by ending, and confirming
one-time lines as standing rules writes false rules into the record.

## Decision Drivers

- A successor brief of about 90 lines, mostly holdings or one-time takeover
  steps, passes the handover check with no row ended by hand: `--intake`
  exits 0, the `briefs` row is written and `brief-unread` is no longer
  listed (the issue's acceptance test).
- A brief that really carries more standing rules than the caps allow still
  stops at the cap and says so. The caps stay where they are: raising them
  was rejected under the provenance design's Decision 10, and the template
  text that motivated it grows with the skill.
- The golden briefs the renderer produces keep their 7, 11 and 11
  candidates, and an intake of them on an empty record still writes exactly
  those rows.
- The intake never edits the brief, reads it once and never prints its path.
- Whatever a person does to clear a capped intake has to converge: once a
  row has been dealt with, a re-run of the same brief doesn't bring it back.
- The intake stays a mechanical read of the brief and the record. It doesn't
  judge a sentence's meaning.
- The change fits the writer's existing costs: shirabe#1283 moved the next
  Standing id off a full read of the record's entries, so a step that needs
  that read again carries a cost the writer has already chosen to avoid.
- Rows already standing in a record are neither re-sourced nor ended by the
  change itself.

## Considered Options

### Decision 1: Which brief sentences the intake takes as rule candidates

On a rendered brief, `brief_candidates` leaves only the lines under
`## Decisions already made`, `## Out of scope` and `## Workspace rules`. A
successor brief written by hand uses none of the renderer's headings, so the
intake takes it whole, and most of it isn't a rule. No read that ignores
meaning can tell a holdings line or a one-time step from a rule in a brief
with no structure, and the intake mustn't judge meaning. So any fix that
passes the acceptance test depends on the brief's author marking which lines
are rules. What's left to choose is which structure the guidance asks for,
how a brief without it is read, and what the gate tells a coordinator whose
intake capped.

Key assumptions:

- The acceptance test may be met by a successor brief written to new
  guidance. The issue asks for a 90-line successor brief of mostly holdings
  and one-time steps, not a brief in today's ad-hoc layout. If it has to pass
  a brief written today with its own headings, no meaning-free filter meets
  it while still stopping a headingless brief that carries more real rules
  than the caps allow.
- A successor's record holds its predecessor's Standing rows, by takeover or
  by carry, and a Standing row of any kind or Source holds a matching
  candidate. A rule restated word for word costs no room.
- No brief written today has a line that is exactly `## Standing rules`. The
  renderer never emits it, and no fixture, golden brief or doc in the
  repository uses it.

#### Chosen: An opt-in rule heading, with today's filter as the fallback

`brief_candidates` gains one mode switch, read from the brief's own heading
lines.

- **Opt-in mode.** When any line of the brief is exactly `## Standing rules`,
  matched whole after `file_sentences` trims it, a sentence is a candidate
  only if its section is `## Standing rules`, `## Decisions already made`,
  `## Out of scope` or `## Workspace rules`. A section runs from a `#` or
  `##` heading to the next one, as today, so `###` subsections inside
  `## Standing rules` still count. Text above the first `##`, every other
  section and the renderer's six excluded sections yield nothing. A heading
  inside a fenced block never switches the mode, because `file_sentences`
  drops fenced text. An empty `## Standing rules` section still switches it.
- **Fallback.** A brief without that line, whether rendered, hand-written,
  structured or headingless, is read exactly as today. When it carries more
  lines than the room, it stops at the cap and names how many it couldn't
  take.
- **Unchanged.** De-duplication under `norm_text`, the caps, the single read
  of the brief, never editing it or printing its path, and
  `next_standing_id`. The rule that a new digest ends rows the brief no
  longer states is tested against the same candidate set as now.
  `state-handover.sh` calls `brief_candidates` too, so the gate and the
  intake stay in agreement.

The coordinate skill tells a successor brief's author, in SKILL.md's
brief-intake paragraph with pointers from the Roles bullet, `state-keys.md`
and `brief-template.md`:

- A successor brief written by hand always carries a `## Standing rules`
  heading, spelled exactly so, even when nothing new goes under it.
- Every rule the successor must keep standing goes under it, one to a
  sentence or bullet. Decisions, out-of-scope lines and workspace rules may
  sit under the renderer's own headings instead, which count too.
- A warning that holds for the rest of the run is a rule. A warning about
  how things stand now isn't.
- A rule the record already holds is restated in its exact words. It costs
  no room.
- Holdings, takeover steps, positions and history go anywhere else, under any
  headings or none.

The renderer never writes the heading itself, so a successor brief rendered
through `dispatch-worker.sh` is read by today's filter unless one of its
free-text fields carries the line; Security Considerations covers that
case. For the rendered path the guidance is the
renderer's field mapping: holdings and where the work stands in `goal`, under
`###` subsections with no `#` or `##` line; the takeover steps in
`checkpoints`; rules in `decisions` or `standing_rules`.

This is the only option that meets every driver without interpretation. A
90-line successor brief with its rules under the heading yields only those
rules; the carried record already holds the predecessor's, so only rules new
with this handover are written, and the intake exits 0. Sixty-one rules under
the heading still write 60 and exit 1, and a headingless brief stops as it
does today. The caps don't move. The golden briefs carry no such heading, so
they keep 7, 11 and 11, and the assertions at `state-schema_test.sh:397-399`
hold. The read stays mechanical, needs no read of the record's entries, and
switches no brief written today into the new mode, so no standing row is
re-sourced or ended by the change.

It also fails in the safer direction. A misspelt heading falls back to
today's read, which on a long brief stops loudly. Its quiet failure is a new
rule placed outside the four counted sections, which isn't captured; that
loss is bounded, since the rule is still in the brief the successor reads and
carried rows are untouched.

#### Alternatives Considered

- **A denylist of handover headings** (add `## Holdings`, `## Takeover steps`
  and `## Where the work stands` to the excluded sections). Rejected: the
  author has to file every non-rule line, which is most of a successor brief,
  under three exact names, with nothing above the first `##`. Any heading
  named otherwise brings the issue back, and below the cap a misfile writes
  one-time lines as inferred rules without a word. In a worked example, one
  `## Holdings` written where `### Holdings` belonged turned every holdings
  sentence after it into a candidate. With a label per successor those rows
  never end on their own, and they build back toward the cap.
- **An allowlist of the renderer's rule sections, with a whole-brief
  fallback** (any of `## Decisions already made`, `## Out of scope` or
  `## Workspace rules` present means only those count). Rejected: it changes
  what some briefs written today yield. A hand-written brief with
  `## Out of scope` that states rules elsewhere loses them, and at a new
  digest under the same label their rows end. It breaks the assertions at
  `state-schema_test.sh:397-399` and the provenance design's reading of
  hand-written briefs. Its vocabulary survives inside the chosen opt-in mode;
  only the trigger differs.
- **No code change, with guidance to file holdings under `## Goal` and
  takeover steps under `## Checkpoints`.** Rejected as the lasting answer,
  though it works with today's code. It stretches headings the renderer
  defines as one or two sentences and as report-and-continue points, and one
  stray `#` or `##` among the holdings over-captures quietly below the cap.
  Its field mapping survives as the guidance for rendered successor briefs.
- **An allowlist with an empty fallback.** Rejected: a headingless brief with
  more real rules than the caps would no longer stop, and the provenance
  design's capture of rules that only a brief states would be lost.
- **Matching candidates against carried Holdings, Work or Run rows.**
  Rejected: under `norm_match` a prose holdings sentence never equals a
  structured cell, and one-time steps name no row. A looser match would be a
  second normalization.
- **Raising the caps.** Rejected under the provenance design's Decision 10
  and excluded by the drivers.

### Decision 2: Whether an ended row's sentence stays taken, and where that's kept

A digest whose intake completed already keeps ended sentences out: once the
Run `briefs` row reads `LABEL D`, the intake exits 0 before computing any
candidates, so ending one of D's rows never brings it back. The loop the issue's comment
measured lives only on a digest whose intake capped. A capped intake
remembers nothing of how far it got, so the next run starts at the first
candidate and takes every sentence no row holds, the ones a person just ended
included.

Key assumptions:

- A completed digest is never re-read. If some other path re-reads one (a
  `briefs` row removed by hand, a record re-seeded without its Run rows),
  ended sentences come back there as they do today.
- `brief_candidates` gives the same list, in the same order, for the same
  bytes. If a plugin upgrade changes the filter between a capped run and its
  re-run, the list's length changes and the marker below is ignored, so the
  worst case is today's behaviour for that one digest, not a skipped rule.
- A sentence a later brief states again, whether a new digest of the same
  label or a successor's brief under another label, is that brief's author
  restating it. The brief decides whether it's taken, not an earlier
  person's end.
- The writer has no Standing confirm mode yet: the provenance design's
  `--confirm` isn't among `state-stored-set.sh`'s flags, so today ending is
  the only act that makes room. The fix text still says "confirm", because
  `rule_cap_problem` and the provenance design both name it.
- The handover gap counts lines without the intake's forge checks, so the two
  counts can differ by the lines those checks leave out. Both start from the
  same position in the candidate list, and both count only the lines from
  that position on.
- The marker travels with the rows it went past. The rotation carry copies
  the Run and Standing sections together (`state-open.sh`, the carry's seed),
  and a takeover carries the record's keys whole. If some path ever copied
  Run rows without Standing rows, a successor would skip lines whose rows it
  doesn't hold, so that pairing is pinned by a test.

#### Chosen: A capped intake records how far it read the digest

A sentence of brief LABEL at digest D stays taken once an intake of D has
gone past it, whether its row was then kept, confirmed or ended. That's the
rule a completed digest already follows; the change gives a capped digest
the same memory. A new digest of LABEL, or another label's brief, reads
whole, as today.

- A new Run key, `briefs-read`, holds one row per label:
  `<label> sha256:<64 hex> <c>/<n>`. Here n is how many candidates
  `brief_candidates` gave for that digest, and c is the 0-based index of the
  first one the intake couldn't take; every candidate before it was written,
  already held by a row, or left out by the checks. Its grammar is checked as
  the `briefs` row's is, plus the `<c>/<n>` suffix with `0 < c < n`, once per
  label.
- A capped intake that writes anything, rows or ends, and whose c is above 0
  writes or replaces LABEL's `briefs-read` row in the same state write, with
  a run entry. When c is 0 (an intake that only ended rows before taking its
  first candidate), a marker would say nothing a fresh start doesn't, so none
  is written. A capped intake that writes nothing leaves the row as it is.
- An intake of D that finds LABEL's `briefs-read` row for D with a matching
  n starts its writes at candidate c. `brief_intake_plan` gains a start
  position: it takes its writes from candidate c onward and still tests the
  ends against the whole list, so a row of an earlier digest that D states
  anywhere stays put. A row for another digest, or with a different n, is
  ignored, and the intake starts at 0.
- The intake that completes writes the `briefs` row and removes LABEL's
  `briefs-read` row in the same write.
- `state-handover.sh` passes the same start position when it computes the
  gap, so the count it names is the lines after the marker.
- Only the intake writes `briefs-read`. `--run` doesn't take the key, since
  the writer's generic Run branch would replace it whole rather than per
  label.

The capped suffix of the `brief-unread` fix text in `state-handover.sh`
becomes, for label L and count N:

> state-stored-set.sh --intake L --by \<you\>; N of its lines can't be taken
> under the caps (60 inferred rule rows, 120 rule rows): when they aren't
> standing rules, have the brief rewritten with its rules under ## Standing
> rules and record it under the same label (state-stored-set.sh --host
> briefs:L \<absolute path\>); otherwise ask a person which rule rows to
> confirm or end; then run it again, and it goes on after the lines it
> already took

Each re-run of a capped digest starts after the last line it took, so it
takes only lines no run has gone through. Rows a person ended or confirmed
stay as they are, and the number of rounds is bounded by the brief's length.
The marker fixes the loop where it is and nothing wider: nothing changes for
a new digest or another label. It costs one Run row per label being read,
read with the record the intake and the handover check already load, and no
read of the entries. The golden briefs never cap on an empty record, so they
never write a marker.

#### Alternatives Considered

- **Derive the ended sentences from the record's entries**, pairing each end
  entry with the rule entry for the same id whose Source reads
  `inferred brief LABEL <d>`. Rejected: it puts back the full read of the
  entries that shirabe#1283 removed, on every intake and every handover
  check. The end entry carries no Source, so the join needs a second entry.
  The intake's own ends look like a person's, and `state-open.sh --carry`
  copies no entries, so the set empties in a successor's record.
- **`--end` writes a per-label ended marker**, a Run row per ended sentence
  or a list in `record/meta`. Rejected: it keeps a sentence out of every later
  digest of the label, overriding a rewritten brief that still states it. It
  writes one row per ended row, with no way back for a sentence ended by
  mistake. In `record/meta` it doesn't survive a restart carry, and it
  doesn't reach a successor brief under another label, where scoping it
  globally would override that brief's author.
- **Keep ended rows in Standing as tombstones** that hold their sentence and
  count against neither cap. Rejected: every reader of Standing (the caps,
  the rule lists, `--rules`, the handover's carry acknowledgement, the
  provenance checks) would have to skip them, the record grows without bound,
  and "ended" would stop meaning gone.
- **No persistence, relying on Decision 1's rewrite route.** Rejected: the
  intake's own stderr still tells a person to end rows, ending still loops on
  a capped digest, and a brief whose author can't rewrite it at once is left
  with no route that converges.

### Decision 3: Whether the renderer refuses heading lines in free-text fields

A rendered brief is read by today's filter, which relies on every `#` or
`##` line being the renderer's own. A free-text field such as `goal` or
`checkpoints` that carries a `##` line of its own starts a new section, and
the sentences after it become candidates. `render-brief.sh` could refuse such
a field, naming it.

#### Chosen: Leave `render-brief.sh` unchanged here

The issue is about successor briefs written by hand, and the rendered path
already holds its 7, 11 and 11 golden counts. A refusal changes the
renderer's contract for every brief it renders, not only successor briefs,
so it belongs in a change of its own. It's named as a follow-up under
Consequences.

#### Alternatives Considered

- **Refuse a free-text field holding a line that matches `^\s*#{1,2}( |$)`,
  as a fourth implementation phase.** Rejected for this design: it would
  close the quiet over-capture when a rendered field carries a stray heading,
  but it widens the change to every rendered brief for a case the issue
  doesn't raise.

### Decision 4: How `brief_intake_plan` takes the start position

The marker needs the plan to start its writes at a given candidate. The plan
has two callers, `state-stored-set.sh` and `state-handover.sh`, plus the
`plan()` helper in `state-schema_test.sh`.

#### Chosen: One function with a fourth `$start` parameter

`brief_intake_plan($label; $digest; $cands; $start)` replaces the
three-argument form. Every call site and the test helper pass the start, 0
where no marker applies, so each caller states where its plan begins.

#### Alternatives Considered

- **A new `brief_intake_plan_from(...; $start)`, with the three-argument
  form delegating at 0.** Rejected: it leaves the old callers and tests
  untouched, but keeps two names for one plan, and a caller that should read
  the marker can silently use the form that doesn't.

### Decision 5: Whether removing the marker gets its own entry

When the intake of a capped digest completes, LABEL's `briefs-read` row goes
in the same write that adds the `briefs` row. The question is whether that
removal is told in the entries.

#### Chosen: No separate entry

The completing intake's run entry, `Run briefs LABEL D set by WHO.`, stands
for both. The `briefs` row supersedes the marker, and nothing reads a
removal entry.

#### Alternatives Considered

- **A second run entry, `Run briefs-read LABEL removed by WHO.`** Rejected:
  it records an act that follows from the `briefs` row already told, and
  adds an entry per completed capped brief that no reader uses.

## Decision Outcome

The two decisions close the two halves of the issue. Decision 1 keeps a
successor brief's one-time lines out of the intake in the first place: an
author who puts the rules under `## Standing rules` gets an intake that reads
only the rule sections, so a 90-line handover brief takes a handful of new
rules and clears `brief-unread` in one run. Decision 2 makes the cleanup
converge when a brief does cap, whether it was written without the heading or
really carries more rules than the caps allow: a capped intake records how
far it got, and the re-run goes on from there rather than taking back what a
person just ended.

They meet in the gap's fix text, which names the routes in the order that
clears a cap fastest. A rewrite under `## Standing rules`, recorded under the
same label, clears a brief of one-time lines in one intake: the new digest
reads whole, ends the earlier digest's rows it no longer states and takes
only the rules. Ending or confirming rows comes second and converges a cap's
worth at a time. The marker belongs to one digest, so the rewrite route is
untouched by it: a new digest ignores an old marker, and the intake that
completes removes it.

Each decision also removes a risk the other would carry alone. Without the
marker, the intake's own stderr ("confirm or end one first") would still walk
a person into the loop on any brief without the heading. A per-sentence
ended set would have kept a rewritten brief's restated rule from getting a
row, which Decision 1 flagged; because the marker is keyed to a digest rather
than to sentences, that interaction doesn't arise. Neither decision moves
the caps, reads the record's entries, or ends or re-sources a row already
standing, and briefs written today read exactly as before.

## Solution Architecture

### Overview

The intake keeps its shape: read the brief once, compute its candidates,
plan the ends and writes against the Standing rows, take what the caps
allow, and write rows, ends, entries and Run rows in one state write. Two
things change inside it. The candidate list depends on whether the brief
opts in with `## Standing rules`, and a capped intake leaves a per-label
marker that the next intake of the same digest starts from. The handover
check reads the same candidates and the same marker, so the gap it lists and
the intake it names agree.

### Components

All the code lives in `skills/coordinate/scripts/`.

- **`state-schema.jq`**
  - `brief_rule_sections`, new: `["## Standing rules", "## Decisions already
    made", "## Out of scope", "## Workspace rules"]`.
  - `brief_candidates`: before the section walk, it checks whether any
    sentence `file_sentences` yields is exactly `## Standing rules`. If one
    is, the walk keeps only sentences whose current section is in
    `brief_rule_sections`, and nothing before the first `#` or `##` heading.
    If none is, the walk runs as today against `brief_excluded_sections`.
    De-duplication under `norm_text` follows in both modes. The comment
    above it states both modes.
  - `run_keys` gains `briefs-read`, with a value check (`<label>
    sha256:<64 hex> <c>/<n>`, integers with `0 < c < n`) and the
    once-per-label check `briefs` already has.
  - `brief_intake_plan($label; $digest; $cands)` becomes
    `brief_intake_plan($label; $digest; $cands; $start)` (Decision 4). The
    ends are still tested against all of `$cands`. The writes come from
    `$cands[$start:]`, and each write carries its index in `$cands`, so the
    caller can name the first index it couldn't take. A caller that passes 0
    gets today's plan.
- **`state-stored-set.sh --intake`**
  - After the digest check, it reads LABEL's `briefs-read` row. When the row
    names the same digest and its n equals the candidate count, the start is
    c; otherwise it's 0.
  - On a capped write that takes or ends anything, it writes or replaces
    LABEL's `briefs-read` row with c, the 0-based index of the first
    candidate kept but not taken, plus the run entry
    `Run briefs-read LABEL D c/n set by WHO.` When c is 0 it writes no marker.
  - On a completed write, it adds the `briefs` row as today and drops
    LABEL's `briefs-read` row in the same write, with no entry of its own
    (Decision 5).
  - When the brief is in opt-in mode, the intake says on stderr how many of
    the brief's sentences sit outside the rule sections and weren't read as
    rules, without the path, and goes on as before. An empty heading, or
    rules filed under the wrong section, shows up as a count rather than
    passing unseen.
  - The `--intake` header comment describes the marker and the opt-in
    heading. `--run` doesn't take `briefs-read`.
- **`state-handover.sh`**
  - The `brief-unread` gap reads LABEL's `briefs-read` row the same way and
    passes the start to `brief_intake_plan`.
  - Its capped suffix (`state-handover.sh:315`) becomes the fix text in
    Decision 2.
- **`render-brief.sh`** is unchanged (Decision 3). It never writes the
  opt-in heading itself, though a free-text field can still carry one.

### Key Interfaces

- **The opt-in heading.** A line that is exactly `## Standing rules` after
  trimming, outside a fenced block. It's a contract between a brief's author
  and the intake. `## Standing Rules`, `## Standing rules (kept)` and
  `### Standing rules` don't switch the mode. `file_sentences` trims
  whitespace at both ends of a line, so a CRLF line ending still matches,
  while a non-breaking space inside the heading doesn't, and the brief falls
  back to today's filter.
- **The Run `briefs-read` row.** Key `briefs-read`, value `<label>
  sha256:<64 hex> <c>/<n>`, at most one per label, written and removed only
  by `--intake`. Like every Run row, the rotation carry, the restart carry
  and a takeover copy it whole, together with the Standing rows it went past,
  so a successor that inherits a capped digest under the same label
  continues it.
- **The gap's fix text.** The capped form is the Decision 2 text; the
  uncapped form stays `state-stored-set.sh --intake L --by <you>`.
- **Exit codes and stderr of `--intake`** are unchanged: 0 when the brief is
  taken or was already taken, 1 when a cap stops it, with the same
  `took T of the brief's lines; N of its lines can't be taken under the caps`
  message. `rule_cap_problem` keeps "confirm or end one first", which
  `--standing` shares.

### Data Flow

1. `--intake L` reads `record/host`'s `briefs:L`, copies the brief once and
   takes its digest D. A Run `briefs` row `L D` exits 0.
2. `brief_candidates` gives the list for D, in one mode or the other.
3. A `briefs-read` row `L D c/n` with n matching the list's length sets the
   start to c. Otherwise the start is 0.
4. `brief_intake_plan` gives the ends (tested against the whole list), the
   writes from the start onward with their indices, and the room.
5. `intake_checks` filters the writes. The caps take the first `room` of
   what's kept.
6. One state write follows. On completion it holds the new rows, the ends,
   the `briefs` row, and no `briefs-read` row for L. On a cap that took or
   ended anything, it holds the new rows, the ends and, when c is above 0,
   `briefs-read` `L D c/n`.
   A cap that took and ended nothing writes nothing.
7. Entries follow, in order: one rule entry per new row, one end entry per
   ended row, then the run entry for `briefs` or for `briefs-read`.
8. `state-handover.sh` runs steps 2 to 4 over the same record for its count,
   and lists `brief-unread L` until step 6 has written `briefs` `L D`.

## Implementation Approach

### Phase 1: The opt-in candidate filter

This comes first because it alone meets the acceptance test, and it's
independent of the marker.

Deliverables:
- `state-schema.jq`: `brief_rule_sections`, the mode switch in
  `brief_candidates`, the comment.
- `state-schema_test.sh` cases:
  - only the four sections count;
  - preamble and other sections are dropped;
  - `###` stays inside its section;
  - `## Standing Rules` and `## Standing rules (kept)` fall back;
  - a fenced heading doesn't switch the mode;
  - the heading with a CRLF line ending switches it, and one with a
    non-breaking space falls back;
  - an empty `## Standing rules` yields `[]`;
  - a brief with `## Out of scope` and no opt-in heading reads as today;
  - the golden briefs keep 7, 11 and 11.
- `brief-intake_engine_test.sh`:
  - a 90-line successor fixture with its rules under the heading: exit 0,
    only new rules written, `briefs` row written, gap gone;
  - the same lines without the heading still cap;
  - 61 rules under the heading write 60 and exit 1;
  - an opt-in brief prints on stderr the count of sentences outside the
    rule sections, an empty `## Standing rules` section exits 0 with every
    sentence counted there, and the brief's path appears nowhere in that
    output.

### Phase 2: The capped-intake marker

This depends on nothing in Phase 1, but it lands after it so the gap's new
fix text, which names the heading, describes something that already exists.

Deliverables:
- `state-schema.jq`: `briefs-read` in `run_keys` with its checks, and the
  start parameter and write indices in `brief_intake_plan`.
- `state-stored-set.sh`: read, write and remove the marker in `--intake`;
  the header comment; `--run` keeps refusing the key.
- `state-handover.sh`: the start position in the gap's plan, and the new
  capped suffix.
- Tests:
  - `state-schema_test.sh`'s `plan()` helper and exact plan JSON take the
    start position;
  - the pinned gap strings at `brief-intake_engine_test.sh:258` and `:279`
    take the new suffix (both are prefix or full-text matches);
  - a 61-rule brief caps; ending one row and re-running writes the 61st,
    not the ended one, lands the `briefs` row and removes `briefs-read`;
  - a long headingless brief caps, most rows are ended, and one re-run takes
    only the lines after the marker;
  - a capped run that writes nothing leaves the marker as it was;
  - a capped run that only ends rows, with its first candidate untaken,
    writes no marker, and the next run starts at 0;
  - a marker for another digest, or with another n, is ignored;
  - a new digest under the same label reads whole, and its ends are tested
    against every candidate;
  - the handover count matches the intake's after the marker;
  - a carry keeps the marker together with the Standing rows it went past,
    and the successor's re-run continues it;
  - `--run briefs-read` is refused;
  - the brief's path appears in neither the capped stderr nor the
    `briefs-read` run entry;
  - a record capped by a headingless brief clears when a rewrite is recorded
    under the same label.

### Phase 3: Guidance and evals

This lands with or after Phase 2, since it quotes the new fix text.

Deliverables:
- `skills/coordinate/SKILL.md`: the brief-intake paragraph (the opt-in
  heading and what goes under it), the capped-intake sentence at
  `SKILL.md:610`, and the Roles bullet on briefing a successor.
- `skills/coordinate/references/state-keys.md`: the `briefs-read` key, and
  that ending rows on a capped intake now sticks.
- `skills/coordinate/references/brief-template.md`: a successor-brief note,
  with the render-path field mapping.
- `skills/coordinate/evals/evals.json`: the capped-intake scenario's
  expected remedy (around `evals.json:1331`) follows the new fix text, and a
  new scenario has a coordinator writing a successor brief by hand put its
  rules under `## Standing rules`.
- `docs/designs/DESIGN-coordinator-standing-rule-provenance.md`: Decision
  10's reading of hand-written briefs applies to a brief with no
  `## Standing rules` heading, and its `--end` paragraph notes that a capped
  digest's re-run goes on after the lines already taken. Both point here.

## Security Considerations

The change adds no input, network call, process, dependency or file
location. The intake still reads one local file, the brief `record/host`
names, copies it once and works from the copy. What changes is which of the
brief's sentences it takes as candidates, plus one new Run row. Nothing here
adds a package or a tool: the code stays in the plugin's shell and jq files.

**Untrusted brief text.** A brief is text from whoever wrote it, and its
author already decides what the intake captures. The `## Standing rules`
heading lets the author narrow that, never widen it. The caps don't change,
and every candidate in both modes still goes through `intake_checks`: the
400-byte limit on a rule row's What, the home-directory path and token
checks, and, on a public host, the visibility of any repository a line
names. The marker only moves the start of the writes past lines an earlier
run of the same digest already went through. A line that is written is
always checked.

**A heading carried in a rendered field.** `render-brief.sh` never writes
`## Standing rules`, but until the follow-up under Consequences lands, a
free-text field can carry that exact line and switch a rendered brief into
opt-in mode. That narrows what the brief yields to the rule sections and
whatever follows the carried heading; it can't add rows past the caps or
past `intake_checks`. A field can already carry `## Decisions already made`
or any other heading today, with the same reach, so this adds little, and
the renderer refusal closes both.

**Silent under-capture.** Someone who can edit the brief before the intake
can add the heading and put few rules, or none, under it. The intake then
completes and clears `brief-unread` without recording rules stated
elsewhere in the brief. That's the quiet loss named under Consequences, and
it's bounded. Carried rows aren't touched, the successor reads the whole
brief, and anyone who can edit the brief can already leave rules out of it.
An opt-in intake prints on stderr how many sentences sit outside the rule
sections, so an empty heading or a misfiled rule shows as a count.

**The `briefs-read` marker.** It holds a label, a sha256 digest and two
integers, with no brief text and no path. Only `--intake` writes it, and
`--run` refuses the key, since `--run` would replace the key whole. The
intake honours a marker only when its digest is the brief's current digest
and its candidate count is the current count, and the grammar requires
`0 < c < n`. So a stale or forged marker can only make the intake skip lines,
never write extra or different rows. Anyone who can forge a Run row can
already write a `briefs` row, which clears the gap outright, so the marker
adds no capability. The brief's path isn't printed in the new stderr text,
in the gap's fix text, where it stays a placeholder, or in the new run entry.
Two intakes running at once don't leave a stale marker: the state write is a
compare-and-swap on the record's written time (`state-write-core.sh`), so the
second write is refused as `record-changed` and has to re-read the record.

**Residual risk, unchanged by this design.** The intake follows symlinks and
accepts any absolute path in `briefs:LABEL`, so it reads any file the running
user can read. The content checks above limit what reaches a row. The
handover check reads the brief apart from the intake, so its count can
differ if the file changes in between. The intake's own read is the one
that decides, and a marker whose digest no longer matches is ignored.

**Residual risk this design adds.** The marker trusts that the Standing rows
it went past are in the record. Every carry and takeover today copies Run and
Standing together, so they are, and a test pins it. A future path that
copied Run rows without Standing would let a successor skip lines no row
holds, and the digest and count checks wouldn't notice, because the brief
hasn't changed. Any such path has to drop `briefs-read` with the rest.

## Consequences

### Positive

- A hand-written successor brief of any length clears `brief-unread` in one
  intake when its rules sit under `## Standing rules`, and nobody ends a
  row by hand.
- Clearing a capped intake converges whichever route a person takes: a
  rewrite clears it in one intake, and ending rows clears it a cap's worth at
  a time without the ended sentences coming back.
- The intake's stderr, the gap's fix text and the skill's guidance agree
  again on what a person does next.
- Briefs written today, rendered or by hand, read exactly as before, and no
  row already standing changes.
- No full read of the record's entries comes back. The marker is one Run row
  per label being read.

### Negative

- Two modes. Whether a sentence is a candidate depends on a heading
  elsewhere in the file, and readers of `brief_candidates` have to hold both
  modes in mind.
- Quiet loss. A new rule an author places outside the four counted sections
  of an opt-in brief isn't captured, and an empty heading takes nothing,
  though the intake prints a count of the sentences it didn't read as rules.
- Briefs without the heading that use the renderer's layout and add their
  own sections keep today's over-capture, and a long one still caps. That
  includes a rendered brief whose free-text field carries a `##` line of its
  own, since `render-brief.sh` doesn't refuse one.
- A record already stuck, like the issue's, doesn't clear from the change
  alone. A person has to record a rewritten brief under its label, or end
  rows and re-run.
- The Run section gets one more key for readers to know, and a sentence ended
  under one digest comes back when a new digest or a successor brief states
  it again.
- The fix text says "confirm", but the writer has no Standing confirm mode
  yet. Until one lands, ending is the only act that makes room.
- Which label a successor's brief uses is still open. Reusing one label
  retires the earlier brief's rows it no longer states, and a label per
  successor keeps them.

### Mitigations

- The comment above `brief_candidates` states both modes. The tests pin the
  near-miss spellings and the fenced heading, so the switch's edges are
  explicit.
- The guidance says every rule goes under the heading and that a warning
  holding for the rest of the run is a rule. The successor still reads the
  whole brief, and carried rows of every Source stay untouched, so a missed
  rule is still in front of the reader.
- Without the heading, the fallback stops loudly on a long brief, and the
  gap's fix text names the rewrite route first. A follow-up change has
  `render-brief.sh` refuse a free-text field holding a `#` or `##` line,
  naming the field, so every heading in a rendered brief is the renderer's
  own and today's filter reads rendered successor briefs exactly. It's kept
  out of this design because it changes the renderer's contract for every
  brief it renders.
- The fix text names both routes for a stuck record, and the marker makes
  the ending route converge. A record with no marker reads as today until
  its next capped run writes one.
- `state-keys.md` documents `briefs-read`, and only `--intake` writes it.
- A rule restated in its exact words costs no room, so carried rules cost
  nothing under either label policy. The guidance says so.
