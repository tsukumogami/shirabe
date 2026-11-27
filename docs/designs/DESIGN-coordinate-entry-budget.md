---
schema: design/v1
status: Draft
problem: |
  A coordinator dispatched under niwa's coordinator profile still starts at
  about 61K tokens of context, against a target below 35K. The profile took
  the harness down to about 28K. The rest is the coordinate skill's own
  SKILL.md, which a leading `/shirabe:coordinate` invocation expands in full
  into the first turn: 32.5K tokens, every word of it, whatever the
  coordinator is about to do. No harness item the profile still keeps is
  unused by coordinators, so the gap can only close in what the skill puts
  into turn 0.
---

# DESIGN: Coordinate entry budget

## Status

Draft

## Context and Problem Statement

niwa's coordinator dispatch profile (niwa's
`docs/designs/DESIGN-coordinator-dispatch-profile.md`, shipped in niwa
v0.44.0) trims what a dispatched coordinator starts with: it denies the tools
coordinators never call, leaves out the bundled skills and the account
connectors, and denies the Skill tool, so the skill listing goes too. Because
the Skill tool is denied, the coordinate skill reaches the session as a
leading slash invocation: since #2188, `dispatch-worker.sh` starts a
coordinator's prompt with `/shirabe:coordinate <args>` and passes
`--profile coordinator`.

The milestone this serves, a dispatched coordinator that starts without the
harness content it never uses, has one acceptance check that matters here: a
coordinator dispatched under the profile, its prompt led by that invocation,
reads below 35K tokens at turn 0, and still loads and uses SendMessage, the
Cron tools and TaskStop. Before the profile the figure was 59.2K. A session
dispatched without the profile, and a session the owner starts by hand, must
start as they do today.

The live check in #2188 read 60,907 tokens at turn 0 (input 2, cache
creation 60,905, cache read 0). Everything the profile drops was gone, and
the deferred tools loaded and worked. The figure didn't move because the
leading invocation now brings the whole of `skills/coordinate/SKILL.md` into
the first turn, and that file is 96,425 bytes.

Measured since, on Claude Code 2.1.332 and Opus, in print mode, with the
workspace's coordinator profile passed as `--settings` from a niwa instance
root, each run twice:

| Launch | Turn-0 tokens |
|--------|---------------|
| trivial prompt | 22,144 and 22,104 |
| same, prompt led by `/shirabe:coordinate <roadmap> --role manager` | 54,695 and 54,695 |

The skill's expansion is the difference: 32,551 tokens for 95,846 characters,
about 2.95 characters per token. The four-characters-per-token estimate in
#2188 (about 24K) was low.

The harness was then measured live. A coordinator dispatched with
`niwa dispatch --profile coordinator`, its prompt a one-line instruction to
reply and open nothing, read 27,401 tokens at turn 0 (input 2, cache creation
27,399). That's the `--bg` harness under the profile with no skill text, about
5.3K above print mode: the background-session and browser sections of the
system prompt, and the AskUserQuestion and ReadNotifications schemas, which
print mode leaves out.

One more print-mode run sized a small entry. A stand-in skill made of today's
frontmatter and the first 12,000 bytes of today's body, which hold the flag
table and the opener commands, was invoked the same way with the same
840-character prompt. It read 26,509, so the stand-in, its expansion wrapper
and the prompt lines together cost 4,365 tokens: about 2.75 bytes of entry per
token, all in.

The harness has no unused item left. Each remaining item was measured by
denying it on top of the profile, and the 1,705 coordinator transcripts on the
measuring host were read for calls to it:

| Item | Turn-0 tokens | Coordinator transcripts calling it |
|------|---------------|------------------------------------|
| Agent, with its subagent-type listing | 3,943 | 1,081 of 1,705, across every listed type |
| datadog MCP server | 1,958 | 79 |
| ScheduleWakeup | 1,734 | 6 |
| ListAgents | 665 | 1,128 |

None of these has the never-called evidence the profile's design requires for
a drop, so this design proposes no further harness trim. The arithmetic left
is short: 35,000 less 27,401 is about 7.6K tokens for the coordinate skill's
turn-0 text, its expansion wrapper and the dispatcher's prompt lines
together, against 32.5K today, and some of that has to stay unspent as
headroom.

The question is how the coordinate skill brings a dispatched start's turn 0
under that line, without moving the same text one turn later and calling it a
saving, and without changing what a coordinator knows when it acts.

## Decision Drivers

- **The target is turn 0, and the point is every turn.** A coordinator tenure
  runs for days and pays its context on every turn. A design that lowers turn
  0 by having the coordinator read the same text on turn 1 meets the letter
  and none of the purpose. Text a start doesn't need must stay out until the
  situation that needs it arises, and text for situations a tenure never meets
  must never load.
- **A coordinator acts on what it was shown.** The contract in SKILL.md holds
  rules a coordinator must follow at the moment a situation arises (a
  takeover, a verdict, a teardown, a bound). Each rule moved out of the entry
  has to reach the coordinator at that moment, through a channel that always
  fires, not through the coordinator remembering to look.
- **Headroom, not a squeak.** The harness grows as plugins and Claude Code
  releases add text. A budget that lands at 34.9K fails at the next release.
  The entry text needs a fixed ceiling with room under the line, and a check
  that fails when the file grows past it.
- **No harness change.** Every remaining harness item is in use. The profile,
  niwa and the workspace config stay as they are.
- **Every start reads the same skill.** A coordinator the owner starts by hand
  and one a dispatcher starts invoke the same `/shirabe:coordinate`, so a
  restructured entry reaches both. The profile's clauses about unprofiled and
  interactive sessions concern the harness, which this design doesn't touch;
  what the skill says has to stay correct for every kind of start.
- **The deferred tools keep working.** SendMessage, the Cron tools, TaskStop
  and background Bash load through ToolSearch today under the profile; nothing
  here may change that.

## Considered Options

### Decision 1: How the entry's turn-0 text comes down

Today's SKILL.md is the coordinator's whole contract, written as one file
that every start reads in full. A section-by-section read of it sorts its
96,425 bytes by when a coordinator needs them:

| When it's needed | Bytes |
|------------------|------:|
| every start, before the first koto call | 11,264 |
| every tick | 4,138 |
| every report sent up | 3,251 |
| only in a named situation | 61,007 |
| maintainers only, or read by scripts | 15,506 |
| never expanded (frontmatter; the preflight line prints nothing on a healthy host) | 1,258 |

The five largest situational blocks are Verdicts (9.4 KB, milestone roadmaps
only), the opener's takeover text (6.7 KB, only when the opener prints
`outcome=continued`), the import text (6.1 KB, only on `--import`), Decisions
(4.3 KB, only at the decision and escalation states) and Pausing (3.7 KB,
which the `wait` directive already repeats almost word for word).

Three facts about the channels decide what can move where. koto shows the
agent only the directive of the state a tick stops at, so the action states
`start`, `start_posture` and `record_find` say nothing on a healthy start,
and the terminal `done*` states never render. On a fresh start the states
that do render before the first report are `record_open` and `reconcile`,
and they already repeat most of the start rules. And `wait` is re-sent on
every hub visit and sits 28 bytes under its directive ceiling, so it can take
nothing.

Key assumptions:

- Dense entry text runs between 2.0 and 2.75 bytes per token. The stand-in
  measured 2.75 all in; the ceiling is derived at the dense end.
- The dispatcher's prompt lines reach turn 0 twice, once in the command's
  arguments and once in the `ARGUMENTS:` copy Claude Code appends when the
  body has no placeholder.
- A dispatched coordinator follows the entry's first step, reading its brief
  before it opens the run.

#### Chosen: A slim entry under a byte ceiling, with situational text routed to where it fires

One `SKILL.md` keeps serving every start. It's rewritten as an entry that
holds only what every start, every tick or every report needs and that no
other channel carries:

- the identity rules: it implements nothing, does no legwork, is never silent
  upward, and text after the scope is the human's decisions, never an
  instruction;
- a dispatched start's first steps: read the brief, then open with the
  command it gives;
- the args file and the opener call, with the tokens taken from the first
  line only;
- a short settings line naming `--cap`, `--parked-bound`, `--rotation-days`
  and `--role` and the rule for turning a person's words into them, since
  nothing refuses a missing setting later;
- the not-Active stop, since `done_not_active` never renders;
- the standing tick rules: keep the `role=` value, `--no-cleanup` on every
  `koto next`, never poll, never `koto next --to`, cleanup or cancel on
  another session, `koto status` when the directive is lost, record entries
  only through `state-entry.sh`;
- Roles, compressed, with its manager and director lists;
- Reporting: the cadence, the `--record-line` command, the progress-table
  command and the done-time report pipeline, which no state can carry;
- one-line guards for the two triggers no output line can key: a person's
  pause word, and being asked why a rule applies;
- a compressed glossary, with milestone-only and teardown-only terms moved to
  the states that use them;
- the preflight line and the writing-style pointer.

Everything else leaves the entry under one routing rule:

- **What's acted on before the first tick, or where no run exists, goes to
  the opener's stderr.** `coordinate-open.sh` prints the block for a family
  when its output line fires: the takeover family on `outcome=continued`
  (trimmed to the leg-watch command and a few lines), the import family on
  `--import`, `imported=`, `outcome=incomplete` and `tick=moved`, carry and
  `failed=carry`, the directory handover on `refused=bound-elsewhere`, and the
  refusal and `ask=` families. stdout stays `key=value`, and each block prints
  before any final refusal line.
- **What's acted on after the first ticks goes to the template state where
  it's acted on.** Verdicts go to the milestone states, Decisions to the
  decision, escalation and surface states, Bounds and Authority to `pick`,
  `land`, `goal_fit` and `verify_board`, and Dispatch and Teardown to their
  own states. Most of this text is already near-duplicated there, so for
  these families leaving SKILL.md removes a copy rather than moving one.
- **Nothing moves into `wait`, the silent action states or the `done*`
  states.**
- **Maintainer text leaves runtime entirely.** Known Limitations, What This
  Version Leaves for Later, Changing This Skill and the background prose move
  to a doc in the skill directory that nothing loads. The two runtime caveats
  in Known Limitations go into the `reconcile` and failure details. The
  Reference Files table moves to a sidecar that `rule-files.sh` reads.

One duty has no carrier today besides SKILL.md: recording a dispatched
start's brief path. The brief's opener command passes that path to the opener
and the opener writes the host row itself, so the duty stops depending on the
coordinator remembering it. A `brief-unrecorded` gap in `reconcile` backs it
up.

This is the only option that meets every driver at once. Nothing new reaches
the states every start stops at, so the saving isn't spent again on turn 1.
Each moved family fires when its situation arises, through the opener's
output before any state renders and through the template after that, and the
template re-sends a state's text on every arrival and through `koto status`.
It touches no harness, niwa, profile or workspace config, and one
`/shirabe:coordinate` still serves every start.

The director list stays in the entry although a manager never needs it. The
owner funnel applies to every message, messages arrive at `wait`, which has
no room, and koto has no role-conditional directive text. About 450 tokens of
manager context is the price of the director reading its rules where they
always fire.

#### Alternatives Considered

**A concision-only rewrite in place.** Keep every rule in SKILL.md and
tighten the prose. Measured concise rewrites that keep every rule cut 60 to
75 percent per section: the takeover text from 6,664 to 1,657 bytes, Verdicts
from 9,435 to 2,427, Pausing from 3,686 to 1,469. The whole file then lands
near 26 to 27 KB, about 39 to 40K at turn 0, still 4 to 5K over the line, and
every future rule adds to every start. Concision stays, as part of the chosen
option: the kept text is 18.7 KB before it's tightened.

**A separate small entry for dispatched starts,** a second skill the
dispatcher leads with while hand starts keep today's file. It breaks the
check's "led by `/shirabe:coordinate`" and the same-skill driver. Hand-started
tenures would keep paying 32.5K on every turn, the small entry would still
need nearly all of the chosen option's routing to stand alone, and no test
could check that the two contracts agree. Its bootstrap variant ("read
SKILL.md when you need a rule") is the turn-1 trap outright.

**The whole contract moved into the koto template.** The args file, the
opener call, reading the brief and `--no-cleanup` all come before any koto
output. The action and `done*` states never render, refusals open no run, and
a takeover's leg watch has to be armed before the first tick, when no state
can render. Standing rules put in `record_open` or `reconcile` would be paid
on turn 1 by every start, and `wait` has no room. The template does take
everything acted on after the first ticks, which is the chosen option's
second routing rule.

**An entry assembled at load time by a `!` script.** Nothing situational is
known when the skill expands: no takeover, refusal, import result or role.
Keying on the profile's environment marker breaks the same-skill driver,
because `dispatch-worker.sh` relaunches without the profile when niwa
refuses it. A `!` line that substitutes `$ARGUMENTS` puts the dispatcher's
free text unquoted into a shell, a failing `!` line aborts the skill load and
leaves no contract at all, and a script-built entry is invisible to the
rule-coverage check.

### Decision 2: How the budget is held

The check has to fail a pull request, and CI has no model to count tokens
with, so the measure is bytes over a measured ratio. What it measures has to
be what the slash command actually puts into turn 0.

Key assumptions:

- Print-mode token deltas carry over to `--bg`; only the harness differs,
  and it was measured live.
- The slim body tokenizes no denser than 2.4 bytes per token. The stand-in's
  body measured about 3.17 once a fixed 580 tokens for the wrapper and both
  copies of the prompt lines is taken off; each further 0.2 bytes per token
  of density costs about 350 tokens of headroom.
- The dispatcher's prompt stays near 840 characters, so both copies and the
  wrapper cost at most 940 tokens.

#### Chosen: A rendered byte ceiling of 8,400, ratcheted against the merge base

A new coordinate test, `skills/coordinate/scripts/entry-ceiling_test.sh`,
renders SKILL.md the way the expansion does and counts UTF-8 bytes:

- the frontmatter is dropped, since it never reaches turn 0;
- the preflight line counts as its healthy output, which is empty;
- `${CLAUDE_PLUGIN_ROOT}` is replaced by a fixed 62-character stand-in, about
  the length of a real cache path;
- any `@` include inside the skill's tree is counted in full, so moving text
  into an included file can't escape the count;
- any other `!` line, and any `$<digit>` or `$ARGUMENTS` in the body, is
  refused, because their size depends on a host or on the dispatcher's
  prompt and can't be measured ahead.

It compares that size with a row in `skills/coordinate/scripts/entry-ceiling.tsv`
read at the merge base, the way `directive-ceiling_engine_test.sh` already
holds the `wait` state, so a change can lower its own ceiling but not raise
it. The row starts at the size the slim entry lands at, not at the cap. A
fixed cap of 8,400 bytes bounds the row: the landing pull request has to come
in under it, and so does any later request to raise the row. `check-skill.tsv`
gains `walk` rows so a change to SKILL.md or a reference selects the test.
`directive-ceiling.tsv` gains rows for `record_open`, `reconcile` and `pick`
at their current rendered sizes, so text can't slide from the entry into the
states every start renders on its first ticks.

| Case | Turn 0 | Headroom under 35K |
|------|-------:|-------------------:|
| entry at the cap, expected (580 tokens fixed, body at 3.17 bytes per token) | 30,631 | 4,369 |
| entry at the cap, worst case (940 tokens fixed, body at 2.4 bytes per token) | 31,841 | 3,159 |
| entry at about 7.8 KB, expected | 30,442 | 4,558 |
| entry at about 7.8 KB, worst case | 31,591 | 3,409 |

Every case starts from the measured 27,401. The worst case keeps 1,500 tokens
for run-to-run swing as MCP servers connect, plus about 1,660 for harness
growth.

The check can't see the harness. A Claude Code or plugin release that adds
more than about 3K tokens to the harness crosses 35K with this test green,
and only a live read shows it. That read is the profile's acceptance check
in niwa's design, and the fix it calls for is a change that lowers the row.

#### Alternatives Considered

**A 12,000-byte cap.** It also fits on the measured figures, but it lets the
landing pull request come in 3.6 KB over the size the entry is designed to,
and in the worst case leaves about 160 tokens beyond the swing reserve. Since
the row starts at the landed size, the cap only governs the landing and any
raise, and both should hold the design's own target.

**A raw `wc -c` on SKILL.md.** It counts about 1,180 bytes of frontmatter that
never reach turn 0, and it misses `@`-included text, so it over-counts and can
be escaped.

**A token estimate in CI.** There's no offline tokenizer for Claude, and the
counting API needs a key and network access that CI lacks. Bytes over a
measured ratio is the same check with the divisor left visible.

**A ceiling plus a recorded live re-measure on every Claude Code upgrade.**
Nothing in shirabe fires on a Claude Code upgrade, the read needs a model,
the workspace's profile and a niwa instance, and harness growth isn't fixed
in SKILL.md anyway. The read stays where it lives now, as niwa's acceptance
check.

**A live check only.** It can't fail a pull request, so growth is found after
it has reached every coordinator.

### Decision 3: How the change lands

Resolved inline, from the architecture. The entry and the carriers its moved
text needs could land together or in steps.

#### Chosen: The new entry and every carrier in one pull request

A rule that leaves SKILL.md before its carrier lands lives nowhere for as long
as the gap lasts, and every coordinator started in that window runs without
it. One pull request means `rule-coverage.tsv` checks every row against the
tree that carries it, in the same CI run that checks the ceiling.

#### Alternatives Considered

**Carriers first, then the entry.** It leaves no rule uncarried, but for the
length of the gap every rule is carried twice, which raises turn 1 for every
start in the meantime and makes the coverage rows ambiguous about which copy
counts. The pull request is large either way; splitting it buys review
convenience at the cost of a state no coordinator should run in.

## Decision Outcome

The coordinate skill's SKILL.md becomes an entry of at most 8,400 bytes,
held there by a test, and the rest of today's contract moves to where each
part fires: the opener's stderr for what is acted on before the first tick,
the template state for what is acted on after, and a maintainer doc for what
no run reads. A coordinator dispatched under the profile then reads the
harness (27,401 measured), the entry, its wrapper and the prompt lines, about
30.4K to 31.8K tokens at turn 0, and pays that on every turn rather than 60.9K. Nothing
in niwa, the profile or the tool list changes, so SendMessage, the Cron
tools, TaskStop and background Bash load as they do now, and a session
dispatched without the profile or started by hand gets the same harness it
gets today. Both kinds of start read the same, smaller skill.

## Solution Architecture

### Overview

Today one file carries the coordinator's whole contract, and every start
reads all of it. After this change the contract is spread over four carriers,
and each rule sits in the one that fires when the rule applies:

| Carrier | Fires | Holds |
|---------|-------|-------|
| `skills/coordinate/SKILL.md` | once, at turn 0, for every start | the entry: identity rules, first steps, the opener call, settings, standing tick rules, Roles, Reporting, glossary |
| `coordinate-open.sh` stderr | when the opener prints the output line a family is keyed to | takeover, import, carry, directory handover, refusals and `ask=` |
| the template's state directives | each time a tick stops at that state, and again through `koto status` | verdicts, decisions and escalation, bounds and authority, dispatch, teardown, pausing |
| `skills/coordinate/MAINTAINING.md` | never, at runtime | known limitations, deferred work, how to change the skill, background |

### Components

**The entry, `skills/coordinate/SKILL.md`.** Rewritten, not cut down: the
sections that stay are tightened, and the ones that go leave whole. It keeps
its frontmatter, its preflight line and its `## Roles` and `## Reporting`
headings, since the template and the references point at those two by name.
It has no `$ARGUMENTS` or `$<digit>` placeholder, so the `ARGUMENTS:` copy of
the dispatcher's prompt stays.

**The opener's guidance blocks, `skills/coordinate/scripts/coordinate-open.sh`.**
A new function prints a family's block to stderr when the opener reaches the
output line that names the situation. The blocks are the takeover family
(`outcome=continued`, `outcome=refused`, `failed=takeover_unfinished`), the
import family (`--import`, `imported=`, `outcome=incomplete`, `tick=moved`),
carry (`carried=`, `failed=carry`), the directory handover
(`refused=bound-elsewhere`) and the refusal and `ask=` families, most of which
print their own text already. stdout stays `key=value`. Each block prints
before any final refusal line, so the tests that read the last
`coordinate-open:` line still find it. The block text lives in the
opener's existing wording table, `coordinate-open.wording.tsv`, so it's
reviewed as text rather than as shell strings.

**Brief recording.** The brief template's opener command gains the brief's
path, and the opener writes the `briefs:` host row itself. `reconcile` gains a
`brief-unrecorded` gap: a `reports-to` row sourced from a dispatcher with no
`briefs:` row.

**The template, `skills/coordinate/koto-templates/coordinate.md`.** The
verdict, decision, escalation, surface, `pick`, `land`, `goal_fit`,
`verify_board`, dispatch and teardown states take what SKILL.md held for them
and doesn't already appear there. `rotation_end` and `roadmap_close_step` each
take one line on the successor input's shape. `wait`, the action states and
the `done*` states take nothing. The template's compat record gets the new
digest.

**The maintainer doc, `skills/coordinate/MAINTAINING.md`.** Known
Limitations, What This Version Leaves for Later, Changing This Skill and the
record's background prose. Its two runtime caveats go to the `reconcile` and
failure details instead. Nothing in the skill reads or links it at runtime.

**The Reference Files sidecar.** `rule-files.sh` parses SKILL.md's Reference
Files table at every start. The table moves to
`skills/coordinate/references/reference-files.tsv`, which `rule-files.sh`
reads instead, and it lists every reference this change adds, so the run's
`rules` rows and the `--rules` answer still cover them.

**The checks.**

- `skills/coordinate/scripts/entry-ceiling_test.sh` and
  `entry-ceiling.tsv`, from Decision 2, with `walk` rows in
  `skills/coordinate/check-skill.tsv`.
- `directive-ceiling.tsv` rows for `record_open`, `reconcile` and `pick`.
- `scripts/testdata/rule-coverage.tsv`: the rows whose phrases leave
  SKILL.md, about 40 of 77, point at their new carrier. Each row already names
  a carrier file and, optionally, a template state, so a script, a reference
  or a state is a carrier with no change to `rule-coverage_test.sh`. Its check
  that the Roles lists hold three, five and six items stays as it is.
- `milestone-verdicts_test.sh` and `skill-states_test.sh` look for their
  strings and state names in the template instead of SKILL.md.
- `rule-files_test.sh` and `rule-files_engine_test.sh` read the sidecar.
- A new opener test runs each keyed output line and checks that its block
  printed, so no family can go missing across the opener's exit paths.

### Key Interfaces

- **The entry ceiling.** `entry-ceiling.tsv` holds one row, the ceiling in
  bytes, read at the merge base and in the tree. The test fails when the
  rendered entry is over the merge-base row, when the tree's row is over the
  merge base's, or when either is over 8,400.
- **The opener's output.** stdout is unchanged. stderr gains blocks keyed to
  the existing output lines. No caller parses stderr except the tests.
- **Pointers into SKILL.md.** The template and references keep pointing at
  `SKILL.md, Roles` and `SKILL.md, Reporting`, which stay. The other
  pointers, about 11 of them in `record_open`, `goal_fit`, `wait`,
  `rotation_end`, `loop.md`, `state-keys.md`, `brief-template.md` and
  `verification-checklist.md`, are rewritten to name the new carrier.

### Data Flow

A dispatched start:

1. `dispatch-worker.sh` launches `niwa dispatch --profile coordinator` with a
   prompt led by `/shirabe:coordinate <tokens>`. Unchanged.
2. Claude Code expands the entry into turn 0: harness, entry, wrapper and the
   prompt lines, about 30.4K to 31.8K tokens.
3. The coordinator reads its brief, writes the args file and runs the opener.
   The opener prints `key=value` lines on stdout and, for a takeover, import,
   carry or refusal, that family's block on stderr.
4. Each `koto next --no-cleanup` returns the directive of the state the tick
   stops at, which carries the rules for what that state does.
5. After a compaction, the template's text comes back on the next arrival or
   through `koto status`.

A hand start follows the same path from step 2, with the owner's harness.

## Implementation Approach

### Phase 1: A measured draft of the entry

Write the new SKILL.md in full and measure it before anything else moves:
its rendered size against 8,400 bytes, and one print-mode turn-0 run under
the workspace's coordinator profile, the way the Context section's figures
were taken. If it doesn't fit, the glossary is the next cut, never a rule
every start needs.

Deliverables:
- the draft entry, with its rendered size and print-mode figure in the pull
  request

### Phase 2: Carriers for the moved text

Move each family to its carrier: the opener's guidance blocks and wording
rows, the template states' text, the brief-path recording and the
`brief-unrecorded` gap, the maintainer doc, and the Reference Files sidecar.

Deliverables:
- `coordinate-open.sh`, `coordinate-open.wording.tsv`
- `koto-templates/coordinate.md` and its compat record
- `references/brief-template.md`, `scripts/render-brief.sh`
- `MAINTAINING.md`, `references/reference-files.tsv`, `scripts/rule-files.sh`

### Phase 3: Checks, then the switch

Land the entry ceiling test and its rows, the new directive-ceiling rows, the
opener block test, and the retargeted coverage, verdict, state and
rule-files tests. Then replace SKILL.md with the Phase 1 draft. The draft and
its carriers land in one pull request, so there's no commit where a rule
lives nowhere.

Deliverables:
- `scripts/entry-ceiling_test.sh`, `scripts/entry-ceiling.tsv`,
  `check-skill.tsv` rows
- `directive-ceiling.tsv` rows
- updated `rule-coverage.tsv` and the retargeted suites
- the new `SKILL.md`

### Phase 4: The live acceptance read

After a shirabe release carries the change and the host installs it,
dispatch one coordinator under the profile, its prompt led by
`/shirabe:coordinate`, with an instruction to open nothing, and read its
turn 0 from the transcript. It has to be below 35,000. In the same run,
SendMessage, CronCreate, CronList, CronDelete and TaskStop load through
ToolSearch and work, and a background command starts and stops. Then one
hand start and one takeover start each reach their first report correctly.

Deliverables:
- the figures, recorded on the pull request that closes the milestone's
  check

## Security Considerations

Not written yet: a later /design phase replaces this line.

## Consequences

### Positive

- A dispatched coordinator starts near 31K instead of 60.9K, and the saving
  is paid on every turn of its tenure, not only at turn 0. A hand-started
  coordinator gets the same saving.
- Each situational rule lives where it fires. The template re-sends a state's
  text on every arrival and through `koto status`, so a rule there comes back
  after a compaction, where a paragraph read once at turn 0 might not.
- The entry has a ceiling a test enforces, so a new standing rule has to
  displace something or come with a measured case for raising the row.
- About 15 KB of maintainer text stops being read by every run.

### Negative

- A one-time migration: about 40 coverage rows re-pointed, three suites
  retargeted, `rule-files.sh` reading a sidecar, about 11 pointers rewritten,
  and new ceiling rows.
- Writing a situational rule is more deliberate: its author has to put it in
  the opener path or the state where it's acted on, not append it to
  SKILL.md.
- Managers carry the director list, about 450 tokens, because koto can't show
  role-conditional text.
- The opener grows guidance blocks across many exit paths, and a family that
  stops printing would go unnoticed without its test.
- The ceiling can't see the harness. A Claude Code or plugin release that
  grows the harness by more than about 3K tokens crosses 35K with every
  shirabe check green.
- The `wait` state keeps its per-visit cost. Trimming it is a separate change.

### Mitigations

- The opener block test runs every keyed output line, so a missing block
  fails at the pull request.
- The `record_open`, `reconcile` and `pick` ceiling rows stop the entry's text
  from drifting back into the states every start renders early.
- The live acceptance read is rerun after a Claude Code upgrade, as niwa's
  guide already asks for the profile; when it shows harness growth, the fix is
  a change that lowers the entry row.
- Phase 1 measures the draft before anything moves, so a draft that doesn't
  fit is found before the migration starts.
