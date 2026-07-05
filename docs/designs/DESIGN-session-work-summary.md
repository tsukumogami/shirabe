---
schema: design/v1
status: Planned
upstream: docs/prds/PRD-session-work-summary.md
problem: |
  A session's real PR set must be surfaced as a standardized, findable block
  without relying on the agent to remember what it opened, and the machinery has
  to straddle the workspace's shirabe (skills, portable) and niwa (harness
  wiring) layer boundary without either layer duplicating the other's contract.
decision: |
  A single `shirabe work-summary` CLI subcommand owns capture (parsing PR identity
  from gh command output into a private per-session ledger), the gate, and
  rendering the block from the ledger plus live gh reads. The shirabe binary is
  already on PATH in provisioned instances, so thin dot-niwa hooks and the
  /inflight skill invoke `shirabe work-summary ...` directly — no path resolution
  needed — and display the block through systemMessage plus a neutral
  additionalContext echo; a dispatch-brief rule covers background workers. niwa
  owns only hook-registration hygiene (the materializer dedup fix and the
  SessionStart merge that lets an installed session_start hook survive
  ephemeral-session mode), not path injection. The cross-layer contract is the
  `shirabe work-summary` CLI surface plus a self-describing block, never a shared
  ledger schema.
rationale: |
  Every mechanical claim was validated against Claude Code 2.1.201 during a
  five-round exploration, including a working prototype. Putting the reusable
  logic in one shirabe component (invoked by both the hooks and /inflight) while
  niwa owns only registration keeps a single render implementation, respects the
  hooks-are-niwa boundary, avoids executing any script from the repo working tree,
  and keeps the agent out of the data path so the summary reflects real PR state.
---

# DESIGN: Session Work Summary

## Status

Planned

## Context and Problem Statement

The PRD requires a standardized, always-recoverable summary of a session's pull
requests that appears on state change, on return-after-absence, on demand, and
in a background worker's final message, and that reflects real PR state rather
than the agent's memory. The technical problem is threefold.

First, the summary must be **deterministic**: if the agent is responsible for
remembering which PRs it opened and reformatting them on cue, it will drift,
forget after a long session, and (as the exploration found) occasionally emit
fabricated PR references that pollute the harness's own footer and session-list
surfaces. The data path must be machinery, not discipline.

Second, the machinery must **straddle two repositories with different roles**.
In this workspace, hook wiring is niwa's responsibility — niwa materializes
`.claude/settings.json` hooks from a config repo (dot-niwa) — while shirabe is a
plugin that ships skills and is deliberately hook-free. A design that puts hooks
in shirabe would double-register against niwa-injected hooks; a design that puts
the user-facing command in niwa would strand it outside the skill system. The
split has to respect the boundary while keeping exactly one implementation of the
block so the two layers cannot drift.

Third, the harness constrains **how content can reach the user versus the
model**. Hooks can inject text the user sees (a user-channel message) and,
separately, text the model sees (added context); these are different channels
with different persistence and different failure modes, and one of them treats
imperative instructions as suspect. Background sessions have neither a live
footer nor a watching user, so their only durable surface is the transcript
itself.

The source PRD and the five-round exploration that preceded it settled the
approach empirically against Claude Code 2.1.201, including a working capture and
render prototype. This design records that architecture and the alternatives it
beat.

## Decision Drivers

- **Determinism over discipline.** The block's contents must come from real PR
  state captured mechanically, not from the agent's recollection (PRD R4, R5).
- **Respect the shirabe/niwa layer boundary.** Hooks are niwa's job; skills are
  shirabe's. The design must not put hooks in the plugin or the command outside
  the skill system.
- **One implementation, no shared schema.** The block spec and its renderer must
  live in exactly one place so the two layers cannot drift. A shared state-file
  schema between layers is a known failure mode in this workspace (a niwa Stop
  hook already reads a state schema shirabe stopped writing, and silently
  no-ops).
- **Signal over volume.** Emission must be tied to state change and to
  return-after-absence, never to a timer or per-turn cadence (PRD R6-R8), and
  the model-awareness cost must stay small (PRD R15).
- **Work in background sessions.** The user-facing display channel is invisible
  to dispatched workers; those must be covered through the transcript and final
  message (PRD R11).
- **Visibility safety.** Multi-repo collection must never surface a private-repo
  PR into a public-visibility summary (PRD R12).
- **Verified against the live harness.** The design commits only to hook and
  skill mechanics confirmed working on Claude Code 2.1.201.

## Considered Options

Each decision below was investigated during the upstream exploration; the
rejected options are real alternatives that were built or tested, not strawmen.

### Decision 1 — Which layer owns the pipeline

- **Option A: shirabe ships everything as a plugin (skill + `hooks/hooks.json`).**
  Portable to any workspace. Rejected: shirabe is deliberately hook-free, and a
  plugin-shipped hook double-registers against niwa-injected hooks for the same
  events with no dedup between the two channels — the exact duplicate-hook class
  the exploration confirmed is already live in this workspace. A
  settings-registered hook also cannot resolve the shirabe plugin cache path,
  which is version-unstable.
- **Option B: niwa/dot-niwa owns everything, including the on-demand command.**
  Single owner, no cross-layer contract. Rejected: the on-demand command belongs
  in the skill system so users invoke it as `/inflight`; burying it in a hook
  strands it from the surface users reach for.
- **Option C (chosen): split by concern, not by pipeline. shirabe ships one
  reusable capture/render implementation as a `shirabe work-summary` CLI
  subcommand; niwa/dot-niwa ships only the thin hook registration that invokes it,
  plus the display glue.** The distinction is that a hook bundles two separable
  things: the *registration* (which event fires it — workspace policy, so niwa's)
  and the *logic* (capture, ledger, render — reusable code, so shirabe's,
  alongside the `validate`/`transition` surfaces the `shirabe` binary already
  ships). Both the ambient hook path and the `/inflight` skill call the same
  subcommand, so there is exactly one render implementation. This preserves
  "shirabe is hook-free" as a precise statement — shirabe ships a *subcommand*, not
  a hook *registration* — while removing the two-copies drift the earlier "dot-niwa
  owns its own render script" framing would have introduced.
  - **Why the compiled CLI over bundled bash scripts.** The security-critical,
    determinism-focused logic (URL/flag-injection validation, the terminal
    sanitizer, the two-level gate, the `flock`'d ledger, and hook-JSON emission)
    lives in typed Rust rather than bash. Determinism is the feature's core
    thesis, and the fragile parsing/sanitizing belongs in compiled, tested code
    where a fixture suite can pin its behavior; the `render` path is also a
    "gh-backed live check," which is the CLI's sanctioned role (the same role
    `shirabe validate --merge-gate` already fills). Because the `shirabe` binary
    is already on PATH in provisioned instances — skills invoke `shirabe validate`
    and `shirabe transition` bare — the hooks and `/inflight` invoke
    `shirabe work-summary ...` directly. This removed the need for niwa to inject a
    resolved plugin *script* path entirely: a settings-registered hook that gets
    only `${CLAUDE_PROJECT_DIR}` could not self-locate a plugin script, but a
    binary on PATH has no path to resolve. The cross-layer contract is that CLI
    surface plus a self-describing block — never a resolved path and never a shared
    ledger schema.

### Decision 2 — Display channel

- **Option A: the agent prints the block in its normal reply text.** Simple, and
  it feeds the harness's native reference surfaces. Rejected as the primary
  channel: it re-introduces agent discipline into the data path (the failure
  mode Decision Driver 1 rules out) and costs context tokens on every emission.
  Retained in a narrow role — the background-worker final message (Decision 2's
  chosen path can't reach a dashboard row), where a model-authored block is the
  only option.
- **Option B: a persistent status line or configurable footer badges.** Always
  visible, zero context cost. Rejected as a deliverable: both are user-level
  settings the feature cannot ship, and both are invisible to background
  sessions. Documented as optional personal companions only.
- **Option C (chosen): the hook emits the block through two channels at once —
  `systemMessage` (user-visible, persisted in the transcript as a
  `hook_system_message` record, zero model-context cost) and a neutral-phrased
  `additionalContext` echo (model-visible, for conversational consistency).**
  Verified: both channels take effect from one hook emission; the user sees the
  block rendered dim-gray under the triggering tool call, and it survives
  `claude attach`, `claude logs`, and the transcript viewer. For background
  workers, the model-authored final-message block (Option A's retained role)
  carries the summary to the dashboard.

### Decision 3 — State source and session scoping

- **Option A: the agent maintains the PR list in its own memory / a
  markdown ledger it updates.** Rejected: fails under compaction and forgets in
  long sessions; this is the discipline dependency the design exists to remove.
- **Option B: reconstruct purely from `gh` at render time (author-scoped
  search).** No stored state. Rejected: `gh search prs --author` over-collects
  across sessions and, critically, can pull private-repo PRs into a
  public-visibility summary — a visibility violation (PRD R12).
- **Option C (chosen): a hook-maintained per-session ledger for scope, refreshed
  from live `gh` for status.** The PostToolUse hook extracts the PR URL from the
  `gh pr create` tool output mechanically and appends it to a ledger keyed by
  session id; the render script reads the ledger for the item set and refreshes
  each item's live state via `gh pr view`. The ledger answers "which PRs are
  this session's" (respecting visibility by construction — only PRs the session
  touched); live `gh` answers "what state are they in now" (PRD R4). The ledger
  is private to dot-niwa's hook and renderer; it is never a cross-layer schema.

### Decision 4 — Emission cadence

- **Option A: timer or turn-count digest.** Rejected during exploration: fires
  when nothing changed, and no surveyed tool uses timed in-transcript digests;
  turn-count fires at the worst moments.
- **Option B: emit on every PR-affecting tool call, ungated.** Rejected:
  parallel tool calls in one turn double-fire the hook, producing duplicate
  blocks; identical blocks train the user to ignore the marker.
- **Option C (chosen): event-gated plus return-after-absence, with a
  compaction repair.** A two-level gate keeps cost bounded (PRD R15): the cheap
  first level compares the ledger hash on every fire (no `gh` call); the
  expensive second level — recomputing the rendered-block hash, which requires
  live `gh` — runs only when the ledger changed or a render interval
  (`WS_RENDER_INTERVAL`) has elapsed, so a status-only flip is caught
  periodically rather than on every tool call. Emit both channels when either
  hash changes; emit on the first prompt after a configurable absence
  (`WS_ABSENCE_THRESHOLD`, default 30 min); emit `additionalContext` only after a
  compaction (`SessionStart` `compact` matcher) to repair model awareness without
  a redundant user-facing block; emit nothing otherwise. Every fire, including
  suppressed ones, refreshes `last_activity` so the absence timer stays accurate.
  State writes are `flock`-protected to survive the parallel-tool-call race.
  Measured cost: ~200 tokens per model-context echo, ~800 per realistic gated
  session.

### Decision 5 — Block format and marker

- **Option A: a GFM pipe table.** Best column alignment. Rejected: markdown-link
  cells render as terminal hyperlinks whose URLs do not survive a plain-text
  scrollback dump — defeating the "find the link later" goal — and bare-URL cells
  blow the table past terminal width.
- **Option B: always-sectioned (Renovate-style state sections).** Best at 10+
  items. Rejected as the default: at the typical 3-4 item scale it spends nearly
  one header per item.
- **Option C (chosen): a flat pipe-line block under a fixed literal marker
  `=== WORK IN FLIGHT ===`, one line per PR (`owner/repo#N | state-tokens |
  title | bare-URL`), attention-first ordering, terminal rows dropped after one
  post-transition appearance, with Renovate-style section headers added only
  above six items.** Bare URL last is load-bearing: it is the only form that
  survives scrollback search and wraps intact on narrow terminals. The marker is
  a literal string so both a human (scrollback search) and the dedup logic can
  grep for it — the same pattern the coordination PR body already uses.

## Decision Outcome

The chosen options compose into a deterministic pipeline whose logic lives in one
`shirabe work-summary` CLI subcommand, wired by thin niwa-owned hook
registrations:

- The **`shirabe work-summary` subcommand** (compiled into the on-PATH `shirabe`
  binary) is the single implementation of capture parsing, the ledger, the
  two-level gate, the renderer, and hook-JSON emission. Given a session id
  `capture` appends captured PRs, and `render` reads the ledger, refreshes each
  item via live `gh`, and prints the standardized block with a freshness line. Its
  `spec` mode is the format spec. It degrades to a ledger-only best-effort block
  when `gh` is unreachable.
- A **PostToolUse capture hook** (dot-niwa, thin) matches PR-affecting `gh`
  commands and calls `shirabe work-summary capture` directly (the binary is on
  PATH). The binary emits the rendered block through `systemMessage` and a neutral
  `additionalContext` echo when the gate passes; the hook is a pure pass-through
  and carries no JSON/nonce/fence logic.
- A **UserPromptSubmit hook** (dot-niwa, thin) calls `shirabe work-summary
  absence` on the first prompt after the absence threshold; a
  **SessionStart(compact) hook** calls `shirabe work-summary compact` to re-inject
  the model-context echo after compaction.
- A **`/inflight` skill** (shirabe) calls `shirabe work-summary render` and relays
  its output through dynamic command injection, falling back to a repo-scoped `gh`
  listing (fail-closed, following the same block spec) when live state is
  unreachable.
- A **dispatch-brief rule** (niwa rootskill / shirabe convention) requires a
  background worker's final message to carry the block, since the systemMessage
  channel does not reach a dashboard row.

This holds the PRD requirements, with two bounds stated honestly. The block is
standardized and identical across surfaces (R1-R2); ordered and terminal-dropping
(R3), which the ledger backs with a per-item `terminal_shown` marker so a
merged/closed PR appears in exactly one summary after transition and then drops;
live-derived (R4); real-PR-only by construction because the ledger only ever
holds captured-from-`gh` references (R5); event-gated with return-after-absence
and duplicate suppression (R6-R8); on-demand via `/inflight`, which stamps a
freshness line so R9's "indicate how fresh" is met; model-aware across compaction
(R10); present in a worker's final message (R11); and multi-repo visibility-safe
because per-session capture never reaches beyond the repos the session touched
(R12).

**Two acknowledged bounds.** (1) A GitHub-side CI or review status change (R6)
produces no hook event — PostToolUse fires only on the agent's own `gh` commands.
A status-only flip therefore surfaces at the next PR-affecting tool call, on
return-after-absence, or on an on-demand `/inflight`, not at the instant GitHub
changes; the `WS_RENDER_INTERVAL` second-level gate bounds the staleness. (2)
R1's uniform block shape holds across every emission because a single component
produces them all — the ambient hooks and `/inflight` invoke the same renderer.
Only the `/inflight` repo-scoped `gh` fallback (used when live state is entirely
unreachable) formats independently, and it follows the same block contract, so
the shape stays consistent even in that mode.

## Solution Architecture

### Components

| Component | Repo | Responsibility |
|-----------|------|----------------|
| `shirabe work-summary` CLI subcommand (`capture`, `absence`, `compact`, `render`, `spec`) | **shirabe** (compiled into the on-PATH `shirabe` binary) | **Single implementation** of capture parsing, ledger maintenance, two-level gate, rendering (block + freshness line + `spec`), and hook-JSON emission. Invoked bare (on PATH) by the dot-niwa hooks and by `/inflight` |
| capture hook (PostToolUse) | dot-niwa `.niwa/hooks/post_tool_use/`, thin | Match PR-affecting `gh` commands; `exec shirabe work-summary capture`. Pure pass-through; the binary emits the block on gate pass |
| return hook (UserPromptSubmit) | dot-niwa `.niwa/hooks/user_prompt_submit/`, thin | `exec shirabe work-summary absence` on first prompt after absence threshold; the binary emits the block |
| compaction hook (SessionStart, `compact` matcher) | dot-niwa `.niwa/hooks/session_start/`, thin | `exec shirabe work-summary compact` to re-inject the `additionalContext` block after compaction |
| session ledger | per-user runtime dir, keyed by session id | Private scope record: one row per PR (repo, number, URL, first-seen, `terminal_shown` flag). Written and read only by the `shirabe work-summary` subcommand. Not a cross-layer contract |
| gate state file | per-user runtime dir, keyed by session id | `flock`-protected: last-emitted ledger hash, last-rendered-block hash, last-render timestamp, `last_activity` timestamp. Every invocation (incl. suppressed) refreshes `last_activity` |
| `/inflight` skill | shirabe `skills/inflight/` | Call `shirabe work-summary render` and relay its output via `!` injection; repo-scoped fail-closed `gh` fallback |
| dispatch-brief final-message rule | niwa rootskill `dispatch` + shirabe convention | Require the block in a background worker's final message |

### Data Flow

```
gh pr create ─▶ PostToolUse hook (thin) ─▶ shirabe work-summary capture
                                                    │
                     append PR to ledger (flock) ───┤
                     read ledger ─▶ gh pr view ─────┤
                     two-level gate ────────────────┘
                                     │ changed
                                     ▼
        emit systemMessage (user) + additionalContext echo (model)

UserPromptSubmit (absence > threshold) ─▶ shirabe work-summary absence ─▶ both channels
SessionStart(compact) ────────────────▶ shirabe work-summary compact ─▶ additionalContext only
/inflight (user-invoked) ─────────────▶ shirabe work-summary render ─▶ relayed in reply
background worker completion ─────────▶ model authors final-message block
```

The dot-niwa hooks are pure pass-throughs: each execs `shirabe work-summary <mode>`
(the binary is on PATH) with a `command -v shirabe || exit 0` fail-safe guard. The
binary owns everything downstream, including hook-JSON emission — the hooks carry
no JSON, nonce, or fence logic.

### Cross-Layer Contract

The coupling between the two layers is deliberately minimal:

1. **A CLI surface**: the `shirabe work-summary` subcommand (`capture`, `absence`,
   `compact`, `render <session-id>`, `spec`), compiled into the on-PATH `shirabe`
   binary. Both the dot-niwa hooks and the `/inflight` skill invoke it bare — no
   path resolution, because the binary is already on PATH (skills invoke `shirabe
   validate`/`shirabe transition` the same way).
2. **A self-describing block**: whatever the subcommand prints, callers relay
   verbatim.

There is no shared ledger schema across layers — the ledger is internal to the
`shirabe work-summary` subcommand, which both writes and reads it. niwa needs no
knowledge of a component path at all; its only remaining role is hook-registration
hygiene (the materializer dedup fix and the SessionStart merge), not path
injection.

**Trust boundary.** The render logic ships in the compiled `shirabe` binary and
callers reach it through the on-PATH binary, so there is no execution of a script
from the repo working tree — the trust anchor is the installed binary itself (the
same trust basis as `shirabe validate`), not a file sitting in `.claude/` that a
malicious branch or checkout could have planted. This removes the
working-tree-execution surface (and the provenance-verification machinery it would
have required) entirely. A hook where `shirabe` is absent from PATH no-ops via its
`command -v shirabe || exit 0` guard, failing safe to no capture rather than
executing an untrusted fallback.

**Degradation.** When shirabe runs without niwa, the ambient hooks are absent but
`/inflight` still works from the plugin. When the hooks are registered but
`shirabe` is absent from PATH, they no-op via the `command -v` guard (fail-safe).
The
`/inflight` `gh` fallback is scoped to the current repo only — never an
author-scoped cross-repo search, which would over-collect private PRs into a
public context (the rejected Decision 3 Option B) — and applies F1 fail-closed
redaction to any item whose visibility it cannot confirm.

### Key Interfaces

- **Capture**: `shirabe work-summary capture` reads the PostToolUse stdin JSON
  (`tool_input.command` and `tool_response.stdout`), parses the PR URL from `gh pr
  create` output, and validates it against an anchored
  `^https://github\.com/<owner>/<repo>/pull/[0-9]+$` pattern (owner/repo per the
  F2 GitHub charset regex) before it reaches the ledger or any `gh` call —
  rejecting, not sanitizing, a non-match, and rejecting `git push`'s
  `/pull/new/` hint. The session id is validated against `^[A-Za-z0-9._-]+$`
  before composing any file path.
- **Render**: `shirabe work-summary render <session-id>` prints the block to
  stdout; exit 0 with a best-effort block when `gh` is unreachable.
- **Gate/state**: a `flock`-protected state file per session holds the
  last-emitted ledger hash, last-rendered-block hash, last-render timestamp, and
  `last_activity` timestamp. The subcommand modes share it: `capture` drives
  the ledger-hash and rendered-hash comparison; `absence` reads
  `last_activity` against `WS_ABSENCE_THRESHOLD`; both refresh `last_activity` on
  every fire including suppressed ones so the absence timer cannot be starved.
- **Ledger row**: repo, PR number, URL, first-seen timestamp, and a
  `terminal_shown` flag set when a merged/closed PR has appeared in its one
  post-transition summary (drives R3's drop-after-one-emission).
- **Display**: the binary emits stdout JSON carrying `systemMessage` and
  `hookSpecificOutput.additionalContext` in a single emission; the thin hook
  passes it through unmodified.

## Implementation Approach

0. **Prerequisites (niwa, sequence first).** Two niwa-side dependencies gate the
   hooks and are sequenced ahead of them: (a) the materializer duplicate-hook fix
   — a hook registered through both declared config and auto-discovery currently
   loses its matcher and fires on every tool call; (b) the SessionStart-merge fix
   — an installed `session_start` hook must survive ephemeral-session mode (the
   SessionStart provisioning hook must not clobber a registered work-summary
   `compact` hook). Neither prerequisite injects a path: the `shirabe` binary is
   already on PATH, so the hooks call `shirabe work-summary ...` bare. Where the
   plan cannot land a prerequisite first, the dependent hook is authored
   defensively (idempotent, tool-type tolerant) and fails safe via its `command -v
   shirabe || exit 0` guard.
1. **`shirabe work-summary` subcommand** (shirabe, Rust). The single
   implementation: capture parsing (anchored URL validation, session-id
   validation), ledger with `terminal_shown`, two-level gate (ledger hash /
   rendered hash / `WS_RENDER_INTERVAL`), renderer (marker, ordering,
   terminal-drop, freshness line, section escalation), the terminal-safety
   sanitizer, hook-JSON emission (systemMessage + neutral nonce-fenced
   additionalContext; `compact` is additionalContext-only), offline degradation,
   and per-user 0700 storage. `spec` is the format spec. Unit-test the capture
   regex and sanitizer against the fixture set.
2. **Thin capture hook** (dot-niwa). PostToolUse matcher on PR-affecting `gh`
   commands; pure pass-through: `exec shirabe work-summary capture`. The binary
   handles the dual-channel emission.
3. **Thin return + compaction hooks** (dot-niwa). UserPromptSubmit runs `exec
   shirabe work-summary absence` (the binary checks `WS_ABSENCE_THRESHOLD`);
   SessionStart(compact) runs `exec shirabe work-summary compact`.
4. **`/inflight` skill** (shirabe). Call `shirabe work-summary render` through `!`
   injection; repo-scoped fail-closed `gh` fallback;
   `disable-model-invocation: true`.
5. **Dispatch-brief rule** (niwa rootskill + shirabe convention). Final-message
   block requirement for background workers, with the same sanitization contract.

## Security Considerations

This feature processes untrusted, attacker-influenceable input — `gh` command
output and, most importantly, PR titles returned by `gh pr view` — and routes it
into a subprocess pipeline, a user-visible terminal channel, and the model's
context. It runs a compiled subcommand and reads PR state that may cross the
public/private visibility boundary. The controls below are load-bearing.

**Untrusted-input handling (capture + render).** The extracted PR URL is
validated against an anchored `^https://github\.com/<owner>/<repo>/pull/[0-9]+$`
pattern before it reaches the ledger or any `gh` call; a non-match is rejected,
not sanitized. This anchoring is load-bearing against `gh` flag-injection: the
`owner`/`repo` components are validated with the coordination contract's F2
GitHub charset regex, whose alphanumeric-first-character anchor prevents an
extracted component from being read as a `gh` flag. The session id is validated
against `^[A-Za-z0-9._-]+$` before composing any file path. Every `gh`-sourced
field — title and state, and any other field ever rendered — passes through a
**terminal-safety sanitizer** before entering the block. This is a distinct
control from the coordination contract's F3 (a markdown/HTML escaper for PR
bodies, which does not address terminals): here, control and ANSI bytes are
stripped first, then the title is truncated (strip-before-truncate, so a
multi-byte escape cannot survive by being split), newlines and `|` are removed,
and the literal `=== WORK IN FLIGHT ===` marker is forbidden inside any cell — so
a crafted title cannot forge rows, inject a second marker, or spoof the terminal.

**Shell / permission discipline.** Every `gh` invocation from the `shirabe
work-summary` subcommand uses an argv array (Rust `Command` args), never a shell
string; no extracted value is interpolated into `sh -c`, `eval`, or backticks.
Field extraction uses
`gh … --json/--jq` rather than stdout scraping, and no environment or token
byte is written to the ledger, block, or logs. The pipeline is read-only against
`gh` except for the agent's own triggering `gh pr create`.

**Model-context exposure.** The `additionalContext` echo carries only
structured fields (repo, number, state, URL); free-text PR titles are either
omitted from the model-facing echo or delimited as opaque untrusted labels, so a
PR title cannot act as a prompt-injection instruction. The neutral hook framing
governs the hook's own text, not embedded data.

**Supply-chain trust of the render code.** The render logic ships in the compiled
`shirabe` binary and every caller reaches it through the on-PATH binary (the same
trust basis as `shirabe validate`) — never from a script sitting in the repo
working tree. This eliminates the working-tree-execution surface: a `render-*.sh`
planted in `.claude/` by a malicious branch, PR checkout, or clone is never on the
execution path, so no per-file provenance-verification machinery is required. The
trust anchor is the installed binary itself. A hook where `shirabe` is absent from
PATH fails safe to no capture via its `command -v shirabe || exit 0` guard, never
to an untrusted alternative, and the `/inflight` `gh` fallback is read-only and
repo-scoped.

**Visibility (R12).** The primary path is safe by construction: the ledger holds
only PRs the session opened, so multi-repo collection never reaches beyond the
repos the session touched. The two residual paths are constrained: (1) the
`/inflight` `gh` fallback is scoped to the current repo only — never an
author-scoped cross-repo search — and applies F1 fail-closed redaction to any
item whose visibility it cannot confirm; (2) a dispatched worker's final-message
block redacts private-repo entries to opaque node id + state (F1) when the
destination surface is lower-visibility than the repo.

**Storage isolation.** The per-session ledger and `flock` state file live under
a per-user private directory (mode 0700, files 0600), opened with symlink-
following disabled, so one local session or user cannot read another's tracked
PR set from a predictable `/tmp` path.

**Residual risk.** The feature trusts the installed `shirabe` binary as the
render-code root and niwa's materializer as the hook-registration wiring; a
compromise of the binary distribution, the materializer, or of `GH_TOKEN` is out
of scope
and inherited from the harness. Prompt-injection defense on the ambient
path is best-effort: sanitization and field-restriction reduce but do not
eliminate the possibility that adversarial PR text influences the model's
narrative, so no security decision is delegated to model interpretation of block
contents. The background-worker final-message path is a distinct, explicit
residual: there the model itself authors a dashboard-bound block from
attacker-influenceable PR titles, so the same sanitization contract applies to
that authored block, and the title-restriction (structured fields preferred over
free text) is the mitigation of record.

## Consequences

### Positive

- The summary is deterministic: it reflects real captured PR state, not agent
  memory, and cannot emit a fabricated PR reference.
- One implementation of the capture/render logic (the `shirabe work-summary`
  subcommand) serves every surface — the ambient hooks and `/inflight` — so the
  two layers cannot drift, while registration/policy stays cleanly in niwa.
- The render code ships in the compiled binary and never executes from the repo
  working tree, so there is no planted-script surface and no per-file provenance
  machinery to build or trust; typed security-critical logic replaces fragile
  bash.
- Zero model-context cost for the user-facing display (systemMessage), with a
  small bounded echo (~200 tokens) only when there is news.
- Works in background sessions through the transcript and final message.
- Degrades cleanly: offline → best-effort block; shirabe-without-niwa → `/inflight`
  only; `shirabe`-absent-from-PATH → hooks no-op (fail-safe).

### Negative / Trade-offs

- The deterministic display (systemMessage) does not reach the Agent View session
  list row, only the drilled-in transcript; the list-row PR chip stays outside
  the feature's control.
- The design depends on undocumented harness behavior (systemMessage persistence,
  additionalContext-in-`-p`, identical-command hook dedup) verified only at
  Claude Code 2.1.201; a harness upgrade could shift it. Mitigation: the
  mechanics are isolated in the `shirabe work-summary` subcommand and thin hooks,
  re-verifiable in one place.
- Two niwa prerequisites: the materializer duplicate-hook fix, and the
  SessionStart-merge fix (so an installed `session_start` hook survives
  ephemeral-session mode). No path injection is needed. Until both land, hooks must
  be idempotent, tool-type tolerant, and fail-safe via the `command -v shirabe`
  guard.
- The dot-niwa hook depends on the `shirabe` binary being on PATH. The binary is
  resolved fresh from PATH on every run, so a plugin/binary version bump leaves
  nothing stale to refresh; a hook where `shirabe` is absent fails safe to no
  capture.
- The background-worker path relies on the model authoring its final message
  correctly — the one place agent discipline remains, mitigated by the
  dispatch-brief rule making it a required instruction.

### Mitigations

- Isolate all harness-version-sensitive mechanics in the `shirabe work-summary`
  subcommand and thin hooks for single-point re-verification.
- Sequence the materializer dedup fix and the SessionStart-merge fix as
  prerequisites in the plan, or author hooks defensively against the current
  behavior.
- Keep the block spec co-located with the single subcommand implementation so no
  second source of truth can drift.
