---
name: inflight
description: >-
  Show the pull requests this session has in flight as a standardized "work in
  flight" block -- repo, PR number, state, CI/review status, title, and a
  clickable URL per item, ordered attention-first. Use when the user asks "what
  PRs are in flight", "show this session's PRs", "work in flight", "which PRs did
  I open", or invokes /inflight explicitly. Does NOT apply to authoring a new PR,
  checking a single named PR's details, or listing every open PR in a repo
  regardless of session -- it reports the current session's tracked PRs, or a
  session-scoped empty-state when none are tracked, not an arbitrary query.
argument-hint: ''
disable-model-invocation: true
allowed-tools: Bash(shirabe:*)
---

# In Flight

Report the pull requests the current session is tracking as the standardized
work-in-flight block. This skill is a thin relay: the compiled `shirabe
work-summary` subcommand owns capture, the gate, and rendering, and the same
binary backs the ambient dot-niwa hooks -- so `/inflight` and the automatic
emissions always produce the identical block shape.

## What it does

`/inflight` invokes `shirabe work-summary render` through dynamic command
injection and relays its output verbatim. The command reads this session's
private PR ledger, refreshes each item's live state via `gh pr view`, orders
attention-first, drops terminal PRs after their one post-transition showing, and
stamps a freshness line. When live state is unreachable it prints a best-effort,
ledger-only block clearly marked as such. When the ledger is empty it prints a
single-line, session-scoped empty-state instead of a block -- it never fails the
turn and never issues a non-session `gh` listing.

## Invocation

Run the command and relay whatever it prints, unchanged:

!`shirabe work-summary render`

Present the output to the user exactly as produced -- do not reformat,
summarize, or add PRs from memory. `render` always prints something: either the
work-in-flight block, or the session-scoped empty-state line (for example `no
pull requests tracked for this session`). Relay that empty-state line as-is; it
is the truthful answer for a session with nothing tracked.

## Session id and the empty-state

`shirabe work-summary render` resolves the session id itself from the harness
environment variable `CLAUDE_CODE_SESSION_ID` (confirmed exposed to a skill's `!`
injection on Claude Code 2.1.201); no `--session` argument is needed. That id
must match the id the dot-niwa capture hook keys the ledger by (the PostToolUse
hook stdin's `session_id`); when they match, the primary path returns this
session's captured PRs.

When the session ledger is empty or unreachable -- a fresh session that has not
opened a PR yet, a session whose id the hooks never captured, or `gh` offline --
`render` prints the session-scoped empty-state. It does **not** fall back to a
repo-and-author `gh pr list`: no `gh`-only query is session-scoped, so a repo
dump would both over-report (other sessions' PRs in this repo) and under-report
(this session's PRs in other repos) under the work-in-flight banner. The
empty-state is the honest answer; completeness for the common case comes from
the ambient capture hook populating the ledger, not from an on-demand listing.

## Recovering a PR the hook missed (submit, don't narrate)

The capture hook records a PR only when this session ran `gh ... pr create` and
its stdout carried the PR URL. A PR opened another way -- via the web UI, a `gh
api` call, or a subagent whose tool calls never hit this session's hook -- is
structurally invisible to capture, so the ledger (and the block) will not list
it.

The sanctioned recovery is to submit it through the validated verb, never to
narrate it as prose:

!`shirabe work-summary track <pr-url> [<pr-url> ...]`

`track` validates each URL against the anchored PR-URL pattern **and** a live
`gh pr view` before appending it to this session's ledger (marked
agent-asserted, deduped by URL); a fabricated or malformed URL is rejected, not
appended. After a successful `track`, re-run `render` to show the recovered PR
inside the normal block. Only submit a PR you actually opened this session.

## Guardrail: no PR reference outside the block

No pull-request reference (URL, `owner/repo#N`, "I opened PR ...") may appear in
the relay text around the block unless it is a real PR the block itself lists.
This is a checkable rule, and it applies to two places:

- **The `/inflight` relay.** Present exactly what `render` prints -- the block,
  or the empty-state line -- and add no PR reference of your own. If a PR is
  missing, the only sanctioned move is `track`-then-`render`, which routes your
  session knowledge *through* the validated block, not around it.
- **The dispatch final-message rule.** A dispatched session's final message must
  not append PR references beside the summary block. A PR the session opened
  belongs in the block (via capture or `track`); if it is not in the block, it
  is not narrated next to it.

A reviewer or an automated check can verify conformance objectively: every PR
reference in the surrounding text must correspond to a row the block renders.
The empty-state carries no PR references, so relaying it can never violate the
rule.

## Notes

- This skill is user-invoked only (`disable-model-invocation: true`); the model
  does not trigger it on its own.
- The block format is defined once, by the binary. The `shirabe work-summary`
  subcommands (`capture`, `absence`, `compact`, `render`, `track`) share the
  same block renderer, so the ambient hooks and `/inflight` never drift.
