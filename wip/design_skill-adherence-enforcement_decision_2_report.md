# Decision 2 — The arming signal

**Question.** What signal identifies a session as performing plan-scale execution
in the orchestrator role, such that R3's write refusal arms?

**Classification.** Critical (Tier 4). The signal decides when an unbypassable
`PreToolUse` deny fires in sessions that run under `bypassPermissions` with no
human available to appeal. A false positive stalls autonomous work with no
recourse; the PRD (R8) explicitly buys down that risk by accepting false
negatives.

---

## Evidence gathered

Everything in this section was measured, not read off documentation. Two headless
`claude -p` runs (v2.1.233) with a `PreToolUse` command hook that dumped its stdin
produced the findings below; the harness was deleted afterward.

### E1. The exact `PreToolUse` input contract

From the binary's common-input builder (`function my(e,t,r,n)` at v2.1.233):

```
session_id, transcript_path, cwd, prompt_id, permission_mode, agent_id, agent_type, effort
```

plus `hook_event_name`, `tool_name`, `tool_input`, `tool_use_id`. Confirmed live:

| Call site | `agent_id` | `agent_type` | `session_id` | `transcript_path` |
|---|---|---|---|---|
| Main thread (`Agent` tool call) | `null` | `null` | `fe02a511-…` | main session `.jsonl` |
| Inside spawned subagent (`Read`) | `ade62eeca6ec312f3` | `general-purpose` | `fe02a511-…` (same) | main session `.jsonl` (same) |

**Independently reproduced.** The team lead ran a separate probe
(`wip/design_skill-adherence-enforcement_probe_subagent_hooks.md`) with a
different registration method (`--settings`), a different tool (`Write`), and a
different scenario, and got the same three fields with the same presence pattern:
`agent_id` and `agent_type` present on the subagent's invocation, absent entirely
on the parent's, same `session_id` for both. My run registered the hook through a
project `.claude/settings.json` instead and observed identical behavior, so the
finding holds across two registration paths and two observers. Where my run
reports `null` and the lead's reports "absent", these are the same observation —
my probe applied a `jq` default to a missing key.

That probe also found that a hook registered in a plugin's `hooks/hooks.json`
loaded via `--plugin-dir` did **not** fire — but the lead has since corrected
that result: plugin-declared hooks *do* fire when the plugin is installed
normally (`superpowers` is the live proof), so the `--plugin-dir` finding is a
fact about the dev-loading path, not about plugin hooks. Decision 3's
plugin-declared placement stands. What remains open is narrower and does touch
me: whether plugin hook registration completes before the first tool call in a
`-p` session whose opening move is a write. If it does not, an AC11 session's
*first* out-of-set write escapes — which is the one write AC11 names.

Decision 3 also confirmed from the binary that **skill-frontmatter hooks do not
fire inside subagents** (`Aat` resolves the lookup key to `agentId`, with a
parent-key fallback for one built-in subagent type), whereas settings and plugin
hooks are pushed without reference to that key. That closes off the one placement
where a structural child exemption would have come for free — and R4 disqualifies
it anyway, since a skill-frontmatter hook exists only after the skill is invoked.

Three consequences, all load-bearing:

1. **`agent_id` is absent on the main thread and present inside any subagent.**
   This is a harness-supplied bit. No tool call the session issues can produce or
   suppress it.
2. **`session_id` does not distinguish a subagent from its parent.** Any signal
   keyed on session identity treats an orchestrator and its delegated child as
   the same session.
3. **`transcript_path` always points at the *main* session transcript**, even when
   the hook fires inside a subagent. The subagent's own transcript is *not*
   handed to the hook.

### E2. The session's own inbound prompt is readable at the first tool call

Measured on the very first `PreToolUse` of a fresh session: `transcript_path`
already existed, held 10 records, and its first `type: "user"` record contained
the complete verbatim task prompt (a marker token planted in the prompt was
found 3 times). The same held on the `Agent` call and inside the subagent.

This is the fact that makes any "what was this session asked to do?" signal
implementable at all, and it holds at the moment of the first write — which is
what AC11 requires.

Corroborated on a real dispatched (background) session: the top-level transcript
for job `4d06ff3a` opens with the full task brief written by the dispatching
agent. A `niwa dispatch` worker's brief is on disk and readable before its first
tool call.

### E3. A subagent's own brief is reachable, by a derivable path

Subagent transcripts live at:

```
<dirname(transcript_path)>/<session_id>/subagents/agent-<agent_id>.jsonl
```

Every component comes from the hook input. Verified live: at the subagent's first
tool call the file already existed at exactly that path. Inspection of real
subagent transcripts shows record shape
`{"isSidechain":true,"agentId":"…","type":"user","message":{...}}` whose first
user record is the verbatim dispatch brief, alongside a sibling
`agent-<agent_id>.meta.json` carrying `agentType`, `taskKind`, `spawnDepth`,
and `permissionMode`.

This was not in the prior hook-surface inventory and it changes the answer. It
means the enforcement can read *the brief the agent under evaluation actually
received*, whether that agent is a main thread or a subagent.

### E4. Cost is not a constraint (R16)

Against a real 4.1 MB transcript, ten iterations each:

| Operation | per call |
|---|---|
| `head -c 65536` + `grep` | ~2 ms |
| full-file `grep` (no early exit) | ~2 ms |
| `jq` process startup floor | ~4 ms |

A hook doing a `jq` parse plus a full transcript scan lands around 10 ms — an
order of magnitude under R16's 100 ms p95 budget. Reading the transcript is free;
this removes cost as a reason to prefer a cheaper but weaker signal.

### E5. Fail-open works, including for background subagents

A prior research note warned that "in non-interactive mode, a background
subagent's tool call with no hook decision is denied." Measured: a `PreToolUse`
command hook returning `{}` did **not** deny — a subagent's `Read` succeeded under
`-p --permission-mode bypassPermissions`, and a subagent's `Write` succeeded under
`-p` in default permission mode. Caveat on the second run: the tool was named in
`--allowed-tools`, so the permission layer was not the binding constraint. The
narrow claim I will stand behind is that **returning `{}` from a command-type
`PreToolUse` hook is a genuine no-op in a non-interactive subagent**, which is
what R8/R17/AC15/AC16 need.

### E6. What PLAN documents do and do not carry

`docs/plans/PLAN-*.md` frontmatter carries `schema: plan/v1`, `status`, and
`execution_mode ∈ {single-pr, multi-pr, coordinated}`. Issue outlines carry
Goal and Acceptance Criteria. They carry **no structured list of file paths**:
`references/issues-table.md:53` asks authors to "mention specific files" in
prose, and the `shirabe plan outlines` envelope consumed by `plan-to-tasks.sh`
emits `{name, vars, waits_on}` only. This kills candidate 2 outright.

### E7. Delegated children share the orchestrator's branch

`skills/execute/koto-templates/execute.md`: "Children receive `SHARED_BRANCH` and
commit directly to it without creating their own branches." The orchestrator and
every delegated child write from the same branch. This kills candidate 3 on AC10.

---

## The options

### Option A — inbound-brief plan-scope signal *(chosen)*

Arm when all three hold, each evaluated independently and each failing open:

**Clause A — select the right brief.** Use `agent_id` to choose which transcript
holds *this agent's own* inbound instructions: absent → `transcript_path`;
present → `<dirname(transcript_path)>/<session_id>/subagents/agent-<agent_id>.jsonl`
(E1, E3). If the selected file is missing or unparseable, do not arm.

**Clause B — plan-scale execution in the orchestrator role.** Scan only the
records the agent *received* — `type: "user"` records that are not tool-result
payloads — for a reference matching `(docs/plans/)?PLAN-[a-z0-9-]+\.md`. Require
the referenced file to exist under `cwd`'s repo and its frontmatter to carry
`schema: plan/v1`. Do not arm when the same inbound brief carries a single-issue
delegation marker (an issue number or outline anchor together with
`SHARED_BRANCH`, or a `parent_orchestration:` sentinel). Do not arm when
`execution_mode` is `coordinated` (R7's carve-out has no single orchestrator) or
`multi-pr` (outside `/execute`'s scope, per its Input Modes section).

**Clause C — out-of-set write.** R3's third conjunct: the target falls outside
`/execute`'s declared closed write-target set (Security Considerations point 2),
and is not the referenced PLAN document or another artifact of its own chain.

The property the signal actually measures is: **the unit of work named in this
agent's own inbound instructions is a whole PLAN rather than one of its issues.**
Thread position selects which brief to read; it is not itself the role test.

#### Evaluation order, and why it matters

Decision 3 chose a plugin-declared hook, so registration is **unconditional**:
the not-armed answer runs on every `Write`/`Edit` in every session on the
machine, not only in shirabe repos. The predicate must therefore be ordered
cheapest-first and bail at the first clause that fails.

| Step | Cost | Bails when |
|---|---|---|
| 0. Tool matcher `Write\|Edit\|NotebookEdit` | zero (harness-side) | any other tool |
| 1. `docs/plans/` exists under the repo containing `cwd`, and holds a `PLAN-*.md` | one `stat` + one `readdir`, sub-ms | **the overwhelmingly common case** — no plans directory |
| 2. `tool_input.file_path` is outside the declared closed set | string only, no I/O | write is in-set (AC9) |
| 3. Select and scan the agent's own transcript | ~2 ms (E4) | no inbound PLAN reference |
| 4. Read the referenced PLAN's frontmatter | one small file read | not `schema: plan/v1`, or `coordinated`/`multi-pr` |

Step 1 is the load-bearing early-out and it is deliberately placed before the
transcript read: a machine-wide hook spends its time overwhelmingly in repos that
have no plans at all, and one `stat` disposes of those. Worst case — a real
plan-scale repo — is ~10 ms of predicate work against Decision 3's measured
~94 ms of remaining R16 headroom.

**Retracted: I argued the predicate should ship inside the existing
`shirabe pr-body-hook` adapter to avoid doubling process startup. The premise was
wrong.** That hook is registered with `"matcher": "Bash"` and nothing else
(`niwa/internal/workspace/materialize.go:838`, verified); the adherence gate
matches `Edit|Write|MultiEdit|NotebookEdit`. The matchers are **disjoint**, so no
tool call ever triggers both and the per-tool-call cost R16 measures is one
process either way. There is no doubled fixed cost to recover, and merging would
put the adherence gate on the `Bash` matcher — the precise footgun niwa documents
at `materialize.go:592-606`, where a hook matching *every* Bash command bricks
every session if the binary goes stale. Two subcommands, two matchers. Decided,
not open.

### Option B — `agent_id` / `agent_type` absence alone as the orchestrator test

Arm on main-thread writes whenever a PLAN is in play. Simplest possible rule,
free to compute, and unforgeable. This is the reading the lead's probe reaches:
"`agent_type` present means delegated child, absent means orchestrator."

I agree with the probe's measurement and disagree with that inference, on one
specific ground: **it silently assumes delegation always happens through the Task
tool.** Absence of `agent_type` does not mean "orchestrator" — it means "not a
subagent of this process". If `/execute`'s per-issue children are dispatched as
separate `claude` processes (the shape `niwa dispatch` uses, and the shape the
coordinated path's per-repo work implies, since each repo is worked in its own
worktree), then every delegated child is a main thread with no `agent_type`, and
AC10 fails on every delegated write — the exact false positive R8 is written to
avoid. The probe cannot see this because it only ever spawned a Task subagent.

Its own Limits section makes the compatible point from the other direction: the
absence test should be "a positive check on a known field rather than an
open-world assumption". Option A retains `agent_id` as the *transcript-selection*
rule, where it is a reliable routing key and no assumption about the delegation
substrate is needed, and puts the role test on the unit of work named in the
agent's own brief instead.

### Option C — arm on skill/workflow state (candidates 4 and 5)

Arm on the presence of `wip/execute_<topic>_state.md`, or on a registered koto
orchestration session bound to the PLAN.

### Option D — arm on branch name `impl/<slug>` (candidate 3)

### Option E — arm on write-target ∩ files the PLAN's outlines name (candidate 2)

---

## Chosen option and rationale

**Option A.** Tied to the acceptance criteria:

- **AC11 (the arming case)** — a session handed plan-scale work by another agent
  that never invoked the skill. The dispatching agent's brief is the first user
  record of the worker's transcript and is readable before the worker's first
  tool call (E2, verified on a real dispatched session). Clause B fires off that
  brief with no skill invocation anywhere in the chain, which is exactly what R4
  demands. This is the criterion that eliminates Options C and D.
- **AC10 (delegated child permitted)** — the child's own brief names one issue,
  not the plan as a unit, so clause B's single-issue exclusion stands the check
  down. Because clause A routes to the *child's own* transcript (E3), this holds
  whether the child is a Task subagent or a separately dispatched session. This
  is the criterion that rules out Option B standing alone.
- **AC15 (fail-open on non-plan-scale work)** — a session whose inbound records
  never name a resolvable PLAN never arms. Restricting the scan to received
  records rather than the whole transcript is what keeps a session that merely
  *read* a PLAN file (a tool result) or *mentioned* one (an assistant record)
  out of scope. Every clause fails open on a missing file, a parse error, or an
  unresolvable reference, satisfying R8.
- **R16** — ~10 ms against a 4 MB transcript (E4), well inside the 100 ms budget.
- **R6/AC14** — no longer an inference. Decision 3's plugin-route probe observed
  a deny land under permission-bypassing mode with neither target file created,
  and the deny reason returned to the model as tool-error text verbatim **in both
  the subagent and the parent role**. That is R5's steerable reason and AC13's
  next-attempt correction observed rather than assumed.
- **AC11 timing** — also settled by that probe: a plugin-declared hook fires on
  the session's *first* tool call, against a prompt whose opening move was a
  write. AC11 names the first out-of-set write as the one that must be refused,
  so this was load-bearing and it holds.
- **R1 admissibility** — worth stating explicitly because it is easy to
  misapply: R1 constrains the *determination*, not arming. Clause A's `agent_id`
  is harness-supplied and inadmissible-proof; clause B reads the agent's inbound
  instructions, which the agent under evaluation did not author. Neither clause
  reads output of a script the session ran.

**Arming and determination must not share evidence.** This is the structural
reason candidate 5 is not merely circular but harmful. The determination (R1/R2)
asks "was a koto orchestration session registered?" Arming asks "should this
session have registered one?" A never-registered run — the target case — has no
session, so keying arming on registration inverts the requirement. They are
disjoint by construction and the DESIGN should keep them so.

---

## Rejected options

**Option B alone** — see above. Its failure mode is conditional on a fact I could
not settle: how koto-materialized `/work-on` children are actually driven in
Claude Code (see Open Questions). Option A does not depend on that fact.

**Option C (state file / registered session)** — fails AC11 by construction. The
state file is written in `/execute` Phase 0 and the koto session in Step 2, so a
session that never invoked the skill has neither, and arming would be exactly
backwards: present only where enforcement is least needed. The state file is also
session-produced and removable with one `rm`.

**Option D (branch `impl/<slug>`)** — two independent hard failures. AC11: the
branch is created by `orchestrator_setup`, so a never-invoked session is not on
it. AC10: children commit directly to the same `SHARED_BRANCH` (E7), so the
branch cannot distinguish orchestrator from delegated child in either direction.
It also arms on any human who names a branch `impl/*`.

**Option E (write target ∩ plan-named files)** — not computable. PLAN outlines
carry no structured file list, and the outline envelope that feeds
`plan-to-tasks.sh` carries `{name, vars, waits_on}` only (E6). A prose grep for
paths inside outline bodies would be both lossy and forgeable.

**`agent_type` as a role discriminator** — rejected. It is `null` on the main
thread, which is precisely where the orchestrator sits, and elsewhere it names a
*subagent type* (`general-purpose`), not a role. It cannot separate a `/work-on`
execution child from a research agent. `agent_id` presence/absence is the usable
bit; `agent_type` is useful only for telemetry. `permission_mode` and `cwd` are
useful for AC14 evidence and repo scoping respectively, not for arming.

---

## Adversarial case against the chosen option

Per instruction, the strongest attacks I can construct. Two of these succeed.

**Attack 1 — the plan-authoring session that also touches source. This one
lands.** An author hands a dispatched session: "revise `docs/plans/PLAN-foo.md`,
and fix the off-by-one in `crates/shirabe-validate/src/table.rs` while you're
there." Clause A: main thread. Clause B: the inbound brief names a resolvable
`single-pr` PLAN, no single-issue marker. Clause C: the `crates/` write is
outside the closed set and is not the PLAN itself. **Armed, refused, legitimate
work blocked with no human present.** No path rule separates this write from an
orchestrator implementing an issue inline, because at the filesystem level they
are the same write. The refusal is steerable and R15's operator switch exists,
but in a dispatched session the agent's only sanctioned move is to enter
`/execute`, which is wrong for a typo fix. This is the real cost of the design
and the DESIGN must decide what session-local escape exists (see Open Questions).

Decision 3's plugin-declared placement **widens this**. Registration is
unconditional and machine-wide, so this false positive is no longer confined to
shirabe repos: it fires in any repository the user works in that happens to carry
a `docs/plans/PLAN-*.md`, including repos whose authors never adopted shirabe's
workflow and for whom "enter `/execute`" is not a meaningful instruction. The
early-out ordering above keeps the *cost* negligible in those repos; it does
nothing about the *refusal* once a plan file is present. This raises rather than
lowers the priority of open question 2.

**Attack 2 — the brief that inlines the work. This one lands too.** A
coordinating agent writes "implement these six things:" and pastes the issue
bodies without naming the PLAN path. Clause B finds no reference; the session is
never armed; every out-of-set write proceeds. **AC11 as literally written is
missed for this sub-case.** R8 blesses false negatives, so this is compliant, but
the DESIGN must not claim AC11 is closed in general — it is closed for handoffs
that name the plan, which is the shape `niwa dispatch` produces and the shape the
BRIEF's journey 2 describes, and it is open for handoffs that inline the work.

**Attack 3 — clause A collapses if `/execute` drives children inline.** If the
per-issue child is not a separate agent at all but the same main thread walking
the child workflow, clause A selects the orchestrator's transcript, clause B
fires, and the child's legitimate source writes are refused. I judge this
outcome *correct* rather than a false positive — a run that implements in the
main thread is by definition not delegated, and R2/AC4 already call it
non-conforming — but it means enabling the refusal could break `/execute`'s
current working path. Verification is a prerequisite, not a nicety.

**Attack 4 — nested subagents.** A `/work-on` child spawns its own analysis agent
(`skills/work-on/references/phases/phase-3-analysis.md:19` does exactly this).
Clause A routes to the grandchild's own brief, which names one issue's analysis.
Not armed. Correct — no defect.

**Attack 5 — compaction and resume.** Transcripts are append-only per session id,
and the 4 MB transcript I inspected still carries its first user record at the
head after many turns. I did not test a session that actually compacted, nor one
resumed under a new session id after `/clear`. If either drops the inbound brief,
the session silently disarms mid-run. Fail-open, so R8-compliant, but it is a
silent loss of coverage and belongs in Known Limitations.

**Attack 6 — the disarm marker is forgeable.** Clause B stands down on a
single-issue delegation marker in the inbound brief. An orchestrator cannot forge
its *own* inbound record (it is written by the harness from what it was handed),
so this is not self-serving in the ordinary case. But an agent that dispatches a
subagent can write whatever brief it likes, so it can hand itself an escape by
spawning a child with a fake single-issue marker and implementing there. That
child is then a genuine delegated session doing one issue's work, which is the
sanctioned shape — so the "attack" produces conforming behavior. I could not turn
this into a real defeat.

**One note on R4 that a reviewer will raise.** The single-issue delegation marker
is shirabe-authored, so it looks like the signal depends on shirabe's own
workflow. It does not: R4 constrains what makes the system *arm*, and the marker
only makes it *stand down*. An unmarked handoff of a whole plan still arms.

---

## Assumptions

1. `/execute`'s per-issue children are dispatched as distinct agents (Task
   subagents or separate sessions), not driven inline by the orchestrator thread.
   Attack 3 is the consequence if this is false. **Not verified — see Open
   Questions.**
2. A plan-scale handoff normally names the PLAN document path. Supported by the
   `niwa dispatch` flow and by the BRIEF's journey 2; Attack 2 is the residue
   when it is false.
3. `transcript_path` remains the main session's transcript for subagent hook
   invocations, and the `subagents/agent-<agent_id>.jsonl` layout is stable.
   Measured on v2.1.233 only; it is an undocumented internal path.
4. Reading the transcript is permitted and non-disruptive. It is a plain file
   read; nothing observed suggests otherwise.
5. The refusal is delivered by a `type: "command"` `PreToolUse` hook registered
   through a path that actually fires, and registration completes before the
   session's first write. **Both halves now confirmed**: settings registration by
   two independent probes (mine via project `.claude/settings.json`, the lead's
   via `--settings`), and plugin registration through the supported
   `claude plugin init` load path by Decision 3, which also observed the hook fire
   on the session's *first* tool call. A `prompt`- or `agent`-type hook
   additionally needs `continueOnBlock: true` or a deny ends the turn instead of
   correcting it (v2.1.210 behavior change).

---

## Interfaces with other decisions

### Interface 1 — the arming component is the determination's liveness witness

Cross-validation raised this and it lands on me. Decision 1 established that
absence of a koto registration record is *not* evidence of non-registration (a
fully delegated eight-child run predates the binary that started writing the
record). The resolution is that my component, which observes tool calls in band,
proves by its own log that the enforcement stack was live while the session ran.

**Requirement as stated:** write a durable per-session entry whenever a tool call
is evaluated, armed or not; the determination treats its absence as
`indeterminate` rather than `non-conforming`.

**How I would satisfy it, with one amendment.** A per-*tool-call* append is more
than the requirement needs and more than the budget wants: it would fsync on
every `Write`/`Edit` in every session on the machine and grow without bound. The
property Decision 1 actually needs is liveness over the session, which is
**one write-once entry per session**, keyed by `session_id`, carrying the
component's contract version and a first-seen timestamp. Cost collapses to a
single file create per session; growth is one small file per session.

**Placement in the ladder matters and is not arbitrary.** The witness must be
written *after* step 1 (the `docs/plans/` `stat`) so it does not fire in every
repo on the machine, and *before* steps 2-4 so it records evaluations that did
**not** arm — which is the whole point of it. That placement gives exactly the
right scope: a witness exists for every session that ran in a repo capable of
hosting plan-scale execution, armed or not.

**It is admissible.** The witness is written by the hook process, not by any tool
call the session issued, so R1's exclusion does not reach it. Worth stating
explicitly, because a durable file that appears during a session is exactly the
shape of thing R1 is written to exclude, and a reviewer will check.

Co-locating it with Decision 4's conflict store under `$XDG_STATE_HOME/shirabe/`
lets the determination read one root.

### Interface 3 — the write-target set must be a readable artifact

Agreed, and it constrains my clause C directly. Clause C currently says "outside
`/execute`'s declared closed write-target set", which today is prose in
`skills/execute/SKILL.md` Security Considerations point 2. Two components now
need to evaluate it mechanically, so the DESIGN owes a declaration format. Until
that exists, clause C is specified against English, which is the one part of my
predicate that is not yet implementable as written.

---

## Open questions the DESIGN must carry

1. **How are koto-materialized `/work-on` children actually driven in Claude
   Code?** `koto`'s spawn primitive is a stub and the dispatch substrate is left
   to the harness; `koto-user/SKILL.md:110` refers to "a dispatched subagent",
   which suggests the Task tool, but I found no shirabe-side instruction naming
   the mechanism. There are three possible answers and they have different
   consequences: **Task subagent** (Option B and Option A both work);
   **separate `claude` process** (Option B breaks AC10, Option A holds, since the
   child's own brief names one issue); **inline on the main thread** (Attack 3 —
   Option A refuses, which I argue is correct but which would change `/execute`'s
   current path). The coordinated path is suggestive of the second: each repo is
   worked in its own worktree on its own branch, which a Task subagent sharing
   the parent's cwd does not naturally do. **Blocking for implementation, not for
   the design shape** — Option A is the right shape under all three.
2. ~~**What session-local escape exists for Attack 1?**~~ **Resolved with
   Decision 3.** The escape is R10's recorded-conflict route (Decision 4's
   vehicle): in-band, per-session, no configuration, available with no human
   present. No new mechanism. The DESIGN must add one thing — **the refusal
   reason has to name that route**, so it is discoverable at the moment it is
   needed rather than documented elsewhere. R15's global switch is not the answer
   here and stays global. Decision 3 also correctly bounds the population my
   Attack 1 exposes: step 4 of the ladder requires `schema: plan/v1`, so an
   unrelated `docs/plans/PLAN-*.md` does not arm, and repos with no
   `docs/plans/` at all die at the step-1 `stat`. The exposed set is shirabe
   adopters doing mixed work, not the machine.

   The tension still worth stating plainly in the DESIGN: any session-local
   escape is by definition session-produced, so the refusal is a speed bump plus
   an audit trail rather than a sandbox. That is defensible — R2 gives it teeth by
   making an unrecorded departure non-conforming — but it should be claimed
   honestly rather than discovered later.
3. **Should `niwa dispatch` stamp a machine-readable plan reference into the
   briefs it writes?** This closes Attack 2 at its source, and the BRIEF already
   locates journey 2's entry point upstream of the worker ("the omission happens
   while the brief is being written"). It is a supplement, not a replacement — a
   bare `claude -p` handoff is not covered — and it sits at the placement
   boundary the PRD's first Decision left open.
4. **Does the inbound brief survive compaction and resume?** Untested (Attack 5).
   Failure is fail-open, so this is a coverage question rather than a safety one,
   but the answer belongs in Known Limitations.
5. **Which tools does the hook match?** Writes issued through `Bash` are already
   out of scope per the PRD's Known Limitations. The matcher should name
   `Write|Edit|NotebookEdit` explicitly rather than `*`, both to keep the blast
   radius legible and to avoid arming on reads.
6. ~~**Does plugin hook registration complete before the first tool call?**~~
   **Closed affirmatively by Decision 3's probe**, through the supported
   `claude plugin init` load path, against a prompt whose opening move was a
   write. AC11's first-write criterion is safe.
7. ~~**Should the arming predicate live in the `pr-body-hook` adapter?**~~
   **Closed: no.** I proposed it on cost grounds and the premise was wrong — that
   hook matches `Bash` only, mine matches the edit tools, so the matchers are
   disjoint and one process runs per tool call either way. Merging would also put
   the gate on the `Bash` matcher, the documented brick-every-session footgun.
8. **What does the transcript scan cost late in a very long armed run?** My 2 ms
   figure is against a 4.1 MB transcript; an armed plan-scale session rescans on
   every write and the file grows all run. Raised by Decision 3 against AC28.

   **My first proposal — memoize the verdict per session — was wrong on two
   counts, both caught by Decision 3, both accepted.**

   *Cache the arming determination, never the whole verdict.* Clause C is a
   property of the write's target path, not of the session. AC9 requires an
   in-set write permitted in the same session where an out-of-set write is
   refused, and AC12 requires two different targets to carry different reason
   text. A session-level cached verdict breaks both outright. Only the
   transcript-derived clauses (A, B, the single-issue exclusion) and the PLAN
   frontmatter read are cacheable; clause C runs per call.

   *The single-issue-marker exclusion is not monotone.* I raised this as a thing
   to check and the answer is no. An author re-scoping mid-session — "actually,
   just do issue 3" — appends a later inbound record whose delegation marker
   should **disarm**. A frozen cache stays armed, which is stricter-when-stale,
   cuts against R8's fail-open direction, and produces exactly the false refusal
   Attack 1 is about.

   **Resolution (Decision 3's fix, plus two guards).** Persist a byte offset and
   rescan only the tail on each call, rather than freezing a result. Clause B
   stays monotone in the append direction; the exclusion gets to fire late. O(new
   bytes) per call, so transcript growth leaves the budget. Two guards the
   implementation needs:

   - **Store `(byte_offset, state_at_that_offset)` as an atomic pair**, and
     re-fold from whichever pair is read. Hooks for one event run in parallel, so
     two concurrent processes can race the cache; with the pair invariant any
     stale read costs a redundant rescan over a superset and can never produce a
     wrong answer. Without it, re-folding a carried state from an earlier offset
     double-applies.
   - **Reset to `(0, initial)` when the file is shorter than the stored offset**,
     so truncation or replacement re-derives instead of reading from a bogus
     position.
