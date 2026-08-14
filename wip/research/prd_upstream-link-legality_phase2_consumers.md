# Consumers of the `upstream:` frontmatter field

Phase 2 research for the upstream-link-legality PRD. Every reader of the
`upstream:` field in the shirabe repo, what it does with the resolved target,
and whether it survives the removal of the recorded BRIEF -> ROADMAP edge.

All paths are relative to the repo root
(`/home/dgazineu/dev/niwaw/tsuku/tsuku+upstream_link_legality-aa457090/public/shirabe/.claude/worktrees/upstream-link-legality`).

---

## 0. The single parse path (not a consumer, the shared front door)

`crates/shirabe-validate/src/upstream.rs`

- `upstream_entries(doc)` (line 69) — the entries of a doc's `upstream:` field.
- `field_entries(field)` (line 82) — scalar = one entry (never split); sequence
  = one entry per item.
- `classify(text)` (line 103) — `Blank` / `Placeholder` (anything containing
  `<` or `>`) / `Path`, with `cross_repo` marked (line 133,
  `owner/repo:path` discriminator).

The module header (lines 4-7) claims **three** readers: `check_upstream_resolves`,
`lifecycle::extract_upstreams`, `finalize::walk_chain_mode`. That comment is
**still accurate for this module** — grepping `upstream_entries|field_entries|
classify` across `crates/` returns exactly those three call sites
(`checks.rs:822`, `lifecycle.rs:460`, `finalize.rs:1146`). It is **incomplete as
a census of the field's readers**: it does not count the readers that consume
those three transitively (the referrer map, chain discovery, the orphan rule),
nor the four non-Rust readers below (three shell scripts, one CI workflow), nor
FC12's presence-only probe.

---

## 1. R6 resolution check — `check_upstream_resolves`

- **File/function:** `crates/shirabe-validate/src/checks.rs:791`
  (`check_upstream_resolves`), wired in `validate.rs:217`.
- **Doc types:** every format that carries the field. The doc comment (line 768)
  is explicit: "The check runs for every format, not just Plan." In practice:
  PLAN, DESIGN, PRD, BRIEF, ROADMAP, STRATEGY.
- **What it does with the target:** existence only, plus git-tracking. `Path::new
  (path).exists()` (line 839) then `git ls-files --error-unmatch` (line 847).
  Never opens the file, never reads its status, never walks further. Cross-repo
  entries are skipped (line 834); placeholders are skipped (line 829); an empty
  field or an empty sequence entry is itself a finding (lines 806/826).
- **Survives BRIEF losing its ROADMAP upstream? YES.** An absent `upstream:` key
  returns an empty vector at line 792-795 before anything is checked. R6 has no
  opinion about which type an upstream names; removing the edge removes the check.

## 2. Lifecycle index and the graph built on it

- **File/function:** `crates/shirabe-validate/src/lifecycle.rs:457`
  (`extract_upstreams`), called from `index_doc` (line 405) during
  `build_doc_index` (line 316). Resolution here joins the canonical repo root,
  canonicalizes, drops cross-repo entries, and suppresses self-references.
- **Doc types:** everything under `docs/{briefs,prds,designs,designs/current,
  plans,roadmaps}` with a `BRIEF-`/`PRD-`/`DESIGN-`/`PLAN-`/`ROADMAP-` prefix
  (lines 335, 360-365). `docs/strategies/` and `docs/visions/` are **never
  indexed** (see the comment at lines 678-686), so a ROADMAP's own
  `upstream: STRATEGY` edge is deliberately dropped on the floor.
- **What it does with the target:** builds three derived structures.
  - `build_inverse_upstream` (line 483) — parent -> children map.
  - `build_referrer_map` (line 539) — the narrow public API the finalization
    walk reads; per-referrer `path`/`format`/`status` plus `is_terminal()`
    (line 518).
  - `discover_chains` (line 592) — see 2a.
- **Survives? YES**, mechanically. Fewer edges, no failure.

### 2a. Chain discovery — `discover_chains`

- **File/function:** `lifecycle.rs:592`. Roots at every `Plan` and every
  `Roadmap` (lines 597-601) and walks the forward `upstream:` edge.
- **Doc types read:** PLAN, DESIGN, PRD (their upstreams are followed).
- **The load-bearing detail:** the walk **stops at a BRIEF and at a ROADMAP**
  (line 690, `if matches!(node.format.as_str(), "Brief" | "Roadmap") { continue; }`).
  The comment at lines 672-687 states the intent plainly: "If a BRIEF carries an
  `upstream:` field ... that's a cross-chain reference, not a chain-membership
  edge, and we do not follow it."
- **Consequence, verified by reading the loop:** a BRIEF's `upstream:` is
  **never** a chain-membership edge. A ROADMAP-rooted chain is therefore always a
  singleton — the root is pushed as a member, then the same line-690 stop fires
  and the frontier empties. The BRIEF -> ROADMAP edge contributes **zero**
  members to any chain, in either direction.
- **Survives? YES.** This traversal already behaves as though the edge does not
  exist. Removing it changes no chain's membership, posture, or passing state.

### 2b. Orphan rule (L02) — `check_orphan`

- **File/function:** `lifecycle.rs:1255`.
- **Doc types:** BRIEF, PRD, DESIGN (PLAN and ROADMAP return early at line 1263).
- **What it does with the target:** three passes, in order.
  1. Terminal-status orphan passes (line 1269).
  2. **Non-terminal orphan whose own upstream resolves to a `Roadmap` at status
     `Active` passes** (lines 1276-1282). This is the *only* place in the
     codebase where the type and status of a BRIEF's upstream is consulted.
  3. Otherwise, any inbound `upstream:` reference from any doc, or an own
     upstream resolving to a `Brief`/`PRD`/`Design`/`Plan`, passes (lines
     1311-1316). The comment at 1303-1310 says `"Roadmap"` is *deliberately
     excluded* from that type list so that only an **Active** ROADMAP exempts.
- **Survives? PARTIALLY — this is the one real behavioral loss.** A BRIEF at
  `Draft`/`Accepted` that (a) has no downstream child yet and (b) has no
  tactical upstream currently passes L02 *only* through branch 2. Drop the edge
  and that BRIEF fails L02 with
  `orphan BRIEF at status 'Accepted' (expected status 'Done', an Active ROADMAP
  upstream, or a tactical upstream/downstream chain link)` (line 1331). The
  window is narrow — the moment a PRD is written naming the BRIEF as its
  upstream, branch 3 covers it — but it is a genuine regression for the
  brief-written-first-nothing-downstream-yet state, which is exactly what
  `/brief` produces at the end of a standalone run.

## 3. Finalization walk — `walk_chain_mode` (the cascade's engine)

- **File/function:** `crates/shirabe-validate/src/finalize.rs:482`
  (`walk_chain_mode`), reading through `read_upstream_entries` (line 1144) and
  classifying with `classify_node` (line 660). Exposed as
  `shirabe finalize-chain <plan>` (`crates/shirabe/src/main.rs:75`).
- **Doc types read:** PLAN, DESIGN, PRD, BRIEF — everything `expands()` admits
  (line 648). ROADMAP, VISION, cross-repo and unrecognized nodes end their
  branch and are **not** expanded.
- **What it does with the target:** dispatch by filename prefix (lines 688-707).
  - `Design` -> `TransitionDesign` (strip `## Implementation Issues`, transition
    to `Current`, possibly `git mv` into `current/`).
  - `PRD` -> `TransitionPrd` (`Done`). `Brief` -> `TransitionBrief` (`Done`).
  - **`Roadmap` -> `NodeAction::RoadmapHandoff`, `target_status: None`, branch
    ends** (line 692). finalize-chain itself does nothing to the ROADMAP: it
    emits a report node with `"action": "roadmap_handoff"` and the ROADMAP's
    path, and hands the whole question to the caller.
  - `VISION` / cross-repo -> `Stop`; unknown prefix -> `Error`.
  Before any mutation, the retirement guard (`decide`, line 773) consults the
  referrer map: a non-terminal referring doc that this walk is not itself
  retiring blocks the transition (reported, not fatal). Note the guard never
  runs for a ROADMAP node — `target_status.is_none()` short-circuits to
  `Verdict::kept()` at line 792.
- **Survives? NO, for the ROADMAP leg specifically.** The report only ever
  contains a `roadmap_handoff` node if some walked node's `upstream:` names a
  `ROADMAP-` file. The walk expands PLAN, DESIGN, PRD and BRIEF; per
  `references/pipeline-model.md:113` and `skills/brief/references/brief-format.md:61`,
  the BRIEF is the node that carries that pointer in a full chain. Remove it
  from a chain that has a BRIEF and no other node names the ROADMAP, and the
  walk terminates at the BRIEF. The other legs (DESIGN/PRD/BRIEF transitions,
  the PLAN delete node) are unaffected — this is proved by
  `run-cascade_test.sh` Scenario 7 (`scenario_brief_no_upstream`, line 711),
  which asserts `transition_brief ok` and `cascade_status == "completed"` for a
  BRIEF with no upstream at all.

## 4. Cascade orchestration — `run-cascade.sh`

- **File:** `skills/execute/scripts/run-cascade.sh`. Reads the finalize-chain
  report, not the frontmatter, except for the PLAN path validation
  (`validate_upstream_path`, line 89 — repo-containment, regular file,
  git-tracked; applied only to `$PLAN_DOC`).
- **Doc types:** whatever finalize-chain reports.
- **What it does with the resolved target:**
  - `roadmap_handoff` (line 799): stores `ROADMAP_PATH="$target"` and
    `ROADMAP_FOUND_IN="$prev_path"`, then calls `handle_roadmap` at line 832.
  - `handle_roadmap` (line 392): greps the ROADMAP for a line containing the
    **plan slug** (`PLAN_SLUG`, derived at line 696 from the PLAN filename) that
    also matches `Downstream:` (line 401); walks up to the enclosing `### `
    heading (line 411); rewrites that feature's `**Status:**` to `Done` (awk,
    line 426) and its `**Downstream:**` to the post-move DESIGN basename
    (line 445, from `CASCADE_DESIGN_PATH`). No match -> a `skipped` step with a
    diagnostic (lines 403-407).
  - `handle_roadmap_deletion` (line 505): if every `**Status:**` line reads
    `Done` and every `https://github.com/.../issues/N` in the file is CLOSED,
    it runs `shirabe transition <roadmap> Done` and `git rm -f` the ROADMAP.
  - So the cascade **transitions, rewrites and deletes** the ROADMAP it reaches.
    This is the heaviest thing any `upstream:` consumer does.
- **How it locates the ROADMAP — precisely:** `ROADMAP_PATH` is assigned in
  exactly one place (line 803), from the report node's `path`. There is no
  directory scan, no `docs/roadmaps/` glob, no fallback. Grepping the script for
  `roadmaps` returns nothing. **The recorded `upstream:` chain is the only route
  into the ROADMAP file.** Once inside the file, the feature entry is found by
  the plain-text `Downstream:`/slug grep described above.
- **Survives? NO** when the chain's only ROADMAP pointer was the BRIEF's. The
  failure is silent-ish and graceful: no `update_roadmap_feature` step, no
  `delete_roadmap` step, `cascade_status: completed`, exit 0. The ROADMAP feature
  keeps its stale `**Status:** Planned` forever and the ROADMAP is never
  deleted. Nothing in the pre/post lifecycle probes catches it — the probe is
  `--lifecycle-chain "$PLAN_DOC"` (line 296), whose scope comes from
  `discover_chains`, which (see 2a) never puts a ROADMAP in a PLAN-rooted chain.

### 4a. Evidence that the ROADMAP leg is reachable by more than one edge

`run-cascade_test.sh` builds the ROADMAP pointer on three different nodes:

| Scenario | Chain built | ROADMAP named by | Assertion |
|---|---|---|---|
| 1 (`scenario_design_roadmap`, line 421) | PLAN -> DESIGN -> ROADMAP | the **DESIGN**'s upstream (line 432) | `update_roadmap_feature ok` |
| 2 (`scenario_design_prd_roadmap`, line 479) | PLAN -> DESIGN -> PRD -> ROADMAP | the **PRD**'s upstream (line 490) | `update_roadmap_feature ok` |
| 6 (`scenario_brief_with_upstream`, line 667) | PLAN -> DESIGN -> PRD -> BRIEF -> ROADMAP | the **BRIEF**'s upstream (line 677) | "walk reaches ROADMAP" (line 703) |
| 7 (`scenario_brief_no_upstream`, line 711) | PLAN -> DESIGN -> PRD -> BRIEF | nobody | completes, no roadmap step |
| 10 (`scenario_deletion_no_roadmap_regression`, line 1009) | no ROADMAP in tree | nobody | no `delete_roadmap` step |

So the consumer keys on *the ROADMAP being named by some expanded node*, not on
*the BRIEF naming it*. `skills/prd/references/prd-format.md:27-29` documents this
directly: the PRD's upstream is "the nearest parent produced above this PRD — a
ROADMAP when no BRIEF was written," and `references/pipeline-model.md:130-135`
states the same nearest-produced rule for the whole tactical chain.

## 5. FC12 — `check_plan_design_field_consistency`

- **File/function:** `crates/shirabe-validate/src/checks.rs:2758`.
- **Doc types:** PLAN only (`schema_version != "plan/v1"` returns early).
- **What it does with the target:** nothing. It tests `doc.fields.contains_key
  ("upstream")` (line 2766) as a gate and then analyzes the PLAN's own AC lines.
  The comment at line 2750 is explicit: "it does not parse the upstream DESIGN."
- **Survives? YES.** Presence-only, PLAN-only.

## 6. `validate-plan.sh` (the /plan skill's pre-flight)

- **File:** `skills/plan/scripts/validate-plan.sh:133-179`.
- **Doc types:** PLAN only.
- **What it does with the target:** resolves it against the repo root (line 149),
  requires the file to exist (153), to be git-tracked (160), and to have
  `status: Accepted` or `Planned` (168-175). Reads the upstream's frontmatter;
  does not walk past it.
- **Survives? YES.** A PLAN's upstream is a DESIGN (or PRD/ROADMAP for
  roadmap-scoped slices); untouched by the BRIEF question. An absent field is an
  explicit pass (line 137).

## 7. `check-no-fixture-design-leak.sh` (CI guard)

- **File:** `scripts/check-no-fixture-design-leak.sh:31` (`read_upstream`, an awk
  frontmatter scrape) and line 56.
- **Doc types:** `docs/designs/current/DESIGN-*.md` only.
- **What it does with the target:** string-matches the value for
  `*evals/fixtures/*` and fails the build if it matches. Never resolves the path.
- **Survives? YES.** DESIGN-only, substring test.

## 8. CI workflows

- **`.github/workflows/lifecycle.yml`** — the only workflow mentioning upstream.
  It runs `shirabe validate --lifecycle .` (whole tree, `--mode=ready` when the
  PR is non-draft), so it consumes consumers 2, 2a and 2b transitively; the
  comment at line 119 names the guarantee ("a present PLAN and un-transitioned
  upstreams ... fails L01"). The **merge-gate step (line 140+) does not read
  frontmatter at all**: its `--pr`/`--upstream` refs are scraped from the
  coordination PR body (lines 207-225) and re-verified live via `gh`
  (`crates/shirabe-validate/src/merge_gate.rs:277-306`,
  `finalize.rs:1076 verify_cross_repo_upstream_terminal`). The CLI flag
  `--upstream` (`main.rs:311`) and the frontmatter field share a name and
  nothing else.
- `check-execute-scripts.yml` / `check-plan-scripts.yml` run the two shell test
  suites above, so they pin consumers 4 and 6 in CI.
- **Survives? YES** for every workflow. None of them asserts a BRIEF's upstream
  type.

## 9. Skill prose that reads (rather than writes) an upstream field

| Where | Reads | Does what | Survives? |
|---|---|---|---|
| `skills/brief/references/phases/phase-1-discover.md:43-53` | the ROADMAP the brief is about to record | "Load the upstream ROADMAP and find the feature this brief frames," derive problem/outcome candidates from the roadmap line item and its sequencing rationale | YES as a workflow (it is an authoring input, available from the invocation argument), NO as a durable record — nothing else can later tell which roadmap feature this BRIEF framed |
| `skills/scope/references/phases/phase-2-chain-orchestration.md:487-499` | **the absorbed artifact's own `upstream:`** | on `absorb`, "Set the survivor's `upstream:` to that value, or remove the field when the absorbed artifact had none," then re-validate (R6 must still resolve) | YES, and this is the mechanism that *preserves* the ROADMAP pointer when a BRIEF is absorbed into a PRD |
| `skills/design/references/phases/phase-0-setup-prd.md:100-133` | the candidate upstream PRD path | wip/-rejection, `git ls-files` resolution, visibility-direction decision (omit rather than dangle) | YES |
| `skills/plan/references/phases/phase-7-creation.md:284-312` | the PLAN's own `upstream:` line | greps it for `wip/` paths and requires `git ls-files` to resolve; hard stop otherwise | YES |
| `skills/execute/koto-templates/execute.md:466` | narrates the cascade | describes `handle_roadmap_deletion` transitioning the ROADMAP to Done and `git rm`-ing it, gated on all-features-Done and all-issues-closed | NO — the described behavior stops happening for BRIEF-headed chains |
| `skills/roadmap/references/phases/phase-3-draft.md:32`, `skills/brief/SKILL.md:130-168`, `skills/scope/references/phases/phase-0-setup.md:15-58` | `--upstream <path>` argument | writers, not readers: they canonicalize the flag value and record it in frontmatter | n/a |

---

## The BRIEF -> ROADMAP edge: what actually depends on it

**Two consumers, and only two:**

1. `check_orphan`'s Active-ROADMAP exemption (`lifecycle.rs:1276-1282`) — a
   partial loss, narrow window.
2. The cascade's ROADMAP leg: `classify_node`'s `Some("Roadmap") =>
   RoadmapHandoff` (`finalize.rs:692`) feeding `run-cascade.sh`'s
   `handle_roadmap` / `handle_roadmap_deletion` — a total loss for chains whose
   only ROADMAP pointer was the BRIEF's.

Everything else either ignores the edge (chain discovery explicitly refuses to
follow it), treats it type-agnostically (R6, the referrer map), or never sees it
(PLAN-only and DESIGN-only checkers).

## Alternative discovery routes for the ROADMAP

**In code today: none.** `ROADMAP_PATH` has exactly one assignment
(`run-cascade.sh:803`), sourced from the finalize-chain report, which sources it
from an expanded node's `upstream:`. No glob, no index, no reverse lookup.

**Available without new data, in order of cost:**

1. **Move the pointer, don't delete it.** The nearest-produced rule
   (`references/pipeline-model.md:121-135`) already lets the **PRD** carry
   `upstream: <ROADMAP>` when no BRIEF was written, and `prd-format.md:27-29`
   documents it. `run-cascade_test.sh` Scenarios 1 and 2 prove the DESIGN and
   PRD legs work identically. This is the cheapest route: it requires no code
   change at all, only an authoring-convention change about which node records
   the boundary crossing.
2. **The reverse edge already written in the ROADMAP.** Real roadmaps record
   per-feature `**Downstream:**` lines naming the artifacts a feature became —
   e.g. `crates/shirabe/tests/fixtures/golden/corpus/real/ROADMAP-strategic-pipeline.md:147`:
   `**Downstream:** PRD-artifact-traceability.md (Done), DESIGN-artifact-traceability.md (Current)`.
   `handle_roadmap` already matches against exactly this line (grep for the plan
   slug + `Downstream:`, line 401) — it just needs the file handed to it first.
   Generalizing that grep from *one known file* to *`docs/roadmaps/*.md`* is a
   few lines of bash and yields a working reverse index keyed on the shared
   topic slug.

   **Caveat, and it is a real one:** `**Downstream:**` is **not** part of the
   canonical feature entry. `skills/roadmap/references/roadmap-format.md:138-150`
   specifies `**Needs:**`, `**Dependencies:**`, `**Status:**` and nothing else,
   and `references/issues-table.md:196-200` says the `Downstream Artifact`
   *column* "is dropped during migration." So the field the cascade both reads
   and writes is undocumented in the format it belongs to — it survives only in
   committed corpora and in the cascade fixtures
   (`skills/execute/evals/fixtures/roadmaps/ROADMAP-cascade-test.md:20`). Any
   PRD that leans on this route should also make the field canonical.
3. **`Downstream Artifacts` sections.** STRATEGY requires one
   (`formats.rs:218`); VISION/PRD/BRIEF carry one by convention. It is prose,
   with no parser, and is the weakest of the three.

## Two facts worth carrying into the PRD

- **Nothing in this repository actually exercises the edge.** Of the nine BRIEFs
  under `docs/briefs/` carrying `upstream:`, **zero** point at a ROADMAP: four
  point at DESIGNs, two at PLANs, two at other BRIEFs. There is no
  `docs/roadmaps/` directory here at all. Every BRIEF -> ROADMAP instance in the
  repo is a test fixture.
- **The edge is already a known liability at the other end.** The cascade
  deletes the ROADMAP (`handle_roadmap_deletion`, `git rm -f` at line 562) with
  no referrer check — the finalization walk's retirement guard cannot cover it,
  because a `RoadmapHandoff` node has `target_status: None` and short-circuits
  to `Verdict::kept()` before the guard's blocker loop runs
  (`finalize.rs:792-795`). The BRIEF that named the deleted ROADMAP is
  transitioned to `Done` in the same commit but keeps its now-dangling
  `upstream:` value, which R6 (`checks.rs:839`) then reports as
  `upstream "..." does not exist on disk` on the next validate. `finalize.rs:37`
  names this as the mechanism behind "the dangling `upstream:` references
  already in this repository."
