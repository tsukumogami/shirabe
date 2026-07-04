# Architecture Review: session-work-summary

Reviewed: `docs/designs/DESIGN-session-work-summary.md` (Solution Architecture,
Implementation Approach, Decision Outcome, Security Considerations) against
`docs/prds/PRD-session-work-summary.md` (R1-R15) and the five-round exploration
(`wip/research/explore_*` + `explore_*_r3_prototype-work-summary.sh` + the phase-5
security review).

**Verdict: CONCERNS.** The core data path is sound and empirically validated —
per-session capture from real `gh pr create` output is integrity-safe (R5) and
visibility-safe (R12) by construction, and the layer split is well-argued. But
several *implementation-level* mechanisms that the research files worked out in
detail were compressed out of the design body, and three PRD requirements (R3
terminal-drop tracking, R6 CI-flip emission, R9 freshness indication) have weak
or missing architectural support. A developer could build the render script and
capture hook from the design, but would have to re-derive the gate/state schema
and the emission policy from the research files, and would hit undefined behavior
on R3/R9. These are closable in a revision pass; none invalidate the approach.

---

## Q1 — Is the architecture clear enough to implement?

**Mostly, with gaps.** Component-by-component:

- **Render script** (`render-work-in-flight.sh`): Clear. A validated prototype
  exists (`explore_*_r3_prototype-work-summary.sh`) covering ledger read, `gh pr
  view` refresh, token formatting, offline degradation. A developer could port it
  directly. GOOD.
- **Capture hook**: Clear. Key Interfaces specifies stdin JSON fields, the
  anchored URL regex, session-id validation, `/pull/new/` rejection. The
  prototype's `cmd_capture` is a working reference. GOOD.
- **Gate / emission policy**: UNDER-SPECIFIED in the design body. The design says
  "emit when the ledger hash or the rendered block changes" and lists a state
  file holding "last-emitted ledger hash, rendered-block hash, and last-activity
  timestamp" — but the *per-event routing logic* (which channel fires on which
  event under which gate) lives only in the phase-4 research policy table (9
  rows). A developer working from Solution Architecture + Implementation Approach
  alone would not know, e.g., that SessionStart(compact) emits `additionalContext`
  only, or that suppressed fires must still refresh `last_activity`. The design
  should either inline that policy table or cite it normatively.
- **`/status` skill + fingerprint verification**: The *intent* is clear, but the
  verification mechanism rests on an unvalidated assumption (see Q2).
- **Dispatch-brief rule**: Clear as a convention; correctly flagged as the one
  place agent discipline remains.

## Q2 — Missing components / interfaces

Answering the specific prompts:

1. **Render script's gate state vs the ledger — ownership is ambiguous.** The
   Components table says the render script does "gate logic," while the
   PostToolUse hook "emit[s] block on gate pass." Who computes the gate? In the
   prototype, `should-render`/`mark-rendered` are subcommands *of the render
   script*, invoked by the hook. The design never states this. Specify: the gate
   is a subcommand of `render-work-in-flight.sh`; the hook calls it, and only
   renders+emits on exit-0. Otherwise a reader can't tell whether the hook or the
   script owns hash comparison.

2. **How the three hooks share the state file — schema and writers undefined.**
   All three hooks (PostToolUse, UserPromptSubmit, SessionStart-compact) touch
   one `flock`-protected per-session state file, but the design never says they
   share one file, nor who writes which field. Critically: **`last_activity` must
   be refreshed by the hooks that measure absence against it, or the absence
   timer never fires correctly.** The phase-4 research is explicit ("every fire,
   including suppressed ones, refreshes `last_activity`"); the design dropped it.
   State this.

3. **What triggers return-after-absence — undefined baseline.** The design says
   "first prompt after the absence threshold" but never defines what the gap is
   measured *from*. It is `now - last_activity` at UserPromptSubmit, where
   `last_activity` is stamped at each prior UserPromptSubmit (and PostToolUse
   fire). Note the r2 open question: PostToolUse only matches PR-affecting `gh`
   commands, so it is NOT a general heartbeat — absence is effectively
   prompt-to-prompt gap. That's fine, but must be written down, because a reader
   might assume a general-activity heartbeat that the matcher does not provide.

4. **Absence threshold config knob unnamed.** R7 requires "configurable." The
   research names `WS_ABSENCE_THRESHOLD` (default 1800s). The design says
   "configurable (default 30 min)" without naming the mechanism (env var? niwa
   config?). Name it so R7 is testable.

5. **NEW GAP — R3 terminal-drop tracking has no home.** "Terminal rows dropped
   after one post-transition appearance" requires per-item state: *which*
   merged/closed PRs have already been shown once. The ledger (prototype: repo,
   num, url, first-seen) has no such field, and the gate state file holds only
   hashes + timestamp. There is no described structure that records "PR #N was
   shown once in terminal state, drop it next time." This mechanism is missing
   from every data structure in the design. Add a per-item shown-terminal marker
   (in the ledger or a sibling state file).

6. **NEW GAP — fingerprint-verification interface may not exist.** The security
   control requires `/status` to "verify niwa's materialization fingerprint"
   before executing the probed `.local.sh`. The r2 research confirms niwa
   sha256-fingerprints materialized content internally (`writeManagedFile`), but
   there is **no described interface for a skill to query "is this file
   niwa-materialized and unmodified?"** The control assumes a provenance-query
   surface that may need to be built in niwa first. This is a second unstated
   cross-repo prerequisite (alongside the duplicate-hook fix). Either point to
   the concrete niwa fingerprint file/command `/status` will read, or flag it as
   a niwa dependency in the plan.

## Q3 — Are the implementation phases correctly sequenced?

**Mostly, but the prerequisite is mis-placed and one dependency is missing.**

- Phases 1-5 (render → capture → return/compact → /status → dispatch-brief) are
  reasonably ordered: the render script is the shared dependency built first, and
  /status depends on the materialized path existing.
- **The materializer duplicate-hook fix is labelled "Prerequisite" but listed
  LAST (phase 6).** A prerequisite by definition sequences *before* the work that
  needs it (phases 2-3 ship the hooks). Move it to phase 0, or the design should
  commit clearly to the "author hooks defensively (idempotent, tool-type
  tolerant)" fallback and drop the "sequence it first" option so the plan isn't
  ambiguous. As written it reads as both-and-neither.
- **Missing dependency:** phase 4 (`/status` fingerprint verification) depends on
  the niwa provenance-query surface from Q2.6. If that surface must be built,
  it's a niwa prerequisite that no phase owns. Add it.

## Q4 — Simpler alternatives / over-engineering

- **The interval / rendered-hash reconciliation was dropped, creating a real
  gap.** The prototype and phase-4 policy use `WS_RENDER_INTERVAL` so the
  expensive rendered-hash (which needs live `gh` calls) is only recomputed
  periodically after the cheap ledger-hash gate passes. The design says only
  "ledger-hash OR rendered-hash changed" with no interval. Without the interval,
  detecting a rendered-hash change requires rendering (network `gh`) on *every*
  PostToolUse fire — contradicting the "no gh calls on quiet fires" cost goal
  (R13/R15). This isn't over-engineering; it's an *under*-specification that
  removed the mechanism reconciling R6 (emit on CI change) with R15 (cheap). Put
  the interval back or state how CI-flip detection stays cheap.

- **The fingerprint-verification dance may be avoidable.** The whole
  supply-chain control exists because the single render implementation must live
  in the repo tree (where niwa-materialized hooks can call it) and `/status` then
  executes a repo-tree-resident script. A simpler cut: ship the render logic (or
  a shared library it sources) in the shirabe *plugin* cache — not attacker-
  plantable, resolved via `${CLAUDE_PLUGIN_ROOT}` for the skill — and have the
  niwa hooks call a thin materialized wrapper that sources it. That removes the
  "execute a file from the working tree" risk entirely and with it the whole
  fingerprint-verification requirement. The design dismisses the plugin-cache
  path (Decision 1 Option A) as "version-unstable," which is true *for niwa
  hooks* (no `${CLAUDE_PLUGIN_ROOT}` there) but not for the skill side. Worth a
  sentence explaining why a plugin-shipped render library shared by both sides
  was rejected, rather than folding it into the hooks-can't-resolve-the-path
  argument.

- **Not over-engineered otherwise.** The PRD is demanding (R1-R15); the
  dual-channel emission, 3-hook set, and two-level hash are each traceable to a
  specific requirement. The one dropped simplification (SessionStart `resume`
  matcher, row 8 in research) is a fair scope cut.

## Q5 — PRD requirement consistency (R1-R15)

| Req | Support | Notes |
|-----|---------|-------|
| R1 standardized block/marker | PARTIAL | Marker + block spec live *only* in the dot-niwa render script. In the shirabe-without-niwa `/status` fallback ("model-driven `gh` listing"), shirabe has no copy of the format — so that emission will NOT match the standard shape, violating R1's "all emissions use this same block shape." Either ship the format spec to shirabe too, or scope R1 to "when niwa is present." |
| R2 fields + selectable URL | YES | Decision 5 flat pipe, bare URL last. |
| R3 order + terminal-drop | PARTIAL | Ordering yes; "shown once then drop" has no backing state structure (Q2.5). |
| R4 live-derived | YES | `gh pr view` refresh at render. |
| R5 real-PR-only | YES | Strong — capture from `gh pr create` output only. |
| R6 emit on set/state change | PARTIAL | A pure CI/review flip (async, GitHub-side) produces NO hook event — PostToolUse fires only on the agent's own `gh` commands. So CI-change emission can only happen incidentally on a later tool call, on return-after-absence, or via `/status`. The architecture cannot emit *when* CI flips absent a triggering event. R6 as written ("SHALL be emitted when its CI status changes") is not fully satisfiable by any hook-based design; the PRD/design should acknowledge this bound explicitly rather than claim R6 met. |
| R7 return-after-absence | YES* | Mechanism present; config knob unnamed (Q2.4). |
| R8 suppress duplicates | YES | Two-level hash gate. |
| R9 on-demand + freshness | PARTIAL | `/status` relays the block, but R9 requires "indicates how fresh the data is." Neither the render prototype nor the design emits a timestamp/freshness marker. No architectural support for the freshness indication. Add a render-time timestamp line. |
| R10 model-aware + post-compaction | YES | additionalContext echo + SessionStart(compact). |
| R11 worker final message | YES | Dispatch-brief rule (relies on model discipline, correctly flagged). |
| R12 visibility | YES | By construction; residual paths constrained in Security section. |
| R13 fast + graceful degradation | YES* | Offline best-effort covered; "sub-second" optimistic for several serial `gh pr view` calls — prototype's `--parallel` + 8s timeout mitigate. |
| R14 legible across widths | YES | Decision 5 bare-URL wraps intact. |
| R15 bounded small cost | YES | ~200 tokens/fire measured; depends on the interval mechanism (Q4) staying in. |

**Requirements to flag: R6 (structural bound — no async trigger), R9 (freshness
indication absent), R3 (terminal-drop state missing), R1 (degraded fallback
breaks shape uniformity).**

---

## Top recommendations (priority order)

1. **Add the terminal-drop state (R3)** — a per-item "shown-once-in-terminal"
   marker; without it R3 cannot be implemented as specified.
2. **Add a freshness indicator to the block (R9)** — a render-time timestamp
   line; currently no support.
3. **Acknowledge the R6 async-CI-flip bound** — no hook fires on a GitHub-side CI
   change; emission is event-triggered only. State the limitation instead of
   claiming R6 fully met (the PRD Known Limitations is the right home).
4. **Restore the render-interval / rendered-hash reconciliation** — otherwise
   CI-flip detection either costs a `gh` call every fire (breaks R15) or never
   happens between ledger changes.
5. **Specify the shared state-file schema and writers** across all three hooks,
   including that suppressed fires refresh `last_activity`; name the absence
   config knob (R7).
6. **Resolve the fingerprint-verification interface** — confirm the niwa
   provenance-query surface exists or add it as an explicit niwa prerequisite;
   consider the plugin-shipped shared-render alternative that removes the
   execute-from-working-tree risk entirely.
7. **Re-place the materializer fix as phase 0** (or commit unambiguously to the
   defensive-hook fallback) and add the fingerprint-surface dependency to the
   phase sequence.
8. **Fix R1 in degraded mode** — either ship the block format to shirabe so the
   `/status` `gh` fallback matches the standard shape, or scope R1's uniformity
   claim to niwa-present operation.
