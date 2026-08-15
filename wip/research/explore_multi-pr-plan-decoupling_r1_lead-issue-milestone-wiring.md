# Lead: Where does GitHub issue and milestone creation get wired, and what downstream consumers depend on those artifacts existing?

## Findings

### 1. Where issues/milestones get created

**`skills/plan/references/phases/phase-2-milestone.md`** — derives the milestone
title/description for a PLAN's source document (design/prd/roadmap/topic input).
Writes `wip/plan_<topic>_milestones.md`. This is pure derivation; no `gh` calls
here. One document (or topic) maps to exactly one milestone (line 20-22).

**`skills/plan/references/phases/phase-7-creation.md`** is the actual creation
point, and it is **strictly mode-gated**:

- `multi-pr` mode (7.1): calls `create-issues-batch.sh` with `--milestone` and
  `--milestone-description`, producing GitHub issues + a milestone.
- `single-pr` mode (7.1, separate section, line 237-241): *"No GitHub milestone
  or issues are created in single-pr mode."* The PLAN doc embeds Issue Outlines
  directly instead (internal `I1`/`I2` IDs in the dependency graph, not GitHub
  numbers).

So the coupling the author is describing is real and lives exactly here: the
`execution_mode` enum (`single-pr` / `multi-pr` / `coordinated`) is the single
flag that simultaneously selects (a) whether the PLAN self-contains its issues
vs. delegates to GitHub, and (b) how downstream tooling tracks/resumes/executes
the work. There is no PLAN-level knob independent of `execution_mode` for "use
GitHub issues or not."

**`skills/plan/scripts/create-issues-batch.sh`** (lines 265-352) does the `gh`
work: creates the milestone via `gh api repos/$repo/milestones` if it doesn't
exist (or reuses an existing one by title match), then creates each issue with
`gh issue create --milestone <name>`.

**`skills/plan/scripts/create-issue.sh`** — single-issue fallback used when the
batch script reports a per-issue failure (phase-7-creation.md line 123-130);
also accepts `--milestone`.

**`skills/roadmap/`** — `shirabe roadmap populate <path> --issues` uses the
*same* `create-issues-batch.sh` with the same `--milestone`/`--milestone-description`
flags (`skills/roadmap/SKILL.md:419-420, 445-446`). So **ROADMAP does use
milestones the same way PLAN does** — same script, same one-per-document
convention, same `gh api repos/$repo/milestones` create-or-reuse logic.

### 2. Downstream consumers of GitHub issue/milestone state

- **`/work-on` (`skills/work-on/SKILL.md`)** is the direct, load-bearing
  consumer for multi-pr PLANs:
  - Milestone input mode (`M3`, milestone URL, or `"Milestone Name"`, line 19):
    lists open issues in the milestone via `gh`, checks each issue's
    Dependencies section for open blockers, and picks the lowest-numbered
    unblocked one. **This is a scheduler that only exists because a GitHub
    milestone groups the issues** — there's no other artifact `/work-on`
    consults to answer "what's next in this plan."
  - Issue-backed mode (line 150): `ISSUE_SOURCE=github` reads the issue via
    `gh issue view <N>` during `plan_context_injection` for title/body/labels,
    vs. `ISSUE_SOURCE=plan_outline` which extracts the same information from
    the PLAN doc's Issue Outlines section (single-pr path). These two paths
    are already parallel and mutually exclusive per PLAN — `plan-to-tasks.sh`
    (see contract doc) emits `ISSUE_SOURCE: github` + `ISSUE_NUMBER` for
    multi-pr rows and `ISSUE_SOURCE: plan_outline` + `ARTIFACT_PREFIX` for
    single-pr rows, driven purely by `execution_mode` in the PLAN frontmatter.
  - Milestone context is also injected as background context in
    `phase-0-context-injection.md:25` ("Milestone context for broader goals").

- **`/execute` (`skills/execute/SKILL.md`)** is explicitly **not** a consumer
  of GitHub-issue-per-work-item tracking for multi-pr: line 40-41 states
  multi-pr plans are **out of scope for `/execute`** — "multi-pr plans run one
  issue at a time through `/work-on` against the repo-persisted PLAN." `/execute`
  only drives `single-pr` and `coordinated` PLANs, and neither of those creates
  GitHub issues (single-pr embeds outlines; coordinated tracks state through a
  durable **home PR**, not through issues/milestones — see below).

- **`/execute`'s own state/resume model does not use issues or milestones at
  all.** Its Resume section (`SKILL.md:419-461`) does a **topic-keyed home-PR
  lookup via `gh pr list --search "<topic> in:title"`** and rebuilds a
  `wip-yaml-md` state projection from that PR's body — cross-branch resume
  (`I-6`) is anchored on a PR, not a milestone. Its "durable home" for
  friction-log/report-upstream notes (line 397-406) is a GitHub issue only as
  a fallback convention for narrative artifacts, unrelated to the milestone/
  issue-per-task tracking mechanism.

- **`/inflight` (`skills/inflight/SKILL.md`)** tracks *pull requests* the
  session opened (a private per-session PR ledger via `shirabe work-summary`),
  not GitHub issues or milestones. Not a consumer of this coupling at all —
  included for completeness since the lead asked to check it.

- **`plan-to-tasks.sh` / `plan-to-tasks-contract.md`** is the seam between the
  PLAN doc and koto task materialization. For multi-pr it reads the
  `## Implementation Issues` table's `#N` GitHub references and Dependencies
  column and emits `ISSUE_SOURCE=github`/`ISSUE_NUMBER` per task — i.e., the
  *execution graph itself* (`waits_on`) for multi-pr is read out of the PLAN
  doc's own table, not out of GitHub's dependency data; GitHub issue numbers
  are just referenced as row identifiers. Nothing here queries `gh` for
  dependency edges — those come from the PLAN doc's Dependencies column, same
  as single-pr's outline-based edges.

### 3. What would break if issues didn't exist (multi-pr, concretely)

- **`/work-on`'s milestone-driven "what's next" scheduler** (SKILL.md:19)
  has no substitute today — it is the only mechanism that answers "give me the
  next unblocked item in this plan" without a human naming an issue number.
  For single-pr, the equivalent already exists and doesn't need GitHub: the
  Issue Outlines section + `plan-to-tasks.sh`'s `waits_on` graph.
- **Per-issue title/body/labels as agent context** (`gh issue view`) — for
  multi-pr this is the agent-facing brief for the unit of work. Single-pr's
  parallel path (`ISSUE_SOURCE=plan_outline`) already proves this is fully
  replaceable by reading the outline straight from the PLAN doc; nothing
  GitHub-specific is required for the *content* to reach the agent.
  Multi-pr PLANs live only on a branch (**the accepted boundary the lead
  states: single-pr/coordinated never land as durable multi-issue GitHub
  state because "those never reach main"**) — but multi-pr PLANs, per the
  boundary given, DO reach main eventually as merged code across several PRs,
  which is exactly why the author's proposal keeps issues/milestones as an
  *option* for multi-pr rather than removing them outright.
- **Cross-branch/cross-session resume for multi-pr** — today this is implicit:
  each issue is its own `/work-on` invocation, and the milestone is the
  grouping that lets a second session re-discover "what's left." There is no
  `wip-yaml-md`/home-PR analog for multi-pr the way `/execute` has for
  single-pr/coordinated. If issues+milestone were removed with nothing put in
  their place, multi-pr would lose both its work-item boundary *and* its
  resume/progress mechanism simultaneously — this is the concrete risk in
  decoupling "tracking mechanism" from "can it land in one PR."
- **Progress reporting** (`gh issue list --milestone`, phase-7-creation.md:203-209)
  is the verification step after creation and implicitly the ongoing progress
  view (closed vs. open issues in the milestone) — nothing else currently
  renders "how much of this multi-pr plan is done."

### 4. The existing "issueless" path — ROADMAP only, not PLAN

`docs/designs/current/DESIGN-populate-issueless-default.md` and its
predecessor `docs/designs/current/DESIGN-roadmap-issueless-preference.md`
describe a real, shipped issueless mode — but **it belongs to `/roadmap`, not
to `/plan`'s multi-pr mode**. Mechanism (from the DESIGN doc):

- `shirabe roadmap populate <path>` resolves its mode on a stack:
  **`--issues` / `--no-issues` flag → `## Roadmap Issues:` CLAUDE.md header
  (`required`/`optional`) → issueless default** (the DESIGN flips the default
  from issue-creating to issueless; `docs/designs/current/DESIGN-roadmap-issueless-preference.md`
  introduced the header and the issueless renderer in the first place).
- Issueless mode renders the roadmap's reserved Implementation Issues /
  Dependency Graph sections **without filing GitHub issues at all** — a
  separate renderer pair (`render_issueless_table`/`render_issueless_diagram`)
  keyed off the same Features section, no `gh` `Command` constructed.
  `/roadmap` now runs this automatically at two points (post-jury, and on
  Draft→Active activation) so a roadmap is never merged with the reserved
  sections empty; the **issue-creating** path only runs on explicit
  `--issues`/`required`.
- **I found no equivalent flag, header, or code path anywhere in `skills/plan/`.**
  `grep -rn -i "issueless\|no_issues"` across `skills/plan/` returns nothing.
  Multi-pr PLAN has exactly one path (issue-creating); single-pr has exactly
  one path (no issues, ever). There is no PLAN-level "optional" middle mode —
  the mode is hard-selected by `execution_mode`, not read from a preference
  header the way ROADMAP's `## Roadmap Issues:` is. **This directly confirms
  the lead's framing**: the mechanism the author wants to generalize
  (preference-driven, header-resolved, issueless-capable) already exists and
  is proven — for ROADMAP — but PLAN has never had it plumbed in.
- The DESIGN doc's own C2 stack (`flag > header > issueless default`) and its
  R7 constraint ("automatic populate is always issueless regardless of the
  header... an automatic run must never create issues") is a template that
  transfers cleanly to a `## Plan Issues:`-style header for multi-pr PLAN,
  though nothing currently implements it.

### 5. `plan-to-tasks-contract.md` — the plan-doc/GitHub-state boundary

The contract document draws the boundary implicitly, by mode, rather than
stating it as a principle:

- multi-pr vars are `ISSUE_SOURCE=github` + `ISSUE_NUMBER` — the koto task is
  *keyed by a GitHub issue number*, so `run-cascade.sh`/`work-on.md` must
  `gh issue view` to get anything.
- single-pr vars are `ISSUE_SOURCE=plan_outline` + `ARTIFACT_PREFIX` (+ optional
  `ISSUE_TYPE`) — the koto task is keyed by a **slug generated from the PLAN
  doc's own heading text**, with GitHub playing no role at task-materialization
  time.
- coordinated mode collapses issue-level `waits_on` into `(repo, pr_group)` PR
  nodes; `gh` still isn't queried here — the graph comes from the PLAN table's
  `Repo`/`Group`/`Gate` annotations.

So the contract already treats "does this task reference a GitHub issue" as a
**per-mode, not per-repo, decision** baked into `ISSUE_SOURCE`. Generalizing
that to a repo preference would mean multi-pr PLANs could, in principle, also
emit `ISSUE_SOURCE: plan_outline`-shaped tasks — but today `plan-to-tasks.sh`'s
multi-pr branch unconditionally parses the `## Implementation Issues` table's
`#N` GitHub-reference cells (line 181: "For each data row where the first cell
contains `#N`") — an issueless multi-pr PLAN would have no `#N` to parse, so
this script's multi-pr branch would need either a third source-var scheme or
to reuse `plan_outline` semantics with a different internal-ID scheme than
single-pr's `o-<slug>` (multi-pr's dependency table already uses `#N` per
issue, not per internal ID, so a straight reuse isn't a drop-in).

## Implications

- The author's "tracking mechanism should be a repo preference" is not a new
  idea in this codebase — it is the exact shape ROADMAP already ships (header
  + flag + issueless default, R7's "automatic run is always issueless"
  invariant). The natural implementation path is to lift that mechanism
  (`## Roadmap Issues:` → e.g. `## Plan Issues:`) into `phase-2-milestone.md`
  and `phase-7-creation.md`'s multi-pr branch, rather than inventing a new
  preference-resolution shape.
- The load-bearing gap is **not** issue creation itself — DESIGN-populate-
  issueless-default.md already proves issueless *rendering* is straightforward
  — it's that **`/work-on`'s milestone-driven scheduler and multi-pr's
  cross-session resume have no non-GitHub substitute today.** An issueless
  multi-pr PLAN would need either (a) an outline-based "what's next" resolver
  analogous to single-pr's, reused across separate `/work-on` invocations on
  separate branches, or (b) to accept that issueless multi-pr loses the
  "resume by re-invoking `/work-on M<milestone>`" convenience and always
  re-derives position from the PLAN doc + git state.
- `plan-to-tasks.sh`'s multi-pr branch is coupled to `#N` GitHub references at
  the parsing level (not just the creation level), so decoupling execution_mode
  from tracking mechanism touches this script's contract, not just phase-7's
  creation step — this is a concrete implementation cost the design will need
  to account for, and `plan-to-tasks-contract.md` will need a documented third
  var scheme (or a repurposed `plan_outline` scheme with `#N`-shaped internal
  IDs) if multi-pr goes issueless.

## Surprises

- `/execute` is a total non-consumer of issues/milestones for multi-pr — it
  explicitly declines to run multi-pr PLANs at all (line 40-41). All multi-pr
  issue-state consumption is concentrated in `/work-on` alone. This narrows
  the blast radius of a multi-pr-issueless change considerably: one skill
  (`/work-on`), not two.
- The issueless mechanism is more mature and more load-bearing than "an
  existing path that could be extended" suggests — it already has an explicit
  R7 rule (automatic runs are *always* issueless, never mode-selected) baked
  in specifically to prevent a workflow from ever depending on the default.
  Any multi-pr analog should inherit that same rule: an automatic multi-pr
  `/plan` run should never depend on falling through to the issue-creating
  default either.
- `/inflight` turned out to be entirely unrelated (PR ledger, not issue/
  milestone state) — worth ruling out explicitly since the lead named it.

## Open Questions

- If multi-pr PLAN goes issueless, what replaces `/work-on`'s
  `M<milestone>` "select next unblocked issue" input mode? Is a milestone-less
  multi-pr PLAN still invoked issue-by-issue by number, or does `/work-on`
  need a `docs/plans/PLAN-*.md` + outline-index argument the way single-pr's
  PLAN-path mode already works for `/execute`?
- Does an issueless multi-pr PLAN still produce *separate PRs per issue* (the
  defining multi-pr property) without GitHub issues to hang each PR off of —
  e.g., branch-per-outline-slug instead of branch-per-issue-number? This
  wasn't visible in any file read for this lead and needs its own investigation.
- Should the `## Plan Issues:` (or equivalent) preference apply uniformly to
  both PLAN and ROADMAP, or does PLAN need its own header separate from
  ROADMAP's since a repo could reasonably want roadmap-level tracking issues
  but not want per-plan-issue GitHub issues (or vice versa)?

## Summary

Issue/milestone creation for multi-pr PLANs is created only in
`skills/plan/references/phases/phase-7-creation.md` via `create-issues-batch.sh`
(same script and milestone convention ROADMAP uses), and consumed almost
entirely by `/work-on` — its milestone-driven "pick the next unblocked issue"
scheduler and its `gh issue view` context read — while `/execute` explicitly
refuses to run multi-pr PLANs at all, so the blast radius of decoupling is
concentrated in one skill. ROADMAP already has a mature, proven issueless
mode (flag → CLAUDE.md header → issueless-default stack, with an explicit rule
that automatic runs never create issues) that PLAN has no equivalent of
(`grep` for issueless/no_issues in `skills/plan/` returns nothing) and that is
the natural template to generalize — but making multi-pr PLAN issueless isn't
just a phase-7 change: `plan-to-tasks.sh` parses `#N` GitHub references at the
task-extraction level for multi-pr, and `/work-on` has no non-GitHub substitute
today for cross-session "what's next" resume, so those are the two places a
decoupling design has to land new behavior, not just gate existing behavior
behind a flag.
