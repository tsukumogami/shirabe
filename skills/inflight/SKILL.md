---
name: inflight
description: >-
  Show the pull requests this session has in flight as a standardized "work in
  flight" block -- repo, PR number, state, CI/review status, title, and a
  clickable URL per item, ordered attention-first. Use when the user asks "what
  PRs are in flight", "show this session's PRs", "work in flight", "which PRs did
  I open", or invokes /inflight explicitly. Does NOT apply to authoring a new PR,
  checking a single named PR's details, or listing every open PR in a repo
  regardless of session -- it reports the current session's tracked PRs (with a
  repo-scoped fallback), not an arbitrary query.
argument-hint: ''
disable-model-invocation: true
allowed-tools: Bash(bash:*)
---

# In Flight

Report the pull requests the current session is tracking as the standardized
work-in-flight block. This skill is a thin relay: the reusable work-summary
component owns capture, the gate, and rendering, and the same component backs
the ambient dot-niwa hooks -- so `/inflight` and the automatic emissions always
produce the identical block shape.

## What it does

`/inflight` invokes the component's `render` entry point through dynamic command
injection and relays its output verbatim. The component reads this session's
private PR ledger, refreshes each item's live state via `gh pr view`, orders
attention-first, drops terminal PRs after their one post-transition showing, and
stamps a freshness line. When live state is unreachable it prints a best-effort,
ledger-only block clearly marked as such -- it never fails the turn.

## Invocation

Run the component and relay whatever it prints, unchanged:

!`bash "${CLAUDE_PLUGIN_ROOT}/skills/inflight/scripts/inflight.sh"`

Present the injected block to the user exactly as produced -- do not reformat,
summarize, or add PRs from memory. If the injection produced no output, tell the
user there are no pull requests in flight for this session.

## Session id and fallback

The wrapper resolves the session id from the harness environment variable
`CLAUDE_CODE_SESSION_ID` (confirmed exposed to a skill's `!` injection on Claude
Code 2.1.201) and calls
`${CLAUDE_PLUGIN_ROOT}/skills/inflight/scripts/work-summary.sh render --session
<id>`. That id must match the id the dot-niwa capture hook keys the ledger by
(the PostToolUse hook stdin's `session_id`); when they match, the primary path
returns this session's captured PRs.

When the session ledger is empty or unreachable -- for example a fresh session
that has not opened a PR yet, or a session whose id the hooks never captured --
the wrapper degrades to a **repo-scoped** fallback: `gh pr list --repo
<current-repo> --author @me`, formatted to the same block spec. It is
deliberately repo-scoped and never an author-scoped cross-repo search, which
would over-collect PRs from other repositories into this context. It is
fail-closed: if the current repository cannot be confirmed via `gh`, it emits
nothing rather than surface PRs whose repository or visibility it cannot
establish, and it lists only PRs whose URL belongs to the confirmed repo.

## Notes

- This skill is user-invoked only (`disable-model-invocation: true`); the model
  does not trigger it on its own.
- The block format is defined once, by the component. Run
  `work-summary.sh help` to see the authoritative spec.
