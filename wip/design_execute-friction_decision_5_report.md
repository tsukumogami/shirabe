# Decision D5: durable report-upstream home

PRD R6: friction logs and other report-upstream artifacts SHALL have a durable
home surviving `/execute`'s finalization cleanup and the squash-merge that keeps
`wip/` off main.

## Source confirmation

- **The cascade has NO `wip/` scrub.** `skills/execute/scripts/run-cascade.sh`
  only ever `git rm`s two kinds of node: the PLAN (Step 3, line 841
  `git rm -f "$PLAN_DOC"`, after the ephemeral Active→Done flip at line 715) and a
  completed ROADMAP (`handle_roadmap_deletion`, line 546 `git rm -f "$path"`, gated
  on all-features-Done AND all-issues-CLOSED). The transition handlers
  (`transition_design`/`transition_prd`/`transition_brief`, lines 764-779) only
  `git add` — they never remove `wip/`. There is no `rm`/`git rm` touching any
  `wip/...` path anywhere in the script. So F7 is **not** an `/execute` bug.
- **What removes `wip/` is the squash-merge, by design.** Per the workspace
  wip-hygiene rule (`/home/dgazineu/dev/niwaw/tsuku/tsuku-5/CLAUDE.md`, "Temporary
  Artifacts (wip/)"): files under `wip/` are non-durable, are committed to feature
  branches during workflows, and "PRs use squash-merge, so wip/ artifacts never
  appear in the main branch history." A friction log dropped in `wip/` is therefore
  carried off main exactly as the rule intends — F7 is a **convention gap**, not a
  mechanism gap.
- **shirabe already owns the lowest-ceremony durable home: `gh issue create`.**
  `/plan` (`skills/plan/scripts/create-issue.sh:240-260`, build + run
  `gh issue create`, parse the returned `https://github.com/owner/repo/issues/N`
  URL) and `/roadmap` (`skills/roadmap/SKILL.md:318-322`, the `shirabe roadmap
  populate` subcommand runs one `gh issue create` per feature) both create GitHub
  issues from skill prose today. No new dependency, no new write surface to build.
- **The automated-emit alternative widens `/execute`'s closed write-target set.**
  `skills/execute/SKILL.md` Security Considerations point 2 enumerates the closed
  set: `wip/execute_<topic>_*`, the skill's own files, the home PR / coordination
  body via `gh pr edit/ready/close`, the cascade's chain transitions under `docs/`,
  and Decision Records under `docs/decisions/`. "A write outside this set fails the
  R9 hard-finalization check." A `gh issue create` from inside an `/execute` run is
  a NEW remote write target not in that set, so adding it is a contract change that
  must be its own design-gated PR — confirming the exploration's deferral.

## Options Considered

- **(a) Manual convention: file a GitHub issue on the skill repo (`gh issue
  create`), recorded as a carve-out.** Lowest ceremony — reuses the `gh issue
  create` pattern shirabe already owns in `/plan` and `/roadmap`, adds zero new
  machinery to `/execute`, and the issue is the natural durable home for a
  report-upstream artifact (it IS the upstream reader's inbox). The artifact lives
  on `github.com`, wholly outside the branch, so neither the cascade nor the
  squash-merge can erase it. Con: depends on author discipline (no enforcement), as
  the PRD already accepts (R6 "manual convention rather than an automated emit ...
  depends on author discipline").
- **(b) A committed `docs/` note.** Durable (survives squash-merge; `docs/` is
  tracked). Con: it's a code-tree artifact for what is really an upstream
  *communication* — it accumulates stale friction notes in the repo, and routing a
  transient "report this upstream" observation into a permanent doc is heavier than
  the signal warrants. Better as a fallback when no suitable issue target exists.
- **(c) Automated `/execute` run-report emit.** Most ergonomic (no author step) but
  widens the closed write-target set (point 2 above) — it requires a new remote
  write surface, security review of issue-target validation, and an R9 amendment.
  Out of proportion to a convention gap and explicitly deferred by PRD D5.

## Chosen Option

**(a) a GitHub issue on the shirabe repo as the durable home, recorded as a
convention carve-out, with (b) a committed `docs/` note as the fallback when no
issue is the right target. (c) is confirmed a deferred, design-gated follow-on.**

This matches PRD D5 ("a GitHub issue on the skill repo as the lowest-ceremony
durable home, with a `docs/` note as fallback and an automated `/execute`
run-report emit as a design-gated follow-on"). It is correct because the gap is a
convention gap, not a missing mechanism: the squash-merge removing `wip/` is
working as designed, so the remedy is to tell authors where report-upstream
artifacts go instead of `wip/`, not to change the cascade or `/execute`. Keeping
the emit deferred respects "author with skills, check with validate" and the
closed write-target set — `/execute` gains no new write target.

## Concrete Mechanism

Two prose edits, zero code/script changes, zero new `/execute` write targets:

1. **Carve-out in the workspace wip-hygiene rule**
   (`/home/dgazineu/dev/niwaw/tsuku/tsuku-5/CLAUDE.md`, "Temporary Artifacts
   (wip/)" section). Add a short paragraph stating: report-upstream artifacts
   (friction logs, notes intended for a maintainer) MUST NOT be left in `wip/`,
   because squash-merge carries `wip/` off main by design; their durable home is a
   GitHub issue on the relevant skill repo (filed with `gh issue create`, the same
   surface `/plan` and `/roadmap` use), or — when no issue is the right target — a
   committed note under `docs/`. This is the canonical location; per the rule's own
   "Private overlay note," the `tsukumogami/dot-niwa-overlay` CLAUDE.md fragment
   must mirror the carve-out verbatim.
2. **Pointer in `skills/execute/SKILL.md`.** Add one sentence (natural homes: the
   **Autonomy** section's blocker/decision-log discussion, or a short note beside
   the **State**/`wip/` description) directing that any friction or report-upstream
   note captured during a run be filed to a shirabe-repo issue (or a `docs/` note),
   NOT left in `wip/execute_<topic>_*` where finalization + squash-merge erase it.
   Crucially this is a *pointer to author behavior*, not a new `/execute` write: the
   SKILL.md text does not add `gh issue create` to `/execute`'s emitted commands, so
   the closed write-target set (Security Considerations point 2) is unchanged.

Defer the automated emit explicitly: note in the DESIGN that an automated
`/execute` run-report emit is a separate, design-gated change because it would add
a remote write target outside the closed set and require an R9 amendment.

## Open Risks

- **Discipline dependence.** A manual convention has no enforcement; an author can
  still forget and drop a note in `wip/`. The PRD accepts this (R6). If it proves
  insufficient in practice, the escalation path is the deferred automated emit (c),
  taken as its own PR.
- **Carve-out drift across the two CLAUDE.md copies.** The rule is workspace-wide
  and the overlay fragment must mirror it verbatim; if only the public CLAUDE.md is
  edited, the private overlay drifts. Land both in lockstep (the rule's "copy-and-
  keep-in-sync" framing).
- **Issue-vs-docs routing ambiguity.** The carve-out gives two homes (issue,
  fallback `docs/` note); without a crisp "use an issue when X" line, authors may
  pick inconsistently. Keep the default unambiguous: prefer the issue; fall back to
  `docs/` only when there is no appropriate upstream issue target.

# Decision D6: template-conformant PR

PRD R4: `/execute`'s finalization SHALL produce a PR with a conventional-commit
title and the project's two-part body, without a separate manual fix-up.

## Source confirmation

- **`pr_finalization` edits only the body, never the title.**
  `skills/execute/koto-templates/execute.md` `pr_finalization` state (prose lines
  312-325): it reads `batch_final_view`, assembles a child-outcome description
  (per-child `name`/`outcome`/`reason`/`reason_source`/`skipped_because_chain`),
  and runs **`gh pr edit <pr-number> --body "<assembled description>"`** (line
  323). There is no `--title`, and the body is a bare child table — no Part 1 / `---`
  / Part 2 structure.
- **The title was set non-conventional at PR creation and is never fixed.**
  `orchestrator_setup` creates the draft PR with
  **`gh pr create --draft --title "impl: $PLAN_SLUG" --body "Implements
  $(basename {{PLAN_DOC}})."`** (line 242). `impl:` is not in the Conventional
  Commits type set (`feat|fix|docs|style|refactor|perf|test|chore|ci|build` —
  `skills/pr-creation/SKILL.md:49`). So even on a fully clean run the PR ends with a
  non-conventional title and a one-part body — exactly F6.
- **`/fix-pr` already encodes the target shape.** `/fix-pr`
  (`.../tsukumogami/skills/fix-pr/SKILL.md` → `shared/shortcut-phases/fix-pr/
  update-pr.md`) reads the PR, invokes the `pr-creation` skill, and runs `gh pr edit
  <pr-number> --title "<new-title>" --body "<new-body>"` with the key requirements:
  "Conventional commits title — `<type>[scope]: <description>`" and "Two-part body —
  Part 1 becomes commit message, Part 2 is deleted at merge." The `pr-creation`
  skill (`skills/pr-creation/SKILL.md:24-76`) is the canonical spec: title
  `<type>[scope]: <description>` (lowercase imperative), body = Part 1 (commit body)
  / `---` / Part 2 (reviewer context, carries `Fixes #<N>`, deleted at merge).

## Options Considered

- **(a) Fold the `/fix-pr` template logic directly into `pr_finalization`.** Make
  `pr_finalization` emit the conventional title and the two-part body in the one
  `gh pr edit` it already runs, so a clean run is template-conformant with no
  second pass. Fits "author with skills" (the authoring lives in the skill that owns
  PR finalization) and the existing single-`gh pr edit` write — no new write
  surface, no cross-plugin dependency. Con: the title/two-part rules are restated/
  referenced in `/execute` rather than centralized in `/fix-pr`.
- **(b) Invoke the cross-plugin `/fix-pr` from `plan_completion`/finalize.** Reuses
  the exact `/fix-pr` logic. Cons: introduces a runtime cross-plugin dependency
  (`/fix-pr` lives in the `tsukumogami` plugin, not shirabe) from inside an
  autonomous `/execute` run; adds a *second* PR-editing pass after `pr_finalization`
  already edited the body (two `gh pr edit`s, redundant and order-sensitive vs the
  DRAFT-before-READY cascade); and "fix-pr" is a *remediation* skill — a clean run
  should produce a conformant PR directly, not produce a malformed one and then
  repair it. Contradicts R4's "without a separate manual fix-up."

## Chosen Option

**(a) fold the `/fix-pr`/`pr-creation` template logic into `pr_finalization`.**

R4 demands conformance "without a separate manual fix-up," which (b) structurally
violates by making conformance a second remediation pass. (a) produces the
conformant PR in the single `gh pr edit` `pr_finalization` already performs, keeps
the authoring inside the skill that owns finalization (author-with-skills), reuses
the existing write (no new target — Security Considerations point 2 unchanged), and
avoids a runtime shirabe→tsukumogami cross-plugin coupling. The canonical
title/body spec stays `pr-creation`'s; `pr_finalization` applies it. This is what
DESIGN R4 already states ("folds the PR-template logic (conventional title +
two-part body, child table as Part 2) into `pr_finalization`").

## Concrete Mechanism

One file: `skills/execute/koto-templates/execute.md`, `pr_finalization` state
(prose lines 312-325). No new koto states, no script, no new write target.

1. **Conventional title.** Replace the bare body edit with a title+body edit:
   `gh pr edit <pr-number> --title "<conventional-title>" --body "<two-part body>"`.
   Derive the title as `<type>(scope): <description>`:
   - `type`: the dominant change type across the merged children. Default
     **`feat`** for a feature-bearing PLAN; use `fix` when the PLAN is purely
     remediation, `docs`/`chore` when all child changes are docs/chore (the
     `pr-creation` content heuristics, SKILL.md:104-114). A safe deterministic
     default is `feat: <plan-slug-as-description>` since a PLAN normally lands
     feature work.
   - `scope` (optional): omit unless an obvious subsystem applies (per
     `pr-creation` scope guidance; NEVER the slug-as-issue-number).
   - `description`: lowercase imperative derived from the PLAN slug/title (the same
     `{{PLAN_DOC}}` basename `orchestrator_setup` already has), e.g.
     `feat: execute-friction` → a readable imperative phrase. PLAN-body text is data,
     never interpolated into emitted shell (Security Considerations point 6): build
     the title from the validated slug, not raw PLAN prose.
   This *replaces* the `impl: $PLAN_SLUG` title set at creation (line 242) — the
   draft can keep `impl:` at creation; `pr_finalization` rewrites it to conventional
   before ready. (Optionally also fix line 242 to a conventional placeholder, but the
   finalization rewrite is the load-bearing fix.)
2. **Two-part body, child table as Part 2.** Restructure the assembled description
   into `pr-creation`'s two-part shape:
   - **Part 1** (becomes the squash commit body): a concise factual paragraph of
     what the PLAN's PR changed in the codebase (lead with concrete changes, not
     issue management — `pr-creation` SKILL.md:65-71). No `Fixes #N` here.
   - `---` separator.
   - **Part 2** (reviewer context, deleted at merge): the existing per-child outcome
     table (`name`/`outcome`/`reason`/`reason_source`/`skipped_because_chain`) plus
     any `Fixes #<N>` lines for issues the PLAN's children resolved.
3. **Prose update.** Rewrite the `pr_finalization` step list (lines 316-325) to
   describe building the conventional title and the Part 1 / `---` / Part 2 body,
   referencing `skills/pr-creation/SKILL.md` as the canonical title/body spec rather
   than restating every rule. The `finalization_status: {updated, update_failed}`
   enum, the `update_failed`→`done_blocked` route, and the DRAFT-before-READY
   ordering (no `gh pr ready` in this state — that stays in `plan_completion`) are
   all unchanged.

## Open Risks

- **Type inference correctness.** Picking `feat` vs `fix`/`docs` from child
  outcomes is a heuristic; a wrong type yields a conformant-but-imprecise title.
  Mitigation: a deterministic `feat:` default (PLANs normally land features) keeps
  it valid and predictable; refine only if a cheap signal exists (e.g. PLAN
  frontmatter). A reasonable default is not a blocker (Autonomy: "take the default,
  record it").
- **Part 1 authored from metadata only.** `/execute` inspects children
  metadata-only (R14/R15) and must not read child PR bodies, so Part 1 is built from
  the PLAN's own (validated) framing plus the child-outcome metadata — not by
  summarizing child diffs. Keep Part 1 a factual change paragraph derived from the
  PLAN, so the metadata-only contract holds.
- **Spec drift vs `pr-creation`.** Referencing rather than copying the
  title/two-part rules keeps `pr-creation` canonical; if `pr_finalization` instead
  hardcodes the format, it can drift from `pr-creation`. Prefer a reference + the
  minimum concrete shape, not a full restatement.
- **No-fix-up guarantee depends on the clean-run path.** R4 is satisfied only if the
  rewrite fires on every finalization (clean and attention runs); ensure
  `pr_finalization` runs the title+body edit unconditionally, not just when the body
  table is non-empty, so a zero-issue or all-skipped run still yields a conformant
  title.
