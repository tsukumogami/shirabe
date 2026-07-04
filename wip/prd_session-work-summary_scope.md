# PRD Scope: session-work-summary

Upstream: docs/briefs/BRIEF-session-work-summary.md (Accepted)
Research source: completed /explore (5 rounds) — findings, decisions, r1-r5 research in wip/.

## Problem (from BRIEF)
Long multi-PR sessions lose PR links; native affordances don't recover them.

## Requirements themes (WHAT, not HOW)
- The standardized block: fixed marker, one line per item, fields, bare URL last, ordering, terminal-drop, >6-item sections.
- Emission behavior: on PR-set/status change; on return-after-absence; never per-message/timer.
- Mechanical capture: block content derives from real PR state, not agent memory.
- Data integrity: only real, gh-verified PR URLs appear (round-5 phantom-badge finding — fabricated URLs pollute native footer/Agent-View surfaces).
- Model awareness: agent stays aware of current PR set, including post-compaction.
- On-demand command: regenerates the same block from live state.
- Background/dispatched coverage: final-message requirement.
- Multi-repo + visibility: entries carry repo identity; collection respects per-repo visibility.

## Explicitly NOT requirements (design-owned HOW)
Hook events, systemMessage/additionalContext channels, render-script placement, ledger schema, flock, which repo ships what — all deferred to DESIGN.

## Out of scope (from BRIEF, carried forward)
Harness changes; timed/turn-count digests; user-settings display channels as deliverables; team notifications; the niwa duplicate-hook materializer fix (prerequisite); non-PR work items.
