---
schema: design/v1
upstream: docs/prds/PRD-session-work-summary.md
status: Proposed
problem: |
  A session's real PR set must be surfaced as a standardized, findable block
  without relying on the agent to remember what it opened, and the machinery has
  to straddle the workspace's shirabe (skills, portable) and niwa (harness
  wiring) layer boundary without either layer duplicating the other's contract.
decision: |
  A dot-niwa PostToolUse hook captures PR identity from gh command output into a
  private per-session ledger; a single render script recomputes the block from
  the ledger plus live gh reads and displays it through the hook's systemMessage
  channel while echoing a neutral-phrased copy through additionalContext for
  model awareness. shirabe ships only a thin /status skill that relays the same
  render script, plus a dispatch-brief rule for background workers. The
  cross-layer contract is a well-known script path and a self-describing block,
  never a shared ledger schema.
rationale: |
  Every mechanical claim was validated against Claude Code 2.1.201 during a
  five-round exploration, including a working prototype. The split follows the
  existing architectural boundary (niwa owns hooks, shirabe owns skills),
  version-matches the block spec to its single implementation, and keeps the
  agent out of the data path so the summary reflects real PR state rather than
  recollection.
---

# DESIGN: Session Work Summary

## Status

Proposed

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
  in the skill system so users invoke it as `/status`; burying it in a hook
  strands it from the surface users reach for.
- **Option C (chosen): layered — dot-niwa owns the deterministic pipeline
  (capture hook, render script, ledger, display), shirabe owns the conversational
  surface (`/status` skill, dispatch-brief rule).** The render script is the
  single implementation; `/status` probes its well-known materialized path. The
  cross-layer contract is that path plus a self-describing block — never a shared
  schema.

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
  compaction repair.** Emit both channels when the ledger hash or the rendered
  block changes (a PR opened, merged, or its CI/review flipped), and on the first
  prompt after a configurable absence (default 30 min); emit `additionalContext`
  only after a compaction (`SessionStart` `compact` matcher) to repair model
  awareness without a redundant user-facing block; emit nothing otherwise. State
  writes are `flock`-protected to survive the parallel-tool-call race. Measured
  cost: ~200 tokens per model-context echo, ~800 per realistic gated session.

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

The chosen options compose into a deterministic pipeline owned by dot-niwa with a
thin conversational surface in shirabe:

- A **PostToolUse capture hook** (dot-niwa) matches PR-affecting `gh` commands,
  extracts the PR reference from the command's output, and appends it to a
  per-session ledger. It then invokes the render script and, when the gate
  passes, emits the rendered block through `systemMessage` and a neutral
  `additionalContext` echo.
- A **render script** (dot-niwa, the single implementation) reads the ledger,
  refreshes each item via live `gh`, and prints the standardized block. Its
  `--help`/header is the format spec. It degrades to a ledger-only best-effort
  block when `gh` is unreachable.
- A **UserPromptSubmit hook** (dot-niwa) emits the block on the first prompt
  after the absence threshold; a **SessionStart(compact) hook** re-injects the
  model-context echo after compaction.
- A **`/status` skill** (shirabe) relays the render script's output via dynamic
  command injection, probing the well-known materialized script path and falling
  back to a model-driven `gh` listing when the script is absent.
- A **dispatch-brief rule** (niwa rootskill / shirabe convention) requires a
  background worker's final message to carry the block, since the systemMessage
  channel does not reach a dashboard row.

This holds every PRD requirement: the block is standardized and identical across
surfaces (R1-R2), ordered and terminal-dropping (R3), live-derived (R4),
real-PR-only by construction because the ledger only ever holds captured-from-`gh`
references (R5), event-gated with return-after-absence and duplicate suppression
(R6-R8), on-demand via `/status` (R9), model-aware across compaction (R10),
present in a worker's final message (R11), and multi-repo visibility-safe because
per-session capture never reaches beyond the repos the session touched (R12).

## Solution Architecture

### Components

| Component | Repo | Responsibility |
|-----------|------|----------------|
| `capture-work-in-flight.sh` (PostToolUse) | dot-niwa `.niwa/hooks/post_tool_use/` | Extract PR ref from `gh pr create` output; append to ledger; invoke renderer; emit block on gate pass |
| `work-summary-return.sh` (UserPromptSubmit) | dot-niwa `.niwa/hooks/user_prompt_submit/` | On first prompt after absence threshold, invoke renderer and emit block |
| `work-summary-compact.sh` (SessionStart, `compact` matcher) | dot-niwa `.niwa/hooks/session_start/` | Re-inject `additionalContext` block after compaction |
| `render-work-in-flight.sh` | dot-niwa, materialized to `.claude/hooks/render-work-in-flight.local.sh` | Single render implementation: ledger + live `gh` → block; gate logic; `--help` is the spec |
| session ledger | runtime dir, keyed by session id | Private scope record (repo, PR number, URL, first-seen). Hook writes, renderer reads. Not a cross-layer contract |
| `/status` skill | shirabe `skills/status/` | Relay the render script's output via `!` injection; `gh` fallback when absent |
| dispatch-brief final-message rule | niwa rootskill `dispatch` + shirabe convention | Require the block in a background worker's final message |

### Data Flow

```
gh pr create ──▶ PostToolUse hook ──▶ extract PR ref ──▶ append to ledger (flock)
                                                              │
                          ┌───────────────────────────────────┘
                          ▼
   render script: read ledger ──▶ gh pr view (live state) ──▶ format block
                          │
          gate: ledger-hash or rendered-hash changed?
                          │ yes
                          ▼
        emit systemMessage (user) + additionalContext echo (model)

UserPromptSubmit (absence > threshold) ─▶ render ─▶ emit both channels
SessionStart(compact) ────────────────▶ render ─▶ emit additionalContext only
/status (user-invoked) ───────────────▶ render script via ! injection ─▶ relayed in reply
background worker completion ─────────▶ model authors final-message block
```

### Cross-Layer Contract

The only coupling between dot-niwa and shirabe is:

1. **A well-known path**: shirabe's `/status` probes
   `${CLAUDE_PROJECT_DIR}/.claude/hooks/render-work-in-flight.local.sh` (the
   `.local` infix is mandatory — niwa's file materializer forces it).
2. **A self-describing block**: whatever the script prints, `/status` relays
   verbatim.

There is no shared ledger schema. The ledger format is internal to dot-niwa's
hook and renderer. When shirabe runs without niwa, `/status` degrades to a
**repo-scoped** `gh` listing (never an author-scoped cross-repo search, which
would over-collect private PRs into a public context — the rejected Decision 3
Option B behavior); when niwa runs without shirabe, the ambient display still
works and only the `/status` command is missing.

**Required control — script provenance.** `/status` executes the probed
`render-work-in-flight.local.sh` only after verifying niwa's materialization
fingerprint. The `.local` path is a naming convention, not a trust boundary: a
file planted at that path by a malicious branch, PR checkout, or clone must not
be executed. When the fingerprint is absent or mismatched, `/status` fails
**closed to the repo-scoped `gh` fallback**, not to executing the file, and
confirms the resolved path stays within the project root.

### Key Interfaces

- **Capture**: PostToolUse stdin JSON provides `tool_input.command` and
  `tool_response.stdout`; the hook parses the PR URL from `gh pr create` output
  and validates it against an anchored
  `^https://github\.com/<owner>/<repo>/pull/[0-9]+$` pattern (owner/repo per the
  F2 GitHub charset regex) before it reaches the ledger or any `gh` call —
  rejecting, not sanitizing, a non-match, and rejecting `git push`'s
  `/pull/new/` hint. The session id is validated against `^[A-Za-z0-9._-]+$`
  before composing any file path.
- **Render**: `render-work-in-flight.sh <session-id>` prints the block to stdout;
  exit 0 with a best-effort block when `gh` is unreachable.
- **Gate/state**: a `flock`-protected state file per session holds the
  last-emitted ledger hash, rendered-block hash, and last-activity timestamp.
- **Display**: hook stdout JSON carries `systemMessage` and
  `hookSpecificOutput.additionalContext` in a single emission.

## Implementation Approach

1. **Render script + block format** (dot-niwa). Port the validated prototype:
   ledger read, `gh pr view` refresh, block formatting with the marker, ordering,
   terminal-drop, section escalation, and offline degradation. Its `--help` is
   the format spec. Unit-test the capture regex against the fixture set.
2. **Capture hook + ledger + gate** (dot-niwa). PostToolUse matcher on
   PR-affecting `gh` commands; `flock`-protected ledger append and gate state;
   dual-channel emission with neutral additionalContext phrasing.
3. **Return + compaction hooks** (dot-niwa). UserPromptSubmit absence check;
   SessionStart(compact) re-injection.
4. **`/status` skill** (shirabe). Injection-line probe of the well-known path;
   `gh` fallback; `disable-model-invocation: true`.
5. **Dispatch-brief rule** (niwa rootskill + shirabe convention). Final-message
   block requirement for background workers.
6. **Prerequisite coordination**: the niwa materializer duplicate-hook fix (a PR
   registered through both declared config and auto-discovery loses its matcher)
   is upstream of hooks shipped this way; the plan sequences it first or the
   hooks are authored to tolerate the current behavior (idempotent, tool-type
   tolerant).

## Security Considerations

This feature processes untrusted, attacker-influenceable input — `gh` command
output and, most importantly, PR titles returned by `gh pr view` — and routes it
into a shell pipeline, a user-visible terminal channel, and the model's context.
It also executes a materialized script and reads PR state that may cross the
public/private visibility boundary. The controls below are load-bearing.

**Untrusted-input handling (capture + render).** The extracted PR URL is
validated against an anchored `^https://github\.com/<owner>/<repo>/pull/[0-9]+$`
pattern (owner/repo per the F2 GitHub charset regex) before it reaches the
ledger or any `gh` call; a non-match is rejected, not sanitized. The session id
is validated against `^[A-Za-z0-9._-]+$` before composing any file path. Every
`gh`-sourced field (title, state) is sanitized per F3 before entering the block:
control/ANSI bytes stripped, newlines and `|` removed, title length truncated,
and the literal `=== WORK IN FLIGHT ===` marker forbidden inside any cell — so a
crafted title cannot forge rows, inject a second marker, or spoof the terminal.

**Shell / permission discipline.** Every `gh` invocation in the hook and render
script uses an argv array, never a shell string; no extracted value is
interpolated into `sh -c`, `eval`, or backticks. Field extraction uses
`gh … --json/--jq` rather than stdout scraping, and no environment or token
byte is written to the ledger, block, or logs. The pipeline is read-only against
`gh` except for the agent's own triggering `gh pr create`.

**Model-context exposure.** The `additionalContext` echo carries only
structured fields (repo, number, state, URL); free-text PR titles are either
omitted from the model-facing echo or delimited as opaque untrusted labels, so a
PR title cannot act as a prompt-injection instruction. The neutral hook framing
governs the hook's own text, not embedded data.

**Supply-chain trust of the render script.** `/status` executes the probed
`render-work-in-flight.local.sh` only after verifying niwa's materialization
fingerprint/provenance; the `.local` path is a naming convention, not a trust
boundary, and a file planted by a malicious branch or clone must not be
executed. If the fingerprint is absent or mismatched, `/status` fails closed to
the read-only, repo-scoped `gh` fallback rather than executing the file, and
confirms the resolved path stays within the project root.

**Visibility (R12).** The primary path is safe by construction: the ledger holds
only PRs the session opened, so multi-repo collection never reaches beyond the
repos the session touched. The two residual paths are constrained: (1) the
`/status` `gh` fallback is scoped to the current repo only — never an
author-scoped cross-repo search — and applies F1 fail-closed redaction to any
item whose visibility it cannot confirm; (2) a dispatched worker's final-message
block redacts private-repo entries to opaque node id + state (F1) when the
destination surface is lower-visibility than the repo.

**Storage isolation.** The per-session ledger and `flock` state file live under
a per-user private directory (mode 0700, files 0600), opened with symlink-
following disabled, so one local session or user cannot read another's tracked
PR set from a predictable `/tmp` path.

**Residual risk.** The feature trusts niwa's materialization fingerprint as the
script-provenance root; a compromise of the materializer or of `GH_TOKEN` is out
of scope and inherited from the harness. Prompt-injection defense is
best-effort: sanitization and field-restriction reduce but do not eliminate the
possibility that adversarial PR text influences the model's narrative, so no
security decision is delegated to model interpretation of block contents.

## Consequences

### Positive

- The summary is deterministic: it reflects real captured PR state, not agent
  memory, and cannot emit a fabricated PR reference.
- The layer split follows the existing architectural boundary and version-matches
  the block spec to its single implementation, so the two layers cannot drift.
- Zero model-context cost for the user-facing display (systemMessage), with a
  small bounded echo (~200 tokens) only when there is news.
- Works in background sessions through the transcript and final message.
- Degrades cleanly: offline → best-effort block; shirabe-without-niwa → `/status`
  only; niwa-without-shirabe → ambient display only.

### Negative / Trade-offs

- The deterministic display (systemMessage) does not reach the Agent View session
  list row, only the drilled-in transcript; the list-row PR chip stays outside
  the feature's control.
- The design depends on undocumented harness behavior (systemMessage persistence,
  additionalContext-in-`-p`, identical-command hook dedup) verified only at
  Claude Code 2.1.201; a harness upgrade could shift it. Mitigation: the
  mechanics are isolated in dot-niwa hooks that can be re-verified in one place.
- A prerequisite materializer fix is required for clean single-channel hook
  registration; until then hooks must be idempotent and tool-type tolerant.
- The background-worker path relies on the model authoring its final message
  correctly — the one place agent discipline remains, mitigated by the
  dispatch-brief rule making it a required instruction.

### Mitigations

- Isolate all harness-version-sensitive mechanics in dot-niwa hooks for
  single-point re-verification.
- Sequence the materializer fix as a prerequisite in the plan, or author hooks
  defensively against the current double-registration behavior.
- Keep the block spec co-located with the single render implementation so no
  second source of truth can drift.
