# Lead: What do shirabe#360 and shirabe#352 imply for a redrawn boundary between `/work-on` and `/execute`, and should they be fixed alongside it or stay separate?

## Findings

### #360 — `--no-cleanup` on the terminal `koto next`

Measured against `main` (9f84fa7), same commands the issue describes:

```
grep -rl "koto next" skills/work-on/   -> 16 files
grep -rl "\-\-no-cleanup" skills/work-on/ -> 0 files
grep -rl "koto next" skills/execute/    -> 3 files
grep -rl "\-\-no-cleanup" skills/execute/ -> 0 files
grep -rl "koto next" skills/scope/      -> 5 files
grep -rl "\-\-no-cleanup" skills/scope/ -> 4 files
```

These match the issue's numbers exactly (16/0 for `/work-on`, 3/0 for `/execute`, and I additionally confirmed `/scope`'s 5/4). `/work-on`'s 16 hits include the template, six phase reference docs, `requires.tsv`, `SKILL.md`, two eval fixtures, an eval JSON, a fixture `koto` binary stub, and a script test. `/execute`'s 3 hits are `evals/evals.json`, `koto-templates/execute.md`, and a script test — i.e. exactly one real call site (the template) plus test/eval scaffolding.

`/work-on`'s terminal states, in `skills/work-on/koto-templates/work-on.md:820-838`:
- `done` (`terminal: true`)
- `done_already_complete` (`terminal: true`)
- `done_blocked` (`terminal: true`, `failure: true`)
- `skipped_due_to_dep_failure` (`terminal: true`, `skipped_marker: true`)

`/execute`'s terminal states, `skills/execute/koto-templates/execute.md:462-487`:
- `done` (`terminal: true`)
- `done_blocked` (`terminal: true`, `failure: true`)
- `paused_for_review` (`terminal: true`, no `failure:` — documented in-template, lines 468-478, as "a successful, solicited stop... a SUSPENSION, not a termination" at the `/execute` SKILL layer, resumable via the home-PR lookup)

`/scope`'s solution, `skills/scope/references/phases/phase-4-cleanup.md:119-124`:

> "The session in particular is retained deliberately: the `koto next` that reaches the terminal carries `--no-cleanup`, because the per-hop record is what an author reads after a run ends and disposing of the session destroys it at exactly that moment. The record is read where it lives and never copied into a committed artifact or a pull-request body."

`/scope` also declares the flag in `skills/scope/requires.tsv:31` (`koto next --with-data,--no-cleanup always`) with a rationale comment at lines 27-30: "The retention flag on the terminal-reaching ticks is what keeps the per-hop record readable after the run ends, so it is a call site rather than a debugging convenience." `/scope` applies `--no-cleanup` unconditionally on every terminal tick (`koto-templates/scope.md:1190-1319` — clean-success, cancel, and blocked terminals all get it), not only on failure terminals. Neither `/work-on`'s nor `/execute`'s `requires.tsv` mentions `--no-cleanup` at all (checked both files in full).

The pattern transfers directly: it's a one-line addition to the `koto next --with-data ...` call at each terminal-reaching tick, plus one `requires.tsv` line, plus a rationale comment. `/scope` and `/work-on`/`/execute` all drive the same koto engine and the same `koto next` verb with the same semantics (deletion of the session, and its `ctx/`, on any terminal). Nothing about `/scope`'s solution depends on `/scope`-specific state shape.

### #352 — no gate observes whether a review panel ran

"Review panel" in this repo means a set of parallel reviewer subagents whose combined verdict gates a `koto next` transition. Panels found:
- `/work-on` Phase 4a scrutiny (three parallel reviewers — completeness, justification, intent) → `scrutiny_results.json`
- `/work-on` Phase 4b review (three parallel reviewers — pragmatic, architect, maintainer) → `review_results.json`
- `/work-on` Phase 4c QA validation → `qa_results.json`
- `/prd` Phase 4 (three-agent jury) → `skills/prd/references/phases/phase-4-validate.md:3,9,177` (the "re-validate if changes are substantial" language the issue quotes is at line 177 verbatim)
- `/design` Phase 6 final review (architecture + security + structural-format, three parallel agents) → `skills/design/references/phases/phase-6-final-review.md:8,23,37,43,53,91`, each writing to `wip/research/design_<topic>_phase6_<name>-review.md`

Confirmed `skills/scope/scripts/hop-complete.sh` is 320 lines and contains zero occurrences of `jury`, `review`, `phase4`, `phase6`, or `wip/research` (`grep -n` on all five terms returned nothing). It checks only that a hop's canonical document exists and that `shirabe validate` returned a verdict — a document-shape verdict, unrelated to reviewer activity.

In `skills/work-on/koto-templates/work-on.md:504-582`, all three panel gates are `type: context-exists` with `override_default: {exists: true, error: ""}` over a context key (`scrutiny_results.json`, `review_results.json`, `qa_results.json`) that the same agent running the panel writes itself. The transitions (lines 517-527, 547-557, 577-587) require `gates.*.exists: true` plus a self-reported enum (`scrutiny_outcome: passed`, etc.) — nothing checks reviewer count, reviewer identity, or that the JSON's content reflects independent review versus a hand-written `{"passed": true}`.

I confirmed no gate, validator, or script anywhere reads the self-reported provenance markers the fallback doc defines. `references/fixes/sub-agent-dispatch.md:84,95` defines `decision_provenance: inline-resolved` and `verdict_source: parent-substitute`. Searching the whole tree, both strings appear only in that one fixes doc and in DESIGN document frontmatter (authors writing the marker about their own decision) — never in `crates/shirabe-validate` (the validator's source), never in `hop-complete.sh`, never in any `koto-templates/*.md` gate. Nothing mechanical reads either marker; both are pure self-report exactly as the issue states.

## Implications

For #360, the states a boundary change would move are unambiguous: every terminal state currently declared in `/work-on`'s own template (`done`, `done_already_complete`, `done_blocked`, `skipped_due_to_dep_failure`) is internal to `/work-on`'s koto session, and every terminal state in `/execute`'s template (`done`, `done_blocked`, `paused_for_review`) is internal to `/execute`'s koto session. A boundary redraw that folds `/work-on` into `/execute` (direction 1) does not merge these state machines into one — it changes which skill's template *contains* the state machine that currently belongs to `/work-on`, and whichever skill ends up owning the terminal `koto next` tick inherits (or fails to inherit) the missing flag. If `/work-on`'s phase logic is inlined as `/execute`'s per-child loop body, `/work-on`'s four terminals (particularly `done_blocked`, the one that lost `plan.md` in the issue's reproduction) become states inside `/execute`'s own session rather than a child session `/execute` merely dispatches into — which changes the blast radius of the missing flag from "one `/work-on` session's context" to "the state that would have been the child's context, now folded into the parent's own history." Direction 2 (keep `/work-on` standalone, migrate finishing logic into it) leaves the existing terminal set and session boundary intact; the fix stays a two-file, two-skill patch regardless.

For #352, the states in question are not terminal states but the panel-running phase states themselves: `scrutiny`, `review`, `qa_validation` in `/work-on`'s template, and equivalent phases in `/prd` Phase 4 and `/design` Phase 6 (neither of which is part of `/work-on`/`/execute` at all — they belong to `/scope`'s chain). A boundary redraw between `/work-on` and `/execute` only touches the `/work-on` subset: `scrutiny`, `review`, `qa_validation`. Whether these phases end up living inside `/work-on` standalone or inside an expanded `/execute`, the gate shape (`context-exists` over a self-written key) is unaffected by which skill file the YAML lives in — it is a property of the koto template's gate definition, not of which skill invokes that template. Moving `/work-on`'s phases into `/execute` verbatim would carry the same unenforceable gates over unchanged; it neither fixes nor worsens #352 by itself.

**If the boundary moves first and these are fixed later:** for #360, the missing flag would very likely propagate into whatever the redrawn `/work-on`/`/execute` split becomes, since nobody currently treats `--no-cleanup` as call-site-critical outside `/scope` — the boundary work has no reason to notice it unless someone brings the checklist over deliberately. Concretely, this exploration itself is already exposed to it (noted in the practical note), and a `/scope`-style `requires.tsv` audit would need to re-run against whatever new template file structure results. That's a small, mechanical re-check, not a redesign — the risk is forgetting it, not difficulty applying it. For #352, moving the boundary first and fixing the gate later is lower-risk precisely because the gate mechanism (`context-exists` + self-report) would get copied unchanged wherever the phase YAML ends up; fixing #352 later means editing whichever file ends up owning `scrutiny`/`review`/`qa_validation`, which is a one-time relocation cost paid regardless of order.

**If they're fixed first or together:** #360 costs almost nothing to fix ahead of the boundary work — it's a flag on an existing call, mirroring a working pattern already in the codebase, independently of what `/work-on` and `/execute` end up looking like. Fixing it first also means the exploration's own future runs (and any runs during the boundary work) don't lose their `plan.md`/`context.md` records, which directly serves the work at hand. #352 is explicitly scoped by its own issue as needing "a design, not a patch" — pinning per-phase jury shape, recording reviewer identity/findings/disposition, making fallback narrowing observable. Fixing it *before or during* the boundary redraw risks solving it against a `/work-on` template shape that the boundary change is about to restructure, meaning the gate redesign might need to be redone once the phase boundaries move. Fixing it *after* means solving it once, against the final phase layout.

## Surprises

- The issue's own claimed counts (16/0, 3/0) were exactly reproduced with no discrepancy — the issue is unusually precise for a self-reported bug report.
- `/execute` has a third terminal, `paused_for_review`, that is *not* `failure: true` and is explicitly documented as a deliberate non-terminating suspension at the SKILL layer (`skills/execute/koto-templates/execute.md:468-478`) even though koto itself marks it `terminal: true`. This is a state `/scope`'s "retain unconditionally" policy would still need to cover (a resumable pause loses its resumability if its context is destroyed), but #360 as filed only asks for `done_blocked` explicitly in its acceptance criteria — the suggested-scope section flags this ambiguity itself ("Worth checking whether the retention should apply to clean terminals too, or only to `done_blocked`").
- #352's panels that actually matter most for *this* exploration's own boundary question (`/prd` Phase 4, `/design` Phase 6) live outside `/work-on`/`/execute` entirely, under `/scope`'s chain — only `/work-on`'s three panels (scrutiny/review/qa) are boundary-adjacent. A `/work-on`/`/execute` boundary redraw cannot touch the `/prd`/`/design` instances of the same defect no matter how it's drawn.
- The self-reported provenance markers from the sub-agent-dispatch fallback doc (`decision_provenance`, `verdict_source`) are written into committed DESIGN document frontmatter by multiple existing designs (`DESIGN-execute-skill.md`, `DESIGN-scope-koto-adoption.md`, others) — meaning the "nothing reads it" gap is not hypothetical; it is already live across several merged documents in this exact repo.

## Open Questions

- Does #361's acceptance criterion ("checked against the new boundary rather than inherited by it") require the boundary PR to literally include the `--no-cleanup` fix, or only to document that it was considered and deliberately deferred? The two issues seem to warrant different answers to that question.
- If direction 1 (fold `/work-on` into `/execn`) is chosen, does the panel-gating YAML (scrutiny/review/qa) get copied as-is into `/execute`'s per-child loop, or restructured? That restructuring point is the natural (and possibly only) moment to also fix #352 for `/work-on`'s three panels without doing the work twice.
- Nothing in this investigation determined who is expected to author the koto#240 durable fix or its timeline — #360 explicitly says the skill-level `--no-cleanup` fix is only a mitigation pending that platform change, which affects how much urgency the boundary work should assign to the skill-level fix.

## Summary
Both issues' measured claims check out exactly against `main` (9f84fa7): `/work-on` has 16 `koto next` call sites and 0 `--no-cleanup`, `/execute` has 3 and 0, and `/scope`'s working fix (`skills/scope/references/phases/phase-4-cleanup.md:119-124`, `requires.tsv:31`) is a directly transferable one-line-per-call-site pattern, while #352's gate defect (`context-exists` over a self-written key, verified in `work-on.md:504-582` and the empty `hop-complete.sh` grep) is orthogonal to where the phase YAML lives and unaffected by which skill owns it. #360 is cheap and safe to fix immediately regardless of boundary direction (it even threatens this exploration's own runs); #352 is scoped by its own issue as a design-level gate redesign that should wait until the boundary redraw settles which file owns `/work-on`'s three panel phases, so it is fixed once against the final shape rather than twice. The open question is whether #361 treats "fix it later, deliberately" as satisfying its acceptance criterion, or requires the fix landed in the same PR.
