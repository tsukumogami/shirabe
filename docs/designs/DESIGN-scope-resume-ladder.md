---
schema: design/v1
status: Accepted
problem: |
  A resumed /scope session can't leave resume_route. Its ladder gate runs a
  probe that waits on seven koto lookups with koto's default 30 s and no
  budget of its own. On a slow or large undeclared bucket a never-opened
  name's lookup either outlasts the gate (koto v0.37.0) or refuses with exit 3
  session_lookup_failed (v0.37.1), which the probe reads as cannot-tell, so
  the session times out or stops at the probe on every visit.
decision: |
  The probe owns the bound: a 20 s deadline over every koto call, an early
  answer once the lookups a row needs are settled, and a new exit 3
  (unsettled) that holds the run with one finding line per lookup that ran
  long or refused, naming the next step. Both resume gates state timeout: 30
  as a backstop with a timed_out arm to done_error. Replies are read by exit
  code and code first; only the exact not-found reply is absent, and no exit 3
  is ever absent. An operator's per-invocation --local-topic, refused under
  --auto and in dispatched runs, lets the probe settle never-opened names
  from the host's list and one read of this directory's prefix; declaring the
  bucket's name index clears the stop for every topic. parent_state reads a
  no-host-copy refusal as "not a parent here", never as absent.
rationale: |
  Only a bound shirabe enforces holds on v0.37.0, where a lookup has no worst
  case, and a hold is the one channel that carries the probe's text to the
  agent. koto's exit-3 "holds none under this directory's prefix" text is
  what a timed-out listing of the bucket's prefixes produces, so reading it as
  absent would settle a live session as gone on a flaky network; the way
  through has to come from the operator or the bucket's owner. Everything
  ships in shirabe against released koto, and the koto asks only shorten a
  visit that is already bounded and explained.
user_visible_surface: true
---

# DESIGN: Scope resume ladder time bound

## Status

Accepted

## Context and Problem Statement

A resumed `/scope` session enters `resume_route`. koto first runs the state's default action, `record-scope-exit.sh --stage resume`, which makes eight serial `koto context` calls. Then koto runs the `ladder` command gate, `resume-probe.sh`. The probe starts seven lookups at once:

- two `koto context exists` checks on `scope-<topic>`, for `work/state.md` and `work/prior-run.md`;
- one `koto context exists` check on `explore-<topic>`, for `handoff/scope.md`;
- four `skill-session.sh has-work` checks, one on `<child>-<topic>` for each of plan, design, prd and brief.

It then waits on each with a plain `wait`. The gate sets no `timeout:` (`skills/scope/koto-templates/scope.md`, the `ladder` gate), so koto's default of 30 s applies.

A lookup on the resumed session's own name doesn't need a sweep, because koto has that session's copy. A lookup of a name that was never opened has to show that no other prefix holds it. On a bucket whose name index isn't declared, that means listing every workspace prefix.

How that lookup ends depends on the koto release:

- At koto v0.37.0 each listing ask is bounded at 10 s and tried three times, but nothing bounds the lookup as a whole. The issue reports one such miss, run by hand on koto 0.37.0, that took 88 s and exited 2, and a later fresh session whose child lookups each took about 86 s, so the gate timed out twice.
- koto v0.37.1 (koto#670) bounds a missing name's lookup at 6 s end to end. A lookup that can't finish in time refuses with exit 3 and `code: "session_lookup_failed"`, and never answers not-found. On a large undeclared bucket a never-opened name now gets that refusal quickly, whether or not the bucket is healthy.

When the 30 s gate fires, koto kills the probe's process group and records `exit_code: -1` with `error: timed_out`, the field a transition can route on (`failure_kind: timed_out` sits beside it). `resume_route` has no arm for -1 or for that error, so the run holds. The state's directive says to tick again, which runs the same lookups again. The issue saw this on all seven of one session's visits.

An answer that arrives in time doesn't resume either. At v0.37.0 koto exits 2 both for "not found" and for "couldn't settle", and only the stdout text tells them apart; at v0.37.1 "couldn't settle" exits 3. `has-work` counts any exit 2 without "not found", and any other exit, as an error, so the probe answers cannot-tell and the run stops at `done_error` with step `scope:resume-probe`. On koto v0.37.1 that's the usual outcome on an undeclared bucket: the session stops at the probe instead of timing out, and it still can't get past `resume_route`.

A tick also carries koto's exit flush: its PUTs and deletes run one after another on the main client, which allows 60 s per request. The issue's 92 s tick against a 30 s gate shows that the rest of a tick can cost more than the gate does.

The goal: a resumed session in front of a slow or partly failing bucket either resumes, or stops with an answer someone can act on (which lookup ran long or refused, what it said, what to do next), within a time the template states.

## Decision Drivers

- The gate's time has a known upper bound, stated in the template and true with koto v0.37.0 and v0.37.1 alike.
- A session that may exist is never misread as absent; the ladder's safety rests on that.
- The session resumes whenever the answers that decide its row are in, even if lookups that can't change the row are still out.
- A stop names the lookups that ran long or refused, with koto's text, and says what to do next. A bare "timed out" isn't enough.
- Each visit makes few bucket round trips, because bucket health isn't shirabe's to control.
- The ladder stays table-tested, and the tests gain the slow-lookup and refusal cases they miss today.
- The work divides between shirabe and koto by what each owns: shirabe owns the gate and the probe, koto owns lookup semantics.

## Considered Options

The problem splits into three questions: where the time bound is enforced, how the never-opened names get settled, and what shirabe needs from koto. Each went to `/decision`. The second is the critical one, since it decides when a lookup that couldn't finish may ever count as absent.

Cross-checking the three answers found one conflict. The second decision's first answer required `parent_state`, the lookup a child's `adopt` makes for its parent sessions, to read koto v0.37.1's exit 3 as absent when its text says "the bucket holds none under this directory's prefix". That's the reading tsukumogami/shirabe#1764 asks for. koto's lookup doesn't support it. koto lists this directory's own prefix as a request of its own (`src/session/cloud.rs:966`). Only when that comes back empty does it list the bucket's workspace prefixes and sweep them (`:1049-1129`), and any failure in that second step exits 3 with exactly that text (`:927-933`). A listing of the prefixes that gets no answer within the deadline produces it: "... holds none under this directory's prefix ..., and koto can't tell whether another directory's prefix holds it: listing the bucket's workspace prefixes failed: io: no answer within ...". So the phrase means this directory's prefix was empty and the rest of the bucket went unchecked. A session under another prefix, including one an older koto wrote, would be settled as absent on a flaky network.

So the three decisions were amended in place rather than re-run, since the design skill's restart path has no route when the decision record is kept append-only (tsukumogami/shirabe#1766). Decision 2 replaces that reading with "not a parent here", keyed on the host holding no copy. Decision 3 keeps "a refusal is never absent" with no exception and takes Decision 2's reply shapes. Decision 1's unsettled hold now says when another tick won't help, and the probe takes the operator's local-topic argument. The amended text is what appears below.

### Decision 1: Where the resume ladder's time bound is enforced

Today the `ladder` gate gets koto's default 30 s, and when it fires koto kills the probe and records `exit_code: -1` with `error: timed_out`. `resume_route` has no arm for that, so the run holds and the next tick repeats the same lookups. At koto v0.37.0 a lookup of a never-opened name has no worst case: it sweeps every workspace prefix with no overall bound. A routed gate result carries no gate text to the agent; only a hold carries the probe's `::koto-finding::` lines on the gate's blocking condition. And the ladder's rows don't all need the same lookups: rows 20-29 need only the resumed session's own keys, rows 40-50 add the local artifact tree, and only rows 10, 11 and 12 need all seven.

Key assumptions:

- Within a tick the default action's calls leave the resumed session's copy current, so the probe's own-session reads make no bucket request. If wrong, a resumable topic on a slow bucket stops unsettled instead of resuming.
- A descendant walk (`pkill -P` on each job, then the job) reaches the koto process that `has-work` starts through command substitution on bash 3.2.
- A 20 s deadline inside a 30 s gate leaves the probe time to kill, collect and print. These are starting values for the tests to confirm.
- A per-gate `timeout:` and routing on `error: timed_out` exist at koto v0.37.0 as at v0.37.1. This was checked against v0.37.0's gate keys and its timeout evidence.

#### Chosen: Probe deadline with early answer, an unsettled answer that holds, a backstop timeout and a timed_out arm

The probe owns the bound. A 20 s deadline covers every koto call it makes. As answers arrive it evaluates the ladder and returns a row as soon as every lookup that row depends on is settled, then kills the lookups that can't change it. When the deadline passes first, or a lookup the row depends on refuses, the probe exits with a new code, 3 (unsettled). It prints one finding line per outstanding or refused lookup, with koto's own text and the next step. `resume_route` has no arm for 3, so the run holds and the agent reads the findings.

The next step depends on the reply. If the refusal says this directory's prefix answered empty and other prefixes went unchecked, or a v0.37.0 lookup was killed at the deadline, another tick won't clear it. The line names the two ways through from Decision 2. The agent ticks at most once more, then stops and reports, under `--auto` too. Any other refusal says to tick again once the bucket answers.

Both resume gates set `timeout: 30` as a stated backstop, with an arm on `error: timed_out` to `done_error` and a fixed reason saying the probe's own deadline didn't fire. This is the only option that makes the stated bound true at v0.37.0. The bound holds because shirabe enforces it, not the bucket.

#### Alternatives Considered

- **Gate timeout only.** Size a `timeout:` on both gates to the worst lookup. There is no worst lookup at v0.37.0, so the stated bound would be false, and a killed gate still holds with nothing to say.
- **A route for the killed gate.** An arm on `exit_code == -1` to `done_error` or a retry-later state. The stop could say only "timed out": a killed probe prints nothing, a routed result carries no gate text, and -1 also covers spawn and wait failures. It survives in narrower form as the backstop's `error: timed_out` arm.
- **Probe deadline, wait for every lookup.** Kill at the deadline and answer cannot-tell. A resumed session whose own state decides its row would still wait on, and be stopped by, names that can't change that row, and the routed answer hides which lookups were out. Per-lookup deadlines add tuning without changing the bound.
- **Early answer, but the deadline answers cannot-tell into `done_error`.** The routed stop drops the lookup names and koto's text, and treats a passing bucket state the same as a broken input.

### Decision 2: How the probe settles never-opened names, and when an unsettled lookup may count as absent

On a fresh topic, five names this host never held reach the bucket: `explore-<topic>` and the four child names. They decide the row only when neither scope key exists and the artifact tree holds nothing. koto's workspace prefix is a hash of the canonical cwd (`src/session/local.rs:890-895`), so every checkout, instance and worktree has its own. A name opened anywhere on this host answers from the host's copy with no bucket request (`src/session/cloud.rs:864`). Only names this host never held need the lookup that sweeps other prefixes. On a large undeclared bucket that lookup can't settle within koto's 6 s, and by koto's cloud-sync guide a caller tells "no session has this name" from "koto couldn't find out" by the exit status and `code`, not the message.

The probe isn't the only blocker. Every child skill's `adopt` checks its parent sessions, `scope-<topic>` and `charter-<topic>`, through `parent_state` (`scripts/skill-session.sh:549-567`, `:914-920`). On a tactical topic `charter-<topic>` is never opened, so at v0.37.1 it refuses with exit 3 and the first hop stops even after the ladder lets the run through (#1764).

Key assumptions:

- koto v0.37.0 ships `koto --workspace <path> status|context exists` with v0.37.1's codes: `session_not_found` and `workspace_not_found` exit 2, `workspace_unreadable` exit 3.
- `koto session list` lists this host's store plus this directory's prefix. Its bucket half can fail with only a warning, and the probe draws no conclusion from what it doesn't show.
- An operator usually knows whether a topic was worked on another host or checkout. In an interactive session agents follow the directive never to add the statement themselves; under `--auto` and in a dispatched run, `scope-open.sh` refuses it outright.
- Declaring the bucket's name index behaves as koto's cloud-sync guide says, including its trade-off. On a declared bucket a session only older koto releases touched has no index entry; the audit writes entries for every session present, and the 7-day probation catches an older koto still writing. The design names the declaration with its probation and never suggests skipping it.

#### Chosen: Strict by default, with an operator-stated local scope read by code

By default a never-opened name's refusal is unsettled, never absent. A fresh topic on a large undeclared bucket stops with the probe's exit 3. The finding says another tick won't clear it and names two ways through:

- **Re-run with `--local-topic=stated`.** The operator runs `/scope <topic> --local-topic=stated` when they know the topic has no session elsewhere. Anything held elsewhere is given up: a second session of the same name opens here, and a handoff held elsewhere isn't read.
- **Declare the bucket's name index.** This clears the stop for every topic.

The flag sets a rebind template variable that both resume gates pass to the probe, so it covers only the invocation that typed it and koto's events record it. The agent never adds it, and `scope-open.sh` refuses it under `--auto` and in a run another session dispatched, so the statement can only come from an operator at an interactive session.

Under the statement, and only for the five never-opened names, the probe reads by code:

1. One `koto session list` runs alongside the scope-key reads. Names it shows get the ordinary lookup, which answers from the host's copy or this directory's prefix.
2. Each name it doesn't show gets one `koto --workspace <this dir>` read. That read covers exactly this directory's prefix and makes no sweep. The name counts as absent from this prefix only on exit 2 with `session_not_found` or `workspace_not_found`.

`parent_state` answers a narrower question: is this session the parent that dispatched this child? Its ground (#1637) is that a parent dispatches from this checkout, which leaves its copy on this host, so a session with no copy here isn't this child's parent. koto builds `session_lookup_failed` only for a name with no copy on this host (`src/session/cloud.rs:864-870`). So `parent_state` reads that exit 3, and v0.37.0's exit-2 no-copy reply as today, as "not a parent here". That's an answer separate from absent, which the dispatch match skips and no other caller sees. Nothing is ever recorded as absent from an exit 3.

#### Alternatives Considered

- **Read the own-prefix-empty refusal as absent.** Applied to the five names, and as first proposed for `parent_state`. That text is what a timed-out listing of the bucket's prefixes produces, so absence would be inferred from a network failure. Any session held only under another prefix would be passed over with no trace, and it gives nothing at v0.37.0.
- **One own-prefix listing as the default.** Read names that `koto session list` doesn't show as absent. This carries the same silent residual, and its check of the warning fails unsafe: a reworded warning turns a failed listing into an empty one. Its coded host-copy-then-`--workspace` read survives as the mechanism under the statement.
- **Scope records the children it opened.** Look up only recorded names. A fresh topic has nothing recorded, and a ledger reads every unrecorded name as absent without asking koto. That includes children from direct `/brief`, `/prd`, `/design` or `/plan` runs, explore handoffs and other checkouts' sessions.
- **Never absent, with the index declaration as the only remedy.** That remedy needs a full audit and up to 7 days' probation. The `/brief`-first workaround suggested for it stops on `parent_state` at v0.37.1. Its strict default and finding text survive in the chosen option.

### Decision 3: What shirabe asks of koto, and what it depends on

The two koto releases differ only in lookup behaviour. At v0.37.0 a lookup that can't settle exits 2 with no `code`, and only its text separates it from the exact not-found reply. At v0.37.1 (koto#670) the lookup has a 6 s deadline, and one that can't finish exits 3 with `code: "session_lookup_failed"` and never says not found. Neither `status` nor `context exists` arms koto's exit flush, so killing a lookup writes nothing to the bucket.

Key assumptions:

- koto's changelog statement describes v0.37.0: before koto#670, a bucket that couldn't be reached at all made a name read as absent.
- The resumed session's copy on this host stays current within a tick, so own-session `context exists` never takes the remote-manifest fallback, where a failed fetch reads as absent. This is the same premise as Decision 1's first assumption.
- koto keeps building `session_lookup_failed` only for a name with no host copy. `parent_state` relies on this, and its tests pin the reply shape.
- At v0.37.0 a lookup that couldn't settle never carries the no-copy text `parent_state` matches. The contract test checks this against real v0.37.0.

#### Chosen: Both releases side by side, read in-band, depend only on shipped behaviour

Each reply is read by its shape, with no version call:

- **`koto status`.** Exit 2 is absent only when `error` is exactly `workflow '<name>' not found` with no `code`. That replaces today's substring match. Exit 3 with `session_lookup_failed`, and any other exit 2, is a refusal.
- **`koto context exists`.** 0 means present and 1 means absent. Exits 2 and 3 are refusals.
- **The `--workspace` reads.** Their not-found codes count only under Decision 2's statement, and `workspace_unreadable` is a refusal.
- **`koto session list`.** Used only to find names this host or this prefix holds.
- **Anything else.** Cannot-tell, with koto's line kept.

A refusal is never absent. The "holds none under this directory's prefix" text inside an exit 3 is a refusal like any other. The only miss the bucket answered is the exact not-found reply. `has-work` gains a refusal exit and passes koto's line through.

The design depends only on behaviour shipped at v0.37.0:

- the exit codes and reply shapes above;
- the per-gate `timeout:`, the kill of the gate's process group, and `error: timed_out` as a routable field;
- the gate's cleared environment;
- read commands that arm no exit flush;
- `koto session list` and the `--workspace` reads.

v0.37.1's deadline and coded refusal are used when present. The asks filed with koto are benefits, not dependencies:

- own-session `context exists` refusing instead of reading absent on a failed manifest fetch;
- a caller-set lookup deadline;
- a batch lookup;
- `session_lookup_failed` in the error-code reference;
- a bounded exit flush;
- a coded failure from `session list`;
- a read-only report of whether the index is declared;
- structured fields saying this directory's prefix answered empty and that the host holds no copy.

Declaring the index is named as the operator remedy. The design names one v0.37.0 limitation: there, a bucket that can't be reached at all answers a never-opened name as not found. v0.37.1 closes that.

#### Alternatives Considered

- **A koto v0.37.1 floor.** Refuse resume on v0.37.0. That stops resume on every v0.37.0 host, including rows decided by the resumed session's own keys, to close a hole that predates this design. The shipped v0.37.1 already closes it for every caller, not just the probe.
- **Version-aware degrade.** On v0.37.0, treat every never-opened name's not-found as unsettled. A version check can't tell an unreachable bucket from a healthy one, so it would stop every fresh topic on v0.37.0, and the `bail` gate, charter's resume and the dispatch match would still trust `has-work`.
- **Make new koto lookup features dependencies.** Build on a caller-set deadline, a batch lookup and a bounded exit flush. None exists on a released koto, so the design couldn't ship against one.

### Implicit decisions in the architecture

The three choices below came up while the architecture was written. Each was confirmed as an implicit decision, not run through `/decision`.

### Decision 4: How a finding line picks its advice

**Context.** An unsettled lookup's finding line says what to do next. Some refusals clear on the next tick, and some never will on a large undeclared bucket.

**Chosen: match koto's refusal text, only to pick the advice.** The line says `next=stop-and-act`, with both remedies, in two cases:

- an exit-3 refusal whose text says this directory's prefix answered empty and other prefixes went unchecked;
- a v0.37.0 lookup killed at the deadline.

Everything else gets `next=tick-again`. The text never decides a row, and a reworded refusal falls back to `tick-again`, which is safe.

**Rejected: name both remedies on every refusal line.** It needs no text match, but it pushes `--local-topic`, which gives up sessions held elsewhere, at failures that another tick would clear.

### Decision 5: The finding line's format

**Context.** The lines reach the agent on the gate's blocking condition, and the tests read them too. That condition is part of the session's event log, so the text also syncs to the bucket and can be copied by an agent into a report.

**Chosen: one `::koto-finding::` line of key=value fields built by the probe, ending with a reduced form of koto's reply.** The fixed fields say which lookup, what happened and what to do next. The last field, `koto=`, carries koto's `code` and its message reduced to an allowlist of characters and capped in length (Security Considerations has the rules). This serves the driver that a stop names the lookups with koto's text and says what to do next, while keeping what reaches the log and the agent to the part of the reply that helps someone act.

**Rejected: a JSON object per line.** It's easier to parse, but the driver this line serves is an agent reading a stop and acting on it, and key=value fields with koto's text last read directly. The table-tested driver doesn't favour JSON either: the tests read only the fixed keys, which key=value pins as well.

**Rejected: koto's stdout line kept whole.** It gives the reader everything koto said, but credentials or endpoints in an io error would sit in a log that syncs to the bucket.

### Decision 6: Build order

**Context.** Three pieces depend on each other: the reply table, the probe's clock with the gate backstop, and `--local-topic`.

**Chosen: the reply table first, then the probe's clock with the backstop, then `--local-topic`.** The reply table closes #1764 on its own, and both later pieces use its refusal exit.

**Rejected: the probe's clock first, as the visible fix for #1737.** It would have to build the refusal exit and the reply table along the way, so the first change would carry two concerns.

## Decision Outcome

The probe owns the time bound, and nothing reads a lookup that couldn't finish as absent.

A resumed `/scope` session's `ladder` and `pointer` gates each state a 30 s bound. Inside it the probe runs a 20 s deadline over all its koto calls.

The probe answers as soon as the lookups its row needs are settled. A resumed topic whose own keys decide the row therefore resumes, even when the never-opened names are still out or refusing. When the row can't be decided in time, the probe exits 3. The run holds in `resume_route`, and the agent sees one finding line per lookup that ran long or refused, with koto's text and the next step. When the reply shows another tick won't help, the line says so and names the two remedies, and the agent stops after at most one more tick. A probe that outlives its own deadline is killed by the backstop and routed to `done_error` with a fixed reason.

koto's replies are read by exit code and `code` first, and absence is only ever the exact not-found reply:

- At v0.37.1 a refusal arrives within 6 s with koto's text.
- At v0.37.0 a refusal is an exit 2 that isn't that reply, or the probe kills the lookup at its deadline.

Either way the stop has the same shape.

The operator's `--local-topic` statement, for one invocation, lets the probe settle the five never-opened names. The probe does this from the host's own list and one read of this directory's prefix each. `scope-open.sh` refuses the statement under `--auto` and in a dispatched run. Declaring the bucket's name index clears the stop for every topic.

The parent lookup in `adopt` stops blocking the first hop the same way, without reading absence: a parent with no copy on this host is "not a parent here", the narrower fact the dispatch match needs. This closes #1764.

Everything ships in shirabe against released koto: the probe, `skill-session.sh`, `scope-open.sh`, the template, and the tests. The koto changes are filed asks that would only make a bounded, explained visit shorter.

## Solution Architecture

### Overview

The resume ladder stays one read-only probe behind one gate per resume state. What changes is the probe: it now has a clock, answers early, and keeps koto's words. Every reply is read by exit code and `code` before anything else, and one table is the single place that says what counts as absent. `skill-session.sh` shares that table, so `has-work` and the parent lookup in `adopt` read koto the same way the probe does.

### Components

- `skills/scope/scripts/resume-probe.sh`: the ladder.
  - Gains a deadline (20 s, overridable only in tests), a poll loop over its seven jobs, marker files, a descendant kill, kept koto text, and the new exit 3 (unsettled) with its finding lines.
  - Gains a `--local-topic <stated|unstated>` argument, accepted once. A missing argument means `unstated`, so the probe built in Phase 2 runs before the gate passes it in Phase 3.
  - Under `stated`, it adds one `koto session list` and the per-name `koto --workspace` reads.
- `scripts/skill-session.sh`:
  - `session_state` and the probe's `key_exists` move to the shape table.
  - `has-work` gains a refusal exit separate from its error exit, and prints koto's stdout line instead of dropping it.
  - `parent_state` gains the "not a parent here" answer. `dispatch_match` skips it like a parent on another branch.
- `skills/scope/koto-templates/scope.md`:
  - Both gates gain `timeout: 30`, the `--local-topic "{{LOCAL_TOPIC}}"` argument, and an arm on `gates.<gate>.error: timed_out` to `done_error` with step `scope:resume-probe` and a fixed `failure_reason`. The gates are `ladder` in `resume_route` and `pointer` in `resume_stale`.
  - Exit 3 stays unrouted, so it holds.
  - A new `LOCAL_TOPIC` variable is declared with `rebind: true` and default `unstated`.
  - The directive for both states explains the hold: read the finding lines; when a line says another tick won't help, tick at most once more, then stop and report the two remedies. The agent never adds `--local-topic` itself.
- `skills/scope/scripts/scope-open.sh` gains `--local-topic`. It accepts only `stated` or `unstated` before it writes the rebind variable, for this invocation only, and refuses the flag under `--auto` and in a dispatched run. The scope skill's usage text names the flag and says when an operator uses it.
- Tests:
  - `resume-probe_test.sh` gains a per-session delay and koto's real refusal texts in its `KOTO_BIN` stub, plus a test-only deadline override.
  - `skill-session_test.sh` gains the shape-table and `parent_state` cases.
  - `scope-template_test.sh` pins exit 3 as unrouted, the `timed_out` arms, and the gate argument.
  - `scope-open_test.sh` pins the flag, its value check, and its refusal under `--auto` and in a dispatched run.
  - A contract test runs `skill-session.sh`'s reply table and `parent_state` against real koto at v0.37.0 and v0.37.1, not only against the stub.

### Key Interfaces

**Probe exit codes.** The probe exits with its ladder row's number, and the existing rows keep their numbers. Exit 2, the probe's cannot-tell answer (bad input, unreadable artifact, failed git read), keeps its meaning and its route to `done_error`. The new code is 3, unsettled: no route, so the run holds. Its stdout carries one line per outstanding or refused lookup:

```
::koto-finding:: lookup=<session>[ <key>] outcome=<deadline|refused> next=<tick-again|stop-and-act> koto=<koto's code and reduced message, or "none before the deadline">
```

**Which lookups decide which rows.** The ladder reads its inputs in a fixed order, so a row is settled once every input before it is:

| Rows | Lookups the row needs |
|---|---|
| 20-29 (the scope session's own state) | the two `scope-<topic>` keys, `work/state.md` and `work/prior-run.md` |
| 40-50 (an artifact on disk) | both scope keys answered, with no row from them, then the local artifact tree |
| 60-63 (a child's partial run) | the above, then `has-work` for plan, design, prd and brief in that order, each up to the first that has work |
| 12 (an explore handoff) | the above with all four children answered, then `handoff/scope.md` on `explore-<topic>` |
| 11 and 10 (topic branch, fresh start) | all seven lookups, then the git branch |

A present `work/state.md` always settles a row in 20-29, and a present `work/prior-run.md` settles one when it holds a failed publish step; either way every row from 40 on is ruled out and the probe stops waiting on the five never-opened names. A prior run with no such step falls through to the artifact tree. A refusal or a deadline on a lookup a row needs is the unsettled case; one on a lookup no remaining row needs is ignored.

`next=stop-and-act` is set for an exit-3 refusal whose text says this directory's prefix answered empty and other prefixes went unchecked, and for a v0.37.0 lookup killed at the deadline. The line then also names `--local-topic` and the index declaration. Every other refusal gets `next=tick-again`. Matching the text here only picks the advice; it never decides a row.

**The reply table.** This is the one place absence is defined, in `skill-session.sh` and mirrored by the probe:

| Command | Absent | Present | Refusal (unsettled) | Cannot tell |
|---|---|---|---|---|
| `koto status` | exit 2, no `code`, `error` exactly `workflow '<name>' not found` | exit 0 | exit 3 `session_lookup_failed`; any other exit 2 | anything else |
| `koto context exists` | exit 1 | exit 0 | exit 2; exit 3 `session_lookup_failed` | anything else |
| `koto --workspace <dir> status`, `context exists` (only under `--local-topic`) | exit 2 `session_not_found` or `workspace_not_found`: absent from this prefix | exit 0 | exit 3 `workspace_unreadable` | anything else |

**`has-work` exits.** 0 means has work and 1 means none, as today. The new exit 7 means refused and carries koto's line on stdout; 4 stays the cannot-tell exit, and 64 and 127 keep their meanings. 7 is unused anywhere in `skill-session.sh` today. The probe's `child_partial` gains a case for 7 as unsettled; without it, 7 would fall into its cannot-tell branch.

**The `--workspace` reads under the statement.** For a child name, the probe's own `--workspace` read stands in for `has-work` only when it answers absent from this prefix, which counts as `has-work`'s 1 (no work). A present reply sends the name to the ordinary `has-work`, inside the same deadline. A refusal or an unknown reply is unsettled, like `has-work`'s refusal exit. For `explore-<topic>`, absent from this prefix answers the handoff key as absent.

**`parent_state` answers.** live, finished and absent come from the reply table. "Not a parent here" comes from exit 3 with `session_lookup_failed`, or from v0.37.0's exit-2 reply carrying the no-copy text #1637 already matches. 4 means cannot tell, from anything else, including exit 3 with another code.

### Data Flow

A tick into `resume_route` first runs the state's default action, `record-scope-exit.sh --stage resume`, unchanged. koto then runs the `ladder` gate with a 30 s timeout. The probe:

1. starts the seven lookups as background jobs, each writing its reply to its own file and a marker when it finishes;
2. under `--local-topic stated`, also starts one `koto session list`;
3. polls every few hundred milliseconds:
   - classifies each finished reply through the reply table;
   - re-evaluates the ladder in its row order;
   - stops as soon as a row's inputs are all settled;
4. kills the jobs still out, walking descendants, and exits with the row; or, at the deadline or on a refusal the row needs, prints the finding lines and exits 3.

Under `stated`, a never-opened name the session list doesn't show gets its `--workspace` read as soon as the list is in, inside the same deadline.

koto routes rows as today. Exit 3 matches no arm and holds, with the findings on the blocking condition. A gate killed at 30 s matches the `timed_out` arm and ends at `done_error`.

The probe writes nothing to koto. A killed `status` or `context exists` lookup arms no exit flush, so killing one leaves the bucket untouched. The same holds for the two reads the statement adds: `koto session list` sets no exit flush and opens no write window, and a `--workspace` read runs on a read-only backend that refuses any bucket write, which koto's cloud-sync guide states as a contract. A `--workspace` read killed mid-run can leave its own temporary directory behind, and nothing else.

On the child's first hop, `adopt` runs `dispatch_match`. For a never-opened `charter-<topic>` or `scope-<topic>`, the reply is exit 3 `session_lookup_failed` on v0.37.1, or v0.37.0's exit-2 no-copy reply. `parent_state` answers "not a parent here", and `dispatch_match` moves on. Any other unreadable reply still returns 4 and stops `adopt` as today.

## Implementation Approach

### Phase 1: The reply table

Build `session_state`'s exact not-found match, `has-work`'s refusal exit 7 and kept text, and `parent_state`'s "not a parent here" answer, with their tests on both releases' replies and the contract test against real koto. Until Phase 2 the probe reads exit 7 as cannot-tell, as it reads 4 today. This comes first because the probe's classification and the finding text both depend on it. It also closes #1764 on its own.

Deliverables:
- `scripts/skill-session.sh`
- `scripts/skill-session_test.sh`
- the contract test

### Phase 2: The probe's clock and the gate bound

On the probe: the deadline, the early answer, the descendant kill, exit 3 with finding lines, `child_partial`'s case for `has-work`'s exit 7, and argument parsing that reads a missing `--local-topic` as `unstated`. On the template: the backstop, which is `timeout: 30` and the `timed_out` arms on both gates, plus the directive text. In this phase the directive and the finding lines name only another tick and the index declaration; the `--local-topic` remedy arrives with the flag in Phase 3. This depends on Phase 1's refusal exit.

Deliverables:
- `skills/scope/scripts/resume-probe.sh`
- `resume-probe_test.sh`, with the delay stub and deadline override
- `skills/scope/koto-templates/scope.md`
- `scope-template_test.sh`

### Phase 3: The operator's statement

Build `--local-topic` in `scope-open.sh`, with its value check and its refusal under `--auto` and in a dispatched run, the `LOCAL_TOPIC` rebind variable and gate argument, and the probe's `session list` plus `--workspace` path. It also adds the `--local-topic` remedy to the finding lines and the directive, and the scope skill's usage text. This depends on Phase 2's finding lines and argument parsing.

Deliverables:
- `scope-open.sh`, `scope-open_test.sh`
- `scope.md`
- `resume-probe.sh`, `resume-probe_test.sh`
- the scope skill's usage text

### Follow-on

File the koto asks listed in Decision 3 as koto issues. Separately, consider presenting the index declaration as part of bucket setup in shirabe's docs, if fresh dispatched topics on large undeclared buckets turn out to be routine.

## Security Considerations

The probe only reads. It writes nothing to koto or the bucket, and none of its lookups, `status`, `context exists`, `session list` or a `--workspace` read, arms an exit flush or opens a write window. The design adds no package, download or binary. What it changes is how text and processes are handled around those reads, plus one operator statement that trades integrity for progress.

**Finding lines carry bucket-derived text.** Each `::koto-finding::` line ends with a reduced form of koto's reply. A reply can include workspace prefixes, endpoints and io errors, and the line sits on the blocking condition in koto's event log, which syncs to the bucket. An agent reads it too. The probe treats that text as data and reduces it by allowlist, not blocklist:
- It keeps koto's `code` when there is one.
- From the message, it keeps only the first line, cuts any URL to its scheme, host and path, and drops every character outside letters, digits, space and `._:/'()-`.
- It caps the result at 300 characters.
- It neutralizes any `::koto-finding::` inside it.

A credential shape the allowlist still passes, such as a long token made of letters and digits in a path, is the residual. The directive tells the agent never to paste `koto=` text into a pull request, issue or commit, and to describe the stop in its own words instead.

`koto=` is always the last field, behind fields the probe builds itself, so a reply can't forge or reorder them. Matching the text only moves a line between `tick-again` and `stop-and-act`; absence is never decided by text. The resume directive says `koto=` is quoted data, and that the only actions a finding names are the remedies the probe prints. A reply that imitates one of those remedies can at most suggest `--local-topic`, which `scope-open.sh` refuses unless an operator types it at an interactive session. The backstop's `failure_reason` is fixed text, so no bucket text reaches `done_error`.

**The operator statement.** `--local-topic` reaches the gate as a template variable, and koto substitutes that variable into the gate's command string before the probe runs. So the value is checked before substitution: `scope-open.sh` accepts only `stated` or `unstated` and refuses anything else before it writes the variable, and the variable's default is `unstated`. The probe's own check, which rejects any other value with a usage error before it reads anything, is a second line. `scope-open_test.sh` and a template test pin both.

The statement gives up integrity, not secrecy. A same-named session or handoff held under another directory or on another host is missed, which can produce a duplicate session or a conflicting PR. `scope-open.sh` refuses the flag under `--auto` and in a dispatched run, so an unattended agent can't state it and reports the stop instead. In an interactive session, the directive and koto's recorded variable events are what keep an agent from adding it; an operator is there to see it. The risk is accepted because the flag covers one invocation and is on the record.

**Process handling.** The descendant kill signals only process ids taken from a snapshot of the probe's own jobs and their children, and only for jobs that are still live and have written no marker. It never matches by name, so a reused id can't redirect it. The gate's process-group kill at 30 s covers any straggler. A SIGKILL skips the probe's exit trap and can leave its private (0700) temp directory, which holds reply text, under `TMPDIR`. The deadline override is honored only in tests and is clamped below the gate's bound.

**The parent lookup.** "Not a parent here" covers exactly two replies: exit 3 with `session_lookup_failed`, and v0.37.0's exit-2 no-copy reply. It changes `adopt` from failing closed to failing open on those two replies: where an unreadable parent lookup used to stop `adopt`, a parent with no copy on this host is now skipped. It rests on two things koto's docs describe but don't promise as a contract. koto builds that refusal only for a name with no copy on this host. And at v0.37.0, a lookup that couldn't settle never carries the no-copy text. The stubbed `parent_state` tests pin the reply shapes shirabe reads, but they can't notice koto changing what it sends. That is the contract test's job: it runs `parent_state` against real koto at v0.37.0 and v0.37.1.

The contract test's evidence includes a session written by a koto release from before the bucket's name index, held two ways. Held on this host, the lookup answers from the host's copy, and `parent_state` answers live or finished. Held only under another directory's prefix, with no copy here, it answers live when the sweep finds the session and "not a parent here" when the sweep can't finish. In neither case does it answer absent. On a bucket whose name index is declared, a lookup answers from the index, which the declaration's audit fills for every session present. A session missing from an unaudited index is the declaration's own trade-off, named in Decision 2. It doesn't come from this path. "Not a parent here" is never absent: only the dispatch match reads it, as a parent on another branch, and nothing records it.

A parent that ran on another host and left no copy here isn't seen by `adopt`. That matches what `adopt` could already see, since a parent dispatches from its own checkout.

**Out of scope: what a resumed session holds.** The probe reads whether keys and sessions exist and their state, never a key's contents. What the resumed run later reads from its own session is the scope skill's trust boundary today, and this design doesn't change it.

**Trust in koto's replies.** The design relies on koto's exit codes, its `code` field and the exact not-found string. That's why every other reply shape counts as a refusal, never as absent.

## Consequences

### Positive

- A resumed session's gate has a stated bound, 30 s plus koto's group-exit wait, that holds on v0.37.0 and v0.37.1 whatever the bucket does.
- A topic whose own keys decide its row resumes on a slow or partly failing bucket. It no longer stops on lookups that can't change its row.
- Every stop names the lookups that ran long or refused, with koto's text, and says whether another tick can help.
- No lookup that couldn't finish is ever read as absent: not by the probe, `has-work` or the parent lookup. The parent lookup still lets the first hop through, on a fact about this host.
- `session_state` stops treating a v0.37.0 refusal whose text contains "not found" as a miss.

### Negative

- A fresh topic on a large undeclared bucket stops once on every first visit until the operator re-runs with `--local-topic` or the bucket's index is declared.
- `--local-topic` gives up any same-named session or handoff held under another directory or on another host. In an interactive session only the directive and the recorded variable keep an agent from adding it.
- The probe's concurrency logic is more involved, must stay on bash 3.2, and its tests involve timing.
- The template states the gate's bound, not the tick's. The default action's eight `koto context` calls and koto's exit flush sit outside it.
- On v0.37.0, `adopt`'s lookup of a never-opened parent still runs an unbounded sweep, and a bucket that can't be reached at all can still read a never-opened name as not found.
- "Not a parent here" rests on koto building `session_lookup_failed` only for a name with no host copy, which koto's docs state but don't promise as a contract.
- `adopt`'s parent lookup now fails open on those two replies where it used to fail closed. This is an accepted residual risk: a koto change that sent the no-copy refusal for a parent that does have a copy here would let `adopt` skip that parent. It would still never be read as absent.
- `koto=` text that passes the allowlist can still carry a credential-shaped token into the event log.
- The finding's advice picks `next=stop-and-act` by matching koto's text. A reworded refusal falls back to `tick-again`, which is safe but less helpful.

### Mitigations

- The finding line names both remedies plainly. The index declaration's audit and probation clear the stop for every topic without weakening the absent rule.
- The flag covers one invocation and is recorded in koto's variable events. `scope-open.sh` refuses it under `--auto` and in a dispatched run, so an unattended agent reports the stop instead.
- The deadline override and short stub delays keep the timing tests fast and deterministic. The descendant kill keeps every process in the gate's group, so koto's backstop still covers them.
- The koto asks in Decision 3 would bound the flush and the lookup from koto's side. v0.37.1 already bounds the parent lookup and closes the unreachable-bucket hole.
- The stubbed `parent_state` tests pin the reply shapes shirabe reads; they catch a change on shirabe's side, not koto's. The contract test runs against real koto at v0.37.0 and v0.37.1, including a session written by a release from before the name index, so a koto change to the replies surfaces when that test runs against the new release. The asks include a structured field for "no copy on this host", which would replace the reply shape the design relies on.
- The directive tells the agent never to paste `koto=` text into a pull request, issue or commit.
