# Wave 1 implementation — /shirabe:work-on friction log

Session: 2026-04-23
Branch: explore/work-on-friction-triage (PR #78)
Invocation: `/shirabe:work-on docs/plans/PLAN-work-on-friction-fixes.md -- in this same branch, work Wave 1`
Plan: docs/plans/PLAN-work-on-friction-fixes.md (Draft; 14 issues; Wave 1 = #1..#7)

---

## Setup observations

### 1. work-on.md template now compiles under koto 0.8.2
The previous session's friction log flagged an "invalid YAML: failed to
parse front-matter" error. On this session's `koto template compile`
run, work-on.md compiles with only a W3 warning ("terminal state name
suggests failure outcome but `failure: true` is not set" on
`skipped_due_to_dep_failure`). Either a template fix landed between
sessions or koto's parser behaviour changed. Worth verifying whether
the blocker is truly resolved or just masked.

### 2. Declined to use the plan orchestrator for Wave 1 — three reasons
- **PLAN is Draft.** No GitHub issues exist for Wave 1; `plan-to-tasks.sh`
  would fall back to `ISSUE_SOURCE=plan_outline` for all 14 outlines.
- **Orchestrator over-reaches.** Items 8-14 have `**Type**: docs` with
  AC "produce a DESIGN doc." The orchestrator would spawn child
  workflows that try to execute those as if they were implementations,
  not route them to `/design`. There's no "per-outline needs-design
  bypass" in the orchestrator.
- **User said same branch.** Orchestrator defaults to creating
  `impl/<slug>`; it accepts `status: override` but then all the
  shared-PR / pr_finalization / ci_monitor / plan_completion ceremony
  still applies for what is ultimately seven small doc-focused edits.
  The cost/benefit doesn't line up.

**Recommendation.** The orchestrator needs an "only run outlines
matching these IDs" selector (e.g., `--wave`, `--only <ids>`, or a
frontmatter filter in plan-to-tasks.sh). Without it, "work on Wave 1"
has no first-class expression; you either modify the PLAN or go manual.

### 3. PLAN doc and PR state mismatch with user intent
The PLAN PR (#78) was written under the assumption that it would merge
before any implementation started. The user is now asking for Wave 1
implementation on the same branch, which means:
- PLAN status stays Draft across the Wave 1 commits (it's still
  pre-creation even if implementation is starting)
- PR #78's description will need updating to reflect the new scope
- The "follow-up commit runs the batch-creation script" sentence in
  the PLAN is no longer accurate — the batch creation should happen
  WITH Wave 1 commits if we want the PLAN's Implementation Issues
  table populated

**Recommendation.** Either `/plan` should support a mode where Wave-1
implementation and issue creation happen on the same branch as PLAN
authoring, or `/work-on --wave` on a Draft PLAN should explicitly
reject (and tell the user to merge the PLAN PR first).

---

## Per-issue entries

### Issue #1 — standardize on CLAUDE_PLUGIN_ROOT
- Clean fix. `grep -rln "CLAUDE_SKILL_DIR" skills/work-on/` surfaced
  two canonical files plus a pile of hits in
  `evals/workspace/iteration-5/…`. Initially flagged the workspace
  hits as a "drift trap" — then verified
  `**/evals/workspace/` is gitignored, so those local-only files
  don't affect the repo. `evals/evals.json` has no matches, and
  `evals/fixtures/` has no matches. Committed state is clean.
  **Observation kept for follow-up:** `scripts/run-evals.sh` spawns a
  `claude -p` subprocess that will regenerate workspace outputs; if
  run pre-fix it would have captured the old env-var name in its
  grading output. Worth re-running the work-on evals after Wave 1
  merges to confirm the fix doesn't regress an eval assertion that
  still checks for the old name.

### Issue #2 — validation:simple in phase-5 skip list
- Two-word change. No friction.

### Issue #3 — AC validation scripts advisory
- Wrote ~11 lines explaining both asymmetric cases (failing script +
  satisfied AC; passing script + unsatisfied AC). **Observation:** the
  friction log item that prompted this said the agent "picked (b)
  correctly but only after careful reading." This means the policy
  was the right one but the agent didn't have a written anchor to cite.
  Writing it down should reduce future hesitation.

### Issue #4 — opt-out subagent delegation for simplified plans
- Restructured the Agent Delegation section into two branches
  (full-plan, simplified-plan). **Observation:** this fix surfaces a
  downstream question — the `../agent-instructions/phase-3-analysis.md`
  file was written assuming a subagent reads it. Now the main agent
  reads it for simplified plans. The file still opens with "You are
  executing Phase 3... You will receive:" which reads awkward when the
  "you" is the main agent that wrote itself those inputs. Worth a
  follow-up: either split that file into
  `phase-3-fullplan-agent.md` + `phase-3-simplified-inline.md`, or
  rewrite the framing to be agent-neutral.

### Issue #5 — per-session tmp paths
- Touched three files. Added the `/tmp/koto-<WF>/` convention in
  phase-1, phase-3 agent-instructions, and phase-5.
  **Observation:** this would benefit from a single shared reference
  (e.g., `references/tmp-path-convention.md`) that each phase links
  to, rather than duplicating the path pattern across three files.
  Three's not bad but it sets up drift when someone changes one.

### Issue #6 — scope_expanded_retry transition
- Added the enum value and transition to work-on.md,
  regenerated work-on.mermaid.md via `koto template export`, ran
  `scripts/validate-template-mermaid.sh` — green. **Observation A:**
  the mermaid file in the repo is wrapped in a ```mermaid fenced
  block but `koto template export` outputs raw stateDiagram-v2
  content without the fence. I had to wrap it myself. Either the
  shirabe convention should drop the fence, or `koto template
  export` should gain a `--wrap` flag. **Observation B:** koto writes
  warnings to stderr during export, so naive `koto template export
  > file.md` captures the warning into the output. Splitting stderr
  (`2>/dev/null`) is easy but it's a footgun for first-time users.

### Issue #7 — mid-implementation AC re-confirmation
- Wrote the new subsection in phase-4-implementation.md. No friction.
  **Observation:** phase-4 now contains three related subsections
  about AC handling — "Re-confirm Acceptance Criteria
  Mid-Implementation", "Acceptance Criteria Validation Scripts",
  "Implementation Review". Readable, but getting dense. If more AC
  guidance lands, worth grouping into a single "Verifying against
  ACs" section.

---

## Overall wave observations

1. **Seven commits, zero koto state machine involvement.** I declined
   the orchestrator for the reasons in setup Observation 2, and
   never missed it. For this wave's scope (seven doc-leaning edits,
   one template change), a plain feature branch with commits was the
   right shape. The orchestrator's value would show up if these were
   code changes in different packages needing separate review panels
   — it's not inherently bad, just overkill here.
2. **Eval fixtures are a drift trap.** Issue #1 changed a string;
   eight eval workspace files now hold the old string as "expected
   output." If the next eval run auto-regenerates fixtures this is
   invisible; if it grades against the committed fixtures it's a
   silent false-positive. Worth an audit.
3. **TaskCreate sustained its value.** Seven discrete commits, seven
   TaskUpdate in_progress/completed cycles. The per-issue visibility
   to the user was clean. The reminders about unused task tools were
   still noisy in the early phase (two in this session), but
   once tasks were active and getting updated the reminders stopped.
4. **The PLAN PR (#78) was the right artifact.** Each commit message
   cites "Implements PLAN-work-on-friction-fixes.md Issue N", so the
   PLAN is a durable reference even though the issues never got
   created on GitHub. A reader can walk the PLAN and the commit log
   side-by-side and see full coverage. Suggests a lightweight "PLAN
   without GitHub issues" mode (items reference plan-outline IDs,
   not issue numbers) could be useful for waves this size.

## Follow-ups to surface

- **Eval-fixture audit** after #1 lands (are fixtures auto-regenerated
  or stale?).
- **phase-3-analysis.md agent-instructions framing** needs a rewrite
  now that both the main agent and the subagent read it (#4 follow-up).
- **`koto template export`** should either wrap mermaid in a fence or
  document the raw-output convention; warnings should go to stderr
  cleanly (koto feature request).
- **Cross-file path convention** — consider a single
  `references/tmp-path-convention.md` referenced from phase-1/3/5
  instead of duplicating the `/tmp/koto-<WF>/` path string (#5
  follow-up).

