# Lead: Does `/execute`'s `pr_finalization` produce a template-conformant PR (conventional-commit title + two-part body), and should the `/fix-pr` template step be folded into finalization? Should a manual/fallback path surface "finalization not done"? (F6 + F5 secondary)

## Findings

### What the project template requires (the conformance bar)

The canonical PR template lives in the **tsukumogami plugin** (`private/tools`), not in shirabe. `tsukumogami:pr-creation` SKILL defines two things:

- **Conventional-commit title** — `skills/pr-creation/SKILL.md:44-61`: `<type>[optional scope]: <description>`, lowercase imperative; types `feat|fix|docs|style|refactor|perf|test|chore|ci|build`.
- **Two-part body** — `skills/pr-creation/SKILL.md:24-39`: "Part 1: Textual explanation (becomes commit body) … `---` … Part 2: Reviewer context (deleted at merge). At merge time, everything from `---` downward is deleted." This matches the shirabe CLAUDE.md note and the worktree `pr-creation` discipline.

`/fix-pr` is the *resume* skill that retro-fits an existing PR to this template. `skills/fix-pr/SKILL.md:22-27` reads the PR then delegates to `shared/shortcut-phases/fix-pr/update-pr.md`. That update step (`update-pr.md:24-36`) does exactly one privileged call:
```bash
gh pr edit <pr-number> --title "<new-title>" --body "<new-body>"
```
with key requirements: "Conventional commits title — `<type>[scope]: <description>`" and "Two-part body — Part 1 becomes commit message, Part 2 is deleted at merge." So **`/fix-pr` sets BOTH title and a two-part body.**

### What `/execute`'s `pr_finalization` produces today

Two `/execute` states touch the PR, neither produces a template-conformant artifact:

1. **`orchestrator_setup`** sets the **title** once, at draft-PR creation (`skills/execute/koto-templates/execute.md:242`):
   ```bash
   gh pr create --draft --title "impl: $PLAN_SLUG" --body "Implements $(basename {{PLAN_DOC}})."
   ```
   `impl:` is **not** a Conventional-Commits type (the allowed set is `feat|fix|docs|…` — `pr-creation/SKILL.md:49`). So the title is non-conformant from creation, and nothing later rewrites it.

2. **`pr_finalization`** (`execute.md:312-325`) updates only the **body**, and only with a **child-summary table** — not a two-part body:
   - `:316-322` — "Assemble a PR description. For each child include: `name`, `outcome`, `reason`, `reason_source`, `skipped_because_chain`." This is a per-child status roll-up.
   - `:323` — `gh pr edit <pr-number> --body "<assembled description>"` — **`--body` only, no `--title`.**
   - The SKILL one-liner agrees: `skills/execute/SKILL.md:161` — "`pr_finalization` — assemble the combined PR body."

There is **no Part 1 / `---` / Part 2 split, no "Fixes #N" placement rule, no conventional-title rewrite** anywhere in `pr_finalization`. It assembles a batch-outcome table and edits the body in place over the `"Implements …"` placeholder.

### So: is the gap structural, or purely a fallback artifact?

**Structural.** F6 is NOT merely a consequence of the manual fallback (F1). Even a *clean*, fully-automated `/execute` single-pr run produces:
- title `impl: <slug>` — non-conventional (set at `execute.md:242`, never rewritten);
- body = child-outcome table — not the two-part Part 1/Part 2 structure.

The manual fallback (F1) made it *more* visible (the operator also had to do the body assembly by hand), but the conformance gap exists by construction in the automated path too. `pr_finalization` and `/fix-pr` are solving different problems: `pr_finalization` answers "what happened in this batch," `/fix-pr` answers "is this PR template-shaped." They do not overlap, so a separate `/fix-pr` pass is required today regardless of whether the run was automated or manual.

### F5 secondary ask: is there a "finalization not done" guard for manual/fallback runs?

The only finalization guard is **R9 hard-finalization**, and it lives in koto/the SKILL exit path:
- `skills/execute/SKILL.md:107-108` — Exit step "run the R9 hard-finalization check"; `:291` — "the R9 hard-finalization check fires when [`exit`] is unset or out-of-enum at termination"; `:458` — a write outside the closed set "fails the R9 hard-finalization check."

R9 checks that `exit:` is set and writes stayed in-bounds. It does **not** check that the PR is template-conformant (conventional title + two-part body), and crucially it is part of the `/execute`-driven exit. The SKILL explicitly contemplates manual/direct invocation — `skills/execute/SKILL.md:435` "the metadata-only rule holds identically whether a child ran inside `/execute` or was invoked directly (manual-fallback non-interference)" — but there is **no guard that fires "finalization not done" when the koto loop is bypassed**. If F1 forces a manual fallback, `pr_finalization` + `plan_completion` are simply skipped silently, exactly as the dogfood showed. The lead's own framing is correct: such a guard "can't live in koto if koto was bypassed."

## Implications

**Two distinct problems, two different fix postures.**

**Problem A (F6 — template conformance):** `pr_finalization` must produce a conventional-commit title and two-part body, not just a child table. This is fixable as a **direct fix**, but with a design caveat about *which* mechanism, weighed against shirabe's "author with skills, check with `validate`" CLI split (`CLAUDE.md:161-183`).

- **Option (a) — fold `/fix-pr` template logic into `pr_finalization`.** Best fit. The two-part body and conventional title are *authoring* concerns, and shirabe's rule is "Artifacts are authored by skills" (`CLAUDE.md:165-168`). `pr_finalization` is already a skill-authored state that calls `gh pr edit`; extend it to (1) rewrite the title to a conventional type (drop `impl:`), and (2) wrap the child-outcome table as Part 2 under a Part 1 change-summary with the `---` separator. The child table becomes the Part 2 reviewer context, which is exactly where it belongs.
- **Option (b) — have `pr_finalization` invoke `/fix-pr`.** Weaker. `/fix-pr` is a cross-plugin (tsukumogami) skill; shirabe's `/execute` shouldn't hard-depend on a tsukumogami resume-skill at a koto-state tick. It also re-reads the PR it just wrote — wasteful — and splits authorship across two skills.
- **Option (c) — leave `/fix-pr` separate, document as required step.** This is the status quo that produced F6. Rejected: "required manual afterthought" is precisely the friction.

Recommend **(a)**. Files that change: `skills/execute/koto-templates/execute.md` (the `pr_finalization` state, `:312-325`, plus the `orchestrator_setup` title at `:242` — change `impl:` placeholder or accept it knowing finalization rewrites it) and the SKILL one-liner `skills/execute/SKILL.md:161` ("assemble the combined PR body" → "assemble the template-conformant combined PR: conventional title + two-part body"). The two-part rules can be cited from `pr-creation/SKILL.md` rather than restated, keeping shirabe's skill thin.

**Problem B (F5 secondary — "finalization not done" guard on manual path):** **needs-design.** A guard that fires when a run falls back to manual cannot live in koto (koto was bypassed). It also can't naturally live in `pr_finalization` (that state is the thing skipped). Candidate homes worth a decision: (1) a `shirabe validate` mode — e.g. `--pr-finalized` / extend the lifecycle check — that an operator (or CI) runs against the home PR to assert "title conventional, body two-part, cascade ran, PR ready"; this fits the "check with `validate`" half of the CLI split (`CLAUDE.md:169-172`) and works regardless of how the run was driven. (2) A `/execute` **Resume**-path check that, on re-entry to a branch with an existing PR, detects an un-finalized PR and surfaces it. Option (1) is the stronger fit because validation is exactly what's allowed to be compiled CLI logic, and it's invokable from a manual path and from CI. This is a genuine design question (where the guard lives, what it asserts, whether CI runs it), not a one-line edit — route to needs-design.

## Surprises

- The non-conventional title originates at **PR creation** (`execute.md:242`, `impl: $PLAN_SLUG`), not at finalization. Even folding title logic into `pr_finalization` leaves a window where the draft PR carries a non-conventional title; acceptable since drafts don't merge, but worth noting.
- `pr_finalization`'s comment block (`execute.md:106-129`) is careful about the DRAFT-before-READY ordering vs `plan_completion`, yet says nothing about template shape — the state's author was focused on the cascade/ready sequencing, and template conformance simply wasn't in scope. That's why `/fix-pr` was assumed to be a separate later pass.
- `/fix-pr` is a **tsukumogami** skill (`private/tools/...`), so it's not even discoverable from inside the shirabe repo's `skills/`. The dogfood operator had to reach across plugins to apply it — extra evidence it shouldn't be the designated finalization mechanism for a shirabe skill.

## Open Questions

- Should the `orchestrator_setup` draft title (`execute.md:242`) be made conventional up-front (e.g. `feat: <slug>` / `chore: <slug>`), or left as `impl:` and unconditionally rewritten at `pr_finalization`? Picking a type requires knowing the PLAN's dominant change class.
- For Problem B, does a `shirabe validate --pr-finalized` mode duplicate what `plan_completion`'s `--lifecycle-chain --mode=ready` already verifies, or is template-shape a genuinely new check surface? (Lifecycle checks doc transitions, not PR title/body shape — likely new, but confirm.)
- Does the coordinated path have the same gap? Its per-repo child PRs are authored by `/work-on` (`SKILL.md:430-431`), and the coordination body is validated by `shirabe validate --coordination-body`. Per-repo PR template conformance there may already be `/work-on`'s responsibility — out of this lead's single-pr scope but worth a cross-check.

## Summary

`/execute`'s `pr_finalization` does NOT produce a template-conformant PR: it edits only the body (`gh pr edit --body`, `execute.md:323`) with a child-outcome table, never the two-part Part 1/`---`/Part 2 structure, and the title stays the non-conventional `impl: <slug>` set at PR creation (`execute.md:242`) — so the gap is structural and present even in a clean automated run, not merely a side effect of the F1 manual fallback. The fix for F6 is a direct edit folding `/fix-pr`'s template logic (conventional title + two-part body, the child table becoming Part 2) into `pr_finalization` itself, which fits shirabe's "author with skills" rule better than invoking the cross-plugin tsukumogami `/fix-pr`; files touched are `skills/execute/koto-templates/execute.md` and the SKILL one-liner. The F5 "finalization not done" guard is needs-design: no such guard exists (the only one, R9, rides the `/execute` exit and can't fire when koto is bypassed), and the strongest home is a new `shirabe validate` mode invokable from a manual path and CI, consistent with the "check with `validate`" half of the CLI split.
