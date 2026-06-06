# FC09 implementation handoff

This document is a self-contained briefing for a fresh Claude session picking up
the FC09 work in this worktree. PR #149 (FC07 + spec canonization) has merged;
this worktree sits on the clean post-merge main. Read this doc end-to-end before
starting any code.

## Quick start for the next session

1. You are at `/home/dgazineu/dev/niwaw/tsuku/tsuku-4/.niwa/worktrees/shirabe-4b5eb18b` on branch `session/4b5eb18b`.
2. Read this doc fully. Then read the issue body: `gh issue view 153 --repo tsukumogami/shirabe`.
3. Read the canonical references: `references/issues-table.md`, `references/dependency-diagram.md`.
4. Read the freshly-merged sub-DESIGN: `docs/designs/current/DESIGN-table-diagram-reconciliation.md` (cite Decisions 1-6).
5. Inspect the FC07 Rust surface you will extend: `crates/shirabe-validate/src/{lib,table,mermaid,checks,validate,formats}.rs`.
6. Begin Phase A of the implementation plan below.

## Where the project is

PR #149 just merged (commit `0b47617` on origin/main). It shipped:

- **FC07** -- three-dimension reconciliation (node-set bijection, edge agreement, class-vs-Status) for both Plan and Roadmap profiles, shipped as a notice via `is_notice` membership. Promotion to error is a one-line membership change.
- **Spec canonization** (D' phase) -- `references/issues-table.md` and `references/dependency-diagram.md` updated to reflect what authors actually do across the workspace corpus. `F<n>` dropped entirely; `I<n>` canonical for both profiles; roadmap-profile bijection by label-match against the Issues column; pipeline-stage classes, custom-mnemonic external nodes, three edge variants, subgraphs, and class overlays all documented.
- **Tactical chain artifacts** -- BRIEF/PRD/sub-DESIGN under `docs/{briefs,prds,designs/current}/`. Lifecycle states: BRIEF Done, PRD Done, sub-DESIGN Current.

Milestone #6 has 5 follow-ups remaining:

- **#116** (Slice D, ready) -- `--lifecycle` mode for the validator
- **#117** (Slice D, blocked on #116) -- reusable lifecycle workflow + cascade wiring
- **#152** (FC08, ready) -- Legend-vs-classDef reconciliation
- **#153** (FC09, ready) -- THIS WORK: doc-vs-GitHub state reconciliation
- **#154** (FC10, ready) -- single-pr plan validation + execution_mode-aware FC04 dispatch

Cross-repo follow-up filed: `tsukumogami/vision#530` -- 6 active vision roadmaps need 3-col to 4-col table migration.

Also filed mid-session: `tsukumogami/shirabe#150` -- clarify `/scope` skill orchestration (TeamCreate per child dispatch). Documentation gap, not blocking.

## FC09: what it is

GitHub issue: <https://github.com/tsukumogami/shirabe/issues/153>. Read the full
acceptance criteria there before anything else.

The short version: today's FC07/FC08 checks are intra-document; they reconcile
the table against the diagram. They cannot catch a plan that's perfectly
self-consistent but lies about external reality -- the doc claims an issue is
closed, table strikethrough applied, diagram painted green, and GitHub says
the issue is still open. FC09 closes that gap. Three sub-checks:

- **A (doc-claims-done vs GitHub):** every `done`-classed node and strikethrough row corresponds to an actually-closed issue on GitHub.
- **B (doc-claims-open vs GitHub):** every non-`done` row corresponds to an actually-open issue on GitHub (catches stale plans where someone closed via another PR but the doc was never updated).
- **C (PR `Closes #N` consistency):** when running in PR context, the body's `Closes #N` lines and the doc's `done`-claims must agree.

This is the first network-dependent check in the validator. The validator binary
is offline-only today. FC09 introduces a GitHub API surface, authentication
handling, rate-limit tolerance, and PR-context plumbing -- meaningful new
infrastructure. Ships as a notice (same staged-rollout shape as FC07/FC08).

## Implementation plan

Phase the work into commits. Suggested sequence:

### Phase A -- design call: `gh api` subprocess vs raw HTTP client

The acceptance criteria explicitly mention both paths. Pick one before writing
code. The decision is small enough to do inline (no separate spike needed):

- **`gh api` subprocess** -- shell out to the `gh` CLI. Pro: smaller code surface, auth comes free from `gh auth login` or `GITHUB_TOKEN`, easier to test (mock subprocess output). Con: runtime dependency on `gh` being present; CI containers need to install it; subprocess overhead per call.
- **Raw HTTP client** -- pick an `http`/`reqwest`-flavor crate. Pro: no runtime dep on `gh`. Con: meaningful new dependency (current crate has only `regex`); auth/retry/JSON-parsing all on our side.

Recommendation: **`gh api` subprocess** is the cleaner first cut. `gh` is already a dev/CI dependency in this repo (look at `validate-tsuku-recipe.yml` `install-latest` job). Subprocess shape is more testable. Pivot to HTTP only if subprocess overhead becomes a real bottleneck.

Capture this decision in the impl commit's message and a doc-comment on the
new client module.

### Phase B -- new module `crates/shirabe-validate/src/gh.rs`

Minimal client surface (illustrative, adapt as needed):

```rust
pub trait IssueStateClient {
    fn fetch_issue_state(&self, owner: &str, repo: &str, number: u64) -> Result<IssueState, ClientError>;
    fn fetch_pr_body(&self, owner: &str, repo: &str, pr_number: u64) -> Result<String, ClientError>;
}

pub enum IssueState { Open, Closed }
pub enum ClientError { Auth, Network, NotFound, RateLimit, Malformed(String) }

pub struct GhSubprocessClient { /* ... */ }
impl IssueStateClient for GhSubprocessClient { /* shells out to `gh api` */ }
```

Trait-based so tests can use a `MockIssueStateClient` with canned responses.

Defensive parsing on every `gh api` response; no panics on malformed JSON. The
token is never logged. Single retry + back-off on 429; on exhausted retries
the check self-disables with the appropriate notice rather than failing.

### Phase C -- `check_fc09` dispatch + sub-checks

In `crates/shirabe-validate/src/checks.rs`, add `check_fc09(doc, spec, client, pr_ctx)` alongside FC07. Dispatch in Plan and Roadmap arms of `validate_file`.

Sub-checks share these primitives from FC07:

- `Table.profile` (Plan or Roadmap)
- `parseIssuesTable` (returns rows with `Row.terminal`, `Row.status`)
- `Diagram.class_assignments` (from the mermaid extractor)
- Profile-specific key extraction (`#N` from the Issues column for Roadmap, from the entity row key for Plan)

For each row + corresponding diagram node:

1. Compute the doc's claimed state: `done` if strikethrough/closed, else `open`.
2. Fetch the GitHub state via the client (skip if `Sub-check A/B` should not engage for this row, e.g., the row's issue is cross-repo and we don't have token access).
3. Compare. Emit `[FC09]` notice on mismatch in either direction.

For Sub-check C, fetch the PR body once (cache it), extract `Closes #N` lines (regex), compare against doc claims.

### Phase D -- environment plumbing

Read these env vars at validator init:

- `GITHUB_TOKEN` -- the token. If absent and `gh` is configured locally, fall through to `gh auth status`. If neither, FC09 self-disables (emit one `[FC09] skipped: no GitHub credentials available` notice; validation otherwise proceeds).
- `GITHUB_REPOSITORY` -- e.g., `tsukumogami/shirabe`. Determines the "current repo" context for cross-repo logic. GitHub Actions sets this automatically.
- `GITHUB_REF` or `GITHUB_PR_NUMBER` -- determines if we're in a PR context. GitHub Actions sets `GITHUB_REF` to `refs/pull/<N>/merge` on `pull_request` events. Parse `<N>` from there OR plumb a dedicated `SHIRABE_PR_NUMBER` env var.
- `SHIRABE_FC09_DISABLE` (or similar) -- escape hatch for local dev to skip the check entirely. Document in the issue.

### Phase E -- tests

NO live GitHub calls in tests. Two options for mocking:

- **Trait-based**: pass a `Box<dyn IssueStateClient>` into `check_fc09`; tests construct a `MockClient` that returns canned responses per `(owner, repo, number)` tuple.
- **Fixture-based**: record real GH responses to `crates/shirabe-validate/testdata/gh-fixtures/`; the `GhSubprocessClient` has an env-toggle to read from fixtures instead of shelling out.

Trait-based is more testable and matches the existing in-file fixture pattern
(per sub-DESIGN Decision 4). Recommend trait-based.

Test cases to cover:

- Reconciled doc + GH (no notice)
- Sub A: doc-claims-done but GH-open (notice fires)
- Sub B: doc-claims-open but GH-closed (notice fires)
- Sub C: PR `Closes #150` but doc shows #150 as ready (notice fires)
- Sub C: doc claims #150 done but PR body has no `Closes #150` (notice fires)
- Missing token (FC09 skips with notice)
- Missing PR number (Sub C skips, Subs A/B run)
- 429 then retry succeeds
- 429 exhausted (FC09 skips with rate-limit notice)
- Malformed JSON response (no panic)
- Cross-repo ref (`tsukumogami/koto#65`) where token has no access (per-row 403 handling)

### Phase F -- `is_notice` membership + sub-DESIGN updates

- Extend `is_notice` to match `FC09`: `matches!(code, "SCHEMA" | "FC07" | "FC09")`.
- Update `docs/designs/current/DESIGN-table-diagram-reconciliation.md` to add a Decision noting FC09's coverage (or a new section "Decision 7: FC09 cross-source reconciliation").
- Update the parent PLAN to strikethrough #153.

### Phase G -- corpus impact survey

Run the validator with FC09 enabled against the shirabe corpus locally
(`./target/release/shirabe validate --visibility=public docs/plans/*.md docs/roadmaps/*.md`) and capture how many FC09 notices appear. This goes into the PR body's "Verification" section.

## Architecture context FC09 builds on

### File layout (`crates/shirabe-validate/src/`)

- `lib.rs` -- re-exports + `is_notice` function (the promotion seam for staged checks)
- `formats.rs` -- `FormatSpec` per artifact type; declares required sections, valid statuses, issues-table column contracts
- `table.rs` -- `Row`, `Table`, `Profile { Plan, Roadmap }`. `Row.terminal` and `Row.status` populated by classifier. `parseIssuesTable` does the markdown table parse.
- `mermaid.rs` -- `Diagram { nodes, edges, class_assignments, class_defs }`. `find_dependency_graph_block(doc)` locates the block; `extract_diagram(lines, start_line)` parses. Handles three edge variants (`-->`, `-.->`, `==>|"label"|`) and subgraph blocks.
- `checks.rs` -- per-check functions. FC07 lives here as `check_fc07(doc, spec)`. Profile-dispatched: Plan profile uses table-key bijection; Roadmap profile uses label-match against the Issues column.
- `validate.rs` -- top-level `validate_file(path, cfg)`. Dispatches by FormatSpec; calls all checks; aggregates notices and errors.

### Key types

- `Profile { Plan, Roadmap }` -- the dispatch key. Determines bijection rules. FC09 follows the same pattern.
- `Row { key, deps, terminal: bool, status: Option<String>, raw, ... }` -- entity row from the issues table.
- `Table { columns, rows, profile, ... }` -- the parsed table.
- `Diagram { nodes, edges, class_assignments, class_defs }` -- the parsed mermaid block.
- `ValidationError { code, message, line }` -- per-defect notice or error. FC09 emits these with `code = "FC09"`.

### How FC07's class-vs-Status pass works (for FC09 inspiration)

```rust
fn class_vs_status_pass(table: &Table, diagram: &Diagram, ...) -> Vec<ValidationError> {
    for (node_id, declared_class) in &diagram.class_assignments {
        let Some(row) = lookup_row_for_node(node_id, table) else { continue };
        if !STATUS_CLASSES.contains(declared_class) { continue }
        let observed_state = if row.terminal { "closed" } else { "open" };
        let expected_class = expected_class(row, ...);
        if declared_class != expected_class {
            errs.push(ValidationError { code: "FC07", message: ..., line: ... });
        }
    }
    errs
}
```

FC09 mirrors this loop but `observed_state` comes from `client.fetch_issue_state(...)` instead of `row.terminal`.

### Canonical spec (just landed in this PR)

- Plan profile: 3-col `Issue | Dependencies | Complexity`, `I<n>` diagram nodes bind to `#n` table keys (or `^_Child:` rows for tracks-design/tracks-plan).
- Roadmap profile: 4-col `Feature | Issues | Dependencies | Status`, `I<n>` diagram nodes bind to entity rows whose Issues column contains `[#n](url)` (label-match).
- Custom-mnemonic external nodes (`KT5V2`, `NW6`, etc.) excluded from FC07 bijection by regex (`^I[0-9]+$`); FC09 follows the same exclusion -- external refs are either cross-repo or unverifiable.
- Pipeline-stage classes (`needsPrd`, `needsDesign`, `needsSpike`, `needsPlanning`, `needsExplore`, `tracksDesign`, `tracksPlan`) are not Status classes; FC07 ignores them; FC09 only fires on Status classes (`done`/`ready`/`blocked`).
- Three edge variants in active corpus; FC07 normalizes them; FC09 doesn't care about edges (Subs A/B/C are all node-keyed, not edge-keyed).

## Workspace conventions (HARD constraints)

These bit me during this session; build them into briefing for any spawned agents.

### Branching and PRs

- **One issue per PR is the default** unless the user explicitly says otherwise.
- **PR title**: conventional commits, lowercase imperative. Example: `feat(validate): add fc09 doc-vs-github state reconciliation as a notice`.
- **PR body**: two-part template. Part 1 is plain paragraphs (no top-level `##` header) and becomes the squash-merge commit body. Then a `---` separator on its own line. Then Part 2 with `## ` section headers (Part 2 is deleted at merge). End with `Closes #N` lines.
- **NEVER use signing-bypass flags**: not `--no-verify`, not `--no-gpg-sign`, not `-c commit.gpgsign=false`. An agent in this session used these unnecessarily once and it was flagged as discipline violation. Plain `git commit -m "..."` only.
- **Conventional commit subjects**: lowercase imperative. `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`, `ci:`.
- **Public-cleanliness**: no `#N` issue/PR refs in committed code comments or docs. Commit messages may reference issues per conventional format (`Closes #N`). Spec/design docs may cite PRs by description but not by number.

### Workspace-wide writing

- No emojis anywhere.
- No AI attribution in commits or PRs (no `Co-Authored-By: Claude`, no "Generated with Claude Code").
- ASCII only except em-dashes (`--` in source is fine; em-dash characters acceptable but prefer `--`).
- Banned writing-style words: **tier, tiered, robust, leverage, comprehensive, holistic, facilitate**. (Watch for `tier` -- it sneaks in when discussing notice/error severity. Use `level` or `category` instead.)
- QA discipline: always `git diff origin/main...HEAD`, NEVER `git diff main...HEAD` (local main can be stale).

### wip-hygiene

- Files under `wip/` are non-durable. Committed to feature branches during workflows; MUST be removed before the PR can merge.
- "Clean up wip/" is two operations: (1) delete the files, (2) grep committed prose / frontmatter / code for `wip/` and remove every reference.
- A coordinator agent in this session committed a `wip/` artifact mid-work and had to push a separate cleanup commit. Cleaner to commit-then-cleanup-before-PR or never commit at all.

### Team-of-agents orchestration

- When invoking sub-skills via `/scope` (or `/charter`), each child dispatch must run inside a `TeamCreate`-spawned team with a coordinator who delegates to peers for the roles the skill requires. See memory: `~/.claude/projects/-home-dgazineu-dev-niwaw-tsuku-tsuku-4/memory/parent-skill-team-per-child.md` for the full rule.
- The standalone `Agent` tool is NOT available inside a team context (only `SendMessage`). Coordinators that need to run a skill's parallel-agent phase must EITHER run those evaluations inline OR have pre-spawned peer team members to delegate to via `SendMessage`.
- For non-skill implementation work (the impl phase of #153), the standard pattern is team-lead + coordinator + reviewer (and optionally pm for parent-PLAN tracking).

### niwa lifecycle

- Use `niwa_create_session(repo, purpose)` to create a worktree. Returns `session_id` and `worktree_path`.
- niwa is **only** for worktree management. All non-worktree work happens via local teams and agents. (The user reaffirmed this preference: "use niwa only to create/delete worktrees, for the rest you should use standard teams of agents locally to this session.")
- `niwa_destroy_session(session_id)` removes the worktree. Sometimes emits a false-positive "branch not deleted" warning if the branch was renamed during the session -- the renamed branch is fine; the warning is about the original session-named branch.
- This worktree is NOT being destroyed at end of session so the new session can pick up from here. Do not call `niwa_destroy_session(4b5eb18b)` until FC09 work is committed and pushed.

## What got built in PR #149 that you'll lean on

### Files you'll likely modify

- `crates/shirabe-validate/src/lib.rs` -- add `pub mod gh;` and extend `is_notice`
- `crates/shirabe-validate/src/checks.rs` -- add `check_fc09` and dispatch it in `validate_file`'s Plan and Roadmap arms
- `crates/shirabe-validate/src/validate.rs` -- `is_notice` extension lives here actually (not lib.rs); verify by reading

### Files you'll likely create

- `crates/shirabe-validate/src/gh.rs` -- new GitHub client module (trait + subprocess impl + mock for tests)

### Tests baseline

- 256/256 passing at the merge of #149. Add ~10-15 FC09 tests. Workspace `cargo test` should report 270+ passing post-FC09.

### Validator runs offline by default

The shipped binary works without any env vars. FC09's network-dependent
behavior is opt-in via credentials presence. Local dev without `GITHUB_TOKEN`
just sees one skip notice, not a failure.

### Reusable CI workflow

`.github/workflows/validate-docs.yml` is the reusable workflow downstream
callers use (e.g., vision pins it). The self-caller is
`validate-shirabe-docs.yml`. Both will exercise FC09 once it lands -- the
self-caller has access to a `GITHUB_TOKEN` automatically.

External callers (vision today) get `GITHUB_TOKEN` automatically too IF they
allow `permissions: contents: read, issues: read`. If their reusable-workflow
call doesn't grant the issues:read permission, FC09 will self-disable for
them with the appropriate notice. Worth checking when planning the FC09 PR
description.

## Open follow-ups (post-FC09)

Once FC09 lands, the milestone has:

- **#116** + **#117** (Slice D lifecycle work) -- can run in parallel with FC09 since they touch different code paths.
- **#152** (FC08 Legend reconciliation) -- smaller scope; could ship together with FC09 or after.
- **#154** (FC10 single-pr plan validation) -- requires a FormatSpec refactor (`execution_mode`-aware `required_sections`).

When milestone #6 closes (all 5 remaining issues done), the parent plan
`docs/plans/PLAN-roadmap-plan-standardization.md` should transition Active ->
Done, and per the lifecycle rule the file should be deleted in the
work-completing PR (single-pr-like ephemeral pattern -- this is the rule from
memory `~/.claude/projects/.../memory/plan-roadmap-lifecycle-guidelines.md`).

The parent BRIEF/PRD/DESIGN-roadmap-plan-standardization stay; their lifecycle
is BRIEF Done / PRD Done / DESIGN Current after the milestone completes (same
shape as the sub-feature artifacts).

The vision migration (`tsukumogami/vision#530`) is on the vision side and
unblocked. Coordinate that work whenever the vision team is ready -- not on
the shirabe critical path.

## Things this session learned the hard way

1. **`/scope`'s SKILL.md is misleading on orchestration**. It says "single-agent skill, no team is spawned" -- the user clarified that's wrong; the intent is one team per child dispatch with a coordinator. Filed as `tsukumogami/shirabe#150`. Memory saved at `parent-skill-team-per-child.md`. **Apply this rule from memory, not from the skill doc.**

2. **The spike's recommendations got partially overruled by D'**. Spike #118 recommended `F<n>` as documented tolerance; D' dropped `F<n>` entirely. The spike doc is preserved at `docs/spikes/SPIKE-mermaid-parser.md` (Complete spikes are durable historical records per spec). Future readers cross-reference current refs for current truth.

3. **D' was empirically grounded**. The user pushed back on "extend FC07 to match the spec" and asked us to survey vision's roadmaps first. The survey found a coherent shape the spec didn't describe, and the spec got updated to match what authors actually do. **Spec-follows-corpus is the right default for most patterns; spec-as-target is the exception** (3-col table got pushed back to 4-col canonical even though vision uses 3-col, because 3-col defeats FC07's edge agreement).

4. **PR body and title need to track scope as it grows**. PR #149 expanded mid-flight to include D'. Multiple body rewrites. Worth considering a "PR scope may expand" callout in the initial PR body when the work has unknowns.

5. **The parity test fixture (`crates/shirabe/tests/parity.rs` and `tests/fixtures/golden/expected/`) is sensitive to validator output changes**. When extending FC07 mid-session, the parity test broke on `real_roadmap_strategic` because the Go baseline didn't include FC07-roadmap notices. The D' label-match algorithm coincidentally produced 0 notices on the strategic-pipeline fixture (Issues=None on every row), so parity was restored. Future check additions need to check parity fixtures explicitly.

6. **The validator currently does not differentiate single-pr from multi-pr plans**. `FormatSpec.required_sections` is a flat list. `## Implementation Issues` and `## Dependency Graph` are required regardless of mode, even though single-pr's authoritative content lives in `## Issue Outlines`. This means single-pr plans pass FC07/08/09 vacuously today. FC10 (#154) will fix this. **FC09's class-vs-Status pass should still run on single-pr plans IF they happen to have populated Implementation Issues (rare but possible) -- behavior under FC10's refactor is TBD.** Coordinate with #154 if you do both.

7. **Coordinators inside a team can't spawn Agents**. They only have SendMessage between named teammates. If FC09 needs parallel work (e.g., concurrent fetches), implement it as concurrent calls within one coordinator's process, NOT as Agent fan-out.

8. **Background CI-wait commands report `failed` because of post-loop `pwd`-after-worktree-destroyed errors**. The actual CI status in the output file is what matters; the exit code from the bash background wait is a false signal. When using `until ... done` background commands, read the file to get the real result.

## Pre-flight checklist for the next session

Before writing any FC09 code:

- [ ] Read this doc end-to-end (you are here)
- [ ] Read `gh issue view 153 --repo tsukumogami/shirabe` for the canonical acceptance criteria
- [ ] Read `references/issues-table.md` and `references/dependency-diagram.md` to understand what FC09 reconciles against
- [ ] Read `docs/designs/current/DESIGN-table-diagram-reconciliation.md` (especially Decision 1, Decision 6) for the sub-DESIGN context
- [ ] Inspect `crates/shirabe-validate/src/checks.rs` (FC07 impl) for the dispatch pattern + per-defect notice voice you should mirror
- [ ] Inspect `crates/shirabe-validate/src/table.rs` and `mermaid.rs` for the data shapes FC09 consumes
- [ ] Run `cargo test --all 2>&1 | tail -5` from this worktree to confirm the baseline 256/256 passing
- [ ] Run `./target/release/shirabe validate --visibility=public docs/plans/*.md docs/roadmaps/*.md` after a release build to confirm shirabe corpus passes FC07 with 0 notices (baseline before FC09)
- [ ] Decide Phase A (gh subprocess vs raw HTTP) explicitly; note the call in your first impl commit message
- [ ] Verify `GITHUB_TOKEN` available in your dev shell (test with `gh api user`) so you can run live integration spot-checks

Then start Phase B.

## How to engage the user during FC09 work

The user's working style observed in this session:

- **Direct, low-ceremony**. They expect concise answers. Brief is good; silent is not.
- **Pushes back on assumptions**. Multiple times in this session, surfacing complexity or design tension was the right move (the F<n>→I<n> pivot, the spec-vs-corpus question, the single-pr gap, the Legend gap, the doc-vs-GitHub gap). They appreciate when you surface a real concern -- but they want it framed clearly with options.
- **Uses AskUserQuestion for non-trivial decisions**. When facing a design fork, use the tool; don't just pick one direction. They prefer to make the call.
- **No mid-session compaction**. They'll explicitly `/compact` when ready.
- **Background tasks**: when you spawn `run_in_background: true` agents or commands, just wait for the notification -- don't poll.

Things they consistently flagged:
- Inconsistent use of teams when one was warranted (the `/scope` chain incident)
- Stale docs / references in non-touched files (the `skills/plan/SKILL.md` 3-col reference)
- Premature claims of completion (the "spike served its purpose, delete it?" question -- which was correctly answered "no" because spec says spikes are durable)

## Final state of PR #149 (for cross-reference)

- Merged at `0b47617 feat(validate): add mermaid extractor and table-diagram reconciliation (#149)` on origin/main
- 23 commits, +/- ~4500 lines net
- Closed #118 (spike) and #119 (FC07)
- Tests: 162 -> 256 (+94 net)
- Reviewer paths and discipline checks all green
- CI 6/6 SUCCESS on merge

The fresh session starts from this base. Good luck with FC09.
