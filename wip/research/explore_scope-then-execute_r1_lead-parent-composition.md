# Lead: How do shirabe's parent skills compose, and is there a precedent for one parent chaining into another?

## Findings

### 1. /charter does not hand off into /scope at all

`skills/charter/SKILL.md` names three children (`/vision`, `/strategy`, `/roadmap`, plus conditional feeder `/comp`) and never invokes, recommends, or spawns `/scope`. Its closed write-target set (SKILL.md:341-356) contains no handoff file for `/scope`. The only coupling between the two is file-based: `/scope --upstream <ROADMAP path>` consumes a ROADMAP the strategic chain produced (skills/scope/SKILL.md:183-200). Even `/roadmap`'s own "suggest next steps" table (skills/roadmap/SKILL.md:297-303) points at `/prd`, `/design`, `/plan` — not at `/scope` — which looks like pre-`/scope` staleness.

So the strategic-to-tactical boundary is a *file handoff the author crosses by hand*, not an auto-continue, a recommendation, or a spawn.

### 2. The pattern's only statement on parent-to-parent composition is "file-handoff between parents"

`references/parent-skill-pattern.md:399-421` defines `team_primitive: single-team-per-leader-no-nested` with three consequences. Consequence 2 is **"File-handoff between parents. Downstream parents read upstream parents' artifacts from `docs/<type>/<TYPE>-<topic>.md` ... There is no live-team query interface in v1."** The same text appears in `docs/designs/current/DESIGN-shirabe-progression-authoring.md:713`.

This describes *how* a downstream parent reads an upstream parent's output. It does not prohibit one agent session from running two parents back to back; it prohibits a parent reaching into another parent's live team. The pattern's invariants (I-1..I-7, parent-skill-pattern.md:40-76) are all per-run: recorded exit, durable terminal artifact, child-isolated resume, topic-keyed state, conditional-field gating, cross-branch resume, active orchestration. None of them says "a parent SHALL NOT be followed by another parent in the same session."

The pattern also has a "parent-of-the-parent" concept (parent-skill-pattern.md:422-445; charter SKILL.md:55-58: "The parent-of-the-parent (the agent invoking the skill) calls `/charter` directly"). That's the slot a scope-then-execute driver would occupy: an agent that calls `/scope`, then calls `/execute`. It's already contemplated as "the agent invoking the skill", just never as a skill of its own.

### 3. No recorded decision says parents must not chain

I searched docs/decisions (7 files), docs/designs/current, docs/prds, docs/briefs, and references/ for "chain into", "hand off", "--execute", "end-to-end", "one session", "--continue", "--through", "run-to-merge", "umbrella", "auto-continue", "parents do not", "invoke the parent". There is no decision record, PRD requirement, or design decision that forbids a `/scope` -> `/execute` continuation. There is also no documented `--continue`, `--through`, `--execute`, `run-to-merge`, or umbrella command concept anywhere in the repo.

The nearest recorded rules are:

- **"Parents do not extend children's input surfaces"** (DESIGN-shirabe-progression-authoring.md:1375; DESIGN-shirabe-scope-skill.md:515, 567, 1419; restated in skills/execute/SKILL.md "Execution-Mode Flags": `/execute` adds no flags to `/work-on` children; autonomy reaches children only via `parent_orchestration:`). This matters if the continuation were implemented by `/scope` invoking `/execute` as a child with a new flag. `/execute` isn't `/scope`'s child, so the rule doesn't strictly bind, but its spirit (don't grow a callee's argument surface to serve a caller) argues against adding e.g. `/execute --from-scope`.
- **"Neither arm invokes its parent"** in `/explore`'s handoff (skills/explore/references/phases/phase-5-produce-handoff.md:1-6, 166-172). This is the strongest precedent *against* auto-invocation, and its rationale is specific: the parent must consume the handoff "through its own resume ladder, below re-entry protection ... That ordering is what lets a settled artifact on disk win over a handoff written last week, and `/explore` cannot reproduce it by invoking the parent mid-session." The same stop-and-name-the-command shape is used by `/explore`'s execute arm (phase-5-produce-execute.md:18-34: "the author runs `/execute <plan-path>` separately") and is described in DESIGN-scope-chain-mandatory-steps.md:574-582. Note the rationale is about entering the parent *through its resume ladder*, not about a separate session being required; a driver that invokes `/execute <PLAN>` via the Skill tool still enters through `/execute`'s own Phase 0 and resume ladder, so the rationale is satisfiable.
- **Mode ownership (PRD-execute-skill.md D2, D5; lines ~285-320):** single-pr and coordinated belong to `/execute` because they have a session-scoped ephemeral home (the single PR / the coordination PR); multi-pr has none and is "excluded on principle" — it runs as independent per-issue `/work-on` runs against a repo-persisted PLAN. Whether `/work-on` offers "a thin sequential convenience loop over a milestone's issues" is left as a downstream design detail (D5).

### 4. There IS a precedent for skill-to-parent hand-off: the /work-on dispatcher

`/work-on <PLAN>` is a thin dispatcher (skills/work-on/SKILL.md:120-141; DESIGN-execute-skill.md Decision 2, "Routing — thin dispatcher (chosen, R1)"): it reads `execution_mode`, runs multi-pr in place, and for single-pr/coordinated "hand[s] off to `/execute`" — but the actual text says "direct the caller to invoke `/execute <PLAN>`". DESIGN-execute-skill.md:186 describes entry as "`/execute <PLAN>` directly, or handed off by the /work-on dispatcher". So the implemented shape is again *redirect*, not spawn. The redirect is keyed on exactly the enum the user's question turns on.

Separately, `/execute` spawning `/work-on` per issue (materialized koto children) is the one place a parent drives a skill that is itself a full workflow; the pattern had to widen its Dispatch Mechanism to carry two Layer-2 bindings for it (parent-skill-pattern.md:506-531).

### 5. The practiced workflow already is "/scope, then /execute on the same branch"

The branch model was deliberately built to make `/scope` -> `/execute` continuous:

- `/scope` refuses to run on the default branch (koto `branch_check` state; skills/scope/references/phases/phase-0-setup.md:64-75) and commits each hop's artifact on that feature branch (phase-2-chain-orchestration.md Per-Hop Commit, ~497-535). "Nothing pushes" (skills/scope/SKILL.md:505-508).
- `/execute`'s `orchestrator_setup` checks for an open PR on the current non-main branch and, if one exists, **adopts** "the author's or `/scope` branch ... including a `docs/<topic>` scoping PR" as the home PR (skills/execute/SKILL.md ~271-276; skills/execute/koto-templates/execute.md `## orchestrator_setup`). `settled_branch_record` then pins children to that branch.
- `docs/guides/execute-friction.md:17-33`: "if you ran `/scope` and are sitting on its branch, just run `/execute` from there. Your implementation lands on the scoping PR you already have."
- `docs/briefs/BRIEF-settled-branch-record.md` motivating context: the bug was "Found running /execute --auto against a twelve-issue single-pr PLAN, on a docs/<topic> scoping branch with an open PR." So the scope-then-execute-on-one-branch path is exercised in practice.
- For coordinated, the coordination PR is created up front by `/scope` ("The coordination PR is created up front, before any child runs", skills/scope/SKILL.md:202-225) and consumed by `/execute` ("coordination home up front stays /scope's responsibility; /execute consumes it", PRD-execute-skill.md:174, DESIGN-execute-skill.md:177). BRIEF-capstone-orchestration.md frames `/scope` + execution as one effort "from framing to merged code" with one durable home. That is the clearest existing precedent for a single effort spanning two parents.

### 6. Where /scope's run ends and what it tells the user

- `/scope` terminal states (`done_full_run` etc., skills/scope/koto-templates/scope.md:1324-1345) carry no next-step recommendation. Phase 4's success summary is a single line, `/scope finished: exit=...; artifact=...` (phase-4-cleanup.md "Success Summary").
- The only next-step hint a user sees comes from `/plan`'s Phase 7 (run inline inside `/scope`): single-pr says "Run `/work-on docs/plans/PLAN-<topic>.md` to begin implementation" (skills/plan/references/phases/phase-7-creation.md:365, 530); multi-pr lists ready issues. That routes through the `/work-on` dispatcher, which then redirects single-pr/coordinated to `/execute`. So today it's a two-hop redirect.
- `plan_execution_mode:` is recorded in `/scope`'s state at full-run exit (phase-3-exit-finalization.md:43-65; scope.md:967, 1091), with values `single-pr | multi-pr | coordinated`. AC8b of PRD-shirabe-scope-skill.md:1094 says `/scope` does NOT pre-decide it — `/plan` does. But Phase 4 deletes the state file, so the recorded mode survives only in the PLAN frontmatter (`execution_mode:`), which is exactly what `/execute` and the `/work-on` dispatcher read anyway.

### 7. Constraints a /scope -> /execute continuation must respect

- **State files:** separate, topic-keyed (I-4): `wip/scope_<topic>_state.md` vs `wip/execute_<topic>_state.md`; koto sessions `scope-<topic>` vs `execute-<plan-slug>`. `/scope`'s Phase 4 removes its wip before `/execute` starts, so there's no collision, but the continuation must start `/execute` only after `/scope` reaches `done_full_run` (not `done_re_evaluation` / `done_abandonment` / `done_cancelled`). Never cancel a session the run didn't open (scope SKILL.md:302-304).
- **`parent_orchestration:` sentinel:** a parent writes it only when invoking its own child. `/execute` unconditionally clears a stale one at Phase 0. A driver running `/scope` then `/execute` shouldn't write one into either (it isn't a child dispatch).
- **Branch model:** single-pr works cleanly only if the scoping branch has an open PR when `/execute` starts; otherwise `orchestrator_setup` falls to the fresh path and `git checkout -b impl/<slug>` from HEAD, producing a second branch/PR (execute.md `orchestrator_setup` script). Since `/scope` never pushes, the continuation needs a "push + open draft PR" step between the two, or it accepts `impl/<slug>`.
- **Child inspection (R14):** a driver above both parents should read only durable artifacts and status: the PLAN's `execution_mode` frontmatter and `/scope`'s `exit:`/success line, never `/scope`'s wip internals.
- **Resume-ladder entry:** the `/explore` rationale requires the downstream parent to be entered through its own Phase 0 / resume ladder. Invoking `/execute <PLAN path>` (not jumping into its template) satisfies this.
- **Altitude boundary for multi-pr:** `/execute` refuses multi-pr and redirects to `/work-on` (execute SKILL.md Input Modes). `/scope`'s Slot 5.1 refuses re-entry against an Active PLAN and redirects to `/work-on` (phase-resume.md:18-25). A multi-pr landing therefore has no plan-level coordinator by design (PRD-execute-skill D2/D5); a one-session "done when merged" goal would have to either loop `/work-on` per issue itself (the "thin sequential convenience loop" D5 leaves open) or stop and report.
- **Interactive pause:** in interactive mode `/execute` stops at `paused_for_review` before the cascade (execute SKILL.md D2). A one-session run-to-merged goal needs `--auto` (or the "run autonomously"/"don't stop" instruction that resolves to the same thing).

### 8. /goal spike is the nearest "umbrella" concept

`docs/spikes/SPIKE-claude-code-goal-integration.md` (Complete) positions Claude Code's `/goal` as a session-level loop orthogonal to shirabe workflows, and lists composition opportunity 1 as "Wrap `work-on` with /goal ... 'PR for issue #N merged and CI green'" and 2 as "all ready issues from DESIGN-X.md merged". It recommends deferring each to its own design. That's the only documented place something like "run until merged" is proposed as a wrapper; it's not a shirabe skill.

## Implications

A `/scope` -> `/execute` continuation in one session would not violate any recorded decision. The pattern explicitly anticipates a "parent-of-the-parent" agent that invokes parents, and requires only that parents hand off through durable files, which a PLAN on disk already is. The one recorded "don't invoke the next parent" rule (`/explore`'s handoff arms, and by imitation the `/work-on` dispatcher) is justified by resume-ladder ordering, which a continuation that invokes `/execute <PLAN>` through its normal entry still honors.

The cleanest shape is a driver above both parents (the session itself, or a thin skill) that runs `/scope`, reads the resulting PLAN's `execution_mode`, and for single-pr/coordinated opens/pushes the scoping PR and invokes `/execute <PLAN> --auto`. Building it into `/scope` as a new flag or into `/execute` as a new input mode would cut against "parents do not extend children's input surfaces" in spirit and would blur the altitude split the trio was built around (charter strategic / scope tactical / execute implementation). For multi-pr, the documented answer is that there is no plan-level coordinator; the session would have to loop `/work-on` per unblocked issue (the open D5 convenience loop) or stop after `/scope` and name the command.

## Surprises

- **`/execute` never merges.** Its SKILL.md and DESIGN say full-run is "the single PR merges (done-signal)", but the koto template's last states are `plan_completion` -> `ci_monitor` -> `done` on green CI with the PR ready (execute.md `ci_monitor`, `done`). There's no `gh pr merge` anywhere in skills/execute or skills/work-on. "Done only when merged" needs a merge step nothing currently owns (single-pr); for coordinated, merge-last is gated but the actual merge still isn't in the template.
- **`/scope` "nothing pushes", yet `/execute`'s adopt path and the execute-friction guide assume `/scope` leaves you on a branch with an open PR**, and `/scope` Phase 3 writes the chain record "into the run's pull-request body". Who opens that PR in the non-coordinated case is unstated.
- **`/plan` still tells single-pr users to run `/work-on docs/plans/PLAN-<topic>.md`** (phase-7-creation.md:365, 530), a two-hop redirect through the dispatcher, rather than `/execute`.
- **`/scope`'s resume Slot 5.1 redirects every Active PLAN to `/work-on`** (phase-resume.md:18-25), but coordinated PLANs are also Active and belong to `/execute`; the `/work-on` dispatcher would bounce it again.
- **Schema drift:** `references/parent-skill-state-schema.md:89-91, 231-235` lists `plan_execution_mode` values as `single-pr | multi-pr`, while `/scope`'s template and Phase 3 accept `coordinated` too.
- `/roadmap`'s next-step table predates `/scope` and points at `/prd`/`/design`/`/plan` individually.

## Open Questions

- Should the continuation live in a new thin driver skill, in a documented session recipe (e.g. `/goal` wrapping `/scope` then `/execute --auto`), or nowhere (keep stop-and-name-the-command)?
- Who pushes the scoping branch and opens its PR between `/scope` and `/execute` so the adopt path fires?
- Who performs the final merge, and is an agent allowed to merge its own PR? This is outside both parents today.
- For multi-pr, does the one-session goal loop `/work-on` per issue until the milestone closes (the unresolved PRD-execute-skill D5 convenience loop), or stop?
- In `--auto`, `/plan` picks the mode inside `/scope`; does the author want to confirm the mode before implementation starts, since it decides whether the session can finish at all?

## Summary

No recorded decision forbids one session running `/scope` then `/execute`. The pattern treats parents as file-handoff peers that a "parent-of-the-parent" agent invokes, and the branch model (`/execute` adopting the `/scope` branch/PR; coordinated `/scope` creating the coordination PR that `/execute` consumes) was built to make that continuation seamless. The existing precedent, though, is always stop-and-name-the-command (`/explore`'s "neither arm invokes its parent", the `/work-on` dispatcher redirecting single-pr/coordinated to `/execute`), and there's no `--continue`/`--through`/umbrella concept. A continuation would have to supply three things nothing owns today: opening the scoping PR (since `/scope` never pushes), actually merging (since `/execute` stops at a ready, green PR), and a multi-pr answer (since multi-pr deliberately has no plan-level coordinator).
