# Lead: Where is 1:1 baked into the CLI, the document types, and the validation rules?

Research question: does the shirabe CLI and its document data model assume a
strictly linear 1:1 chain between artifact types, and what concretely breaks if a
link becomes 1:N?

Updated after the author confirmed 1:N fan-out is **live today** on both
strategic links: multiple STRATEGYs under one VISION, and multiple ROADMAPs under
one STRATEGY. Documented at `skills/strategy/references/strategy-format.md:278`
("Multiple STRATEGYs may operate under one upstream VISION when they make
distinct bets"). Those artifacts live in a private repo, so this public repo has
no instances; every claim below is from code plus synthetic fixtures built to the
documented shapes.

All paths are relative to `public/shirabe/`. Line numbers from the worktree at
`.claude/worktrees/charter-scope-parity`, 2026-08-13.

Empirical claims were verified by running throwaway integration tests against the
real library (`run_lifecycle_check`, `run_lifecycle_chain_check`,
`parse_doc_bytes`, `check_upstream_resolves`). Probe files were deleted after the
run; recorded outputs are reproduced verbatim.

## Findings

### 0. Headline: the live strategic fan-out is unmodelled, not broken

The single most important correction to my first pass. The strategic chain is
**not indexed by the lifecycle checker at all**, so the fan-out the author
confirmed does not hit the unsatisfiability trap that dominates the tactical
chain. Verified against the documented shapes:

```
--- STRATEGY -> 2 ROADMAPs, both Active (0 findings) ---
---   same, --mode=ready (0 findings) ---
---   --lifecycle-chain at ROADMAP-a (0 findings) ---

--- STRATEGY -> ROADMAP-a Active + ROADMAP-b Done (1 finding) ---
  L01 docs/roadmaps/ROADMAP-b.md :: ROADMAP at status 'Done' (expected DELETED for multi-pr work-completing posture)

--- VISION -> 2 STRATEGYs (whole-tree lifecycle) (0 findings) ---

R6 on STRATEGY-a.md -> 0 findings
R6 on STRATEGY-b.md -> 0 findings
```

The mixed-stage case produces exactly one finding, on the completed ROADMAP
itself, which is the intended per-roadmap forcing function — not a fan-out
artifact. The STRATEGY is never touched because it is never indexed.

Both live shapes are **N children each carrying ONE `upstream:` scalar**. That is
precisely the shape R6 and the frontmatter parser handle correctly. The breakages
I catalogued for multi-valued upstream (parser collapse, R6 hard error,
`finalize-chain` no-op) are the *converging* direction — one child, several
parents — and the live corpus does not have that shape.

So: no hard errors and no wrong answers from the confirmed live fan-out. What
there is instead is a total absence of enforcement, detailed in finding 3.

### 1. The command surface

Two crates (`Cargo.toml`): `crates/shirabe` (binary — `main.rs` 1827 lines, plus
`populate.rs`, `pr_body_hook.rs`, `work_summary.rs`) and
`crates/shirabe-validate` (library, 19 modules, ~29k lines; `checks.rs` is 6882,
`lifecycle.rs` 2824).

Subcommands, `crates/shirabe/src/main.rs:63-102`:

| Subcommand | What it does |
|---|---|
| `validate` | Six modes behind one verb (below) |
| `roadmap populate` | Fills one roadmap's reserved sections |
| `transition <file> <status>` | Moves one doc to a new status |
| `finalize-chain <plan>` | Walks a finished PLAN's upstream chain, applies terminal transitions |
| `slug-prefix-detect <slug>` | Samples docs dirs for naming convention |
| `install-hooks` | Installs a git pre-commit hook |
| `work-summary` | Session PR-URL ledger |
| `pr-body-hook` | PreToolUse gate on `gh pr create` / `gh pr edit` |

`validate` modes (`ValidateArgs`, `main.rs:201-362`): per-file (default);
`--lifecycle ROOT`; `--lifecycle-chain DOC`; `--merge-gate`;
`--coordination-body FILE`; `--pr-body FILE`. The last four are mutually
exclusive with each other and with positional files.

Note for the fan-out question: **no CLI subcommand takes an `--upstream` flag.**
The `--upstream` in the charter evals is a *skill* argument
(`skills/roadmap/SKILL.md:165`), parsed from `$ARGUMENTS` by the roadmap skill.
The CLI never receives it.

### 2. The document model carries no link type

`Doc` — `crates/shirabe-validate/src/doc.rs:29-39`:

```rust
pub struct Doc {
    pub path: String,
    pub schema: String,
    pub status: String,
    pub fields: HashMap<String, FieldValue>,   // flat, ONE value per key
    pub sections: Vec<Section>,
    pub body: Vec<String>,
}
```

`FieldValue` is `{ value: String, line: usize }` (`doc.rs:43-46`). No typed
upstream, no downstream, no link type anywhere. `upstream` is a plain string in a
map, looked up by name independently at each call site — which is why every
consumer re-derives its own idea of what it means.

`FormatSpec` (`formats.rs:7-38`) defines 8 formats (`formats.rs:87-242`), matched
by filename prefix, longest wins (`detect_format`, `formats.rs:248-260`). **It
carries no ordering and no successor relation.**

The ordered relation lives only in `lifecycle.rs`: `ChainRole`
(`lifecycle.rs:118-124`) with five variants — Brief, Prd, Design, Plan, Roadmap —
baked into the walk's stop conditions (`lifecycle.rs:539`) and
`compute_passing_state`, a 25-arm `(role x posture)` match table
(`lifecycle.rs:620-670`).

**VISION, STRATEGY and COMP have no `ChainRole` variant.** The strategic chain has
no ordered relation in code.

### 3. `Downstream Artifacts` — specified as a list, enforced in neither direction

This is where the live fan-out actually lands, so it gets full treatment.

**What the spec asks for.** Both strategic formats carry a downstream list, and
the spec is explicit that it is 1:N:

- STRATEGY: "**Downstream Artifacts** — typed link list of the ROADMAP documents
  that sequence this strategy's work, and nothing else"
  (`skills/strategy/references/strategy-format.md:80`). Each entry is "a path
  (durable, repo-relative) and a one-sentence description"
  (`strategy-format.md:131`). "Empty at draft creation; populated as downstream
  ROADMAPs land that reference this STRATEGY as their upstream"
  (`strategy-format.md:~425`).
- VISION: "**Downstream Artifacts** — added when the first STRATEGY that
  operationalizes this VISION exists. Lists paths to the STRATEGY documents"
  (`skills/vision/references/vision-format.md:65`).

The spec even names the failure mode it expects to be caught: "**Stale Downstream
Artifacts.** The section should be updated as downstream work lands. Empty when
no downstream artifacts exist yet is fine; outdated paths are not"
(`strategy-format.md:454`).

**What the validator actually does.** `Downstream Artifacts` appears in the Rust
codebase in exactly **one** place:

```
crates/shirabe-validate/src/formats.rs:218:  "Downstream Artifacts",
```

That is a string literal inside STRATEGY's `required_sections` vector. Its only
consumers are FC04 (heading present, `checks.rs:188`) and FC15 (heading in
canonical order, `checks.rs:220`). **Nothing parses the section body.** No list
extraction, no path extraction, no durability check, no count.

Asymmetry worth noting: **VISION's `Downstream Artifacts` is not in
`required_sections` at all** (`formats.rs:154-162` lists Status, Thesis,
Audience, Value Proposition, Org Fit, Success Criteria, Non-Goals). The skill
spec marks it "When exists" (`vision-format.md:104`), so a VISION's list of its
STRATEGYs is not even presence-checked, let alone parsed.

**Answering the three questions directly:**

- *Parsed and checked as a list?* **No.** Heading presence and ordering only, and
  only for STRATEGY.
- *Back-link verified — does each listed downstream doc's `upstream:` point
  home?* **No.** R6 (`checks.rs:784-822`) checks only that a doc's own `upstream:`
  string resolves to a file that exists and is git-tracked. It does not check the
  target's *type* (a ROADMAP with `upstream: docs/prds/PRD-x.md` passes R6
  cleanly), and it never reads the parent's `Downstream Artifacts` to see whether
  the child is listed.
- *Enforced in one direction, both, or neither?* **Neither, mechanically.** The
  forward edge (parent lists children) is an unparsed prose section. The backward
  edge (child names parent) is checked for file existence but not for type or
  reciprocity. There is no code path that puts the two together.

Concretely: a STRATEGY can list ROADMAP-a and ROADMAP-b while ROADMAP-b's
`upstream:` points at an entirely different STRATEGY; or list a ROADMAP deleted
three months ago; or list neither of its two real ROADMAPs — and every document
passes `shirabe validate` clean.

**Who does enforce it.** The spec assigns it to an LLM: "The structural reviewer
parses each entry for durability" (`strategy-format.md:135`), and the
`wip/...` rejection is listed under "During /strategy finalization"
(`strategy-format.md:312`) — a jury-phase check, not a validator check. So the
entire downstream-link contract for the live 1:N structure rests on jury agents
re-reading prose each time, with no mechanical backstop.

### 4. Progress rollup across N ROADMAPs — the concept does not exist

`roadmap populate` takes exactly one roadmap path (`populate.rs:46`). `run_inner`
(`populate.rs:108-172`) parses that file's own `## Features` section
(`parse_features`), then rewrites `## Implementation Issues` and
`## Dependency Graph` in the same file. It never reads `upstream:`, never opens a
STRATEGY, never aggregates.

So if one STRATEGY lists two ROADMAPs, populate/rollup does **none of sum, pick,
or error — it never looks.** Each roadmap populates independently and is correct
in isolation.

Reinforcing this: **STRATEGY has no Progress section.** Its `required_sections`
(`formats.rs:210-219`) are Status, Strategic Context, Defensibility Thesis,
Building Blocks, Coordination Dependencies, Bet-Specific Falsifiability,
Non-Goals, Downstream Artifacts. Only ROADMAP has `Progress` (`formats.rs:179`),
and even there nothing computes it — the section is required to exist and is
never read. The only status rollup in the codebase is per-feature-row within one
roadmap: `pick_status_cell` (`populate.rs:778`), `pick_class`
(`populate.rs:873`), `ready_or_blocked` (`populate.rs:897`), plus FC09's
reconciliation of table status against live `gh` issue state (`checks.rs:2150`).

There is no strategy-level or vision-level progress concept to double-count.

### 5. What already works correctly under 1:N

Worth stating plainly — more than expected:

- **Chain discovery is fan-out-correct.** `discover_chains`
  (`lifecycle.rs:460-561`) iterates PLAN/ROADMAP roots and walks *upward*, so N
  downstream docs produce N chains.
- **Normal roadmap fan-out works today.** One ROADMAP with many BRIEF-rooted
  feature chains is the routine shape, and it validates correctly:

  ```
  --- ROADMAP with 2 independent feature chains (BRIEF-rooted) (1 finding) ---
    L01 docs/plans/PLAN-f2.md :: PLAN at status 'Done' (expected DELETED for multi-pr work-completing)
  ```

  One finding, the correct one, on the completed plan. The ROADMAP is untouched.
  The reason is `lifecycle.rs:539` — the walk stops at a BRIEF and deliberately
  does **not** follow the BRIEF's `upstream:` to the ROADMAP, documented at
  `lifecycle.rs:523-528` as "a cross-chain reference, not a chain-membership
  edge". That stop rule is exactly what keeps roadmap fan-out safe.
- The inverse-upstream graph is genuinely `Vec`-valued (`lifecycle.rs:254`,
  `440-450`), and `check_orphan`'s `has_downstream_child` (`lifecycle.rs:742`)
  reads it correctly. L02 is 1:N-clean.
- All 18 FC checks are document-local — FC06 says so: "document-local (no graph
  model)" (`checks.rs:631-633`).
- `transition` is per-doc (`transition.rs:266-270`), no successor relation.

### 6. Ranked: hard error, silently wrong, unmodelled

Ordered by severity, each tagged with whether the **confirmed live corpus** hits
it today.

#### Hard errors

**H1. `--lifecycle-chain` on a VISION or STRATEGY is rejected outright.**
*Live today.* The prefix allowlist (`lifecycle.rs:1056-1070`) admits only
BRIEF-/PRD-/DESIGN-/PLAN-/ROADMAP-. Verified:

```
L05 :: doc path 'STRATEGY-a.md' has an unrecognized artifact prefix
       (expected BRIEF-/PRD-/DESIGN-/PLAN-/ROADMAP-)
```

You cannot point the chain checker at a strategic document at all. Exit code 2.
This is by design, but it means the live fan-out is not merely unchecked — it is
unaskable.

**H2. A ROADMAP directly upstream of ≥2 PLANs in mixed postures is
unsatisfiable.** *Possibly live* — depends on whether `/plan` is run directly
against a roadmap, which the plan skill explicitly supports ("Decomposes a design
doc, PRD, roadmap, or directly-stated topic"). Verified:

```
--- ROADMAP directly upstream of 2 PLANs (mixed posture) (2 findings) ---
  L01 docs/plans/PLAN-b.md   :: PLAN at status 'Done' (expected DELETED for multi-pr work-completing)
  L01 docs/roadmaps/ROADMAP-x.md :: ROADMAP at status 'Active' (expected DELETED for multi-pr work-completing)
```

`(Roadmap, MultiPrWorkCompleting) => PassingState::Deleted` (`lifecycle.rs:637`)
and `Deleted` always fails for a doc discovered in the tree
(`lifecycle.rs:874-877`). So one completing multi-pr PLAN demands deletion of a
ROADMAP that the other in-flight PLAN still needs. No status resolves it.
This is the one path by which the tactical unsatisfiability reaches a strategic
document.

**H3. Shared tactical ancestors (BRIEF/PRD) under two PLANs are unsatisfiable.**
*Not hit by the confirmed strategic fan-out* — requires the tactical chain itself
to fork. `(Brief, SinglePrMidPR) => Status("Accepted")` (`lifecycle.rs:652`) vs
`(Brief, MultiPrWorkCompleting) => Status("Done")` (`lifecycle.rs:633`) are
disjoint. Full sweep:

```
BRIEF Draft    -> 2 findings (expected 'Accepted' AND expected 'Done')
BRIEF Accepted -> 1 finding  (expected 'Done')
BRIEF Done     -> 1 finding  (expected 'Accepted')
```

No status passes. DESIGN escapes only because `DesignPlannedOrCurrent`
(`lifecycle.rs:212`) overlaps `Status("Current")` — `Current` is its unique
satisfying value, which then forces the file into `docs/designs/current/` to
satisfy L07 (`lifecycle.rs:784-808`).

**H4. Multi-valued `upstream:` is rejected with a misleading message.**
*Not live* — every confirmed shape has one upstream per child. `check_upstream_resolves`
treats the whole value as one path (`checks.rs:790`). Verified:

```
[R6] upstream "" does not exist on disk
```

The empty string comes from the parser (finding 7). Would become live only if a
doc gains several upstreams — e.g. a PRD absorbing two BRIEFs.

**H5. `finalize-chain` on one of N siblings strands the others.** *Not hit by
strategic fan-out; live if the tactical chain forks.* Walking up from one PLAN
transitions shared ancestors to terminal (`finalize.rs:426-451`) and *moves* the
DESIGN into `docs/designs/current/` (`transition.rs:446-451`, applied at
`transition.rs:742`/`1004-1018`). Siblings' `upstream:` then dangles — R6 hard
error plus L04 (`lifecycle.rs:499-506`).

#### Silently wrong results

**S1. `--lifecycle-chain` picks a chain by filename sort order.** *Not hit by
strategic fan-out (H1 blocks it); live if the tactical chain forks.*
`lifecycle.rs:1113-1115` uses `.find()`, first match in `BTreeMap` path order.
Identical tree, only the healthy plan renamed:

```
single-pr plan sorts first (PLAN-a) -> 0 findings
single-pr plan sorts last  (PLAN-z) -> 2 findings
```

And targeting a shared DESIGN returned 0 findings while whole-tree mode returned
4 on the same tree, one of them on that DESIGN. This is the mode the work-on
cascade uses (`lifecycle.rs:999-1001`).

**S2. Second and later upstreams are silently dropped.** *Not live.*
`lifecycle.rs:542`: `cur = node.upstreams.first().cloned();` — the comment at
`519-522` admits it.

**S3. `finalize-chain` silently no-ops on a list-shaped upstream.** *Not live.*
`read_upstream` returns the raw scalar (`finalize.rs:722-726`); the walk breaks
on empty (`finalize.rs:392-396`). A YAML list yields `Some("")`, so the walk
terminates immediately, reports only the PLAN delete node, and exits 0 claiming
the chain is complete. (Code-read plus the confirmed parse behaviour in finding
7; not run end to end.)

**S4. L03 cycle detection covers only the first-upstream path.** *Not live.*
`visited` is per-root (`lifecycle.rs:472`) and only `.first()` is followed.

#### Merely unmodelled

**U1. The whole strategic chain has zero lifecycle validation.** *Live.*
`build_doc_index` (`lifecycle.rs:275-282`) indexes only
`docs/{briefs,prds,designs,designs/current,plans,roadmaps}`. `docs/strategies/`
and `docs/visions/` are absent, deliberately (`lifecycle.rs:530-541`). VISION,
STRATEGY and COMP get per-file FC/R checks and nothing else.

**U2. `Downstream Artifacts` contents are never parsed.** *Live.* Finding 3.

**U3. The back-link is never verified in either direction.** *Live.* Finding 3.

**U4. `upstream:` is never type-checked.** *Live.* R6 checks existence and git
tracking only; a ROADMAP whose upstream names a PRD passes.

**U5. No strategy-level or vision-level progress concept exists.** *Live.*
Finding 4.

**U6. Stale downstream entries are undetectable.** *Live.* The spec names this as
a pitfall (`strategy-format.md:454`); nothing mechanical can see it.

### 7. The plural upstream is unreachable from idiomatic YAML

Relevant because it caps what a fix could assume. `scalar_source_text`
(`frontmatter.rs:264-270`) returns `None` for sequences and mappings;
`parse_yaml_fields` applies `.unwrap_or_default()` (`frontmatter.rs:236`).
Verified:

```
block sequence: value=Some("")
flow sequence : value=Some("")
block scalar  : value=Some("docs/prds/PRD-a.md\ndocs/prds/PRD-b.md")
plain scalar  : value=Some("docs/prds/PRD-a.md")
```

`IndexedDoc.upstreams: Vec<PathBuf>` (`lifecycle.rs:248`) is plural, and
`extract_upstreams` (`lifecycle.rs:396-436`) documents a multi-value contract —
its comment claims the field "carries multi-line content when the YAML is a
list" (`lifecycle.rs:393-395`). **That comment is wrong.** A YAML sequence
arrives as an empty string. The only shape yielding more than one element is a
`|` block scalar.

### 8. Rule inventory

Per-file registry, `is_known_check_code` (`validate.rs:150-176`): SCHEMA,
FC01–FC16, FC-CONVENTIONS, R6–R9. The L-family (L01–L07, `lifecycle.rs:13-36`) is
deliberately excluded — chain-level, reachable only via `--lifecycle` /
`--lifecycle-chain`.

| Code | Rule | Cardinality-sensitive? |
|---|---|---|
| SCHEMA | `schema:` matches format version (notice) | No |
| FC01 | required frontmatter fields (`checks.rs:70`) | No |
| FC02 | status in valid set (`checks.rs:88`) | No |
| FC03 | frontmatter status vs `## Status` (`checks.rs:121`) | No |
| FC04 | required sections present (`checks.rs:188`) | No — presence only, incl. Downstream Artifacts |
| FC05 | issues-table header (`checks.rs:457`) | No |
| FC06 | deps resolve within same table (`checks.rs:641`) | No — explicitly document-local |
| FC07 | mermaid/table reconciliation (`checks.rs:1012`) | No |
| FC08 | Legend vs classDef (`checks.rs:1955`) | No |
| FC09 | table status vs live `gh` issue state (`checks.rs:2150`) | No |
| FC10 | writing-style banned words (`checks.rs:2572`) | No |
| FC11 | plan section structure (`checks.rs:2642`) | No |
| FC12 | plan AC field-shape consistency (`checks.rs:2704`) | No — `contains_key` only (`checks.rs:2712`) |
| FC13 | eval-fixture frontmatter (`checks.rs:2828`) | No |
| FC14 | (`checks.rs:2893`) | No |
| FC15 | required-section order (`checks.rs:220`) | No |
| FC16 | roadmap reserved-section shape (`checks.rs:408`) | No |
| FC-CONVENTIONS | CLAUDE.md conventions (`checks.rs:3167`) | No |
| R6 | `upstream:` exists + git-tracked (`checks.rs:784`) | **Yes — scalar-only (H4); no type or back-link check (U3, U4)** |
| R7 | prohibited sections, public VISION (`checks.rs:828`) | No |
| R8 | prohibited sections, public STRATEGY (`checks.rs:855`) | No |
| R9 | private-only formats (`checks.rs:883`) | No |
| L01 | member status vs chain posture (`lifecycle.rs:878-890`) | **Yes — unsatisfiable (H2, H3)** |
| L02 | orphan doc rule (`lifecycle.rs:686-768`) | No — already 1:N-clean |
| L03 | upstream cycle (`lifecycle.rs:477-492`) | **Yes — first path only (S4)** |
| L04 | upstream references missing doc (`lifecycle.rs:499-506`) | Partly — walked path only |
| L05 | parse/containment/prefix failure (`lifecycle.rs:320-335`, `1056-1070`) | **Yes — rejects strategic docs (H1)** |
| L06 | unticked outline ACs (`lifecycle.rs:941-990`) | No |
| L07 | DESIGN directory vs status (`lifecycle.rs:784-808`) | No |

One caveat on R6: it shells out to `git ls-files` in the **process** cwd
(`checks.rs:775-778`), so it validates against whatever repo the caller is in.

### 9. Charter/scope integration

The CLI has no model of a chain run, session, or charter/scope invocation. All of
it lives in the skills' wip markdown (`skills/scope/references/state-schema.md`;
`wip/scope_<topic>_state.md`, `wip/charter_<topic>_state.md`). Skills invoke the
CLI strictly per-document — `shirabe validate --format json --visibility=<v>`
against one artifact at a time
(`skills/scope/references/phases/phase-2-chain-orchestration.md:58,341,472`;
`skills/charter/references/phases/phase-finalization.md:138-165`).

The only session-shaped state in the binary is `work-summary`'s per-session
ledger (`crates/shirabe/src/work_summary.rs`), which tracks PR URLs, not
documents.

The skill layer already models plurality (`exit_artifacts` is a list,
`consolidation_judgments` records a verdict per hop), so the skills can express
1:N that the CLI cannot see.

## Implications

The confirmed live fan-out is safe today, and safe for a reason that will not
survive contact with any attempt to check it: the strategic chain is invisible to
the only component that understands chains. The CLI cannot give a wrong answer
about VISION -> STRATEGY -> ROADMAP because it never forms an opinion. Anyone
extending the lifecycle checker to cover the strategic chain inherits the
unsatisfiability problem immediately, because `compute_passing_state` is a
`(role x posture)` table and posture is a property of a *chain*, not an edge. A
doc with N downstream roots inherits N postures and gets judged against each
independently. For BRIEF and PRD those demands are already disjoint sets. Adding
STRATEGY and VISION rows to that table without changing its shape reproduces the
bug one altitude up.

H2 is the live seam worth watching, because it is the one place the tactical
unsatisfiability already reaches a strategic document. A ROADMAP that is the
direct upstream of a completing multi-pr PLAN is ordered deleted while other
plans still depend on it — and roadmap deletion is exactly what
`(Roadmap, MultiPrWorkCompleting) => Deleted` intends at 1:1. The rule is right
for one downstream and wrong for many, with no way for the code to tell the
difference.

The `Downstream Artifacts` gap is the largest surface relative to expectation.
The spec describes a typed link list with durability rules, one-level-deep
discipline, and an explicit staleness warning, and assigns the checking to a
"structural reviewer" — an LLM jury phase. The validator contributes one string
literal in a required-sections vector. For a live 1:N structure whose whole point
is that the parent enumerates several children, the enumeration is prose that
nothing reads, and the reciprocal link is checked for file existence but not for
type or reciprocity. Both halves of the relationship are unenforced, so the two
can drift apart silently and indefinitely.

That the fan-out lives in a private repo compounds this: public CI never sees
those documents, so the jury phase is not merely the primary enforcement, it is
the only enforcement.

## Surprises

1. **The stop-at-BRIEF rule is what makes roadmap fan-out safe.**
   `lifecycle.rs:539` refuses to follow a BRIEF's `upstream:`, dismissing it as
   "a cross-chain reference, not a chain-membership edge". That single line is
   the reason one ROADMAP with many feature chains validates cleanly today. It
   reads as a scoping convenience; it is load-bearing 1:N protection.

2. **`--lifecycle-chain` cannot be pointed at a STRATEGY or VISION at all** —
   L05, unrecognized prefix. The live fan-out is not just unchecked, it is
   unaskable.

3. **VISION's `Downstream Artifacts` is not even in `required_sections`**
   (`formats.rs:154-162`), while STRATEGY's is (`formats.rs:218`). The asymmetry
   is invisible in the skill specs, which describe both the same way.

4. **`Downstream Artifacts` appears exactly once in the Rust codebase** — as a
   string literal in a vector. The one section whose name announces fan-out is
   the one section nothing reads.

5. **The `Vec<PathBuf>` for upstreams is unreachable from idiomatic YAML**, and
   `extract_upstreams`' doc comment states the opposite of what the parser does.

6. **`STRATEGY` has no Progress section**, so strategy-level rollup is not a
   thing that exists to get wrong. Even ROADMAP's `Progress` is required-present
   and never read.

7. **R6 never type-checks the upstream.** A ROADMAP pointing at a PRD passes.

8. **The mixed-stage roadmap case produces exactly the right answer** — one
   finding on the completed roadmap, none on the strategy — which makes the
   absence of enforcement easy to mistake for working enforcement.

## Open Questions

1. Does any live PLAN take a ROADMAP as its direct `upstream:`? That is the
   single live trigger for H2. The `/plan` skill accepts a roadmap as input, so
   the shape is reachable; whether the private corpus contains it decides whether
   H2 is theoretical or current.

2. Does the tactical chain fork anywhere in the private corpus — one DESIGN with
   two PLANs, or one PRD with two DESIGNs? The author confirmed strategic
   fan-out; the tactical case is what H3, H5 and S1 need, and it has different
   consequences (unsatisfiable BRIEFs, order-dependent cascade results).

3. Is convergence (one PRD absorbing two BRIEFs) in use or planned? That is the
   direction that breaks the parser, R6 and `finalize-chain` (H4, S2, S3), and
   none of it is reachable from the confirmed shapes.

4. If the strategic chain were indexed, what is the intended passing state for a
   STRATEGY whose two ROADMAPs are at different stages? The current table shape
   admits no answer. This is a product question about whether posture belongs to
   the chain or to the edge.

5. Should the `Downstream Artifacts` / `upstream:` reciprocity be mechanical at
   all, or is jury-phase checking the deliberate design? The spec reads as though
   mechanical checking was assumed ("entries are durable paths", "outdated paths
   are not [fine]") without a validator ever acquiring the capability.

6. Is the `|` block-scalar upstream form used anywhere live? It is the only
   working multi-upstream shape, so any parser change must preserve it.

## Summary

The CLI does not model chains as a first-class thing: `Doc` is a flat string map
with no link type, `FormatSpec` carries no ordering, and the entire notion of
artifact succession lives in one module as a five-variant enum plus a hardcoded
25-arm `(role x posture)` table. VISION, STRATEGY and COMP are not in that enum.

The live 1:N fan-out the author confirmed — many STRATEGYs under a VISION, many
ROADMAPs under a STRATEGY — produces **no hard errors and no wrong answers
today**, because the strategic chain is not indexed by the lifecycle checker at
all. Both live shapes are N children each carrying one `upstream:` scalar, which
is exactly what R6 and the parser handle. Verified: both-Active gives 0 findings;
mixed-stage gives exactly one correct finding on the completed roadmap; R6 passes
on every child. Normal roadmap fan-out into many feature chains also works, saved
by a stop-at-BRIEF rule that reads like scoping convenience but is load-bearing.

What exists instead of breakage is absence. The `Downstream Artifacts` section —
specified as a typed link list with durability and staleness rules — appears in
the Rust codebase exactly once, as a string in a required-sections vector; its
body is never parsed. The reciprocal `upstream:` is checked for file existence
and git tracking, never for type or for whether the parent lists the child. The
relationship is enforced in **neither** direction. There is no strategy-level
progress concept, so two ROADMAPs under one STRATEGY are neither summed nor
picked between — nothing looks. And `--lifecycle-chain` rejects strategic
documents outright with L05, so the fan-out is not merely unchecked but unaskable.

One live seam does bite: a ROADMAP that is the direct upstream of two PLANs in
mixed postures is ordered deleted by the completing one while the in-flight one
still needs it, and no status resolves the conflict. That is the single path by
which the tactical unsatisfiability reaches a strategic document today. The
deeper tactical breakages — unsatisfiable shared BRIEFs, filename-order-dependent
cascade results, parser collapse on multi-valued upstream — all require shapes
the confirmed corpus does not have.
