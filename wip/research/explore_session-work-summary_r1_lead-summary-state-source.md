# Lead: What should the summary render from — conversation memory or durable state?

## Findings

### (a) Durable state that already records PRs / work items

**shirabe `/execute` — the home PR is already the durable source of truth.**
`public/shirabe/skills/execute/SKILL.md` (State section, lines 333-352) is explicit: the
`wip/execute_<topic>_state.md` file is "a reconstructable per-session projection, not the
source of truth. The durable source of truth is the **home pull request**." Cross-branch
resume (Resume section, lines 410-444) already reconstructs lost state from GitHub with a
topic-keyed lookup:

```bash
gh pr list --state open --search "<topic> in:title" --json number,title,headRefName
```

The state file's `child_snapshots:` field carries one entry per dispatched `/work-on` child
with the child PR's merge/head state read through `gh` metadata. So shirabe has already
decided this exact question once — for resume rather than for summaries — and chose
"gh-reconstructable, wip/ file is disposable cache."

**shirabe `/work-on` — PR URL passes through koto evidence, no wip ledger.** The
`pr_creation` state in `public/shirabe/skills/work-on/koto-templates/work-on.md` (lines
695-718) accepts `pr_url` as typed evidence. That lands in the koto event log, not in a
wip/ file. Single-issue runs have no on-disk PR record beyond koto.

**koto — records `pr_url` but deletes it at completion.** Koto state lives at
`~/.koto/sessions/<repo-id>/<name>/koto-<name>.state.jsonl` (event-log JSONL; per
`public/koto/README.md` lines 100-104). Critically: "When a workflow reaches its terminal
state, `koto next` automatically cleans up the session directory." Verified on this
machine: `~/.koto/sessions/` holds only stalled/in-flight sessions (e.g.
`issue_2264` has 6 events, last state `context_injection`, no `pr_url`); completed runs are
gone. Koto is therefore a good live-work source and a useless historical one.

**niwa mesh tasks — a `result` payload exists but PR content is convention, not schema.**
`public/niwa/docs/prds/PRD-cross-session-communication.md` R14/R24: tasks materialize at
`<instanceRoot>/.niwa/tasks/<task-id>/` and complete only via
`niwa_finish_task(outcome="completed", result=<arbitrary JSON>)`. Nothing requires the
result to carry a PR URL. `niwa task list` / `niwa task show` (README lines 132-133) can
enumerate them. This instance has no `.niwa/tasks/` populated — but it does have
`.niwa/sessions/<session-id>.json` at the workspace root
(`/home/dangazineu/dev/niwaw/tsuku/.niwa/sessions/`) mapping session_id → instance path,
with `"ephemeral": true, "origin": "dispatch"`. That's the key join: **niwa already knows
which instance belongs to which session**, so "PRs from this session" reduces to "PRs from
branches in this instance's repos."

**Coordination PRs — a real multi-PR ledger already exists for coordinated plans.**
`public/shirabe/references/coordination-strategy.md` (lines 87-116): the coordination PR
body carries a PR Index (`<node-id> | <owner/repo:path#number> | <merge-state>`) and a
fenced merge-order block, refreshed from live `gh` every pass. For coordinated efforts, the
"summary of work in flight" already exists as a durable, validated artifact — it just lives
on GitHub, not in chat.

**Git branches.** Verified: this fresh dispatched instance has zero non-main local branches
across its public repos. Because ephemeral instances start from clean clones, *any*
non-main local branch is by construction this session's work. Head-branch matching is a
precise per-instance reconstruction with no false positives from other sessions.

### (b) gh reconstruction queries — latency and cost (measured in public/shirabe)

| Query | Wall time | Notes |
|---|---|---|
| `gh pr list --author @me --state all --limit 5 --json ...,statusCheckRollup` | 0.91s | rollup returns per-check objects (name, conclusion, detailsUrl, timestamps) — ~1,500 tokens for 5 PRs. Accurate CI state but verbose; needs jq reduction. |
| same, compact (`number,title,state,url,headRefName` + template) | 0.57s | ~10 lines, ~300 tokens for 10 PRs. |
| `gh pr status` | 0.83s | Best cost/benefit per repo: current-branch PR + "Created by you" open PRs, each with a one-line check summary ("✓ Checks passing", "× 1/5 checks failing"). No JSON needed. Repo-scoped. |
| `gh search prs --author <user> --owner <org> --state open --limit 20 --json repository,...` | 0.97s | **One call covers every repo in the org.** But it returns ALL the user's open PRs — 17 here, most from prior weeks/other sessions — and it surfaces PRs in private repos the user can access, which a summary rendered in a public context must not leak. Author-filtering alone cannot scope to "this session." |
| `gh pr list --state all --head <branch>` | 0.26s | Precise; scales linearly (N branches x M repos, serial). Parallelizable with `&`. |

Two supporting observations:

- Shirabe PR #216 has head branch `session/9499fb68` — session-id-keyed branch naming
  already occurs in this workspace (remote/dispatched sessions), so head-branch matching
  can sometimes recover the session→PR link even without local state.
- `/work-on` branch prefixes are issue-keyed (`fix/`, `feature/`, `chore/` per
  `skills/work-on/references/phases/phase-1-setup.md`), `/execute` uses `impl/<slug>` —
  branch names identify the *work item*, and the instance identifies the *session*.

### (c) Architecture comparison

**(i) Pure instruction (model memory).** Zero infra, zero latency, zero tokens beyond the
rendered block. Fails exactly when the feature is needed most: long sessions get compacted,
and a compaction summary may drop or garble PR URLs; parallel/child agents open PRs the
parent never saw; status (CI, merged?) is stale the moment it's rendered. The workspace's
own design history (execute SKILL.md State section) explicitly rejected model/scratch
memory as source of truth for resume — the same argument applies to summaries.

**(ii) Session ledger file (append on PR open, render on demand).** Survives compaction
(it's on disk, re-readable). Cheap to render (~1 line/PR). But: it's a *second* bookkeeping
convention the model must remember to maintain (an instruction-reliability problem of the
same kind as (i), just smaller — one append at PR-open time vs. total recall at summary
time); it goes stale on status (a merged PR still shows "open"); it misses PRs opened by
children/koto/other tools unless every path writes it; and per the workspace wip-hygiene
rule (root CLAUDE.md), anything under `wip/` is deleted at cleanup and MUST NOT be
referenced from durable artifacts — fine for a session-lifetime ledger, but it will not
survive the session and cannot be linked from anything durable.

**(iii) Live gh reconstruction at summary time.** Always current (state, CI, merged).
Survives compaction trivially — nothing to remember except "how to ask." Costs ~0.3-1s per
query; a multi-repo sweep is 1 search call (~1s) or M `gh pr status` calls (~0.8s each).
Two gaps: (1) scoping — `--author @me` over-collects across sessions and can pull private
repo PRs into a public summary; (2) it can't see intent (a PR the session *plans* to open,
or why a PR exists).

**Hybrid (ledger for scope, gh for status) is the strongest shape**, and the workspace
already implements this pattern twice: `/execute`'s wip projection + home-PR refresh, and
the coordination PR's PR Index + live-`gh` re-derivation each pass. A session-work summary
would apply the same design at session scope: a tiny scope ledger (repo + PR number or
branch, appended at PR-open) and a render step that refreshes each entry via
`gh pr view <n> --json state,url,title,statusCheckRollup` or per-repo `gh pr status`.
The ledger solves gh's scoping gap; gh solves the ledger's staleness gap. A pure-gh
fallback exists when the ledger is missing (head-branch matching against the instance's
non-main branches — precise in ephemeral instances).

Reliability-under-compaction ranking: gh-reconstruction ≈ hybrid > ledger > instruction.
Token-cost ranking (per summary): ledger < hybrid ≈ compact-gh << statusCheckRollup-gh.

## Implications

- The convention should NOT rely on conversation memory as the record. Shirabe's own
  execute/coordination designs treat GitHub as the durable source of truth and on-disk
  state as a disposable projection; a summary feature should inherit that stance rather
  than invent a third model.
- The rendering primitive is cheap enough to run at any reasonable cadence: a compact
  per-repo `gh pr status` or a jq-reduced `gh pr list` is sub-second and a few hundred
  tokens. Cost is not the constraint; *scoping* is.
- The hardest sub-problem is "which PRs belong to this session," and niwa is the component
  best placed to answer it: ephemeral dispatched instances make "non-main branches in this
  instance's repos" a precise session fingerprint, and `.niwa/sessions/<id>.json` already
  joins session→instance. That argues for niwa (or a niwa-provided helper/hook) owning
  scope, while shirabe skills own the moment-of-creation append (they already capture
  `pr_url` as koto evidence — teeing that into a session ledger is one extra line).
- Visibility filtering must be part of the render step: `gh search prs --owner <org>`
  returns private-repo PRs, and a summary block pasted into a public artifact would leak
  them. A per-repo iteration over the instance's checked-out repos naturally respects the
  instance's visibility boundary; an org-wide search does not.
- Long-lived (non-ephemeral) workspaces weaken the branch fingerprint (old branches
  accumulate), which strengthens the case for the ledger half of the hybrid there.

## Surprises

- Koto *does* capture `pr_url` as typed evidence but deliberately destroys it: session
  directories are auto-cleaned at the terminal state (`koto next`), verified on this
  machine — only stalled sessions remain under `~/.koto/sessions/`. Koto is a live-work
  source only.
- A `session/<id>` head branch (shirabe PR #216) shows session-keyed branch naming already
  happens in this workspace for some session types — part of the scoping problem may
  already be solved by naming convention, unevenly.
- The coordination PR's PR Index is essentially the requested "standardized summary of
  work in flight, with links and status" — already specified, validated
  (`shirabe validate --coordination-body`), and refreshed from live gh. The exploration
  may be generalizing an existing artifact downward to ordinary sessions more than
  designing something new.
- `gh search prs` over the org is a single ~1s call for all repos — cheaper than expected —
  but its author-scope over-collection (17 open PRs, weeks old) and private-repo bleed make
  it the wrong default despite the attractive economics.

## Open Questions

- Where should the session ledger live for non-ephemeral sessions — `wip/` (deleted at
  cleanup, fine for session lifetime), the niwa instance dir (`.niwa/`, outside any repo,
  survives repo cleanup, multi-repo by construction), or Claude Code session state? The
  `.niwa/` option looks best for multi-repo scope but couples the convention to niwa.
- Can a hook (PostToolUse on `gh pr create`, or a niwa hook) do the ledger append
  mechanically, removing the last instruction-reliability dependency? That would make the
  hybrid fully mechanical: hook-appended scope + gh-refreshed status.
- What should the summary include for *planned-but-not-yet-opened* work (in-flight koto
  states before `pr_creation`)? Koto's live sessions can answer this, but only while
  in flight and only per-repo.
- Cadence was out of scope for this lead, but the state sources constrain it: gh refresh
  is cheap enough for every-N-turns; the ledger append is event-driven (PR open). Whether
  the render trigger is a hook, a skill step, or an instruction remains open.
- Does `niwa_finish_task`'s `result` payload need a lightweight convention (e.g. a
  `prs: []` field) so delegated background work reports PR outcomes structurally?

## Summary

The workspace has already answered this question for resume: GitHub (the home PR /
coordination PR Index) is the durable source of truth and on-disk wip state is a
disposable projection — and measured gh queries are cheap enough (0.3-1s, a few hundred
tokens compact) to make live reconstruction the status source for summaries too. The main
implication is a hybrid: a small event-driven scope ledger (or, in ephemeral niwa
instances, the non-main-branch fingerprint, since niwa already joins session→instance)
plus a gh refresh at render time, because author-scoped gh queries over-collect across
sessions and can pull private-repo PRs into public contexts. Biggest open question:
where the session-scoped ledger should live (wip/ vs. the niwa instance dir) and whether
a hook can maintain it mechanically instead of by instruction.
