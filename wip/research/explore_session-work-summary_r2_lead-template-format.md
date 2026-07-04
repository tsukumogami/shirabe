# Lead: What should the summary block look like?

## Findings

### Conventions read

- **Coordination PR Index** (`public/shirabe/references/coordination-strategy.md`, lines 89-101): one pipe-delimited bullet per node, `- <node-id> | <owner/repo:path#number> | <merge-state>`. Notable properties: line-oriented, fixed field order, pipe separators, a literal declaration-marker line that tooling greps for verbatim (`lifecycle.yml` detects coordination PRs by grepping the marker). Merge state is deliberately the only live-verified field (F4: recompute from `gh`, never trust body text).
- **Issues table** (`public/shirabe/references/issues-table.md`): GFM pipe table, key-link-first column (`[#N: <title>](<url>)`), description rows, strikethrough on done, validator-enforced (FC05/FC06/FC07/FC09 in `crates/shirabe-validate/src/`). Crucially, all of that enforcement applies to *committed docs* with a `schema:` frontmatter — none of it can apply to a chat block, which is never committed.
- **Renovate dashboard**: single mutable document, state-sectioned (Pending / Open / Blocked / Closed), empty sections omitted. Strongest prior art for many concurrent items in one findable place (per r1 prior-art lead).
- **Round-1 decisions** (`wip/explore_session-work-summary_decisions.md`): event-gated push + return-after-absence, shirabe owns the template as a reference file, niwa/dot-niwa owns hook cadence.

### Marker design (shared by all candidates)

Requirements: short ASCII token, no emojis, survives markdown rendering, findable in terminal scrollback (Ctrl+O then `[` dumps the rendered transcript to native scrollback; Ctrl+R searches user prompts only, so the marker targets scrollback/terminal search, per r1 prior-art findings).

Rejected forms:

- `## WORK IN FLIGHT` — the `##` is consumed by the markdown renderer; what lands in scrollback is styled text with no distinctive token beyond the words themselves.
- `**WORK IN FLIGHT**` — asterisks consumed the same way.
- A bare `WORK IN FLIGHT` — collides with prose (this exploration itself says "work in flight" constantly).
- Emoji or box-drawing sigils — banned by workspace style / fragile across fonts and copies.

**Chosen marker: `=== WORK IN FLIGHT ===`** — all on one line. Equals signs are not inline markdown, and setext-heading interpretation only triggers when `===` sits alone on the line below a paragraph, so the marker passes through the renderer literally. It is searchable three ways: the full string, the fragment `WORK IN FLIGHT` (all-caps survives case-sensitive search), and the fragment `===` for coarse jumping. It is also grep-able by tooling (the niwa dedupe hook can detect "did the last N transcript lines already contain a block" the same way `lifecycle.yml` greps the coordination declaration marker — a proven pattern in this workspace).

### Shared scenario for the examples

Three PRs across two repos plus one pre-PR item:

1. `tsukumogami/tsuku#412` "Retry checksum downloads on transient failure" — open, CI failing (2 of 14 checks)
2. `tsukumogami/shirabe#87` "Add coordination-strategy validation notes" — open, CI green, awaiting review
3. `tsukumogami/tsuku#409` "Cache version provider lookups" — merged this session
4. Pre-PR: branch `docs/session-work-summary` pushed to `tsukumogami/shirabe`, tracking issue #83, no PR yet

### Candidate A — flat pipe-line list (PR Index grammar, extended)

One line per item, fixed field order, attention-first ordering, URL last. Direct descendant of the PR Index line grammar with the `node-id` slot replaced by the `owner/repo#number` ref and the merge-state slot widened into a state-token field.

```
=== WORK IN FLIGHT ===
- tsukumogami/tsuku#412 | open ci-fail 2/14 | Retry checksum downloads on transient failure | https://github.com/tsukumogami/tsuku/pull/412
- tsukumogami/shirabe#87 | open ci-pass review-wait | Add coordination-strategy validation notes | https://github.com/tsukumogami/shirabe/pull/87
- tsukumogami/shirabe (no-pr) | branch docs/session-work-summary | exploration in progress | https://github.com/tsukumogami/shirabe/issues/83
- tsukumogami/tsuku#409 | merged | Cache version provider lookups | https://github.com/tsukumogami/tsuku/pull/409
```

- **Scannability:** high at the target scale (a handful). The `owner/repo#N` key and the state token sit in fixed positions, so the eye scans two ragged columns. At 8-10 items it becomes a undifferentiated wall unless the ordering rule (needs-attention first, merged last) carries the grouping.
- **Clickability:** bare URLs are the most reliably linkified form in terminal emulators and the only form that survives the Ctrl+O `[` scrollback dump as recoverable text. Risk: a long title pushes the URL past the wrap column and renderer hard-wrapping can split it. Mitigated by a title-truncation rule (~60 chars) but not eliminated.
- **Token cost:** lowest. ~30-40 tokens per line; the 4-item block is ~150 tokens including marker.
- **Scrollback searchability:** marker plus per-line `owner/repo#N` keys; a user can search either.
- **Degradation:** 1 PR = 2 lines, ideal. 10 PRs = 11 dense lines; readable only because of the ordering rule.

### Candidate B — GFM pipe table (issues-table profile transplanted)

```
=== WORK IN FLIGHT ===

| Item | State | CI | Link |
|------|-------|----|------|
| tsukumogami/tsuku#412: Retry checksum downloads | open | fail 2/14 | https://github.com/tsukumogami/tsuku/pull/412 |
| tsukumogami/shirabe#87: Add coordination-strategy validation notes | review-wait | pass | https://github.com/tsukumogami/shirabe/pull/87 |
| tsukumogami/shirabe: branch docs/session-work-summary | no-pr | - | https://github.com/tsukumogami/shirabe/issues/83 |
| tsukumogami/tsuku#412: Cache version provider lookups | merged | - | https://github.com/tsukumogami/tsuku/pull/409 |
```

- **Scannability:** best column alignment once rendered; state is a true column.
- **Clickability:** the worst of the three. The issues-table's native `[#N: title](url)` form renders as an OSC-8 hyperlink whose URL text does not survive the scrollback dump — the link is unrecoverable from scrollback, which defeats the block's core purpose. Falling back to bare URLs in a cell (as shown) blows the table past 120 columns and forces horizontal truncation in the renderer.
- **Token cost:** highest — header row, separator row, cell padding.
- **Scrollback searchability:** same marker; table pipes add noise around the `owner/repo#N` keys but they remain searchable.
- **Degradation:** 1 PR = 4 lines of scaffolding for one row (worst small-N shape). 10 PRs fine vertically, but the width problem worsens as titles vary.
- Also: the issues-table conventions that make the table shape worth its cost (FC05 schema check, strikethrough-on-done, description rows) are all validator- or document-bound; none transfer to an ephemeral chat block. Inheriting the shape buys the cost without the benefit.

### Candidate C — Renovate-style state sections

```
=== WORK IN FLIGHT ===

Needs attention:
- tsukumogami/tsuku#412 Retry checksum downloads on transient failure — CI failing 2/14
  https://github.com/tsukumogami/tsuku/pull/412

Awaiting review:
- tsukumogami/shirabe#87 Add coordination-strategy validation notes — CI green
  https://github.com/tsukumogami/shirabe/pull/87

No PR yet:
- tsukumogami/shirabe — branch docs/session-work-summary pushed (exploration in progress)
  https://github.com/tsukumogami/shirabe/issues/83

Merged this session:
- tsukumogami/tsuku#409 Cache version provider lookups
  https://github.com/tsukumogami/tsuku/pull/409
```

- **Scannability:** best grouping semantics — state is read once from the section header, not decoded per line. Empty sections are omitted (Renovate's rule).
- **Clickability:** best — the URL lives alone on a continuation line, so it never wraps and always linkifies, and it survives the scrollback dump verbatim.
- **Token cost:** middle. Two lines per item plus a header line per non-empty section; the 4-item block is ~2x Candidate A.
- **Scrollback searchability:** marker plus section-header strings ("Needs attention:") as secondary search targets.
- **Degradation:** 10 PRs = excellent (this is what the shape is for). 1 PR = marker + one header + two lines, acceptable. The weak spot is exactly the expected scale: 3-4 items spread across 3-4 sections means nearly one header per item — the sections stop paying for themselves.

### Recommendation

**Candidate A as the canonical shape, with Candidate C's section headers as a defined escalation at >6 items (line grammar unchanged).** Rationale:

1. The stated constraint is "short, a handful of PRs" — at that scale A is roughly half C's height and a third of B's tokens, and it is emitted repeatedly by design, so per-emission cost compounds.
2. A's line grammar is the PR Index grammar users and tooling already know (`ref | state | ...` pipe lines, greppable marker), keeping shirabe internally consistent — the reference file can literally cite `coordination-strategy.md` as the parent grammar.
3. The pipe lines are trivially machine-parseable, which matters for the layer contract: the niwa dedupe hook and the pull-side `/status` both need to recognize and regenerate the block; a regular grammar makes "did we already emit this state?" a string comparison.
4. The escalation rule preserves "users learn one shape": section headers are additive; every item line looks identical whether or not headers are present. This is also exactly how `gh pr status` and Renovate scale.
5. B is eliminated on clickability alone: markdown-link cells lose their URLs in scrollback, and bare-URL cells break the table width. The issues-table convention should stay a committed-doc convention.

**Exact marker:** `=== WORK IN FLIGHT ===` (verbatim, own line, first line of the block, identical in push emissions and `/status` renders).

**Line grammar:** `- <owner/repo>#<number> | <state-tokens> | <title, truncated to 60 chars> | <url>` for PR rows; `- <owner/repo> (no-pr) | branch <headRefName> | <one-clause description> | <issue-or-compare-url>` for pre-PR rows. Pre-PR items are included — a session's work in flight is not only PRs, and the `no-pr` state token keeps them distinguishable and sortable (they sit between review-wait and merged in the ordering).

**State-token vocabulary** (all derivable from `gh pr view --json state,statusCheckRollup,reviewDecision,isDraft`): `open`, `draft`, `merged`, `closed`, `no-pr`; CI qualifiers `ci-pass`, `ci-fail F/N`, `ci-pending`; review qualifiers `review-wait`, `changes-requested`, `approved`. Ordering within the block: `ci-fail` and `changes-requested` first, then `ci-pending`/`review-wait`, then `draft`, then `no-pr`, then `merged`/`closed` last.

**Emission rules (spec-ready text):**

- Emit the block when a tracked item's state changes: PR created, PR merged or closed, CI rollup transitions to failing or recovers, review decision becomes changes-requested, or a pre-PR item is registered (branch pushed for tracked work). Also emit on the first assistant turn after a return-after-absence gap (cadence per the r1 decision; dedupe state shared with the niwa hook layer).
- Emit inside the turn that performed or reported the triggering event, as the final element of that turn. Never append the block to unrelated turns; it is not a per-message footer.
- Every emission is self-contained: full URLs on every line, every time. Never "see the block above."
- At most one block per turn; if several events land in one turn, emit once with all rows current.
- A row that reached a terminal state (merged/closed) appears in exactly one emission after the transition, then drops from subsequent blocks. (This replaces the issues-table strikethrough-on-done, which does not survive terminal rendering meaningfully.)
- The block is regenerated from the session ledger plus live `gh` reads at emission time — never replayed from a previous emission (the chat-side analog of coordination F4: state comes from `gh`, not from earlier body text).

**Pull-side `/status` render:** identical block, regenerated fresh — read the ledger for the item set, refresh each item via `gh pr view <n> --json state,title,url,statusCheckRollup,reviewDecision` (or one `gh pr status` per repo when the ledger is repo-dense), render the same marker + lines, and append one freshness line:

```
=== WORK IN FLIGHT ===
- tsukumogami/tsuku#412 | open ci-fail 2/14 | Retry checksum downloads on transient failure | https://github.com/tsukumogami/tsuku/pull/412
- tsukumogami/shirabe#87 | open ci-pass review-wait | Add coordination-strategy validation notes | https://github.com/tsukumogami/shirabe/pull/87
- tsukumogami/shirabe (no-pr) | branch docs/session-work-summary | exploration in progress | https://github.com/tsukumogami/shirabe/issues/83
- tsukumogami/tsuku#409 | merged | Cache version provider lookups | https://github.com/tsukumogami/tsuku/pull/409
(refreshed 2026-07-04T14:02Z via gh)
```

`/status` differs from push emissions in exactly two allowed ways: terminal rows from the whole session may be shown (history view), and the freshness line is mandatory rather than optional. Everything else is byte-identical in shape, so users learn one block.

## Implications

- The reference file (sibling to `issues-table.md`, e.g. `references/work-in-flight.md`) should define: the marker verbatim, the line grammar, the state-token vocabulary, the ordering rule, the >6-item section escalation, the emission rules, and the `/status` contract — and explicitly cite `coordination-strategy.md` as the parent line grammar and F4 as the live-refresh precedent.
- Because no validator can enforce a chat block, conformance rests entirely on the reference's examples being copy-pasteable. Keep the grammar simple enough that drift is visually obvious; a future `shirabe validate` mode could lint the *ledger* file instead, which is committed-adjacent state.
- The greppable marker doubles as the dedupe hook's detection token (same pattern as `lifecycle.yml` grepping the coordination declaration marker), which cleanly serves the round-2 "layer coordination without double emission" lead: the niwa hook can suppress its return-after-absence injection if the tail of the transcript already carries a current block.
- URL-last field ordering plus 60-char title truncation is the load-bearing clickability rule for Candidate A; it belongs in the reference as a MUST, not a style suggestion.

## Surprises

- The PR Index slot is `owner/repo:path#number` — it carries a `:path` segment because F2 validates `owner/repo:path` components (coordination-strategy.md lines 91, 108-109, 246-258). The chat block should *not* inherit the `:path` segment; plain `owner/repo#number` is the natural chat form, and the reference should say so explicitly to prevent cargo-culting the coordination grammar.
- The issues-table's strikethrough-on-done rule (issues-table.md lines 58-72) has no usable chat analog: rendered strikethrough loses the tildes in scrollback dumps and struck text conveys nothing when the row later disappears anyway. "One emission after terminal state, then drop" is the correct translation.
- Markdown links (`[#N](url)`) are actively harmful here: they render as OSC-8 hyperlinks whose URL is unrecoverable from a plain-text scrollback dump — the exact medium the marker is designed to be found in. This single fact eliminates the issues-table's key-link form and Candidate B with it.
- Nothing in `crates/shirabe-validate` can see chat output, so this will be the first shirabe reference whose format has no machine check at all — every other formatted convention in `references/` (issues table, coordination body, merge-order block) has a validate mode.

## Open Questions

- Should the session ledger's on-disk format be these exact pipe lines (block = trivial render of ledger) or structured JSON with the block as a projection? The former makes the dedupe grep trivial; the latter is easier for `gh` refresh merging.
- Does Claude Code's renderer hard-wrap long lines in a way that breaks terminal linkification of a trailing URL, and at what column? Needs an empirical check — the round-2 hook-injection empirics lead could piggyback this.
- Does `/status` history mode (all terminal rows from the session) need a cap, and does it read merged rows from the ledger only or re-verify them via `gh`?
- Should the no-pr row's link slot fall back to a branch compare URL when no tracking issue exists, or render `-`?

## Summary

Recommended: a flat pipe-line block headed by the verbatim marker `=== WORK IN FLIGHT ===`, one line per item in an extension of the coordination PR Index grammar (`- owner/repo#N | state-tokens | title | bare URL`), ordered attention-first with merged rows shown once then dropped, pre-PR items included via a `no-pr` state, and Renovate-style section headers added only above 6 items. It beats the GFM-table candidate decisively on clickability — markdown links lose their URLs in scrollback dumps, so bare URLs in the last field are mandatory — and beats the always-sectioned candidate on token cost at the typical 3-4 item scale. Push emissions and the `/status` render are byte-identical in shape (both regenerated fresh from ledger + live `gh`, per the F4 precedent), with `/status` adding only a mandatory freshness line and optional session history.
