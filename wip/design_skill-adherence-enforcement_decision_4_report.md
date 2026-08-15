# Decision 4: the conflict-record vehicle and its surfacing

Requirements: R10, R11, R19. Complexity: standard.

## Question

What vehicle carries the conflict record when no orchestration session exists,
and by what surface does it reach the author without the author querying the
session?

Four sub-questions, answered in order below: the in-loop and pre-session
vehicles; the surfacing channel including the dispatched-run case; the durable
home given `wip/` is not durable and R19 constrains a public repo; and whether
R2's "unrecorded departure is non-conforming" is enough teeth.

## What was verified for this decision

Everything in this section was run or read on this machine, not inferred.

**`koto overrides record` and `koto decisions record` both fail with no
workflow, and both exit 1.** The brief recorded exit 1 for `overrides`; I
confirmed it and found `decisions` behaves identically:

```
$ koto overrides record nonexistent-workflow-xyz --gate g --rationale r
{"command":"overrides record","error":"workflow 'nonexistent-workflow-xyz' not found"}
exit=1
$ koto decisions record nonexistent-workflow-xyz --with-data '{"choice":"a","rationale":"b"}'
{"command":"decisions record","error":"workflow 'nonexistent-workflow-xyz' not found"}
exit=1
```

Both also write hundreds of `koto: migration skipped <name>` lines to stderr on
every invocation on this machine (over 20 KB in the run above). Any caller must
redirect stderr or it swamps a hook log. This matches the `koto status` warning
recorded in the koto-observability lead.

**Their surfaces differ in a way that matters.** `overrides record` takes
`--gate <GATE> --rationale <RATIONALE>` plus optional `--with-data` JSON;
`decisions record` takes only `--with-data <JSON>` and requires the JSON to
carry `choice` and `rationale`. Neither has a native field for "the instruction
that conflicts". Both accept arbitrary `--with-data` JSON, so a three-field
payload is expressible in either.

**`shirabe work-summary`'s store is not durable.** `ensure_store()` at
`crates/shirabe/src/work_summary.rs:404-423` resolves the store dir as
`WS_STORE_DIR` → `$XDG_RUNTIME_DIR` → `$XDG_STATE_HOME` → `~/.local/state`,
joined with `shirabe-work-summary`. On this machine it lands in
`/run/user/1000/shirabe-work-summary` — tmpfs, wiped on logout and reboot.
`~/.local/state/shirabe-work-summary` does not exist. Confirmed by listing both.
The per-session files are `<sid>.ledger`, `<sid>.state`, `<sid>.lock` at mode
0600 in a 0700 directory, symlink-refused at both the directory and the file
level.

Preferring the runtime dir is correct for what work-summary is — a per-session
snapshot of in-flight PRs, worthless after the session ends. It is wrong for a
conflict record, which is an audit artifact. **A conflict record must not reuse
that store's resolution order.**

**Work-summary's emission is throttled, and the throttle is a problem.** The
component runs a two-level gate: a content hash of the rendered block, then an
interval (`WS_RENDER_INTERVAL`, default 300s; `WS_ABSENCE_THRESHOLD`, default
1800s). A new conflict changes the block content, so it clears level one, but
level two would hold it for up to five minutes. Also relevant:
`work-summary compact` (SessionStart) emits `additionalContext` **only** — no
`systemMessage`. Only `capture` (PostToolUse) and `absence` (UserPromptSubmit)
carry the user-facing channel.

**`/execute`'s closed write-target set already contains two durable homes.**
`skills/execute/SKILL.md:661-667`, Security Considerations point 2, confines
writes to: `wip/execute_<topic>_*`; the skill's own files; **the home PR /
coordination body via `gh pr edit` / `gh pr ready` / `gh pr close`**; the
finalization cascade's chain transitions under `docs/`; and **Decision Records
under `docs/decisions/` on `re-evaluation`**. A write outside the set fails the
R9 hard-finalization check. `docs/decisions/` exists and holds six
`DECISION-<topic>-<date>.md` files.

`SKILL.md:411-415` is explicit that an automated run-report emit is deferred
precisely because it would add a target outside this set and need an R9
amendment. The PR body and `docs/decisions/` are inside it already.

**R19 has a shipped precedent with a named rule and an implementation.**
`references/coordination-strategy.md:229-252` is F1, fail-closed
private-identifier redaction: "A private repo's name, path, branch, PR title,
and number are themselves private. The skill authoring a body MUST NOT write a
private repo's identifiers into a public coordination PR body... if a repo's
visibility cannot be resolved, treat it as private." `/execute`'s Security
Considerations point 5 calls F1 "the runtime face of" its visibility boundary.
R19 is F1 applied to a different body, not a new class of rule.

**The repo's CLI-surface rule constrains what may be built.** `CLAUDE.md`:
artifacts are authored by skills, `shirabe validate` is the correctness engine,
and adding a CLI subcommand that renders an artifact body is a named
anti-pattern with a removed-feature worked example (`shirabe coordination
create/status/sync`). A CLI that writes a mechanical ledger and emits hook JSON
is not that — `work-summary capture`/`track` is the shipped precedent. A CLI
that renders a PR-body block would be.

## Options

### O1 — `koto overrides record` as the single vehicle

Rejected before this decision opened and re-confirmed: exits 1 with no workflow.
Retained only as an in-loop candidate.

### O2 — `koto decisions record` in-loop, something else pre-session

`decisions record` fits the semantics better than `overrides record`. The
incident's conflict was with `spawn_and_await`, a workflow state whose
directive text materializes children — not with a gate. `overrides record
--gate` asks the caller to name a gate; a conflict with a non-gate step has no
honest gate name to give, and inventing one puts a false entry in the override
list. `decisions record` records a choice with a rationale and does not advance
state, which is exactly what "I am departing here, for this reason" is.

Fails on its own because it needs a workflow.

### O3 — a `wip/` file

Disqualified by the workspace rule. `wip/` contents are deleted before a PR can
merge and MUST NOT be referenced from any committed artifact. A conflict record
there is erased exactly as intended, and `/execute`'s own D5 convention
(`SKILL.md:400-409`) already routes report-upstream notes away from `wip/` for
this reason.

### O4 — a Decision Record under `docs/decisions/`

Durable, in-repo, survives the squash-merge, visible in the PR diff, and
partially pre-authorized: the write target is already in the closed set,
conditioned on `re-evaluation`. Widening that condition is a small in-family
amendment rather than a new target class.

The cost is what it does to the decision index. The six existing entries are
considered architectural decisions with workspace lifetime
(`DECISION-cascade-trigger-mechanism`, `DECISION-multi-pr-posture-detection`).
A conflict record is a run event — one session, one departure, no durable design
content. Emitting one per departing run floods a curated index with run
telemetry and degrades the thing a reader goes to `docs/decisions/` for. It also
does not answer the pre-session question on its own: it is a file write, so it
is available with no koto session, but nothing about it reaches an author who is
not reading the branch.

### O5 — the home PR body

Already in the closed write-target set via `gh pr edit`. Off-machine, durable,
and it is the artifact an absent author actually opens when a dispatched run
finishes. It is where R19 bites and where F1 already tells us how to behave.

Two things make it insufficient alone. First, the timing: the PR may not exist
when the conflict happens. Incident 2's conflict fired at `spawn_and_await`,
after `orchestrator_setup` had opened the draft PR, so a PR existed — but
incident 1 never entered the workflow, and R10 requires the route to work with
no orchestration session, which is the same population. Second, the
squash-merge: Part 2 of a tsukumogami PR body is deleted at merge
(`references/pr-body-conformance.md`), so only a block in **Part 1** survives
onto `main`. A conflict block in the reviewer-context half is durable until
merge and then gone.

### O6 — extend `shirabe work-summary`'s ledger

Attractive because the distribution already exists: niwa registers it at three
events by default and it already emits both channels. Rejected as the *record*
because the ledger's grammar is PR-URL-keyed six-column TSV with dedup by URL,
its store defaults to tmpfs, and its emission is throttled to a five-minute
interval. A conflict is a single immediate event with three text fields, not a
snapshot row. Bending the ledger to hold it changes its keying, its dedup, its
durability, and its gate — which is a rewrite wearing the old name.

Its **emission path**, however, is exactly right and is kept below.

### O7 — layered: one command, local durable record, two surfaces

The chosen option.

## Chosen option

**One command, `shirabe conflict record`, writing a durable machine-local record
and surfacing through two channels: the already-registered work-summary hook
emission for the watching author, and a Part 1 block in the home PR body for the
absent one. In-loop it additionally mirrors into the koto event log.**

Concretely:

**1. Vehicle — the same command in both cases.** `shirabe conflict record
--instruction <text> --step <workflow-step> --course <intended-course>`, a
fail-safe subcommand modeled on `work-summary` (always exit 0, `flock`-guarded
store, symlink-refused, 0600/0700, hook-JSON assembled with `serde_json`). It
requires no koto session, no PR, no branch, and no repo state. Its three
required flags are R11's three fields; the command refuses to write with any of
them empty, which is what makes the record identify rather than gesture.

When a koto session exists, the same invocation **additionally** mirrors the
record into the session via `koto decisions record <name> --with-data`, with
stderr discarded. The mirror is best-effort: it never fails the local write, and
its failure is reported but not fatal. This is one route the agent learns, not
two. The in-loop and pre-session vehicles are therefore the *same* vehicle with
a conditional second backend — which is the point, because the incident is an
agent that had a route available and did not reach for it, and a route that
changes shape depending on whether `koto init` has run yet is a route with two
chances to be missed.

`koto decisions record` is chosen over `koto overrides record` for the mirror
because a conflict may be with a workflow step that is not a gate, and
`overrides record --gate` would require naming one.

**2. Durable home — `$XDG_STATE_HOME/shirabe/conflicts/<session-id>.jsonl`,
append-only, one JSON object per record.** Explicitly `XDG_STATE_HOME` (then
`~/.local/state`), **not** `XDG_RUNTIME_DIR`. This is a deliberate divergence
from `work_summary.rs:409-419` and the reason must be written into the code: a
work-in-flight snapshot is worthless after the session, an audit record is not,
and a runtime-dir default silently loses the record at the next reboot. The
local copy carries the instruction **verbatim** — it is 0600, machine-local, and
never crosses a visibility boundary, so full fidelity is free there.

`wip/` is rejected (deleted before merge, and referencing it from a committed
artifact is forbidden). `docs/decisions/` is rejected as the primary home for
the index-pollution reason in O4; it remains available to an author who decides
a particular conflict rose to an architectural decision, which is a human call,
not an automated write.

**3. Immediate surfacing — the work-summary hook emissions carry a conflict
line, throttle-exempt.** This needs no new hook registration and no new
distribution: `shirabe work-summary` is already registered by niwa into every
adopting instance at PostToolUse/Bash, UserPromptSubmit, and SessionStart, and
`capture` and `absence` already emit `systemMessage` (user-facing) alongside
`hookSpecificOutput.additionalContext` (model-facing). A non-empty conflict
ledger for the session prepends a conflict line to the block on both channels.

The second-level interval gate MUST be bypassed for a record the session has not
yet emitted. A conflict held for five minutes behind a render interval is not
"surfaced"; it is delayed. The first-level content-hash gate is kept, so a
conflict is announced once and does not repeat on every subsequent tool call.
Note that `compact` (SessionStart) emits `additionalContext` only, so the
post-compaction path re-reminds the model but does not re-notify the user — that
is correct and should stay.

**4. Durable surfacing for the absent author — a fenced conflict block in Part 1
of the home PR body.** `gh pr edit` on the home PR is already inside `/execute`'s
closed write-target set, so this needs no R9 amendment — unlike the deferred
run-report emit that `SKILL.md:411-415` calls out. Part 1, not Part 2, because
Part 1 becomes the squash commit body that lands permanently on `main` and Part
2 is deleted at merge. A departure from the sanctioned workflow belongs in the
permanent record of the change, not in reviewer scratch.

Per the repo's CLI-surface rule, the block is **skill-authored** from a
reference — the same division the coordination PR body uses — and **checked by
`shirabe validate`**, as a `--conflict-record` mode alongside the existing
`--pr-body` and `--coordination-body`. No CLI subcommand renders it.

**5. R19 — the published copy is redacted; the local copy is not.** The hazard
is concrete and it is the `instruction` field: the conflicting instruction can
be quoted from a private workspace overlay (this workspace has both
`CLAUDE.overlay.md` and a private `dot-niwa-overlay`), and quoting it verbatim
into a public PR body publishes private content. F1 is the answer and it already
exists: when the target repo is public, the published block identifies the
instruction by **source class and a stable hash** — "a workspace-level
instruction from a private overlay, `sha256:ab12…`" — never verbatim text, never
a private repo's name, path, branch, or issue number. Fail closed: unresolvable
visibility is treated as private.

This still satisfies R11's "identifies the instruction." Identification by
source and stable digest is identification; verbatim quotation is not required,
and the author holds the full text locally. AC23 tests the published copy, which
is the copy that can leak.

Note the incident's own instruction — "Do not call the AgentTool unless the user
requested it" — is a session-level system instruction, not repo content, so R19
does not bite on it. R19 bites on the workspace-level half of R10's
"session-level or workspace-level instruction," which is exactly where overlay
content lives.

## Rationale

**Why the vehicle is not a koto verb.** Both koto recording verbs are keyed on a
workflow name and both exit 1 without one. That is not a bug to route around: it
is what koto is. koto is a state machine over files, and a record against no
state machine has nowhere to go. R10 asks for a route that works when no session
exists, so the route cannot be a session verb. The mirror keeps the koto event
log complete when there *is* a session, which matters because that log is the
append-only trace decision 1's determination reads.

**Why the surfacing reuses work-summary rather than adding a hook.** The
established fact that work-summary is registered by niwa at three events by
default is the single most valuable thing in this decision's inputs, because
"reaches the author without the author querying" is a distribution problem and
that distribution is already solved and already carries a user-facing channel.
Adding a fourth registration to say one more sentence would be new machinery for
no additional reach.

**Why the PR body is the answer for a dispatched run.** For a run nobody is
watching, `systemMessage` goes to a terminal with no one in front of it. The
author comes back to the PR. That is not a workaround; it is where the author's
attention actually lands, and it is already a sanctioned write.

**Why Part 1.** The difference between Part 1 and Part 2 is the difference
between a permanent record and a note deleted at merge. The PRD's user story is
"a reviewer establishing what a branch went through," which is a question asked
after the merge.

**Why redaction rather than omission.** Dropping the instruction field for
public targets would satisfy R19 and break R11. Hashing it satisfies both, and
F1 already establishes redaction-with-an-opaque-identifier as the shipped
pattern for exactly this trade.

## R10's teeth: the honest answer

The brief asks whether R2 making an unrecorded departure non-conforming is
sufficient. **On its own it is not, and the reason is structural rather than a
matter of degree.**

A *recorded* departure is also non-conforming. R2 reports conforming only when a
session was both registered and delegated, and a session that departed was
neither. So recording changes nothing about the outcome the check prints. Worse,
R1's admissibility clause forbids the check from counting the conflict ledger as
evidence at all — the ledger is written by a tool call the evaluated session
issued, which is precisely the class R1 excludes. The record can never upgrade
an outcome, and it should not be able to.

That is fine as far as it goes: a conflict record is not supposed to buy
conformance. But it means R10's stated teeth reduce to "the outcome is the same
either way," which gives an agent no reason at the moment of decision to spend a
tool call on the record. The field incident is an agent that had the judgment and
did not use it. A rule whose only consequence is an outcome the departure already
produced does not address that agent.

**What actually bites is the coupling to R3's refusal.** R5 requires the refusal
to name "the sanctioned alternative for that target," and the design drivers
already state that a gate without a sanctioned bypass makes an agent that can
neither delegate nor edit resolve the bind privately — manufacturing a new silent
failure in place of the old one. The conflict record is that bypass. An armed
orchestrator that hits the refusal has exactly two doors: delegate the issue, or
record the conflict and proceed. Recording lifts the refusal for the remainder of
the session; it never lifts non-conformance.

That gives recording a reason to exist at the moment of decision, and it keeps
R18 clean: the departure stays available to the agent, it just cannot be silent.
Nothing here asserts skills outrank session instructions — the agent that reads
its instruction as binding still wins, it simply wins in writing.

**Is that gameable?** The stated driver is that a predicate satisfiable by one
honest command is dangerous because it "leaves a record falsely attesting the
loop ran." That objection does not transfer. The cheat code here produces a
visible confession pushed to the author on a user-facing channel and written into
the permanent commit body, and the run is still reported non-conforming. An agent
that learns "record a conflict and you may proceed" has learned the behavior the
requirement wants.

**This couples decision 4 to decisions 2 and 3 and needs cross-validation.**
Whether a recorded conflict lifts the refusal is a property of the gate, which
decisions 2 (arming) and 3 (registration and the operator switch) own. My
recommendation is that it does, scoped to the session and to the target class
named in the refusal, and that decision 3's operator switch and this bypass stay
distinct mechanisms — the switch is for an operator who thinks the enforcement is
wrong, the bypass is for an agent that thinks this particular step is wrong.

## Rejected options and why

- **`koto overrides record` as the vehicle.** Exits 1 with no workflow
  (re-confirmed). Also asks for a gate name a non-gate conflict does not have.
- **`koto decisions record` as the sole vehicle.** Same workflow-name
  dependency; kept as the in-loop mirror.
- **A `wip/` file.** Deleted before merge; committed references to `wip/` paths
  are forbidden workspace-wide. `/execute`'s own D5 convention already routes
  durable notes away from it.
- **`docs/decisions/` as the primary home.** Durable and nearly pre-authorized,
  but it turns a curated index of six architectural decisions into a run-event
  log. Left available as a human escalation.
- **Extending the work-summary ledger to hold the record.** Wrong keying (PR
  URL), wrong durability (tmpfs by default), wrong gate (five-minute interval).
  Its emission path is kept; its storage is not.
- **In-session surfacing only.** Named and rejected in the PRD's own decision
  block: it relies on the author being present, which for a dispatched run they
  are not.
- **A new dedicated hook registration for conflict surfacing.** New distribution
  for reach that work-summary's three registrations already provide.
- **Publishing the record to a new remote surface (an issue, a gist).** Outside
  `/execute`'s closed write-target set, needs the R9 amendment `SKILL.md:411-415`
  defers, and the PRD puts off-machine travel of the conformance record out of
  scope. The PR body reaches the same reader from inside the set.

## Assumptions

1. **niwa's work-summary registration is a dependency this decision inherits.**
   Surfacing via those three hooks reaches adopters who use niwa. An adopter
   installing shirabe as a bare plugin gets the durable local record and the PR
   block but not the ambient emission, unless decision 3's skill-frontmatter
   registration also carries it. Decision 3 should confirm.
2. **A dispatched run reaches a PR.** Both incidents did. A departing run that
   never opens one leaves only the local record, and the author learns of it from
   the check rather than from the PR.
3. **`/execute`'s closed write-target set can be read as already covering a
   conflict block in the home PR body.** The set names "the home PR /
   coordination body via `gh`" without restricting which sections may be
   written. If a reviewer reads it more narrowly, this becomes a set amendment —
   a small one, and still not a new target class.
4. **The refusal message can name the conflict command.** R5 requires a
   sanctioned alternative per target; this assumes "record a conflict" is an
   acceptable alternative to name alongside "delegate this issue."
5. **`XDG_STATE_HOME` is durable on adopter machines.** Standard, but a
   container that mounts `~/.local/state` as tmpfs would defeat it. The PR block
   is the off-machine copy that survives that case.

## Open questions

1. **Does a recorded conflict lift the R3 refusal?** My recommendation is yes,
   session-scoped. Decisions 2 and 3 own the gate and must ratify. If they say
   no, R10's teeth reduce to the outcome-neutral case described above and the
   requirement should be re-examined rather than shipped as written.
2. **Does the conflict record survive into a coordinated run?** R7's coordinated
   path has no koto session at all, so the mirror never fires and there is no
   single home PR — there is a coordination PR. Whether the block goes there, and
   how F1's existing redaction interacts with a conflict block in a body F1
   already governs, is unresolved. Cross-check with decision 1, which owns R7.
3. **Where does the conflict block sit relative to PB2?** The PR-body rule
   requires exactly one top-level bare `---`. A fenced block in Part 1 is fine,
   but the block's own formatting must not introduce a second separator. The
   `--conflict-record` validate mode should test this jointly with `--pr-body`.
4. **Do subagents write to the parent's conflict ledger?** The ledger is keyed by
   session id. If a `/work-on` child hits a conflict, whether it records under its
   own id or the parent's decides whether the parent's PR block sees it. This is
   the same session-id-inheritance question decision 3 must answer for hooks; the
   answers should match.
5. **Should the record carry the plan and the issue it departed from?** R11 names
   three fields. A fourth — which issue was being implemented — would make the
   record far more useful to a reviewer, at the cost of going past the
   requirement. Worth raising with the author rather than deciding here.
