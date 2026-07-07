---
schema: prd/v1
status: Done
problem: |
  In long agent sessions that open multiple pull requests, often across several
  repositories, PR links scroll out of reach and no reliable surface recovers
  them. The developer driving the session cannot answer "what is in flight right
  now, and where is it?" without hunting through the transcript, and dispatched
  background workers leave the answer buried in a transcript nobody re-reads.
goals: |
  Give the session a single standardized, findable summary of the pull requests
  it has touched — state, CI status, and a clickable link per item — that
  appears when the PR set changes, on return after a break, on demand, and in a
  background worker's final message. The summary reflects real PR state rather
  than the agent's recollection, and never degrades into per-message noise.
upstream: docs/briefs/BRIEF-session-work-summary.md
motivating_context: |
  A five-round exploration compared candidate architectures, prototyped and
  validated the chosen one against Claude Code 2.1.201, and surfaced a
  data-integrity hazard: fabricated PR references pollute the harness's own
  native surfaces (footer badges, the session-list PR chip). This PRD captures
  the requirements that exploration settled, deferring architecture to the
  design doc.
---

# PRD: Session Work Summary

## Status

Done

## Problem Statement

A working session with an AI coding agent routinely produces several pull
requests — sometimes within one repository, sometimes spread across a multi-repo
workspace. Each PR's link is printed once, at creation, then scrolls away as the
session continues. When the developer needs that link again — to review, to
share, to check CI — the only recourse is scanning the transcript by eye.

The people affected are developers running long or PR-dense sessions, and
developers who dispatch background workers and check results later. The harness's
own affordances do not close the gap: the footer PR badge reflects only the
current branch and disappears on merge; reverse-search covers the user's prompts
but never the agent's output; session recaps carry no structured links; and a
dispatched worker's only durable trace is a transcript the user rarely reopens.
An investigation during this feature's exploration also found that the
session-list PR chip can show a count with no way to see the underlying PRs, and
that stray PR-shaped references in a transcript can inflate that count — so the
one native surface that hints at "how many PRs" is both unlistable and
untrustworthy.

The result is a paradox: the more productive a session is, the harder it becomes
to keep track of the work it produced.

## Goals

- A developer can, at any point in a session, see the full set of pull requests
  the session has touched, each with its current state, CI/review status, and a
  usable link — without scrolling back through the transcript.
- That view appears at the moments it is needed (after a PR changes, on return
  from a break, on request, at a worker's completion) and stays quiet otherwise.
- The view is trustworthy: it reflects live PR state, and it never shows a PR
  the session did not actually produce.
- The view is consistent: it reads the same wherever it appears, so a user
  learns one shape and can find it again by searching for it.
- The capability works in single-repo and multi-repo workspaces, and respects
  the visibility boundary between public and private repositories.

## User Stories

- As a developer in a long interactive session, I want the current set of my
  session's PRs to reappear whenever one is opened or its status changes, so
  that I always have a current, clickable list without asking.
- As a developer returning to a session after time away, I want a refreshed
  summary on my next exchange, so that I can re-orient in one glance before
  continuing.
- As a developer who remembers a PR was opened earlier, I want to find the most
  recent summary by searching the transcript for a consistent landmark, so that
  I can recover the link even in a long history.
- As a developer, I want to ask for the current status on demand and get an
  up-to-date list, so that I can check in between events without waiting for one.
- As a developer who dispatched a background worker, I want its final message to
  carry the summary of PRs it produced, so that I can see the outcome from the
  session dashboard without attaching to it.
- As a developer whose agent is answering questions about in-flight work, I want
  the agent's own answers to reflect the real PR set, so that its narrative and
  the summary do not disagree.

## Requirements

### Functional

- **R1** — The system SHALL define a single standardized summary block with a
  fixed, constant leading marker line and one entry per pull request the session
  is tracking. All emissions of the summary — automatic, on-demand, and in a
  worker's final message — SHALL use this same block shape.
- **R2** — Each entry SHALL carry, at minimum: the owning repository identity,
  the PR number, the PR state (for example open, draft, merged, closed), a
  CI/review status indication, a short title, and the PR's full URL. The full
  URL SHALL be present on each entry in a form that remains selectable and
  clickable when the transcript is viewed as plain text.
- **R3** — Entries SHALL be ordered so that items needing attention appear
  before settled ones, and an item that has reached a terminal state (merged or
  closed) SHALL appear in at most one summary after reaching that state and then
  be dropped from later summaries.
- **R4** — The summary's data SHALL be derived from authoritative PR state at
  render time, not replayed from a prior emission or reconstructed from the
  agent's memory. A summary MUST reflect the current state of each item it lists.
- **R5** — Only pull requests the session actually produced or acted on SHALL
  appear in the summary. The system MUST NOT emit a PR reference that does not
  correspond to a real pull request, because fabricated references corrupt both
  the summary and the harness's native PR surfaces.
- **R6** — An automatic summary SHALL be emitted when the tracked PR set changes
  or an item's state changes (a PR is opened, merged, closed, or its CI/review
  status changes). The summary SHALL be emitted as a distinct, self-contained
  element, not appended to unrelated responses.
- **R7** — A summary SHALL be emitted on the first exchange after the session
  has been idle for a configurable absence threshold, to support re-orientation
  on return. It SHALL NOT be emitted on a fixed timer or per-turn cadence
  independent of state change or return.
- **R8** — Repeated automatic emissions SHALL be suppressed when neither the PR
  set nor any item's state has changed since the last summary, so that the
  summary does not become per-message noise.
- **R9** — The system SHALL provide an on-demand way for the user to request the
  current summary, which regenerates the block from live state and indicates how
  fresh the data is.
- **R10** — The agent SHALL be kept aware of the current tracked PR set so that
  its conversational answers about in-flight work stay consistent with the
  summary, and this awareness SHALL be restored after the session's context is
  compacted.
- **R11** — For dispatched or background sessions, the summary of PRs the session
  produced SHALL appear in the session's final message, so that it is visible
  from the session's post-run surfaces without attaching to the session.
- **R12** — In a multi-repo workspace, each entry SHALL identify its repository,
  and summary collection SHALL respect per-repository visibility such that a
  private repository's PR is never surfaced into a public-visibility context.

### Non-functional

- **R13** — Generating a summary SHALL complete quickly enough to be used at
  interactive cadence (sub-second under normal conditions for a handful of PRs),
  and SHALL degrade gracefully when live PR state cannot be reached, producing a
  clearly-marked best-effort summary rather than failing the turn.
- **R14** — The summary's format SHALL remain legible across common terminal
  widths, including when lines wrap, without breaking the usability of the URL
  on each entry.
- **R15** — The per-emission cost of keeping the agent aware of the PR set SHALL
  be bounded and small relative to the session's context budget (on the order of
  a few hundred tokens per emission for a typical handful of PRs), and the
  emission policy SHALL favor signal over volume.

## Acceptance Criteria

- [ ] A summary block with the fixed marker and per-item entries (repo, PR
      number, state, CI/review status, title, full URL) is produced, and the
      same shape is used for automatic, on-demand, and final-message emissions.
- [ ] Opening a PR, and later a change to that PR's state or CI status, each
      cause an automatic summary to appear as a self-contained element.
- [ ] After the configured absence threshold, the next exchange leads with a
      refreshed summary; below the threshold, ordinary exchanges do not.
- [ ] When neither the PR set nor any item's status has changed, no duplicate
      automatic summary is emitted.
- [ ] A merged or closed PR appears in one summary after the transition, then no
      longer appears in subsequent summaries.
- [ ] The on-demand request returns a block regenerated from live state with a
      freshness indication.
- [ ] Every entry's URL corresponds to a real pull request; no summary emits a
      PR reference that does not resolve to an actual PR.
- [ ] A PR-shaped reference that appears in the conversation but was not produced
      or acted on by the session (for example a URL quoted in passing) does not
      enter the summary.
- [ ] A summary rendered while live PR state is unreachable is clearly marked as
      best-effort and does not abort the turn, and the same summary is produced
      within an interactive-cadence time budget under normal conditions.
- [ ] The summary remains legible and each entry's URL stays usable when the
      block is rendered at a narrow terminal width where lines wrap.
- [ ] In a multi-repo workspace, entries name their repository, and a
      private-repo PR does not appear in a public-visibility summary.
- [ ] A dispatched worker's final message contains the summary of the PRs it
      produced.
- [ ] After context compaction, the agent can still answer correctly about the
      current tracked PR set.

## Out of Scope

- Modifications to Claude Code itself. The feature relies on existing extension
  points; anything requiring a change to the harness (for example the data
  source behind the session-list PR chip) is excluded.
- Timed or turn-count digests. Emission is tied to state change and to
  return-after-absence only; nothing fires on a schedule detached from those.
- Shipping always-on display surfaces that live in user-level configuration
  (persistent status-line renderers, configurable footer link badges). These may
  be documented as optional personal companions, but they are not deliverables
  and no requirement depends on them.
- Team-facing notification fan-out (chat digests, email). This is a single-user,
  in-session capability.
- Correcting the workspace tooling defect in which a hook registered through
  both declared configuration and auto-discovery loses its matcher. That fix is a
  prerequisite tracked separately, not part of this feature.
- Summarizing work that never becomes a pull request (ad-hoc edits, analysis
  sessions). A pushed branch enters the summary only once it corresponds to
  tracked PR work.

## Known Limitations

- The most reliable always-visible surfaces (a persistent status line, footer
  link badges) are configured at the user level and cannot be shipped by the
  feature; users who want an ambient view must opt in themselves. The feature
  therefore centers on the in-conversation summary and the on-demand command,
  which work without user-level configuration.
- The harness's native session-list PR chip is outside the feature's control:
  the feature can ensure the worker's transcript carries an accurate summary, but
  it cannot change what the chip counts or make it expandable.
- Background sessions surface the summary through their transcript and final
  message rather than any live, ambient channel, because no such channel is
  available to a session no one is watching.

## Decisions and Trade-offs

- **Event-driven and return-triggered emission, not periodic.** Timed and
  turn-count digests were evaluated during exploration and rejected: they fire
  when nothing has changed and miss the moments that matter. Emission is bound to
  state change and to return-after-absence. Trade-off: a summary will not appear
  during a long stretch of unrelated work even if the user would have glanced at
  it; the on-demand command (R9) covers that case.
- **Live-state derivation over a remembered ledger.** The summary is recomputed
  from authoritative PR state (R4) rather than replayed, mirroring the existing
  coordination-PR discipline where state is recomputed rather than trusted from
  prior text. Trade-off: each render pays a small live-data cost (bounded by
  R13) in exchange for never showing stale status.
- **Data integrity as an explicit requirement (R5).** The exploration found that
  fabricated PR references inflate the harness's footer badges and session-list
  chip. Rather than treat this as incidental, the PRD makes "only real PRs
  appear" a testable requirement, because the failure mode corrupts surfaces
  outside the feature's own output.
- **Ambient display surfaces documented, not shipped.** Status-line and footer
  badge surfaces are user-configuration-scoped; the feature cannot deliver them
  and does not depend on them. They are recorded as optional companions so the
  boundary is explicit and downstream design does not treat them as in-scope.
- **The BRIEF carried no unresolved Open Questions.** The upstream framing was
  settled before this PRD; no deferred questions needed closure here.

## Amendment — 2026-07-06: opt-out default and a complete cross-repo summary

Two defects observed after the feature shipped drive new requirements. The
requirements above are unchanged; these extend them. Both defects share one root
cause — a session in a workspace that never registered the capture hook records
no PRs, so it gets no ambient summary, and its on-demand summary, asked for while
the shell was inside a single repo, listed only that repo's PRs even though the
session had PRs in flight across several repos. The summary was **incomplete**,
so the agent appended the missing cross-repo PRs to make the answer whole. The
defect is the incompleteness; the agent's amendment is the symptom that exposed
it. The upstream BRIEF amendment of the same date frames the two together.

### New Requirements

#### Functional

- **R16 — Default-on ambient behavior for shirabe adopters, with an off switch.**
  The ambient work-summary hooks SHALL be present by default in a
  niwa-provisioned instance **for the repos and workspaces that install the
  shirabe plugin**, so a shirabe adopter receives the summary behavior without
  registering the hooks by hand. The default SHALL be gated on shirabe-plugin
  installation: a workspace that does not install shirabe SHALL NOT receive the
  hooks, since the work-summary feature belongs to shirabe and the ambient hooks
  travel with the plugin rather than being injected into every provisioned
  instance. A workspace that does install shirabe SHALL be able to turn the
  behavior off through an explicit, documented switch. Default-on is bounded by
  two further facts the requirement states rather than hides: the ambient summary
  takes effect only where the render component is also available on PATH (the
  hooks fail safe to no-op otherwise), and only in instances niwa provisions.
  Flipping opt-in to opt-out — scoped to shirabe adoption — closes the gap where
  a shirabe-using workspace that never adopted the registration got nothing, and,
  because capture is what populates the cross-repo session ledger, it is the
  precondition for R17's complete on-demand summary.
- **R17 — The on-demand summary is complete across the session's repos.** The
  on-demand summary SHALL report every pull request the session has in flight
  across all repositories the session touched, independent of which repository
  the session's shell is currently in. The authoritative source for this is the
  cross-repo session ledger, which lists a PR the session opened in any repo. The
  summary MUST NOT present a single-repository subset as though it were the
  session's full set of in-flight PRs. This corrects the observed defect where a
  session spanning multiple repos, asked for its summary from inside one repo,
  received only that repo's PRs.
- **R18 — Honest labeling of the degraded, repo-scoped view.** When the session
  ledger is empty or unreachable and the on-demand path can only produce a
  repo-scoped listing (only the current repository's PRs), the block SHALL state
  plainly that it is a partial, current-repository-only view that may omit this
  session's PRs in other repositories — so the reader understands it as
  incomplete rather than whole. The repo-scoped fallback SHALL remain
  fail-closed and MUST NOT widen into an author-scoped cross-repo search, which
  would over-collect PRs across sessions and risk pulling a private-repo PR into
  a public-visibility context (PRD R12); the way to make the summary complete is
  to capture the session's PRs into the ledger (R16), not to broaden the
  fallback's query.
- **R19 — No unverified PR reference around the block.** As a guardrail paired
  with R17-R18, no pull-request reference SHALL be appended around the block on a
  model-framed surface (the on-demand relay, a dispatched worker's final
  message) unless it corresponds to a real captured PR the block itself lists. A
  cross-repo item the component did not capture SHALL NOT be reconstructed from
  the agent's memory into free text — the same real-PR-only guarantee R5 makes
  for the block's contents. This guardrail exists so that a degraded, honestly
  labeled block (R18) is not quietly "completed" with unverified references; it
  is the safety net, while R16-R17 are the actual fix for completeness.
- **R20 — Consistent session keying.** The session identity the on-demand render
  keys on and the identity the capture path keys the ledger by SHALL be the same,
  so a session that did capture PRs renders its complete ledger and is never
  pushed to the degraded fallback by a keying mismatch.

### New Acceptance Criteria

- [ ] A freshly provisioned niwa instance that installs the shirabe plugin emits
      the ambient summary without the workspace hand-registering the hooks, and a
      documented off switch suppresses it.
- [ ] A provisioned instance that does NOT install the shirabe plugin receives no
      work-summary hooks.
- [ ] Where the render component is absent from PATH, the default-on hooks
      no-op and never abort a turn.
- [ ] A session that opened PRs in two or more repositories, asked for its
      on-demand summary from inside one of them, lists all of the session's
      in-flight PRs across every repo — not just the current repository's.
- [ ] A session that captured its PRs into the ledger renders from the ledger
      and does not fall back to the repo-scoped listing.
- [ ] When the ledger is empty or unreachable, the repo-scoped fallback block is
      clearly labeled as a partial, current-repository-only view that may omit
      the session's PRs in other repos; it does not present itself as complete
      and does not widen into an author-scoped cross-repo search.
- [ ] No PR reference appears around the block, on the on-demand relay or a
      worker's final message, that does not correspond to a real captured PR.

### Updated Known Limitations

- Default-on reaches only shirabe adopters: instances that install the shirabe
  plugin, that niwa provisions, and where the render component is on PATH. A
  workspace that doesn't install shirabe, one niwa does not manage, or one
  without the component installed sees nothing — opt-out changes the default
  within the intersection of shirabe adoption and niwa's reach, not beyond it.
- Cross-repo completeness (R17) depends on capture having run for the session's
  PRs. When capture never ran (R16 off, or component absent) the on-demand path
  can only offer the honestly-labeled partial view (R18); it cannot safely
  reconstruct the full cross-repo set from `gh` alone without risking the R12
  visibility violation. Completeness is a property of the ledger, so it follows
  capture.
- The R19 no-unverified-reference guardrail is enforceable on the component's
  output and the skill contract, but the background-worker final-message path
  still has a model authoring the surrounding message; the guarantee there is a
  required instruction plus the block's self-describing labeling, not a
  mechanical impossibility, consistent with the existing R11 final-message
  limitation.
