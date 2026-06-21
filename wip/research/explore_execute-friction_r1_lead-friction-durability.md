# Lead: How should friction logs (and other "report-upstream" artifacts) survive `/execute`'s wip-cleanup + squash-merge? (Friction point F7)

## Findings

### 1. The wip-hygiene lifecycle is intentional and workspace-wide

The canonical rule lives in the workspace CLAUDE.md ("Temporary Artifacts (wip/)" section,
`/home/dgazineu/dev/niwaw/tsuku/tsuku-5/CLAUDE.md`):

- wip/ files are **non-durable**, committed to feature branches during workflows, and
  **removed from the branch before a PR can merge**.
- "PRs use squash-merge, so wip/ artifacts never appear in the main branch history."
- The rule is explicitly workspace-wide: "wip/ is a workflow primitive, not a CI artifact."

So a friction log placed at `public/niwa/wip/friction_execute_niwa-default-worktree.md` is, by
construction, designed to be ephemeral. Squash-merge alone guarantees it never reaches `main`,
**independent of any cleanup step**. The artifact's destruction was not a malfunction — it was
the wip/ contract operating exactly as specified. The real question is placement: where SHOULD a
report-upstream artifact live?

### 2. The cascade does NOT do a blanket `wip/` scrub

I read `skills/execute/scripts/run-cascade.sh` and the `plan_completion` state in
`skills/execute/koto-templates/execute.md`. The cascade's `git rm` targets are narrow and named:

- `skills/execute/scripts/run-cascade.sh:827-846` — "Step 3: git rm the PLAN" — deletes only the
  PLAN doc: `if git rm -f "$PLAN_DOC" ...`.
- `run-cascade.sh:476, 542-552` — `handle_roadmap_deletion` transitions the ROADMAP Active->Done
  and `git rm`s **the ROADMAP file** in the same atomic commit, gated by all-features-Done.
- `execute.md:350` (plan_completion) — "performs the atomic finalization commit (PLAN deletion +
  BRIEF/PRD/DESIGN transitions)". No directory-level `wip/` removal anywhere.

There is **no `rm -rf wip/`, no `git rm wip/friction_*`, no glob scrub** in the cascade. Confirmed
by grep across all skills: the only `wip/` deletions are per-skill, named-file `rm -f` calls in
*finalize* phases (e.g. `skills/strategy/references/phases/phase-5-finalize.md:160-164` deletes
`wip/strategy_<topic>_context.md` etc. by exact name). The `/execute` "Closed write-target set"
(`skills/execute/SKILL.md`, Security Considerations item 2) confines `/execute`'s own writes to
`wip/execute_<topic>_*`, the skill's files, the PR body via `gh`, the cascade transitions under
`docs/`, and Decision Records under `docs/decisions/`.

**Conclusion for instruction #2:** an arbitrary `wip/friction_*.md` is NOT deleted by the cascade.
It is carried off `main` by **squash-merge** (it lives on the feature branch and the squash collapses
it away). So F7 is a squash-merge consequence, not a cascade-deletion bug. Either way the file does
not survive to `main` at a queryable path — the practical outcome the friction log described is real.

### 3. Shirabe already has multiple durable-output conventions

Durable homes that already exist and are wired into skills:

- **`docs/decisions/` (Decision Records / ADRs).** Heavily used. `/scope`, `/charter`, `/design`
  write `docs/decisions/DECISION-...-<YYYY-MM-DD>.md` (e.g. `skills/scope/SKILL.md:182,376,449`,
  `skills/charter/references/templates/decision-record-*.md`). `/execute` itself already writes
  Decision Records under `docs/decisions/` on `re-evaluation` (per its Closed write-target set).
- **`docs/spikes/` (Spike Reports).** `/explore` writes `docs/spikes/SPIKE-<topic>.md`
  (`skills/explore/references/phases/phase-5-produce-deferred.md:46,101`) as the durable home for
  exploration findings that don't yet become a design.
- **`docs/guides/`** referenced (`skills/scope/references/phases/phase-2-chain-orchestration.md:293`).
- **`gh issue create`** is an established programmatic emit. `/plan` creates one GitHub issue per
  feature via discrete `gh issue create` args (`skills/plan/scripts/create-issue.sh:240-260`);
  `/roadmap` populate does the same (`skills/roadmap/SKILL.md:318-322`). So "file a GitHub issue
  programmatically" is a pattern shirabe already owns — it is not new machinery.

The notable gap: **none of these conventions covers a "report friction back to the skill repo"
artifact.** Decision Records and Spike Reports are about the *work product* in the consuming repo;
they are not the home for "the tooling I just ran has a rough edge." There is no
`docs/friction/`, no friction template, and no skill step that emits friction anywhere durable.

## Implications

**This is primarily a convention/doc gap, not an `/execute` bug.** The cascade behaved as designed;
squash-merge behaved as designed; the wip-hygiene rule is correct and should not change. What is
missing is a *placement convention* for report-upstream artifacts plus (optionally) a small
finalization affordance so the rule is hard to violate by accident.

Evaluating the three options from the lead:

- **(a) `/execute` surfaces wip/ contents / "anything to preserve?" prompt before cleanup.**
  Weak. It conflicts directly with `--auto` non-interactivity (a prompt cannot run unattended), and
  it fights the wip-hygiene contract by trying to rescue files the contract says are disposable.
  Even a non-interactive variant (dump wip/ listing to run output) only surfaces *paths* that are
  about to vanish — it does not give the content a durable home. Reject as the primary fix.

- **(b) A workspace convention: friction / report-upstream logs go to a durable path or a GitHub
  issue, NOT wip/.** Strong and cheap. This is the root cause. The friction log was put in the
  wrong place; a documented convention ("friction about a skill goes to a GitHub issue on that
  skill's repo, or to `docs/spikes/` / a durable note — never wip/") prevents recurrence with zero
  code change. Fits shirabe's existing pattern vocabulary.

- **(c) `/execute` emits a structured "run report" to a durable location as part of finalization.**
  Medium. Useful but heavier: it adds a new artifact type and a new write-target to `/execute`'s
  closed write set (currently a security-bounded list), which is a design-level change, not a
  one-liner. Worth considering as a follow-on, but not the lowest-ceremony fix.

**Lowest-ceremony durable home (instruction #5):** because a friction log's entire purpose is to
report *to the shirabe repo specifically*, **a GitHub issue on the shirabe repo is the natural,
lowest-ceremony durable home.** It is: (1) already a pattern shirabe owns (`gh issue create` in
`/plan` and `/roadmap`), (2) repo-correct (the report lands on the skill's own tracker, not buried
in a consumer repo's `docs/`), (3) immune to squash-merge and wip-cleanup entirely (it's not a file
on any branch), and (4) directly actionable (it becomes triage input). A durable file under
`docs/spikes/` or a `docs/` friction note is the fallback when filing an issue isn't possible
(no network, wrong repo), but the issue is the better default for cross-repo "report upstream."

**Recommendation: (b) as the direct fix, with the GitHub-issue home as the documented default;
(c) deferred to design if an automated, `--auto`-safe emit is wanted later.**

### Is it an `/execute` change, a convention/doc change, or both?

Primarily **convention/doc**. Concretely:

- **Direct-fix (doc/convention), no design needed:**
  - Add a short "report-upstream artifacts" convention. Candidate homes:
    - Workspace `CLAUDE.md` "Temporary Artifacts (wip/)" section
      (`/home/dgazineu/dev/niwaw/tsuku/tsuku-5/CLAUDE.md`) — add an explicit "friction / report-
      upstream logs do NOT go in wip/; file a GitHub issue on the relevant repo (or a durable
      `docs/` note)" carve-out. This is the canonical wip rule's natural home and the overlay
      mirrors it verbatim.
    - Optionally `skills/execute/SKILL.md` and/or the execute SKILL's user-facing notes, so a
      `/execute` author is told where to put friction the moment they hit it.

- **Needs-design (only if option (c) is pursued):** a `/execute` finalization step that auto-emits
  a structured run report to a durable location would touch `skills/execute/koto-templates/execute.md`
  (a new state or an extension of `plan_completion`) and `skills/execute/SKILL.md`'s Closed
  write-target set (Security Considerations item 2) — that set is a hard-bounded contract, so adding
  a write target is a deliberate design change, not an edit. Defer.

**Files that change for the recommended direct fix:**
- `/home/dgazineu/dev/niwaw/tsuku/tsuku-5/CLAUDE.md` (canonical wip rule — add the report-upstream carve-out)
- `skills/execute/SKILL.md` (point `/execute` authors at the durable home; small)
- (mirror) the private overlay's wip-rule fragment, per the canonical-wording sync note in CLAUDE.md

**Files that change only if (c) is pursued (design-gated):**
- `skills/execute/koto-templates/execute.md` (plan_completion / new finalization step)
- `skills/execute/SKILL.md` Security Considerations item 2 (widen closed write set)

## Surprises

- The cascade never touches `wip/` as a directory. I expected to find the "wip scrub" that the
  exploration framing implied; there is none. The destruction is **squash-merge**, not a delete
  step. F7's mechanism is subtly mis-attributed in the friction log ("the cascade cleans wip/") —
  the cascade only `git rm`s the PLAN and ROADMAP; squash-merge is what removes the friction file.
  The user-visible outcome (file gone post-merge) is identical, but the fix surface differs: there
  is no cleanup step to "delay until after capture," so option (a) has even less to grab onto than
  it appears.
- `/execute` *already* has a sanctioned durable-write channel into `docs/decisions/` (for
  re-evaluation Decision Records) and already uses `gh` to write PR bodies. So emitting a durable
  artifact at finalization is not foreign to its security envelope — `docs/decisions/` and `gh` are
  both inside the existing closed write set. A friction-as-Decision-Record or friction-as-gh-issue
  path is closer to "in-contract" than expected.
- Shirabe has no friction-artifact convention at all despite a rich docs/-artifact taxonomy
  (decisions, spikes, guides, plans, prds, designs, roadmaps, strategies). Friction-about-tooling is
  a genuinely unmodeled category.

## Open Questions

- Should the durable home be a **GitHub issue on the shirabe repo** (best for cross-repo "report
  upstream," already a shirabe pattern) or a **file under `docs/`** (survives offline, but lands in
  the *consuming* repo, which is the wrong tracker)? My read: issue-first, docs-note fallback.
- If option (c) is ever pursued, must the run-report emit be `--auto`-safe (fully non-interactive)?
  If yes, it cannot be a prompt; it must be an unconditional emit to a fixed durable location.
- Does the private overlay's wip-rule fragment need the same report-upstream carve-out to stay in
  verbatim sync (CLAUDE.md says the overlay copies the canonical wording)? Almost certainly yes.
- Is friction common enough across skills to warrant a shared `/file-friction` helper, or is a
  documented convention plus manual `gh issue create` sufficient? (Scope question for the synthesis.)

## Summary

F7 is a friction-log-*placement* convention gap, not an `/execute` bug: the cascade only `git rm`s
the PLAN and ROADMAP, and it is squash-merge (working exactly as the workspace wip-hygiene rule
intends) that carries any `wip/friction_*.md` off `main` — so the artifact meant for upstream
reporting was simply put in a location designed to be disposable. The lowest-ceremony durable home
is a **GitHub issue on the shirabe repo** (a pattern shirabe already owns via `gh issue create` in
`/plan` and `/roadmap`, repo-correct and immune to wip-cleanup), with a `docs/` note as the offline
fallback. The recommended direct fix is a convention/doc change (a "report-upstream artifacts go to
an issue/durable path, never wip/" carve-out in the canonical wip rule in
`/home/dgazineu/dev/niwaw/tsuku/tsuku-5/CLAUDE.md` plus a pointer in `skills/execute/SKILL.md`),
reserving an automated `/execute` run-report emit (option c) as a design-gated follow-on since it
would widen `/execute`'s security-bounded closed write-target set.
