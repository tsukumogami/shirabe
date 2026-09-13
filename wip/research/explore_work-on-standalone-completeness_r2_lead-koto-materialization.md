# Lead: When koto materializes a child workflow, does the child run through the skill's SKILL.md prose at all, or does koto seed the child session's state directly from the template?

## Findings

**1. `materialize_children` never spawns a process, prompt, or agent. It writes a state file.**

The real work happens in `init_child_core` (`src/cli/init_child.rs:481-628`), reached
from `init_child_from_parent` / `init_child_from_parent_at`
(`src/cli/init_child.rs:339-379`), which the batch scheduler calls once per task
entry. The function:

1. Compiles the child's template (`compile_with_cache`, `src/cli/init_child.rs:492`)
   — for `/execute`, this is `work-on.md`, named as the hook's `default_template`.
2. Resolves `--var`-style variables against *that* template's own `variables:` block
   (`src/cli/init_child.rs:507-519`).
3. Builds a `StateFileHeader` (`src/cli/init_child.rs:555-582`) and two events —
   `WorkflowInitialized { template_path, variables, spawn_entry }` and
   `Transitioned { from: None, to: initial_state, condition_type: "auto" }`
   (`src/cli/init_child.rs:584-608`) — where `initial_state` is the compiled
   template's own `initial_state` (`src/cli/init_child.rs:521-524`).
4. Commits both events atomically via `backend.init_state_file(child_name, header,
   initial_events)` (`src/cli/init_child.rs:625-627`).

There is no `Command::new`, no subprocess, no prompt string, no reference to
"skill", "SKILL.md", or "slash command" anywhere in this path — or anywhere in
koto's source at all: `grep -rl "SKILL.md\|slash_command\|ClaudeCode" src/` returns
zero files. koto has no concept of a Claude Code skill. It knows only: templates
(markdown+YAML files it compiles), sessions (state files it writes events to), gates,
and evidence. The `materialize_children` hook (`src/template/compile.rs:355-420`,
`SourceMaterializeChildrenSpec` at `src/template/compile.rs:72-…`) is a pointer to
another **template file**, not to a skill.

This settles the core question: **koto seeds the child session's state directly at
the template's entry state**, from disk-level data (`WorkflowInitialized` +
`Transitioned{to: initial_state}` events), not by constructing a prompt that would
cause an agent to invoke `/work-on` and load `work-on/SKILL.md`.

**2. What actually drives the child forward, and what prose it sees.**

koto is a passive state machine — something else has to call `koto next
<child-session>` on each tick. In shirabe's `/execute`, that something is
documented explicitly in `skills/execute/SKILL.md` under **Team Shape**: *"Single-agent
parent — no team is spawned at the `/execute` layer. In single-pr, the per-issue
children are koto-materialized `/work-on` single-issue workflows on the shared
branch."* No Task/subagent dispatch, and no `/work-on` slash-command invocation, is
described anywhere in `/execute`'s Phase Execution or Single-PR Execution Path
sections (`skills/execute/SKILL.md:130-295`) for driving a materialized child —
the orchestrator's own loop ticks `spawn_and_await`
(`skills/execute/koto-templates/execute.md:289-310`), which carries the
`materialize_children` hook, and cross-issue context is shuttled with `koto context
get/add` (`skills/execute/references/cross-issue-context.md`), not with any skill
invocation.

On koto's side, what an agent receives per tick is exactly two template-sourced
fields: `directive` and `details`. These come from splitting the template's markdown
**body** (not the frontmatter) per `## <state>` heading
(`extract_directives`, `src/template/compile.rs:632-672`): everything before an
optional `<!-- details -->` marker becomes `directive`, everything after becomes
`details` (`split_directive_details`, `src/template/compile.rs:677-690`). `koto
next`/`koto status` substitute variables into both and hand them back verbatim:
`response["directive"] = substitute(&state.directive)` /
`response["details"] = substitute(&state.details)` (`src/cli/mod.rs:5942-5944`).
These are fields of the **compiled `work-on.md` template** — the same file
`/work-on`'s own runs use — never anything sourced from `work-on/SKILL.md`.

`work-on/SKILL.md` itself is long prose (Definition of Done, Finalization and No
Silent Deferral, label-vocabulary routing, etc. — `skills/work-on/SKILL.md:1-100`+)
that exists purely as a Claude Code skill file, loaded only when the Skill-loading
mechanism for `/work-on` fires (a slash-command / Skill-tool invocation). koto has no
way to reach it, and per Finding 1, nothing in `/execute`'s dispatch path invokes
`/work-on` as a skill for its children — round 1 of this same exploration already
established this from the shirabe side (`execute.md:302-305`,
`wip/explore_..._findings.md` insight 5: *"`/execute` does not invoke `/work-on` as
a skill. They share one template file."*). This round confirms it from koto's
engine: koto's only surface for reaching an agent is `directive`/`details` text
compiled straight from `work-on.md`'s markdown body, and koto has no reference to
`SKILL.md` anywhere in its source to route through even if something wanted it to.

Reference files cited from directive prose (e.g.
`skills/work-on/references/phases/phase-2.5-worktree-discipline.md`, which
`execute.md:563` tells the agent to read for the per-child worktree-discipline
check) are **not loaded by koto** in any form — koto only ever reads the *template*
source file to compile it (`std::fs::canonicalize` + `compile_cached`,
`src/cli/init_child.rs:176-224`); nothing in the compiler, the gate evaluator, or the
`next`/`status` handlers opens a path mentioned inside directive text. Whether such a
file gets read is entirely up to the agent's own behavior (a Read tool call it
chooses to make, or skips).

**3. Evidence gates versus prose, mechanically — koto enforces schemas and command
exit codes, nothing about whether prose was read.**

- **`accepts` schema.** `validate_evidence` (`src/engine/evidence.rs:45-91`) checks,
  without short-circuiting: every submitted key is declared in `accepts`
  (unknown fields rejected, `src/engine/evidence.rs:64-70`), every `required` field is
  present (`src/engine/evidence.rs:74-80`), and every present field's JSON type
  matches its schema (`validate_field_type`, `src/engine/evidence.rs:96-…`). A
  failure returns `EvidenceValidationError`, which the CLI (`src/cli/mod.rs:4260-4272`)
  turns into `NextErrorCode::InvalidSubmission` and a non-zero exit — the submission
  is rejected outright; no event is appended, no state advance happens.
- **`gates`.** `evaluate_gates` (`src/gate.rs:67-…`) runs every declared gate
  (`type: command` spawns a shell command and records its exit code;
  `context-exists`/`context-matches` check the context store;
  `children-complete` is the batch-completion check) and never short-circuits, so a
  caller sees every blocking condition at once. Transition resolution
  (`resolve_transition`, `src/engine/advance.rs:1228-1310`) treats a `when:` clause
  referencing `gates.<name>.exit_code` as ordinary dot-path evidence: if the
  submitted/derived evidence doesn't satisfy any conditional `when`, and the state has
  no permissive unconditional fallback (or `gate_failed` is true), the result is
  `TransitionResolution::NeedsEvidence` — the tick returns without advancing
  the state, surfaced to the agent as a blocked/gate-blocked status (tests:
  `gate_blocked_stops_loop`, `failing_command_gate_without_override_produces_gate_blocked`,
  `src/engine/advance.rs:2098`, `4525`). A non-zero-exit command gate is exactly this
  case: the run cannot cross the transition until either passing evidence is
  submitted or an explicit override happens.

What this buys over prose: a state with `accepts`/`gates` **cannot** be crossed by
merely asserting completion — the engine mechanically rejects malformed/missing
evidence and blocks on a failing gate. There is no equivalent mechanism for anything
that lives only as SKILL.md text: nothing stops an agent from skipping a whole
SKILL.md section, because koto never sees SKILL.md at all (Finding 2), and even for
prose inside the *template's own* `directive`/`details`, koto has no gate type that
verifies "the agent read this paragraph" or "the agent opened this referenced file"
— the four gate types are exhaustively `command`, `context-exists`,
`context-matches`, `children-complete` (`GATE_TYPE_*` constants,
`src/gate.rs:14-16`); nothing checks file-read provenance.

**4. `--no-cleanup` and terminal-state context retention — symmetric between success
and failure terminals.**

`finish_terminal_tick` (`src/cli/mod.rs:2674-2723`, called from both the advance-loop
completion path and the directed `koto next --to <terminal>` path,
`src/cli/mod.rs:5449`) runs the same sequence regardless of whether the terminal is a
success or a failure state:

1. Re-reads events, computes `outcome = project_terminal_outcome(compiled,
   final_state)` (`src/cli/mod.rs:2390-2402`) — this only classifies the terminal as
   `Failure` / `Skipped` / `Success` (from the state's own `failure:` /
   `skipped_marker:` frontmatter fields) to shape the synthesized `WorkflowResult`
   payload, not to decide whether cleanup runs.
2. Synthesizes and appends the result to the child's own log (skipped entirely when
   `no_cleanup` is true: `let has_result = if no_cleanup { false } else {
   append_request_store_result_to_child(...) }`, `src/cli/mod.rs:2697-2701`).
3. Promotes the result onto a bound leg (`promote_leg_result`) — this one step runs
   even under `--no-cleanup`, per the comment at `src/cli/mod.rs:2660-2665`, because a
   parked session's requester still needs its answer.
4. `if no_cleanup { return; }` (`src/cli/mod.rs:2715-2717`) — everything after this
   line is skipped when `--no-cleanup` is passed.
5. Otherwise: appends the terminal-index entry, appends `ChildCompleted` to the
   parent, and — if neither append had to be deferred for retry —
   `backend.cleanup(name)` (`src/cli/mod.rs:2719-2723`).

`cleanup` on the local backend is `fs::remove_dir_all(&dir)`
(`src/session/local.rs:85-90`) — it deletes the entire session directory: state
file, event log, and context store. Nothing in `finish_terminal_tick` branches on
`TerminalOutcome::Failure` vs `Success` before calling `cleanup`; the same
delete-on-terminal behavior applies to a clean success terminal and a `failure: true`
terminal alike. `--no-cleanup` is the only lever that preserves the on-disk record in
either case (and additionally skips the terminal-index and parent-`ChildCompleted`
writes, deferring them to a later, explicit tick against the parked session — see
the "Why only step 3 is hoisted" comment at `src/cli/mod.rs:2657-2668`).

**5. Template composition — confirmed absent in the engine.**

`SourceFrontmatter` (`src/template/compile.rs:14-27`) — the top-level YAML
frontmatter struct the compiler deserializes — has exactly five fields: `name`,
`version`, `description`, `initial_state`, `variables`, `states`. There is no
`include`, `extends`, `base`, or `import` field, and no code anywhere in
`src/template/compile.rs` (or elsewhere in `src/`) that reads a second template file
and merges its states into the one being compiled — `grep -rn
"\binclude\b|\bextends\b|\binherit\b|\bimport\b" src/template/` matches nothing
relevant (only unrelated doc-comment prose). `SourceState` (which nested per-state
fields live under) *is* `#[serde(deny_unknown_fields)]`
(`src/template/compile.rs:44-47`), so an author who tried to write an `extends:`-like
key at the state level would get a compile-time error rather than silent adoption —
reinforcing that no such mechanism was ever wired in, even partially.

The only cross-template linkage the engine has at all is `materialize_children`'s
`default_template` (and per-task template overrides): this spawns a **wholly separate
child session** — its own state file, its own event log, its own `initial_state`
entry point (Finding 1) — not an inclusion of the child template's states into the
parent's compiled state graph. The parent and child remain two independent
state machines linked only by `parent_workflow` in the header
(`src/cli/init_child.rs:560`) and the `children-complete` gate type. This confirms
round 1's conclusion ("templates cannot include/inherit/delegate") directly from the
compiler, not from its absence in shirabe.

## Implications

The diagnosis under test — "the finishing obligations exist as prose in `SKILL.md`
and reference files, which an agent may skip, rather than as koto states with
evidence gates, which it cannot" — is **too weak** for `/execute`'s materialized
children specifically. It frames the defect as a skippable-prose problem, which
implies the fix is "move the prose into gated states, wherever it lives." But for a
child spawned via `materialize_children`, `work-on/SKILL.md`'s prose (Definition of
Done language, finalization checklist, label-vocabulary routing, etc.) is not
reachable at all in that code path — not "read but ignorable," but structurally
absent, because nothing in `/execute`'s single-agent dispatch loop or in koto itself
ever triggers a `/work-on` skill load for a child. The only prose a materialized
child's driving agent ever sees is `work-on.md`'s own `directive`/`details` text per
state (Finding 2) plus whatever reference files that text happens to point at and the
agent happens to choose to open (Finding 2, unenforced).

This means: any finishing obligation that exists *only* in `work-on/SKILL.md` prose
(not mirrored into `work-on.md`'s per-state `directive`/`details`, and not enforced
by an `accepts`/`gates` block on some state in that template) is unreachable for
`/execute`'s children on every run, not merely skippable on some runs by an
inattentive agent. Round 1's Direction 3 ("move `/work-on`'s finishing obligations
out of skippable prose into koto states with evidence gates") is the right shape of
fix for exactly this reason: it is the *only* kind of fix that reaches
`/execute`-spawned children at all, since koto states/gates are the one channel both
entry points (`/work-on`'s own SKILL.md-driven runs and `/execute`'s
skill-independent, template-only runs) share. A fix that adds obligations purely to
`work-on/SKILL.md` prose would improve standalone `/work-on` runs while leaving
`/execute`'s children exactly as they are today.

## Surprises

- koto is *entirely* unaware of Claude Code skills as a concept — not merely
  "doesn't read SKILL.md by default," but has zero code referencing skills, slash
  commands, or prompt construction anywhere in its ~source. Every "the agent does X"
  behavior in a koto-driven workflow is externally supplied by whatever process is
  issuing `koto next`/`koto init` calls; koto's job ends at handing back
  `directive`/`details` JSON and validating what comes back.
- `--no-cleanup`'s effect is broader than "keeps the state file": it also skips the
  terminal-index write and the parent's `ChildCompleted` notification (step 5), not
  just the child-log result append and `remove_dir_all`. A `--no-cleanup` terminal
  is genuinely parked mid-protocol, not just "not yet garbage collected."
- The `details` field (post-`<!-- details -->` prose) is explicitly *not* delivered
  by default on `koto next` in every case — `src/cli/mod.rs:5900-5910`'s comment
  says `koto status` always returns the full instructions "regardless of the
  delivery rule `koto next` applies," implying `koto next` itself can deliver a
  reduced form (e.g., `directive` only, or a first-line synopsis per the
  `first_line(&state.directive)` call at `src/cli/mod.rs:1762`) in some situations.
  This wasn't chased further; see Open Questions.

## Open Questions

- Exactly which `koto next` responses (vs. `koto status`) omit `details`, and under
  what condition — the comment at `src/cli/mod.rs:5900-5910` implies `koto next` has
  its own "delivery rule" distinct from `koto status`'s always-full return, but I
  did not trace that rule's exact conditions (I read `src/cli/mod.rs` around lines
  4700-4900 and 5900-5960 only; the delivery-rule logic likely lives in
  `next_types.rs` or another section of `mod.rs` between those windows).
  This matters only at the margin: even the fuller `koto status` form is still
  template-sourced `directive`/`details`, never `SKILL.md` prose, so it doesn't
  change this lead's core finding.
- Whether any *other* orchestration path in shirabe (outside `/execute`) invokes
  `koto init`/`materialize_children` against a target template while *also*
  separately dispatching a Task/subagent that loads that skill's own SKILL.md (which
  would make the child dual-sourced: SKILL.md prose from the fresh agent's skill
  load, plus koto's directive/details). I only inspected `/execute` and `/work-on`;
  I did not survey `/scope`, `/plan`, or other skills' koto templates for a
  different materialization pattern that might combine both channels.
- I did not verify whether koto's cloud backend (`src/session/cloud.rs`) changes any
  of the terminal-cleanup or materialize_children mechanics versus the local backend
  beyond `cleanup` also calling `sync_delete_session` (`src/session/cloud.rs:694-698`)
  — plausible but not separately confirmed for `/execute`'s actual deployment.

## Summary

koto's `materialize_children` (`init_child_core`, `src/cli/init_child.rs:481-628`) seeds a child session by writing `WorkflowInitialized` and `Transitioned{to: initial_state}` events straight from the compiled child template — it never constructs a prompt, spawns a process, or references SKILL.md anywhere in its source, and `/execute`'s own "single-agent parent, no team spawned" design confirms the same agent drives each child by reading koto's `directive`/`details` text (compiled from `work-on.md`'s markdown body) rather than by invoking `/work-on` as a skill. The main implication is that the enforcement-altitude diagnosis is too weak for this code path: any finishing obligation living only in `work-on/SKILL.md` prose is not skippable but structurally unreachable for `/execute`'s children, so only fixes that land in `work-on.md`'s own gated states (not SKILL.md) reach both entry points. The open thread is the exact `koto next` vs `koto status` delivery-rule difference for `details`, which I didn't fully trace but which doesn't change the core finding since both are template-sourced, never SKILL.md-sourced.
