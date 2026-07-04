# Brief Discovery: session-work-summary

## Source

Completed 4-round /explore on this branch (findings, decisions, crystallize under
wip/). User-confirmed direction: deterministic work-in-flight summary; event-gated
+ return-after-absence cadence; shirabe owns conversational surface, dot-niwa owns
hooks; validated empirically on Claude Code 2.1.201.

## Problem/Outcome Pair

Problem: in long agent sessions that open multiple PRs (often across several
repos), PR links and status scroll out of reach. Native affordances don't close
the gap: the footer badge tracks only the current branch, Ctrl+R searches only
user prompts, /recap has no structured links. Users lose track of what's in
flight and dig through scrollback to find a PR link.

Outcome: at any moment in a session — after a PR event, on returning from a
break, on demand, or reading a finished background worker's transcript — the
user finds one recognizable, searchable block listing every PR this session
touched with its state, CI status, and a clickable link.

## Journey Sketches

1. Interactive multi-PR afternoon (event push + return refresh)
2. Finding a link later in scrollback (marker search)
3. On-demand status pull (/status)
4. Dispatched background worker (final-message block via Agent View/attach)

## Scope Edges (from explore decisions)

IN: block format + marker; mechanical PR capture; event-gated display;
return-after-absence refresh; model-context echo; /status; dispatch final-message
rule; multi-repo coverage.
OUT: Claude Code changes; timed/turn-count digests; Agent View list-row changes;
statusline/footer badges as shipped components (recommend-only); team notification
systems; the niwa hook-dedup materializer fix (prerequisite, tracked separately).
