# Findings: work-on-friction-triage

Source: `/tmp/codespar-enterprise-pr38.md` (521 lines, 5 bundled issues).

Verification pass: I read current skill files — `SKILL.md`,
`koto-templates/work-on.md`, `references/phases/*`,
`references/scripts/extract-context.sh`,
`references/agent-instructions/phase-3-analysis.md` — to confirm or refute
each claim before filing.

Each entry carries a **Category**, **Verdict** (confirmed / partial / stale
/ misattributed), **Impact** (high/med/low), **Effort** estimate, and
**Recommendation** (suggested issue title + target repo, or "no action").

---

## Category A — Real shirabe improvement opportunities (confirmed)

### A1. Context extraction can't follow design docs on a remote branch in a sibling repo
- **Source §:** "Design doc was on a remote branch, not in the local repo"
- **Verdict:** Confirmed. `references/scripts/extract-context.sh` line 150-154
  uses `find docs -name "DESIGN-*.md"` — local repo only. No handling for
  `origin/*` refs or cross-repo lookups.
- **Impact:** Medium. Common in multi-repo workspaces.
- **Effort:** Medium. Needs design: where to look, how to materialize the
  remote ref without full checkout, caching.
- **Recommendation:** File shirabe issue
  *"extract-context.sh: resolve DESIGN docs on remote branches and sibling repos"*.

### A2. Skill template references `check-staleness.sh` that does not ship with shirabe
- **Source §:** Implicit — friction log's staleness-gate observation worked
  because the author's workspace has the private plugin on disk. I found
  no `check-staleness.sh` in shirabe; it lives at
  `private/tools/plugin/tsukumogami/skills/issue-staleness/scripts/check-staleness.sh`.
  The shirabe template at `work-on.md:325` calls it unqualified.
- **Verdict:** Confirmed during my verification pass. This was not
  in the friction log but surfaced while verifying the staleness claim.
- **Impact:** High. Users who install only shirabe get a broken gate.
- **Effort:** Medium. Either port the script into shirabe or make the gate
  conditional on script availability.
- **Recommendation:** File shirabe issue
  *"staleness_check gate depends on check-staleness.sh that is not in the shirabe plugin"*.

### A3. Context extraction can't tell "baseline broken by my change" from "baseline was already broken"
- **Source §:** "Pre-existing migration FK issue wasn't caught by any gate"
- **Verdict:** Confirmed. `phase-1-setup.md` requires baseline tests to pass
  ("Run the project's test suite. All must pass.") but has no branch for
  "baseline is broken upstream — document and proceed." The agent has to
  route around this manually.
- **Impact:** Medium. Every broken-baseline encounter forces a manual
  workaround.
- **Effort:** Medium. Template addition: accept `baseline_status: broken_preexisting`
  as an evidence value and capture the pre-existing failure list into
  baseline.md so later gates don't blame the current change.
- **Recommendation:** File shirabe issue
  *"setup phase: model pre-existing baseline failures as a first-class outcome"*.

### A4. Analysis forces subagent delegation even for trivial / simplified-plan issues
- **Source §:** "Forced agent delegation even for trivial tasks"
- **Verdict:** Confirmed. `references/phases/phase-3-analysis.md` says
  "Launch an analysis agent (Task tool, `subagent_type=\"general-purpose\"`)"
  unconditionally. The simplified-plan path uses a shorter template but
  still requires delegation.
- **Impact:** Medium. Pure overhead for chores where the main agent has
  already read everything.
- **Effort:** Low. Allow "write plan inline" when issue label is in
  `{docs, config, chore, validation:simple}`.
- **Recommendation:** File shirabe issue
  *"phase-3-analysis: make subagent delegation opt-out for simplified-plan issues"*.

### A5. Finalization auto-skip list omits `validation:simple`
- **Source §:** "`Simplified plan` (validation:simple label) still demands a summary"
- **Verdict:** Confirmed. `phase-5-finalization.md` says
  "Default: skip for `docs`, `config`, `chore`". `validation:simple` not in
  the list.
- **Impact:** Low. A 50-line summary that duplicates the commit message.
- **Effort:** Trivial. Extend the default skip list.
- **Recommendation:** File shirabe issue
  *"phase-5 auto-skip: include `validation:simple` in default skip list"*.

### A6. No explicit confirmation step before `git push` / `gh pr create`
- **Source §:** "The 'visible action' confirmation point isn't part of the workflow"
- **Verdict:** Confirmed. `phase-6-pr.md` goes straight from Pre-PR
  Verification → `git push` → `gh pr create`, and the `pr_creation` state
  in `work-on.md` accepts `pr_status` without a pause. This conflicts with
  the system-level guidance about visible actions (see Claude Code system
  prompt's "Executing actions with care").
- **Impact:** Medium. Silent push on --auto or unattended runs. The user
  has to insert their own pause.
- **Effort:** Low-medium. Add a pre-push decision point (respecting
  `--auto` mode).
- **Recommendation:** File shirabe issue
  *"phase-6: add explicit user confirmation before git push and gh pr create"*.

### A7. Multi-issue bundling is not a first-class flow
- **Source §:** "`koto init issue_33` in the middle of an active session wants
  a fresh branch + baseline"; "Bundled-PR support worked once I did it manually";
  "Composite observation"
- **Verdict:** Confirmed. `setup_issue_backed` accepts `status: override` but
  the skill does not document or model "append another issue to an
  existing workflow and PR." The author reached around the skill four
  times for five issues.
- **Impact:** High. Real bundling is common and currently requires manual
  koto override + manual PR-body rewrite.
- **Effort:** Medium-high. Needs design: is this a new top-level
  invocation (`/work-on --bundle #33`), a PR-body template, a helper
  script, or a new state?
- **Recommendation:** File shirabe design-doc request:
  *"multi-issue bundling as a first-class /work-on flow"* (DESIGN doc, not
  a regular issue — multiple viable approaches).

### A8. Per-session tmp paths not documented; `/tmp/plan.md` / `/tmp/baseline.md` collide across sessions
- **Source §:** "Per-session tmp paths" (recommendation §2); "`/tmp/plan.md`
  collision across concurrent issue workflows"
- **Verdict:** Confirmed by omission. `phase-1-setup.md` and
  `phase-3-analysis.md` say "Write ... to a local file" without prescribing
  a path. Agents default to `/tmp/plan.md` etc. and collide on concurrent
  sessions.
- **Impact:** Medium. Silent data loss between concurrent workflows.
- **Effort:** Low. Prescribe `/tmp/koto-<session>/plan.md`,
  `/tmp/koto-<session>/baseline.md` in the phase files.
- **Recommendation:** File shirabe issue
  *"phase-1 and phase-3 should prescribe per-session tmp paths
  (/tmp/koto-<WF>/...) to avoid collisions"*.

### A9. Env var inconsistency: `CLAUDE_SKILL_DIR` vs `CLAUDE_PLUGIN_ROOT`
- **Source §:** "Stale skill invocation path"
- **Verdict:** Confirmed. `SKILL.md:179, 186` and
  `phase-0-context-injection.md:12` use `CLAUDE_SKILL_DIR`. `SKILL.md:101`
  and `work-on-plan.md:183, 197` use `CLAUDE_PLUGIN_ROOT`. Claude Code
  plugin convention sets `CLAUDE_PLUGIN_ROOT`; `CLAUDE_SKILL_DIR` is not
  standard and was empty in the author's environment.
- **Impact:** Medium. Silent — `${UNSET}/path` evaluates to `/path` which
  is missing from the filesystem.
- **Effort:** Trivial. Pick one. Replace all `${CLAUDE_SKILL_DIR}` with
  `${CLAUDE_PLUGIN_ROOT}/skills/work-on`.
- **Recommendation:** File shirabe issue
  *"work-on: standardize on CLAUDE_PLUGIN_ROOT; remove CLAUDE_SKILL_DIR
  references"*. Trivial fix.

### A10. No "scope expanded mid-implementation, update plan" transition
- **Source §:** "Scope expansion mid-implementation was smooth but not
  workflow-aware"
- **Verdict:** Confirmed. `implementation` state has no transition back to
  `analysis`. `scope_changed_retry` is only accepted at the `analysis`
  state. Once in implementation, scope expansion requires `koto rewind`.
- **Impact:** Medium. Agents route around it; decisions get lost.
- **Effort:** Medium. Add an `implementation_status: scope_expanded_retry`
  value that routes back to `analysis`, or document `koto rewind` as the
  canonical escape.
- **Recommendation:** File shirabe issue
  *"implementation state: accept `scope_expanded_retry` transition back to
  analysis"*.

### A11. Re-confirm-AC pass is not a built-in phase
- **Source §:** "My first read missed a literal AC detail"; "User's MAKE
  SURE YOU READ THE ISSUE AGAIN nudge was genuinely useful"
- **Verdict:** Confirmed by omission. `phase-4-implementation.md` has
  "Self-review: git diff main...HEAD, re-read acceptance criteria" at the
  end, but there's no mid-phase re-read hook. The user-delegated
  second-pass worked in the friction log.
- **Impact:** Low-medium. Helps catch AC-drift; not blocking.
- **Effort:** Low. Add a "phase-4.5 AC re-confirmation" directive, or
  strengthen phase-4's self-review step.
- **Recommendation:** File shirabe issue
  *"phase-4: add explicit mid-implementation AC re-confirmation step"*.

### A12. Workflow doesn't cache per-branch context findings
- **Source §:** "Context extract's degraded status was correct but misleading"
- **Verdict:** Confirmed. Each `koto init` re-runs extract-context.sh with
  no awareness of sibling issues already explored on the same branch. Four
  redundant "Design doc not found" runs on one branch.
- **Impact:** Low-medium. Wasted time and duplicate warnings obscure new
  warnings.
- **Effort:** Medium. Cache key = branch + referenced design-doc path;
  store under koto context with a shared key.
- **Recommendation:** File shirabe issue
  *"extract-context: cache design-doc findings per-branch to avoid
  redundant re-investigation"*.

### A13. AC validation scripts supplied by the issue author are treated as
  authoritative, not advisory
- **Source §:** "The skill should probably not run author-supplied
  validation scripts verbatim"
- **Verdict:** Confirmed by omission. No phase file explicitly distinguishes
  "validation script is a hint" from "validation script is authoritative."
  Two separate issues (#36, #35) had buggy validation scripts in this run.
- **Impact:** Low. Agents can reason their way out, but the skill could
  make the policy explicit.
- **Effort:** Trivial. Note in phase-4 or phase-5 that validation scripts
  in issue bodies are advisory.
- **Recommendation:** File shirabe issue
  *"document: author-supplied AC validation scripts are advisory, not
  authoritative"*.

### A14. Baseline scope is always the whole workspace, never the touched
  package(s)
- **Source §:** "Baseline test run is slow — backgrounded by user"
- **Verdict:** Confirmed. `phase-1-setup.md` says "Run the project's test
  suite" — unscoped. Monorepos pay full baseline cost even for a
  single-file PR.
- **Impact:** Medium for monorepo users; negligible for single-package
  projects.
- **Effort:** Medium. Requires detecting the touched package(s) from the
  plan or the issue's `Files:` annotation; language-skill-specific.
- **Recommendation:** File shirabe issue
  *"baseline: scope test run to touched packages when the project is a
  monorepo"*.

---

## Category B — Possibly koto engine, worth filing upstream

### B1. "Legacy-behavior" warnings at `koto init`
- **Source §:** "Fix legacy-behavior warnings at `koto init`"
- **Verdict:** Partial. I could not reproduce because
  `koto-templates/work-on.md` fails to compile entirely on koto 0.8.2
  ("invalid YAML: failed to parse front-matter") — see my own friction
  log on PR #77. The author ran on an older koto that surfaced the
  warnings. This is worth filing as a koto bug (compile regression)
  separately from the "legacy warnings" observation.
- **Impact:** High. The template compile regression blocks the skill
  entirely on koto ≥ 0.8.x; the legacy warnings are cosmetic drift.
- **Effort:** Low-medium for koto; would likely reveal what changed
  between 0.7.x and 0.8.2.
- **Recommendation:** File koto issue
  *"regression: work-on.md template YAML no longer parses in 0.8.2"*.
  Separately, if the legacy warnings persist on a compiling template,
  file *"koto: template migration path from legacy gate routing"* — but
  verify first.

### B2. Koto state lag after PR update — three back-to-back `koto next` calls
  failed mid-sequence
- **Source §:** "Koto state lag after PR update"
- **Verdict:** Partial. The friction log says "koto had already advanced
  past implementation on the commit presence." The `implementation` state's
  `has_commits` gate fires on commit presence, but transitions out of
  implementation only happen on `--with-data`. I cannot reproduce without
  session state. Likely either: (a) a misread by the author (state
  machines are deterministic about transitions), (b) a koto race when
  multiple `koto next` fire concurrently, or (c) a template issue where
  a gate re-evaluation resets state.
- **Impact:** Uncertain.
- **Effort:** Needs reproduction.
- **Recommendation:** Ask the author for a reproduction (session name,
  koto version, `koto workflows --children` output). Do NOT file yet.

### B3. Koto output verbosity / noise
- **Source §:** "state labels in koto output (state, action, expects) are
  verbose and noisy"
- **Verdict:** Confirmed — koto's `koto next` output is verbose JSON by
  default. Not a bug; a UX request.
- **Recommendation:** File koto UX issue
  *"koto: add --quiet mode for execution-loop output"*. Low priority.

---

## Category C — Belongs in adjacent skills, not work-on

### C1. `npm install` missing before baseline — `turbo: not found`
- **Source §:** "`npm test` at workspace root fails with `turbo: not found`"
- **Verdict:** Confirmed, but this is language-skill turf.
- **Recommendation:** File against whichever skill owns Node.js project
  quality checks (looks like the org uses `tsukumogami:nodejs` privately;
  shirabe has no public nodejs skill yet). If shirabe ships a nodejs
  skill later, it should include a "ensure `node_modules` exists before
  test" step. For now, **no shirabe action**.

### C2. Turbo cache hides stdout on cache hits; `rm -rf .turbo` needed for
  cold reads
- **Source §:** Four entries ("Turbo cache still hides first-cold-run output")
- **Verdict:** Confirmed; turbo's documented behavior.
- **Recommendation:** Same as C1 — belongs in a nodejs/turbo-aware
  language skill, not work-on. **No shirabe action.**

### C3. Dependency conflict (ERESOLVE) on new npm package
- **Source §:** "Dependency conflict on new npm package — not surfaced by
  any gate"
- **Verdict:** Confirmed by omission, but the same "install dependency"
  checkpoint argument applies.
- **Recommendation:** Same as C1. **No shirabe action.**

### C4. `*/` inside a block comment broke esbuild
- **Source §:** "`*/` inside a block comment broke esbuild"
- **Verdict:** Pure coding mistake caught by CI. Not a workflow issue.
- **Recommendation:** **No action.** Mentioning this in a skill would be
  chasing tails.

---

## Category D — Harness / Claude Code, not shirabe

### D1. TaskCreate "task tools haven't been used recently" reminder spam
- **Source §:** "Task tool spam in system-reminders"
- **Verdict:** Confirmed (I'm also seeing these mid-run right now). This
  is a Claude Code harness behavior — fires on a timer regardless of
  workflow context.
- **Recommendation:** Ask the user whether to raise this against Claude
  Code feedback channel. **No shirabe action.**

---

## Category E — User / agent foot-guns

### E1. pwd drift from `cd` inside Bash tool persists across calls
- **Source §:** "Found my own pwd drift bug"
- **Verdict:** Confirmed — documented Bash-tool behavior ("The working
  directory persists between commands").
- **Recommendation:** **No action.** Agent discipline.

### E2. Issue author's AC validation scripts have regex bugs
- **Source §:** two entries on `grep -qE "pattern1\|pattern2"` style bugs
- **Verdict:** Author bug, not skill bug. See A13 for the meta-fix
  (making script-as-advisory explicit in docs). **No separate action.**

### E3. Stale migration number in the issue AC (0020 vs 0028)
- **Source §:** "Stale migration number in the issue AC was not caught by
  any gate"
- **Verdict:** Author-side issue staleness. The shirabe staleness gate
  (A2) exists precisely for this; see A2's bug about the gate script not
  shipping with shirabe.
- **Recommendation:** **No separate action** — covered by A2.

---

## Summary table

| # | Category | Title | Impact | Effort |
|---|---|---|---|---|
| A1 | shirabe | extract-context: resolve DESIGN docs on remote branches and sibling repos | Med | Med |
| A2 | shirabe | staleness_check gate depends on check-staleness.sh not in shirabe | High | Med |
| A3 | shirabe | setup: model pre-existing baseline failures as first-class outcome | Med | Med |
| A4 | shirabe | phase-3: make subagent delegation opt-out for simplified-plan | Med | Low |
| A5 | shirabe | phase-5 auto-skip: include `validation:simple` | Low | Trivial |
| A6 | shirabe | phase-6: add user confirmation before git push / gh pr create | Med | Low-Med |
| A7 | shirabe (design) | multi-issue bundling as first-class /work-on flow | High | Med-High |
| A8 | shirabe | phase-1 and phase-3: prescribe per-session tmp paths | Med | Low |
| A9 | shirabe | standardize on CLAUDE_PLUGIN_ROOT; remove CLAUDE_SKILL_DIR | Med | Trivial |
| A10 | shirabe | implementation: accept scope_expanded_retry back to analysis | Med | Med |
| A11 | shirabe | phase-4: mid-implementation AC re-confirmation | Low-Med | Low |
| A12 | shirabe | extract-context: cache per-branch to avoid redundant runs | Low-Med | Med |
| A13 | shirabe | document: AC validation scripts are advisory, not authoritative | Low | Trivial |
| A14 | shirabe | baseline: scope test run to touched packages in monorepos | Med | Med |
| B1 | koto | regression: work-on.md template YAML no longer parses in 0.8.2 | High | Low-Med |
| B2 | koto (defer) | state lag after PR update — needs repro | ? | ? |
| B3 | koto (ux) | add --quiet mode for execution-loop output | Low | Low |
| C1-C4 | nodejs skill | monorepo/turbo/npm workflow hygiene | — | — |
| D1 | Claude Code | TaskCreate reminder spam | — | — |
| E1-E3 | n/a | user/agent foot-guns | — | — |

## Priority recommendation for filing

**First wave (trivial fixes, high signal):**
- A5, A9, A13 — single-line fixes; file and merge same day.

**Second wave (medium-effort, clear design):**
- A1, A2, A3, A4, A6, A8, A10, A11, A12, A14 — straightforward issues with
  scoped acceptance criteria.

**Third wave (needs design, not an issue):**
- A7 (multi-issue bundling) — write `/design` for the flow before filing
  implementation issues.

**File at koto:**
- B1 (template compile regression) — critical for the skill to work.
- B3 (quiet mode) — nice-to-have.

**Defer pending repro:**
- B2 (state lag).

**Upstream to language skill / Claude Code:**
- C1-C4, D1 — route out of scope.

## Decision: Crystallize
